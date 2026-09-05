class_name LootRoller
extends RefCounted
## 掉落三层判定链纯函数（loot-rarity #8 + set-items #18 §3 套装件特例）。
## 击杀是唯一入口：一次 on_kill 走一遍「掉不掉 → 稀有度 → 实例生成」三层 roll。
## 数值层纯函数、零引擎 API、零 IO——在线、离线、编辑器三处同构复用。
## 全部概率与权重是引擎常量（loot-rarity §6），内容只存离散配方数据。
##
## 层一 掉落判定：普通怪 p = DROP_CHANCE_NORMAL；首领 p = 1.0（必掉，不消耗 RNG）。
## 层二 稀有度：四档权重表归一化 roll；首领对传奇档权重 ×LEADER_LEGENDARY_MULTIPLIER。
## 层三 实例生成：
##   - 掉落表按 weight 归一化 roll：droptable 递归、base 直取、family 在「材质
##     达标上限内的家族成员」中均匀 roll（v1 无衰减系数）。
##   - 稀有度决定词缀数量（档内均匀）：普通 0 / 魔法 1~2 / 稀有 3~4 /
##     传奇 = 1 条传奇词缀 + 2~3 条 stat 词缀。
##   - 词缀池 AND 过滤：声明 allowed_slots 则槽位必须命中，声明 allowed_categories
##     则类别必须命中，至少一条档位的 ilvl 门槛 ≤ 装备 ilvl；同一实例不重复同词缀
##     （池被抽干即提前收尾，不多不少也不报错）。
##   - 档位与数值：达标档位中均匀 roll，档内 min~max 均匀分布。v1 不做 ilvl 缩放
##     ——ilvl 只通过档位门槛影响强度（schema 的缩放钩子留给后续版本）。
##   - 传奇词缀数值固定不 roll（效果原语参数不随 ilvl 分档），实例不携带 values。
##   - 套装件：稀有度低于稀有档钳到稀有；显示名恒为专属基底名。
## 层序即 RNG 消费序（票面「先判掉不掉 → 再 roll 稀有度 → 最后生成实例」）：
## 掉落判定 roll → 稀有度 roll → 选基底 → 抽词缀定数值 → 起名字。
## 未生效的设计钩子：loot-rarity §6 的 tier_offset_factor（难度阶稀有度偏移）随
## 难度阶一起归进度票，本票 ilvl 只由区域等级决定。
## 命名（loot-rarity §4）：传奇 = 传奇词缀名；魔法取一条词缀入名，前缀优先；
## 稀有 = 前缀 + 基底 + 后缀（各取其一）；无词缀 = 基底名。position=any 可补任一侧，
## 同一条词缀只占一个位置。

const DROP_CHANCE_NORMAL := 0.20
const DROP_CHANCE_LEADER := 1.0
const RARITY_WEIGHTS := {"normal": 55.0, "magic": 32.0, "rare": 12.0, "legendary": 1.0}
const LEADER_LEGENDARY_MULTIPLIER := 10.0
const RARITY_ORDER := ["normal", "magic", "rare", "legendary"]
const RARITY_AFFIX_COUNT := {"normal": [0, 0], "magic": [1, 2], "rare": [3, 4], "legendary": [2, 3]}
const SET_PIECE_RARITY_FLOOR := "rare"
# 家族材质达标上限：cap = 1 + (ilvl-1) / MATERIAL_TIER_ILVL_STEP，高档材质的
# 出现率由内容供给（高阶区域才配高材质基底），引擎侧不加衰减系数。
const MATERIAL_TIER_ILVL_STEP := 10
const MAX_TABLE_DEPTH := 8  # 嵌套子表深度护栏（自引用表是合法引用，不能无限递归）


