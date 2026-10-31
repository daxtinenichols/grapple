class_name DevKeys
extends Node3D

## Test-only keys, kept out of the player controls.
##   F small shove, G big shove, R reset, M reach drill (touch the three balls).

signal reset_requested

const SHOVE := 60.0
const BIG_SHOVE := 220.0
## Ball positions for the reach drill, in the fighter's heading frame from the chest.
const DRILL := [Vector3(-0.3, 0.15, -0.45), Vector3(0.35, -0.2, -0.4), Vector3(0.0, 0.3, -0.5)]
const TOUCH_RADIUS := 0.09

var fighter: Fighter
var camera: Camera3D
var drill_balls: Array[MeshInstance3D] = []
var drill_hit := 0


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset"):
		reset_requested.emit()
		return
	if not is_instance_valid(fighter):
		return
	if Input.is_action_just_pressed("shove"):
		fighter.shove(_shove_dir() * SHOVE)
	if Input.is_action_just_pressed("big_shove"):
		fighter.shove(_shove_dir() * BIG_SHOVE)
	_update_drill()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		if is_instance_valid(fighter):
			start_drill()


## Push away from the camera so the shove is easy to read.
func _shove_dir() -> Vector3:
	var d := -camera.global_basis.z
	d.y = 0.0
	return d.normalized()


func start_drill() -> void:
	clear_drill()
	var hb := fighter.heading_basis()
	var origin: Vector3 = fighter.parts.chest.global_position
	for p in DRILL:
		var ball := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = TOUCH_RADIUS * 0.6
		m.height = TOUCH_RADIUS * 1.2
		ball.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.55, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.2, 0.0)
		ball.material_override = mat
		add_child(ball)
		ball.global_position = origin + hb * p
		drill_balls.append(ball)
	drill_hit = 0


func clear_drill() -> void:
	for b in drill_balls:
		b.queue_free()
	drill_balls.clear()
	drill_hit = 0


## Balls must be touched in order. The current one glows; a touched one turns green.
func _update_drill() -> void:
	if drill_balls.is_empty() or drill_hit >= drill_balls.size():
		return
	var ball := drill_balls[drill_hit]
	(ball.material_override as StandardMaterial3D).emission = Color(1, 0.5, 0.0)
	for h in ["l_hand", "r_hand"]:
		if fighter.parts[h].global_position.distance_to(ball.global_position) < TOUCH_RADIUS:
			var mat := ball.material_override as StandardMaterial3D
			mat.albedo_color = Color(0.3, 1, 0.4)
			mat.emission = Color(0.1, 0.5, 0.1)
			drill_hit += 1
			return


func drill_status() -> String:
	if drill_balls.is_empty():
		return "M: reach drill"
	if drill_hit >= drill_balls.size():
		return "drill done%s  (M to go again)" % ("" if not fighter.has_fallen else ", but you fell")
	return "drill %d/%d" % [drill_hit, drill_balls.size()]
