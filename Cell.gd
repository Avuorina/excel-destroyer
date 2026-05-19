# Cell.gd
# Cell.tscnにアタッチするスクリプト。セル1つ分のUIを制御する。
extends PanelContainer

signal cell_clicked(id: String)
signal cell_double_clicked(id: String)
signal cell_right_clicked(id: String, mouse_pos: Vector2)

@onready var cell_label: Label = $VBoxContainer/CellLabel
@onready var value_label: Label = $VBoxContainer/ValueLabel

var cell_id: String = ""
var is_formula: bool = false
var _current_style: StyleBoxFlat = null # border操作用に保持

# --- 定数: カラー ---
const COLOR_NORMAL_BG := Color(0.01, 0.04, 0.02, 1.0) # 極深緑（入力セル）
const COLOR_FORMULA_BG := Color(0.02, 0.06, 0.03, 1.0) # 少し明るい深緑（数式セル）
const COLOR_TEXT_NORMAL := Color(1.0, 1.0, 1.0, 1.0) # 白（通常文字）
const COLOR_TEXT_FORMULA := Color(0.9, 1.0, 0.95, 1.0) # 明るいミント白（数式文字）
const COLOR_ERROR := Color(1.00, 0.23, 0.19, 1.0) # 赤
const COLOR_SELECTED_BORDER := Color(0.13, 0.98, 0.56, 1.0) # 眩しいExcelグリーン枠
const COLOR_BORDER_IDLE := Color(0.02, 0.12, 0.05, 1.0) # 深緑グリッド線

# 桁数→色のステップ（exponentベース）
const MAGNITUDE_COLORS: Array = [
	[0, Color(1.0, 1.0, 1.0, 1.0)], # 白 (normal)
	[6, Color(0.98, 0.92, 0.13, 1.0)], # 黄 (heating up)
	[12, Color(0.98, 0.58, 0.13, 1.0)], # オレンジ (hot)
	[24, Color(0.98, 0.20, 0.13, 1.0)], # 赤 (critical)
	[48, Color(0.90, 0.10, 0.95, 1.0)], # マゼンタ (APOCALYPSE)
]

# セルのIDとタイプを設定する
func setup(id: String, formula: bool) -> void:
	cell_id = id
	is_formula = formula
	cell_label.text = id

	# StyleBoxFlatを複製してborder操作できるようにする
	var original = get_theme_stylebox("panel") as StyleBoxFlat
	if original:
		_current_style = original.duplicate() as StyleBoxFlat
		add_theme_stylebox_override("panel", _current_style)

	# FormulaCell は緑テキスト
	if is_formula:
		value_label.add_theme_color_override("font_color", COLOR_TEXT_FORMULA)
	else:
		value_label.add_theme_color_override("font_color", COLOR_TEXT_NORMAL)

	# クリック検知のためにマウス入力を有効化
	mouse_filter = Control.MOUSE_FILTER_STOP

