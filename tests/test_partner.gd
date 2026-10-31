extends SceneTree

## Headless checks for the training partner, grips and the sparring AI:
##   godot --headless --path . --script res://tests/test_partner.gd
## 1. the partner spawns facing the player and both stand, 2. the dummy holds
## its guard, 3. a closed hand touching the partner grabs it, 4. pulling the
## grip drags the partner, 5. letting go of the trigger releases, 6. yanking
## too hard tears the grip and it needs a fresh press, 7. a downed partner gets
## back up, 8. the AI only writes the intent, 9. the sparring AI gets grips on
## the player, 10. and moves the player around without falling over itself.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/partner_ai.gd")
	var cheats := RegEx.create_from_string("\\bInput\\.|apply_(central_)?(force|impulse|torque)|linear_velocity\\s*=|global_position\\s*=").search(src)
	_check("AI only writes the intent (no Input, no forces)", cheats == null, cheats.get_string() if cheats else "")

	var main := await _fresh()
	var f: Fighter = main.fighter
	var tp: TrainingPartner = main.partner
	var grips: GripSystem = main.grips
	var p: Fighter = tp.fighter
	_quiet(main)
	await _wait(3.0)
	var to_p: Vector3 = p.parts.chest.global_position - f.parts.chest.global_position
	to_p.y = 0.0
	var facing := (-p.heading_basis().z).dot(-to_p.normalized())
	_check("partner faces the player", facing > 0.95, "dot %.2f, %.2f m apart" % [facing, to_p.length()])
	_check("both stand 3 s", f.parts.head.global_position.y > 1.5 and p.parts.head.global_position.y > 1.5,
		"head y %.2f / %.2f" % [f.parts.head.global_position.y, p.parts.head.global_position.y])
	var guard_ok := true
	for i in 2:
		var off: Vector3 = p.chest_frame().inverse() * (p.parts[("l_" if i == 0 else "r_") + "hand"].global_position - p.parts.chest.global_position)
		guard_ok = guard_ok and off.z < -0.1 and off.y > -0.45
	_check("dummy holds its hands up", guard_ok, "")

	# Reach the right hand to the partner's chest with the grip closed.
	var it := f.intent
	# Both hands on its sleeves (its forearms across from them).
	var spot := Vector3.ZERO
	var t := 0.0
	for i in 2:
		it.hand_active[i] = true
		it.arm_tone[i] = 0.8
		it.grip[i] = true
	while (grips.holding(f, 0).is_empty() or grips.holding(f, 1).is_empty()) and t < 2.0:
		for i in 2:
			spot = p.parts["r_forearm" if i == 0 else "l_forearm"].global_position
			it.hand_target[i] = spot
			it.hand_effort[i] = (spot - f.parts[("l_" if i == 0 else "r_") + "hand"].global_position).normalized() * 0.4
		await physics_frame
		t += 1.0 / 120.0
	var g := grips.holding(f, 1)
	_check("closed hands on the partner grab it", not g.is_empty() and not grips.holding(f, 0).is_empty(),
		"%.2f s, parts %s / %s" % [t, grips.part_name(grips.holding(f, 0)), grips.part_name(g)])

	# Pull it toward us and down.
	var p0: Vector3 = p.parts.chest.global_position
	var most := 0.0
	it.tension = 1.0
	it.torso_lean = -0.6
	it.weight_shift = Vector2(0, -0.6)
	for k in 240:
		var cf := f.chest_frame()
		for i in 2:
			it.hand_target[i] = f.parts.chest.global_position + cf * Vector3(0.18 * (i * 2 - 1), -0.25, -0.12)
			it.hand_effort[i] = cf * Vector3(0, -0.3, 1).normalized()
		await physics_frame
		most = maxf(most, (p.parts.chest.global_position - p0).dot(-to_p.normalized()))
	_check("pulling the grips drags the partner", most > 0.15,
		"chest came %.2f m toward us, partner fell %s, still held %s" % [most, p.has_fallen, not grips.holding(f, 1).is_empty()])
	it.tension = 0.0
	it.torso_lean = 0.0
	it.weight_shift = Vector2.ZERO
	for i in 2:
		it.hand_effort[i] = Vector3.ZERO
		it.grip[i] = false
	await _wait(0.05)
	_check("letting go of the triggers releases", grips.holding(f, 0).is_empty() and grips.holding(f, 1).is_empty(), "")

	# Grip again, then shove the partner hard away: the grip tears.
	main = await _fresh()
	f = main.fighter
	tp = main.partner
	grips = main.grips
	p = tp.fighter
	it = f.intent
	_quiet(main)
	await _wait(1.5)
	it.grip[1] = true
	it.hand_active[1] = true
	t = 0.0
	while grips.holding(f, 1).is_empty() and t < 2.0:
		spot = p.parts.l_forearm.global_position
		it.hand_target[1] = spot
		it.hand_effort[1] = (spot - f.parts.r_hand.global_position).normalized() * 0.4
		await physics_frame
		t += 1.0 / 120.0
	it.hand_effort[1] = Vector3.ZERO
	var torn := [false]
	grips.released.connect(func(_f: Fighter, _h: int, was_torn: bool) -> void: torn[0] = torn[0] or was_torn)
	p.shove(-to_p.normalized() * -260.0)
	await _wait(0.6)
	_check("a hard yank tears the grip", torn[0] and grips.holding(f, 1).is_empty(), "torn %s" % torn[0])
	await _wait(0.4)
	_check("a torn grip needs a fresh press", grips.holding(f, 1).is_empty(), "")

	# Knocked down, the partner is back up after down_reset.
	p.shove(Vector3(0, 0, -300))
	await _wait(1.5)
	var was_down: bool = tp.fighter.parts.head.global_position.y < 0.9
	await _wait(tp.down_reset + 1.5)
	_check("a downed partner gets back up", was_down and tp.fighter.parts.head.global_position.y > 1.5,
		"down %s, head y %.2f" % [was_down, tp.fighter.parts.head.global_position.y])

	# Sparring: the AI gets grips on the player and moves them.
	var got_grip := 0.0
	var foe_moved := 0.0
	var foe_fell := 0
	var ai_fell := 0
	var acts := {}
	for round in 3:
		main = await _fresh()
		f = main.fighter
		tp = main.partner
		grips = main.grips
		_quiet(main)
		tp.ai.seed = 100 + round
		tp.ai._rng.seed = 100 + round
		tp.set_mode(PartnerAI.Mode.SPAR)
		# The player just holds a loose guard.
		for i in 2:
			f.intent.hand_active[i] = true
			f.intent.arm_tone[i] = 0.7
		var start: Vector3 = f.parts.chest.global_position
		var first := -1.0
		var far := 0.0
		for k in 120 * 12:
			var g0 := PlayerInput.hand_targets(f, f.parts.chest.global_position, PlayerInput.GUARD)
			for i in 2:
				f.intent.hand_target[i] = g0[i]
			await physics_frame
			acts[tp.ai.ACT_NAMES[tp.ai.act]] = true
			if first < 0.0 and (not grips.holding(tp.fighter, 0).is_empty() or not grips.holding(tp.fighter, 1).is_empty()):
				first = k / 120.0
			far = maxf(far, (f.parts.chest.global_position - start).length())
		got_grip += 1 if first >= 0.0 and first < 6.0 else 0
		foe_moved = maxf(foe_moved, far)
		foe_fell += int(f.has_fallen)
		ai_fell += int(tp.fighter.has_fallen)
		print("  round %d: first grip %.1f s, player chest moved up to %.2f m, player fell %s, AI fell %s" % [round, first, far, f.has_fallen, tp.fighter.has_fallen])
	print("  actions seen: ", acts.keys())
	_check("sparring AI gets grips", got_grip >= 2, "%d of 3 rounds within 6 s" % got_grip)
	_check("sparring AI moves the player", foe_moved > 0.25, "up to %.2f m" % foe_moved)
	_check("AI doesn't fall over on its own every round", ai_fell < 3, "fell %d of 3, player fell %d" % [ai_fell, foe_fell])

	print("FAILURES: %d" % failures)
	quit(failures)


## Keep the player's real input nodes from writing the intent.
func _quiet(main: Node) -> void:
	main.player.fighter = null
	main.pad.fighter = null
	main.dev.fighter = null


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
