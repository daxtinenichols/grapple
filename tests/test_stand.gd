extends SceneTree

## Headless check for the standing milestone:
##   godot --headless --path . --script res://tests/test_stand.gd
## 1. stands for 5 s, 2. survives a small shove, 3. falls from a big one,
## 3b. goes floppy once down, 4. elbow and knee targets are reached, 5. the elbow can't hyperextend.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("physics engine: ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	var f := await _fresh()
	await _wait(5.0)
	_check("stands 5 s", f.parts.head.global_position.y > 1.5, "head y %.2f" % f.parts.head.global_position.y)

	f.shove(Vector3(0, 0, -60))
	await _wait(4.0)
	_check("survives small shove", f.parts.head.global_position.y > 1.5, "head y %.2f" % f.parts.head.global_position.y)

	f.shove(Vector3(0, 0, -220))
	await _wait(4.0)
	_check("falls from big shove", f.parts.head.global_position.y < 0.9, "head y %.2f" % f.parts.head.global_position.y)
	_check("goes floppy after falling", f.limpness_scale <= f.floppy_strength + 0.01, "strength x%.2f" % f.limpness_scale)

	# Joint accuracy only: bending a knee tips the fighter over, so keep full strength.
	f = await _fresh()
	f.floppy_strength = 1.0
	f.set_target("r_forearm", Vector3(90, 0, 0))
	f.set_target("l_shin", Vector3(-60, 0, 0))
	await _wait(2.0)
	_check("elbow reaches 90 deg", _error_deg(f, "r_forearm") < 12.0, "off by %.1f deg" % _error_deg(f, "r_forearm"))
	_check("knee reaches 60 deg", _error_deg(f, "l_shin") < 12.0, "off by %.1f deg" % _error_deg(f, "l_shin"))

	# Hyperextension past the limit must be blocked: submissions push against these.
	f.set_target("r_forearm", Vector3(-60, 0, 0))
	await _wait(2.0)
	var flex := _flex_deg(f, "r_forearm")
	_check("elbow limit blocks hyperextension", flex > -10.0, "elbow flex %.1f deg" % flex)

	print("FAILURES: ", failures)
	quit(failures)


func _joint(f: Fighter, n: String) -> Dictionary:
	for j in f.joints:
		if j.name == n:
			return j
	return {}


func _error_deg(f: Fighter, n: String) -> float:
	var j := _joint(f, n)
	var e: Quaternion = j.target * f.joint_rotation(j).inverse()
	return rad_to_deg(e.get_angle()) if e.w >= 0.0 else rad_to_deg((-e).get_angle())


## Signed flexion about the joint's x axis, from the child's long axis.
func _flex_deg(f: Fighter, n: String) -> float:
	var down := f.joint_rotation(_joint(f, n)) * Vector3.DOWN
	return rad_to_deg(atan2(-down.z, -down.y))


func _fresh() -> Fighter:
	for c in root.get_children():
		c.queue_free()
	await process_frame
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	return main.fighter


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(label: String, ok: bool, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + label + "  (" + detail + ")")
	if not ok:
		failures += 1
