class_name PadInput
extends Node

## Fills a Fighter's intent from a game controller (Xbox 360 layout). One stick
## is your base, the other your upper body; the fighter balances, steps and
## blends the moves itself (FighterMoves).
##
## Standing:
##   Left stick: walk (camera relative). You face your partner when they're
##     within face_range, otherwise the way you walk.
##   Right stick: both hands, sideways and push forward / pull back. Your
##     hips and legs follow (reach leans in, pulling sinks, a sideways swing
##     turns the hips like a throw while the feet brace).
##   Hold LB / RB: the right stick moves only the left / right hand.
##   Hold B: lower your stance; hold it all the way to sit down.
## On the mat:
##   Left stick (hips and legs): up = knees / legs up, down = bridge (down-left
##     / down-right over that shoulder), sideways = swing the hips that way.
##   Right stick (chest): up = sit up (held while sitting: butt scoot), down =
##     lie back, sideways = shrimp. Face down: up pushes up, sideways rolls.
##   Sit up (or get on hands and knees) and push the left stick down to stand.
##   Hold LB / RB: the right stick moves that hand instead (the hands post and
##     frame by themselves otherwise).
## Always: LT / RT close the left / right hand. A (hold): tense. Right stick
##   click: hands back to guard. D-pad: camera. Start: first / third person.
##   Back: reset.

const DEADZONE := 0.18
const JOY_BINDINGS := {"tense": JOY_BUTTON_A, "reset": JOY_BUTTON_BACK}
## Hand reach box in the chest frame (x right, y up, -z forward), metres.
const HAND_MIN := Vector3(-0.55, -0.6, -0.65)
const HAND_MAX := Vector3(0.55, 0.35, -0.08)

@export var fighter: Fighter
@export var camera: CameraRig
## Who to face (main sets it to the training partner).
@export var opponent: Fighter
@export var device := 0
## Face the opponent when closer than this (m).
@export var face_range := 3.0
## How fast (m/s) a full stick moves a hand's target.
@export var hand_speed := 0.9
## How far (m) a hand's target may run ahead of the real hand. Small keeps the
## arm feeling like it's yours; large makes it springy.
@export var hand_lead := 0.2
## Arm firmness (see FighterIntent.arm_tone).
@export var arm_tone := 0.7
## Extra muscle push in the stick direction, 0..1, for a bit of throw and flop.
@export var arm_push := 0.3
## How fast (per second) holding B lowers you, and letting go raises you.
@export var crouch_down_speed := 1.4
@export var crouch_up_speed := 2.5
@export var camera_step := PI / 4.0

## Per-hand target, offset from the chest in the chest frame.
var hand_offset: Array[Vector3] = PlayerInput.GUARD.duplicate()
## What the sticks are doing right now, for the HUD.
var mode_text := ""
var _fighter_seen: Fighter
var _face := Vector2(0, -1)
var _crouch := 0.0
## Seconds left of a hands-to-guard reset (the hands travel there).
var _guard_t := 0.0


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
	var it := fighter.intent
	it.tension = 1.0 if Input.is_action_pressed("tense") else 0.0
	for i in 2:
		it.grip[i] = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT if i == 0 else JOY_AXIS_TRIGGER_RIGHT) > 0.5
	var hands: Array[bool] = [Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER),
		Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)]
	drive(_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y), _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y), hands,
		Input.is_joy_button_pressed(device, JOY_BUTTON_B), _clicked(JOY_BUTTON_RIGHT_STICK), delta)


var _click_was := false


func _clicked(b: JoyButton) -> bool:
	var down := Input.is_joy_button_pressed(device, b)
	var hit := down and not _click_was
	_click_was = down
	return hit


