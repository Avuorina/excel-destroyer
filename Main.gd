# Main.gd
# Main.tscnにアタッチするスクリプト。UIとGameManagerを接続する。
extends Control

# --- ノード参照 ---
@onready var calc_timer:         Timer          = $CalcTimer
@onready var value_display:      Label          = $UI/TopBar/HBox/ValueDisplay
@onready var dps_display:        Label          = $UI/TopBar/HBox/DPSDisplay
@onready var phase_label:        Label          = $UI/TopBar/HBox/PhaseLabel
@onready var cell_ref_label:     Label          = $UI/FormulaBar/HBox/CellRef
@onready var formula_text:       Label          = $UI/FormulaBar/HBox/FormulaText
@onready var spreadsheet:        GridContainer  = $UI/ContentArea/Spreadsheet/Margin/Spreadsheet
@onready var upgrade_list:       VBoxContainer  = $UI/ContentArea/Sidebar/SidebarMargin/SidebarVBox/UpgradeScroll/UpgradeList
@onready var prestige_count_lbl: Label          = $UI/ContentArea/Sidebar/SidebarMargin/SidebarVBox/PrestigeCountLabel
@onready var prestige_panel:     PanelContainer = $PrestigePanel
@onready var num_error_label:    Label          = $PrestigePanel/VBox/NumErrorLabel
@onready var prestige_button:    Button         = $PrestigePanel/VBox/PrestigeButton
@onready var bg:                 ColorRect      = $BG

# Cell.tscnをプリロード
const CELL_SCENE = preload("res://scenes/Cell.tscn")
const CONTEXT_MENU_SCENE = preload("res://scenes/ContextMenu.tscn")

# 現在表示中のCellノード { "A1": Cell, ... }
var cell_nodes: Dictionary = {}
var context_menu_node: Control = null

# フェーズ別設定
const PHASE_LABELS = ["[NORMAL]", "[CORRUPTED]", "[CRITICAL]", "[APOCALYPSE]"]
const PHASE_LABEL_COLORS = [
	Color(1.0, 1.0, 1.0, 0.9),      # NORMAL: 白
	Color(0.98, 0.85, 0.13, 0.85),  # CORRUPTED: 黄
	Color(0.98, 0.40, 0.13, 1.0),   # CRITICAL: オレンジ
	Color(0.98, 0.13, 0.80, 1.0),   # APOCALYPSE: マゼンタ
]
const PHASE_BG_COLORS = [
	Color(0.01, 0.04, 0.02, 1),   # NORMAL: 極深緑
	Color(0.10, 0.08, 0.01, 1),   # CORRUPTED: 汚染黄黒
	Color(0.12, 0.02, 0.04, 1),   # CRITICAL: 崩壊赤黒
	Color(0.04, 0.01, 0.06, 1),   # APOCALYPSE: 崩壊紫黒
]

# グリッチ管理
var _glitch_timer: float = 0.0
const GLITCH_INTERVALS: Array = [9999.0, 7.0, 2.5, 0.6]

func _ready() -> void:
	# GameManagerシグナル接続
	GameManager.cells_updated.connect(_on_cells_updated)
	GameManager.num_error_triggered.connect(_on_num_error_triggered)
	GameManager.prestige_done.connect(_on_prestige_done)
	GameManager.upgrade_applied.connect(_on_upgrade_applied)
	GameManager.phase_changed.connect(_on_phase_changed)

	# タイマー接続
	calc_timer.timeout.connect(_on_calc_timer_timeout)

	# 転生パネルは初期非表示
	prestige_panel.visible = false

	# 右クリックコンテキストメニュー初期化
	context_menu_node = CONTEXT_MENU_SCENE.instantiate()
	add_child(context_menu_node)
	context_menu_node.action_selected.connect(_on_context_menu_action_selected)

	# 初期UI構築
	_rebuild_spreadsheet()
	_rebuild_upgrade_buttons()
	_update_formula_bar()
	_update_phase_ui(GameManager.get_phase())

	# タイマー開始
	calc_timer.start()

# --- メインループ（グリッチ判定）---
func _process(delta: float) -> void:
	var phase := GameManager.get_phase()
	_glitch_timer -= delta
	if _glitch_timer <= 0.0:
		_glitch_timer = GLITCH_INTERVALS[phase]
		if phase != GameManager.GamePhase.NORMAL:
			_do_glitch_frame()

