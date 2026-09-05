extends SceneTree
## 机器执法层：headless 全量加载检查（脚本编译 + 场景/资源加载）。
## 用法（在 game 目录下，或用 --path 指定项目）：
##   godot --headless --path . --script res://tools/validation/check_project.gd
## 退出码 0 = 全部通过；1 = 存在加载/编译失败。CI（.github/workflows/ci.yml）跑的就是它。
## 编码规范见 docs/agents/godot-standards.md。

const SCRIPT_EXTS := ["gd"]
const SCENE_EXTS := ["tscn", "scn"]
const RESOURCE_EXTS := ["tres", "res"]

var _checked := 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var queue: Array[String] = ["res://"]
	while not queue.is_empty():
		var dir_path: String = queue.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			_failures.append("无法打开目录: " + dir_path)
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir():
				# 跳过 .godot 等隐藏目录（Windows 上无隐藏属性，必须按名字排除）
				if not entry.begins_with("."):
					queue.append(dir_path.path_join(entry))
			else:
				var ext := entry.get_extension()
				if SCRIPT_EXTS.has(ext) or SCENE_EXTS.has(ext) or RESOURCE_EXTS.has(ext):
					_check_load(dir_path.path_join(entry))
			entry = dir.get_next()
		dir.list_dir_end()
	_report()


func _check_load(file_path: String) -> void:
	_checked += 1
	var res := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null:
		_failures.append("加载失败: " + file_path)
		return
	# 实测：编译失败的 GDScript load() 仍返回非 null（错误只打印到控制台），
	# 必须用 reload() 的返回码做权威判定（探针验证过）。
	var script := res as Script
	if script == null:
		return
	# 校验脚本自身正在执行，reload 会被引擎拒绝（误报）；其编译成功由
	# 引擎启动时裁决，CI 侧还有 CHECK OK 输出锚点兜底。
	if script == get_script():
		return
	if script.reload() != OK:
		_failures.append("编译失败: " + file_path)


func _report() -> void:
	if _failures.is_empty():
		print("CHECK OK: %d 个脚本/场景/资源全部编译加载通过" % _checked)
		quit(0)
		return
	for failure in _failures:
		printerr("CHECK FAIL: " + failure)
	printerr("CHECK FAIL: 共 %d 项检查，%d 项失败" % [_checked, _failures.size()])
	quit(1)
