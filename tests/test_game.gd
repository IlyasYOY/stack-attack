extends SceneTree
var failures: Array[String] = []
var assertions := 0
const Config = preload("res://game/tuning.gd")
const Simulation = preload("res://game/simulation.gd")
const Profile = preload("res://game/profile.gd")
const NEW_EQUIPMENT := ["strong_arms", "speed_boots", "lamp_helmet", "spring_boots"]

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
	crate_variant_assignment()
	crate_slide_signal()
	diagonal_crate_collisions()
	clearing()
	equipment_rewards()
	equipment_jumps()
	bonus_equipment()
	mallet_actions()
	gloves_pull_and_break()
	gloves_blockers()
	gloves_detachment()
	gloves_input_priority()
	helmet_falling_hits()
	helmet_underside_hits()
	helmet_multiple_hits()
	loss_conditions()
	crush_beside_support()
	crane_cycles()
	crane_contention()
	storage()
	broken_crate_history()
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
	var airborne := falling.add_crate(4, 9.8, .2, 8)
	falling.player.x = 4 - falling.tuning.player_width
	advance(falling, .04, 1)
	check(float(airborne.x) > 4.01 and float(airborne.y) > 9.8 and float(airborne.y) < 10,
		"The character must be able to push a crate while it is falling")
	check(int(airborne.variant) == 8, "A moving and falling crate must keep its assigned appearance")
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


func crate_variant_assignment() -> void:
	var game := Simulation.new(Config.new(), 42)
	var reference := Simulation.new(Config.new(), 42)
	var variants := {}
	for crate in game.crates:
		variants[int(crate.variant)] = true
	for crane in game.cranes:
		variants[int(crane.variant)] = true
	check(variants.size() == game.crates.size() + game.cranes.size(),
		"The initial floor crates and crane loads must have distinct appearances")
	var initial_crates := game.crates.duplicate(true)
	var initial_cranes := game.cranes.duplicate(true)
	var gameplay_rng := game._rng.state
	var assigned := {}
	for index in range(Simulation.CRATE_VARIANT_COUNT):
		var explicit := game.add_crate(4.0, 0.0, 0.0, index)
		check(int(explicit.variant) == index and int(explicit.color) == int(explicit.id) % 3,
			"An explicit appearance must leave the existing crate IDs and color sequence intact")
		var appearance := int(game.add_crate(4.0, 0.0).variant)
		assigned[appearance] = true
		check(appearance == reference.add_crate(4.0, 0.0).variant,
			"Explicit appearances must not consume a seeded assignment")
	check(assigned.size() == Simulation.CRATE_VARIANT_COUNT and assigned.keys().all(
		func(variant: int) -> bool: return variant >= 0 and variant < Simulation.CRATE_VARIANT_COUNT),
		"A full appearance cycle must cover precisely the valid variants")
	check(game._rng.state == gameplay_rng, "Assigning appearances must not consume gameplay randomness")
	game.add_crate(4.0, 0.0)
	game.reset(42)
	check(game.crates == initial_crates and game.cranes == initial_cranes,
		"Resetting the same seed must reproduce both floor and crane appearances")


