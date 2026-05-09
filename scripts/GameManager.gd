# scripts/GameManager.gd
# AutoLoad登録必須:
#   プロジェクト設定 → AutoLoad → scripts/GameManager.gd → 名前: GameManager
extends Node

# --- フェーズ定義 ---
enum GamePhase {
	NORMAL,      # 0〜1回転生: 普通のExcel
	CORRUPTED,   # 2〜4回転生: 壊れかけ
	CRITICAL,    # 5〜9回転生: 崩壊中
	APOCALYPSE   # 10回転生〜: 完全崩壊
}

# --- シグナル ---
signal cells_updated
signal num_error_triggered
signal prestige_done
signal upgrade_applied(id: String)
signal phase_changed(new_phase: GamePhase)

# --- セルデータ ---
var cells: Dictionary = {}         # { "A1": CellData, ... }
var cell_order: Array[String] = [] # 計算順序（InputCell → FormulaCell）

# --- 数値管理 ---
var coins: HugeNumber              # 累積獲得コイン（UIに表示・アップグレードのコスト）
var current_max: HugeNumber        # 最後のFormulaCellの現在値
var overflow_limit: HugeNumber     # これを超えると#NUM!
var last_tick_gain: HugeNumber     # 1tickあたりのコイン獲得量（DPS表示用）
var dps: float = 0.0               # 互换性用（小さい数値のうちは有効）

# --- 転生 ＆ シート解放 ---
var prestige_count: int = 0
var prestige_multiplier: float = 1.0
var is_num_error: bool = false
var max_columns: int = 1 # 初期は A列 のみ (1列)
var max_rows: int = 1    # 初期は 1行 のみ (1行)
var column_cost_base: float = 200.0
var row_cost_base: float = 40.0

# --- アップグレード（データ駆動） ---
# cost_base: コスト基準値（購入回数に応じて乗算）
var upgrades: Array[Dictionary] = [
	{ "id": "cell_value_a1", "label": "A1 値+0.1",    "cost_base": 10.0,   "purchased": 0, "max": 99, "cost_scale": 3.5 },
	{ "id": "cell_value_a2", "label": "A2 値+0.1",    "cost_base": 100.0,  "purchased": 0, "max": 99, "cost_scale": 3.5 },
	{ "id": "cell_value_a3", "label": "A3 値+0.1",    "cost_base": 500.0,  "purchased": 0, "max": 99, "cost_scale": 3.5 },
	{ "id": "cell_value_a4", "label": "A4 値+0.1",    "cost_base": 2000.0, "purchased": 0, "max": 99, "cost_scale": 3.5 },
	{ "id": "cell_value_a5", "label": "A5 値+0.1",    "cost_base": 10000.0,"purchased": 0, "max": 99, "cost_scale": 3.5 },
	{ "id": "cell_value_a6", "label": "A6 値+0.1",    "cost_base": 50000.0,"purchased": 0, "max": 99, "cost_scale": 3.5 },
	{ "id": "recalc_speed",  "label": "計算速度 x2",   "cost_base": 100.0,  "purchased": 0, "max": 5,  "cost_scale": 6.0 },
	{ "id": "add_sum",       "label": "SUM アンロック",     "cost_base": 10.0,   "purchased": 0, "max": 1,  "cost_scale": 1.0 },
	{ "id": "add_product",   "label": "PRODUCT アンロック", "cost_base": 200.0,  "purchased": 0, "max": 1,  "cost_scale": 1.0 },
	{ "id": "add_fact",      "label": "FACT アンロック",    "cost_base": 1000.0, "purchased": 0, "max": 1,  "cost_scale": 1.0 },
]

func _ready() -> void:
	coins         = HugeNumber.new(0.0, 0)
	current_max   = HugeNumber.new(0.0, 0)
	last_tick_gain = HugeNumber.new(0.0, 0)
	overflow_limit = HugeNumber.from_float(1.79e308)
	_init_cells()

# --- セル初期化 ---
func _init_cells() -> void:
	cells.clear()
	cell_order.clear()

	# max_rows, max_columns に応じてグリッドを構築
	for row in range(1, max_rows + 1):
		for col_idx in range(1, max_columns + 1):
			var col_letter = String.chr(64 + col_idx)
			var id = "%s%d" % [col_letter, row]
			var cell := CellData.new()
			cell.cell_id = id
			
			if col_idx == 1:
				# A列はすべて「無関数（定数）」列
				cell.cell_type = CellData.CellType.INPUT
				cell.raw_value = HugeNumber.new(1.0, 0)
			elif col_idx >= 2:
				# B列・C列以降は初期状態はすべて「空白（無関数）」セル
				cell.cell_type = CellData.CellType.INPUT
				cell.raw_value = HugeNumber.new(0.0, 0)
			
			cells[id] = cell
			cell_order.append(id)

