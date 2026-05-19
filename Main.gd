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
var selected_cell_id: String = ""
var col_header_nodes: Dictionary = {}
var row_header_nodes: Dictionary = {}
var status_left_label: Label = null
var status_right_label: Label = null

const UPGRADE_DESCRIPTIONS: Dictionary = {
	"cell_value_a1": "定数 A1 の生産基礎値を +0.1 ハックする",
	"cell_value_a2": "定数 A2 の生産基礎値を +0.1 ハックする",
	"cell_value_a3": "定数 A3 の生産基礎値を +0.1 ハックする",
	"cell_value_a4": "定数 A4 の生産基礎値を +0.1 ハックする",
	"cell_value_a5": "定数 A5 の生産基礎値を +0.1 ハックする",
	"cell_value_a6": "定数 A6 の生産基礎値を +0.1 ハックする",
	"recalc_speed": "再計算のディレイを半分に加速する",
	"add_sum": "B列にSUM関数を配置する能力を解放する",
	"add_product": "C列にPRODUCT関数を配置する能力を解放する",
	"add_fact": "D列にFACT関数を配置する能力を解放する"
}

# 動的グリッド用キャッシュ
var _last_cols: int = 0
var _last_rows: int = 0
var _last_cell_count: int = 0

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

	# 数式バーの高さ微調整（28px）および動的 fx ラベルの構築
	var fbar = $UI/FormulaBar as PanelContainer
	if fbar:
		fbar.custom_minimum_size.y = 28
		
		# セルIDラベル: 幅36px、フォント色 #6aaa6a、フォントサイズ 12px
		if cell_ref_label:
			cell_ref_label.custom_minimum_size = Vector2(36, 0)
			cell_ref_label.add_theme_color_override("font_color", Color(0.41, 0.66, 0.41, 1.0))
			cell_ref_label.add_theme_font_size_override("font_size", 12)
			cell_ref_label.text = "A1"
			
		# | セパレーター: 色 #2d4a2d
		var separator = $UI/FormulaBar/HBox/Separator as Label
		if separator:
			separator.add_theme_color_override("font_color", Color(0.17, 0.29, 0.17, 1.0))
			
		# fxラベル: イタリック、色 #4a7a4a、フォントサイズ 11px
		var fx_lbl := Label.new()
		fx_lbl.text = "fx"
		var italic_font := SystemFont.new()
		italic_font.font_italic = true
		italic_font.font_names = ["Arial", "Helvetica", "sans-serif"]
		fx_lbl.add_theme_font_override("font", italic_font)
		fx_lbl.add_theme_font_size_override("font_size", 11)
		fx_lbl.add_theme_color_override("font_color", Color(0.29, 0.48, 0.29, 1.0))
		
		# 値フィールド: 残り幅、等幅フォント、色 #a0c8a0、サイズ 12px
		if formula_text:
			formula_text.add_theme_color_override("font_color", Color(0.62, 0.78, 0.62, 1.0))
			var mono_font := SystemFont.new()
			mono_font.font_names = ["Courier New", "Courier", "monospace"]
			formula_text.add_theme_font_override("font", mono_font)
			formula_text.add_theme_font_size_override("font_size", 12)
		
		var fbar_hbox = $UI/FormulaBar/HBox as HBoxContainer
		if fbar_hbox:
			fbar_hbox.add_child(fx_lbl)
			fbar_hbox.move_child(fx_lbl, 2)

	# TopBarの動大改修（高さ36px・統合三カラム・背景#0f1f0f）
	var top_bar = $UI/TopBar as PanelContainer
	if top_bar:
		top_bar.custom_minimum_size.y = 36
		var top_sb := StyleBoxFlat.new()
		top_sb.bg_color = Color(0.06, 0.12, 0.06, 1.0) # #0f1f0f
		top_sb.border_width_bottom = 1
		top_sb.border_color = Color(0.02, 0.12, 0.05, 1.0)
		top_sb.content_margin_left = 12
		top_sb.content_margin_right = 0
		top_sb.content_margin_top = 0
		top_sb.content_margin_bottom = 0
		top_bar.add_theme_stylebox_override("panel", top_sb)

	var top_hbox = $UI/TopBar/HBox as HBoxContainer
	if top_hbox:
		top_hbox.remove_child(phase_label)
		top_hbox.remove_child(value_display)
		top_hbox.remove_child(dps_display)
		
		for child in top_hbox.get_children():
			top_hbox.remove_child(child)
			child.queue_free()
			
		# 1. LeftBox (Title + Phase Badge)
		var left_box := HBoxContainer.new()
		left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_box.alignment = BoxContainer.ALIGNMENT_BEGIN
		top_hbox.add_child(left_box)
		
		var title_lbl := Label.new()
		title_lbl.text = "ExcelDestroyer"
		title_lbl.add_theme_font_size_override("font_size", 13)
		title_lbl.add_theme_color_override("font_color", Color(0.62, 0.78, 0.62, 1.0)) # #a0c8a0
		var title_font := SystemFont.new()
		title_font.font_names = ["Arial", "Helvetica", "sans-serif"]
		title_lbl.add_theme_font_override("font", title_font)
		left_box.add_child(title_lbl)
		
		var spacer_lbl := Control.new()
		spacer_lbl.custom_minimum_size = Vector2(8, 0)
		left_box.add_child(spacer_lbl)
		
		var phase_badge := PanelContainer.new()
		var p_sb := StyleBoxFlat.new()
		p_sb.bg_color = Color(0.04, 0.10, 0.04, 1.0) # #0a1a0a
		p_sb.border_color = Color(0.16, 0.29, 0.16, 1.0) # #2a4a2a
		p_sb.border_width_left = 1
		p_sb.border_width_top = 1
		p_sb.border_width_right = 1
		p_sb.border_width_bottom = 1
		p_sb.corner_radius_top_left = 2
		p_sb.corner_radius_top_right = 2
		p_sb.corner_radius_bottom_right = 2
		p_sb.corner_radius_bottom_left = 2
		p_sb.content_margin_left = 4
		p_sb.content_margin_top = 4
		p_sb.content_margin_right = 4
		p_sb.content_margin_bottom = 4
		phase_badge.add_theme_stylebox_override("panel", p_sb)
		
		phase_label.add_theme_font_size_override("font_size", 10)
		phase_badge.add_child(phase_label)
		left_box.add_child(phase_badge)
		
		# 2. CenterBox (🪙 79.0 のように中央配置)
		var center_box := HBoxContainer.new()
		center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center_box.alignment = BoxContainer.ALIGNMENT_CENTER
		top_hbox.add_child(center_box)
		
		var coin_icon := Label.new()
		coin_icon.text = "🪙 "
		coin_icon.add_theme_font_size_override("font_size", 14)
		center_box.add_child(coin_icon)
		
		value_display.add_theme_font_size_override("font_size", 14)
		value_display.add_theme_color_override("font_color", Color(0.78, 0.90, 0.78, 1.0)) # #c8e6c8
		
		var mono_font := SystemFont.new()
		mono_font.font_names = ["Courier New", "Courier", "monospace"]
		value_display.add_theme_font_override("font", mono_font)
		center_box.add_child(value_display)
		
		# 3. RightBox (DPS Display without panel - blends into background)
		var right_box := HBoxContainer.new()
		right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_box.alignment = BoxContainer.ALIGNMENT_END
		top_hbox.add_child(right_box)
		
		dps_display.add_theme_font_size_override("font_size", 12)
		dps_display.add_theme_color_override("font_color", Color(0.41, 0.66, 0.41, 1.0)) # #6aaa6a
		right_box.add_child(dps_display)
		
		var pad_right := Control.new()
		pad_right.custom_minimum_size = Vector2(12, 0)
		right_box.add_child(pad_right)
		
	# ショップのカード間隔を4pxに詰める
	upgrade_list.add_theme_constant_override("separation", 4)

	# サイドバー内の下部スペーサー（空のControl）の不要な縦方向拡大(SIZE_EXPAND_FILL)を完全無効化！
	# これにより、UpgradeScroll（ショップ一覧）が縦幅全体に拡張され、初期状態でも一切のスクロールなしでUNLOCKSおよびSUMカードが1画面に収まるぜ！
	var spacer_end = get_node_or_null("UI/ContentArea/Sidebar/SidebarMargin/SidebarVBox/SidebarSpacerEnd") as Control
	if spacer_end:
		spacer_end.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		spacer_end.custom_minimum_size.y = 2 # 必要最小限の空間に抑制

	# 下部ステータスバーの動的生成
	var status_bar := PanelContainer.new()
	status_bar.custom_minimum_size.y = 20
	
	var s_sb := StyleBoxFlat.new()
	s_sb.bg_color = Color(0.04, 0.08, 0.04, 1.0) # #0a150aベース
	s_sb.content_margin_left = 8
	s_sb.content_margin_right = 8
	s_sb.content_margin_top = 2
	s_sb.content_margin_bottom = 2
	status_bar.add_theme_stylebox_override("panel", s_sb)
	
	var s_hbox := HBoxContainer.new()
	s_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(s_hbox)
	
	status_left_label = Label.new()
	status_left_label.add_theme_font_size_override("font_size", 10)
	status_left_label.add_theme_color_override("font_color", Color(0.35, 0.54, 0.35, 1.0)) # #5a8a5a
	s_hbox.add_child(status_left_label)
	
	var s_spacer := Control.new()
	s_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_hbox.add_child(s_spacer)
	
	status_right_label = Label.new()
	status_right_label.add_theme_font_size_override("font_size", 10)
	status_right_label.add_theme_color_override("font_color", Color(0.35, 0.54, 0.35, 1.0))
	s_hbox.add_child(status_right_label)
	
	$UI.add_child(status_bar)

	# 右クリックコンテキストメニュー初期化
	context_menu_node = CONTEXT_MENU_SCENE.instantiate()
	add_child(context_menu_node)
	context_menu_node.action_selected.connect(_on_context_menu_action_selected)

	# 初期UI構築
	_rebuild_spreadsheet()
	_rebuild_upgrade_buttons()
	_update_formula_bar()
	_update_status_bar()
	_update_phase_ui(GameManager.get_phase())

	# スプレッドシートの親コンテナのリサイズを監視し、グリッドを動的に埋め尽くす
	var parent_container = spreadsheet.get_parent().get_parent() as Control
	if parent_container:
		parent_container.resized.connect(_on_spreadsheet_resized)

	# デバッグ用：今回だけ初期の計算速度を4倍速（1.0s -> 0.25s）にブースト
	calc_timer.wait_time = 0.25

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

	# 数式バーの表示値を同期
	_update_formula_bar()

	# TopBar更新
	value_display.text = GameManager.coins.to_display_string()
	
	# 真のDPS（1秒あたりのコイン獲得量）＝ 1tickの獲得量 × (1.0 / タイマー間隔)
	var ticks_per_second: float = 1.0 / calc_timer.wait_time
	var real_dps: HugeNumber = GameManager.last_tick_gain.multiply(HugeNumber.from_float(ticks_per_second))
	dps_display.text   = "DPS: " + real_dps.to_display_string() + " /s"

	# アップグレードボタンの有効/無効を毎tick更新
	_update_upgrade_affordability()
	_update_status_bar()

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
	_update_status_bar()

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
	# 強制的に再構築を走らせるため、キャッシュのセル数を無効値にする
	_last_cell_count = -1
	_adjust_grid_dimensions()

