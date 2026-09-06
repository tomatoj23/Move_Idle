extends Node2D
## 仅供开发调试的战斗可视化场景（dev-only，不进正式游戏路径；正式表现层 = #36）。
## 用法：编辑器打开本场景按 F6 运行当前场景。headless 冒烟（加速打完两场并退出）：
##   godot --headless --path game res://tools/dev/battle_view.tscn
## 回放 = 逐 tick 调会话门面（budget 1 + resume 句柄续跑）——即 #34 在线循环的
## 原语用法，本场景不复制任何模拟逻辑。玩家血量读句柄 player_hp（含 proc 回血
## 的真值）；怪血由 on_attack 载荷累计（MVP 怪不回血）。drop/暴击按稀有度着色。

const ZONE_ID := "zone_graveyard_path"
const PLAYER_SKILL := "skill_heavy_strike"
const RARITY_COLORS := {
	"normal": Color(0.85, 0.85, 0.85),
	"magic": Color(0.4, 0.65, 1.0),
	"rare": Color(1.0, 0.85, 0.3),
	"legendary": Color(1.0, 0.5, 0.15),
}
const MONSTER_COLORS := [Color(0.75, 0.3, 0.3), Color(0.3, 0.75, 0.45),
		Color(0.65, 0.5, 0.8), Color(0.8, 0.65, 0.3), Color(0.4, 0.6, 0.75)]
const MAX_LOG_LINES := 6

var _db: ContentDB
var _headless := false
var _state := {}
var _ref := {}
var _resume := {}
var _shown := 0
var _running := false
var _acc := 0.0
var _player_max_hp := 1.0
var _mons_hp := {}
var _mons_nodes := {}
var _log_lines: Array[String] = []
var _last := {}

var _result_label: Label
var _player_box: ColorRect
var _player_bar: ColorRect
var _player_hp_label: Label
var _log_label: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_db = ContentDB.load_from_dir(_content_root())
	if not _db.errors.is_empty():
		for e in _db.errors:
			printerr("[BATTLE-VIEW] content error: " + String(e))
		if _headless:
			get_tree().quit(1)
		return
	if not _db.zones.has(ZONE_ID):
		printerr("[BATTLE-VIEW] zone missing: " + ZONE_ID)
		if _headless:
			get_tree().quit(1)
		return
	_build_ui()
	if _headless:
		_smoke()
	else:
		_pick(0)


func _content_root() -> String:
	# 与回归脚本同款解析：res:// = <repo>/game，content/ 在仓库根。
	return ProjectSettings.globalize_path("res://").path_join("../content").simplify_path()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.14)
	bg.position = Vector2.ZERO
	bg.size = Vector2(1280, 720)
	add_child(bg)

	var title := Label.new()
	title.text = "战斗回放（调试场景，仅供测试；正式表现层 = #36）"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_child(title)

	var zone: Dictionary = _db.zones[ZONE_ID]
	var x := 24.0
	for i in (zone["encounters"] as Array).size():
		x = _add_encounter_button("遭遇 %d" % (i + 1), x, i)
	x = _add_encounter_button("首领", x, -1)

	_player_box = ColorRect.new()
	_player_box.color = Color(0.3, 0.5, 0.9)
	_player_box.position = Vector2(90, 330)
	_player_box.size = Vector2(110, 150)
	add_child(_player_box)
	var pname := Label.new()
	pname.text = "玩家 Lv1"
	pname.position = Vector2(90, 298)
	pname.add_theme_font_size_override("font_size", 18)
	add_child(pname)
	_player_bar = ColorRect.new()
	_player_bar.color = Color(0.25, 0.8, 0.35)
	_player_bar.position = Vector2(90, 490)
	_player_bar.size = Vector2(110, 14)
	add_child(_player_bar)
	_player_hp_label = Label.new()
	_player_hp_label.position = Vector2(90, 508)
	_player_hp_label.add_theme_font_size_override("font_size", 14)
	add_child(_player_hp_label)

	_log_label = Label.new()
	_log_label.position = Vector2(24, 560)
	_log_label.add_theme_font_size_override("font_size", 15)
	_log_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	add_child(_log_label)

	_result_label = Label.new()
	_result_label.position = Vector2(430, 200)
	_result_label.add_theme_font_size_override("font_size", 40)
	add_child(_result_label)


