# 设计文档索引

MVP 全部设计决议的落点：12 份文档，均为 v1 设计定稿（2026-09-03 决策地图 17/17 关闭，无待定项）。每份文档头部有「票 / 日期 / 决议输入 / 状态」，正文以「范围边界」开篇、以「对其他票的输入」收尾。术语以 `CONTEXT.md` 为唯一真相；引擎选型见 `docs/adr/0001`。

## 按任务路由

- 实现/修改**战斗数值层**（tick、聚合、伤害公式、事件）→ `combat-model.md` + `multi-monster-encounters.md`（后者修订前者，见「已知失效点」）
- 实现/修改**掉落与稀有度** → `loot-rarity.md`；套装件特例 → `set-items.md` §3
- 实现/修改**进度、区域、难度阶、挂机点** → `progression-structure.md`
- 实现/修改**离线结算** → `offline-settlement.md`（入账时机已被 `save-persistence.md` §6 微修）
- 实现/修改**背包、穿戴、换装** → `inventory-equipment.md`
- 实现/修改**存档** → `save-persistence.md`
- 实现/修改**技能与 build** → `build-system.md`（含对 combat-model 基础技能常量的修订）+ `set-items.md`（套装试点）
- 生成/校验**内容数据**、动编辑器 → `editor-agent-pipeline.md`（生成契约与校验器）+ `editor-asset-hub.md`（资产产线枢纽）
- 产出/校验**美术资产** → `art-asset-spec.md`（产线契约唯一真相）
- 写 MVP 规格（/to-spec）或追溯决议出处 → 按下方「文档清单」票号反查

## 文档清单（票号 ↔ 文档）

| 票 | 文档 | 一句话定位 | 随票落盘的产物 |
|---|---|---|---|
| #5 | progression-structure.md | 区域链 + 难度阶的进度结构；卡关回退永不挂起；挂机点 = {区域, 阶} | zone schema、content/zones/ 首示例 |
| #7 | combat-model.md | 数值层：100ms tick、属性聚合、乘算因子链伤害公式、on_attack/on_kill 零回调事件 | 接口草案（§6） |
| #8 | loot-rarity.md | 三层掉落判定链（掉不掉→稀有度→实例生成）、四档权重 55/32/12/1、传奇 roster | content/affixes/legendary/ |
| #9 | offline-settlement.md | 离线 = 回归时模拟补算（非速率折算），缺口上限 24h，drop 即自动入背包 | — |
| #10 | editor-agent-pipeline.md | 不直连 apikey：agent 经 skill 写 content/ + TS 校验器唯一真相 + pre-commit 兜底 | — |
| #11 | art-asset-spec.md | 资产规格：风格锚点、CC0/CC-BY 底线、命名映射即接口、网格基线、图标产线 | — |
| #12 | multi-monster-encounters.md | 遭遇 = 玩家 vs 一批同屏怪（count ≤5、boss 单挑）；explode_fire 恢复真实伤害 | zone schema 修订（encounters 元素升级） |
| #13 | build-system.md | build = 技能 × 装备；三主动槽等级解锁冷却即放；#17 候选 C1~C6 拍板 | skill schema、content/skills/ |
| #14 | inventory-equipment.md | 三槽一对一穿戴、任意时刻换装即时重聚合、背包无限只进不出 | — |
| #15 | save-persistence.md | user:// 三文件（save.json / heartbeat.json / inventory.jsonl append-only）；推导态不入档 | — |
| #16 | editor-asset-hub.md | 编辑器三职能：缺口识别 / 资产库 registry.json / 导入向导；任务包契约落 docs/tasks/ | — |
| #17 | docs/research/equipment-features-survey.md | D3/D4/PoE1/PoE2 装备特性调研，C1~C6 候选出处（不在本目录） | — |
| #18 | set-items.md | 套装件 = 专属基底（非第五档稀有度）；2 套 × 3 件套试点与强度锚 | set schema、content/sets/、items/base/ 成员基底 |

内容 schema 本身不在本目录：类型清单与管线契约见 `schema/README.md`，示例在 `content/`。

## 已知失效点（后补修订；原文档相应章节顶部已加 ⚠️ 指针，一律以取代方为准）

- `combat-model.md` §5「单怪轮番」→ 被 `multi-monster-encounters.md` 取代（玩家 vs 一批怪）；§3/§6「MVP 基础技能 = 引擎常量、skill_config」→ 被 `build-system.md` §2.4 修订（倍率来自技能内容、run_encounter 收装配技能数组）。
- `progression-structure.md` §2「一场遭遇 = 一个怪」与 §7 encounters 裸 monster 数组 → 被 `multi-monster-encounters.md` 升级为 `{monster, count}`（建议值改为 3~6 场、总普通怪 10~20）。
- `offline-settlement.md` §7「一键领取统一入账」→ 被 `save-persistence.md` §6 微修为「补算完成即入账落盘，摘要面板纯展示」。
- `editor-agent-pipeline.md` 中「七类型」计数 → 此后新增 skill 与 set 类型，实际类型清单以 `schema/README.md` 为准。

## 跨文档硬约束（改动前自查）

- 内容数据纯 JSON 直载，永不进 Resource/.tres（ADR-0001）。
- 公式与引擎常量全归引擎，内容只存离散配方数据（#4 配方模型）。
- 数值层 = 纯函数、零 IO / 引擎 API：在线、离线、编辑器三处同构复用（combat-model §6）。
- 事件载荷封闭、零回调：on_attack / on_kill / drop 事件（combat-model §4、loot-rarity §5）。
- 效果原语封闭集（stat_amp / proc_on_hit / proc_on_kill / convert_damage），新增 = schema 升版（CONTEXT.md「效果原语」）。
- 运行时实例不入 `content/`；可推导态不入档（save-persistence §3）。

## 相邻真相源

- `schema/README.md` + `schema/`：内容类型清单、id 即文件名、引用闭合与校验规则。
- `CONTEXT.md`（仓库根）：术语唯一真相；写文档时用表内术语，勿造同义词。
- `docs/adr/0001-godot-4-7-engine-selection.md`：引擎、内容直载与特效程序化路线。
- `docs/research/`：调研报告与许可快照。
