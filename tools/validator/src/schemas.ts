// schema/ 加载与编译：Ajv draft 2020-12，全 schema 同实例注册（common $ref 跨文件解析）。
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { Ajv2020 } from "ajv/dist/2020.js";
import type { SchemaObject, ValidateFunction } from "ajv/dist/2020.js";

export const SCHEMA_ID_PATTERN = /^urn:move-idle:schema:([a-z0-9-]+):v1$/;

export interface SchemaBundle {
  /** 类型 id（schema $id 尾段）→ 编译好的校验函数；common 为纯 $defs 库，无校验函数 */
  validators: Map<string, ValidateFunction>;
}

export function loadSchemas(schemaDir: string): SchemaBundle {
  const ajv = new Ajv2020({ allErrors: true });
  const files = readdirSync(schemaDir).filter((f) => f.toLowerCase().endsWith(".json")).sort();
  const loaded: { typeId: string; id: string }[] = [];
  for (const file of files) {
    const schema = JSON.parse(readFileSync(join(schemaDir, file), "utf8")) as SchemaObject;
    const id = schema.$id;
    if (typeof id !== "string") {
      throw new Error(`schema file without $id: ${file}`);
    }
    const m = SCHEMA_ID_PATTERN.exec(id);
    if (!m) {
      throw new Error(`schema $id does not match urn:move-idle:schema:<type>:v1: ${id} (${file})`);
    }
    ajv.addSchema(schema);
    loaded.push({ typeId: m[1]!, id });
  }
  const validators = new Map<string, ValidateFunction>();
  for (const entry of loaded) {
    if (entry.typeId !== "common") {
      const validate = ajv.getSchema(entry.id);
      if (!validate) {
        throw new Error(`schema failed to compile: ${entry.id}`);
      }
      validators.set(entry.typeId, validate);
    }
  }
  return { validators };
}
