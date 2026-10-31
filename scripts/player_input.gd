class_name PlayerInput
extends Node

## Fills a Fighter's intent from mouse and keyboard. Click the game window to
## capture the mouse, Esc to release it.
##   Hold left / right button + mouse: move the left / right arm (both buttons: both arms).
##     The hand moves the way the mouse moves on screen. A held button also closes that hand.
##   Hold a button + wheel: reach out / pull in that arm.
##   No button: mouse orbits the camera, wheel zooms.
##   WASD: walk (camera relative); on the mat the hips and legs, like the
##     controller's left stick (S = bridge, W = legs up, A / D = hip swing)
##   Arrow keys: on the mat the chest, like the right stick (up = sit up /
##     scoot, down = lie back, left / right = shrimp)
##   C (hold): lower your stance, all the way to sit down
##   Q / E: turn shoulders    Ctrl: tense    Tab: swap lead side

## Actions this script registers if project.godot doesn't define them already.
const BINDINGS := {
	"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W, "move_back": KEY_S,
	"turn_left": KEY_Q, "turn_right": KEY_E, "tense": KEY_CTRL, "swap_lead": KEY_TAB,
	"focus_hips": KEY_SHIFT, "focus_legs": KEY_SPACE,
	"upper_left": KEY_LEFT, "upper_right": KEY_RIGHT, "upper_up": KEY_UP, "upper_down": KEY_DOWN,
	"crouch": KEY_C,
}
## Starting hand offsets from the chest, in the heading frame (x right, y up, -z forward).
const GUARD: Array[Vector3] = [Vector3(-0.18, -0.15, -0.3), Vector3(0.18, -0.15, -0.3)]

@export var fighter: Fighter
@export var camera: CameraRig
## Who to face (main sets it to the training partner).
@export var opponent: Fighter
## Face the opponent when closer than this (m).
@export var face_range := 3.0
## Metres a hand moves per pixel of mouse motion.
@export var mouse_sensitivity := 0.002
## Box the hand offsets stay in, metres from the chest: x sideways, y up/down, z forward.
@export var offset_min := Vector3(-0.6, -0.6, -0.65)
@export var offset_max := Vector3(0.6, 0.4, -0.08)
@export var reach_step := 0.04
## How fast (1/s) the hand frame follows the chest. Lower keeps hands steadier
## while the body sways.
@export var anchor_rate := 8.0

## Per-hand offset from the chest in the heading frame.
var hand_offset: Array[Vector3] = GUARD.duplicate()
var _anchor := Vector3.ZERO
var _anchor_fighter: Fighter
var _face := Vector2(0, -1)
var _crouch := 0.0


func _ready() -> void:
	# Run before the fighters so they read this tick's intent.
	process_physics_priority = -10
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = BINDINGS[action]
			InputMap.action_add_event(action, ev)


## Arms under mouse control right now: [left, right].
func controlled() -> Array[bool]:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	return [captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)]


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if not captured:
		return
	var arms := controlled()
	var any_arm: bool = arms[0] or arms[1]
	if event is InputEventMouseMotion:
		if any_arm:
			move_hands(arms, event.relative)
		elif camera:
			camera.orbit(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		var step := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = 1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = -1.0
		if step != 0.0:
			if any_arm:
				for i in 2:
					if arms[i]:
						_set_offset(i, hand_offset[i] + Vector3(0, 0, -step * reach_step))
			elif camera:
				camera.zoom(step)


## Moves the chosen hands the way the mouse moved on screen: right on screen is
## the camera's right, up is up.
func move_hands(arms: Array[bool], pixels: Vector2) -> void:
	if not is_instance_valid(fighter) or not fighter.parts.has("chest"):
		return
	var right := Vector3.RIGHT
	if camera:
		right = camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
	var world := (right * pixels.x - Vector3.UP * pixels.y) * mouse_sensitivity
	var local := fighter.heading_basis().inverse() * world
	for i in 2:
		if arms[i]:
			_set_offset(i, hand_offset[i] + local)


func _set_offset(i: int, v: Vector3) -> void:
	hand_offset[i] = v.clamp(offset_min, offset_max)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(fighter) or not fighter.parts.has("chest"):
		return
	var it := fighter.intent
	if Input.is_action_pressed("focus_hips"):
		it.focus = FighterIntent.Focus.HIPS
	elif Input.is_action_pressed("focus_legs"):
		it.focus = FighterIntent.Focus.LEGS
	else:
		it.focus = FighterIntent.Focus.HANDS
	if Input.is_action_just_pressed("swap_lead"):
		it.lead = 1 - it.lead
	it.tension = 1.0 if Input.is_action_pressed("tense") else 0.0
	it.turn = Input.get_axis("turn_left", "turn_right")
	it.weight_shift = Vector2.ZERO
	it.grip = controlled()
	var base := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var ground := fighter.on_ground()
	if ground:
		it.move = Vector2.ZERO
		it.hips = base
		it.upper = Input.get_vector("upper_left", "upper_right", "upper_down", "upper_up")
		_crouch = 0.0
	else:
		it.hips = Vector2.ZERO
		it.upper = Vector2.ZERO
		it.move = _camera_relative(base)
		var c := Input.is_action_pressed("crouch")
		_crouch = move_toward(_crouch, 1.0 if c else 0.0, (1.4 if c else 2.5) * delta)
	it.crouch = _crouch
	it.face_dir = _face_dir(it.move)

	# Smooth the chest position the hands hang off, so body sway doesn't feed
	# straight back into the arms.
	var chest: Vector3 = fighter.parts.chest.global_position
	if _anchor_fighter != fighter:
		_anchor_fighter = fighter
		_anchor = chest
		hand_offset = GUARD.duplicate()
		_crouch = 0.0
		var hf := -fighter.heading_basis().z
		_face = Vector2(hf.x, hf.z).normalized()
	_anchor = _anchor.lerp(chest, 1.0 - exp(-anchor_rate * delta))

	# Arms hang until you take the mouse, then each hand holds where you left it.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var targets := hand_targets(fighter, _anchor, hand_offset)
	var held := controlled()
	for i in 2:
		it.hand_target[i] = targets[i]
		# On the mat a hand you aren't moving posts and frames by itself.
		it.hand_active[i] = captured and (not ground or held[i])
		it.hand_effort[i] = Vector3.ZERO
		it.arm_tone[i] = 1.0


func _camera_relative(s: Vector2) -> Vector2:
	if s == Vector2.ZERO:
		return Vector2.ZERO
	var fwd := Vector3(0, 0, -1)
	if camera:
		fwd = -camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3(0, 0, -1)
	var w := fwd.cross(Vector3.UP) * s.x + fwd * s.y
	return Vector2(w.x, w.z).limit_length(1.0)


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


## World hand targets from per-hand offsets in the fighter's heading frame.
static func hand_targets(f: Fighter, origin: Vector3, offsets: Array[Vector3]) -> Array[Vector3]:
	var hb := f.heading_basis()
	var out: Array[Vector3] = [origin + hb * offsets[0], origin + hb * offsets[1]]
	return out