# --- タイマーtick ---
func _on_calc_timer_timeout() -> void:
	GameManager.recalculate()

# --- セル更新 ---
func _on_cells_updated() -> void:
	# 新しいセルが追加されている場合は再構築
	if cell_nodes.size() != GameManager.cells.size():
		_rebuild_spreadsheet()
		_rebuild_upgrade_buttons()
		_update_formula_bar()

	# 全セルの値を更新
	for id in GameManager.cell_order:
		var c: CellData = GameManager.cells[id]
		if cell_nodes.has(id):
			cell_nodes[id].update_value(c.display_value)

	# TopBar更新
	value_display.text = GameManager.coins.to_display_string()
	
	# 真のDPS（1秒あたりのコイン獲得量）＝ 1tickの獲得量 × (1.0 / タイマー間隔)
	var ticks_per_second: float = 1.0 / calc_timer.wait_time
	var real_dps: HugeNumber = GameManager.last_tick_gain.multiply(HugeNumber.from_float(ticks_per_second))
	dps_display.text   = "DPS: " + real_dps.to_display_string()

	# アップグレードボタンの有効/無効を毎tick更新
	_update_upgrade_affordability()

# --- #NUM! 発生 ---
func _on_num_error_triggered() -> void:
	# 全セルをエラー表示
	for id in cell_nodes:
		cell_nodes[id].show_error()

	# TopBar更新
	value_display.text = "#NUM!"
	dps_display.text   = "DPS: ---"

	# 派手なクラッシュ演出
	_play_crash_sequence()

# --- 転生完了 ---
func _on_prestige_done() -> void:
	prestige_panel.visible = false
	_rebuild_spreadsheet()
	_rebuild_upgrade_buttons()
	_update_formula_bar()
	value_display.text = "0"
	dps_display.text   = "DPS: 0"
	prestige_count_lbl.text = "転生: %d回" % GameManager.prestige_count
	_update_phase_ui(GameManager.get_phase())

# --- アップグレード適用後 ---
func _on_upgrade_applied(id: String) -> void:
	if id == "recalc_speed":
		calc_timer.wait_time = max(0.1, calc_timer.wait_time * 0.5)

# --- フェーズ変化 ---
func _on_phase_changed(new_phase: GameManager.GamePhase) -> void:
	_update_phase_ui(new_phase)

# ==============================================
# フェーズUI更新
# ==============================================
func _update_phase_ui(phase: GameManager.GamePhase) -> void:
	var pi := int(phase)

	# PhaseLabel テキスト+色
	phase_label.text = PHASE_LABELS[pi]
	phase_label.add_theme_color_override("font_color", PHASE_LABEL_COLORS[pi])

	# 背景色をゆっくり遷移
	var tween = create_tween()
	tween.tween_property(bg, "color", PHASE_BG_COLORS[pi], 1.2)

# ==============================================
# #NUM! クラッシュシーケンス
# ==============================================
func _play_crash_sequence() -> void:
	# Step1: 画面を真っ赤にフラッシュ（複数回）
	var tween = create_tween()
	for _i in range(3):
		tween.tween_property(self, "modulate", Color(2.0, 0.15, 0.15, 1.0), 0.06)
		tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.08)

	# Step2: 全セルをガタガタ震わせる
	tween.tween_callback(_shake_all_cells)

	# Step3: 1秒後にPrestigePanelをスケールインで登場
	tween.tween_interval(0.8)
	tween.tween_callback(_show_prestige_panel_animated)

func _shake_all_cells() -> void:
	for id in cell_nodes:
		_shake_node(cell_nodes[id], 5, 0.05)

func _shake_node(node: CanvasItem, strength: float, duration: float) -> void:
	var origin = node.position
	var tween = create_tween().set_loops(6)
	tween.tween_property(node, "position",
		origin + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)),
		duration * 0.5)
	tween.tween_property(node, "position", origin, duration * 0.5)

