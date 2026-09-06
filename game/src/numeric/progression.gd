class_name Progression
extends RefCounted
## 进度结构纯函数（progression-structure #5 §3/§4/§5/§6 + 规格 #24 C 进度契约）：
## 难度阶缩放、有效等级、经验曲线、解锁游标与挂机点的默认值推导。
## 数值层纯函数、零 IO、零引擎 API——在线、离线、编辑器三处同构复用。
## 全部数值是引擎常量（#24 常量条款）：内容只存离散基准数据（区域 level、怪物
## 基准 stats），公式与缩放一律归本层。
##
## 难度阶（§3）：第 n 阶怪物属性 = 基准 stats × 难度阶乘数^n；有效等级 = 区域
## level + n × 步长。有效等级是掉落 ilvl 与击杀经验的唯一锚（角色等级不参与，§6）。
## 「属性随阶缩放」取字面口径：stats 里全部属性统一 × 难度阶乘数^n（含
## attack_speed / crit_chance），v1 裁量记录在门面 #34 头注。loot-rarity §6 的
## tier_offset_factor
## （稀有度偏移钩子）v1 = 1.0 不生效，本层不落地；生效时由 LootRoller 消费。
##
## 经验（§6）：击杀经验 = 单位经验 × 怪物有效等级；升级门槛 = 基数 + 成长 ×
## (level-1)（分段线性 MVP 单段）。升级抬升玩家初始属性集由 StatAggregator 按
## 等级重建完成，本层不重复属性曲线。经验与解锁只在遭遇边界产生（save-persistence §4）。
##
## 解锁游标与挂机点（§4/§5 + save-persistence §3 状态集）：unlocked =
## {max_zone_order, zone_tiers}，idle_spot = {zone_id, tier}。两者都是持久化状态
## 字段，由门面在遭遇边界写入；走图位置（遭遇下标）是瞬态不入档——重启 = 从
## 挂机点区域的遭遇清单头开始，挂机点是唯一锚。

const TIER_STAT_MULTIPLIER := 1.15  # 难度阶属性乘数：第 n 阶 = 基准 × 乘数^n
const TIER_LEVEL_STEP := 10  # 难度阶有效等级步长（与 LootRoller 材质阶步长同刻度）
const EXP_PER_KILL_PER_EFF_LEVEL := 10.0  # 击杀经验 = 此值 × 有效等级
const EXP_TO_NEXT_BASE := 100.0  # 升级门槛基数（level -> level+1 所需经验）
const EXP_TO_NEXT_GROWTH := 40.0  # 门槛线性成长（每级 +40）


## 第 tier 阶的有效等级 = 区域基准等级 + tier × 步长（progression-structure §3）。
static func effective_level(zone_level: int, tier: int) -> int:
	return zone_level + tier * TIER_LEVEL_STEP


## 怪物基准 stats 的第 tier 阶缩放：全部属性 × 难度阶乘数^tier，返回全新字典——
## 绝不改写内容库里的基准记录（ContentDB 对象是共享只读数据）。
static func scale_stats(stats: Dictionary, tier: int) -> Dictionary:
	var factor := pow(TIER_STAT_MULTIPLIER, float(tier))
	var out := {}
	for attr_id in stats:
		out[String(attr_id)] = float(stats[attr_id]) * factor
	return out


## 一只怪（有效等级 effective_lvl）被击杀产出的经验（∝ 有效等级，§6）。
static func exp_for_kill(effective_lvl: int) -> int:
	return int(EXP_PER_KILL_PER_EFF_LEVEL * float(effective_lvl))


## 从 level 升到 level + 1 所需经验（分段线性 MVP 单段）。
static func exp_to_next(level: int) -> int:
	return int(EXP_TO_NEXT_BASE + EXP_TO_NEXT_GROWTH * float(level - 1))


## 把 kill_count 只击杀的经验入账（可连升多级，余量留在 exp）。state 就地更新
## ——调用方传入的是 new_state 深拷贝，输入状态永不改写由门面保证。
## exp / player_level 缺失按新档默认补齐（宽接收：JSON 回读数字一律 float）。
static func bank_kills(state: Dictionary, kill_count: int, effective_lvl: int) -> void:
	var exp_pool := int(state.get("exp", 0)) + kill_count * exp_for_kill(effective_lvl)
	var level := maxi(1, int(state.get("player_level", 1)))
	while exp_pool >= exp_to_next(level):
		exp_pool -= exp_to_next(level)
		level += 1
	state["exp"] = exp_pool
	state["player_level"] = level


## 解锁游标默认值（状态缺 unlocked 字段 = 新档）：最早区域可打，全部第 0 阶。
static func default_unlocked(zones: Dictionary) -> Dictionary:
	return {"max_zone_order": min_zone_order(zones), "zone_tiers": {}}


## 挂机点默认值：最早区域 + 第 0 阶（save-persistence §3：挂机点是唯一锚）。
## 空内容库返回空 spot（{}），由调用方拒绝——不静默造一个打不了的锚。
static func default_idle_spot(zones: Dictionary) -> Dictionary:
	var first_order := min_zone_order(zones)
	if first_order < 0:
		return {}
	return {"zone_id": zone_by_order(zones, first_order), "tier": 0}


## 内容库中最小的区域序号（空库返回 -1）。
static func min_zone_order(zones: Dictionary) -> int:
	var best := -1
	for id in zones:
		var order := int(zones[id]["order"])
		if best < 0 or order < best:
			best = order
	return best


## 序号 -> 区域 id（同序取 id 序最小者；schema 不强制 order 连续或唯一，确定性兜底）。
static func zone_by_order(zones: Dictionary, order: int) -> String:
	var best_id := ""
	for id in zones:
		if int(zones[id]["order"]) != order:
			continue
		if best_id == "" or String(id) < best_id:
			best_id = String(id)
	return best_id
