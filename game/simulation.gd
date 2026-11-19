class_name StackSimulation
extends RefCounted
## Deterministic AABB simulation. One cell is one unit; drawing never changes it.
const STEP := 1.0 / 120.0
const EPS := 0.0001
const CRANE_EDGE_MARGIN := 1.5
const CRATE_RELEASE_Y := -0.95
const CRATE_VARIANT_COUNT := 10
const DROP_CHANCE := 0.10
const ITEM_RADIUS := 0.23
const PICKUP_DISTANCE := 1.12
const BOOTS_MAX_CHARGES := 10
const HELMET_MAX_CHARGES := 5
const GLOVES_MAX_CHARGES := 6
const MALLET_MAX_CHARGES := 3
const STRONG_ARMS_MAX_CHARGES := 6
const SPEED_BOOTS_MAX_CHARGES := 8
const LAMP_HELMET_MAX_CHARGES := 4
const SPRING_BOOTS_MAX_CHARGES := 8
const CAPACITIES := {"boots": BOOTS_MAX_CHARGES, "helmet": HELMET_MAX_CHARGES,
	"gloves": GLOVES_MAX_CHARGES, "mallet": MALLET_MAX_CHARGES, "strong_arms": STRONG_ARMS_MAX_CHARGES,
	"speed_boots": SPEED_BOOTS_MAX_CHARGES, "lamp_helmet": LAMP_HELMET_MAX_CHARGES,
	"spring_boots": SPRING_BOOTS_MAX_CHARGES}
const SLOTS := {"feet": ["boots", "speed_boots", "spring_boots"],
	"head": ["helmet", "lamp_helmet"], "hands": ["gloves", "mallet", "strong_arms"]}
const SPEED_BOOTS_MULTIPLIER := 1.55
const LAMP_REVEAL_TIME := 1.5
const SPRING_STAGE_TIME := 0.18
const SPRING_STAGE_SPEED := 2.4
const PLAYER_TOP := -1.0
const GRAB_REACH := 0.18
const MALLET_REACH := 0.22
const MALLET_WINDUP_TIME := 0.10
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
var broken_crates := 0
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
var ground_items: Array[Dictionary] = []
var _loot_rng := RandomNumberGenerator.new()
var _next_item_id := 0
var boots_equipped := false
var boots_charges := 0
var helmet_charges := 0
var gloves_charges := 0
var mallet_charges := 0
var strong_arms_charges := 0
var speed_boots_charges := 0
var speed_boots_progress := 0.0
var speed_boost_active := false
var lamp_helmet_equipped := false
var lamp_helmet_charges := 0
var lamp_active_time := 0.0
var spring_boots_charges := 0
var spring_charge_stages := 0
var grabbed_crate_id := -1
var _rng := RandomNumberGenerator.new()
var _next_id := 0
var _next_crate_variant := 0
var _jump_buffer := 0.0
var _coyote := 0.0
var _air_jump_requested := false
var _lamp_pending := false
var _spring_charging := false
var _spring_charge_time := 0.0
var _spring_flight := false
var _strong_pair: Array[Dictionary] = []
var _strong_direction := 0
var _pull_crate := {}
var _pull_start_player_x := 0.0
var _pull_start_crate_x := 0.0
var _pull_returning := false
var _pushed_crate_id := -1
var _push_contact_id := -1
var _sliding_push_direction := 0.0
var _sliding_pull := false
var _mallet_pending := false
var _mallet_impact_tick := -1
var _mallet_facing := 1
var _clear_ids: Array[int] = []
var _collapse_started := false
var _player_clear_start := Vector2.ZERO


func _init(settings: StackTuning = null, seed_value: int = 1) -> void:
	tuning = settings if settings != null else StackTuning.new()
	reset(seed_value)


