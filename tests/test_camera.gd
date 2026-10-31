extends SceneTree

## Camera steadiness: lying on the ground working the hips and legs (bridges,
## hip swings, shrimps: limbs bumping the floor) must not shake the
## third-person camera.

var failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var f: Fighter = main.fighter
	var cam: CameraRig = main.cam
	var pad: PadInput = main.pad
	main.player.set_physics_process(false)
	pad.set_physics_process(false)
	cam.first_person = false
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in 60:
		await physics_frame
	f.shove(Vector3(0, 0, 220))
	var no_hands: Array[bool] = [false, false]
	for k in 360:
		pad.drive(Vector2.ZERO, Vector2.ZERO, no_hands, false, false, dt)
		await physics_frame
	# Work the legs for 4 s and watch how much the camera turns from frame to frame.
	var prev := cam.global_basis
	var prev_pos := cam.global_position
	var prev_w := Vector3.ZERO
	var prev_v := Vector3.ZERO
	var worst := 0.0
	var total := 0.0
	var moved := 0.0
	var n := 0
	for rep in 4:
		for s in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
			for k in 30:
				pad.drive(s, Vector2(-s.x, 0) * 0.5, no_hands, false, false, dt)
				await physics_frame
				await process_frame
				# Shake = how much the camera's turn and travel change from one
				# tick to the next (steady motion is fine).
				var q := prev.get_rotation_quaternion().inverse() * cam.global_basis.get_rotation_quaternion()
				var w := q.get_axis() * rad_to_deg(q.get_angle()) if q.get_angle() > 1e-6 else Vector3.ZERO
				var v := cam.global_position - prev_pos
				var a := (w - prev_w).length() + rad_to_deg((v - prev_v).length() / 2.4)
				prev_w = w
				prev_v = v
				worst = maxf(worst, a)
				total += a * a
				moved += v.length()
				n += 1
				prev = cam.global_basis
				prev_pos = cam.global_position
	var rms := sqrt(total / n)
	_check("camera turns smoothly while the legs bump the ground", worst < 0.5 and rms < 0.1,
		"jitter worst %.3f deg/tick, rms %.3f, travelled %.2f m" % [worst, rms, moved])
	print("FAILURES: ", failures)
	quit(failures)


func _check(label: String, ok: bool, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + label + "  (" + detail + ")")
	if not ok:
		failures += 1
