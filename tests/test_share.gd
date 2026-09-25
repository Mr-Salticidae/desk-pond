extends SceneTree
# 分享码的无头测试：
#   godot --headless --path . --script tests/test_share.gd
# 全部通过时退出码 0，否则 1。

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_roundtrip()
	_test_extract_from_link_and_text()
	_test_rejects_garbage()
	_test_tamper_detected()
	_test_limits_and_unknown_indices()
	_test_name_cleaning()
	_test_render_models()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _fish_data() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_data.json"))

func _tank() -> EcoTank:
	var t := EcoTank.new()
	t.bind(EcoTank.default_state(), _fish_data())
	return t

func _sample_snap() -> Dictionary:
	return {
		"name": "小鱼的摸鱼缸",
		"tank_level": 2,
		"stars": 4,
		"oxygen": 87,
		"clean": 64,
		"fish": {"commute_sardine": 6, "annual_koi": 1, "overtime_eel": 2},
		"levels": {"commute_sardine": 3, "annual_koi": 1, "overtime_eel": 2},
		"visitors": ["hermit_crab", "turtle"],
		"placed": [
			{"id": "shipwreck", "x": 0.5, "d": 0.6, "flip": true},
			{"id": "grass", "x": 0.1, "d": 0.0, "flip": false},
			{"id": "duckweed", "x": 1.0, "d": 1.0, "flip": false},
		],
	}

