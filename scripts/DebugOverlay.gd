# scripts/DebugOverlay.gd
extends CanvasLayer

var label: Label

func _ready() -> void:
	layer = 100 # 最前面
	
	label = Label.new()
	label.add_theme_color_override("font_color", Color.GREEN)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_font_size_override("font_size", 12)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_left", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)
	
	add_child(margin)

func _process(_delta: float) -> void:
	if not visible: return
	
	var hn_allocs = 0
	if ClassDB.class_exists("HyperNumber"):
		# 簡易的なアクセス (GDScriptではstatic変数をクラス名で直接参照可能)
		hn_allocs = HyperNumber.alloc_count
		
	var fps = Engine.get_frames_per_second()
	var time_node = get_node_or_null("/root/GameTime")
	var t_time = time_node.tick_time if time_node else 0.0
	
	var store_node = get_node_or_null("/root/Store")
	var current_layer = store_node.state["layer"] if store_node else 0
	
	var text = "[Debug Overlay]\n"
	text += "FPS: %d\n" % fps
	text += "Current Layer: %d\n" % current_layer
	text += "Tick Time: %.1f\n" % t_time
	text += "HN Allocs: %d\n" % hn_allocs
	
	label.text = text
