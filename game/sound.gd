class_name StackSound
extends Node
const SLIDE_FADE_SECONDS := 0.03

var profile: StackProfile
var music_player: AudioStreamPlayer
var slide_player: AudioStreamPlayer
var effects_players: Array[AudioStreamPlayer] = []
var unlocked := false
var sounds := {}
var _slide_gain := 0.0


func setup(settings: StackProfile) -> void:
	profile = settings
	for bus in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	var track: AudioStreamWAV = load("res://audio/night_shift.wav")
	music_player.stream = track
	add_child(music_player)
	for index in range(6):
		var player := AudioStreamPlayer.new()
		player.bus = "Effects"
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		effects_players.append(player)
	for name in ["click", "jump", "land", "line", "over", "crush", "helmet_hit", "helmet_break",
		"gloves_tear", "mallet_swing", "mallet_hit", "mallet_break",
		"spring_jump", "spring_jump_auto", "lamp_reveal", "lamp_break"]:
		sounds[name] = load("res://audio/" + name + ".wav")
	slide_player = AudioStreamPlayer.new()
	slide_player.bus = "Effects"
	slide_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	slide_player.stream = preload("res://audio/crate_slide.wav")
	add_child(slide_player)
	apply_volumes()


func unlock() -> void:
	if not unlocked:
		unlocked = true
		music_player.play()


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.0001, profile.music)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), profile.music <= 0.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), linear_to_db(maxf(0.0001, profile.effects)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Effects"), profile.effects <= 0.0)


func effect(name: String, haptics: bool = true) -> void:
	if not sounds.has(name) or not unlocked:
		return
	_play_effect(name)
	if haptics and _supports_haptics() and profile.vibration:
		if name == "line":
			_vibrate(40)
		elif name in ["over", "crush"]:
			_vibrate(90)
		elif name in ["jump", "spring_jump", "spring_jump_auto"]:
			_vibrate(12)


func loss(reason: String, haptics: bool = true) -> void:
	effect("crush" if reason == "crushed" else "over", haptics)


func _play_effect(name: String) -> void:
	for player in effects_players:
		if not player.playing:
			player.stream = sounds[name]
			player.play()
			return
	# A fatal impact must still be audible during a busy chain reaction.
	if name == "crush":
		effects_players[0].stream = sounds[name]
		effects_players[0].play()


func set_slide_active(active: bool, delta: float) -> void:
	if active and unlocked:
		if not slide_player.playing:
			slide_player.volume_db = -80.0
			slide_player.play()
			return
		_slide_gain = move_toward(_slide_gain, 1.0, delta / SLIDE_FADE_SECONDS)
	elif slide_player.playing:
		_slide_gain = move_toward(_slide_gain, 0.0, delta / SLIDE_FADE_SECONDS)
		if _slide_gain == 0.0:
			stop_slide()
			return
	else:
		return
	slide_player.volume_db = linear_to_db(maxf(0.0001, _slide_gain))


func stop_slide() -> void:
	_slide_gain = 0.0
	slide_player.stop()


func _supports_haptics() -> bool:
	return OS.has_feature("android")


func _vibrate(duration: int) -> void:
	Input.vibrate_handheld(duration)


func preview_vibration() -> void:
	if _supports_haptics() and profile.vibration:
		_vibrate(60)


func _exit_tree() -> void:
	if is_instance_valid(music_player):
		music_player.stop()
	if is_instance_valid(slide_player):
		stop_slide()
	for player in effects_players:
		if is_instance_valid(player):
			player.stop()
