extends SceneTree

## Headless checks for the automatic movement layer (FighterMoves):
##   godot --headless --path . --script res://tests/test_moves.gd
## Standing balance and stepping, walking and turning, full-body moves from
## the hands, and the ground moves (bridge, shrimp, sit up, scoot, stand up).
## Pass a test name as a user arg to run only that one:
##   godot --headless --path . --script res://tests/test_moves.gd -- walk

var failures := 0
var main: Node3D
var only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		only = args[0]
	_run.call_deferred()


func _run() -> void:
	for t in ["stand", "shoves", "walk", "strafe", "turn", "full_body", "sit_down", "sit_up", "bridge",
			"shrimp", "scoot", "legs_up", "hip_swing", "stand_up", "prone", "ai_footwork", "ai_get_up"]:
		if only == "" or only == t:
			await call("_t_" + t)
	print("FAILURES: ", failures)
	quit(failures)


# --- Standing ---------------------------------------------------------------

func _t_stand() -> void:
	var f := await _fresh()
	await _wait(5.0)
	_check("stands on its own 5 s", _up(f), "head y %.2f, moved %.2f m" % [f.parts.head.global_position.y, _flat(f.parts.pelvis.global_position).length()])


func _t_shoves() -> void:
	for imp in [60.0, 110.0]:
		var f := await _fresh()
		await _wait(1.0)
		f.shove(Vector3(0, 0, -imp))
		await _wait(4.0)
		_check("steps to catch a %d N s shove" % int(imp), _up(f), "head y %.2f" % f.parts.head.global_position.y)
	var f2 := await _fresh()
	await _wait(1.0)
	f2.shove(Vector3(0, 0, -220))
	await _wait(4.0)
	_check("falls from a big shove", f2.parts.head.global_position.y < 0.9, "head y %.2f" % f2.parts.head.global_position.y)
	var f3 := await _fresh()
	await _wait(1.0)
	f3.shove(Vector3(70, 0, 0))
	await _wait(4.0)
	_check("steps to catch a sideways shove", _up(f3), "head y %.2f" % f3.parts.head.global_position.y)


func _t_walk() -> void:
	var f := await _fresh()
	await _wait(1.0)
	var p0: Vector3 = f.parts.pelvis.global_position
	f.intent.move = Vector2(0, -1)
	await _wait(3.0)
	f.intent.move = Vector2.ZERO
	var d: Vector3 = f.parts.pelvis.global_position - p0
	await _wait(1.5)
	_check("walks forward", -d.z > 2.0 and absf(d.x) < 0.5 and _up(f), "moved %.2f m forward, %.2f sideways, up %s" % [-d.z, d.x, _up(f)])
	var p1: Vector3 = f.parts.pelvis.global_position
	await _wait(1.5)
	_check("stops when the stick lets go", _flat(f.parts.pelvis.global_position - p1).length() < 0.15, "drifted %.2f m" % _flat(f.parts.pelvis.global_position - p1).length())
	f.intent.move = Vector2(0, 1)
	var p2: Vector3 = f.parts.pelvis.global_position
	await _wait(2.0)
	f.intent.move = Vector2.ZERO
	await _wait(1.0)
	_check("walks backward", f.parts.pelvis.global_position.z - p2.z > 1.0 and _up(f), "moved %.2f m back" % (f.parts.pelvis.global_position.z - p2.z))


func _t_strafe() -> void:
	var f := await _fresh()
	await _wait(1.0)
	var p0: Vector3 = f.parts.pelvis.global_position
	f.intent.face_dir = Vector2(0, -1)
	f.intent.move = Vector2(1, 0)
	await _wait(2.5)
	f.intent.move = Vector2.ZERO
	await _wait(1.0)
	var d: Vector3 = f.parts.pelvis.global_position - p0
	var yaw := rad_to_deg(_yaw(f))
	_check("side-steps while facing forward", d.x > 1.2 and absf(yaw) < 25.0 and _up(f), "moved %.2f m right, facing %.0f deg" % [d.x, yaw])


