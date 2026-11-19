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
