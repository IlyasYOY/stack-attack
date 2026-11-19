extends RefCounted
## End-to-end fixed-step scenarios for the slingshot and both repair cycles.


static func run(check: Callable) -> void:
	_edge_targets(check)
	_repair_cycle(check)
	_two_rails(check)
	_fall_collisions(check)


static func _board() -> StackSimulation:
	var game := StackSimulation.new(StackTuning.new(), 512)
	game.crates.clear()
	game.player = Vector2(1.5, game.tuning.rows - game.tuning.player_height)
	for crane in game.cranes:
		crane.release_column = -1
	return game


static func _step(game: StackSimulation, ticks: int = 1) -> void:
	for index in range(ticks):
		game.advance(StackSimulation.STEP, 0.0)


static func _until(game: StackSimulation, condition: Callable, ticks: int) -> bool:
	for index in range(ticks):
		if condition.call():
			return true
		_step(game)
	return condition.call()


static func _shoot(game: StackSimulation) -> void:
	game.advance(StackSimulation.STEP, 0.0, false, false, false, {"slingshot_pressed": true})


static func _edge_targets(check: Callable) -> void:
	var game := _board()
	game.slingshot_charges = 5
	game.cranes[0].x = -0.55
	_shoot(game)
	check.call(game.slingshot_charges == 4 and not game.repair.shots.is_empty()
		and game.repair.shots[0].crane == 0,
		"A partly visible trolley remains an eligible target")
	game.repair.shots.clear()
	game.cranes[0].x = -0.86
	var worker := game.repair.workers[0]
	worker.phase = "passenger"
	worker.id = 21
	game.cranes[1].x = 5.0
	_shoot(game)
	check.call(game.slingshot_charges == 3 and not game.repair.shots.is_empty()
		and game.repair.shots[0].worker and game.repair.shots[0].target_code == 21,
		"A partly visible passenger wins over a fully visible crane")

	game = _board()
	game.slingshot_charges = 5
	var crane := game.cranes[0]
	crane.loaded = false
	crane.x = -0.70
	_shoot(game)
	check.call(game.slingshot_charges == 4 and not game.repair.shots.is_empty(),
		"The closed jaw remains a target past the visible trolley")
	game.repair.shots.clear()
	crane.x = -0.90
	_shoot(game)
	check.call(game.slingshot_charges == 4 and game.repair.shots.is_empty(),
		"A closed jaw hidden behind the end stop is not a target")
	crane.open_time = game.tuning.crane_open_time * 0.7
	_shoot(game)
	check.call(game.slingshot_charges == 3 and not game.repair.shots.is_empty(),
		"Opening the jaws exposes a target beyond the reach of closed jaws")


static func _repair_cycle(check: Callable) -> void:
	var game := _board()
	game.slingshot_charges = 5
	_shoot(game)
	check.call(game.slingshot_charges == 5 and game.repair.shots.is_empty(),
		"Slingshot reserves stone when both cranes are outside the visible rails")
	var crane := game.cranes[0]
	crane.x = 3.5
	crane.release_column = 8
	crane.material = "metal"
	var worker := game.repair.workers[0]
	_shoot(game)
	check.call(game.slingshot_charges == 4 and not game.repair.shots.is_empty() and not worker.broken,
		"Aimed shot has a visible flight before it hits")
	_step(game, 8)
	if not game.repair.shots.is_empty():
		var shot := game.repair.shots[0]
		check.call(shot.position != shot.from and shot.position != shot.to,
			"Projectile moves from the player toward the selected visible target")
	check.call(_until(game, func(): return worker.broken, 40),
		"Impact freezes the selected crane")
	var frozen_x := float(crane.x)
	var cargo_variant := int(crane.variant)
	check.call(_until(game, func(): return worker.phase == "repair", 150)
		and crane.x == frozen_x and crane.loaded and crane.variant == cargo_variant and crane.material == "metal",
		"Mechanic climbs from the edge while the damaged crane holds the original cargo in place")
	_step(game, 92)
	var first_worker_id := int(worker.id)
	_shoot(game)
	check.call(_until(game, func(): return int(worker.id) != first_worker_id, 40)
		and worker.broken and worker.phase == "climb" and not game.repair.fallen.is_empty(),
		"Knocking the repairer off calls a replacement while the crane stays broken")
	check.call(_until(game, func(): return worker.phase == "repair", 150) and worker.elapsed == 0.0,
		"Replacement starts the repair clock from zero")
	_step(game, 299)
	check.call(worker.phase == "repair" and crane.x == frozen_x,
		"Repair still holds the crane during tick 299")
	_step(game)
	check.call(worker.phase == "passenger" and crane.x > frozen_x and crane.loaded
		and crane.variant == cargo_variant and crane.material == "metal",
		"On tick 300 the worker rides away with the same cargo")

	var other := game.cranes[1]
	other.x = 6.75
	other.waiting = false
	var passenger_id := int(worker.id)
	var before := float(crane.x)
	_shoot(game)
	check.call(not game.repair.shots.is_empty() and game.repair.shots[0].worker
		and game.repair.shots[0].target_code == passenger_id,
		"A visible passenger draws the shot before any healthy crane")
	check.call(_until(game, func(): return worker.phase == "idle", 40)
		and crane.x > before and not worker.broken and not game.repair.workers[1].broken,
		"Hitting a passenger sends them down while both operational cranes keep moving")
	check.call(_until(game, func(): return not crane.loaded, 300),
		"The repaired crane keeps the original release route")
	var metal_released := false
	for crate in game.crates:
		metal_released = metal_released or (crate.material == "metal" and crate.variant == cargo_variant)
	check.call(metal_released, "Repaired crane eventually delivers the original metal crate")


