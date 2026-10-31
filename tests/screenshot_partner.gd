extends SceneTree

## Saves screenshots of the training partner: the dummy, then the sparring AI.
##   godot --path . --script res://tests/screenshot_partner.gd -- <out_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cam.yaw_offset = PI / 2.0
	await _wait(2.0)
	await _shot(out + "/partner_dummy.png")
	main.partner.set_mode(PartnerAI.Mode.SPAR)
	for n in 4:
		await _wait(1.5)
		await _shot(out + "/partner_spar_%d.png" % n)
	quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
