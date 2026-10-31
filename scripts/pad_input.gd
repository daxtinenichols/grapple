class_name PadInput
extends Node

## Fills a Fighter's intent from a game controller (Xbox 360 layout). The arms
## are muscle-driven: a stick pushes its hand with a force, and the arm is
## otherwise loose, so it sags and swings and stays roughly where you leave it.
##   Left / right stick: push the left / right hand (sideways and up / down)
##   Hold LB / RB: that stick pushes forward / pulls back instead of up / down
##   LT / RT: close the left / right hand    A (hold): tense
##   Hold X (body): left stick shifts weight over the feet, right stick leans
##     (up / down) and turns (left / right) the torso
##   Hold Y (legs): sticks push the left / right foot, LB / RB clamp (bend) that leg
## The triggers grip in every mode, so a grip holds through a throw.
##   D-pad left / right: swing the camera round, up / down: zoom
##   Back: reset    (WASD and the other keyboard keys still work)
## Arms hold where they are (loosely) while X or Y is held.

const DEADZONE := 0.18
const JOY_BINDINGS := {"tense": JOY_BUTTON_A, "reset": JOY_BUTTON_BACK}

@export var fighter: Fighter
@export var camera: CameraRig
@export var device := 0
## Arm firmness while driven by the sticks (see FighterIntent.arm_tone).
@export var arm_tone := 0.3
## How fast (1/s) a loose arm's resting spot catches up with where the hand
## actually is while you push it. 0 = always springs back to the guard.
@export var settle_rate := 6.0
@export var camera_step := PI / 4.0
## Leg firmness while its stick pushes it (1 when the stick is centred).
@export var leg_tone := 0.5
## How much moving a leg shifts your weight onto the other leg (0..1).
@export var stance_shift := 1.0
## How much a leg push also lifts the foot, so it comes off the mat.
@export var foot_lift := 0.35

## Per-hand resting spot, offset from the chest in the heading frame.
var hand_offset: Array[Vector3] = PlayerInput.GUARD.duplicate()
var _fighter_seen: Fighter


func _ready() -> void:
	process_physics_priority = -10
	for action in JOY_BINDINGS:
		if InputMap.has_action(action):
			var ev := InputEventJoypadButton.new()
			ev.button_index = JOY_BINDINGS[action]
			ev.device = -1
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed and camera:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT:
				camera.yaw_offset -= camera_step
			JOY_BUTTON_DPAD_RIGHT:
				camera.yaw_offset += camera_step
			JOY_BUTTON_DPAD_UP:
				camera.zoom(1.0)
			JOY_BUTTON_DPAD_DOWN:
				camera.zoom(-1.0)


func _stick(x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(device, x_axis), -Input.get_joy_axis(device, y_axis))
	var l := v.length()
	if l < DEADZONE:
		return Vector2.ZERO
	return v / l * minf((l - DEADZONE) / (1.0 - DEADZONE), 1.0)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(fighter) or not fighter.parts.has("chest"):
		return
	var sticks: Array[Vector2] = [_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y), _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)]
	var push_pull: Array[bool] = [Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER),
		Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)]
	var triggers: Array[float] = [Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT),
		Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)]

	var it := fighter.intent
	it.tension = 1.0 if Input.is_action_pressed("tense") else 0.0
	var keys_turn := Input.get_axis("turn_left", "turn_right")
	var keys_shift := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var body := Input.is_joy_button_pressed(device, JOY_BUTTON_X)
	var legs := Input.is_joy_button_pressed(device, JOY_BUTTON_Y) and not body
	var none: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var no: Array[bool] = [false, false]

	if body:
		it.focus = FighterIntent.Focus.HIPS
		var hb := fighter.heading_basis()
		var w := _camera_flat(sticks[0])
		var local := hb.inverse() * w
		it.weight_shift = (Vector2(local.x, -local.z) + keys_shift).limit_length(1.0)
		it.turn = clampf(sticks[1].x + keys_turn, -1.0, 1.0)
		it.torso_lean = sticks[1].y
	else:
		it.weight_shift = keys_shift
		it.turn = keys_turn
		it.torso_lean = 0.0

	for i in 2:
		it.grip[i] = triggers[i] > 0.5
	if legs:
		it.focus = FighterIntent.Focus.LEGS
		apply_leg_sticks(sticks, push_pull)
		# Moving a leg leans you onto the other one, so the foot can come up.
		it.weight_shift.x = clampf(it.weight_shift.x + (sticks[0].length() - sticks[1].length()) * stance_shift, -1.0, 1.0)
	else:
		apply_leg_sticks(none, no)

	if body or legs:
		apply_sticks(none, no, delta)
	else:
		it.focus = FighterIntent.Focus.HANDS
		apply_sticks(sticks, push_pull, delta)


## World direction for a stick: x along the camera's sideways, y along the
## camera's forward, both flat on the mat.
func _camera_flat(s: Vector2) -> Vector3:
	var right := Vector3.RIGHT
	var fwd := Vector3.FORWARD
	if camera:
		right = camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		fwd = Vector3.UP.cross(right)
	return right * s.x + fwd * s.y


## Leg sticks push the feet (flat, relative to the camera, plus a little lift);
## a pushed leg goes loose so the push can move it. clamp bends the knee.
func apply_leg_sticks(sticks: Array[Vector2], clamp: Array[bool]) -> void:
	var it := fighter.intent
	for i in 2:
		var s := sticks[i]
		it.foot_effort[i] = _camera_flat(s) + Vector3.UP * foot_lift * s.length()
		it.leg_tone[i] = leg_tone if s != Vector2.ZERO else 1.0
		it.leg_clamp[i] = clamp[i]


## Turns stick values into the arm part of the intent. Sideways is the camera's
## sideways; up / down is world up, or forward / back along the fighter's facing
## while push_pull is held.
func apply_sticks(sticks: Array[Vector2], push_pull: Array[bool], delta: float) -> void:
	var f := fighter
	var it := f.intent
	if _fighter_seen != f:
		_fighter_seen = f
		hand_offset = PlayerInput.GUARD.duplicate()
	var hb := f.heading_basis()
	var right := hb.x
	if camera:
		right = camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
	var chest: Vector3 = f.parts.chest.global_position
	for i in 2:
		var s := sticks[i]
		var second := -hb.z if push_pull[i] else Vector3.UP
		it.hand_effort[i] = right * s.x + second * s.y
		it.arm_tone[i] = arm_tone
		it.hand_active[i] = true
		# While pushing, the arm's resting spot drifts to where the hand is, so
		# letting go leaves it there (sagging) instead of snapping back.
		if s != Vector2.ZERO:
			var hand: Vector3 = f.parts[("l_" if i == 0 else "r_") + "hand"].global_position
			var here := hb.inverse() * (hand - chest)
			hand_offset[i] = hand_offset[i].lerp(here, 1.0 - exp(-settle_rate * delta))
		it.hand_target[i] = chest + hb * hand_offset[i]
