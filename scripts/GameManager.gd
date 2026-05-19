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
var _is_recalculating: bool = false
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
	{ "id": "add_sum",       "label": "SUM アンロック",     "cost_base": 10.0,   "purchased": 0, "max": 1,  "cost_scale": 1.0 },
	{ "id": "add_product",   "label": "PRODUCT アンロック", "cost_base": 200.0,  "purchased": 0, "max": 1,  "cost_scale": 1.0 },
	{ "id": "add_fact",      "label": "FACT アンロック",    "cost_base": 1000.0, "purchased": 0, "max": 1,  "cost_scale": 1.0 },

	# CONSTANT 生産x2（5段階）
	{ "id": "prod_constant_1", "label": "CONSTANT 生産 x2",   "group": "prod_constant", "tier": 1, "cost_base": 100.0,      "max": 1, "purchased": 0 },
	{ "id": "prod_constant_2", "label": "CONSTANT 生産 x4",   "group": "prod_constant", "tier": 2, "cost_base": 1000.0,     "max": 1, "purchased": 0 },
	{ "id": "prod_constant_3", "label": "CONSTANT 生産 x8",   "group": "prod_constant", "tier": 3, "cost_base": 10000.0,    "max": 1, "purchased": 0 },
	{ "id": "prod_constant_4", "label": "CONSTANT 生産 x16",  "group": "prod_constant", "tier": 4, "cost_base": 100000.0,   "max": 1, "purchased": 0 },
	{ "id": "prod_constant_5", "label": "CONSTANT 生産 x32",  "group": "prod_constant", "tier": 5, "cost_base": 1000000.0,  "max": 1, "purchased": 0 },

	# SUM 生産x2（5段階）- SUMアンロック後に出現
	{ "id": "prod_sum_1", "label": "SUM 生産 x2",   "group": "prod_sum", "tier": 1, "cost_base": 500.0,      "max": 1, "purchased": 0 },
	{ "id": "prod_sum_2", "label": "SUM 生産 x4",   "group": "prod_sum", "tier": 2, "cost_base": 5000.0,     "max": 1, "purchased": 0 },
	{ "id": "prod_sum_3", "label": "SUM 生産 x8",   "group": "prod_sum", "tier": 3, "cost_base": 50000.0,    "max": 1, "purchased": 0 },
	{ "id": "prod_sum_4", "label": "SUM 生産 x16",  "group": "prod_sum", "tier": 4, "cost_base": 500000.0,   "max": 1, "purchased": 0 },
	{ "id": "prod_sum_5", "label": "SUM 生産 x32",  "group": "prod_sum", "tier": 5, "cost_base": 5000000.0,  "max": 1, "purchased": 0 },

	# PRODUCT 生産x2（5段階）- PRODUCTアンロック後に出現
	{ "id": "prod_product_1", "label": "PRODUCT 生産 x2",  "group": "prod_product", "tier": 1, "cost_base": 5000.0,      "max": 1, "purchased": 0 },
	{ "id": "prod_product_2", "label": "PRODUCT 生産 x4",  "group": "prod_product", "tier": 2, "cost_base": 50000.0,     "max": 1, "purchased": 0 },
	{ "id": "prod_product_3", "label": "PRODUCT 生産 x8",  "group": "prod_product", "tier": 3, "cost_base": 500000.0,    "max": 1, "purchased": 0 },
	{ "id": "prod_product_4", "label": "PRODUCT 生産 x16", "group": "prod_product", "tier": 4, "cost_base": 5000000.0,   "max": 1, "purchased": 0 },
	{ "id": "prod_product_5", "label": "PRODUCT 生産 x32", "group": "prod_product", "tier": 5, "cost_base": 50000000.0,  "max": 1, "purchased": 0 },

	# FACT 生産x2（5段階）- FACTアンロック後に出現
	{ "id": "prod_fact_1", "label": "FACT 生産 x2",  "group": "prod_fact", "tier": 1, "cost_base": 50000.0,     "max": 1, "purchased": 0 },
	{ "id": "prod_fact_2", "label": "FACT 生産 x4",  "group": "prod_fact", "tier": 2, "cost_base": 500000.0,    "max": 1, "purchased": 0 },
	{ "id": "prod_fact_3", "label": "FACT 生産 x8",  "group": "prod_fact", "tier": 3, "cost_base": 5000000.0,   "max": 1, "purchased": 0 },
	{ "id": "prod_fact_4", "label": "FACT 生産 x16", "group": "prod_fact", "tier": 4, "cost_base": 50000000.0,  "max": 1, "purchased": 0 },
	{ "id": "prod_fact_5", "label": "FACT 生産 x32", "group": "prod_fact", "tier": 5, "cost_base": 500000000.0, "max": 1, "purchased": 0 },
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
# --- スプレッドシート全体の表示値更新（コイン加算なし・ループ防御つき） ---
func recalculate() -> void:
	if _is_recalculating or is_num_error:
		return
	_is_recalculating = true

	# Step1: InputCell → display_value = raw_value
	for id in cell_order:
		var c: CellData = cells[id]
		if c.cell_type == CellData.CellType.INPUT:
			c.display_value = c.raw_value

	# Step2: FormulaCell → FormulaEngineで計算（順番に）
	for id in cell_order:
		var c: CellData = cells[id]
		if c.cell_type == CellData.CellType.FORMULA:
			c.display_value = FormulaEngine.calculate(c, cells)

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

	# オーバーフロー判定
	if current_max.is_overflow(overflow_limit) and not is_num_error:
		is_num_error = true
		_is_recalculating = false
		emit_signal("num_error_triggered")
		return

	emit_signal("cells_updated")
	_is_recalculating = false