func reset(seed_value: int) -> void:
	_rng.seed = seed_value
	cancel_grab()
	cancel_mallet_swing()
	cancel_bonus_input()
	_cancel_strong_push()
	_pushed_crate_id = -1
	_push_contact_id = -1
	_sliding_push_direction = 0.0
	crates.clear()
	events.clear()
	_next_id = 0
	_next_crate_variant = posmod(seed_value, CRATE_VARIANT_COUNT)
	player = Vector2(tuning.columns * 0.5 - tuning.player_width * 0.5,
		tuning.rows - tuning.player_height)
	player_velocity = Vector2.ZERO
	grounded = true
	facing = 1
	score = 0
	lines = 0
	cleared_crates = 0
	broken_crates = 0
	best_combo = 0
	elapsed = 0.0
	ticks = 0
	state = "playing"
	loss_reason = ""
	impact_crate_id = -1
	chain = 0
	accumulator = 0.0
	ground_items.clear()
	_next_item_id = 0
	_loot_rng.seed = seed_value
	boots_equipped = false
	boots_charges = 0
	helmet_charges = 0
	gloves_charges = 0
	mallet_charges = 0
	strong_arms_charges = 0
	speed_boots_charges = 0
	speed_boots_progress = 0.0
	speed_boost_active = false
	lamp_helmet_equipped = false
	lamp_helmet_charges = 0
	lamp_active_time = 0.0
	spring_boots_charges = 0
	_spring_flight = false
	_jump_buffer = 0.0
	_coyote = 0.0
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


func _take_crate_variant() -> int:
	var variant := _next_crate_variant
	# The stride visits all ten appearances without sampling the gameplay RNG.
	_next_crate_variant = (_next_crate_variant + 7) % CRATE_VARIANT_COUNT
	return variant


func add_crate(x: float, y: float, velocity: float = 0.0, variant: int = -1) -> Dictionary:
	if variant < 0 or variant >= CRATE_VARIANT_COUNT:
		variant = _take_crate_variant()
	var crate := {"id": _next_id, "x": x, "y": y, "vy": velocity,
		"target_x": x, "color": _next_id % 3, "variant": variant}
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
		"reason": loss_reason, "broken_crates": broken_crates}


func advance(delta: float, axis: float, jump_pressed: bool = false, pull_held: bool = false,
		mallet_pressed: bool = false, bonus_input: Dictionary = {}) -> void:
	events.clear()
	if not pull_held:
		release_pull_input()
	if signf(axis) != _sliding_push_direction or _gloves_take_control(pull_held):
		_sliding_push_direction = 0.0
	if state == "over":
		return
	if mallet_pressed and mallet_charges > 0 and state == "playing":
		_mallet_pending = true
	if bool(bonus_input.get("lamp_pressed", false)) and state == "playing":
		_lamp_pending = true
	if _gloves_take_control(pull_held):
		_jump_buffer = 0.0
		_air_jump_requested = false
		_cancel_spring_charge()
	elif jump_pressed:
		_request_jump()
	var jump_held := bool(bonus_input.get("jump_held", false))
	var speed_held := bool(bonus_input.get("speed_held", false))
	accumulator += maxf(delta, 0.0)
	while accumulator + EPS * 0.01 >= STEP:
		accumulator -= STEP
		_tick(clampf(axis, -1.0, 1.0), pull_held, jump_held, speed_held)
		if state == "over":
			accumulator = 0.0
			break


func is_crate_sliding(axis: float, pull_held: bool) -> bool:
	if state != "playing":
		return false
	if _gloves_take_control(pull_held):
		return pull_held and _sliding_pull and grabbed_crate_id >= 0
	return _sliding_push_direction != 0.0 and signf(axis) == _sliding_push_direction


func add_ground_item(kind: String, x: float, bottom: float, charges: int = -1) -> Dictionary:
	var item := {"id": _next_item_id, "kind": kind, "charges": int(CAPACITIES[kind]) if charges < 0 else charges,
		"x": x, "y": bottom, "vy": 0.0, "bounced": false, "progress": 0.0, "born": -1}
	_next_item_id += 1
	ground_items.append(item)
	return item


