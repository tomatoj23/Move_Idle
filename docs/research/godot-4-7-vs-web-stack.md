# 调研：Godot 4.7 现状评估 vs Web 技术栈

> 票据：#2（调研 / research）｜日期：2026-09-02｜产出供「决策：技术栈与引擎选型」使用，本文不拍板。
> 状态：底稿由调研子代理产出；第 7 节为主会话同日完成的一手核证补充，已消化部分核实清单。

## 0. 方法与证据可信度声明

- 底稿撰写时代理环境无外网访问，**未能实时抓取任何官方页面**；版本特定事实一律标 [待核实] 并附官方核对 URL，绝不编造 4.7 的新特性条目。
- 证据分三级标注：
  - **[票据]**：仅来自调研票给出、尚未经官方页面复核的信息。
  - **[结构性]**：跨大版本长期稳定、低风险的事实，仍应复核。
  - **[推演]**：由本仓库 `CONTEXT.md` 既定架构推出的分析，不依赖外部版本事实。
- 详见第 7 节：发布页一手核证已完成，未决项已收敛。

## 1. 评估基准（来自本仓库既定架构，[推演] 的输入）

- **内容数据**：引擎无关纯 JSON（装备、词缀、怪物、风味文本），引擎与编辑器都只是消费者。
- **内容编辑器**：运行于本地的 Web 工具——「内容编辑器是 Web 工具」已是术语表内的既定事实，不是本次待决项。
- **数值层**：独立于表现的战斗结算；**表现层**只做可视化，不参与判定。
- 放置 = 在线自动战斗 + 离线结算收益 → 数值层必须一处实现、多宿主运行（浏览器在线跑、离线按同构规则折算）。
- 横版只是表现层取向；MVP 切片要求「界面可以糙，循环必须闭环」。

## 2. 候选对象

| 候选 | 定位 |
|---|---|
| Godot 4.7.x | 完整开源引擎 |
| PixiJS | Web 2D 渲染器（非完整引擎），TypeScript 原生 |
| Phaser | Web 2D 完整框架（场景/输入/动画/粒子/tilemap 内置），官方 TS 定义 |
| 裸 Canvas | 平台原生 Canvas2D，零依赖，表现层设施全自建 |

## 3. 逐维度评估

### 3.1 2D 动画 / 粒子 / 表现层能力

- **Godot [结构性]**：内置 AnimationPlayer（时间线/轨道）、SpriteFrames 帧动画、GPUParticles2D / CPUParticles2D、着色器、TileMap；2D 有独立像素工作流。表现层工具链开箱即用，四者中最全。4.7 相对 4.3–4.6 的 2D/粒子改进幅度见第 7 节。
- **PixiJS [结构性]**：WebGL/WebGPU 渲染器，绘制性能好；但只是渲染器——补间、状态机、粒子发射器等需自写或用生态包。
- **Phaser [结构性]**：框架级，动画管理器、粒子发射器、输入、tilemap 内置，覆盖本项目表现层需求绰绰有余；版本线见第 7 节。
- **裸 Canvas [推演]**：MVP 阶段可行，但掉落飞行动画、命中粒子、换装视觉爽感迟早要补间与粒子库，纯自写长期成本高。

**小结 [推演]**：此项对 MVP 权重低（界面可以糙），对长期「数值爽感可视化」权重高。Godot 上限最省事；Web 栈里 Phaser 省事、PixiJS 自由度高但要拼装。

### 3.2 Web 导出质量与体积、桌面导出成本

- **Godot [结构性]**：Web 导出 = WebAssembly；启用线程需跨源隔离响应头（COOP/COEP）+ SharedArrayBuffer；包体量级为数十 MB，比 Web 栈大 1–2 个数量级；C# 的 Web 导出在 4.x 早期不受支持、后续推进中——4.7 的实际状态见第 7 节。桌面导出（Win/macOS/Linux）为内置导出模板，个人项目成本极低。
- **Web 栈 [推演]**：产物为静态文件（几百 KB ～ 数 MB 量级），任意静态托管可发布，免费档可覆盖；需要桌面壳时走 Tauri/Electron，属额外成本。

