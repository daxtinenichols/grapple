class_name Fighter
extends Node3D

## Active ragdoll fighter: 15 rigid body parts joined by 6DOF joints.
## Every joint runs an angular velocity motor that chases a target pose, so the
## body is always physical and only "wants" to be in a pose.
## Faces -Z. The fighter's left side is -X.

signal fell

## Motor gain: how fast (1/s) a joint tries to close its angle error.
@export var pose_gain := 14.0
## Multiplies every joint's strength. 1.0 is relaxed, Ctrl raises it.
@export var tension := 1.0
## 0..1, scales strength. Drained by later milestones.
@export var stamina := 1.0
## Upright assist torque (Nm per rad) on pelvis and chest while standing.
@export var upright_stiffness := 900.0
@export var upright_damping := 90.0
@export var upright_max_torque := 450.0
## How far (m) the center of mass may leave the base before the assist gives up.
@export var assist_give_up_margin := 0.06
## Joint strength multiplier once the fighter has lost its balance. Low = floppy.
@export var floppy_strength := 0.12
## How fast (per second) the body goes limp after losing balance.
@export var go_limp_rate := 6.0

# Part table. pos = center in the standing build pose, joint = anchor point.
# Limits are degrees per joint-frame axis (x = flex, y = twist, z = side).
# side: -1 left, 1 right, 0 center. Side parts mirror their y and z limits.
const BODY := [
	{"name": "pelvis", "parent": "", "shape": "box", "size": Vector3(0.32, 0.18, 0.20), "mass": 11.0, "pos": Vector3(0, 0.98, 0)},
	{"name": "abdomen", "parent": "pelvis", "shape": "box", "size": Vector3(0.28, 0.20, 0.18), "mass": 10.0, "pos": Vector3(0, 1.17, 0),
		"joint": Vector3(0, 1.07, 0), "lim": [[-30, 45], [-30, 30], [-25, 25]], "strength": 320.0},
	{"name": "chest", "parent": "abdomen", "shape": "box", "size": Vector3(0.38, 0.28, 0.22), "mass": 15.0, "pos": Vector3(0, 1.41, 0),
		"joint": Vector3(0, 1.27, 0), "lim": [[-20, 30], [-30, 30], [-20, 20]], "strength": 320.0},
	{"name": "head", "parent": "chest", "shape": "sphere", "size": Vector3(0.11, 0, 0), "mass": 5.0, "pos": Vector3(0, 1.70, 0),
		"joint": Vector3(0, 1.57, 0), "lim": [[-50, 60], [-70, 70], [-35, 35]], "strength": 60.0},
]

const LIMB := [
	{"name": "upper_arm", "parent": "chest", "shape": "capsule", "size": Vector3(0.05, 0.32, 0), "mass": 2.2, "pos": Vector3(0.25, 1.35, 0),
		"joint": Vector3(0.24, 1.50, 0), "lim": [[-60, 170], [-80, 80], [-10, 160]], "strength": 90.0},
	{"name": "forearm", "parent": "upper_arm", "shape": "capsule", "size": Vector3(0.04, 0.29, 0), "mass": 1.4, "pos": Vector3(0.25, 1.065, 0),
		"joint": Vector3(0.25, 1.20, 0), "lim": [[0, 145], [-80, 80], [-5, 5]], "strength": 60.0},
	{"name": "hand", "parent": "forearm", "shape": "box", "size": Vector3(0.03, 0.16, 0.08), "mass": 0.5, "pos": Vector3(0.25, 0.855, 0),
		"joint": Vector3(0.25, 0.935, 0), "lim": [[-70, 70], [-10, 10], [-30, 30]], "strength": 15.0},
	{"name": "thigh", "parent": "pelvis", "shape": "capsule", "size": Vector3(0.07, 0.46, 0), "mass": 8.0, "pos": Vector3(0.11, 0.72, 0),
		"joint": Vector3(0.11, 0.94, 0), "lim": [[-30, 120], [-40, 40], [-15, 45]], "strength": 380.0},
	{"name": "shin", "parent": "thigh", "shape": "capsule", "size": Vector3(0.055, 0.44, 0), "mass": 3.5, "pos": Vector3(0.11, 0.29, 0),
		"joint": Vector3(0.11, 0.50, 0), "lim": [[-145, 0], [-10, 10], [-5, 5]], "strength": 320.0},
	{"name": "foot", "parent": "shin", "shape": "box", "size": Vector3(0.10, 0.08, 0.26), "mass": 1.1, "pos": Vector3(0.11, 0.04, -0.05),
		"joint": Vector3(0.11, 0.08, 0), "lim": [[-45, 30], [-15, 15], [-20, 20]], "strength": 220.0},
]