func _destroy_crate(crate: Dictionary, row: bool = false) -> void:
	if not crates.has(crate):
		return
	crates.erase(crate)
	if row:
		cleared_crates += 1
	else:
		broken_crates += 1
	if _loot_rng.randf() < DROP_CHANCE:
		var kind: String = CAPACITIES.keys()[_loot_rng.randi_range(0, CAPACITIES.size() - 1)]
		var item := add_ground_item(kind, float(crate.x) + 0.5, float(crate.y) + 0.78)
		item.vy = -4.2
		item.born = ticks
		item.row_splinters = row
		item.origin_y = float(crate.y) + 0.5


func _move_items() -> void:
	for item in ground_items:
		var bottom := float(item.y)
		var support := float(tuning.rows)
		var ceiling := PLAYER_TOP
		for crate in crates:
			if not _overlap(float(item.x) - ITEM_RADIUS, ITEM_RADIUS * 2, float(crate.x), 1.0):
				continue
			if bottom <= float(crate.y) + EPS:
				support = minf(support, float(crate.y))
			elif float(crate.y) + 1.0 <= bottom - ITEM_RADIUS * 2 + EPS:
				ceiling = maxf(ceiling, float(crate.y) + 1.0)
		item.vy = minf(float(item.vy) + tuning.gravity * STEP, tuning.crate_fall_speed)
		item.y = bottom + float(item.vy) * STEP
		if item.vy < 0.0 and item.y < ceiling + ITEM_RADIUS * 2:
			item.y = ceiling + ITEM_RADIUS * 2
			item.vy = 0.0
		elif item.y >= support:
			item.y = support
			if not item.bounced and float(item.vy) > 1.0:
				item.bounced = true
				item.vy = -1.8
			else:
				item.vy = 0.0


func nearest_item() -> Dictionary:
	if state != "playing":
		return {}
	var center := player + Vector2(tuning.player_width, tuning.player_height) * 0.5
	var nearest := {}
	var best := PICKUP_DISTANCE * PICKUP_DISTANCE
	# Insertion order is also the stable tie breaker. Exchanges retain the ground ID.
	for item in ground_items:
		var at := Vector2(item.x, float(item.y) - ITEM_RADIUS)
		var distance := center.distance_squared_to(at)
		if distance <= best and (nearest.is_empty() or distance < best - EPS * EPS):
			nearest = item
			best = distance
	return nearest


func equipped_charges(kind: String) -> int:
	var charges := int(get(kind + "_charges"))
	if charges > 0 or (kind == "boots" and boots_equipped) or (kind == "lamp_helmet" and lamp_helmet_equipped):
		return charges
	return -1


func equipped_in_slot(kind: String) -> String:
	for slot in SLOTS.values():
		if kind in slot:
			for current: String in slot:
				if equipped_charges(current) >= 0:
					return current
	return ""


func pick_up_nearest() -> String:
	var item := nearest_item()
	if item.is_empty():
		return ""
	var kind := str(item.kind)
	var charges := int(item.charges)
	var progress := float(item.progress)
	var old := equipped_in_slot(kind)
	if old.is_empty():
		ground_items.erase(item)
	else:
		item.kind = old
		item.charges = int(get(old + "_charges"))
		item.progress = speed_boots_progress if old == "speed_boots" else 0.0
		item.born = -1
	if kind in SLOTS.feet:
		_release_feet_slot()
	elif kind in SLOTS.head:
		_release_head_slot()
	else:
		_release_hands_slot()
	set(kind + "_charges", charges)
	if kind == "boots":
		boots_equipped = true
	elif kind == "lamp_helmet":
		lamp_helmet_equipped = true
	elif kind == "speed_boots":
		speed_boots_progress = progress
	return kind


