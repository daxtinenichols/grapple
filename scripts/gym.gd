class_name Gym
extends Arena

## A small jiu jitsu gym around the competition square: wall-to-wall mats, padded
## walls, ceiling lights, windows, a belt rack, a bench, kettlebells and a
## grappling dummy. Everything here is static scenery; only the floor and the
## walls collide. Keeps the Arena API (spawns, mat edge signal).

## Inside size of the room (m), x by z.
@export var room_size := Vector2(16, 14)
@export var wall_height := 4.2
@export var pad_height := 1.8
@export var pad_color := Color(0.62, 0.12, 0.12)
@export var wall_color := Color(0.86, 0.84, 0.8)

var _mats := {}


func _ready() -> void:
	super()
	_mats = {
		"pad": _mat(pad_color, 0.7),
		"wall": _mat(wall_color, 0.9),
		"ceiling": _mat(Color(0.32, 0.32, 0.34), 0.9),
		"wood": _mat(Color(0.5, 0.33, 0.2), 0.7),
		"metal": _mat(Color(0.18, 0.18, 0.2), 0.4),
		"steel": _mat(Color(0.7, 0.7, 0.72), 0.3),
		"window": _glow(Color(0.75, 0.86, 1.0), 1.4),
		"panel": _glow(Color(1.0, 0.97, 0.9), 3.0),
		"white": _mat(Color(0.95, 0.95, 0.93), 0.5),
		"dummy": _mat(Color(0.12, 0.12, 0.13), 0.8),
		"cooler": _mat(Color(0.3, 0.55, 0.85), 0.2),
	}
	_build_room()
	_build_props()


func _build_room() -> void:
	var hx := room_size.x * 0.5
	var hz := room_size.y * 0.5
	var t := 0.3
	# The Mat body only collides over the middle 12 x 12 m, the size the movement
	# tests are tuned on (a bigger Jolt box changes the ground contacts); these
	# strips carry the rest of the room's floor.
	var border := StaticBody3D.new()
	border.name = "MatBorder"
	border.physics_material_override = ($Mat as StaticBody3D).physics_material_override
	add_child(border)
	var sx := (room_size.x - 12.0) * 0.5
	var sz := (room_size.y - 12.0) * 0.5
	for r in [
		[Vector3(0, -0.5, -6.0 - sz * 0.5), Vector3(room_size.x, 1, sz)],
		[Vector3(0, -0.5, 6.0 + sz * 0.5), Vector3(room_size.x, 1, sz)],
		[Vector3(-6.0 - sx * 0.5, -0.5, 0), Vector3(sx, 1, 12)],
		[Vector3(6.0 + sx * 0.5, -0.5, 0), Vector3(sx, 1, 12)],
	]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = r[1]
		cs.shape = b
		cs.position = r[0]
		border.add_child(cs)
	# Walls: solid boxes for collision, a padded strip and a painted upper part.
	var walls := [
		[Vector3(0, 0, -hz - t * 0.5), Vector3(room_size.x + t * 2, 0, t), Vector3(0, 0, 1)],
		[Vector3(0, 0, hz + t * 0.5), Vector3(room_size.x + t * 2, 0, t), Vector3(0, 0, -1)],
		[Vector3(-hx - t * 0.5, 0, 0), Vector3(t, 0, room_size.y), Vector3(1, 0, 0)],
		[Vector3(hx + t * 0.5, 0, 0), Vector3(t, 0, room_size.y), Vector3(-1, 0, 0)],
	]
	for w in walls:
		var pos: Vector3 = w[0]
		var size: Vector3 = w[1]
		var inward: Vector3 = w[2]
		var body := StaticBody3D.new()
		body.name = "Wall"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, wall_height, size.z)
		shape.shape = box
		body.add_child(shape)
		body.position = pos + Vector3(0, wall_height * 0.5 - 0.1, 0)
		add_child(body)
		_box("wall", Vector3(size.x, wall_height, size.z), pos + Vector3(0, wall_height * 0.5 - 0.1, 0))
		var pad_size := Vector3(size.x - t * 2, pad_height, 0.08) if inward.x == 0 else Vector3(0.08, pad_height, size.z)
		_box("pad", pad_size, pos + inward * (t * 0.5 + 0.04) + Vector3(0, pad_height * 0.5, 0))

	_box("ceiling", Vector3(room_size.x + t * 2, 0.2, room_size.y + t * 2), Vector3(0, wall_height, 0))
	# Ceiling light panels, each with a soft light under it.
	for x in [-4.0, 0.0, 4.0]:
		for z in [-3.5, 0.0, 3.5]:
			_box("panel", Vector3(1.6, 0.05, 0.6), Vector3(x, wall_height - 0.13, z))
			var l := OmniLight3D.new()
			l.position = Vector3(x, wall_height - 0.6, z)
			l.light_color = Color(1.0, 0.96, 0.9)
			l.light_energy = 1.1
			l.omni_range = 6.5
			l.omni_attenuation = 1.2
			add_child(l)
	# Windows high on the back wall.
	for x in [-5.0, -1.7, 1.7, 5.0]:
		_box("window", Vector3(2.2, 0.9, 0.04), Vector3(x, 3.1, -hz + 0.03))
		_box("white", Vector3(2.35, 0.08, 0.08), Vector3(x, 2.62, -hz + 0.05))