## name -> RigidBody3D
var parts := {}
## Each entry: {joint, parent, child, target: Quaternion, strength}
var joints: Array[Dictionary] = []
## Filled every tick by update_base().
var com := Vector3.ZERO
var base_points: PackedVector2Array = []
var base_hull: PackedVector2Array = []
## Signed distance of the COM from the base edge (positive = inside).
var base_margin := 0.0
var assist := 1.0
var has_fallen := false
## 1 = full motor strength, floppy_strength = limp. Drops when balance is lost.
var limpness_scale := 1.0


func _ready() -> void:
	_build()


func _physics_process(_delta: float) -> void:
	update_base()
	_drive_joints()
	_upright_assist()
	_update_limp()
	if not has_fallen and parts.head.global_position.y < 0.9:
		has_fallen = true
		fell.emit()


# --- Construction -----------------------------------------------------------

func _build() -> void:
	var defs: Array = []
	for d in BODY:
		var c: Dictionary = d.duplicate()
		c["side"] = 0
		defs.append(c)
	for side in [-1, 1]:
		var prefix := "l_" if side < 0 else "r_"
		for d in LIMB:
			var c: Dictionary = d.duplicate(true)
			c.name = prefix + d.name
			if d.parent != "chest" and d.parent != "pelvis":
				c.parent = prefix + d.parent
			c.pos = Vector3(d.pos.x * side, d.pos.y, d.pos.z)
			c.joint = Vector3(d.joint.x * side, d.joint.y, d.joint.z)
			c["side"] = side
			defs.append(c)

	for d in defs:
		var body := _make_body(d)
		add_child(body)
		body.global_position = global_transform * d.pos
		parts[d.name] = body

	# No self-collision for now: keeps the solver calm. Revisit for grappling.
	var all := parts.values()
	for a in all:
		for b in all:
			if a != b:
				a.add_collision_exception_with(b)

	for d in defs:
		if d.parent == "":
			continue
		_make_joint(d)


func _make_body(d: Dictionary) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = d.name
	body.mass = d.mass
	body.can_sleep = false
	body.angular_damp = 1.0
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	body.physics_material_override = mat

	var shape := CollisionShape3D.new()
	var mesh := MeshInstance3D.new()
	match d.shape:
		"box":
			var s := BoxShape3D.new()
			s.size = d.size
			shape.shape = s
			var m := BoxMesh.new()
			m.size = d.size
			mesh.mesh = m
		"sphere":
			var s := SphereShape3D.new()
			s.radius = d.size.x
			shape.shape = s
			var m := SphereMesh.new()
			m.radius = d.size.x
			m.height = d.size.x * 2.0
			mesh.mesh = m
		"capsule":
			var s := CapsuleShape3D.new()
			s.radius = d.size.x
			s.height = d.size.y
			shape.shape = s
			var m := CapsuleMesh.new()
			m.radius = d.size.x
			m.height = d.size.y
			mesh.mesh = m
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.93, 0.93, 0.95) if d.name.contains("arm") or d.name in ["chest", "abdomen", "pelvis"] or d.name.contains("thigh") or d.name.contains("shin") else Color(0.86, 0.66, 0.52)
	mesh.material_override = skin
	body.add_child(shape)
	body.add_child(mesh)
	return body


