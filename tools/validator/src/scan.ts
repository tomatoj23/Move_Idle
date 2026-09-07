// content/ 目录扫描：类型目录映射（schema/README.md 布局）、已知目录之外的 json 识别。
import { readdirSync } from "node:fs";
import { join, relative } from "node:path";

export interface TypeDirSpec {
  type: string;
  dir: string;
  recursive: boolean;
}

// 类型清单 = schema/README.md 的九类型封闭集；type id = schema 文件名去 .json。
export const TYPE_DIRS: readonly TypeDirSpec[] = [
  { type: "attribute", dir: "attributes", recursive: false },
  { type: "item-base", dir: "items/base", recursive: false },
  { type: "affix", dir: "affixes", recursive: true },
  { type: "monster", dir: "monsters", recursive: false },
  { type: "monster-modifier", dir: "monster_modifiers", recursive: false },
  { type: "droptable", dir: "droptables", recursive: false },
  { type: "zone", dir: "zones", recursive: false },
  { type: "skill", dir: "skills", recursive: false },
  { type: "set", dir: "sets", recursive: false },
];

export interface ScannedFile {
  /** 相对 content 根，POSIX 风格 */
  rel: string;
  abs: string;
  type: string;
}

function listAllJson(root: string): { rel: string; abs: string }[] {
  const out: { rel: string; abs: string }[] = [];
  const walk = (dir: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const abs = join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(abs);
      } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".json")) {
        out.push({ rel: toPosix(relative(root, abs)), abs });
      }
    }
  };
  walk(root);
  return out;
}

export function toPosix(p: string): string {
  return p.split("\\").join("/");
}

export interface ScanResult {
  claimed: ScannedFile[];
  unclaimed: string[];
  allCount: number;
}

/**
 * 全库扫描：返回按类型归属的文件（每类内按相对路径排序，保证跨平台确定性）
 * 与落在任何已知类型目录之外的 json 文件（相对路径）。
 */
export function scanContent(contentRoot: string): ScanResult {
  const all = listAllJson(contentRoot);
  const byRel = new Map(all.map((f) => [f.rel, f]));
  const claimed: ScannedFile[] = [];
  for (const spec of TYPE_DIRS) {
    // rel 与 spec.dir 均为 POSIX 风格，直接前缀匹配
    const prefix = spec.dir + "/";
    const files = all
      .filter((f) => {
        if (!f.rel.startsWith(prefix)) return false;
        if (spec.recursive) return true;
        // 非递归：只收该目录直接子文件（无更深的 /）
        return !f.rel.slice(prefix.length).includes("/");
      })
      .sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
    for (const f of files) {
      claimed.push({ rel: f.rel, abs: f.abs, type: spec.type });
      byRel.delete(f.rel);
    }
  }
  return {
    claimed,
    unclaimed: [...byRel.keys()].sort(),
    allCount: all.length,
  };
}
