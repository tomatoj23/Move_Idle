// 测试公共设施：临时内容树 + 最小合法库种子。
// schema 目录一律指向仓库真实 schema/（单一真相），不给测试复制副本。
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

export function repoRoot(): string {
  // test/ -> validator/ -> tools/ -> repo root
  return join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
}

export function repoSchemaDir(): string {
  return join(repoRoot(), "schema");
}

export interface TempTree {
  root: string;
  write(rel: string, value: unknown): void;
  writeRaw(rel: string, text: string): void;
  cleanup(): void;
}

export function makeTempTree(): TempTree {
  const root = mkdtempSync(join(tmpdir(), "move-idle-validator-"));
  return {
    root,
    write(rel: string, value: unknown) {
      const p = join(root, rel);
      mkdirSync(dirname(p), { recursive: true });
      writeFileSync(p, JSON.stringify(value, null, 2), "utf8");
    },
    writeRaw(rel: string, text: string) {
      const p = join(root, rel);
      mkdirSync(dirname(p), { recursive: true });
      writeFileSync(p, text, "utf8");
    },
    cleanup() {
      rmSync(root, { recursive: true, force: true });
    },
  };
}

// 一套全绿的最小合法库：九类型齐、引用全闭合、套装 3 成员 2 档。
export function seedValidLibrary(tree: TempTree): void {
  tree.write("attributes/attr_attack_power.json", {
    id: "attr_attack_power",
    name: "攻击强度",
    aggregation: "add",
    category: "offense",
  });
  tree.write("attributes/attr_max_hp.json", {
    id: "attr_max_hp",
    name: "生命上限",
    aggregation: "add",
    category: "defense",
  });
  tree.write("items/base/base_sword.json", {
    id: "base_sword",
    name: "长剑",
    slot: "weapon",
    category: "sword",
    family: "sword_long",
    material_tier: 1,
    implicit_mods: [{ attribute: "attr_attack_power", value: 5 }],
  });
  tree.write("items/base/base_helm.json", {
    id: "base_helm",
    name: "头盔",
    slot: "armor",
    category: "helm",
    material_tier: 1,
  });
  tree.write("items/base/base_ring.json", {
    id: "base_ring",
    name: "指环",
    slot: "trinket",
    category: "ring",
    material_tier: 1,
  });
  tree.write("affixes/prefix/affix_sharp.json", {
    id: "affix_sharp",
    name: "锋利",
    kind: "stat",
    position: "prefix",
    mods: [
      {
        attribute: "attr_attack_power",
        tiers: [{ ilvl: 1, min: 1, max: 2 }],
      },
    ],
  });
  tree.write("affixes/legendary/affix_legend.json", {
    id: "affix_legend",
    name: "传奇",
    kind: "legendary",
    legendary: {
      effects: [
        { type: "stat_amp", attribute: "attr_attack_power", operation: "multiply", value: 1.1 },
      ],
    },
  });
  tree.write("monsters/mob_a.json", {
    id: "mob_a",
    name: "小怪",
    stats: { attr_max_hp: 10, attr_attack_power: 2 },
    drop_table: "dt_a",
  });
  tree.write("monsters/mob_boss.json", {
    id: "mob_boss",
    name: "首领",
    stats: { attr_max_hp: 100 },
  });
  tree.write("monster_modifiers/mobmod_swift.json", {
    id: "mobmod_swift",
    name: "迅捷",
    mods: [{ attribute: "attr_attack_power", operation: "add", value: 3 }],
  });
  tree.write("droptables/dt_a.json", {
    id: "dt_a",
    name: "常规",
    entries: [
      { type: "base", ref: "base_sword", weight: 60 },
      { type: "family", ref: "sword_long", weight: 20 },
      { type: "droptable", ref: "dt_junk", weight: 20 },
    ],
  });
  tree.write("droptables/dt_junk.json", {
    id: "dt_junk",
    name: "杂物",
    entries: [{ type: "base", ref: "base_ring", weight: 100 }],
  });
  tree.write("zones/zone_1.json", {
    id: "zone_1",
    name: "小径",
    level: 1,
    encounters: [
      { monster: "mob_a", count: 2 },
      { monster: "mob_a", count: 1 },
    ],
    boss: "mob_boss",
    order: 1,
  });
  tree.write("skills/skill_1.json", {
    id: "skill_1",
    name: "重斩",
    multiplier: 2,
    cooldown_ticks: 10,
    damage_type: "physical",
    unlock_level: 1,
  });
  tree.write("sets/set_1.json", {
    id: "set_1",
    name: "试炼",
    members: ["base_sword", "base_helm", "base_ring"],
    tiers: [
      { pieces: 2, effects: [{ type: "stat_amp", attribute: "attr_max_hp", operation: "add", value: 5 }] },
      { pieces: 3, effects: [{ type: "proc_on_kill", chance_percent: 10, effect: "explode_fire", amount_percent: 50 }] },
    ],
  });
}

export const SEEDED_FILE_COUNT = 15;
