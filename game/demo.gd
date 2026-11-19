class_name StackDemo
extends RefCounted
## A separate real game driven through the same actions as the player.
var model: StackSimulation
var tuning: StackTuning
var axis := 1.0
var rounds := 0
var jumps := 0
var drops := 0
var lines := 0
var losses := 0
var total_ticks := 0
var events: Array[Dictionary] = []
var _seed: int
var _accumulator := 0.0
var over_elapsed := 0.0
var _think := 0.0
var _retreat := 0.0
var _retreat_axis := 0.0
var _jump_wait := 0.0
var _last_x := 0.0
var _stuck := 0.0
var _watch_hold := 0.0
var _watch_wait := 0.0
var _shot_wait := 0.0
var _goggles_pressed := false
var _shot_pressed := false


func _init(settings: StackTuning, seed_value: int = 7481) -> void:
	tuning = settings
	_seed = seed_value
	_restart()


func _restart() -> void:
	model = StackSimulation.new(tuning, _seed + rounds * 97)
	rounds += 1
	over_elapsed = 0.0
	_think = 0.0
	_retreat = 0.0
	_jump_wait = 0.6
	_stuck = 0.0
	_watch_hold = 0.0
	_watch_wait = 0.0
	_shot_wait = 0.0
	axis = 1.0 if rounds % 2 == 1 else -1.0
	_last_x = model.player.x


func advance(delta: float) -> void:
	events.clear()
	_accumulator += maxf(0.0, delta)
	while _accumulator >= StackSimulation.STEP:
		_accumulator -= StackSimulation.STEP
		total_ticks += 1
		if model.state == "over":
			over_elapsed += StackSimulation.STEP
			if over_elapsed >= 1.2:
				_restart()
			continue
		_goggles_pressed = false
		_shot_pressed = false
		var jump := _input_step()
		model.advance(StackSimulation.STEP, axis, jump, false, false, {
			"watch_held": _watch_hold > 0.0, "goggles_pressed": _goggles_pressed,
			"slingshot_pressed": _shot_pressed})
		for event in model.events:
			events.append(event.duplicate())
			match event.type:
				"jump": jumps += 1
				"drop": drops += int(event.count)
				"line": lines += 1
				"over":
					losses += 1
					axis = 0.0


# Sample what is on screen between short, interruptible movement decisions.
func _input_step() -> bool:
	var step := StackSimulation.STEP
	_watch_hold = maxf(0.0, _watch_hold - step)
	_watch_wait = maxf(0.0, _watch_wait - step)
	_shot_wait = maxf(0.0, _shot_wait - step)
	_jump_wait = maxf(0.0, _jump_wait - step)
	_retreat = maxf(0.0, _retreat - step)
	_think -= step
	if _think > 0.0 or model.state != "playing":
		return false
	_think = 0.12
	_stuck = _stuck + _think if absf(model.player.x - _last_x) < 0.08 else 0.0
	_last_x = model.player.x
	var falls: Array[float] = []
	for crate in model.crates:
		var gap := model.player.y - (float(crate.y) + 1.0)
		if float(crate.vy) > 0.1 and gap >= -0.08 and gap < 3.6:
			falls.append(float(crate.x))
	for mechanic in model.repair.fallen:
		var at: Vector2 = mechanic.position
		var gap := model.player.y - at.y - StackCraneRepair.FALL_HALF_HEIGHT
		if gap >= -0.08 and gap < 3.6:
			falls.append(at.x - 0.5)
	var center := model.player.x + tuning.player_width * 0.5
	for left in falls:
		if absf(center - left - 0.5) < 0.5 + tuning.player_width * 0.5 + 0.12:
			var left_cost := _exit_cost(left - tuning.player_width - 0.12, falls)
			var right_cost := _exit_cost(left + 1.12, falls)
			axis = -1.0 if left_cost < right_cost else 1.0
			_retreat_axis = axis
			_retreat = 0.23
			if model.watch_cap_time > 0.0 and _watch_wait <= 0.0:
				_watch_hold = 0.66
				_watch_wait = 1.4
			return false
	if _retreat > 0.0:
		axis = _retreat_axis
		return false

	var nearest := model.nearest_item()
	if not nearest.is_empty() and _useful(nearest):
		model.pick_up_nearest()
	_goggles_pressed = model.engineer_goggles_charges > 0 and not model.nearest_trap().is_empty()
	if model.slingshot_charges > 0 and _shot_wait <= 0.0:
		_shot_pressed = true
		_shot_wait = 1.8
	var item_goal := INF
	var distance := 3.0
	for item in model.ground_items:
		var dx := float(item.x) - center
		var dy := float(item.y) - model.player.y - tuning.player_height
		var cost := absf(dx) + absf(dy)
		if cost < distance and _useful(item):
			distance = cost
			item_goal = float(item.x)
	var jump_needed := false
	if is_finite(item_goal):
		axis = signf(item_goal - center)
		jump_needed = absf(item_goal - center) < 0.6
	else:
		var push := _row_push()
		if not push.is_empty():
			var dx := float(push.approach) - model.player.x
			var in_reach := absf(dx) < 0.18
			if in_reach and absf(model.player.y + tuning.player_height - float(push.bottom)) < 0.55:
				axis = float(push.side)
				# A short nudge starts the normal one-cell slide. Step clear
				# before the crate above a displaced base loses support.
				_retreat_axis = -axis
				_retreat = 0.4
			else:
				axis = signf(dx)
				jump_needed = in_reach and model.player.y + tuning.player_height > float(push.bottom) + 0.55
		else:
			if model.player.x < 0.4:
				axis = 1.0
			elif model.player.x > tuning.columns - tuning.player_width - 0.4:
				axis = -1.0
			elif is_zero_approx(axis):
				axis = float(model.facing)
			jump_needed = true
	# Look one short stride ahead before following an item or approaching a stack.
	for left in falls:
		if absf(center + axis * 0.45 - left - 0.5) < 0.5 + tuning.player_width * 0.5:
			axis = 0.0
			return false
	var trap_ahead := _trap_ahead(center) and not _goggles_pressed
	if model.grounded and ((trap_ahead and model.hunting_boots_charges == 0)
			or (_jump_wait <= 0.0 and (jump_needed or _stuck > 0.22))):
		_jump_wait = 1.15
		return true
	return false


