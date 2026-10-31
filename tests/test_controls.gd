extends SceneTree

## Headless checks for movement milestones 1 and 2 (intent and hand IK):
##   godot --headless --path . --script res://tests/test_controls.gd
## 1. Fighter never reads Input, 2. tension comes through the intent,
## 3. Q/E turn twists the chest, 4. the hands touch three drill balls in a row
## without the fighter falling, 5. mouse buttons pick which arm the mouse moves,
## 6. the arms stay calm while holding a guard, 7. controller sticks push the
## hands without dragging the body, 8. grips hold in every controller mode,
## 9. RB (body) shifts weight and leans the torso, 10. LB (legs) moves a foot
## and clamps a knee, also lying down, without sliding the body around.

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

	# Controller arms: right stick right moves the right hand right, it stays
	# there after letting go, and the body doesn't get dragged.
	p.fighter = null
	var pad: PadInput = main.pad
	pad.set_physics_process(false)
	pad.fighter = f
	var dt := 1.0 / Engine.physics_ticks_per_second
	var idle: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	for k in 240:
		pad.apply_sticks(idle, dt)
		await physics_frame
	var pel0: Vector3 = f.parts.pelvis.global_position
	var h0 := _hand_local(f, "r_hand")
	var push: Array[Vector2] = [Vector2.ZERO, Vector2(1, 0)]
	for k in 60:
		pad.apply_sticks(push, dt)
		await physics_frame
	var moved := _hand_local(f, "r_hand").x - h0.x
	_check("right stick moves the right hand right", moved > 0.2, "moved %.2f m in 0.5 s" % moved)
	for k in 120:
		pad.apply_sticks(idle, dt)
		await physics_frame
	var kept := _hand_local(f, "r_hand").x - h0.x
	_check("hand stays where it was moved", kept > moved * 0.7, "%.2f m from the guard 1 s later" % kept)
	var drift: float = (f.parts.pelvis.global_position - pel0).length()
	_check("pushing an arm doesn't move the body", drift < 0.05 and not f.has_fallen, "pelvis moved %.3f m" % drift)

	# Controller modes, driven through fake joypad events. Grips hold in every mode.
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
	_check("grip holds in legs mode", f.intent.grip[1] and f.intent.focus == FighterIntent.Focus.LEGS, "")
	_button(JOY_BUTTON_LEFT_SHOULDER, false)
	_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await _wait(0.1)
	_check("grip holds in body mode", f.intent.grip[1] and f.intent.focus == FighterIntent.Focus.HIPS, "")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)

	# Body mode: left stick shifts the weight that way, right stick leans the torso.
	var c0: Vector3 = f.heading_basis().inverse() * f.com
	main.cam.yaw_offset = 0.0
	main.cam.snap()
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _wait(1.5)
	var c1: Vector3 = f.heading_basis().inverse() * f.com
	_check("RB + left stick right shifts weight right", c1.x - c0.x > 0.025 and not f.has_fallen,
		"center of mass moved %.3f m" % (c1.x - c0.x))
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _wait(1.5)
	var head: Vector3 = f.heading_basis().inverse() * (f.parts.head.global_position - f.parts.pelvis.global_position)
	_check("RB + right stick up leans forward without falling", head.z < -0.15 and not f.has_fallen,
		"head %.2f m ahead of the hips" % -head.z)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _wait(1.0)
	var c2: Vector3 = f.heading_basis().inverse() * f.com
	_check("weight and lean stay put after letting go of RB",
		f.intent.weight_shift.x > 0.5 and f.intent.torso_lean > 0.5 and c2.x - c0.x > 0.02 and not f.has_fallen,
		"shift %.2f, lean %.2f" % [f.intent.weight_shift.x, f.intent.torso_lean])
	_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	_button(JOY_BUTTON_RIGHT_STICK, true)
	await _wait(0.1)
	_button(JOY_BUTTON_RIGHT_STICK, false)
	_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _wait(0.1)
	_check("RB + stick click recentres the body", f.intent.weight_shift == Vector2.ZERO and f.intent.torso_lean == 0.0, "")

	# Legs on the ground: knock the fighter down, then work the legs. Let the
	# fake joypad events land first: they switch the controller back on.
	await _wait(0.1)
	pad.set_physics_process(false)
	f.shove(Vector3(0, 0, 220))
	var lying: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	pad.mode = PadInput.Mode.LEGS
	for k in 480:
		pad.drive(lying, dt)
		await physics_frame
	var pel1: Vector3 = f.parts.pelvis.global_position
	var foot0: Vector3 = f.parts.r_foot.global_position - f.parts.pelvis.global_position
	var out: Array[Vector2] = [Vector2.ZERO, Vector2(0, 1)]
	for k in 60:
		pad.drive(out, dt)
		await physics_frame
	var foot1: Vector3 = f.parts.r_foot.global_position - f.parts.pelvis.global_position
	_check("LB + right stick up moves the right foot when lying down", foot1.distance_to(foot0) > 0.15,
		"foot moved %.2f m" % foot1.distance_to(foot0))
	var curl: Array[Vector2] = [Vector2.ZERO, Vector2(0, -1)]
	for k in 90:
		pad.drive(curl, dt)
		await physics_frame
	var knee := rad_to_deg(f.joint_rotation(f._joint_by_name["r_shin"]).get_angle())
	_check("pulling the stick back clamps the knee", f.intent.leg_clamp[1] and knee > 50.0, "knee bent %.0f deg" % knee)
	for k in 120:
		pad.drive(lying, dt)
		await physics_frame
	knee = rad_to_deg(f.joint_rotation(f._joint_by_name["r_shin"]).get_angle())
	_check("the leg stays bent after letting go of the stick", knee > 50.0, "knee bent %.0f deg" % knee)
	var stand: Array[bool] = [false, true]
	pad.drive(lying, dt, stand)
	await physics_frame
	for k in 120:
		pad.drive(lying, dt)
		await physics_frame
	knee = rad_to_deg(f.joint_rotation(f._joint_by_name["r_shin"]).get_angle())
	_check("clicking the stick straightens the leg again", knee < 25.0, "knee bent %.0f deg" % knee)
	for k in 90:
		pad.drive(curl, dt)
		await physics_frame
	for rep in 3:
		for side in [Vector2(1, 0), Vector2(-1, 0)]:
			var wiggle: Array[Vector2] = [side, side]
			for k in 60:
				pad.drive(wiggle, dt)
				await physics_frame
	var slid: float = (f.parts.pelvis.global_position - pel1).length()
	_check("wiggling the legs on the ground doesn't slide the body far", slid < 0.25, "pelvis moved %.2f m" % slid)

	# Both bumpers on the ground: left stick moves the hips, right stick pulled
	# back clamps both legs (a closed guard squeeze).
	pad.mode = PadInput.Mode.BOTH
	var both: Array[Vector2] = [Vector2(1, 0), Vector2(0, -1)]
	for k in 90:
		pad.drive(both, dt)
		await physics_frame
	var kl := rad_to_deg(f.joint_rotation(f._joint_by_name["l_shin"]).get_angle())
	var kr := rad_to_deg(f.joint_rotation(f._joint_by_name["r_shin"]).get_angle())
	_check("RB + LB: left stick moves the hips, right stick clamps both legs",
		f.intent.weight_shift.x > 0.5 and kl > 50.0 and kr > 50.0,
		"shift %.2f, knees %.0f / %.0f deg" % [f.intent.weight_shift.x, kl, kr])
	var clicks: Array[bool] = [true, true]
	pad.drive(lying, dt, clicks)
	await physics_frame
	for k in 120:
		pad.drive(lying, dt)
		await physics_frame
	kl = rad_to_deg(f.joint_rotation(f._joint_by_name["l_shin"]).get_angle())
	_check("RB + LB + stick clicks recentre the hips and straighten the legs",
		f.intent.weight_shift == Vector2.ZERO and kl < 25.0, "left knee %.0f deg" % kl)

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