func crate_slide_signal() -> void:
	for direction in [1, -1]:
		var game := empty()
		var crate := game.add_crate(4, 10)
		game.player.x = 4 - game.tuning.player_width if direction == 1 else 5.0
		game.advance(Simulation.STEP * .25, direction)
		check(not game.is_crate_sliding(direction, false), "Push intent needs actual horizontal motion before it can sound")
		game.advance(Simulation.STEP * .75, direction)
		var continuous := game.is_crate_sliding(direction, false)
		for tick in range(49):
			game.advance(Simulation.STEP, direction)
			continuous = continuous and game.is_crate_sliding(direction, false)
		check(continuous, "Sustained direct pushing must sound through a cell boundary in either direction")
		check(not game.is_crate_sliding(-direction, false), "Reversing input must silence the slide immediately")
		var x := float(crate.x)
		game.advance(0.0, 0.0)
		game.advance(0.0, direction)
		check(not game.is_crate_sliding(direction, false) and float(crate.x) == x,
			"Releasing and repressing between steps must not replay a stale slide")
		game.advance(Simulation.STEP, 0.0)
		check((float(crate.x) - x) * direction > 0.0 and not game.is_crate_sliding(0.0, false),
			"An ordinary push keeps its existing motion and becomes silent on release")

	for obstacle in ["edge", "crate"]:
		var game := empty()
		var x := 9.0 if obstacle == "edge" else 4.0
		var crate := game.add_crate(x, 10)
		game.player.x = x - game.tuning.player_width
		if obstacle == "crate":
			game.add_crate(x + 1, 10)
		game.advance(.1, 1)
		check(not game.is_crate_sliding(1, false) and float(crate.x) == x,
			"A push blocked by the %s must stay silent" % obstacle)

	var returning := empty()
	var crate := returning.add_crate(3.9, 10)
	crate.target_x = 4.0
	returning.player.x = 3.9 - returning.tuning.player_width
	returning.advance(Simulation.STEP, 1)
	check(float(crate.x) > 3.9 and not returning.is_crate_sliding(1, false),
		"Touching a crate that is already returning must not count as a direct push")

	var falling := empty()
	var airborne := falling.add_crate(4, 9.8, 6)
	falling.advance(.1, -1)
	check(float(airborne.y) == 10.0 and not falling.is_crate_sliding(-1, false)
		and falling.events == [{"type": "land", "x": 4.0, "y": 10.0}],
		"A vertical fall must only produce the existing landing event")


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
	var variants := {}
	for crate in game.crates:
		variants[int(crate.id)] = int(crate.variant)
	var same_variant := func(crate: Dictionary) -> bool: return variants[int(crate.id)] == int(crate.variant)
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
	check(game.crates.all(same_variant), "The held row must retain the appearance of every retiring crate")
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
	check(game.crates.all(same_variant), "The surviving crates must keep their appearances after changing rows")
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
		"crates": 8, "broken_crates": 0, "best_combo": 2, "reason": "overflow"}, "A match result must count clear ticks and preserve the final counters and loss reason")
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
	game.resolve_equipment("boots")
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
	check(game.equipment_options() == ["boots", "helmet", "gloves", "mallet"] + NEW_EQUIPMENT,
		"The first offer must present both hands items and both independent slots")
	var frozen := [game.ticks, game.elapsed, game.player, game.player_velocity, game.cranes.duplicate(true), game._rng.state]
	game.advance(20.0, 1, true)
	check(frozen == [game.ticks, game.elapsed, game.player, game.player_velocity, game.cranes, game._rng.state],
		"An open offer must ignore elapsed wall time, movement and jumps")
	game.resolve_equipment("unknown")
	check(game.equipment_pending and game.equipment_rows == 7 and game.boots_charges == 0 and game.helmet_charges == 0,
		"An invalid item must leave the current offer open and the next threshold queued")
	game.resolve_equipment("")
	check(game.equipment_pending and not game.boots_equipped and game.equipment_rows == 2 and game.ticks == frozen[0],
		"Skipping the first offer must immediately present the next one from the same combo")
	game.resolve_equipment("boots")
	check(not game.equipment_pending and game.boots_equipped
		and game.boots_charges == Simulation.BOOTS_MAX_CHARGES and game.helmet_charges == 0,
		"Choosing boots must equip ten charges and spend the offer on the chosen slot")
	game.advance(Simulation.STEP, 0)
	check(game.ticks == frozen[0] + 1 and game.grounded and game.events.is_empty(),
		"Play must resume on a fresh tick without input or time carried through the reward")

	add_full_rows(game, 9)
	game.advance(5.0, 0)
	check(game.equipment_pending and game.equipment_rows == 6 and game.equipment_options() == ["helmet", "gloves", "mallet"] + NEW_EQUIPMENT,
		"Full boots must leave the helmet and both hands items available and preserve queued thresholds")
	game.resolve_equipment("boots")
	check(game.equipment_pending and game.equipment_rows == 6, "Choosing an unavailable full item must leave the offer open")
	game.resolve_equipment("helmet")
	check(game.equipment_pending and game.equipment_rows == 1 and game.equipment_options() == ["gloves", "mallet"] + NEW_EQUIPMENT,
		"Choosing a helmet must leave both hands items available with boots and helmet full")
	game.resolve_equipment("gloves")
	check(not game.equipment_pending and game.equipment_rows == 1 and game.equipment_options() == ["mallet"] + NEW_EQUIPMENT
		and game.helmet_charges == Simulation.HELMET_MAX_CHARGES and game.boots_charges == 10
		and game.gloves_charges == Simulation.GLOVES_MAX_CHARGES,
		"All three equipment slots must stay equipped after choosing gloves")
	add_full_rows(game, 10)
	game.advance(5.0, 0)
	check(game.equipment_pending and game.equipment_rows == 6 and game.equipment_options() == ["mallet"] + NEW_EQUIPMENT,
		"A full hands item must leave the other item available on the next reward")
	game.resolve_equipment("mallet")
	check(game.equipment_pending and game.equipment_rows == 1 and game.equipment_options() == ["gloves"] + NEW_EQUIPMENT
		and game.mallet_charges == Simulation.MALLET_MAX_CHARGES and game.gloves_charges == 0
		and game.helmet_charges == 3 and game.boots_charges == 10,
		"The mallet must replace the gloves without affecting the independent slots")
	game.resolve_equipment("gloves")
	check(not game.equipment_pending and game.equipment_rows == 1 and game.mallet_charges == 0
		and game.gloves_charges == Simulation.GLOVES_MAX_CHARGES,
		"Choosing gloves from the queued offer must replace the mallet")

	game.helmet_charges -= 1
	add_full_rows(game, 4)
	game.advance(3.0, 0)
	check(game.equipment_pending and game.equipment_options() == ["helmet", "mallet"] + NEW_EQUIPMENT,
		"A partly spent helmet must be available while the boots are full")
	game.resolve_equipment("")
	check(not game.equipment_pending and game.helmet_charges == 2 and game.boots_charges == 10,
		"Skipping the helmet must keep the two remaining charges and the boots")
	add_full_rows(game, 5)
	game.advance(3.0, 0)
	game.resolve_equipment("helmet")
	check(not game.equipment_pending and game.helmet_charges == 3 and game.boots_charges == 10,
		"A later helmet reward must restore three charges without affecting the boots")

	game.advance(Simulation.STEP, 0, true)
	game.advance(Simulation.STEP, 0, true)
	game.advance(1.0, 0)
	add_full_rows(game, 5)
	game.advance(3.0, 0)
	check(game.equipment_pending and game.equipment_rows == 0 and game.boots_charges == 9
		and game.equipment_options() == ["boots", "mallet"] + NEW_EQUIPMENT, "Partially spent boots must remain available while the helmet is full")
	game.resolve_equipment("")
	check(not game.equipment_pending and game.boots_equipped and game.boots_charges == 9,
		"Skipping a replacement must keep the equipped pair and its remaining charges")
	add_full_rows(game, 10)
	game.advance(5.0, 0)
	check(game.equipment_pending and game.equipment_rows == 5, "An earlier skip must not prevent future offers")
	game.resolve_equipment("boots")
	check(game.equipment_pending and game.equipment_options() == ["mallet"] + NEW_EQUIPMENT,
		"Refilling boots leaves the hands replacement in the second queued reward")
	game.resolve_equipment("")
	check(not game.equipment_pending and game.equipment_rows == 0 and game.boots_charges == 10,
		"A replacement must restore ten charges after both queued rewards are resolved")
	game.gloves_charges -= 1
	add_full_rows(game, 5)
	game.advance(3.0, 0)
	check(game.equipment_pending and game.equipment_options() == ["gloves", "mallet"] + NEW_EQUIPMENT,
		"Partly spent gloves must remain available while the helmet and boots are full")
	game.resolve_equipment("")
	check(not game.equipment_pending and game.gloves_charges == 5,
		"Skipping a gloves offer must keep the remaining charges")
	add_full_rows(game, 5)
	game.advance(3.0, 0)
	game.resolve_equipment("gloves")
	check(not game.equipment_pending and game.gloves_charges == 6 and game.boots_charges == 10
		and game.helmet_charges == 3, "Replacing gloves must refill only the hands slot")
	game.reset(7481)
	check(game.equipment_enabled and not game.equipment_pending and not game.boots_equipped
		and game.boots_charges == 0 and game.helmet_charges == 0 and game.gloves_charges == 0
		and game.mallet_charges == 0 and game.grabbed_crate_id == -1 and game.equipment_rows == 0,
		"Reset must retain the opt-in and clear all equipment slots and the grip")