func _make_joint(d: Dictionary) -> void:
	var parent: RigidBody3D = parts[d.parent]
	var child: RigidBody3D = parts[d.name]
	var j := Generic6DOFJoint3D.new()
	j.name = "joint_" + d.name
	add_child(j)
	j.global_transform = Transform3D(global_basis, global_transform * d.joint)
	j.node_a = j.get_path_to(parent)
	j.node_b = j.get_path_to(child)

	var lim: Array = d.lim
	var side: int = d.side
	for axis in 3:
		var lo: float = lim[axis][0]
		var hi: float = lim[axis][1]
		if side < 0 and axis > 0:
			var t := lo
			lo = -hi
			hi = -t
		# The 6DOF joint measures angles the opposite way to our child-relative-to-parent
		# convention (the motor velocity below is negated for the same reason).
		_set_axis_param(j, axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-hi))
		_set_axis_param(j, axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(-lo))
		_set_axis_flag(j, axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		_set_axis_flag(j, axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)

	joints.append({
		"joint": j, "parent": parent, "child": child, "name": d.name,
		"target": Quaternion.IDENTITY, "strength": d.strength,
	})


func _set_axis_param(j: Generic6DOFJoint3D, axis: int, p: int, v: float) -> void:
	match axis:
		0: j.set_param_x(p, v)
		1: j.set_param_y(p, v)
		2: j.set_param_z(p, v)


func _set_axis_flag(j: Generic6DOFJoint3D, axis: int, f: int, v: bool) -> void:
	match axis:
		0: j.set_flag_x(f, v)
		1: j.set_flag_y(f, v)
		2: j.set_flag_z(f, v)


# --- Pose control ------------------------------------------------------------

## Sets a joint's target as Euler degrees (x flex, y twist, z side) in the
## parent's frame. Side parts are given by full name, e.g. "l_forearm".
func set_target(part: String, euler_deg: Vector3) -> void:
	for j in joints:
		if j.name == part:
			j.target = Quaternion.from_euler(euler_deg * (PI / 180.0))
			return


## Current rotation of a joint relative to its parent, in the parent frame.
func joint_rotation(j: Dictionary) -> Quaternion:
	var pb: Basis = j.parent.global_basis.orthonormalized()
	var cb: Basis = j.child.global_basis.orthonormalized()
	return (pb.inverse() * cb).get_rotation_quaternion()


func _drive_joints() -> void:
	var strength_scale := tension * stamina * limpness_scale
	for j in joints:
		var err: Quaternion = j.target * joint_rotation(j).inverse()
		if err.w < 0.0:
			err = -err
		var angle := err.get_angle()
		var v := Vector3.ZERO
		if angle > 0.0001:
			v = err.get_axis() * angle * pose_gain
		var force: float = j.strength * strength_scale
		var jn: Generic6DOFJoint3D = j.joint
		for axis in 3:
			_set_axis_param(jn, axis, Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, -v[axis])
			_set_axis_param(jn, axis, Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, force)


# --- Balance -----------------------------------------------------------------

## Center of mass, contact points near the mat, the base hull and the margin.
func update_base() -> void:
	var total := 0.0
	var sum := Vector3.ZERO
	base_points = PackedVector2Array()
	for p: RigidBody3D in parts.values():
		total += p.mass
		sum += p.global_position * p.mass
		for pt in _low_points(p):
			if pt.y < 0.03:
				base_points.append(Vector2(pt.x, pt.z))
	com = sum / total
	base_hull = Geometry2D.convex_hull(base_points) if base_points.size() >= 3 else base_points
	base_margin = _signed_margin(Vector2(com.x, com.z), base_hull)


## Points on a part that can touch the mat: box corners or the bottom of a round shape.
func _low_points(p: RigidBody3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cs: CollisionShape3D = p.get_child(0)
	var s := cs.shape
	var t := p.global_transform
	if s is BoxShape3D:
		var h: Vector3 = s.size * 0.5
		for x in [-1, 1]:
			for y in [-1, 1]:
				for z in [-1, 1]:
					out.append(t * Vector3(h.x * x, h.y * y, h.z * z))
	elif s is SphereShape3D:
		out.append(t.origin - Vector3(0, s.radius, 0))
	elif s is CapsuleShape3D:
		var half: float = s.height * 0.5 - s.radius
		for e in [-1, 1]:
			var c := t * Vector3(0, half * e, 0)
			out.append(c - Vector3(0, s.radius, 0))
	return out


func _signed_margin(pt: Vector2, hull: PackedVector2Array) -> float:
	if hull.size() < 3:
		if hull.is_empty():
			return -1.0
		var best := INF
		for h in hull:
			best = min(best, pt.distance_to(h))
		return -best
	var inside := Geometry2D.is_point_in_polygon(pt, hull)
	var dist := INF
	for i in hull.size():
		var a := hull[i]
		var b := hull[(i + 1) % hull.size()]
		dist = min(dist, pt.distance_to(Geometry2D.get_closest_point_to_segment(pt, a, b)))
	return dist if inside else -dist


## The cheat that keeps a standing fighter upright: a capped torque on the
## pelvis and chest that fades out once the center of mass leaves the base.
func _upright_assist() -> void:
	var standing: bool = parts.pelvis.global_position.y > 0.6
	var target := 1.0 if standing and base_margin > -assist_give_up_margin else 0.0
	assist = move_toward(assist, target, 4.0 / Engine.physics_ticks_per_second)
	if assist <= 0.0:
		return
	for n in ["pelvis", "chest"]:
		var b: RigidBody3D = parts[n]
		var up := b.global_basis.y.normalized()
		var axis := up.cross(Vector3.UP)
		var tilt := asin(clampf(axis.length(), 0.0, 1.0))
		var torque := Vector3.ZERO
		if tilt > 0.0001:
			torque = axis.normalized() * tilt * upright_stiffness
		var w := b.angular_velocity
		w.y = 0.0
		torque -= w * upright_damping
		b.apply_torque(torque.limit_length(upright_max_torque) * assist)


## Once the balance assist has given up, the motors fade to a fraction of their
## strength so the fall is a goofy flop instead of a falling plank.
func _update_limp() -> void:
	var target := 1.0 if assist > 0.5 else floppy_strength
	limpness_scale = move_toward(limpness_scale, target, go_limp_rate / Engine.physics_ticks_per_second)


# --- Test helpers ------------------------------------------------------------

func shove(impulse: Vector3) -> void:
	parts.chest.apply_central_impulse(impulse)
