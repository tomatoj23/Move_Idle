# 掉落与稀有度系统设计 v1

- 票：#8｜日期：2026-09-02｜决议输入：issue #4（内容 schema）、issue #5（进度结构，ilvl 锚）、issue #7（战斗结算模型，事件契约）
- 状态：设计定稿；首批传奇词缀 roster 已随本票落盘 `content/affixes/legendary/`

## 范围边界

- 本票管：掉落三层判定链（掉不掉 → 稀有度 → 实例生成）、词缀抽取规则、传奇词缀占比/渠道/首批 roster、drop 事件契约。
- 本票不管：离线收益折算（#9）、掉落时刻 UI 与手感（雾区，prototype）、拾取/背包/分解、掉落加成属性与 pity（雾区）。

## 1. 三层判定链

on_kill 是唯一掉落入口（#7 既定）。击杀后依次三层 roll，全部是数值层纯函数，在线/离线同一套：

1. **掉落判定（掉不掉）**：普通怪按全局概率 p（引擎常量，初值 0.20）出装备，首领 p = 1.0（必掉）。「掉不掉」归引擎全局层，**掉落表 schema 不动**（继续只管「掉什么」）。
2. **稀有度 roll（掉多好）**：分层式——四档权重表（引擎常量）：普通 55 / 魔法 32 / 稀有 12 / 传奇 1（归一化语义归引擎）。难度阶偏移钩子预留：偏移系数 v1 = 1.0（不生效），公式归引擎。
3. **实例生成（掉什么、多强）**：见 §2。

首领专属修正：首领掉落 roll 时对传奇档权重 ×10（引擎常量）。普通怪也能出传奇（惊喜时刻），首领倍率保证目标感。

## 2. 实例生成规则

- **掉落表 roll**：entries 按 weight 归一化 roll；type=droptable 递归子表；type=base 直接指定基底；type=family 按家族 roll（下条）。
- **家族材质 roll**：ilvl 达标上限内的 material_tier 中**均匀** roll；达标上限公式归引擎，高档材质的出现率由内容供给控制（高阶区域才配高材质基底）。v1 不加衰减系数。
- **稀有度 → 词缀数量**（档内均匀浮动）：普通 0；魔法 1~2；稀有 3~4；传奇 = 1 条传奇词缀 + 2~3 条 stat 词缀。
- **词缀池过滤**（AND 语义）：声明 `allowed_slots` 则槽位必须命中；声明 `allowed_categories` 则类别必须命中；未声明即不限；档位 `ilvl` 门槛 ≤ 装备 ilvl；**同一实例不重复同词缀**。
- **档位与数值**：达标档位中均匀 roll（无高档偏置，高档随 ilvl 自然入池）；档内数值 min~max 均匀分布。`position` 仅用于命名，v1 不限前后缀数量。
- **传奇实例**：传奇词缀从达标传奇池均匀 roll；传奇数值**固定不 roll**（原语参数不随 ilvl 分档；随阶强化走未来版本）。
- **roll 终点 = 完整装备实例**（含词缀与数值）。拾取/背包/分解不在本票。
- **套装件特例**：稀有度 roll 结果低于稀有档则 clamp 到稀有；显示名恒为专属基底名，不走本票 §4 前后缀命名。规则细节见 `docs/design/set-items.md`（票 #18）。

## 3. 传奇词缀

- **渠道**：全池可出（普通怪小概率惊喜）+ 首领 ×10 倍率；占比曲线由 §1 权重表与倍率承载，本票不设其他特例。
- **风格**：混合偏 proc；覆盖全部四原语（stat_amp / proc_on_hit / proc_on_kill / convert_damage）。
- **首批 roster（10 条）**：

