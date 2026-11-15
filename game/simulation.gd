class_name StackSimulation
extends RefCounted
## Deterministic AABB simulation. One cell is one unit; drawing never changes it.
const STEP := 1.0 / 120.0
const EPS := 0.0001
const CRANE_EDGE_MARGIN := 1.5
const CRATE_RELEASE_Y := -0.95
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
var _rng := RandomNumberGenerator.new()
var _next_id := 0
var _jump_buffer := 0.0
var _coyote := 0.0
var _clear_ids: Array[int] = []
var _collapse_started := false
var _player_clear_start := Vector2.ZERO


func _init(settings: StackTuning = null, seed_value: int = 1) -> void:
	tuning = settings if settings != null else StackTuning.new()
	reset(seed_value)


func reset(seed_value: int) -> void:
	_rng.seed = seed_value
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
	_jump_buffer = 0.0
	_coyote = 0.0
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


func advance(delta: float, axis: float, jump_pressed: bool = false) -> void:
	events.clear()
	if state == "over":
		return
	if jump_pressed:
		_jump_buffer = 0.12
	accumulator += maxf(delta, 0.0)
	while accumulator + EPS * 0.01 >= STEP:
		accumulator -= STEP
		_tick(clampf(axis, -1.0, 1.0))
		if state == "over":
			accumulator = 0.0
			break


func _tick(axis: float) -> void:
	ticks += 1
	if state == "clearing":
		_advance_clear()
		return
	elapsed += STEP
	_jump_buffer = maxf(0.0, _jump_buffer - STEP)
	_coyote = 0.085 if grounded else maxf(0.0, _coyote - STEP)
	_move_player(axis)
	_move_crates()
	if state == "over":
		return
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
	var width := tuning.player_width
	var height := tuning.player_height
	if not is_zero_approx(axis):
		facing = 1 if axis > 0.0 else -1
	var proposed_x := clampf(player.x + axis * tuning.player_speed * STEP,
		0.0, tuning.columns - width)
	for crate in crates:
		if not _overlap(player.y, height, float(crate.y), 1.0):
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
	if _jump_buffer > 0.0 and (grounded or _coyote > 0.0):
		player_velocity.y = -tuning.jump_speed
		grounded = false
		_coyote = 0.0
		_jump_buffer = 0.0
		events.append({"type": "jump"})
	player_velocity.y = minf(player_velocity.y + tuning.gravity * STEP, 12.0)
	var proposed_y := player.y + player_velocity.y * STEP
	grounded = false
	if player_velocity.y >= 0.0:
		var support := float(tuning.rows)
		for crate in crates:
			if _overlap(player.x, width, float(crate.x), 1.0, 0.04):
				if player.y + height <= float(crate.y) + 0.025:
					support = minf(support, float(crate.y))
		if proposed_y + height >= support:
			proposed_y = support - height
			player_velocity.y = 0.0
			grounded = true
	else:
		for crate in crates:
			if _overlap(player.x, width, float(crate.x), 1.0, 0.03):
				var underside := float(crate.y) + 1.0
				if player.y >= underside - EPS and proposed_y < underside:
					proposed_y = maxf(proposed_y, underside)
					player_velocity.y = 0.0
	player.y = maxf(-1.0, proposed_y)


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
	for crate in crates:
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
		if new_y + 1.0 >= support:
			new_y = support - 1.0
			if float(crate.vy) > 1.0:
				events.append({"type": "land", "x": float(crate.x), "y": new_y})
			crate.vy = 0.0
		if new_y + 1.0 > old_bottom + EPS and old_bottom <= player.y + 0.08:
			if new_y + 1.0 >= player.y + 0.02 and _overlap(
				float(crate.x), 1.0, player.x, tuning.player_width, 0.055):
				crate.y = new_y
				impact_crate_id = int(crate.id)
				_lose("crushed")
				return
		crate.y = new_y


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
	_clear_ids = ids
	state = "clearing"
	clear_elapsed = 0.0
	_collapse_started = false
	chain += 1
	best_combo = maxi(best_combo, chain)
	lines += 1
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
		if not _begin_clear_if_full():
			chain = 0


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
	state = "over"
	loss_reason = reason
	events.append({"type": "over", "reason": reason, "score": score})
