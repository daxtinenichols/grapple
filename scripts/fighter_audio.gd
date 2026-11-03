class_name FighterAudio
extends Node3D

## Sounds for one fighter, worked out from the ragdoll's motion so nothing in the
## physics has to report contacts: parts that stop falling near the mat slap or
## thud, feet pat, the gi rustles with limb speed, and the fighter grunts when it
## tenses up, lands hard or falls over. Only reads the fighter.
## FighterSkin adds one of these by itself; sounds live in res://audio
## (regenerate them with tools/gen_sounds.py).

## Master volume offset (dB) for this fighter's sounds.
@export var volume_db := 0.0
## Voice pitch; give each fighter a different one.
@export var voice_pitch := 1.0
## Height (m) of the mat surface.
@export var floor_y := 0.0

const SLAP := ["mat_slap_0", "mat_slap_1", "mat_slap_2", "mat_slap_3"]
const THUD := ["body_thud_0", "body_thud_1", "body_thud_2"]
const STEP := ["step_0", "step_1", "step_2", "step_3"]
const GRUNT := ["grunt_0", "grunt_1", "grunt_2", "grunt_3", "grunt_4"]
const OOF := ["oof_0", "oof_1", "oof_2"]
const EXHALE := ["exhale_0", "exhale_1", "exhale_2"]
## Part kinds that thud (big and heavy) rather than slap.
const HEAVY := ["pelvis", "abdomen", "chest", "head"]

var fighter: Fighter
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0
var _rustle: AudioStreamPlayer3D
var _prev_vy := {}
var _cooldown := {}
var _voice_cooldown := 0.0
var _last_tension := 0.0
var _rng := RandomNumberGenerator.new()

static var _streams := {}


static func stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var s: AudioStream = load("res://audio/%s.wav" % sound)
		if s is AudioStreamWAV and sound.ends_with("_loop"):
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		_streams[sound] = s
	return _streams[sound]


func attach(f: Fighter) -> void:
	fighter = f
	_rng.randomize()
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 30.0
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	_rustle = AudioStreamPlayer3D.new()
	_rustle.stream = stream("gi_rustle_loop")
	_rustle.unit_size = 3.0
	_rustle.volume_db = -60.0
	add_child(_rustle)
	_rustle.play()
	if f.has_signal("fell"):
		f.fell.connect(_on_fell)


## Plays a one-shot at a world position. `sound` may be a name or a list to pick from.
func play(sound, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	if _players.is_empty():
		return
	var s: String = sound if sound is String else sound[_rng.randi() % sound.size()]
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream(s)
	p.global_position = at
	p.volume_db = volume_db + db
	p.pitch_scale = pitch * _rng.randf_range(0.93, 1.07)
	p.play()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(fighter) or not fighter.is_inside_tree():
		return
	_voice_cooldown = maxf(_voice_cooldown - delta, 0.0)
	var limb_speed := 0.0
	var chest: RigidBody3D = fighter.parts.get("chest")
	for part_name in fighter.parts:
		var body: RigidBody3D = fighter.parts[part_name]
		var vy := body.linear_velocity.y
		var prev: float = _prev_vy.get(part_name, vy)
		_prev_vy[part_name] = vy
		_cooldown[part_name] = maxf(_cooldown.get(part_name, 0.0) - delta, 0.0)
		var kind: String = part_name.trim_prefix("l_").trim_prefix("r_")
		# Landing: was falling, suddenly isn't, and is down at the mat.
		var near := body.global_position.y - floor_y < (0.22 if kind in HEAVY else 0.14)
		if near and prev < -0.9 and vy > prev * 0.35 and _cooldown[part_name] == 0.0:
			_land(kind, body.global_position, -prev)
			_cooldown[part_name] = 0.15
		if chest and kind in ["forearm", "hand", "shin", "foot", "upper_arm", "thigh"]:
			limb_speed += (body.linear_velocity - chest.linear_velocity).length()
	# Gi rustle follows how fast the limbs move against the chest.
	var want := clampf(limb_speed / 14.0, 0.0, 1.0)
	_rustle.volume_db = lerpf(_rustle.volume_db, volume_db + (linear_to_db(want) if want > 0.02 else -60.0), 0.15)
	if chest:
		_rustle.global_position = chest.global_position
	# Tensing up gets a breathy effort sound.
	var tension := 0.0
	if "intent" in fighter and fighter.intent:
		tension = fighter.intent.tension
	if tension > 0.6 and _last_tension <= 0.6 and _voice_cooldown == 0.0:
		_voice(EXHALE if _rng.randf() < 0.6 else GRUNT, -4.0)
	_last_tension = tension


func _land(kind: String, at: Vector3, speed: float) -> void:
	var loud := clampf((speed - 0.9) / 4.0, 0.0, 1.0)
	var db := lerpf(-18.0, 0.0, loud)
	if kind in HEAVY:
		play(THUD, at, db, 1.0 - loud * 0.1)
		if loud > 0.45 and _voice_cooldown == 0.0:
			_voice(OOF, 0.0)
	elif kind == "foot":
		play(STEP, at, db - 6.0)
	else:
		play(SLAP, at, db)


func _voice(sounds: Array, db: float) -> void:
	var head: RigidBody3D = fighter.parts.get("head")
	if head:
		play(sounds, head.global_position, db, voice_pitch)
		_voice_cooldown = 1.6


func _on_fell() -> void:
	_voice_cooldown = 0.0
	_voice(["yelp"] if _rng.randf() < 0.5 else GRUNT, 0.0)
