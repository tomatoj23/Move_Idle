# 内容数据 schema v1 约定

本目录是内容数据的唯一合法性来源（单一真相）。数据对象在 `content/` 下，由编辑器（`editor/`，票 #10 实现）与引擎侧加载器消费。

校验器实现落点：`tools/validator/`（CLI 与编辑器共用唯一实现；用法与输出契约见 `tools/validator/README.md`）。

## 目录布局

```
schema/                      ← 本目录：JSON Schema（draft 2020-12）
content/
  attributes/                ← 属性注册表（attribute.schema.json）
  items/base/                ← 装备基底（item-base.schema.json）
  affixes/                   ← 词缀（affix.schema.json），建议按 prefix/suffix/legendary 分子目录
  monsters/                  ← 基础怪物（monster.schema.json）
  monster_modifiers/         ← 怪物修饰符（monster-modifier.schema.json）
  droptables/                ← 掉落表（droptable.schema.json）
  zones/                     ← 区域（zone.schema.json）
  skills/                    ← 技能（skill.schema.json）
  sets/                      ← 套装（set.schema.json）
```

## 核心规则

1. **配方模型**：内容只存配方（基底 + 词缀池 + 掉落权重）。玩家掉落的具体装备是运行时按配方 roll 出的实例，绝不回写 `content/`。
2. **id 即文件名**：每个对象的 `id` 等于其文件名（去 `.json`），snake_case，全局唯一（跨类型也唯一）。
3. **每对象一个文件**：批量操作由工具完成；git diff 按对象可追溯。
4. **引用完整性**：校验器必须检查——`attribute` 引用 → `content/attributes/` 的 id；`base` 引用 → 基底 id；`family` 引用 → 各基底 `family` 字段值的并集；`drop_table`/`droptable` 引用 → 掉落表 id；`encounters[].monster`/`boss` 引用 → monster id；`encounters[].count` ∈ [1,5]；`set.members` 引用 → 基底 id 且各成员 `slot` 互不重复、`tiers[].pieces` ≤ 成员数且升序。悬空引用 = 导入失败。
5. **公式边界**：schema 不含任何数学公式。词缀/怪物只存离散档位与基准区间；ilvl→最终数值的缩放、掉落次数 roll、家族内材质加权等公式全部归引擎（战斗模型票 #7、掉落票 #8 定）。
6. **版本化**：版本住在 schema 的 `$id` 上（`…:v1`）。不兼容变更必须升版本号并写迁移说明；数据对象内不重复携带版本字段。
7. **伤害类型与效果原语是封闭集合**：新增 = schema 版本升级（走 ADR）。

## LLM 批量生成注意事项（编辑器实现时遵守）

- 只允许生成上述九种类型（attribute / item-base / affix / monster / monster-modifier / droptable / zone / skill / set），禁止发明新顶层字段。
- 生成时提供：目标类型 schema 全文 + 属性注册表 id 清单 + 已存在同类型 id 清单（防重、防漂移、防同义属性）。
- 文案（name/flavor）用中文；id 保持英文 snake_case。
- 生成结果先过 JSON Schema 校验 + 引用完整性校验，再写入 `content/`；`custom` 字段内容必须以警告形式呈现给人工。