## 一次击杀的掉落 roll。
## ctx = {"ilvl": int, "is_leader": bool, "drop_table": String（"" = 无渠道）,
##        "item_bases": {id -> 内容对象}, "affixes": {...}, "droptables": {...},
##        "sets": {...}}
## 返回 {"dropped": bool, "instance": Dictionary | null, "error": String}
## （error 非空 = 内容/配置不合法，调用方必须拒绝，绝不静默继续。）
static func roll_kill(ctx: Dictionary, rng: DeterministicRng) -> Dictionary:
	var table_id := String(ctx.get("drop_table", ""))
	if table_id == "":
		return _no_drop()
	var leader := bool(ctx.get("is_leader", false))
	var chance := DROP_CHANCE_LEADER if leader else DROP_CHANCE_NORMAL
	if chance < 1.0 and rng.next_float() >= chance:
		return _no_drop()
	var ilvl := int(ctx.get("ilvl", 1))
	# 层序 = RNG 消费序：稀有度先于实例生成（票面三层定义）
	var rarity := _roll_rarity(leader, rng)
	var resolved := _roll_base(table_id, ilvl, ctx, rng, 0)
	if String(resolved["error"]) != "":
		return _fail(String(resolved["error"]))
	var base_id := String(resolved["base"])
	var bases: Dictionary = ctx["item_bases"]
	var base_rec: Dictionary = bases[base_id]
	var is_set_piece := _set_id_for_base(base_id, ctx) != ""
	if is_set_piece and _rarity_rank(rarity) < _rarity_rank(SET_PIECE_RARITY_FLOOR):
		rarity = SET_PIECE_RARITY_FLOOR
	var built := _roll_instance(base_rec, rarity, ilvl, is_set_piece, ctx, rng)
	if String(built["error"]) != "":
		return _fail(String(built["error"]))
	return {"dropped": true, "instance": built["instance"], "error": ""}


## 家族材质达标上限（引擎公式，内容只声明 material_tier）。
static func material_tier_cap(ilvl: int) -> int:
	return 1 + maxi(0, floori(float(ilvl - 1) / float(MATERIAL_TIER_ILVL_STEP)))


# ---------------------------------------------------------------- layer 2 / 3

static func _no_drop() -> Dictionary:
	return {"dropped": false, "instance": null, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"dropped": false, "instance": null, "error": message}


static func _rarity_rank(rarity: String) -> int:
	return RARITY_ORDER.find(rarity)


## 掉落表 roll：按 weight 归一化，命中条目按 type 分派。
static func _roll_base(table_id: String, ilvl: int, ctx: Dictionary,
		rng: DeterministicRng, depth: int) -> Dictionary:
	var tables: Dictionary = ctx["droptables"]
	if not tables.has(table_id):
		return {"base": "", "error": "unknown droptable '%s'" % table_id}
	if depth > MAX_TABLE_DEPTH:
		return {"base": "", "error": "droptable nesting deeper than %d at '%s'"
				% [MAX_TABLE_DEPTH, table_id]}
	var entries: Array = tables[table_id]["entries"]
	var weights: Array = []
	for e in entries:
		weights.append(float(e["weight"]))
	var entry: Dictionary = entries[_pick_weighted(weights, rng)]
	var ref_id := String(entry["ref"])
	match String(entry["type"]):
		"base":
			if not (ctx["item_bases"] as Dictionary).has(ref_id):
				return {"base": "", "error": "droptable '%s' points at unknown base '%s'"
						% [table_id, ref_id]}
			return {"base": ref_id, "error": ""}
		"droptable":
			return _roll_base(ref_id, ilvl, ctx, rng, depth + 1)
		"family":
			return _roll_family(table_id, ref_id, ilvl, ctx, rng)
	return {"base": "", "error": "droptable '%s' has an unknown entry type '%s'"
			% [table_id, String(entry["type"])]}


## 家族 roll：ilvl 达标上限内的成员均匀 roll（无衰减系数）。
static func _roll_family(table_id: String, family: String, ilvl: int, ctx: Dictionary,
		rng: DeterministicRng) -> Dictionary:
	var pool := _family_pool(family, ilvl, ctx)
	if pool.is_empty():
		return {"base": "", "error": "family '%s' has no member within the ilvl %d material cap"
				% [family, ilvl]}
	return {"base": String(pool[_rand_index(rng, pool.size())]), "error": ""}


