# Godot 4.7 编码标准（agent 执法用）

状态：生效（2026-09-03）｜ 关联：ADR-0001（引擎锚定 4.7.x）、`docs/research/godot-4-5-to-4-7-changes.md`（变更全量镜像）

## 版本锚定与知识边界

- 本项目引擎 = **Godot 4.7.x**（ADR-0001），所有 GDScript / 场景 / 项目设置按 4.7 形态书写。
- AI agent 的训练数据**只可靠到 Godot 4.4 stable（2025-03）**，已实测校准。凡 4.5 及以后的 API、行为、默认值，**一律以下列两处为准，禁止凭训练记忆作答**：
  1. 本地真相：`docs/research/godot-4-5-to-4-7-changes.md`（4.5/4.6/4.7 破坏性、行为、默认值变更的官方迁移指南 1:1 全量镜像，按子系统分组）；
  2. 权威：官方 class reference（锁定 4.7 版本，见文末查证入口）。

## 核证流程（落码前的强制步骤）

1. **圈定本任务要碰的子系统**（UI→GUI、战斗→2D/Physics、音频→Audio……），**规划落稿前**（或直接落码时）先扫镜像表对应分组的三小节（破坏性/行为/默认值，§4.2–6.4，每版各约一页）。这是**任务级动作，做一次**，不是每个 API 做一次。
2. 对每个 API 分流（**拿不准 = 按"晚于 4.4"处理**）：
   - 🟢 直接写：4.4 前存量核心 API、能完整复述签名、**且第 1 步扫描未见其变更记录**——如 `Vector2`、`Node2D`、`Input.is_action_pressed`；
   - 🟡 按本地记录写：出现在策展/审计补记 → 形态已核证，按记录用；
   - 🔴 必查："感觉应该有"但复述不出完整签名、4.5+ 新概念词、C#/XR/3D 渲染弱区。
   - **"4.4 前就存在"不豁免查证**：存在只证明"我认识它"，不证明"它还是老样子"。实证（全是训练记忆里的老朋友）：`duplicate(true)` 4.5 语义收窄、`AudioStreamPlayer.area_mask` 4.7 默认 1→0、`draw_line` 4.7 去 AA 羽化、`get_as_text` 4.6 删参、`device == 0` 4.7 失效。**签名复述永远无法验证默认值**——默认值变更只能靠镜像表。
   - 镜像表只证明"改过什么"，不证明"什么没改过"——存在性与签名的最终裁决是 class reference，不是记忆，也不是"镜像里没有"。
3. 签名、默认值、存在性仍无把握 → 查锁定版 class reference 对应类页。
4. **完成标准**：diff 中每个晚于 4.4 的 API，都有本地镜像或 class reference 的明确出处；训练记忆与查证结果冲突时，以查证结果为准。

## 规划与文档的核证（设计文档 / ADR / 任务规划）

规划偏差沿流水线放大：规划层修复是分钟级（改一页文档），实现层是小时级（改码 + 重测）。两类偏差，抓法不同：

- **基于旧假设做设计**（地基用了已变更/已失效的 API）——文档中具体 API/属性提法可静态检索，硬规则同样适用；
- **遗漏更优新特性**（方案能工作但错过 4.5+ 更好路径）——机器不可抓，只能靠策展节对照。

**触发边界**：意图级提法（"用 Tween 做动画"）不触发；具体 API / 属性 / 类名写进设计文档、ADR、任务规划即触发核证。防仪式化，不让每个 TODO 都查库。

**落稿 checklist（一问）**：本设计涉及的每个子系统，对照镜像文档该版本的策展节——(a) 计划采用的方式是否已被 4.5+ 新 API 替代；(b) 是否有新特性直接命中本需求。只扫涉及子系统的策展节（每版约一页），不读全量。

**ADR 特别提醒**：决策理由里的引擎能力假设（"因引擎支持 X，所以选 A"）是旧版形态最危险的藏身处——论据中的每个引擎事实按核证流程处理。

**第三方插件选型**：先查插件对 4.7.x 的兼容声明；插件文档不能当引擎 API 形态的依据。

**优先级**：本页合规约束优先于任何任务方法论（含 skill 工作流）；机器层（CI / pre-commit）对一切来源的产物执法。

## 测试脚本的核证

- 测试也是 GDScript：编译检查、反模式 lint、headless 校验自动覆盖，无需另设机制。
- 断言依赖的引擎行为若属 4.5–4.7 变更区（镜像表可查），测试处标注出处，与产品代码同规则。
- **测试绿 ≠ 符合新版规范**：用旧 API 写的测试也能绿——测试只证明"行为符合断言预期"，不证明"方案是新版最优路径"，后者仍靠策展对照。
- 测试框架选型（GUT / gdUnit4）是规划类决策：先查框架对本引擎版本的兼容声明。

## 硬规则清单（GDScript 视角，标引入版本）

### GDScript / Core

- 深拷贝用 `duplicate_deep(DEEP_DUPLICATE_ALL)`；`duplicate(true)` 自 4.5 只复制资源文件内部资源。（4.5）
- 可变参数用 `func f(first: int, ...rest: Array)` 语法。（4.5）
- 强制子类实现用 `@abstract class_name` + `@abstract func`。（4.5）
- Packed Array **元素**赋值不触发整属性 setter（4.7）；setter 副作用逻辑改走整属性赋值或显式方法。
- override 父方法时显式写 `return`（4.7 起缺 return 编译错）。
- Tween 等信号用 `tween_await()`。（4.7）
- RichTextLabel 图片参数用 `width_unit` / `height_unit`（`ImageUnit` 枚举）；`size_in_percent`（≤4.4）与 `width_in_percent`（4.5）均已废。（4.7）
- 多人 RPC 配置方法叫 `get_node_rpc_config`。（4.5 更名）
- `FileAccess.get_as_text()` 无参调用；`skip_cr` 参数已删。（4.6）
- 属性枚举迁移：`EDITOR_SCENE_FORMAT_IMPORTER_*` → `ImportFlags`；`ImageUpdateMask.UPDATE_WIDTH_IN_PERCENT` → `UPDATE_WIDTH_UNIT`。（4.7）