func _build_props() -> void:
	var hx := room_size.x * 0.5
	var hz := room_size.y * 0.5

	# Gym sign above the padding on the back wall.
	_box("pad", Vector3(4.6, 0.75, 0.05), Vector3(0, 2.25, -hz + 0.04))
	var sign := Label3D.new()
	sign.text = "GRAPPLE  JIU JITSU"
	sign.font_size = 96
	sign.pixel_size = 0.004
	sign.outline_size = 0
	sign.modulate = Color(0.97, 0.95, 0.9)
	sign.position = Vector3(0, 2.25, -hz + 0.075)
	add_child(sign)

	# Belt rack on the left wall: white, blue, purple, brown, black.
	var belts := [Color(0.95, 0.95, 0.93), Color(0.15, 0.3, 0.75), Color(0.4, 0.2, 0.6), Color(0.42, 0.25, 0.12), Color(0.06, 0.06, 0.06)]
	_box("wood", Vector3(0.06, 0.08, 2.4), Vector3(-hx + 0.06, 2.4, -2.0))
	for i in belts.size():
		var z := -3.0 + i * 0.5
		var m := _mat(belts[i], 0.7)
		var a := _box_m(m, Vector3(0.025, 0.7, 0.05), Vector3(-hx + 0.1, 2.05, z - 0.06))
		a.rotation_degrees.x = 6
		var b := _box_m(m, Vector3(0.025, 0.62, 0.05), Vector3(-hx + 0.1, 2.08, z + 0.06))
		b.rotation_degrees.x = -6
		if i == belts.size() - 1:
			_box_m(_mat(Color(0.75, 0.1, 0.1), 0.7), Vector3(0.03, 0.12, 0.055), Vector3(-hx + 0.1, 1.86, z - 0.04))

	# Clock on the right wall.
	var clock := _add(_cylinder(), "white", Vector3(hx - 0.05, 3.0, 0), Vector3(0.45, 0.04, 0.45))
	clock.rotation_degrees.z = 90
	_box("metal", Vector3(0.02, 0.16, 0.02), Vector3(hx - 0.08, 3.05, 0))
	_box("metal", Vector3(0.02, 0.02, 0.12), Vector3(hx - 0.08, 3.0, 0.05))

	# Bench along the right wall.
	_box("wood", Vector3(0.45, 0.06, 3.0), Vector3(hx - 0.45, 0.45, 2.5))
	for z in [1.2, 3.8]:
		_box("metal", Vector3(0.4, 0.42, 0.06), Vector3(hx - 0.45, 0.21, z))
	# Water bottles and a towel on the bench.
	for z in [1.8, 2.0, 3.1]:
		_add(_cylinder(), "cooler", Vector3(hx - 0.4, 0.58, z), Vector3(0.07, 0.2, 0.07))
	_box("white", Vector3(0.35, 0.03, 0.5), Vector3(hx - 0.45, 0.49, 2.6))

	# Kettlebells in the front right corner.
	for i in 4:
		var p := Vector3(hx - 0.5 - i * 0.45, 0, hz - 0.5)
		var s := 0.18 + i * 0.03
		_add(_sphere(), "metal", p + Vector3(0, s * 0.5, 0), Vector3(s, s * 0.95, s))
		var handle := _add(_torus(), "metal", p + Vector3(0, s * 1.05, 0), Vector3(s * 0.7, s * 0.7, s * 0.7))
		handle.rotation_degrees.x = 90

	# Water cooler by the door.
	_box("white", Vector3(0.35, 1.0, 0.35), Vector3(-hx + 0.4, 0.5, hz - 2.6))
	_add(_cylinder(), "cooler", Vector3(-hx + 0.4, 1.22, hz - 2.6), Vector3(0.28, 0.45, 0.28))

	# Door in the front wall, with shoes lined up outside the mat edge.
	_box("wood", Vector3(1.1, 2.2, 0.06), Vector3(-hx + 1.4, 1.0, hz - 0.03))
	_box("steel", Vector3(0.04, 0.04, 0.12), Vector3(-hx + 1.85, 1.0, hz - 0.08))
	var shoe_colors := [Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.1), Color(0.8, 0.25, 0.2), Color(0.25, 0.45, 0.8)]
	for i in shoe_colors.size():
		var m := _mat(shoe_colors[i], 0.6)
		for s in [-1, 1]:
			_box_m(m, Vector3(0.1, 0.08, 0.27), Vector3(-hx + 2.4 + i * 0.4 + s * 0.065, 0.04, hz - 0.3))

	# A grappling dummy slumped in the back left corner.
	var d := Vector3(-hx + 0.8, 0, -hz + 0.9)
	_add(_capsule(), "dummy", d + Vector3(0, 0.45, 0), Vector3(0.38, 0.6, 0.3), Vector3(-25, 30, 0))
	_add(_sphere(), "dummy", d + Vector3(0.12, 0.98, 0.25), Vector3(0.24, 0.26, 0.24))
	for s in [-1, 1]:
		_add(_capsule(), "dummy", d + Vector3(s * 0.25, 0.12, 0.55), Vector3(0.16, 0.7, 0.16), Vector3(80, 30 + s * 12, 0))
		_add(_capsule(), "dummy", d + Vector3(s * 0.32, 0.55, 0.2), Vector3(0.12, 0.5, 0.12), Vector3(30, 0, s * 25))

	# Stacked spare mats in the back right corner.
	for i in 5:
		_box_m(_mat(Color(0.18, 0.36, 0.62) if i % 2 == 0 else Color(0.2, 0.2, 0.22), 0.6),
			Vector3(1.0, 0.04, 2.0), Vector3(hx - 0.7, 0.02 + i * 0.045, -hz + 1.2))