# Sweep the leading edge. Each crate resolves its first contact only, and new
# drops become eligible on the next physics tick.
func _hit_ground_items(crate: Dictionary, start: float, end: float, sideways: bool = false) -> bool:
	if start == end or ground_items.is_empty() or (not sideways and end < start):
		return false
	var direction := signf(end - start)
	var leading_edge := start * direction + (1.0 if direction > 0.0 else 0.0)
	var travel := absf(end - start)
	var closest := INF
	var hit := {}
	for item in ground_items:
		if item.born == ticks:
			continue
		var near_edge: float
		if sideways:
			if not _overlap(float(crate.y), 1.0, float(item.y) - ITEM_RADIUS * 2, ITEM_RADIUS * 2, 0.0):
				continue
			near_edge = float(item.x) * direction - ITEM_RADIUS
		else:
			if not _overlap(float(crate.x), 1.0, float(item.x) - ITEM_RADIUS, ITEM_RADIUS * 2):
				continue
			near_edge = float(item.y) - ITEM_RADIUS * 2
		var distance := near_edge - leading_edge
		if distance < -ITEM_RADIUS * 2 - EPS or distance > travel:
			continue
		distance = maxf(0.0, distance)
		if distance < closest:
			closest = distance
			hit = item
	if hit.is_empty():
		return false
	if hit.kind in ["helmet", "mallet"] and int(hit.charges) > 1:
		hit.charges -= 1
	else:
		ground_items.erase(hit)
	crate["x" if sideways else "y"] = start + direction * closest
	_destroy_crate(crate)
	events.append({"type": "ground_impact", "x": float(crate.x), "y": float(crate.y)})
	return true


func _release_hands_slot() -> void:
	cancel_grab()
	cancel_mallet_swing()
	_cancel_strong_push()
	gloves_charges = 0
	mallet_charges = 0
	strong_arms_charges = 0


func _release_head_slot() -> void:
	helmet_charges = 0
	lamp_helmet_equipped = false
	lamp_helmet_charges = 0
	lamp_active_time = 0.0
	_lamp_pending = false


func _release_feet_slot() -> void:
	boots_equipped = false
	boots_charges = 0
	_air_jump_requested = false
	speed_boots_charges = 0
	speed_boots_progress = 0.0
	speed_boost_active = false
	spring_boots_charges = 0
	_spring_flight = false
	_cancel_spring_charge()


func cancel_jump_input() -> void:
	_jump_buffer = 0.0
	_air_jump_requested = false
	_cancel_spring_charge()


func cancel_bonus_input() -> void:
	cancel_jump_input()
	_lamp_pending = false
	speed_boost_active = false


func _tick(axis: float, pull_held: bool, jump_held: bool, speed_held: bool) -> void:
	ticks += 1
	_push_contact_id = -1
	_sliding_push_direction = 0.0
	_sliding_pull = false
	speed_boost_active = false
	if state == "clearing":
		_advance_clear()
		return
	elapsed += STEP
	_jump_buffer = maxf(0.0, _jump_buffer - STEP)
	_coyote = 0.085 if grounded else maxf(0.0, _coyote - STEP)
	_update_lamp()
	if _gloves_take_control(pull_held):
		_move_with_gloves(pull_held and gloves_charges > 0)
	else:
		_walk_player(axis, speed_held)
	_advance_mallet()
	_move_player_vertically(jump_held)
	_move_items()
	_move_crates()
	if state == "over":
		return
	if (grabbed_crate_id >= 0 or is_pulling()) and _held_crate().is_empty():
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


func cancel_mallet_swing() -> void:
	_mallet_pending = false
	_mallet_impact_tick = -1


func _advance_mallet() -> void:
	if _mallet_impact_tick >= 0:
		if ticks >= _mallet_impact_tick:
			_mallet_impact_tick = -1
			_finish_mallet_swing()
		return
	if not _mallet_pending or mallet_charges <= 0:
		return
	_mallet_pending = false
	_mallet_facing = facing
	_mallet_impact_tick = ticks + roundi(MALLET_WINDUP_TIME / STEP)
	events.append(_mallet_event("mallet_swing"))


func _mallet_event(kind: String) -> Dictionary:
	return {"type": kind, "player_x": player.x, "player_y": player.y,
		"facing": _mallet_facing, "tick": ticks}


