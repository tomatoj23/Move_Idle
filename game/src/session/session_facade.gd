class_name SessionFacade
extends RefCounted
## 引擎侧唯一对外顶层接口（#24 实施决策 A/E：唯一受测接缝）。
## 输入 = 存档状态（内存态）+ 内容库 + 遭遇引用；输出 = 结果 + 事件流 + 新状态。
## 战斗、聚合、随机性全部藏在私有实现后；事件载荷封闭、零回调。
## #27 范围：单场遭遇（encounter_index >= 0 = 普通遭遇下标，-1 = 首领单挑）。
## #30 增量：传奇词缀实例免 values（效果数值固定于内容，#8 约定）；四效果原语
## 求值——stat_amp 并入聚合链，proc_on_hit / proc_on_kill / convert_damage 交给
## EncounterSim（套装阶梯接入后复用同一求值器）。
## #31 增量：技能装配三槽执法（超过三槽 / 同一技能装多槽 = 状态非法报错——
## 同 id 多槽共享一份冷却，第二槽是永远放不出的死槽，绝不静默运行）；解锁判定
## 纯等级（level >= unlock_level 即可装配，无任何额外系统，build-system #2.3）。
## #32 增量：击杀是唯一掉落入口——遭遇模拟结束后按事件流顺序逐条 on_kill 走
## LootRoller 三层判定链（掉不掉 → 稀有度 → 实例生成），命中即在所属 on_kill
## 之后追加 drop 事件（在线/离线同规则）；ilvl 锚 = 区域等级（难度阶偏移归进度票，
## progression-structure §3）。
## #33 增量：背包进状态（inventory = 装备实例数组，入包序，无上限、只进不出，
## CONTEXT「背包」）。掉落 roll 时机沿用 #32 裁量（遭遇完结后统一补 roll），完结时
## 把全部 drop 实例按流序入包随 new_state 返回——「掉落事件发生即入包」
## （CONTEXT「自动拾取」），在线/离线同规则。换装三操作：equip（背包下标 + 槽位，
## 同槽一对一替换、旧件无损回包尾）/ unequip（穿戴位回包尾）——纯状态操作，永不
## 触碰技能装配（build 的两条装配轴互不影响）。「任意时刻换装、下一 tick 起按
## 新属性结算」由 run_encounter 的切片参数落实：budget_ticks 限本次推进的 tick 数，
## 未完场返回 in_progress + 续跑句柄（瞬态不入档，save-persistence §3），下一次
## 调用按传入的新状态重新聚合——怪血量、相位、技能冷却与 RNG 流跨切片连续，
## 当前遭遇不中断。query_stats = 聚合属性面板数据，与战斗共用同一条状态校验与
## 聚合路径（面板与战斗同源；编辑器「装备试算面板」同函数异端，inventory-equipment
## §4）。排序与筛选是纯表现层，本层不提供也不感知。进度推进、离线补算、落盘由
## 后续票接入；遭遇内血量瞬态不入档——「遭遇间玩家回满」由每场从满血起算直接成立。
## 确定性：种子从**完整输入**派生（区域、遭遇、等级、技能装配、装备形状）——
## 同输入必得同事件流；同关同级不同 build 不共享随机序列。背包不在种子部件里
## （掉落入包不扰动后续战斗）。

const TICK_MS := 100  # 引擎常量：tick 间隔，集中管理点（#24 引擎常量条款）
const BOSS_ENCOUNTER := -1  # encounter_index 哨兵：首领固定单挑（multi-monster-encounters #1）
const SKILL_SLOTS := 3  # 引擎常量：三主动技能槽（build-system #2.2）
const PLAYER_ID := "player"  # 事件流里的玩家身份（击杀怪物才掉落，玩家倒下不掉）
# 续跑句柄的必需键（模拟快照 5 键 + 门面附件 3 键）；_check_resume 据此执法。
const RESUME_KEYS: Array[String] = ["tick", "player_hp", "pnext", "mons", "cooldown",
	"rng_state", "events", "monster_ids"]


