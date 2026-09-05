class_name ContentDB
extends RefCounted
## 内容直载层：把 content/ 九类纯 JSON 载入内存并做引擎侧轻量断言。
## 断言只覆盖「必需字段 + 引用存在性 + id 约定 + 战斗语义前置」，绝不重复实现 schema
## 校验（校验器 #26 是唯一 schema 真相，#24 实施决策 A）；坏内容一律收集为错误，
## 由调用方拒绝启动——不静默继续。
## 已知引擎事实（规格 F + 本仓实测）：JSON 回读数字一律 float——整型字段全部宽接收
## 显式转 int；文件读取用 get_as_text() 无参形态（4.6 镜像行）。

const TYPE_DIRS := {
	"attributes": "attributes",
	"item_bases": "items/base",
	"affixes": "affixes",
	"monsters": "monsters",
	"monster_modifiers": "monster_modifiers",
	"droptables": "droptables",
	"zones": "zones",
	"skills": "skills",
	"sets": "sets",
}

const DAMAGE_TYPES := ["physical", "fire", "cold", "lightning", "poison", "arcane"]
const EFFECT_PRIMITIVES := ["stat_amp", "proc_on_hit", "proc_on_kill", "convert_damage"]
# 装备槽是域概念，单一真相在数值层聚合器（本层与门面共用）
const EQUIP_SLOTS: Array = StatAggregator.EQUIP_SLOTS

var errors: PackedStringArray = PackedStringArray()
var attributes := {}
var item_bases := {}
var affixes := {}
var monsters := {}
var monster_modifiers := {}
var droptables := {}
var zones := {}
var skills := {}
var sets := {}


static func load_from_dir(root: String) -> ContentDB:
	var db := ContentDB.new()
	var seen := {}  # id -> 类型名（跨类型全局唯一，schema/README 核心规则 2）
	for key in TYPE_DIRS:
		var rel: String = TYPE_DIRS[key]
		var dir_path := root.path_join(rel)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			db.errors.append("content dir missing: " + rel)
			continue
		db._load_dir(dir, dir_path, key, seen)
	db._assert_refs()
	return db


func _load_dir(dir: DirAccess, dir_path: String, key: String, seen: Dictionary) -> void:
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			var sub := DirAccess.open(full)
			if sub != null:
				_load_dir(sub, full, key, seen)
		elif entry.get_extension() == "json":
			_load_file(full, key, seen)
		entry = dir.get_next()
	dir.list_dir_end()


func _load_file(path: String, key: String, seen: Dictionary) -> void:
	var obj_id := path.get_file().get_basename()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append(path + ": cannot open file")
		return
	var text := f.get_as_text()
	f = null
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		errors.append(path + ": not a valid JSON object")
		return
	var obj: Dictionary = parsed
	if String(obj.get("id", "")) != obj_id:
		errors.append("%s: id '%s' does not match filename" % [path, str(obj.get("id", ""))])
	if seen.has(obj_id):
		errors.append("%s: duplicate id '%s' (already loaded as %s)" % [path, obj_id, seen[obj_id]])
		return
	seen[obj_id] = key
	var table := _table_for(key)
	# 对象级断言；通过才入库（引用断言阶段只会看到合法对象）
	if not _assert_object(obj, path, key):
		return
	table[obj_id] = obj


func _table_for(key: String) -> Dictionary:
	match key:
		"attributes":
			return attributes
		"item_bases":
			return item_bases
		"affixes":
			return affixes
		"monsters":
			return monsters
		"monster_modifiers":
			return monster_modifiers
		"droptables":
			return droptables
		"zones":
			return zones
		"skills":
			return skills
		"sets":
			return sets
	return {}


func _required(key: String) -> Array:
	match key:
		"attributes":
			return ["id", "name", "aggregation"]
		"item_bases":
			return ["id", "name", "slot", "category"]
		"affixes":
			return ["id", "name", "kind"]
		"monsters":
			return ["id", "name", "stats"]
		"monster_modifiers":
			return ["id", "name", "mods"]
		"droptables":
			return ["id", "entries"]
		"zones":
			return ["id", "name", "level", "encounters", "boss", "order"]
		"skills":
			return ["id", "name", "multiplier", "cooldown_ticks", "damage_type", "unlock_level"]
		"sets":
			return ["id", "name", "members", "tiers"]
	return []


