extends SceneTree

## Saves screenshots of the match scene: both fighters standing, a close-up,
## the plain ragdoll for comparison, and fighter A falling after a big shove.
##   godot --path . --script res://tests/screenshot_match.gd -- <out_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var m: Node3D = load("res://scenes/match.tscn").instantiate()
	root.add_child(m)
	await _wait(2.0)
	await _shot(out + "/match.png")
	m.cam_yaw = 0.35
	m.set_process(false)
	var focus: Vector3 = m.fighters[0].parts.head.global_position
	m.cam.global_position = focus + Vector3(0.55, -0.05, -1.2)
	m.cam.look_at(focus + Vector3(0, -0.35, 0))
	await _shot(out + "/closeup.png")
	m.set_process(true)
	m.cam_yaw = 1.15
	for s in m.skins:
		s.show_ragdoll = true
	await _wait(0.1)
	await _shot(out + "/ragdoll.png")
	for s in m.skins:
		s.show_ragdoll = false
	m.fighters[0].shove(Vector3(-0.9, 0, -0.4) * 220.0)
	await _wait(0.5)
	await _shot(out + "/match_falling.png")
	await _wait(2.5)
	await _shot(out + "/match_down.png")
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
