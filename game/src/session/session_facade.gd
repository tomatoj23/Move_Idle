class_name SessionFacade
extends RefCounted
## 引擎侧唯一对外顶层接口（#24 实施决策 A/E：唯一受测接缝）。
## 输入 = 存档状态（内存态）+ 内容库 + 遭遇引用；输出 = 结果 + 事件流 + 新状态。
## 战斗、聚合、随机性全部藏在私有实现后；事件载荷封闭、零回调。
## #27 范围：单场遭遇（encounter_index >= 0 = 普通遭遇下标，-1 = 首领单挑）。
## #30 增量：传奇词缀实例免 values（效果数值固定于内容，#8 约定）；四效果原语
## 求值——stat_amp 并入聚合链，proc_on_hit / proc_on_kill / convert_damage 交给
## EncounterSim（套装阶梯接入后复用同一求值器）。
## 进度推进、掉落、离线补算、落盘由后续票接入；new_state 目前为输入状态原样透传
## （遭遇内血量是瞬态不入档——「遭遇间玩家回满」由每场从满血起算直接成立，
## save-persistence §3 既定）。
## 确定性：种子从输入派生（zone + encounter + level），同输入必得同事件流。

const TICK_MS := 100  # 引擎常量：tick 间隔，集中管理点（#24 引擎常量条款）
const BOSS_ENCOUNTER := -1  # encounter_index 哨兵：首领固定单挑（multi-monster-encounters #1）


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
	for sid in state.get("skills", []):
		var rec = content_db.skills.get(String(sid))
		if rec == null:
			errors.append("unknown skill id: %s" % String(sid))
			continue
		if int(rec["unlock_level"]) > level:
			errors.append("skill %s is locked (unlock_level %d > level %d)"
					% [String(sid), int(rec["unlock_level"]), level])
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
	for spec in monsters_spec:
		var mrec = content_db.monsters.get(String(spec["monster"]))
		if mrec == null:
			errors.append("unknown monster id: %s" % str(spec["monster"]))
			continue
		var count := int(spec.get("count", 1))
		# 同 id 多怪以 #序号 区分事件身份；站位序 = 展开序（表现层消费）
		for i in count:
			var display_id := String(mrec["id"]) if count == 1 else "%s#%d" % [String(mrec["id"]), i + 1]
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
	return {
		"result": String(sim["result"]),
		"duration_ticks": int(sim["duration_ticks"]),
		"events": sim["events"],
		"new_state": state,
	}