## 耗时换算：tick 是数值层原生时间单位，表现层 / 统计层需要毫秒时经此换算。
static func duration_ms(duration_ticks: int) -> int:
	return duration_ticks * TICK_MS


## 确定性：种子从**完整输入**派生（区域、遭遇、等级、技能装配、装备形状）——
## 同输入必得同事件流；同关同级不同 build 不共享随机序列。
static func _seed_parts(state: Dictionary, zone_id: String, encounter_index: int, level: int) -> Array:
	var skill_ids := PackedStringArray()
	for sid in state.get("skills", []):
		skill_ids.append(String(sid))
	return [
		zone_id, encounter_index, level,
		",".join(skill_ids),
		JSON.stringify(state.get("equipment", {})),
	]


## state = {"player_level": int, "equipment": {slot -> 实例 | null}, "skills": [skill_id, ...],
##          "inventory": [装备实例, ...]（可选；缺失视为空包）}
##   实例 = {"base": base_id, "affixes": [{"affix": id, "values": [{"attribute", "value"}...]}]}
##   （词缀实例按 mod 携带已定数值；传奇词缀免 values，#8 约定。）
## ref   = {"zone_id": String, "encounter_index": int（>= 0 普通，-1 首领）}
## budget_ticks = 本次调用最多推进的 tick 数（相对值；< 0 = 打完整场）。
## resume = 上一次 in_progress 返回的续跑句柄（{} = 全新开打）。
## 完结返回 = {"result": "win"|"lose", "duration_ticks": int, "events": Array,
##   "new_state": Dictionary}；切片返回 = {"result": "in_progress", "duration_ticks": int,
##   "events": Array（累计）, "resume": Dictionary}；
## 失败  = {"errors": PackedStringArray}（内容或状态非法，绝不静默给结果）。
static func run_encounter(state: Dictionary, content_db: ContentDB, ref: Dictionary,
		budget_ticks: int = -1, resume: Dictionary = {}) -> Dictionary:
	var prep := _prepare(state, content_db, ref)
	if prep["errors"].size() > 0:
		return {"errors": prep["errors"]}
	var stats := StatAggregator.aggregate(content_db.attributes, prep["level"], prep["equipped"])
	var rng: DeterministicRng
	var sim_resume: Dictionary = {}
	if resume.is_empty():
		rng = DeterministicRng.new(DeterministicRng.seed_from(
				_seed_parts(state, prep["zone_id"], prep["encounter_index"], prep["level"])))
	else:
		var handle_errors := _check_resume(resume, prep["mons"])
		if handle_errors.size() > 0:
			return {"errors": handle_errors}
		sim_resume = {
			"tick": int(resume["tick"]),
			"player_hp": float(resume["player_hp"]),
			"pnext": int(resume["pnext"]),
			"mons": resume["mons"],
			"cooldown": resume["cooldown"],
		}
		rng = DeterministicRng.new(int(resume["rng_state"]))
	var sim := EncounterSim.run({
		"stats": stats,
		"skills": prep["resolved_skills"],
		"effects": prep["fx"],
	}, prep["mons"], rng, budget_ticks, sim_resume)
	if String(sim["result"]) == "stalemate":
		return {"errors": PackedStringArray([
			"encounter exceeded the tick budget: content cannot converge (check monster HP vs player damage)",
		])}
	if String(sim["result"]) == "in_progress":
		var cum: Array = sim["events"]
		if not resume.is_empty():
			cum = (resume["events"] as Array) + cum
		return {
			"result": "in_progress",
			"duration_ticks": int(sim["duration_ticks"]),
			"events": cum,
			"resume": _resume_handle(sim["resume"], cum, prep["mons"]),
		}
	var events: Array = sim["events"]
	if not resume.is_empty():
		# 切片完结：合并此前各切片的累计流，drop 事件要插回各自 on_kill 之后。
		events = (resume["events"] as Array) + events
	var looted := _with_drops(events, prep["monster_of_display"], prep["is_leader"],
			int(prep["ilvl"]), content_db, rng)
	var drop_errors: PackedStringArray = looted["errors"]
	if not drop_errors.is_empty():
		return {"errors": drop_errors}
	var banked: Array = []
	for e in looted["events"]:
		if String(e.get("type", "")) == "drop":
			banked.append(e["instance"])
	return {
		"result": String(sim["result"]),
		"duration_ticks": int(sim["duration_ticks"]),
		"events": looted["events"],
		"new_state": _state_with_drops_banked(state, banked),
	}


