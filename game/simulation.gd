class_name StackSimulation
extends RefCounted
## Deterministic AABB simulation. One cell is one unit; drawing never changes it.
const STEP := 1.0 / 120.0
const EPS := 0.0001
const CRANE_EDGE_MARGIN := 1.5
const CRATE_RELEASE_Y := -0.95
const ROWS_PER_EQUIPMENT := 5
const BOOTS_MAX_CHARGES := 10
const HELMET_MAX_CHARGES := 3
const GLOVES_MAX_CHARGES := 6
const GRAB_REACH := 0.18
var tuning: StackTuning
var crates: Array[Dictionary] = []
var cranes: Array[Dictionary] = []
var cranes_enabled := true
var player := Vector2.ZERO
var player_velocity := Vector2.ZERO
var grounded := false
var facing := 1
var score := 0
var lines := 0
var cleared_crates := 0
var best_combo := 0
var elapsed := 0.0
var ticks := 0
var state := "playing"
var loss_reason := ""
var impact_crate_id := -1
var events: Array[Dictionary] = []
var chain := 0
var clear_elapsed := 0.0
var accumulator := 0.0
var equipment_enabled := false
var equipment_rows := 0
var equipment_pending := false
var boots_equipped := false
var boots_charges := 0
var helmet_charges := 0
var gloves_charges := 0
var grabbed_crate_id := -1
var _rng := RandomNumberGenerator.new()
var _next_id := 0
var _jump_buffer := 0.0
var _coyote := 0.0
var _air_jump_available := false
var _air_jump_requested := false
var _grab_requested := false
var _pull_crate := {}
var _pull_start_player_x := 0.0
var _pull_start_crate_x := 0.0
var _pull_returning := false
var _clear_ids: Array[int] = []
var _collapse_started := false
var _player_clear_start := Vector2.ZERO


func _init(settings: StackTuning = null, seed_value: int = 1) -> void:
	tuning = settings if settings != null else StackTuning.new()
	reset(seed_value)


func reset(seed_value: int) -> void:
	_rng.seed = seed_value
	cancel_grab()
	crates.clear()
	events.clear()
	_next_id = 0
	player = Vector2(tuning.columns * 0.5 - tuning.player_width * 0.5,
		tuning.rows - tuning.player_height)
	player_velocity = Vector2.ZERO
	grounded = true
	facing = 1
	score = 0
	lines = 0
	cleared_crates = 0
	best_combo = 0
	elapsed = 0.0
	ticks = 0
	state = "playing"
	loss_reason = ""
	impact_crate_id = -1
	chain = 0
	accumulator = 0.0
	equipment_rows = 0
	equipment_pending = false
	boots_equipped = false
	boots_charges = 0
	helmet_charges = 0
	gloves_charges = 0
	_jump_buffer = 0.0
	_coyote = 0.0
	_air_jump_available = false
	_air_jump_requested = false
	clear_elapsed = 0.0
	_clear_ids.clear()
	_collapse_started = false
	cranes_enabled = true
	cranes.assign([{"direction": 1}, {"direction": -1}])
	for crane in cranes:
		_enter_crane(crane)
	for column in [0, 1, 8]:
		if column < tuning.columns:
			add_crate(float(column), float(tuning.rows - 1))


func add_crate(x: float, y: float, velocity: float = 0.0) -> Dictionary:
	var crate := {"id": _next_id, "x": x, "y": y, "vy": velocity,
		"target_x": x, "color": _next_id % 3}
	_next_id += 1
	crates.append(crate)
	return crate


func time_to_crane_release(crane: Dictionary) -> float:
	if not cranes_enabled or crane.waiting or not crane.loaded or int(crane.release_column) < 0:
		return INF
	var distance := (float(crane.release_column) + 0.5 - float(crane.x)) * int(crane.direction)
	return maxf(0.0, distance) / tuning.crane_speed


func is_clearing_crate(crate_id: int) -> bool:
	return state == "clearing" and not _collapse_started and _clear_ids.has(crate_id)


