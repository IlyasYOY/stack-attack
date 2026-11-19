class_name StackCraneRepair
extends RefCounted
## Independent state for each rail. All motion and timers follow simulation ticks.

const REPAIR_TIME := 2.5
const CLIMB_SPEED := 5.0
const TRACK_Y := [-46.0 / 24.0, -34.0 / 24.0]
const HANGING_OFFSET := 0.33
const SITTING_OFFSET := -0.39
const FALL_HALF_WIDTH := 0.19
const FALL_HALF_HEIGHT := 0.28
const FALL_SPEED := 10.0
const SHOT_ARC := 0.62
const RAIL_MARGIN := 10.0 / 24.0
const END_STOP_WIDTH := 7.0
const JAW_HINGE_X := 12.0
const WORKER_SPRITE_HALF_WIDTH := 12.5 / 24.0

var workers: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var fallen: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _next_worker := 0


func reset(seed_value: int) -> void:
	_rng.seed = seed_value ^ 0x21c96a5
	_next_worker = 0
	workers.clear()
	for index in range(TRACK_Y.size()):
		workers.append({"phase": "idle", "broken": false, "id": -1,
			"elapsed": 0.0, "x": 0.0, "cycle": 0})
	shots.clear()
	fallen.clear()


func worker_position(model: StackSimulation, index: int) -> Vector2:
	var worker := workers[index]
	if worker.phase == "passenger":
		return _crane_position(model, index) + Vector2(0, SITTING_OFFSET)
	return Vector2(float(worker.x), float(TRACK_Y[index]) + HANGING_OFFSET)


func shoot(model: StackSimulation) -> bool:
	if not model.cranes_enabled or model.slingshot_charges <= 0:
		return false
	var candidates: Array[int] = []
	for index in range(workers.size()):
		if workers[index].phase != "idle" and _visible(model, worker_position(model, index).x, WORKER_SPRITE_HALF_WIDTH):
			candidates.append(index)
	var targets_worker := not candidates.is_empty()
	if not targets_worker:
		for index in range(workers.size()):
			var crane := model.cranes[index]
			if _active_crane(model, index) and _crane_visible(model, crane):
				candidates.append(index)
	if candidates.is_empty():
		return false
	var index := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var origin := model.player + Vector2(model.tuning.player_width * (0.5 + float(model.facing) * 0.32),
		model.tuning.player_height * 0.43)
	var target := worker_position(model, index) if targets_worker else _crane_position(model, index)
	var duration := clampf(origin.distance_to(target) * 0.017, 0.13, 0.26)
	var target_code := int(workers[index].id) if targets_worker else int(workers[index].cycle)
	shots.append({"from": origin, "to": target, "position": origin, "elapsed": 0.0, "duration": duration,
		"crane": index, "worker": targets_worker, "target_code": target_code})
	model.slingshot_charges -= 1
	_event(model, "slingshot_fire", index, origin)
	return true


static func shot_position(shot: Dictionary, t: float) -> Vector2:
	var origin: Vector2 = shot.from
	var target: Vector2 = shot.to
	return origin.lerp(target, t) - Vector2(0, sin(t * PI) * SHOT_ARC)


func advance(model: StackSimulation) -> void:
	_advance_falls(model)
	if model.state != "over":
		_advance_shots(model)


func blocks_crane(model: StackSimulation, index: int) -> bool:
	var worker := workers[index]
	if not worker.broken:
		return false
	worker.elapsed += StackSimulation.STEP
	if worker.phase == "climb":
		var target_x := float(model.cranes[index].x)
		worker.x = move_toward(float(worker.x), target_x, CLIMB_SPEED * StackSimulation.STEP)
		if worker.x == target_x:
			worker.phase = "repair"
			worker.elapsed = 0.0
			_event(model, "mechanic_repair", index, worker_position(model, index))
	elif float(worker.elapsed) + StackSimulation.EPS >= REPAIR_TIME:
		worker.phase = "passenger"
		worker.broken = false
		worker.elapsed = 0.0
		_event(model, "crane_fixed", index, worker_position(model, index))
		return false
	return true


func crane_exited(index: int) -> void:
	var worker := workers[index]
	worker.phase = "idle"
	worker.broken = false
	worker.id = -1
	worker.elapsed = 0.0
	worker.cycle += 1


func _crane_position(model: StackSimulation, index: int) -> Vector2:
	return Vector2(float(model.cranes[index].x), float(TRACK_Y[index]))


func _visible(model: StackSimulation, x: float, half_width: float) -> bool:
	return x + half_width > -RAIL_MARGIN and x - half_width < model.tuning.columns + RAIL_MARGIN


