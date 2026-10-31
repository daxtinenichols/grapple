extends Node3D

## Test arena. Player controls live in PlayerInput, test keys in DevKeys.

var fighter: Fighter
var player: PlayerInput
var dev: DevKeys
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

	player = PlayerInput.new()
	player.name = "PlayerInput"
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
		var it := fighter.intent
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		hud.text = "%s\nmouse hands   wheel reach   L/R button close hand   Q/E turn   WASD weight   Ctrl tense   Tab swap lead   Shift hips   Space legs\nF shove   G big shove   R reset   M reach drill   J/L orbit camera   Esc free mouse\n\nfocus %s   lead %s   reach %.2f m   grips %s %s   weight (%.1f, %.1f)\nbase margin %.2f m   assist %.0f%%   tension %.1f   %s" % [
			"" if captured else ">>> click the window to take the mouse <<<",
			FighterIntent.Focus.keys()[it.focus].to_lower(), "left" if it.lead == FighterIntent.LEFT else "right",
			player.reach, "L" if it.grip[0] else "-", "R" if it.grip[1] else "-",
			it.weight_shift.x, it.weight_shift.y,
			fighter.base_margin, fighter.assist * 100.0, fighter.tension, dev.drill_status()]
