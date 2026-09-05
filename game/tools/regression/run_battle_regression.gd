extends SceneTree
## #27 headless regression: content direct-load + stat aggregation + first encounter.
## #30 headless regression: multi-monster ordering + the four effect primitives
## (stat_amp / proc_on_hit / proc_on_kill heal+explode chain / convert_damage).
## #31 headless regression: skill loadout (three slots, cooldown-ready cast in slot
## order, unlock level boundary, build-axis difference, new_state passthrough).
## #32 headless regression: loot three-layer roll (drop gate -> rarity -> instance
## generation), droptable weights/nesting/family material cap, affix count bands,
## tier gates and filters, display names, set-piece rarity floor, drop event
## contract and distribution determinism.
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

# Event-stream source labels (#30): explosion kills are labeled by their source in
# on_kill.killer (the #12 §2.2 "skill carries the source" convention), which makes
# chain count / aoe target count directly assertable from the closed payload.
const KILLER_PLAYER := "player"
const KILLER_EXPLODE := "explode_fire"
const SKILL_PROC_ON_HIT := "proc_on_hit"
const SKILL_EXPLODE_FIRE := "explode_fire"

# Closed drop payload (loot-rarity #5: instance summary + the kill it came from).
const DROP_KEYS: Array[String] = ["instance", "monster", "type"]
const INSTANCE_KEYS: Array[String] = ["affixes", "base", "ilvl", "name", "rarity"]
const AFFIX_KEYS: Array[String] = ["affix", "values"]
const VALUE_KEYS: Array[String] = ["attribute", "value"]
const RARITIES: Array[String] = ["normal", "magic", "rare", "legendary"]

# Loot fixtures: 1-HP monsters die to the first basic attack, so a run is short
# and the kill count is an exact input (5 per ordinary encounter).
const LOOT_STATS := {"max_hp": 1.0, "attack_power": 1.0, "attack_speed": 1.0, "crit_chance": 0.0}
const REF_LOOT_FIRST := {"zone_id": "zone_mini", "encounter_index": 0}
const REF_LOOT_BOSS := {"zone_id": "zone_mini", "encounter_index": -1}
const DROP_RUNS := 240  # distribution sample size (240 kills per sample)
# material_tier of the droptable-family fixture bases (rolled tier is inferred from it)
const FAMILY_TIERS := {"base_dt_f1": 1, "base_dt_f2": 2, "base_dt_f3": 3}

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
	_section("multi-monster position order at the count cap")
	_run_count5_order(tmp)
	_section("effect primitive: stat_amp")
	_run_stat_amp(content_root, tmp)
	_section("effect primitive: proc_on_hit")
	_run_proc_on_hit(content_root, tmp)
	_section("effect primitive: proc_on_kill heal")
	_run_proc_heal(tmp)
	_section("effect primitive: proc_on_kill explode_fire chain")
	_run_proc_explode(tmp)
	_section("effect primitive: convert_damage")
	_run_convert(content_root)
	_section("skill slots: cast order and caps")
	_run_skill_slots(tmp)
	_section("skill build difference and state passthrough")
	_run_skill_build_diff(content_root)
	_section("drop gate: kill is the only loot entry")
	_run_drop_gate(tmp)
	_section("drop: rarity distribution and leader legendary multiplier")
	_run_drop_rarity(tmp)
	_section("drop: droptable weights, nesting, family material tier cap")
	_run_drop_droptable(tmp)
	_section("drop: affix count, tier gates, filters, legendary fixed values")
	_run_drop_affixes(tmp)
	_section("drop: display names and set-piece rarity floor")
	_run_drop_naming(tmp)
	_section("drop instance is wearable as-is (#33 seam)")
	_run_drop_wearable(tmp)
	_section("drop: event contract and determinism")
	_run_drop_determinism(tmp)

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


## Weapon base shared by #30 mini fixtures (AP bonus is the fixture's damage dial).
func _mini_blade(ap_bonus: float) -> Dictionary:
	return {"id": "base_mini_blade", "name": "Mini Blade", "slot": "weapon", "category": "sword",
			"implicit_mods": [{"attribute": "attack_power", "value": ap_bonus}]}


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
## proc_fx (optional): {"damage_percent": float} of the build's single proc_on_hit
## effect; proc events are then re-derived as floor(AP x pct% x element coef), no crit.
## Without proc_fx, proc/explosion events must not appear in the stream.
func _verify_stream(events: Array, pstats: Dictionary, mstats: Dictionary, label: String,
		proc_fx: Dictionary = {}) -> void:
	for e in events:
		if e["type"] != "on_attack":
			continue
		var atk: Dictionary = pstats if e["attacker"] == "player" else mstats
		if String(e["skill"]) == SKILL_EXPLODE_FIRE:
			_check(false, "%s explosion events belong to the dedicated cascade section" % label)
			continue
		if String(e["skill"]) == SKILL_PROC_ON_HIT:
			_check(not proc_fx.is_empty(),
					"%s proc_on_hit event appeared without proc_fx (would be silently unverified)" % label)
			if proc_fx.is_empty():
				continue
			var pct := float(proc_fx.get("damage_percent", 0.0))
			var coef := 1.0
			var pel := String(e["element"])
			if pel != "physical":
				coef = float(atk.get(pel + "_damage_multiplier", 1.0))
			var expect_p := maxi(1, floori(float(atk["attack_power"]) * pct / 100.0 * coef))
			_check(int(e["raw_damage"]) == expect_p and not bool(e["crit"]),
					"%s proc raw=%d matches floor(AP x %s%% x coef), no crit"
							% [label, int(e["raw_damage"]), str(pct)])
			continue
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

	case_dir = tmp.path_join("bad_effect_enum")
	_write_mini_db(case_dir, [_mini_monster("mob_x", ok_stats)], "mob_x", {
		"affixes/affix_bad_effect.json": {"id": "affix_bad_effect", "name": "Bad Effect",
				"kind": "legendary",
				"legendary": {"effects": [{"type": "proc_on_kill", "chance_percent": 10,
						"effect": "summon_dragon", "amount_percent": 1}]}},
	})
	_check(ContentDB.load_from_dir(case_dir).errors.size() > 0, "unknown proc_on_kill effect value -> error")


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
		"items/base/base_mini_blade.json": _mini_blade(30.0),
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

	# Unlock boundary, lower side: level 4 < unlock_level 5 -> fire bolt must refuse.
	# (The == side is covered by the level-5 fire-bolt assertions in the win path.)
	var lvl4 := {"player_level": 4, "equipment": {}, "skills": ["skill_fire_bolt"]}
	_check(SessionFacade.run_encounter(lvl4, db, REF_FIRST).has("errors"),
			"level 4 < unlock_level 5 -> fire bolt locked -> error")


# ---------------------------------------------------------------- #30 sections

