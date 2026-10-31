extends SceneTree

## Headless checks for movement milestones 1 and 2 (intent and hand IK):
##   godot --headless --path . --script res://tests/test_controls.gd
## 1. Fighter never reads Input, 2. tension comes through the intent,
## 3. Q/E turn twists the chest, 4. the hands touch three drill balls in a row
## without the fighter falling, 5. PlayerInput's cursor moves the lead hand target.

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

	# PlayerInput: moving the mouse right moves the lead (right) hand target right.
	var before := PlayerInput.hand_targets(f, p.cursor, p.reach, FighterIntent.RIGHT)[1]
	p.move_cursor(Vector2(100, 0))
	var after := PlayerInput.hand_targets(f, p.cursor, p.reach, FighterIntent.RIGHT)[1]
	var dx := (f.heading_basis().inverse() * (after - before)).x
	_check("mouse right moves lead hand right", dx > 0.15, "moved %.2f m" % dx)

	print("FAILURES: ", failures)
	quit(failures)


func _chest_yaw(f: Fighter) -> float:
	var fwd: Vector3 = -f.parts.chest.global_basis.z
	return atan2(-fwd.x, -fwd.z)


func _fresh() -> Node3D:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	return main


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(label: String, ok: bool, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + label + "  (" + detail + ")")
	if not ok:
		failures += 1
