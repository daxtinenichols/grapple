class_name GripSystem
extends Node3D

## Grips between fighters. While a fighter's intent.grip[i] is held and that
## hand touches a part of another fighter, the hand grabs it: a stiff spring
## (a bit of gi slack) pulls the hand and the gripped spot together, with the
## force shared equally between both bodies. Pull too hard (the spot gets
## more than break_stretch away from the hand) and the grip tears loose; the
## trigger then has to be let go and pressed again to re-grip.
## Never writes a fighter's intent or its joints: it only adds forces.

## Spring stiffness (N/m) between the hand and the gripped spot.
@export var stiffness := 3500.0
## Damping ratio of that spring (0..1).
@export var damping_ratio := 0.5
## Most force (N) one grip can hold, times the gripping fighter's stamina.
@export var max_force := 650.0
## The grip tears when the spot is this far (m) from the hand for break_time.
@export var break_stretch := 0.17
@export var break_time := 0.08
## How close (m) the hand's center has to be to a part's surface to grab it.
@export var reach := 0.06
## Draw a small ball on each held grip.
@export var show_grips := true

signal grabbed(fighter: Fighter, hand: int, target: Fighter, part: RigidBody3D)
signal released(fighter: Fighter, hand: int, torn: bool)

var fighters: Array[Fighter] = []
## Live grips. Each: {fighter, hand, target (Fighter), body (RigidBody3D),
## anchor (Vector3, in the body's local frame), over (s past break_stretch), marker}
var grips: Array[Dictionary] = []
## Hands that tore loose and wait for the trigger to be let go: "<id>:<hand>".
var _torn := {}
var _probe := SphereShape3D.new()
var _marker_mesh: SphereMesh
var _marker_mat: StandardMaterial3D


func _ready() -> void:
	# Run after the fighters' controllers wrote the intent, before the fighters.
	process_physics_priority = -5
	_marker_mesh = SphereMesh.new()
	_marker_mesh.radius = 0.025
	_marker_mesh.height = 0.05
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.albedo_color = Color(1.0, 0.85, 0.1)
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.no_depth_test = true


func add_fighter(f: Fighter) -> void:
	if not fighters.has(f):
		fighters.append(f)


func remove_fighter(f: Fighter) -> void:
	fighters.erase(f)
	for g in grips.duplicate():
		if g.fighter == f or g.target == f:
			_release(g, false)


func clear() -> void:
	for g in grips.duplicate():
		_release(g, false)
	fighters.clear()
	_torn.clear()


## The grip a fighter's hand holds, or {} if none.
func holding(f: Fighter, hand: int) -> Dictionary:
	for g in grips:
		if g.fighter == f and g.hand == hand:
			return g
	return {}


## Grips other fighters hold on f.
func grips_on(f: Fighter) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in grips:
		if g.target == f:
			out.append(g)
	return out


## Name of the part a grip holds, without the side prefix kept ("l_forearm").
func part_name(g: Dictionary) -> String:
	return g.body.name if is_instance_valid(g.body) else ""


func _physics_process(delta: float) -> void:
	for f in fighters.duplicate():
		if not is_instance_valid(f) or f.is_queued_for_deletion():
			remove_fighter(f)
	for g in grips.duplicate():
		if not _valid(g) or not g.fighter.intent.grip[g.hand]:
			_release(g, false)
	for f in fighters:
		if not f.parts.has("l_hand"):
			continue
		for i in 2:
			var key := "%d:%d" % [f.get_instance_id(), i]
			if not f.intent.grip[i]:
				_torn.erase(key)
				continue
			if _torn.has(key) or not holding(f, i).is_empty():
				continue
			_try_grab(f, i)
	for g in grips.duplicate():
		_pull(g, delta)


func _valid(g: Dictionary) -> bool:
	return is_instance_valid(g.fighter) and is_instance_valid(g.target) and is_instance_valid(g.body) \
		and not g.fighter.is_queued_for_deletion() and not g.target.is_queued_for_deletion()


func _hand(f: Fighter, i: int) -> RigidBody3D:
	return f.parts["l_hand" if i == 0 else "r_hand"]


func _try_grab(f: Fighter, i: int) -> void:
	var hand := _hand(f, i)
	var space := hand.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	_probe.radius = reach + 0.04
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, hand.global_position)
	q.exclude = f.parts.values().map(func(p: RigidBody3D) -> RID: return p.get_rid())
	var best: RigidBody3D
	var best_d := INF
	for hit in space.intersect_shape(q, 16):
		var body := hit.collider as RigidBody3D
		if body == null or not (body.get_parent() is Fighter) or body.get_parent() == f:
			continue
		var d := hand.global_position.distance_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	if best == null:
		return
	var target: Fighter = best.get_parent()
	var anchor := best.to_local(hand.global_position)
	var g := {"fighter": f, "hand": i, "target": target, "body": best, "anchor": anchor, "over": 0.0, "marker": null}
	if show_grips:
		var m := MeshInstance3D.new()
		m.mesh = _marker_mesh
		m.material_override = _marker_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		m.global_position = hand.global_position
		g.marker = m
	grips.append(g)
	grabbed.emit(f, i, target, best)


func _pull(g: Dictionary, delta: float) -> void:
	var hand := _hand(g.fighter, g.hand)
	var body: RigidBody3D = g.body
	var spot: Vector3 = body.to_global(g.anchor)
	var stretch := spot - hand.global_position
	if stretch.length() > break_stretch:
		g.over += delta
		if g.over >= break_time:
			_release(g, true)
			return
	else:
		g.over = 0.0
	var v_spot := body.linear_velocity + body.angular_velocity.cross(spot - body.global_position)
	var m_eff := hand.mass * body.mass / (hand.mass + body.mass)
	var c := 2.0 * damping_ratio * sqrt(stiffness * m_eff)
	var f := stretch * stiffness + (v_spot - hand.linear_velocity) * c
	f = f.limit_length(max_force * clampf(g.fighter.stamina, 0.0, 1.0))
	hand.apply_central_force(f)
	body.apply_force(-f, spot - body.global_position)
	if g.marker:
		g.marker.global_position = spot


func _release(g: Dictionary, torn: bool) -> void:
	grips.erase(g)
	if is_instance_valid(g.marker):
		g.marker.queue_free()
	if torn and is_instance_valid(g.fighter):
		_torn["%d:%d" % [g.fighter.get_instance_id(), g.hand]] = true
	if is_instance_valid(g.fighter):
		released.emit(g.fighter, g.hand, torn)