# ==============================================
# 画面サイズに合わせてグリッドの列数・行数・ダミーセルを動的に調整（高速）
# ==============================================
func _adjust_grid_dimensions() -> void:
	var parent_container = spreadsheet.get_parent().get_parent() as Control
	if not parent_container:
		return
		
	var viewport_size = get_viewport_rect().size
	
	# 親コンテナのサイズ直接使用を避け、無限ループを防ぐためビューポート基準の絶対サイズで計算。
	# サイドバー(220px) + マージン(16px) + 行ヘッダー幅(36px) = 272px
	var available_width = viewport_size.x - 272
	# トップバー(64px) + 数式バー(28px) + マージン(16px) + 列ヘッダー高(24px) + ステータスバー(20px) = 152px
	var available_height = viewport_size.y - 152
	
	# セルサイズ(110x60) + 間隔(4px) = 横114px / 縦64px
	var cols = max(GameManager.max_columns, int(floor(available_width / 114.0)))
	var rows = max(GameManager.max_rows, int(floor(available_height / 64.0)))
	
	var active_count = GameManager.cells.size()
	
	# キャッシュ比較
	if cols == _last_cols and rows == _last_rows and active_count == _last_cell_count:
		return
		
	_last_cols = cols
	_last_rows = rows
	_last_cell_count = active_count
	
	# 列ヘッダーを含むため、GridContainerの列数を cols + 1 に設定
	spreadsheet.columns = cols + 1
	
	# 既存セル・ヘッダーをクリーンアップ
	for child in spreadsheet.get_children():
		spreadsheet.remove_child(child)
		child.queue_free()
	cell_nodes.clear()
	col_header_nodes.clear()
	row_header_nodes.clear()
	
	# グリッド走査（ヘッダー含めて走査: rは-1〜rows-1, cは-1〜cols-1）
	for r in range(-1, rows):
		for c in range(-1, cols):
			if r == -1 and c == -1:
				# Corner Box
				var corner := PanelContainer.new()
				corner.custom_minimum_size = Vector2(36, 24)
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0.04, 0.08, 0.04, 1.0) # #0a150aベース
				sb.border_color = Color(0.02, 0.12, 0.05, 1.0) # グリッド枠線
				sb.border_width_right = 1
				sb.border_width_bottom = 1
				corner.add_theme_stylebox_override("panel", sb)
				spreadsheet.add_child(corner)
				
			elif r == -1 and c >= 0:
				# Column Header (A, B, C...)
				var col_letter = String.chr(65 + c)
				var header := PanelContainer.new()
				header.custom_minimum_size = Vector2(110, 24)
				
				var sb := StyleBoxFlat.new()
				sb.border_color = Color(0.02, 0.12, 0.05, 1.0)
				sb.border_width_right = 1
				sb.border_width_bottom = 1
				
				# max_columns未満（解放済み列数、上限5）ならラベルを描画
				if c < GameManager.max_columns:
					sb.bg_color = Color(0.05, 0.12, 0.05, 1.0) # #0e1f0eベース
					header.add_theme_stylebox_override("panel", sb)
					
					var lbl := Label.new()
					lbl.text = col_letter
					lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					lbl.add_theme_font_size_override("font_size", 10)
					
					var sys_font := SystemFont.new()
					sys_font.font_names = ["Courier New", "Courier", "monospace"]
					lbl.add_theme_font_override("font", sys_font)
					lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 1.0)) # #8ac88a
					
					header.add_child(lbl)
					col_header_nodes[col_letter] = header
				else:
					# F列以降はヘッダーラベルなしの透明スペーサー
					sb.bg_color = Color(0, 0, 0, 0)
					header.add_theme_stylebox_override("panel", sb)
					
				spreadsheet.add_child(header)
				
			elif r >= 0 and c == -1:
				# Row Header (1, 2, 3...)
				var r_num = r + 1
				var header := PanelContainer.new()
				header.custom_minimum_size = Vector2(36, 60)
				
				var sb := StyleBoxFlat.new()
				sb.border_color = Color(0.02, 0.12, 0.05, 1.0)
				sb.border_width_right = 1
				sb.border_width_bottom = 1
				
				# 6行以下（行の上限6）ならラベルを描画
				if r_num <= 6:
					sb.bg_color = Color(0.05, 0.12, 0.05, 1.0) # #0e1f0eベース
					header.add_theme_stylebox_override("panel", sb)
					
					var lbl := Label.new()
					lbl.text = str(r_num)
					lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					lbl.add_theme_font_size_override("font_size", 10)
					
					var sys_font := SystemFont.new()
					sys_font.font_names = ["Courier New", "Courier", "monospace"]
					lbl.add_theme_font_override("font", sys_font)
					
					# 解放済み: #5a8a5a, 未解放: #2a4a2a
					if r_num <= GameManager.max_rows:
						lbl.add_theme_color_override("font_color", Color(0.35, 0.54, 0.35, 1.0))
					else:
						lbl.add_theme_color_override("font_color", Color(0.16, 0.29, 0.16, 1.0))
					
					header.add_child(lbl)
					row_header_nodes[r_num] = header
				else:
					# 7行目以降はヘッダーラベルなしの透明スペーサー
					sb.bg_color = Color(0, 0, 0, 0)
					header.add_theme_stylebox_override("panel", sb)
					
				spreadsheet.add_child(header)
				
			else:
				# Cell
				var is_active_area = r < GameManager.max_rows and c < GameManager.max_columns
				if is_active_area:
					var col_letter = String.chr(65 + c)
					var cell_id = "%s%d" % [col_letter, r + 1]
					
					if GameManager.cells.has(cell_id):
						var cell_data = GameManager.cells[cell_id]
						var cell_node = CELL_SCENE.instantiate()
						spreadsheet.add_child(cell_node)
						
						cell_node.setup(cell_id, cell_data.cell_type == CellData.CellType.FORMULA)
						
						if GameManager.is_num_error:
							cell_node.show_error()
						else:
							cell_node.update_value(cell_data.display_value)
							
						cell_node.cell_clicked.connect(_on_cell_clicked)
						cell_node.cell_double_clicked.connect(_on_cell_double_clicked)
						cell_node.cell_right_clicked.connect(_on_cell_right_clicked)
						
						cell_nodes[cell_id] = cell_node
						continue
						
				# Dummy Cell
				var dummy_node = CELL_SCENE.instantiate()
				spreadsheet.add_child(dummy_node)
				dummy_node.setup_empty()
				
	# 選択セルのヘッダーハイライトを復元
	if selected_cell_id != "":
		_update_header_highlights(selected_cell_id)

