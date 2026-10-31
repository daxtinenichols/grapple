class_name PadInput
extends Node

## Fills a Fighter's intent from a game controller (Xbox 360 layout). Both
## thumbs stay on the sticks; the bumpers (index fingers) pick what they move.
##   Sticks: move the left / right hand, sideways and push forward / pull back,
##     relative to your chest (hands sit at chest height; lean to go lower)
##   Hold RB (body): left stick shifts weight over the feet, right stick leans
##     (up / down) and turns (left / right) the torso
##   Hold LB (legs): sticks move the left / right foot relative to your hips:
##     up pushes it out, down pulls the heel in (a clamp), sideways is sideways
##   LT / RT: close the left / right hand, in every mode    A (hold): tense
##   D-pad left / right: swing the camera round, up / down: zoom
##   Start: first person / third person    Back: reset
## Arms hold where they are while a bumper is held.

const DEADZONE := 0.18
const JOY_BINDINGS := {"tense": JOY_BUTTON_A, "reset": JOY_BUTTON_BACK}
## Hand reach box in the chest frame (x right, y up, -z forward), metres.
const HAND_MIN := Vector3(-0.55, -0.6, -0.65)
const HAND_MAX := Vector3(0.55, 0.35, -0.08)

enum Mode { ARMS, BODY, LEGS }

@export var fighter: Fighter
@export var camera: CameraRig
@export var device := 0
## How fast (m/s) a full stick moves a hand's target.
@export var hand_speed := 0.9
## How far (m) a hand's target may run ahead of the real hand. Small keeps the
## arm feeling like it's yours; large makes it springy.
@export var hand_lead := 0.2
## Arm firmness (see FighterIntent.arm_tone).
@export var arm_tone := 0.7
## Extra muscle push in the stick direction, 0..1, for a bit of throw and flop.
@export var arm_push := 0.3
## Leg firmness while its stick pushes it (1 when the stick is centred).
@export var leg_tone := 0.15
## How much moving a leg shifts your weight onto the other leg (0..1).
@export var stance_shift := 1.0
## Stick pulled down this far (0..1) in legs mode clamps that knee.
@export var clamp_at := 0.6
@export var camera_step := PI / 4.0

var mode := Mode.ARMS
## Per-hand target, offset from the chest in the chest frame.
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
			JOY_BUTTON_START:
				camera.first_person = not camera.first_person


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
	if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER):
		mode = Mode.BODY
	elif Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER):
		mode = Mode.LEGS
	else:
		mode = Mode.ARMS
	var it := fighter.intent
	it.tension = 1.0 if Input.is_action_pressed("tense") else 0.0
	for i in 2:
		it.grip[i] = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT if i == 0 else JOY_AXIS_TRIGGER_RIGHT) > 0.5
	drive(sticks, delta)


## Turns the sticks into the intent for the current mode. Split out so tests
## can drive it without a controller.
func drive(sticks: Array[Vector2], delta: float) -> void:
	var it := fighter.intent
	var none: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var keys_turn := Input.get_axis("turn_left", "turn_right")
	var keys_shift := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	it.weight_shift = keys_shift
	it.turn = keys_turn
	it.torso_lean = 0.0
	match mode:
		Mode.BODY:
			it.focus = FighterIntent.Focus.HIPS
			it.weight_shift = (sticks[0] + keys_shift).limit_length(1.0)
			it.turn = clampf(sticks[1].x + keys_turn, -1.0, 1.0)
			it.torso_lean = sticks[1].y
		Mode.LEGS:
			it.focus = FighterIntent.Focus.LEGS
			# Moving a leg leans you onto the other one, so the foot can come up.
			it.weight_shift.x = clampf(it.weight_shift.x + (sticks[0].length() - sticks[1].length()) * stance_shift, -1.0, 1.0)
		Mode.ARMS:
			it.focus = FighterIntent.Focus.HANDS
	apply_leg_sticks(sticks if mode == Mode.LEGS else none)
	apply_sticks(sticks if mode == Mode.ARMS else none, delta)


## Arm sticks move each hand's target at hand_speed in the chest frame
## (x sideways, y push / pull), never more than hand_lead ahead of the real
## hand, plus a light muscle push the same way.
func apply_sticks(sticks: Array[Vector2], delta: float) -> void:
	var f := fighter
	var it := f.intent
	if _fighter_seen != f:
		_fighter_seen = f
		hand_offset = PlayerInput.GUARD.duplicate()
	var cf := f.chest_frame()
	var chest: Vector3 = f.parts.chest.global_position
	for i in 2:
		var s := sticks[i]
		var hand: Vector3 = f.parts[("l_" if i == 0 else "r_") + "hand"].global_position
		var here := cf.inverse() * (hand - chest)
		var o := hand_offset[i] + Vector3(s.x, 0, -s.y) * hand_speed * delta
		o = here + (o - here).limit_length(hand_lead)
		hand_offset[i] = o.clamp(HAND_MIN, HAND_MAX)
		it.hand_target[i] = chest + cf * hand_offset[i]
		it.hand_active[i] = true
		it.arm_tone[i] = arm_tone
		it.hand_effort[i] = cf * Vector3(s.x, 0, -s.y) * arm_push


## Leg sticks push each foot in the hip frame: up pushes it out the way the
## knee points, down pulls the heel in and past clamp_at clamps the knee,
## sideways is sideways. The same stick means the same thing standing or lying.
func apply_leg_sticks(sticks: Array[Vector2]) -> void:
	var it := fighter.intent
	var pb: Basis = fighter.parts.pelvis.global_basis.orthonormalized()
	for i in 2:
		var s := sticks[i]
		it.foot_effort[i] = pb * Vector3(s.x, 0, -maxf(s.y, 0.0))
		it.leg_tone[i] = leg_tone if s != Vector2.ZERO else 1.0
		it.leg_clamp[i] = s.y < -clamp_at
