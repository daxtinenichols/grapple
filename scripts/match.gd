extends Node3D

## Match scene: the competition mat with two skinned fighters facing each other.
## Leaving the combat area resets both fighters to their spawn points.
## Dev keys: F small shove, G big shove (on fighter A, away from the camera),
## R reset, K skin / plain ragdoll, J / L orbit the camera.
## The J / L camera is a debug viewer; the main camera comes from movement.

const SHOVE := 60.0
const BIG_SHOVE := 220.0
const GI := [Color(0.95, 0.94, 0.9), Color(0.16, 0.3, 0.68)]
const BELTS := [Color(0.38, 0.2, 0.58), Color(0.42, 0.25, 0.12)]
const SKINS := [Color(0.87, 0.65, 0.5), Color(0.55, 0.37, 0.25)]
const HAIR := [Color(0.2, 0.13, 0.08), Color(0.08, 0.06, 0.05)]

@onready var arena: Arena = $Arena
@onready var cam: Camera3D = $Camera
@onready var hud: Label = $HUD/Label

var fighters: Array[Fighter] = []
var skins: Array[FighterSkin] = []
var cam_yaw := 1.15
var show_ragdoll := false
var _notice := ""
var _notice_time := 0.0


func _ready() -> void:
	arena.fighter_left_mat.connect(_on_left_mat)
	spawn_fighters()


func spawn_fighters() -> void:
	arena.clear_watch()
	for f in fighters:
		if is_instance_valid(f):
			f.queue_free()
	fighters.clear()
	skins.clear()
	for i in 2:
		var f := Fighter.new()
		f.name = "Fighter" + "AB"[i]
		f.transform = arena.spawn_transform(i)
		add_child(f)
		fighters.append(f)
		arena.watch(f)
		var skin := FighterSkin.new()
		skin.name = "Skin" + "AB"[i]
		skin.gi_color = GI[i]
		skin.belt_color = BELTS[i]
		skin.skin_tone = SKINS[i]
		skin.hair_color = HAIR[i]
		skin.head_layer = 19 + i
		add_child(skin)
		skin.attach(f)
		skin.show_ragdoll = show_ragdoll
		skins.append(skin)


func _on_left_mat(f: Fighter) -> void:
	_notice = "%s left the mat: reset to center" % f.name
	_notice_time = 2.0
	spawn_fighters.call_deferred()


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset"):
		spawn_fighters()
		return
	if fighters.is_empty() or not is_instance_valid(fighters[0]):
		return
	if Input.is_action_just_pressed("shove"):
		fighters[0].shove(_shove_dir() * SHOVE)
	if Input.is_action_just_pressed("big_shove"):
		fighters[0].shove(_shove_dir() * BIG_SHOVE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_K:
		show_ragdoll = not show_ragdoll
		for s in skins:
			if is_instance_valid(s):
				s.show_ragdoll = show_ragdoll


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_J):
		cam_yaw -= delta * 1.5
	if Input.is_key_pressed(KEY_L):
		cam_yaw += delta * 1.5
	var focus := Vector3(0, 0.9, 0)
	var n := 0
	var sum := Vector3.ZERO
	for f in fighters:
		if is_instance_valid(f) and f.parts.has("pelvis"):
			sum += f.parts.pelvis.global_position
			n += 1
	if n > 0:
		focus = sum / n
		focus.y = 0.85
	cam.global_position = focus + Vector3(sin(cam_yaw), 0.42, cos(cam_yaw)) * 4.2
	cam.look_at(focus)
	_notice_time = maxf(_notice_time - delta, 0.0)
	hud.text = "F shove   G big shove   R reset   K skin / ragdoll   J/L orbit\n%s" % (_notice if _notice_time > 0.0 else "")


func _shove_dir() -> Vector3:
	var d := -cam.global_basis.z
	d.y = 0.0
	return d.normalized()
