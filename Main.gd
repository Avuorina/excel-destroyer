# Main.gd
# Main.tscnにアタッチするスクリプト。UIとGameManagerを接続する。
extends Control

# --- ノード参照 ---
@onready var calc_timer:      Timer          = $CalcTimer
@onready var value_display:   Label          = $UI/TopBar/HBox/ValueDisplay
@onready var dps_display:     Label          = $UI/TopBar/HBox/DPSDisplay
@onready var cell_ref_label:  Label          = $UI/FormulaBar/HBox/CellRef
@onready var formula_text:    Label          = $UI/FormulaBar/HBox/FormulaText
@onready var spreadsheet:     GridContainer  = $UI/Spreadsheet/Margin/Spreadsheet
@onready var upgrade_list:    HBoxContainer  = $UI/UpgradePanel/Margin/Scroll/UpgradeList
@onready var prestige_panel:  PanelContainer = $PrestigePanel
@onready var num_error_label: Label          = $PrestigePanel/VBox/NumErrorLabel
@onready var prestige_button: Button         = $PrestigePanel/VBox/PrestigeButton

# Cell.tscnをプリロード
const CELL_SCENE = preload("res://scenes/Cell.tscn")

# 現在表示中のCellノード { "A1": Cell, ... }
var cell_nodes: Dictionary = {}

func _ready() -> void:
	# GameManagerシグナル接続
	GameManager.cells_updated.connect(_on_cells_updated)
	GameManager.num_error_triggered.connect(_on_num_error_triggered)
	GameManager.prestige_done.connect(_on_prestige_done)
	GameManager.upgrade_applied.connect(_on_upgrade_applied)

	# タイマー接続
	calc_timer.timeout.connect(_on_calc_timer_timeout)

	# 転生パネルは初期非表示
	prestige_panel.visible = false

	# 初期UI構築
	_rebuild_spreadsheet()
	_rebuild_upgrade_buttons()
	_update_formula_bar()

	# タイマー開始
	calc_timer.start()

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
	dps_display.text   = "DPS: %.2f" % GameManager.dps

# --- #NUM! 発生 ---
func _on_num_error_triggered() -> void:
	# 全セルをエラー表示
	for id in cell_nodes:
		cell_nodes[id].show_error()

	# TopBar更新
	value_display.text = "#NUM!"
	dps_display.text   = "DPS: ---"

	# 転生パネル表示（Tweenでフラッシュ）
	prestige_panel.visible = true
	_play_num_error_flash()

# --- 転生完了 ---
func _on_prestige_done() -> void:
	prestige_panel.visible = false
	_rebuild_spreadsheet()
	_rebuild_upgrade_buttons()
	_update_formula_bar()
	value_display.text = "0"
	dps_display.text   = "DPS: 0"

# --- アップグレード適用後 ---
func _on_upgrade_applied(id: String) -> void:
	# recalc_speed の場合はTimerの待機時間を短縮
	if id == "recalc_speed":
		calc_timer.wait_time = max(0.1, calc_timer.wait_time * 0.5)

# --- スプレッドシート再構築 ---
func _rebuild_spreadsheet() -> void:
	# 既存の子ノードを削除
	for child in spreadsheet.get_children():
		child.queue_free()
	cell_nodes.clear()

	# GameManagerのcell_orderに従ってセルを生成
	for id in GameManager.cell_order:
		var c: CellData = GameManager.cells[id]
		var cell_node = CELL_SCENE.instantiate()
		spreadsheet.add_child(cell_node)
		cell_node.setup(id, c.cell_type == CellData.CellType.FORMULA)
		cell_node.update_value(c.display_value)
		cell_nodes[id] = cell_node

# --- アップグレードボタン再構築（データ駆動） ---
func _rebuild_upgrade_buttons() -> void:
	for child in upgrade_list.get_children():
		child.queue_free()

	for upg in GameManager.upgrades:
		# 購入上限に達したものはスキップ（または無効表示）
		var btn: Button = Button.new()
		btn.name = upg["id"]

		var cost: HugeNumber = GameManager.get_upgrade_cost(upg["id"])
		btn.text = "%s  [%s]" % [upg["label"], cost.to_display_string()]

		if upg["purchased"] >= upg["max"]:
			btn.text     = "%s  [MAX]" % upg["label"]
			btn.disabled = true
		else:
			# bind()でIDを渡す
			btn.pressed.connect(_on_upgrade_pressed.bind(upg["id"]))

		upgrade_list.add_child(btn)

# --- アップグレード押下 ---
func _on_upgrade_pressed(id: String) -> void:
	var success: bool = GameManager.apply_upgrade(id)
	if success:
		# ボタンテキストを更新するため再構築
		_rebuild_upgrade_buttons()

# --- 転生ボタン押下 ---
func _on_prestige_button_pressed() -> void:
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

# --- #NUM! 演出（Tweenフラッシュ） ---
func _play_num_error_flash() -> void:
	var tween: Tween = create_tween()
	# 背景を赤→元色に戻す
	tween.tween_property(
		self, "modulate",
		Color(1.0, 0.2, 0.2, 1.0), 0.1
	)
	tween.tween_property(
		self, "modulate",
		Color(1.0, 1.0, 1.0, 1.0), 0.4
	)
