extends SceneTree
var failures: Array[String] = []
var assertions := 0
const Config = preload("res://game/tuning.gd")
const Simulation = preload("res://game/simulation.gd")
const Profile = preload("res://game/profile.gd")

class HapticProbe extends StackSound:
	var pulses: Array[int] = []
	func _play_effect(_name: String) -> void:
		pass
	func _supports_haptics() -> bool:
		return true
	func _vibrate(duration: int) -> void:
		pulses.append(duration)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func empty(columns: int = 10, rows: int = 11) -> StackSimulation:
	var config := Config.new()
	config.columns = columns
	config.rows = rows
	var game := Simulation.new(config, 7481)
	game.crates.clear()
	game.player = Vector2(2, rows - config.player_height)
	game.cranes_enabled = false
	return game


func advance(game: StackSimulation, duration: float, axis: float = 0.0) -> void:
	for index in range(roundi(duration * 120)):
		game.advance(1.0 / 120.0, axis)


func run() -> void:
	movement_and_jump()
	pushing_and_danger()
	diagonal_crate_collisions()
	clearing()
	equipment_rewards()
	equipment_jumps()
	loss_conditions()
	crush_beside_support()
	crane_cycles()
	crane_contention()
	storage()
	random_sessions()
	demo_games()
	await app_flow()
	await vibration_toggle()
	if not failures.is_empty():
		for failure in failures:
			printerr("GAME_TEST_FAILED: " + failure)
		quit(1)
		return
	print("GAME_TEST_PASS: %d assertions; physics, clears, equipment, loss, cranes, storage and screens" % assertions)
	quit(0)


func movement_and_jump() -> void:
	var first := empty()
	var second := empty()
	for index in range(30):
		first.advance(1.0 / 30.0, 1.0)
	for index in range(144):
		second.advance(1.0 / 144.0, 1.0)
	var slow := empty()
	slow.advance(1.0, 1.0)
	check(slow.player.distance_to(first.player) < .0001, "A long render frame must retain every simulation tick")
	check(first.ticks == 120 and second.ticks == 120, "Simulation must use equal fixed ticks across frame rates")
	check(first.player.distance_to(second.player) < 0.0001, "Movement must not depend on render rate")
	check(absf(first.player.x - 5.6) < 0.001, "Configured walking speed must be respected")
	var late := empty()
	late.elapsed = 500
	advance(late, 1, 1)
	check(absf(late.player.x - first.player.x) < 0.001, "Elapsed match time must not accelerate the player")
	var jumping := empty()
	var floor_y := jumping.player.y
	jumping.advance(1.0 / 120.0, 0, true)
	var highest := jumping.player.y
	for index in range(150):
		jumping.advance(1.0 / 120.0, 0)
		highest = minf(highest, jumping.player.y)
	check(highest < floor_y - 1.0, "Jump must clear a one-cell crate")
	check(absf(jumping.player.y - floor_y) < 0.001 and jumping.grounded, "Jump must land on the floor")
	check(jumping.score == 0, "Survival and jumping must not award points")


func pushing_and_danger() -> void:
	var pushing := empty()
	var crate := pushing.add_crate(4, 10)
	pushing.player.x = 4 - pushing.tuning.player_width
	advance(pushing, .4, 1)
	advance(pushing, .4)
	check(float(crate.x) >= 4.99, "Walking into a crate must push it smoothly")
	check(absf(float(crate.x) - roundf(float(crate.x))) < .001, "A completed push must align to columns")
	check(pushing.player.x + pushing.tuning.player_width <= float(crate.x) + .01, "Pushing must not penetrate the crate")
	var falling := empty()
	var airborne := falling.add_crate(4, 9.8, .2)
	falling.player.x = 4 - falling.tuning.player_width
	advance(falling, .04, 1)
	check(float(airborne.x) > 4.01 and float(airborne.y) > 9.8 and float(airborne.y) < 10,
		"The character must be able to push a crate while it is falling")
	var stack := empty()
	stack.player.x = 4 - stack.tuning.player_width
	stack.add_crate(4, 10)
	var upper := stack.add_crate(4, 9)
	advance(stack, .9, 1)
	check(float(upper.y) > 9.03, "Removing support must make the upper crate fall")
	check(stack.state == "over" and stack.loss_reason == "crushed", "An unsupported upper crate can kill the character")
	var blocked := empty()
	blocked.player.x = 4 - blocked.tuning.player_width
	var lower := blocked.add_crate(4, 10)
	blocked.add_crate(5, 10)
	advance(blocked, .4, 1)
	check(absf(float(lower.x) - 4) < .001, "One push must not move an entire horizontal chain")


func crates_separate(game: StackSimulation) -> bool:
	for a in game.crates:
		for b in game.crates:
			if int(a.id) >= int(b.id):
				continue
			var width := minf(float(a.x) + 1, float(b.x) + 1) - maxf(float(a.x), float(b.x))
			var height := minf(float(a.y) + 1, float(b.y) + 1) - maxf(float(a.y), float(b.y))
			if width > 0.000001 and height > 0.000001:
				return false
	return true


