class_name StackSound
extends Node
var profile: StackProfile
var music_player: AudioStreamPlayer
var effects_players: Array[AudioStreamPlayer] = []
var unlocked := false
var sounds := {}


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
	for name in ["click", "jump", "land", "line", "over", "helmet_hit", "helmet_break",
		"gloves_pull", "gloves_tear"]:
		sounds[name] = load("res://audio/" + name + ".wav")
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
		elif name == "over":
			_vibrate(90)
		elif name == "jump":
			_vibrate(12)


func _play_effect(name: String) -> void:
	for player in effects_players:
		if not player.playing:
			player.stream = sounds[name]
			player.play()
			break


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
	for player in effects_players:
		if is_instance_valid(player):
			player.stop()
