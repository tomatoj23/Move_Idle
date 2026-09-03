# Godot 4.5→4.7 变更全量调研：AI 知识边界校准 + 迁移镜像

状态：调研完成（2026-09-03，v2 补全镜像）｜ 关联：ADR-0001（引擎选型 4.7.x）｜ 本项目形态：2D 横版放置 ARPG，纯 GDScript，JSON 内容直载

## 1. 文档目的

1. **校准** AI 代理训练数据中的 Godot 版本边界。实测结论：**可靠覆盖到 Godot 4.4 stable（2025-03 发布），4.5 起全部视为未知**。
2. 把 4.5 / 4.6 / 4.7 三个版本的官方迁移指南**逐条 1:1 镜像**落盘（含 GDScript 兼容标记与仅 C# 条目），作为 agent 开发各环节的本地一手真相。

**使用规则**：凡涉及「某 API 是否存在 / 是否改名 / 默认值是什么」且可能晚于 4.4，一律先查本文档或官方文档，禁止凭训练记忆作答。

## 2. 校准方法与证据

方法：先凭训练记忆盲答「各版本引入了什么」，再对照官方发布页逐条验证识别度，断崖位置即知识边界。

| 版本 | 识别度 | 判定 |
| --- | --- | --- |
| ≤ 4.3 | 完整掌握 | 可靠 |
| 4.4 | 完整掌握，且被反向印证 | **可靠** |
| 4.5 | 高优先条目几乎全盲 | **不可信** |
| 4.6 | 零识别 | 未知 |
| 4.7 | 零识别 | 未知 |

- **4.4 边界反向印证**：4.5/4.6 官方页引用的三条 4.4 旧特性（embedded game window、UID 扩展到更多资源类型、Jolt 以实验性选项集成）与训练记忆完全吻合；4.5 迁移指南亦确认「3D physics interpolation 于 4.4 在 RenderingServer 实现」（与训练记忆一致），而其移入 SceneTree 的 4.5 改动训练记忆中不存在。
- **4.5 断崖证据**（训练记忆均无）：GDScript 可变参数、`@abstract` 抽象类落地、TileMapLayer 物理分块、独立 2D NavigationServer、`duplicate_deep()`、`FoldableContainer`。
- 4.6 / 4.7：所有条目零识别。

## 3. 完整性边界声明（本文件什么可信、什么不全、靠什么兜底）

真相分三级，本文件只对第 1 级承诺全量：

| 层级 | 内容 | 本文件的角色 | 权威来源 |
| --- | --- | --- | --- |
| 1. 破坏性变更 / 行为变更 / 默认值变更 | 官方迁移指南认为「迁移时必须注意」的集合 | **1:1 全量镜像**（含仅 C# 条目；随迁移指南版本同步） | godot-docs 仓库迁移指南 RST |
| 2. 新特性（非破坏性增量） | 每版约 1600–2500 个 PR | **只做策展精选**（明确标注，不承诺全量） | GitHub releases changelog |
| 3. 当前 API 的最终形态（签名/默认值/存在性） | — | 不镜像，禁止当作豁免 | **官方 class reference（锁定 4.7 版本）** |

配套约定：

- 变更表按**官方子系统分组**（Core / 2D / 3D / GUI / Text / Rendering / Animation / Physics / Audio / Input / Navigation / Networking / Editor / 平台 / XR / GDScript），**不按「本项目相关」筛选**——项目未来扩展到新子系统（3D、多人、音频、XR、C#、Web）时直接按组查阅，不会漏。
- 仅影响 C# 的条目以 `[仅 C#]` 标注收录，GDScript 兼容列照常给出；未来引入 C# 时无需重查。
- **元规则（同步写入 `docs/agents/godot-standards.md`）**：凡 4.5+ 的 API 落码前，若对其签名/默认值/存在性无把握，必须查锁定版本的官方 class reference；本文件是缓存与加速器，不是豁免。
- 表格符号：`✔️` = 不破坏该语言兼容；`❌` = 破坏（`❌(stub)` = 保留空壳防崩溃但功能失效）；`⚠` = 需改调用点。

## 4. Godot 4.5（2025-09-15 发布，4.4→4.5）

### 4.1 新特性策展精选（非全量；全量见 release 页与 changelog）

