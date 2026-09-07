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
## 之后追加 drop 事件（在线/离线同规则）；ilvl 锚 = 有效等级（区域 level + 阶 ×
## 步长；难度阶已随 #34 落地，progression-structure §3）。
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
## §4）。排序与筛选是纯表现层，本层不提供也不感知。离线补算、落盘由后续票接入
## （进度推进已随 #34 落地，见下）；遭遇内血量瞬态不入档——「遭遇间玩家回满」
## 由每场从满血起算直接成立。
## #34 增量：进度结构进状态——unlocked（max_zone_order + zone_tiers）与 idle_spot
## （挂机点锚）为持久化字段，exp 入账与升级发生在遭遇边界（save-persistence §4）。
## 难度阶：ref.tier 把怪物基准 stats × 难度阶乘数^tier（全属性统一缩放的字面口径，
## 缩放公式归 Progression 常量），
## 有效等级 = 区域 level + tier × 步长，即掉落 ilvl 与击杀经验的唯一锚（角色等级
## 不参与，progression-structure §6）。解锁门拒绝未解锁的区域 / 阶，绝不放行越级
## 战斗。首领胜 = 两维解锁（order+1 区域、tier+1 阶）+ 首通时挂机点沿链自动推进
## （先区域链、链顶爬阶；无新解锁不挪锚——回头刷旧区域由此成立）；遭遇失败的
## 回退落点即挂机点（非起点退当前区域起点，起点再败退上一区域起点第 0 阶，
## 永不挂起）。next_ref = 在线走图决策（纯读）；set_idle_spot = 玩家自选挂机点
## （限已解锁）。种子部件不含 tier：同输入必得同事件流在任意固定 tier 下成立。
## 对 #39 离线票的接缝：离线补算必须把 new_state 的 unlocked / idle_spot 还原为
## 会话前取值（「离线不推进、不写解锁」由离线结算票保证），经验 / 掉落照常入账。
## #35 增量：套装阶梯进聚合链（set-items #18）——穿着件数只数装备槽中的成员件
## （背包里的不算），每套独立计数，多套互不稀释；件数达标（最低 2 件）即激活
## 对应档，3 件 = 两档叠加。效果展开与传奇词缀共用同一求值器：stat_amp 作为
## 聚合链第四来源（StatAggregator.aggregate 的 bonus 参数），proc/convert 按
## 同形载荷进 EncounterSim 结算钩子。套装归属由 base_id 对套装对象反查推导——
## 不入档、不入种子（equipment JSON 已在种子部件里，推导态随装备自动确定）。
## 展开序 = 套装 id 字典序（对内容目录序无关）× 档位清单序（schema 约定升序，
## 校验器执法）× 效果清单序：同一内容库下确定。
## 确定性：种子从**完整输入**派生（区域、遭遇、等级、技能装配、装备形状）——
## 同输入必得同事件流；同关同级不同 build 不共享随机序列。背包不在种子部件里
## （掉落入包不扰动后续战斗）；tier 也不在部件里（同输入在固定 tier 下必得同流，
## 见上 #34 注）。