# ==============================================
# コンテナリサイズ時のイベント
# ==============================================
func _on_spreadsheet_resized() -> void:
	# リサイズ時は境界線をまたいだ時だけ再計算処理を叩く
	_adjust_grid_dimensions()

# ==============================================
# アップグレードボタン再構築
# ==============================================
func _rebuild_upgrade_buttons() -> void:
	for child in upgrade_list.get_children():
		upgrade_list.remove_child(child)
		child.queue_free()

	# 1. 通常カードの選別と描画
	var normal_upgs: Array = []
	for upg in GameManager.upgrades:
		# すでに購入済みの1回限りアンロック系アップグレードカードはショップから完全に非表示にする！
		if upg["max"] == 1 and upg["purchased"] >= 1:
			continue
			
		var is_unlock_card = upg["id"] in ["add_sum", "add_product", "add_fact"]
		if not is_unlock_card:
			# 通常カードのロック条件判定
			var is_locked := false
			var lock_text := ""
			match upg["id"]:
				"cell_value_a2":
					if GameManager.max_rows < 2:
						is_locked = true
						lock_text = "2行目が必要"
				"cell_value_a3":
					if GameManager.max_rows < 3:
						is_locked = true
						lock_text = "3行目が必要"
				"cell_value_a4":
					if GameManager.max_rows < 4:
						is_locked = true
						lock_text = "4行目が必要"
				"cell_value_a5":
					if GameManager.max_rows < 5:
						is_locked = true
						lock_text = "5行目が必要"
				"cell_value_a6":
					if GameManager.max_rows < 6:
						is_locked = true
						lock_text = "6行目が必要"
			
			# 通常カードは条件未達成（ロック中）なら完全に非表示にする（既存仕様を尊重！）
			if is_locked:
				continue
				
			normal_upgs.append(upg)

	for upg in normal_upgs:
		var card := _make_upgrade_card(upg, false, "")
		upgrade_list.add_child(card)

	# 2. アンロックカードの選別と描画
	var unlock_upgs: Array = []
	for upg in GameManager.upgrades:
		if upg["max"] == 1 and upg["purchased"] >= 1:
			continue
			
		var is_unlock_card = upg["id"] in ["add_sum", "add_product", "add_fact"]
		if is_unlock_card:
			var is_locked := false
			var lock_text := ""
			match upg["id"]:
				"add_sum":
					if GameManager.max_rows < 2:
						is_locked = true
						lock_text = "2行解放で使用可能"
				"add_product":
					var sum_purchased := false
					for u in GameManager.upgrades:
						if u["id"] == "add_sum" and u["purchased"] == 1:
							sum_purchased = true
							break
					if not sum_purchased:
						is_locked = true
						lock_text = "SUMアンロックが必要"
				"add_fact":
					var product_purchased := false
					for u in GameManager.upgrades:
						if u["id"] == "add_product" and u["purchased"] == 1:
							product_purchased = true
							break
					if not product_purchased:
						is_locked = true
						lock_text = "PRODUCTアンロックが必要"
			
			unlock_upgs.append({ "upg": upg, "is_locked": is_locked, "lock_text": lock_text })

	# 通常とアンロックの間に見出しと境界線を追加
	if not unlock_upgs.is_empty():
		var spacer_top := Control.new()
		spacer_top.custom_minimum_size = Vector2(0, 2)
		upgrade_list.add_child(spacer_top)
		
		var unlocks_lbl := Label.new()
		unlocks_lbl.text = " — UNLOCKS — "
		unlocks_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlocks_lbl.add_theme_font_size_override("font_size", 10)
		unlocks_lbl.add_theme_color_override("font_color", Color(0.16, 0.48, 0.29, 1.0)) # #2a7a4a
		upgrade_list.add_child(unlocks_lbl)
		
		var sep := HSeparator.new()
		sep.add_theme_color_override("color", Color(0.16, 0.48, 0.29, 0.4))
		upgrade_list.add_child(sep)
		
		var spacer_bot := Control.new()
		spacer_bot.custom_minimum_size = Vector2(0, 2)
		upgrade_list.add_child(spacer_bot)

		for entry in unlock_upgs:
			var card := _make_upgrade_card(entry["upg"], entry["is_locked"], entry["lock_text"])
			upgrade_list.add_child(card)