func mallet_actions() -> void:
	for direction in [-1, 1]:
		var game := empty()
		game.equipment_enabled = true
		game.equipment_rows = Simulation.ROWS_PER_EQUIPMENT - 1
		game.mallet_charges = 1
		game.facing = direction
		var target_x := game.player.x + game.tuning.player_width + .08 if direction > 0 else game.player.x - 1.08
		var target := game.add_crate(target_x, 10)
		var above := game.add_crate(target_x, 9)
		var behind := game.add_crate(0.0 if direction > 0 else 4.0, 10)
		game.advance(0.0, 0.0, false, false, true)
		check(game.events.is_empty() and game.mallet_charges == 1, "A tap between steps must wait for simulation time")
		game.advance(Simulation.STEP, 0)
		check(game.events.size() == 1 and game.events[0].type == "mallet_swing" and game.events[0].facing == direction
			and game.crates.has(target), "A mallet must announce a facing-aware windup before changing the board")
		game.advance(Simulation.MALLET_WINDUP_TIME - Simulation.STEP, 0)
		check(game.events.is_empty() and game.crates.has(target), "The target must remain until the windup completes")
		game.advance(Simulation.STEP, 0)
		check(game.events.size() == 1 and game.events[0].type == "mallet_hit" and game.events[0].mallet_broke
			and game.events[0].crate_id == target.id and game.mallet_charges == 0 and not game.crates.has(target),
			"The last mallet charge must break exactly the crate in front, then break the tool")
		check(game.crates.has(behind) and game.crates.has(above) and float(above.y) > 9.0,
			"A struck lower crate must lose support immediately without breaking or moving another crate laterally")
		check(game.broken_crates == 1 and game.score == 0 and game.lines == 0 and game.cleared_crates == 0
			and game.equipment_rows == 4 and not game.equipment_pending,
			"Breaking a crate must be counted separately and leave the reward threshold and score alone")
		game.advance(.5, 0, false, false, true)
		check(game.broken_crates == 1 and float(above.y) == 10.0,
			"An exhausted tool must leave the upper crate to fall and settle normally")

	var miss := empty()
	miss.player.x = 0.0
	miss.facing = -1
	miss.mallet_charges = 3
	var wrong_side := miss.add_crate(miss.tuning.player_width + .02, 10)
	miss.advance(.2, 0, false, false, true)
	check(miss.events.size() == 2 and miss.events[1].type == "mallet_miss"
		and miss.crates.has(wrong_side) and miss.mallet_charges == 3,
		"An outward swing at the boundary must miss without spending a charge or reaching behind")
	miss.facing = 1
	miss.advance(Simulation.STEP, 0, false, false, true)
	miss.cancel_mallet_swing()
	miss.advance(.3, 0)
	check(miss.crates.has(wrong_side) and miss.broken_crates == 0,
		"Cancelling a swing on pause must prevent a late impact after resuming")
	miss.advance(.2, 0, false, false, true)
	var next := miss.add_crate(miss.tuning.player_width + .02, 10)
	miss.advance(.5, 0)
	check(miss.crates.has(next) and miss.mallet_charges == 2 and miss.broken_crates == 1,
		"A new crate must survive until another distinct tap")
	miss.advance(.2, 0, false, false, true)
	check(not miss.crates.has(next) and miss.mallet_charges == 1 and miss.broken_crates == 2,
		"A later tap must strike the newly adjacent crate")
	var distant := miss.add_crate(miss.tuning.player_width + Simulation.MALLET_REACH + .01, 10)
	miss.advance(.2, 0, false, false, true)
	check(miss.crates.has(distant) and miss.mallet_charges == 1,
		"The mallet must not reach a crate outside its neighboring space")
	miss.advance(0, 0, false, false, true)
	miss.reset(7481)
	check(miss.broken_crates == 0 and miss.mallet_charges == 0,
		"Restart must clear the tool, buffered action and broken-crate counter")

	for charges in [0, 1]:
		var game := empty()
		game.mallet_charges = 3
		game.helmet_charges = charges
		var x := game.player.x + game.tuning.player_width
		game.add_crate(x, 10)
		game.add_crate(x, 9)
		game.advance(Simulation.STEP + Simulation.MALLET_WINDUP_TIME, 0, false, false, true)
		game.advance(.23, 1)
		check(game.mallet_charges == 2 and game.broken_crates == 1 + charges
			and game.helmet_charges == 0 and game.state == ("playing" if charges > 0 else "over"),
			"Walking under the crate freed by the mallet must follow existing crush and helmet rules")


func equipment_jumps() -> void:
	var game := empty(4)
	game.equipment_enabled = true
	add_full_rows(game, 5)
	game.advance(3.0, 0)
	game.resolve_equipment("boots")
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
		game.advance(Simulation.STEP, 0, false, false, false, {"jump_held": true})
		check(game.events.is_empty() and game.boots_charges == charges - 1 and game.player_velocity.y > jump_velocity,
			"Holding jump after an airborne press must not consume another charge")
		game.advance(1.0, 0)
		check(game.grounded and game.boots_equipped == (charges > 1),
			"Landing must end the flight and remove the boots when the last charge is spent")
	add_full_rows(game, 5)
	game.advance(3.0, 0)
	check(game.equipment_pending, "A new offer must be available after the boots are exhausted")
	game.resolve_equipment("boots")

	for row in range(7, game.tuning.rows):
		game.add_crate(2, row)
	var ledge := Vector2(2.94, 7 - game.tuning.player_height)
	game.player = ledge
	game.advance(Simulation.STEP, 0)
	game.advance(Simulation.STEP, 1)
	game.advance(.11, 1)
	game.advance(Simulation.STEP, 0, true)
	check(not game.grounded and game.player_velocity.y < 0.0 and game.events == [{"type": "air_jump"}]
		and game.boots_charges == 9, "Walking off a ledge qualifies for paid rocket thrust once coyote time expires")
	var coyote := empty(4)
	for row in range(7, coyote.tuning.rows):
		coyote.add_crate(2, row)
	coyote.boots_equipped = true
	coyote.boots_charges = 10
	coyote.player = ledge
	coyote.advance(Simulation.STEP, 0)
	coyote.advance(Simulation.STEP, 1)
	coyote.advance(Simulation.STEP, 0, true)
	check(coyote.events == [{"type": "jump"}] and coyote.boots_charges == 10,
		"Coyote takeoff must still use an ordinary jump")
	coyote.advance(Simulation.STEP, 0, true)
	check(coyote.events == [{"type": "air_jump"}] and coyote.boots_charges == 9,
		"Coyote takeoff must qualify for rocket thrust")
	coyote.advance(Simulation.STEP, 0, true)
	check(coyote.events == [{"type": "air_jump"}] and coyote.boots_charges == 8,
		"A fresh press triggers another rocket thrust within the same flight")


