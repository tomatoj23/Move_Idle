// Wave C：CLI 契约——退出码 0/1/2、stdout 结构化错误 JSON、参数缺省与显式路径。
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makeTempTree, seedValidLibrary, repoSchemaDir, repoRoot, type TempTree } from "./helpers.ts";
import type { ValidationReport } from "../src/types.ts";

const cliPath = join(dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");

function runCli(args: string[], cwd?: string): { status: number | null; stdout: string; stderr: string } {
  const res = spawnSync(process.execPath, [cliPath, ...args], { cwd, encoding: "utf8" });
  return { status: res.status, stdout: res.stdout ?? "", stderr: res.stderr ?? "" };
}

function runOnTree(tree: TempTree, extra: string[] = []): { status: number | null; report: ValidationReport | null; stderr: string } {
  const res = runCli(["--content", tree.root, "--schema", repoSchemaDir(), ...extra]);
  const report = res.stdout.trim().length > 0 ? (JSON.parse(res.stdout) as ValidationReport) : null;
  return { status: res.status, report, stderr: res.stderr };
}

test("合法库：退出码 0，stdout 为单行 JSON 报告", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    const { status, report, stderr } = runOnTree(tree);
    assert.equal(status, 0, stderr);
    assert.ok(report);
    assert.equal(report.ok, true);
    assert.equal(report.errors.length, 0);
    assert.equal(report.filesChecked, 15);
  } finally {
    tree.cleanup();
  }
});

test("非法库：退出码 1，stdout 结构化错误（类型/id/字段/原因齐备）", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("attributes/attr_ghost.json", {
      id: "attr_ghost",
      name: "半残属性",
      // 缺 aggregation（schema 违规）
    });
    tree.write("droptables/dt_dangle.json", {
      id: "dt_dangle",
      name: "悬空表",
      entries: [{ type: "base", ref: "base_ghost", weight: 1 }],
    });
    const { status, report } = runOnTree(tree);
    assert.equal(status, 1);
    assert.ok(report);
    assert.equal(report.ok, false);
    assert.ok(report.errors.length >= 2, JSON.stringify(report.errors, null, 2));
    for (const e of report.errors) {
      assert.equal(typeof e.file, "string");
      assert.equal(typeof e.field, "string");
      assert.equal(typeof e.reason, "string");
      assert.ok(e.type === null || typeof e.type === "string");
      assert.ok(e.id === null || typeof e.id === "string");
    }
    const schemaErr = report.errors.find((e) => e.id === "attr_ghost" && e.field === "aggregation");
    assert.ok(schemaErr, JSON.stringify(report.errors, null, 2));
    const refErr = report.errors.find((e) => e.file === "droptables/dt_dangle.json" && e.field === "entries[0].ref");
    assert.ok(refErr, JSON.stringify(report.errors, null, 2));
  } finally {
    tree.cleanup();
  }
});

test("content 目录不存在：退出码 2，stderr 给原因，stdout 为空", () => {
  const { status, stdout, stderr } = runCli(["--content", "definitely-missing-dir", "--schema", repoSchemaDir()]);
  assert.equal(status, 2);
  assert.equal(stdout, "");
  assert.match(stderr, /content directory not found/);
});

test("未知参数：退出码 2", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    const { status, stderr } = runOnTree(tree, ["--verbose"]);
    assert.equal(status, 2);
    assert.match(stderr, /unknown argument/);
  } finally {
    tree.cleanup();
  }
});

test("缺省参数：cwd 下的 content/ 与 schema/", () => {
  const tree = makeTempTree();
  try {
    // 默认 --content = <cwd>/content，种子须落在该子目录下
    tree.write("content/attributes/attr_x.json", {
      id: "attr_x",
      name: "属性",
      aggregation: "add",
      category: "offense",
    });
    const { status, stdout, stderr } = runCli(["--schema", repoSchemaDir()], tree.root);
    assert.equal(status, 0, stderr);
    const report = JSON.parse(stdout) as ValidationReport;
    assert.equal(report.ok, true);
    assert.equal(report.filesChecked, 1);
  } finally {
    tree.cleanup();
  }
});

test("真实内容库：CLI 端到端退出码 0 且九类型齐", () => {
  const { status, stdout, stderr } = runCli(["--content", join(repoRoot(), "content"), "--schema", repoSchemaDir()], repoRoot());
  assert.equal(status, 0, stderr);
  const report = JSON.parse(stdout) as ValidationReport;
  assert.equal(report.ok, true, JSON.stringify(report.errors, null, 2));
  const types = Object.keys(report.typeCounts).sort();
  assert.deepEqual(types, ["affix", "attribute", "droptable", "item-base", "monster", "monster-modifier", "set", "skill", "zone"]);
});