## 对象级轻量断言（必需字段 + 枚举成员 + 战斗语义前置）。true = 入库。
func _assert_object(obj: Dictionary, path: String, key: String) -> bool:
	var ok := true
	for field in _required(key):
		if not obj.has(field):
			errors.append("%s: missing required field '%s'" % [path, field])
			ok = false
	if not ok:
		return false
	match key:
		"attributes":
			if not ["add", "multiply"].has(String(obj["aggregation"])):
				errors.append("%s: aggregation must be add|multiply" % path)
				ok = false
		"item_bases":
			if not EQUIP_SLOTS.has(String(obj["slot"])):
				errors.append("%s: slot must be weapon|armor|trinket" % path)
				ok = false
			for mod in obj.get("implicit_mods", []):
				ok = _assert_stat_value(mod, path) and ok
		"affixes":
			ok = _assert_affix(obj, path) and ok
		"monsters":
			ok = _assert_battle_stats(obj["stats"], path) and ok
		"monster_modifiers":
			for mod in obj["mods"]:
				ok = _assert_stat_op(mod, path) and ok
		"droptables":
			for entry in obj["entries"]:
				ok = _assert_droptable_entry(entry, path) and ok
		"zones":
			var encounters: Array = obj["encounters"]
			if encounters.is_empty():
				errors.append(path + ": encounters must not be empty")
				ok = false
			for enc in encounters:
				if not (enc is Dictionary) or String(enc.get("monster", "")) == "":
					errors.append(path + ": encounters entries need a monster ref")
					ok = false
					continue
				if enc.has("count") and (int(enc["count"]) < 1 or int(enc["count"]) > 5):
					errors.append("%s: encounter count %d out of [1,5]" % [path, int(enc["count"])])
					ok = false
			if int(obj["level"]) < 1:
				errors.append(path + ": level must be >= 1")
				ok = false
			if int(obj["order"]) < 1:
				errors.append(path + ": order must be >= 1")
				ok = false
		"skills":
			if float(obj["multiplier"]) <= 0.0:
				errors.append(path + ": multiplier must be > 0")
				ok = false
			if int(obj["cooldown_ticks"]) < 1:
				errors.append(path + ": cooldown_ticks must be >= 1")
				ok = false
			if not DAMAGE_TYPES.has(String(obj["damage_type"])):
				errors.append(path + ": unknown damage_type '%s'" % String(obj["damage_type"]))
				ok = false
			if int(obj["unlock_level"]) < 1:
				errors.append(path + ": unlock_level must be >= 1")
				ok = false
		"sets":
			var members: Array = obj["members"]
			if members.size() < 2:
				errors.append(path + ": members needs at least 2 bases")
				ok = false
			for m in members:
				if String(m) == "":
					errors.append(path + ": members entries must be base refs")
					ok = false
			var tiers: Array = obj["tiers"]
			if tiers.is_empty():
				errors.append(path + ": tiers must not be empty")
				ok = false
			for tier in tiers:
				if not (tier is Dictionary) or int(tier.get("pieces", 0)) < 2:
					errors.append(path + ": tier needs pieces >= 2")
					ok = false
					continue
				ok = _assert_effects(tier.get("effects", []), path) and ok
	return ok


func _assert_affix(obj: Dictionary, path: String) -> bool:
	var kind := String(obj["kind"])
	if kind == "stat":
		var ok := true
		if not obj.has("position"):
			errors.append(path + ": stat affix needs position")
			ok = false
		if not obj.has("mods") or (obj["mods"] as Array).is_empty():
			errors.append(path + ": stat affix needs non-empty mods")
			ok = false
			return false
		for mod in obj["mods"]:
			if not (mod is Dictionary) or String(mod.get("attribute", "")) == "":
				errors.append(path + ": mods entries need an attribute ref")
				ok = false
				continue
			if not mod.has("tiers") or (mod["tiers"] as Array).is_empty():
				errors.append(path + ": mods entries need non-empty tiers")
				ok = false
		return ok
	if kind == "legendary":
		var legendary = obj.get("legendary")
		if not (legendary is Dictionary):
			errors.append(path + ": legendary affix needs a legendary object")
			return false
		return _assert_effects(legendary.get("effects", []), path)
	errors.append(path + ": kind must be stat|legendary")
	return false


func _assert_effects(effects: Array, path: String) -> bool:
	var ok := not effects.is_empty()
	if effects.is_empty():
		errors.append(path + ": effects must not be empty")
	for e in effects:
		if not (e is Dictionary):
			errors.append(path + ": effect must be an object")
			ok = false
			continue
		match String(e.get("type", "")):
			"stat_amp":
				ok = _has_fields(e, path, ["attribute", "operation", "value"]) and ok
			"proc_on_hit":
				ok = _has_fields(e, path, ["chance_percent", "damage_type", "damage_percent"]) and ok
				if ok and not DAMAGE_TYPES.has(String(e["damage_type"])):
					errors.append("%s: proc_on_hit damage_type must be a known damage type, got '%s'"
							% [path, String(e["damage_type"])])
					ok = false
			"proc_on_kill":
				ok = _has_fields(e, path, ["chance_percent", "effect", "amount_percent"]) and ok
				if ok and not ["heal_percent_of_max_hp", "explode_fire"].has(String(e["effect"])):
					errors.append("%s: proc_on_kill effect must be heal_percent_of_max_hp|explode_fire, got '%s'"
							% [path, String(e["effect"])])
					ok = false
			"convert_damage":
				ok = _has_fields(e, path, ["from_type", "to_type", "percent"]) and ok
				if ok:
					for t in ["from_type", "to_type"]:
						if not DAMAGE_TYPES.has(String(e[t])):
							errors.append("%s: convert_damage %s must be a known damage type, got '%s'"
									% [path, t, String(e[t])])
							ok = false
			_:
				errors.append("%s: unknown effect primitive '%s'" % [path, String(e.get("type", ""))])
				ok = false
	return ok