func diagonal_crate_collisions() -> void:
	for direction in [1, -1]:
		# The review's end-to-end repro, plus a small initial vertical gap.
		for start_y in [8.0, 7.97]:
			var game := empty()
			var ax := 4.0 if direction == 1 else 5.0
			var bx := 5.0 if direction == 1 else 4.0
			var support_x := 3.0 if direction == 1 else 6.0
			var moving := game.add_crate(ax, start_y, 6)
			game.add_crate(bx, 9)
			game.add_crate(bx, 10)
			game.add_crate(support_x, 9)
			game.add_crate(support_x, 10)
			game.player = Vector2(ax - game.tuning.player_width if direction == 1 else ax + 1,
				9 - game.tuning.player_height)
			check(crates_separate(game), "Diagonal fixture must start without penetration")
			for tick in range(120):
				game.advance(StackSimulation.STEP, direction)
				var separate := crates_separate(game)
				check(separate, "Diagonal push dir=%d y=%.2f penetrated at tick %d" % [direction, start_y, tick + 1])
				if not separate:
					break
				if tick == 0:
					check(absf(float(moving.y) - 8) < .000001 and absf(float(moving.x) - ax) > .01,
						"A falling push must land on the neighbour's top instead of entering its corner")
		# A command is already active, but gravity has moved its body below the
		# neighbour's top. Vertical support alone cannot resolve this contact.
		for speed in [3.1, 240.0]:
			var side := empty()
			side.tuning.push_speed = speed
			var ax := 4.0 if direction == 1 else 5.0
			var bx := 5.0 if direction == 1 else 4.0
			var moving := side.add_crate(ax, 8.15, 6)
			moving.target_x = ax + direction
			side.add_crate(bx, 9)
			side.add_crate(bx, 10)
			check(crates_separate(side), "Side-contact fixture must start without penetration")
			for tick in range(120):
				side.advance(StackSimulation.STEP, 0)
				var separate := crates_separate(side)
				check(separate, "Active push dir=%d speed=%.1f penetrated at tick %d" % [direction, speed, tick + 1])
				if not separate:
					break
			check(absf(float(moving.x) - ax) < .000001 and absf(float(moving.target_x) - ax) < .000001,
				"A blocked push must stop at the side, including a large horizontal step")
			check(absf(float(moving.y) - 10) < .000001,
				"Side contact must preserve ordinary falling alongside the obstacle")


func clearing() -> void:
	var game := empty(4, 6)
	game.cranes_enabled = true
	game.cranes[0].x = 2.5 - game.tuning.crane_speed * Simulation.STEP
	game.cranes[0].release_column = 2
	var crane_positions := game.cranes.duplicate(true)
	game.player = Vector2(2, 4 - game.tuning.player_height)
	var retiring_ids: Array[int] = []
	for column in range(4):
		retiring_ids.append(int(game.add_crate(column, 5).id))
	var survivor := game.add_crate(2, 4)
	game.add_crate(0, 4)
	var player_y := game.player.y
	game.advance(Simulation.STEP, 0)
	check(game.state == "clearing", "Only a complete settled bottom row starts clearing")
	check(game.score == 100, "A line awards exactly the configured points")
	var is_retiring := func(crate_id: int) -> bool: return game.is_clearing_crate(crate_id)
	check(retiring_ids.all(is_retiring) and not game.is_clearing_crate(int(survivor.id))
		and not game.is_clearing_crate(-1), "Only actual bottom-row IDs must be exposed for retirement")
	advance(game, 26 * Simulation.STEP)
	check(game.cranes == crane_positions, "Cranes must stay still and hold cargo during a clear")
	check(game.cleared_crates == 0 and game.crates.size() == 6 and retiring_ids.all(is_retiring),
		"The retiring crates must remain in the model throughout the 0.22 second hold")
	check(game.player.y == player_y and float(survivor.y) == 4.0, "Support must stay in place during the hold")
	game.cranes_enabled = false
	var safe_support := true
	for tick in range(30):
		game.advance(Simulation.STEP, 0)
		var feet_y := game.player.y + game.tuning.player_height
		safe_support = safe_support and crates_separate(game) and absf(feet_y - float(survivor.y)) < .000001
		if tick == 0:
			check(game.cleared_crates == 4 and not retiring_ids.any(is_retiring),
				"Collapse must count the removed crates and stop exposing their retirement IDs")
		if tick == 14:
			check(float(survivor.y) > 4.4 and float(survivor.y) < 4.6 and game.state == "clearing",
				"The player and crates must still be descending halfway through collapse")
	check(safe_support, "Collapse must preserve contact between the player and their support without penetration")
	check(game.state == "clearing", "Collapse must continue for the full 0.25 seconds")
	game.advance(Simulation.STEP, 0)
	var descended := game.crates.all(func(crate: Dictionary) -> bool: return absf(float(crate.y) - 5) < .001)
	check(game.crates.size() == 2 and descended, "All crates above a cleared row descend one cell")
	check(absf(game.player.y - player_y - 1) < .001, "The character descends together with the warehouse contents")
	check(game.state == "playing", "Joint descent must not cause a false crush")
	var chain_game := empty(4, 6)
	chain_game.player = Vector2(2, 4 - chain_game.tuning.player_height)
	var chain_ids: Array[int] = []
	for row in [4, 5]:
		for column in range(4):
			var crate := chain_game.add_crate(column, row)
			if column == 0:
				chain_ids.append(int(crate.id))
	chain_game.advance(Simulation.STEP, 0)
	check(chain_game.is_clearing_crate(chain_ids[1]) and not chain_game.is_clearing_crate(chain_ids[0]),
		"Only the first bottom row must retire when a chain starts")
	advance(chain_game, 57 * Simulation.STEP)
	check(chain_game.is_clearing_crate(chain_ids[0]) and not chain_game.is_clearing_crate(chain_ids[1]),
		"The next row must retire with its own IDs after the first collapse")
	advance(chain_game, 86 * Simulation.STEP)
	check(chain_game.lines == 2 and chain_game.score == 200, "Successive full bottom rows clear without score multipliers")
	check(chain_game.crates.is_empty() and chain_game.state == "playing", "A chain must finish with safe descent")
	check(chain_game.chain == 0 and chain_game.best_combo == 2, "The longest chain must survive the reset of the current chain")
	var ended_at := "2026-11-15T22:04:35"
	check(chain_game.match_result(ended_at).is_empty(), "An unfinished game must have no match result")
	for row in range(chain_game.tuning.rows):
		chain_game.add_crate(0, row)
	chain_game.advance(Simulation.STEP, 0)
	var result := chain_game.match_result(ended_at)
	check(result == {"ended_at": ended_at, "duration_ms": 1208, "score": 200, "lines": 2,
		"crates": 8, "best_combo": 2, "reason": "overflow"}, "A match result must count clear ticks and preserve the final counters and loss reason")
	check(result.duration_ms > chain_game.elapsed * 1000, "The match duration must include time spent in clear animations")
	chain_game.reset(7481)
	check(chain_game.cleared_crates == 0 and chain_game.best_combo == 0 and chain_game.ticks == 0,
		"A new match must reset crates cleared, best combo and active ticks")
	var upper_only := empty(4, 6)
	upper_only.player.x = 2
	for column in range(4):
		upper_only.add_crate(column, 3)
	upper_only.advance(1.0 / 120, 0)
	check(upper_only.lines == 0 and not upper_only.is_clearing_crate(int(upper_only.crates[0].id)),
		"A full upper row must not clear independently")


