class_name CameraRig
extends Camera3D

## Fighter camera (third person by default). First person: sits just in front of the head, looking where
## the chest faces and a little down so you see your hands; smoothed so the
## ragdoll's wobble doesn't shake it. Third person: eases along behind the
## fighter, turning with them; yaw_offset swings it around (D-pad, mouse with
## no button held, J / L), zoom() moves it in and out. V or Start switches.

@export var target: Fighter
@export var sensitivity := 0.005
@export var distance := 2.4
@export var min_distance := 1.4
@export var max_distance := 7.0
@export var min_pitch := -0.2
@export var max_pitch := 1.2
## How fast (1/s) the camera catches up with the fighter. Lower is floatier.
@export var follow_rate := 6.0
## Height of the point the camera looks at, blended with the pelvis height.
@export var focus_height := 0.9

## Where the camera sits around the fighter, radians: 0 = behind, PI = in front.
@export var yaw_offset := 0.5
## How fast (1/s) the camera swings round when the fighter turns. Slow, so body
## wobble doesn't shake it.
@export var turn_rate := 1.5
@export var first_person := false
## First person: how far down (radians) the view tips from where the chest faces.
@export var fp_look_down := 0.35
## First person: how fast (1/s) the view follows the head.
@export var fp_follow_rate := 10.0

var yaw := 0.0
var pitch := 0.3
var _focus := Vector3(0, 0.9, 0)
var _snap := true
var _focus_lag := Vector3(0, 0.9, 0)
var _yaw_lag := 0.0
var _last_offset := 0.0


func _ready() -> void:
	# Moved every rendered frame from interpolated positions, so it must not be
	# interpolated again.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.04


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		first_person = not first_person


func orbit(pixels: Vector2) -> void:
	yaw_offset -= pixels.x * sensitivity
	pitch = clampf(pitch + pixels.y * sensitivity, min_pitch, max_pitch)


func zoom(steps: float) -> void:
	distance = clampf(distance * pow(0.9, steps), min_distance, max_distance)


## Jump straight to the fighter on the next frame (after a reset).
func snap() -> void:
	_snap = true


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_J):
		yaw_offset -= delta * 1.5
	if Input.is_key_pressed(KEY_L):
		yaw_offset += delta * 1.5
	if not is_instance_valid(target) or not target.parts.has("pelvis"):
		return
	if first_person:
		_first_person(delta)
		return
	var pelvis: Vector3 = target.parts.pelvis.get_global_transform_interpolated().origin
	var want := Vector3(pelvis.x, lerpf(focus_height, pelvis.y, 0.5), pelvis.z)
	var body_yaw := _body_yaw(pelvis)
	if _snap:
		_focus = want
		_focus_lag = want
		yaw = (body_yaw if not is_nan(body_yaw) else 0.0) + yaw_offset
		_yaw_lag = yaw
	else:
		# Two smoothing stages in a row, so a body bump turns into a gentle
		# drift instead of a jolt.
		var k := 1.0 - exp(-follow_rate * delta)
		_focus_lag = _focus_lag.lerp(want, k)
		_focus = _focus.lerp(_focus_lag, k)
		if not is_nan(body_yaw):
			var kt := 1.0 - exp(-turn_rate * delta)
			_yaw_lag = lerp_angle(_yaw_lag, body_yaw + yaw_offset, kt)
		# The D-pad / mouse yaw_offset still answers quickly.
		_yaw_lag += yaw_offset - _last_offset
		_last_offset = yaw_offset
		yaw = lerp_angle(yaw, _yaw_lag, 1.0 - exp(-turn_rate * 2.0 * delta))
	_last_offset = yaw_offset
	_snap = false
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	global_position = _focus + dir * distance
	look_at(_focus)


## Which way the camera should sit behind, from the fighter's body: the hips'
## facing when upright; lying down (when that points at the sky or floor), the
## line from the head down to the hips, so the camera sits behind the head
## looking down the body. NAN when neither is clear (no change).
func _body_yaw(pelvis: Vector3) -> float:
	var fwd: Vector3 = -target.parts.pelvis.get_global_transform_interpolated().basis.z
	var head: Vector3 = target.parts.head.get_global_transform_interpolated().origin
	var along := pelvis - head
	var upright := clampf(fwd.y * fwd.y * 4.0, 0.0, 1.0)  # 0 standing, 1 when facing up or down
	var d := Vector3(fwd.x, 0, fwd.z).normalized() * (1.0 - upright) + Vector3(along.x, 0, along.z).normalized() * upright
	if d.length() < 0.3:
		return NAN
	return atan2(-d.x, -d.z)


func _first_person(delta: float) -> void:
	var head: Vector3 = target.parts.head.get_global_transform_interpolated().origin
	var cb: Basis = target.parts.chest.get_global_transform_interpolated().basis.orthonormalized()
	var look := (-cb.z).rotated(cb.x, -fp_look_down)
	var want := Transform3D(Basis.looking_at(look, cb.y), head - cb.z * 0.13 + cb.y * 0.03)
	if _snap:
		global_transform = want
	else:
		var k := 1.0 - exp(-fp_follow_rate * delta)
		var q := global_basis.get_rotation_quaternion().slerp(want.basis.get_rotation_quaternion(), k)
		global_transform = Transform3D(Basis(q), global_position.lerp(want.origin, k))
	_snap = false
