class_name Arena
extends Node3D

## Competition mat: an 8 x 8 m combat area inside a 2 m safety border, lights,
## and two spawn points facing each other. Watches fighters and signals when one
## leaves the combat area (the match resets both to the center; see match.gd).
## Pure scenery: nothing here touches fighter physics.

signal fighter_left_mat(fighter: Fighter)

## Side length (m) of the combat area. The mat's colors follow it.
@export var combat_size := 8.0:
	set(v):
		combat_size = v
		_sync_mat()
## A fighter is out when its pelvis is this far (m) past the combat edge.
@export var edge_margin := 0.0

var _watched: Array[Fighter] = []
var _out := {}


func _ready() -> void:
	_sync_mat()


## Start watching a fighter for the mat edge. Freed fighters drop out on their own.
func watch(f: Fighter) -> void:
	_watched.append(f)
	_out[f] = false


func clear_watch() -> void:
	_watched.clear()
	_out.clear()


## Spawn transform for fighter 0 (SpawnA) or 1 (SpawnB). Both face the center.
func spawn_transform(i: int) -> Transform3D:
	return ($SpawnA if i == 0 else $SpawnB).global_transform


## True while a world point is inside the combat area (height ignored).
func is_on_mat(p: Vector3) -> bool:
	var local := global_transform.affine_inverse() * p
	var half := combat_size * 0.5 + edge_margin
	return absf(local.x) <= half and absf(local.z) <= half


func _physics_process(_delta: float) -> void:
	for f in _watched.duplicate():
		if not is_instance_valid(f) or not f.is_inside_tree():
			_watched.erase(f)
			_out.erase(f)
			continue
		if not f.parts.has("pelvis"):
			continue
		var out := not is_on_mat(f.parts.pelvis.global_position)
		if out and not _out[f]:
			fighter_left_mat.emit(f)
		_out[f] = out


func _sync_mat() -> void:
	if not is_node_ready():
		return
	var m := ($Mat/Mesh as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	if m:
		m.set_shader_parameter("combat_half", combat_size * 0.5)
