extends SceneTree

## Headless checks for the intent, hand IK and the controls:
##   godot --headless --path . --script res://tests/test_controls.gd
## 1. Fighter never reads Input, 2. tension comes through the intent,
## 3. Q/E turn twists the chest, 4. the hands touch three drill balls in a row
## without the fighter falling, 5. mouse buttons pick which arm the mouse moves,
## 6. the arms stay calm while holding a guard, 7. the right stick moves both
## hands or (with a bumper) one, 8. the left stick walks, 9. grips work standing
## and on the mat, 10. B lowers you and sits you down, 11. on the mat the sticks
## drive the hips and chest, and sit up + hips up stands you, 12. you keep
## facing the partner. The moves themselves are in test_moves.gd.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/fighter.gd")
	var reads_input := RegEx.create_from_string("\\bInput\\.").search(src) != null
	_check("fighter.gd never reads Input", not reads_input, "")

	var main := await _fresh()
	var f: Fighter = main.fighter
	# Drive the intent directly; keep PlayerInput from overwriting it.
	var p: PlayerInput = main.player
	p.fighter = null
	await _wait(1.0)
	f.intent.tension = 1.0
	await _wait(0.1)
	_check("tension through intent", is_equal_approx(f.tension, f.max_tension), "tension %.2f" % f.tension)
	f.intent.tension = 0.0

	var yaw0 := _chest_yaw(f)
	f.intent.turn = 1.0
	await _wait(1.5)
	var turned := rad_to_deg(angle_difference(yaw0, _chest_yaw(f)))
	_check("E turns the shoulders right", turned < -15.0, "chest yaw %.1f deg" % turned)
	f.intent.turn = 0.0
	await _wait(1.5)

	# Reach drill: touch each ball with the nearest hand, in order.
	var dev: DevKeys = main.dev
	dev.start_drill()
	for n in dev.drill_balls.size():
		var ball: Vector3 = dev.drill_balls[n].global_position
		var hb := f.heading_basis()
		var hand := FighterIntent.LEFT if (hb.inverse() * (ball - f.parts.chest.global_position)).x < 0.0 else FighterIntent.RIGHT
		f.intent.hand_target[hand] = ball
		f.intent.hand_active[hand] = true
		var t := 0.0
		while dev.drill_hit <= n and t < 3.0:
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
		var name := "l_hand" if hand == FighterIntent.LEFT else "r_hand"
		_check("hand touches ball %d" % (n + 1), dev.drill_hit > n,
			"%.2f s, %.3f m off" % [t, f.parts[name].global_position.distance_to(ball)])
		f.intent.hand_active[hand] = false
	await _wait(1.0)
	_check("still standing after the drill", f.parts.head.global_position.y > 1.5 and not f.has_fallen,
		"head y %.2f" % f.parts.head.global_position.y)

	# Arms held out in a guard must not buzz (the build pose once made them shake).
	var guard := PlayerInput.hand_targets(f, f.parts.chest.global_position, PlayerInput.GUARD)
	for i in 2:
		f.intent.hand_target[i] = guard[i]
		f.intent.hand_active[i] = true
	await _wait(1.5)
	var hv := 0.0
	var n := 0
	for k in 240:
		await physics_frame
		hv += f.parts.l_hand.linear_velocity.length_squared() + f.parts.r_hand.linear_velocity.length_squared()
		n += 2
	_check("hands steady in guard", sqrt(hv / n) < 0.35, "hand speed rms %.2f m/s" % sqrt(hv / n))

	# PlayerInput: with only the right button held, moving the mouse right on
	# screen moves the right hand right (camera behind the fighter) and leaves the left alone.
	p.fighter = f
	main.cam.yaw_offset = 0.0
	main.cam.snap()
	await process_frame
	await process_frame
	var l0 := p.hand_offset[FighterIntent.LEFT]
	var r0 := p.hand_offset[FighterIntent.RIGHT]
	p.move_hands([false, true], Vector2(100, 0))
	var dx := p.hand_offset[FighterIntent.RIGHT].x - r0.x
	_check("right button + mouse right moves the right hand right", dx > 0.15, "moved %.2f m" % dx)
	_check("left hand stays put", p.hand_offset[FighterIntent.LEFT] == l0, "")
	p.move_hands([true, true], Vector2(0, -100))
	_check("both buttons + mouse up raise both hands",
		p.hand_offset[0].y > l0.y + 0.15 and p.hand_offset[1].y > r0.y + 0.15, "")

	# Controller, standing: the right stick moves both hands; a bumper picks one.
	p.fighter = null
	var pad: PadInput = main.pad
	pad.set_physics_process(false)
	pad.fighter = f
	var dt := 1.0 / Engine.physics_ticks_per_second
	var none: Array[bool] = [false, false]
	var rb: Array[bool] = [false, true]
	var lb: Array[bool] = [true, false]
	for k in 240:
		pad.drive(Vector2.ZERO, Vector2.ZERO, none, false, false, dt)
		await physics_frame
	var pel0: Vector3 = f.parts.pelvis.global_position
	var hl0 := _hand_local(f, "l_hand")
	var hr0 := _hand_local(f, "r_hand")
	for k in 60:
		pad.drive(Vector2.ZERO, Vector2(1, 0), none, false, false, dt)
		await physics_frame
	var lm := _hand_local(f, "l_hand").x - hl0.x
	var rm := _hand_local(f, "r_hand").x - hr0.x
	_check("right stick right moves both hands right", lm > 0.15 and rm > 0.15, "left %.2f m, right %.2f m" % [lm, rm])
	for k in 120:
		pad.drive(Vector2.ZERO, Vector2.ZERO, none, false, true if k == 0 else false, dt)
		await physics_frame
	hl0 = _hand_local(f, "l_hand")
	hr0 = _hand_local(f, "r_hand")
	for k in 60:
		pad.drive(Vector2.ZERO, Vector2(0, 1), rb, false, false, dt)
		await physics_frame
	var r_fwd := hr0.z - _hand_local(f, "r_hand").z
	var l_fwd := hl0.z - _hand_local(f, "l_hand").z
	_check("RB + right stick up pushes only the right hand out", r_fwd > 0.12 and absf(l_fwd) < 0.06, "right %.2f m, left %.2f m" % [r_fwd, l_fwd])
	for k in 120:
		pad.drive(Vector2.ZERO, Vector2.ZERO, none, false, false, dt)
		await physics_frame
	var kept := hr0.z - _hand_local(f, "r_hand").z
	_check("hand stays where it was moved", kept > r_fwd * 0.6, "%.2f m out 1 s later" % kept)
	var drift: float = _flat(f.parts.pelvis.global_position - pel0).length()
	_check("moving the hands doesn't walk the body away", drift < 0.15 and not f.has_fallen, "pelvis moved %.3f m" % drift)

	# Left stick walks, relative to the camera.
	main.cam.yaw_offset = 0.0
	main.cam.snap()
	await process_frame
	var w0: Vector3 = f.parts.pelvis.global_position
	var cam_fwd: Vector3 = -main.cam.global_basis.z
	cam_fwd.y = 0.0
	for k in 240:
		pad.drive(Vector2(0, 1), Vector2.ZERO, none, false, false, dt)
		await physics_frame
	for k in 60:
		pad.drive(Vector2.ZERO, Vector2.ZERO, none, false, false, dt)
		await physics_frame
	var walked: float = (f.parts.pelvis.global_position - w0).dot(cam_fwd.normalized())
	_check("left stick up walks away from the camera", walked > 1.2 and f.moves.standing(), "walked %.2f m" % walked)

	# Grips through real (fake) joypad events, standing and on the mat.
	main = await _fresh()
	f = main.fighter
	main.player.set_physics_process(false)
	pad = main.pad
	pad.set_physics_process(true)
	await _wait(1.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _wait(0.1)
	_check("right trigger grips", f.intent.grip[1], "")
	_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await _wait(0.1)
	_check("grip holds with LB held", f.intent.grip[1], "")
	_button(JOY_BUTTON_LEFT_SHOULDER, false)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	# Hold B: lower stance, then sit down.
	_button(JOY_BUTTON_B, true)
	await _wait(0.4)
	var low: float = f.parts.pelvis.global_position.y
	_check("holding B lowers the stance", f.intent.crouch > 0.3 and low < 0.9, "crouch %.2f, pelvis y %.2f" % [f.intent.crouch, low])
	await _wait(2.5)
	_button(JOY_BUTTON_B, false)
	await _wait(1.0)
	_check("holding B all the way sits you down", f.on_ground(), "state %s" % FighterMoves.State.keys()[f.moves.state])
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _wait(0.1)
	_check("left trigger grips on the mat", f.intent.grip[0], "")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _wait(0.1)
	pad.set_physics_process(false)

	# On the mat: left stick = hips, right stick = chest, a bumper = that hand.
	pad.drive(Vector2(-0.7, -0.7), Vector2(1, 0), none, false, false, dt)
	_check("on the mat the left stick drives the hips", f.intent.hips == Vector2(-0.7, -0.7) and f.intent.move == Vector2.ZERO, "hips %s" % f.intent.hips)
	_check("on the mat the right stick drives the chest", f.intent.upper == Vector2(1, 0) and not f.intent.hand_active[0], "upper %s" % f.intent.upper)
	pad.drive(Vector2.ZERO, Vector2(1, 0), lb, false, false, dt)
	_check("on the mat LB hands the right stick to the left hand", f.intent.upper == Vector2.ZERO and f.intent.hand_active[0] and not f.intent.hand_active[1], "")
	# Sit up, then drive the hips up: stand.
	for k in 180:
		pad.drive(Vector2.ZERO, Vector2(0, 1), none, false, false, dt)
		await physics_frame
	for k in 360:
		pad.drive(Vector2(0, -1), Vector2(0, 1), none, false, false, dt)
		await physics_frame
		if f.moves.state == FighterMoves.State.STAND:
			break
	for k in 240:
		pad.drive(Vector2.ZERO, Vector2.ZERO, none, false, false, dt)
		await physics_frame
	_check("sit up + left stick down stands you up", f.moves.state == FighterMoves.State.STAND and f.parts.head.global_position.y > 1.4,
		"state %s, head y %.2f" % [FighterMoves.State.keys()[f.moves.state], f.parts.head.global_position.y])

	# Facing: with the partner near, you turn to face it while side-stepping.
	main = await _fresh()
	f = main.fighter
	main.player.set_physics_process(false)
	pad = main.pad
	pad.set_physics_process(false)
	main.partner.distance = 1.6
	main.partner.respawn()
	await _wait(0.5)
	main.cam.yaw_offset = 0.0
	main.cam.snap()
	for k in 180:
		pad.opponent = main.partner.fighter
		pad.drive(Vector2(1, 0), Vector2.ZERO, none, false, false, dt)
		await physics_frame
	for k in 60:
		pad.drive(Vector2.ZERO, Vector2.ZERO, none, false, false, dt)
		await physics_frame
	var to_p: Vector3 = main.partner.fighter.parts.chest.global_position - f.parts.chest.global_position
	to_p.y = 0.0
	var facing: Vector3 = -f.heading_basis().z
	var off := rad_to_deg(facing.angle_to(to_p.normalized()))
	_check("you keep facing the partner while circling", off < 25.0 and f.moves.standing(), "%.0f deg off" % off)

	print("FAILURES: ", failures)
	quit(failures)


func _axis(axis: JoyAxis, v: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = v
	Input.parse_input_event(ev)


func _button(b: JoyButton, down: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = b
	ev.pressed = down
	Input.parse_input_event(ev)


func _hand_local(f: Fighter, hand: String) -> Vector3:
	return f.heading_basis().inverse() * (f.parts[hand].global_position - f.parts.chest.global_position)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _chest_yaw(f: Fighter) -> float:
	var fwd: Vector3 = -f.parts.chest.global_basis.z
	return atan2(-fwd.x, -fwd.z)


func _fresh() -> Node3D:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# Solo checks: take the training partner off the mat.
	main.partner.remove()
	await physics_frame
	return main


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(label: String, ok: bool, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + label + "  (" + detail + ")")
	if not ok:
		failures += 1
