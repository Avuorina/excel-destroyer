# scripts/GameTime.gd
extends Node

const TICK_RATE: int = 20
var tick_time: float = 0.0
var _accum: float = 0.0

# 1 Tick ごとに発火。全計算はこのシグナルに同期させる
signal on_tick(delta_tick: float)

func _process(delta: float) -> void:
	# 時間圧縮やTime Dilationが後でここに入る
	# 例: delta *= time_multiplier
	
	_accum += delta
	var step = 1.0 / TICK_RATE
	
	# ラグ落ち時のスパイラルを防ぐための上限
	var max_ticks = 10 
	var ticks_processed = 0
	
	while _accum >= step and ticks_processed < max_ticks:
		_accum -= step
		tick_time += step
		emit_signal("on_tick", step)
		ticks_processed += 1
