class_name EncounterSim
extends RefCounted
## 遭遇模拟纯函数：combat-model #1/#3 + multi-monster-encounters #2 + 四效果原语求值（#30）。
## 100ms tick（10 tps）；同 tick 到点先玩家、后怪物按站位序；玩家打最靠前存活怪
## （first-alive），怪物全部攻击玩家；怪物侧减伤 MVP 恒 0（读都不读，combat-model #3）。
## 主击伤害 = max(1, floor(攻击强度 × 技能倍率 × (1−减伤) × 暴击因子 × 元素系数))，
## 暴击每次攻击独立 roll，暴击伤害基准 50（crit_damage 属性可覆盖）。
##
## 效果原语求值（#30，封闭集；传奇词缀经门面收集传入，套装阶梯接入后复用同一求值器）：
## - stat_amp：不在此求值——进 StatAggregator 聚合链（两阶段，加算先乘算后）。
## - proc_on_hit：主击命中且目标仍存活才逐条 roll（依效果序）；额外伤害 =
##   攻击力 × damage_percent% × 效果自带 damage_type 的元素系数，floor 最低 1，
##   不吃暴击，单目标（当前攻击目标）；proc 击杀照常走死亡链。
## - proc_on_kill：怪死亡时逐条 roll（依效果序）；heal 回复 max_hp × amount%
##   （封顶 max_hp；事件模型零变更——heal 无事件）；explode_fire 对「打到的时刻
##   还存活」的场内其余全部怪按站位序结算：攻击力 × amount% × 火焰系数，floor
##   最低 1，不吃暴击；爆炸击杀即再 roll proc_on_kill——连锁允许、无深度上限
##   （multi-monster-encounters #2.2/#2.3，深度天然以同屏怪数为界）。
## - convert_damage：把命中伤害的 from_type 份额按 percent 移交给 to_type（依效果
##   序组合，份额不足即取剩余，不会越过 100%）；有效元素系数 = Σ 份额 × 对应系数；
##   on_attack.element 报最后一个实际转移了份额的转换的 to_type（无生效转换 =
##   技能原生类型）。
##
## 事件模型（载荷封闭，零回调；multi-monster-encounters #2.2）：on_attack / on_kill
## 载荷不变。proc 与爆炸伤害表达为 on_attack，skill 字段携带来源（"proc_on_hit" /
## "explode_fire"）；爆炸击杀的 on_kill.killer = "explode_fire"（来源标注惯例的
## on_kill 侧延伸），玩家直杀（主击与 proc_on_hit 击杀）恒 "player"。事件流统计：
## 连锁次数 = killer=="explode_fire" 的 on_kill 数；群伤目标数 = skill==
## "explode_fire" 的 on_attack 数。
##
## RNG 消耗序（确定性同输入同输出）：每次攻击恒 1 次暴击 roll（crit_chance=0 也
## roll）→ 主击后目标存活时依效果序每条 proc_on_hit 一次 chance roll → 每次死亡
## 依效果序每条 proc_on_kill 一次 chance roll。爆炸对每个目标不再单独 roll（伤害即定）。
## 输入 / 输出全是语言内建容器；随机性只经 DeterministicRng 注入。
##
## 切片与续跑（#33）：budget_ticks = 本次调用最多推进的 tick 数（相对值，< 0 =
## 打完为止）。预算耗尽且胜负未分时返回 result = "in_progress"，附带 resume
## 快照（绝对 tick、玩家当前血量、双方相位、技能冷却、RNG 状态）——瞬态数据，
## 只活在内存里，不入档（save-persistence §3）。续跑时传入 resume：状态原样
## 恢复（玩家血量只按新 max_hp 下钳，不加血——回满只发生在遭遇间），统计层用
## 新 StatTable 求值 = 「下一 tick 起按新属性结算」（换装/升级即时生效）。
## 战斗进度（怪血、相位、冷却）与 RNG 流跨切片连续：切片边界不扰动任何结果。

const MAX_TICKS := 100000  # 引擎常量：tick 预算；超出 = 内容不可收敛，上层必须报错
const BASIC_ATTACK_ID := "basic_attack"
const CRIT_DAMAGE_BASE := 50.0
const DR_CAP := 0.95
const TICKS_PER_SECOND := 10.0
const KILLER_PLAYER := "player"        # 玩家直杀的 on_kill.killer
const KILLER_EXPLODE := "explode_fire"  # 爆炸连锁击杀的 on_kill.killer（来源标签）
const SKILL_PROC_ON_HIT := "proc_on_hit"  # proc 伤害事件的 skill 来源标签
const SKILL_EXPLODE_FIRE := "explode_fire"  # 爆炸伤害事件的 skill 来源标签