func _trap_ahead(center: float) -> bool:
	var feet := model.player.y + tuning.player_height
	for trap in model.traps:
		var x := float(trap.x)
		if absf(feet - float(trap.y)) <= 0.1 and trap.phase != "folded" \
				and absf(center + axis * 0.48 - x) < 0.64:
			return true
	return false


func _exit_cost(x: float, falls: Array[float]) -> float:
	var travel := absf(x - model.player.x)
	var cost := travel
	if x < 0.0 or x + tuning.player_width > tuning.columns:
		cost += 20.0
	var route := Rect2(minf(x, model.player.x), model.player.y,
		travel + tuning.player_width, tuning.player_height).grow(-0.02)
	for crate in model.crates:
		if route.intersects(Rect2(float(crate.x), float(crate.y), 1.0, 1.0)):
			cost += 4.0
	for left in falls:
		if x < left + 1.0 and x + tuning.player_width > left:
			cost += 6.0
	return cost


func _useful(item: Dictionary) -> bool:
	var kind := str(item.kind)
	var current := model.equipped_in_slot(kind)
	return int(item.charges) > 0 and (current.is_empty() or
		(current == kind and int(item.charges) > model.equipped_charges(kind)))


# Look for a spare crate in a stack next to a gap in the bottom row.
# The approach cell must have room for the player at the pushing height.
func _row_push() -> Dictionary:
	var heights := PackedInt32Array()
	heights.resize(tuning.columns)
	var metal_cells := {}
	for crate in model.crates:
		var column := roundi(float(crate.x))
		if column >= 0 and column < tuning.columns and absf(float(crate.vy)) < 0.01 and absf(float(crate.x) - column) < 0.02:
			heights[column] += 1
			if crate.material == "metal":
				metal_cells[Vector2i(column, roundi(float(crate.y)))] = true
	var best := {}
	var distance := INF
	for col in range(1, tuning.columns - 1):
		if heights[col] < 2:
			continue
		for side: int in [-1, 1]:
			if heights[col + side] != 0:
				continue
			var level := heights[col - side]
			if level >= heights[col]:
				continue
			var at := col - tuning.player_width if side > 0 else float(col + 1)
			var bottom := tuning.rows - level
			if model.strong_arms_charges <= 0 and metal_cells.has(Vector2i(col, bottom - 1)):
				continue
			var cost := absf(at - model.player.x) + absf(bottom - model.player.y - tuning.player_height)
			if cost < distance:
				distance = cost
				best = {"approach": at, "bottom": bottom, "side": side}
	return best
