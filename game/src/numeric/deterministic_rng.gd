class_name DeterministicRng
extends RefCounted
## 数值层专用确定性随机源：32 位 LCG（Numerical Recipes 常数）+ FNV-1a 种子派生。
## 纯 GDScript 语言内建、零引擎 API——不用引擎 RandomNumberGenerator / hash()，
## 避免引擎版本间行为漂移；同种子序列恒定，是「同输入同输出」与三处同构复用的地基。

const _LCG_A := 1664525
const _LCG_C := 1013904223
const _MASK := 0xFFFFFFFF
const _FNV_OFFSET := 2166136261
const _FNV_PRIME := 16777619
const _FLOAT_SCALE := 16777216.0  # 2^24，取高 24 位映射 [0,1)

var _state := 0


## 从输入部件派生 32 位种子（FNV-1a 逐字节，部件间以 | 分隔）。
## 部件用 str() 归一，String / int 皆可；同部件序列必得同种子。
static func seed_from(parts: Array) -> int:
	var h := _FNV_OFFSET
	for i in parts.size():
		if i > 0:
			for b in "|".to_utf8_buffer():
				h = ((h ^ int(b)) * _FNV_PRIME) & _MASK
		for b in str(parts[i]).to_utf8_buffer():
			h = ((h ^ int(b)) * _FNV_PRIME) & _MASK
	return h


func _init(seed_value: int = 0) -> void:
	_state = seed_value & _MASK


## 返回 [0, 1) 的确定性浮点。LCG 全 32 位状态步进，取高 24 位参与映射
## （低 8 位序列质量弱，弃用）。
func next_float() -> float:
	_state = (_state * _LCG_A + _LCG_C) & _MASK
	return float(_state >> 8) / _FLOAT_SCALE
