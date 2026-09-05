extends SceneTree
## #27 headless regression: content direct-load + stat aggregation + first encounter.
## The ONLY seam under test is SessionFacade.run_encounter (spec #24 Testing Decisions);
## internal pure functions (aggregation / encounter sim / PRNG) are NOT tested directly.
## Run:
##   godot --headless --path game --script res://tools/regression/run_battle_regression.gd
## Contract (spec #24): clean user:// dir -> repeatable; ASCII-only output with anchors;
## exit code decides pass/fail; same input -> same output.
## Engine rules: docs/agents/godot-standards.md -- FileAccess.get_as_text() called with
## no args (skip_cr removed in 4.6, local mirror row); DirAccess walk proven on 4.7.2
## by tools/validation/check_project.gd; no 4.5+ APIs without a mirror/reference row.

const ANCHOR := "[MOVE-IDLE-REGRESSION]"

# Closed event payloads (combat-model #4, multi-monster-encounters #2.2).
const ON_ATTACK_KEYS: Array[String] = [
	"attacker", "crit", "element", "raw_damage", "skill", "target", "type",
]
const ON_KILL_KEYS: Array[String] = ["killer", "type", "victim"]

# Golden content values used by assertion re-derivation (from content/ files).
const GOLD_MULT := {"skill_heavy_strike": 2.0, "skill_fire_bolt": 2.2}
const CRIT_DAMAGE_BASE := 50.0  # engine base (combat-model #3)

# Golden player base stats at level 1 (engine curve snapshot the assertions rely on).
const P1 := {
	"max_hp": 100.0, "attack_power": 10.0, "attack_speed": 1.0,
	"crit_chance": 5.0, "crit_damage": 50.0, "damage_reduction": 0.0,
	"fire_damage_multiplier": 1.0, "move_speed": 60.0,
}

const REF_FIRST := {"zone_id": "zone_graveyard_path", "encounter_index": 0}
const REF_BOSS := {"zone_id": "zone_graveyard_path", "encounter_index": -1}

var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print(ANCHOR + " start")
	var content_root := _resolve_content_root()
	var tmp := ProjectSettings.globalize_path("user://regression_fixtures")
	_rmtree(tmp)

	_section("content direct-load")
	_run_content_load(content_root, tmp)
	_section("encounter win path + determinism")
	_run_encounter_win(content_root)
	_section("stat aggregation (add / multiply)")
	_run_aggregation(content_root)
	_section("damage formula floor and min 1")
	_run_min_damage(content_root)
	_section("monster damage reduction forced to 0")
	_run_monster_dr(tmp)
	_section("same-tick order: player first")
	_run_player_first(tmp)
	_section("full heal between encounters")
	_run_full_heal(tmp)
	_section("stalemate reported, never silent")
	_run_stalemate(tmp)
	_section("boss encounter ref")
	_run_boss(content_root)
	_section("session state assertions")
	_run_state_assertions(content_root)

	_rmtree(tmp)
	_report()


# ---------------------------------------------------------------- assertions

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print(ANCHOR + " PASS " + label)
		return
	_failed += 1
	_failures.append(label)
	print(ANCHOR + " FAIL " + label)


func _section(title: String) -> void:
	print(ANCHOR + " ---- " + title)


func _report() -> void:
	print(ANCHOR + " checks passed: %d failed: %d" % [_passed, _failed])
	if _failed == 0:
		print(ANCHOR + " REGRESSION PASS")
		quit(0)
		return
	for f in _failures:
		printerr(ANCHOR + " failed: " + f)
	printerr(ANCHOR + " REGRESSION FAIL")
	quit(1)


# ---------------------------------------------------------------- helpers

func _resolve_content_root() -> String:
	# Editor / source-run layout: res:// = <repo>/game, content/ sits at repo root.
	# Exported-build layout is a packaging-ticket concern; this seam stays here.
	return ProjectSettings.globalize_path("res://").path_join("../content").simplify_path()


