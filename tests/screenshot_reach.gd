extends SceneTree

## Saves a screenshot of the fighter reaching with both hands (IK and overlay).
##   godot --path . --script res://tests/screenshot_reach.gd -- <out_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.player.fighter = null
	var f: Fighter = main.fighter
	await _wait(1.0)
	main.dev.start_drill()
	var targets := PlayerInput.hand_targets(f, Vector2(0.15, 0.05), 0.5, FighterIntent.RIGHT)
	for i in 2:
		f.intent.hand_target[i] = targets[i]
		f.intent.hand_active[i] = true
	f.intent.grip[FighterIntent.RIGHT] = true
	await _wait(1.5)
	await _shot(out + "/reaching.png")
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
