class_name FighterSkin
extends Node3D

## Visual skin over a Fighter's ragdoll: a lofted body in a gi (jacket with a
## thick collar and lapels, skirt, pants with knee patches, sleeves with cuffs,
## a belt with a rank bar, patches), hands whose fingers curl when gripping, bare
## feet with toes, and a goofy face that blinks, squints when tense and gapes
## when falling, with googly eyes. Every piece follows one rigid part's transform
## each frame. It adds no bodies, shapes or joints and never writes to the
## fighter; the only thing it changes is hiding the ragdoll's own debug meshes
## (K in the match scene shows them again). It also adds a FighterAudio.
##   var skin := FighterSkin.new(); skin.apply_look("blue"); add_child(skin); skin.attach(fighter)

## Ready-made looks for apply_look(). Any key missing falls back to the export.
const LOOKS := {
	"white": {"gi_color": Color(0.95, 0.94, 0.9), "belt_color": Color(0.38, 0.2, 0.58), "skin_tone": Color(0.87, 0.65, 0.5),
		"hair_color": Color(0.2, 0.13, 0.08), "hair_style": "short", "beard": false, "build": 0.4, "patch_color": Color(0.75, 0.12, 0.12), "voice_pitch": 1.0},
	"blue": {"gi_color": Color(0.16, 0.3, 0.68), "belt_color": Color(0.42, 0.25, 0.12), "skin_tone": Color(0.55, 0.37, 0.25),
		"hair_color": Color(0.08, 0.06, 0.05), "hair_style": "buzz", "beard": true, "build": 0.7, "patch_color": Color(0.95, 0.8, 0.2), "voice_pitch": 0.85},
	"black": {"gi_color": Color(0.1, 0.1, 0.11), "belt_color": Color(0.06, 0.06, 0.06), "skin_tone": Color(0.95, 0.76, 0.62),
		"hair_color": Color(0.85, 0.65, 0.3), "hair_style": "bun", "beard": false, "build": 0.2, "patch_color": Color(0.9, 0.9, 0.9), "voice_pitch": 1.25},
	"bald": {"gi_color": Color(0.95, 0.94, 0.9), "belt_color": Color(0.06, 0.06, 0.06), "skin_tone": Color(0.72, 0.5, 0.36),
		"hair_color": Color(0.35, 0.33, 0.32), "hair_style": "bald", "beard": true, "build": 1.0, "patch_color": Color(0.15, 0.3, 0.7), "voice_pitch": 0.75},
	"mohawk": {"gi_color": Color(0.16, 0.3, 0.68), "belt_color": Color(0.95, 0.95, 0.93), "skin_tone": Color(0.9, 0.7, 0.56),
		"hair_color": Color(0.85, 0.15, 0.4), "hair_style": "mohawk", "beard": false, "build": 0.0, "patch_color": Color(0.1, 0.1, 0.1), "voice_pitch": 1.15},
}

@export var gi_color := Color(0.95, 0.94, 0.9)
@export var belt_color := Color(0.38, 0.2, 0.58)
@export var skin_tone := Color(0.87, 0.65, 0.5)
@export var hair_color := Color(0.2, 0.13, 0.08)
@export_enum("short", "buzz", "bun", "mohawk", "bald") var hair_style := "short"
@export var beard := false
## 0 = lean, 1 = heavy. Only changes how thick the skin is drawn.
@export_range(0.0, 1.0) var build := 0.4
@export var patch_color := Color(0.75, 0.12, 0.12)
## Pitch of this fighter's grunts.
@export var voice_pitch := 1.0
## Add a FighterAudio for this fighter's sounds.
@export var with_sound := true
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
var audio: FighterAudio
## Each entry: {node: Node3D, body: RigidBody3D}
var _follow: Array[Dictionary] = []
var _mats := {}
## Each entry: {node: MeshInstance3D, rest: Vector3, off: Vector2, vel: Vector2}
var _pupils: Array[Dictionary] = []
var _head_vel := Vector3.ZERO
# Face pieces driven by the expression.
var _lids: Array[MeshInstance3D] = []
var _brows: Array[MeshInstance3D] = []
var _mouth: MeshInstance3D
var _teeth: MeshInstance3D
var _blink_in := 2.0
var _blink_t := 0.0
var _scared := 0.0
var _tense := 0.0
## Finger pivots per hand: index 0 left, 1 right.
var _fingers: Array = [[], []]
var _curl := [0.0, 0.0]