const TICK_MS := 100  # 引擎常量：tick 间隔，集中管理点（#24 引擎常量条款）
const BOSS_ENCOUNTER := -1  # encounter_index 哨兵：首领固定单挑（multi-monster-encounters #1）
const SKILL_SLOTS := 3  # 引擎常量：三主动技能槽（build-system #2.2）
const PLAYER_ID := "player"  # 事件流里的玩家身份（击杀怪物才掉落，玩家倒下不掉）
# 续跑句柄的必需键（模拟快照 5 键 + 门面附件 4 键）；_check_resume 据此执法。
const RESUME_KEYS: Array[String] = ["tick", "player_hp", "pnext", "mons", "cooldown",
	"rng_state", "events", "monster_ids", "tier"]


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
	var stats := StatAggregator.aggregate(content_db.attributes, prep["level"],
			prep["equipped"], prep["set_mods"])
	var rng: DeterministicRng
	var sim_resume: Dictionary = {}
	if resume.is_empty():
		rng = DeterministicRng.new(DeterministicRng.seed_from(
				_seed_parts(state, prep["zone_id"], prep["encounter_index"], prep["level"])))
	else:
		var handle_errors := _check_resume(resume, prep["mons"], int(prep["tier"]))
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
			"resume": _resume_handle(sim["resume"], cum, prep["mons"], int(prep["tier"])),
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
	var next_state := _state_with_drops_banked(state, banked)
	# 遭遇边界的进度结算（#34）：经验入账 + 首领解锁/锚推进 + 失败回退锚。
	# 写入的是深拷贝 new_state，输入状态永不改写。
	_with_progression(next_state, content_db, prep, String(sim["result"]), events)
	return {
		"result": String(sim["result"]),
		"duration_ticks": int(sim["duration_ticks"]),
		"events": looted["events"],
		"new_state": next_state,
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
	return {"stats": StatAggregator.aggregate(content_db.attributes, v["level"],
			v["equipped"], v["set_mods"])}


## AC5：玩家自选挂机点（区域 + 难度阶），限已解锁（progression-structure §5）。
## 纯状态操作：只写 idle_spot，不触碰战斗轴（技能 / 穿戴 / 背包互不影响），也不
## 复检整个状态——挂机点不参与战斗校验，指向非法内容的锚会在 run_encounter 的
## 进度门被拒绝。解锁判定与 _prepare 同一条默认值路径（缺 unlocked = 新档）。
static func set_idle_spot(state: Dictionary, content_db: ContentDB, zone_id: String,
		tier: int) -> Dictionary:
	var errors := PackedStringArray()
	var zone = content_db.zones.get(zone_id)
	if zone == null:
		errors.append("unknown zone id: %s" % zone_id)
	if tier < 0:
		errors.append("tier must be >= 0, got %d" % tier)
	errors = _check_unlock_gate(errors, state, content_db, zone_id, zone, tier)
	if errors.size() > 0:
		return {"errors": errors}
	var next_state: Dictionary = state.duplicate_deep(Resource.DeepDuplicateMode.DEEP_DUPLICATE_ALL)
	next_state["idle_spot"] = {"zone_id": zone_id, "tier": tier}
	return {"state": next_state}


## AC1/AC4/AC8：在线走图决策（纯读，不写状态）。last_ref = {} 或 last_result 非
## "win" = 从挂机点锚出发（区域遭遇清单头，tier 取锚的阶）——首领胜的首通推进与
## 失败的回退锚已由 run_encounter 写入 new_state，本函数只按锚重出发；上一步是
## 普通遭遇且胜 → 走图前移（清单尾则首领，同区同阶）。返回
## {"ref": {"zone_id", "encounter_index", "tier"}} 或 {"errors": PackedStringArray}。
## 走图位置是瞬态不入档：重启 = 本函数以空 last_ref 从锚重出发（save-persistence §3）。
static func next_ref(state: Dictionary, content_db: ContentDB, last_ref: Dictionary,
		last_result: String) -> Dictionary:
	var errors := PackedStringArray()
	if last_result != "win" and last_result != "lose" and last_result != "":
		errors.append("unknown last_result: %s (expected win|lose|\"\")" % last_result)
	var spot: Dictionary = {}
	if state.get("idle_spot") is Dictionary and not (state["idle_spot"] as Dictionary).is_empty():
		spot = state["idle_spot"]
	else:
		spot = Progression.default_idle_spot(content_db.zones)
	if spot.is_empty() or not content_db.zones.has(String(spot.get("zone_id", ""))):
		errors.append("idle spot points at no known zone: %s" % str(spot.get("zone_id", "")))
	if errors.size() > 0:
		return {"errors": errors}
	var anchor := {
		"zone_id": String(spot["zone_id"]),
		"encounter_index": 0,
		"tier": int(spot.get("tier", 0)),
	}
	if last_ref.is_empty() or last_result != "win":
		return {"ref": anchor}
	var zone_id := String(last_ref.get("zone_id", ""))
	var zone = content_db.zones.get(zone_id)
	if zone == null:
		return {"errors": PackedStringArray(["unknown last_ref zone: %s" % zone_id])}
	var index := int(last_ref.get("encounter_index", 0))
	if index == BOSS_ENCOUNTER:
		return {"ref": anchor}
	if index < 0:
		return {"errors": PackedStringArray(["bad last_ref encounter index: %d" % index])}
	var encounters: Array = zone["encounters"]
	if index >= encounters.size():
		# 越界下标是上游 bug（run_encounter 拒收越界 ref，正常循环到不了这里）——
		# 拒绝而不是静默升格成首领，「绝不静默给结果」的接缝契约。
		return {"errors": PackedStringArray(["last_ref encounter index out of range: %d" % index])}
	if index + 1 < encounters.size():
		return {"ref": {"zone_id": zone_id, "encounter_index": index + 1,
				"tier": int(last_ref.get("tier", 0))}}
	return {"ref": {"zone_id": zone_id, "encounter_index": BOSS_ENCOUNTER,
			"tier": int(last_ref.get("tier", 0))}}


## 状态侧校验（等级 + 技能装配 + 穿戴实例 + 套装阶梯展开），战斗与面板共用同一条
## 执法路径。返回 {"errors": PackedStringArray, "level": int, "resolved_skills": Array,
##   "equipped": Array（聚合输入）, "fx": {"on_hit" / "on_kill" / "convert"},
##   "set_mods": Array（套装阶梯的 stat_amp，聚合链第四来源）}。
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
	var worn_bases: Array = []  # 已通过校验入列的穿戴基底 id（套装件数只数它们）
	# 传奇效果收集（#30）：依装备槽序 × 实例词缀序 × 效果清单序展开，供遭遇模拟
	# 求值。stat_amp 直接并入聚合链；proc/convert 传给 EncounterSim（套装阶梯
	# #35 已接入，同一求值器）。效果数值固定于内容（#8 约定），实例不携带。
	var fx_on_hit: Array = []
	var fx_on_kill: Array = []
	var fx_convert: Array = []
	# 效果钩子聚合视图（Array 是引用类型）：共用展开器 _expand_effect 与返回载荷都指向它们。
	var fx := {"on_hit": fx_on_hit, "on_kill": fx_on_kill, "convert": fx_convert}
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
					_expand_effect(e, entry["affixes"], fx)
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
		worn_bases.append(String(base_rec["id"]))
	# 套装阶梯（#35，set-items #18 §2/§4）：件数只数装备槽中的成员件（背包不算），
	# 每套独立计数；pieces <= worn 的档全部激活（3 件 = 2 件档 + 3 件档叠加），
	# 阈值下限 2 件由内容库断言保证（tiers[].pieces >= 2）。展开序 = 套装 id
	# 字典序（对内容目录序无关）× 档位清单序（schema 约定升序，校验器 #26 执法）
	# × 效果清单序。stat_amp 进聚合链第四来源（set_mods）；proc/convert 与传奇
	# 词缀共用 _expand_effect（同一求值器，不新增原语）。
	var set_mods: Array = []
	var set_ids: Array = content_db.sets.keys()
	set_ids.sort()
	for sid in set_ids:
		var set_rec: Dictionary = content_db.sets[sid]
		var worn := 0
		for base_id in worn_bases:
			if (set_rec["members"] as Array).has(base_id):
				worn += 1
		for tier in set_rec["tiers"]:
			if int(tier["pieces"]) > worn:
				continue
			for e in tier["effects"]:
				_expand_effect(e, set_mods, fx)
	return {
		"errors": errors,
		"level": level,
		"resolved_skills": resolved_skills,
		"equipped": equipped,
		"fx": fx,
		"set_mods": set_mods,
	}


## 单条效果原语的归一化展开——传奇词缀（#30）与套装阶梯（#35）共用同一形状契约：
## stat_amp 落 stat_target（传奇 = 携带实例的词缀表，套装 = 聚合链第四来源 bonus），
## proc/convert 落 fx 对应结算钩子数组。载荷字段与 schema 原语一一对应。
static func _expand_effect(e: Dictionary, stat_target: Array, fx: Dictionary) -> void:
	match String(e["type"]):
		"stat_amp":
			stat_target.append({
				"attribute": String(e["attribute"]),
				"value": float(e["value"]),
				"operation": String(e["operation"]),
			})
		"proc_on_hit":
			(fx["on_hit"] as Array).append({
				"chance_percent": float(e["chance_percent"]),
				"damage_type": String(e["damage_type"]),
				"damage_percent": float(e["damage_percent"]),
			})
		"proc_on_kill":
			(fx["on_kill"] as Array).append({
				"chance_percent": float(e["chance_percent"]),
				"effect": String(e["effect"]),
				"amount_percent": float(e["amount_percent"]),
			})
		"convert_damage":
			(fx["convert"] as Array).append({
				"from_type": String(e["from_type"]),
				"to_type": String(e["to_type"]),
				"percent": float(e["percent"]),
			})


## 战斗路径全量准备：状态校验 + 遭遇解析。errors 非空即拒绝，绝不带着坏输入开打。
static func _prepare(state: Dictionary, content_db: ContentDB, ref: Dictionary) -> Dictionary:
	var v := _validate_state(state, content_db)
	var errors: PackedStringArray = v["errors"]

	# 遭遇解析：-1 = 首领单挑；普通遭遇下标越界即错。
	var zone_id := String(ref.get("zone_id", ""))
	var zone = content_db.zones.get(zone_id)
	if zone == null:
		errors.append("unknown zone id: %s" % zone_id)
	var tier := int(ref.get("tier", 0))
	if tier < 0:
		errors.append("tier must be >= 0, got %d" % tier)
	# 进度门（#34）：区域与难度阶都必须已解锁，绝不放行越级战斗。只读视图，
	# 缺字段按新档默认值（最早区域 / 第 0 阶）——不写回输入状态。
	errors = _check_unlock_gate(errors, state, content_db, zone_id, zone, tier)
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

	# 难度阶（#34 AC3）：怪物基准 stats × 难度阶乘数^tier（scale_stats 返回新字典，
	# 内容库基准记录只读不改写）；有效等级 = 区域 level + tier × 步长，是掉落
	# ilvl 与击杀经验的唯一锚（progression-structure §3/§6）。
	var eff_level := 0
	if zone != null:
		eff_level = Progression.effective_level(int(zone["level"]), tier)
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
			mons.append({"id": display_id, "stats": Progression.scale_stats(mrec["stats"], tier)})

	return {
		"errors": errors,
		"level": v["level"],
		"resolved_skills": v["resolved_skills"],
		"equipped": v["equipped"],
		"fx": v["fx"],
		"set_mods": v["set_mods"],
		"zone_id": zone_id,
		"encounter_index": encounter_index,
		"tier": tier,
		"eff_level": eff_level,
		"mons": mons,
		"monster_of_display": monster_of_display,
		"is_leader": encounter_index == BOSS_ENCOUNTER,
		"ilvl": eff_level,
	}


## 续跑句柄 = 模拟快照（tick/player_hp/pnext/mons/cooldown/rng_state 六键原样）
## + 累计事件流 + 遭遇怪物清单 + 遭遇难度阶。句柄是瞬态对象，只活在调用方内存
## 里（在线循环手里），不入档。
static func _resume_handle(sim_resume: Dictionary, cum_events: Array, mons: Array,
		tier: int) -> Dictionary:
	var handle: Dictionary = sim_resume.duplicate()
	handle["events"] = cum_events
	handle["monster_ids"] = _monster_ids(mons)
	handle["tier"] = tier
	return handle


## 遭遇的怪物显示 id 清单（站位序）——句柄附件与句柄校验共用。
static func _monster_ids(mons: Array) -> Array:
	var ids: Array = []
	for m in mons:
		ids.append(String(m["id"]))
	return ids


## 句柄校验：RESUME_KEYS 齐全 + 形状正确 + 怪物清单与难度阶与本次解析一致
## （#34：同 zone/index 换 tier 续跑 = HP 快照套在缩放不同的怪物上，拒绝）；
## 不匹配 = 拒绝续跑，绝不静默续跑错场。
static func _check_resume(resume: Dictionary, mons: Array, tier: int) -> PackedStringArray:
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
	if int(resume["tier"]) != tier:
		errors.append("resume handle does not match the resolved encounter (tier changed)")
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


# ---------------------------------------------------------------- #34 progression

## 遭遇边界的进度结算（AC1/2/4/5/6/8）：进度字段形状归一化 → 击杀经验入账
## （胜负皆入账——击杀即经验）→ 首领胜的两维解锁与挂机点首通推进 → 失败的回退锚。
## 只写 next_state（深拷贝）；本路径不产生拒绝性错误，内容合法性已由 _prepare 把关。
static func _with_progression(next_state: Dictionary, content_db: ContentDB,
		prep: Dictionary, result: String, events: Array) -> void:
	_norm_progression(next_state, content_db)
	Progression.bank_kills(next_state, _kill_count(events), int(prep["eff_level"]))
	if result == "win" and bool(prep["is_leader"]):
		_advance_anchor_after_boss(next_state, content_db, prep)
	elif result == "lose":
		_fallback_anchor(next_state, content_db, prep)


## 首领胜：解锁 order+1 区域与 tier+1（max 语义——重打不清零、不回退）；首通
## （本次产生新解锁）时挂机点沿链自动推进：先区域链（推进 = 依次打通区域，
## progression-structure §1），链顶才爬阶；无新解锁（重刷旧首领）不挪锚——
## 挂机点停在玩家自选处，回头刷旧区域由此成立（§5）。
static func _advance_anchor_after_boss(next_state: Dictionary, content_db: ContentDB,
		prep: Dictionary) -> void:
	var zones: Dictionary = content_db.zones
	var zone_id := String(prep["zone_id"])
	var order := int(zones[zone_id]["order"])
	var tier := int(prep["tier"])
	var unlocked: Dictionary = next_state["unlocked"]
	var zone_tiers: Dictionary = unlocked["zone_tiers"]
	var max_before := int(unlocked["max_zone_order"])
	var tier_before := int(zone_tiers.get(zone_id, 0))
	unlocked["max_zone_order"] = maxi(max_before, order + 1)
	zone_tiers[zone_id] = maxi(tier_before, tier + 1)
	var next_zone := Progression.zone_by_order(zones, order + 1)
	if next_zone != "" and max_before < order + 1:
		next_state["idle_spot"] = {"zone_id": next_zone, "tier": 0}
	elif tier_before < tier + 1:
		next_state["idle_spot"] = {"zone_id": zone_id, "tier": tier + 1}


## 失败回退（AC4，永不挂起）：非起点遭遇（含首领）失败退当前区域起点重刷（同阶）；
## 当前区域起点（普通第 0 场）再败退上一区域起点并落回第 0 阶——上一区域的高阶
## 未必已解锁，第 0 阶恒合法且必然已被打通（区域解锁链逐级指向它）；链底没有
## 上一区域就原地重试。回退落点即挂机点（progression-structure §5）：锚跟随回退，
## 「挂机点永远可赢」由回退规则保证。
static func _fallback_anchor(next_state: Dictionary, content_db: ContentDB,
		prep: Dictionary) -> void:
	var zones: Dictionary = content_db.zones
	var zone_id := String(prep["zone_id"])
	var landing := {"zone_id": zone_id, "tier": int(prep["tier"])}
	if int(prep["encounter_index"]) == 0 and not bool(prep["is_leader"]):
		var prev := Progression.zone_by_order(zones, int(zones[zone_id]["order"]) - 1)
		if prev != "":
			landing = {"zone_id": prev, "tier": 0}
	next_state["idle_spot"] = landing


## 进度字段形状归一化（save-persistence §8 前向兼容：缺字段补默认值）。只作用于
## new_state 深拷贝；unlocked / exp / idle_spot 缺失即按新档默认补齐，存档票拿到
## 的状态恒为完整形状。非法形状（unlocked 不是字典等）同样归一化为默认——
## 内容引用的合法性由 run_encounter 的进度门按最终值执法。
static func _norm_progression(next_state: Dictionary, content_db: ContentDB) -> void:
	if not (next_state.get("unlocked") is Dictionary):
		next_state["unlocked"] = Progression.default_unlocked(content_db.zones)
	var unlocked: Dictionary = next_state["unlocked"]  # 深拷贝产物，写入安全
	if not (unlocked.get("zone_tiers") is Dictionary):
		unlocked["zone_tiers"] = {}
	if not unlocked.has("max_zone_order"):
		unlocked["max_zone_order"] = Progression.min_zone_order(content_db.zones)
	if not next_state.has("exp"):
		next_state["exp"] = 0
	if not (next_state.get("idle_spot") is Dictionary) \
			or (next_state["idle_spot"] as Dictionary).is_empty():
		next_state["idle_spot"] = Progression.default_idle_spot(content_db.zones)


## 解锁游标只读视图：缺字段按新档默认值补齐，绝不写回输入状态（门面的一切状态
## 写入只发生在 new_state 深拷贝上）。_prepare / set_idle_spot / 进度门共用。
static func _unlocked_view(state: Dictionary, content_db: ContentDB) -> Dictionary:
	var src: Dictionary = {}
	if state.get("unlocked") is Dictionary:
		src = state["unlocked"]
	var zone_tiers: Dictionary = {}
	if src.get("zone_tiers") is Dictionary:
		zone_tiers = src["zone_tiers"]
	var max_order := Progression.min_zone_order(content_db.zones)
	if src.has("max_zone_order"):
		max_order = int(src["max_zone_order"])
	return {"max_zone_order": max_order, "zone_tiers": zone_tiers}


## 解锁门（#34 AC1/AC2/AC5 执法点）：区域与难度阶都必须已解锁，绝不放行越级
## 战斗 / 锚选择。errors 以返回值传出（PackedStringArray 是值类型，就地追加不出
## 函数）；zone 可为 null（unknown zone 的报错由调用方负责）；缺 unlocked 字段
## 按新档默认值。战斗路径与挂机点选择共用同一条执法与同一套文案。
static func _check_unlock_gate(errors: PackedStringArray, state: Dictionary,
		content_db: ContentDB, zone_id: String, zone, tier: int) -> PackedStringArray:
	var unlocked := _unlocked_view(state, content_db)
	var max_order := int(unlocked["max_zone_order"])
	var zone_tiers: Dictionary = unlocked["zone_tiers"]
	if zone != null and int(zone["order"]) > max_order:
		errors.append("zone %s is locked (order %d > max unlocked order %d)"
				% [zone_id, int(zone["order"]), max_order])
	if zone != null and tier > int(zone_tiers.get(zone_id, 0)):
		errors.append("tier %d of zone %s is locked (max unlocked tier %d)"
				% [tier, zone_id, int(zone_tiers.get(zone_id, 0))])
	return errors


## 击杀数 = 事件流里 victim 非玩家的 on_kill 条数（玩家是唯一击杀方：直杀、
## proc 与爆炸连锁都算玩家战果；玩家倒下的那条不是击杀）。
static func _kill_count(events: Array) -> int:
	var n := 0
	for e in events:
		if String(e.get("type", "")) == "on_kill" and String(e.get("victim", "")) != PLAYER_ID:
			n += 1
	return n
