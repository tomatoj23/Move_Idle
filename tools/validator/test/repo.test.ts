// 真实内容库守卫：仓库 content/ + schema/ 必须永远全绿（库 API 直连）。
// 任何后续内容提交破坏规则时，这条测试与 pre-commit / CI 三层都会红。
import { test } from "node:test";
import assert from "node:assert/strict";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { validateContentLibrary } from "../src/index.ts";
import { repoRoot, repoSchemaDir } from "./helpers.ts";

test("仓库真实内容库通过全部校验", () => {
  const report = validateContentLibrary({
    contentDir: join(repoRoot(), "content"),
    schemaDir: repoSchemaDir(),
  });
  assert.equal(report.ok, true, JSON.stringify(report.errors, null, 2));
  assert.equal(report.errors.length, 0);
  assert.ok(report.filesChecked >= 39, `filesChecked=${report.filesChecked}`);
  // 九类型封闭集全在库中
  for (const t of ["attribute", "item-base", "affix", "monster", "monster-modifier", "droptable", "zone", "skill", "set"]) {
    assert.ok((report.typeCounts[t] ?? 0) > 0, `type missing from real library: ${t}`);
  }
});