func apply_look(look_name: String) -> void:
	var look: Dictionary = LOOKS.get(look_name, {})
	for k in look:
		set(k, look[k])


func attach(f: Fighter) -> void:
	fighter = f
	_mats = {
		"gi": _cloth(gi_color),
		"trim": _cloth(gi_color.lightened(0.14) if gi_color.get_luminance() < 0.15 else gi_color.darkened(0.08 if gi_color.get_luminance() > 0.7 else 0.3)),
		"stitch": _cloth(gi_color.darkened(0.2) if gi_color.get_luminance() > 0.5 else gi_color.lightened(0.25)),
		"belt": _mat(belt_color, 0.7),
		"bar": _mat(Color(0.75, 0.08, 0.08) if belt_color.get_luminance() < 0.1 else Color(0.06, 0.06, 0.06), 0.6),
		"patch": _mat(patch_color, 0.6),
		"skin": _mat(skin_tone, 0.55),
		"skin_dark": _mat(skin_tone.darkened(0.12), 0.6),
		"hair": _mat(hair_color, 0.85),
		"eye": _mat(Color(0.98, 0.98, 0.96), 0.25),
		"pupil": _mat(Color(0.05, 0.05, 0.06), 0.2),
		"mouth": _mat(Color(0.3, 0.07, 0.08), 0.7),
		"teeth": _mat(Color(0.97, 0.96, 0.9), 0.3),
		"nail": _mat(skin_tone.lightened(0.25), 0.3),
	}
	for part_name in f.parts:
		var body: RigidBody3D = f.parts[part_name]
		var root := Node3D.new()
		root.name = part_name
		root.top_level = true
		add_child(root)
		var side := -1 if part_name.begins_with("l_") else (1 if part_name.begins_with("r_") else 0)
		_build_part(part_name.trim_prefix("l_").trim_prefix("r_"), root, side)
		if part_name == "head":
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				mi.layers = head_layer_mask()
		_follow.append({"node": root, "body": body})
	f.tree_exiting.connect(queue_free)
	if with_sound:
		audio = FighterAudio.new()
		audio.name = "Audio"
		audio.voice_pitch = voice_pitch
		add_child(audio)
		audio.attach(f)
	_apply_visibility()
	_sync()


## Bit mask of head_layer, for a camera's cull_mask.
func head_layer_mask() -> int:
	return 1 << (head_layer - 1)


func _process(delta: float) -> void:
	_sync()
	if not is_instance_valid(fighter):
		return
	_wobble_pupils(delta)
	_animate_face(delta)
	_animate_hands(delta)


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
# along local Y (the hand and foot end is -Y). Lofts are lists of
# [y, half width (x), half depth (z), z offset] rings.