static func _family_pool(family: String, ilvl: int, ctx: Dictionary) -> Array:
	var cap := material_tier_cap(ilvl)
	var pool: Array = []
	var bases: Dictionary = ctx["item_bases"]
	for id in bases:
		var rec: Dictionary = bases[id]
		if String(rec.get("family", "")) != family:
			continue
		if int(rec.get("material_tier", 1)) <= cap:
			pool.append(String(id))
	pool.sort()
	return pool


## 稀有度 roll：四档权重表；首领把传奇档权重放大 LEADER_LEGENDARY_MULTIPLIER 倍。
static func _roll_rarity(leader: bool, rng: DeterministicRng) -> String:
	var weights: Array = []
	for r in RARITY_ORDER:
		var w := float(RARITY_WEIGHTS[String(r)])
		if leader and String(r) == "legendary":
			w *= LEADER_LEGENDARY_MULTIPLIER
		weights.append(w)
	return String(RARITY_ORDER[_pick_weighted(weights, rng)])


## 实例生成：抽词缀、定数值、起名字。rolls 保持抽取顺序（命名依赖它）。
static func _roll_instance(base_rec: Dictionary, rarity: String, ilvl: int,
		is_set_piece: bool, ctx: Dictionary, rng: DeterministicRng) -> Dictionary:
	var rolls: Array = []
	var legend_id := ""
	if rarity == "legendary":
		var legend_pool := _affix_pool("legendary", base_rec, ilvl, ctx)
		if legend_pool.is_empty():
			return {"instance": {}, "error": "no legendary affix is eligible for base '%s'"
					% String(base_rec["id"])}
		legend_id = String(legend_pool[_rand_index(rng, legend_pool.size())])
		rolls.append({"affix": legend_id, "values": []})
	var band: Array = RARITY_AFFIX_COUNT[rarity]
	var want := _rand_int_range(rng, int(band[0]), int(band[1]))
	var pool := _affix_pool("stat", base_rec, ilvl, ctx)
	for _i in want:
		if pool.is_empty():
			break
		var pick := _rand_index(rng, pool.size())
		var affix_id := String(pool[pick])
		pool.remove_at(pick)  # 同一实例不重复同一词缀
		rolls.append(_roll_affix(affix_id, ilvl, ctx, rng))
	return {
		"instance": {
			"base": String(base_rec["id"]),
			"rarity": rarity,
			"ilvl": ilvl,
			"name": _display_name(base_rec, rarity, is_set_piece, legend_id, rolls, ctx),
			"affixes": rolls,
		},
		"error": "",
	}


## 词缀池：kind 分流 + 槽位 / 类别 / 档位门槛 AND 过滤；按 id 排序保证内容顺序无关。
static func _affix_pool(kind: String, base_rec: Dictionary, ilvl: int, ctx: Dictionary) -> Array:
	var slot := String(base_rec["slot"])
	var category := String(base_rec["category"])
	var pool: Array = []
	var affixes: Dictionary = ctx["affixes"]
	for id in affixes:
		var rec: Dictionary = affixes[id]
		if String(rec.get("kind", "")) != kind:
			continue
		if not _filter_ok(rec, "allowed_slots", slot):
			continue
		if not _filter_ok(rec, "allowed_categories", category):
			continue
		if kind == "stat" and not _has_eligible_tier(rec, ilvl):
			continue
		pool.append(String(id))
	pool.sort()
	return pool


static func _filter_ok(rec: Dictionary, field: String, value: String) -> bool:
	var allowed: Array = rec.get(field, [])
	return allowed.is_empty() or allowed.has(value)


static func _has_eligible_tier(rec: Dictionary, ilvl: int) -> bool:
	for mod in rec["mods"]:
		for t in mod["tiers"]:
			if int(t["ilvl"]) <= ilvl:
				return true
	return false


