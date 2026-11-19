extends RefCounted

const STEP := StackSimulation.STEP


static func run(check: Callable) -> void:
	_watch_cap(check)
	_traps(check)
	_metal(check)
	_history(check)


static func _empty() -> StackSimulation:
	var game := StackSimulation.new()
	game.cranes_enabled = false
	game.crates.clear()
	game.player.x = 4.25
	game._loot_rng.seed = 14
	return game


static func _watch_cap(check: Callable) -> void:
	for fps in [24, 30, 60, 120, 144]:
		var game := _empty()
		game.watch_cap_time = 5.0
		var frame := 1.0 / float(fps)
		for index in range(fps * 5 - 1):
			game.advance(frame, 0, false, false, false, {"watch_held": true})
		check.call(game.watch_cap_active and is_equal_approx(game.watch_cap_time, frame),
			"Watch cap lasts five real seconds at %d FPS" % fps)
		game.advance(frame, 0, false, false, false, {"watch_held": true})
		check.call(not game.watch_cap_active and game.watch_cap_time == 0 and game.ticks == 300,
			"Five real seconds consume the cap and advance 2.5 game seconds")
		game.advance(frame, 0, false, false, false, {"watch_held": true})
		check.call(is_equal_approx(game.frame_world_delta, frame), "Runtime resumes without requiring a keyup")
	var game := _empty()
	game.watch_cap_time = 5.0
	game.advance(0.6, 1, false, false, false, {"watch_held": true, "real_delta": 0.4})
	var x := game.player.x
	check.call(is_equal_approx(game.watch_cap_time, 4.6) and is_equal_approx(game.frame_world_delta, 0.3),
		"Frame time and the cap's real-time reserve are independent")
	game.advance(0.3, 1)
	check.call(game.player.x > x and is_equal_approx(game.watch_cap_time, 4.6)
		and is_equal_approx(game.frame_world_delta, 0.3) and not game.watch_cap_active,
		"Releasing the cap immediately restores speed and saves the remainder")
	game.add_ground_item("engineer_goggles", game.player.x + 0.28, 11.0)
	game.pick_up_nearest()
	check.call(game.watch_cap_time == 0.0 and game.engineer_goggles_charges == 3
		and is_equal_approx(game.ground_items[0].progress, 4.6), "Swapping out keeps the exact remainder")
	game.pick_up_nearest()
	check.call(is_equal_approx(game.watch_cap_time, 4.6), "The remainder survives the exchange back")
	game.advance(STEP, 0, false, false, false, {"watch_held": true})
	var remaining := game.watch_cap_time
	check.call(game.watch_cap_active, "The re-equipped cap can resume the same charge")
	game.cancel_bonus_input()
	game.advance(STEP, 0)
	check.call(not game.watch_cap_active and game.watch_cap_time == remaining,
		"Releasing controls cancels slowdown without spending time")
	game.add_crate(game.player.x, game.player.y - 1.025, 6)
	game.advance(STEP, 0)
	check.call(game.loss_reason == "crushed" and game.watch_cap_time == 0.0,
		"A wooden overhead impact breaks the cap and kills")
	var crossing := _empty()
	crossing.watch_cap_time = 0.02
	crossing.advance(0.1, 0, false, false, false, {"watch_held": true})
	check.call(is_equal_approx(crossing.frame_world_delta, 0.09) and crossing.watch_cap_time == 0.0,
		"A frame spanning exhaustion uses both rates")


