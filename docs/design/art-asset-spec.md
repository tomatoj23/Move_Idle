# 设计：美术资产产出规格（资产规格 v0）

- **票**：wayfinder 决策票 [决策：美术资产来源与占位策略](https://github.com/tomatoj23/Move_Idle/issues/11) 的决议产物（2026-09-02）
- **地位**：agent 生成、编辑器导入校验、引擎加载三方共同消费的产线契约；本文档为该契约的唯一真相
- **弹性条款**：文中标注「基线」的数字与选型均为默认值，**不写死**——修订本文档即修订产线契约；因表现层可整体替换（架构保证），修订无需迁移历史资产

## 1. 风格锚点

- 像素风，暗黑西幻，40px 级小体量角色。
- 风格基准 = 当前参考包（§4）；新产资产（AI / 外包 / 自制）向基准对齐：同色阶密度、同轮廓读法。
- 特效不在此列：特效程序化（GPUParticles2D + shader + Tween），见 ADR-0001。

## 2. 许可政策

- **基线：只收 CC0 / CC-BY**；自定义 EULA 池（CraftPix 类）默认排除，特例须在本文档记录理由。
- 许可快照存 `docs/research/licenses/`（逐来源一档，换包/升版时重抓对应小节）。
- 署名清单自 MVP 起维护（CC0 不强制，作者感激 + 未来上架留余地）；清单随资产落库写在 `docs/research/licenses/` 对应档内。
- 外来资产导入一律过同一许可检查（「编辑器：资产产线枢纽」票的校验项）。

## 3. 占位与替换策略

- **候选正式包即占位**：不另做程序员美术。「占位 / 正式」之差只是换不换；表现层不参与战斗判定，可整体替换。
- 替换 = 接口替换：新资产满足 §5 命名与帧结构 + §6 网格基线即可整体换装。

## 4. 当前选择（占位即正式）

| 角色 | 资产 | 来源 | 许可 | 备注 |
|---|---|---|---|---|
| 主角 | Medieval Warrior v1.2 | luizmelo.itch.io/medieval-warrior | CC0（已核证） | 必须用 v1.2 文件（21kB），旧包仅 5 组动画；13 组动画含 attack×3 |
| 怪物 | Monsters Creatures Fantasy v1.3 | luizmelo.itch.io/monsters-creatures-fantasy | CC0（已核证） | 4 怪全套动画；扩怪优先同作者系列（MCF 2、Fantasy Troll 等，同风格成套） |
| UI 占位 | Kenney | kenney.nl | CC0 | 按需取用 |

- 实测帧内容尺寸：怪物包平均 35×39px；主角包同量级（精确值下载后回填本表）。

## 5. 命名与帧结构约定（#6 接口细化）

- 动作命名，MVP 必需集：`idle / run / attack_N / hurt / death`；富余集（可选，不进 MVP 验收）：`jump / fall / crouch / roll / slide`。
- 目录与映射（**命名约定即映射**，内容 schema 零变更）：
  - 怪物：`content/monsters/<id>.json` ↔ `game/assets/monsters/<id>/`
  - 主角：固定目录 `game/assets/hero/`
  - 图标：装备基底 id ↔ `game/assets/icons/<base_id>.png`
- 每资产目录内：动画 spritesheet PNG（原包原样，不重排）+ `manifest.json`。
- `manifest.json` 字段（基线）：`{ "frame_width", "frame_height", "animations": { "<动作名>": { "row": <行号>, "frames": <帧数>, "fps": <帧率> } } }`。
- 引擎侧：通用 loader 读 manifest 转 SpriteFrames；表现资产不进 Resource 体系（与 ADR-0001 纯 JSON 直载同精神）。
- 校验器职责：资产存在性检查（内容 id ↔ 目录/PNG 断链即报错）；schema 不动，检查走文件系统。

## 6. 帧网格基线

- 角色/怪物：**64×64 画布**（40px 级内容居中留白可容）。
- 图标：**32×32**。
- 升档条款：内容超出画布 → 网格升档（64→96/128…），manifest 记实际值，全项目随档。
- 原参考包**原样直用**：不强制重排进网格；网格只约束新产资产的产出标准。

## 7. 图标产线（AI 生成为主）

- 生成：统一 prompt 模板（基线：dark fantasy pixel art item icon / 32×32 / 限定调色板 / 纯色或透明背景 / 居中单体）。
- 调色板基线：从参考包采样主色阶，随模板固化。
- 入库：AI 产出 → 人工筛选 → `game/assets/icons/<base_id>.png`；icon id 与表现解耦（内容数据只按 §5 命名映射）。
- 披露义务：Steam 等平台要求申报预生成 AI 内容，上架前如实填写。

## 8. 编辑器接口（消费方：「编辑器：资产产线枢纽」票）

- 制作需求（任务包）格式、资产库数据模型、导入校验流水线：归该票设计。
- 本文档 + §5 校验规则 = 该票的输入契约。
- 决议（2026-09-03）：三职能 MVP 范围、registry 数据模型、任务包契约、导入流水线与校验器边界见 `docs/design/editor-asset-hub.md`。