### 2D

- TileMapLayer 物理默认分块合并；逐格取碰撞坐标需 `physics_quadrant_size = 1` 或改用 tile 坐标。（4.5）
- 单面碰撞方向用 `CollisionShape2D.one_way_collision_direction`，不依赖形状本地朝向。（4.7）
- 程序化画纹理用 `DrawableTexture2D`，不用 Viewport 中转 hack。（4.7）
- `draw_line` / `draw_polyline` 线宽按 4.7 实际渲染调（无 AA 羽化加粗）。（4.7）
- 锥形渐变用 `GradientTexture2D.FILL_CONIC`。（4.7）

### UI

- 容器子节点变换动画用 `Control.offset_transform_*`，布局重排不覆盖。（4.7）
- 枢轴按比例设用 `pivot_offset_ratio`。（4.6）
- 整组禁用/启用交互用 `mouse_behavior_recursive` / `focus_behavior_recursive`。（4.5）
- 手风琴用 `FoldableContainer`。（4.5）
- 动态字体默认 hinting=3（4.7），UI 字体观感核对。

### 输入

- 区分键鼠设备用 `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD` 常量（4.7）；`device == 0` 判断已失效。
- 移动端虚拟摇杆用内置 `VirtualJoystick` 节点。（4.7）

### 项目设置 / 场景 / 导出

- 场景文件为 4.6+ 格式（unique node IDs、无 `load_steps`）；旧场景首次保存前跑 `Project > Tools > Upgrade Project Files...` 并**单独一个 commit**。（4.6）
- Windows 新建项目默认渲染器 D3D12（4.6）；stretch 新项目默认 `canvas_items` + `expand`（4.7）——沿用本仓库项目设置时逐项核对。
- Windows 导出无需 rcedit（4.5）；Android 导出满足 16KB pages（Google Play 2025-11 起新提交强制）。

### 音频

- `AudioStreamPlayer2D/3D.area_mask` 默认 0（4.7）；`Area` 音频总线覆写场景必须显式设掩码。非定位 `AudioStreamPlayer` 无 `area_mask` 属性（ClassDB 实测，官方指南措辞泛指系列）。

## 完整性边界

- 本文件只列**会改变写法的规则**。完整变更清单（含 C# 条目、3D/XR/网络子系统）在 research doc——**扩展新子系统（3D、多人、XR、C#、Web）前，先读其对应分组**。
- 本文件与 research doc 均为缓存与加速器；API 最终形态的权威只有锁定版 class reference。
- 已知未覆盖盲区（新资产类型首次落库前，按 `docs/agents/process-audit.md` 触发时机第 4 条实测再定执法方案）：`.gdshader`（shader 语言同样有版本演进，lint 与加载检查均不扫）；场景/资源旧属性漂移（`check_project.gd` 只 grep 错误不 grep 警告）；运行时序列化数据兼容（默认值/格式变更破坏旧存档，发布前关注）；本地引擎版本低于锁定版时 headless 校验是假绿信号（本地校验只是加速器，CI 才是裁决）。

## 机器执法（headless 校验）

仓库 CI（`.github/workflows/ci.yml`）在 `new-game-project/` 变更时自动执行：Godot 4.7.2-stable headless 导入 → `tools/validation/check_project.gd` 全量加载检查（脚本编译 + 场景/资源加载），任何 `SCRIPT ERROR` / `Parse Error` 直接红。CI 另含**反模式 lint**：命中可静态匹配的 4.5+ 已改名/已移除 API（`device == 0`、`size_in_percent`、带参 `get_as_text()`、`duplicate(true)` 等）同样直接红。**红了先修到绿，再继续其余工作。**

本地同款命令（把 `godot` 换成本机编辑器路径）：

    godot --headless --path new-game-project --script res://tools/validation/check_project.gd

提交时另有 **pre-commit 钩子**（`.githooks/pre-commit`）自动跑同款反模式 lint，命中即拒绝提交。新克隆装机：`git config core.hooksPath .githooks`。

## 查证入口

- Class reference（锁定 4.7）：`https://docs.godotengine.org/en/4.7/`（若该版本路径不存在，用 `/en/stable/` 并核对页头版本号 = 4.7）
- 机器可读 API 文档：`https://raw.githubusercontent.com/godotengine/godot/<版本分支>/doc/classes/<ClassName>.xml`（godot **主仓库**；godot-docs 仓库无 XML，docs 站页面抓取只出导航目录）
- 本地 ClassDB 探针核证法（4.5+ API 最快权威，与 CI 同版引擎）：临时 `extends SceneTree` 脚本 dump `ClassDB.class_get_property_list / class_get_method_list / class_get_integer_constant_list` + 实例 `get()` 取默认值，输出落盘后读、跑完即删。已知坑：`class_has_method` 对 Packed*/Variant 内建类型恒 false，不能当存在性证据；`class_name` 是保留字不能作参数名；探针脚本勿与 `tools/validation/` 正式校验器混放，输出别落仓库根。
- 迁移指南：`https://docs.godotengine.org/en/stable/tutorials/migrating/`（正文抓取用 godot-docs 仓库 raw RST）
- Release 页：`https://godotengine.org/releases/4.7/`