func _rmtree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_rmtree(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_check(false, "fixture write failed: " + path)
		return
	f.store_string(JSON.stringify(data, " "))


func _mini_monster(id: String, stats: Dictionary) -> Dictionary:
	return {"id": id, "name": id, "stats": stats}


func _mini_zone(zone_monster: String, boss: String, count: int = 1) -> Dictionary:
	return {
		"id": "zone_mini", "name": "Mini", "level": 1,
		"encounters": [{"monster": zone_monster, "count": count}],
		"boss": boss, "order": 1,
	}


## Writes a full nine-type content layout under root; only attributes/monsters/zones
## are populated (empty dirs elsewhere must load fine). extra_files overrides paths.
func _write_mini_db(root: String, monsters: Array, zone_monster: String, extra_files: Dictionary) -> void:
	for rel in ["attributes", "items/base", "affixes", "monsters", "monster_modifiers",
			"droptables", "zones", "skills", "sets"]:
		DirAccess.make_dir_recursive_absolute(root.path_join(rel))
	for a in [["max_hp", "add"], ["attack_power", "add"], ["attack_speed", "add"],
			["crit_chance", "add"], ["damage_reduction", "add"]]:
		_write_json(root.path_join("attributes/%s.json" % a[0]),
				{"id": a[0], "name": a[0], "aggregation": a[1]})
	for m in monsters:
		_write_json(root.path_join("monsters/%s.json" % m["id"]), m)
	var boss: String = monsters[0]["id"] if monsters.size() > 0 else zone_monster
	_write_json(root.path_join("zones/zone_mini.json"), _mini_zone(zone_monster, boss))
	for rel in extra_files:
		_write_json(root.path_join(rel), extra_files[rel])


func _load_db(content_root: String) -> ContentDB:
	var db := ContentDB.load_from_dir(content_root)
	if not db.errors.is_empty():
		for e in db.errors:
			print(ANCHOR + "   load error: " + e)
	return db


## Re-derives one hit from golden knowledge only (independent of implementation).
func _expected_raw(atk: Dictionary, mult: float, dtype: String, crit: bool, target_dr: float) -> int:
	var dr: float = clampf(target_dr / 100.0, 0.0, 0.95)
	var critf := 1.0
	if crit:
		critf = 1.0 + float(atk.get("crit_damage", CRIT_DAMAGE_BASE)) / 100.0
	var coef := 1.0
	if dtype != "physical":
		coef = float(atk.get(dtype + "_damage_multiplier", 1.0))
	return maxi(1, floori(float(atk["attack_power"]) * mult * (1.0 - dr) * critf * coef))


## Re-derives every on_attack in the stream. Monster-side damage reduction is forced
## to 0 by design (combat-model #3), which is exactly what the dr fixture asserts.
func _verify_stream(events: Array, pstats: Dictionary, mstats: Dictionary, label: String) -> void:
	for e in events:
		if e["type"] != "on_attack":
			continue
		var atk: Dictionary = pstats if e["attacker"] == "player" else mstats
		var mult := 1.0
		if GOLD_MULT.has(e["skill"]):
			mult = float(GOLD_MULT[e["skill"]])
		var expect := _expected_raw(atk, mult, String(e["element"]), bool(e["crit"]), 0.0)
		_check(int(e["raw_damage"]) == expect,
				"%s raw=%d matches formula (crit=%s)" % [label, int(e["raw_damage"]), str(e["crit"])])


func _check_closed(e: Dictionary, keys: Array[String], kind: String) -> void:
	var got := e.keys()
	got.sort()
	var want := keys.duplicate()
	want.sort()
	_check(got == want, kind + " payload is closed")


# ---------------------------------------------------------------- sections

func _run_content_load(content_root: String, tmp: String) -> void:
	var db := _load_db(content_root)
	_check(db.errors.is_empty(), "real content/ loads with zero errors")
	_check(db.attributes.size() == 8, "8 attributes loaded")
	_check(db.item_bases.size() == 7, "7 item bases loaded")
	_check(db.affixes.size() == 12, "12 affixes loaded")
	_check(db.monsters.size() == 2, "2 monsters loaded")
	_check(db.monster_modifiers.size() == 1, "1 monster modifier loaded")
	_check(db.droptables.size() == 4, "4 droptables loaded")
	_check(db.zones.size() == 1, "1 zone loaded")
	_check(db.skills.size() == 2, "2 skills loaded")
	_check(db.sets.size() == 2, "2 sets loaded")

	var ok_stats := {"max_hp": 40.0, "attack_power": 8.0, "attack_speed": 1.0}
	var bad_root := ContentDB.load_from_dir(tmp.path_join("does_not_exist"))
	_check(bad_root.errors.size() > 0, "missing content root -> error")

	var case_dir := tmp.path_join("bad_json")
	_write_mini_db(case_dir, [_mini_monster("mob_x", ok_stats)], "mob_x", {})
	var f := FileAccess.open(case_dir.path_join("attributes/max_hp.json"), FileAccess.WRITE)
	f.store_string("{not json")
	f = null
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "corrupt json -> error")

	case_dir = tmp.path_join("missing_field")
	_write_mini_db(case_dir, [], "mob_x", {
		"monsters/mob_x.json": {"id": "mob_x", "stats": ok_stats},
		"zones/zone_mini.json": _mini_zone("mob_x", "mob_x"),
	})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "required field missing -> error")

	case_dir = tmp.path_join("no_battle_stats")
	_write_mini_db(case_dir, [], "mob_x", {
		"monsters/mob_x.json": {"id": "mob_x", "name": "X", "stats": {"attack_power": 8.0}},
		"zones/zone_mini.json": _mini_zone("mob_x", "mob_x"),
	})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "battle stat (max_hp) missing -> error")

	case_dir = tmp.path_join("dangling_monster")
	_write_mini_db(case_dir, [], "mob_ghost", {})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "dangling zone->monster ref -> error")

	case_dir = tmp.path_join("dangling_attribute")
	_write_mini_db(case_dir, [], "mob_x", {
		"monsters/mob_x.json": {"id": "mob_x", "name": "X",
				"stats": {"max_hp": 40.0, "attack_power": 8.0, "attack_speed": 1.0, "bad_attr": 1.0}},
		"zones/zone_mini.json": _mini_zone("mob_x", "mob_x"),
	})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "dangling attribute ref -> error")

	case_dir = tmp.path_join("dangling_droptable")
	_write_mini_db(case_dir, [], "mob_x", {
		"monsters/mob_x.json": {"id": "mob_x", "name": "X", "stats": ok_stats, "drop_table": "no_such_dt"},
		"zones/zone_mini.json": _mini_zone("mob_x", "mob_x"),
	})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "dangling drop_table ref -> error")

	case_dir = tmp.path_join("id_mismatch")
	_write_mini_db(case_dir, [], "mob_x", {
		"monsters/mob_y.json": {"id": "mob_x", "name": "X", "stats": ok_stats},
		"zones/zone_mini.json": _mini_zone("mob_x", "mob_x"),
	})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "id != filename -> error")

	case_dir = tmp.path_join("duplicate_id")
	_write_mini_db(case_dir, [], "mob_x", {
		"attributes/mob_x.json": {"id": "mob_x", "name": "Dup", "aggregation": "add"},
		"zones/zone_mini.json": _mini_zone("mob_x", "mob_x"),
	})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "cross-type duplicate id -> error")

	case_dir = tmp.path_join("count_range")
	_write_mini_db(case_dir, [_mini_monster("mob_x", ok_stats)], "mob_x", {
		"zones/zone_mini.json": _mini_zone("mob_x", "mob_x", 6),
	})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "encounter count out of [1,5] -> error")