func bonus_equipment() -> void:
	var gear := empty()
	gear.equipment_enabled = true
	for item in ["gloves", "helmet", "boots", "strong_arms", "lamp_helmet", "spring_boots"]:
		gear.equipment_pending = true
		gear.resolve_equipment(item)
	check(gear.strong_arms_charges == Simulation.STRONG_ARMS_MAX_CHARGES and gear.gloves_charges == 0
		and gear.lamp_helmet_equipped and gear.helmet_charges == 0 and gear.boots_charges == 0
		and not gear.boots_equipped and gear.spring_boots_charges == Simulation.SPRING_BOOTS_MAX_CHARGES,
		"New gear replaces in its own slot and coexists across slots")
	gear.equipment_pending = true
	gear.resolve_equipment("speed_boots")
	check(gear.spring_boots_charges == 0 and gear.speed_boots_charges == Simulation.SPEED_BOOTS_MAX_CHARGES
		and gear.lamp_helmet_equipped and gear.strong_arms_charges > 0,
		"Exchanging footwear must preserve the independent slots")
	gear.reset(7481)
	check(gear.strong_arms_charges == 0 and gear.speed_boots_charges == 0
		and not gear.lamp_helmet_equipped and gear.lamp_helmet_charges == 0 and gear.spring_boots_charges == 0,
		"A new game clears every new item")

	for direction: int in [-1, 1]:
		var pair := empty()
		pair.strong_arms_charges = 1
		var near := pair.add_crate(4, 10)
		var far := pair.add_crate(4 + direction, 10)
		var upper := pair.add_crate(4, 9)
		pair.player.x = 4 - pair.tuning.player_width if direction > 0 else 5
		var completed := false
		for tick in range(70):
			pair.advance(Simulation.STEP, direction)
			check(crates_separate(pair), "A linked push must preserve collision in either direction")
			if pair.strong_arms_charges == 0:
				completed = pair.events.any(func(event: Dictionary) -> bool: return event.type == "strong_push")
				break
		check(completed and near.x == 4 + direction and far.x == 4 + 2 * direction,
			"The last charge completes both cells in the same pair action")
		pair.player.x = 0
		pair.advance(.7, 0)
		check(upper.x == 4 and upper.y == 10, "An unsupported upper crate must fall without being dragged sideways")
	var blocked := empty()
	blocked.strong_arms_charges = 1
	blocked.player.x = 7 - blocked.tuning.player_width
	var first := blocked.add_crate(7, 10)
	blocked.add_crate(8, 10)
	blocked.add_crate(9, 10)
	blocked.advance(.65, 1)
	check(first.x == 7 and blocked.strong_arms_charges == 1 and crates_separate(blocked),
		"A blocked pair and a third adjacent crate must not consume strength")
	var interrupted := empty()
	interrupted.strong_arms_charges = 1
	interrupted.player.x = 4 - interrupted.tuning.player_width
	interrupted.add_crate(4, 10)
	var leading := interrupted.add_crate(5, 10)
	interrupted.advance(4 * Simulation.STEP, 1)
	var obstacle := interrupted.add_crate(6.3, 9.2, 4.0)
	interrupted.advance(.4, 1)
	check(leading.x < 6 and leading.x + 1 <= obstacle.x + .001 and interrupted.strong_arms_charges == 1
		and crates_separate(interrupted), "Both crates must stop safely on a new obstruction without spending a charge")

	var runner := empty()
	runner.speed_boots_charges = 1
	var start := runner.player.x
	runner.advance(.4, 0)
	check(runner.speed_boots_charges == 1 and runner.player.x == start, "Idle speed boots must not drain")
	for tick in range(120):
		runner.advance(Simulation.STEP, 1)
		if runner.speed_boots_charges == 0:
			break
	check(runner.speed_boots_charges == 0 and absf(runner.player.x - start - 1) < .055,
		"Speed boosts finish the last full cell before removing the equipment")
	var normal_at := runner.player.x
	runner.advance(.25, 1)
	check(absf(runner.player.x - normal_at - .25 * runner.tuning.player_speed) < .002,
		"After the last charge, the same input continues at ordinary speed")
	runner.player.x = runner.tuning.columns - runner.tuning.player_width
	runner.speed_boots_charges = 2
	runner.advance(.5, 1)
	check(runner.speed_boots_charges == 2, "Walking against the field edge must not drain speed boots")

	var lamp := empty()
	lamp.lamp_helmet_equipped = true
	lamp.lamp_helmet_charges = 1
	lamp.cranes_enabled = true
	lamp.cranes[0].release_column = 3
	lamp.cranes[0].loaded = false
	lamp.cranes[1].loaded = false
	lamp.advance(Simulation.STEP, 0, false, false, false, {"lamp_pressed": true})
	check(lamp.lamp_helmet_charges == 1 and lamp.lamp_active_time == 0.0, "An empty lamp call costs nothing")
	lamp.cranes[0].loaded = true
	lamp.advance(Simulation.STEP, 0, false, false, false, {"lamp_pressed": true})
	check(lamp.lamp_helmet_charges == 0 and lamp.lamp_active_time > 0.0 and lamp.lamp_columns() == [3],
		"The last lamp charge reveals a loaded crane only")
	lamp.cranes_enabled = false
	for hit in range(2):
		lamp.add_crate(floorf(lamp.player.x), lamp.player.y - 1.10, 6.0)
		lamp.advance(.1, 0)
		check(not lamp.lamp_helmet_equipped and lamp.broken_crates == 1
			and lamp.state == ("playing" if hit == 0 else "over") and lamp.score == 0,
			"An exhausted lamp helmet protects exactly once and preserves the score")

	var spring := empty()
	spring.spring_boots_charges = Simulation.SPRING_BOOTS_MAX_CHARGES
	spring.advance(Simulation.STEP, 0, true, false, false, {"jump_held": false})
	check(not spring.grounded and spring.spring_boots_charges == Simulation.SPRING_BOOTS_MAX_CHARGES,
		"A complete short tap launches a normal jump without using spring resources")
	spring.advance(2.0, 0)
	spring.advance(.38, 0, true, false, false, {"jump_held": true})
	check(spring.grounded and spring.spring_charge_stages == 2,
		"Holding the control charges in steps without taking off early")
	spring.advance(Simulation.STEP, 0)
	check(not spring.grounded and spring.spring_boots_charges == Simulation.SPRING_BOOTS_MAX_CHARGES - 2
		and spring.events.any(func(event: Dictionary) -> bool: return event.type == "spring_jump" and not event.automatic),
		"Release spends exactly the displayed stages")
	spring.advance(2.0, 0)
	spring.spring_boots_charges = 1
	spring.advance(.25, 0, true, false, false, {"jump_held": true})
	check(not spring.grounded and spring.spring_boots_charges == 0
		and spring.events.any(func(event: Dictionary) -> bool: return event.type == "spring_jump" and event.automatic),
		"The last stage auto-launches when the available resource is exhausted")
	spring.advance(2.0, 0, false, false, false, {"jump_held": true})
	check(spring.grounded and spring.events.is_empty(), "A continued hold must not start a second charge")
	spring.spring_boots_charges = 4
	spring.advance(.24, 0, true, false, false, {"jump_held": true})
	spring.cancel_bonus_input()
	spring.advance(.5, 0)
	check(spring.grounded and spring.spring_boots_charges == 4 and spring.spring_charge_stages == 0,
		"Cancelling a charge for pause must discard the pending jump")
	var ceiling := empty()
	ceiling.spring_boots_charges = 6
	for row in range(1, ceiling.tuning.rows):
		ceiling.add_crate(2, row)
	ceiling.player.y = 1.0 - ceiling.tuning.player_height
	check(ceiling.spring_charge_limit() == 1, "Spring charge cap must be calculated from the current elevated position")
	ceiling.advance(.22, 0, true, false, false, {"jump_held": true})
	check(ceiling.spring_boots_charges == 5 and ceiling.events.any(func(event: Dictionary) -> bool:
		return event.type == "spring_jump" and event.automatic and event.stages == 1),
		"A high perch reaches the height cap and auto-launches before later stages")
	for tick in range(60):
		ceiling.advance(Simulation.STEP, 0, false, false, false, {"jump_held": true})
		check(ceiling.player.y >= Simulation.PLAYER_TOP - .001, "Boosted vertical motion must respect the top of the field")