# --- 指定されたタイマー型セルのみの再計算 ＆ コイン加算（ループ防御つき） ---
func recalculate_for_type(cell_type: int) -> void:
	if _is_recalculating or is_num_error:
		return
	_is_recalculating = true

	# Step1: 全セルの表示値を最新状態に更新（スプレッドシートの参照連鎖を保つため必須）
	for id in cell_order:
		var c: CellData = cells[id]
		if c.cell_type == CellData.CellType.INPUT:
			c.display_value = c.raw_value

	for id in cell_order:
		var c: CellData = cells[id]
		if c.cell_type == CellData.CellType.FORMULA:
			c.display_value = FormulaEngine.calculate(c, cells)

	# Step2: 今回のタイマー型（cell_type）に該当するセルのみの表示値を集計
	var gain_base := HugeNumber.new(0.0, 0)
	for id in cell_order:
		var c: CellData = cells[id]
		if _get_cell_interval_type(c) == cell_type:
			gain_base = gain_base.add(c.display_value)

	# 新規：関数別の生産倍率の適用
	var multiplier := 1.0
	match cell_type:
		CellData.CellIntervalType.CONSTANT:
			multiplier = get_prod_multiplier("prod_constant")
		CellData.CellIntervalType.SUM:
			multiplier = get_prod_multiplier("prod_sum")
		CellData.CellIntervalType.PRODUCT:
			multiplier = get_prod_multiplier("prod_product")
		CellData.CellIntervalType.FACT:
			multiplier = get_prod_multiplier("prod_fact")

	gain_base = gain_base.multiply(HugeNumber.from_float(multiplier))

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

	# Step4: 該当する収益があればコイン加算
	if not gain_base.is_zero():
		var tick_gain: HugeNumber = gain_base.multiply(HugeNumber.from_float(prestige_multiplier))
		coins = coins.add(tick_gain)
		last_tick_gain = tick_gain  # 最新の加算量を保持

	# Step5: オーバーフロー判定
	if current_max.is_overflow(overflow_limit) and not is_num_error:
		is_num_error = true
		_is_recalculating = false
		emit_signal("num_error_triggered")
		return

	# 値加算に関わらずスプレッドシート画面更新のためシグナル発火
	emit_signal("cells_updated")
	_is_recalculating = false

# --- セルがどのタイマー型（CellIntervalType）に属するかを返す ---
func _get_cell_interval_type(c: CellData) -> int:
	if c.cell_type == CellData.CellType.INPUT:
		return CellData.CellIntervalType.CONSTANT
	else:
		match c.formula_type:
			CellData.FormulaType.SUM:     return CellData.CellIntervalType.SUM
			CellData.FormulaType.PRODUCT: return CellData.CellIntervalType.PRODUCT
			CellData.FormulaType.FACT:    return CellData.CellIntervalType.FACT
			CellData.FormulaType.POWER:   return CellData.CellIntervalType.POWER
			CellData.FormulaType.TOWER:   return CellData.CellIntervalType.TOWER
			_:                            return CellData.CellIntervalType.CONSTANT

# --- 各タイマーのwait_timeを元に、1秒あたりの期待獲得コイン（真のDPS）を算出 ---
func calc_total_dps(cell_timers: Dictionary) -> HugeNumber:
	var total := HugeNumber.new(0.0, 0)
	for cell_type in cell_timers.keys():
		var timer: Timer = cell_timers[cell_type]
		if not is_instance_valid(timer) or timer.wait_time <= 0.0:
			continue
		
		# 該当するセルの表示値合計を算出
		var gain_base := HugeNumber.new(0.0, 0)
		for id in cell_order:
			var c: CellData = cells[id]
			if _get_cell_interval_type(c) == cell_type:
				gain_base = gain_base.add(c.display_value)
		
		# 新規：関数別の生産倍率の適用
		var multiplier := 1.0
		match cell_type:
			CellData.CellIntervalType.CONSTANT:
				multiplier = get_prod_multiplier("prod_constant")
			CellData.CellIntervalType.SUM:
				multiplier = get_prod_multiplier("prod_sum")
			CellData.CellIntervalType.PRODUCT:
				multiplier = get_prod_multiplier("prod_product")
			CellData.CellIntervalType.FACT:
				multiplier = get_prod_multiplier("prod_fact")
				
		gain_base = gain_base.multiply(HugeNumber.from_float(multiplier))

		# 1秒あたりの期待値 = 合計値 / wait_time
		var dps_part = gain_base.multiply(HugeNumber.from_float(1.0 / timer.wait_time))
		total = total.add(dps_part)
		
	return total.multiply(HugeNumber.from_float(prestige_multiplier))

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

# --- アップグレードが購入済みかどうか（段階数1以上）を返す ---
func is_purchased(id: String) -> bool:
	for upg in upgrades:
		if upg["id"] == id:
			return upg["purchased"] >= 1
	return false

# --- 指定グループの購入済み段階数から倍率を返す ---
func get_prod_multiplier(group: String) -> float:
	var count := 0
	for upg in upgrades:
		if upg.get("group", "") == group and upg["purchased"] >= 1:
			count += 1
	return pow(2.0, count)  # 0段階=x1, 1段階=x2, 2段階=x4...

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
