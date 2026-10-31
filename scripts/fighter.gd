class_name Fighter
extends Node3D

## Active ragdoll fighter: 15 rigid body parts joined by 6DOF joints.
## Every joint runs an angular velocity motor that chases a target pose, so the
## body is always physical and only "wants" to be in a pose.
## Faces -Z. The fighter's left side is -X.

signal fell

## Motor gain: how fast (1/s) a joint tries to close its angle error.
@export var pose_gain := 14.0
## Strength multiplier at full intent tension (Ctrl). Relaxed is 1.0.
@export var max_tension := 1.8
## How far (degrees) Q/E twists the abdomen and the chest each.
@export var turn_deg := 25.0
## How far (degrees) a full torso lean bends the abdomen (the chest bends 70% of it).
@export var lean_deg := 15.0
## How far (degrees) a full weight shift tilts the legs at the hips and ankles.
@export var weight_shift_deg := 4.0
## Knee bend (degrees) of a leg clamp. Kept under 90: see _build.
@export var clamp_knee_deg := 85.0
## Force (N) of a full foot_effort push.
@export var foot_muscle_force := 150
## Force (N) of a full hand_effort push.
@export var hand_muscle_force := 170.0
## How fast (1/s) the arm IK's copy of the chest follows the real chest.
@export var ik_chest_rate := 4.0
## Arm pose (degrees: flex, twist, out) the arms are built in; see _build.
@export var arm_build_pose := Vector3(50, 0, 0)
## Elbow bend (degrees) the arms are built with; see _build.
@export var elbow_build_flex := 60.0
## Where an elbow points while reaching, in the chest frame (x is mirrored per side).
@export var elbow_pole := Vector3(0.5, -1.0, 0.3)
## 0..1, scales strength. Drained by later milestones.
@export var stamina := 1.0
## Upright assist torque (Nm per rad) on pelvis and chest while standing.
@export var upright_stiffness := 900.0
@export var upright_damping := 90.0
@export var upright_max_torque := 450.0
## How far (m) the center of mass may leave the base before the assist gives up.
@export var assist_give_up_margin := 0.06

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

## Everything this fighter wants to do. Written by PlayerInput or the AI.
var intent := FighterIntent.new()
## Current strength multiplier, derived from intent.tension.
var tension := 1.0

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
## name -> entry in joints
var _joint_by_name := {}
## Arm chain per hand (index 0 left, 1 right): shoulder anchor in chest space, bone lengths.
var _arms: Array[Dictionary] = []
## The hidden target skeleton for each arm, for the overlay: shoulder, elbow, hand target.
var arm_ik: Array[Dictionary] = [{}, {}]
var _last_torso := Vector2.ZERO
var _last_legs := [Vector2.ZERO, false, false]
var _ik_chest := Quaternion.IDENTITY
var _ik_chest_fresh := true


func _ready() -> void:
	_build()