func add_full_rows(game: StackSimulation, count: int) -> void:
	var top := game.tuning.rows - count
	game.player.y = top - game.tuning.player_height
	for row in range(top, game.tuning.rows):
		for column in range(game.tuning.columns):
			game.add_crate(column, row)


func equipment_rewards() -> void:
	var disabled := empty(4)
	add_full_rows(disabled, 5)
	disabled.advance(10.0, 0)
	check(disabled.lines == 5 and disabled.ticks == 1200 and not disabled.equipment_pending
		and disabled.equipment_rows == 0, "Simulations without equipment must ignore reward thresholds")

	var game := empty(4)
	game.equipment_enabled = true
	game.resolve_equipment(true)
	check(not game.boots_equipped, "Resolving equipment without an offer must have no effect")
	add_full_rows(game, 4)
	game.advance(3.0, 0)
	check(game.lines == 4 and game.equipment_rows == 4 and not game.equipment_pending,
		"Four rows must carry toward the first equipment offer")
	var start := game.ticks
	add_full_rows(game, 8)
	game.advance(Simulation.STEP, 0)
	check(game.lines == 5 and game.state == "clearing" and not game.equipment_pending,
		"Reaching a threshold must leave the whole clear animation available to play")
	game.advance(2.0, 0)
	check(game.lines > 5 and game.chain > 1 and game.state == "clearing" and not game.equipment_pending,
		"A reward must wait while later rows in the same combo are clearing")
	game.advance(10.0, 1)
	var clear_ticks := ceili((game.tuning.clear_flash_time + game.tuning.collapse_time) / Simulation.STEP)
	check(game.lines == 12 and game.cleared_crates == 48 and game.best_combo == 8 and game.chain == 0
		and game.state == "playing" and game.ticks == start + 1 + 8 * clear_ticks,
		"A long frame must stop on the first playable boundary after the final collapse")
	check(game.equipment_pending and game.equipment_rows == 7 and game.accumulator == 0.0,
		"Opening the first offer must preserve the second threshold and surplus, and discard leftover frame time")
	var frozen := [game.ticks, game.elapsed, game.player, game.player_velocity, game.cranes.duplicate(true), game._rng.state]
	game.advance(20.0, 1, true)
	check(frozen == [game.ticks, game.elapsed, game.player, game.player_velocity, game.cranes, game._rng.state],
		"An open offer must ignore elapsed wall time, movement and jumps")
	game.resolve_equipment(false)
	check(game.equipment_pending and not game.boots_equipped and game.equipment_rows == 2 and game.ticks == frozen[0],
		"Skipping the first offer must immediately present the next one from the same combo")
	game.resolve_equipment(true)
	check(not game.equipment_pending and game.boots_equipped and game.boots_charges == Simulation.BOOTS_MAX_CHARGES,
		"Accepting an offer must equip ten charges")
	game.advance(Simulation.STEP, 0)
	check(game.ticks == frozen[0] + 1 and game.grounded and game.events.is_empty(),
		"Play must resume on a fresh tick without input or time carried through the reward")

	start = game.ticks
	add_full_rows(game, 9)
	game.advance(5.0, 0)
	check(not game.equipment_pending and game.equipment_rows == 1 and game.boots_charges == 10
		and game.ticks == start + 600, "Full boots must silently consume every crossed threshold and retain surplus")
	game.advance(Simulation.STEP, 0, true)
	game.advance(Simulation.STEP, 0, true)
	game.advance(1.0, 0)
	add_full_rows(game, 4)
	game.advance(3.0, 0)
	check(game.equipment_pending and game.equipment_rows == 0 and game.boots_charges == 9,
		"Partially spent boots must get an offer at the next threshold")
	game.resolve_equipment(false)
	check(not game.equipment_pending and game.boots_equipped and game.boots_charges == 9,
		"Skipping a replacement must keep the equipped pair and its remaining charges")
	add_full_rows(game, 10)
	game.advance(5.0, 0)
	check(game.equipment_pending and game.equipment_rows == 5, "An earlier skip must not prevent future offers")
	game.resolve_equipment(true)
	check(not game.equipment_pending and game.equipment_rows == 0 and game.boots_charges == 10,
		"A replacement must restore ten charges and silently consume the next threshold at full capacity")
	game.reset(7481)
	check(game.equipment_enabled and not game.equipment_pending and not game.boots_equipped
		and game.boots_charges == 0 and game.equipment_rows == 0, "Reset must retain the opt-in and clear the run's equipment")