## AC3：穿上背包第 inventory_index 件到 slot。同槽一对一替换：新件上身、旧件
## 无损回包尾（回包时刻序），一次调用完成、没有「先卸下腾位」的中间态。纯状态
## 操作：不改写输入状态、不触碰技能装配。返回前用 _validate_state 复检**整个结果
## 状态**——equip 拒绝制造任何战斗/面板都拒绝的非法状态（含穿入件自身的词缀/
## 属性引用），不会出现「穿上后打不了」的死锁；输入状态本身非法时同样拒绝并点名。
static func equip(state: Dictionary, content_db: ContentDB, inventory_index: int,
		slot: String) -> Dictionary:
	var errors := PackedStringArray()
	if not StatAggregator.EQUIP_SLOTS.has(slot):
		errors.append("unknown equipment slot: %s" % slot)
	var inventory: Array = []
	if state.get("inventory") is Array:
		inventory = state["inventory"]
	else:
		errors.append("state has no inventory array to equip from")
	var idx := int(inventory_index)
	if idx < 0 or idx >= inventory.size():
		errors.append("inventory index out of range: %d" % idx)
	var inst: Dictionary = {}
	if errors.is_empty():
		var candidate = inventory[idx]
		if not (candidate is Dictionary):
			errors.append("inventory item %d is not an instance object" % idx)
		else:
			inst = candidate
			var base_rec = content_db.item_bases.get(String(inst.get("base", "")))
			if base_rec == null:
				errors.append("unknown base id: %s" % str(inst.get("base", "")))
			elif String(base_rec["slot"]) != slot:
				errors.append("base %s (slot %s) cannot go into slot %s"
						% [String(base_rec["id"]), String(base_rec["slot"]), slot])
	if errors.size() > 0:
		return {"errors": errors}
	var next_state: Dictionary = state.duplicate_deep(Resource.DeepDuplicateMode.DEEP_DUPLICATE_ALL)
	var worn = (next_state["inventory"] as Array).pop_at(idx)
	# equipment 表缺失即建（与战斗路径对缺 equipment 的宽容一致——不是要求调用方预建形状）
	if not (next_state.get("equipment") is Dictionary):
		next_state["equipment"] = {}
	var previous = next_state["equipment"].get(slot)
	next_state["equipment"][slot] = worn
	if previous != null:
		(next_state["inventory"] as Array).append(previous)
	var check := _validate_state(next_state, content_db)
	if check["errors"].size() > 0:
		return {"errors": check["errors"]}
	return {"state": next_state}


## AC3：卸下 = 穿戴位实例移回背包尾（背包无上限，永远放得下）；空槽卸下是调用方
## bug，报错而非静默成功。不做 _validate_state 复检——unequip 是从非法状态里
## 逃出来的通道（比如外部改档穿进了坏实例），不能反过来把它堵死。
static func unequip(state: Dictionary, slot: String) -> Dictionary:
	var errors := PackedStringArray()
	if not StatAggregator.EQUIP_SLOTS.has(slot):
		errors.append("unknown equipment slot: %s" % slot)
	if errors.is_empty() and (not (state.get("equipment") is Dictionary)
			or state["equipment"].get(slot) == null):
		errors.append("equipment slot %s is empty" % slot)
	if errors.size() > 0:
		return {"errors": errors}
	var next_state: Dictionary = state.duplicate_deep(Resource.DeepDuplicateMode.DEEP_DUPLICATE_ALL)
	var worn = next_state["equipment"].get(slot)
	next_state["equipment"][slot] = null
	# inventory 缺失即建：卸下时背包必然放得下，形状归一化由门面负责
	if not (next_state.get("inventory") is Array):
		next_state["inventory"] = []
	(next_state["inventory"] as Array).append(worn)
	return {"state": next_state}


