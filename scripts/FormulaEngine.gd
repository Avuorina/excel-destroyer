# scripts/FormulaEngine.gd
# 数式計算エンジン。enumベースで文字列パースなし。
# 静的メソッドのみ。インスタンス化不要。
class_name FormulaEngine

# FormulaCellを計算してHugeNumberを返す
static func calculate(cell: CellData, all_cells: Dictionary) -> HugeNumber:
	match cell.formula_type:
		CellData.FormulaType.SUM:     return _sum(cell.inputs, all_cells)
		CellData.FormulaType.PRODUCT: return _product(cell.inputs, all_cells)
		CellData.FormulaType.POWER:   return _power(cell.inputs, all_cells)
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

# 数式バー用の表示文字列を生成
static func formula_to_string(cell: CellData) -> String:
	var fn_name: String = CellData.FormulaType.keys()[cell.formula_type]
	return "=%s(%s)" % [fn_name, ", ".join(cell.inputs)]
