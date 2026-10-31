class_name FighterSkin
extends Node3D

## Visual skin over a Fighter's ragdoll: gi jacket, pants, belt, bare hands and
## feet, and a goofy face with googly eyes. Every piece follows one rigid part's
## transform each frame. It adds no bodies, shapes or joints and never writes to
## the fighter; the only thing it changes is hiding the ragdoll's own debug meshes
## (K in the match scene shows them again).
##   var skin := FighterSkin.new(); add_child(skin); skin.attach(fighter)

@export var gi_color := Color(0.95, 0.94, 0.9)
@export var belt_color := Color(0.38, 0.2, 0.58)
@export var skin_tone := Color(0.87, 0.65, 0.5)
@export var hair_color := Color(0.2, 0.13, 0.08)
## Show the plain ragdoll parts instead of the skin.
@export var show_ragdoll := false:
	set(v):
		show_ragdoll = v
		_apply_visibility()
## How far (m) the pupils can roll inside the eyes, and how lively they are.
@export var pupil_travel := 0.013
@export var pupil_stiffness := 60.0
@export var pupil_damping := 5.0
## Render layer (1-20) for this fighter's head pieces. Give each fighter its own,
## so a first-person camera can leave out only its own head
## (camera.cull_mask &= ~skin.head_layer_mask()); the head still casts a shadow.
## Set it before attach().
@export_range(1, 20) var head_layer := 20

var fighter: Fighter
## Each entry: {node: Node3D, body: RigidBody3D}
var _follow: Array[Dictionary] = []
var _mats := {}
## Each entry: {node: MeshInstance3D, rest: Vector3, off: Vector2, vel: Vector2}
var _pupils: Array[Dictionary] = []
var _head_vel := Vector3.ZERO


func attach(f: Fighter) -> void:
	fighter = f
	_mats = {
		"gi": _mat(gi_color, 0.9),
		"trim": _mat(gi_color.darkened(0.07 if gi_color.get_luminance() > 0.7 else 0.25), 0.85),
		"belt": _mat(belt_color, 0.7),
		"skin": _mat(skin_tone, 0.6),
		"hair": _mat(hair_color, 0.8),
		"eye": _mat(Color(0.98, 0.98, 0.96), 0.3),
		"pupil": _mat(Color(0.05, 0.05, 0.06), 0.3),
		"mouth": _mat(Color(0.35, 0.1, 0.1), 0.7),
	}
	for part_name in f.parts:
		var body: RigidBody3D = f.parts[part_name]
		var root := Node3D.new()
		root.name = part_name
		root.top_level = true
		add_child(root)
		_build_part(part_name.trim_prefix("l_").trim_prefix("r_"), root)
		if part_name == "head":
			for mi in root.get_children():
				mi.layers = head_layer_mask()
		_follow.append({"node": root, "body": body})
	f.tree_exiting.connect(queue_free)
	_apply_visibility()
	_sync()


## Bit mask of head_layer, for a camera's cull_mask.
func head_layer_mask() -> int:
	return 1 << (head_layer - 1)


func _process(delta: float) -> void:
	_sync()
	_wobble_pupils(delta)


func _sync() -> void:
	for e in _follow:
		if is_instance_valid(e.body):
			e.node.global_transform = e.body.get_global_transform_interpolated()


func _apply_visibility() -> void:
	if not fighter:
		return
	for body in fighter.parts.values():
		for c in body.get_children():
			if c is MeshInstance3D:
				c.visible = show_ragdoll
	for e in _follow:
		e.node.visible = not show_ragdoll


# --- Pieces -----------------------------------------------------------------
# Positions are in each part's own frame: torso and head face -Z, limbs run
# along local Y (the hand and foot end is -Y).