- **GDScript**：可变参数 `func sum(first: float, ...numbers: Array) -> float`；抽象类 `@abstract class_name Animal extends Node` + `@abstract func cry() -> void`（子类必须实现）。
- **2D**：TileMapLayer 物理分块（多格碰撞合并）；独立 2D NavigationServer（纯 2D 导出可裁 3D，体积显著减小）。
- **Core**：`Array` / `Dictionary` / `Resource` 新增 `duplicate_deep()`。
- **UI**：`FoldableContainer`（手风琴）；`Control.mouse_behavior_recursive` / `focus_behavior_recursive`（整组禁用/启用交互）；Label 多层描边/阴影；`@export` 支持 `Variant` 类型（带类型选择器）+ `PROPERTY_HINT_GROUP_ENABLE`。
- **调试/日志**：脚本回溯（Release 构建也可，需开 `Always Track Call Stacks`）；自定义 Logger；Game 视图静音键。
- **渲染**：stencil buffer；Shader Baker（导出预编译着色器，Metal/D3D12 实测启动快 20 倍）。
- **编辑器**：拖资源入脚本按 UID 预载（抗路径变更）；远程节点多选；编辑器语言即时切换；Inspector 分组开关/颜色色块预览/批量导入编辑/Paste as Unique；项目管理器复制项目；动画编辑器框选/排序/过滤；HiDPI 图标。
- **平台**：Windows 导出不再依赖 rcedit；Android 16KB pages（Google Play 2025-11 起新提交强制；C# 需 .NET 9）+ 边到边显示 + 相机馈送 + 移动端烘焙光照贴图；Linux Wayland 原生子窗口；macOS 游戏嵌入；visionOS 导出（首个原生支持的新平台）；Web WASM SIMD。
- **输入**：手柄驱动迁移到 SDL3（第三方手柄特性与修复收敛更快）。
- **官方 highlights 审计补记（2026-09-03，与 release 页逐条对表后补收）**：BoneConstraint3D 骨骼绑定骨骼（3D 动画）；镜面遮蔽/弯曲法线贴图/SMAA 1x/Mobile 半精度渲染（Rendering 3D）；OpenXR D3D12 后端、注视点渲染、Render Models、Application SpaceWarp（XR）；GDExtension 主循环回调；.NET 程序集从 APK 直载（C#）；编辑器 TouchActionsPanel。
- 未列入的其余条目（i18n 实时预览、屏幕阅读器、build profile 增强等）见 §7 来源。

### 4.2 Breaking changes 全量镜像

Core：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| JSONRPC | `set_scope` 被 `set_method` 取代 | ❌(stub) | ❌(stub) | GH-104890 |
| Node | `get_rpc_config` 更名 `get_node_rpc_config` | ❌ | ✔️(compat) | GH-106848 |
| Node | `set_name` 参数 `String`→`StringName` | ✔️ | ✔️(compat) | GH-76560 |

Rendering：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| DisplayServer | `file_dialog_show` 新增可选 `parent_window_id` | ✔️ | ✔️(compat) | GH-98194 |
| DisplayServer | `file_dialog_with_options_show` 新增可选 `parent_window_id` | ✔️ | ✔️(compat) | GH-98194 |
| RenderingDevice | `texture_create_from_extension` 新增可选 `mipmaps` | ✔️ | ✔️(compat) | GH-105570 |
| RenderingServer | `instance_reset_physics_interpolation` 移除 | ❌ | ✔️(compat) | GH-104269 |
| RenderingServer | `instance_set_interpolated` 移除 | ❌ | ✔️(compat) | GH-104269 |

`[仅 C#]` 枚举 `RenderingDevice.Features` 成员 `Address` 更名 `BufferDeviceAddress`（绑定生成器前缀检测所致，GH-103941）。

GLTF（全部 GDScript ✔️，C# ❌，GH-106220；类型元数据 int32→int64 或 int→枚举）：

| 类 | 属性 |
| --- | --- |
| GLTFAccessor | `byte_offset`、`count`、`sparse_count`、`sparse_indices_byte_offset`、`sparse_values_byte_offset`（int32→int64）；`component_type`、`sparse_indices_component_type`（int→GLTFComponentType） |
| GLTFBufferView | `byte_length`、`byte_offset`、`byte_stride`（int32→int64） |

Text（draw 系列全部新增可选参数 `oversampling`，GDScript ✔️，GH-104872）：

| 类 | 方法 |
| --- | --- |
| CanvasItem | `draw_char`、`draw_char_outline`、`draw_multiline_string`、`draw_multiline_string_outline`、`draw_string`、`draw_string_outline` |
| Font | 同上 6 个同名方法 |
| TextLine | `draw`、`draw_outline` |
| TextParagraph | `draw`、`draw_dropcap`、`draw_dropcap_outline`、`draw_line`、`draw_line_outline`、`draw_outline` |
| TextServer | `font_draw_glyph`、`font_draw_glyph_outline`、`shaped_text_draw`、`shaped_text_draw_outline` |