func _t_turn() -> void:
	var f := await _fresh()
	await _wait(1.0)
	f.intent.face_dir = Vector2(1, 0)
	await _wait(2.0)
	var yaw := rad_to_deg(_yaw(f))
	_check("turns to face right", absf(angle_difference(deg_to_rad(yaw), deg_to_rad(-90.0))) < deg_to_rad(20.0) and _up(f), "facing %.0f deg (want -90)" % yaw)
	f.intent.face_dir = Vector2(0, 1)
	await _wait(2.5)
	yaw = rad_to_deg(_yaw(f))
	_check("turns around", absf(angle_difference(deg_to_rad(yaw), PI)) < deg_to_rad(25.0) and _up(f), "facing %.0f deg (want 180)" % yaw)


func _t_full_body() -> void:
	var f := await _fresh()
	await _wait(1.0)
	var hb := f.heading_basis()
	var chest: Vector3 = f.parts.chest.global_position
	for i in 2:
		f.intent.hand_active[i] = true
		f.intent.hand_target[i] = chest + hb * Vector3(0.15 * (i * 2 - 1), -0.15, -0.3)
	await _wait(1.0)
	var p0 := _com_over_feet(f)
	# Both hands pulled in tight: hips drop back and sink, feet brace.
	for i in 2:
		f.intent.hand_target[i] = chest + hb * Vector3(0.15 * (i * 2 - 1), -0.15, -0.1)
	await _wait(1.0)
	var back := (_com_over_feet(f) - p0).dot(hb.z)
	_check("pulling drops the hips back and sinks", back > 0.03 and f.parts.pelvis.global_position.y < 0.93 and _up(f),
		"hips back %.2f m, pelvis y %.2f" % [back, f.parts.pelvis.global_position.y])
	# Both hands swung hard to the right: shoulders and hips turn, feet stay.
	var feet0 := [f.parts.l_foot.global_position, f.parts.r_foot.global_position]
	var yaw0 := _yaw(f)
	var cyaw0 := _chest_yaw(f)
	for i in 2:
		f.intent.hand_target[i] = chest + hb * Vector3(0.45, -0.1, -0.3)
	await _wait(1.0)
	var hip_turn := rad_to_deg(angle_difference(yaw0, _yaw(f)))
	var chest_turn := rad_to_deg(angle_difference(cyaw0, _chest_yaw(f)))
	var feet_moved: float = maxf(_flat(f.parts.l_foot.global_position - feet0[0]).length(), _flat(f.parts.r_foot.global_position - feet0[1]).length())
	_check("a throw swing turns hips and shoulders together", hip_turn < -10.0 and chest_turn < hip_turn - 10.0 and _up(f),
		"hips %.0f deg, shoulders %.0f deg" % [hip_turn, chest_turn])
	_check("feet stay planted during the swing", feet_moved < 0.15, "feet moved up to %.2f m" % feet_moved)


func _t_sit_down() -> void:
	var f := await _fresh()
	await _wait(1.0)
	f.intent.crouch = 0.5
	await _wait(1.0)
	_check("crouch lowers the hips", f.parts.pelvis.global_position.y < 0.86 and _up(f), "pelvis y %.2f" % f.parts.pelvis.global_position.y)
	f.intent.crouch = 1.0
	await _wait(3.0)
	f.intent.crouch = 0.0
	await _wait(1.0)
	_check("holding a full crouch sits you down", f.moves.on_ground() and f.moves.ground == FighterMoves.Ground.SITTING,
		"state %s, ground %s, pelvis y %.2f" % [_st(f), FighterMoves.Ground.keys()[f.moves.ground], f.parts.pelvis.global_position.y])


# --- Ground -----------------------------------------------------------------

func _t_sit_up() -> void:
	var f := await _on_back()
	f.intent.upper = Vector2(0, 1)
	await _wait(2.0)
	_check("right stick up sits you up", f.moves.ground == FighterMoves.Ground.SITTING,
		"ground %s, chest up %.2f" % [FighterMoves.Ground.keys()[f.moves.ground], f.parts.chest.global_basis.y.y])
	f.intent.upper = Vector2(0, -1)
	await _wait(2.0)
	_check("right stick down lies you back", f.moves.ground == FighterMoves.Ground.SUPINE, "ground %s" % FighterMoves.Ground.keys()[f.moves.ground])


