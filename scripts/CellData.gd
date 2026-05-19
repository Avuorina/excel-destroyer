# scripts/CellData.gd
# セル1つ分のデータモデル。InputCell / FormulaCellの両方を兼ねる。
class_name CellData

enum CellType    { INPUT, FORMULA }
enum FormulaType { SUM, PRODUCT, FACT, POWER, TOWER }
enum CellIntervalType { CONSTANT, SUM, PRODUCT, FACT, POWER, TOWER }

var cell_id: String       # "A1", "A2", "B1" など
var cell_type: CellType

# InputCell用
var raw_value: HugeNumber

# FormulaCell用
var formula_type: FormulaType
var inputs: Array[String]  # 参照セルIDの配列 例: ["A1", "A2"]

# 共通（計算後の表示値）
var display_value: HugeNumber

func _init() -> void:
	# 必ずnull事故を防ぐため_initで初期化
	raw_value     = HugeNumber.new(1.0, 0)  # デフォルト値1
	display_value = HugeNumber.new(0.0, 0)  # 計算前は0
	inputs        = []
