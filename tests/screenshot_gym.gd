extends SceneTree

## Saves an overview of each gym variant from the match scene.
##   godot --path . --script res://tests/screenshot_gym.gd -- <out_dir>

const VIEWS := [
	[Vector3(6.5, 2.8, 6.0), Vector3(-1, 0.8, -1.5)],
	[Vector3(4.6, 2.2, 4.2), Vector3(-1.5, 0.7, -1.5)],
	[Vector3(9.0, 5.5, 11.0), Vector3(-1, 0.5, -1)],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var m: Node3D = load("res://scenes/match.tscn").instantiate()
	root.add_child(m)
	m.set_process(false)
	m.arena.remember_choice = false
	for v in 3:
		m.arena.variant = v
		await _wait(1.0)
		m.cam.global_position = VIEWS[v][0]
		m.cam.look_at(VIEWS[v][1])
		await _shot(out + "/gym_%d.png" % v)
	m.arena.variant = 2
	m.cam.global_position = Vector3(-12.5, 3.2, 6.0)
	m.cam.look_at(Vector3(2, 0.6, -1))
	m.fighters[0].shove(Vector3(0, 0, -220))
	await _wait(1.2)
	await _shot(out + "/gym_hall_side.png")
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