static func _traps(check: Callable) -> void:
	var game := _empty()
	var x := game.player.x + game.tuning.player_width / 2.0
	var trap := game.add_trap(x, 10.6)
	game.advance(0.1, 0)
	check.call(trap.phase == "folded", "A falling trap remains folded")
	game.advance(0.15, 0)
	check.call(trap.phase == "warning" and game.state == "playing", "A landing trap warns without damage")
	game.advance(0.8, 0)
	check.call(trap.phase == "open" and game.loss_reason == "trap", "An opened trap catches stationary feet")

	game = _empty()
	trap = game.add_trap(5.45, 11)
	trap.phase = "open"
	game.advance(0.44, 1, true)
	check.call(game.state == "playing" and not game.grounded and game.player.x > 5.8,
		"A jump clears open jaws")

	game = _empty()
	game.hunting_boots_charges = 2
	for remaining in [1, 0]:
		x = game.player.x + game.tuning.player_width / 2.0
		trap = game.add_trap(x, 11)
		trap.phase = "open"
		var falling := game.add_crate(0, 5)
		game.advance(STEP, 0)
		var at := game.player
		var y := float(falling.y)
		game.advance(0.49, 1, true)
		check.call(game.player == at and float(falling.y) > y and game.hunting_boots_charges == remaining + 1,
			"Boots hold the player while crates still fall")
		game.advance(2.0 * STEP, 0)
		check.call(game.state == "playing" and not game.traps.has(trap)
			and game.hunting_boots_charges == remaining and game.trap_hold_time == 0.0,
			"Boots escape after half a game second for one charge")
		game.crates.clear()
	trap = game.add_trap(x, 11)
	trap.phase = "open"
	game.advance(STEP, 0)
	check.call(game.loss_reason == "trap", "Hunting boots only save twice")

	game = _empty()
	game.engineer_goggles_charges = 3
	trap = game.add_trap(4.7, 10.6)
	game.add_trap(5.35, 11)
	game.advance(STEP, 0, false, false, false, {"goggles_pressed": true})
	check.call(game.engineer_goggles_charges == 2 and not game.traps.has(trap) and game.traps.size() == 1,
		"Goggles dismantle the nearest folded trap")
	game.player.x = 0
	game.advance(STEP, 0, false, false, false, {"goggles_pressed": true})
	check.call(game.engineer_goggles_charges == 2, "Goggles are free without a target in range")
	game.player.x = 4.25
	game.traps[0].phase = "open"
	game.player.x = 5.0
	game.advance(STEP, 0)
	check.call(game.loss_reason == "trap", "Engineer goggles give no passive protection")

	game = _empty()
	game.player.x = 0.2
	game.player.y -= 1.0
	for col in range(game.tuning.columns):
		game.add_crate(col, 10, 0, -1, "metal")
	game.advance(STEP, 0)
	trap = game.add_trap(0.5, 9.95)
	game.advance(0.5, 0)
	check.call(game.state == "playing" and trap.phase != "open", "Line clear holds trap warnings until the controls return")
	game.advance(0.15, 0)
	check.call(trap.phase == "warning", "Trap lands after a line clear")
	if trap.phase == "warning":
		var warning_left := float(trap.timer)
		game.advance(warning_left - 0.01, 0)
		check.call(trap.phase == "warning", "Full warning after the board settles")
		game.advance(0.03, 0)
		check.call(trap.phase == "open" and game.loss_reason == "trap", "Row trap is lethal once the full warning ends")

	for material in ["wood", "metal"]:
		for sideways in [false, true]:
			game = _empty()
			game.player.x = 0.0
			trap = game.add_trap(7.5, 11)
			trap.phase = "open"
			var crate := game.add_crate(6.0 if sideways else 7.0, 10.0 if sideways else 9.4, 0, -1, material)
			if sideways:
				crate.target_x = 7.0
			game.advance(0.45, 0)
			check.call(game.traps.is_empty() and game.crates.has(crate) and crate.y == 10,
				"%s crate crushes a trap without breaking (sideways: %s)" % [material, sideways])