func _assert_battle_stats(stats: Dictionary, path: String) -> bool:
	# 战斗语义前置：tick 模型与胜负判定必需属性（combat-model #1）；缺失/非法不静默。
	var ok := true
	for must in ["max_hp", "attack_power", "attack_speed"]:
		if not stats.has(must):
			errors.append("%s: monster stats missing battle-required '%s'" % [path, must])
			ok = false
		elif not (stats[must] is float or stats[must] is int):
			errors.append("%s: monster stat '%s' must be a number" % [path, must])
			ok = false
		elif float(stats[must]) <= 0.0:
			errors.append("%s: monster stat '%s' must be > 0" % [path, must])
			ok = false
	return ok


func _assert_stat_value(mod, path: String) -> bool:
	if not (mod is Dictionary) or String(mod.get("attribute", "")) == "":
		errors.append(path + ": stat entries need an attribute ref")
		return false
	return true


func _assert_stat_op(mod, path: String) -> bool:
	if not (mod is Dictionary):
		errors.append(path + ": mods entries must be objects")
		return false
	var ok := _has_fields(mod, path, ["attribute", "operation", "value"])
	if ok and not ["add", "multiply"].has(String(mod["operation"])):
		errors.append("%s: operation must be add|multiply" % path)
		ok = false
	return ok


func _assert_droptable_entry(entry, path: String) -> bool:
	if not (entry is Dictionary):
		errors.append(path + ": entries must be objects")
		return false
	var ok := _has_fields(entry, path, ["type", "ref", "weight"])
	if ok:
		if not ["base", "family", "droptable"].has(String(entry["type"])):
			errors.append("%s: entry type must be base|family|droptable" % path)
			ok = false
		if float(entry["weight"]) <= 0.0:
			errors.append(path + ": weight must be > 0")
			ok = false
	return ok


func _has_fields(obj: Dictionary, path: String, fields: Array) -> bool:
	var ok := true
	for field in fields:
		if not obj.has(field):
			errors.append("%s: missing field '%s'" % [path, field])
			ok = false
	return ok


## 引用存在性断言（全部对象载完后跑；悬空引用即失败）。
func _assert_refs() -> void:
	for id in monsters:
		var rec: Dictionary = monsters[id]
		var stats: Dictionary = rec["stats"]
		for attr_id in stats:
			_attr_ref(String(attr_id), "monster %s" % id)
		if rec.has("drop_table") and not droptables.has(String(rec["drop_table"])):
			errors.append("monster %s: dangling drop_table ref '%s'" % [id, String(rec["drop_table"])])
	for id in item_bases:
		for mod in item_bases[id].get("implicit_mods", []):
			_attr_ref(String(mod["attribute"]), "base %s" % id)
	for id in affixes:
		var rec: Dictionary = affixes[id]
		if String(rec.get("kind", "")) == "stat":
			for mod in rec.get("mods", []):
				_attr_ref(String(mod["attribute"]), "affix %s" % id)
		else:
			for e in rec.get("legendary", {}).get("effects", []):
				if String(e.get("type", "")) == "stat_amp":
					_attr_ref(String(e["attribute"]), "affix %s" % id)
	for id in monster_modifiers:
		for mod in monster_modifiers[id].get("mods", []):
			_attr_ref(String(mod["attribute"]), "modifier %s" % id)
	var families := {}
	for id in item_bases:
		if item_bases[id].has("family"):
			families[String(item_bases[id]["family"])] = true
	for id in droptables:
		for entry in droptables[id]["entries"]:
			var ref_id := String(entry["ref"])
			match String(entry["type"]):
				"base":
					if not item_bases.has(ref_id):
						errors.append("droptable %s: dangling base ref '%s'" % [id, ref_id])
				"droptable":
					if ref_id != id and not droptables.has(ref_id):
						errors.append("droptable %s: dangling droptable ref '%s'" % [id, ref_id])
				"family":
					if not families.has(ref_id):
						errors.append("droptable %s: dangling family ref '%s'" % [id, ref_id])
	for id in zones:
		for enc in zones[id]["encounters"]:
			if not monsters.has(String(enc["monster"])):
				errors.append("zone %s: dangling monster ref '%s'" % [id, String(enc["monster"])])
		if not monsters.has(String(zones[id]["boss"])):
			errors.append("zone %s: dangling boss ref '%s'" % [id, String(zones[id]["boss"])])
	for id in sets:
		for m in sets[id]["members"]:
			if not item_bases.has(String(m)):
				errors.append("set %s: dangling member ref '%s'" % [id, String(m)])


func _attr_ref(attr_id: String, where: String) -> void:
	if not attributes.has(attr_id):
		errors.append("%s: dangling attribute ref '%s'" % [where, attr_id])