func _physics_process(_delta: float) -> void:
	update_base()
	_apply_intent()
	_drive_joints()
	_upright_assist()
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

	# Arms are built half-raised with the elbow half-bent (arm_build_pose,
	# elbow_build_flex), not hanging straight: Jolt's joint motors misbehave
	# (~90 deg+) away from the pose a joint was created in, so each joint's zero
	# sits in the middle of its working range. Targets still use the hanging,
	# straight arm as identity, and limits stay written for it.
	for d in defs:
		d["rot"] = Basis.IDENTITY
		if d.side != 0 and d.name.substr(2) in ["upper_arm", "forearm", "hand"]:
			var e := arm_build_pose
			var r := Basis.from_euler(Vector3(e.x, e.y * d.side, e.z * d.side) * (PI / 180.0))
			var shoulder: Vector3 = Vector3(LIMB[0].joint.x * d.side, LIMB[0].joint.y, LIMB[0].joint.z)
			var elbow: Vector3 = Vector3(LIMB[1].joint.x * d.side, LIMB[1].joint.y, LIMB[1].joint.z)
			var bend := Basis(Vector3.RIGHT, deg_to_rad(elbow_build_flex))
			if d.name.ends_with("upper_arm"):
				d.rot = r
				d.pos = shoulder + r * (d.pos - shoulder)
				d["build_offset"] = e
			else:
				var elbow_now := shoulder + r * (elbow - shoulder)
				d.rot = r * bend
				d.pos = elbow_now + d.rot * (d.pos - elbow)
				d.joint = elbow_now + d.rot * (d.joint - elbow)
				if d.name.ends_with("forearm"):
					d["build_offset"] = Vector3(elbow_build_flex, 0, 0)
	var rot_of := {}
	for d in defs:
		rot_of[d.name] = d.rot

	for d in defs:
		var body := _make_body(d)
		add_child(body)
		body.global_transform = global_transform * Transform3D(d.rot, d.pos)
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
		_make_joint(d, rot_of[d.parent])

	var by_name := {}
	for d in defs:
		by_name[d.name] = d
	for prefix in ["l_", "r_"]:
		var shoulder: Vector3 = by_name[prefix + "upper_arm"].joint
		var elbow: Vector3 = by_name[prefix + "forearm"].joint
		var hand: Vector3 = by_name[prefix + "hand"].pos
		_arms.append({
			"shoulder": parts.chest.global_transform.affine_inverse() * (global_transform * shoulder),
			"upper": shoulder.distance_to(elbow),
			"lower": elbow.distance_to(hand),
			"prefix": prefix,
		})


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


## The joint frame lines up with the parent's build pose. Limits are measured from
## the build pose, so a part built rotated (see arm_build_pose) has them shifted.
func _make_joint(d: Dictionary, parent_rot: Basis) -> void:
	var parent: RigidBody3D = parts[d.parent]
	var child: RigidBody3D = parts[d.name]
	var j := Generic6DOFJoint3D.new()
	j.name = "joint_" + d.name
	add_child(j)
	j.global_transform = Transform3D(global_basis * parent_rot, global_transform * d.joint)
	j.node_a = j.get_path_to(parent)
	j.node_b = j.get_path_to(child)

	var lim: Array = d.lim
	var side: int = d.side
	for axis in 3:
		var lo: float = lim[axis][0]
		var hi: float = lim[axis][1]
		if d.has("build_offset"):
			lo -= d.build_offset[axis]
			hi -= d.build_offset[axis]
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

	var entry := {
		"joint": j, "parent": parent, "child": child, "name": d.name,
		"target": Quaternion.IDENTITY, "strength": d.strength,
		# Which arm this joint belongs to (0 left, 1 right), -1 if none.
		"arm": (0 if d.side < 0 else 1) if d.name.substr(2) in ["upper_arm", "forearm", "hand"] else -1,
		"leg": (0 if d.side < 0 else 1) if d.name.substr(2) in ["thigh", "shin", "foot"] else -1,
	}
	joints.append(entry)
	_joint_by_name[d.name] = entry


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
	set_target_quat(part, Quaternion.from_euler(euler_deg * (PI / 180.0)))


func set_target_quat(part: String, q: Quaternion) -> void:
	if _joint_by_name.has(part):
		_joint_by_name[part].target = q


## The smoothed chest frame the arm IK works in. Controllers that place the hands
## relative to the body should use it too, so they agree with the IK.
func chest_frame() -> Basis:
	return Basis(_ik_chest) if not _ik_chest_fresh else parts.chest.global_basis.orthonormalized()


## Yaw-only frame of the fighter: -Z is where the pelvis faces, Y is world up.
func heading_basis() -> Basis:
	var f: Vector3 = -parts.pelvis.global_basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		f = -global_basis.z
	return Basis.looking_at(f.normalized(), Vector3.UP)


# --- Intent ------------------------------------------------------------------

