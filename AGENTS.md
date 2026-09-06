# AGENTS.md

## Agent skills

### Issue tracker

Issues, specs, and the wayfinder map are GitHub issues; every operation goes through `gh` (issue create / read / list / comment / label / close, and the wayfinding steps: map, child, blocking, claim, resolve). See `docs/agents/issue-tracker.md`.

### Triage labels

Applying or reading a triage label: this repo's label string equals the role name. `docs/agents/triage-labels.md` holds the mapping if the two ever diverge.

### Domain docs

Before exploring the codebase, and before any output that names a domain concept or revisits a recorded decision: `CONTEXT.md` (terms) + `docs/adr/` (decisions), both at the repo root — single-context layout. See `docs/agents/domain.md`.

### Design docs

`docs/design/README.md` routes each implementation task to its owning design doc (task → doc, ticket → doc, plus supersessions). Read it before implementing or revising anything designed there; update it whenever you revise any design doc.

### Content data conventions

Reading or writing `content/` JSON, building content fixtures (especially a deliberately small affix pool), or touching drop / affix filter fields: a missing `allowed_slots` / `allowed_categories` matches everything, not nothing. See `docs/agents/content-data-conventions.md`.

### Godot 4.7 standards

Engine pinned to 4.7.x; agent training data is only reliable through 4.4, so verify rather than recall. Before writing or reviewing GDScript / scenes / shaders, touching project settings or export presets, naming a specific API, property, or class in any repo doc (design docs, ADRs, task plans, `CONTEXT.md`, research notes), or diagnosing a red CI / headless validation run: run the verification flow and hard rules in `docs/agents/godot-standards.md`. Those constraints outrank any task methodology, including skill-provided workflows. Handing a diff to a skill subagent (e.g. the code-review Standards axis): pass that page in its reference list.

### Process audit

The enforcement system is itself validated, not assumed. When work hits a gap in the standards — a fact stated wrong, a lookup that took a wrong path, a pointer that failed to fire, a legal-but-suboptimal choice — and when CI / a compile / a pre-commit hook goes red, the first instance of a new asset type (`.tscn` / `.tres` / `.gdshader` / `addons/`) lands, or you move / roll back / delete a doc (grep every anchor that pointed at it — `sh tools/check-doc-links.sh` does this): classify the miss and feed the fix back per `docs/agents/process-audit.md`. Out-of-band audit runbooks live behind that page.

### Cross-ticket discipline

每票收尾必做：

- **跨票接缝**：本票产出物若会被下游票消费，加一条「下游消费路径」断言（不只验产出物形状），别让下游开工第一天撞格式墙。
- **v1 裁量**（spec / 设计文档未钉的工程判断）：实现时按裁量写 → 关票评论全文记录可否决理由（**持久真相在此**：`.codebuddy/` 被 gitignore、不可评审，不承载真相）→ 收尾回复里单列给用户拍板。
- **票尾复查清单**：账目闭合（断言数对得上）+ 各 section 断言密度（≥10 条，防空样本假绿）+ 逐条 AC 覆盖 + 跨票接缝。

### Windows / PowerShell 环境约束（仅本机；CI 在 Linux）

执行任何 `git` / `gh` / Godot CLI、启动 Godot 编辑器，或任何含中文（非 ASCII）的内容要落盘 / 传出前：先读 `docs/agents/toolchain-win.md`。

## Working conventions

- 提交纪律：`git add` 只加具体路径；提交走 pre-commit 钩子（反模式 lint + 文档互引检查），被拦下就修到过，误报则改钩子与 CI 里的模式；提交前确认改动清单与当前票范围一致（工作区有其它会话遗留改动时用路径限定 diff / review）。
- `.codebuddy/` 被 gitignore：搜索工具查不到其中文件，查证用已知路径直读；需要长期有效、可评审的**规则**落本文件与 `docs/agents/`，状态与日志留在 `.codebuddy/memory/`（`.codebuddy/memory/STATUS.md` 只留当前票 + 上一票的滚动站位，不复制裁量全文）。
- 子代理能力边界：`code-explorer` 无网络、无 `use_skill`、无写文件 → research 类任务 = 子代理出底稿 + 主会话 `web_search` / `web_fetch` 核证落盘。
- Agent skills：运行时 `<available_skills>` 只暴露一部分，不在列表 ≠ 未安装，需要时直接 `use_skill` 按名调用。
- 命令输出必须整体落盘后 grep error，禁止只看末尾或截尾——靠前单元的错误会被吞掉造成假绿。
