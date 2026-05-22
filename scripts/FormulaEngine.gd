# scripts/FormulaEngine.gd
class_name FormulaEngine

# 「数学仮想マシン」として、AST(Operation)の実行と最適化のみを担当する。
# UI操作、副作用、シグナル発火は一切禁止。

const MAX_COMPLEXITY: float = 1000.0

static var _registry: Dictionary = {}
static var _initialized: bool = false

const Ops = preload("res://scripts/FormulaOperations.gd")

static func _init_registry() -> void:
	if _initialized: return
	_registry[CellData.FormulaType.SUM] = Ops.AddOp.new()
	_registry[CellData.FormulaType.PRODUCT] = Ops.MulOp.new()
	_registry[CellData.FormulaType.FACT] = Ops.FactOp.new()
	_registry[CellData.FormulaType.POWER] = Ops.PowerOp.new()
	_registry[CellData.FormulaType.TOWER] = Ops.TowerOp.new()
	_initialized = true

# FormulaCellを計算して HyperNumber を返す (循環参照ガード付き)
static func calculate(cell: CellData, all_cells: Dictionary, visited: Dictionary = {}) -> HyperNumber:
	_init_registry()
	
	if visited.has(cell.cell_id):
		# 無限再帰（循環参照）検知。
		# バグでクラッシュしないよう、ひとまず 0 を返す。
		# （正しい処理は DependencyGraphSystem が別途 Infinity Loop リソース等に変換する）
		return HyperNumber.new(0, 0, 0.0)
		
	visited[cell.cell_id] = true
	
	if not cell.is_dirty:
		return HyperMath.clone(cell.cached_value)
		
	if not _registry.has(cell.formula_type):
		return HyperNumber.new(0, 0, 0.0)
		
	var op: Ops.BaseOp = _registry[cell.formula_type]
	
	# 演算コスト層によるリミッター
	var cost = op.get_cost()
	if cost > MAX_COMPLEXITY:
		# TODO: 将来的には approximate() による近似計算モードへフォールバック
		pass
		
	# 純粋な数学評価を実行
	var result = op.evaluate(cell.inputs, all_cells)
	
	# キャッシュ更新 (完全なImmutableとして扱う)
	cell.cached_value = HyperMath.clone(result)
	cell.display_value = HyperMath.clone(result) # GameManager完全移行までの暫定
	cell.is_dirty = false
	
	return result

# 数式バー用の表示文字列を生成（UI用ヘルパーだが数学定義なのでここに残すか、別途分けるか）
static func formula_to_string(cell: CellData) -> String:
	var fn_name: String = CellData.FormulaType.keys()[cell.formula_type]
	if fn_name == "TOWER" and cell.inputs.size() >= 2:
		return "=%s ^ (%s ^ %s)" % [cell.inputs[0], cell.inputs[0], cell.inputs[1]]
	return "=%s(%s)" % [fn_name, ", ".join(cell.inputs)]