func _finish_mallet_swing() -> void:
	var target := {}
	var closest_gap := INF
	var closest_height := INF
	for crate in crates:
		var x := float(crate.x)
		var y := float(crate.y)
		var gap := x - (player.x + tuning.player_width) if _mallet_facing > 0 else player.x - (x + 1.0)
		if gap < -0.03 or gap > MALLET_REACH or not _overlap(player.y, tuning.player_height, y, 1.0, 0.12):
			continue
		var height := absf(y + 0.5 - (player.y + tuning.player_height * 0.5))
		if gap < closest_gap - EPS or (absf(gap - closest_gap) <= EPS and height < closest_height):
			target = crate
			closest_gap = gap
			closest_height = height
	if target.is_empty():
		events.append(_mallet_event("mallet_miss"))
		return
	_destroy_crate(target)
	mallet_charges -= 1
	if mallet_charges == 0:
		cancel_mallet_swing()
	var impact := _mallet_event("mallet_hit")
	impact.merge({"crate_id": int(target.id), "x": float(target.x), "y": float(target.y),
		"color": int(target.color), "charges": mallet_charges, "mallet_broke": mallet_charges == 0})
	events.append(impact)


func lamp_columns() -> Array[int]:
	var result: Array[int] = []
	if not cranes_enabled:
		return result
	for crane in cranes:
		if not crane.loaded or crane.waiting:
			continue
		var column := int(crane.release_column)
		while column >= 0 and column < tuning.columns and not _crane_column_is_free(column):
			column += int(crane.direction)
		if column >= 0 and column < tuning.columns and not result.has(column):
			result.append(column)
	return result


func _update_lamp() -> void:
	lamp_active_time = maxf(0.0, lamp_active_time - STEP)
	if not _lamp_pending:
		return
	_lamp_pending = false
	if not lamp_helmet_equipped or lamp_helmet_charges <= 0:
		return
	var columns := lamp_columns()
	if not columns.is_empty():
		lamp_helmet_charges -= 1
		lamp_active_time = LAMP_REVEAL_TIME
		events.append({"type": "lamp_reveal", "columns": columns, "charges": lamp_helmet_charges})


func _request_jump() -> void:
	if state == "playing" and spring_boots_charges > 0 and grounded:
		if not _spring_charging:
			_spring_charging = true
			_jump_buffer = 0.0
	elif state == "playing" and boots_equipped and boots_charges > 0 and not grounded and _coyote <= STEP:
		_air_jump_requested = true
	else:
		_jump_buffer = 0.12


func spring_charge_limit() -> int:
	var extra_speed := maxf(0.0, _spring_ceiling_speed() - tuning.jump_speed)
	return mini(spring_boots_charges, ceili(extra_speed / SPRING_STAGE_SPEED))


func _spring_ceiling_speed() -> float:
	var room := maxf(0.0, player.y - PLAYER_TOP)
	return sqrt(2.0 * tuning.gravity * room) + tuning.gravity * STEP * 0.5


func _cancel_spring_charge() -> void:
	_spring_charging = false
	_spring_charge_time = 0.0
	spring_charge_stages = 0


func _advance_spring_jump(jump_held: bool) -> void:
	if not _spring_charging:
		return
	if spring_boots_charges <= 0 or (not grounded and _coyote <= 0.0):
		_cancel_spring_charge()
		return
	var limit := spring_charge_limit()
	if jump_held:
		if not grounded:
			return
		_spring_charge_time += STEP
		var timed_stages := floori((_spring_charge_time + EPS) / SPRING_STAGE_TIME)
		spring_charge_stages = mini(timed_stages, limit)
		if spring_charge_stages < limit:
			return
	var stages := mini(spring_charge_stages, limit)
	_cancel_spring_charge()
	if stages == 0 and not jump_held:
		_jump_buffer = 0.12
		return
	var speed := minf(tuning.jump_speed + SPRING_STAGE_SPEED * stages, _spring_ceiling_speed())
	spring_boots_charges -= stages
	_spring_flight = true
	_launch_ground_jump(speed)
	events.append({"type": "spring_jump", "stages": stages, "limit": limit, "automatic": jump_held,
		"player_x": player.x, "player_y": player.y, "facing": facing})


func _launch_ground_jump(speed: float) -> void:
	player_velocity.y = -speed
	grounded = false
	_coyote = 0.0
	_jump_buffer = 0.0