func _make_upgrade_card(upg: Dictionary, is_locked: bool = false, lock_text: String = "") -> Control:
	var cost: HugeNumber = GameManager.get_upgrade_cost(upg["id"])
	var is_maxed: bool = upg["purchased"] >= upg["max"]
	var can_afford: bool = (not is_maxed) and (not is_locked) and GameManager.can_afford(cost)

	# カード用PanelContainer
	var card := PanelContainer.new()
	card.name = upg["id"]
	if is_locked:
		card.modulate.a = 0.5

	var is_unlock_card = upg["id"] in ["add_sum", "add_product", "add_fact"]

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.10, 0.04, 1.0) # #0a1a0a
	
	if is_unlock_card:
		sb.border_width_left = 3
		sb.border_color = Color(0.16, 0.48, 0.29, 1.0) # #2a7a4a
	else:
		sb.border_width_left = 1
		if is_maxed:
			sb.border_color = Color(0.1, 0.4, 0.1, 0.6)
		elif can_afford:
			sb.border_color = Color(0.23, 0.54, 0.23, 1.0) # #3a8a3a
		else:
			sb.border_color = Color(0.16, 0.29, 0.16, 1.0) # #2a4a2a
			
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 8
	sb.content_margin_top = 6
	sb.content_margin_right = 8
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# 1行目: アップグレード名
	var name_lbl := Label.new()
	name_lbl.text = upg["label"]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.54, 0.78, 0.54, 1.0) # #8ac88a
		if is_maxed or is_locked else Color(0.85, 0.95, 0.85, 1.0))
	vbox.add_child(name_lbl)

	# 2行目: 説明文
	var desc_lbl := Label.new()
	desc_lbl.text = UPGRADE_DESCRIPTIONS.get(upg["id"], "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.29, 0.48, 0.29, 1.0)) # #4a7a4a
	vbox.add_child(desc_lbl)

	# 🔒 条件テキスト表示（ロック中のみ）
	if is_locked:
		var cond_lbl := Label.new()
		cond_lbl.text = "🔒 必要: " + lock_text
		cond_lbl.add_theme_font_size_override("font_size", 9)
		cond_lbl.add_theme_color_override("font_color", Color(0.65, 0.35, 0.35, 1.0)) # 薄い赤
		vbox.add_child(cond_lbl)

	# 3行目: コイン＋コスト＋「購入」ボタンの横並び
	var row_hbox := HBoxContainer.new()
	row_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(row_hbox)

	var cost_lbl := Label.new()
	if is_maxed:
		cost_lbl.text = "MAX"
		cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4, 0.8))
	else:
		cost_lbl.text = "💰 " + cost.to_display_string()
		cost_lbl.add_theme_color_override("font_color",
			Color(0.13, 0.98, 0.56, 1.0) if can_afford else Color(0.5, 0.5, 0.5, 1.0))
	cost_lbl.add_theme_font_size_override("font_size", 10)
	row_hbox.add_child(cost_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_hbox.add_child(spacer)

	# 購入ボタン (Excel風フラットボーダーデザイン)
	if not is_maxed:
		var btn := Button.new()
		btn.name = "BuyBtn"
		btn.text = "購入"
		btn.add_theme_font_size_override("font_size", 10)
		btn.disabled = not can_afford or is_locked
		btn.pressed.connect(_on_upgrade_pressed.bind(upg["id"]))
		
		# ボタンのカスタムフラットスタイルを設定
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = Color(0, 0, 0, 0)
		normal_style.border_color = Color(0.13, 0.98, 0.56, 0.6)
		normal_style.border_width_left = 1
		normal_style.border_width_top = 1
		normal_style.border_width_right = 1
		normal_style.border_width_bottom = 1
		normal_style.corner_radius_top_left = 2
		normal_style.corner_radius_top_right = 2
		normal_style.corner_radius_bottom_right = 2
		normal_style.corner_radius_bottom_left = 2
		normal_style.content_margin_left = 4
		normal_style.content_margin_top = 4
		normal_style.content_margin_right = 4
		normal_style.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", normal_style)
		
		var hover_style := normal_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.13, 0.98, 0.56, 0.15)
		hover_style.border_color = Color(0.13, 0.98, 0.56, 1.0)
		btn.add_theme_stylebox_override("hover", hover_style)
		
		var pressed_style := normal_style.duplicate() as StyleBoxFlat
		pressed_style.bg_color = Color(0.13, 0.98, 0.56, 0.3)
		pressed_style.border_color = Color(0.13, 0.98, 0.56, 1.0)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		
		var disabled_style := normal_style.duplicate() as StyleBoxFlat
		disabled_style.border_color = Color(0.3, 0.3, 0.3, 0.4)
		btn.add_theme_stylebox_override("disabled", disabled_style)

		row_hbox.add_child(btn)

		# 買えるときに脈動アニメ
		if can_afford and not is_locked:
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

