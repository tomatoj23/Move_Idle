class_name EncounterSim
extends RefCounted
## 遭遇模拟纯函数：combat-model #1/#3 + multi-monster-encounters #2 的实现。
## 100ms tick（10 tps）；同 tick 到点先玩家、后怪物按站位序；玩家打最靠前存活怪
## （first-alive），怪物全部攻击玩家；怪物侧减伤 MVP 恒 0（读都不读，combat-model #3）。
## 伤害 = max(1, floor(攻击强度 × 技能倍率 × (1−减伤) × 暴击因子 × 元素系数))，
## 暴击每次攻击独立 roll，暴击伤害基准 50（crit_damage 属性可覆盖）。
## 事件载荷封闭（on_attack / on_kill），只带数据、零回调。
## 输入 / 输出全是语言内建容器；随机性只经 DeterministicRng 注入（确定性同输入同输出）。

const MAX_TICKS := 100000  # 引擎常量：tick 预算；超出 = 内容不可收敛，上层必须报错
const BASIC_ATTACK_ID := "basic_attack"
const CRIT_DAMAGE_BASE := 50.0
const DR_CAP := 0.95
const TICKS_PER_SECOND := 10.0


## player = {"stats": StatTable, "skills": [内容技能对象，按槽位序]}
## monsters = [{"id": String, "stats": StatTable}, ...]（站位序）
## 返回 {"result": "win"|"lose"|"stalemate", "duration_ticks": int, "events": Array}
static func run(player: Dictionary, monsters: Array, rng: DeterministicRng) -> Dictionary:
	var events: Array = []
	var pstate := {
		"id": "player",
		"stats": player["stats"],
		"hp": float(player["stats"]["max_hp"]),
	}
	var mons: Array = []
	for m in monsters:
		mons.append({
			"id": String(m["id"]),
			"stats": m["stats"],
			"hp": float(m["stats"]["max_hp"]),
			"next": 0,
		})
	var pnext := 0
	var cooldown := {}  # skill_id -> 冷却好时的 tick
	var tick := 0
	while true:
		# 同 tick 多个单位到点：先玩家（multi-monster-encounters #2.1 确定性顺序）
		if pstate["hp"] > 0.0 and pnext <= tick:
			pnext = tick + _interval(pstate["stats"])
			_player_act(tick, player, pstate, mons, cooldown, rng, events)
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


## 攻击间隔：interval_ticks = max(1, round(10 / attack_speed))（combat-model #1）。
static func _interval(stats: Dictionary) -> int:
	return maxi(1, roundi(TICKS_PER_SECOND / float(stats["attack_speed"])))


## 玩家出手：目标 = 最靠前存活怪；技能「冷却好即放、按槽位序取」，全冷则普攻
## （build-system #2.2）。怪物侧减伤恒 0——玩家攻击不读目标减伤（combat-model #3）。
static func _player_act(tick: int, player: Dictionary, pstate: Dictionary, mons: Array,
		cooldown: Dictionary, rng: DeterministicRng, events: Array) -> void:
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
	_strike(tick, "player", pstate["stats"], skill_id, mult, dtype, target, 0.0, rng, events)


## 一次命中：暴击 roll → 乘算因子链 → on_attack（+ 可能的 on_kill）。
static func _strike(tick: int, attacker_id: String, atk_stats: Dictionary, skill_id: String,
		mult: float, dtype: String, target: Dictionary, target_dr: float,
		rng: DeterministicRng, events: Array) -> void:
	var crit: bool = rng.next_float() * 100.0 < float(atk_stats.get("crit_chance", 0.0))
	var crit_factor := 1.0
	if crit:
		crit_factor = 1.0 + float(atk_stats.get("crit_damage", CRIT_DAMAGE_BASE)) / 100.0
	var element_coef := 1.0
	if dtype != "physical":
		element_coef = float(atk_stats.get(dtype + "_damage_multiplier", 1.0))
	var dr := clampf(target_dr / 100.0, 0.0, DR_CAP)
	var raw := maxi(1, floori(float(atk_stats["attack_power"]) * mult * (1.0 - dr) * crit_factor * element_coef))
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