# 空の装飾用セルを設定する
func setup_empty() -> void:
	cell_id    = ""
	is_formula = false
	cell_label.text = ""
	value_label.text = ""
	
	# StyleBoxFlatを複製して見た目を薄くする
	var original = get_theme_stylebox("panel") as StyleBoxFlat
	if original:
		_current_style = original.duplicate() as StyleBoxFlat
		add_theme_stylebox_override("panel", _current_style)
		_current_style.bg_color = Color(0.047, 0.102, 0.047, 0.6) # #0c1a0c（不透明度0.6）
		_current_style.border_color = Color(0.02, 0.12, 0.05, 0.3) # 薄いボーダー
		_current_style.border_width_left = 1
		_current_style.border_width_top = 1
		_current_style.border_width_right = 1
		_current_style.border_width_bottom = 1
	
	# 入力・フォーカスを一切無視
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# 値を更新する（フラッシュ演出つき）
func update_value(value: HugeNumber) -> void:
	# A列以外かつ数式セル（is_formula）ではない（＝空白セル）の場合は、完全に空白にする！
	if not is_formula and not cell_id.begins_with("A"):
		if cell_id == "B1":
			value_label.text = "行を追加で解放"
			value_label.add_theme_font_size_override("font_size", 9)
			value_label.add_theme_color_override("font_color", Color(0.16, 0.29, 0.16, 1.0)) # #2a4a2a
		else:
			value_label.text = ""
	else:
		value_label.remove_theme_font_size_override("font_size")
		value_label.text = value.to_display_string()

	# --- 桁数に応じた文字色 ---
	var target_color: Color
	if is_formula:
		target_color = _get_color_for_magnitude(value)
	else:
		target_color = COLOR_TEXT_NORMAL

	# --- 更新フラッシュ: 一瞬輝いてから目標色へ ---
	var tween = create_tween()
	tween.tween_property(
		value_label, "modulate",
		Color(1.8, 1.8, 1.8, 1.0), 0.04 # ホワイトフラッシュ
	)
	tween.tween_property(
		value_label, "modulate",
		Color(1.0, 1.0, 1.0, 1.0), 0.18
	)
	value_label.add_theme_color_override("font_color", target_color)

# #NUM! エラー表示
func show_error() -> void:
	value_label.text = "#NUM!"
	value_label.add_theme_color_override("font_color", COLOR_ERROR)

	# セル全体を赤く染める
	if _current_style:
		var tween = create_tween()
		tween.tween_property(_current_style, "bg_color",
			Color(0.25, 0.04, 0.04, 1.0), 0.15)

# 表示リセット
func reset_display() -> void:
	value_label.text = "0"
	value_label.add_theme_color_override("font_color",
		COLOR_TEXT_FORMULA if is_formula else COLOR_TEXT_NORMAL)

	if _current_style:
		_current_style.bg_color = \
			COLOR_FORMULA_BG if is_formula else COLOR_NORMAL_BG

# --- セル選択演出 ＆ クリック検知 ---
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				emit_signal("cell_double_clicked", cell_id)
			else:
				_play_select_animation()
				emit_signal("cell_clicked", cell_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			emit_signal("cell_right_clicked", cell_id, event.global_position)

func _play_select_animation() -> void:
	if not _current_style:
		return

	# border をシアンに光らせてスケールポンッ
	var tween = create_tween().set_parallel(true)

	# border色変化
	tween.tween_property(_current_style, "border_color",
		COLOR_SELECTED_BORDER, 0.06)
	tween.tween_property(_current_style, "border_width_left", 2, 0.06)
	tween.tween_property(_current_style, "border_width_top", 2, 0.06)
	tween.tween_property(_current_style, "border_width_right", 2, 0.06)
	tween.tween_property(_current_style, "border_width_bottom", 2, 0.06)

	# スケールポップ
	tween.tween_property(self , "scale", Vector2(1.06, 1.06), 0.07)

	# 戻す
	tween.chain().set_parallel(true)
	tween.tween_property(self , "scale", Vector2(1.0, 1.0), 0.10)
	tween.tween_property(_current_style, "border_color",
		COLOR_BORDER_IDLE, 0.25)
	tween.tween_property(_current_style, "border_width_left", 1, 0.25)
	tween.tween_property(_current_style, "border_width_top", 1, 0.25)
	tween.tween_property(_current_style, "border_width_right", 1, 0.25)
	tween.tween_property(_current_style, "border_width_bottom", 1, 0.25)

# --- 桁数→色マッピング ---
func _get_color_for_magnitude(value: HugeNumber) -> Color:
	var magnitude: int = value.exponent if value.exponent > 0 else 0
	var result := MAGNITUDE_COLORS[0][1] as Color
	for pair in MAGNITUDE_COLORS:
		if magnitude >= pair[0]:
			result = pair[1] as Color
	return result
