class_name Gym
extends Arena

## The room around the competition square, in three variants (N cycles them and
## the choice is remembered):
##   Academy: a jiu jitsu school with padded walls, belt rack, trophies, cubbies,
##     posters, ceiling fans and a round timer.
##   Garage gym: puzzle mats on concrete, block walls, a roll-up door, rafters,
##     swinging bulbs, a workbench, a heavy bag and an old couch.
##   Competition hall: the mat under spotlights, bleachers full of a crowd that
##     cheers when someone falls, scoreboards, sponsor boards and banners.
## Everything here is static scenery; only the floor and the walls collide. The
## Mat body always collides over the middle 12 x 12 m (the size the movement
## tests are tuned on); MatBorder strips carry any floor beyond that.
## Keeps the Arena API (spawns, mat edge signal).

signal variant_changed(variant_name: String)

enum Variant { ACADEMY, GARAGE, HALL }
const NAMES := ["Academy", "Garage gym", "Competition hall"]
const SETTINGS := "user://settings.cfg"

@export var variant := Variant.ACADEMY:
	set(v):
		variant = v
		if is_node_ready():
			_rebuild()
## Load and save the variant in user://settings.cfg.
@export var remember_choice := true
## Room tone volume (dB).
@export var ambience_db := -16.0

var room_size := Vector2(16, 14)
var _scenery: Node3D
var _mats := {}
var _ambience: AudioStreamPlayer
var _sfx: AudioStreamPlayer
## Things _process animates: {node, kind, ...}
var _animated: Array[Dictionary] = []
var _crowd_body: MultiMeshInstance3D
var _crowd_head: MultiMeshInstance3D
var _crowd_base: Array[Transform3D] = []
var _crowd_phase: PackedFloat32Array = []
var _cheer := 0.0
var _time := 0.0


func _ready() -> void:
	super()
	if remember_choice:
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS) == OK:
			variant = clampi(cfg.get_value("scene", "gym", variant), 0, NAMES.size() - 1)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	add_child(_ambience)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "Sfx"
	add_child(_sfx)
	fighter_left_mat.connect(func(_f): react(0.8))
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
		next_variant()


func next_variant() -> void:
	variant = (variant + 1) % NAMES.size()
	if remember_choice:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("scene", "gym", variant)
		cfg.save(SETTINGS)


func variant_name() -> String:
	return NAMES[variant]


func watch(f: Fighter) -> void:
	super(f)
	if f.has_signal("fell"):
		f.fell.connect(func(): react(1.0))


## The crowd (in the hall) cheers; strength 0..1.
func react(strength: float) -> void:
	_cheer = maxf(_cheer, strength)
	if variant == Variant.HALL and _sfx:
		_sfx.stream = FighterAudio.stream("cheer")
		_sfx.volume_db = lerpf(-14.0, -4.0, strength)
		_sfx.play()


func _process(delta: float) -> void:
	_time += delta
	_cheer = maxf(_cheer - delta * 0.4, 0.0)
	for a in _animated:
		var n: Node3D = a.node
		match a.kind:
			"spin":
				n.rotate_y(a.speed * delta)
			"swing":
				n.rotation.z = sin(_time * a.speed + a.phase) * a.amount
			"clock":
				var t := Time.get_time_dict_from_system()
				var sec: float = t.second
				var minute: float = t.minute + sec / 60.0
				var hour: float = fmod(t.hour, 12.0) + minute / 60.0
				a.hour.rotation.z = -hour / 12.0 * TAU
				a.minute.rotation.z = -minute / 60.0 * TAU
			"timer":
				var left := 300 - int(_time) % 300
				n.text = "%d:%02d" % [left / 60, left % 60]
	if _crowd_body:
		for i in _crowd_base.size():
			var hop := maxf(sin(_time * (2.0 + _cheer * 9.0) + _crowd_phase[i]), 0.0) * (0.015 + _cheer * 0.18)
			var t := _crowd_base[i]
			t.origin.y += hop
			_crowd_body.multimesh.set_instance_transform(i, t)
			var ht := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.22), t.origin + Vector3(0, 0.42, 0))
			_crowd_head.multimesh.set_instance_transform(i, ht)


# --- Building ----------------------------------------------------------------

func _rebuild() -> void:
	if _scenery:
		_scenery.free()
	_animated.clear()
	_crowd_body = null
	_crowd_head = null
	_crowd_base.clear()
	_scenery = Node3D.new()
	_scenery.name = "Scenery"
	add_child(_scenery)
	_mats = _base_materials()
	match variant:
		Variant.ACADEMY:
			_build_academy()
		Variant.GARAGE:
			_build_garage()
		Variant.HALL:
			_build_hall()
	_floor_border()
	variant_changed.emit(variant_name())