## AC: 同屏怪数量由内容给定（上限 5 由 ContentDB 把关）、站位序即清单序、
## first-alive 索敌、无仇恨系统。mini fixture（弱怪 + 一击必杀）专测引擎侧
## 展开——真实内容 zone 的 count 2/3 已由 win-path 切片覆盖；count-5 的真实
## 平衡（裸装 1 级打 5 只 8 AP 骷髅必输）不是本票目标，数值曲线归后续票。
func _run_count5_order(tmp: String) -> void:
	var case_dir := tmp.path_join("count5")
	_write_mini_db(case_dir, [_mini_monster("mob_rank", {
		"max_hp": 40.0, "attack_power": 1.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_rank", {
		"items/base/base_mini_blade.json": _mini_blade(30.0),
		"zones/zone_mini.json": _mini_zone("mob_rank", "mob_rank", 5),
	})
	var mdb := ContentDB.load_from_dir(case_dir)
	_check(mdb.errors.is_empty(), "count-5 mini db loads")
	if not mdb.errors.is_empty():
		return
	var state := {"player_level": 1, "equipment": {"weapon": {"base": "base_mini_blade", "affixes": []}}, "skills": []}
	var r := SessionFacade.run_encounter(state, mdb, {"zone_id": "zone_mini", "encounter_index": 0})
	_check(not r.has("errors"), "count-5 encounter runs without errors")
	if r.has("errors"):
		return
	_check(r["result"] == "win" and int(r["duration_ticks"]) == 40,
			"five one-shot kills at the 10-tick cadence -> win at tick 40")
	var kills: Array = r["events"].filter(func(e): return e["type"] == "on_kill")
	_check(kills.size() == 5, "five on-screen monsters -> five on_kill events (one per monster)")
	if kills.size() == 5:
		var order_ok := true
		for i in 5:
			if String(kills[i]["victim"]) != "mob_rank#%d" % (i + 1):
				order_ok = false
		_check(order_ok, "kills follow position order #1..#5 (first-alive targeting)")
	var no_aggro := true
	for e in r["events"]:
		if e["type"] == "on_attack" and e["attacker"] != "player" and e["target"] != "player":
			no_aggro = false
	_check(no_aggro, "every monster attack targets the player (no aggro system)")
	var pstats_count5 := {"attack_power": 40.0, "crit_damage": 50.0}
	_verify_stream(r["events"], pstats_count5, mdb.monsters["mob_rank"]["stats"], "count5")


## AC: 属性放大进入聚合链。加算源（铁剑固有 +12）先求和，乘算源（泰坦之力 ×1.3）
## 乘在总和上：AP 22×1.3 = 28.6 -> 重斩 floor(57.2) = 57（暴击 85）。若乘算先于
## 加算会得到 10×1.3+12 = 25 -> 50，此断言区分两种次序。狂暴之心 ×1.25 攻速：
## 间隔 max(1, round(10/1.25)) = 8（1.25 为 2 的负幂，浮点精确）。
func _run_stat_amp(content_root: String, tmp: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	var state_titan := {
		"player_level": 1,
		"equipment": {"weapon": {"base": "base_sword_long_iron",
				"affixes": [{"affix": "affix_legend_titan_might"}]}},
		"skills": ["skill_heavy_strike"],
	}
	var rt := SessionFacade.run_encounter(state_titan, db, REF_FIRST)
	_check(not rt.has("errors"), "stat_amp (titan might) encounter runs without errors")
	if rt.has("errors"):
		for e in rt["errors"]:
			print(ANCHOR + "   facade error: " + e)
		return
	var first: Dictionary = rt["events"][0]
	if bool(first["crit"]):
		_check(int(first["raw_damage"]) == 85, "stat_amp: (+12 then x1.3) -> AP 28.6, crit heavy hit 85")
	else:
		_check(int(first["raw_damage"]) == 57, "stat_amp: multiply applies to the summed AP (57, not 50)")
	var pstats_amp := {"attack_power": 28.6, "crit_damage": 50.0}
	_verify_stream(rt["events"], pstats_amp, db.monsters["mob_skeleton_warrior"]["stats"], "titan")

	var state_berserk := {
		"player_level": 1,
		"equipment": {"weapon": {"base": "base_sword_long_iron",
				"affixes": [{"affix": "affix_legend_berserk_heart"}]}},
		"skills": ["skill_heavy_strike"],
	}
	var rb := SessionFacade.run_encounter(state_berserk, db, REF_FIRST)
	_check(not rb.has("errors"), "stat_amp (berserk heart) encounter runs without errors")
	if rb.has("errors"):
		return
	var b_attacks: Array = rb["events"].filter(func(e): return e["type"] == "on_attack" and e["attacker"] == "player")
	var b_expect: int = floori(float(rb["duration_ticks"]) / 8.0) + 1
	_check(b_attacks.size() == b_expect,
			"attack_speed x1.25 -> interval 8 (%d hits in %d ticks)"
					% [b_attacks.size(), int(rb["duration_ticks"])])

	# 显式 operation "add"：走注册表分派（attack_power 为 add 属性）→ 纯求和。
	# AP 10 + 30 固有 + 5 放大 = 45 -> 普攻 45（暴击 67）。
	var case_dir := tmp.path_join("stat_amp_add")
	_write_mini_db(case_dir, [_mini_monster("mob_amp_add", {
		"max_hp": 40.0, "attack_power": 1.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_amp_add", {
		"items/base/base_mini_blade.json": _mini_blade(30.0),
		"affixes/affix_amp_add.json": {"id": "affix_amp_add", "name": "Amp Add",
				"kind": "legendary",
				"legendary": {"effects": [{"type": "stat_amp", "attribute": "attack_power",
						"operation": "add", "value": 5}]}},
	})
	var adb := ContentDB.load_from_dir(case_dir)
	_check(adb.errors.is_empty(), "stat_amp add mini db loads")
	if adb.errors.is_empty():
		var state_add := {"player_level": 1, "equipment": {"weapon": {
				"base": "base_mini_blade", "affixes": [{"affix": "affix_amp_add"}]}}, "skills": []}
		var ra := SessionFacade.run_encounter(state_add, adb, {"zone_id": "zone_mini", "encounter_index": 0})
		_check(not ra.has("errors"), "stat_amp add encounter runs without errors")
		if not ra.has("errors"):
			var first_add: Dictionary = ra["events"][0]
			if bool(first_add["crit"]):
				_check(int(first_add["raw_damage"]) == 67, "stat_amp add: crit basic hit 67")
			else:
				_check(int(first_add["raw_damage"]) == 45, "stat_amp add: AP 10+30+5 -> basic hit 45")


## AC: 命中触发按概率造成额外伤害。真实词缀腐蚀之触（25%/45% 毒）：proc 伤害
## = floor(22 x 0.45 x 1.0) = 9，不吃暴击，element = 效果伤害类型，单目标。
## 另用 100% 触发 fixture 钉死「每次主击命中且目标存活恰好一条 proc」与数值 20。
func _run_proc_on_hit(content_root: String, tmp: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	var state := {
		"player_level": 1,
		"equipment": {"weapon": {"base": "base_sword_long_iron",
				"affixes": [{"affix": "affix_legend_corrode_touch"}]}},
		"skills": [],
	}
	var r := SessionFacade.run_encounter(state, db, REF_FIRST)
	_check(not r.has("errors"), "legendary affix instance (fixed values, no roll array) resolves")
	if r.has("errors"):
		for e in r["errors"]:
			print(ANCHOR + "   facade error: " + e)
		return
	var procs: Array = r["events"].filter(func(e): return e["type"] == "on_attack" and e["skill"] == SKILL_PROC_ON_HIT)
	_check(procs.size() > 0, "golden seed produced at least one proc_on_hit")
	var proc_ok := true
	for e in procs:
		if int(e["raw_damage"]) != 9 or bool(e["crit"]) or String(e["element"]) != "poison" \
				or String(e["attacker"]) != "player":
			proc_ok = false
	_check(proc_ok, "proc_on_hit: floor(22 x 45%) = 9, no crit, poison, single target")
	var pstats_proc := {"attack_power": 22.0, "crit_damage": 50.0}
	_verify_stream(r["events"], pstats_proc, db.monsters["mob_skeleton_warrior"]["stats"],
			"proc_hit", {"damage_percent": 45.0})

	var case_dir := tmp.path_join("proc_on_hit_full")
	_write_mini_db(case_dir, [_mini_monster("mob_proc_wall", {
		"max_hp": 100.0, "attack_power": 5.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_proc_wall", {
		"items/base/base_mini_blade.json": _mini_blade(30.0),
		"affixes/affix_mini_ember.json": {"id": "affix_mini_ember", "name": "Mini Ember",
				"kind": "legendary",
				"legendary": {"effects": [{"type": "proc_on_hit", "chance_percent": 100,
						"damage_type": "fire", "damage_percent": 50}]}},
		"zones/zone_mini.json": _mini_zone("mob_proc_wall", "mob_proc_wall", 2),
	})
	var mdb := ContentDB.load_from_dir(case_dir)
	_check(mdb.errors.is_empty(), "proc_on_hit 100% mini db loads")
	if not mdb.errors.is_empty():
		return
	var mstate := {"player_level": 1, "equipment": {"weapon": {
			"base": "base_mini_blade", "affixes": [{"affix": "affix_mini_ember"}]}}, "skills": []}
	var mr := SessionFacade.run_encounter(mstate, mdb, {"zone_id": "zone_mini", "encounter_index": 0})
	_check(not mr.has("errors"), "proc_on_hit 100% encounter runs without errors")
	if mr.has("errors"):
		return
	# AP 40，怪 100 血：主击 40 不杀 -> proc 20 -> 下一击才杀，两只怪各恰好吃一条 proc。
	var mprocs: Array = mr["events"].filter(func(e): return e["type"] == "on_attack" and e["skill"] == SKILL_PROC_ON_HIT)
	_check(mprocs.size() == 2, "100% proc: exactly one per survived main hit (2 procs, 0 after killing blows)")
	for e in mprocs:
		_check(int(e["raw_damage"]) == 20 and not bool(e["crit"]) and String(e["element"]) == "fire",
				"100% proc damage floor(40 x 50%) = 20, no crit, fire")
	var m_kills: Array = mr["events"].filter(func(e): return e["type"] == "on_kill")
	_check(m_kills.size() == 2, "100% proc fight still kills both monsters")


## AC: proc_on_kill heal。100% 概率回复 100% 最大生命：双怪夹击（2x15/秒），
## 无词缀玩家在第 3~4 拍必死（任何暴击序列下都输），有词缀每杀一口回满必胜
## ——结果翻转证明 heal 进入结算；数值留足余量，结论不依赖随机序列。
func _run_proc_heal(tmp: String) -> void:
	var case_dir := tmp.path_join("proc_heal")
	_write_mini_db(case_dir, [_mini_monster("mob_flanker", {
		"max_hp": 400.0, "attack_power": 15.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_flanker", {
		"items/base/base_mini_blade.json": _mini_blade(90.0),
		"affixes/affix_mini_feast.json": {"id": "affix_mini_feast", "name": "Mini Feast",
				"kind": "legendary",
				"legendary": {"effects": [{"type": "proc_on_kill", "chance_percent": 100,
						"effect": "heal_percent_of_max_hp", "amount_percent": 100}]}},
		"zones/zone_mini.json": _mini_zone("mob_flanker", "mob_flanker", 2),
	})
	var mdb := ContentDB.load_from_dir(case_dir)
	_check(mdb.errors.is_empty(), "proc_heal mini db loads")
	if not mdb.errors.is_empty():
		return
	var bare := {"player_level": 1, "equipment": {"weapon": {"base": "base_mini_blade", "affixes": []}}, "skills": []}
	var feasted := {"player_level": 1, "equipment": {"weapon": {"base": "base_mini_blade",
			"affixes": [{"affix": "affix_mini_feast"}]}}, "skills": []}
	var ref := {"zone_id": "zone_mini", "encounter_index": 0}
	var r_bare := SessionFacade.run_encounter(bare, mdb, ref)
	_check(r_bare.get("result") == "lose", "without heal proc the two-monster press kills the player")
	var r_feast := SessionFacade.run_encounter(feasted, mdb, ref)
	_check(r_feast.get("result") == "win", "100% heal on kill flips the fight to a win")
	var kills: Array = r_feast.get("events", []).filter(func(e): return e["type"] == "on_kill")
	_check(kills.size() == 2, "heal fight still kills both monsters")


## AC: proc_on_kill explode_fire + 连锁 + 事件流统计。100% 概率、100% 攻击力火焰
## 爆炸（AP 40 -> 每目标 40 = 怪满血即秒）：主杀 #1 -> 爆炸杀 #2 -> #2 的死亡
## 再 roll -> 爆炸杀 #3 -> 清场，tick 0 结束。事件流按精确序列断言；统计口径：
## 连锁次数 = killer=="explode_fire" 的 on_kill 数（2），群伤目标数 =
## skill=="explode_fire" 的 on_attack 数（2）。爆炸不吃暴击、元素恒 fire。
func _run_proc_explode(tmp: String) -> void:
	var case_dir := tmp.path_join("proc_explode")
	_write_mini_db(case_dir, [_mini_monster("mob_dry_leaf", {
		"max_hp": 40.0, "attack_power": 1.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_dry_leaf", {
		"items/base/base_mini_blade.json": _mini_blade(30.0),
		"affixes/affix_mini_wake.json": {"id": "affix_mini_wake", "name": "Mini Wake",
				"kind": "legendary",
				"legendary": {"effects": [{"type": "proc_on_kill", "chance_percent": 100,
						"effect": "explode_fire", "amount_percent": 100}]}},
		"zones/zone_mini.json": _mini_zone("mob_dry_leaf", "mob_dry_leaf", 3),
	})
	var mdb := ContentDB.load_from_dir(case_dir)
	_check(mdb.errors.is_empty(), "proc_explode mini db loads")
	if not mdb.errors.is_empty():
		return
	var state := {"player_level": 1, "equipment": {"weapon": {"base": "base_mini_blade",
			"affixes": [{"affix": "affix_mini_wake"}]}}, "skills": []}
	var r := SessionFacade.run_encounter(state, mdb, {"zone_id": "zone_mini", "encounter_index": 0})
	_check(not r.has("errors"), "proc_explode encounter runs without errors")
	if r.has("errors"):
		return
	_check(r["result"] == "win" and int(r["duration_ticks"]) == 0, "cascade clears the field at tick 0")
	var events: Array = r["events"]
	_check(events.size() == 6, "cascade stream is exactly the 6 deterministic events")
	var expected_seq: Array = [
		{"type": "on_attack", "attacker": "player", "target": "mob_dry_leaf#1", "skill": "basic_attack", "element": "physical", "killer": "", "victim": ""},
		{"type": "on_kill", "attacker": "", "skill": "", "element": "", "killer": KILLER_PLAYER, "victim": "mob_dry_leaf#1"},
		{"type": "on_attack", "attacker": "player", "target": "mob_dry_leaf#2", "skill": SKILL_EXPLODE_FIRE, "element": "fire", "killer": "", "victim": ""},
		{"type": "on_kill", "attacker": "", "skill": "", "element": "", "killer": KILLER_EXPLODE, "victim": "mob_dry_leaf#2"},
		{"type": "on_attack", "attacker": "player", "target": "mob_dry_leaf#3", "skill": SKILL_EXPLODE_FIRE, "element": "fire", "killer": "", "victim": ""},
		{"type": "on_kill", "attacker": "", "skill": "", "element": "", "killer": KILLER_EXPLODE, "victim": "mob_dry_leaf#3"},
	]
	for i in mini(events.size(), expected_seq.size()):
		var e: Dictionary = events[i]
		var w: Dictionary = expected_seq[i]
		var target_key := "target" if e.has("target") else "victim"
		var want_key := "target" if w["type"] == "on_attack" else "victim"
		_check(String(e["type"]) == String(w["type"])
				and String(e.get("attacker", "")) == String(w["attacker"])
				and String(e[target_key]) == String(w[want_key])
				and String(e.get("skill", "")) == String(w["skill"])
				and String(e.get("killer", "")) == String(w["killer"])
				and String(e.get("victim", "")) == String(w["victim"])
				and String(e.get("element", "")) == String(w["element"]),
				"cascade event %d matches the expected sequence" % i)
	for e in events:
		if e["type"] != "on_attack":
			continue
		if String(e["skill"]) == SKILL_EXPLODE_FIRE:
			_check(int(e["raw_damage"]) == 40 and not bool(e["crit"]),
					"explosion hit: AP x 100%% fire = 40, no crit")
		else:
			_check((int(e["raw_damage"]) == 40 and not bool(e["crit"]))
					or (int(e["raw_damage"]) == 60 and bool(e["crit"])),
					"cascade main hit consistent with its crit roll")
	var chain_kills: Array = events.filter(func(e): return e["type"] == "on_kill" and e["killer"] == KILLER_EXPLODE)
	var aoe_targets: Array = events.filter(func(e): return e["type"] == "on_attack" and e["skill"] == SKILL_EXPLODE_FIRE)
	_check(chain_kills.size() == 2, "event-stream stat: chain count (explosion kills) = 2")
	_check(aoe_targets.size() == 2, "event-stream stat: aoe target count (explosion hits) = 2")


## AC: 伤害类型转换进入元素系数。烈焰之心 50% 物理->火 + 之焰 fdm 1.1：
## 有效系数 = 0.5x1.0 + 0.5x1.1 = 1.05 -> 重斩 floor(44 x 1.05) = 46（暴击 69）；
## 无转换是 48/72，46 证明转换进了系数。寒霜之魂 100% 物理->冰：物理命中
## element 报 cold；火弹不受影响（from_type 份额为 0，element 恒 fire）。
func _run_convert(content_root: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	var state := {
		"player_level": 1,
		"equipment": {"weapon": {"base": "base_sword_long_iron", "affixes": [
			{"affix": "affix_legend_flame_heart"},
			{"affix": "affix_of_fires", "values": [{"attribute": "fire_damage_multiplier", "value": 1.1}]},
		]}},
		"skills": ["skill_heavy_strike"],
	}
	var r := SessionFacade.run_encounter(state, db, REF_FIRST)
	_check(not r.has("errors"), "convert (flame heart) encounter runs without errors")
	if r.has("errors"):
		return
	var first: Dictionary = r["events"][0]
	_check(String(first["skill"]) == "skill_heavy_strike", "convert build opens with heavy strike")
	if bool(first["crit"]):
		_check(int(first["raw_damage"]) == 69, "50% phys->fire convert: crit heavy hit 69 (72 unconverted)")
	else:
		_check(int(first["raw_damage"]) == 46, "50% phys->fire convert: heavy hit 46 (48 unconverted)")

	var state_cold := {
		"player_level": 5,
		"equipment": {"weapon": {"base": "base_sword_long_iron",
				"affixes": [{"affix": "affix_legend_frost_soul"}]}},
		"skills": ["skill_fire_bolt"],
	}
	var rc := SessionFacade.run_encounter(state_cold, db, REF_FIRST)
	_check(not rc.has("errors"), "convert (frost soul) encounter runs without errors")
	if rc.has("errors"):
		return
	var basic_ok := true
	var bolt_ok := true
	var basic_seen := false
	var bolt_seen := false
	for e in rc["events"]:
		if e["type"] != "on_attack" or e["attacker"] != "player":
			continue
		if e["skill"] == "basic_attack":
			basic_seen = true
			if String(e["element"]) != "cold":
				basic_ok = false
		elif e["skill"] == "skill_fire_bolt":
			bolt_seen = true
			if String(e["element"]) != "fire":
				bolt_ok = false
	_check(basic_seen and basic_ok, "100% phys->cold convert: basic attacks report element cold")
	_check(bolt_seen and bolt_ok, "fire bolts keep element fire (conversion only moves the physical share)")


# ---------------------------------------------------------------- #31 sections

## AC: 三主动槽，冷却好即放、按槽位序取，无优先级逻辑（build-system #2.2）。
## Mini fixture：crit 归零词缀（stat_amp crit_chance -5，5.0 基准归零）消除随机，
## 厚血怪墙（999999 HP / AP 1）拉长战斗让玩家出手远超 10 次，施放序列完全确定。
## 冷却 20 的 A 与冷却 70 的 B 对调槽序，前 10 次出手的技能 id 序列随之翻转——
## 「换一套装配，节奏与伤害就是不一样」（build-system §5 技能侧验收线）的最强形态。
## 同段覆盖三槽上限与重复装配的门面拒绝（状态非法绝不静默，#24 实施决策 A）。
func _run_skill_slots(tmp: String) -> void:
	var case_dir := tmp.path_join("skill_slots")
	_write_mini_db(case_dir, [_mini_monster("mob_wall", {
		"max_hp": 999999.0, "attack_power": 1.0, "attack_speed": 1.0, "crit_chance": 0.0,
	})], "mob_wall", {
		"items/base/base_mini_blade.json": _mini_blade(0.0),
		"affixes/affix_mini_steady.json": {"id": "affix_mini_steady", "name": "Mini Steady",
				"kind": "legendary",
				"legendary": {"effects": [{"type": "stat_amp", "attribute": "crit_chance",
						"operation": "add", "value": -5}]}},
		"affixes/affix_mini_ember.json": {"id": "affix_mini_ember", "name": "Mini Ember",
				"kind": "legendary",
				"legendary": {"effects": [{"type": "proc_on_hit", "chance_percent": 100,
						"damage_type": "fire", "damage_percent": 50}]}},
		"skills/skill_mini_a.json": {"id": "skill_mini_a", "name": "A", "multiplier": 3.0,
				"cooldown_ticks": 20, "damage_type": "physical", "unlock_level": 1},
		"skills/skill_mini_b.json": {"id": "skill_mini_b", "name": "B", "multiplier": 2.0,
				"cooldown_ticks": 70, "damage_type": "physical", "unlock_level": 1},
		"skills/skill_mini_c.json": {"id": "skill_mini_c", "name": "C", "multiplier": 1.5,
				"cooldown_ticks": 10, "damage_type": "physical", "unlock_level": 1},
		"skills/skill_mini_d.json": {"id": "skill_mini_d", "name": "D", "multiplier": 1.2,
				"cooldown_ticks": 15, "damage_type": "physical", "unlock_level": 1},
	})
	var mdb := ContentDB.load_from_dir(case_dir)
	_check(mdb.errors.is_empty(), "skill-slots mini db loads")
	if not mdb.errors.is_empty():
		for e in mdb.errors:
			print(ANCHOR + "   load error: " + e)
		return
	var gear := {"weapon": {"base": "base_mini_blade", "affixes": [{"affix": "affix_mini_steady"}]}}
	var ref := {"zone_id": "zone_mini", "encounter_index": 0}

	# Slot order [A, B]: A opens (cd 20), B takes over at tick 10 (slot 0 cooling),
	# basics fill the gaps. Golden sequence derived from "cooldown-ready, first in
	# slot order" with attack interval 10 and no crits; the fight runs to tick ~1000
	# (wall monster), so only the first 10 player actions are pinned.
	var hits_ab := _player_hits(mdb, {"player_level": 1, "equipment": gear,
			"skills": ["skill_mini_a", "skill_mini_b"]}, ref, "[A,B] build")
	var seq_ab := _skill_sequence(hits_ab)
	_check(seq_ab.slice(0, 10) == ["skill_mini_a", "skill_mini_b", "skill_mini_a", "basic_attack",
			"skill_mini_a", "basic_attack", "skill_mini_a", "basic_attack",
			"skill_mini_a", "skill_mini_b"],
			"slot order [A,B]: cast sequence = cooldown-ready, first in slot order")

	# Swapped slot order [B, A]: same pair, flipped cast sequence and flipped first
	# hit damage (multiplier comes from the skill being cast).
	var hits_ba := _player_hits(mdb, {"player_level": 1, "equipment": gear,
			"skills": ["skill_mini_b", "skill_mini_a"]}, ref, "[B,A] build")
	var seq_ba := _skill_sequence(hits_ba)
	_check(seq_ba.slice(0, 10) == ["skill_mini_b", "skill_mini_a", "basic_attack", "skill_mini_a",
			"basic_attack", "skill_mini_a", "basic_attack", "skill_mini_b",
			"skill_mini_a", "basic_attack"],
			"slot order [B,A]: same pair, flipped cast sequence")
	_check(seq_ab != seq_ba, "swapping slots changes the battle rhythm (build axis exists)")
	if hits_ab.size() > 0 and hits_ba.size() > 0:
		_check(int(hits_ab[0]["raw_damage"]) == 30 and int(hits_ba[0]["raw_damage"]) == 20,
				"first hit follows the cast skill multiplier (A 3.0 -> 30, B 2.0 -> 20)")

	# Slot cap: four distinct loaded skills overflow the three active slots. The
	# error must name the overflow (a stray locked-skill error must not satisfy this).
	var over := {"player_level": 1, "equipment": {}, "skills": [
			"skill_mini_a", "skill_mini_b", "skill_mini_c", "skill_mini_d"]}
	_check(_has_error(SessionFacade.run_encounter(over, mdb, ref), "overflow"),
			"four loaded skills -> over the three-slot cap -> error names the overflow")

	# Duplicate: the same skill in two slots shares one cooldown, making slot 2 a
	# silent dead slot -- the facade refuses instead of running it.
	var dup := {"player_level": 1, "equipment": {}, "skills": ["skill_mini_a", "skill_mini_a"]}
	_check(_has_error(SessionFacade.run_encounter(dup, mdb, ref), "more than one slot"),
			"same skill in two slots -> error names the duplicate")

	# Exactly three distinct skills fill the slots; slot 2 (C, cd 10) is picked up
	# in slot order once A and B are both cooling -- the third slot leaves evidence
	# in the event stream, not just a clean run.
	var three := {"player_level": 1, "equipment": gear, "skills": [
			"skill_mini_a", "skill_mini_b", "skill_mini_c"]}
	var seq_three := _skill_sequence(_player_hits(mdb, three, ref, "[A,B,C] build"))
	_check(seq_three.slice(0, 4) == ["skill_mini_a", "skill_mini_b", "skill_mini_a",
			"skill_mini_c"],
			"three slots: C (slot 2) casts in slot order while A and B cool")

	# Skill main hits still roll proc_on_hit (AC: 命中触发照常判定；来源字段区分)：
	# steady (crit 0) + ember (100% proc, 50% fire) on one weapon, slot 0 = C whose
	# cd 10 equals the attack interval, so every action is C. The wall never dies,
	# hence each main hit is followed by exactly one proc: pairs of [C, proc], proc
	# raw = floor(10 x 50% x 1.0) = 5, no crit, element fire.
	var ember_gear := {"weapon": {"base": "base_mini_blade", "affixes": [
			{"affix": "affix_mini_steady"}, {"affix": "affix_mini_ember"}]}}
	var hits_ce := _player_hits(mdb, {"player_level": 1, "equipment": ember_gear,
			"skills": ["skill_mini_c"]}, ref, "skill+proc build")
	var seq_ce := _skill_sequence(hits_ce)
	_check(seq_ce.slice(0, 10) == ["skill_mini_c", SKILL_PROC_ON_HIT, "skill_mini_c",
			SKILL_PROC_ON_HIT, "skill_mini_c", SKILL_PROC_ON_HIT, "skill_mini_c",
			SKILL_PROC_ON_HIT, "skill_mini_c", SKILL_PROC_ON_HIT],
			"skill main hits roll proc_on_hit right after; sources distinct in the stream")
	var proc_ok := true
	for i in [1, 3, 5, 7, 9]:
		if int(hits_ce[i]["raw_damage"]) != 5 or bool(hits_ce[i]["crit"]) \
				or String(hits_ce[i]["element"]) != "fire":
			proc_ok = false
	_check(proc_ok, "proc after skill hit: floor(10 x 50%) = 5, no crit, fire")


## AC: 装配差异在真实内容上可感知（build-system §5）+ new_state 进出一致（#15
## 存档票的接缝前提，#31 保证 skills 数组按槽位序不丢不变形）+ 三槽组合节奏
## （槽 0 重斩先放，槽 1 火弹在重斩冷却中接管，普攻兜底）。crit 5% 由确定性
## 种子决定——期望按 crit 双分支写，两分支集合无交集，断言与随机序列无关。
func _run_skill_build_diff(content_root: String) -> void:
	var db := _load_db(content_root)
	if not db.errors.is_empty():
		return
	var bare := {"player_level": 1, "equipment": {}, "skills": []}
	var rb := SessionFacade.run_encounter(bare, db, REF_FIRST)
	_check(not rb.has("errors"), "bare build (no skills) runs without errors")
	if rb.has("errors"):
		return
	var heavy := {"player_level": 1, "equipment": {}, "skills": ["skill_heavy_strike"]}
	var rh := SessionFacade.run_encounter(heavy, db, REF_FIRST)
	_check(not rh.has("errors"), "heavy-strike build runs without errors")
	if rh.has("errors"):
		return
	var raw_b := int(rb["events"][0]["raw_damage"])
	var raw_h := int(rh["events"][0]["raw_damage"])
	_check(raw_b == 10 or raw_b == 15, "bare first hit = basic x1.0 (10, crit 15)")
	_check(raw_h == 20 or raw_h == 30, "heavy build first hit = skill x2.0 (20, crit 30)")
	_check(JSON.stringify(rb["events"]) != JSON.stringify(rh["events"]),
			"different skill loadouts produce different event streams")

	_check(JSON.stringify(rh["new_state"]["skills"]) == JSON.stringify(heavy["skills"]),
			"new_state preserves the skill loadout verbatim (slot order intact)")

	# Three-slot combo on real content at the unlock boundary (fire bolt unlocks
	# at 5): slot 0 opens, slot 1 fires while slot 0 cools -- regardless of crits.
	var lvl5 := {"player_level": 5, "equipment": {},
			"skills": ["skill_heavy_strike", "skill_fire_bolt"]}
	var r5 := SessionFacade.run_encounter(lvl5, db, REF_FIRST)
	_check(not r5.has("errors"), "level == unlock_level 5 -> fire bolt unlocked and usable")
	if r5.has("errors"):
		return
	var seq5 := _skill_sequence(_player_hits(db, lvl5, REF_FIRST, "level-5 combo"))
	_check(seq5.size() >= 2 and seq5[0] == "skill_heavy_strike" and seq5[1] == "skill_fire_bolt",
			"slot 0 heavy strike opens, slot 1 fire bolt takes over while heavy cools")


## Runs one encounter and returns the player's on_attack events for sequence
## assertions (caller owns the error check via the label).
func _player_hits(db: ContentDB, state: Dictionary, ref: Dictionary, label: String) -> Array:
	var r := SessionFacade.run_encounter(state, db, ref)
	_check(not r.has("errors"), label + ": encounter runs without errors")
	if r.has("errors"):
		for e in r["errors"]:
			print(ANCHOR + "   facade error: " + e)
		return []
	var hits: Array = (r["events"] as Array).filter(func(e):
		return e["type"] == "on_attack" and e["attacker"] == "player")
	return hits


func _skill_sequence(hits: Array) -> Array:
	var seq: Array = []
	for h in hits:
		seq.append(String(h["skill"]))
	return seq


## True when the facade result carries an error whose text contains `needle`
## (asserts the refusal reason, not just "any error happened").
func _has_error(result: Dictionary, needle: String) -> bool:
	if not result.has("errors"):
		return false
	for e in result["errors"]:
		if String(e).contains(needle):
			return true
	return false


# ---------------------------------------------------------------- #32 sections

## AC: 击杀是唯一掉落入口；先判掉不掉（普通怪全局概率 / 首领必掉）。
func _run_drop_gate(tmp: String) -> void:
	var db := _load_db(_write_loot_db(tmp.path_join("loot_gate"), 1, {}))
	_check(db.errors.is_empty(), "loot fixture loads with zero errors")
	if not db.errors.is_empty():
		return

	var boss := _drop_sample(db, REF_LOOT_BOSS, 60)
	_check(int(boss["error_runs"]) == 0, "60 boss runs complete without facade errors")
	_check(int(boss["kills"]) == 60, "boss sample: 60 kills")
	_check(boss["drops"].size() == 60,
			"leader always drops: 60 kills -> %d drops" % boss["drops"].size())

	var normal := _drop_sample(db, REF_LOOT_FIRST, DROP_RUNS)
	_check(int(normal["error_runs"]) == 0, "ordinary runs complete without facade errors")
	_check(int(normal["kills"]) == 5 * DROP_RUNS,
			"ordinary sample: %d kills (5 per encounter)" % int(normal["kills"]))
	_check(normal["drops"].size() > 0, "ordinary monsters do drop (%d of %d kills)"
			% [normal["drops"].size(), int(normal["kills"])])
	var rate := float(normal["drops"].size()) / float(normal["kills"])
	_check(rate > 0.13 and rate < 0.27,
			"ordinary drop rate %.3f sits on the 0.20 engine constant" % rate)

	# 无掉落表 = 不掉（内容没给渠道就是不掉，绝不是「掉了但没东西」）。
	var no_dt := _load_db(_write_loot_db(tmp.path_join("loot_no_dt"), 1, {
			"monsters/mob_loot.json": {"id": "mob_loot", "name": "Loot", "stats": LOOT_STATS},
			"monsters/mob_loot_boss.json": {"id": "mob_loot_boss", "name": "Loot Boss",
					"stats": LOOT_STATS},
	}))
	var bare := _drop_sample(no_dt, REF_LOOT_FIRST, 10)
	_check(int(bare["kills"]) == 50, "no-drop-table sample: 50 kills")
	_check(bare["drops"].size() == 0, "monster without a drop_table never drops")
	_check(int(bare["error_runs"]) == 0, "a kill without a drop_table is not an error")

	# 玩家倒下的那次 on_kill 不是击杀，不产生掉落。
	var lethal := _load_db(_write_loot_db(tmp.path_join("loot_player_death"), 1, {
			"monsters/mob_loot.json": {"id": "mob_loot", "name": "Loot", "drop_table": "dt_loot",
					"stats": {"max_hp": 1.0, "attack_power": 25.0, "attack_speed": 1.0,
							"crit_chance": 0.0}},
	}))
	var r := SessionFacade.run_encounter({"player_level": 1, "equipment": {}, "skills": []},
			lethal, REF_LOOT_FIRST)
	_check(not r.has("errors"), "lethal fixture runs without errors")
	if r.has("errors"):
		return
	_check(String(r["result"]) == "lose", "lethal fixture: the player falls")
	_check(_kills_of(r["events"], true) == 1, "the player's own death is one on_kill event")
	_check(_kills_of(r["events"], false) == 1, "one monster died before the player fell")
	var pdrops := _drops_of(r["events"])
	var wrong_monster := 0
	for d in pdrops:
		if String(d["monster"]) == "player":
			wrong_monster += 1
	_check(wrong_monster == 0 and pdrops.size() <= _kills_of(r["events"], false),
			"no drop is ever attributed to the player's death (%d drops for %d monster kills)"
					% [pdrops.size(), _kills_of(r["events"], false)])

	# 真实内容冒烟：首领必掉（1 次击杀 = 1 件），普通遭遇 2 杀最多 2 件。
	var real := _load_db(_resolve_content_root())
	if real.errors.is_empty():
		var winning := {"player_level": 1, "equipment": {}, "skills": ["skill_heavy_strike"]}
		var rb := SessionFacade.run_encounter(winning, real, REF_BOSS)
		_check(not rb.has("errors"), "real content: boss encounter still runs")
		if not rb.has("errors"):
			_check(_kills_of(rb["events"], false) == 1, "real content: boss fight is one kill")
			_check(_drops_of(rb["events"]).size() == 1,
					"real content: boss kill -> exactly 1 drop")
		var rn := SessionFacade.run_encounter(winning, real, REF_FIRST)
		_check(not rn.has("errors"), "real content: first encounter still runs")
		if not rn.has("errors"):
			_check(_kills_of(rn["events"], false) == 2, "real content: 2 skeletons killed")
			_check(_drops_of(rn["events"]).size() <= 2,
					"real content: 2 kills -> at most 2 drops")


## AC: 稀有度四档按权重 roll；首领对传奇档权重施加倍率加成。
func _run_drop_rarity(tmp: String) -> void:
	var db := _load_db(_write_loot_db(tmp.path_join("loot_rarity"), 1, {}))
	if not db.errors.is_empty():
		return
	var boss := _drop_sample(db, REF_LOOT_BOSS, DROP_RUNS)
	var normal := _drop_sample(db, REF_LOOT_FIRST, DROP_RUNS)
	_check(int(boss["error_runs"]) == 0 and int(normal["error_runs"]) == 0,
			"rarity samples run clean")
	var bc := _rarity_counts(boss["drops"])
	var nc := _rarity_counts(normal["drops"])
	_check(boss["drops"].size() == DROP_RUNS, "boss sample: %d drops" % boss["drops"].size())
	_check(_all_rarities_seen(bc), "all four rarities appear on leader kills")
	# 首领权重 = 55/32/12/1(传奇 ×10) -> .505/.294/.110/.092
	_check(_share_in(bc, "normal", 0.505, 0.12),
			"leader normal share %.3f ~ .505" % _share(bc, "normal"))
	_check(_share_in(bc, "magic", 0.294, 0.12),
			"leader magic share %.3f ~ .294" % _share(bc, "magic"))
	_check(_share_in(bc, "legendary", 0.092, 0.07),
			"leader legendary share %.3f ~ .092 (legendary weight x10)" % _share(bc, "legendary"))
	_check(int(bc["normal"]) > int(bc["magic"]) and int(bc["magic"]) > int(bc["rare"]),
			"leader rarity weights order normal > magic > rare")
	# 普通怪权重 = 55/32/12/1 -> .55/.32/.12/.01
	_check(normal["drops"].size() > 60,
			"ordinary sample collects enough drops (%d)" % normal["drops"].size())
	_check(_share_in(nc, "normal", 0.55, 0.12),
			"ordinary normal share %.3f ~ .55" % _share(nc, "normal"))
	_check(_share_in(nc, "magic", 0.32, 0.12),
			"ordinary magic share %.3f ~ .32" % _share(nc, "magic"))
	_check(int(nc["normal"]) > int(nc["magic"]) and int(nc["magic"]) > int(nc["rare"]),
			"ordinary rarity weights order normal > magic > rare")
	_check(int(nc["rare"]) > 0, "ordinary kills can roll rare (%d)" % int(nc["rare"]))
	_check(_share(bc, "legendary") > _share(nc, "legendary"),
			"leader legendary share %.3f > ordinary %.3f (leader multiplier)"
					% [_share(bc, "legendary"), _share(nc, "legendary")])
	_check(int(nc["legendary"]) <= 8, "ordinary legendary stays rare (%d of %d drops)"
			% [int(nc["legendary"]), normal["drops"].size()])


## AC: 掉落表权重 roll、嵌套子表、直接指定基底、按家族 roll；
## 家族材质在达标上限内均匀 roll。
func _run_drop_droptable(tmp: String) -> void:
	var files := {
			"items/base/base_dt_a.json": _base_rec("base_dt_a", "DT A", "weapon", "sword", 1, ""),
			"items/base/base_dt_b.json": _base_rec("base_dt_b", "DT B", "weapon", "sword", 1, ""),
			"items/base/base_dt_f1.json": _base_rec("base_dt_f1", "DT F1", "weapon", "sword", 1, "fam_dt"),
			"items/base/base_dt_f2.json": _base_rec("base_dt_f2", "DT F2", "weapon", "sword", 2, "fam_dt"),
			"items/base/base_dt_f3.json": _base_rec("base_dt_f3", "DT F3", "weapon", "sword", 3, "fam_dt"),
			"droptables/dt_loot.json": {"id": "dt_loot", "entries": [
					{"type": "droptable", "ref": "dt_sub", "weight": 40},
					{"type": "base", "ref": "base_dt_b", "weight": 30},
					{"type": "family", "ref": "fam_dt", "weight": 30}]},
			"droptables/dt_sub.json": {"id": "dt_sub", "entries": [
					{"type": "base", "ref": "base_dt_a", "weight": 100}]}}
	var db := _load_db(_write_loot_db(tmp.path_join("loot_dt"), 25, files))
	if not db.errors.is_empty():
		return
	var sample := _drop_sample(db, REF_LOOT_BOSS, DROP_RUNS)
	var drops: Array = sample["drops"]
	_check(int(sample["error_runs"]) == 0, "droptable sample runs clean")
	_check(drops.size() == DROP_RUNS, "droptable sample: %d drops" % drops.size())
	var by_base := _base_counts(drops)
	_check(by_base.has("base_dt_a") and by_base.has("base_dt_b"),
			"nested subtable and direct base entry both drop")
	_check(_share_in(by_base, "base_dt_a", 0.40, 0.13),
			"nested subtable share %.3f ~ .40" % _share(by_base, "base_dt_a"))
	_check(_share_in(by_base, "base_dt_b", 0.30, 0.13),
			"direct base share %.3f ~ .30" % _share(by_base, "base_dt_b"))
	_check(by_base.has("base_dt_f1") and by_base.has("base_dt_f2") and by_base.has("base_dt_f3"),
			"all three family material tiers drop at ilvl 25")
	_check(_share_in(by_base, "base_dt_f1", 0.10, 0.08)
					and _share_in(by_base, "base_dt_f2", 0.10, 0.08)
					and _share_in(by_base, "base_dt_f3", 0.10, 0.08),
			"family material tiers roll uniformly (%.3f / %.3f / %.3f ~ .10 each)"
					% [_share(by_base, "base_dt_f1"), _share(by_base, "base_dt_f2"),
							_share(by_base, "base_dt_f3")])

	# 材质达标上限：cap = 1 + (ilvl-1)/10 -> ilvl 1 只到 tier 1，ilvl 15 到 tier 2。
	var low := _drop_sample(_load_db(_write_loot_db(tmp.path_join("loot_dt_low"), 1, files)),
			REF_LOOT_BOSS, DROP_RUNS)
	var low_tiers := _family_tier_counts(low["drops"])
	_check(_dict_total(low_tiers) > 0,
			"family entry still rolls at ilvl 1 (%d drops)" % _dict_total(low_tiers))
	_check(low_tiers.size() == 1 and low_tiers.has(1),
			"ilvl 1 caps family material tier at 1 (only tier-1 members are eligible)")
	var mid := _drop_sample(_load_db(_write_loot_db(tmp.path_join("loot_dt_mid"), 15, files)),
			REF_LOOT_BOSS, DROP_RUNS)
	var mid_tiers := _family_tier_counts(mid["drops"])
	_check(mid_tiers.size() == 2 and mid_tiers.has(1) and mid_tiers.has(2),
			"ilvl 15 admits material tiers 1 and 2 only (tier 3 stays behind its cap)")


## AC: 稀有度决定词缀数量档次；档位与数值在达标范围内均匀 roll；
## 与语义过滤（槽位 / 类别 / ilvl 门槛）；同实例不重复词缀；传奇数值固定不 roll。
func _run_drop_affixes(tmp: String) -> void:
	var db := _load_db(_write_loot_db(tmp.path_join("loot_affix"), 25, {}))
	if not db.errors.is_empty():
		return
	var sample := _drop_sample(db, REF_LOOT_BOSS, DROP_RUNS)
	var drops: Array = sample["drops"]
	_check(int(sample["error_runs"]) == 0, "affix sample runs clean")
	_check(drops.size() == DROP_RUNS, "affix sample: %d drops" % drops.size())

	var band_bad := 0
	var dup_bad := 0
	var legend_bad := 0
	var value_bad := 0
	var armor_only := 0
	var axe_only := 0
	var future := 0
	for d in drops:
		var inst: Dictionary = d["instance"]
		var affixes: Array = inst["affixes"]
		var seen := {}
		var legend_count := 0
		for a in affixes:
			var aid := String(a["affix"])
			if seen.has(aid):
				dup_bad += 1
			seen[aid] = true
			var arec: Dictionary = db.affixes[aid]
			if String(arec["kind"]) == "legendary":
				legend_count += 1
				if (a["values"] as Array).size() != 0:
					legend_bad += 1
				continue
			for v in a["values"]:
				if not _value_in_eligible_tier(arec, float(v["value"]), int(inst["ilvl"])):
					value_bad += 1
			match aid:
				"affix_d_armor":
					armor_only += 1
				"affix_d_axe":
					axe_only += 1
				"affix_d_high":
					future += 1
		if not _affix_band_ok(String(inst["rarity"]), affixes.size(), legend_count):
			band_bad += 1
	_check(band_bad == 0, "affix count follows the rarity band on all %d drops" % drops.size())
	_check(dup_bad == 0, "no affix repeats inside one instance")
	_check(legend_bad == 0, "legendary affixes carry no rolled values (numbers fixed in content)")
	_check(value_bad == 0, "every rolled value sits inside an ilvl-eligible tier range")
	_check(armor_only == 0, "slot filter: armor-only affix never lands on a weapon")
	_check(axe_only == 0, "category filter: axe-only affix never lands on a sword")
	_check(future == 0, "ilvl gate: an affix whose lowest tier needs ilvl 50 never lands at ilvl 25")

	var legends: Array = drops.filter(func(d): return String(d["instance"]["rarity"]) == "legendary")
	_check(legends.size() > 0, "legendary rarity appears in the sample (%d)" % legends.size())
	var exactly_one := true
	var legend_stat := {}
	for d in legends:
		var n := 0
		for a in d["instance"]["affixes"]:
			if String(db.affixes[String(a["affix"])]["kind"]) == "legendary":
				n += 1
		if n != 1:
			exactly_one = false
		legend_stat[(d["instance"]["affixes"] as Array).size() - 1] = true
	_check(exactly_one, "every legendary instance carries exactly one legendary affix")
	_check(legend_stat.has(2) and legend_stat.has(3),
			"legendary stat affix count floats across its 2~3 band")

	# 档内浮动：魔法 1~2、稀有 3~4 两侧都要出现（数量在档内均匀，不是钉在一端）
	var magic_counts := {}
	var rare_counts := {}
	for d in drops:
		var inst: Dictionary = d["instance"]
		var n := (inst["affixes"] as Array).size()
		match String(inst["rarity"]):
			"magic":
				magic_counts[n] = true
			"rare":
				rare_counts[n] = true
	_check(magic_counts.has(1) and magic_counts.has(2),
			"magic affix count floats across its 1~2 band")
	_check(rare_counts.has(3) and rare_counts.has(4),
			"rare affix count floats across its 3~4 band")

	# 词缀池小于档位需求（护甲槽只配了 2 条）：提前收尾，不报错、不重复、不溢出。
	var thin_files := _loot_affix_files(["weapon"])
	thin_files["items/base/base_thin_plate.json"] = _base_rec("base_thin_plate", "Thin Plate",
			"armor", "plate", 1, "")
	thin_files["affixes/affix_d_armor2.json"] = _with_filter(_affix_rec("affix_d_armor2",
			"Bulwark", "prefix", "max_hp", [{"ilvl": 1, "min": 1, "max": 4}]),
			{"allowed_slots": ["armor"]})
	thin_files["droptables/dt_loot.json"] = {"id": "dt_loot", "entries": [
			{"type": "base", "ref": "base_thin_plate", "weight": 100}]}
	var thin_db := _load_db(_write_loot_db(tmp.path_join("loot_thin"), 25, thin_files))
	var thin := _drop_sample(thin_db, REF_LOOT_BOSS, 60)
	_check(int(thin["error_runs"]) == 0, "an affix pool smaller than the count band is not an error")
	_check(thin["drops"].size() == 60, "thin-pool sample: %d drops" % thin["drops"].size())
	var thin_bad := 0
	var thin_capped := 0
	for d in thin["drops"]:
		var stat_n := 0
		var seen := {}
		for a in d["instance"]["affixes"]:
			var aid := String(a["affix"])
			if seen.has(aid):
				thin_bad += 1
			seen[aid] = true
			if String(thin_db.affixes[aid]["kind"]) == "stat":
				stat_n += 1
		if stat_n > 2:
			thin_bad += 1
		if String(d["instance"]["rarity"]) == "rare" and stat_n == 2:
			thin_capped += 1
	_check(thin_bad == 0, "an exhausted pool stops at its size: no repeats, no overflow")
	_check(thin_capped > 0, "rare drops stop at the 2-affix pool instead of failing (%d)" % thin_capped)

	# 档位门槛：ilvl 1 只吃 ilvl-1 档（区间上界 4），ilvl 25 高档进场（>= 10）。
	var low := _drop_sample(_load_db(_write_loot_db(tmp.path_join("loot_affix_low"), 1, {})),
			REF_LOOT_BOSS, DROP_RUNS)
	_check(_max_value(low["drops"]) <= 4.0,
			"ilvl 1 never rolls the ilvl-20 tier (max value %.2f)" % _max_value(low["drops"]))
	var high_rolls := _count_at_least(drops, 10.0)
	_check(high_rolls > 0, "ilvl 25 lets the high tier into the pool (%d high rolls)" % high_rolls)

	# 传奇数值固定不随 ilvl roll：ilvl 1 与 ilvl 25 的传奇条目逐字相同（values 恒空）
	var legend_shapes := {}
	for zone_level in [1, 25]:
		var ldb := _load_db(_write_loot_db(tmp.path_join("loot_leg_%d" % zone_level),
				zone_level, {}))
		var ls := _drop_sample(ldb, REF_LOOT_BOSS, 60)
		for d in ls["drops"]:
			if String(d["instance"]["rarity"]) != "legendary":
				continue
			for a in d["instance"]["affixes"]:
				if String(ldb.affixes[String(a["affix"])]["kind"]) != "legendary":
					continue
				legend_shapes[JSON.stringify({"affix": String(a["affix"]),
						"values": a["values"]})] = true
	_check(legend_shapes.size() == 1
					and legend_shapes.has(JSON.stringify({"affix": "affix_d_leg", "values": []})),
			"legendary values never roll with ilvl: one fixed entry shape at ilvl 1 and 25")


## AC: 显示名按稀有度规则生成；套装件稀有度低于稀有档钳到稀有档，显示名恒为基底名。
func _run_drop_naming(tmp: String) -> void:
	var db := _load_db(_write_loot_db(tmp.path_join("loot_name"), 1, {}))
	if not db.errors.is_empty():
		return
	var drops: Array = _drop_sample(db, REF_LOOT_BOSS, DROP_RUNS)["drops"]
	_check(drops.size() == DROP_RUNS, "naming sample: %d drops" % drops.size())
	var counts := _rarity_counts(drops)
	_check(int(counts["magic"]) > 0 and int(counts["rare"]) > 0,
			"naming sample covers magic (%d) and rare (%d)" % [int(counts["magic"]), int(counts["rare"])])
	# 显示名按稀有度规则从实例自身的词缀推出（loot-rarity §4）。
	var bad := {}
	for r in RARITIES:
		bad[r] = 0
	var two_sided := 0
	for d in drops:
		var inst: Dictionary = d["instance"]
		var rarity := String(inst["rarity"])
		if String(inst["name"]) != _expected_name(inst, db):
			bad[rarity] = int(bad[rarity]) + 1
		if rarity == "rare":
			var w := _name_words_of(inst, db)
			if w["prefix"] != "" and w["suffix"] != "":
				two_sided += 1
	_check(int(bad["normal"]) == 0, "normal items are named after their base alone")
	_check(int(bad["magic"]) == 0, "magic items take one affix word into the name (prefix first)")
	_check(int(bad["rare"]) == 0, "rare items take one prefix and one suffix word")
	_check(int(bad["legendary"]) == 0, "legendary items are named after their legendary affix")
	_check(two_sided > 0, "the sample exercises the two-sided rare name (%d rare drops)" % two_sided)

	# 套装件：稀有度下限稀有档 + 显示名恒为专属基底名。
	var set_files := {
			"items/base/base_set_ring.json": _base_rec("base_set_ring", "Oath Ring", "trinket", "ring", 1, ""),
			"sets/set_oath.json": {"id": "set_oath", "name": "Oath",
					"members": ["base_loot_blade", "base_set_ring"],
					"tiers": [{"pieces": 2, "effects": [{"type": "stat_amp",
							"attribute": "attack_power", "operation": "multiply", "value": 1.1}]}]}}
	var sdb := _load_db(_write_loot_db(tmp.path_join("loot_set"), 1, set_files))
	if not sdb.errors.is_empty():
		return
	var sdrops: Array = _drop_sample(sdb, REF_LOOT_BOSS, DROP_RUNS)["drops"]
	_check(sdrops.size() == DROP_RUNS, "set-piece sample: %d drops" % sdrops.size())
	var floor_bad := 0
	var name_bad := 0
	for d in sdrops:
		var inst: Dictionary = d["instance"]
		if not (String(inst["rarity"]) == "rare" or String(inst["rarity"]) == "legendary"):
			floor_bad += 1
		if String(inst["name"]) != String(sdb.item_bases[String(inst["base"])]["name"]):
			name_bad += 1
	_check(floor_bad == 0, "set pieces clamp up to rare when the rarity roll lands lower")
	_check(name_bad == 0, "set pieces keep their exclusive base name (no prefix/suffix composition)")
	# 钳档必须真的按稀有档生成（3~4 条词缀），不是只把标签改成稀有
	var set_band_bad := 0
	for d in sdrops:
		var inst: Dictionary = d["instance"]
		if String(inst["rarity"]) != "rare":
			continue
		var n := (inst["affixes"] as Array).size()
		if n < 3 or n > 4:
			set_band_bad += 1
	_check(set_band_bad == 0, "clamped set pieces are generated at the rare band (3~4 affixes)")


## #32 -> #33 接缝：掉出来的实例必须能被会话门面直接当装备消费（CONTEXT「自动拾取」：
## drop 事件发生即入背包；#33 负责入包与穿戴）。本票钉住的是实例形状本身可穿戴，
## 不让 #33 开工第一天撞上格式墙。
func _run_drop_wearable(tmp: String) -> void:
	var db := _load_db(_write_loot_db(tmp.path_join("loot_wear"), 25, {}))
	if not db.errors.is_empty():
		return
	var sample := _drop_sample(db, REF_LOOT_BOSS, 60)
	_check(int(sample["error_runs"]) == 0, "wearable seam: 60 boss runs are clean")
	var drops: Array = sample["drops"]
	_check(drops.size() == 60, "wearable seam: 60 boss kills -> 60 drops")
	if drops.is_empty():
		return
	# 挑一件带 attack_power 词缀的非传奇掉落实例——普通档 0 词缀推不出数值进聚合链，
	# 传奇档还带 stat_amp 乘算（归下面那条两阶段断言）。
	var inst: Dictionary = {}
	var ap_bonus := 0.0
	for d in drops:
		var cand: Dictionary = d["instance"]
		if String(cand["rarity"]) == "legendary":
			continue
		var bonus := 0.0
		for a in cand["affixes"]:
			for v in a["values"]:
				if String(v["attribute"]) == "attack_power":
					bonus += float(v["value"])
		if bonus > 0.0:
			inst = cand
			ap_bonus = bonus
			break
	_check(ap_bonus > 0.0,
			"the sample includes a drop carrying an attack_power affix (+%.2f)" % ap_bonus)
	if ap_bonus <= 0.0:
		return
	_check(String(db.item_bases[String(inst["base"])]["slot"]) == "weapon",
			"the dropped base belongs to the weapon slot")

	# 原样穿上掉落实例：词缀数值必须进聚合链（fixture 基底无固有属性）。
	var worn := {"player_level": 1, "equipment": {"weapon": inst}, "skills": []}
	var rw := SessionFacade.run_encounter(worn, db, REF_LOOT_BOSS)
	_check(not rw.has("errors"), "a dropped instance is wearable as-is (no reshaping)")
	if rw.has("errors"):
		for e in rw["errors"]:
			print(ANCHOR + "   facade error: " + e)
		return
	var first = null
	for e in rw["events"]:
		if String(e["type"]) == "on_attack" and String(e["attacker"]) == "player":
			first = e
			break
	_check(first != null, "wearing the drop still produces player attacks")
	if first == null:
		return
	var crit_factor := 1.0
	if bool(first["crit"]):
		crit_factor = 1.0 + CRIT_DAMAGE_BASE / 100.0
	var expect := floori((P1["attack_power"] + ap_bonus) * crit_factor)
	_check(int(first["raw_damage"]) == expect,
			"worn drop: first hit %d = floor((10 base + %.2f affix AP) x %s)"
					% [int(first["raw_damage"]), ap_bonus, str(crit_factor)])

	# 传奇实例（values 恒空、数值固定于内容）同样原样可穿；stat_amp 走乘算且
	# 两阶段先加后乘：(10 + 5 词缀) x 1.3，而不是 (10 x 1.3) + 5。
	var legend_shape := JSON.stringify({"affix": "affix_d_leg", "values": []})
	var leg_amp := 0.0
	for e in db.affixes["affix_d_leg"]["legendary"]["effects"]:
		if String(e["type"]) == "stat_amp" and String(e["attribute"]) == "attack_power":
			leg_amp = float(e["value"])
	_check(leg_amp > 0.0, "the fixture legendary carries a stat_amp on attack_power (%.2f)" % leg_amp)
	var legend_inst := {"base": "base_loot_blade", "rarity": "legendary", "ilvl": 25,
			"name": "Doombringer", "affixes": [
					{"affix": "affix_d_leg", "values": []},
					{"affix": "affix_d_suf2", "values": [
							{"attribute": "attack_power", "value": 5.0}]}]}
	var rl := SessionFacade.run_encounter({"player_level": 1,
			"equipment": {"weapon": legend_inst}, "skills": []}, db, REF_LOOT_BOSS)
	_check(not rl.has("errors"), "a legendary instance (empty values) is wearable too")
	if not rl.has("errors"):
		var lfirst = null
		for e in rl["events"]:
			if String(e["type"]) == "on_attack" and String(e["attacker"]) == "player":
				lfirst = e
				break
		_check(lfirst != null, "legendary drop: player still attacks")
		if lfirst != null:
			var lcrit := 1.0
			if bool(lfirst["crit"]):
				lcrit = 1.0 + CRIT_DAMAGE_BASE / 100.0
			var l_expect := floori((P1["attack_power"] + 5.0) * leg_amp * lcrit)
			_check(int(lfirst["raw_damage"]) == l_expect,
					"legendary drop: hit %d = floor((10 + 5 add) x %.2f stat_amp x %s), two-phase"
							% [int(lfirst["raw_damage"]), leg_amp, str(lcrit)])

	# drop 产出的传奇条目与穿戴路径期望的形状逐字一致
	var legend_entries := {}
	for d in drops:
		if String(d["instance"]["rarity"]) != "legendary":
			continue
		for a in d["instance"]["affixes"]:
			if String(db.affixes[String(a["affix"])]["kind"]) == "legendary":
				legend_entries[JSON.stringify({"affix": String(a["affix"]),
						"values": a["values"]})] = true
	_check(legend_entries.size() == 1 and legend_entries.has(legend_shape),
			"legendary entries in drops are exactly the wearable shape {affix, values: []}")

	# 槽位校验对掉落实例同样生效（#33 穿戴路径的前置执法）
	var wrong_slot := SessionFacade.run_encounter({"player_level": 1,
			"equipment": {"armor": inst}, "skills": []}, db, REF_LOOT_BOSS)
	_check(_has_error(wrong_slot, "cannot go into slot"),
			"a dropped weapon is refused by the armor slot like any other instance")


## AC: 掉落事件进入事件流；载荷封闭；固定输入下分布稳定可复现。
func _run_drop_determinism(tmp: String) -> void:
	var db := _load_db(_write_loot_db(tmp.path_join("loot_det"), 12, {}))
	if not db.errors.is_empty():
		return
	var state := {"player_level": 7, "equipment": {}, "skills": []}
	var a := SessionFacade.run_encounter(state, db, REF_LOOT_FIRST)
	var b := SessionFacade.run_encounter(state, db, REF_LOOT_FIRST)
	_check(not a.has("errors") and not b.has("errors"), "determinism pair runs without errors")
	if a.has("errors") or b.has("errors"):
		return
	_check(JSON.stringify(a["events"]) == JSON.stringify(b["events"]),
			"same input -> identical event stream including drops")
	var drops := _drops_of(a["events"])
	_check(drops.size() > 0, "determinism sample has drops to inspect (%d)" % drops.size())
	if drops.is_empty():
		return
	for d in drops:
		_check_closed(d, DROP_KEYS, "drop")
		var inst: Dictionary = d["instance"]
		_check_closed(inst, INSTANCE_KEYS, "instance")
		for af in inst["affixes"]:
			_check_closed(af, AFFIX_KEYS, "affix instance")
			for v in af["values"]:
				_check_closed(v, VALUE_KEYS, "affix value")
	# ilvl 锚 = 区域等级（难度阶偏移归进度票，本票 ilvl = zone.level）
	_check(int(drops[0]["instance"]["ilvl"]) == 12, "instance ilvl is the zone level (12)")

	# 事件序：drop 紧跟在产生它的那次 on_kill 之后（击杀是唯一入口）。
	# on_kill.victim 带站位后缀（mob_x#2），drop.monster 是怪物内容 id。
	var events: Array = a["events"]
	var order_bad := 0
	for i in events.size():
		if String(events[i]["type"]) != "drop":
			continue
		if i == 0 or String(events[i - 1]["type"]) != "on_kill":
			order_bad += 1
		elif String(events[i - 1]["victim"]).split("#")[0] != String(events[i]["monster"]):
			order_bad += 1
	_check(order_bad == 0, "every drop event directly follows the on_kill that produced it")

	# 分布可复现：两次同输入采样得到同一份稀有度分布与词缀数分布
	var s1 := _rarity_counts(_drop_sample(db, REF_LOOT_FIRST, 20)["drops"])
	var s2 := _rarity_counts(_drop_sample(db, REF_LOOT_FIRST, 20)["drops"])
	_check(JSON.stringify(s1) == JSON.stringify(s2), "rarity distribution is reproducible")
	var h1 := _affix_histogram(_drop_sample(db, REF_LOOT_FIRST, 20)["drops"])
	var h2 := _affix_histogram(_drop_sample(db, REF_LOOT_FIRST, 20)["drops"])
	_check(JSON.stringify(h1) == JSON.stringify(h2), "affix-count distribution is reproducible")
	_check(_dict_total(h1) > 0, "affix-count histogram is populated (%d buckets)" % h1.size())

	# 一次调用即一场遭遇、不共享随机状态：夹进别的遭遇后重跑，掉落逐字一致
	# （离线补算就是逐场调用同一入口，同构性由此成立）。
	var boss_run := SessionFacade.run_encounter(state, db, REF_LOOT_BOSS)
	_check(not boss_run.has("errors"), "interleaved boss run has no errors")
	var again := SessionFacade.run_encounter(state, db, REF_LOOT_FIRST)
	_check(JSON.stringify(again["events"]) == JSON.stringify(a["events"]),
			"an unrelated encounter in between does not shift the drop rolls")


# ---------------------------------------------------------------- #32 helpers

## 掉落 fixture：5 只 1 血弱怪（一击必杀）+ 1 血首领，掉落表直指单基底；
## 词缀池 3 前缀 / 2 后缀 / 1 任意 + 1 传奇 + 3 条过滤探针（护甲槽 / 斧类别 /
## ilvl 50 门槛）。files 可覆写任意文件；level = 区域等级 = ilvl 锚。
func _write_loot_db(root: String, level: int, files: Dictionary) -> String:
	_write_mini_db(root, [], "mob_loot", {})
	var all := _loot_affix_files([])
	var rest := {
			"monsters/mob_loot.json": {"id": "mob_loot", "name": "Loot", "stats": LOOT_STATS,
					"drop_table": "dt_loot"},
			"monsters/mob_loot_boss.json": {"id": "mob_loot_boss", "name": "Loot Boss",
					"stats": LOOT_STATS, "drop_table": "dt_loot"},
			"zones/zone_mini.json": {"id": "zone_mini", "name": "Loot", "level": level,
					"encounters": [{"monster": "mob_loot", "count": 5}],
					"boss": "mob_loot_boss", "order": 1},
			"items/base/base_loot_blade.json": _base_rec("base_loot_blade", "Loot Blade",
					"weapon", "sword", 1, "fam_blade"),
			"affixes/affix_d_armor.json": _with_filter(_affix_rec("affix_d_armor", "Armored",
					"prefix", "max_hp", [{"ilvl": 1, "min": 1, "max": 4}]),
					{"allowed_slots": ["armor"]}),
			"affixes/affix_d_axe.json": _with_filter(_affix_rec("affix_d_axe", "of Axes",
					"suffix", "attack_power", [{"ilvl": 1, "min": 1, "max": 2}]),
					{"allowed_categories": ["axe"]}),
			"affixes/affix_d_high.json": _affix_rec("affix_d_high", "Far Future", "prefix",
					"crit_chance", [{"ilvl": 50, "min": 30, "max": 40}]),
			"affixes/affix_d_leg.json": _legend_rec("affix_d_leg", "Doombringer"),
			"droptables/dt_loot.json": {"id": "dt_loot", "entries": [
					{"type": "base", "ref": "base_loot_blade", "weight": 100}]}}
	for rel in rest:
		all[rel] = rest[rel]
	for rel in files:
		all[rel] = files[rel]
	for rel in all:
		_write_json(root.path_join(rel), all[rel])
	return root


## 掉落 fixture 的通用词缀（无槽位 / 类别限制）。slot_filter 非空即把它们整体挪到
## 指定槽位——thin 切片用它造出「词缀池小于档位需求」的合法内容组合。
func _loot_affix_files(slot_filter: Array) -> Dictionary:
	var files := {
			"affixes/affix_d_pre1.json": _affix_rec("affix_d_pre1", "Keen", "prefix",
					"attack_power", [{"ilvl": 1, "min": 1, "max": 3},
							{"ilvl": 20, "min": 10, "max": 20}]),
			"affixes/affix_d_pre2.json": _affix_rec("affix_d_pre2", "Stout", "prefix",
					"max_hp", [{"ilvl": 1, "min": 1, "max": 4}]),
			"affixes/affix_d_pre3.json": _affix_rec("affix_d_pre3", "Lucky", "prefix",
					"crit_chance", [{"ilvl": 1, "min": 1, "max": 2}]),
			"affixes/affix_d_suf1.json": _affix_rec("affix_d_suf1", "of Vitality", "suffix",
					"max_hp", [{"ilvl": 1, "min": 1, "max": 3}]),
			"affixes/affix_d_suf2.json": _affix_rec("affix_d_suf2", "of Might", "suffix",
					"attack_power", [{"ilvl": 1, "min": 1, "max": 2}]),
			"affixes/affix_d_any1.json": _affix_rec("affix_d_any1", "of Stone", "any",
					"damage_reduction", [{"ilvl": 1, "min": 1, "max": 2}])}
	if slot_filter.is_empty():
		return files
	var filtered := {}
	for rel in files:
		filtered[rel] = _with_filter(files[rel], {"allowed_slots": slot_filter})
	return filtered


func _base_rec(id: String, name: String, slot: String, category: String, tier: int,
		family: String) -> Dictionary:
	var rec := {"id": id, "name": name, "slot": slot, "category": category,
			"material_tier": tier}
	if family != "":
		rec["family"] = family
	return rec


func _affix_rec(id: String, name: String, position: String, attribute: String,
		tiers: Array) -> Dictionary:
	return {"id": id, "name": name, "kind": "stat", "position": position,
			"mods": [{"attribute": attribute, "tiers": tiers}]}


func _legend_rec(id: String, name: String) -> Dictionary:
	return {"id": id, "name": name, "kind": "legendary",
			"legendary": {"effects": [{"type": "stat_amp", "attribute": "attack_power",
					"operation": "multiply", "value": 1.3}]}}


func _with_filter(rec: Dictionary, extra: Dictionary) -> Dictionary:
	for k in extra:
		rec[k] = extra[k]
	return rec


## 采样 N 场遭遇：等级逐场递增只为换种子（ilvl 只由区域等级决定，
## progression-structure §6：角色等级不参与 ilvl）。
func _drop_sample(db: ContentDB, ref: Dictionary, runs: int) -> Dictionary:
	var drops: Array = []
	var kills := 0
	var error_runs := 0
	for i in runs:
		var state := {"player_level": 1 + i, "equipment": {}, "skills": []}
		var r := SessionFacade.run_encounter(state, db, ref)
		if r.has("errors"):
			error_runs += 1
			for e in r["errors"]:
				print(ANCHOR + "   facade error: " + e)
			continue
		kills += _kills_of(r["events"], false)
		for e in r["events"]:
			if String(e["type"]) == "drop":
				drops.append(e)
	return {"drops": drops, "kills": kills, "error_runs": error_runs}


func _drops_of(events: Array) -> Array:
	var out: Array = events.filter(func(e): return String(e["type"]) == "drop")
	return out


## on_kill 计数：player_deaths = true 数玩家倒下，false 数怪物死亡。
func _kills_of(events: Array, player_deaths: bool) -> int:
	var n := 0
	for e in events:
		if String(e["type"]) != "on_kill":
			continue
		if (String(e["victim"]) == "player") == player_deaths:
			n += 1
	return n


func _rarity_counts(drops: Array) -> Dictionary:
	var counts := {}
	for r in RARITIES:
		counts[r] = 0
	for d in drops:
		var rarity := String(d["instance"]["rarity"])
		if counts.has(rarity):
			counts[rarity] = int(counts[rarity]) + 1
	return counts


## 稀有度 -> 词缀数直方图（AC「词缀数分布稳定可复现」）。
func _affix_histogram(drops: Array) -> Dictionary:
	var hist := {}
	for d in drops:
		var key := String(d["instance"]["rarity"]) + ":" + str((d["instance"]["affixes"] as Array).size())
		hist[key] = int(hist.get(key, 0)) + 1
	return hist


func _base_counts(drops: Array) -> Dictionary:
	var counts := {}
	for d in drops:
		var bid := String(d["instance"]["base"])
		counts[bid] = int(counts.get(bid, 0)) + 1
	return counts


## 家族掉落按材质等级计数（base -> material_tier 见 FAMILY_TIERS）。
func _family_tier_counts(drops: Array) -> Dictionary:
	var counts := {}
	for d in drops:
		var tier := int(FAMILY_TIERS.get(String(d["instance"]["base"]), 0))
		if tier == 0:
			continue
		counts[tier] = int(counts.get(tier, 0)) + 1
	return counts


func _dict_total(counts: Dictionary) -> int:
	var total := 0
	for k in counts:
		total += int(counts[k])
	return total


func _share(counts: Dictionary, key: String) -> float:
	var total := 0
	for k in counts:
		total += int(counts[k])
	if total == 0:
		return 0.0
	return float(counts.get(key, 0)) / float(total)


func _share_in(counts: Dictionary, key: String, expected: float, tol: float) -> bool:
	return absf(_share(counts, key) - expected) <= tol


func _all_rarities_seen(counts: Dictionary) -> bool:
	for r in RARITIES:
		if int(counts.get(r, 0)) == 0:
			return false
	return true


## 稀有度 -> 词缀数量档（loot-rarity §2）：普通 0 / 魔法 1~2 / 稀有 3~4 /
## 传奇 = 1 条传奇 + 2~3 条 stat。
func _affix_band_ok(rarity: String, total: int, legend: int) -> bool:
	match rarity:
		"normal":
			return total == 0 and legend == 0
		"magic":
			return total >= 1 and total <= 2 and legend == 0
		"rare":
			return total >= 3 and total <= 4 and legend == 0
		"legendary":
			return legend == 1 and (total - 1) >= 2 and (total - 1) <= 3
	return false


## 数值必须落在某条「ilvl 门槛已达标」的档位区间内。
func _value_in_eligible_tier(arec: Dictionary, value: float, ilvl: int) -> bool:
	for mod in arec["mods"]:
		for t in mod["tiers"]:
			if int(t["ilvl"]) > ilvl:
				continue
			if value >= float(t["min"]) - 0.001 and value <= float(t["max"]) + 0.001:
				return true
	return false


func _max_value(drops: Array) -> float:
	var top := 0.0
	for d in drops:
		for a in d["instance"]["affixes"]:
			for v in a["values"]:
				top = maxf(top, float(v["value"]))
	return top


func _count_at_least(drops: Array, threshold: float) -> int:
	var n := 0
	for d in drops:
		for a in d["instance"]["affixes"]:
			for v in a["values"]:
				if float(v["value"]) >= threshold:
					n += 1
	return n


## 实例自身的前后缀用词：按 roll 序各取第一条；position=any 补缺的一侧，
## 同一条词缀只占一个位置。
func _name_words_of(inst: Dictionary, db: ContentDB) -> Dictionary:
	var words := {"prefix": "", "suffix": ""}
	var any_words: Array = []
	for a in inst["affixes"]:
		var rec: Dictionary = db.affixes[String(a["affix"])]
		if String(rec["kind"]) == "legendary":
			continue
		var name := String(rec["name"])
		match String(rec.get("position", "")):
			"prefix":
				if words["prefix"] == "":
					words["prefix"] = name
			"suffix":
				if words["suffix"] == "":
					words["suffix"] = name
			_:
				any_words.append(name)
	for w in any_words:
		if words["prefix"] == "":
			words["prefix"] = w
		elif words["suffix"] == "":
			words["suffix"] = w
	return words


## 按稀有度规则从实例自身推出应有显示名（loot-rarity §4 + set-items §3 套装件）。
func _expected_name(inst: Dictionary, db: ContentDB) -> String:
	var base_id := String(inst["base"])
	var base_name := String(db.item_bases[base_id]["name"])
	if _is_set_member(base_id, db):
		return base_name
	var rarity := String(inst["rarity"])
	if rarity == "legendary":
		for a in inst["affixes"]:
			var rec: Dictionary = db.affixes[String(a["affix"])]
			if String(rec["kind"]) == "legendary":
				return String(rec["name"])
		return base_name
	var words := _name_words_of(inst, db)
	if rarity == "rare" and words["prefix"] != "" and words["suffix"] != "":
		return words["prefix"] + "的" + base_name + "之" + words["suffix"]
	if rarity != "normal" and words["prefix"] != "":
		return words["prefix"] + "的" + base_name
	if rarity != "normal" and words["suffix"] != "":
		return base_name + "之" + words["suffix"]
	return base_name


func _is_set_member(base_id: String, db: ContentDB) -> bool:
	for sid in db.sets:
		for m in db.sets[sid]["members"]:
			if String(m) == base_id:
				return true
	return false