Text 其余（GDScript ✔️）：

| 类 | 变更 | PR |
| --- | --- | --- |
| RichTextLabel | `add_image` 新增可选 `alt_text` | GH-76829 |
| RichTextLabel | `add_image` / `update_image`：`size_in_percent` 被 `width_in_percent` + `height_in_percent` 取代 | GH-107347 |
| RichTextLabel | `push_strikethrough` / `push_underline` 新增可选 `color` | GH-106300 |
| RichTextLabel | `push_table` 新增可选 `name` | GH-76829 |
| TreeItem | `add_button` 新增可选 `alt_text` | GH-76829 |

Text 虚方法覆写（**GDScript ❌**，覆写签名必须补参数；C# ❌，GH-104872）：

| 类 | 方法 |
| --- | --- |
| TextServerExtension | `_font_draw_glyph`、`_font_draw_glyph_outline`、`_shaped_text_draw`、`_shaped_text_draw_outline`（均新增 `oversampling` 参数） |

XR：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| OpenXRAPIExtension | `register_composition_layer_provider` / `register_projection_views_extension` / `unregister_composition_layer_provider` / `unregister_projection_views_extension` 参数类型 `OpenXRExtensionWrapperExtension`→`OpenXRExtensionWrapper` | ✔️ | ✔️(compat) | GH-104087 |
| OpenXRBindingModifierEditor / OpenXRInteractionProfileEditor / OpenXRInteractionProfileEditorBase | API 类型 Core→Editor（导出包中不存在） | ❌ | ❌ | GH-103869（已回移 4.4.1） |

Editor plugins：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| EditorExportPlatform | `get_forced_export_files` 新增可选 `preset` | ✔️ | ✔️(compat) | GH-71542 |
| EditorUndoRedoManager | `create_action` 新增可选 `mark_unsaved` | ✔️ | ✔️(compat) | GH-106121 |
| EditorExportPlatformExtension | `_get_option_icon` 返回 `ImageTexture`→`Texture2D` | ✔️ | ❌ | GH-108825 |

`[仅 C#]` Android 导出要求 .NET 9（其余平台仍 .NET 8 起步，可更高）。

### 4.3 行为变更全量镜像

- **TileMapLayer**：物理分块默认开启，`get_coords_for_body_rid()` 返回值与 4.4 不同（分块越大越不精确）；`physics_quadrant_size = 1` 可恢复逐格精确。
- **3D 模型导入**：修正骨架层级内非关节节点处理；旧文件保持旧行为，新文件（无 .import）用新行为；旧文件要新行为需改 Import dock 的 Naming Version。
- **Core**：`Resource.duplicate(true)` 只复制资源文件内部的资源，外部引用资源不再复制；旧行为用 `duplicate_deep(DEEP_DUPLICATE_ALL)`。
- **Core**：`ProjectSettings.add_property_info()` 对缺失/无效键（含 `usage`）从静默忽略改为警告；改用 `set_as_basic()` / `set_restart_if_changed()` / `set_as_internal()`。
- **Navigation**：region 默认异步更新（`navigation/world/region_use_async_iterations` 可关，有线程同步延迟代价）；navmesh 合并处理顺序变化，原布局错误会更显眼（`navigation/2d_or_3d/merge_rasterizer_cell_scale` 调小增加栅格精度，最小 0.01）。
- **Physics**：Jolt 下 `Area3D` 与静态体重叠默认必报（`physics/jolt_physics_3d/simulation/areas_detect_static_bodies` 已移除），需靠碰撞层/掩码规避。
- **Text**：`add_image` / `update_image` 旧参数 `size_in_percent` 自动映射为 `width_in_percent`，`height_in_percent` 默认 `false`——依赖旧百分比行为需显式传两参。
- `[仅 C#]` `StringExtensions.PathJoin` 空串/前导分隔符处理修正；`GetExtension` 无扩展名时返回空串；`Quaternion(Vector3, Vector3)` 构造修正最短弧。

### 4.4 默认值变更

官方 4.5 迁移指南**无默认值变更章节**（无条目）。

## 5. Godot 4.6（2026-01-26 发布，4.5→4.6）

### 5.1 新特性策展精选（非全量；全量见 release 页与 changelog）

