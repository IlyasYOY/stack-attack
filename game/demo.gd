class_name StackDemo
extends RefCounted
## A separate real game, driven only through the normal movement/jump inputs.
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
var _over_wait := 0.0
var _think := 0.0
var _escape := 0.0
var _escape_axis := 0.0
var _push := 0.0
var _jump_wait := 0.0
var _last_x := 0.0
var _stuck := 0.0


func _init(settings: StackTuning, seed_value: int = 7481) -> void:
	tuning = settings
	_seed = seed_value
	_restart()


func _restart() -> void:
	model = StackSimulation.new(tuning, _seed + rounds * 97)
	rounds += 1
	_over_wait = 0.0
	_think = 0.0
	_escape = 0.0
	_push = 0.0
	_jump_wait = 0.6
	_stuck = 0.0
	axis = 1.0 if rounds % 2 == 1 else -1.0
	_last_x = model.player.x


func advance(delta: float) -> void:
	events.clear()
	_accumulator += maxf(0.0, delta)
	while _accumulator >= StackSimulation.STEP:
		_accumulator -= StackSimulation.STEP
		total_ticks += 1
		if model.state == "over":
			_over_wait += StackSimulation.STEP
			if _over_wait >= 1.2:
				_restart()
			continue
		var jump := _input_step()
		model.advance(StackSimulation.STEP, axis, jump)
		for event in model.events:
			events.append(event.duplicate())
			match event.type:
				"jump": jumps += 1
				"drop": drops += int(event.count)
				"line": lines += 1
				"over":
					losses += 1
					axis = 0.0


func _input_step() -> bool:
	var step := StackSimulation.STEP
	_jump_wait = maxf(0.0, _jump_wait - step)
	if _push > 0.0:
		_push -= step
		return false
	if _escape > 0.0:
		_escape -= step
		axis = _escape_axis
		return false
	_think -= step
	if _think > 0.0:
		return false
	_think = 0.1
	_stuck = _stuck + 0.1 if absf(model.player.x - _last_x) < 0.08 else 0.0
	_last_x = model.player.x
	# Move away from a falling crate or a crane about to release above the bot.
	var center := model.player.x + tuning.player_width * 0.5
	for crate in model.crates:
		if float(crate.vy) > 0.1 and float(crate.y) + 1.0 <= model.player.y + 0.02:
			if model.player.y - float(crate.y) - 1.0 < 2.5 and absf(float(crate.x) + 0.5 - center) < 0.8:
				axis = -1.0 if center < float(crate.x) + 0.5 else 1.0
				_escape_axis = axis
				_escape = 0.35
				return false
	for crane in model.cranes:
		if int(crane.release_column) == int(floorf(center)) and model.time_to_crane_release(crane) < 0.4:
			axis = -1.0 if center > tuning.columns * 0.5 else 1.0
			_escape_axis = axis
			_escape = 0.35
			return false
	# A supported stack next to a floor gap can be spread by nudging its base,
	# then retreating while the upper crate falls through the real simulation.
	var best := INF
	var approach := 0.0
	var direction := 0.0
	for crate in model.crates:
		if absf(float(crate.y) - (tuning.rows - 1)) > 0.01 or absf(float(crate.vy)) > 0.01:
			continue
		var stacked := false
		for upper in model.crates:
			if upper.id != crate.id and absf(float(upper.x) - float(crate.x)) < 0.05 and absf(float(upper.y) - (tuning.rows - 2)) < 0.05:
				stacked = true
		if not stacked:
			continue
		for side in [-1, 1]:
			var target: float = float(crate.x) + float(side)
			if target < 0.0 or target >= tuning.columns:
				continue
			var free := true
			for other in model.crates:
				if other.id != crate.id and absf(float(other.x) - target) < 0.99 and float(other.y) > tuning.rows - 1.1:
					free = false
			if not free:
				continue
			var at := float(crate.x) - tuning.player_width if side > 0 else float(crate.x) + 1.0
			var distance := absf(model.player.x - at) + absf(model.player.y - (tuning.rows - tuning.player_height))
			if distance < best:
				best = distance
				approach = at
				direction = side
	if is_finite(best):
		if absf(model.player.x - approach) < 0.12 and model.grounded and model.player.y > tuning.rows - 1.0:
			axis = direction
			_push = 0.045
			_escape_axis = -direction
			_escape = 0.42
			return false
		axis = signf(approach - model.player.x)
	elif model.player.x < 0.4:
		axis = 1.0
	elif model.player.x > tuning.columns - tuning.player_width - 0.4:
		axis = -1.0
	elif is_zero_approx(axis):
		axis = float(model.facing)
	if _stuck > 1.1:
		axis = -axis
		_stuck = 0.0
	if model.grounded and _jump_wait <= 0.0 and (_stuck > 0.1 or not is_finite(best)):
		_jump_wait = 1.4
		return true
	return false
