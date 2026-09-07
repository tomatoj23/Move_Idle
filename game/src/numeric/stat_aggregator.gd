class_name StatAggregator
extends RefCounted
## 属性聚合纯函数（combat-model #2）：等级基准 + 基底固有属性 + 词缀 + 套装阶梯
## → StatTable。
## 来源分派（common v1 stat_op / effect_primitive 语义）：
## - 无显式 operation（stat 词缀、固有属性）：按属性注册表 aggregation 字段分派
##   —— add 求和、multiply 连乘（multiply 无来源 = 1.0 恒等）。
## - 显式 operation（stat_amp 原语自带）：multiply 强制走乘算（哪怕属性本身是
##   add 型，如泰坦之力 attack_power ×1.3）；add 按注册表分派（schema：
##   「add：按属性聚合方式叠加」）。
## 两阶段结算：全部加算源先并入，乘算源统一在其后相乘——结果与来源先后次序
## 无关（武器 +12 与饰品 ×1.3 的先后不该改变结果）。
## 第四来源 = 套装阶梯（set-items #18 §4）：bonus 参数由门面按「件数达标才展开」
## 传入，形状与词缀 mod 相同（attribute/value/operation?），经同一 _collect 分派。
## 输入 / 输出全是语言内建容器，零引擎 API、零 IO——在线、离线、编辑器三处同构复用。
## 玩家等级基准曲线归引擎常量（progression-structure #6：简单分段线性；MVP 单段，
## 内容库不存基准值，注册表只登记属性）。平衡调整只动本文件常量。

const CURVE_ADD := {
	"max_hp": {"base": 100.0, "per_level": 20.0},
	"attack_power": {"base": 10.0, "per_level": 2.0},
	"attack_speed": {"base": 1.0, "per_level": 0.0},
	"crit_chance": {"base": 5.0, "per_level": 0.0},
	"crit_damage": {"base": 50.0, "per_level": 0.0},
	"damage_reduction": {"base": 0.0, "per_level": 0.0},
	"move_speed": {"base": 60.0, "per_level": 0.0},
}

const EQUIP_SLOTS := ["weapon", "armor", "trinket"]


## 玩家初始属性集（等级基准）。multiply 属性不预置——消费方按缺省 1.0 取值，
## 「无来源乘法恒等」由此成立。
static func player_base_stats(level: int) -> Dictionary:
	var stats := {}
	for attr_id in CURVE_ADD:
		var curve: Dictionary = CURVE_ADD[attr_id]
		stats[attr_id] = float(curve["base"]) + float(curve["per_level"]) * float(level - 1)
	return stats


## 聚合。stat_registry = 属性注册表（id -> 内容对象，算子查 aggregation 字段）；
## equipped = 已解引用的穿戴实例数组，每项：
##   {"implicit": [{"attribute", "value"}...],
##    "affixes": [{"attribute", "value"}... 或 {"attribute", "value", "operation"}...]}
## （实例的词缀数值已由输入状态携带——实例 roll 归掉落/背包票；"operation" 仅
## stat_amp 来源携带，语义见文件头。）
## bonus = 套装阶梯等非实例来源的 mods（形状同上，默认空 = 无第四来源）。
static func aggregate(stat_registry: Dictionary, level: int, equipped: Array,
		bonus: Array = []) -> Dictionary:
	var stats := player_base_stats(level)
	var mults: Array = []  # 乘算源 [attr_id, value]，统一在加算源之后结算
	for inst in equipped:
		for mod in inst.get("implicit", []):
			_collect(stats, stat_registry, mod, mults)
		for mod in inst.get("affixes", []):
			_collect(stats, stat_registry, mod, mults)
	for mod in bonus:
		_collect(stats, stat_registry, mod, mults)
	for m in mults:
		var attr_id := String(m[0])
		stats[attr_id] = stats.get(attr_id, 1.0) * float(m[1])
	return stats


## 单个来源分派：显式 operation（stat_amp）优先；否则按属性注册表聚合方式。
## 乘算源暂存 mults，聚合末尾统一相乘（两阶段，次序无关）。
static func _collect(stats: Dictionary, registry: Dictionary, mod, mults: Array) -> void:
	var attr_id := String(mod["attribute"])
	var value := float(mod["value"])
	var op := String(mod.get("operation", ""))
	if op != "multiply":
		var rec = registry.get(attr_id)
		op = String(rec.get("aggregation", "add")) if rec is Dictionary else "add"
	if op == "multiply":
		mults.append([attr_id, value])
	else:
		stats[attr_id] = stats.get(attr_id, 0.0) + value
