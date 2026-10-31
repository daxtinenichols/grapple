extends SceneTree

## Saves overview screenshots of the gym from two corners.
##   godot --path . --script res://tests/screenshot_gym.gd -- <out_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var m: Node3D = load("res://scenes/match.tscn").instantiate()
	root.add_child(m)
	m.set_process(false)
	await _wait(1.5)
	m.cam.global_position = Vector3(6.5, 2.8, 6.0)
	m.cam.look_at(Vector3(-1, 0.8, -1.5))
	await _shot(out + "/gym.png")
	m.cam.global_position = Vector3(-6.5, 2.6, -5.5)
	m.cam.look_at(Vector3(1.5, 0.8, 1.5))
	await _shot(out + "/gym_back.png")
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
