# scripts/NotationSystem.gd
class_name NotationSystem

# 様々なフォーマット（Scientific, Engineering, EE, Arrow等）を一括管理する

enum NotationMode {
	SCIENTIFIC,
	ENGINEERING,
	DOUBLE_EXP,
	ARROW
}

static var current_mode: NotationMode = NotationMode.SCIENTIFIC

static func format(num: HyperNumber) -> String:
	if num.sign == 0:
		return "0"
		
	var s_str = "" if num.sign > 0 else "-"
	
	match current_mode:
		NotationMode.SCIENTIFIC:
			return s_str + _format_scientific(num.layer, num.mag)
		NotationMode.DOUBLE_EXP:
			return s_str + _format_double_exp(num.layer, num.mag)
		_:
			return s_str + _format_scientific(num.layer, num.mag)

static func _format_scientific(layer: int, mag: float) -> String:
	if layer == 0:
		if mag < 1000000:
			# 小さい数字はカンマ区切り風か小数第2位
			return str(snapped(mag, 0.01))
		else:
			var e = floor(log10(mag))
			var m = mag / pow(10.0, e)
			return "%.2fe%d" % [m, e]
	elif layer == 1:
		var e = floor(mag)
		var m = pow(10.0, mag - e)
		if e < 1000000:
			return "%.2fe%d" % [m, e]
		else:
			return "e%.2fe%d" % [m, e]
	elif layer == 2:
		return "ee%.2f" % [mag]
	else:
		return "e".repeat(layer) + "%.2f" % [mag]

static func _format_double_exp(layer: int, mag: float) -> String:
	if layer == 0:
		if mag < 1000000:
			return str(snapped(mag, 0.01))
		var e = floor(log10(mag))
		var m = mag / pow(10.0, e)
		return "%.2fe%d" % [m, e]
	elif layer == 1:
		if mag < 1e6:
			var e = floor(mag)
			var m = pow(10.0, mag - e)
			return "%.2fe%d" % [m, e]
		return "ee%.2f" % log10(mag)
	elif layer == 2:
		return "ee%.2f" % mag
	else:
		return "e".repeat(layer) + "%.2f" % mag

static func log10(x: float) -> float:
	return log(x) / log(10.0)
