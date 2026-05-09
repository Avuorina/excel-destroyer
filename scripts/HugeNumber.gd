# scripts/HugeNumber.gd
# 巨大数クラス。float限界(1.79e308)を突破するためのラッパー。
# TODO: MVPはfloatベース演算。将来的に多倍長整数へ置換予定。
class_name HugeNumber

var mantissa: float  # 1.0 <= |mantissa| < 10.0
var exponent: int    # 10の指数部

func _init(m: float = 0.0, e: int = 0) -> void:
	mantissa = m
	exponent = e
	_normalize()

func _normalize() -> void:
	if abs(mantissa) < 1e-15:
		mantissa = 0.0
		exponent = 0
		return
	while abs(mantissa) >= 10.0:
		mantissa /= 10.0
		exponent += 1
	while abs(mantissa) < 1.0 and mantissa != 0.0:
		mantissa *= 10.0
		exponent -= 1

# 加算: 大きい方を基準に揃えて計算（負diffバグ修正済み）
func add(other: HugeNumber) -> HugeNumber:
	if mantissa == 0.0:
		return HugeNumber.new(other.mantissa, other.exponent)
	if other.mantissa == 0.0:
		return HugeNumber.new(mantissa, exponent)

	# 必ず大きい方をaに揃える
	var a: HugeNumber = self
	var b: HugeNumber = other
	if b.exponent > a.exponent:
		a = other
		b = self

	var diff: int = a.exponent - b.exponent  # 必ず >= 0

	# 差が大きすぎる場合はaがそのまま支配的
	if diff >= 16:
		return HugeNumber.new(a.mantissa, a.exponent)

	var result: HugeNumber = HugeNumber.new()
	result.mantissa = a.mantissa + b.mantissa * pow(10.0, -diff)
	result.exponent = a.exponent
	result._normalize()
	return result

# 乗算
func multiply(other: HugeNumber) -> HugeNumber:
	return HugeNumber.new(mantissa * other.mantissa, exponent + other.exponent)

# 累乗: 上限制御あり（9^9999999999 等で死なないように）
func power(exp_num: HugeNumber) -> HugeNumber:
	var e: int = int(exp_num.to_float())
	e = clamp(e, 0, 1000)  # 指数上限1000

	if e == 0:
		return HugeNumber.new(1.0, 0)

	# 結果の指数が爆発する場合は上限値を返す
	if exponent * e > 1_000_000:
		return HugeNumber.new(1.0, 1_000_000)

	return HugeNumber.new(pow(mantissa, e), exponent * e)

# float変換（DPS計算・コスト比較用）
func to_float() -> float:
	return mantissa * pow(10.0, exponent)

# ゼロ判定
func is_zero() -> bool:
	return mantissa == 0.0

# 比較: self > other なら 1、self < other なら -1、等しければ 0
# exponent先比較で超高速化
func compare(other: HugeNumber) -> int:
	var self_zero := is_zero()
	var other_zero := other.is_zero()
	if self_zero and other_zero:
		return 0
	if self_zero:
		return -1 if other.mantissa > 0.0 else 1
	if other_zero:
		return 1 if mantissa > 0.0 else -1

	var s1 := 1 if mantissa > 0.0 else -1
	var s2 := 1 if other.mantissa > 0.0 else -1
	if s1 != s2:
		return 1 if s1 > s2 else -1

	if s1 > 0:
		if exponent != other.exponent:
			return 1 if exponent > other.exponent else -1
		if abs(mantissa - other.mantissa) < 1e-11:
			return 0
		return 1 if mantissa > other.mantissa else -1
	else:
		if exponent != other.exponent:
			return -1 if exponent > other.exponent else 1
		if abs(mantissa - other.mantissa) < 1e-11:
			return 0
		return -1 if mantissa > other.mantissa else 1

# 最小値クランプ
func clamp_min(min_val: HugeNumber) -> HugeNumber:
	if compare(min_val) < 0:
		return HugeNumber.new(min_val.mantissa, min_val.exponent)
	return HugeNumber.new(mantissa, exponent)

# 減算
func subtract(other: HugeNumber) -> HugeNumber:
	if other.mantissa == 0.0:
		return HugeNumber.new(mantissa, exponent)
	if mantissa == 0.0:
		return HugeNumber.new(-other.mantissa, other.exponent)

	var diff: int = exponent - other.exponent

	if diff >= 16:
		return HugeNumber.new(mantissa, exponent)
	if diff <= -16:
		return HugeNumber.new(-other.mantissa, other.exponent)

	var result: HugeNumber = HugeNumber.new()
	result.mantissa = mantissa - other.mantissa * pow(10.0, -diff)
	result.exponent = exponent
	result._normalize()
	return result

# 表示文字列
func to_display_string() -> String:
	if exponent < 6:
		return str(snapped(to_float(), 0.01))
	return "%.2fe%d" % [mantissa, exponent]

# オーバーフロー判定
func is_overflow(limit: HugeNumber) -> bool:
	if exponent != limit.exponent:
		return exponent > limit.exponent
	return mantissa >= limit.mantissa

# floatからHugeNumberを生成
static func from_float(v: float) -> HugeNumber:
	if v == 0.0:
		return HugeNumber.new(0.0, 0)
	var e: int = int(floor(log(abs(v)) / log(10.0)))
	return HugeNumber.new(v / pow(10.0, e), e)
