# 内容校验器（#26）

内容数据合法性的**唯一真相**（`CONTEXT.md`「校验器」）：JSON Schema（draft 2020-12，ajv）+ 引用完整性（`schema/README.md` 规则 4）+ id 规则。CLI 与编辑器（#28）共用同一实现，引擎侧只做轻量断言、不重复实现 schema 校验。

## 运行

```sh
# 一次性装机（本目录内）
npm install

# 全库校验（cwd = 仓库根；默认 content/ + schema/）
node tools/validator/src/cli.ts

# 显式路径
node tools/validator/src/cli.ts --content <content目录> --schema <schema目录>
```

Node 要求 >= 24（原生 TS 类型剥离直跑，无构建步骤）。

## 契约

- **stdout**：单行 JSON 报告 `{ok, filesChecked, typeCounts, errors[]}`；每个 error = `{type, id, file, field, reason}`（`type` 为九类型之一或 null，`file` 为相对 content 根的 POSIX 路径，`reason` 英文 ASCII 供批量生成 agent 检索自迭代）。
- **退出码**：`0` 合法；`1` 校验失败（stdout 有结构化错误）；`2` 环境错误（目录不存在、schema 损坏、参数错误——诊断走 stderr，stdout 为空）。

## 校验规则

1. 九类型 schema 校验：attribute / item-base / affix / monster / monster-modifier / droptable / zone / skill / set（类型 id = schema 文件名去 `.json`）。
2. 引用闭合（悬空即失败）：属性（含怪物 stats 键、词缀/套装效果原语）、基底、家族（各基底 `family` 值并集）、掉落表（含嵌套子表 + **环检测**）、怪物（区域遭遇与首领）。
3. 遭遇 `count ∈ [1,5]`；套装成员槽位互不重复；阶梯件数严格升序且 ≤ 成员数。
4. `id` 等于文件名（去 `.json`）且跨类型全局唯一。
5. 已知类型目录之外的 `.json` 文件、非法 JSON、顶层非对象均报错。

## 下游消费路径（跨票接缝）

- **编辑器（#28）**：`import { validateContentLibrary } from "<repo>/tools/validator/src/index.ts"`，传 `{contentDir, schemaDir}` 拿 `ValidationReport`；不要复制实现。
- **批量生成 agent**：写 `content/` 前跑 CLI，`errors[]` 即自迭代输入（上限两轮，见 `docs/design/editor-agent-pipeline.md`）。
- **pre-commit / CI**：`.githooks/pre-commit` 全库校验；`.github/workflows/ci.yml` 的 `content-validator` job 同源兜底。

## 测试

```sh
npm test        # node:test：九类型 / 引用闭合 / 错误结构与退出码 / 真实库守卫
npm run typecheck
```
