# scripts/FormulaOperations.gd
class_name FormulaOperations

class BaseOp extends RefCounted:
	func get_cost() -> float: 
		return 1.0
		
	func evaluate(_inputs: Array, _all_cells: Dictionary) -> HyperNumber:
		return HyperNumber.new(0, 0, 0.0)
		
	# 依存セルの値を取得するヘルパー
	func _get_val(id: String, all_cells: Dictionary) -> HyperNumber:
		if all_cells.has(id):
			var c: CellData = all_cells[id]
			# Dirtyフラグが立っている場合は安全のため再計算を促すべきだが、
			# 評価順序（TopoSort）が正しければここでDirtyなことはない。
			return c.cached_value
		return HyperNumber.new(0, 0, 0.0)

class AddOp extends BaseOp:
	func evaluate(inputs: Array, all_cells: Dictionary) -> HyperNumber:
		var result: HyperNumber = HyperNumber.new(0, 0, 0.0)
		for id in inputs:
			# HyperNumberはImmutableに扱うため、常に新しいインスタンスを受け取る
			result = HyperMath.add(result, _get_val(id, all_cells))
		return result

class MulOp extends BaseOp:
	func evaluate(inputs: Array, all_cells: Dictionary) -> HyperNumber:
		var result: HyperNumber = HyperNumber.new(1, 0, 1.0)
		for id in inputs:
			result = HyperMath.multiply(result, _get_val(id, all_cells))
		return result

class PowerOp extends BaseOp:
	func get_cost() -> float: 
		return 5.0 # 指数計算はやや重い
		
	func evaluate(inputs: Array, all_cells: Dictionary) -> HyperNumber:
		if inputs.size() < 2: return HyperNumber.new(0, 0, 0.0)
		var base: HyperNumber = _get_val(inputs[0], all_cells)
		var exp_num: HyperNumber = _get_val(inputs[1], all_cells)
		return HyperMath.power(base, exp_num)

class FactOp extends BaseOp:
	func get_cost() -> float:
		return 10.0
		
	func evaluate(inputs: Array, all_cells: Dictionary) -> HyperNumber:
		if inputs.is_empty(): return HyperNumber.new(1, 0, 1.0)
		var _val = _get_val(inputs[0], all_cells)
		# TODO: Stirling's approximation 等による HyperNumber 階乗計算
		return HyperNumber.new(1, 0, 1.0) # スタブ

class TowerOp extends BaseOp:
	func get_cost() -> float:
		return 50.0 # テトレーションは激重
		
	func evaluate(inputs: Array, all_cells: Dictionary) -> HyperNumber:
		if inputs.size() < 2: return HyperNumber.new(1, 0, 1.0)
		var base: HyperNumber = _get_val(inputs[0], all_cells)
		var exp_num: HyperNumber = _get_val(inputs[1], all_cells)
		# TOWER計算 (スタブ、HyperMath側で実装予定)
		return HyperMath.power(base, HyperMath.power(base, exp_num))