- **编辑器**：新 "Modern" 主题默认（灰阶无蓝偏）；底板统一进停靠系统（可移动/浮动）；拖资源入脚本生成 `@export`；运行时加减速按钮；Output 面板错误点击跳转；ObjectDB 快照对比查泄漏；Quick Open 实时预览；3D 选择/变换模式解耦；旋转 Gizmo 视角轴手柄；GridMap Bresenham 连线。
- **Core**：unique node IDs（重命名/移动节点不断引用）；LibGodot（引擎作为库嵌入应用）。
- **2D**：TileMap 场景瓦片可旋转（90°）。
- **GUI**：`pivot_offset_ratio`（按比例设 Control 枢轴）；鼠标/键盘焦点分离；MarginContainer 边距可视化。
- **动画/3D**：新 IK 框架（`IKModifier3D` + `TwoBoneIK3D`/`SplineIK3D`/`FABRIK3D`/`CCDIK3D`/`JacobianIK3D`）；SSR 大改（粗真度+性能，支持半分辨率）；网格自动生成 CollisionShape3D。
- **脚本**：调试器 Step Out；Tracy/Perfetto/Instruments 追踪分析器；字符串占位符高亮；LSP BBCode→Markdown 改进。
- **导出/平台**：patch PCK delta 编码（增量补丁）；Windows 新项目默认 D3D12；Android：scrcpy 运行导出、GABE Gradle 构建、SAF 细粒度存储访问；手柄 LED 自定义奠基。
- **其他**：GDExtension 接口改 JSON 定义、参数可标 required；Glow 默认值大改（见 5.3）；八面体贴图反射探针；Betsy GPU 导入提速 2 倍；LOD 组件修剪。
- **官方 highlights 审计补记（2026-09-03，与 release 页逐条对表后补收）**：AgX tonemapper 参数开放、3D 材质去带纹 + Mobile HDR 精度、Mali/Adreno 崩溃修复（Rendering）；CSV 翻译 context/plural 列与模板生成、C# 翻译解析（i18n）；OpenXR 1.1、Spatial Entities、Android XR 编辑器（XR）；EditorSettings 自定义快捷键注册；下划线信号在补全/文档中隐藏；Jolt 对新建 3D 项目设为默认（已录 5.4 默认值表）。

### 5.2 Breaking changes 全量镜像

Core：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| FileAccess | `create_temp` 的 `mode_flags` `int`→`ModeFlags` | ✔️ | ✔️(compat) | GH-114053 |
| FileAccess | `get_as_text` 移除 `skip_cr` 参数 | ⚠ | ✔️(compat) | GH-110867 |
| Performance | `add_custom_monitor` 新增可选 `type` | ✔️ | ✔️(compat) | GH-110433 |

Animation（全部 GDScript ✔️，C# ❌，GH-110767）：

| 类 | 变更 |
| --- | --- |
| AnimationPlayer | `assigned_animation` / `autoplay` / `current_animation`：`String`→`StringName`；`get_queue` 返回 `PackedStringArray`→`StringName[]`；信号 `current_animation_changed` 参数同变 |

3D（GDScript ✔️，C# ❌，GH-110120）：

| 类 | 变更 |
| --- | --- |
| SpringBoneSimulator3D | 6 个方法的枚举类型移至 `SkeletonModifier3D`：`get_end_bone_direction`、`get_joint_rotation_axis`、`get_rotation_axis`（返回类型）；`set_end_bone_direction`、`set_joint_rotation_axis`、`set_rotation_axis`（参数类型），`BoneDirection`/`RotationAxis` |

Rendering：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| DisplayServer | `accessibility_create_sub_text_edit_elements` 新增可选 `is_last_line` | ✔️ | ✔️(compat) | GH-113459 |
| DisplayServer | `tts_speak` 的 `utterance_id` 元数据 int32→int64 | ✔️ | ✔️(compat) | GH-112379 |

GUI nodes：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| Control | `grab_focus` 新增可选 `hide_focus` | ✔️ | ✔️(compat) | GH-110250 |
| Control | `has_focus` 新增可选 `ignore_hidden_focus` | ✔️ | ✔️(compat) | GH-110250 |
| FileDialog | `add_filter` 新增可选 `mime_type` | ✔️ | ✔️(compat) | GH-111439 |
| LineEdit | `edit` 新增可选 `hide_focus` | ✔️ | ✔️(compat) | GH-111117 |
| SplitContainer | `clamp_split_offset` 新增可选 `priority_index` | ✔️ | ✔️(compat) | GH-90411 |

