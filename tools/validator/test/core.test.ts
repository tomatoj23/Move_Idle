// Wave A：目录扫描 / 类型映射 / id 规则 / schema 违规映射。
import { test } from "node:test";
import assert from "node:assert/strict";
import { validateContentLibrary } from "../src/index.ts";
import type { ValidationIssue } from "../src/types.ts";
import { makeTempTree, seedValidLibrary, repoSchemaDir, SEEDED_FILE_COUNT, type TempTree } from "./helpers.ts";

function runWithTree(tree: TempTree) {
  return validateContentLibrary({ contentDir: tree.root, schemaDir: repoSchemaDir() });
}

test("种子库全绿且九类型计数正确", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    const report = runWithTree(tree);
    assert.equal(report.ok, true, JSON.stringify(report.errors, null, 2));
    assert.equal(report.filesChecked, SEEDED_FILE_COUNT);
    assert.equal(report.errors.length, 0);
    assert.equal(report.typeCounts["attribute"], 2);
    assert.equal(report.typeCounts["item-base"], 3);
    assert.equal(report.typeCounts["affix"], 2);
    assert.equal(report.typeCounts["monster"], 2);
    assert.equal(report.typeCounts["monster-modifier"], 1);
    assert.equal(report.typeCounts["droptable"], 2);
    assert.equal(report.typeCounts["zone"], 1);
    assert.equal(report.typeCounts["skill"], 1);
    assert.equal(report.typeCounts["set"], 1);
    assert.equal(Object.keys(report.typeCounts).length, 9);
  } finally {
    tree.cleanup();
  }
});

test("id 必须等于文件名（去 .json）", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("attributes/wrong_name.json", {
      id: "attr_unique",
      name: "错名属性",
      aggregation: "add",
      category: "offense",
    });
    const report = runWithTree(tree);
    const hits = report.errors.filter((e: ValidationIssue) => e.file === "attributes/wrong_name.json");
    assert.equal(hits.length, 1, JSON.stringify(report.errors, null, 2));
    assert.equal(hits[0]!.type, "attribute");
    assert.equal(hits[0]!.id, "attr_unique");
    assert.equal(hits[0]!.field, "id");
    assert.match(hits[0]!.reason, /filename/);
  } finally {
    tree.cleanup();
  }
});

test("跨类型 id 全局唯一：第二处被标错", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("skills/attr_attack_power.json", {
      id: "attr_attack_power",
      name: "撞名技能",
      multiplier: 2,
      cooldown_ticks: 10,
      damage_type: "physical",
      unlock_level: 1,
    });
    const report = runWithTree(tree);
    const dup = report.errors.filter((e: ValidationIssue) => e.reason.includes("duplicate"));
    assert.equal(dup.length, 1, JSON.stringify(report.errors, null, 2));
    assert.equal(dup[0]!.file, "skills/attr_attack_power.json");
    assert.equal(dup[0]!.id, "attr_attack_power");
    assert.match(dup[0]!.reason, /attributes\/attr_attack_power\.json/);
  } finally {
    tree.cleanup();
  }
});

test("同类型 id 重复同样报错", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("attributes/attr_max_hp_copy.json", {
      id: "attr_max_hp",
      name: "重名属性",
      aggregation: "add",
      category: "defense",
    });
    const report = runWithTree(tree);
    const dup = report.errors.filter((e: ValidationIssue) => e.reason.includes("duplicate"));
    assert.equal(dup.length, 1, JSON.stringify(report.errors, null, 2));
    assert.equal(dup[0]!.file, "attributes/attr_max_hp_copy.json");
  } finally {
    tree.cleanup();
  }
});

test("已知类型目录之外的 json 文件报错", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("stray.json", { id: "stray" });
    tree.write("items/other/thing.json", { id: "thing" });
    const report = runWithTree(tree);
    const stray = report.errors.filter((e: ValidationIssue) => e.file === "stray.json");
    const other = report.errors.filter((e: ValidationIssue) => e.file === "items/other/thing.json");
    assert.equal(stray.length, 1);
    assert.equal(other.length, 1);
    assert.match(stray[0]!.reason, /outside known type directories/);
    assert.match(other[0]!.reason, /outside known type directories/);
  } finally {
    tree.cleanup();
  }
});

test("非法 JSON 文件报结构化错误而非崩溃", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.writeRaw("attributes/broken.json", "{ not json ]");
    const report = runWithTree(tree);
    const hits = report.errors.filter((e: ValidationIssue) => e.file === "attributes/broken.json");
    assert.equal(hits.length, 1);
    assert.equal(hits[0]!.type, "attribute");
    assert.match(hits[0]!.reason, /invalid JSON/);
  } finally {
    tree.cleanup();
  }
});

test("顶层非对象（数组）报错", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("skills/array_doc.json", [1, 2, 3]);
    const report = runWithTree(tree);
    const hits = report.errors.filter((e: ValidationIssue) => e.file === "skills/array_doc.json");
    assert.equal(hits.length, 1);
    assert.match(hits[0]!.reason, /not a JSON object/);
  } finally {
    tree.cleanup();
  }
});

test("schema 违规映射出类型/id/字段/原因", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("attributes/attr_bad.json", {
      id: "attr_bad",
      name: "缺聚合方式的属性",
      category: "offense",
    });
    const report = runWithTree(tree);
    const hits = report.errors.filter((e: ValidationIssue) => e.id === "attr_bad");
    assert.ok(hits.length >= 1, JSON.stringify(report.errors, null, 2));
    const required = hits.find((e: ValidationIssue) => e.field === "aggregation");
    assert.ok(required, JSON.stringify(hits, null, 2));
    assert.equal(required!.type, "attribute");
    assert.match(required!.reason, /required/);
  } finally {
    tree.cleanup();
  }
});

test("schema 违规同时不掩盖 id 规则与引用检查", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("attributes/bad_name.json", {
      id: "attr_bad2",
      name: "又缺又撞名",
    });
    tree.write("skills/attr_bad2.json", {
      id: "attr_bad2",
      name: "撞名技能",
      multiplier: 2,
      cooldown_ticks: 10,
      damage_type: "physical",
      unlock_level: 1,
    });
    const report = runWithTree(tree);
    const schemaErr = report.errors.some((e: ValidationIssue) => e.file === "attributes/bad_name.json" && e.field === "aggregation");
    const idErr = report.errors.some((e: ValidationIssue) => e.file === "attributes/bad_name.json" && /filename/.test(e.reason));
    const dupErr = report.errors.some((e: ValidationIssue) => e.file === "skills/attr_bad2.json" && /duplicate/.test(e.reason));
    assert.ok(schemaErr, JSON.stringify(report.errors, null, 2));
    assert.ok(idErr, JSON.stringify(report.errors, null, 2));
    assert.ok(dupErr, JSON.stringify(report.errors, null, 2));
    assert.equal(report.ok, false);
  } finally {
    tree.cleanup();
  }
});
