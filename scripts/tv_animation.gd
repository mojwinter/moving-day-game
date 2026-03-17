extends AnimatedSprite2D
## Cycles through all TV channel animations.
## Each channel plays its full loop once, then switches to the next.

var _channels: Array[StringName] = []
var _current_index: int = 0
var _loops_played: int = 0
const LOOPS_PER_CHANNEL := 1
@export var speed_scale_override := 0.7
@export var static_speed_scale := 0.4


func _ready() -> void:
	var sf := sprite_frames
	if sf == null:
		return
	var _skip := [&"weather_cloudy", &"weather_rain", &"weather_snow", &"weather_thunder", &"static"]
	for i in sf.get_animation_names():
		if i != &"default" and i not in _skip:
			_channels.append(i)
	_channels.sort()
	if _channels.is_empty():
		return
	speed_scale = speed_scale_override
	animation_looped.connect(_on_loop)
	_play_current()


var _playing_static: bool = false


func _play_current() -> void:
	_loops_played = 0
	if _playing_static:
		_playing_static = false
		speed_scale = speed_scale_override
		play(_channels[_current_index])
	else:
		_playing_static = true
		speed_scale = static_speed_scale
		play(&"static")


func _on_loop() -> void:
	_loops_played += 1
	if _loops_played >= LOOPS_PER_CHANNEL:
		_current_index = (_current_index + 1) % _channels.size()
		_play_current()