## player = {"stats": StatTable, "skills": [内容技能对象，按槽位序],
##           "effects": {"on_hit": [...], "on_kill": [...], "convert": [...]}}
##   效果清单元素 = 门面归一化后的原语载荷（schema 字段，数值已转 float）。
## monsters = [{"id": String, "stats": StatTable}, ...]（站位序）
## resume = 上一次 in_progress 返回的快照子集：{"tick", "player_hp", "pnext",
##   "mons": [{"hp", "next"}...], "cooldown": {skill_id -> tick}}（{} = 全新开打；
##   由门面校验后传入，怪物清单必须与 monsters 一一对应）。
## 返回 {"result": "win"|"lose"|"stalemate"|"in_progress", "duration_ticks": int,
##   "events": Array}，in_progress 另带 "resume" 快照。
static func run(player: Dictionary, monsters: Array, rng: DeterministicRng,
		budget_ticks: int = -1, resume: Dictionary = {}) -> Dictionary:
	var fx: Dictionary = player.get("effects", {})
	var events: Array = []
	var max_hp := float(player["stats"]["max_hp"])
	var pstate := {
		"id": "player",
		"stats": player["stats"],
		"hp": max_hp,
	}
	var mons: Array = []
	var pnext := 0
	var cooldown := {}  # skill_id -> 冷却好时的 tick
	var tick := 0
	if not resume.is_empty():
		tick = int(resume["tick"])
		# 玩家血量原样恢复，只按（换装后可能变化上限的）max_hp 下钳；不加血。
		pstate["hp"] = minf(float(resume["player_hp"]), max_hp)
		pnext = int(resume["pnext"])
		var rmons: Array = resume["mons"]
		for i in monsters.size():
			var m = monsters[i]
			var rh: Dictionary = rmons[i]
			mons.append({
				"id": String(m["id"]),
				"stats": m["stats"],
				"hp": float(rh["hp"]),
				"next": int(rh["next"]),
			})
		var rcd: Dictionary = resume["cooldown"]
		for sid in rcd:
			cooldown[sid] = int(rcd[sid])
	else:
		for m in monsters:
			mons.append({
				"id": String(m["id"]),
				"stats": m["stats"],
				"hp": float(m["stats"]["max_hp"]),
				"next": 0,
			})
	var budget_end := tick + budget_ticks  # budget_ticks < 0 时永不到达
	while true:
		# 预算门：只在「未定胜负且预算耗尽」时挂起；本 tick 内已分胜负则照常收尾
		if budget_ticks >= 0 and tick >= budget_end:
			return {
				"result": "in_progress",
				"duration_ticks": tick,
				"events": events,
				"resume": _snapshot(tick, pstate, pnext, mons, cooldown, rng),
			}
		# 同 tick 多个单位到点：先玩家（multi-monster-encounters #2.1 确定性顺序）
		if pstate["hp"] > 0.0 and pnext <= tick:
			pnext = tick + _interval(pstate["stats"])
			_player_act(tick, player, pstate, mons, cooldown, rng, events, fx)
		# 后怪物按站位序；玩家倒下即刻停手
		for m in mons:
			if pstate["hp"] <= 0.0:
				break
			if m["hp"] > 0.0 and m["next"] <= tick:
				m["next"] = tick + _interval(m["stats"])
				_strike(tick, String(m["id"]), m["stats"], BASIC_ATTACK_ID, 1.0, "physical",
						pstate, float(pstate["stats"].get("damage_reduction", 0.0)), rng, events)
		var all_dead := true
		for m in mons:
			if m["hp"] > 0.0:
				all_dead = false
				break
		if all_dead:
			return {"result": "win", "duration_ticks": tick, "events": events}
		if pstate["hp"] <= 0.0:
			return {"result": "lose", "duration_ticks": tick, "events": events}
		tick += 1
		if tick > MAX_TICKS:
			return {"result": "stalemate", "duration_ticks": tick, "events": events}
	# Unreachable (every loop path returns); satisfies the 4.7 static "all paths
	# return" rule for while-true loops.
	return {"result": "lose", "duration_ticks": tick, "events": events}