**小结 [推演]**：Web 发行是既定方向（放置品类天然适合浏览器即开即玩）→ Web 栈此项天然占优；Godot 的桌面导出优势只在你决定走 Steam 桌面发行时兑现。

### 3.3 与「引擎无关 JSON 内容数据」的契合度

- **两者都能消费 JSON [结构性]**：Godot 内置 JSON 解析；Web 栈 JSON 即原生。
- **关键差异是「引力」[推演]**：Godot 的工作流会持续把内容往 Resource/.tres/编辑器资产上拉，坚持引擎无关 JSON 需要纪律（数值内容不进 Resource 体系，只做表现资产与 JSON 双轨）；Web 栈没有这股引力，JSON 即第一公民。
- **同构复用差距 [推演]**（本报告最重的判断）：内容数据的消费者有三个——数值层、内容编辑器、表现层。
  - 选 Web/TS：数值层 = 纯 TS 模块，浏览器（在线自动战斗）与 Node（离线结算/内容校验 CLI）同一份代码；内容编辑器（已是 Web 工具）与数值层共享同一套类型 + schema 校验；「LLM 批量生成 → 校验 → 导入」闭环在一种语言内完成。
  - 选 Godot：数值层用 GDScript 或 C#，与内容编辑器（Web 工具）异构；JSON schema、校验规则、词缀组合逻辑需要两套实现并保持同步（或引入代码生成），这是一笔持续的架构税。

### 3.4 TypeScript 生态与 LLM 辅助开发友好度

- **[推演]** 内容编辑器的职责之一是「LLM 批量生成并校验导入」：TS 类型 + JSON Schema + 校验器（如 zod）是对 LLM 生成-校验-导入最直接、语料最富的链路。
- **[结构性]** Godot 侧：GDScript 语料量小于 TS/C#；C# 语料富但需混用引擎 API 与 .NET，LLM 生成后仍需人工接引擎侧装配。

### 3.5 个人项目的构建/发布现实成本

- **Web 栈 [推演]**：构建 = npm + 打包器，一次配置；发布 = 静态托管，零成本档可用；无平台审核。
- **Godot [结构性]**：引擎免费开源（MIT）、无版税；桌面导出近乎零边际成本；Web 导出需处理跨源隔离头与包体。

## 4. 带条件倾向（不构成拍板）

- **倾向 Web/TS**，当且仅当：① 内容编辑器 / 数值层 / 离线结算的同语言同构复用是最高权重；② 接受表现层用 Phaser（省事）或 PixiJS（自由）补齐，MVP 阶段容忍糙表现；③ 短期不依赖 Steam 桌面发行。此倾向与既定事实「内容编辑器 = 本地 Web 工具」同侧。
- **倾向 Godot 4.7.x**，当且仅当：① 后续核实显示 4.7 在 Web 导出体积/线程/C# 支持上有实质改善（第 7 节已部分证伪）；② 你更看重内置动画/粒子工具链（长期表现层省力）；③ 桌面发行进入近期规划。
- 裸 Canvas 仅作兜底认知，不建议作为独立候选进入决策票。

## 5. 决策票的输入格式建议

决策票只需回答三问：① 3.3 节「同构复用」与 3.2 节「Web 发行质量」哪个权重更高；② 第 6 节剩余核实清单的复核结果；③ Web 栈内部再选 Phaser vs PixiJS（若走 Web/TS）。

## 6. 核实清单（原始版）

1. Godot 4.7 发布公告与 4.7 / 4.7.1 / 4.7.2 release notes：https://godotengine.org/blog/ 与 https://github.com/godotengine/godot/releases
2. Web 导出官方文档：https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
3. C# / .NET 平台支持矩阵：https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/index.html
4. PixiJS 当前大版本与 WebGPU 渲染器状态：https://pixijs.com/guides/ 与 https://github.com/pixijs/pixijs/releases
5. Phaser 当前大版本与维护节奏：https://phaser.io/
6. 若 Web 发行确定：WebGL 托管平台对 Godot Web 导出跨源隔离头的支持现状。