Networking（方法上移基类，GDScript ✔️，GH-107954）：

| 类 | 变更 |
| --- | --- |
| StreamPeerTCP | `disconnect_from_host`、`poll` → `StreamPeerSocket`；`get_status` → `StreamPeerSocket`（C# 返回类型 ❌） |
| TCPServer | `is_connection_available`、`is_listening`、`stop` → `SocketServer` |

OpenXR：

| 类 | 变更 | GDScript | PR |
| --- | --- | --- | --- |
| OpenXRExtensionWrapper | `_get_requested_extensions` 新增 `xr_version` 参数 | ❌ | GH-109302 |
| OpenXRExtensionWrapper | `_set_instance_create_info_and_get_next_pointer` 新增 `xr_version` 参数 | 不暴露给脚本（N/A） | GH-109302 |

Editor：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| EditorExportPreset | `get_script_export_mode` 返回 `int`→`ScriptExportMode` | ✔️ | ❌ | GH-107167 |
| EditorFileDialog | 17 个方法上移基类 `FileDialog`：`add_filter`、`add_option`、`clear_filename_filter`、`clear_filters`、`get_filename_filter`、`get_line_edit`、`get_option_default`、`get_option_name`、`get_option_values`、`get_selected_options`、`get_vbox`、`invalidate`、`popup_file_dialog`、`set_filename_filter`、`set_option_default`、`set_option_name`、`set_option_values` | ✔️ | 部分 ❌ | GH-111212 |
| EditorFileDialog | `add_side_menu` 移除 | ❌(stub) | ❌(stub) | GH-111162 |
| EditorFileDialog | 9 个属性上移：`access`、`current_dir`、`current_file`、`current_path`、`display_mode`、`file_mode`、`filters`、`option_count`、`show_hidden_files`（C# 侧 `access`/`display_mode`/`file_mode` ❌） | ✔️ | 部分 ❌ | GH-111212 |
| EditorFileDialog | 4 个信号上移：`dir_selected`、`filename_filter_changed`、`file_selected`、`files_selected`（C# ❌） | ✔️ | ❌ | GH-111212 |

### 5.3 行为变更全量镜像

- **Android**：导出模板 source sets 对齐 Android Studio 结构——`android/build/src/` → `android/build/src/main/java/`，manifest 与 assets 移入 `src/main/`（如 `GodotApp.java` 从 `src/com/godot/game/` 移到 `src/main/java/com/godot/game/`）。
- **Core（场景文件格式）**：`.tscn/.scn` 不再写入 `load_steps`（编辑器本就不用它，GH-103352）；写入 unique node IDs（GH-106837）。前后向兼容（4.5 场景 4.6 可读，反之亦可），**但首次用 4.6+ 保存旧场景 git diff 很大，属预期**。标准动作：`Project > Tools > Upgrade Project Files...` 一次升级全部并单独提交，避免日后编辑场景时反复大 diff。
- **Rendering（Glow）**：默认混合改 Screen（比旧 Soft Light 明显更亮），多个 glow 默认值重配，升级后大概率要重调 Environment glow；Soft Light 现在恒按 `use_hdr_2d` 的旧行为（GH-109971）；Mobile renderer glow 整体重写观感不同（GH-110077）。
- **Rendering（体积雾）**：混合更物理正确、多数场景更亮，需降雾密度/亮度或 `Volumetric Fog Energy`（GH-112494）。
- **Navigation**：`AStar2D.get_point_path`、`AStar3D.get_point_path`、`AStarGrid2D.get_id_path`、`AStarGrid2D.get_point_path` 在 `from_id` 为 disabled/solid 点时返回空路径（GH-113988）。

### 5.4 默认值变更全量镜像