| id | 名称 | 原语组合 | 槽位 | 备注 |
|---|---|---|---|---|
| affix_legend_ember_wake | 余烬觉醒 | proc_on_kill：explode_fire 20%/60% | 武器 | 既有示例；v1 表现事件（#7 结论） |
| affix_legend_blood_feast | 血之盛宴 | proc_on_kill：heal_percent_of_max_hp 30%/5% | 任意 | 生存型 |
| affix_legend_corrode_touch | 腐蚀之触 | proc_on_hit：poison 25%/45% | 武器 | |
| affix_legend_thunder_pierce | 雷霆贯击 | proc_on_hit：lightning 20%/85% | 武器 | 单发高伤（单怪制无第二目标） |
| affix_legend_frost_bite | 霜咬 | proc_on_hit：cold 30%/40% | 武器 | |
| affix_legend_frost_soul | 寒霜之魂 | convert_damage：物理→冰霜 100% | 任意 | 全转 build 灵魂件 |
| affix_legend_flame_heart | 烈焰之心 | convert_damage：物理→火焰 50% | 任意 | |
| affix_legend_berserk_heart | 狂暴之心 | stat_amp：attack_speed ×1.25 | 任意 | |
| affix_legend_titan_might | 泰坦之力 | stat_amp：attack_power ×1.30 | 任意 | 玻璃大炮向 |
| affix_legend_dead_whisper | 亡者低语 | proc_on_kill：heal 15%/3% + stat_amp：attack_speed ×1.10 | 饰品 | 组合原语示例 |

- explode_fire 沿 #7 结论：单怪制下 v1 为表现层演出（数值层零伤害），真实伤害语义随 #12 波次系统恢复；schema 不变。

## 4. 命名规则（归引擎）

- 传奇：显示名 = 传奇词缀 `name`。
- 魔法：`<前缀词>的<基底名>` 或 `<基底名>之<后缀词>`（按 roll 到词缀的 position）。
- 稀有：`<前缀词>的<基底名>之<后缀词>`（前后缀各取其一）。

## 5. drop 事件契约

- **数值层**：on_kill 后追加独立 **drop 事件**，载荷 = 装备实例摘要（id、显示名、稀有度、ilvl）+ 来源遭遇引用；on_kill 本身保持零回调不变。
- **表现层**：稀有度映射演出强度阶梯——普通不演出 → 魔法飘字 → 稀有横幅 → 传奇全屏高光；具体演出形式归雾区「掉落时刻的 UI 与手感」。
- **离线**：drop 事件照常进入事件流（在线/离线同规则），回归时汇总补发；收益折算规则归 #9。

## 6. 引擎常量表（掉率 tuning，不进内容库）

- `drop_chance_normal = 0.20`（普通怪掉装备概率）
- `rarity_weights = { normal: 55, magic: 32, rare: 12, legendary: 1 }`
- `leader_legendary_multiplier = 10`（首领传奇权重倍率）
- `tier_offset_factor = 1.0`（难度阶稀有度偏移钩子，v1 不生效）

全部为引擎常量，名字供规格参考；调参不改结构、不进内容数据。

## 7. v1 排除（进雾区或票外）

- 掉落加成属性（magic_find/稀有度加成）不入属性注册表 → 雾区。
- 怪物修饰符不附带掉落加成（精英变体只强化战斗，遭遇构成本身归 #12 侧）。
- 不做 pity 保底 → 雾区。
- 拾取/背包/分解 → 雾区/后续票。

## 8. 对其他票的输入

- **#9 离线收益**：drop 事件流是收益统计源之一；掉落在挂机点按同规则进行（数值层同构复用）。
- **#10 编辑器**：LLM 可生成类型确认含 legendary 词缀，roster 即参考样例；掉率常量不进内容库，编辑器只读展示或不展示。
- **#12 波次/多怪**：explode_fire 恢复真实伤害语义的宿主。
- **Build 多样性票（本次毕业）**：stat_amp / proc / convert 三类 build 改变级已有封闭原语与实例，纯装备驱动路线已被证实可行，技能树是否参与成为真问题。