func gloved(facing: int = 1, crate_x: float = 4.0, gap: float = 0.14) -> StackSimulation:
	var game := empty()
	game.equipment_enabled = true
	game.gloves_charges = Simulation.GLOVES_MAX_CHARGES
	game.add_crate(crate_x, game.tuning.rows - 1)
	game.facing = facing
	game.player.x = crate_x - game.tuning.player_width - gap if facing == 1 else crate_x + 1 + gap
	return game


func gloves_pull_and_break() -> void:
	for direction in [1, -1]:
		var start_x := 7.0 if direction == 1 else 2.0
		var game := gloved(direction, start_x)
		var crate := game.crates[0]
		var other := game.add_crate(start_x + direction, 10)
		var cell_ticks := ceili(1.0 / (game.tuning.push_speed * Simulation.STEP))
		for remaining in range(5, -1, -1):
			var previous := float(crate.x)
			var hero_previous := game.player.x
			game.advance(Simulation.STEP, 0, false, true)
			check((float(crate.x) - previous) * direction < 0.0 and absf(float(crate.x) - previous) < 1.0
				and is_equal_approx(game.player.x - hero_previous, float(crate.x) - previous)
				and game.is_pulling() and game.grabbed_crate_id == int(crate.id),
				"Holding the glove button alone must pull the same adjacent crate while facing it")
			game.advance((cell_ticks - 2) * Simulation.STEP, 0, false, true)
			check(game.gloves_charges == remaining + 1 and game.events.is_empty(), "Partial distance must spend no charge")
			game.advance(Simulation.STEP, 0, false, true)
			check(game.gloves_charges == remaining and float(crate.x) == previous - direction
				and is_equal_approx(game.player.x, hero_previous - direction) and game.facing == direction
				and not game.is_pulling(),
				"A started pull must finish one cell at unchanged spacing, including the last charge")
			check(game.events == [{"type": "gloves_pull", "crate_id": int(crate.id), "x": float(crate.x), "y": 10.0,
				"player_x": game.player.x, "player_y": game.player.y, "facing": direction,
				"gloves_broke": remaining == 0, "charges": remaining, "tick": game.ticks}],
				"Each completed cell must emit one event with the remaining charges and tear only at zero")
			check(game.grabbed_crate_id == (int(crate.id) if remaining > 0 else -1)
				and float(other.x) == start_x + direction and crates_separate(game),
				"A grip must stay on the same crate while usable and release when the gloves tear")
			check(game.is_crate_sliding(0, true) == (remaining > 0),
				"Held pulling must sound at each cell boundary until the gloves tear")
		game.advance(Simulation.STEP, 0, false, true)
		check(game.grabbed_crate_id == -1 and game.events.is_empty(), "Torn gloves must not grab again")

	var reference := gloved(1, 7)
	reference.advance(1.0, 0, false, true)
	for frame_rate in [30, 144]:
		var game := gloved(1, 7)
		var pulls: Array[Dictionary] = []
		for frame in range(frame_rate):
			game.advance(1.0 / frame_rate, 0, false, true)
			pulls.append_array(game.events)
		check(game.ticks == reference.ticks and game.player == reference.player and game.crates == reference.crates
			and game.gloves_charges == 3 and game.gloves_charges == reference.gloves_charges and pulls == reference.events,
			"One continuous hold must finish the same three cells across render frame rates")


func gloves_blockers() -> void:
	var distant := gloved(1, 4, .3)
	distant.add_crate(2, 10)
	distant.advance(Simulation.STEP, 0, false, true)
	check(distant.grabbed_crate_id == -1, "A grab must not select a distant or rear crate")
	var falling := gloved()
	falling.crates[0].y = 9.96
	falling.crates[0].vy = .2
	falling.advance(Simulation.STEP, 0, false, true)
	check(falling.grabbed_crate_id == -1, "A grab must not attach to a falling crate")
	var airborne := gloved()
	airborne.advance(Simulation.STEP, 0, true)
	airborne.advance(Simulation.STEP, 0, false, true)
	check(airborne.grabbed_crate_id == -1, "An airborne hero must not grab a nearby crate")
	for obstacle in ["edge", "hero", "crate"]:
		var game := gloved(1, 1 if obstacle == "edge" else 4)
		if obstacle == "hero":
			game.add_crate(2, 10)
		elif obstacle == "crate":
			game.add_crate(3, 9.02)
		var crate := game.crates[0]
		var initial := game.player
		var initial_x := float(crate.x)
		game.advance(Simulation.STEP, 0, false, true)
		check(game.grabbed_crate_id == int(crate.id) and game.player == initial and float(crate.x) == initial_x
			and game.gloves_charges == 6 and game.events.is_empty() and crates_separate(game) and not game.is_pulling()
			and not game.is_crate_sliding(0, true),
			"A %s obstacle must block the whole pair without a charge or loss of grip" % obstacle)
		game.advance(0, 0)
		check(game.grabbed_crate_id == -1, "Releasing the button must clear a blocked grip immediately")

	var dynamic := gloved()
	var crate := dynamic.crates[0]
	var initial := dynamic.player
	dynamic.advance(8 * Simulation.STEP, 0, false, true)
	dynamic.add_crate(2, 9.08, 6)
	dynamic.advance(2 * Simulation.STEP, 0, false, true)
	check(dynamic.is_pulling() and dynamic.grabbed_crate_id == -1 and not dynamic.is_crate_sliding(0, true),
		"A dynamic blocker must silence pulling as soon as rollback starts under held input")
	dynamic.advance(.18, 0)
	check(dynamic.player == initial and float(crate.x) == 4.0 and dynamic.grabbed_crate_id == -1
		and dynamic.gloves_charges == 6 and crates_separate(dynamic) and dynamic.state == "playing",
		"A falling obstacle that enters the unfinished route must safely reverse the pair to its start")