func _base_materials() -> Dictionary:
	return {
		"wood": _mat(Color(0.5, 0.33, 0.2), 0.7),
		"dark_wood": _mat(Color(0.3, 0.19, 0.12), 0.65),
		"metal": _mat(Color(0.18, 0.18, 0.2), 0.4),
		"steel": _metal(Color(0.72, 0.72, 0.74), 0.3),
		"gold": _metal(Color(0.95, 0.75, 0.25), 0.25),
		"white": _mat(Color(0.95, 0.95, 0.93), 0.5),
		"black": _mat(Color(0.05, 0.05, 0.06), 0.5),
		"red": _mat(Color(0.75, 0.12, 0.1), 0.5),
		"dummy": _mat(Color(0.12, 0.12, 0.13), 0.8),
		"cooler": _mat(Color(0.3, 0.55, 0.85), 0.15),
		"panel": _glow(Color(1.0, 0.97, 0.9), 3.0),
		"bulb": _glow(Color(1.0, 0.85, 0.55), 4.0),
		"window": _glow(Color(0.75, 0.86, 1.0), 1.4),
		"screen": _glow(Color(0.05, 0.06, 0.08), 0.2),
	}


## Sets up the mat mesh, its colors and the world lighting for a variant.
func _setup_mat(size: Vector2, combat: Color, safety: Color, checker := Color(0, 0, 0, 0), thickness := 0.1) -> void:
	var mesh_inst := $Mat/Mesh as MeshInstance3D
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, thickness, size.y)
	var sm := (mesh_inst.mesh.surface_get_material(0) as ShaderMaterial)
	if not sm:
		sm = mesh_inst.get_meta("mat") as ShaderMaterial
	mesh_inst.set_meta("mat", sm)
	bm.material = sm
	mesh_inst.mesh = bm
	mesh_inst.position.y = -thickness * 0.5
	sm.set_shader_parameter("combat_color", combat)
	sm.set_shader_parameter("safety_color", safety)
	sm.set_shader_parameter("checker_color", checker)
	sm.set_shader_parameter("combat_half", combat_size * 0.5)


func _setup_light(ambient: Color, ambient_energy: float, sun_energy: float, background: Color, fog := 0.0) -> void:
	var e: Environment = $WorldEnvironment.environment
	e.ambient_light_color = ambient
	e.ambient_light_energy = ambient_energy
	e.background_color = background
	e.fog_enabled = fog > 0.0
	e.fog_density = fog
	e.fog_light_color = background
	($Sun as DirectionalLight3D).light_energy = sun_energy


func _setup_ambience(sound: String) -> void:
	_ambience.stop()
	if sound == "":
		return
	_ambience.stream = FighterAudio.stream(sound)
	_ambience.volume_db = ambience_db
	_ambience.play()


## Static floor collision for whatever part of the room lies outside the Mat's 12 x 12 m.
func _floor_border() -> void:
	var sx := (room_size.x - 12.0) * 0.5
	var sz := (room_size.y - 12.0) * 0.5
	if sx <= 0.0 and sz <= 0.0:
		return
	var border := StaticBody3D.new()
	border.name = "MatBorder"
	border.physics_material_override = ($Mat as StaticBody3D).physics_material_override
	_scenery.add_child(border)
	var w := maxf(room_size.x, 12.0)
	var strips := []
	if sz > 0.0:
		strips.append([Vector3(0, -0.5, -6.0 - sz * 0.5), Vector3(w, 1, sz)])
		strips.append([Vector3(0, -0.5, 6.0 + sz * 0.5), Vector3(w, 1, sz)])
	if sx > 0.0:
		strips.append([Vector3(-6.0 - sx * 0.5, -0.5, 0), Vector3(sx, 1, 12)])
		strips.append([Vector3(6.0 + sx * 0.5, -0.5, 0), Vector3(sx, 1, 12)])
	for r in strips:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = r[1]
		cs.shape = b
		cs.position = r[0]
		border.add_child(cs)


## Four walls with collision. Each wall gets an optional lower band (padding, wainscot).
func _walls(height: float, wall_mat: String, band_mat := "", band_height := 0.0, t := 0.3) -> void:
	var hx := room_size.x * 0.5
	var hz := room_size.y * 0.5
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
		box.size = Vector3(size.x, height, size.z)
		shape.shape = box
		body.add_child(shape)
		body.position = pos + Vector3(0, height * 0.5 - 0.1, 0)
		_scenery.add_child(body)
		_box(wall_mat, Vector3(size.x, height, size.z), pos + Vector3(0, height * 0.5 - 0.1, 0))
		if band_mat != "":
			var bs := Vector3(size.x - t * 2, band_height, 0.08) if inward.x == 0 else Vector3(0.08, band_height, size.z)
			_box(band_mat, bs, pos + inward * (t * 0.5 + 0.04) + Vector3(0, band_height * 0.5, 0))


func _ceiling(height: float, mat: String) -> void:
	_box(mat, Vector3(room_size.x + 0.6, 0.2, room_size.y + 0.6), Vector3(0, height + 0.1, 0))