func match_result(ended_at: String) -> Dictionary:
	if state != "over" or loss_reason not in ["crushed", "overflow"]:
		return {}
	return {"ended_at": ended_at, "duration_ms": roundi(ticks * STEP * 1000.0),
		"score": score, "lines": lines, "crates": cleared_crates, "best_combo": best_combo,
		"reason": loss_reason}


func advance(delta: float, axis: float, jump_pressed: bool = false, grab_pressed: bool = false) -> void:
	events.clear()
	if state == "over" or equipment_pending:
		return
	if jump_pressed:
		if state == "playing" and _air_jump_available and not grounded and boots_charges > 0:
			_air_jump_requested = true
		else:
			_jump_buffer = 0.12
	if grab_pressed and state == "playing":
		_grab_requested = not _grab_requested
	accumulator += maxf(delta, 0.0)
	while accumulator + EPS * 0.01 >= STEP:
		accumulator -= STEP
		_tick(clampf(axis, -1.0, 1.0))
		if state == "over" or equipment_pending:
			accumulator = 0.0
			break


func equipment_options() -> Array[String]:
	var options: Array[String] = []
	if boots_charges < BOOTS_MAX_CHARGES:
		options.append("boots")
	if helmet_charges < HELMET_MAX_CHARGES:
		options.append("helmet")
	if gloves_charges < GLOVES_MAX_CHARGES:
		options.append("gloves")
	return options


func resolve_equipment(item: String) -> void:
	if not equipment_pending or (not item.is_empty() and not equipment_options().has(item)):
		return
	equipment_pending = false
	match item:
		"boots":
			boots_equipped = true
			boots_charges = BOOTS_MAX_CHARGES
		"helmet":
			helmet_charges = HELMET_MAX_CHARGES
		"gloves":
			gloves_charges = GLOVES_MAX_CHARGES
	_offer_equipment_if_due()


func _offer_equipment_if_due() -> void:
	if equipment_rows < ROWS_PER_EQUIPMENT:
		return
	if equipment_options().is_empty():
		equipment_rows %= ROWS_PER_EQUIPMENT
		return
	equipment_rows -= ROWS_PER_EQUIPMENT
	equipment_pending = true
	_jump_buffer = 0.0
	_air_jump_requested = false


func _tick(axis: float) -> void:
	ticks += 1
	if state == "clearing":
		_advance_clear()
		return
	elapsed += STEP
	_jump_buffer = maxf(0.0, _jump_buffer - STEP)
	_coyote = 0.085 if grounded else maxf(0.0, _coyote - STEP)
	var has_grip := grabbed_crate_id >= 0 or not _pull_crate.is_empty()
	if has_grip and (_jump_ready() or _air_jump_requested or _held_crate().is_empty()):
		cancel_grab()
	if _grab_requested and not _jump_ready() and not _air_jump_requested:
		_toggle_grab()
	_grab_requested = false
	_move_player(axis)
	_move_crates()
	if state == "over":
		return
	if (grabbed_crate_id >= 0 or not _pull_crate.is_empty()) and _held_crate().is_empty():
		cancel_grab()
	if _begin_clear_if_full():
		return
	for crate in crates:
		if float(crate.y) <= EPS and absf(float(crate.vy)) < EPS:
			_lose("overflow")
			return
	if cranes_enabled:
		# If both reach the same column this tick, give the last chance to
		# the crane that has no further column to try.
		var first := 1 if cranes[1].loaded and int(cranes[1].release_column) == 0 else 0
		_advance_crane(first)
		_advance_crane(1 - first)


func _overlap(a: float, aw: float, b: float, bw: float, margin: float = 0.002) -> bool:
	return a + aw > b + margin and a < b + bw - margin


