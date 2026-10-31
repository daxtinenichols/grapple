extends Node3D

## Test arena for the standing ragdoll milestone.
## F: shove, G: big shove, R: reset, hold Ctrl: tense up.

const SHOVE := 60.0
const BIG_SHOVE := 220.0

var fighter: Fighter
var overlay: DebugOverlay
var hud: Label
var cam: Camera3D
var cam_yaw := 0.6


func _ready() -> void:
	_build_world()
	_spawn_fighter()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var mat := StaticBody3D.new()
	mat.name = "Mat"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 1, 12)
	shape.shape = box
	shape.position.y = -0.5
	mat.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(12, 0.1, 12)
	mesh.mesh = bm
	mesh.position.y = -0.05
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.2, 0.42, 0.62)
	mesh.material_override = mm
	mat.add_child(mesh)
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	mat.physics_material_override = pm
	add_child(mat)

	cam = Camera3D.new()
	add_child(cam)

	overlay = DebugOverlay.new()
	add_child(overlay)

	hud = Label.new()
	hud.position = Vector2(16, 12)
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)


func _spawn_fighter() -> void:
	if fighter:
		fighter.queue_free()
	fighter = Fighter.new()
	fighter.name = "Fighter"
	add_child(fighter)
	overlay.fighter = fighter


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset"):
		_spawn_fighter()
		return
	fighter.tension = 1.8 if Input.is_action_pressed("tense") else 1.0
	if Input.is_action_just_pressed("shove"):
		fighter.shove(_shove_dir() * SHOVE)
	if Input.is_action_just_pressed("big_shove"):
		fighter.shove(_shove_dir() * BIG_SHOVE)


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_J):
		cam_yaw -= delta * 1.5
	if Input.is_key_pressed(KEY_L):
		cam_yaw += delta * 1.5
	if fighter and fighter.parts.has("pelvis"):
		var focus: Vector3 = fighter.parts.pelvis.global_position
		focus.y = 0.9
		cam.global_position = focus + Vector3(sin(cam_yaw), 0.35, cos(cam_yaw)) * 3.2
		cam.look_at(focus)
		hud.text = "F shove   G big shove   R reset   hold Ctrl tense   J/L orbit\nbase margin %.2f m   assist %.0f%%   tension %.1f" % [
			fighter.base_margin, fighter.assist * 100.0, fighter.tension]


## Push away from the camera so the shove is easy to read.
func _shove_dir() -> Vector3:
	var d := -cam.global_basis.z
	d.y = 0.0
	return d.normalized()