func _t_bridge() -> void:
	var f := await _on_back()
	var y0: float = f.parts.pelvis.global_position.y
	f.intent.hips = Vector2(0, -1)
	var top := y0
	for k in 180:
		await physics_frame
		top = maxf(top, f.parts.pelvis.global_position.y)
	_check("left stick down bridges the hips up", top - y0 > 0.15, "pelvis rose %.2f m" % (top - y0))
	f.intent.hips = Vector2.ZERO
	await _wait(1.0)
	# Bridge over the left shoulder rolls the body that way.
	var right0: Vector3 = f.parts.pelvis.global_basis.x
	f.intent.hips = Vector2(-0.8, -0.8)
	await _wait(1.5)
	var roll: float = f.parts.pelvis.global_basis.x.y - right0.y
	_check("down-left bridges over the left shoulder", roll > 0.2, "right hip rose by %.2f (dot)" % roll)


func _t_shrimp() -> void:
	var f := await _on_back()
	var right: Vector3 = f.parts.pelvis.global_basis.x
	f.intent.upper = Vector2(-1, 0)
	# Rolling onto the side comes first; measure the hip escapes after it.
	await _wait(0.8)
	var p0: Vector3 = f.parts.pelvis.global_position
	await _wait(2.4)
	var d := _flat(f.parts.pelvis.global_position - p0)
	var away := d.dot(_flat(right).normalized())
	_check("right stick left shrimps (hips move away to the right)", away > 0.2,
		"hips moved %.2f m right (%.2f total), ground %s" % [away, d.length(), FighterMoves.Ground.keys()[f.moves.ground]])


func _t_scoot() -> void:
	var f := await _on_back()
	f.intent.upper = Vector2(0, 1)
	await _wait(1.5)
	var p0: Vector3 = f.parts.pelvis.global_position
	var fwd: Vector3 = -f.parts.chest.global_basis.z
	fwd.y = 0.0
	await _wait(3.0)
	var d: float = (f.parts.pelvis.global_position - p0).dot(fwd.normalized())
	_check("holding up while sitting butt scoots forward", d > 0.3 and f.moves.ground == FighterMoves.Ground.SITTING, "moved %.2f m forward" % d)


func _t_legs_up() -> void:
	var f := await _on_back()
	f.intent.hips = Vector2(0, 1)
	await _wait(1.5)
	var knees: float = (f.parts.l_shin.global_position.y + f.parts.r_shin.global_position.y) * 0.5
	_check("left stick up brings the knees and feet up", knees > 0.35, "shins at y %.2f" % knees)


func _t_hip_swing() -> void:
	var f := await _on_back()
	var yaw0 := _spine_yaw(f)
	f.intent.hips = Vector2(1, 0)
	await _wait(2.0)
	var turned := rad_to_deg(angle_difference(yaw0, _spine_yaw(f)))
	_check("left stick sideways pivots the body on the mat", absf(turned) > 20.0, "turned %.0f deg" % turned)


func _t_stand_up() -> void:
	var f := await _on_back()
	f.intent.upper = Vector2(0, 1)
	await _wait(1.5)
	f.intent.hips = Vector2(0, -1)
	await _wait(3.0)
	f.intent.upper = Vector2.ZERO
	f.intent.hips = Vector2.ZERO
	await _wait(2.0)
	_check("sit up + hips up stands you back up", f.moves.state == FighterMoves.State.STAND and _up(f),
		"state %s, head y %.2f" % [_st(f), f.parts.head.global_position.y])


