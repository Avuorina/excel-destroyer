# scripts/CellData.gd
# セル1つ分のデータモデル。InputCell / FormulaCellの両方を兼ねる。
class_name CellData

enum CellType    { INPUT, FORMULA }
enum FormulaType { SUM, PRODUCT, FACT, POWER, TOWER }
enum CellIntervalType { CONSTANT, SUM, PRODUCT, FACT, POWER, TOWER }

var cell_id: String       # "A1", "A2", "B1" など
var cell_type: CellType

# InputCell用
var raw_value: HyperNumber

# FormulaCell用
var formula_type: FormulaType
var inputs: Array[String]  # 参照セルIDの配列 例: ["A1", "A2"]

# 共通（計算後の表示値）
var display_value: HyperNumber

# --- 新アーキテクチャ追加分 ---
var is_dirty: bool = true
var cached_value: HyperNumber
var dependencies: Array[String] = [] # このセルが依存しているセル(inputs)
var dependents: Array[String] = []   # このセルに依存しているセル

func _init() -> void:
	raw_value     = HyperNumber.new(1, 0, 1.0)  # デフォルト値1
	display_value = HyperNumber.new(0, 0, 0.0)  # 計算前は0
	cached_value  = HyperNumber.new(0, 0, 0.0)
	inputs        = []
	dependencies  = []
	dependents    = []