func _label(text: String, pos: Vector3, size: float, color: Color, rot_y_deg := 0.0, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = size / 96.0
	l.modulate = color
	l.outline_size = outline
	l.position = pos
	l.rotation_degrees.y = rot_y_deg
	_scenery.add_child(l)
	return l


func _omni(pos: Vector3, color: Color, energy: float, reach: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	_scenery.add_child(l)
	return l


# --- Academy -------------------------------------------------------------------

func _build_academy() -> void:
	room_size = Vector2(16, 14)
	var hx := room_size.x * 0.5
	var hz := room_size.y * 0.5
	var h := 4.2
	_mats["pad"] = _mat(Color(0.62, 0.12, 0.12), 0.7)
	_mats["wall"] = _mat(Color(0.86, 0.84, 0.8), 0.9)
	_mats["ceiling"] = _mat(Color(0.32, 0.32, 0.34), 0.9)
	_setup_mat(room_size, Color(0.16, 0.36, 0.64), Color(0.3, 0.3, 0.33))
	_setup_light(Color(0.75, 0.74, 0.72), 0.6, 0.55, Color(0.1, 0.1, 0.12))
	_setup_ambience("hvac_loop")
	_walls(h, "wall", "pad", 1.8)
	_ceiling(h, "ceiling")
	# Trim along the top of the padding.
	for z in [-hz + 0.09, hz - 0.09]:
		_box("dark_wood", Vector3(room_size.x - 0.6, 0.06, 0.04), Vector3(0, 1.83, z))
	for x in [-hx + 0.09, hx - 0.09]:
		_box("dark_wood", Vector3(0.04, 0.06, room_size.y), Vector3(x, 1.83, 0))
	# Ceiling light panels, each with a soft light under it, and two fans.
	for x in [-4.0, 0.0, 4.0]:
		for z in [-3.5, 0.0, 3.5]:
			_box("panel", Vector3(1.6, 0.05, 0.6), Vector3(x, h - 0.03, z))
			_omni(Vector3(x, h - 0.6, z), Color(1.0, 0.96, 0.9), 1.1, 6.5)
	for x in [-2.0, 2.0]:
		_fan(Vector3(x, h, -1.75), 0.9)
		_fan(Vector3(x, h, 1.75), 0.9)
	# Windows high on the back wall, and the gym sign.
	for x in [-5.0, -1.7, 1.7, 5.0]:
		_box("window", Vector3(2.2, 0.9, 0.04), Vector3(x, 3.1, -hz + 0.03))
		_box("white", Vector3(2.35, 0.08, 0.08), Vector3(x, 2.62, -hz + 0.05))
	_box("pad", Vector3(4.6, 0.75, 0.05), Vector3(0, 2.25, -hz + 0.04))
	_label("GRAPPLE  JIU JITSU", Vector3(0, 2.25, -hz + 0.075), 0.38, Color(0.97, 0.95, 0.9))

	# Belt rack on the left wall: white, blue, purple, brown, black.
	var belts := [Color(0.95, 0.95, 0.93), Color(0.15, 0.3, 0.75), Color(0.4, 0.2, 0.6), Color(0.42, 0.25, 0.12), Color(0.06, 0.06, 0.06)]
	_box("dark_wood", Vector3(0.06, 0.08, 2.4), Vector3(-hx + 0.06, 2.4, -2.0))
	for i in belts.size():
		var z := -3.0 + i * 0.5
		var m := _mat(belts[i], 0.7)
		var a := _box_m(m, Vector3(0.025, 0.7, 0.05), Vector3(-hx + 0.1, 2.05, z - 0.06))
		a.rotation_degrees.x = 6
		var b := _box_m(m, Vector3(0.025, 0.62, 0.05), Vector3(-hx + 0.1, 2.08, z + 0.06))
		b.rotation_degrees.x = -6
		_box("red" if i == belts.size() - 1 else "black", Vector3(0.03, 0.1, 0.055), Vector3(-hx + 0.1, 1.85, z - 0.04))

	# Posters on the left wall.
	var posters := [["TAP EARLY\nTAP OFTEN", Color(0.15, 0.3, 0.75)], ["POSITION\nBEFORE\nSUBMISSION", Color(0.1, 0.1, 0.1)], ["BREATHE", Color(0.85, 0.6, 0.15)]]
	for i in posters.size():
		var z := 0.8 + i * 1.6
		_box("dark_wood", Vector3(0.04, 1.0, 0.8), Vector3(-hx + 0.05, 2.75, z))
		_box_m(_mat(posters[i][1], 0.6), Vector3(0.045, 0.9, 0.7), Vector3(-hx + 0.06, 2.75, z))
		_label(posters[i][0], Vector3(-hx + 0.09, 2.75, z), 0.14, Color(0.97, 0.96, 0.92), 90)

	# Trophy shelf on the right wall.
	_box("dark_wood", Vector3(0.3, 0.05, 2.6), Vector3(hx - 0.2, 2.2, -3.5))
	for i in 7:
		var z := -4.6 + i * 0.37
		var s := 0.7 + 0.35 * float((i * 5) % 3) / 2.0
		_add(_cylinder(), "black", Vector3(hx - 0.2, 2.25, z), Vector3(0.09, 0.05, 0.09))
		_add(_cylinder(), "gold", Vector3(hx - 0.2, 2.3 + 0.07 * s, z), Vector3(0.03, 0.14 * s, 0.03))
		_add(_sphere(), "gold", Vector3(hx - 0.2, 2.38 + 0.14 * s, z), Vector3(0.12, 0.1, 0.12) * s)

	# Clock with real-time hands, and the round timer over the door.
	var clock := _add(_cylinder(), "white", Vector3(hx - 0.05, 3.0, 0), Vector3(0.45, 0.04, 0.45))
	clock.rotation_degrees.z = 90
	var face := Node3D.new()
	face.position = Vector3(hx - 0.09, 3.0, 0)
	face.rotation_degrees.y = -90
	_scenery.add_child(face)
	var hands := []
	for len_w in [[0.11, 0.022], [0.17, 0.014]]:
		var pivot := Node3D.new()
		face.add_child(pivot)
		var hand := MeshInstance3D.new()
		hand.mesh = _unit("box")
		hand.material_override = _mats.black
		hand.scale = Vector3(len_w[1], len_w[0], 0.01)
		hand.position.y = len_w[0] * 0.5
		pivot.add_child(hand)
		hands.append(pivot)
	_animated.append({"node": face, "kind": "clock", "hour": hands[0], "minute": hands[1]})
	_box("black", Vector3(1.0, 0.36, 0.08), Vector3(-hx + 1.4, 2.65, hz - 0.05))
	var timer := _label("5:00", Vector3(-hx + 1.4, 2.65, hz - 0.095), 0.3, Color(1.0, 0.2, 0.15), 180)
	_animated.append({"node": timer, "kind": "timer"})

	# Cubbies with gym bags, by the door.
	for c in 4:
		for r in 3:
			var p := Vector3(-hx + 2.6 + c * 0.55, 0.3 + r * 0.42, hz - 0.25)
			_box("wood", Vector3(0.53, 0.4, 0.4), p)
			_box("dark_wood", Vector3(0.45, 0.33, 0.02), p + Vector3(0, 0, -0.19))
			if (c + r * 2) % 3 != 0:
				var bag := _mat([Color(0.1, 0.1, 0.12), Color(0.7, 0.15, 0.15), Color(0.15, 0.35, 0.7), Color(0.85, 0.65, 0.15)][(c * 3 + r) % 4], 0.6)
				var m := _add(_capsule(), "black", p + Vector3(0, -0.04, -0.12), Vector3(0.18, 0.4, 0.18), Vector3(0, 0, 90))
				m.material_override = bag

	# Bench, bottles and towel along the right wall.
	_box("wood", Vector3(0.45, 0.06, 3.0), Vector3(hx - 0.45, 0.45, 2.5))
	for z in [1.2, 3.8]:
		_box("metal", Vector3(0.4, 0.42, 0.06), Vector3(hx - 0.45, 0.21, z))
	for z in [1.8, 2.0, 3.1]:
		_add(_cylinder(), "cooler", Vector3(hx - 0.4, 0.58, z), Vector3(0.07, 0.2, 0.07))
	_box("white", Vector3(0.35, 0.03, 0.5), Vector3(hx - 0.45, 0.49, 2.6))
	_kettlebells(Vector3(hx - 0.5, 0, hz - 0.5), Vector3(-0.45, 0, 0), 4)
	# Water cooler, door and shoes.
	_box("white", Vector3(0.35, 1.0, 0.35), Vector3(-hx + 0.4, 0.5, hz - 2.6 - 2.2))
	_add(_cylinder(), "cooler", Vector3(-hx + 0.4, 1.22, hz - 4.8), Vector3(0.28, 0.45, 0.28))
	_box("wood", Vector3(1.1, 2.2, 0.06), Vector3(-hx + 1.4, 1.0, hz - 0.03))
	_box("steel", Vector3(0.04, 0.04, 0.12), Vector3(-hx + 1.85, 1.0, hz - 0.08))
	_shoes(Vector3(-hx + 0.6, 0, hz - 1.0), 4)
	_dummy(Vector3(-hx + 0.8, 0, -hz + 0.9), 30)
	for i in 5:
		_box_m(_mat(Color(0.18, 0.36, 0.62) if i % 2 == 0 else Color(0.2, 0.2, 0.22), 0.6),
			Vector3(1.0, 0.04, 2.0), Vector3(hx - 0.7, 0.02 + i * 0.045, -hz + 1.2))


# --- Garage ---------------------------------------------------------------------

func _build_garage() -> void:
	room_size = Vector2(11, 10)
	var hx := room_size.x * 0.5
	var hz := room_size.y * 0.5
	var h := 2.9
	_mats["block"] = _blocks()
	_mats["concrete"] = _concrete()
	_mats["ceiling"] = _mat(Color(0.55, 0.5, 0.42), 0.9)
	_mats["door"] = _mat(Color(0.78, 0.78, 0.76), 0.5)
	_mats["peg"] = _mat(Color(0.62, 0.48, 0.32), 0.8)
	_setup_mat(Vector2(9, 9), Color(0.12, 0.12, 0.13), Color(0.22, 0.22, 0.24), Color(0.62, 0.1, 0.1, 1.0), 0.04)
	_setup_light(Color(1.0, 0.85, 0.65), 0.35, 0.0, Color(0.06, 0.05, 0.05))
	_setup_ambience("garage_loop")
	_walls(h, "block")
	_ceiling(h, "ceiling")
	# Concrete floor around the mats (the physics floor stays flat at y = 0).
	_box("concrete", Vector3(room_size.x, 0.02, room_size.y), Vector3(0, -0.05, 0))
	# Rafters.
	for x in range(-5, 6, 1):
		_box("wood", Vector3(0.08, 0.2, room_size.y), Vector3(x, h - 0.1, 0))
	# Swinging bulbs.
	for p in [Vector3(-2, 0, -1.5), Vector3(2, 0, 1.5), Vector3(-2.5, 0, 2.5)]:
		var pivot := Node3D.new()
		pivot.position = Vector3(p.x, h - 0.2, p.z)
		_scenery.add_child(pivot)
		var cord := MeshInstance3D.new()
		cord.mesh = _unit("box")
		cord.material_override = _mats.black
		cord.scale = Vector3(0.01, 0.6, 0.01)
		cord.position.y = -0.3
		pivot.add_child(cord)
		var bulb := MeshInstance3D.new()
		bulb.mesh = _sphere()
		bulb.material_override = _mats.bulb
		bulb.scale = Vector3.ONE * 0.09
		bulb.position.y = -0.64
		pivot.add_child(bulb)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.82, 0.55)
		light.light_energy = 1.6
		light.omni_range = 7.0
		light.shadow_enabled = true
		light.position.y = -0.72
		pivot.add_child(light)
		_animated.append({"node": pivot, "kind": "swing", "speed": 1.3 + p.x * 0.1, "phase": p.z, "amount": 0.06})

	# Roll-up door on the front wall, light leaking under it.
	for i in 9:
		_box("door", Vector3(4.2, 0.24, 0.06), Vector3(1.5, 0.25 + i * 0.26, hz - 0.04))
		_box("steel", Vector3(4.2, 0.02, 0.08), Vector3(1.5, 0.37 + i * 0.26, hz - 0.05))
	_box("window", Vector3(4.2, 0.08, 0.02), Vector3(1.5, 0.08, hz - 0.02))
	_omni(Vector3(1.5, 0.3, hz - 0.6), Color(0.75, 0.86, 1.0), 0.4, 3.0)

	# Workbench with a pegboard of tools on the back wall.
	_box("wood", Vector3(2.4, 0.08, 0.7), Vector3(-2.5, 0.9, -hz + 0.4))
	for x in [-3.6, -1.4]:
		_box("wood", Vector3(0.08, 0.9, 0.6), Vector3(x, 0.45, -hz + 0.4))
	_box("peg", Vector3(2.4, 1.0, 0.03), Vector3(-2.5, 1.6, -hz + 0.03))
	var tool_colors := [Color(0.85, 0.15, 0.1), Color(0.1, 0.3, 0.75), Color(0.95, 0.75, 0.1), Color(0.15, 0.15, 0.15)]
	for i in 7:
		_box_m(_mat(tool_colors[i % 4], 0.5), Vector3(0.05 + (i % 3) * 0.03, 0.25 + (i % 2) * 0.12, 0.03), Vector3(-3.4 + i * 0.3, 1.6, -hz + 0.06))
	_box("red", Vector3(0.5, 0.3, 0.3), Vector3(-2.0, 1.09, -hz + 0.35))
	for i in 3:
		_add(_cylinder(), "steel", Vector3(-3.3 + i * 0.22, 1.03, -hz + 0.45), Vector3(0.16, 0.18, 0.16))
	# Whiteboard with the schedule.
	_box("white", Vector3(1.4, 0.9, 0.03), Vector3(1.8, 1.7, -hz + 0.03))
	_label("OPEN MAT\nTUE / THU  7PM\nNO SHOES ON\nTHE MATS!!", Vector3(1.8, 1.7, -hz + 0.05), 0.11, Color(0.1, 0.2, 0.6))
	# Heavy bag from a rafter, a tire stack, an old couch and a mini fridge.
	var bag_pivot := Node3D.new()
	bag_pivot.position = Vector3(hx - 0.8, h - 0.2, -hz + 1.0)
	_scenery.add_child(bag_pivot)
	var chain := MeshInstance3D.new()
	chain.mesh = _unit("box")
	chain.material_override = _mats.steel
	chain.scale = Vector3(0.02, 0.5, 0.02)
	chain.position.y = -0.25
	bag_pivot.add_child(chain)
	var bag := MeshInstance3D.new()
	bag.mesh = _capsule()
	bag.material_override = _mats.red
	bag.scale = Vector3(0.36, 1.1, 0.36)
	bag.position.y = -1.05
	bag_pivot.add_child(bag)
	_animated.append({"node": bag_pivot, "kind": "swing", "speed": 0.9, "phase": 0.0, "amount": 0.03})
	for i in 3:
		var tire := _add(_torus(), "black", Vector3(hx - 0.7, 0.11 + i * 0.2, hz - 0.8), Vector3(0.65, 0.65, 0.65))
		tire.material_override = _mat(Color(0.06, 0.06, 0.06), 0.9)
	_box_m(_mat(Color(0.35, 0.42, 0.25), 0.9), Vector3(0.9, 0.45, 2.0), Vector3(-hx + 0.55, 0.22, 1.0))
	_box_m(_mat(Color(0.35, 0.42, 0.25), 0.9), Vector3(0.25, 0.5, 2.0), Vector3(-hx + 0.15, 0.6, 1.0))
	for z in [0.1, 1.9]:
		_box_m(_mat(Color(0.35, 0.42, 0.25), 0.9), Vector3(0.9, 0.3, 0.2), Vector3(-hx + 0.55, 0.55, z))
	_box("white", Vector3(0.55, 0.85, 0.55), Vector3(-hx + 0.4, 0.42, -hz + 0.5))
	_box("steel", Vector3(0.02, 0.25, 0.03), Vector3(-hx + 0.69, 0.6, -hz + 0.65))
	# Box fan on the floor, blades spinning.
	_box("black", Vector3(0.5, 0.5, 0.12), Vector3(hx - 0.5, 0.27, 1.2))
	var blades := Node3D.new()
	blades.position = Vector3(hx - 0.57, 0.27, 1.2)
	blades.rotation_degrees.z = 90
	_scenery.add_child(blades)
	for i in 3:
		var bl := MeshInstance3D.new()
		bl.mesh = _unit("box")
		bl.material_override = _mats.steel
		bl.scale = Vector3(0.08, 0.01, 0.2)
		bl.rotation_degrees.y = i * 120
		bl.position = Vector3(sin(deg_to_rad(i * 120)), 0, cos(deg_to_rad(i * 120))) * 0.1
		blades.add_child(bl)
	_animated.append({"node": blades, "kind": "spin", "speed": 18.0})
	_kettlebells(Vector3(-hx + 1.4, 0, hz - 0.4), Vector3(0.45, 0, 0), 3)
	_shoes(Vector3(-1.2, 0, hz - 0.45), 3)


# --- Competition hall ------------------------------------------------------------

func _build_hall() -> void:
	room_size = Vector2(32, 26)
	var hx := room_size.x * 0.5
	var hz := room_size.y * 0.5
	var h := 12.0
	_mats["wall"] = _mat(Color(0.12, 0.12, 0.15), 0.9)
	_mats["floor"] = _mat(Color(0.2, 0.2, 0.23), 0.6)
	_mats["ceiling"] = _mat(Color(0.05, 0.05, 0.06), 0.9)
	_mats["bleacher"] = _mat(Color(0.32, 0.33, 0.38), 0.6)
	_mats["board"] = _mat(Color(0.95, 0.95, 0.95), 0.5)
	_setup_mat(Vector2(12, 12), Color(0.12, 0.42, 0.72), Color(0.96, 0.78, 0.18), Color(0, 0, 0, 0), 0.06)
	_setup_light(Color(0.55, 0.58, 0.7), 0.25, 0.15, Color(0.03, 0.03, 0.05), 0.012)
	_setup_ambience("crowd_loop")
	_walls(h, "wall")
	_ceiling(h, "ceiling")
	_box("floor", Vector3(room_size.x, 0.02, room_size.y), Vector3(0, -0.07, 0))
	# Black skirt around the competition mat.
	for s in [-1, 1]:
		_box("black", Vector3(12.3, 0.06, 0.15), Vector3(0, -0.03, s * 6.07))
		_box("black", Vector3(0.15, 0.06, 12.3), Vector3(s * 6.07, -0.03, 0))
	# Spotlights on the mat from four corners high up.
	for c in [Vector3(-7, 10, -7), Vector3(7, 10, -7), Vector3(-7, 10, 7), Vector3(7, 10, 7)]:
		var l := SpotLight3D.new()
		l.position = c
		l.light_energy = 18.0
		l.light_color = Color(1.0, 0.97, 0.9)
		l.spot_range = 22.0
		l.spot_angle = 26.0
		l.shadow_enabled = c.x < 0 and c.z > 0
		_scenery.add_child(l)
		l.look_at(Vector3(0, 0, 0))
		var housing := _add(_cylinder(), "black", c, Vector3(0.5, 0.6, 0.5))
		housing.look_at_from_position(c, Vector3.ZERO, Vector3.UP)
		housing.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# Bleachers with the crowd on both long sides.
	var seats: Array[Transform3D] = []
	for s in [-1, 1]:
		for tier in 7:
			var x: float = s * (9.5 + tier * 0.8)
			var y := 0.25 + tier * 0.45
			_box("bleacher", Vector3(0.8, y * 2.0, 18.0), Vector3(x, y * 0.5 - 0.05, 0))
			for k in 30:
				if (k * 7 + tier * 3 + (1 if s > 0 else 0)) % 5 == 0:
					continue
				var z := -8.5 + k * 0.58 + randf_range(-0.05, 0.05)
				var basis := Basis(Vector3.UP, -s * PI * 0.5 + randf_range(-0.25, 0.25)).scaled(Vector3(0.38, 0.55, 0.3))
				seats.append(Transform3D(basis, Vector3(x, y + 0.3, z)))
	_crowd(seats)
	# Barrier boards with made-up sponsors around the mat area.
	var sponsors := ["SHRIMP CO.", "GOOFY GRAPPLE", "OSS ENERGY", "MAT CHAT", "BRIDGE BANK", "GUARD DOGS"]
	var i := 0
	for side in [[Vector3(0, 0.45, -8.0), 0.0, 14.0], [Vector3(0, 0.45, 8.0), 180.0, 14.0], [Vector3(-8.0, 0.45, 0), 90.0, 14.0], [Vector3(8.0, 0.45, 0), -90.0, 14.0]]:
		var center: Vector3 = side[0]
		var rot: float = side[1]
		var dir := Basis(Vector3.UP, deg_to_rad(rot)) * Vector3.RIGHT
		for k in 4:
			var p := center + dir * (-5.25 + k * 3.5)
			var board := _add(_unit("box"), "board", p, Vector3(3.3, 0.9, 0.06))
			board.rotation_degrees.y = rot
			var l := _label(sponsors[i % sponsors.size()], p + Basis(Vector3.UP, deg_to_rad(rot)) * Vector3(0, 0, 0.04), 0.22,
				[Color(0.12, 0.3, 0.7), Color(0.75, 0.12, 0.1), Color(0.1, 0.1, 0.1)][i % 3], rot)
			l.double_sided = false
			i += 1
	# Scoreboards hanging over the mat, one facing each way.
	for s in [-1, 1]:
		var p := Vector3(0, 6.5, s * 3.0)
		_box("black", Vector3(4.0, 1.6, 0.25), p)
		_box("screen", Vector3(3.8, 1.4, 0.02), p + Vector3(0, 0, s * 0.13))
		var rot := 0.0 if s > 0 else 180.0
		_label("WHITE   0   :   0   BLUE", p + Vector3(0, 0.3, s * 0.15), 0.26, Color(1, 1, 1), rot)
		var t := _label("5:00", p + Vector3(0, -0.32, s * 0.15), 0.42, Color(1.0, 0.8, 0.1), rot)
		_animated.append({"node": t, "kind": "timer"})
		_box("steel", Vector3(0.03, 5.5, 0.03), p + Vector3(-1.8, 3.5, 0))
		_box("steel", Vector3(0.03, 5.5, 0.03), p + Vector3(1.8, 3.5, 0))
	# Banners hanging from the ceiling, and the event banner on the back wall.
	var colors := [Color(0.75, 0.12, 0.1), Color(0.12, 0.3, 0.7), Color(0.95, 0.78, 0.18), Color(0.95, 0.95, 0.93)]
	for k in 8:
		var x := -10.5 + k * 3.0
		_box_m(_mat(colors[k % 4], 0.7), Vector3(1.2, 3.5, 0.03), Vector3(x, h - 2.0, -hz + 1.0))
	_box("black", Vector3(12, 2.0, 0.1), Vector3(0, 6.0, -hz + 0.1))
	_label("GRAPPLE OPEN 2026", Vector3(0, 6.0, -hz + 0.17), 1.1, Color(0.96, 0.78, 0.18))
	# Referee table with chairs and a laptop.
	_box("white", Vector3(2.4, 0.06, 0.8), Vector3(0, 0.75, 9.3))
	_box("black", Vector3(2.4, 0.72, 0.05), Vector3(0, 0.37, 8.92))
	for x in [-0.8, 0.0, 0.8]:
		_box("metal", Vector3(0.45, 0.05, 0.45), Vector3(x, 0.45, 9.9))
		_box("metal", Vector3(0.45, 0.5, 0.05), Vector3(x, 0.7, 10.12))
	_box("black", Vector3(0.38, 0.02, 0.26), Vector3(-0.5, 0.79, 9.3))
	var lid := _box("screen", Vector3(0.38, 0.26, 0.02), Vector3(-0.5, 0.92, 9.45))
	lid.rotation_degrees.x = -15
	# Dim house lights over the stands.
	for s in [-1, 1]:
		_omni(Vector3(s * 12.0, 7.0, 0), Color(0.6, 0.65, 0.85), 2.2, 16.0)


func _crowd(seats: Array[Transform3D]) -> void:
	var shirts := [Color(0.75, 0.12, 0.1), Color(0.12, 0.3, 0.7), Color(0.95, 0.78, 0.18), Color(0.95, 0.95, 0.93),
		Color(0.1, 0.1, 0.12), Color(0.2, 0.55, 0.3), Color(0.55, 0.3, 0.6)]
	var skins := [Color(0.95, 0.76, 0.62), Color(0.87, 0.65, 0.5), Color(0.72, 0.5, 0.36), Color(0.55, 0.37, 0.25), Color(0.4, 0.26, 0.17)]
	for part in ["body", "head"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _capsule() if part == "body" else _sphere()
		mm.instance_count = seats.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.8
		mmi.material_override = m
		_scenery.add_child(mmi)
		for k in seats.size():
			var c: Color = shirts[(k * 5 + k / 7) % shirts.size()] if part == "body" else skins[(k * 3 + k / 5) % skins.size()]
			mm.set_instance_color(k, c)
			mm.set_instance_transform(k, seats[k])
		if part == "body":
			_crowd_body = mmi
		else:
			_crowd_head = mmi
	_crowd_base = seats
	_crowd_phase.resize(seats.size())
	for k in seats.size():
		_crowd_phase[k] = randf() * TAU


# --- Props shared by variants -------------------------------------------------

func _fan(pos: Vector3, radius: float) -> void:
	_add(_cylinder(), "white", pos + Vector3(0, -0.25, 0), Vector3(0.03, 0.5, 0.03))
	_add(_cylinder(), "white", pos + Vector3(0, -0.52, 0), Vector3(0.22, 0.1, 0.22))
	var blades := Node3D.new()
	blades.position = pos + Vector3(0, -0.55, 0)
	_scenery.add_child(blades)
	for i in 4:
		var b := MeshInstance3D.new()
		b.mesh = _unit("box")
		b.material_override = _mats.wood
		b.scale = Vector3(0.14, 0.015, radius)
		b.rotation_degrees.y = i * 90
		b.position = Vector3(sin(deg_to_rad(i * 90)), 0, cos(deg_to_rad(i * 90))) * radius * 0.5
		blades.add_child(b)
	_animated.append({"node": blades, "kind": "spin", "speed": 4.5})


func _kettlebells(start: Vector3, step: Vector3, count: int) -> void:
	for i in count:
		var p := start + step * i
		var s := 0.18 + i * 0.03
		_add(_sphere(), "metal", p + Vector3(0, s * 0.5, 0), Vector3(s, s * 0.95, s))
		var handle := _add(_torus(), "metal", p + Vector3(0, s * 1.05, 0), Vector3(s * 0.7, s * 0.7, s * 0.7))
		handle.rotation_degrees.x = 90


func _shoes(start: Vector3, pairs: int) -> void:
	var colors := [Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.1), Color(0.8, 0.25, 0.2), Color(0.25, 0.45, 0.8)]
	for i in pairs:
		var m := _mat(colors[i % colors.size()], 0.6)
		for s in [-1, 1]:
			var shoe := _box_m(m, Vector3(0.1, 0.08, 0.27), start + Vector3(i * 0.4 + s * 0.065, 0.04, 0))
			shoe.rotation_degrees.y = randf_range(-15, 15)


func _dummy(at: Vector3, yaw: float) -> void:
	_add(_capsule(), "dummy", at + Vector3(0, 0.45, 0), Vector3(0.38, 0.6, 0.3), Vector3(-25, yaw, 0))
	_add(_sphere(), "dummy", at + Vector3(0.12, 0.98, 0.25), Vector3(0.24, 0.26, 0.24))
	for s in [-1, 1]:
		_add(_capsule(), "dummy", at + Vector3(s * 0.25, 0.12, 0.55), Vector3(0.16, 0.7, 0.16), Vector3(80, yaw + s * 12, 0))
		_add(_capsule(), "dummy", at + Vector3(s * 0.32, 0.55, 0.2), Vector3(0.12, 0.5, 0.12), Vector3(30, 0, s * 25))


# --- Materials and meshes -----------------------------------------------------

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _metal(c: Color, rough: float) -> StandardMaterial3D:
	var m := _mat(c, rough)
	m.metallic = 0.85
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Cinder block wall: grey blocks with mortar lines, mapped in world space.
func _blocks() -> StandardMaterial3D:
	var img := Image.create(128, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in 64:
		for x in 128:
			var row := y / 32
			var bx := (x + (32 if row % 2 else 0)) % 64
			var mortar := y % 32 < 2 or bx < 2
			var g := 0.62 + rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(0.75, 0.74, 0.7) if mortar else Color(g, g, g * 0.97))
	var m := _mat(Color(1, 1, 1), 0.95)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.6, 1.2, 0.6)
	return m


## Concrete: speckled grey with a few stains.
func _concrete() -> StandardMaterial3D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for y in 128:
		for x in 128:
			var stain := 0.06 * sin(x * 0.05 + y * 0.03) * sin(y * 0.07)
			var g := 0.5 + rng.randf_range(-0.05, 0.05) + stain
			img.set_pixel(x, y, Color(g, g * 0.98, g * 0.95))
	var m := _mat(Color(1, 1, 1), 0.85)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	return m


func _add(mesh: Mesh, mat: String, pos: Vector3, scl := Vector3.ONE, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	_scenery.add_child(mi)
	return mi


func _box(mat: String, size: Vector3, pos: Vector3) -> MeshInstance3D:
	return _add(_unit("box"), mat, pos, size)


func _box_m(m: Material, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := _box("white", size, pos)
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