| 类 | 属性 | 旧 | 新 | PR |
| --- | --- | --- | --- | --- |
| ProjectSettings | `rendering/rendering_device/driver.windows`（**仅新建项目**） | Vulkan | D3D12 | GH-113213 |
| ProjectSettings | `physics/3d/physics_engine`（**仅新建项目**） | Godot Physics | Jolt | GH-105737 |
| MeshInstance3D | `skeleton` | `NodePath("..")` | `NodePath("")` | GH-112267（需旧行为开 `animation/compatibility/default_parent_skeleton_in_mesh_instance_3d`） |
| ProjectSettings | `rendering/reflections/sky_reflections/roughness_layers` | 8 | 7 | GH-107902 |
| ProjectSettings | `rendering/rendering_device/d3d12/agility_sdk_version` | 613 | 618 | GH-114043 |
| Environment | `glow_blend_mode` | 2（Soft Light） | 1（Screen） | GH-110671 |
| Environment | `glow_intensity` | 0.8 | 0.3 | GH-110671 |
| Environment | `glow_levels/2` | 0.0 | 0.8 | GH-110671 |
| Environment | `glow_levels/3` | 1.0 | 0.4 | GH-110671 |
| Environment | `glow_levels/4` | 0.0 | 0.1 | GH-110671 |
| Environment | `glow_levels/5` | 1.0 | 0.0 | GH-110671 |
| Environment | `ssr_depth_tolerance` | 0.2 | 0.5 | GH-111210 |
| PopupMenu | `submenu_popup_delay` | 0.3 | 0.2 | GH-110256 |
| ResourceImporterCSVTranslation | `compress` | true | 1 | GH-112073 |

## 6. Godot 4.7（2026-06-18 发布，4.6→4.7）

### 6.1 新特性策展精选（非全量；全量见 release 页与 changelog）

- **GDScript/动画**：`Tween.tween_await()`（等待信号再继续）。
- **2D**：`CollisionShape2D` 新增 `one_way_collision_direction`（单面碰撞方向任意）；`DrawableTexture2D`（官方 API 直接画纹理，替代 Viewport hack）；`GradientTexture2D.FILL_CONIC`；`TextureRect` 支持 AtlasTexture 平铺；2D Scene Paint Mode（B 键散布场景）。
- **GUI**：Control `offset_transform_*`（容器子节点变换动画不被重排覆盖，类 CSS transform，默认纯视觉不影响命中）；Tree 拖放位置指示；PopupMenu 搜索栏；RichTextLabel 图片随字号缩放（`height=1em`）；最近邻 3D 缩放选项。
- **输入**：内置 `VirtualJoystick`（Fixed/Dynamic/Following）；键盘/鼠标设备 ID 常量；手柄陀螺仪（陀螺瞄准）；iOS 手柄改 SDL3；失焦忽略手柄开关。
- **渲染**：HDR 输出（Windows/macOS/iOS/visionOS/Wayland）；`AreaLight3D`（矩形面光源）；粒子 3D 缩放/旋转增强；clearcoat 对齐 Disney PBR。
- **平台/生态**：Asset Store 取代 Asset Library（评分/线程化）；GABE 稳定（安卓端完整导出发布）；安卓画中画、内嵌窗口可移动缩放、GDScript 实现 Java 接口；分平台下载导出模板；文本 shader 编辑器实时内联预览；编辑器：双击 F 跟随移动物体、3D 顶点吸附（B）、轨道球旋转、CSG 自动平滑、路径点吸附碰撞体、MeshLibrary 专用编辑器、Inspector 分组复制粘贴；GDExtension 在项目设置中列出；Wayland 触摸。
- **官方 highlights 审计补记（2026-09-03，与 release 页逐条对表后补收）**：3D 标尺向量测量、创建对话框过滤、项目版本差异图标、远程 Inspector 折叠/枚举显示、单等宽字体符号、脚本列表快速定位、统一 3D 视角控制器（编辑器）；逐 pass 独立 Environment uniform buffer（Rendering 内部优化）；Vulkan 亚采样图、composition layer 增强、动作映射简化、Android XR + Steam Frame 首日支持（XR）；无障碍 landmark 导航；安卓启动屏自定义、Perfetto 默认追踪、脚本编辑器横竖屏（平台）。

### 6.2 Breaking changes 全量镜像

Core：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| Object | `is_class` 参数 `String`→`StringName` | ✔️ | ✔️(compat)/✔️ | GH-118582 |
| ZIPPacker | `start_file` 新增可选 `permissions`、`modified_time` | ✔️ | ✔️(compat)/✔️ | GH-115946 |
| OptimizedTranslation | `generate` 返回 `void`→`bool` | ✔️ | ❌/✔️ | GH-119563 |

2D / 3D：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| CPUParticles2D / GPUParticles2D / CPUParticles3D / GPUParticles3D | `request_particles_process` 新增可选 `process_time_residual` | ✔️ | ✔️(compat)/✔️ | GH-109142 |