func _move_player(axis: float) -> void:
	if not _move_with_gloves(axis):
		_walk_player(axis)
	var height := tuning.player_height
	if _jump_ready():
		player_velocity.y = -tuning.jump_speed
		grounded = false
		_coyote = 0.0
		_jump_buffer = 0.0
		_air_jump_available = equipment_enabled
		events.append({"type": "jump"})
	elif _air_jump_requested:
		player_velocity.y = -tuning.jump_speed
		boots_charges -= 1
		_air_jump_available = false
		events.append({"type": "air_jump"})
	_air_jump_requested = false
	player_velocity.y = minf(player_velocity.y + tuning.gravity * STEP, 12.0)
	var proposed_y := player.y + player_velocity.y * STEP
	grounded = false
	if player_velocity.y >= 0.0:
		var support := _player_support()
		if proposed_y + height >= support:
			proposed_y = support - height
			player_velocity.y = 0.0
			grounded = true
			_land_player()
	else:
		proposed_y = _move_player_up(proposed_y)
	player.y = maxf(-1.0, proposed_y)


func _jump_ready() -> bool:
	return _jump_buffer > 0.0 and (grounded or _coyote > 0.0)


func _walk_player(axis: float) -> void:
	var width := tuning.player_width
	if not is_zero_approx(axis):
		facing = 1 if axis > 0.0 else -1
	var proposed_x := clampf(player.x + axis * tuning.player_speed * STEP,
		0.0, tuning.columns - width)
	for crate in crates:
		if not _overlap(player.y, tuning.player_height, float(crate.y), 1.0):
			continue
		if not _overlap(proposed_x, width, float(crate.x), 1.0):
			continue
		if axis > 0.0 and player.x + width <= float(crate.x) + 0.04:
			_try_push(crate, 1)
			proposed_x = minf(proposed_x, float(crate.x) - width)
		elif axis < 0.0 and player.x >= float(crate.x) + 0.96:
			_try_push(crate, -1)
			proposed_x = maxf(proposed_x, float(crate.x) + 1.0)
	player.x = clampf(proposed_x, 0.0, tuning.columns - width)


func _grab_gap(crate: Dictionary) -> float:
	if facing > 0:
		return float(crate.x) - (player.x + tuning.player_width)
	return player.x - (float(crate.x) + 1.0)


func _can_hold(crate: Dictionary) -> bool:
	var gap := _grab_gap(crate)
	return (grounded and gap >= -0.002 and gap <= GRAB_REACH + EPS
		and absf(player.y + tuning.player_height - (float(crate.y) + 1.0)) <= 0.025
		and absf(float(crate.vy)) <= EPS and absf(float(crate.target_x) - float(crate.x)) <= EPS)


func _held_crate() -> Dictionary:
	var id := grabbed_crate_id if _pull_crate.is_empty() else int(_pull_crate.id)
	for crate in crates:
		if int(crate.id) == id and _can_hold(crate):
			return crate
	return {}


func _toggle_grab() -> void:
	if grabbed_crate_id >= 0:
		grabbed_crate_id = -1
		return
	if gloves_charges <= 0 or not grounded or not _pull_crate.is_empty():
		return
	var nearest := INF
	for crate in crates:
		var x := float(crate.x)
		if absf(x - roundf(x)) > EPS or not _can_hold(crate):
			continue
		var gap := _grab_gap(crate)
		if gap < nearest:
			grabbed_crate_id = int(crate.id)
			nearest = gap


func clear_grab_input() -> void:
	_grab_requested = false


func cancel_grab() -> void:
	grabbed_crate_id = -1
	clear_grab_input()
	if not _pull_crate.is_empty():
		# On detachment the crate can settle back using ordinary collision and gravity.
		_pull_crate.target_x = _pull_start_crate_x
		_pull_crate = {}


func _pull_path_clear(crate: Dictionary, player_target: float, crate_target: float) -> bool:
	if (player_target < -EPS or player_target + tuning.player_width > tuning.columns + EPS
			or crate_target < 0.0 or crate_target > tuning.columns - 1.0):
		return false
	var player_edge := minf(player.x, player_target)
	var player_span := tuning.player_width + absf(player_target - player.x)
	var crate_edge := minf(float(crate.x), crate_target)
	var crate_span := 1.0 + absf(crate_target - float(crate.x))
	for other in crates:
		if other.id == crate.id:
			continue
		var x := float(other.x)
		var y := float(other.y)
		if _overlap(crate_edge, crate_span, x, 1.0, 0.0) and _overlap(float(crate.y), 1.0, y, 1.0, 0.0):
			return false
		if _overlap(player_edge, player_span, x, 1.0) and _overlap(player.y, tuning.player_height, y, 1.0):
			return false
	return true