func _show_prestige_panel_animated() -> void:
	prestige_panel.scale = Vector2(0.7, 0.7)
	prestige_panel.modulate = Color(1, 1, 1, 0)
	prestige_panel.visible = true

	var tween = create_tween().set_parallel(true)
	tween.tween_property(prestige_panel, "scale",   Vector2(1.0, 1.0), 0.25)
	tween.tween_property(prestige_panel, "modulate", Color(1,1,1,1),   0.25)

	# #NUM!ラベルを点滅させる
	var blink = create_tween().set_loops()
	blink.tween_property(num_error_label, "modulate:a", 0.2, 0.4)
	blink.tween_property(num_error_label, "modulate:a", 1.0, 0.4)

# ==============================================
# グリッチ演出（CORRUPTED以降）
# ==============================================
func _do_glitch_frame() -> void:
	if cell_nodes.is_empty():
		return

	var ids = GameManager.cell_order.duplicate()
	ids.shuffle()
	var glitch_count := mini(2, ids.size())
	for i in glitch_count:
		var node = cell_nodes.get(ids[i])
		if node == null:
			continue
		var original_pos: Vector2 = node.position
		node.position += Vector2(randf_range(-5, 5), randf_range(-4, 4))
		await get_tree().create_timer(0.07).timeout
		if is_instance_valid(node):
			node.position = original_pos

# ==============================================
# スプレッドシート再構築
# ==============================================
func _rebuild_spreadsheet() -> void:
	spreadsheet.columns = GameManager.max_columns
	for child in spreadsheet.get_children():
		spreadsheet.remove_child(child)
		child.queue_free()
	cell_nodes.clear()

	for r in range(1, GameManager.max_rows + 1):
		for col_idx in range(1, GameManager.max_columns + 1):
			var col_letter = String.chr(64 + col_idx)
			var id = "%s%d" % [col_letter, r]
			if not GameManager.cells.has(id):
				continue
				
			var c: CellData = GameManager.cells[id]
			var cell_node = CELL_SCENE.instantiate()
			spreadsheet.add_child(cell_node)
			cell_node.setup(id, c.cell_type == CellData.CellType.FORMULA)
			cell_node.update_value(c.display_value)
			
			# シグナル接続
			cell_node.cell_clicked.connect(_on_cell_clicked)
			cell_node.cell_double_clicked.connect(_on_cell_double_clicked)
			cell_node.cell_right_clicked.connect(_on_cell_right_clicked)
			
			cell_nodes[id] = cell_node

# ==============================================
# アップグレードボタン再構築
# ==============================================
func _rebuild_upgrade_buttons() -> void:
	for child in upgrade_list.get_children():
		upgrade_list.remove_child(child)
		child.queue_free()

	for upg in GameManager.upgrades:
		# すでに購入済みの1回限りアンロック系アップグレードカードはショップから完全に非表示にする！
		if upg["max"] == 1 and upg["purchased"] >= 1:
			continue
			
		# まだ解放されていないセルのアップグレードカードは非表示
		if upg["id"] == "cell_value_a2" and GameManager.max_rows < 2:
			continue
		if upg["id"] == "cell_value_a3" and GameManager.max_rows < 3:
			continue
		if upg["id"] == "cell_value_a4" and GameManager.max_rows < 4:
			continue
		if upg["id"] == "cell_value_a5" and GameManager.max_rows < 5:
			continue
		if upg["id"] == "cell_value_a6" and GameManager.max_rows < 6:
			continue
			
		# 段階的表示: 行を増やす（2行以上になる）まで SUM カードは非表示！
		if upg["id"] == "add_sum" and GameManager.max_rows < 2:
			continue
			
		# SUM を購入するまで PRODUCT カードは非表示！
		if upg["id"] == "add_product":
			var sum_purchased := false
			for u in GameManager.upgrades:
				if u["id"] == "add_sum" and u["purchased"] == 1:
					sum_purchased = true
					break
			if not sum_purchased:
				continue

		# PRODUCT を購入するまで FACT カードは非表示！
		if upg["id"] == "add_fact":
			var product_purchased := false
			for u in GameManager.upgrades:
				if u["id"] == "add_product" and u["purchased"] == 1:
					product_purchased = true
					break
			if not product_purchased:
				continue
				
		var card := _make_upgrade_card(upg)
		upgrade_list.add_child(card)

