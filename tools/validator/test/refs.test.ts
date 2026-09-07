// Wave B：引用完整性（schema/README.md 规则 4）+ 遭遇数量 + 套装槽位/阶梯 + 嵌套掉落表环。
import { test } from "node:test";
import assert from "node:assert/strict";
import { validateContentLibrary } from "../src/index.ts";
import type { ValidationIssue } from "../src/types.ts";
import { makeTempTree, seedValidLibrary, repoSchemaDir, type TempTree } from "./helpers.ts";

function runWithTree(tree: TempTree) {
  return validateContentLibrary({ contentDir: tree.root, schemaDir: repoSchemaDir() });
}

test("悬空属性引用：affix.mods / implicit_mods / stats 键 / 修饰符 / 两处原语", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("affixes/prefix/affix_bad_attr.json", {
      id: "affix_bad_attr",
      name: "悬空词缀",
      kind: "stat",
      position: "prefix",
      mods: [
        { attribute: "attr_ghost", tiers: [{ ilvl: 1, min: 1, max: 2 }] },
        { attribute: "attr_ghost2", tiers: [{ ilvl: 1, min: 1, max: 2 }] },
      ],
    });
    tree.write("items/base/base_bad_imp.json", {
      id: "base_bad_imp",
      name: "悬空固有",
      slot: "weapon",
      category: "sword",
      implicit_mods: [{ attribute: "attr_ghost", value: 1 }],
    });
    tree.write("monsters/mob_bad_stats.json", {
      id: "mob_bad_stats",
      name: "悬空怪物属性",
      stats: { attr_ghost: 1 },
    });
    tree.write("monster_modifiers/mobmod_bad.json", {
      id: "mobmod_bad",
      name: "悬空修饰",
      mods: [{ attribute: "attr_ghost", operation: "add", value: 1 }],
    });
    tree.write("affixes/legendary/affix_bad_amp.json", {
      id: "affix_bad_amp",
      name: "悬空原语",
      kind: "legendary",
      legendary: {
        effects: [{ type: "stat_amp", attribute: "attr_ghost", operation: "add", value: 1 }],
      },
    });
    tree.write("sets/set_bad_amp.json", {
      id: "set_bad_amp",
      name: "悬空套装原语",
      members: ["base_sword", "base_helm", "base_ring"],
      tiers: [
        { pieces: 2, effects: [{ type: "stat_amp", attribute: "attr_ghost", operation: "add", value: 1 }] },
      ],
    });
    const report = runWithTree(tree);
    const dangling = (file: string, field: string) =>
      report.errors.filter((e: ValidationIssue) => e.file === file && e.field === field && /dangling attribute reference 'attr_ghost/.test(e.reason));
    assert.ok(dangling("affixes/prefix/affix_bad_attr.json", "mods[0].attribute").length === 1, JSON.stringify(report.errors, null, 2));
    assert.ok(dangling("affixes/prefix/affix_bad_attr.json", "mods[1].attribute").length === 1);
    assert.ok(dangling("items/base/base_bad_imp.json", "implicit_mods[0].attribute").length === 1);
    assert.ok(dangling("monsters/mob_bad_stats.json", "stats.attr_ghost").length === 1);
    assert.ok(dangling("monster_modifiers/mobmod_bad.json", "mods[0].attribute").length === 1);
    assert.ok(dangling("affixes/legendary/affix_bad_amp.json", "legendary.effects[0].attribute").length === 1);
    assert.ok(dangling("sets/set_bad_amp.json", "tiers[0].effects[0].attribute").length === 1);
    assert.equal(report.ok, false);
  } finally {
    tree.cleanup();
  }
});

test("悬空基底引用：掉落表 base 与套装成员", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("droptables/dt_bad_base.json", {
      id: "dt_bad_base",
      name: "悬空基底表",
      entries: [{ type: "base", ref: "base_ghost", weight: 100 }],
    });
    tree.write("sets/set_bad_member.json", {
      id: "set_bad_member",
      name: "悬空成员",
      members: ["base_sword", "base_helm", "base_ghost"],
      tiers: [{ pieces: 2, effects: [{ type: "stat_amp", attribute: "attr_max_hp", operation: "add", value: 1 }] }],
    });
    const report = runWithTree(tree);
    const dtErr = report.errors.find((e: ValidationIssue) => e.file === "droptables/dt_bad_base.json" && e.field === "entries[0].ref");
    const setErr = report.errors.find((e: ValidationIssue) => e.file === "sets/set_bad_member.json" && e.field === "members[2]");
    assert.ok(dtErr, JSON.stringify(report.errors, null, 2));
    assert.match(dtErr!.reason, /dangling base reference 'base_ghost'/);
    assert.ok(setErr, JSON.stringify(report.errors, null, 2));
    assert.match(setErr!.reason, /dangling base reference 'base_ghost'/);
  } finally {
    tree.cleanup();
  }
});

