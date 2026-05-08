# scripts/GameManager.gd
# AutoLoad登録必須:
#   プロジェクト設定 → AutoLoad → scripts/GameManager.gd → 名前: GameManager
extends Node

# --- シグナル ---
signal cells_updated
signal num_error_triggered
signal prestige_done
signal upgrade_applied(id: String)

# --- セルデータ ---
var cells: Dictionary = {}         # { "A1": CellData, ... }
var cell_order: Array[String] = [] # 計算順序（InputCell → FormulaCell）

# --- 数値管理 ---
var coins: HugeNumber              # 累積獲得コイン（UIに表示・アップグレードのコスト）
var current_max: HugeNumber        # 最後のFormulaCellの現在値
var overflow_limit: HugeNumber     # これを超えると#NUM!
var prev_max_float: float = 0.0    # DPS計算用
var dps: float = 0.0               # DPS（float）

# --- 転生 ---
var prestige_count: int = 0
var prestige_multiplier: float = 1.0
var is_num_error: bool = false

# --- アップグレード（データ駆動） ---
# cost_base: コスト基準値（購入回数に応じて乗算）
var upgrades: Array[Dictionary] = [
	{ "id": "cell_value_a1", "label": "A1 値+1",      "cost_base": 10.0,   "purchased": 0, "max": 99 },
	{ "id": "cell_value_a2", "label": "A2 値+1",      "cost_base": 10.0,   "purchased": 0, "max": 99 },
	{ "id": "recalc_speed",  "label": "計算速度 x2",   "cost_base": 100.0,  "purchased": 0, "max": 5  },
	{ "id": "add_product",   "label": "PRODUCT アンロック", "cost_base": 200.0,  "purchased": 0, "max": 1  },
	{ "id": "add_power",     "label": "POWER アンロック",   "cost_base": 1000.0, "purchased": 0, "max": 1  },
]

func _ready() -> void:
	coins         = HugeNumber.new(0.0, 0)
	current_max   = HugeNumber.new(0.0, 0)
	overflow_limit = HugeNumber.from_float(1.79e308)
	_init_cells()

# --- セル初期化 ---
func _init_cells() -> void:
	cells.clear()
	cell_order.clear()

	# InputCell A1
	var a1: CellData = CellData.new()
	a1.cell_id   = "A1"
	a1.cell_type = CellData.CellType.INPUT
	a1.raw_value = HugeNumber.new(1.0, 0)
	cells["A1"]  = a1
	cell_order.append("A1")

	# InputCell A2
	var a2: CellData = CellData.new()
	a2.cell_id   = "A2"
	a2.cell_type = CellData.CellType.INPUT
	a2.raw_value = HugeNumber.new(1.0, 0)
	cells["A2"]  = a2
	cell_order.append("A2")

	# FormulaCell B1 = SUM(A1, A2)
	var b1: CellData = CellData.new()
	b1.cell_id      = "B1"
	b1.cell_type    = CellData.CellType.FORMULA
	b1.formula_type = CellData.FormulaType.SUM
	b1.inputs       = ["A1", "A2"]
	cells["B1"]     = b1
	cell_order.append("B1")

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
	var last_formula_value: HugeNumber = HugeNumber.new(0.0, 0)
	for id in cell_order:
		var c: CellData = cells[id]
		if c.cell_type == CellData.CellType.FORMULA:
			c.display_value  = FormulaEngine.calculate(c, cells)
			last_formula_value = c.display_value

	# Step3: current_max = 最後のFormulaCellの値
	current_max = last_formula_value

	# Step4: コイン加算（current_max × prestige_multiplier / tick）
	var tick_gain: HugeNumber = HugeNumber.from_float(
		current_max.to_float() * prestige_multiplier
	)
	coins = coins.add(tick_gain)

	# Step5: DPS計算（float同士）
	var cur_float: float = current_max.to_float() * prestige_multiplier
	dps           = cur_float - prev_max_float
	prev_max_float = cur_float

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
			upg["cost_base"] * pow(2.0, float(upg["purchased"]))
		)

		# コイン不足チェック
		if coins.to_float() < cost.to_float():
			return false

		# コイン消費
		coins = HugeNumber.from_float(coins.to_float() - cost.to_float())

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
				c.raw_value = c.raw_value.add(HugeNumber.new(1.0, 0))

		"cell_value_a2":
			if cells.has("A2"):
				var c: CellData = cells["A2"]
				c.raw_value = c.raw_value.add(HugeNumber.new(1.0, 0))

		"recalc_speed":
			# Timerの速度変更はMain.gdで upgrade_applied シグナルを受けて行う
			pass

		"add_product":
			# B2 = PRODUCT(B1, A1) を追加
			if not cells.has("B2"):
				var b2: CellData = CellData.new()
				b2.cell_id      = "B2"
				b2.cell_type    = CellData.CellType.FORMULA
				b2.formula_type = CellData.FormulaType.PRODUCT
				b2.inputs       = ["B1", "A1"]
				cells["B2"]     = b2
				cell_order.append("B2")

		"add_power":
			# B3 = POWER(B2, A2) を追加（B2がある場合のみ）
			if not cells.has("B3") and cells.has("B2"):
				var b3: CellData = CellData.new()
				b3.cell_id      = "B3"
				b3.cell_type    = CellData.CellType.FORMULA
				b3.formula_type = CellData.FormulaType.POWER
				b3.inputs       = ["B2", "A2"]
				cells["B3"]     = b3
				cell_order.append("B3")

# --- 転生 ---
func do_prestige() -> void:
	prestige_count      += 1
	prestige_multiplier += 0.5
	# overflow_limitを10倍（指数+1）
	overflow_limit.exponent += 1
	is_num_error = false
	prev_max_float = 0.0
	coins        = HugeNumber.new(0.0, 0)

	# セルリセット
	_init_cells()

	# アップグレードリセット
	for upg in upgrades:
		upg["purchased"] = 0

	emit_signal("prestige_done")

# --- アップグレードのコスト取得（UI表示用） ---
func get_upgrade_cost(id: String) -> HugeNumber:
	for upg in upgrades:
		if upg["id"] == id:
			return HugeNumber.from_float(
				upg["cost_base"] * pow(2.0, float(upg["purchased"]))
			)
	return HugeNumber.new(0.0, 0)