func _build_part(kind: String, root: Node3D, side: int) -> void:
	var b := 1.0 + build * 0.18   # torso girth
	var lb := 1.0 + build * 0.12  # limb girth
	match kind:
		"pelvis":
			# Pants seat, then the jacket skirt flaring over it, then the belt.
			_loft(root, "gi", [[-0.13, 0.11, 0.09, 0.0], [-0.08, 0.17 * b, 0.13 * b, 0.0], [0.0, 0.185 * b, 0.135 * b, 0.0], [0.09, 0.17 * b, 0.125 * b, 0.0]])
			_loft(root, "gi", [[-0.085, 0.205 * b, 0.155 * b, 0.0], [0.0, 0.195 * b, 0.148 * b, 0.0], [0.07, 0.182 * b, 0.138 * b, 0.0]], false)
			_loft(root, "stitch", [[-0.09, 0.207 * b, 0.157 * b, 0.0], [-0.08, 0.207 * b, 0.157 * b, 0.0]], false)
			_loft(root, "belt", [[0.055, 0.19 * b, 0.143 * b, 0.0], [0.1, 0.183 * b, 0.137 * b, 0.0]])
			# Knot and tails, with the rank bar near the ends.
			var front := -0.14 * b
			_ellipsoid(root, "belt", Vector3(0.07, 0.06, 0.04), Vector3(0, 0.077, front))
			for s in [-1, 1]:
				var tail := Node3D.new()
				tail.position = Vector3(0.012 * s, 0.065, front - 0.008)
				tail.rotation_degrees = Vector3(-8, 0, 14 * s)
				root.add_child(tail)
				_box(tail, "belt", Vector3(0.042, 0.17, 0.012), Vector3(0, -0.085, 0))
				_box(tail, "bar", Vector3(0.044, 0.05, 0.014), Vector3(0, -0.13, 0))
		"abdomen":
			_loft(root, "gi", [[-0.14, 0.17 * b, 0.125 * b, 0.0], [0.0, 0.168 * b, 0.13 * b, 0.0], [0.13, 0.18 * b, 0.13 * b, 0.0]])
			# The left side of the jacket crossing over the right, down to the belt.
			_ellipsoid(root, "trim", Vector3(0.055, 0.3, 0.035), Vector3(0.03, -0.02, -0.122 * b), Vector3(0, 0, 26))
		"chest":
			_loft(root, "gi", [[-0.16, 0.175 * b, 0.128 * b, 0.0], [-0.06, 0.2 * b, 0.14 * b, 0.0], [0.04, 0.225 * b, 0.148 * b, -0.005],
				[0.11, 0.235 * b, 0.13 * b, 0.0], [0.16, 0.18 * b, 0.105, 0.01], [0.2, 0.07, 0.06, 0.01]])
			# Neck, then the thick collar around it and the two lapels down the front.
			_capsule_at(root, "skin", 0.048, 0.16, Vector3(0, 0.22, 0.005))
			var collar := _add(root, _torus(0.72), "trim", Vector3(0, 0.19, 0.0), Vector3(0.15, 0.13, 0.13))
			collar.rotation_degrees.x = -12
			for s in [-1, 1]:
				_ellipsoid(root, "trim", Vector3(0.065, 0.3, 0.05), Vector3(0.052 * s, 0.01, -0.14 * b), Vector3(10, 0, -24 * s))
			# Shoulder patch on the back, and a stitched seam down the spine.
			_box(root, "patch", Vector3(0.2, 0.09, 0.012), Vector3(0, 0.07, 0.143 * b))
			_box(root, "stitch", Vector3(0.012, 0.26, 0.01), Vector3(0, -0.05, 0.145 * b))
		"head":
			_build_head(root)
		"upper_arm":
			_loft(root, "gi", [[-0.19, 0.06 * lb, 0.06 * lb, 0.0], [-0.1, 0.066 * lb, 0.07 * lb, 0.0], [0.04, 0.075 * lb, 0.076 * lb, 0.0], [0.16, 0.082 * lb, 0.08 * lb, 0.0], [0.2, 0.06, 0.06, 0.0]])
			_ellipsoid(root, "gi", Vector3(0.15, 0.13, 0.15) * lb, Vector3(0, 0.14, 0))
			# Patch on the outside of the shoulder.
			_box(root, "patch", Vector3(0.012, 0.065, 0.06), Vector3(0.069 * lb * side, 0.06, 0))
		"forearm":
			# Loose sleeve, a cuff, then the bare wrist. The elbow ball hides the joint.
			_ellipsoid(root, "gi", Vector3(0.13, 0.12, 0.13) * lb, Vector3(0, 0.14, 0))
			_loft(root, "gi", [[-0.105, 0.058, 0.058, 0.0], [0.0, 0.062 * lb, 0.062 * lb, 0.0], [0.15, 0.066 * lb, 0.066 * lb, 0.0]])
			_loft(root, "trim", [[-0.112, 0.062, 0.062, 0.0], [-0.09, 0.062, 0.062, 0.0]])
			_loft(root, "skin", [[-0.19, 0.031, 0.036, 0.0], [-0.1, 0.038, 0.04, 0.0]])
		"hand":
			_build_hand(root, side)
		"thigh":
			_loft(root, "gi", [[-0.25, 0.075 * lb, 0.078 * lb, 0.0], [-0.12, 0.088 * lb, 0.09 * lb, -0.005], [0.08, 0.1 * lb, 0.105 * lb, -0.005], [0.24, 0.105 * lb, 0.11 * lb, 0.0]])
			# Reinforced knee patch at the bottom front, and a side seam.
			_ellipsoid(root, "trim", Vector3(0.12, 0.16, 0.06) * lb, Vector3(0, -0.2, -0.065 * lb))
			_box(root, "stitch", Vector3(0.01, 0.4, 0.01), Vector3(0.095 * lb * side, 0.0, 0))
			_box(root, "patch", Vector3(0.01, 0.08, 0.07), Vector3(0.1 * lb * side, 0.14, -0.01))
		"shin":
			_ellipsoid(root, "gi", Vector3(0.15, 0.13, 0.15) * lb, Vector3(0, 0.2, 0))
			_ellipsoid(root, "trim", Vector3(0.11, 0.12, 0.05) * lb, Vector3(0, 0.17, -0.06 * lb))
			_loft(root, "gi", [[-0.135, 0.068, 0.07, 0.0], [0.0, 0.075 * lb, 0.082 * lb, 0.008], [0.14, 0.075 * lb, 0.08 * lb, 0.0], [0.22, 0.072, 0.075, 0.0]])
			_loft(root, "trim", [[-0.142, 0.071, 0.073, 0.0], [-0.122, 0.071, 0.073, 0.0]])
			_loft(root, "skin", [[-0.215, 0.038, 0.042, 0.0], [-0.13, 0.044, 0.048, 0.0]])
		"foot":
			_ellipsoid(root, "skin", Vector3(0.105, 0.075, 0.26), Vector3(0, -0.005, -0.01))
			_ellipsoid(root, "skin", Vector3(0.085, 0.07, 0.09), Vector3(0, 0.0, 0.085))
			_ellipsoid(root, "skin_dark", Vector3(0.05, 0.05, 0.05), Vector3(0.045 * side, 0.03, 0.03))
			for i in 5:
				var x := (0.034 - i * 0.017) * -side
				var s := 0.026 if i == 0 else 0.019
				_ellipsoid(root, "skin", Vector3(s, s * 0.9, s * 1.1), Vector3(x, -0.018, -0.135 + absf(i - 0.5) * 0.004))