GUI nodes：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| Control | `accessibility_live` 类型 `DisplayServer.AccessibilityLiveMode`→`AccessibilityServer.AccessibilityLiveMode` | ✔️ | ❌ | GH-116839 |
| RichTextLabel | 枚举 `ImageUpdateMask.UPDATE_WIDTH_IN_PERCENT` 更名 `UPDATE_WIDTH_UNIT` | ❌ | ✔️ | GH-112617 |
| RichTextLabel | `add_image` / `update_image`：`width`/`height` `int`→`float`（4 条） | ✔️ | ✔️(compat)/✔️ | GH-112617 |
| RichTextLabel | `add_image` / `update_image`：`width_in_percent`/`height_in_percent` 更名 `width_unit`/`height_unit` 且 `bool`→`ImageUnit`（4 条） | ✔️ | 源码级 ❌ | GH-112617 |

Text：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| Font | `find_variation` 新增可选 `palette_index`、`custom_colors` | ✔️ | ✔️(compat)/✔️ | GH-117149 |
| TreeItem | `select` 新增可选 `set_as_cursor` | ✔️ | ✔️(compat)/✔️ | GH-119367 |

Rendering：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| Image | `save_exr` / `save_exr_to_buffer` 新增可选 `color_image`、`max_linear_value` | ✔️ | ✔️(compat)/✔️ | GH-117800 |
| ImageTexture / PortableCompressedTexture2D | `get_format` 上移基类 `Texture2D` | ✔️ | ✔️ | GH-109004 |
| RenderingServer | `particles_request_process_time` 参数 `time`→`process_time` 并新增可选 `process_time_residual` | ✔️ | ✔️(compat)/❌ | GH-109142 |
| RenderingServer | `viewport_set_size` 新增可选 `view_count` | ✔️ | ✔️(compat)/✔️ | GH-115799 |

Animation：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| Animation | `length` 元数据 `float`→`double` | ✔️ | ❌ | GH-116394 |
| AnimationNodeBlendSpace1D / 2D | `add_blend_point` 新增可选 `name` | ✔️ | ✔️(compat)/✔️ | GH-110369 |

Physics / Audio：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| PhysicsServer2D | `body_set_shape_as_one_way_collision` 新增可选 `direction` | ✔️ | ✔️(compat)/✔️ | GH-104736 |
| PhysicsServer2DExtension | `_body_set_shape_as_one_way_collision` 新增 `direction` 参数（覆写签名变） | ❌ | ❌ | GH-104736 |
| AudioEffectSpectrumAnalyzer | `tap_back_pos` 属性移除 | ❌ | ❌ | GH-114355 |

XR / Editor：

| 类 | 变更 | GDScript | C# | PR |
| --- | --- | --- | --- | --- |
| OpenXRExtensionWrapper | `_on_register_metadata` 新增 `interaction_profile_metadata` 参数 | ❌ | ❌ | GH-117399 |
| OpenXRSpatialAnchorCapability | `create_new_anchor` 新增可选 `next` | ✔️ | ✔️(compat)/✔️ | GH-118128 |
| EditorSceneFormatImporter | 7 个 `IMPORT_*` 常量移入 `ImportFlags` 枚举：`IMPORT_ANIMATION`、`IMPORT_DISCARD_MESHES_AND_MATERIALS`、`IMPORT_FAIL_ON_MISSING_DEPENDENCIES`、`IMPORT_FORCE_DISABLE_MESH_COMPRESSION`、`IMPORT_GENERATE_TANGENT_ARRAYS`、`IMPORT_SCENE`、`IMPORT_USE_NAMED_SKIN_BINDS` | ✔️ | ❌ | GH-115788 |
| EditorVCSInterface | `_commit` 新增 `amend` 参数（覆写签名变） | ❌ | ❌ | GH-117968 |

### 6.3 行为变更全量镜像