func _make_upgrade_card(upg: Dictionary) -> Control:
	var cost: HugeNumber = GameManager.get_upgrade_cost(upg["id"])
	var is_maxed: bool = upg["purchased"] >= upg["max"]
	var can_afford: bool = (not is_maxed) and GameManager.can_afford(cost)

	# カード用PanelContainer
	var card := PanelContainer.new()
	card.name = upg["id"]

	var sb := StyleBoxFlat.new()
	if is_maxed:
		sb.bg_color = Color(0.04, 0.10, 0.04, 1)
		sb.border_color = Color(0.1, 0.4, 0.1, 0.6)
	elif can_afford:
		sb.bg_color = Color(0.07, 0.17, 0.10, 1)
		sb.border_color = Color(0.13, 0.98, 0.56, 0.9)
	else:
		sb.bg_color = Color(0.06, 0.10, 0.18, 1)
		sb.border_color = Color(0.15, 0.25, 0.40, 0.6)
	sb.border_width_left   = 1
	sb.border_width_top    = 1
	sb.border_width_right  = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left     = 4
	sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left  = 4
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# アップグレード名ラベル
	var name_lbl := Label.new()
	name_lbl.text = upg["label"]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color",
		Color(0.5, 0.8, 0.5, 1) if is_maxed else Color(0.9, 0.9, 0.9, 1))
	vbox.add_child(name_lbl)

	# コスト / MAX ラベル
	var cost_lbl := Label.new()
	if is_maxed:
		cost_lbl.text = "MAX"
		cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4, 0.8))
	else:
		cost_lbl.text = "💰 " + cost.to_display_string()
		cost_lbl.add_theme_color_override("font_color",
			Color(0.13, 0.98, 0.56, 1) if can_afford else Color(0.5, 0.5, 0.5, 1))
	cost_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(cost_lbl)

	# 購入ボタン
	if not is_maxed:
		var btn := Button.new()
		btn.name = "BuyBtn"  # find_child()で検索するための名前
		btn.text = "購入"
		btn.add_theme_font_size_override("font_size", 11)
		btn.disabled = not can_afford
		btn.pressed.connect(_on_upgrade_pressed.bind(upg["id"]))
		vbox.add_child(btn)

		# 買えるときに脈動アニメ
		if can_afford:
			var tween = btn.create_tween().set_loops()
			tween.tween_property(btn, "modulate",
				Color(1.2, 1.4, 1.1, 1.0), 0.5)
			tween.tween_property(btn, "modulate",
				Color(1.0, 1.0, 1.0, 1.0), 0.5)

	return card

# ==============================================
# アップグレード購入ボタン 有効/無効を毎tick更新（軽量）
# ==============================================
func _update_upgrade_affordability() -> void:
	for upg in GameManager.upgrades:
		var card := upgrade_list.get_node_or_null(upg["id"])
		if card == null:
			continue

		var is_maxed: bool = upg["purchased"] >= upg["max"]
		if is_maxed:
			continue

		var cost: HugeNumber = GameManager.get_upgrade_cost(upg["id"])
		var can_afford: bool = GameManager.can_afford(cost)

		# ボタンのdisabled更新
		var btn := card.find_child("BuyBtn", true, false) as Button
		if btn == null:
			continue

		var was_disabled := btn.disabled
		btn.disabled = not can_afford

		# 買えるようになった瞬間だけ脈動アニメを開始
		if was_disabled and can_afford:
			var tween = btn.create_tween().set_loops()
			tween.tween_property(btn, "modulate",
				Color(1.2, 1.4, 1.1, 1.0), 0.5)
			tween.tween_property(btn, "modulate",
				Color(1.0, 1.0, 1.0, 1.0), 0.5)
		elif not can_afford:
			# 買えなくなったらアニメリセット
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)

# ==============================================
# アップグレード押下
# ==============================================
func _on_upgrade_pressed(id: String) -> void:
	var success: bool = GameManager.apply_upgrade(id)
	if success:
		_rebuild_upgrade_buttons()

# --- 転生ボタン押下 ---
func _on_prestige_button_pressed() -> void:
	# 転生パネルのアニメを止める
	for node in prestige_panel.get_children():
		if node is Label:
			node.modulate = Color(1, 1, 1, 1)
	GameManager.do_prestige()