# --- Helpers ----------------------------------------------------------------

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _add(mesh: Mesh, mat: String, pos: Vector3, scl := Vector3.ONE, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	add_child(mi)
	return mi


func _box(mat: String, size: Vector3, pos: Vector3) -> MeshInstance3D:
	return _add(_unit("box"), mat, pos, size)


func _box_m(m: Material, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := _box("wall", size, pos)
	mi.material_override = m
	return mi


func _sphere() -> Mesh:
	var m: SphereMesh = _unit("sphere")
	m.radius = 0.5
	m.height = 1.0
	return m


func _cylinder() -> Mesh:
	var m: CylinderMesh = _unit("cylinder")
	m.top_radius = 0.5
	m.bottom_radius = 0.5
	m.height = 1.0
	return m


func _capsule() -> Mesh:
	var m: CapsuleMesh = _unit("capsule")
	m.radius = 0.5
	m.height = 1.0
	return m


func _torus() -> Mesh:
	var m: TorusMesh = _unit("torus")
	m.inner_radius = 0.38
	m.outer_radius = 0.5
	return m


var _unit_cache := {}


func _unit(kind: String) -> Mesh:
	if not _unit_cache.has(kind):
		_unit_cache[kind] = {"box": BoxMesh, "sphere": SphereMesh, "cylinder": CylinderMesh,
			"capsule": CapsuleMesh, "torus": TorusMesh}[kind].new()
	return _unit_cache[kind]