func _move_player_vertically(jump_held: bool) -> void:
	var height := tuning.player_height
	_advance_spring_jump(jump_held)
	if _jump_buffer > 0.0 and (grounded or _coyote > 0.0):
		_launch_ground_jump(tuning.jump_speed)
		events.append({"type": "jump"})
	elif _air_jump_requested and boots_charges > 0 and player.y > PLAYER_TOP + EPS:
		player_velocity.y = -tuning.jump_speed
		boots_charges -= 1
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
	if proposed_y < PLAYER_TOP and (boots_equipped or _spring_flight):
		player_velocity.y = maxf(player_velocity.y, 0.0)
	player.y = maxf(PLAYER_TOP, proposed_y)


func _walk_player(axis: float, speed_held: bool) -> void:
	var width := tuning.player_width
	var old_x := player.x
	if not is_zero_approx(axis):
		facing = 1 if axis > 0.0 else -1
	var step := axis * tuning.player_speed * STEP
	var boosting := speed_held and speed_boots_charges > 0
	if boosting:
		step = signf(step) * minf(absf(step) * SPEED_BOOTS_MULTIPLIER,
			float(speed_boots_charges) - speed_boots_progress)
	var proposed_x := clampf(player.x + step, 0.0, tuning.columns - width)
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
	if boosting:
		_spend_speed_distance(maxf(0.0, (player.x - old_x) * signf(axis)))


func _spend_speed_distance(distance: float) -> void:
	speed_boost_active = distance > EPS
	speed_boots_progress += distance
	var cells := mini(speed_boots_charges, floori(speed_boots_progress + EPS * 0.01))
	speed_boots_charges -= cells
	speed_boots_progress = maxf(0.0, speed_boots_progress - cells)
	if cells > 0:
		events.append({"type": "speed_step", "cells": cells, "charges": speed_boots_charges,
			"player_x": player.x, "player_y": player.y, "facing": facing})


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
	var id := int(_pull_crate.id) if is_pulling() else grabbed_crate_id
	if id < 0:
		return {}
	for crate in crates:
		if int(crate.id) == id and _can_hold(crate):
			return crate
	return {}


func _find_grabbable_crate() -> Dictionary:
	if not grounded:
		return {}
	var nearest_gap := INF
	var nearest := {}
	for crate in crates:
		var x := float(crate.x)
		if absf(x - roundf(x)) > EPS or not _can_hold(crate):
			continue
		var gap := _grab_gap(crate)
		if gap < nearest_gap:
			nearest = crate
			nearest_gap = gap
	return nearest


func is_pulling() -> bool:
	return not _pull_crate.is_empty()


func _gloves_take_control(pull_held: bool) -> bool:
	return (pull_held and gloves_charges > 0) or is_pulling()


func release_pull_input() -> void:
	grabbed_crate_id = -1
	_sliding_pull = false


func cancel_grab() -> void:
	release_pull_input()
	if is_pulling():
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


func _move_with_gloves(pull_held: bool) -> void:
	var crate := _held_crate()
	if crate.is_empty():
		cancel_grab()
		if not pull_held:
			return
		crate = _find_grabbable_crate()
		if crate.is_empty():
			return
	if pull_held and (not is_pulling() or not _pull_returning):
		grabbed_crate_id = int(crate.id)
	if not is_pulling():
		var start_x := float(crate.x)
		if not _pull_path_clear(crate, player.x - facing, start_x - facing):
			return
		if crates.any(func(other: Dictionary) -> bool: return absf(float(other.target_x) - float(other.x)) > EPS):
			return
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
			return
	var previous_x := float(_pull_crate.x)
	var previous_offset := previous_x - _pull_start_crate_x
	var offset := move_toward(previous_offset, distance, tuning.push_speed * STEP)
	_sliding_pull = pull_held and not _pull_returning and offset != previous_offset
	player.x = _pull_start_player_x + offset
	_pull_crate.x = _pull_start_crate_x + offset
	_pull_crate.target_x = _pull_crate.x
	if _hit_ground_items(_pull_crate, previous_x, float(_pull_crate.x), true):
		player.x = _pull_start_player_x + (float(_pull_crate.x) - _pull_start_crate_x)
		cancel_grab()
		return
	if offset == distance:
		if not _pull_returning:
			gloves_charges -= 1
			events.append({"type": "gloves_pull", "crate_id": int(_pull_crate.id), "x": float(_pull_crate.x),
				"y": float(_pull_crate.y), "player_x": player.x, "player_y": player.y, "facing": facing,
				"gloves_broke": gloves_charges == 0, "charges": gloves_charges, "tick": ticks})
			if gloves_charges == 0:
				release_pull_input()
		_pull_crate = {}


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
	_spring_flight = false
	if boots_charges == 0:
		boots_equipped = false