func equipment_jumps() -> void:
	var game := empty(4)
	game.equipment_enabled = true
	add_full_rows(game, 5)
	game.advance(3.0, 0)
	game.resolve_equipment(true)
	game.advance(Simulation.STEP, 0)
	for charges in range(Simulation.BOOTS_MAX_CHARGES, 0, -1):
		game.advance(Simulation.STEP, 0, true)
		var jump_velocity := game.player_velocity.y
		check(game.events == [{"type": "jump"}] and game.boots_charges == charges,
			"The ordinary jump must not spend a charge")
		game.advance(50 * Simulation.STEP, 0)
		check(game.player_velocity.y > 0.0 and not game.grounded and game.boots_charges == charges,
			"Without a second press, the original jump must continue into descent")
		game.advance(Simulation.STEP * .25, 0, true)
		check(game.boots_charges == charges, "A press before a fixed tick must wait for that tick")
		game.advance(Simulation.STEP * .75, 0)
		check(game.events == [{"type": "air_jump"}] and game.boots_charges == charges - 1
			and game.player_velocity.y == jump_velocity and game.boots_equipped,
			"One separate airborne press must spend one charge and launch a full jump, including the last charge")
		game.advance(Simulation.STEP, 0, true)
		check(game.events.is_empty() and game.boots_charges == charges - 1 and game.player_velocity.y > jump_velocity,
			"Additional presses before landing must not launch another air jump")
		game.advance(1.0, 0)
		check(game.grounded and game.boots_equipped == (charges > 1),
			"Landing must end the flight and remove the boots when the last charge is spent")
	add_full_rows(game, 5)
	game.advance(3.0, 0)
	check(game.equipment_pending, "A new offer must be available after the boots are exhausted")
	game.resolve_equipment(true)

	for row in range(7, game.tuning.rows):
		game.add_crate(2, row)
	var ledge := Vector2(2.94, 7 - game.tuning.player_height)
	game.player = ledge
	game.advance(Simulation.STEP, 0)
	game.advance(Simulation.STEP, 1)
	game.advance(.11, 1)
	game.advance(Simulation.STEP, 0, true)
	check(not game.grounded and game.player_velocity.y > 0.0 and game.events.is_empty() and game.boots_charges == 10,
		"Walking off a ledge must not grant an air jump after coyote time expires")
	game.advance(1.0, 0)
	game.player = ledge
	game.advance(Simulation.STEP, 1)
	game.advance(Simulation.STEP, 0, true)
	check(game.events == [{"type": "jump"}] and game.boots_charges == 10,
		"Coyote takeoff must still use an ordinary jump")
	game.advance(Simulation.STEP, 0, true)
	check(game.events == [{"type": "air_jump"}] and game.boots_charges == 9,
		"Coyote takeoff must qualify for the second jump")


func loss_conditions() -> void:
	var crushed := empty(4, 6)
	crushed.player.x = 1.2
	crushed.add_crate(3, 5)
	var falling := crushed.add_crate(1, 3, 1)
	check(crushed.impact_crate_id == -1, "A living character must have no impact crate")
	crushed.advance(1.0, 0)
	check(crushed.state == "over" and crushed.loss_reason == "crushed", "A crate falling on the head must end the party")
	check(crushed.impact_crate_id == int(falling.id), "The impact ID must identify the crate that hit the character")
	check(crushed.events == [{"type": "over", "reason": "crushed", "score": 0}], "Crush must still emit the ordinary loss event")
	var ended_at := "2026-11-15T21:52:35"
	var crush_result := crushed.match_result(ended_at)
	check(crush_result == {"ended_at": ended_at, "duration_ms": 317, "score": 0, "lines": 0,
		"crates": 0, "best_combo": 0, "reason": "crushed"}, "Crush must preserve the ordinary final result and duration")
	var final_ticks := crushed.ticks
	var final_player := crushed.player
	var final_crates := crushed.crates.duplicate(true)
	crushed.advance(.5, 1.0, true)
	check(crushed.ticks == final_ticks and crushed.events.is_empty() and crushed.player == final_player
		and crushed.crates == final_crates and crushed.impact_crate_id == int(falling.id)
		and crushed.match_result(ended_at) == crush_result, "Game over must be emitted only once and freeze the model")
	crushed.reset(7481)
	check(crushed.impact_crate_id == -1, "Reset must discard the prior impact ID")
	var full := empty(4, 6)
	full.cranes_enabled = true
	for row in range(6):
		full.add_crate(0, row)
	full.advance(1.0 / 120, 0)
	check(full.state == "over" and full.loss_reason == "overflow" and full.impact_crate_id == -1,
		"A settled tower at full field height blocks the cranes without reporting an impact")
	check(full.cranes[0].x == -Simulation.CRANE_EDGE_MARGIN, "Overflow must stop the cranes before another release")


func crush_beside_support() -> void:
	var game := empty()
	game.player = Vector2(2.1, 4.83)
	game.grounded = false
	var support := game.add_crate(1.0, 5.0)
	for row in range(6, game.tuning.rows):
		game.add_crate(1.0, row)
	var impact := game.add_crate(1.8, 3.81, 6.0)
	game.advance(Simulation.STEP, 0.0)
	check(game.state == "over" and game.loss_reason == "crushed" and game.impact_crate_id == int(impact.id),
		"An off-center impact beside a stack must cause the ordinary loss")
	check(not game.grounded and is_equal_approx(float(impact.y), 3.86) and crates_separate(game),
		"The lethal simulation tick must keep the airborne hero and the falling crate in their original contact geometry")
	var final_player := game.player
	var final_crates := game.crates.duplicate(true)
	var view := StackWorldView.new()
	view.model = game
	view.crush_progress = 1.0
	var geometry := view.crush_geometry(impact)
	var crate: Rect2 = geometry.crate
	var hero: Rect2 = geometry.hero
	var support_top := float(support.y) * StackWorldView.PIXELS_PER_CELL
	var support_right := (float(support.x) + 1.0) * StackWorldView.PIXELS_PER_CELL
	check(crate.end.y <= support_top + Simulation.EPS, "The animated crate must stop above the adjacent support")
	check(hero.position.x >= support_right - Simulation.EPS, "The flattened hero must stay outside the stack")
	check(hero.position.y <= crate.end.y + Simulation.EPS and hero.position.x < crate.end.x and hero.end.x > crate.position.x,
		"The flattened hero must remain in contact with the crate")
	check(game.player == final_player and game.crates == final_crates,
		"Drawing the supported crush must preserve the final simulation positions")
	view.free()