## Turns the sticks and buttons into the intent. Split out so tests (and the
## keyboard fallback) can drive it without a controller.
##   base: left stick, upper: right stick, hands: [LB, RB] held,
##   crouch: B held, guard: right stick clicked this tick.
func drive(base: Vector2, upper: Vector2, hands: Array[bool], crouch: bool, guard: bool, delta: float) -> void:
	var f := fighter
	var it := f.intent
	if _fighter_seen != f:
		_fighter_seen = f
		hand_offset = PlayerInput.GUARD.duplicate()
		_crouch = 0.0
		_face = Vector2(-f.heading_basis().z.x, -f.heading_basis().z.z)
	if guard:
		_guard_t = 0.8
	var one_hand: bool = hands[0] != hands[1]
	var ground := f.on_ground()

	# --- Base stick ---
	if ground:
		it.move = Vector2.ZERO
		it.hips = base
		_crouch = 0.0
	else:
		it.hips = Vector2.ZERO
		var m := camera_relative(base)
		it.move = m
		_crouch = move_toward(_crouch, 1.0 if crouch else 0.0, (crouch_down_speed if crouch else crouch_up_speed) * delta)
	it.crouch = _crouch
	it.face_dir = _face_dir(it.move)

	# --- Upper stick ---
	var hand_sticks: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var active: Array[bool] = [true, true]
	if ground:
		# The hands post and frame by themselves unless a bumper takes one.
		active = [hands[0], hands[1]]
		it.upper = Vector2.ZERO if (hands[0] or hands[1]) else upper
		for i in 2:
			if hands[i]:
				hand_sticks[i] = upper
	else:
		it.upper = Vector2.ZERO
		for i in 2:
			if not one_hand or hands[i]:
				hand_sticks[i] = upper
	apply_hands(hand_sticks, active, delta)

	if ground:
		mode_text = "on the mat (%s)%s" % [FighterMoves.Ground.keys()[f.moves.ground].to_lower().replace("_", " "),
			(": " + f.moves.move_name) if f.moves.move_name != "" else ""]
		if one_hand:
			mode_text += ", right stick moves the " + ("left" if hands[0] else "right") + " hand"
	else:
		mode_text = "standing" + ("" if not one_hand else ", right stick moves the " + ("left" if hands[0] else "right") + " hand")
		if _crouch > 0.01:
			mode_text += ", low stance %d%%" % int(_crouch * 100.0)


## A stick direction turned into a world (x, z) direction relative to the camera.
func camera_relative(s: Vector2) -> Vector2:
	if s == Vector2.ZERO:
		return Vector2.ZERO
	var fwd := Vector3(0, 0, -1)
	if camera:
		fwd = -camera.global_basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.0001:
			fwd = Vector3(0, 0, -1)
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var w := right * s.x + fwd * s.y
	return Vector2(w.x, w.z).limit_length(1.0)


## Face the opponent when one is near, otherwise the way you walk.
func _face_dir(move: Vector2) -> Vector2:
	if is_instance_valid(opponent) and opponent.parts.has("chest"):
		var d: Vector3 = opponent.parts.chest.global_position - fighter.parts.chest.global_position
		d.y = 0.0
		if d.length() < face_range and d.length() > 0.05:
			_face = Vector2(d.x, d.z).normalized()
			return _face
	if move.length() > 0.2:
		_face = move.normalized()
	return _face


## Sticks move each hand's target at hand_speed in the chest frame
## (x sideways, y push / pull), never more than hand_lead ahead of the real
## hand, plus a light muscle push the same way. Inactive hands are left to
## the fighter (they post and frame by themselves on the mat).
func apply_hands(sticks: Array[Vector2], active: Array[bool], delta: float) -> void:
	var f := fighter
	var it := f.intent
	var cf := f.chest_frame()
	var chest: Vector3 = f.parts.chest.global_position
	for i in 2:
		it.hand_active[i] = active[i]
		if not active[i]:
			it.hand_effort[i] = Vector3.ZERO
			continue
		var s := sticks[i]
		var hand: Vector3 = f.parts[("l_" if i == 0 else "r_") + "hand"].global_position
		var here := cf.inverse() * (hand - chest)
		var o := hand_offset[i] + Vector3(s.x, 0, -s.y) * hand_speed * delta
		if _guard_t > 0.0 and s == Vector2.ZERO:
			o = hand_offset[i].move_toward(PlayerInput.GUARD[i], 1.5 * delta)
		else:
			o = here + (o - here).limit_length(hand_lead)
		hand_offset[i] = o.clamp(HAND_MIN, HAND_MAX)
		it.hand_target[i] = chest + cf * hand_offset[i]
		it.arm_tone[i] = arm_tone
		it.hand_effort[i] = cf * Vector3(s.x, 0, -s.y) * arm_push
	_guard_t -= delta
	for i in 2:
		it.foot_effort[i] = Vector3.ZERO
		it.leg_tone[i] = 1.0
		it.leg_clamp[i] = false
		it.leg_stand[i] = false