# --- FormulaBar更新（最後のFormulaCellを固定表示） ---
func _update_formula_bar() -> void:
	var last_formula_id: String = ""
	for id in GameManager.cell_order:
		var c: CellData = GameManager.cells[id]
		if c.cell_type == CellData.CellType.FORMULA:
			last_formula_id = id

	if last_formula_id == "":
		cell_ref_label.text = ""
		formula_text.text   = ""
		return

	var lc: CellData = GameManager.cells[last_formula_id]
	cell_ref_label.text = last_formula_id
	formula_text.text   = FormulaEngine.formula_to_string(lc)

# ==============================================
# 入力・イベント制御 (メニュー領域外クリックキャンセルなど)
# ==============================================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if context_menu_node and context_menu_node.visible:
				if not context_menu_node.get_global_rect().has_point(event.global_position):
					context_menu_node.visible = false

# --- 左クリック選択時の数式バー更新 ---
func _on_cell_clicked(id: String) -> void:
	if context_menu_node:
		context_menu_node.visible = false # 左クリック時はポップアップを閉じる

	var c: CellData = GameManager.cells[id]
	cell_ref_label.text = id
	if c.cell_type == CellData.CellType.FORMULA:
		formula_text.text = FormulaEngine.formula_to_string(c)
	else:
		formula_text.text = c.raw_value.to_display_string()

# --- 右クリック時のメニュー呼び出し ---
func _on_cell_right_clicked(id: String, mouse_pos: Vector2) -> void:
	if context_menu_node:
		var c: CellData = GameManager.cells[id]
		var next_col_cost = GameManager.get_next_column_cost()
		
		var is_purchased = func(upg_id: String) -> bool:
			for u in GameManager.upgrades:
				if u["id"] == upg_id:
					return u["purchased"] >= 1
			return false
			
		var options = {
			"can_delete": c.cell_type == CellData.CellType.FORMULA,
			"can_add_column": GameManager.max_columns < 5 and GameManager.can_afford(next_col_cost),
			"column_cost": next_col_cost.to_display_string(),
			"can_add_row": GameManager.max_rows < 6 and GameManager.can_afford(GameManager.get_next_row_cost()),
			"row_cost": GameManager.get_next_row_cost().to_display_string(),
			"sum_locked": GameManager.max_columns < 2 or not is_purchased.call("add_sum"),
			"product_locked": GameManager.max_columns < 2 or not is_purchased.call("add_product"),
			"fact_locked": GameManager.max_columns < 2 or not is_purchased.call("add_fact"),
			"power_locked": GameManager.max_columns < 2 or GameManager.prestige_count < 1,
			"tower_locked": GameManager.max_columns < 2 or GameManager.prestige_count < 2,
			
			# 段階的アンロック（前の関数を解放していないと非表示）
			"sum_visible": GameManager.max_rows >= 2,
			"product_visible": is_purchased.call("add_sum"),
			"fact_visible": is_purchased.call("add_product"),
			"power_visible": is_purchased.call("add_fact"),
			"tower_visible": GameManager.prestige_count >= 1
		}
		context_menu_node.open_menu(id, mouse_pos, options)

# --- コンテキストメニューでの選択アクション実行 ---
func _on_context_menu_action_selected(action: String, extra: String) -> void:
	var target_cell_id = context_menu_node.current_cell_id
	match action:
		"insert_function":
			_apply_context_formula(target_cell_id, extra)
		"insert_column":
			_apply_context_insert_column()
		"insert_row":
			_apply_context_insert_row()
		"delete_formula":
			_apply_context_delete_formula(target_cell_id)