static func _two_rails(check: Callable) -> void:
	var game := _board()
	game.slingshot_charges = 5
	var left := game.cranes[0]
	var right := game.cranes[1]
	left.x = 2.0
	# Queue the second shot before either repairer appears, with the first
	# crane departing the target region manually between selection events.
	_shoot(game)
	var first := game.repair.shots[0]
	left.x = -1.35
	right.x = 7.0
	_shoot(game)
	left.x = 2.05
	var second := game.repair.shots[1]
	var left_worker := game.repair.workers[0]
	var right_worker := game.repair.workers[1]
	check.call(first.crane == 0 and second.crane == 1, "Each independent shot can target a different rail")
	check.call(_until(game, func(): return left_worker.broken and right_worker.broken, 40),
		"Both cranes can be broken at once")
	_shoot(game)
	var shot := game.repair.shots[0]
	var hit: Dictionary = game.repair.workers[int(shot.crane)]
	var unaffected: Dictionary = game.repair.workers[1 - int(shot.crane)]
	var hit_id := int(hit.id)
	var unaffected_id := int(unaffected.id)
	check.call(_until(game, func(): return hit.id != hit_id, 40) and unaffected.id == unaffected_id
		and unaffected.broken, "A replacement on one rail leaves the other worker's repair cycle intact")
	check.call(_until(game, func(): return unaffected.phase == "passenger", 550),
		"The unaffected rail still completes its own repair")


static func _fall_collisions(check: Callable) -> void:
	for material in ["wood", "metal"]:
		var game := _board()
		game.cranes_enabled = false
		var lower := game.add_crate(4, 10, 0, 3)
		var upper := game.add_crate(4, 9, 0, 2, material)
		game.repair.fallen.append({"position": Vector2(4.5, 8.55), "vy": 6.0, "crane": 0})
		_step(game, 60)
		check.call(game.repair.fallen.is_empty() and game.crates.has(lower)
			and game.crates.has(upper) == (material == "metal")
			and game.broken_crates == int(material == "wood"),
			"The falling mechanic stops at the first crate and breaks only wood")
	for protection in ["none", "helmet", "lamp_helmet"]:
		var game := _board()
		game.cranes_enabled = false
		match protection:
			"helmet": game.helmet_charges = 2
			"lamp_helmet":
				game.lamp_helmet_equipped = true
				game.lamp_helmet_charges = 2
		game.repair.fallen.append({"position": game.player + Vector2(0.3, -0.4), "vy": 6.0, "crane": 0})
		_step(game, 60)
		check.call(game.repair.fallen.is_empty(), "The falling mechanic stops after hitting a hero")
		match protection:
			"none":
				check.call(game.state == "over" and game.loss_reason == "mechanic",
					"Unprotected hero dies from the falling mechanic with the new history reason")
			"helmet":
				check.call(game.state == "playing" and game.helmet_charges == 1,
					"A normal helmet takes exactly one charge from a falling mechanic")
			"lamp_helmet":
				check.call(game.state == "playing" and not game.lamp_helmet_equipped,
					"The first hit from a falling mechanic breaks the lamp helmet")