func _move_with_gloves(axis: float) -> bool:
	if _pull_crate.is_empty():
		if grabbed_crate_id < 0:
			return false
		if axis * facing >= -EPS:
			return true
		var crate := _held_crate()
		var start_x := float(crate.x)
		if not _pull_path_clear(crate, player.x - facing, start_x - facing):
			return true
		if crates.any(func(other: Dictionary) -> bool: return absf(float(other.target_x) - float(other.x)) > EPS):
			return true
		_pull_crate = crate
		_pull_start_player_x = player.x
		_pull_start_crate_x = start_x
		_pull_returning = false

	# Move the pair by the same delta. If a falling crate blocks the route,
	# back out of the unfinished cell and release the grip.
	var distance := 0.0 if _pull_returning else -float(facing)
	if not _pull_path_clear(_pull_crate, _pull_start_player_x + distance, _pull_start_crate_x + distance):
		grabbed_crate_id = -1
		_pull_returning = true
		distance = 0.0
		if not _pull_path_clear(_pull_crate, _pull_start_player_x, _pull_start_crate_x):
			cancel_grab()
			return false
	var offset := move_toward(float(_pull_crate.x) - _pull_start_crate_x, distance, tuning.push_speed * STEP)
	player.x = _pull_start_player_x + offset
	_pull_crate.x = _pull_start_crate_x + offset
	_pull_crate.target_x = _pull_crate.x
	if offset == distance:
		if not _pull_returning:
			gloves_charges -= 1
			events.append({"type": "gloves_pull", "crate_id": int(_pull_crate.id), "x": float(_pull_crate.x),
				"y": float(_pull_crate.y), "player_x": player.x, "player_y": player.y, "facing": facing,
				"gloves_broke": gloves_charges == 0, "charges": gloves_charges, "tick": ticks})
			if gloves_charges == 0:
				grabbed_crate_id = -1
		_pull_crate = {}
	return true


func _move_player_up(proposed_y: float) -> float:
	var contacts: Array[Dictionary] = []
	var sweep_y := maxf(-1.0, proposed_y) if helmet_charges > 0 else proposed_y
	for crate in crates:
		var underside := float(crate.y) + 1.0
		if player.y >= underside - EPS and sweep_y < underside and _overlap(
				player.x, tuning.player_width, float(crate.x), 1.0, 0.03):
			contacts.append(crate)
	# A larger y is closer to a rising player, regardless of storage order.
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.id) < int(b.id) if float(a.y) == float(b.y) else float(a.y) > float(b.y))
	for crate in contacts:
		var underside := float(crate.y) + 1.0
		if helmet_charges <= 0:
			player_velocity.y = 0.0
			return underside
		_break_crate_with_helmet(crate, float(crate.y), underside, "jump")
	return proposed_y


func _player_support() -> float:
	var support := float(tuning.rows)
	for crate in crates:
		if _overlap(player.x, tuning.player_width, float(crate.x), 1.0, 0.04):
			if player.y + tuning.player_height <= float(crate.y) + 0.025:
				support = minf(support, float(crate.y))
	return support


func _land_player() -> void:
	_air_jump_available = false
	if boots_charges == 0:
		boots_equipped = false


func _try_push(crate: Dictionary, direction: int) -> bool:
	if absf(float(crate.target_x) - float(crate.x)) > EPS:
		return false
	for other in crates:
		if absf(float(other.target_x) - float(other.x)) > EPS:
			return false
	var target := roundf(float(crate.x)) + direction
	if target < 0.0 or target > tuning.columns - 1:
		return false
	for other in crates:
		if other.id == crate.id:
			continue
		if _overlap(target, 1.0, float(other.x), 1.0) and _overlap(
			float(crate.y), 1.0, float(other.y), 1.0):
			return false
	crate.target_x = target
	return true