func gloves_detachment() -> void:
	var released := gloved()
	var target := released.crates[0]
	released.advance(Simulation.STEP * .25, 0, false, true)
	check(released.grabbed_crate_id == -1 and not released.is_pulling(), "Sub-tick hold must not start a partial cell")
	released.advance(Simulation.STEP * .75, 0)
	check(released.grabbed_crate_id == -1 and not released.is_pulling(), "A hold released before its first tick must leave no queued grip")
	released.advance(Simulation.STEP, 0, false, true)
	var paused_player := released.player
	var paused_x := float(target.x)
	check(released.is_crate_sliding(0, true) and not released.is_crate_sliding(0, false),
		"Held pull motion must sound only while input is active, including between fixed steps")
	released.release_pull_input()
	check(released.grabbed_crate_id == -1 and released.gloves_charges == 6 and released.is_pulling()
		and released.player == paused_player and float(target.x) == paused_x and not released.is_crate_sliding(0, true),
		"Releasing input for a pause must detach immediately without advancing or charging the cell")
	released.advance(Simulation.STEP, 0, false, true)
	check(released.grabbed_crate_id == int(target.id) and released.is_pulling(),
		"Holding again during safe completion must reattach to the same crate")
	released.advance(Simulation.STEP, 0)
	check(released.is_pulling() and not released.is_crate_sliding(0, false),
		"A safe finishing step can continue moving silently after release")
	released.advance(.4, 0)
	check(float(target.x) == 3.0 and released.gloves_charges == 5 and released.grabbed_crate_id == -1
		and not released.is_pulling(),
		"A started valid cell must finish once after release, with no follow-on pull")

	var removed := gloved()
	removed.advance(4 * Simulation.STEP, 0, false, true)
	removed.crates.clear()
	var before := removed.player.x
	removed.advance(Simulation.STEP, -1)
	check(removed.grabbed_crate_id == -1 and removed.gloves_charges == 6 and not removed.is_pulling(),
		"Losing the attached ID must end the unfinished step without a charge")
	removed.advance(Simulation.STEP, -1)
	check(removed.player.x < before, "After losing the target and releasing the button, normal walking must resume")
	var restarted := gloved()
	restarted.advance(Simulation.STEP, 0, false, true)
	restarted.reset(1)
	check(restarted.grabbed_crate_id == -1 and restarted.gloves_charges == 0 and not restarted.is_pulling(),
		"Reset during a pull must clear grip, transaction and charges")

	var ledge := gloved()
	var ledge_crate := ledge.crates[0]
	ledge_crate.y = 9.0
	ledge.player.y -= 1.0
	ledge.add_crate(3, 10)
	ledge.add_crate(4, 10)
	ledge.advance(.29, 0, false, true)
	ledge.advance(.4, 0)
	check(ledge.grabbed_crate_id == -1 and ledge.gloves_charges == 6 and float(ledge_crate.x) == 4.0
		and is_equal_approx(ledge.player.y + ledge.tuning.player_height, 11.0) and crates_separate(ledge),
		"Walking the pair off the hero's support must detach and let ordinary gravity take over")

	var stacked := gloved()
	var upper := stacked.add_crate(4, 9)
	stacked.advance(Simulation.STEP, 0, false, true)
	stacked.advance(.55, 0)
	check(float(upper.y) > 9.0 and is_equal_approx(float(upper.x), 4.0) and crates_separate(stacked),
		"Moving a supporting crate must leave the crate above to fall at its own column")
	var helmet := gloved()
	helmet.helmet_charges = 1
	helmet.advance(14 * Simulation.STEP, 0, false, true)
	helmet.add_crate(2, 9.10, 6)
	helmet.advance(.35, 0)
	check(helmet.helmet_charges == 0 and helmet.gloves_charges == 5 and helmet.state == "playing"
		and helmet.events.size() == 2 and helmet.events[0].type == "helmet_hit"
		and helmet.events[1].type == "gloves_pull",
		"Moving with a crate must preserve the helmet response to a falling head strike")
	var crushed := gloved()
	crushed.advance(14 * Simulation.STEP, 0, false, true)
	crushed.add_crate(2, 9.10, 6)
	crushed.advance(Simulation.STEP, 0, false, true)
	check(crushed.state == "over" and crushed.loss_reason == "crushed" and not crushed.is_pulling()
		and crushed.grabbed_crate_id == -1 and crushed.gloves_charges == 6,
		"A fatal hit while holding must clear the unfinished pull without spending a charge")

	var cleared := empty(4, 6)
	cleared.gloves_charges = 6
	cleared.player = Vector2(1.3, 5 - cleared.tuning.player_height)
	var upper_crate := cleared.add_crate(2, 4)
	cleared.add_crate(1, 5)
	cleared.add_crate(2, 5)
	cleared.advance(Simulation.STEP, 0, false, true)
	check(cleared.grabbed_crate_id == int(upper_crate.id), "A crate can be grabbed while standing on the same row")
	cleared.add_crate(0, 5)
	cleared.add_crate(3, 5)
	cleared.advance(Simulation.STEP, 0, false, true)
	check(cleared.state == "clearing" and cleared.grabbed_crate_id == -1 and cleared.gloves_charges == 6,
		"A row clear must release an unfinished grip without spending a charge")
	cleared.advance(.8, 0)
	check(cleared.state == "playing" and float(upper_crate.x) == 2.0 and cleared.gloves_charges == 6,
		"Collapse must settle the interrupted crate without restoring the old grip")


func gloves_input_priority() -> void:
	var game := gloved()
	game.boots_equipped = true
	game.boots_charges = Simulation.BOOTS_MAX_CHARGES
	var initial := game.player
	game.advance(Simulation.STEP * .25, 0, true)
	game.advance(Simulation.STEP * .75, 1, true, true)
	check(game.player.x < initial.x and game.player.y == initial.y and game.facing == 1 and game.events.is_empty(),
		"Held gloves must ignore movement and jumps, including an already buffered jump")
	game.advance(Simulation.STEP, -1, true)
	check(game.facing == 1 and game.player.y == initial.y and game.events.is_empty(),
		"The unfinished cell must keep control and discard jump input even after release")
	game.advance(.4, 0)
	check(game.player.y == initial.y and game.grounded and game.gloves_charges == 5
		and game.boots_charges == Simulation.BOOTS_MAX_CHARGES,
		"A discarded jump must not fire or consume the boots when the cell finishes")
	game.advance(Simulation.STEP, 0, true)
	check(game.events == [{"type": "jump"}], "A fresh jump input after completion must take effect")
	game.advance(Simulation.STEP, 0, true, true)
	check(game.events.is_empty() and game.boots_charges == Simulation.BOOTS_MAX_CHARGES,
		"Held gloves must also discard an airborne jump input even without a grabbable crate")
	game.advance(Simulation.STEP, 0)
	check(game.events.is_empty(), "Releasing the button must not replay the discarded air jump")
	game.advance(Simulation.STEP, 0, true)
	check(game.events == [{"type": "air_jump"}] and game.boots_charges == Simulation.BOOTS_MAX_CHARGES - 1,
		"A new airborne jump input must use the equipped boots as usual")

	var bare := gloved()
	bare.gloves_charges = 0
	initial = bare.player
	bare.advance(Simulation.STEP, -1, true, true)
	check(bare.player.x < initial.x and bare.facing == -1 and bare.events == [{"type": "jump"}],
		"The glove button without charges must leave ordinary movement and jumping available")