func _add_encounter_button(text: String, x: float, idx: int) -> float:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, 52)
	b.size = Vector2(110, 36)
	b.pressed.connect(_pick.bind(idx))
	add_child(b)
	_buttons.append(b)
	return x + 120.0


func _pick(idx: int) -> void:
	for b in _buttons:
		b.disabled = false
	_result_label.text = ""
	_state = {"player_level": 1, "equipment": {}, "skills": [PLAYER_SKILL]}
	_ref = {"zone_id": ZONE_ID, "encounter_index": idx}
	_resume = {}
	_shown = 0
	_running = true
	_acc = 0.0
	_log_lines.clear()
	_log_label.text = ""
	_clear_monsters()
	var q := SessionFacade.query_stats(_state, _db)
	if q.has("errors"):
		_log_line("状态非法: " + str(q["errors"]))
		_running = false
		return
	_player_max_hp = float(q["stats"]["max_hp"])
	_set_player_hp(_player_max_hp)
	var zone: Dictionary = _db.zones[ZONE_ID]
	var spec: Dictionary
	if idx < 0:
		spec = {"monster": String(zone["boss"]), "count": 1}
	else:
		spec = zone["encounters"][idx]
	_spawn_monsters(String(spec["monster"]), int(spec.get("count", 1)))
	_log_line("开打：" + ("首领战" if idx < 0 else "遭遇 %d" % (idx + 1)))


func _spawn_monsters(monster_id: String, count: int) -> void:
	var rec: Dictionary = _db.monsters[monster_id]
	var max_hp := float(rec["stats"]["max_hp"])
	for i in count:
		var display_id := monster_id if count == 1 else "%s#%d" % [monster_id, i + 1]
		_mons_hp[display_id] = max_hp
		var px := 700.0 + float(i % 2) * 210.0
		var py := 150.0 + float(floori(i / 2.0)) * 140.0
		var box := ColorRect.new()
		box.color = MONSTER_COLORS[i % MONSTER_COLORS.size()]
		box.position = Vector2(px, py)
		box.size = Vector2(90, 110)
		add_child(box)
		var bar := ColorRect.new()
		bar.color = Color(0.85, 0.3, 0.3)
		bar.position = Vector2(px, py + 114)
		bar.size = Vector2(90, 10)
		add_child(bar)
		var name_label := Label.new()
		name_label.text = String(rec["name"]) if count == 1 else "%s×%d" % [String(rec["name"]), i + 1]
		name_label.position = Vector2(px, py - 26)
		name_label.add_theme_font_size_override("font_size", 14)
		add_child(name_label)
		_mons_nodes[display_id] = {"box": box, "bar": bar, "label": name_label,
				"max_hp": max_hp, "pos": Vector2(px, py)}


func _clear_monsters() -> void:
	for node in _mons_nodes.values():
		(node["box"] as ColorRect).queue_free()
		(node["bar"] as ColorRect).queue_free()
		(node["label"] as Label).queue_free()
	_mons_nodes.clear()
	_mons_hp.clear()


func _set_player_hp(hp: float) -> void:
	var ratio := clampf(hp / _player_max_hp, 0.0, 1.0)
	_player_bar.size = Vector2(110.0 * ratio, 14.0)
	_player_bar.color = Color(0.25, 0.8, 0.35) if ratio > 0.3 else Color(0.9, 0.5, 0.2)
	_player_hp_label.text = "HP %d / %d" % [int(round(maxf(hp, 0.0))), int(round(_player_max_hp))]


func _process(delta: float) -> void:
	if _headless or not _running:
		return
	_acc += delta
	var step := float(SessionFacade.TICK_MS) / 1000.0
	while _acc >= step and _running:
		_acc -= step
		_tick()


func _tick() -> void:
	var r := SessionFacade.run_encounter(_state, _db, _ref, 1, _resume)
	if r.has("errors"):
		_running = false
		for e in r["errors"]:
			_log_line("错误: " + String(e))
		return
	var events: Array = r["events"]
	for i in range(_shown, events.size()):
		_on_event(events[i])
	_shown = events.size()
	var result := String(r["result"])
	if result == "in_progress":
		_resume = r["resume"]
		_set_player_hp(float(_resume["player_hp"]))
	else:
		_running = false
		_finish(r, result)