func crane_cycles() -> void:
	var game := empty()
	game.cranes_enabled = true
	var stride := game.tuning.crane_speed * Simulation.STEP
	var released := [false, false]
	var passes := [0, 0]
	var waits := []
	var saw_independent_entry := false
	var wait_started := [0, 0]
	var wait_length := [0.0, 0.0]
	check(game.cranes.size() == 2 and game.cranes[0].direction == 1 and game.cranes[1].direction == -1,
		"Two cranes travel on their fixed, opposite routes")
	for tick in range(120 * 24):
		var previous := game.cranes.duplicate(true)
		game.advance(Simulation.STEP, 0.0)
		var columns := []
		for event in game.events:
			if event.type != "drop":
				continue
			var crane: Dictionary = game.cranes[event.crane]
			var crate := game.crates.back() as Dictionary
			if crate.id != event.crate_id:
				for added in game.crates:
					if added.id == event.crate_id:
						crate = added
						break
			check(not released[event.crane] and previous[event.crane].loaded and not crane.loaded,
				"A pass releases its one held crate exactly once")
			check(not columns.has(event.column) and event.column in range(game.tuning.columns),
				"Releases in a step must use distinct columns in the board")
			check(crate.id == event.crate_id and crate.x == event.column and crate.y == Simulation.CRATE_RELEASE_Y and crate.vy == 0.0,
				"The released crate must enter the ordinary physics at rest and at the original height")
			check(absf(crane.x - (event.column + 0.5)) <= stride + Simulation.EPS and crane.open_time > 0.0,
				"The crane must open its jaws in the column at the handoff")
			columns.append(event.column)
			released[event.crane] = true
			passes[event.crane] += 1
		for index in range(2):
			var before: Dictionary = previous[index]
			var crane: Dictionary = game.cranes[index]
			var entrance := -Simulation.CRANE_EDGE_MARGIN if crane.direction == 1 else game.tuning.columns + Simulation.CRANE_EDGE_MARGIN
			var exit := game.tuning.columns - entrance
			if not before.waiting and not crane.waiting:
				check(is_equal_approx((crane.x - before.x) * crane.direction, stride), "The crane must keep a constant speed before and after release")
			elif not before.waiting and crane.waiting:
				check(released[index] and not crane.loaded and crane.x == exit, "The empty crane must travel fully past the edge before waiting")
				check(crane.wait_remaining >= game.tuning.crane_wait_min and crane.wait_remaining <= game.tuning.crane_wait_max,
					"Each sampled wait must be within bounds")
				waits.append(crane.wait_remaining)
				wait_started[index] = tick
				wait_length[index] = crane.wait_remaining
			elif before.waiting and not crane.waiting:
				var waited := (tick - int(wait_started[index])) * Simulation.STEP
				check(crane.loaded and crane.x == entrance and absf(waited - float(wait_length[index])) <= Simulation.STEP + Simulation.EPS,
					"The next loaded pass starts offstage only after its own wait")
				saw_independent_entry = saw_independent_entry or game.cranes[1 - index].waiting
				released[index] = false
			else:
				check(crane.x == exit and not crane.loaded, "A waiting carriage holds at its hidden exit")
		# Clear the runway after checking each actual spawn, so late cycles can be exercised without a loss.
		game.crates.clear()
	check(passes[0] >= 4 and passes[1] >= 4, "Both cranes must sustain repeated passes")
	check(waits.size() >= 8 and waits.min() < waits.max() and saw_independent_entry,
		"Return times must vary and allow one crane to re-enter while the other is still waiting")


func crane_contention() -> void:
	var game := empty()
	game.cranes_enabled = true
	var stride := game.tuning.crane_speed * Simulation.STEP
	game.cranes[0].x = 0.5 - stride
	game.cranes[1].x = 0.5 + stride
	for crane in game.cranes:
		crane.release_column = 0
	game.advance(Simulation.STEP, 0.0)
	check(game.crates.size() == 1 and game.crates[0].x == 0 and game.cranes[0].loaded and not game.cranes[1].loaded,
		"The crane at its last column gets the only safe release for a shared target")
	check(game.cranes[0].release_column == 1, "The other crane should try the next column without stopping")
	advance(game, 1.0 / game.tuning.crane_speed)
	check(game.crates.size() == 2 and game.crates.any(func(crate: Dictionary) -> bool: return crate.x == 1),
		"The next column can take the second crate without overlapping the first")


