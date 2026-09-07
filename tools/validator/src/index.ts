// 校验器唯一实现入口：CLI 与编辑器（#28）都从这里 import。
// 职责（#26 AC）：九类型 schema 校验（draft 2020-12）、引用完整性、
// id = 文件名 + 跨类型全局唯一、结构化错误 JSON、由调用方映射退出码。
import { existsSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";
import { scanContent } from "./scan.ts";
import { loadSchemas } from "./schemas.ts";
import { checkReferences } from "./refs.ts";
import type { ErrorObject } from "ajv/dist/2020.js";
import type { ValidationIssue, ValidationReport, ValidatorOptions } from "./types.ts";

interface ParsedObject {
  rel: string;
  type: string;
  id: string | null;
  value: Record<string, unknown>;
}

export function validateContentLibrary(opts: ValidatorOptions): ValidationReport {
  const { contentDir, schemaDir } = opts;
  for (const [label, dir] of [["content", contentDir], ["schema", schemaDir]] as const) {
    if (!existsSync(dir) || !statSync(dir).isDirectory()) {
      throw new Error(`${label} directory not found: ${dir}`);
    }
  }

  const errors: ValidationIssue[] = [];
  const add = (issue: ValidationIssue) => errors.push(issue);

  const bundle = loadSchemas(schemaDir);
  const scan = scanContent(contentDir);

  // 类型目录之外的 json：结构级错误
  for (const rel of scan.unclaimed) {
    add({ type: null, id: null, file: rel, field: "", reason: "json file outside known type directories" });
  }

  // 解析 + schema 校验
  const parsed: ParsedObject[] = [];
  const typeCounts: Record<string, number> = {};
  for (const file of scan.claimed) {
    typeCounts[file.type] = (typeCounts[file.type] ?? 0) + 1;
    let value: unknown;
    try {
      value = JSON.parse(readFileSync(file.abs, "utf8"));
    } catch (err) {
      add({
        type: file.type,
        id: null,
        file: file.rel,
        field: "",
        reason: `invalid JSON: ${err instanceof Error ? err.message : String(err)}`,
      });
      continue;
    }
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      add({ type: file.type, id: null, file: file.rel, field: "", reason: "top-level JSON value is not a JSON object" });
      continue;
    }
    const obj = value as Record<string, unknown>;
    const id = typeof obj["id"] === "string" ? obj["id"] : null;
    parsed.push({ rel: file.rel, type: file.type, id, value: obj });

    const validate = bundle.validators.get(file.type);
    if (!validate) {
      throw new Error(`no schema compiled for content type: ${file.type}`);
    }
    if (!validate(obj)) {
      for (const err of validate.errors ?? []) {
        add({
          type: file.type,
          id,
          file: file.rel,
          field: ajvField(err),
          reason: err.message ?? "schema violation",
        });
      }
    }
  }

  // id = 文件名（去 .json）
  for (const obj of parsed) {
    if (obj.id === null) continue; // 缺失/非字符串 id 由 schema 报
    const expected = basename(obj.rel).replace(/\.json$/i, "");
    if (obj.id !== expected) {
      add({
        type: obj.type,
        id: obj.id,
        file: obj.rel,
        field: "id",
        reason: `id '${obj.id}' does not match filename '${expected}.json'`,
      });
    }
  }

  // 跨类型全局唯一（含同类型重复）；扫描序确定性 → 永远标在第二处
  const firstSeen = new Map<string, string>();
  for (const obj of parsed) {
    if (obj.id === null) continue;
    const prev = firstSeen.get(obj.id);
    if (prev === undefined) {
      firstSeen.set(obj.id, obj.rel);
    } else {
      add({
        type: obj.type,
        id: obj.id,
        file: obj.rel,
        field: "id",
        reason: `duplicate id '${obj.id}' (already defined in ${prev})`,
      });
    }
  }

  // 引用完整性（schema/README.md 规则 4）
  checkReferences(parsed, add);

  errors.sort(byFileFieldReason);
  return { ok: errors.length === 0, filesChecked: scan.allCount, typeCounts, errors };
}

function byFileFieldReason(a: ValidationIssue, b: ValidationIssue): number {
  for (const key of ["file", "field", "reason"] as const) {
    if (a[key] !== b[key]) return a[key] < b[key] ? -1 : 1;
  }
  return 0;
}

function ajvField(err: ErrorObject): string {
  const segs = err.instancePath
    .split("/")
    .filter((s) => s.length > 0)
    .map((s) => s.replace(/~1/g, "/").replace(/~0/g, "~"));
  if (err.keyword === "required" && typeof err.params["missingProperty"] === "string") {
    segs.push(err.params["missingProperty"]);
  }
  if (err.keyword === "propertyNames" && typeof err.params["propertyName"] === "string") {
    segs.push(err.params["propertyName"]);
  }
  let field = "";
  for (const seg of segs) {
    if (/^\d+$/.test(seg)) {
      field += `[${seg}]`;
    } else {
      field += field === "" ? seg : `.${seg}`;
    }
  }
  return field;
}
