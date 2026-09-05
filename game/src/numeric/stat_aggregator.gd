class_name StatAggregator
extends RefCounted
## 属性聚合纯函数（combat-model #2）：等级基准 + 基底固有属性 + 词缀 → StatTable。
## 算子来自属性注册表：add 求和、multiply 连乘（multiply 无来源 = 1.0 恒等）。
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
##   {"implicit": [{"attribute", "value"}...], "affixes": [{"attribute", "value"}...]}
## （实例的词缀数值已由输入状态携带——#27 不做实例 roll，生成归掉落/背包票。）
static func aggregate(stat_registry: Dictionary, level: int, equipped: Array) -> Dictionary:
	var stats := player_base_stats(level)
	for inst in equipped:
		for mod in inst.get("implicit", []):
			_apply(stats, stat_registry, String(mod["attribute"]), float(mod["value"]))
		for mod in inst.get("affixes", []):
			_apply(stats, stat_registry, String(mod["attribute"]), float(mod["value"]))
	return stats


static func _apply(stats: Dictionary, registry: Dictionary, attr_id: String, value: float) -> void:
	var rec = registry.get(attr_id)
	if rec is Dictionary and String(rec.get("aggregation", "add")) == "multiply":
		stats[attr_id] = stats.get(attr_id, 1.0) * value
	else:
		stats[attr_id] = stats.get(attr_id, 0.0) + value
