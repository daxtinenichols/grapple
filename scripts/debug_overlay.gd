class_name DebugOverlay
extends MeshInstance3D

## Draws the fighter's center of mass, mat contacts and base polygon.
## Green base = balanced, red = the COM has left the base.

var fighter: Fighter
var _im := ImmediateMesh.new()


func _ready() -> void:
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	material_override = m


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	if not is_instance_valid(fighter) or fighter.base_hull.is_empty():
		return
	var ok := fighter.base_margin >= 0.0
	var col := Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3)
	var y := 0.01
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var hull := fighter.base_hull
	for i in hull.size():
		var a := hull[i]
		var b := hull[(i + 1) % hull.size()]
		_line(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), col)
	for p in fighter.base_points:
		_cross(Vector3(p.x, y, p.y), 0.02, Color(1, 1, 0.4))
	var c := fighter.com
	_line(c, Vector3(c.x, y, c.z), Color.WHITE)
	_cross(c, 0.06, Color.WHITE)
	_cross(Vector3(c.x, y, c.z), 0.05, col)
	_im.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_im.surface_set_color(c)
	_im.surface_add_vertex(a)
	_im.surface_set_color(c)
	_im.surface_add_vertex(b)


func _cross(p: Vector3, s: float, c: Color) -> void:
	_line(p - Vector3(s, 0, 0), p + Vector3(s, 0, 0), c)
	_line(p - Vector3(0, s, 0), p + Vector3(0, s, 0), c)
	_line(p - Vector3(0, 0, s), p + Vector3(0, 0, s), c)