## 词缀实例：每个 mod 独立 roll 档位与数值（达标档位均匀、档内均匀分布）。
static func _roll_affix(affix_id: String, ilvl: int, ctx: Dictionary,
		rng: DeterministicRng) -> Dictionary:
	var rec: Dictionary = ctx["affixes"][affix_id]
	var values := []
	for mod in rec["mods"]:
		var tiers := _eligible_tiers(mod["tiers"], ilvl)
		var tier: Dictionary = tiers[_rand_index(rng, tiers.size())]
		values.append({
			"attribute": String(mod["attribute"]),
			"value": _roll_value(tier, rng),
		})
	return {"affix": affix_id, "values": values}


static func _eligible_tiers(tiers: Array, ilvl: int) -> Array:
	var eligible: Array = []
	for t in tiers:
		if int(t["ilvl"]) <= ilvl:
			eligible.append(t)
	# 池过滤已保证至少一条达标；兜底取最低档，避免空数组下标崩溃。
	if eligible.is_empty():
		eligible.append(tiers[0])
	return eligible


static func _roll_value(tier: Dictionary, rng: DeterministicRng) -> float:
	var lo := float(tier["min"])
	var hi := float(tier["max"])
	return lo + rng.next_float() * (hi - lo)


# ---------------------------------------------------------------- naming

## 显示名：套装件恒为专属基底名；传奇取传奇词缀名；稀有前后缀各一；魔法前缀优先。
static func _display_name(base_rec: Dictionary, rarity: String, is_set_piece: bool,
		legend_id: String, rolls: Array, ctx: Dictionary) -> String:
	var base_name := String(base_rec["name"])
	if is_set_piece:
		return base_name
	if rarity == "legendary":
		return String(ctx["affixes"][legend_id]["name"])
	var words := _name_words(rolls, ctx)
	match rarity:
		"rare":
			if words["prefix"] != "" and words["suffix"] != "":
				return words["prefix"] + "的" + base_name + "之" + words["suffix"]
			if words["prefix"] != "":
				return words["prefix"] + "的" + base_name
			if words["suffix"] != "":
				return base_name + "之" + words["suffix"]
			return base_name
		"magic":
			if words["prefix"] != "":
				return words["prefix"] + "的" + base_name
			if words["suffix"] != "":
				return base_name + "之" + words["suffix"]
	return base_name


## 前后缀用词：各取抽到的第一条；position=any 可补任一侧，同一条只占一个位置。
## 传奇词缀不参与命名（它的 name 是完整装备名，不是前后缀词）。
static func _name_words(rolls: Array, ctx: Dictionary) -> Dictionary:
	var words := {"prefix": "", "suffix": ""}
	var any_words: Array = []
	for r in rolls:
		var rec: Dictionary = ctx["affixes"][String(r["affix"])]
		if String(rec.get("kind", "")) == "legendary":
			continue
		var name := String(rec["name"])
		match String(rec.get("position", "")):
			"prefix":
				if words["prefix"] == "":
					words["prefix"] = name
			"suffix":
				if words["suffix"] == "":
					words["suffix"] = name
			_:
				any_words.append(name)
	for w in any_words:
		if words["prefix"] == "":
			words["prefix"] = w
		elif words["suffix"] == "":
			words["suffix"] = w
	return words


# ---------------------------------------------------------------- rng helpers

## 权重归一化 roll：返回命中的下标。
static func _pick_weighted(weights: Array, rng: DeterministicRng) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := rng.next_float() * total
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if roll < acc:
			return i
	return weights.size() - 1


## [0, count) 均匀下标。
static func _rand_index(rng: DeterministicRng, count: int) -> int:
	return clampi(floori(rng.next_float() * float(count)), 0, maxi(0, count - 1))


## [lo, hi] 闭区间均匀整数。
static func _rand_int_range(rng: DeterministicRng, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + _rand_index(rng, hi - lo + 1)


## 套装归属由 base_id 反查（推导态，不入档；set-items §2）。
static func _set_id_for_base(base_id: String, ctx: Dictionary) -> String:
	var sets: Dictionary = ctx.get("sets", {})
	for sid in sets:
		var members: Array = sets[sid]["members"]
		for m in members:
			if String(m) == base_id:
				return String(sid)
	return ""