## 7. 主会话一手核证补充（2026-09-02）

以下事实由主会话直接抓取官方一手来源核证：

### 7.1 Godot 4.7 官方发布页（https://godotengine.org/releases/4.7/ ，标题 Godot 4.7, Lights, Camera, Action!）

已核证的高亮条目：AreaLight3D（3D）、文本着色器内联预览、**全新 Asset Store（取代 Asset Library，带评分与预览缩放，编辑器内多线程浏览）**、Control 节点 offset transform（UI 位移动画不再被容器覆盖，默认纯视觉不影响输入命中）、DrawableTexture2D、HDR 输出（**平台列表为 Windows / macOS / iOS / visionOS / Linux(Wayland)——Web 不在列**）、CollisionShape2D 单向碰撞方向属性（2D）、Tween.tween_await()（等待信号）、**按平台下载导出模板**、内置 VirtualJoystick 节点（移动端）、Wayland 触控、Android XR / Steam Frame day-one 支持、Android 画中画与 GABE 转正。

**对决策最关键的两条**：

1. **整个 4.7 发布说明没有任何 Web 导出 / HTML5 / WASM 相关条目，也没有 C# / .NET 改进条目。** 4.7 的重心是编辑器 QoL、3D 渲染、XR、Android。即：票面担心的「4.7 更新了很多重要东西」属实，但**不在 Web 导出方向上**——3.2/4 节里「若 4.7 Web 导出有实质改善则 Godot 重新占优」的翻转条件，在 4.7 这个版本上**未兑现**。
2. Control offset transform 与 Tween 信号等待等 QoL 对「表现层爽感」有真实帮助，但 Web/TS 侧的补间/动画生态同样成熟，此项不构成决定性差异。

顺带 [结构性] 补充：发布页称 2026 上半年 Steam 已上架 700+ 新 Godot 游戏、itch.io 每周新增 1000+ Godot 游戏（供将来发行参考，与本决策无直接关系）。

### 7.2 Phaser 当前版本（phaser.io / GitHub releases）

- v4.0.0 稳定版 **2026-04-10** 发布：**全新 WebGL 渲染器彻底重写**（GitHub 称其为 Phaser 历史上最大版本）。
- 当前稳定版 **v4.2.1（Giedi）**，2026-07-09。
- 决策含义：Phaser v4 很新（转正不到半年），生态插件对新渲染器的适配成熟度需要在决策票时抽查；v3 线仍在维护（存量语料大）。

### 7.3 PixiJS 当前版本（pixijs.com / GitHub）

- 现行大版本 **v8**：WebGL 为主、**WebGPU 可选**，全扩展（extension）化架构；2026-04 仍活跃维护。
- 决策含义：PixiJS 定位未变（渲染器，非完整引擎），与 3.1 节判断一致。

### 7.4 清单收敛状态

| 原清单项 | 状态 |
|---|---|
| 1. 4.7 发布说明 | ✅ 主发布页已核证（4.7.1/4.7.2 补丁内容未逐条读，维护性补丁，低风险） |
| 4. PixiJS 版本线 | ✅ v8，WebGPU 可选 |
| 5. Phaser 版本线 | ✅ v4.2.1，v4 渲染器重写 |
| 2. Web 导出文档（线程/COOP-COEP/包体） | ⬜ 留给决策票（结构性事实不变，预期 4.7 未变） |
| 3. C# / .NET 平台支持矩阵 | ⬜ 留给决策票（4.7 发布说明无相关条目，预期未变） |
| 6. 托管平台对 Godot Web 导出的支持 | ⬜ 仅在决策票倾向 Godot 时需要 |

### 7.5 引用

- https://godotengine.org/releases/4.7/ （官方发布页，2026-06）
- https://phaser.io/download/stable （v4.2.1，2026-07-09）
- https://github.com/phaserjs/phaser/blob/master/changelog/v4/4.0/CHANGELOG-v4.0.0.md （v4 渲染器重写说明）
- https://pixijs.com/ 与 https://pixijs.io/guides/basics/architecture-overview.html （v8 扩展架构、WebGPU 可选）
