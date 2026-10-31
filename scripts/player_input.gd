class_name PlayerInput
extends Node

## Fills a Fighter's intent from mouse and keyboard. Click the game window to
## capture the mouse, Esc to release it.
##   Mouse: move the hand targets in a plane in front of the chest (lead hand follows closely)
##   Wheel: reach (pull in / extend)    Left / right button: close left / right hand
##   WASD: weight shift    Q / E: turn shoulders    Ctrl: tense    Tab: swap lead hand
##   Shift: hips focus    Space: legs focus

## Actions this script registers if project.godot doesn't define them already.
const BINDINGS := {
	"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W, "move_back": KEY_S,
	"turn_left": KEY_Q, "turn_right": KEY_E, "tense": KEY_CTRL, "swap_lead": KEY_TAB,
	"focus_hips": KEY_SHIFT, "focus_legs": KEY_SPACE,
}

@export var fighter: Fighter
## Metres the hand cursor moves per pixel of mouse motion.
@export var mouse_sensitivity := 0.0022
## Hand plane limits, metres from the chest: x sideways, y up/down.
@export var cursor_limit := Vector2(0.55, 0.45)
@export var reach_min := 0.12
@export var reach_max := 0.65
@export var reach_step := 0.04

## x right, y up, in the hand plane.
var cursor := Vector2(0.0, -0.1)
## How far in front of the chest the lead hand sits.
var reach := 0.35


func _ready() -> void:
	# Run before the fighters so they read this tick's intent.
	process_physics_priority = -10
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = BINDINGS[action]
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			reach = minf(reach + reach_step, reach_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			reach = maxf(reach - reach_step, reach_min)
	elif event is InputEventMouseMotion and captured:
		move_cursor(event.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func move_cursor(pixels: Vector2) -> void:
	cursor += Vector2(pixels.x, -pixels.y) * mouse_sensitivity
	cursor = cursor.clamp(-cursor_limit, cursor_limit)


func _physics_process(_delta: float) -> void:
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
	it.weight_shift = Input.get_vector("move_left", "move_right", "move_back", "move_forward")

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	it.grip[FighterIntent.LEFT] = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	it.grip[FighterIntent.RIGHT] = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	# Arms hang until you take the mouse. Hands keep their last targets while
	# another group is in focus.
	for i in 2:
		it.hand_active[i] = captured and it.hand_active[i]
	if captured and it.focus == FighterIntent.Focus.HANDS:
		var targets := hand_targets(fighter, cursor, reach, it.lead)
		for i in 2:
			it.hand_target[i] = targets[i]
			it.hand_active[i] = true


## World targets for both hands from a cursor in the plane in front of the chest.
## The lead hand sits on the cursor; the other hand follows at half the distance,
## closer to the body, on its own side.
static func hand_targets(f: Fighter, cur: Vector2, depth: float, lead: int) -> Array[Vector3]:
	var hb := f.heading_basis()
	var origin: Vector3 = f.parts.chest.global_position
	var out: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	for i in 2:
		var side := -1.0 if i == FighterIntent.LEFT else 1.0
		var p: Vector3
		if i == lead:
			p = Vector3(cur.x + side * 0.06, cur.y, -depth)
		else:
			p = Vector3(side * 0.2 + cur.x * 0.45, cur.y * 0.5 - 0.05, -depth * 0.65)
		out[i] = origin + hb * p
	return out
