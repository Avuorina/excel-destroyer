# Cell.gd
# Cell.tscnにアタッチするスクリプト。セル1つ分のUIを制御する。
extends PanelContainer

@onready var cell_label:  Label = $VBoxContainer/CellLabel
@onready var value_label: Label = $VBoxContainer/ValueLabel

var cell_id: String = ""
var is_formula: bool = false

# --- 定数: カラー ---
const COLOR_NORMAL_BG    := Color(0.06, 0.20, 0.38, 1.0)   # #0f3460
const COLOR_FORMULA_BG   := Color(0.05, 0.15, 0.28, 1.0)   # 少し暗め
const COLOR_TEXT_NORMAL  := Color(0.88, 0.88, 0.88, 1.0)   # #e0e0e0
const COLOR_TEXT_FORMULA := Color(0.13, 0.98, 0.56, 1.0)   # #21fa90 緑
const COLOR_ERROR        := Color(1.00, 0.23, 0.19, 1.0)   # #ff3b30 赤

# セルのIDとタイプを設定する
func setup(id: String, formula: bool) -> void:
	cell_id    = id
	is_formula = formula
	cell_label.text = id

	# FormulaCell は緑テキスト
	if is_formula:
		value_label.add_theme_color_override("font_color", COLOR_TEXT_FORMULA)
	else:
		value_label.add_theme_color_override("font_color", COLOR_TEXT_NORMAL)

# 値を更新する
func update_value(value: HugeNumber) -> void:
	value_label.add_theme_color_override("font_color",
		COLOR_TEXT_FORMULA if is_formula else COLOR_TEXT_NORMAL)
	value_label.text = value.to_display_string()

# #NUM! エラー表示
func show_error() -> void:
	value_label.text = "#NUM!"
	value_label.add_theme_color_override("font_color", COLOR_ERROR)

# 表示リセット
func reset_display() -> void:
	value_label.text = "0"
	value_label.add_theme_color_override("font_color",
		COLOR_TEXT_FORMULA if is_formula else COLOR_TEXT_NORMAL)