func _build_head(root: Node3D) -> void:
	_ellipsoid(root, "skin", Vector3(0.25, 0.27, 0.25))
	# Jaw and chin, a little wider and further forward for a goofy profile.
	_ellipsoid(root, "skin", Vector3(0.21, 0.13, 0.2), Vector3(0, -0.07, -0.025))
	match hair_style:
		"short":
			_add(root, _hemisphere(), "hair", Vector3(0, 0.012, 0.008), Vector3(0.265, 0.28, 0.265), Vector3(28, 0, 0))
			_ellipsoid(root, "hair", Vector3(0.12, 0.05, 0.06), Vector3(0.035, 0.115, -0.08), Vector3(0, 0, -20))
		"buzz":
			_add(root, _hemisphere(), "hair", Vector3(0, 0.02, 0.012), Vector3(0.256, 0.262, 0.256), Vector3(32, 0, 0))
		"bun":
			_add(root, _hemisphere(), "hair", Vector3(0, 0.012, 0.008), Vector3(0.265, 0.28, 0.265), Vector3(25, 0, 0))
			_ellipsoid(root, "hair", Vector3(0.1, 0.09, 0.1), Vector3(0, 0.1, 0.11))
			_ellipsoid(root, "hair", Vector3(0.27, 0.2, 0.24), Vector3(0, 0.0, 0.035))
		"mohawk":
			for i in 6:
				var a := deg_to_rad(-40 + i * 24)
				_ellipsoid(root, "hair", Vector3(0.035, 0.09, 0.05), Vector3(0, cos(a) * 0.135, sin(a) * 0.135), Vector3(rad_to_deg(a), 0, 0))
		"bald":
			_ellipsoid(root, "hair", Vector3(0.24, 0.12, 0.2), Vector3(0, -0.01, 0.04))
	if beard:
		_ellipsoid(root, "hair", Vector3(0.215, 0.12, 0.19), Vector3(0, -0.085, -0.03))
		_ellipsoid(root, "skin", Vector3(0.11, 0.06, 0.05), Vector3(0, -0.062, -0.112))
	for s in [-1, 1]:
		_ellipsoid(root, "skin", Vector3(0.03, 0.06, 0.042), Vector3(0.124 * s, -0.005, 0.01))
		_ellipsoid(root, "skin_dark", Vector3(0.012, 0.035, 0.025), Vector3(0.137 * s, -0.005, 0.01))
		_ellipsoid(root, "eye", Vector3(0.064, 0.07, 0.04), Vector3(0.043 * s, 0.022, -0.104))
		var pupil := _ellipsoid(root, "pupil", Vector3(0.028, 0.028, 0.012), Vector3(0.043 * s, 0.022, -0.125))
		_pupils.append({"node": pupil, "rest": pupil.position, "off": Vector2.ZERO, "vel": Vector2.ZERO})
		var lid := _ellipsoid(root, "skin", Vector3(0.07, 0.02, 0.046), Vector3(0.043 * s, 0.058, -0.106))
		lid.set_meta("side", s)
		_lids.append(lid)
		var brow := _box(root, "hair" if hair_style != "bald" else "skin_dark", Vector3(0.05, 0.012, 0.014), Vector3(0.045 * s, 0.072, -0.113))
		brow.set_meta("side", s)
		_brows.append(brow)
		_ellipsoid(root, "skin_dark", Vector3(0.04, 0.025, 0.02), Vector3(0.07 * s, -0.03, -0.108))
	_ellipsoid(root, "skin", Vector3(0.036, 0.046, 0.044), Vector3(0, -0.01, -0.126))
	_mouth = _ellipsoid(root, "mouth", Vector3(0.055, 0.012, 0.02), Vector3(0, -0.062, -0.117))
	_teeth = _box(root, "teeth", Vector3(0.05, 0.012, 0.01), Vector3(0, -0.062, -0.124))
	_teeth.visible = false


