# scripts/GraphView.gd
extends CanvasLayer

var text_edit: TextEdit

func _ready() -> void:
	layer = 99 # DebugOverlayの下
	
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.custom_minimum_size = Vector2(300, 200)
	panel.position = Vector2(850, 400) # 右下に配置
	
	text_edit = TextEdit.new()
	text_edit.editable = false
	text_edit.add_theme_font_size_override("font_size", 12)
	text_edit.add_theme_color_override("font_color", Color.CYAN)
	
	panel.add_child(text_edit)
	add_child(panel)

func update_view(all_cells: Dictionary, order: Array[String], cycles: Array[Array]) -> void:
	var s = "=== Math Network ===\n\n"
	
	s += "[ Topological Order ]\n"
	s += " -> ".join(order) + "\n\n"
	
	s += "[ Dependencies ]\n"
	for id in order:
		var c = all_cells.get(id)
		if c and c.dependents.size() > 0:
			s += "%s → %s\n" % [id, ", ".join(c.dependents)]
			
	s += "\n[ Infinity Loops ]\n"
	if cycles.is_empty():
		s += "None\n"
	else:
		for cycle in cycles:
			var path_str = ""
			for node in cycle:
				path_str += str(node) + " -> "
			path_str += str(cycle[0])
			s += " ↻ " + path_str + "\n"
		
	text_edit.text = s