## in_progress 快照：战斗进度（绝对 tick、双方相位、冷却、血量）+ RNG 状态。
## 全部是瞬态值，仅供下一次切片调用恢复，不入档。
static func _snapshot(tick: int, pstate: Dictionary, pnext: int, mons: Array,
		cooldown: Dictionary, rng: DeterministicRng) -> Dictionary:
	var mons_snap: Array = []
	for m in mons:
		mons_snap.append({"hp": float(m["hp"]), "next": int(m["next"])})
	return {
		"tick": tick,
		"player_hp": float(pstate["hp"]),
		"pnext": pnext,
		"mons": mons_snap,
		"cooldown": cooldown.duplicate(),
		"rng_state": rng.get_state(),
	}


## 攻击间隔：interval_ticks = max(1, round(10 / attack_speed))（combat-model #1）。
static func _interval(stats: Dictionary) -> int:
	return maxi(1, roundi(TICKS_PER_SECOND / float(stats["attack_speed"])))


## 玩家出手：目标 = 最靠前存活怪；技能「冷却好即放、按槽位序取」，全冷则普攻
## （build-system #2.2）。怪物侧减伤恒 0——玩家攻击不读目标减伤（combat-model #3）。
static func _player_act(tick: int, player: Dictionary, pstate: Dictionary, mons: Array,
		cooldown: Dictionary, rng: DeterministicRng, events: Array, fx: Dictionary) -> void:
	var target = null
	for m in mons:
		if m["hp"] > 0.0:
			target = m
			break
	if target == null:
		return
	var skill_id := BASIC_ATTACK_ID
	var mult := 1.0
	var dtype := "physical"
	for s in player["skills"]:
		var sid := String(s["id"])
		if int(cooldown.get(sid, 0)) <= tick:
			skill_id = sid
			mult = float(s["multiplier"])
			dtype = String(s["damage_type"])
			var cd := int(s["cooldown_ticks"])
			if cd > 0:
				cooldown[sid] = tick + cd
			break
	_player_strike(tick, pstate, target, skill_id, mult, dtype, mons, rng, events, fx)


## 玩家一次出手：主击（暴击 roll + 转换合成系数）→ 目标死亡走死亡链；存活则
## 依效果序逐条 proc_on_hit roll，proc 击杀同样走死亡链。主击致死不 roll
## proc_on_hit：单目标语义下死亡目标不是合法目标，对尸体 roll 只是空转的
## RNG 消耗（v1 澄清，规格「on_attack 时照常 roll」未覆盖击杀帧）。
static func _player_strike(tick: int, pstate: Dictionary, target: Dictionary,
		skill_id: String, mult: float, dtype: String, mons: Array, rng: DeterministicRng,
		events: Array, fx: Dictionary) -> void:
	var crit: bool = rng.next_float() * 100.0 < float(pstate["stats"].get("crit_chance", 0.0))
	var crit_factor := 1.0
	if crit:
		crit_factor = 1.0 + float(pstate["stats"].get("crit_damage", CRIT_DAMAGE_BASE)) / 100.0
	var comp := _compose(dtype, fx.get("convert", []))
	var raw := maxi(1, floori(float(pstate["stats"]["attack_power"]) * mult * crit_factor
			* _blended_coef(pstate["stats"], comp["shares"])))
	events.append({
		"type": "on_attack",
		"attacker": "player",
		"target": String(target["id"]),
		"skill": skill_id,
		"raw_damage": raw,
		"crit": crit,
		"element": String(comp["element"]),
	})
	target["hp"] -= float(raw)
	if target["hp"] <= 0.0:
		_on_death(tick, KILLER_PLAYER, target, pstate, mons, rng, events, fx)
		return
	for e in fx.get("on_hit", []):
		if rng.next_float() * 100.0 >= float(e["chance_percent"]):
			continue
		var praw := maxi(1, floori(float(pstate["stats"]["attack_power"])
				* float(e["damage_percent"]) / 100.0
				* _type_coef(pstate["stats"], String(e["damage_type"]))))
		events.append({
			"type": "on_attack",
			"attacker": "player",
			"target": String(target["id"]),
			"skill": SKILL_PROC_ON_HIT,
			"raw_damage": praw,
			"crit": false,
			"element": String(e["damage_type"]),
		})
		target["hp"] -= float(praw)
		if target["hp"] <= 0.0:
			_on_death(tick, KILLER_PLAYER, target, pstate, mons, rng, events, fx)
			return