- **Animation**：`AnimationNodeBlendSpace1D/2D` 布尔 `sync` 被 `SyncMode` 枚举取代；升级后混合过渡异常先查各 blend space 的 `sync_mode`。
- **Rendering**：`LinearToSRGB` 视觉 shader 节点在 Mobile/Forward+ 下不再 clamp 到 [0,1]（GH-113956）。
- **Rendering**：`CanvasItem` 画线不再附加抗锯齿羽化（GH-105122）——线更细，依赖旧观感需显式加大 `width`。
- **Physics（音频相关）**：`AudioStreamPlayer` 的 `area_mask` 默认 1→0（GH-107679）。用 `Area2D`/`Area3D` 的 `audio_bus_override` 且原来就用默认掩码（仅 layer 1）的，必须手动把掩码设回 layer 1，否则总线覆写失效；掩码本来就非 layer 1 的不受影响。【2026-09-03 ClassDB 实测注记】4.7.2 中非定位 `AudioStreamPlayer` **无** `area_mask` 属性（仅 `AudioStreamPlayer2D/3D` 有）；官方指南此处措辞泛指 AudioStreamPlayer 系列，实际默认值变更作用于定位变体——以 ClassDB 实测为准。
- **Physics（Jolt，3D）**：`WorldBoundaryShape3D.plane.d` 符号约定对齐 Godot（与 4.6 相反，需自行翻转，GH-118948）；`SoftBody3D` 默认质量改为整体 1kg（原每点 1kg，GH-116041）；`SoftBody3D.linear_stiffness` 语义更贴近 Godot Physics，全部实例需重新调参（GH-116041）；`Area3D` 开始报告与 `SoftBody3D` 的重叠（GH-114198）。
- **Input**：鼠标/键盘事件 `InputEvent.device` 从 `0` 改为 `InputEvent.DEVICE_ID_MOUSE` / `InputEvent.DEVICE_ID_KEYBOARD` 常量（GH-116274）——任何 `device == 0` 判断失效，改按类型判断或比较常量。
- **GDScript**：对 Packed Array 的**元素**赋值不再触发整属性的 setter（GH-113228）——依赖 setter 副作用的属性封装会静默失效。
- **GDScript**：override 继承父方法签名时同时继承返回类型，重写方法缺少显式 `return` 直接编译报错（GH-115763）——修复：补 `return null` 或正确返回值。
- **平台**：运行引擎的 macOS 最低版本 10.13→11 (Big Sur)。

### 6.4 默认值变更全量镜像

| 类 | 属性 | 旧 | 新 | PR |
| --- | --- | --- | --- | --- |
| ProjectSettings | `display/window/stretch/mode` + `aspect`（**仅新建项目**） | `disabled` + `keep` | `canvas_items` + `expand` | 官方指南注记 |
| LookAtModifier3D | `relative` | true | false | 官方指南 |
| ProjectSettings | `rendering/reflections/sky_reflections/roughness_layers` | 7 | 8 | 官方指南 |
| RichTextLabel | `add_image`/`update_image` 的 `width_in_percent`/`height_in_percent`（4 处） | false | 0（ImageUnit 枚举） | 官方指南 |
| ResourceImporterDynamicFont | `hinting` | 1 | 3 | 官方指南（动态字体默认渲染变清晰，UI 观感可能变化） |

## 7. 升级到 4.7.x 的行动清单

1. 打开项目后执行 `Project > Tools > Upgrade Project Files...`，产物**单独一个 commit**（unique node IDs 写入 + load_steps 清理，diff 大属预期）。
2. 全局搜索并修正：`get_as_text(` 带参调用；`instance_set_interpolated` / `instance_reset_physics_interpolation` / `get_rpc_config`；`InputEvent.device == 0` 类比较；`size_in_percent`；`tap_back_pos`。
3. 检查 `draw_line` / `draw_polyline` 等画线代码：4.7 起线变细，按需加宽。
4. 检查依赖 packed array setter 副作用的属性封装；override 方法补 `return`。
5. `Resource.duplicate(true)` 若依赖旧全深拷贝语义 → `duplicate_deep(DEEP_DUPLICATE_ALL)`。
6. TileMapLayer 若做物理：确认 `get_coords_for_body_rid()` 用法（必要时 `physics_quadrant_size = 1`）。
7. 用 `Area2D` 音频总线覆写的，核对 `AudioStreamPlayer.area_mask`。
8. 核对 `display/window/stretch/*` 与动态字体 hinting 观感。
9. **未来若扩展到新子系统**（3D 渲染/Jolt、多人 RPC、音频频谱、XR、C#、Web 导出）：先重读本文件对应子系统分组，再查锁定版本的官方迁移指南与 class reference——本文件按官方子系统全量镜像，理论上不会漏。

## 8. 来源

- Release notes: godotengine.org/releases/4.5/ ・ /4.6/ ・ /4.7/（4.7 stable 2026-06-18）
- 迁移指南（godot-docs 仓库 RST 原文，master 分支，本文档 §4.2–6.4 的镜像底本）：
  - tutorials/migrating/upgrading_to_godot_4.5.rst
  - tutorials/migrating/upgrading_to_godot_4.6.rst
  - tutorials/migrating/upgrading_to_godot_4.7.rst
- 校准测试执行记录：见 §2（盲答→官方页对照，2026-09-03）