func storage() -> void:
	var path := "user://test-profile-%d.json" % Time.get_ticks_usec()
	var legacy_records := [{"score": 600, "date": "12.11.2026"}, {"score": 100, "date": "13.11.2026"}]
	var version_one := JSON.stringify({"version": 1, "music": .2, "effects": 0,
		"vibration": false, "records": legacy_records})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(version_one)
	file.close()
	var loaded := Profile.new(path)
	check(is_equal_approx(loaded.music, .2) and loaded.effects == 0 and not loaded.vibration,
		"Migration must preserve legacy sound and vibration settings")
	check(loaded.records == legacy_records and loaded.matches.is_empty(), "Migration must preserve legacy scores and dates without creating matches")
	check(FileAccess.get_file_as_string(path) == version_one, "A read-only profile load must preserve the legacy file")
	check(loaded.statistics() == {"played": 0, "best_score": 600,
		"total_lines": 0, "total_crates": 0, "max_lines": 0, "best_combo": 0,
		"crushed": 0, "overflow": 0, "average_duration_ms": 0, "max_duration_ms": 0},
		"Legacy scores may set the best score without affecting any match statistics")
	var first := {"ended_at": "2026-11-15T19:30:20", "duration_ms": 8100, "score": 200,
		"lines": 2, "crates": 20, "best_combo": 1, "reason": "crushed"}
	var second := {"ended_at": "2026-11-15T18:00:42", "duration_ms": 12601, "score": 400,
		"lines": 4, "crates": 40, "best_combo": 3, "reason": "overflow"}
	loaded.add_match(first)
	loaded.add_match(second)
	check(loaded.statistics() == {"played": 2, "best_score": 600,
		"total_lines": 6, "total_crates": 60, "max_lines": 4, "best_combo": 3,
		"crushed": 1, "overflow": 1, "average_duration_ms": 10351, "max_duration_ms": 12601},
		"Aggregates must use all finished matches and a rounded average duration")
	var migrated: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(migrated.version == 2, "The next save must upgrade the existing profile file")
	var migrated_profile := Profile.new(path)
	check(is_equal_approx(migrated_profile.music, .2) and migrated_profile.effects == 0 and not migrated_profile.vibration,
		"The upgraded save must retain the legacy settings on reload")
	check(migrated_profile.records == legacy_records and migrated_profile.matches == [second, first],
		"The upgraded save must preserve legacy rows and round-trip new rows in completion order, even if the clock goes backward")
	var latest := first.duplicate()
	for index in range(15):
		latest.score = index * 100
		migrated_profile.add_match(latest)
	var with_history := Profile.new(path)
	check(with_history.matches.size() == 17 and with_history.matches.front() == latest and with_history.matches.back() == first,
		"Full history must retain older and zero-score matches beyond the old records limit")
	check(with_history.statistics().best_score == 1400, "A new score may exceed the legacy high score")
	var malformed: Dictionary = first.duplicate()
	malformed.lines = -1
	var fractional: Dictionary = first.duplicate()
	fractional.duration_ms = 2.5
	var wrong_reason: Dictionary = first.duplicate()
	wrong_reason.reason = "abandoned"
	var wrong_date: Dictionary = first.duplicate()
	wrong_date.ended_at = "2026-02-31T19:30:20"
	var partial: Dictionary = first.duplicate()
	partial.erase("crates")
	migrated.matches = ["invalid", malformed, second, wrong_reason, wrong_date, fractional, partial, first]
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(migrated))
	file.close()
	check(Profile.new(path).matches == [second, first], "Malformed saved matches must not affect valid history")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("broken-json")
	file.close()
	var recovered := Profile.new(path)
	check(recovered.records.is_empty() and recovered.matches.is_empty() and not recovered.last_error.is_empty(),
		"Corrupt storage must fall back safely")
	DirAccess.remove_absolute(path)


func demo_games() -> void:
	var personal := Simulation.new(Config.new(), 74)
	var rng_state: int = personal._rng.state
	var demo := StackDemo.new(Config.new(), 7481)
	for tick in range(120 * 120):
		demo.advance(1.0 / 120.0)
	check(demo.model != personal, "Demo and personal game must be different simulations")
	check(personal.ticks == 0 and personal.score == 0 and personal._rng.state == rng_state, "AI demo must not consume personal time, score or randomness")
	check(demo.jumps > 0 and demo.drops > 0, "Demo must jump and receive real crane drops")
	check(demo.lines > 0, "Reactive AI must be able to clear a real bottom line")
	check(demo.losses > 0 and demo.rounds > 1, "Demo must restart real lost games without inventing victory rules")
	print("DEMO_PASS: %d jumps, %d drops, %d lines, %d losses, %d rounds" % [demo.jumps, demo.drops, demo.lines, demo.losses, demo.rounds])


func vibration_toggle() -> void:
	var path := "user://test-vibration-profile.json"
	var app = load("res://game/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile = Profile.new(path)
	app.profile.vibration = false
	app.sound.queue_free()
	var probe := HapticProbe.new()
	app.add_child(probe)
	probe.setup(app.profile)
	app.sound = probe
	app._show_screen("settings")
	app._vibration_option(app.panel.get_child(0))
	await process_frame
	var toggle: Button = app.buttons.vibration
	toggle.grab_focus()
	toggle.button_pressed = true
	check(app.profile.vibration and toggle.text.ends_with("Вкл") and toggle.button_pressed, "Enabled vibration must immediately show a clear on state")
	check(probe.pulses == [60], "Enabling vibration must request one short preview pulse")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style: StyleBoxFlat = toggle.get_theme_stylebox(state)
		check(is_zero_approx(style.bg_color.a) if state == "focus" else style.bg_color.a >= 0.7 and style.bg_color.a <= 0.9, "Vibration must use the shared translucent action styles without a black fallback: " + state)
		check(style == app.theme.get_stylebox(state, "Button"), "Vibration must share every action state: " + state)
	toggle.button_pressed = false
	check(not app.profile.vibration and toggle.text.ends_with("Выкл") and probe.pulses == [60], "Disabling vibration must update the state without a pulse")
	app.profile.vibration = true
	probe.unlocked = true
	probe.effect("jump", false)
	check(probe.pulses == [60], "Background game effects must never vibrate the phone")
	probe.effect("jump")
	check(probe.pulses == [60, 12], "Personal game haptics must remain enabled by the saved setting")
	app.profile.vibration = false
	probe.preview_vibration()
	check(probe.pulses == [60, 12], "A disabled vibration setting must suppress preview requests")
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)


