# scripts/ContextMenuManager.gd
extends PanelContainer

signal action_selected(action: String, extra: String)

@onready var vbox: VBoxContainer = $VBox

var current_cell_id: String = ""

# --- 定数: ボタンのStyle ---
var btn_style_normal: StyleBoxFlat
var btn_style_hover: StyleBoxFlat
var btn_style_disabled: StyleBoxFlat

func _ready() -> void:
	# ボタンの共通Styleをコードから生成
	btn_style_normal = StyleBoxFlat.new()
	btn_style_normal.bg_color = Color(0.01, 0.04, 0.02, 1.0)
	btn_style_normal.content_margin_left = 6
	btn_style_normal.content_margin_top = 6
	btn_style_normal.content_margin_right = 6
	btn_style_normal.content_margin_bottom = 6

	btn_style_hover = StyleBoxFlat.new()
	btn_style_hover.bg_color = Color(0.06, 0.45, 0.22, 1.0) # ホバー時はきれいな緑
	btn_style_hover.content_margin_left = 6
	btn_style_hover.content_margin_top = 6
	btn_style_hover.content_margin_right = 6
	btn_style_hover.content_margin_bottom = 6

	btn_style_disabled = StyleBoxFlat.new()
	btn_style_disabled.bg_color = Color(0.01, 0.04, 0.02, 0.5)
	btn_style_disabled.content_margin_left = 6
	btn_style_disabled.content_margin_top = 6
	btn_style_disabled.content_margin_right = 6
	btn_style_disabled.content_margin_bottom = 6

	# 初期状態は非表示
	visible = false

# メニューを生成して開く
func open_menu(cell_id: String, mouse_pos: Vector2, options: Dictionary) -> void:
	current_cell_id = cell_id
	visible = true
	
	# 古いメニュー項目をクリア
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()

	# 1. 挿入関数リストの定義（FACT と POWER を正しい順序に入れ替え ＆ 段階的表示フラグをサポート）
	var formulas = [
		{
			"name": "SUM",
			"locked": options.get("sum_locked", true),
			"visible": options.get("sum_visible", true),
			"cost": HugeNumber.from_float(10.0),
			"cost_str": "10.0"
		},
		{
			"name": "PRODUCT",
			"locked": options.get("product_locked", true),
			"visible": options.get("product_visible", true),
			"cost": HugeNumber.from_float(200.0),
			"cost_str": "200.0"
		},
		{
			"name": "FACT",
			"locked": options.get("fact_locked", true),
			"visible": options.get("fact_visible", true),
			"cost": HugeNumber.from_float(1000.0),
			"cost_str": "1,000"
		},
		{
			"name": "POWER",
			"locked": options.get("power_locked", true),
			"visible": options.get("power_visible", true),
			"cost": HugeNumber.new(5.0, 4),
			"cost_str": "50,000"
		},
		{
			"name": "TOWER",
			"locked": options.get("tower_locked", true),
			"visible": options.get("tower_visible", true),
			"cost": HugeNumber.new(1.0, 6),
			"cost_str": "1.0e6"
		},
	]

	# ヘッダーラベル
	var header := Label.new()
	header.text = "  関数挿入 (セル: %s)" % cell_id
	header.add_theme_font_size_override("font_size", 9)
	header.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5, 1))
	vbox.add_child(header)

	var sep1 := HSeparator.new()
	sep1.add_theme_color_override("color", Color(0.02, 0.12, 0.05, 1.0))
	vbox.add_child(sep1)

	# 関数ボタン追加
	for f in formulas:
		# まだ段階に達していない関数は完全に非表示（ボタンを作らない）
		if not f.get("visible", true):
			continue
			
		var btn := Button.new()
		btn.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_stylebox_override("normal", btn_style_normal)
		btn.add_theme_stylebox_override("hover", btn_style_hover)
		btn.add_theme_stylebox_override("disabled", btn_style_disabled)

		if f["locked"]:
			btn.text = "🔒 " + f["name"] + " (ロック中)"
			btn.disabled = true
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
		else:
			var can_afford = GameManager.coins.compare(f["cost"]) >= 0
			btn.text = "   =" + f["name"] + " (コスト: " + f["cost_str"] + ")"
			btn.disabled = not can_afford
			if can_afford:
				btn.pressed.connect(_on_action_selected.bind("insert_function", f["name"]))
			else:
				btn.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3, 1.0))
		vbox.add_child(btn)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("color", Color(0.02, 0.12, 0.05, 1.0))
	vbox.add_child(sep2)

	# 2. その他アクション
	var col_cost_str = options.get("column_cost", "200")
	_add_action_button("列を挿入 (コスト: " + col_cost_str + ")", "insert_column", options.get("can_add_column", false))
	if options.has("can_add_row"):
		var row_cost_str = options.get("row_cost", "50")
		_add_action_button("行を挿入 (コスト: " + row_cost_str + ")", "insert_row", options.get("can_add_row", false))
	_add_action_button("数式をクリア", "delete_formula", options.get("can_delete", false))

	# マウスポジションに移動 ＆ クリッピング
	global_position = mouse_pos
	_clip_to_screen()

# アクションボタン追加ヘルパー
func _add_action_button(label_text: String, action: String, enabled: bool) -> void:
	var btn := Button.new()
	btn.text = "   " + label_text
	btn.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_stylebox_override("normal", btn_style_normal)
	btn.add_theme_stylebox_override("hover", btn_style_hover)
	btn.add_theme_stylebox_override("disabled", btn_style_disabled)
	btn.disabled = not enabled
	if enabled:
		btn.pressed.connect(_on_action_selected.bind(action, ""))
	vbox.add_child(btn)

# クリック時処理
func _on_action_selected(action: String, extra: String) -> void:
	visible = false
	emit_signal("action_selected", action, extra)

# 画面端からはみ出さないようにクリッピング
func _clip_to_screen() -> void:
	reset_size()
	var screen_size := get_viewport_rect().size
	var end_pos := global_position + size
	if end_pos.x > screen_size.x:
		global_position.x -= (end_pos.x - screen_size.x) + 8
	if end_pos.y > screen_size.y:
		global_position.y -= (end_pos.y - screen_size.y) + 8
	# 画面外（マイナス）防止
	global_position.x = max(global_position.x, 8)
	global_position.y = max(global_position.y, 8)