func helmet_falling_hits() -> void:
	var game := empty()
	game.player.x = 4.2
	game.helmet_charges = Simulation.HELMET_MAX_CHARGES
	var contact_y := game.player.y - 1.0
	for remaining in range(Simulation.HELMET_MAX_CHARGES - 1, -1, -1):
		var crate := game.add_crate(4.0, contact_y - .025, 6.0)
		game.advance(Simulation.STEP, 0)
		check(game.state == "playing" and game.grounded and game.impact_crate_id == -1
			and game.helmet_charges == remaining and game.crates.is_empty(),
			"Every charge, including the last, must protect and remove exactly one falling crate")
		check(game.events == [{"type": "helmet_hit", "crate_id": int(crate.id), "x": 4.0,
			"y": contact_y, "player_x": game.player.x, "player_y": game.player.y, "direction": "fall",
			"helmet_broke": remaining == 0, "charges": remaining, "tick": game.ticks}],
			"A head strike must report the collision position and the remaining charges exactly once")
	check(game.lines == 0 and game.score == 0 and game.cleared_crates == 0 and game.best_combo == 0,
		"Individual crate destruction must not count towards clear statistics")
	var fatal := game.add_crate(4.0, contact_y - .025, 6.0)
	game.advance(Simulation.STEP, 0)
	check(game.state == "over" and game.impact_crate_id == int(fatal.id) and game.crates.has(fatal)
		and game.events == [{"type": "over", "reason": "crushed", "score": 0}],
		"The next falling strike after helmet breakage must follow the normal crush path")

	var side := empty()
	side.helmet_charges = 3
	side.player.x = 4 - side.tuning.player_width
	var pushed := side.add_crate(4, 9.8, .2)
	advance(side, .04, 1)
	check(float(pushed.x) > 4.01 and side.helmet_charges == 3 and side.state == "playing",
		"Pushing the side of a falling crate must keep ordinary push behavior and spend no charge")
	var landing := empty()
	landing.helmet_charges = 3
	landing.player = Vector2(4.2, 8.9)
	var support := landing.add_crate(4, 10)
	advance(landing, .3)
	check(landing.grounded and is_equal_approx(landing.player.y + landing.tuning.player_height, float(support.y))
		and landing.helmet_charges == 3 and landing.crates.has(support),
		"Landing on top of a crate must keep it as ordinary support")
	var clearing_game := empty(4, 6)
	clearing_game.helmet_charges = 3
	add_full_rows(clearing_game, 2)
	clearing_game.advance(2.0, 0)
	check(clearing_game.helmet_charges == 3 and clearing_game.lines == 2 and clearing_game.score == 200
		and clearing_game.cleared_crates == 8 and clearing_game.best_combo == 2,
		"Clear and collapse must preserve the helmet and count only their own line crates")


func helmet_underside_hits() -> void:
	for input_event in ["jump", "air_jump"]:
		for charges in [0, 1]:
			var game := empty()
			game.equipment_enabled = true
			game.helmet_charges = charges
			game.boots_equipped = true
			game.boots_charges = Simulation.BOOTS_MAX_CHARGES
			if input_event == "air_jump":
				game.advance(Simulation.STEP, 0, true)
			var start_y := game.player.y
			var crate := game.add_crate(game.player.x, start_y - 1.03)
			var contact_y := float(crate.y) + 1.0
			game.advance(Simulation.STEP, 0, true)
			var expected: Array[Dictionary] = [{"type": input_event}]
			if charges == 1:
				expected.append({"type": "helmet_hit", "crate_id": int(crate.id), "x": float(crate.x),
					"y": contact_y - 1.0, "player_x": game.player.x, "player_y": contact_y, "direction": "jump",
					"helmet_broke": true, "charges": 0, "tick": game.ticks})
				var jump_velocity := -game.tuning.jump_speed + game.tuning.gravity * Simulation.STEP
				check(game.crates.is_empty() and game.helmet_charges == 0 and game.player.y < contact_y
					and is_equal_approx(game.player.y, start_y + jump_velocity * Simulation.STEP)
					and is_equal_approx(game.player_velocity.y, jump_velocity),
					"A rising helmet hit must break the crate and continue at full jump velocity")
			else:
				check(game.crates.has(crate) and game.player_velocity.y == 0.0 and is_equal_approx(game.player.y, contact_y),
					"Without a helmet a rising collision must stop at the underside")
			check(game.events == expected and game.boots_equipped and not game.grounded
				and game.boots_charges == (9 if input_event == "air_jump" else 10),
				"Ordinary and rocket jump collisions must retain their independent inputs and charge costs")

	# An accelerated test jump crosses two separated undersides in one tick.
	for charges in [1, 2]:
		var game := empty()
		game.helmet_charges = charges
		game.tuning.jump_speed = 180.2
		var farther := game.add_crate(2, 8.0897)
		var nearer := game.add_crate(2, 9.09)
		var farther_underside := float(farther.y) + 1.0
		var farther_start_y := float(farther.y)
		game.advance(Simulation.STEP, 0, true)
		check(game.events.size() == charges + 1 and game.events[1].crate_id == nearer.id
			and game.helmet_charges == 0 and not game.crates.has(nearer),
			"The nearer underside must be hit before an earlier-stored farther crate")
		if charges == 1:
			check(game.crates == [farther] and is_equal_approx(float(farther.y), farther_start_y + game.tuning.crate_gravity * Simulation.STEP * Simulation.STEP)
				and game.player_velocity.y == 0.0 and is_equal_approx(game.player.y, farther_underside),
				"The unbroken upper crate must still block the jump and fall once its support is gone")
		else:
			check(game.crates.is_empty() and game.events[2].crate_id == farther.id
				and game.player.y < farther_underside and game.player_velocity.y < 0.0,
				"Both distinct swept undersides must consume charges in contact order")
	var tied := empty()
	tied.player.x = 1.72
	tied.helmet_charges = 1
	var earlier := tied.add_crate(1, 9.09)
	var later := tied.add_crate(2, 9.09)
	tied.crates.reverse()
	tied.advance(Simulation.STEP, 0, true)
	check(tied.crates == [later] and tied.events.size() == 2 and tied.events[1].crate_id == earlier.id,
		"Equal upward contact heights must use crate ID rather than storage order")


func simultaneous_fall(charges: int) -> StackSimulation:
	var game := empty()
	game.helmet_charges = charges
	game.player.x = 1.72
	var falling_y := game.player.y - 1.025
	game.add_crate(1, falling_y, 6)
	game.add_crate(2, falling_y, 6)
	game.add_crate(1, falling_y - 1.005, 6)
	return game