## AC6：聚合属性面板数据。与战斗共用 _validate_state 的校验与 aggregate 的聚合——
## 面板数字与战斗数字同源；非法状态拒绝，绝不静默给一张错表。
static func query_stats(state: Dictionary, content_db: ContentDB) -> Dictionary:
	var v := _validate_state(state, content_db)
	if v["errors"].size() > 0:
		return {"errors": v["errors"]}
	return {"stats": StatAggregator.aggregate(content_db.attributes, v["level"], v["equipped"])}


## 状态侧校验（等级 + 技能装配 + 穿戴实例），战斗与面板共用同一条执法路径。
## 返回 {"errors": PackedStringArray, "level": int, "resolved_skills": Array,
##   "equipped": Array（聚合输入）, "fx": {"on_hit" / "on_kill" / "convert"}}。
static func _validate_state(state: Dictionary, content_db: ContentDB) -> Dictionary:
	var errors := PackedStringArray()
	var level := int(state.get("player_level", 0))
	if level < 1:
		errors.append("player_level must be >= 1")

	var resolved_skills: Array = []
	var raw_skills = state.get("skills", [])
	if not (raw_skills is Array):
		errors.append("skills must be an array of skill ids (slot order)")
	else:
		if raw_skills.size() > SKILL_SLOTS:
			errors.append("skill slots overflow: %d loaded > %d slots"
					% [raw_skills.size(), SKILL_SLOTS])
		var seen_skills := {}  # 同一技能禁止装多槽：共享一份冷却会让第二槽永远放不出
		for sid in raw_skills:
			var sid_str := String(sid)
			if seen_skills.has(sid_str):
				errors.append("skill %s loaded in more than one slot" % sid_str)
				continue
			seen_skills[sid_str] = true
			var rec = content_db.skills.get(sid_str)
			if rec == null:
				errors.append("unknown skill id: %s" % sid_str)
				continue
			if int(rec["unlock_level"]) > level:
				errors.append("skill %s is locked (unlock_level %d > level %d)"
						% [sid_str, int(rec["unlock_level"]), level])
				continue
			resolved_skills.append(rec)

	var equipped: Array = []
	# 传奇效果收集（#30）：依装备槽序 × 实例词缀序 × 效果清单序展开，供遭遇模拟
	# 求值。stat_amp 直接并入聚合链；proc/convert 传给 EncounterSim（套装阶梯接入
	# 后复用同一求值器，set-items 既定）。效果数值固定于内容（#8 约定），实例不携带。
	var fx_on_hit: Array = []
	var fx_on_kill: Array = []
	var fx_convert: Array = []
	var equipment: Dictionary = state.get("equipment", {})
	for slot in StatAggregator.EQUIP_SLOTS:
		var inst = equipment.get(slot)
		if inst == null:
			continue
		if not (inst is Dictionary):
			errors.append("equipment slot %s must hold an instance object" % slot)
			continue
		var base_rec = content_db.item_bases.get(String(inst.get("base", "")))
		if base_rec == null:
			errors.append("unknown base id: %s" % str(inst.get("base", "")))
			continue
		if String(base_rec["slot"]) != slot:
			errors.append("base %s (slot %s) cannot go into slot %s"
					% [String(base_rec["id"]), String(base_rec["slot"]), slot])
			continue
		var entry := {"implicit": base_rec.get("implicit_mods", []), "affixes": []}
		for aff in inst.get("affixes", []):
			var arec = content_db.affixes.get(String(aff.get("affix", "")))
			if arec == null:
				errors.append("unknown affix id: %s" % str(aff.get("affix", "")))
				continue
			if String(arec["kind"]) == "legendary":
				for e in arec["legendary"].get("effects", []):
					match String(e["type"]):
						"stat_amp":
							entry["affixes"].append({
								"attribute": String(e["attribute"]),
								"value": float(e["value"]),
								"operation": String(e["operation"]),
							})
						"proc_on_hit":
							fx_on_hit.append({
								"chance_percent": float(e["chance_percent"]),
								"damage_type": String(e["damage_type"]),
								"damage_percent": float(e["damage_percent"]),
							})
						"proc_on_kill":
							fx_on_kill.append({
								"chance_percent": float(e["chance_percent"]),
								"effect": String(e["effect"]),
								"amount_percent": float(e["amount_percent"]),
							})
						"convert_damage":
							fx_convert.append({
								"from_type": String(e["from_type"]),
								"to_type": String(e["to_type"]),
								"percent": float(e["percent"]),
							})
				continue
			if not (aff.get("values") is Array):
				errors.append("affix instance %s needs a values array (per-mod rolled numbers); refusing to silently drop it"
						% String(aff.get("affix", "")))
				continue
			for v in aff["values"]:
				var attr_id := String(v.get("attribute", ""))
				if not content_db.attributes.has(attr_id):
					errors.append("unknown attribute in affix instance: %s" % attr_id)
					continue
				entry["affixes"].append({"attribute": attr_id, "value": float(v.get("value", 0.0))})
		equipped.append(entry)
	return {
		"errors": errors,
		"level": level,
		"resolved_skills": resolved_skills,
		"equipped": equipped,
		"fx": {"on_hit": fx_on_hit, "on_kill": fx_on_kill, "convert": fx_convert},
	}