func _build_hand(root: Node3D, side: int) -> void:
	# The hand's thin axis is x (palm faces the body when hanging), width is z,
	# fingers point down -Y. Thumb on the front (-Z) edge.
	var palm_dir := -side
	_ellipsoid(root, "skin", Vector3(0.05, 0.11, 0.092), Vector3(0, 0.02, 0))
	var list: Array = _fingers[0 if side < 0 else 1]
	for i in 4:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, -0.03, -0.03 + i * 0.02)
		pivot.set_meta("dir", palm_dir)
		root.add_child(pivot)
		var length: float = [0.06, 0.068, 0.064, 0.05][i]
		_capsule_at(pivot, "skin", 0.0115, length, Vector3(0, -length * 0.5, 0))
		_ellipsoid(pivot, "nail", Vector3(0.006, 0.014, 0.014), Vector3(-palm_dir * 0.009, -length + 0.012, 0))
		list.append(pivot)
	var thumb := Node3D.new()
	thumb.position = Vector3(palm_dir * 0.012, 0.03, -0.045)
	thumb.rotation_degrees = Vector3(-30, 0, 20 * palm_dir)
	thumb.set_meta("dir", palm_dir)
	thumb.set_meta("thumb", true)
	root.add_child(thumb)
	_capsule_at(thumb, "skin", 0.014, 0.065, Vector3(0, -0.03, 0))
	list.append(thumb)


# --- Animation -------------------------------------------------------------

## Pupils roll like googly eyes: they sag with gravity and slosh when the head jerks.
func _wobble_pupils(delta: float) -> void:
	if _pupils.is_empty() or delta <= 0.0 or not fighter.parts.has("head"):
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


## Blinks now and then, squints and grits teeth when tense, gapes when flying.
func _animate_face(delta: float) -> void:
	if _lids.is_empty() or not fighter.parts.has("head"):
		return
	var tension := 0.0
	if "intent" in fighter and fighter.intent:
		tension = clampf(fighter.intent.tension, 0.0, 1.0)
	_tense = lerpf(_tense, tension, 1.0 - exp(-delta * 8.0))
	var speed: float = fighter.parts.head.linear_velocity.length()
	var scared_target := clampf((speed - 1.6) / 2.0, 0.0, 1.0)
	_scared = maxf(scared_target, _scared - delta * 1.5)

	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_t = 0.13
		_blink_in = randf_range(1.8, 5.0)
	_blink_t = maxf(_blink_t - delta, 0.0)
	var close := 0.18 + _tense * 0.4 - _scared * 0.18
	if _blink_t > 0.0:
		close = 1.0
	close = clampf(close, 0.0, 1.0)
	for lid in _lids:
		# The lid's top edge stays at the top of the eye; it grows down to cover it.
		var h := lerpf(0.012, 0.074, close)
		lid.scale.y = h
		lid.position.y = 0.022 + 0.035 - h * 0.5 + 0.003
	for brow in _brows:
		var s: int = brow.get_meta("side")
		brow.rotation_degrees.z = s * (_tense * 22.0 - _scared * 18.0) - s * 6.0
		brow.position.y = 0.072 + _scared * 0.014 - _tense * 0.006
	var open := _scared
	_mouth.scale = Vector3(lerpf(0.055, 0.04, open) + _tense * 0.02, lerpf(0.012, 0.042, open), 0.02)
	_teeth.visible = _tense > 0.5 and open < 0.3