func _on_event(e: Dictionary) -> void:
	var kind := String(e["type"])
	if kind == "on_attack":
		var raw := int(e["raw_damage"])
		var crit := bool(e["crit"])
		var target := String(e["target"])
		if target == "player":
			_floater("-%d" % raw, Vector2(100, 330),
					Color(1.0, 0.25, 0.25) if crit else Color(1.0, 0.55, 0.55),
					24 if crit else 16)
			return
		if _mons_nodes.has(target):
			_mons_hp[target] = maxf(float(_mons_hp[target]) - float(raw), 0.0)
			_update_monster_bar(target)
			var skill := String(e["skill"])
			if skill == "proc_on_hit" or skill == "explode_fire":
				_log_line("%s 触发（%d 伤害）" % [skill, raw])
			_floater(("暴击 -%d" % raw) if crit else ("-%d" % raw),
					_mons_nodes[target]["pos"] + Vector2(10, 10),
					Color(1.0, 0.85, 0.3) if crit else Color(1, 1, 1),
					22 if crit else 16)
		return
	if kind == "on_kill":
		var victim := String(e["victim"])
		if victim == "player":
			_player_box.color = Color(0.3, 0.3, 0.35)
			_log_line("玩家倒下")
			return
		if _mons_nodes.has(victim):
			_mons_hp[victim] = 0.0
			_update_monster_bar(victim)
			(_mons_nodes[victim]["box"] as ColorRect).modulate = Color(1, 1, 1, 0.25)
			_log_line("击杀 " + String(_mons_nodes[victim]["label"].text))
		return
	if kind == "drop":
		var inst: Dictionary = e["instance"]
		var rarity := String(inst["rarity"])
		var col: Color = RARITY_COLORS.get(rarity, Color.WHITE)
		_floater("掉落：%s" % String(inst["name"]), Vector2(560, 100), col, 20)
		_log_line("掉落 [%s] %s" % [rarity, String(inst["name"])])


func _update_monster_bar(id: String) -> void:
	var node: Dictionary = _mons_nodes[id]
	var ratio := clampf(float(_mons_hp[id]) / float(node["max_hp"]), 0.0, 1.0)
	(node["bar"] as ColorRect).size = Vector2(90.0 * ratio, 10.0)


func _finish(r: Dictionary, result: String) -> void:
	var ticks := int(r["duration_ticks"])
	var seconds := float(SessionFacade.duration_ms(ticks)) / 1000.0
	var drops := 0
	var drop_names: Array[String] = []
	for e in r["events"]:
		if String(e["type"]) == "drop":
			drops += 1
			drop_names.append(String(e["instance"]["name"]))
	_result_label.text = "胜利" if result == "win" else "败北"
	_result_label.add_theme_color_override("font_color",
			Color(0.3, 0.9, 0.4) if result == "win" else Color(0.9, 0.3, 0.3))
	var tail := "，".join(drop_names) if drops > 0 else ""
	_log_line("战斗结束：%s，%d tick（%.1f 秒），掉落 %d 件 %s"
			% [result, ticks, seconds, drops, tail])
	_last = {"result": result, "ticks": ticks, "events": r["events"].size(), "drops": drops}


func _log_line(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)


func _floater(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	if _headless:
		return
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", pos.y - 46.0, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


## headless 冒烟：同步打完遭遇 0 与首领（两者在回归里都是黄金胜局），打印锚点退出。
func _smoke() -> void:
	var all_ok := true
	for idx in [0, -1]:
		all_ok = _smoke_run(idx) and all_ok
	print("[BATTLE-VIEW] smoke %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)


func _smoke_run(idx: int) -> bool:
	_pick(idx)
	var guard := 0
	while _running and guard < 200000:
		_tick()
		guard += 1
	if _running:
		printerr("[BATTLE-VIEW] enc %d did not finish (guard hit)" % idx)
		return false
	print("[BATTLE-VIEW] enc %d -> %s, %s ticks, %s events, %s drops"
			% [idx, str(_last.get("result", "error")), str(_last.get("ticks", -1)),
			str(_last.get("events", -1)), str(_last.get("drops", -1))])
	return _last.has("result") and String(_last["result"]) == "win"