func _apply_context_formula(cell_id: String, formula_name: String) -> void:
	var cost_map = {
		"SUM": HugeNumber.from_float(10.0),
		"PRODUCT": HugeNumber.from_float(200.0),
		"POWER": HugeNumber.from_float(1000.0),
		"FACT": HugeNumber.new(5.0, 4), # 5e4
		"TOWER": HugeNumber.new(1.0, 6) # 1e6
	}
	var cost: HugeNumber = cost_map.get(formula_name, HugeNumber.new(0.0, 0))
	if GameManager.coins.compare(cost) < 0:
		return
	
	GameManager.coins = GameManager.coins.subtract(cost)

	var c: CellData = GameManager.cells[cell_id]
	c.cell_type = CellData.CellType.FORMULA
	
	var col_letter = cell_id.substr(0, 1)
	var row = int(cell_id.substr(1))
	var prev_col_letter = String.chr(col_letter.unicode_at(0) - 1)
	
	c.formula_type = CellData.FormulaType.get(formula_name)
	
	match formula_name:
		"SUM":
			if row == 1:
				c.inputs = ["%s1" % prev_col_letter, "%s2" % prev_col_letter]
			else:
				c.inputs = ["%s%d" % [col_letter, row - 1], "%s%d" % [prev_col_letter, row]]
		"PRODUCT":
			if row == 1:
				c.inputs = ["%s1" % prev_col_letter, "%s2" % prev_col_letter]
			else:
				c.inputs = ["%s%d" % [col_letter, row - 1], "%s%d" % [prev_col_letter, row]]
		"POWER":
			if row == 1:
				c.inputs = ["%s1" % prev_col_letter, "%s2" % prev_col_letter]
			else:
				c.inputs = ["%s%d" % [col_letter, row - 1], "%s%d" % [prev_col_letter, row]]
		"FACT":
			c.inputs = ["%s%d" % [col_letter, row - 1] if row > 1 else "%s1" % prev_col_letter]
		"TOWER":
			if row == 1:
				c.inputs = ["%s1" % prev_col_letter, "%s2" % prev_col_letter]
			else:
				c.inputs = ["%s%d" % [col_letter, row - 1], "%s%d" % [prev_col_letter, row]]
			
	GameManager.recalculate()
	_rebuild_spreadsheet()
	_update_formula_bar()

func _apply_context_insert_column() -> void:
	var success = GameManager.add_new_column()
	if success:
		_rebuild_spreadsheet()
		_rebuild_upgrade_buttons()
		_update_formula_bar()

func _apply_context_insert_row() -> void:
	var success = GameManager.add_new_row()
	if success:
		_rebuild_spreadsheet()
		_rebuild_upgrade_buttons()
		_update_formula_bar()

func _apply_context_delete_formula(cell_id: String) -> void:
	var c: CellData = GameManager.cells[cell_id]
	c.cell_type = CellData.CellType.INPUT
	c.raw_value = HugeNumber.new(1.0, 0)
	GameManager.recalculate()
	_rebuild_spreadsheet()
	_update_formula_bar()

# --- セルダブルクリック詳細インスペクター ---
var _current_detail_popup: PanelContainer = null

