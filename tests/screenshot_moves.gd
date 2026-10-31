extends SceneTree

## Saves screenshots of the fundamental moves (needs a window, not --headless):
##   godot --path . --script res://tests/screenshot_moves.gd -- <out_dir>

var main: Node3D
var out := "user://"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.partner.remove()
	main.player.set_physics_process(false)
	main.pad.set_physics_process(false)
	var f: Fighter = main.fighter
	var cam: CameraRig = main.cam
	cam.yaw_offset = PI / 2.0
	await _wait(1.0)
	f.intent.move = Vector2(0, -1)
	await _wait(0.9)
	await _shot("move_walk")
	f.intent.move = Vector2.ZERO
	await _wait(1.0)
	var hb := f.heading_basis()
	var chest: Vector3 = f.parts.chest.global_position
	for i in 2:
		f.intent.hand_active[i] = true
		f.intent.hand_target[i] = chest + hb * Vector3(0.45, -0.1, -0.3)
	await _wait(1.0)
	await _shot("move_throw_swing")
	for i in 2:
		f.intent.hand_target[i] = chest + hb * Vector3(0.15 * (i * 2 - 1), -0.15, -0.1)
	await _wait(1.0)
	await _shot("move_pull")
	for i in 2:
		f.intent.hand_active[i] = false
	f.intent.crouch = 1.0
	await _wait(2.5)
	f.intent.crouch = 0.0
	await _shot("move_sitting")
	f.intent.upper = Vector2(0, -1)
	await _wait(2.0)
	f.intent.upper = Vector2.ZERO
	await _wait(0.5)
	f.intent.hips = Vector2(0, -1)
	await _wait(1.0)
	await _shot("move_bridge")
	f.intent.hips = Vector2.ZERO
	await _wait(1.0)
	f.intent.upper = Vector2(-1, 0)
	await _wait(1.0)
	await _shot("move_shrimp")
	f.intent.upper = Vector2(0, 1)
	await _wait(1.5)
	await _shot("move_sit_up")
	f.intent.hips = Vector2(0, -1)
	await _wait(0.8)
	await _shot("move_standing_up")
	await _wait(2.0)
	f.intent.upper = Vector2.ZERO
	f.intent.hips = Vector2.ZERO
	await _wait(1.0)
	await _shot("move_back_up")
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out + "/" + name + ".png"
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, "  ", main.fighter.moves.move_name)
