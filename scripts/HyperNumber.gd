# scripts/HyperNumber.gd
# 宇宙を破壊するための超巨大数クラス（OmegaNum / ExpantaNum ライクな実装）
class_name HyperNumber

@warning_ignore("shadowed_global_identifier")
var sign: int = 1
var layer: int = 0
var mag: float = 0.0

static var alloc_count: int = 0

const PROMOTE_THRESHOLD = 1e300
const DEMOTE_THRESHOLD = 295.0 # 10^295

# ---------------------------------------------------------
# 初期化
# ---------------------------------------------------------
func _init(s: int = 1, l: int = 0, m: float = 0.0) -> void:
	HyperNumber.alloc_count += 1
	sign = s
	layer = l
	mag = m
	_normalize()

# 内部データの正規化 (layer昇格/降格、ヒステリシス対応、NaN/INF保護)
func _normalize() -> void:
	if is_nan(mag):
		sign = 0
		layer = 0
		mag = 0.0
		return
		
	if is_inf(mag):
		mag = 1e300 # limit for promote
		
	if sign == 0 or mag == 0.0:
		sign = 0
		layer = 0
		mag = 0.0
		return
	
	if mag < 0:
		sign *= -1
		mag = abs(mag)
		
	# Layer昇格と降格の連鎖
	while true:
		if layer == 0:
			if mag < 1e-15:
				sign = 0
				mag = 0.0
				break
			elif mag >= PROMOTE_THRESHOLD:
				layer = 1
				mag = log10(mag)
				continue
			break
		else:
			# layer >= 1
			if mag < 0:
				mag = 0.0 # フェイルセーフ
				break
			
			if layer == 1 and mag < DEMOTE_THRESHOLD:
				layer = 0
				mag = pow(10.0, mag)
				continue
			
			if layer == 2 and mag < log10(DEMOTE_THRESHOLD):
				layer = 1
				mag = pow(10.0, mag)
				continue
				
			if mag >= PROMOTE_THRESHOLD:
				layer += 1
				mag = log10(mag)
				continue
			break

# ---------------------------------------------------------
# 比較
# ---------------------------------------------------------
func is_zero() -> bool:
	return sign == 0

func compare(other: HyperNumber) -> int:
	if sign != other.sign:
		return 1 if sign > other.sign else -1
	if is_zero():
		return 0
		
	var cmp := 0
	if layer != other.layer:
		cmp = 1 if layer > other.layer else -1
	else:
		if abs(mag - other.mag) < 1e-10:
			cmp = 0
		else:
			cmp = 1 if mag > other.mag else -1
			
	return cmp if sign > 0 else -cmp

func compare_abs(other: HyperNumber) -> int:
	if is_zero() and other.is_zero(): return 0
	if is_zero(): return -1
	if other.is_zero(): return 1
	
	if layer != other.layer:
		return 1 if layer > other.layer else -1
	if abs(mag - other.mag) < 1e-10:
		return 0
	return 1 if mag > other.mag else -1

func eq(other: HyperNumber) -> bool: return compare(other) == 0
func lt(other: HyperNumber) -> bool: return compare(other) < 0
func lte(other: HyperNumber) -> bool: return compare(other) <= 0
func gt(other: HyperNumber) -> bool: return compare(other) > 0
func gte(other: HyperNumber) -> bool: return compare(other) >= 0

# ---------------------------------------------------------
# 旧 HugeNumber 互換レイヤー (Phase A 必須)
# ---------------------------------------------------------
static func from_huge(old) -> HyperNumber:
	if old == null:
		return HyperNumber.new(0, 0, 0.0)
	var m: float = old.mantissa
	var e: int = old.exponent
	
	if m == 0.0:
		return HyperNumber.new(0, 0, 0.0)
		
	var s := 1 if m >= 0 else -1
	m = abs(m)
	
	var log_val = log10(m) + float(e)
	
	if log_val < 300.0 and log_val > -300.0:
		return HyperNumber.new(s, 0, pow(10.0, log_val))
	else:
		return HyperNumber.new(s, 1, log_val)

static func from_mantissa_exponent(m: float, e: int) -> HyperNumber:
	if m == 0.0:
		return HyperNumber.new(0, 0, 0.0)
	
	var s := 1 if m > 0 else -1
	m = abs(m)
	
	var log_val = log10(m) + float(e)
	
	if log_val < 300.0 and log_val > -300.0:
		return HyperNumber.new(s, 0, pow(10.0, log_val))
	else:
		return HyperNumber.new(s, 1, log_val)

func to_huge():
	var huge = load("res://scripts/HugeNumber.gd").new()
	if sign == 0:
		huge.mantissa = 0.0
		huge.exponent = 0
		return huge
		
	if layer == 0:
		var e = int(floor(log10(mag)))
		var m = (mag / pow(10.0, e)) * sign
		huge.mantissa = m
		huge.exponent = e
	elif layer == 1:
		var e = int(floor(mag))
		var m = pow(10.0, mag - float(e)) * sign
		huge.mantissa = m
		huge.exponent = e
	else:
		# Layer >= 2 は HugeNumber では扱えないためカンスト値を返す
		huge.mantissa = 9.99 * sign
		huge.exponent = 922337203685477580 # 適当な極大値
		
	return huge

static func log10(x: float) -> float:
	return log(x) / log(10.0)