func _build_part(kind: String, root: Node3D) -> void:
	match kind:
		"pelvis":
			_ellipsoid(root, "gi", Vector3(0.38, 0.27, 0.28), Vector3(0, -0.02, 0))
			_add(root, _cylinder(0.5, 0.56), "gi", Vector3(0, 0.03, 0), Vector3(0.39, 0.12, 0.29))
			_add(root, _cylinder(0.5, 0.5), "belt", Vector3(0, 0.085, 0), Vector3(0.375, 0.05, 0.275))
			_box(root, "belt", Vector3(0.065, 0.055, 0.035), Vector3(0, 0.085, -0.14))
			_box(root, "belt", Vector3(0.035, 0.15, 0.012), Vector3(-0.028, 0.02, -0.145), Vector3(0, 0, -12))
			_box(root, "belt", Vector3(0.035, 0.13, 0.012), Vector3(0.03, 0.025, -0.15), Vector3(0, 0, 15))
		"abdomen":
			_ellipsoid(root, "gi", Vector3(0.36, 0.34, 0.27))
			# Where the jacket's left side crosses over the right, down to the belt.
			_ellipsoid(root, "trim", Vector3(0.05, 0.3, 0.035), Vector3(0.035, -0.01, -0.126), Vector3(0, 0, 28))
		"chest":
			_ellipsoid(root, "gi", Vector3(0.48, 0.38, 0.3))
			for s in [-1, 1]:
				_ellipsoid(root, "trim", Vector3(0.06, 0.3, 0.045), Vector3(0.05 * s, 0.0, -0.136), Vector3(8, 0, -22 * s))
			_box(root, "trim", Vector3(0.2, 0.05, 0.05), Vector3(0, 0.17, 0.05), Vector3(20, 0, 0))
			_add(root, _capsule(0.045, 0.14), "skin", Vector3(0, 0.2, 0))
		"head":
			_ellipsoid(root, "skin", Vector3(0.25, 0.27, 0.25))
			var hair := _add(root, _hemisphere(), "hair", Vector3(0, 0.012, 0.008), Vector3(0.265, 0.27, 0.265), Vector3(28, 0, 0))
			hair.name = "Hair"
			for s in [-1, 1]:
				_ellipsoid(root, "skin", Vector3(0.03, 0.055, 0.04), Vector3(0.123 * s, 0, 0.01))
				_ellipsoid(root, "eye", Vector3(0.062, 0.068, 0.04), Vector3(0.043 * s, 0.022, -0.104))
				var pupil := _ellipsoid(root, "pupil", Vector3(0.028, 0.028, 0.012), Vector3(0.043 * s, 0.022, -0.125))
				_pupils.append({"node": pupil, "rest": pupil.position, "off": Vector2.ZERO, "vel": Vector2.ZERO})
				_box(root, "hair", Vector3(0.045, 0.011, 0.012), Vector3(0.045 * s, 0.068, -0.112), Vector3(0, 0, -14 * s))
			_ellipsoid(root, "skin", Vector3(0.036, 0.042, 0.04), Vector3(0, -0.012, -0.124))
			_box(root, "mouth", Vector3(0.05, 0.01, 0.012), Vector3(0, -0.058, -0.108), Vector3(0, 0, 4))
		"upper_arm":
			_add(root, _capsule(0.07, 0.38), "gi")
		"forearm":
			_add(root, _capsule(0.058, 0.27), "gi", Vector3(0, 0.025, 0))
			_add(root, _cylinder(0.5, 0.5), "trim", Vector3(0, -0.105, 0), Vector3(0.122, 0.025, 0.122))
			_add(root, _capsule(0.037, 0.12), "skin", Vector3(0, -0.12, 0))
		"hand":
			_ellipsoid(root, "skin", Vector3(0.06, 0.17, 0.1))
			_ellipsoid(root, "skin", Vector3(0.035, 0.075, 0.035), Vector3(0, 0.02, -0.05), Vector3(-25, 0, 0))
		"thigh":
			_add(root, _capsule(0.094, 0.52), "gi")
		"shin":
			_add(root, _capsule(0.076, 0.37), "gi", Vector3(0, 0.04, 0))
			_add(root, _cylinder(0.5, 0.5), "trim", Vector3(0, -0.13, 0), Vector3(0.158, 0.025, 0.158))
			_add(root, _capsule(0.045, 0.14), "skin", Vector3(0, -0.17, 0))
		"foot":
			_ellipsoid(root, "skin", Vector3(0.11, 0.085, 0.28), Vector3(0, 0, -0.01))


## Pupils roll like googly eyes: they sag with gravity and slosh when the head jerks.
func _wobble_pupils(delta: float) -> void:
	if _pupils.is_empty() or delta <= 0.0 or not fighter or not fighter.parts.has("head"):
		return
	var head: RigidBody3D = fighter.parts.head
	var accel := (head.linear_velocity - _head_vel) / delta
	_head_vel = head.linear_velocity
	var felt := head.global_basis.inverse() * (Vector3(0, -9.8, 0) - accel.limit_length(80.0))
	var push := Vector2(felt.x, felt.y) / 9.8
	for p in _pupils:
		p.vel += (push * pupil_travel * pupil_stiffness - p.off * pupil_stiffness - p.vel * pupil_damping) * delta
		p.off += p.vel * delta
		if p.off.length() > pupil_travel:
			p.off = p.off.limit_length(pupil_travel)
			p.vel *= 0.5
		p.node.position = p.rest + Vector3(p.off.x, p.off.y, 0)


# --- Helpers ----------------------------------------------------------------

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.4
	return m


func _add(root: Node3D, mesh: Mesh, mat: String, pos := Vector3.ZERO, scl := Vector3.ONE, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	root.add_child(mi)
	return mi


func _ellipsoid(root: Node3D, mat: String, size: Vector3, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	return _add(root, _unit_sphere(), mat, pos, size, rot_deg)


func _box(root: Node3D, mat: String, size: Vector3, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	return _add(root, _unit_box(), mat, pos, size, rot_deg)


static var _cache := {}


static func _unit_sphere() -> Mesh:
	if not _cache.has("sphere"):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		_cache.sphere = m
	return _cache.sphere


static func _hemisphere() -> Mesh:
	if not _cache.has("hemisphere"):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 0.5
		m.is_hemisphere = true
		_cache.hemisphere = m
	return _cache.hemisphere


static func _unit_box() -> Mesh:
	if not _cache.has("box"):
		_cache.box = BoxMesh.new()
	return _cache.box


static func _cylinder(top: float, bottom: float) -> Mesh:
	var key := "cyl%.3f_%.3f" % [top, bottom]
	if not _cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = 1.0
		_cache[key] = m
	return _cache[key]


static func _capsule(radius: float, height: float) -> Mesh:
	var key := "cap%.3f_%.3f" % [radius, height]
	if not _cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		_cache[key] = m
	return _cache[key]
