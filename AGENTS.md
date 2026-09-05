# AGENTS.md

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (tomatoj23/Move_Idle), operated via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage-role labels; label string equals role name (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Design docs

MVP design decisions index (task-based routing + issue-to-doc lookup + supersession notes): `docs/design/README.md`. Update the index whenever you revise any design doc.

### Godot 4.7 standards

Engine pinned to 4.7.x (ADR-0001); agent training data is only reliable through Godot 4.4. When writing or reviewing GDScript/scenes/shaders, touching project settings or export presets, writing or revising any repo doc that references engine capabilities or APIs (design docs, ADRs, task plans, CONTEXT.md, research notes), using any API that may postdate 4.4, or fixing a red CI validation run: run the verification flow and hard rules in `docs/agents/godot-standards.md` before coding, or before finalizing those docs. Compliance constraints in that page outrank any task methodology (including skill-provided workflows). When handing a diff to a skill subagent (e.g. the code-review Standards axis), include `docs/agents/godot-standards.md` in the reference list you pass it.

### Process audit

The enforcement system itself is validated, not assumed: probe runs, session-export audits, and doc audits follow the runbooks in `docs/agents/process-audit.md` (triggers, checklists, failure-to-fix mapping).

### Cross-ticket discipline

每票收尾必做两件事：①**跨票接缝**——本票产出物若会被下游票消费，加一条「下游消费路径」断言（不只验产出物形状），别让下游开工第一天撞格式墙；②**v1 裁量**（spec / 设计文档未钉的工程判断）三步走——实现时按裁量写、关票评论全文记录可否决理由、收尾回复里单列给用户拍板，同时进 `.codebuddy/memory/STATUS.md`。票尾复查清单：账目闭合（断言数对得上）+ 各 section 断言密度（≥10 条，防空样本假绿）+ 逐条 AC 覆盖 + 跨票接缝。