func is_strong_pushing() -> bool:
	return not _strong_pair.is_empty()


func _try_strong_push(crate: Dictionary, direction: int) -> bool:
	if strong_arms_charges <= 0:
		return false
	var x := float(crate.x)
	var y := float(crate.y)
	for other in crates:
		if absf(float(other.x) - x - direction) > EPS or absf(float(other.y) - y) > EPS:
			continue
		var target := ceilf(x - EPS) if direction > 0 else floorf(x + EPS)
		if absf(target - x) <= EPS:
			target += direction
		if not _strong_step_clear(crate, other, target - x):
			return false
		crate.target_x = target
		other.target_x = target + direction
		_strong_pair.assign([crate, other])
		_strong_direction = direction
		_push_contact_id = int(crate.id)
		return true
	return false


func _strong_step_clear(first: Dictionary, second: Dictionary, shift: float) -> bool:
	for crate in [first, second]:
		var x := float(crate.x)
		var target := x + shift
		if target < -EPS or target > tuning.columns - 1.0 + EPS:
			return false
		for other in crates:
			if other.id == first.id or other.id == second.id:
				continue
			if _overlap(minf(x, target), 1.0 + absf(shift), float(other.x), 1.0, EPS) and _overlap(
					float(crate.y), 1.0, float(other.y), 1.0, 0.0):
				return false
	return true


func _cancel_strong_push() -> void:
	for crate in _strong_pair:
		crate.target_x = crate.x
	_strong_pair.clear()
	_strong_direction = 0


func _advance_strong_push() -> float:
	if not is_strong_pushing():
		return 0.0
	var first := _strong_pair[0]
	var second := _strong_pair[1]
	if not crates.has(first) or not crates.has(second):
		_cancel_strong_push()
		return 0.0
	var x := float(first.x)
	var next_x := move_toward(x, float(first.target_x), tuning.push_speed * STEP)
	var shift := next_x - x
	if not _strong_step_clear(first, second, shift):
		_cancel_strong_push()
		return 0.0
	var previous_second_x := float(second.x)
	first.x = next_x
	second.x = next_x + _strong_direction
	var front_hit := _hit_ground_items(second, previous_second_x, float(second.x), true)
	var rear_hit := _hit_ground_items(first, x, next_x, true)
	if front_hit or rear_hit:
		# The surviving crate finishes its slide to the original grid cell.
		_strong_pair.clear()
		_strong_direction = 0
		return shift
	if next_x == float(first.target_x):
		strong_arms_charges -= 1
		events.append({"type": "strong_push", "crate_ids": [int(first.id), int(second.id)],
			"charges": strong_arms_charges, "player_x": player.x, "player_y": player.y,
			"facing": _strong_direction})
		_cancel_strong_push()
	return shift


func _try_push(crate: Dictionary, direction: int) -> bool:
	if is_strong_pushing():
		if crate.id == _strong_pair[0].id and direction == _strong_direction:
			_push_contact_id = int(crate.id)
		return false
	var remaining := float(crate.target_x) - float(crate.x)
	if absf(remaining) > EPS:
		if int(crate.id) == _pushed_crate_id and remaining * direction > 0.0:
			_push_contact_id = _pushed_crate_id
		return false
	for other in crates:
		if absf(float(other.target_x) - float(other.x)) > EPS:
			return false
	if _try_strong_push(crate, direction):
		return true
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
	_pushed_crate_id = int(crate.id)
	_push_contact_id = _pushed_crate_id
	return true