# --- 再計算（Timerのtimeoutで呼ばれる） ---
func recalculate() -> void:
	if is_num_error:
		return

	# Step1: InputCell → display_value = raw_value
	for id in cell_order:
		var c: CellData = cells[id]
		if c.cell_type == CellData.CellType.INPUT:
			c.display_value = c.raw_value

	# Step2: FormulaCell → FormulaEngineで計算（順番に）
	for id in cell_order:
		var c: CellData = cells[id]
		if c.cell_type == CellData.CellType.FORMULA:
			c.display_value  = FormulaEngine.calculate(c, cells)

	# Step3: current_max = すべての数式（FORMULA）セルの合計 ＋ すべての定数（A列）セルの合計
	var total_sum: HugeNumber = HugeNumber.new(0.0, 0)
	for id in cell_order:
		var c: CellData = cells[id]
		if c.cell_type == CellData.CellType.FORMULA:
			total_sum = total_sum.add(c.display_value)
	for r in range(1, max_rows + 1):
		var a_id = "A%d" % r
		if cells.has(a_id):
			total_sum = total_sum.add(cells[a_id].display_value)
	current_max = total_sum

	# Step4: コイン加算（current_max × prestige_multiplier / tick）
	var tick_gain: HugeNumber = current_max.multiply(HugeNumber.from_float(prestige_multiplier))
	coins = coins.add(tick_gain)
	last_tick_gain = tick_gain  # DPS表示用に保持

	# Step6: オーバーフロー判定
	if current_max.is_overflow(overflow_limit) and not is_num_error:
		is_num_error = true
		emit_signal("num_error_triggered")
	else:
		emit_signal("cells_updated")

# --- アップグレード購入 ---
func apply_upgrade(id: String) -> bool:
	for upg in upgrades:
		if upg["id"] != id:
			continue

		# 購入上限チェック
		if upg["purchased"] >= upg["max"]:
			return false

		# コスト計算（purchased回数に比例）
		var cost: HugeNumber = HugeNumber.from_float(
			upg["cost_base"] * pow(upg.get("cost_scale", 3.5), float(upg["purchased"]))
		)

		# コイン不足チェック
		if not can_afford(cost):
			return false

		# コイン消費
		coins = coins.subtract(cost)

		upg["purchased"] += 1
		_apply_upgrade_effect(id)
		emit_signal("upgrade_applied", id)
		return true

	return false

func _apply_upgrade_effect(id: String) -> void:
	match id:
		"cell_value_a1":
			if cells.has("A1"):
				var c: CellData = cells["A1"]
				c.raw_value = c.raw_value.add(HugeNumber.new(0.1, 0))

		"cell_value_a2":
			if cells.has("A2"):
				var c: CellData = cells["A2"]
				c.raw_value = c.raw_value.add(HugeNumber.new(0.1, 0))

		"cell_value_a3":
			if cells.has("A3"):
				var c: CellData = cells["A3"]
				c.raw_value = c.raw_value.add(HugeNumber.new(0.1, 0))

		"cell_value_a4":
			if cells.has("A4"):
				var c: CellData = cells["A4"]
				c.raw_value = c.raw_value.add(HugeNumber.new(0.1, 0))

		"cell_value_a5":
			if cells.has("A5"):
				var c: CellData = cells["A5"]
				c.raw_value = c.raw_value.add(HugeNumber.new(0.1, 0))

		"cell_value_a6":
			if cells.has("A6"):
				var c: CellData = cells["A6"]
				c.raw_value = c.raw_value.add(HugeNumber.new(0.1, 0))

		"recalc_speed":
			# Timerの速度変更はMain.gdで upgrade_applied シグナルを受けて行う
			pass

		"add_sum":
			# 右クリックでのアンロック条件フラグ。購入効果は pass
			pass

		"add_product":
			# 右クリックでのアンロック条件フラグ。購入効果は pass
			pass

		"add_fact":
			# 右クリックでのアンロック条件フラグ。購入効果は pass
			pass

# --- フェーズ取得 ---
func get_phase() -> GamePhase:
	if prestige_count < 2:  return GamePhase.NORMAL
	if prestige_count < 5:  return GamePhase.CORRUPTED
	if prestige_count < 10: return GamePhase.CRITICAL
	return GamePhase.APOCALYPSE

