# scripts/FormulaEngine.gd
# 数式計算エンジン。enumベースで文字列パースなし。
# 静的メソッドのみ。インスタンス化不要。
class_name FormulaEngine

# FormulaCellを計算してHugeNumberを返す
static func calculate(cell: CellData, all_cells: Dictionary) -> HugeNumber:
	match cell.formula_type:
		CellData.FormulaType.SUM:     return _sum(cell.inputs, all_cells)
		CellData.FormulaType.PRODUCT: return _product(cell.inputs, all_cells)
		CellData.FormulaType.FACT:    return _fact(cell.inputs, all_cells)
		CellData.FormulaType.POWER:   return _power(cell.inputs, all_cells)
		CellData.FormulaType.TOWER:   return _tower(cell.inputs, all_cells)
	return HugeNumber.new(0.0, 0)

static func _sum(inputs: Array[String], all_cells: Dictionary) -> HugeNumber:
	var result: HugeNumber = HugeNumber.new(0.0, 0)
	for id in inputs:
		var c: CellData = all_cells.get(id, null)
		if c != null:
			result = result.add(c.display_value)
	return result

static func _product(inputs: Array[String], all_cells: Dictionary) -> HugeNumber:
	var result: HugeNumber = HugeNumber.new(1.0, 0)
	for id in inputs:
		var c: CellData = all_cells.get(id, null)
		if c != null:
			result = result.multiply(c.display_value)
	return result

static func _power(inputs: Array[String], all_cells: Dictionary) -> HugeNumber:
	if inputs.size() < 2:
		return HugeNumber.new(0.0, 0)
	var base:     CellData = all_cells.get(inputs[0], null)
	var exp_cell: CellData = all_cells.get(inputs[1], null)
	if base == null or exp_cell == null:
		return HugeNumber.new(0.0, 0)
	return base.display_value.power(exp_cell.display_value)

static func _fact(inputs: Array[String], all_cells: Dictionary) -> HugeNumber:
	if inputs.is_empty():
		return HugeNumber.new(1.0, 0)
	var c: CellData = all_cells.get(inputs[0], null)
	if c == null:
		return HugeNumber.new(1.0, 0)
	
	var val := c.display_value
	var n: int = 1
	if val.exponent > 0:
		n = 100  # 指数が1以上の超巨大数の場合は安全に最大限界の100とする
	else:
		# exponent が 0 以下の場合は安全に実数化
		var float_val = val.mantissa * pow(10.0, val.exponent)
		n = int(float_val)
		n = clamp(n, 1, 100)
	
	var result := HugeNumber.new(1.0, 0)
	for i in range(1, n + 1):
		result = result.multiply(HugeNumber.from_float(float(i)))
	return result

static func _tower(inputs: Array[String], all_cells: Dictionary) -> HugeNumber:
	if inputs.size() < 2:
		return HugeNumber.new(1.0, 0)
	var base_cell: CellData = all_cells.get(inputs[0], null)
	var exp_cell:  CellData = all_cells.get(inputs[1], null)
	if base_cell == null or exp_cell == null:
		return HugeNumber.new(1.0, 0)
	
	var b := base_cell.display_value
	var e := exp_cell.display_value
	
	# b ^ (b ^ e)
	var first_power := b.power(e)
	return b.power(first_power)

# 数式バー用の表示文字列を生成
static func formula_to_string(cell: CellData) -> String:
	var fn_name: String = CellData.FormulaType.keys()[cell.formula_type]
	if fn_name == "TOWER" and cell.inputs.size() >= 2:
		return "=%s ^ (%s ^ %s)" % [cell.inputs[0], cell.inputs[0], cell.inputs[1]]
	return "=%s(%s)" % [fn_name, ", ".join(cell.inputs)]