func _apply_intent() -> void:
	tension = lerpf(1.0, max_tension, clampf(intent.tension, 0.0, 1.0))
	# Torso and idle arms are only touched when the intent changes, so poses set
	# with set_target (tests, later stance code) survive while the intent is idle.
	var torso := Vector2(clampf(intent.turn, -1.0, 1.0), clampf(intent.torso_lean, -1.0, 1.0))
	if torso != _last_torso:
		_last_torso = torso
		# Forward lean is negative flex for the spine (positive tips it back).
		set_target("abdomen", Vector3(-torso.y * lean_deg, -torso.x * turn_deg, 0))
		set_target("chest", Vector3(-torso.y * lean_deg * 0.7, -torso.x * turn_deg, 0))
	var legs := [intent.weight_shift.limit_length(1.0), intent.leg_clamp[0], intent.leg_clamp[1]]
	if legs != _last_legs:
		_last_legs = legs
		_set_leg_targets(legs[0], [legs[1], legs[2]])
	# The arm IK hangs off a smoothed copy of the chest. Using the live chest made
	# a loop: arm torque rocks the chest, which moves the arm targets, which
	# rocks the chest again, and the arms buzzed.
	var chest_q: Quaternion = parts.chest.global_basis.get_rotation_quaternion()
	var k := 1.0 - exp(-ik_chest_rate / Engine.physics_ticks_per_second)
	_ik_chest = chest_q if _ik_chest_fresh else _ik_chest.slerp(chest_q, k)
	_ik_chest_fresh = false
	for i in 2:
		var prefix: String = _arms[i].prefix
		if intent.hand_active[i]:
			_solve_arm(i, intent.hand_target[i])
			set_target_quat(prefix + "hand", Quaternion.IDENTITY)
		elif not arm_ik[i].is_empty():
			# Just let go of the target: drop back to the hanging rest pose.
			set_target_quat(prefix + "upper_arm", Quaternion.IDENTITY)
			set_target_quat(prefix + "forearm", Quaternion.IDENTITY)
			arm_ik[i] = {}
		_arm_muscle(i)
		_leg_muscle(i)


## Weight shift leans both legs so the hips move over the feet in that
## direction (feet stay flat), and a clamp bends that knee hard.
func _set_leg_targets(shift: Vector2, clamp: Array) -> void:
	# Hips go +x (right) / forward when the legs' bottoms swing the other way.
	var a := Vector3(shift.y * weight_shift_deg, 0, -shift.x * weight_shift_deg)
	for i in 2:
		var prefix := "l_" if i == 0 else "r_"
		var knee := -clamp_knee_deg if clamp[i] else 0.0
		set_target(prefix + "thigh", Vector3(-a.x, 0, a.z) + Vector3(-knee * 0.5, 0, 0))
		set_target(prefix + "shin", Vector3(knee, 0, 0))
		set_target(prefix + "foot", Vector3(a.x, 0, -a.z) + Vector3(-knee * 0.5, 0, 0))


## The muscle push: a force on the hand toward intent.hand_effort, with the
## equal and opposite force on the shoulder so the body can't push itself along.
func _arm_muscle(i: int) -> void:
	var e: Vector3 = intent.hand_effort[i].limit_length(1.0)
	if e.length_squared() < 0.0001:
		return
	var f := e * hand_muscle_force * tension * stamina
	var hand: RigidBody3D = parts[_arms[i].prefix + "hand"]
	var chest: RigidBody3D = parts.chest
	hand.apply_central_force(f)
	chest.apply_force(-f, chest.global_basis * _arms[i].shoulder)


## Same muscle push for a leg: force on the foot, reaction on the hip.
func _leg_muscle(i: int) -> void:
	var e: Vector3 = intent.foot_effort[i].limit_length(1.0)
	if e.length_squared() < 0.0001:
		return
	var f := e * foot_muscle_force * tension * stamina
	var prefix := "l_" if i == 0 else "r_"
	var foot: RigidBody3D = parts[prefix + "foot"]
	var pelvis: RigidBody3D = parts.pelvis
	var thigh: RigidBody3D = parts[prefix + "thigh"]
	foot.apply_central_force(f)
	pelvis.apply_force(-f, thigh.global_position + thigh.global_basis.y * 0.23 - pelvis.global_position)


