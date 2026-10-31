extends SceneTree

## Saves screenshots of the arena: standing, then mid-fall after a big shove.
##   godot --path . --script res://tests/screenshot.gd -- <out_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(2.0)
	await _shot(out + "/standing.png")
	main.fighter.shove(Vector3(-0.6, 0, -0.8) * 220.0)
	await _wait(0.6)
	await _shot(out + "/falling.png")
	await _wait(3.0)
	await _shot(out + "/down.png")
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