## 怪物死亡结算（killer = "player" 直杀 | "explode_fire" 爆炸连锁）：on_kill →
## 依效果序逐条 proc_on_kill roll。heal 即时回血（封顶 max_hp，无事件）；explode_fire
## 遍历全场按站位序结算「打到的时刻还存活」的其他怪，击杀即递归本函数（连锁）。
## victim 死亡后 hp<=0，目标循环的存活判定天然排除尸体与击杀目标本身——不要用
## 字典相等判同一性（GDScript Dictionary == 是深比较）。
static func _on_death(tick: int, killer: String, victim: Dictionary, pstate: Dictionary,
		mons: Array, rng: DeterministicRng, events: Array, fx: Dictionary) -> void:
	events.append({"type": "on_kill", "killer": killer, "victim": String(victim["id"])})
	var on_kill: Array = fx.get("on_kill", [])
	for e in on_kill:
		if rng.next_float() * 100.0 >= float(e["chance_percent"]):
			continue
		var effect := String(e["effect"])
		if effect == "heal_percent_of_max_hp":
			var max_hp := float(pstate["stats"]["max_hp"])
			pstate["hp"] = minf(max_hp, float(pstate["hp"]) + max_hp * float(e["amount_percent"]) / 100.0)
		elif effect == "explode_fire":
			var raw := maxi(1, floori(float(pstate["stats"]["attack_power"])
					* float(e["amount_percent"]) / 100.0
					* _type_coef(pstate["stats"], "fire")))
			for m in mons:
				if float(m["hp"]) <= 0.0:
					continue
				events.append({
					"type": "on_attack",
					"attacker": "player",
					"target": String(m["id"]),
					"skill": SKILL_EXPLODE_FIRE,
					"raw_damage": raw,
					"crit": false,
					"element": "fire",
				})
				m["hp"] -= float(raw)
				if m["hp"] <= 0.0:
					_on_death(tick, KILLER_EXPLODE, m, pstate, mons, rng, events, fx)


## 怪物一次命中玩家：暴击 roll → 乘算因子链（玩家减伤生效，clamp 后封顶 0.95）
## → on_attack（+ 可能的 on_kill）。怪物不携带效果原语（精英修饰符接入遭遇是
## multi-monster-encounters §6 雾区），故无 proc/死亡链。
static func _strike(tick: int, attacker_id: String, atk_stats: Dictionary, skill_id: String,
		mult: float, dtype: String, target: Dictionary, target_dr: float,
		rng: DeterministicRng, events: Array) -> void:
	var crit: bool = rng.next_float() * 100.0 < float(atk_stats.get("crit_chance", 0.0))
	var crit_factor := 1.0
	if crit:
		crit_factor = 1.0 + float(atk_stats.get("crit_damage", CRIT_DAMAGE_BASE)) / 100.0
	var dr := clampf(target_dr / 100.0, 0.0, DR_CAP)
	var raw := maxi(1, floori(float(atk_stats["attack_power"]) * mult * (1.0 - dr)
			* crit_factor * _type_coef(atk_stats, dtype)))
	events.append({
		"type": "on_attack",
		"attacker": attacker_id,
		"target": String(target["id"]),
		"skill": skill_id,
		"raw_damage": raw,
		"crit": crit,
		"element": dtype,
	})
	target["hp"] -= float(raw)
	if target["hp"] <= 0.0:
		events.append({"type": "on_kill", "killer": attacker_id, "victim": String(target["id"])})


## 伤害类型转换合成：从命中原生类型出发，依效果序把 from_type 份额按 percent
## 移交给 to_type（份额不足即取剩余）。返回 {"shares": {类型: 份额}, "element":
## 最后一个实际转移了份额的转换的 to_type（无则原生类型）}。
static func _compose(dtype: String, convert: Array) -> Dictionary:
	var shares := {dtype: 1.0}
	var element := dtype
	for e in convert:
		var from_type := String(e["from_type"])
		var to_type := String(e["to_type"])
		var remain := float(shares.get(from_type, 0.0))
		if remain <= 0.0:
			continue
		var moved := minf(remain, float(e["percent"]) / 100.0)
		shares[from_type] = remain - moved
		shares[to_type] = float(shares.get(to_type, 0.0)) + moved
		element = to_type
	return {"shares": shares, "element": element}


## 有效元素系数：Σ 份额 × 对应类型的元素系数。
static func _blended_coef(stats: Dictionary, shares: Dictionary) -> float:
	var total := 0.0
	for t in shares:
		total += float(shares[t]) * _type_coef(stats, String(t))
	return total


## 类型元素系数：物理恒 1.0（combat-model #3）；元素取聚合后的对应 multiplier
## 属性，无来源 = 1.0 恒等。
static func _type_coef(stats: Dictionary, dtype: String) -> float:
	if dtype == "physical":
		return 1.0
	return float(stats.get(dtype + "_damage_multiplier", 1.0))