test("家族引用 = 各基底 family 字段值的并集", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    // 种子里 base_sword 声明家族 sword_long，dt_a 引用它 = 合法。
    // 把 base_sword 的家族改掉后，dt_a 的 family 引用悬空。
    tree.write("items/base/base_sword.json", {
      id: "base_sword",
      name: "长剑",
      slot: "weapon",
      category: "sword",
      family: "hammer_heavy",
      material_tier: 1,
    });
    const report = runWithTree(tree);
    const hits = report.errors.filter((e: ValidationIssue) => e.file === "droptables/dt_a.json" && e.field === "entries[1].ref");
    assert.equal(hits.length, 1, JSON.stringify(report.errors, null, 2));
    assert.match(hits[0]!.reason, /dangling family reference 'sword_long'/);
  } finally {
    tree.cleanup();
  }
});

test("悬空掉落表引用：怪物挂载与嵌套子表", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("monsters/mob_bad_dt.json", {
      id: "mob_bad_dt",
      name: "悬空掉落表怪物",
      stats: { attr_max_hp: 1 },
      drop_table: "dt_ghost",
    });
    tree.write("droptables/dt_bad_nest.json", {
      id: "dt_bad_nest",
      name: "悬空嵌套表",
      entries: [{ type: "droptable", ref: "dt_ghost", weight: 100 }],
    });
    const report = runWithTree(tree);
    const mobErr = report.errors.find((e: ValidationIssue) => e.file === "monsters/mob_bad_dt.json" && e.field === "drop_table");
    const nestErr = report.errors.find((e: ValidationIssue) => e.file === "droptables/dt_bad_nest.json" && e.field === "entries[0].ref");
    assert.ok(mobErr, JSON.stringify(report.errors, null, 2));
    assert.match(mobErr!.reason, /dangling droptable reference 'dt_ghost'/);
    assert.ok(nestErr, JSON.stringify(report.errors, null, 2));
    assert.match(nestErr!.reason, /dangling droptable reference 'dt_ghost'/);
  } finally {
    tree.cleanup();
  }
});

test("悬空怪物引用：区域遭遇与首领", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("zones/zone_bad_mobs.json", {
      id: "zone_bad_mobs",
      name: "悬空怪物区域",
      level: 1,
      encounters: [{ monster: "mob_ghost", count: 1 }],
      boss: "mob_ghost2",
      order: 2,
    });
    const report = runWithTree(tree);
    const enc = report.errors.find((e: ValidationIssue) => e.file === "zones/zone_bad_mobs.json" && e.field === "encounters[0].monster");
    const boss = report.errors.find((e: ValidationIssue) => e.file === "zones/zone_bad_mobs.json" && e.field === "boss");
    assert.ok(enc, JSON.stringify(report.errors, null, 2));
    assert.match(enc!.reason, /dangling monster reference 'mob_ghost'/);
    assert.ok(boss, JSON.stringify(report.errors, null, 2));
    assert.match(boss!.reason, /dangling monster reference 'mob_ghost2'/);
  } finally {
    tree.cleanup();
  }
});

test("遭遇 count 越界（0 与 6）由 schema 拦截", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("zones/zone_bad_count.json", {
      id: "zone_bad_count",
      name: "越界数量",
      level: 1,
      encounters: [
        { monster: "mob_a", count: 0 },
        { monster: "mob_a", count: 6 },
      ],
      boss: "mob_boss",
      order: 2,
    });
    const report = runWithTree(tree);
    const zero = report.errors.find((e: ValidationIssue) => e.file === "zones/zone_bad_count.json" && e.field === "encounters[0].count");
    const six = report.errors.find((e: ValidationIssue) => e.file === "zones/zone_bad_count.json" && e.field === "encounters[1].count");
    assert.ok(zero, JSON.stringify(report.errors, null, 2));
    assert.ok(six, JSON.stringify(report.errors, null, 2));
    // 边界：1 与 5 合法
    tree.write("zones/zone_edge_count.json", {
      id: "zone_edge_count",
      name: "边界数量",
      level: 1,
      encounters: [
        { monster: "mob_a", count: 1 },
        { monster: "mob_a", count: 5 },
      ],
      boss: "mob_boss",
      order: 3,
    });
    const report2 = runWithTree(tree);
    assert.ok(!report2.errors.some((e: ValidationIssue) => e.file === "zones/zone_edge_count.json"), JSON.stringify(report2.errors, null, 2));
  } finally {
    tree.cleanup();
  }
});

