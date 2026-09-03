# 战斗结算模型（数值层）设计 v1

- 票：#7｜日期：2026-09-02｜决议输入：issue #4（内容 schema 与属性注册表）、本票两轮拍板
- 状态：设计定稿，待引擎实现（技术栈票 #6 后）

## 范围边界

- 本票管：**一场遭遇内怎么打赢**。
- 本票不管：卡关与进度策略（#5）、离线折算（#9）、掉落 roll（#8）、技能内容化（雾区）、表现层渲染（雾区）。

## 1. Tick 模型

- 固定 **100ms tick（10 tps）**。
- Combatant 状态：`hp`、聚合后的属性表、`next_attack_tick`。
- 攻击间隔：`interval_ticks = max(1, round(10 / attack_speed))`（attack_speed 单位：次/秒）。
- 每 tick：轮到谁出手谁出手（tick 制下双方独立计时），出手 = 一次攻击事件。

## 2. 属性聚合（纯函数）

- `add` 属性：全部来源求和（属性基准值归引擎的玩家初始属性集，注册表不存基准）。
- `multiply` 属性：全部来源相乘（无来源 = 1.0）。
- 来源 = 玩家初始值 + 已装备实例的词缀值（实例由配方 roll 生成，见 #4）。
- 聚合输出 `StatTable`，供公式与 UI 面板消费。

## 3. 伤害公式（乘算因子链）

> ⚠️ 本节「MVP 基础技能 2.0（引擎常量）」已被 `build-system.md` §2.4 修订：技能倍率来自当前施放技能的 `multiplier`（初始技能内容 `skill_heavy_strike`，数值 2.0 不变，身份变数据）；普攻 1.0 不变。

```
最终伤害 = floor( 攻击强度 × 技能倍率 × (1 − 减伤) × 暴击因子 × 元素系数 )，最低为 1
```

- 技能倍率：普攻 1.0；MVP 基础技能 2.0（引擎常量）。
- 减伤：`clamp(目标 damage_reduction / 100, 0, 0.95)`；**MVP 怪物侧为 0**（属性注册待用）。
- 暴击因子：每次攻击独立 roll `crit_chance`；命中 → `1 + crit_damage / 100`（基准 50），未命中 → 1。
- 元素系数：物理恒 1.0；元素伤害取对应 multiplier 属性聚合（如 `fire_damage_multiplier`，基准 1.0）。

## 4. 事件模型（proc 附着点 + 表现层钩子）

- `on_attack`：`{ attacker, target, skill, raw_damage, crit, element }`。
- `on_kill`：`{ killer, victim }`——掉落 roll（#8）的唯一入口。
- `proc_on_hit`：on_attack 时按 `chance_percent` roll → 按原语造成额外伤害（`攻击力 × damage_percent% × 元素系数`）；**v1 简化：proc 伤害不吃暴击**。
- `proc_on_kill`：目标死亡时 roll → `heal`（回复 `max_hp × amount%`）或 `explode_fire`。
- **诚实标注**：单怪轮番制下 `explode_fire` 暂无溅射对象，v1 降级为纯表现事件（视觉爆炸）；波次系统从雾区毕业后恢复伤害语义——schema 无需变更。
- 事件只带数据、零回调依赖：表现层订阅渲染，掉落层订阅 on_kill，统计层订阅全部（#9 的期望折算数据源）。

## 5. 遭遇流程

> ⚠️ 本节已被 `multi-monster-encounters.md` 取代：遭遇 = 玩家 vs 一批同屏怪（`{monster, count}`，count ≤5，boss 单挑）；「波次系统在雾区」表述失效。

- `run_encounter`：驱动 tick 直到一方 `hp <= 0`。
- 胜利（怪 hp 空）：发 on_kill，掉落层接管。
- 失败（玩家 hp 空）：返回 lose；**卡关后玩家去哪归 #5**。
- 遭遇间隔：玩家回满 HP（MVP 规则，引擎行为常量——免掉药水/食物系统）。
- 遭遇结构：单怪轮番；波次系统在雾区。

## 6. 引擎接口草案（语言无关）

> ⚠️ 本节「MVP 基础技能（引擎常量，不走内容管线）」与 `skill_config` 已被 `build-system.md` §2.4 修订：`run_encounter` 收装配技能数组（按槽位序），技能倍率来自技能内容。

```
aggregate(base_stats, affix_instances[]) -> StatTable        // 纯函数
run_encounter(player: {StatTable, hp}, monster: StatTable,
              skill_config) -> { result: win|lose,
                                 duration_ticks, events: Event[] }
```

- MVP 基础技能（引擎常量，不走内容管线）：`{ multiplier: 2.0, cooldown_ticks: 50, element: physical }`。
- 硬约束：数值层纯计算、无 IO/DOM/引擎 API 依赖——浏览器在线、Node 离线（#9）、编辑器试算（#10）三处同构复用。这是引擎调研报告 3.3 节「同构复用」判断的兑现点。

## 7. 对其他票的输入

- **#5 进度结构**：需要玩家初始属性集与等级成长曲线（max_hp / attack_power 基准值表归你）。
- **#8 掉落**：on_kill 是唯一掉落入口；单怪制下掉落频率 = 击杀频率，平衡锚点。
- **#9 离线收益**：run_encounter 可离线驱动，事件流即统计源。
- **#10 编辑器**：aggregate + run_encounter 直接复用为「装备试算面板」。