## 战斗路径全量准备：状态校验 + 遭遇解析。errors 非空即拒绝，绝不带着坏输入开打。
static func _prepare(state: Dictionary, content_db: ContentDB, ref: Dictionary) -> Dictionary:
	var v := _validate_state(state, content_db)
	var errors: PackedStringArray = v["errors"]

	# 遭遇解析：-1 = 首领单挑；普通遭遇下标越界即错
	var zone_id := String(ref.get("zone_id", ""))
	var zone = content_db.zones.get(zone_id)
	if zone == null:
		errors.append("unknown zone id: %s" % zone_id)
	var monsters_spec: Array = []
	var encounter_index := int(ref.get("encounter_index", 0))
	if zone != null:
		if encounter_index == BOSS_ENCOUNTER:
			monsters_spec = [{"monster": String(zone["boss"]), "count": 1}]
		else:
			var encounters: Array = zone["encounters"]
			if encounter_index < 0 or encounter_index >= encounters.size():
				errors.append("encounter index out of range: %d" % encounter_index)
			else:
				monsters_spec = [encounters[encounter_index]]

	var mons: Array = []
	var monster_of_display := {}  # 站位 id -> 怪物 id（掉落 roll 要认出死的是哪只怪）
	for spec in monsters_spec:
		var mrec = content_db.monsters.get(String(spec["monster"]))
		if mrec == null:
			errors.append("unknown monster id: %s" % str(spec["monster"]))
			continue
		var count := int(spec.get("count", 1))
		# 同 id 多怪以 #序号 区分事件身份；站位序 = 展开序（表现层消费）
		for i in count:
			var display_id := String(mrec["id"]) if count == 1 else "%s#%d" % [String(mrec["id"]), i + 1]
			monster_of_display[display_id] = String(mrec["id"])
			mons.append({"id": display_id, "stats": mrec["stats"]})

	return {
		"errors": errors,
		"level": v["level"],
		"resolved_skills": v["resolved_skills"],
		"equipped": v["equipped"],
		"fx": v["fx"],
		"zone_id": zone_id,
		"encounter_index": encounter_index,
		"mons": mons,
		"monster_of_display": monster_of_display,
		"is_leader": encounter_index == BOSS_ENCOUNTER,
		"ilvl": int(zone["level"]) if zone != null else 0,
	}


## 续跑句柄 = 模拟快照（tick/player_hp/pnext/mons/cooldown/rng_state 六键原样）
## + 累计事件流 + 遭遇怪物清单。句柄是瞬态对象，只活在调用方内存里（在线循环
## 手里），不入档。
static func _resume_handle(sim_resume: Dictionary, cum_events: Array, mons: Array) -> Dictionary:
	var handle: Dictionary = sim_resume.duplicate()
	handle["events"] = cum_events
	handle["monster_ids"] = _monster_ids(mons)
	return handle


