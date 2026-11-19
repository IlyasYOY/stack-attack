extends RefCounted
## Starting boards for the opt-in Web QA bridge and headless demo tests.
## The normal demo controller supplies every action after setup.
static func prepare(name: String) -> StackDemo:
	var demo := StackDemo.new(StackTuning.new(), 7481)
	var game := demo.model
	game.cranes_enabled = false
	game.crates.clear()
	game.grounded = true
	var floor_y := float(game.tuning.rows - 1)
	game.player = Vector2(0.04, game.tuning.rows - game.tuning.player_height)
	match name:
		"demo_dodge":
			game.add_crate(0.0, floor_y - 4.0, 2.0)
			game.add_ground_item("helmet", 1.25, game.tuning.rows)
		"demo_row":
			for col in range(game.tuning.columns):
				if col != 6:
					game.add_crate(col, floor_y)
			game.add_crate(5, floor_y - 1)
			game.player.x = 5 - game.tuning.player_width
			game.player.y -= 1.0
		"demo_pickup":
			game.player.x = 4.15
			game.add_ground_item("helmet", 2.0, game.tuning.rows)
	return demo


## Start ordinary live simulations on repeatable boards for browser QA and capture.
static func prepare_release(game: StackSimulation, scenario: String) -> void:
	game.reset(7481)
	game.crates.clear()
	game.cranes_enabled = false
	var floor_y := float(game.tuning.rows)
	game.player = Vector2(4.3, floor_y - game.tuning.player_height)
	for crane in game.cranes:
		crane.waiting = true
		crane.wait_remaining = 12.0
		crane.material = "wood"
	match scenario:
		"input":
			game.player.x = 1.5
			game.watch_cap_time = 5.0
			game.slingshot_charges = 5
			game.speed_boots_charges = 8
			_position_claw(game, 3.5, 9, "wood")
		"cap":
			game.watch_cap_time = 5.0
			game.add_crate(4.0, 5.8, 1.5)
		"boots":
			game.hunting_boots_charges = 2
			game.add_trap(5.67, floor_y - 0.12)
		"goggles":
			game.engineer_goggles_charges = 3
			game.add_trap(5.42, floor_y - 0.12)
		"repair":
			game.slingshot_charges = 5
			_position_claw(game, 3.5, 9, "wood")
		"metal":
			game._loot_rng.seed = 14
			game.player.y -= 1.0
			for column in range(game.tuning.columns - 1):
				game.add_crate(column, floor_y - 1.0)
			_position_claw(game, 7.0, game.tuning.columns - 1, "metal")


static func _position_claw(game: StackSimulation, x: float, column: int, material: String) -> void:
	game.cranes_enabled = true
	var crane := game.cranes[0]
	crane.x = x
	crane.waiting = false
	crane.wait_remaining = 0.0
	crane.loaded = true
	crane.release_column = column
	crane.material = material