func _move_crate_horizontally(crate: Dictionary) -> float:
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
	if int(crate.id) == _pushed_crate_id and absf(float(crate.target_x) - resolved) <= EPS:
		_pushed_crate_id = -1
	return resolved - old_x if resolved == desired else 0.0


func _move_crates() -> void:
	var strong_ids: Array[int] = []
	for crate in _strong_pair:
		strong_ids.append(int(crate.id))
	var strong_slide := _advance_strong_push()
	crates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.y) > float(b.y) if not is_equal_approx(float(a.y), float(b.y)) else int(a.id) < int(b.id))
	var index := 0
	while index < crates.size():
		var crate := crates[index]
		var slide := strong_slide
		if not strong_ids.has(int(crate.id)):
			var old_x := float(crate.x)
			slide = _move_crate_horizontally(crate)
			if _hit_ground_items(crate, old_x, float(crate.x), true):
				continue
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
		var sweep_end := minf(new_y + 1.0, player.y) if hits_head else new_y + 1.0
		if _hit_ground_items(crate, float(crate.y), sweep_end - 1.0):
			continue
		if hits_head and (helmet_charges > 0 or lamp_helmet_equipped):
			var contact_y := clampf(player.y - 1.0, float(crate.y), new_y)
			_break_crate_with_helmet(crate, contact_y, player.y, "fall", lamp_helmet_equipped)
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
		if int(crate.id) == _push_contact_id and _overlap(player.y, tuning.player_height, new_y, 1.0):
			_sliding_push_direction = signf(slide)
		index += 1


func _break_crate_with_helmet(crate: Dictionary, crate_y: float, player_y: float, direction: String,
		lamp: bool = false) -> void:
	if lamp:
		_release_head_slot()
	else:
		helmet_charges -= 1
	crate.y = crate_y
	_destroy_crate(crate)
	events.append({"type": "lamp_break" if lamp else "helmet_hit", "crate_id": int(crate.id), "x": float(crate.x),
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
	cancel_mallet_swing()
	_cancel_spring_charge()
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
		_move_items()
		return
	if not _collapse_started:
		for crate: Dictionary in crates.duplicate():
			if _clear_ids.has(int(crate.id)):
				_destroy_crate(crate, true)
		for crate in crates:
			crate.clear_y = float(crate.y)
			crate.vy = 0.0
		_player_clear_start = player
		_collapse_started = true
	var fraction := clampf((clear_elapsed - tuning.clear_flash_time) / tuning.collapse_time, 0.0, 1.0)
	var smooth_fraction := fraction * fraction * (3.0 - 2.0 * fraction)
	_move_items()
	for crate: Dictionary in crates.duplicate():
		var new_y := float(crate.clear_y) + smooth_fraction
		if not _hit_ground_items(crate, float(crate.y), new_y):
			crate.y = new_y
	player.y = minf(_player_clear_start.y + smooth_fraction, tuning.rows - tuning.player_height)
	player_velocity.y = 0.0
	if fraction >= 1.0:
		state = "playing"
		grounded = false
		if player.y + tuning.player_height + EPS >= _player_support():
			_land_player()
		if not _begin_clear_if_full():
			chain = 0


func _crane_entrance(direction: int) -> float:
	return -CRANE_EDGE_MARGIN if direction > 0 else tuning.columns + CRANE_EDGE_MARGIN


func _enter_crane(crane: Dictionary) -> void:
	crane.x = _crane_entrance(int(crane.direction))
	crane.loaded = true
	crane.variant = _take_crate_variant()
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
			var crate := add_crate(float(column), CRATE_RELEASE_Y, 0.0, int(crane.variant))
			crane.loaded = false
			crane.open_time = tuning.crane_open_time
			events.append({"type": "drop", "count": 1, "crane": index,
				"column": column, "crate_id": int(crate.id), "tick": ticks, "variant": int(crate.variant)})
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
	cancel_mallet_swing()
	cancel_bonus_input()
	_cancel_strong_push()
	lamp_active_time = 0.0
	state = "over"
	loss_reason = reason
	events.append({"type": "over", "reason": reason, "score": score})