# --- FormulaBar更新（選択中のセルのIDと値・数式を同期） ---
func _update_formula_bar(selected_id: String = "") -> void:
	var target_id = selected_id
	if target_id == "":
		target_id = selected_cell_id
	if target_id == "":
		target_id = "A1"

	if not GameManager.cells.has(target_id):
		cell_ref_label.text = target_id
		formula_text.text   = ""
		return

	var c: CellData = GameManager.cells[target_id]
	cell_ref_label.text = target_id
	if c.cell_type == CellData.CellType.FORMULA:
		formula_text.text = FormulaEngine.formula_to_string(c)
	else:
		formula_text.text = c.raw_value.to_display_string()

# --- 下部ステータスバー更新 ---
func _update_status_bar() -> void:
	if not is_instance_valid(status_left_label) or not is_instance_valid(status_right_label):
		return
		
	var max_col_letter = String.chr(65 + GameManager.max_columns - 1)
	var active_cells_count = GameManager.cells.size()
	
	var overflow_limit = "1.79e308"
	if GameManager.prestige_count > 0:
		overflow_limit = "1.79e%d" % (308 + GameManager.prestige_count)
		
	status_left_label.text = "セル数: %d ｜ 解放列: %s ｜ オーバーフロー上限: %s" % [
		active_cells_count,
		max_col_letter,
		overflow_limit
	]
	
	status_right_label.text = "マルチプライヤー: x%d" % GameManager.prestige_multiplier

