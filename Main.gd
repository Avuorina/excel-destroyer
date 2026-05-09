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

# 現在表示中のCellノード { "A1": Cell, ... }
var cell_nodes: Dictionary = {}

# フェーズ別設定
const PHASE_LABELS = ["[NORMAL]", "[CORRUPTED]", "[CRITICAL]", "[APOCALYPSE]"]
const PHASE_LABEL_COLORS = [
	Color(0.5, 0.7, 0.9, 0.7),      # NORMAL: 薄ブルー
	Color(0.98, 0.85, 0.13, 0.85),  # CORRUPTED: 黄
	Color(0.98, 0.40, 0.13, 1.0),   # CRITICAL: オレンジ
	Color(0.98, 0.13, 0.80, 1.0),   # APOCALYPSE: マゼンタ
]
const PHASE_BG_COLORS = [
	Color(0.08, 0.10, 0.17, 1),   # NORMAL
	Color(0.10, 0.08, 0.04, 1),   # CORRUPTED: 茶色がかる
	Color(0.12, 0.04, 0.08, 1),   # CRITICAL:  赤紫
	Color(0.04, 0.01, 0.06, 1),   # APOCALYPSE: ほぼ黒
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
	dps_display.text   = "DPS: " + GameManager.last_tick_gain.to_display_string()

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

func _shake_node(node: Node2D, strength: float, duration: float) -> void:
	var origin = node.position if node is Node2D else Vector2.ZERO
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
	for child in spreadsheet.get_children():
		child.queue_free()
	cell_nodes.clear()

	for id in GameManager.cell_order:
		var c: CellData = GameManager.cells[id]
		var cell_node = CELL_SCENE.instantiate()
		spreadsheet.add_child(cell_node)
		cell_node.setup(id, c.cell_type == CellData.CellType.FORMULA)
		cell_node.update_value(c.display_value)
		cell_nodes[id] = cell_node

# ==============================================
# アップグレードボタン再構築
# ==============================================
func _rebuild_upgrade_buttons() -> void:
	for child in upgrade_list.get_children():
		child.queue_free()

	for upg in GameManager.upgrades:
		var card := _make_upgrade_card(upg)
		upgrade_list.add_child(card)

func _make_upgrade_card(upg: Dictionary) -> Control:
	var cost: HugeNumber = GameManager.get_upgrade_cost(upg["id"])
	var is_maxed: bool = upg["purchased"] >= upg["max"]
	var can_afford: bool = (not is_maxed) and \
		(GameManager.coins.to_float() >= cost.to_float())

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
