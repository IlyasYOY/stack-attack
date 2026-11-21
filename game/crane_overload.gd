class_name StackCraneOverload
extends RefCounted
## One schedule for both rails, in seconds of the simulation's playing clock.
enum Phase { NORMAL, WARNING, ACTIVE, FADING }

const WARNING_TIME := 1.5
const FADE_TIME := 0.5
var phase := Phase.NORMAL
var phase_end := 0.0
var _next_warning := 0.0
var _rng := RandomNumberGenerator.new()


func reset(seed_value: int) -> void:
	_rng.seed = seed_value ^ 0x4c9f73
	phase = Phase.NORMAL
	_next_warning = _rng.randf_range(30.0, 60.0)
	phase_end = _next_warning


func advance(now: float) -> void:
	if now < phase_end:
		return
	match phase:
		Phase.NORMAL:
			phase = Phase.WARNING
			phase_end += WARNING_TIME
		Phase.WARNING:
			phase = Phase.ACTIVE
			phase_end += _rng.randf_range(8.0, 12.0)
		Phase.ACTIVE:
			# The fading sparks share the first half-second of the new interval.
			_next_warning = phase_end + _rng.randf_range(30.0, 60.0)
			phase = Phase.FADING
			phase_end += FADE_TIME
		Phase.FADING:
			phase = Phase.NORMAL
			phase_end = _next_warning


func rate() -> float:
	return 2.0 if phase == Phase.ACTIVE else 1.0