test("套装成员槽位互不重复", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("items/base/base_helm.json", {
      id: "base_helm",
      name: "头盔改武器",
      slot: "weapon",
      category: "helm",
      material_tier: 1,
    });
    const report = runWithTree(tree);
    const hits = report.errors.filter((e: ValidationIssue) => e.file === "sets/set_1.json" && /slot/.test(e.reason));
    assert.equal(hits.length, 1, JSON.stringify(report.errors, null, 2));
    assert.equal(hits[0]!.field, "members[1]");
  } finally {
    tree.cleanup();
  }
});

test("成员基底缺失时不做槽位判重（不重复报错不崩溃）", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("sets/set_1.json", {
      id: "set_1",
      name: "试炼",
      members: ["base_sword", "base_helm", "base_ghost"],
      tiers: [{ pieces: 2, effects: [{ type: "stat_amp", attribute: "attr_max_hp", operation: "add", value: 1 }] }],
    });
    const report = runWithTree(tree);
    const setErrs = report.errors.filter((e: ValidationIssue) => e.file === "sets/set_1.json");
    assert.equal(setErrs.length, 1, JSON.stringify(report.errors, null, 2));
    assert.equal(setErrs[0]!.field, "members[2]");
  } finally {
    tree.cleanup();
  }
});

test("套装阶梯：必须严格升序且不超过成员数", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("sets/set_bad_tiers.json", {
      id: "set_bad_tiers",
      name: "坏阶梯",
      members: ["base_sword", "base_helm"],
      tiers: [
        { pieces: 3, effects: [{ type: "stat_amp", attribute: "attr_max_hp", operation: "add", value: 1 }] },
        { pieces: 2, effects: [{ type: "stat_amp", attribute: "attr_max_hp", operation: "add", value: 2 }] },
      ],
    });
    const report = runWithTree(tree);
    const exceed = report.errors.find((e: ValidationIssue) => e.file === "sets/set_bad_tiers.json" && e.field === "tiers[0].pieces");
    const order = report.errors.find((e: ValidationIssue) => e.file === "sets/set_bad_tiers.json" && e.field === "tiers[1].pieces");
    assert.ok(exceed, JSON.stringify(report.errors, null, 2));
    assert.match(exceed!.reason, /exceeds member count 2/);
    assert.ok(order, JSON.stringify(report.errors, null, 2));
    assert.match(order!.reason, /ascending/);
  } finally {
    tree.cleanup();
  }
});

test("嵌套掉落表环：环上每条 back-edge 各报一次", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("droptables/dt_a.json", {
      id: "dt_a",
      name: "常规",
      entries: [
        { type: "base", ref: "base_sword", weight: 60 },
        { type: "droptable", ref: "dt_loop", weight: 20 },
        { type: "droptable", ref: "dt_junk", weight: 20 },
      ],
    });
    tree.write("droptables/dt_loop.json", {
      id: "dt_loop",
      name: "回环",
      entries: [{ type: "droptable", ref: "dt_a", weight: 100 }],
    });
    const report = runWithTree(tree);
    const cycles = report.errors.filter((e: ValidationIssue) => /cycle/.test(e.reason));
    assert.equal(cycles.length, 1, JSON.stringify(report.errors, null, 2));
    assert.equal(cycles[0]!.file, "droptables/dt_loop.json");
    assert.equal(cycles[0]!.field, "entries[0].ref");
  } finally {
    tree.cleanup();
  }
});

test("掉落表自引用：单条 back-edge 报一次", () => {
  const tree = makeTempTree();
  try {
    seedValidLibrary(tree);
    tree.write("droptables/dt_self.json", {
      id: "dt_self",
      name: "自环",
      entries: [{ type: "droptable", ref: "dt_self", weight: 100 }],
    });
    const report = runWithTree(tree);
    const cycles = report.errors.filter((e: ValidationIssue) => /cycle/.test(e.reason));
    assert.equal(cycles.length, 1, JSON.stringify(report.errors, null, 2));
    assert.equal(cycles[0]!.file, "droptables/dt_self.json");
  } finally {
    tree.cleanup();
  }
});