## 遭遇的怪物显示 id 清单（站位序）——句柄附件与句柄校验共用。
static func _monster_ids(mons: Array) -> Array:
	var ids: Array = []
	for m in mons:
		ids.append(String(m["id"]))
	return ids


## 句柄校验：RESUME_KEYS 齐全 + 形状正确 + 怪物清单与本次解析一致；不匹配 =
## 拒绝续跑，绝不静默续跑错场。
static func _check_resume(resume: Dictionary, mons: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in RESUME_KEYS:
		if not resume.has(key):
			errors.append("resume handle missing key: %s" % key)
	if not errors.is_empty():
		return errors
	var current := _monster_ids(mons)
	var handle_ids: Array = resume["monster_ids"]
	if JSON.stringify(handle_ids) != JSON.stringify(current):
		errors.append("resume handle does not match the resolved encounter (monster list changed)")
	if not (resume["mons"] is Array) or (resume["mons"] as Array).size() != current.size():
		errors.append("resume handle does not match the resolved encounter (monster states)")
	else:
		for rh in resume["mons"]:
			if not (rh is Dictionary) or not rh.has("hp") or not rh.has("next"):
				errors.append("resume handle monster states need hp and next")
				break
	if not (resume["events"] is Array):
		errors.append("resume handle events must be an array")
	if not (resume["cooldown"] is Dictionary):
		errors.append("resume handle cooldown must be a dictionary")
	return errors


## new_state = 输入状态的深拷贝 + 掉落入包（入包序）；输入状态永不被改写。
## inventory 缺失即建（形状归一化，存档票拿到的是完整形状）。
static func _state_with_drops_banked(state: Dictionary, banked: Array) -> Dictionary:
	var next_state: Dictionary = state.duplicate_deep(Resource.DeepDuplicateMode.DEEP_DUPLICATE_ALL)
	var inv: Array = []
	if next_state.get("inventory") is Array:
		inv = next_state["inventory"]
	else:
		next_state["inventory"] = inv
	for inst in banked:
		inv.append(inst)
	return next_state


## 掉落：逐条 on_kill 走三层判定链（击杀是唯一入口），命中即在它之后追加 drop
## 事件。首领由遭遇哨兵判定（首领 = 区域收尾遭遇的怪物，progression-structure §2）。
## drop.monster 是怪物内容 id（on_kill.victim 才是带站位后缀的显示 id）。
## 载荷 = 实例本体（摘要四条 base/name/rarity/ilvl 都在实例顶层）+ 来源击杀。
## loot-rarity §5 的「来源遭遇引用」不重复进载荷：一次门面调用即一场遭遇，
## 遭遇引用由调用方持有（离线补算逐场调用，天然带自己的 ref）。
static func _with_drops(events: Array, monster_of_display: Dictionary, is_leader: bool,
		ilvl: int, content_db: ContentDB, rng: DeterministicRng) -> Dictionary:
	var out: Array = []
	var errs := PackedStringArray()
	for e in events:
		out.append(e)
		if String(e.get("type", "")) != "on_kill":
			continue
		var victim := String(e["victim"])
		if victim == PLAYER_ID:
			continue  # 玩家倒下不是击杀，不掉落
		if not monster_of_display.has(victim):
			errs.append("drop roll: unknown kill victim '%s'" % victim)
			continue
		var monster_id := String(monster_of_display[victim])
		var mrec = content_db.monsters.get(monster_id)
		if mrec == null:
			errs.append("drop roll: unknown monster id '%s'" % monster_id)
			continue
		var drop := LootRoller.roll_kill({
			"ilvl": ilvl,
			"is_leader": is_leader,
			"drop_table": String(mrec.get("drop_table", "")),
			"item_bases": content_db.item_bases,
			"affixes": content_db.affixes,
			"droptables": content_db.droptables,
			"sets": content_db.sets,
		}, rng)
		if String(drop["error"]) != "":
			errs.append("drop roll for %s: %s" % [monster_id, String(drop["error"])])
			continue
		if bool(drop["dropped"]):
			out.append({"type": "drop", "monster": monster_id, "instance": drop["instance"]})
	return {"events": out, "errors": errs}