## Two-bone IK on the hidden target skeleton: works out where the upper arm and
## forearm should point for the hand to reach `target`, anchored at the real
## chest, and sets those as joint targets. The motors and physics do the rest.
func _solve_arm(i: int, target: Vector3) -> void:
	var arm := _arms[i]
	var side := -1.0 if i == FighterIntent.LEFT else 1.0
	var chest: RigidBody3D = parts.chest
	var cb := Basis(_ik_chest)
	var s: Vector3 = chest.global_position + cb * arm.shoulder
	var l1: float = arm.upper
	var l2: float = arm.lower
	var to_t := target - s
	var d := clampf(to_t.length(), 0.08, l1 + l2 - 0.005)
	var u := to_t.normalized() if to_t.length() > 0.001 else -cb.y
	var pole := cb * Vector3(elbow_pole.x * side, elbow_pole.y, elbow_pole.z)
	var p_perp := pole - u * pole.dot(u)
	if p_perp.length_squared() < 0.0001:
		p_perp = cb.z - u * cb.z.dot(u)
	p_perp = p_perp.normalized()

	# Law of cosines: shoulder angle off the shoulder-target line, and elbow flex.
	var a := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var flex := PI - acos(clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0))
	var reach_t := s + u * d

	var upper_dir := (u * cos(a) + p_perp * sin(a)).normalized()
	var e := s + upper_dir * l1

	# Upper arm basis: local -Y runs down the bone, the forearm bends toward local -Z.
	var bend := (reach_t - e).normalized()
	bend = bend - upper_dir * bend.dot(upper_dir)
	if bend.length_squared() < 0.0001:
		bend = -p_perp
	var y := -upper_dir
	var z := -bend.normalized()
	var upper := Basis(y.cross(z), y, z).orthonormalized()

	set_target_quat(arm.prefix + "upper_arm", (cb.inverse() * upper).get_rotation_quaternion())
	set_target_quat(arm.prefix + "forearm", Quaternion(Vector3.RIGHT, flex))
	arm_ik[i] = {"shoulder": s, "elbow": e, "target": target, "reach": reach_t}


## Current rotation of a joint relative to its parent, in the parent frame.
func joint_rotation(j: Dictionary) -> Quaternion:
	var pb: Basis = j.parent.global_basis.orthonormalized()
	var cb: Basis = j.child.global_basis.orthonormalized()
	return (pb.inverse() * cb).get_rotation_quaternion()


func _drive_joints() -> void:
	var strength_scale := tension * stamina
	for j in joints:
		var err: Quaternion = j.target * joint_rotation(j).inverse()
		if err.w < 0.0:
			err = -err
		var angle := err.get_angle()
		var v := Vector3.ZERO
		if angle > 0.0001:
			v = err.get_axis() * angle * pose_gain
		var force: float = j.strength * strength_scale
		if j.arm >= 0:
			force *= clampf(intent.arm_tone[j.arm], 0.0, 1.0)
		elif j.leg >= 0:
			force *= clampf(intent.leg_tone[j.leg], 0.0, 1.0)
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
	# The chest is held at the torso lean the intent asks for, not bolt upright.
	var hb := heading_basis()
	var lean := deg_to_rad(clampf(intent.torso_lean, -1.0, 1.0) * lean_deg * 1.7)
	var chest_up := Vector3.UP.rotated(hb.x, -lean)
	for n in ["pelvis", "chest"]:
		var b: RigidBody3D = parts[n]
		var up := b.global_basis.y.normalized()
		var want := chest_up if n == "chest" else Vector3.UP
		var axis := up.cross(want)
		var tilt := asin(clampf(axis.length(), 0.0, 1.0))
		var torque := Vector3.ZERO
		if tilt > 0.0001:
			torque = axis.normalized() * tilt * upright_stiffness
		var w := b.angular_velocity
		w.y = 0.0
		torque -= w * upright_damping
		b.apply_torque(torque.limit_length(upright_max_torque) * assist)


# --- Test helpers ------------------------------------------------------------

func shove(impulse: Vector3) -> void:
	parts.chest.apply_central_impulse(impulse)
