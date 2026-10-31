extends Node3D

## Test arena. Player controls live in PlayerInput, test keys in DevKeys.

var fighter: Fighter
var player: PlayerInput
var dev: DevKeys
var overlay: DebugOverlay
var hud: Label
var cam: CameraRig


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

	cam = CameraRig.new()
	cam.name = "Camera"
	add_child(cam)

	overlay = DebugOverlay.new()
	add_child(overlay)

	player = PlayerInput.new()
	player.name = "PlayerInput"
	player.camera = cam
	add_child(player)

	dev = DevKeys.new()
	dev.name = "DevKeys"
	dev.camera = cam
	dev.reset_requested.connect(_spawn_fighter)
	add_child(dev)

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
	player.fighter = fighter
	dev.fighter = fighter
	dev.clear_drill()
	cam.target = fighter
	cam.snap()


func _process(_delta: float) -> void:
	if fighter and fighter.parts.has("pelvis"):
		var it := fighter.intent
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var arms := player.controlled()
		hud.text = "%s\nhold left / right mouse + move: move that arm (both buttons: both arms)   + wheel: reach\nno button: mouse turns the camera, wheel zooms   Q/E turn   WASD weight   Ctrl tense   Tab swap lead   Shift hips   Space legs\nF shove   G big shove   R reset   M reach drill   Esc free mouse\n\nmoving %s   weight (%.1f, %.1f)   base margin %.2f m   assist %.0f%%   tension %.1f   %s" % [
			"" if captured else ">>> click the window to take the mouse <<<",
			("both arms" if arms[0] and arms[1] else "left arm" if arms[0] else "right arm" if arms[1] else "camera"),
			it.weight_shift.x, it.weight_shift.y,
			fighter.base_margin, fighter.assist * 100.0, fighter.tension, dev.drill_status()]