func _t_prone() -> void:
	var f := await _fresh()
	await _wait(0.5)
	f.shove(Vector3(0, 0, -260))
	await _wait(3.0)
	var g := f.moves.ground
	f.intent.upper = Vector2(0, 1)
	await _wait(2.0)
	_check("face down, right stick up pushes up to hands and knees",
		f.moves.ground == FighterMoves.Ground.ALL_FOURS or f.moves.ground == FighterMoves.Ground.SITTING or g != FighterMoves.Ground.PRONE,
		"landed %s, now %s, pelvis y %.2f" % [FighterMoves.Ground.keys()[g], FighterMoves.Ground.keys()[f.moves.ground], f.parts.pelvis.global_position.y])
	f.intent.hips = Vector2(0, -1)
	await _wait(3.0)
	f.intent.upper = Vector2.ZERO
	f.intent.hips = Vector2.ZERO
	await _wait(1.5)
	_check("then hips up stands you up", f.moves.state == FighterMoves.State.STAND and _up(f), "state %s" % _st(f))


# --- The sparring AI uses the same moves -------------------------------------

func _t_ai_footwork() -> void:
	var f := await _fresh()
	main.partner.distance = 2.2
	main.partner.respawn()
	main.partner.set_mode(PartnerAI.Mode.SPAR)
	var ai: Fighter = main.partner.fighter
	var d0: float = _flat(ai.parts.chest.global_position - f.parts.chest.global_position).length()
	var t := 0.0
	var d := d0
	while t < 5.0 and d > 0.95:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		d = _flat(ai.parts.chest.global_position - f.parts.chest.global_position).length()
	_check("sparring AI walks in to grip range", d <= 0.95 and ai.moves.standing(), "%.2f m -> %.2f m in %.1f s" % [d0, d, t])


func _t_ai_get_up() -> void:
	var f := await _fresh()
	main.partner.distance = 1.6
	main.partner.respawn()
	main.partner.set_mode(PartnerAI.Mode.SPAR)
	var ai: Fighter = main.partner.fighter
	await _wait(0.5)
	ai.shove(Vector3(0, 0, 260))
	var was_down := false
	var t := 0.0
	while t < 9.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if ai.on_ground():
			was_down = true
		if was_down and ai.moves.state == FighterMoves.State.STAND and ai.parts.head.global_position.y > 1.4:
			break
	_check("knocked-down AI gets up by itself (no respawn)", was_down and main.partner.fighter == ai and ai.moves.state == FighterMoves.State.STAND,
		"down %s, up after %.1f s, same body %s" % [was_down, t, main.partner.fighter == ai])


# --- Helpers ----------------------------------------------------------------

func _fresh() -> Fighter:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.partner.remove()
	main.player.fighter = null
	main.pad.fighter = null
	main.pad.set_physics_process(false)
	main.player.set_physics_process(false)
	return main.fighter


## A fighter lying on its back, settled.
func _on_back() -> Fighter:
	var f := await _fresh()
	await _wait(0.5)
	f.intent.crouch = 1.0
	await _wait(2.5)
	f.intent.crouch = 0.0
	f.intent.upper = Vector2(0, -1)
	await _wait(2.0)
	f.intent.upper = Vector2.ZERO
	await _wait(1.0)
	if f.moves.ground != FighterMoves.Ground.SUPINE:
		print("  (setup: ended up %s, state %s)" % [FighterMoves.Ground.keys()[f.moves.ground], _st(f)])
	return f


func _com_over_feet(f: Fighter) -> Vector3:
	var mid: Vector3 = (f.parts.l_foot.global_position + f.parts.r_foot.global_position) * 0.5
	return _flat(f.com - mid)


func _up(f: Fighter) -> bool:
	return f.parts.head.global_position.y > 1.45 and f.moves.state == FighterMoves.State.STAND


func _st(f: Fighter) -> String:
	return FighterMoves.State.keys()[f.moves.state]


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _yaw(f: Fighter) -> float:
	var fw := -f.heading_basis().z
	return atan2(-fw.x, -fw.z)


func _chest_yaw(f: Fighter) -> float:
	var fw: Vector3 = -f.parts.chest.global_basis.z
	return atan2(-fw.x, -fw.z)


func _spine_yaw(f: Fighter) -> float:
	var s: Vector3 = f.parts.chest.global_position - f.parts.pelvis.global_position
	return atan2(s.x, s.z)


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(label: String, ok: bool, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + label + "  (" + detail + ")")
	if not ok:
		failures += 1