# --- 転生 ---
func do_prestige() -> void:
	var prev_phase := get_phase()
	prestige_count      += 1
	prestige_multiplier += 0.5
	# overflow_limitを10倍（指数+1）
	overflow_limit.exponent += 1
	is_num_error = false
	coins        = HugeNumber.new(0.0, 0)
	last_tick_gain = HugeNumber.new(0.0, 0)
	max_columns  = 1 # 転生時に列数を1列に初期化
	max_rows     = 1 # 転生時に行数を1行に初期化

	# セルリセット
	_init_cells()

	# アップグレードリセット
	for upg in upgrades:
		upg["purchased"] = 0

	# フェーズが変わったらシグナル発火
	var new_phase := get_phase()
	if new_phase != prev_phase:
		emit_signal("phase_changed", new_phase)

	emit_signal("prestige_done")

# --- アップグレードのコスト取得（UI表示用） ---
func get_upgrade_cost(id: String) -> HugeNumber:
	for upg in upgrades:
		if upg["id"] == id:
			return HugeNumber.from_float(
				upg["cost_base"] * pow(upg.get("cost_scale", 3.5), float(upg["purchased"]))
			)
	return HugeNumber.new(0.0, 0)

# --- 購入可能判定（UIなどから呼ぶ用） ---
func can_afford(cost: HugeNumber) -> bool:
	return coins.compare(cost) >= 0

# --- 次の列追加 of コスト取得 ---
func get_next_column_cost() -> HugeNumber:
	if max_columns >= 5:
		return HugeNumber.new(0.0, 0)
	if max_columns == 1:
		return HugeNumber.from_float(10.0) # B列解放
	if max_columns == 2:
		return HugeNumber.from_float(200.0) # C列解放
	if max_columns == 3:
		return HugeNumber.from_float(5000.0) # D列解放
	return HugeNumber.from_float(100000.0) # E列解放

# --- 動的な新列の解放アクション ---
func add_new_column() -> bool:
	if max_columns >= 5:
		return false
	var cost = get_next_column_cost()
	if not can_afford(cost):
		return false
	
	coins = coins.subtract(cost)
	max_columns += 1
	
	# 新列構築
	var col_letter = String.chr(64 + max_columns)
	for row in range(1, max_rows + 1):
		var id = "%s%d" % [col_letter, row]
		var cell := CellData.new()
		cell.cell_id = id
		
		# 最初はすべて「空白（無関数）」セルとして生成！
		cell.cell_type = CellData.CellType.INPUT
		cell.raw_value = HugeNumber.new(0.0, 0)
				
		cells[id] = cell
		cell_order.append(id)
		
	recalculate()
	emit_signal("cells_updated")
	return true

# --- 次の行（スロット）追加のコスト取得 ---
func get_next_row_cost() -> HugeNumber:
	return HugeNumber.from_float(row_cost_base * pow(6.5, float(max_rows - 1)))

# --- 動的な行（スロット）の解放アクション ---
func add_new_row() -> bool:
	var cost = get_next_row_cost()
	if not can_afford(cost):
		return false
	
	coins = coins.subtract(cost)
	max_rows += 1
	
	# 全列に新しい行を生成
	for col_idx in range(1, max_columns + 1):
		var col_letter = String.chr(64 + col_idx)
		var id = "%s%d" % [col_letter, max_rows]
		var cell := CellData.new()
		cell.cell_id = id
		
		if col_idx == 1:
			cell.cell_type = CellData.CellType.INPUT
			cell.raw_value = HugeNumber.new(1.0, 0)
		elif col_idx >= 2:
			# B列・C列以降は初期状態はすべて「空白（無関数）」セル
			cell.cell_type = CellData.CellType.INPUT
			cell.raw_value = HugeNumber.new(0.0, 0)
			
		cells[id] = cell
		cell_order.append(id)

	# 動的インプット・シンクロナイザー（A列全体、B列全体をスキャン）
	var all_a_cells: Array[String] = []
	for r in range(1, max_rows + 1):
		all_a_cells.append("A%d" % r)
		
	var all_b_cells: Array[String] = []
	for r in range(1, max_rows + 1):
		all_b_cells.append("B%d" % r)
		
	# B列（SUM）かつ実際にFORMULAになっているセルの inputs を A列全体 に同期
	for b_id in all_b_cells:
		if cells.has(b_id):
			var b_cell: CellData = cells[b_id]
			if b_cell.cell_type == CellData.CellType.FORMULA:
				b_cell.inputs = all_a_cells.duplicate()
			
	# C列（PRODUCT）かつ実際にFORMULAになっているセルの inputs を B列全体 に同期
	for r in range(1, max_rows + 1):
		var c_id = "C%d" % r
		if cells.has(c_id):
			var c_cell: CellData = cells[c_id]
			if c_cell.cell_type == CellData.CellType.FORMULA:
				c_cell.inputs = all_b_cells.duplicate()
		
	recalculate()
	emit_signal("cells_updated")
	return true