static func _metal(check: Callable) -> void:
	var game := StackSimulation.new()
	check.call(game.crates.all(func(crate: Dictionary) -> bool: return crate.material == "wood"),
		"All starting crates are wood")
	var metal := 0
	for index in range(1000):
		game._enter_crane(game.cranes[0])
		metal += int(game.cranes[0].material == "metal")
	check.call(metal > 70 and metal < 130, "About ten percent of new cargo is metal")

	game = _empty()
	game.player.x = 2.44
	var crate := game.add_crate(3, 10, 0, -1, "metal")
	game.advance(0.3, 1)
	check.call(crate.x == 3, "Normal movement cannot push metal")
	game.gloves_charges = 2
	game.advance(0.4, 0, false, true)
	check.call(crate.x == 3 and game.gloves_charges == 2, "Gloves cannot pull metal")
	game.gloves_charges = 0
	game.strong_arms_charges = 2
	var stop := game.add_crate(4, 10)
	game.advance(0.4, 1)
	check.call(crate.x == 3 and stop.x == 4 and game.strong_arms_charges == 2,
		"A pair involving metal is fixed, with no extra charge for a block")
	game.crates.erase(stop)
	game.advance(STEP, 1)
	var offered := game.add_ground_item("slingshot", game.player.x + 0.28, 11)
	check.call(game.pick_up_nearest().is_empty() and offered.kind == "slingshot",
		"A pending steel step keeps ownership of the hands")
	game.advance(0.34, 0)
	check.call(is_equal_approx(crate.x, 4.0) and game.strong_arms_charges == 1,
		"One completed metal move spends one charge")
	check.call(game.pick_up_nearest() == "slingshot" and offered.kind == "strong_arms" and offered.charges == 1,
		"Hands can be exchanged as soon as the steel step settles")
	game.ground_items.clear()
	game.player.x = 3.44
	game.mallet_charges = 2
	game.advance(0.12, 0, false, false, true)
	check.call(game.mallet_charges == 2 and game.crates.has(crate)
		and game.events.any(func(event: Dictionary) -> bool: return event.type == "mallet_ring"),
		"Mallet rings on metal without charge or damage")
	var held := game.add_ground_item("helmet", 8.5, 11)
	var fall := game.add_crate(8, 9, 0, -1, "metal")
	game.advance(0.45, 0)
	check.call(not game.ground_items.has(held) and game.crates.has(fall) and fall.y == 10,
		"Metal crushes even durable gear and continues to land")
	var upper := game.add_crate(8, 8.2)
	game.advance(0.4, 0)
	check.call(upper.y == 9, "Metal is a normal support surface")

	for gear in ["helmet", "lamp_helmet"]:
		game = _empty()
		game.helmet_charges = 3 if gear == "helmet" else 0
		game.lamp_helmet_equipped = gear == "lamp_helmet"
		crate = game.add_crate(game.player.x, game.player.y - 1.025, 6, -1, "metal")
		game.advance(STEP, 0)
		check.call(game.loss_reason == "metal_crushed" and game.crates.has(crate),
			"Metal crushes despite " + gear)
	game = _empty()
	game.helmet_charges = 3
	crate = game.add_crate(game.player.x, game.player.y - 1.03, 0, -1, "metal")
	game.advance(STEP, 0, true)
	check.call(game.state == "playing" and game.player_velocity.y == 0.0 and game.helmet_charges == 3
		and game.crates.has(crate), "A jump into metal stops without damage")

	game = _empty()
	var rng_before := game._loot_rng.state
	crate = game.add_crate(6, 10, 0, -1, "metal")
	game._destroy_crate(crate)
	check.call(game.crates.has(crate) and game.broken_crates == 0, "Metal only disappears in a full row")
	game.player.y -= 1.0
	for col in range(game.tuning.columns):
		if col != 6:
			game.add_crate(col, 10, 0, -1, "metal")
	game.advance(0.6, 0)
	check.call(game.crates.is_empty() and game.cleared_crates == game.tuning.columns and game.lines == 1
		and game._loot_rng.state == rng_before and game.traps.is_empty() and game.ground_items.is_empty(),
		"A full metal row counts every crate without loot rolls")


static func _history(check: Callable) -> void:
	var path := "user://workshop-release-test.json"
	var profile := StackProfile.new(path)
	profile.matches.clear()
	for reason in StackSimulation.LOSS_REASONS:
		var game := _empty()
		game._lose(reason)
		profile.add_match(game.match_result("2026-11-19T12:00:00"))
	var saved := profile.save_profile()
	var fresh := StackProfile.new(path)
	var stats := fresh.statistics()
	check.call(saved and fresh.matches.size() == 5 and stats.trap == 1 and stats.mechanic == 1
		and stats.metal_crushed == 1 and stats.crushed == 1 and stats.overflow == 1,
		"History persists new causes and still reads old ones")
	DirAccess.remove_absolute(path)