func app_flow() -> void:
	check(ProjectSettings.get_setting("application/config/name") == "Stack Attack · Ночная смена", "Visual changes must preserve the existing user data namespace")
	var path := "user://test-match-flow-%d.json" % Time.get_ticks_usec()
	var app = load("res://game/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile = Profile.new(path)
	app.sound.profile = app.profile
	app.sound.apply_volumes()
	check(app.sound.music_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and app.sound.music_player.stream.loop_end > 300000, "Music must loop over decoded frames on every platform")
	check(app.screen == "menu" and app.buttons.has("play") and app.buttons.has("settings") and app.buttons.has("statistics"), "Main menu must offer the agreed screens")
	var art_model = app.world.model
	var art_snapshot := [art_model.player, art_model.score, art_model.crates.duplicate(true), art_model._rng.state, art_model.ticks]
	for equipped in [false, true]:
		check(StackWorldView.pause_portrait(equipped).get_size() == Vector2(32, 48),
			"The pause portrait must preserve the full hero sprite canvas")
		check(art_snapshot == [art_model.player, art_model.score, art_model.crates, art_model._rng.state, art_model.ticks],
			"Equipment portraits must never mutate gameplay")
	for pose in ["idle", "walk", "jump", "push"]:
		check(app.world.HERO_TEXTURES[pose].get_size() == Vector2(32, 48), "All workshop poses must preserve the same full sprite canvas")
	check(app.world.CRATE_TEXTURE.get_size() == Vector2(48, 48) and app.world.CRATE_TEXTURE.resource_path == "res://art/crate_wood.png", "All crates must use the one existing wooden appearance")
	check(app._missing_menu_glyphs().is_empty(), "The original workshop bitmap face must cover the visible menu text")
	var personal = app.model
	var random_before: int = personal._rng.state
	var demo_losses: int = app.demo.losses
	app.demo._restart()
	for row in range(app.demo.model.tuning.rows - 1):
		app.demo.model.add_crate(0, row)
	app._advance_demo(.1)
	check(app.demo.losses == demo_losses + 1, "The isolation test must exercise a real demo loss")
	check(app.model == personal and personal.ticks == 0 and personal._rng.state == random_before, "Menu demo must not advance or replace the personal game")
	check(app.session == 0 and app.profile.matches.is_empty() and not FileAccess.file_exists(path),
		"Losing the demo cannot create personal sessions, history rows or a profile file")
	for index in range(10):
		app.profile.records.append({"score": 1000000 - index * 100, "date": "12.11.2026"})
	app.profile.matches.append({"ended_at": "2026-11-15T20:04:05", "duration_ms": 3651000,
		"score": 100000000, "lines": 1000000, "crates": 10000000, "best_combo": 11, "reason": "overflow"})
	for dimensions in [Vector2i(320, 568), Vector2i(568, 320), Vector2i(390, 844), Vector2i(844, 390),
			Vector2i(344, 882), Vector2i(882, 344), Vector2i(768, 1004), Vector2i(1004, 768), Vector2i(360, 360)]:
		root.size = dimensions
		for menu in ["menu", "settings", "statistics", "paused", "over"]:
			app._show_screen(menu)
			if menu == "settings" and not OS.has_feature("android"):
				# Include the real Android-only row when checking the smallest layouts.
				app._vibration_option(app.panel.get_child(0))
			for frame in range(4):
				await process_frame
			var viewport := Rect2(Vector2.ZERO, app.size)
			check(viewport.encloses(app.panel.get_global_rect()), "%s panel must fit %s without scrolling" % [menu, dimensions])
			check(app.panel.find_children("*", "ScrollContainer", true, false).is_empty(), "Menus must not contain a ScrollContainer")
			for control in app.panel.find_children("*", "Control", true, false):
				if control is Button:
					check(control.size.y >= 48, "Shared styling must preserve touch target height")
					for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
						var style: StyleBoxFlat = control.get_theme_stylebox(state)
						check(style == app.theme.get_stylebox(state, "Button"), "Every menu button must share the result action style: " + menu + "/" + str(control.name) + "/" + state)
						check(style.border_width_left == 1 and style.corner_radius_top_left == 4 and (is_zero_approx(style.bg_color.a) if state == "focus" else style.bg_color.a >= 0.7 and style.bg_color.a <= 0.9), "Shared actions must retain the thin border and translucent backing")
				if control is Label or control.focus_mode == Control.FOCUS_ALL:
					check(viewport.encloses(control.get_global_rect()), "%s content must remain visible at %s: %s" % [menu, dimensions, control.name])
			var focused := root.gui_get_focus_owner()
			check(focused != null and app.panel.is_ancestor_of(focused), "Focus must start inside each menu panel")
	app.profile.records.clear()
	app.profile.matches.clear()
	for reason in ["crushed", "overflow"]:
		app.model.loss_reason = reason
		app.model.score = 200
		app.model.lines = 2
		app._show_screen("over")
		var labels: Array[String] = []
		for label in app.panel.find_children("*", "Label", true, false):
			labels.append(label.text)
		check(labels == ["Смена окончена", "Счёт: 200"], "Game over must display only its unchanged title and final score for either loss")
		check(app.model.loss_reason == reason and app.model.lines == 2, "Hiding result details must preserve the model's reason and line count")
	for dimensions in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(768, 1004)]:
		root.size = dimensions
		for score in [0, 200, 100000000]:
			app.model.score = score
			app._show_screen("over")
			for frame in range(4):
				await process_frame
			var label: Label = app.panel.find_child("result_score", true, false)
			check(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "Result score must be horizontally centered")
			check(absf(label.get_global_rect().get_center().x - app.size.x * 0.5) <= 1, "Result score layout must share the viewport's center")
			var text_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			check(label.autowrap_mode == TextServer.AUTOWRAP_OFF and text_width <= label.size.x - 4, "Long result scores must fit on one centered line")
			for id in ["again", "home"]:
				for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
					var style: StyleBoxFlat = app.buttons[id].get_theme_stylebox(state)
					check(style.bg_color.a >= 0.7 and style.bg_color.a <= 0.9 and style.border_width_left == 1, "Result buttons need a subtle backing and thin border in every state")
	app._show_screen("menu")
	app._start_game()
	app._pause()
	var paused_ticks: int = app.model.ticks
	var paused_player: Vector2 = app.model.player
	app._show_screen("menu")
	app._advance_demo(5.0)
	check(app.model.ticks == paused_ticks and app.model.player == paused_player and app.session == 1, "Visiting a demo menu must preserve a paused personal game")
	app._show_screen("paused")
	for index in range(4):
		await process_frame
	check(app.model.ticks == paused_ticks, "Pause must freeze the entire simulation")
	app._show_screen("playing")
	for dimensions in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(320, 568), Vector2i(568, 320),
			Vector2i(344, 882), Vector2i(882, 344), Vector2i(768, 1004), Vector2i(1004, 768), Vector2i(360, 360)]:
		root.size = dimensions
		await process_frame
		await process_frame
		check(app.model.tuning.columns == 10 and app.model.tuning.rows == 11, "Orientation cannot change field dimensions")
		for rect in app.world.controls.values():
			check(Rect2(Vector2.ZERO, app.size).encloses(rect), "Every touch control must stay inside the viewport")
			check(not app.world.field.intersects(rect), "Touch controls must not cover the field")
	app._show_screen("settings")
	check(app.sliders.has("music") and app.sliders.has("effects"), "Music and effects need separate sliders")
	app._show_screen("statistics")
	check(app.buttons.has("back"), "Statistics must provide a return path")
	app.set_process(false)
	# Exercise input and button callbacks without starting audio in the headless lifecycle test.
	app.sound.unlocked = true
	app.sound.sounds.clear()
	var arrow_up := InputEventKey.new()
	arrow_up.physical_keycode = KEY_UP
	arrow_up.pressed = true
	app._input(arrow_up)
	check(not app.jump_pending, "Arrow Up in menus must remain available for UI navigation")
	app._start_game()
	check(app.session == 2 and app.model.score == 0, "Restart must start a fresh party")
	app._input(arrow_up)
	check(app.jump_pending, "Arrow Up must queue the ordinary jump during personal play")
	app._pause()
	app._input(arrow_up)
	check(not app.jump_pending, "Arrow Up must not queue a jump on the pause panel")
	app.buttons.restart.pressed.emit()
	await process_frame
	check(app.session == 3 and app.profile.matches.is_empty() and not FileAccess.file_exists(path),
		"Restarting an unfinished match must discard it without saving")
	app._pause()
	app.buttons.home.pressed.emit()
	await process_frame
	check(app.screen == "menu" and app.profile.matches.is_empty() and not FileAccess.file_exists(path),
		"Leaving an unfinished match must discard it without saving")
	app.buttons.play.pressed.emit()
	await process_frame
	app._advance_game(1.0)
	app._pause()
	app._advance_game(30.0)
	check(app.model.ticks == 120, "Paused wall time must not add active match ticks")
	app.buttons.resume.pressed.emit()
	await process_frame
	app.model.crates.clear()
	for row in range(app.model.tuning.rows):
		app.model.add_crate(0, row)
	app._advance_game(Simulation.STEP)
	check(app.screen == "over" and app.profile.matches.size() == 1, "The normal loss path must save exactly one personal match")
	if app.profile.matches.size() == 1:
		var result: Dictionary = app.profile.matches[0]
		check(result.duration_ms == 1008 and result.reason == "overflow" and result.score == 0,
			"The saved zero-score loss must count active ticks and exclude the pause")
		check(Profile.new(path).matches == [result], "The completed match must survive loading the actual profile file")
	app._end_game()
	check(app.profile.matches.size() == 1, "Re-entering the result screen must not duplicate the completed match")
	app.buttons.again.pressed.emit()
	await process_frame
	check(app.screen == "playing", "Playing again after a loss must start a new unfinished match")
	app.model.crates.clear()
	app.model.cranes_enabled = false
	app.model.player.x = 4.3
	var impact: Dictionary = app.model.add_crate(4.0, 8.0, 1.0)
	app._advance_game(.5)
	var impact_ticks: int = app.model.ticks
	check(app.model.state == "over" and app.screen == "playing" and app.crush_elapsed == 0.0,
		"A fatal hit must stop physics immediately and play before the result appears")
	check(app.model.impact_crate_id == impact.id and Profile.new(path).matches.size() == 2,
		"The fatal impact must keep its crate ID and save the result before the animation")
	app._advance_game(.12)
	app._pause()
	app._advance_game(.5)
	check(app.crush_elapsed == .12 and app.model.ticks == impact_ticks,
		"Pause must freeze the squash without extending the match")
	app.buttons.resume.pressed.emit()
	await process_frame
	app._advance_game(.31)
	check(app.screen == "over" and app.model.ticks == impact_ticks and app.profile.matches.size() == 2,
		"The standard result must follow the squash without writing a duplicate match")
	app.buttons.again.pressed.emit()
	await process_frame
	check(app.crush_elapsed < 0.0 and app.model.impact_crate_id == -1, "A new match must clear the death pose")
	app.queue_free()
	await process_frame
	check(Profile.new(path).matches.size() == 2, "Closing during a new match must leave completed history unchanged")
	DirAccess.remove_absolute(path)


func random_sessions() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 48132
	var count := 0
	for trial in range(8):
		var game := Simulation.new(Config.new(), trial + 100)
		var axis := 0.0
		var valid := true
		for tick in range(6000):
			if tick % 36 == 0:
				axis = rng.randi_range(-1, 1)
			game.advance(1.0 / 120, axis, tick % 67 == 0)
			count += 1
			if tick % 20 == 0:
				for a in game.crates:
					valid = valid and float(a.x) >= -.001 and float(a.x) <= 9.001 and float(a.y) <= 10.001
					if game.state == "playing":
						var hero_rect := Rect2(game.player + Vector2(.04, .04), Vector2(game.tuning.player_width - .08, game.tuning.player_height - .08))
						valid = valid and not hero_rect.intersects(Rect2(a.x+.04,a.y+.04,.92,.92))
					for b in game.crates:
						if int(a.id) >= int(b.id):
							continue
						valid = valid and not Rect2(a.x+.01,a.y+.01,.98,.98).intersects(Rect2(b.x+.01,b.y+.01,.98,.98))
			if game.state == "over":
				break
		check(valid, "Seeded session %d must keep crates inside the field without interpenetration" % trial)
	print("STRESS_PASS: %d ticks across eight seeded sessions" % count)
