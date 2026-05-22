# scripts/Store.gd
extends Node
# ゲームの全状態を一元管理し、セーブ・ロードを担当する（Reduxライク）

const SAVE_PATH = "user://excel_destroyer_save.json"
const CURRENT_VERSION = 2

var state: Dictionary = {
	"version": CURRENT_VERSION,
	"layer": 0,
	"coins_mag": 0.0,
	"coins_layer": 0,
	"fragments_mag": 0.0,
	"fragments_layer": 0,
	"prestige_count": 0,
	"max_rows": 1,
	"max_columns": 1,
	"purchased_upgrades": [], # ["add_sum", "prod_constant_1"]
	"cells": {} # { "A1": { "type": 0, "val_m": 1.0, "val_l": 0, "func": 0, "inputs": [] } }
}

func save_game() -> void:
	state["version"] = CURRENT_VERSION
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json = JSON.stringify(state, "\t")
		file.store_string(json)
		file.close()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var err = json.parse(content)
		if err == OK:
			var loaded_data = json.data
			if typeof(loaded_data) == TYPE_DICTIONARY:
				_migrate_save(loaded_data)
				_merge_state(loaded_data)
				return true
	return false

# セーブデータのマイグレーション（超重要）
func _migrate_save(loaded: Dictionary) -> void:
	var loaded_ver = loaded.get("version", 1)
	
	if loaded_ver == 1:
		# 旧バージョン(HugeNumber時代)からの移行
		_migrate_v1_to_v2(loaded)
		loaded["version"] = 2
		loaded_ver = 2
		
	if loaded_ver == 2:
		# v2 is current
		pass

func _migrate_v1_to_v2(loaded: Dictionary) -> void:
	# 旧コインデータをHyperNumber形式(mag/layer)に変換
	if loaded.has("coins_mantissa") and loaded.has("coins_exponent"):
		# v1では旧HugeNumberとして保存されていたとする
		var m: float = loaded["coins_mantissa"]
		var e: int = loaded["coins_exponent"]
		var hn = HyperNumber.from_mantissa_exponent(m, e)
		loaded["coins_mag"] = hn.mag
		loaded["coins_layer"] = hn.layer
		loaded.erase("coins_mantissa")
		loaded.erase("coins_exponent")

# セーブデータとデフォルト状態をマージする
func _merge_state(loaded: Dictionary) -> void:
	for key in loaded.keys():
		if state.has(key):
			state[key] = loaded[key]
