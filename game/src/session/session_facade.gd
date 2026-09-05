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
## progression-structure §3）。掉落进背包归 #33，本票 new_state 仍原样透传。
## 进度推进、离线补算、落盘由后续票接入；new_state 目前为输入状态原样透传
## （遭遇内血量是瞬态不入档——「遭遇间玩家回满」由每场从满血起算直接成立，
## save-persistence §3 既定）。
## 确定性：种子从**完整输入**派生（区域、遭遇、等级、技能装配、装备形状）——
## 同输入必得同事件流；同关同级不同 build 不共享随机序列。

const TICK_MS := 100  # 引擎常量：tick 间隔，集中管理点（#24 引擎常量条款）
const BOSS_ENCOUNTER := -1  # encounter_index 哨兵：首领固定单挑（multi-monster-encounters #1）
const SKILL_SLOTS := 3  # 引擎常量：三主动技能槽（build-system #2.2）
const PLAYER_ID := "player"  # 事件流里的玩家身份（击杀怪物才掉落，玩家倒下不掉）


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


## state = {"player_level": int, "equipment": {slot -> 实例 | null}, "skills": [skill_id, ...]}
##   实例 = {"base": base_id, "affixes": [{"affix": id, "values": [{"attribute", "value"}...]}]}
##   （词缀实例按 mod 携带已定数值——#27 不做实例 roll，实例生成归掉落/背包票）
## ref   = {"zone_id": String, "encounter_index": int（>= 0 普通，-1 首领）}
## 成功  = {"result": "win"|"lose", "duration_ticks": int, "events": Array, "new_state": Dictionary}
## 失败  = {"errors": PackedStringArray}（内容或状态非法，绝不静默给结果）
static func run_encounter(state: Dictionary, content_db: ContentDB, ref: Dictionary) -> Dictionary:
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

	if errors.size() > 0:
		return {"errors": errors}

	var stats := StatAggregator.aggregate(content_db.attributes, level, equipped)
	var seed := DeterministicRng.seed_from(_seed_parts(state, zone_id, encounter_index, level))
	var rng := DeterministicRng.new(seed)
	var sim := EncounterSim.run({
		"stats": stats,
		"skills": resolved_skills,
		"effects": {"on_hit": fx_on_hit, "on_kill": fx_on_kill, "convert": fx_convert},
	}, mons, rng)
	if String(sim["result"]) == "stalemate":
		return {"errors": PackedStringArray([
			"encounter exceeded the tick budget: content cannot converge (check monster HP vs player damage)",
		])}
	var ilvl := int(zone["level"])  # 掉落 ilvl 锚 = 区域等级（难度阶偏移归进度票）
	var looted := _with_drops(sim["events"], monster_of_display,
			encounter_index == BOSS_ENCOUNTER, ilvl, content_db, rng)
	var drop_errors: PackedStringArray = looted["errors"]
	if not drop_errors.is_empty():
		return {"errors": drop_errors}
	return {
		"result": String(sim["result"]),
		"duration_ticks": int(sim["duration_ticks"]),
		"events": looted["events"],
		"new_state": state,
	}


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
