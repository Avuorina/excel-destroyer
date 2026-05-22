# scripts/HyperMath.gd
class_name HyperMath

# ---------------------------------------------------------
# HyperNumberの演算コア
# ---------------------------------------------------------

static func add(a: HyperNumber, b: HyperNumber) -> HyperNumber:
	if a.is_zero(): return clone(b)
	if b.is_zero(): return clone(a)
	
	# 絶対値が大きい方を base にする
	var base = a
	var sub = b
	if b.compare_abs(a) > 0:
		base = b
		sub = a
		
	# 符号が同じ場合 (加算)
	if base.sign == sub.sign:
		# Layer格差が大きければ sub は無視できる
		if base.layer > sub.layer:
			return clone(base)
			
		if base.layer == 0:
			var result_mag = base.mag + sub.mag
			return HyperNumber.new(base.sign, 0, result_mag)
			
		if base.layer == 1:
			# base.mag >= sub.mag が保証されている
			var diff = base.mag - sub.mag
			if diff > 16.0: # float精度の限界
				return clone(base)
			var result_mag = base.mag + log10(1.0 + pow(10.0, -diff))
			return HyperNumber.new(base.sign, 1, result_mag)
			
		# layer >= 2 では floatの精度的に 1 + eps = 1 になるのでそのまま返す
		return clone(base)
		
	# 符号が違う場合 (減算処理)
	else:
		if base.layer > sub.layer:
			return clone(base)
			
		if base.layer == 0:
			var result_mag = base.mag - sub.mag
			if result_mag <= 0: # 万が一 0 以下の場合は 0 として扱う
				return HyperNumber.new(0, 0, 0.0)
			return HyperNumber.new(base.sign, 0, result_mag)
			
		if base.layer == 1:
			var diff = base.mag - sub.mag
			if diff > 16.0:
				return clone(base)
			if diff == 0.0:
				return HyperNumber.new(0, 0, 0.0)
			var result_mag = base.mag + log10(1.0 - pow(10.0, -diff))
			return HyperNumber.new(base.sign, 1, result_mag)
			
		return clone(base)

static func subtract(a: HyperNumber, b: HyperNumber) -> HyperNumber:
	var neg_b = HyperNumber.new(-b.sign, b.layer, b.mag)
	return add(a, neg_b)

static func multiply(a: HyperNumber, b: HyperNumber) -> HyperNumber:
	if a.is_zero() or b.is_zero():
		return HyperNumber.new(0, 0, 0.0)
		
	var rs = a.sign * b.sign
	
	if a.layer == 0 and b.layer == 0:
		var m = a.mag * b.mag
		return HyperNumber.new(rs, 0, m)
		
	# 乗算は指数(Layer 1)の加算
	# どちらかがLayer 0の場合、Layer 1に変換してから加算
	var a_l1_mag = a.mag if a.layer >= 1 else log10(a.mag)
	var a_l1_layer = max(1, a.layer)
	
	var b_l1_mag = b.mag if b.layer >= 1 else log10(b.mag)
	var b_l1_layer = max(1, b.layer)
	
	var a_l1 = HyperNumber.new(1, a_l1_layer, a_l1_mag)
	var b_l1 = HyperNumber.new(1, b_l1_layer, b_l1_mag)
	
	var exp_sum = add(a_l1, b_l1)
	return HyperNumber.new(rs, exp_sum.layer, exp_sum.mag)

static func power(base: HyperNumber, exp_num: HyperNumber) -> HyperNumber:
	if exp_num.is_zero():
		return HyperNumber.new(1, 0, 1.0)
	if base.is_zero():
		return HyperNumber.new(0, 0, 0.0)
		
	# a^b の計算
	# Layerの限界を押し上げる (ここは一旦Layer1中心に簡易実装、後でTetration対応)
	
	# b が非常に大きい場合、a^b = 10^(b * log10(a))
	var log_a = log10(base.mag) if base.layer == 0 else base.mag
	var log_a_hn = HyperNumber.new(1, base.layer if base.layer > 0 else 0, abs(log_a)) # TODO: 厳密にはlayerを1下げるべきだが、とりあえず近似
	if base.layer == 0:
		log_a_hn = HyperNumber.new(1 if log_a >= 0 else -1, 0, abs(log_a))
	else:
		# base.layer >= 1 の log10(base) は事実上 layer が1下がる
		log_a_hn = HyperNumber.new(1, base.layer - 1, base.mag)

	var new_exp = multiply(exp_num, log_a_hn)
	
	var rs = 1
	if base.sign < 0:
		# 負の数の累乗は指数が奇数か偶数かで変わるが、インフレゲームでは一旦エラー回避で正とするか、floorで判定
		rs = 1 
		
	# 結果は 10^new_exp なので、layerを1つ上げる
	return HyperNumber.new(rs, new_exp.layer + 1, new_exp.mag)

# クローン
static func clone(a: HyperNumber) -> HyperNumber:
	return HyperNumber.new(a.sign, a.layer, a.mag)

static func log10(x: float) -> float:
	return log(x) / log(10.0)