func helmet_multiple_hits() -> void:
	for charges in [1, 2]:
		var game := simultaneous_fall(charges)
		var first := game.crates[0]
		var second := game.crates[1]
		var upper := game.crates[2]
		var upper_start_y := float(upper.y)
		game.advance(Simulation.STEP, 0)
		check(game.events.size() == 2 and game.events[0].crate_id == first.id
			and game.events[0].charges == charges - 1 and game.events[0].tick == 1
			and not game.crates.has(first) and game.helmet_charges == 0,
			"The first contact must spend one charge and leave the next same-tick contact to resolve")
		if charges == 1:
			check(game.loss_reason == "crushed" and game.impact_crate_id == int(second.id)
				and game.crates.has(second) and game.events[1] == {"type": "over", "reason": "crushed", "score": 0},
				"The first fall can break the helmet without protecting against a second fall in the same tick")
		else:
			check(game.state == "playing" and game.events[1].type == "helmet_hit" and game.events[1].tick == 1
				and game.events[1].crate_id == second.id and game.events[1].helmet_broke and game.crates == [upper]
				and is_equal_approx(float(upper.y), upper_start_y + 6 * Simulation.STEP),
				"The second charge must remove the next crate and leave the upper crate free to fall in the same tick")

	var batched := simultaneous_fall(2)
	var stepped := simultaneous_fall(2)
	batched.advance(30 * Simulation.STEP, 0)
	var stepped_events: Array[Dictionary] = []
	for index in range(30):
		stepped.advance(Simulation.STEP, 0)
		stepped_events.append_array(stepped.events)
	check(batched.state == "over" and batched.events.size() == 3 and batched.events == stepped_events
		and batched.ticks == stepped.ticks and batched.player == stepped.player and batched.crates == stepped.crates
		and batched.helmet_charges == stepped.helmet_charges and batched.impact_crate_id == stepped.impact_crate_id,
		"Helmet strikes and the following loss must agree across different render frame sizes")


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
		"crates": 0, "broken_crates": 0, "best_combo": 0, "reason": "crushed"}, "Crush must preserve the ordinary final result and duration")
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
	full.helmet_charges = 3
	for row in range(6):
		full.add_crate(0, row)
	full.advance(1.0 / 120, 0)
	check(full.state == "over" and full.loss_reason == "overflow" and full.impact_crate_id == -1,
		"A settled tower at full field height blocks the cranes without reporting an impact")
	check(full.helmet_charges == 3, "Overflow must not use a helmet charge")
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
	var stable_appearances := true
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
			check(crate.variant == event.variant and crate.variant == previous[event.crane].variant,
				"The falling crate and drop event must carry the exact appearance held by the crane")
			check(absf(crane.x - (event.column + 0.5)) <= stride + Simulation.EPS and crane.open_time > 0.0,
				"The crane must open its jaws in the column at the handoff")
			columns.append(event.column)
			released[event.crane] = true
			passes[event.crane] += 1
		for index in range(2):
			var before: Dictionary = previous[index]
			var crane: Dictionary = game.cranes[index]
			if not before.waiting or crane.waiting:
				stable_appearances = stable_appearances and crane.variant == before.variant
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
	check(stable_appearances, "A crane appearance must remain stable until the start of another loaded pass")
	check(waits.size() >= 8 and waits.min() < waits.max() and saw_independent_entry,
		"Return times must vary and allow one crane to re-enter while the other is still waiting")


func crane_contention() -> void:
	var game := empty()
	game.cranes_enabled = true
	var stride := game.tuning.crane_speed * Simulation.STEP
	game.cranes[0].x = 0.5 - stride
	game.cranes[1].x = 0.5 + stride
	var left_variant := int(game.cranes[0].variant)
	var right_variant := int(game.cranes[1].variant)
	for crane in game.cranes:
		crane.release_column = 0
	game.advance(Simulation.STEP, 0.0)
	check(game.crates.size() == 1 and game.crates[0].x == 0 and game.cranes[0].loaded and not game.cranes[1].loaded,
		"The crane at its last column gets the only safe release for a shared target")
	check(game.cranes[0].release_column == 1, "The other crane should try the next column without stopping")
	check(game.crates[0].variant == right_variant and game.cranes[0].variant == left_variant,
		"A contested column must transfer the first load and preserve the rerouted load's appearance")
	advance(game, 1.0 / game.tuning.crane_speed)
	check(game.crates.size() == 2 and game.crates.any(func(crate: Dictionary) -> bool: return crate.x == 1),
		"The next column can take the second crate without overlapping the first")
	check(game.crates.any(func(crate: Dictionary) -> bool: return crate.x == 1 and crate.variant == left_variant),
		"The delayed release must still use the original load's appearance")


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
	check(migrated.version == 3, "The next save must upgrade the existing profile file")
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


func broken_crate_history() -> void:
	var path := "user://test-broken-crates-%d.json" % Time.get_ticks_usec()
	var old_match := {"ended_at": "2026-11-15T19:30:20", "duration_ms": 8100, "score": 200,
		"lines": 2, "crates": 20, "best_combo": 1, "reason": "crushed"}
	var old_save := JSON.stringify({"version": 2, "matches": [old_match]})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(old_save)
	file.close()
	var profile := Profile.new(path)
	check(profile.matches == [old_match] and not profile.statistics().has("total_broken_crates")
		and FileAccess.get_file_as_string(path) == old_save,
		"An old history must survive with unknown breaks and without a migration write on load")
	var fresh_match := old_match.duplicate()
	fresh_match.broken_crates = 3
	profile.add_match(fresh_match)
	var zero_match := old_match.duplicate()
	zero_match.broken_crates = 0
	profile.add_match(zero_match)
	var invalid_count := old_match.duplicate()
	invalid_count.broken_crates = -1
	profile.add_match(invalid_count)
	var restored := Profile.new(path)
	var stats := restored.statistics()
	check(restored.matches == [old_match, zero_match, fresh_match, old_match]
		and stats.total_broken_crates == 3 and stats.total_crates == 80 and stats.total_lines == 8,
		"Count measured breaks separately and preserve matches without a valid break count")
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
	for boots in [false, true]:
		for helmet in [false, true]:
			check(StackWorldView.pause_portrait(boots, helmet).get_size() == Vector2(32, 48),
				"Every equipment combination must preserve the full pause portrait canvas")
			check(art_snapshot == [art_model.player, art_model.score, art_model.crates, art_model._rng.state, art_model.ticks],
				"Equipment portraits must never mutate gameplay")
	for pose in ["idle", "walk", "jump", "push"]:
		check(app.world.HERO_TEXTURES[pose].get_size() == Vector2(32, 48), "All workshop poses must preserve the same full sprite canvas")
	check(app.world.CRATE_TEXTURE.get_size() == Vector2(480, 48)
		and app.world.CRATE_TEXTURE.resource_path == "res://art/crate_wood_variants.png",
		"The crate texture must hold ten equally sized wooden appearances")
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
