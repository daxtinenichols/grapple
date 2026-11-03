class_name PadInput
extends Node

## Fills a Fighter's intent from a game controller (Xbox 360 layout). Both
## thumbs stay on the sticks; the bumpers (index fingers) pick what they move.
##   Sticks: move the left / right hand, sideways and push forward / pull back,
##     relative to your chest (hands sit at chest height; lean to go lower)
##   Hold RB (body): left stick moves your weight over the feet, right stick
##     leans (up / down) and turns (left / right) the torso. They stay where you
##     leave them; click a stick to recentre.
##   Hold LB (legs): sticks move the left / right foot relative to your hips:
##     up pushes it out, down pulls the heel in (a clamp), sideways is sideways.
##     A leg stays where you leave it; click its stick to stand it back up.
##   Hold RB + LB (body and legs): left stick moves your weight / hips as in
##     body mode, right stick moves both legs together the way it moves one leg
##     in legs mode (pull it down past clamp_at to clamp both knees).
##   LT / RT: close the left / right hand, in every mode    A (hold): tense
##   D-pad left / right: swing the camera round, up / down: zoom
##   Start: first person / third person    Back: reset
## Arms, hips and legs all hold where you left them when you switch mode.

const DEADZONE := 0.18
const JOY_BINDINGS := {"tense": JOY_BUTTON_A, "reset": JOY_BUTTON_BACK}
## Hand reach box in the chest frame (x right, y up, -z forward), metres.
const HAND_MIN := Vector3(-0.55, -0.6, -0.65)
const HAND_MAX := Vector3(0.55, 0.35, -0.08)

enum Mode { ARMS, BODY, LEGS, BOTH }

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
## How fast (per second) a full stick moves weight, lean and turn in body mode.
@export var body_speed := 1.2

var mode := Mode.ARMS
## Where the body mode left the hips and torso; they hold in every mode.
var body_shift := Vector2.ZERO
var body_lean := 0.0
var body_turn := 0.0
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
	var rb := Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
	var lb := Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER)
	if rb and lb:
		mode = Mode.BOTH
	elif rb:
		mode = Mode.BODY
	elif lb:
		mode = Mode.LEGS
	else:
		mode = Mode.ARMS
	var it := fighter.intent
	it.tension = 1.0 if Input.is_action_pressed("tense") else 0.0
	for i in 2:
		it.grip[i] = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT if i == 0 else JOY_AXIS_TRIGGER_RIGHT) > 0.5
	var clicks: Array[bool] = [_clicked(JOY_BUTTON_LEFT_STICK, 0), _clicked(JOY_BUTTON_RIGHT_STICK, 1)]
	drive(sticks, delta, clicks)


var _click_was: Array[bool] = [false, false]


func _clicked(b: JoyButton, i: int) -> bool:
	var down := Input.is_joy_button_pressed(device, b)
	var hit := down and not _click_was[i]
	_click_was[i] = down
	return hit


## Turns the sticks into the intent for the current mode. Split out so tests
## can drive it without a controller. clicks = stick buttons (L3, R3) pressed
## this tick.
func drive(sticks: Array[Vector2], delta: float, clicks: Array[bool] = [false, false]) -> void:
	var it := fighter.intent
	var none: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	if _fighter_seen != fighter:
		body_shift = Vector2.ZERO
		body_lean = 0.0
		body_turn = 0.0
	match mode:
		Mode.BODY:
			it.focus = FighterIntent.Focus.HIPS
			# The sticks move the hips and torso; they stay put when let go.
			body_shift = (body_shift + sticks[0] * body_speed * delta).limit_length(1.0)
			body_turn = clampf(body_turn + sticks[1].x * body_speed * delta, -1.0, 1.0)
			body_lean = clampf(body_lean + sticks[1].y * body_speed * delta, -1.0, 1.0)
			if clicks[0] or clicks[1]:
				body_shift = Vector2.ZERO
				body_lean = 0.0
				body_turn = 0.0
		Mode.LEGS:
			it.focus = FighterIntent.Focus.LEGS
		Mode.BOTH:
			it.focus = FighterIntent.Focus.HIPS
			body_shift = (body_shift + sticks[0] * body_speed * delta).limit_length(1.0)
			if clicks[0]:
				body_shift = Vector2.ZERO
		Mode.ARMS:
			it.focus = FighterIntent.Focus.HANDS
	var keys_shift := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	it.weight_shift = (body_shift + keys_shift).limit_length(1.0)
	it.turn = clampf(body_turn + Input.get_axis("turn_left", "turn_right"), -1.0, 1.0)
	it.torso_lean = body_lean
	if mode == Mode.LEGS:
		# Moving a leg leans you onto the other one, so the foot can come up.
		it.weight_shift.x = clampf(it.weight_shift.x + (sticks[0].length() - sticks[1].length()) * stance_shift, -1.0, 1.0)
	var leg_sticks := none
	if mode == Mode.LEGS:
		leg_sticks = sticks
	elif mode == Mode.BOTH:
		leg_sticks = [sticks[1], sticks[1]]
	for i in 2:
		it.leg_stand[i] = (mode == Mode.LEGS and clicks[i]) or (mode == Mode.BOTH and clicks[1])
	apply_leg_sticks(leg_sticks)
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