## Fingers curl closed while the hand grips.
func _animate_hands(delta: float) -> void:
	var grip := [false, false]
	if "intent" in fighter and fighter.intent and "grip" in fighter.intent:
		grip = fighter.intent.grip
	for i in 2:
		_curl[i] = move_toward(_curl[i], 1.0 if grip[i] else 0.15, delta * 6.0)
		for pivot in _fingers[i]:
			var dir: int = pivot.get_meta("dir")
			if pivot.has_meta("thumb"):
				pivot.rotation_degrees.y = dir * _curl[i] * 35.0
			else:
				pivot.rotation_degrees.z = dir * _curl[i] * 100.0


# --- Helpers ----------------------------------------------------------------

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.4
	return m


## Cotton: matte, with a fine weave in the normal map.
func _cloth(c: Color) -> StandardMaterial3D:
	var m := _mat(c, 0.92)
	m.normal_enabled = true
	m.normal_texture = _weave()
	m.normal_scale = 0.35
	m.uv1_scale = Vector3(6, 6, 1)
	return m


static var _weave_tex: Texture2D


static func _weave() -> Texture2D:
	if not _weave_tex:
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for y in 64:
			for x in 64:
				# Over-under threads: alternate a horizontal and vertical bump per cell.
				var cx := (x % 8) / 8.0
				var cy := (y % 8) / 8.0
				var over := ((x / 8) + (y / 8)) % 2 == 0
				var nx := sin(cx * TAU) * (0.35 if over else 0.1)
				var ny := sin(cy * TAU) * (0.1 if over else 0.35)
				img.set_pixel(x, y, Color(0.5 + nx * 0.5, 0.5 + ny * 0.5, 1.0))
		_weave_tex = ImageTexture.create_from_image(img)
	return _weave_tex


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


func _capsule_at(root: Node3D, mat: String, radius: float, height: float, pos := Vector3.ZERO) -> MeshInstance3D:
	return _add(root, _capsule(radius, height), mat, pos)


## A smooth tube through elliptical rings ([y, half x, half z, z offset]), with caps.
func _loft(root: Node3D, mat: String, rings: Array, caps := true) -> MeshInstance3D:
	var key := "loft%s%s" % [str(rings), caps]
	if not _cache.has(key):
		_cache[key] = _make_loft(rings, caps)
	return _add(root, _cache[key], mat)


static func _make_loft(rings: Array, caps: bool) -> Mesh:
	const SEG := 24
	# Round the ends off with a few shrinking rings (a squashed half-ellipsoid),
	# closing on a tiny ring, so lofts end in smooth domes.
	var all: Array = rings.duplicate()
	if caps:
		for end in [0, 1]:
			var r: Array = rings[0] if end == 0 else rings[-1]
			var dir := -1.0 if end == 0 else 1.0
			var depth := minf(r[1], r[2]) * 0.8
			for j in range(1, 6):
				var f := j / 5.0 * PI * 0.5
				var k := maxf(cos(f), 0.02)
				var ring := [r[0] + dir * sin(f) * depth, r[1] * k, r[2] * k, r[3]]
				if end == 0:
					all.push_front(ring)
				else:
					all.push_back(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0: float = all[0][0]
	var y1: float = all[-1][0]
	# Rings share their first and last vertex so the normals stay smooth all round.
	for r in all:
		for i in SEG:
			var a := TAU * i / SEG
			st.set_uv(Vector2(absf(float(i) / SEG - 0.5) * 4.0, (r[0] - y0) / maxf(y1 - y0, 0.01)))
			st.add_vertex(Vector3(r[1] * sin(a), r[0], r[2] * cos(a) + r[3]))
	for k in all.size() - 1:
		for i in SEG:
			var a := k * SEG + i
			var a1 := k * SEG + (i + 1) % SEG
			st.add_index(a)
			st.add_index(a + SEG)
			st.add_index(a1)
			st.add_index(a1)
			st.add_index(a + SEG)
			st.add_index(a1 + SEG)
	st.generate_normals()
	return st.commit()


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


static func _torus(inner: float) -> Mesh:
	var key := "torus%.2f" % inner
	if not _cache.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner * 0.5
		m.outer_radius = 0.5
		_cache[key] = m
	return _cache[key]


static func _capsule(radius: float, height: float) -> Mesh:
	var key := "cap%.3f_%.3f" % [radius, height]
	if not _cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(height, radius * 2.0)
		_cache[key] = m
	return _cache[key]
