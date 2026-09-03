# 编辑器与内容生成/导入管线（agent 联动版）

票 #10 决议文档 · 2026-09-02

> ⚠️ 本文成文于 7 种内容类型时期（文中两处「七类型」）；此后新增 skill 与 set 类型，当前类型清单以 `schema/README.md` 为准。

## 背景与计划变更

原设想：编辑器内置 LLM 批量生成（OpenAI 兼容协议 + 自定义 base_url + api key 本地存放）。

计划变更（用户拍板）：**不再直连 apikey**。按量计价贵；各家 coding plan 订阅实惠但锁定指定 agent。裁定：批量生成能力整体移交 agent harness，编辑器不再持有任何 LLM 集成。

核证事实（2026-09）：

- CodeBuddy IDE：支持 SKILL.md 标准 skills；支持 MCP（Settings 配置、stdio、MCP Market）；有文件读写与命令执行。
- ZCode：智谱 GLM-5.3 官方 Harness（ADE 形态）；MCP 与 Skill 均为一等功能；终端面板 + 文件读写 + 后台命令。
- GLM Coding Plan 类套餐：订阅制，绑定指定编程工具（Claude Code / Cline / ZCode 等），ToS 限定在指定 harness 内使用。

结论：让 agent 在 coding plan 覆盖的 harness 里干活 = 编辑器零 key、零 API 成本。

## 架构总览

三个组件 + 一条协议：

1. **content-authoring skill**（用户自制）：agent 侧的生成工作流规范。本票只钉契约，SKILL.md 本体不在 agent 交付范围。
2. **CLI 校验器**（TS，编辑器包内或独立 tools/validator）：校验唯一真相，双消费者（编辑器 UI 直接 import；agent 走命令行入口）。
3. **编辑器**（`editor/`，Vite + React + TS + Node 本地服务）：浏览 / 修整 / 校验。

**协议 = 文件系统**：agent 直接写 `content/`，git diff 即人工 review 面；编辑器 watch 文件变化自动重校验（反应端，不依赖任何 agent 专属协议）。

## 生成工作流（skill 须遵守的契约）

- 输入上下文：目标类型 schema 全文 + 属性注册表 id 清单 + 已存在同类型 id 清单（`schema/README.md` 既有约定）。
- `attributes` 只读：属性注册表锁手写，agent 不得生成或修改。
- 先校验后落库：生成 → 跑校验 CLI → 结构化错误反馈自迭代，**上限 2 轮** → 全绿才写 `content/`；仍不过的条目丢弃并留清单。
- 文案（name/flavor）中文；id 英文 snake_case；id 即文件名；每对象一个文件。
- `custom` 逃生舱字段照 README 约定：出现即警告呈现。
- 生成任务 brief 模板放 skill 的 references/（例：「生成 20 条 T2 攻击倾向 stat 词缀」）。

## 校验器

- TS 侧单一真相（ADR-0001 双语言税只付在数值层，校验能不重复就不重复）：
  - JSON Schema 校验（ajv，draft 2020-12，schema/ 七类型）。
  - 引用完整性（`schema/README.md` 规则 4：attribute/base/family/droptable/monster 引用闭合，悬空 = 失败）。
  - 跨类型 id 全局唯一（id 即文件名）。
- CLI 入口：`pnpm validate`（或等价命令），退出码 + 结构化错误 JSON 到 stdout，供 agent 自迭代解析。
- 引擎侧（GDScript）加载时只做轻量断言（必需字段与引用存在，失败报错退出），不重复实现 schema 校验。

## 编辑器（MVP 功能集）

- 浏览树：七类型目录 + 对象视图。
- JSON 手编：Monaco 编辑器 + 实时校验错误。
- 全库校验面板：结构化错误列表，点错误跳对应文件。
- 引用跳转：校验器 id 索引现成，点 id 跳到被引用对象（加分项）。
- watch：文件变化自动重校验。

技术形态：Vite + React + TS 前端 + Node 本地服务（文件读写 + 校验服务），`pnpm dev` 一键起。服务职责 = 文件 + 校验，**不做 LLM 代理**。

明确不做：表单编辑（雾区）、LLM 生成 UI、api key 配置、导入按钮（写入 `content/` 由 agent 承担）、内置 git（写文件后 git add/commit/rollback 由用户完成）。

## 质量防线

1. skill 纪律：先校验后落库（契约见上）。
2. pre-commit 全库校验钩子：把「入库数据合法」从纪律升级为硬门槛，防 agent 绕过、防手滑提交非法数据。
3. git 兜底：非法数据即使入库，`git checkout` 即回滚（与「编辑器不内置 git」的站定决策配套）。

## 联动通道扩展（记入地图雾区，按需单开票）

- 编辑器 MCP server：agent 经工具驱动编辑器（写入前强制校验 + UI 实时观察产出）；代价 = 常驻服务 + 每家 agent 各自配置 + 工具集维护 + 批量生成逐对象调用效率低。
- agent CLI headless「生成按钮」：编辑器 shell 出无头 agent 命令，保留一键体验且仍骑 coding plan；前置事实 = 各家无头 CLI 可用性（未核证，ZCode 未见 CLI 文档）。
- 剪贴板任务包：编辑器导出任务包（schema 摘要 + id 清单 + 约束），供无仓库访问的纯聊天 agent；产出回贴编辑器候选框校验入库。兜底通道。
- staging 收件箱：`content/_inbox/` + 编辑器 review/晋升 UI；git diff review 不够用时再开。

## v1 范围外

直连 apikey、编辑器内 LLM 集成、MCP server、表单编辑、内置 git、staging 收件箱。