func _move_crate_horizontally(crate: Dictionary) -> void:
	# Revalidate the entire horizontal step at the CURRENT height. A push can
	# start above a neighbour, then descend into its side before it finishes.
	var old_x := float(crate.x)
	var desired := move_toward(old_x, float(crate.target_x), tuning.push_speed * STEP)
	var resolved := clampf(desired, 0.0, tuning.columns - 1.0)
	for other in crates:
		if other.id == crate.id or not _overlap(float(crate.y), 1.0, float(other.y), 1.0, 0.0):
			continue
		if desired > old_x and old_x + 1.0 <= float(other.x) + EPS:
			if resolved + 1.0 > float(other.x):
				resolved = minf(resolved, float(other.x) - 1.0)
		elif desired < old_x and old_x >= float(other.x) + 1.0 - EPS:
			if resolved < float(other.x) + 1.0:
				resolved = maxf(resolved, float(other.x) + 1.0)
	crate.x = resolved
	if resolved != desired:
		# Stop at contact instead of keeping a stale command inside the wall.
		crate.target_x = resolved


func _move_crates() -> void:
	crates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.y) > float(b.y) if not is_equal_approx(float(a.y), float(b.y)) else int(a.id) < int(b.id))
	var index := 0
	while index < crates.size():
		var crate := crates[index]
		_move_crate_horizontally(crate)
		var old_bottom := float(crate.y) + 1.0
		crate.vy = minf(float(crate.vy) + tuning.crate_gravity * STEP, tuning.crate_fall_speed)
		var new_y := float(crate.y) + float(crate.vy) * STEP
		var support := float(tuning.rows)
		for other in crates:
			if other.id == crate.id:
				continue
			# Solid crates cannot use the character's forgiving edge margin:
			# even a narrow new overlap must catch a diagonal corner this tick.
			if _overlap(float(crate.x), 1.0, float(other.x), 1.0, 0.0):
				if old_bottom <= float(other.y) + EPS:
					support = minf(support, float(other.y))
		var landed := new_y + 1.0 >= support
		if landed:
			new_y = support - 1.0
		var hits_head := (new_y + 1.0 > old_bottom + EPS and old_bottom <= player.y + 0.08
			and new_y + 1.0 >= player.y + 0.02 and _overlap(
				float(crate.x), 1.0, player.x, tuning.player_width, 0.055))
		if hits_head and helmet_charges > 0:
			var contact_y := clampf(player.y - 1.0, float(crate.y), new_y)
			_break_crate_with_helmet(crate, contact_y, player.y, "fall")
			continue
		if landed:
			if float(crate.vy) > 1.0:
				events.append({"type": "land", "x": float(crate.x), "y": new_y})
			crate.vy = 0.0
		crate.y = new_y
		if hits_head:
			impact_crate_id = int(crate.id)
			_lose("crushed")
			return
		index += 1


func _break_crate_with_helmet(crate: Dictionary, crate_y: float, player_y: float, direction: String) -> void:
	helmet_charges -= 1
	crates.erase(crate)
	events.append({"type": "helmet_hit", "crate_id": int(crate.id), "x": float(crate.x),
		"y": crate_y, "player_x": player.x, "player_y": player_y, "direction": direction,
		"helmet_broke": helmet_charges == 0, "charges": helmet_charges, "tick": ticks})


func _bottom_line() -> Array[int]:
	var columns := {}
	for crate in crates:
		if absf(float(crate.y) - (tuning.rows - 1)) < 0.005 and absf(float(crate.vy)) < EPS:
			if absf(float(crate.x) - roundf(float(crate.x))) < 0.005 and absf(float(crate.target_x) - float(crate.x)) < EPS:
				columns[int(roundf(float(crate.x)))] = int(crate.id)
	var result: Array[int] = []
	if columns.size() == tuning.columns:
		for column in range(tuning.columns):
			if not columns.has(column):
				return []
			result.append(columns[column])
	return result


