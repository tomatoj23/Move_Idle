// 引用完整性（schema/README.md 规则 4）：
// attribute → 属性注册表；base → 基底 id；family → 各基底 family 值并集；
// droptable → 掉落表 id（含嵌套子表与环检测）；monster → 遭遇与首领；
// 套装成员槽位互不重复、阶梯件数升序且 ≤ 成员数。
interface RefObject {
  rel: string;
  type: string;
  id: string | null;
  value: Record<string, unknown>;
}

type AddIssue = (issue: { type: string; id: string | null; file: string; field: string; reason: string }) => void;

interface BaseInfo {
  slot: unknown;
  family: unknown;
}

interface DroptableEntryEdge {
  fromId: string;
  toId: string;
  rel: string;
  entryIndex: number;
}

export function checkReferences(objects: RefObject[], add: AddIssue): void {
  // ---- 索引：id 注册表 ----
  const attributeIds = new Set<string>();
  const baseIds = new Set<string>();
  const baseInfo = new Map<string, BaseInfo>();
  const familyValues = new Set<string>();
  const droptableIds = new Set<string>();
  const monsterIds = new Set<string>();

  for (const obj of objects) {
    if (obj.id === null) continue; // id 缺失/非法由 schema 与 id 规则报
    switch (obj.type) {
      case "attribute":
        attributeIds.add(obj.id);
        break;
      case "item-base": {
        baseIds.add(obj.id);
        const family = obj.value["family"];
        const slot = obj.value["slot"];
        baseInfo.set(obj.id, { slot, family });
        if (typeof family === "string") familyValues.add(family);
        break;
      }
      case "droptable":
        droptableIds.add(obj.id);
        break;
      case "monster":
        monsterIds.add(obj.id);
        break;
    }
  }

  const dangler = (
    obj: RefObject,
    field: string,
    kind: string,
    registry: Set<string>,
    ref: unknown,
  ) => {
    if (typeof ref !== "string") return; // 类型错误由 schema 报
    if (!registry.has(ref)) {
      add({
        type: obj.type,
        id: obj.id,
        file: obj.rel,
        field,
        reason: `dangling ${kind} reference '${ref}'`,
      });
    }
  };

  const statAmpAttribute = (effect: unknown, field: string, obj: RefObject) => {
    if (typeof effect !== "object" || effect === null) return;
    const e = effect as Record<string, unknown>;
    if (e["type"] === "stat_amp") {
      dangler(obj, field, "attribute", attributeIds, e["attribute"]);
    }
  };

  // 各类型共用的「mods 数组逐项查 attribute 引用」形状（implicit_mods / mods）
  const checkModList = (obj: RefObject, prefix: string, mods: unknown) => {
    if (!Array.isArray(mods)) return;
    mods.forEach((m, i) => {
      if (typeof m === "object" && m !== null) {
        dangler(obj, `${prefix}[${i}].attribute`, "attribute", attributeIds, (m as Record<string, unknown>)["attribute"]);
      }
    });
  };

  // ---- 逐对象检查出边 ----
  const droptableEdges: DroptableEntryEdge[] = [];
  for (const obj of objects) {
    switch (obj.type) {
      case "item-base":
        checkModList(obj, "implicit_mods", obj.value["implicit_mods"]);
        break;
      case "affix": {
        checkModList(obj, "mods", obj.value["mods"]);
        const legendary = obj.value["legendary"];
        if (typeof legendary === "object" && legendary !== null) {
          const effects = (legendary as Record<string, unknown>)["effects"];
          if (Array.isArray(effects)) {
            effects.forEach((e, i) => statAmpAttribute(e, `legendary.effects[${i}].attribute`, obj));
          }
        }
        break;
      }
      case "monster": {
        const stats = obj.value["stats"];
        if (typeof stats === "object" && stats !== null) {
          for (const key of Object.keys(stats as Record<string, unknown>)) {
            dangler(obj, `stats.${key}`, "attribute", attributeIds, key);
          }
        }
        dangler(obj, "drop_table", "droptable", droptableIds, obj.value["drop_table"]);
        break;
      }
      case "monster-modifier":
        checkModList(obj, "mods", obj.value["mods"]);
        break;
      case "droptable": {
        const entries = obj.value["entries"];
        if (Array.isArray(entries)) {
          entries.forEach((e, i) => {
            if (typeof e !== "object" || e === null) return;
            const entry = e as Record<string, unknown>;
            const ref = entry["ref"];
            const kind = entry["type"];
            if (kind === "base") dangler(obj, `entries[${i}].ref`, "base", baseIds, ref);
            else if (kind === "family") dangler(obj, `entries[${i}].ref`, "family", familyValues, ref);
            else if (kind === "droptable") {
              dangler(obj, `entries[${i}].ref`, "droptable", droptableIds, ref);
              if (typeof ref === "string" && typeof obj.id === "string") {
                droptableEdges.push({ fromId: obj.id, toId: ref, rel: obj.rel, entryIndex: i });
              }
            }
          });
        }
        break;
      }
      case "zone": {
        const encounters = obj.value["encounters"];
        if (Array.isArray(encounters)) {
          encounters.forEach((e, i) => {
            if (typeof e === "object" && e !== null) {
              dangler(obj, `encounters[${i}].monster`, "monster", monsterIds, (e as Record<string, unknown>)["monster"]);
            }
          });
        }
        dangler(obj, "boss", "monster", monsterIds, obj.value["boss"]);
        break;
      }
      case "set": {
        const members = obj.value["members"];
        const memberCount = Array.isArray(members) ? members.length : 0;
        if (Array.isArray(members)) {
          members.forEach((m, i) => dangler(obj, `members[${i}]`, "base", baseIds, m));
          // 槽位互不重复（成员基底都存在才有意义；悬空成员已单独报）
          const bySlot = new Map<string, number>();
          members.forEach((m, i) => {
            if (typeof m !== "string" || !baseInfo.has(m)) return;
            const slot = baseInfo.get(m)!.slot;
            if (typeof slot !== "string") return;
            const prev = bySlot.get(slot);
            if (prev === undefined) {
              bySlot.set(slot, i);
            } else {
              add({
                type: obj.type,
                id: obj.id,
                file: obj.rel,
                field: `members[${i}]`,
                reason: `duplicate member slot '${slot}' (members[${prev}] and members[${i}] both use it)`,
              });
            }
          });
        }
        const tiers = obj.value["tiers"];
        if (Array.isArray(tiers)) {
          tiers.forEach((t, i) => {
            if (typeof t !== "object" || t === null) return;
            const tier = t as Record<string, unknown>;
            if (typeof tier["pieces"] === "number") {
              if (memberCount > 0 && tier["pieces"] > memberCount) {
                add({
                  type: obj.type,
                  id: obj.id,
                  file: obj.rel,
                  field: `tiers[${i}].pieces`,
                  reason: `tier pieces ${tier["pieces"]} exceeds member count ${memberCount}`,
                });
              }
              if (i > 0) {
                const prev = (tiers[i - 1] as Record<string, unknown>)["pieces"];
                if (typeof prev === "number" && !(prev < tier["pieces"])) {
                  add({
                    type: obj.type,
                    id: obj.id,
                    file: obj.rel,
                    field: `tiers[${i}].pieces`,
                    reason: `tier pieces must be strictly ascending (tiers[${i - 1}].pieces=${prev}, tiers[${i}].pieces=${tier["pieces"]})`,
                  });
                }
              }
            }
            const effects = tier["effects"];
            if (Array.isArray(effects)) {
              effects.forEach((e, j) => statAmpAttribute(e, `tiers[${i}].effects[${j}].attribute`, obj));
            }
          });
        }
        break;
      }
    }
  }

  // ---- 嵌套掉落表环检测（全局 DFS，back-edge 各报一次）----
  const adjacency = new Map<string, DroptableEntryEdge[]>();
  for (const edge of droptableEdges) {
    const list = adjacency.get(edge.fromId) ?? [];
    list.push(edge);
    adjacency.set(edge.fromId, list);
  }
  const visited = new Set<string>();
  const inStack = new Set<string>();
  const visit = (tableId: string) => {
    visited.add(tableId);
    inStack.add(tableId);
    for (const edge of adjacency.get(tableId) ?? []) {
      if (inStack.has(edge.toId)) {
        add({
          type: "droptable",
          id: edge.fromId,
          file: edge.rel,
          field: `entries[${edge.entryIndex}].ref`,
          reason: `nested droptable cycle detected: '${edge.fromId}' -> '${edge.toId}'`,
        });
      } else if (!visited.has(edge.toId)) {
        visit(edge.toId);
      }
    }
    inStack.delete(tableId);
  };
  for (const tableId of [...droptableIds].sort()) {
    if (!visited.has(tableId)) visit(tableId);
  }
}
