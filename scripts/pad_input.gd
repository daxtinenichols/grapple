class_name PadInput
extends Node

## Fills a Fighter's intent from a game controller (Xbox 360 layout). The arms
## are muscle-driven: a stick pushes its hand with a force, and the arm is
## otherwise loose, so it sags and swings and stays roughly where you leave it.
##   Left / right stick: push the left / right hand (sideways and up / down)
##   Hold LB / RB: that stick pushes forward / pulls back instead of up / down
##   LT / RT: close the left / right hand    A (hold): tense
##   X / B: turn the shoulders left / right
##   D-pad left / right: swing the camera round, up / down: zoom
##   Back: reset    (WASD and the other keyboard keys still work)

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
	it.focus = FighterIntent.Focus.HANDS
	it.tension = 1.0 if Input.is_action_pressed("tense") else 0.0
	var turn := Input.get_axis("turn_left", "turn_right")
	turn += float(Input.is_joy_button_pressed(device, JOY_BUTTON_B)) - float(Input.is_joy_button_pressed(device, JOY_BUTTON_X))
	it.turn = clampf(turn, -1.0, 1.0)
	it.weight_shift = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	for i in 2:
		it.grip[i] = triggers[i] > 0.5
	apply_sticks(sticks, push_pull, delta)


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