func _test_roundtrip() -> void:
	var eco := _tank()
	var code := EcoShare.encode(_sample_snap(), eco)
	_check(code.length() > 10 and code.length() < 200, "code is short (%d chars)" % code.length())
	var ok := true
	for ch in code:
		ok = ok and ((ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_")
	_check(ok, "code is URL safe")
	var s := EcoShare.decode(code, eco)
	_check(not s.is_empty(), "decodes")
	_check(String(s["name"]) == "小鱼的摸鱼缸", "name survives")
	_check(int(s["tank_level"]) == 2 and int(s["stars"]) == 4, "level and stars")
	_check(int(s["oxygen"]) == 87 and int(s["clean"]) == 64, "oxygen and clean")
	_check(int(s["fish"]["commute_sardine"]) == 6 and int(s["levels"]["commute_sardine"]) == 3, "fish counts and levels")
	_check((s["visitors"] as Array).has("hermit_crab") and (s["visitors"] as Array).has("turtle") and (s["visitors"] as Array).size() == 2, "visitors")
	var placed: Array = s["placed"]
	_check(placed.size() == 3 and String(placed[0]["id"]) == "shipwreck" and bool(placed[0]["flip"]), "placed items keep order and flip")
	_check(absf(float(placed[0]["x"]) - 0.5) < 0.01 and absf(float(placed[0]["d"]) - 0.6) < 0.01, "positions within quantization")

	# 从真实缸拍快照再编码，结果应与缸一致
	eco.state["shells"] = 999
	var ctx := {"fish_counts": {"slacking_crucian": 5, "salted_fish": 2}, "total_sessions": 3}
	eco.buy("rock", ctx)
	eco.place("rock", 0.3, 0.7)
	var ev := eco.evaluate(ctx)
	var snap := EcoShare.snapshot(eco, ev, {"slacking_crucian": 3, "salted_fish": 2}, "  我的缸 ")
	var back := EcoShare.decode(EcoShare.encode(snap, eco), eco)
	_check(String(back["name"]) == "我的缸", "snapshot name trimmed")
	_check(int(back["fish"]["slacking_crucian"]) == int(ev["per_species"]["slacking_crucian"]), "snapshot fish match tank")
	_check((back["placed"] as Array).size() == eco.placed().size(), "snapshot placed match tank")

func _test_extract_from_link_and_text() -> void:
	var eco := _tank()
	var code := EcoShare.encode(_sample_snap(), eco)
	_check(EcoShare.extract_code("https://www.bilibili.com/toy/x/index.html?tank=%s&from=share" % code) == code, "code from link with more params")
	_check(EcoShare.extract_code("来看看我的缸！ https://a.b/index.html?tank=%s 好看吗" % code) == code, "code from share text")
	_check(EcoShare.extract_code("  %s\n" % code) == code, "bare code with whitespace")
	_check(not EcoShare.decode("来看看 index.html?tank=%s" % code, eco).is_empty(), "decode accepts share text")
	_check(EcoShare.share_path(code) == "index.html?tank=" + code, "toy share path")

func _test_rejects_garbage() -> void:
	var eco := _tank()
	for junk in ["", "   ", "hello", "tank=", "!!!@@@", "AAAAAAAAAAAAAAAA", "https://example.com/?tank=zzzz", "x".repeat(5000)]:
		_check(EcoShare.decode(junk, eco).is_empty(), "rejects %s" % junk.substr(0, 20))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var survived := 0
	for i in range(300):
		var b := PackedByteArray()
		for j in range(rng.randi_range(1, 120)):
			b.append(rng.randi_range(0, 255))
		var junk_code := Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").replace("=", "")
		var s := EcoShare.decode(junk_code, eco)
		if not s.is_empty():
			survived += 1
			_check((s["placed"] as Array).size() <= EcoShare.MAX_PLACED, "random bytes never exceed limits")
	_check(survived < 10, "random bytes are almost always rejected (%d/300 passed checksum+version)" % survived)

func _test_tamper_detected() -> void:
	var eco := _tank()
	var code := EcoShare.encode(_sample_snap(), eco)
	var mid := code.length() / 2
	var swapped := code.substr(0, mid) + ("A" if code[mid] != "A" else "B") + code.substr(mid + 1)
	_check(EcoShare.decode(swapped, eco).is_empty(), "single char change is rejected")
	_check(EcoShare.decode(code.substr(0, code.length() - 6), eco).is_empty(), "truncated code is rejected")

func _test_limits_and_unknown_indices() -> void:
	var eco := _tank()
	var snap := _sample_snap()
	var many: Array = []
	for i in range(200):
		many.append({"id": "rock", "x": 0.5, "d": 0.5, "flip": false})
	many.append({"id": "not_a_thing", "x": 0.5, "d": 0.5, "flip": false})
	snap["placed"] = many
	snap["fish"] = {"slacking_crucian": 500}
	var s := EcoShare.decode(EcoShare.encode(snap, eco), eco)
	_check((s["placed"] as Array).size() == EcoShare.MAX_PLACED, "placed capped")
	_check(int(s["fish"]["slacking_crucian"]) == EcoShare.MAX_FISH_IN_TANK, "fish capped")

	# 手工构造：未知鱼种 / 物件下标、超大星级，都应被安全跳过或夹紧
	var b := PackedByteArray([1, 3 | (7 << 2), 200, 50, 0, 2, 250, 5, 1, 0, 3, 9, 0, 0, 2, 250, 10, 10, 0, 128, 64])
	var sum := 0
	for v in b:
		sum += v
	b.append(sum & 0xFF)
	var raw := Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").replace("=", "")
	var t := EcoShare.decode(raw, eco)
	_check(not t.is_empty(), "hand-built code decodes")
	_check(int(t["stars"]) == 5 and int(t["oxygen"]) == 100, "stars and oxygen clamped")
	_check((t["fish"] as Dictionary).size() == 1 and (t["fish"] as Dictionary).has("slacking_crucian"), "unknown fish index skipped")
	_check((t["placed"] as Array).size() == 1 and String(t["placed"][0]["id"]) == "grass" and bool(t["placed"][0]["flip"]) == false, "unknown item index skipped")

func _test_name_cleaning() -> void:
	_check(EcoShare.clean_name("  a\tb\nc\u0007d ") == "abcd", "control chars removed")
	_check(EcoShare.clean_name("一二三四五六七八九十十一十二十三").length() == EcoShare.MAX_NAME_CHARS, "name length capped")
	_check(EcoShare.display_name({"name": ""}) == "一只生态缸", "default display name")

func _test_render_models() -> void:
	var eco := _tank()
	var s := EcoShare.decode(EcoShare.encode(_sample_snap(), eco), eco)
	var tank := EcoShare.build_tank(s, _fish_data())
	_check(tank.placed().size() == 3 and tank.tank_level() == 2, "friend tank has items and level")
	_check(tank.shells() == 0 and tank.pearls() == 0, "friend tank has no economy")
	var ev := EcoShare.build_eval(s, tank)
	_check((ev["fish"] as Array).size() == 9, "eval expands fish")
	_check(int(ev["stars"]) == 4 and (ev["visitors_present"] as Array).size() == 2, "eval keeps stars and visitors")
	_check(EcoShare.summary(s) == "9 条鱼 · 3 种 · 2 位访客 · 3 件摆设", "summary line")