static func jaw_spread(cue: float, duration: float) -> float:
	if cue <= 0.0 or duration <= 0.0:
		return 0.0
	var opening := 0.55 + (duration - cue) / (duration * 0.25)
	var closing := cue / (duration * 0.35)
	return roundf(7.0 * clampf(minf(opening, closing), 0.0, 1.0))


func _crane_visible(model: StackSimulation, crane: Dictionary) -> bool:
	# The outer fingers extend farther than the trolley and its carried crate.
	var hinge := JAW_HINGE_X + jaw_spread(float(crane.open_time), model.tuning.crane_open_time)
	var x := roundf(float(crane.x) * 24.0)
	var visible_margin := RAIL_MARGIN * 24.0 - END_STOP_WIDTH
	return x + hinge + 3.0 > -visible_margin \
		and x - hinge - 2.0 < model.tuning.columns * 24.0 + visible_margin


func _active_crane(model: StackSimulation, index: int) -> bool:
	return not model.cranes[index].waiting and not workers[index].broken


func _start_worker(model: StackSimulation, index: int) -> void:
	var worker := workers[index]
	worker.phase = "climb"
	worker.broken = true
	worker.id = _next_worker
	_next_worker += 1
	worker.elapsed = 0.0
	worker.x = -RAIL_MARGIN if model.cranes[index].direction > 0 else model.tuning.columns + RAIL_MARGIN


func _advance_shots(model: StackSimulation) -> void:
	var shot_index := 0
	while shot_index < shots.size():
		var shot := shots[shot_index]
		var index := int(shot.crane)
		var worker := workers[index]
		var valid: bool
		if shot.worker:
			valid = worker.phase != "idle" and worker.id == shot.target_code
			if valid:
				shot.to = worker_position(model, index)
		else:
			valid = _active_crane(model, index) and worker.cycle == shot.target_code
			if valid:
				shot.to = _crane_position(model, index)
		shot.elapsed += StackSimulation.STEP
		var t := minf(1.0, float(shot.elapsed) / float(shot.duration))
		shot.position = shot_position(shot, t)
		if t < 1.0:
			shot_index += 1
			continue
		shots.remove_at(shot_index)
		if valid:
			if shot.worker:
				_hit_worker(model, index)
			else:
				_start_worker(model, index)
				_event(model, "crane_break", index, _crane_position(model, index))


func _hit_worker(model: StackSimulation, index: int) -> void:
	var worker := workers[index]
	var at := worker_position(model, index)
	fallen.append({"position": at, "vy": 0.0, "crane": index})
	_event(model, "mechanic_hit", index, at)
	if worker.broken:
		_start_worker(model, index)
	else:
		worker.phase = "idle"
		worker.id = -1


func _advance_falls(model: StackSimulation) -> void:
	var index := 0
	while index < fallen.size():
		var worker := fallen[index]
		var at: Vector2 = worker.position
		worker.vy = minf(float(worker.vy) + model.tuning.gravity * StackSimulation.STEP, FALL_SPEED)
		var end_y := at.y + float(worker.vy) * StackSimulation.STEP
		var end_bottom := end_y + FALL_HALF_HEIGHT
		var contact_y := float(model.tuning.rows)
		var contact := "floor"
		var crate_hit := {}
		if _intersects_fall(at, end_bottom, model.player, model.tuning.player_width,
				model.tuning.player_height, 0.04):
			contact_y = model.player.y
			contact = "player"
		for crate in model.crates:
			var corner := Vector2(float(crate.x), float(crate.y))
			if corner.y <= contact_y and _intersects_fall(at, end_bottom, corner, 1.0, 1.0):
				contact_y = corner.y
				contact = str(crate.get("material", "wood"))
				crate_hit = crate
		if end_bottom < contact_y:
			worker.position = Vector2(at.x, end_y)
			index += 1
			continue
		fallen.remove_at(index)
		_event(model, "mechanic_land", int(worker.crane), Vector2(at.x, contact_y), contact)
		if contact == "wood":
			model._destroy_crate(crate_hit)
		elif contact == "player":
			model.hit_by_mechanic()
			if model.state == "over":
				return


func _intersects_fall(at: Vector2, end_bottom: float, corner: Vector2,
		width: float, height: float, margin: float = 0.0) -> bool:
	return at.x + FALL_HALF_WIDTH > corner.x + margin \
		and at.x - FALL_HALF_WIDTH < corner.x + width - margin \
		and at.y - FALL_HALF_HEIGHT < corner.y + height \
		and end_bottom >= corner.y


func _event(model: StackSimulation, type: String, index: int, at: Vector2, contact: String = "") -> void:
	model.events.append({"type": type, "crane": index, "position": at, "contact": contact})