func _begin_clear_if_full() -> bool:
	var ids := _bottom_line()
	if ids.is_empty():
		return false
	cancel_grab()
	_clear_ids = ids
	state = "clearing"
	clear_elapsed = 0.0
	_collapse_started = false
	chain += 1
	best_combo = maxi(best_combo, chain)
	lines += 1
	if equipment_enabled:
		equipment_rows += 1
	score += tuning.points_per_line
	events.append({"type": "line", "chain": chain, "score": score})
	return true


func _advance_clear() -> void:
	clear_elapsed += STEP
	if clear_elapsed < tuning.clear_flash_time:
		return
	if not _collapse_started:
		var crate_count := crates.size()
		crates = crates.filter(func(crate: Dictionary) -> bool: return not _clear_ids.has(int(crate.id)))
		cleared_crates += crate_count - crates.size()
		for crate in crates:
			crate.clear_y = float(crate.y)
			crate.vy = 0.0
		_player_clear_start = player
		_collapse_started = true
	var fraction := clampf((clear_elapsed - tuning.clear_flash_time) / tuning.collapse_time, 0.0, 1.0)
	var smooth_fraction := fraction * fraction * (3.0 - 2.0 * fraction)
	for crate in crates:
		crate.y = float(crate.clear_y) + smooth_fraction
	player.y = minf(_player_clear_start.y + smooth_fraction, tuning.rows - tuning.player_height)
	player_velocity.y = 0.0
	if fraction >= 1.0:
		state = "playing"
		grounded = false
		if equipment_enabled and player.y + tuning.player_height + EPS >= _player_support():
			_land_player()
		if not _begin_clear_if_full():
			chain = 0
			_offer_equipment_if_due()


func _crane_entrance(direction: int) -> float:
	return -CRANE_EDGE_MARGIN if direction > 0 else tuning.columns + CRANE_EDGE_MARGIN


func _enter_crane(crane: Dictionary) -> void:
	crane.x = _crane_entrance(int(crane.direction))
	crane.loaded = true
	crane.waiting = false
	crane.wait_remaining = 0.0
	crane.release_column = _rng.randi_range(0, tuning.columns - 1)
	crane.open_time = 0.0


func _advance_crane(index: int) -> void:
	var crane := cranes[index]
	if crane.waiting:
		crane.wait_remaining = maxf(0.0, float(crane.wait_remaining) - STEP)
		if float(crane.wait_remaining) <= EPS:
			_enter_crane(crane)
		return
	var direction := int(crane.direction)
	var exit := _crane_entrance(-direction)
	crane.x = move_toward(float(crane.x), exit, tuning.crane_speed * STEP)
	crane.open_time = maxf(0.0, float(crane.open_time) - STEP)
	if crane.loaded:
		_try_crane_release(index)
	if absf(exit - float(crane.x)) <= EPS:
		crane.x = exit
		crane.waiting = true
		crane.loaded = false
		crane.wait_remaining = _rng.randf_range(tuning.crane_wait_min, tuning.crane_wait_max)


func _try_crane_release(index: int) -> void:
	var crane := cranes[index]
	var direction := int(crane.direction)
	var column := int(crane.release_column)
	while column >= 0 and column < tuning.columns:
		if (float(crane.x) - (column + 0.5)) * direction < -EPS:
			return
		if _crane_column_is_free(column):
			var crate := add_crate(float(column), CRATE_RELEASE_Y)
			crane.loaded = false
			crane.open_time = tuning.crane_open_time
			events.append({"type": "drop", "count": 1, "crane": index,
				"column": column, "crate_id": int(crate.id), "tick": ticks})
			return
		# A blocked target moves forward with the route; a crane never turns back.
		column += direction
		crane.release_column = column if column < tuning.columns else -1


func _crane_column_is_free(column: int) -> bool:
	for crate in crates:
		if _overlap(float(column), 1.0, float(crate.x), 1.0) and float(crate.y) < 1.0:
			return false
	return true


func _lose(reason: String) -> void:
	if state == "over":
		return
	cancel_grab()
	state = "over"
	loss_reason = reason
	events.append({"type": "over", "reason": reason, "score": score})
