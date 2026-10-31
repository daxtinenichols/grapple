extends SceneTree

## Saves a lineup of every FighterSkin look in the academy.
##   godot --path . --script res://tests/screenshot_looks.gd -- <out_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var gym: Gym = load("res://scenes/gym.tscn").instantiate()
	gym.remember_choice = false
	root.add_child(gym)
	gym.variant = Gym.Variant.ACADEMY
	var names := FighterSkin.LOOKS.keys()
	for i in names.size():
		var f := Fighter.new()
		f.transform = Transform3D(Basis.IDENTITY, Vector3((i - (names.size() - 1) * 0.5) * 0.9, 0, 0))
		root.add_child(f)
		var s := FighterSkin.new()
		s.apply_look(names[i])
		s.with_sound = false
		root.add_child(s)
		s.attach(f)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0, 1.3, -3.6)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.fov = 50
	await _wait(1.5)
	await _shot(out + "/looks.png")
	cam.global_position = Vector3(0.45, 1.6, -1.3)
	cam.look_at(Vector3(0.45, 1.45, 0))
	await _shot(out + "/looks_face.png")
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