func _run_encounter_win(content_root: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	var state := {"player_level": 1, "equipment": {}, "skills": ["skill_heavy_strike"]}
	var r1 := SessionFacade.run_encounter(state, db, REF_FIRST)
	var r2 := SessionFacade.run_encounter(state, db, REF_FIRST)
	_check(not r1.has("errors"), "encounter runs without errors")
	if r1.has("errors"):
		for e in r1["errors"]:
			print(ANCHOR + "   facade error: " + e)
		return
	_check(r1["result"] == "win", "first encounter of zone wins")
	_check(int(r1["duration_ticks"]) >= 0, "duration_ticks present")
	_check(JSON.stringify(r1["events"]) == JSON.stringify(r2["events"]),
			"same input -> same event stream")
	_check(int(r1["duration_ticks"]) == int(r2["duration_ticks"]),
			"same input -> same duration")
	var events: Array = r1["events"]
	var first: Dictionary = events[0]
	_check(first["attacker"] == "player" and first["skill"] == "skill_heavy_strike",
			"player acts first with slot-0 skill")
	var attack_seen := false
	var kill_seen := false
	for e in events:
		if e["type"] == "on_attack":
			attack_seen = true
			_check_closed(e, ON_ATTACK_KEYS, "on_attack")
		else:
			kill_seen = true
			_check_closed(e, ON_KILL_KEYS, "on_kill")
	_check(attack_seen and kill_seen, "stream contains on_attack and on_kill")
	var kills: Array = events.filter(func(e): return e["type"] == "on_kill")
	# Encounter 0 is {monster, count: 2} -> two monsters expanded with #n ids, one kill each.
	_check(kills.size() == 2, "one on_kill per monster (count:2 encounter)")
	if kills.size() == 2:
		_check(kills[0]["victim"] == "mob_skeleton_warrior#1" and kills[1]["victim"] == "mob_skeleton_warrior#2"
				and kills[0]["killer"] == "player" and kills[1]["killer"] == "player",
				"kill payload ids correct (first-alive order)")
	# Cadence: player attack_speed 1.0 -> one hit per 10 ticks, starting tick 0.
	var p_attacks := events.filter(func(e): return e["type"] == "on_attack" and e["attacker"] == "player")
	var expected_hits: int = floori(float(r1["duration_ticks"]) / 10.0) + 1
	_check(p_attacks.size() == expected_hits,
			"player cadence matches attack_speed-derived interval (%d hits in %d ticks)"
					% [p_attacks.size(), int(r1["duration_ticks"])])
	var mstats: Dictionary = db.monsters["mob_skeleton_warrior"]["stats"]
	_verify_stream(events, P1, mstats, "win")


func _run_aggregation(content_root: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	# add: iron long sword implicit +12 AP -> heavy hit floor(22 x 2.0) = 44 (66 on crit).
	var state_add := {
		"player_level": 1,
		"equipment": {"weapon": {"base": "base_sword_long_iron", "affixes": []}},
		"skills": ["skill_heavy_strike"],
	}
	var r := SessionFacade.run_encounter(state_add, db, REF_FIRST)
	_check(not r.has("errors"), "equipped encounter runs without errors")
	if r.has("errors"):
		return
	var first: Dictionary = r["events"][0]
	if bool(first["crit"]):
		_check(int(first["raw_damage"]) == 66, "add aggregation: crit heavy hit 66")
	else:
		_check(int(first["raw_damage"]) == 44, "add aggregation: implicit +12 AP -> heavy hit 44")

	# multiply: level 5 -> AP 18 + 12 implicit = 30. fire bolt x fdm 1.1 ->
	# floor(30 x 2.2 x 1.1) = 72 (108 on crit); with fdm at its no-source identity 1.0
	# the same hit would be 66, so 72 proves the multiplier aggregation applies.
	# basic attacks stay physical -> 30 (45 on crit), untouched by fdm.
	var state_mul := {
		"player_level": 5,
		"equipment": {"weapon": {
			"base": "base_sword_long_iron",
			"affixes": [{"affix": "affix_of_fires", "values": [{"attribute": "fire_damage_multiplier", "value": 1.1}]}],
		}},
		"skills": ["skill_fire_bolt"],
	}
	var rf := SessionFacade.run_encounter(state_mul, db, REF_FIRST)
	_check(not rf.has("errors"), "fire-bolt encounter runs without errors")
	if rf.has("errors"):
		return
	var fire_hit: Dictionary = rf["events"][0]
	_check(fire_hit["skill"] == "skill_fire_bolt" and fire_hit["element"] == "fire",
			"slot-0 fire bolt fires with fire element")
	if bool(fire_hit["crit"]):
		_check(int(fire_hit["raw_damage"]) == 108, "multiply aggregation: crit fire bolt 108")
	else:
		_check(int(fire_hit["raw_damage"]) == 72, "multiply aggregation: fdm 1.1 -> fire bolt 72 (identity would be 66)")
	var basic_hit := {}
	for e in rf["events"]:
		if e["type"] == "on_attack" and e["attacker"] == "player" and e["skill"] == "basic_attack":
			basic_hit = e
			break
	_check(not basic_hit.is_empty(), "basic attack fallback happens while fire bolt cools")
	if not basic_hit.is_empty():
		if bool(basic_hit["crit"]):
			_check(int(basic_hit["raw_damage"]) == 45, "basic attack ignores fdm: crit 45")
		else:
			_check(int(basic_hit["raw_damage"]) == 30, "basic attack ignores fdm: 30")


func _run_min_damage(content_root: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	# Affix value -25 -> AP 10 + 12 - 25 = -3 -> every hit floors to 1, never negative.
	var state := {
		"player_level": 1,
		"equipment": {"weapon": {
			"base": "base_sword_long_iron",
			"affixes": [{"affix": "affix_sharp", "values": [{"attribute": "attack_power", "value": -25.0}]}],
		}},
		"skills": [],
	}
	var r := SessionFacade.run_encounter(state, db, REF_FIRST)
	_check(not r.has("errors"), "negative-AP encounter runs without errors")
	if r.has("errors"):
		return
	_check(r["result"] == "lose", "negative-AP player loses the fight")
	for e in r["events"]:
		if e["type"] == "on_attack" and e["attacker"] == "player":
			_check(int(e["raw_damage"]) == 1, "damage floors at 1 (got %d)" % int(e["raw_damage"]))
			return
	_check(false, "player on_attack present in negative-AP stream")


func _run_monster_dr(tmp: String) -> void:
	var case_dir := tmp.path_join("monster_dr")
	_write_mini_db(case_dir, [_mini_monster("mob_dr", {
		"max_hp": 40.0, "attack_power": 8.0, "attack_speed": 1.0,
		"crit_chance": 0.0, "damage_reduction": 95.0,
	})], "mob_dr", {})
	var db := ContentDB.load_from_dir(case_dir)
	_check(db.errors.is_empty(), "monster_dr mini db loads")
	if not db.errors.is_empty():
		return
	var state := {"player_level": 1, "equipment": {}, "skills": []}
	var r := SessionFacade.run_encounter(state, db, {"zone_id": "zone_mini", "encounter_index": 0})
	_check(not r.has("errors"), "monster-dr encounter runs without errors")
	if r.has("errors"):
		return
	_check(r["result"] == "win", "monster-dr fight still wins")
	for e in r["events"]:
		if e["type"] != "on_attack" or e["attacker"] != "player":
			continue
		if bool(e["crit"]):
			_check(int(e["raw_damage"]) == 15, "monster dr ignored: crit hit 15 (got %d)" % int(e["raw_damage"]))
		else:
			_check(int(e["raw_damage"]) == 10, "monster dr ignored: hit 10, not 1 (got %d)" % int(e["raw_damage"]))
		return
	_check(false, "player on_attack present in monster-dr stream")


func _run_player_first(tmp: String) -> void:
	var case_dir := tmp.path_join("player_first")
	_write_mini_db(case_dir, [_mini_monster("mob_fastkill", {
		"max_hp": 40.0, "attack_power": 150.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_fastkill", {
		# Mini db carries its own base so the fixture does not depend on real content/.
		"items/base/base_mini_blade.json": {"id": "base_mini_blade", "name": "Mini Blade",
				"slot": "weapon", "category": "sword",
				"implicit_mods": [{"attribute": "attack_power", "value": 30.0}]},
	})
	var db := ContentDB.load_from_dir(case_dir)
	_check(db.errors.is_empty(), "player_first mini db loads")
	if not db.errors.is_empty():
		return
	# +30 AP implicit -> 40 AP basic one-shots the 40 HP monster at tick 0.
	var state := {
		"player_level": 1,
		"equipment": {"weapon": {"base": "base_mini_blade", "affixes": []}},
		"skills": [],
	}
	var r := SessionFacade.run_encounter(state, db, {"zone_id": "zone_mini", "encounter_index": 0})
	_check(not r.has("errors"), "one-shot encounter runs without errors")
	if r.has("errors"):
		return
	_check(r["result"] == "win", "one-shot fight wins")
	_check(int(r["duration_ticks"]) == 0, "one-shot ends at tick 0")
	for e in r["events"]:
		if e["type"] == "on_attack":
			_check(e["attacker"] == "player", "player moves before monsters on the same tick")
	# Only the player acts in this stream.
	var monster_hits: Array = r["events"].filter(func(e): return e["type"] == "on_attack" and e["attacker"] != "player")
	_check(monster_hits.is_empty(), "monster never swings back in one-shot fight")


func _run_full_heal(tmp: String) -> void:
	var case_dir := tmp.path_join("full_heal")
	_write_mini_db(case_dir, [_mini_monster("mob_wall", {
		"max_hp": 999999.0, "attack_power": 60.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_wall", {})
	var db := ContentDB.load_from_dir(case_dir)
	_check(db.errors.is_empty(), "full_heal mini db loads")
	if not db.errors.is_empty():
		return
	var state := {"player_level": 1, "equipment": {}, "skills": []}
	var ref := {"zone_id": "zone_mini", "encounter_index": 0}
	var r1 := SessionFacade.run_encounter(state, db, ref)
	var r2 := SessionFacade.run_encounter(state, db, ref)
	_check(r1.get("result") == "lose", "wall fight loses")
	_check(r1.get("result") == r2.get("result")
			and int(r1.get("duration_ticks", -2)) == int(r2.get("duration_ticks", -1))
			and JSON.stringify(r1.get("events", [])) == JSON.stringify(r2.get("events", [])),
			"second encounter identical to first -> player heals back to full between fights")


func _run_stalemate(tmp: String) -> void:
	var case_dir := tmp.path_join("stalemate")
	_write_mini_db(case_dir, [_mini_monster("mob_immortal", {
		"max_hp": 20000000.0, "attack_power": 1.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_immortal", {})
	var db := ContentDB.load_from_dir(case_dir)
	_check(db.errors.is_empty(), "stalemate mini db loads")
	if not db.errors.is_empty():
		return
	# Level 600: hp 12080 survives 1 damage per 10 ticks over the 100k tick budget
	# (10000 incoming < 12080), while 1208 AP per 10 ticks needs ~165k ticks to chew
	# through 20,000,000 HP -> the fight cannot converge, the facade must report.
	var state := {"player_level": 600, "equipment": {}, "skills": []}
	var r := SessionFacade.run_encounter(state, db, {"zone_id": "zone_mini", "encounter_index": 0})
	_check(r.has("errors") and r["errors"].size() > 0, "unwinnable fight is reported as error")


func _run_boss(content_root: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	var state := {"player_level": 1, "equipment": {}, "skills": ["skill_heavy_strike"]}
	var r := SessionFacade.run_encounter(state, db, REF_BOSS)
	_check(not r.has("errors"), "boss encounter runs without errors")
	if r.has("errors"):
		return
	# Golden-seed outcome: the tick-0..80 hit cadence with one crit lands exactly 120
	# damage while the boss deals 7x14=98. Boss balance is NOT this ticket's target
	# (stat curves belong to later tickets); the assertion locks determinism only.
	_check(r["result"] == "win", "boss ref resolves to the single boss fight (golden seed: win)")
	var kills: Array = r["events"].filter(func(e): return e["type"] == "on_kill")
	_check(kills.size() == 1, "exactly one on_kill in boss fight")
	if kills.size() == 1:
		_check(kills[0]["victim"] == "mob_bone_warden" and kills[0]["killer"] == "player",
				"player kills the boss")
	# Cadence: boss attack_speed 0.75 is exactly representable, so
	# max(1, round(10 / 0.75)) = 13 with no float ambiguity -- an independent golden
	# value, not a same-expression restatement of the engine formula (attack-speed AC).
	var interval := 13
	var boss_hits: Array = r["events"].filter(func(e): return e["type"] == "on_attack" and e["attacker"] == "mob_bone_warden")
	var expected_hits: int = floori(float(r["duration_ticks"]) / float(interval)) + 1
	_check(boss_hits.size() == expected_hits,
			"boss cadence matches attack_speed 0.75 -> interval %d (%d hits in %d ticks)"
					% [interval, boss_hits.size(), int(r["duration_ticks"])])
	_verify_stream(r["events"], P1, db.monsters["mob_bone_warden"]["stats"], "boss")


func _run_state_assertions(content_root: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	var base := {"player_level": 1, "equipment": {}, "skills": []}

	var s := base.duplicate()
	s["skills"] = ["skill_fire_bolt"]
	_check(SessionFacade.run_encounter(s, db, REF_FIRST).has("errors"),
			"locked skill (unlock_level 5 > level 1) -> error")

	s = base.duplicate()
	s["skills"] = ["no_such_skill"]
	_check(SessionFacade.run_encounter(s, db, REF_FIRST).has("errors"),
			"unknown skill id -> error")

	s = base.duplicate()
	s["equipment"] = {"armor": {"base": "base_sword_long_iron", "affixes": []}}
	_check(SessionFacade.run_encounter(s, db, REF_FIRST).has("errors"),
			"weapon base in armor slot -> error")

	s = base.duplicate()
	s["equipment"] = {"weapon": {"base": "no_such_base", "affixes": []}}
	_check(SessionFacade.run_encounter(s, db, REF_FIRST).has("errors"),
			"unknown base id -> error")

	s = base.duplicate()
	s["equipment"] = {"weapon": {"base": "base_sword_long_iron", "affixes": [{"affix": "no_such_affix", "value": 1.0}]}}
	_check(SessionFacade.run_encounter(s, db, REF_FIRST).has("errors"),
			"unknown affix id -> error")

	_check(SessionFacade.run_encounter(base, db, {"zone_id": "no_such_zone", "encounter_index": 0}).has("errors"),
			"unknown zone id -> error")

	_check(SessionFacade.run_encounter(base, db, {"zone_id": "zone_graveyard_path", "encounter_index": 3}).has("errors"),
			"encounter index out of range -> error")
