extends SceneTree

## Headless checks for the match scene and the fighter skin:
##   godot --headless --path . --script res://tests/test_scene.gd
## 1. two fighters spawn facing each other and stand, 2. the skin adds no
## physics and follows its parts, 3. the mat edge is detected and resets both.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var m: Node3D = load("res://scenes/match.tscn").instantiate()
	root.add_child(m)
	await _wait(0.1)
	var a: Fighter = m.fighters[0]
	var b: Fighter = m.fighters[1]
	var a_face: Vector3 = -a.parts.chest.global_basis.z
	var to_b: Vector3 = b.parts.pelvis.global_position - a.parts.pelvis.global_position
	_check("two fighters face each other", a_face.dot(to_b.normalized()) > 0.95 and (-b.parts.chest.global_basis.z).dot(-to_b.normalized()) > 0.95, "dot %.2f" % a_face.dot(to_b.normalized()))

	var bodies := 0
	var shapes := 0
	var joints := 0
	for n in _all(m):
		if n is PhysicsBody3D:
			bodies += 1
		if n is CollisionShape3D:
			shapes += 1
		if n is Joint3D:
			joints += 1
	# Every part of both fighters plus the mat and the floor; the fighters' own joints.
	var want_bodies: int = a.parts.size() + b.parts.size() + 2
	var want_joints: int = a.joints.size() + b.joints.size()
	_check("skin adds no physics", bodies == want_bodies and shapes == want_bodies and joints == want_joints, "bodies %d shapes %d joints %d" % [bodies, shapes, joints])
	var skin_bodies := 0
	for s in m.skins:
		for n in _all(s):
			if n is CollisionObject3D or n is CollisionShape3D or n is Joint3D:
				skin_bodies += 1
	_check("skin nodes are visual only", skin_bodies == 0, "%d physics nodes under skins" % skin_bodies)

	await _wait(3.0)
	_check("both stand 3 s", a.parts.head.global_position.y > 1.5 and b.parts.head.global_position.y > 1.5,
		"head y %.2f / %.2f" % [a.parts.head.global_position.y, b.parts.head.global_position.y])

	var hidden := true
	for c in a.parts.chest.get_children():
		if c is MeshInstance3D and c.visible:
			hidden = false
	_check("ragdoll debug meshes hidden", hidden, "")

	a.shove(Vector3(0, 0, -220))
	await _wait(1.0)
	var worst := 0.0
	for s in m.skins:
		for e in s._follow:
			worst = maxf(worst, e.node.global_position.distance_to(e.body.global_position))
	_check("skin follows its parts while falling", worst < 0.05, "worst gap %.3f m" % worst)

	var arena: Arena = m.arena
	_check("center is on the mat", arena.is_on_mat(Vector3.ZERO), "")
	_check("past the edge is off the mat", not arena.is_on_mat(Vector3(4.2, 0, 0)) and not arena.is_on_mat(Vector3(0, 0, -4.2)), "")
	_check("safety border is off the mat", not arena.is_on_mat(Vector3(5.5, 0, 5.5)), "")

	# Throw fighter A off the combat area: both should come back to the spawns.
	var left := [false]
	arena.fighter_left_mat.connect(func(_f): left[0] = true)
	for p in a.parts.values():
		p.linear_velocity = Vector3(12, 2, 0)
	await _wait(1.5)
	var na: Fighter = m.fighters[0]
	_check("leaving the mat signals", left[0], "")
	_check("leaving the mat resets both", na != a and na.parts.pelvis.global_position.distance_to(arena.spawn_transform(0).origin + Vector3(0, 0.98, 0)) < 0.3,
		"pelvis at %s" % na.parts.pelvis.global_position)

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame
