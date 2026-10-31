class_name CameraRig
extends Camera3D

## Orbit camera that smoothly follows a fighter. PlayerInput sends it mouse
## motion and wheel steps when no arm button is held. J / L also orbit.

@export var target: Fighter
@export var sensitivity := 0.005
@export var distance := 3.2
@export var min_distance := 1.4
@export var max_distance := 7.0
@export var min_pitch := -0.2
@export var max_pitch := 1.2
## How fast (1/s) the camera catches up with the fighter. Lower is floatier.
@export var follow_rate := 6.0
## Height of the point the camera looks at, blended with the pelvis height.
@export var focus_height := 0.9

var yaw := 0.6
var pitch := 0.12
var _focus := Vector3(0, 0.9, 0)
var _snap := true


func _ready() -> void:
	# Moved every rendered frame from interpolated positions, so it must not be
	# interpolated again.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func orbit(pixels: Vector2) -> void:
	yaw -= pixels.x * sensitivity
	pitch = clampf(pitch + pixels.y * sensitivity, min_pitch, max_pitch)


func zoom(steps: float) -> void:
	distance = clampf(distance * pow(0.9, steps), min_distance, max_distance)


## Jump straight to the fighter on the next frame (after a reset).
func snap() -> void:
	_snap = true


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_J):
		yaw -= delta * 1.5
	if Input.is_key_pressed(KEY_L):
		yaw += delta * 1.5
	if not is_instance_valid(target) or not target.parts.has("pelvis"):
		return
	var pelvis: Vector3 = target.parts.pelvis.get_global_transform_interpolated().origin
	var want := Vector3(pelvis.x, lerpf(focus_height, pelvis.y, 0.5), pelvis.z)
	_focus = want if _snap else _focus.lerp(want, 1.0 - exp(-follow_rate * delta))
	_snap = false
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	global_position = _focus + dir * distance
	look_at(_focus)
