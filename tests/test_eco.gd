extends SceneTree
# 生态缸逻辑的无头测试：
#   godot --headless --path . --script tests/test_eco.gd
# 全部通过时退出码 0，否则 1。

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_catalog_loads()
	_test_focus_and_task_rewards()
	_test_buy_and_price_growth()
	_test_placement_roundtrip()
	_test_eval_never_collapses()
	_test_balance_and_stars()
	_test_best_stars_never_drop()
	_test_visitors_arrive_on_focus()
	_test_pearls()
	_test_legacy_migration()
	_test_gifts()
	_test_stocking_and_exclusion()
	_test_sanitize()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)

func _fish_data() -> Array:
	var f := FileAccess.open("res://data/fish_data.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _tank(state: Dictionary = {}) -> EcoTank:
	var t := EcoTank.new()
	var s := EcoTank.default_state()
	for k in state:
		s[k] = state[k]
	t.bind(s, _fish_data())
	return t

func _counts(pairs: Dictionary) -> Dictionary:
	var c := {}
	for f in _fish_data():
		c[String(f["id"])] = int(pairs.get(String(f["id"]), 0))
	return c

func _test_catalog_loads() -> void:
	var t := _tank()
	_check(t.items.size() >= 15, "catalog has items")
	_check(t.visitors.size() >= 6, "catalog has visitors")
	_check(t.tank_levels.size() == 4, "4 tank levels")
	for it in t.items:
		_check(EcoTank.CATEGORY_NAMES.has(String(it["category"])), "known category for " + String(it["id"]))
		_check(TankArt.ITEM_SIZES.has(String(it["id"])), "art exists for item " + String(it["id"]))
	for v in t.visitors:
		_check(TankArt.VISITOR_SIZES.has(String(v["id"])), "art exists for visitor " + String(v["id"]))

func _test_focus_and_task_rewards() -> void:
	var t := _tank()
	_check(t.focus_reward(4) == 0, "under 5 minutes gives no shells")
	_check(t.focus_reward(25) == 5, "25 minutes gives 5 shells")
	_check(t.focus_reward(600) == EcoTank.FOCUS_SHELL_CAP, "long focus is capped")
	var before := t.shells()
	for i in range(EcoTank.TASK_SHELL_DAILY_CAP + 3):
		t.task_reward("2026-09-25")
	_check(t.shells() - before == EcoTank.TASK_SHELL * EcoTank.TASK_SHELL_DAILY_CAP, "task shells capped per day")
	_check(t.task_reward("2026-09-26") == EcoTank.TASK_SHELL, "task cap resets next day")

func _test_buy_and_price_growth() -> void:
	var t := _tank({"shells": 100})
	var ctx := {"fish_counts": _counts({}), "total_sessions": 0, "mature_trees": 0}
	var p0 := t.price_of("grass")
	_check(t.buy("grass", ctx) == "", "can buy grass")
	_check(t.shells() == 100 - p0, "price deducted")
	_check(t.price_of("grass") > p0, "second copy costs more")
	_check(t.buy("sword", ctx) != "", "sword locked at 0 stars")
	_check(t.buy("driftwood", ctx) != "", "driftwood locked without trees")
	ctx["mature_trees"] = 3
	_check(t.buy("driftwood", ctx) == "", "driftwood unlocked by forest")
	_check(t.buy("coral", ctx) != "", "gift item not buyable before gift")
	var poor := _tank({"shells": 1})
	_check(poor.buy("airstone", ctx).begins_with("贝壳还差"), "not enough shells message")

func _test_placement_roundtrip() -> void:
	var t := _tank({"shells": 100})
	var ctx := {"fish_counts": _counts({}), "total_sessions": 0, "mature_trees": 0}
	t.buy("rock", ctx)
	var uid := t.place("rock", 0.4, 0.5)
	_check(uid > 0, "placed rock")
	_check(t.place("rock", 0.6, 0.5) == -1, "cannot place more than owned")
	t.move(uid, 1.7, -2.0)
	var e := t.find_placed(uid)
	_check(is_equal_approx(float(e["x"]), 1.0) and is_equal_approx(float(e["d"]), 0.0), "move clamps")
	t.flip(uid)
	_check(bool(t.find_placed(uid)["flip"]), "flip toggles")
	t.remove(uid)
	_check(t.find_placed(uid).is_empty() and t.spare_count("rock") == 1, "remove returns to inventory")
	_check(t.inventory().size() == 1, "inventory lists spare item")

func _test_eval_never_collapses() -> void:
	# 满缸大鱼、零设备：生态再差也只是打折，分数不为负、星级不低于 0
	var t := _tank({"tank_level": 3})
	var r := t.evaluate({"fish_counts": _counts({"meeting_carp": 50, "annual_koi": 1}), "total_sessions": 30})
	_check(float(r["oxygen"]) >= 0.0 and float(r["oxygen"]) < 50.0, "overloaded tank has low oxygen")
	_check(float(r["balance"]) >= 0.5, "balance never below 0.5")
	_check(int(r["score"]) >= 0, "score non-negative")
	_check((r["fish"] as Array).size() == 40, "capacity respected")
	var empty := _tank().evaluate({"fish_counts": _counts({})})
	_check(float(empty["oxygen"]) == 100.0 and int(empty["stars"]) == 0, "empty tank is healthy with 0 stars")

func _test_balance_and_stars() -> void:
	var t := _tank({"shells": 1000, "best_stars": 5, "tank_level": 1})
	var ctx := {"fish_counts": _counts({"slacking_crucian": 6, "meeting_carp": 4, "commute_sardine": 5}), "total_sessions": 0, "mature_trees": 5}
	var bare := t.evaluate(ctx)
	for id in ["hornwort", "hornwort", "airstone", "filter", "snail", "sword", "grass", "rock", "castle"]:
		t.buy(id, ctx)
		t.place(id, 0.5, 0.5)
	var built := t.evaluate(ctx)
	_check(float(built["oxygen"]) > float(bare["oxygen"]), "plants and airstone raise oxygen")
	_check(float(built["clean"]) > float(bare["clean"]), "filter and snail raise water quality")
	_check(int(built["score"]) > int(bare["score"]), "building raises score")
	_check(int(built["stars"]) >= 2, "a decent build reaches 2 stars (got %d, score %d)" % [built["stars"], built["score"]])
	_check((built["trait_notes"] as Array).size() == 1, "sardine school detected")

func _test_best_stars_never_drop() -> void:
	var t := _tank({"shells": 1000})
	var ctx := {"fish_counts": _counts({"slacking_crucian": 3, "salted_fish": 2}), "total_sessions": 0}
	for i in range(4):
		t.buy("grass", ctx)
		t.place("grass", 0.1 * i, 0.3)
	t.buy("rock", ctx)
	t.place("rock", 0.5, 0.5)
	var r := t.evaluate(ctx)
	var best := int(r["best_stars"])
	_check(best >= 1, "some stars earned")
	for e in t.placed().duplicate():
		t.remove(int(e["uid"]))
	var r2 := t.evaluate(ctx)
	_check(int(r2["stars"]) < best, "current stars drop when emptied")
	_check(int(r2["best_stars"]) == best, "best stars kept")
	_check(bool(t.unlock_state("sword", ctx)["ok"]), "unlocks keep using best stars")

func _test_visitors_arrive_on_focus() -> void:
	var t := _tank({"shells": 500})
	var ctx := {"fish_counts": _counts({"slacking_crucian": 2}), "total_sessions": 0}
	t.buy("seashell", ctx)
	t.place("seashell", 0.5, 0.5)
	var r := t.evaluate(ctx)
	_check((r["visitors_ready"] as Array).has("hermit_crab"), "hermit crab conditions met")
	_check(not (r["visitors_present"] as Array).has("hermit_crab"), "not present until a focus completes")
	var shells_before := t.shells()
	var came := t.arrive_visitors(r, "2026-09-25")
	_check(came.size() == 1 and String(came[0]["id"]) == "hermit_crab", "hermit crab arrives")
	_check(t.shells() == shells_before + 15, "first visit gift")
	_check(t.arrive_visitors(t.evaluate(ctx), "2026-09-26").is_empty(), "no double arrival")
	_check((t.evaluate(ctx)["visitors_present"] as Array).has("hermit_crab"), "present after arrival")
	for e in t.placed().duplicate():
		t.remove(int(e["uid"]))
	_check(not (t.evaluate(ctx)["visitors_present"] as Array).has("hermit_crab"), "leaves when shell removed")
	_check(t.visitor_seen("hermit_crab"), "still recorded in the catalog")

func _test_pearls() -> void:
	var t := _tank({"last_stars": 3})
	t.accrue_pearls("2026-09-25")
	_check(t.pearls() == 0, "first day only sets the date")
	t.accrue_pearls("2026-09-25")
	_check(t.pearls() == 0, "same day no pearls")
	t.accrue_pearls("2026-09-26")
	_check(t.pearls() == 3, "new day pearls = stars")
	var s := t.shells()
	_check(t.take_pearl() == EcoTank.PEARL_VALUE and t.shells() == s + EcoTank.PEARL_VALUE, "pearl gives shells")
	for i in range(20):
		t.accrue_pearls("2026-10-%02d" % (i + 1))
	_check(t.pearls() == EcoTank.PEARL_PENDING_CAP, "pearls capped")

func _test_legacy_migration() -> void:
	var t := _tank()
	var save := {
		"total_focus_sessions": 42,
		"total_tasks_completed": 10,
		"aquarium_decor": {"coral": {"on": true, "slot": 0}, "shipwreck": {"on": false, "slot": 1}, "chest": {"on": true, "slot": 2}},
	}
	var ctx := {"fish_counts": _counts({"slacking_crucian": 20, "salted_fish": 5}), "total_sessions": 42}
	var paid := t.migrate_legacy(save, ctx)
	_check(paid == EcoTank.WELCOME_SHELLS + 42 * 5 + 10 * 2, "back pay for past effort")
	_check(t.capacity() >= 25, "tank big enough for existing fish (cap %d)" % t.capacity())
	_check(t.owned_count("coral") == 1 and t.placed_count("coral") == 1, "coral migrated and placed")
	_check(t.owned_count("shipwreck") == 1 and t.placed_count("shipwreck") == 0, "hidden shipwreck owned but not placed")
	_check(t.owned_count("chest") == 0, "chest not earned (no koi)")
	_check(t.placed_count("grass") == 2, "starter plants placed")
	_check(t.migrate_legacy(save, ctx) == 0, "migration runs once")
	_check(t.grant_gifts(ctx).is_empty(), "no duplicate gifts after migration")

func _test_gifts() -> void:
	var t := _tank()
	var ctx := {"fish_counts": _counts({"annual_koi": 1}), "total_sessions": 12}
	var got := t.grant_gifts(ctx)
	var ids := got.map(func(it): return String(it["id"]))
	_check(ids.has("coral") and ids.has("chest") and not ids.has("shipwreck"), "gifts by milestone")
	_check(t.placed_count("coral") == 1, "gift auto-placed")
	_check(t.grant_gifts(ctx).is_empty(), "gifts once")
	_check(bool(t.unlock_state("coral", ctx)["ok"]), "gift item buyable after gift")

func _test_stocking_and_exclusion() -> void:
	var t := _tank()
	var counts := _counts({"slacking_crucian": 30, "drift_bottle": 1, "overtime_eel": 1})
	var fish := t.tank_fish(counts)
	_check(fish.size() == 12, "small tank holds 12")
	_check(fish.has("drift_bottle") and fish.has("overtime_eel"), "rare ones always make it in")
	t.set_excluded("slacking_crucian", true)
	_check(t.tank_fish(counts).size() == 2, "excluded species stays in the pond")
	_check(EcoTank.species_level(0) == 0 and EcoTank.species_level(1) == 1 and EcoTank.species_level(20) == 5, "species levels")
	_check(EcoTank.next_level_at(4) == 6 and EcoTank.next_level_at(25) == 0, "next level thresholds")

func _test_sanitize() -> void:
	var t := _tank({
		"owned": {"rock": 1, "bogus": 3},
		"placed": [
			{"uid": 5, "id": "rock", "x": 0.2, "d": 0.2},
			{"uid": 6, "id": "rock", "x": 0.3, "d": 0.2},
			{"uid": 7, "id": "bogus", "x": 0.3, "d": 0.2},
		],
	})
	_check(t.placed().size() == 1, "extra and unknown placements dropped")
	_check(not (t.state["owned"] as Dictionary).has("bogus"), "unknown owned dropped")
	_check(int(t.state["next_uid"]) >= 6, "uid counter advanced past existing")