func _on_cell_double_clicked(cell_id: String) -> void:
	if _current_detail_popup and is_instance_valid(_current_detail_popup):
		_current_detail_popup.queue_free()
		
	var c: CellData = GameManager.cells.get(cell_id)
	if not c:
		return
		
	# インスペクターのPanelContainer生成
	var popup := PanelContainer.new()
	_current_detail_popup = popup
	add_child(popup)
	
	# スタイル設定（ガラス調・サイバーExcelグリーン）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.05, 0.02, 0.96)
	sb.border_color = Color(0.13, 0.98, 0.56, 1.0)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	sb.set_content_margin_all(12)
	popup.add_theme_stylebox_override("panel", sb)
	
	# レイアウト構成
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)
	
	# 1. ヘッダー
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "📊 セルインスペクター [%s]" % cell_id
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.13, 0.98, 0.56, 1.0))
	hbox.add_child(title_lbl)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = " ❌ "
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 9)
	close_btn.pressed.connect(popup.queue_free)
	hbox.add_child(close_btn)
	
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.02, 0.12, 0.05, 1.0))
	vbox.add_child(sep)
	
	# 2. 基本データ
	var is_blank = (not c.cell_type == CellData.CellType.FORMULA and not cell_id.begins_with("A"))
	var type_str := "定数入力セル (CONSTANT)" if cell_id.begins_with("A") else "数式セル (FORMULA)"
	if is_blank:
		type_str = "未配置スロット (EMPTY)"
		
	var type_lbl := Label.new()
	type_lbl.text = "・セルタイプ : %s" % type_str
	type_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(type_lbl)
	
	var val_lbl := Label.new()
	val_lbl.text = "・現在の表示値 : %s" % ("(空白)" if is_blank else c.display_value.to_display_string())
	val_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(val_lbl)
	
	# 数式内容
	if c.cell_type == CellData.CellType.FORMULA:
		var form_lbl := Label.new()
		form_lbl.text = "・適用中数式 : =%s" % FormulaEngine.formula_to_string(c)
		form_lbl.add_theme_font_size_override("font_size", 10)
		form_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8, 1.0))
		vbox.add_child(form_lbl)
		
	# 3. 脳汁要素: 全体DPS貢献度
	var contribution: float = 0.0
	if GameManager.current_max.compare(HugeNumber.from_float(0.0)) > 0:
		var exp_diff = c.display_value.exponent - GameManager.current_max.exponent
		if exp_diff > 5:
			contribution = 100.0
		elif exp_diff < -5:
			contribution = 0.0
		else:
			var base_ratio = c.display_value.mantissa / GameManager.current_max.mantissa
			contribution = base_ratio * pow(10, exp_diff) * 100.0
			contribution = clamp(contribution, 0.0, 100.0)
			
	var contrib_lbl := Label.new()
	contrib_lbl.text = "・秒間売上貢献度 : %.2f %%" % contribution
	contrib_lbl.add_theme_font_size_override("font_size", 10)
	contrib_lbl.add_theme_color_override("font_color", Color(0.98, 0.92, 0.13, 1.0))
	vbox.add_child(contrib_lbl)
	
	# 4. フレーバー豆知識
	var desc := ""
	if is_blank:
		desc = "【未配置セル (EMPTY)】\nまだ何も配置されていない、未来の可能性のマス。右クリックから関数を挿入できる。"
	elif cell_id.begins_with("A"):
		desc = "【定数 (CONSTANT)】\nすべてのインフレの始祖。詳細下のボタン、または右ショップでハック強化できる。"
	else:
		match c.formula_type:
			0: desc = "【SUM (合算)】\nすべてのA列を自動スキャンして合算する。安定した線形生産の要。"
			1: desc = "【PRODUCT (乗算)】\nすべてのB列をスキャンして総乗（掛け合わせ）する。指数爆発の始まり。"
			2: desc = "【FACT (階乗)】\n値を段階的に階乗する。浮動小数点数が熱融解し始める数学災害の引き金。"
			3: desc = "【POWER (べき乗)】\n転生の彼方。天文学的インフレを一瞬で生み出す指数エネルギー。"
			4: desc = "【TOWER (テトレーション)】\nパワーの塔。世界を真の数学崩壊（#NUM!）へと導く、絶対禁忌の最終兵器。"
			
	var desc_lbl := Label.new()
	desc_lbl.text = "\n" + desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 9)
	desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.7, 1.0))
	vbox.add_child(desc_lbl)
	
	# A列なら、インスペクター内から定数ダイレクト強化アクションを追加！！！
	if cell_id.begins_with("A"):
		var a_idx = int(cell_id.substr(1))
		var upg_id = "cell_value_a%d" % a_idx
		var cost = GameManager.get_upgrade_cost(upg_id)
		
		var h_sep := HSeparator.new()
		h_sep.add_theme_color_override("color", Color(0.02, 0.12, 0.05, 1.0))
		vbox.add_child(h_sep)
		
		var upg_btn := Button.new()
		upg_btn.text = "定数ハック強化 (コスト: %s)" % cost.to_display_string()
		upg_btn.add_theme_font_size_override("font_size", 10)
		
		var can_afford = GameManager.can_afford(cost)
		upg_btn.disabled = not can_afford
		
		upg_btn.pressed.connect(func():
			_on_upgrade_pressed(upg_id)
			_on_cell_double_clicked(cell_id) # ポップアップの再描画
		)
		vbox.add_child(upg_btn)

	# 画面中央付近に配置してクリッピング
	popup.size = Vector2(250, 190)
	popup.global_position = get_global_mouse_position() - Vector2(125, 95)
	
	# 画面外はみ出し防止
	var screen_size := get_viewport_rect().size
	popup.global_position.x = clamp(popup.global_position.x, 20, screen_size.x - 270)
	popup.global_position.y = clamp(popup.global_position.y, 20, screen_size.y - 210)