# ==============================================
# 入力・イベント制御 (メニュー領域外クリックキャンセルなど)
# ==============================================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if context_menu_node and context_menu_node.visible:
				if not context_menu_node.get_global_rect().has_point(event.global_position):
					context_menu_node.visible = false

# --- ヘッダー選択ハイライト更新 ---
func _update_header_highlights(selected_id: String) -> void:
	selected_cell_id = selected_id
	var sel_col = selected_id.substr(0, 1) if selected_id != "" else ""
	var sel_row = int(selected_id.substr(1)) if selected_id != "" else 0

	# 1. 列ヘッダー
	for col_letter in col_header_nodes:
		var panel: PanelContainer = col_header_nodes[col_letter]
		var label: Label = panel.get_child(0) as Label
		var sb: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if not sb:
			continue
		
		# スタイルボックスを複製して個別ハイライトする
		sb = sb.duplicate() as StyleBoxFlat
		panel.add_theme_stylebox_override("panel", sb)

		var c_idx = col_letter.unicode_at(0) - 65
		
		if col_letter == sel_col:
			label.add_theme_color_override("font_color", Color(0.62, 0.78, 0.62, 1.0)) # #a0c8a0ハイライト
			sb.border_width_bottom = 2
			sb.border_color = Color(0.62, 0.78, 0.62, 1.0)
		else:
			sb.border_width_bottom = 1
			sb.border_color = Color(0.02, 0.12, 0.05, 1.0)
			if c_idx < GameManager.max_columns:
				label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 1.0)) # #8ac88a
			else:
				label.add_theme_color_override("font_color", Color(0.22, 0.41, 0.22, 1.0)) # #3a6a3a

	# 2. 行ヘッダー
	for r_num in row_header_nodes:
		var panel: PanelContainer = row_header_nodes[r_num]
		var label: Label = panel.get_child(0) as Label
		var sb: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if not sb:
			continue
		
		sb = sb.duplicate() as StyleBoxFlat
		panel.add_theme_stylebox_override("panel", sb)
		
		if r_num == sel_row:
			label.add_theme_color_override("font_color", Color(0.62, 0.78, 0.62, 1.0)) # #a0c8a0ハイライト
			sb.border_width_right = 2
			sb.border_color = Color(0.62, 0.78, 0.62, 1.0)
		else:
			sb.border_width_right = 1
			sb.border_color = Color(0.02, 0.12, 0.05, 1.0)
			if r_num <= GameManager.max_rows:
				label.add_theme_color_override("font_color", Color(0.35, 0.54, 0.35, 1.0)) # #5a8a5a
			else:
				label.add_theme_color_override("font_color", Color(0.16, 0.29, 0.16, 1.0)) # #2a4a2a

