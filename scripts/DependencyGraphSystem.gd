# scripts/DependencyGraphSystem.gd
extends Node

signal infinity_loop_generated(cycle_nodes: Array, cycle_depth: int, instability: float, entropy: float)

var _evaluation_order: Array[String] = []
var _cycles: Array[Array] = []
var _entropy: float = 0.0

# ---------------------------------------------------------
# 1. グラフ再構築 & オプティマイザ
# ---------------------------------------------------------
func update_graph(all_cells: Dictionary) -> void:
	# リンククリア
	for c in all_cells.values():
		c.dependents.clear()
		c.dependencies.clear()
		
	# リンク再構築と数式最適化
	for c in all_cells.values():
		if c.cell_type == CellData.CellType.FORMULA:
			c.inputs = _optimize_formula(c, all_cells)
			for input_id in c.inputs:
				if all_cells.has(input_id):
					c.dependencies.append(input_id)
					all_cells[input_id].dependents.append(c.cell_id)

	# トポロジカルソートと循環抽出
	_analyze_graph(all_cells)
	
	# GraphViewがあれば更新
	var view = get_node_or_null("/root/GraphView")
	if view and view.has_method("update_view"):
		view.update_view(all_cells, _evaluation_order, _cycles)

# ---------------------------------------------------------
# 2. Dirty Propagation (再帰汚染)
# ---------------------------------------------------------
func mark_dirty(start_id: String, all_cells: Dictionary) -> void:
	if not all_cells.has(start_id): return
	var queue = [start_id]
	while queue.size() > 0:
		var curr = queue.pop_front()
		if all_cells.has(curr):
			var c: CellData = all_cells[curr]
			if not c.is_dirty:
				c.is_dirty = true
				for dep in c.dependents:
					queue.append(dep)

# ---------------------------------------------------------
# 3. Topological Sort
# ---------------------------------------------------------
func get_evaluation_order() -> Array[String]:
	return _evaluation_order

func _analyze_graph(all_cells: Dictionary) -> void:
	var in_degree = {}
	for id in all_cells.keys():
		in_degree[id] = 0
		
	for id in all_cells.keys():
		var cell: CellData = all_cells[id]
		for dep in cell.dependents:
			if not in_degree.has(dep): in_degree[dep] = 0
			in_degree[dep] += 1
			
	var queue = []
	for id in in_degree.keys():
		if in_degree[id] == 0:
			queue.append(id)
			
	_evaluation_order.clear()
	while queue.size() > 0:
		var curr = queue.pop_front()
		_evaluation_order.append(curr)
		if all_cells.has(curr):
			var cell: CellData = all_cells[curr]
			for dep in cell.dependents:
				in_degree[dep] -= 1
				if in_degree[dep] == 0:
					queue.append(dep)
					
	# 循環参照チェック
	_cycles.clear()
	if _evaluation_order.size() != all_cells.size():
		_extract_cycles(all_cells)
		_process_entropy()

# ---------------------------------------------------------
# 4. Cycle Detection & 5. Entropy System
# ---------------------------------------------------------
func _extract_cycles(all_cells: Dictionary) -> void:
	var visited = {}
	var rec_stack = {}
	var path = []
	
	for id in all_cells.keys():
		if not visited.has(id):
			_dfs(id, all_cells, visited, rec_stack, path)

func _dfs(node: String, all_cells: Dictionary, visited: Dictionary, rec_stack: Dictionary, path: Array) -> void:
	visited[node] = true
	rec_stack[node] = true
	path.append(node)
	
	if all_cells.has(node):
		for dep in all_cells[node].dependents:
			if not visited.has(dep):
				_dfs(dep, all_cells, visited, rec_stack, path)
			elif rec_stack.has(dep) and rec_stack[dep]:
				# 循環を抽出
				var cycle_start = path.find(dep)
				if cycle_start != -1:
					var cycle_nodes = path.slice(cycle_start, path.size())
					_cycles.append(cycle_nodes)
					
	rec_stack[node] = false
	path.pop_back()

func _process_entropy() -> void:
	for cycle in _cycles:
		var cycle_depth = cycle.size()
		var instability = float(cycle_depth) * 1.5
		_entropy += instability * 0.1
		
		# EventBus経由で資源獲得（本来はここで独自通貨化）
		emit_signal("infinity_loop_generated", cycle, cycle_depth, instability, _entropy)

# ---------------------------------------------------------
# 6. Formula Optimizer
# ---------------------------------------------------------
func _optimize_formula(cell: CellData, all_cells: Dictionary) -> Array[String]:
	var new_inputs = cell.inputs.duplicate()
	
	# TODO: 恒等式の除去 (例: A1 * 1 -> A1)
	# 後半のTick圧縮や数千セル処理を見据えたオプティマイザ。
	# 現段階ではスタブとしてそのまま返す。
	
	return new_inputs