# --- 左クリック選択時の数式バー更新 ---
func _on_cell_clicked(id: String) -> void:
	if context_menu_node:
		context_menu_node.visible = false # 左クリック時はポップアップを閉じる

	_update_header_highlights(id)
	_update_formula_bar(id)

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
			"sum_locked": GameManager.max_columns < 2 or not is_purchased.call("add_sum") or id.begins_with("A"),
			"product_locked": GameManager.max_columns < 2 or not is_purchased.call("add_product") or id.begins_with("A"),
			"fact_locked": GameManager.max_columns < 2 or not is_purchased.call("add_fact") or id.begins_with("A"),
			"power_locked": GameManager.max_columns < 2 or GameManager.prestige_count < 1 or id.begins_with("A"),
			"tower_locked": GameManager.max_columns < 2 or GameManager.prestige_count < 2 or id.begins_with("A"),
			
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
		"FACT": HugeNumber.from_float(1000.0),
		"POWER": HugeNumber.new(5.0, 4),  # 50,000.0
		"TOWER": HugeNumber.new(1.0, 6)  # 1,000,000.0
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
	
	match formula_name:
		"SUM":
			c.formula_type = CellData.FormulaType.SUM
			if row == 1:
				c.inputs = ["%s1" % prev_col_letter, "%s2" % prev_col_letter]
			else:
				c.inputs = ["%s%d" % [col_letter, row - 1], "%s%d" % [prev_col_letter, row]]
		"PRODUCT":
			c.formula_type = CellData.FormulaType.PRODUCT
			if row == 1:
				c.inputs = ["%s1" % prev_col_letter, "%s2" % prev_col_letter]
			else:
				c.inputs = ["%s%d" % [col_letter, row - 1], "%s%d" % [prev_col_letter, row]]
		"POWER":
			c.formula_type = CellData.FormulaType.POWER
			if row == 1:
				c.inputs = ["%s1" % prev_col_letter, "%s2" % prev_col_letter]
			else:
				c.inputs = ["%s%d" % [col_letter, row - 1], "%s%d" % [prev_col_letter, row]]
		"FACT":
			c.formula_type = CellData.FormulaType.FACT
			c.inputs = ["%s%d" % [prev_col_letter, row]]
		"TOWER":
			c.formula_type = CellData.FormulaType.TOWER
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
	_on_cell_clicked(cell_id)
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
	sb.content_margin_left = 12
	sb.content_margin_top = 12
	sb.content_margin_right = 12
	sb.content_margin_bottom = 12
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
