class_name FighterIntent
extends RefCounted

## What a fighter wants to do this tick. PlayerInput and the AI both write it;
## Fighter only ever reads it. This is the shared contract: see README.md.
## All positions are world space. Index 0 is the left hand/foot, 1 the right.

enum Focus { HANDS, HIPS, LEGS }

const LEFT := 0
const RIGHT := 1

## Which body group the controller is working with right now.
var focus := Focus.HANDS
## Which hand (and later leg) leads: LEFT or RIGHT.
var lead := RIGHT

## Where each hand should go. Only used while hand_active is true for that hand;
## an inactive arm relaxes to its hanging rest pose.
var hand_target: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var hand_active: Array[bool] = [false, false]
## Muscle push on each hand, world space, length 0..1 (1 = hand_muscle_force).
## The push pulls back on the shoulder, so it moves the arm, not the whole body.
var hand_effort: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## How firmly each arm holds its pose, 0 (limp) .. 1 (full strength).
var arm_tone: Array[float] = [1.0, 1.0]
## Hand closed (grip button held). Grabs a grip zone once GripSystem exists.
var grip: Array[bool] = [false, false]

## Weight shift, -1..1 per axis, in the fighter's heading frame: x = right, y = forward.
var weight_shift := Vector2.ZERO
## Shoulder turn, -1 (left) .. 1 (right).
var turn := 0.0
## Torso lean, -1 (back) .. 1 (forward).
var torso_lean := 0.0
## Body tension, 0 relaxed .. 1 fully tense.
var tension := 0.0

## Muscle push on each foot, world space, length 0..1 (1 = foot_muscle_force).
## The push pulls back on the hip.
var foot_effort: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## How firmly each leg holds its pose, 0 (limp) .. 1 (full strength).
var leg_tone: Array[float] = [1.0, 1.0]
## Clamp: bend that knee hard (hooks, closed guard, squeeze).
var leg_clamp: Array[bool] = [false, false]
## Put that leg back to standing straight (it otherwise holds the pose it was
## last pushed into). Hold it true for one tick.
var leg_stand: Array[bool] = [false, false]

## --- Fundamental moves (read by FighterMoves) ---
## Walk, world space (x, z), length 0..1 (1 = walk_speed). Standing only.
var move := Vector2.ZERO
## Direction to face, world space (x, z). Zero keeps the current heading.
var face_dir := Vector2.ZERO
## Level change, 0 (tall) .. 1 (low). Held at 1 it sits you down on the mat.
var crouch := 0.0
## On the mat, the hips and legs: y up = knees / legs up, y down = bridge
## (diagonals bridge over that shoulder), x = swing hips and legs that way.
## Sitting or on hands and knees, y down drives the hips up into a stand-up.
var hips := Vector2.ZERO
## On the mat, the chest and shoulders: y up = sit up (held while sitting:
## butt scoot forward; face down: push up), y down = lie back, x = shrimp to
## that side (face down: roll that way).
var upper := Vector2.ZERO
## Hips and legs follow the hands (lean, hip drive, throw turn, brace).
var full_body := true

## Reserved for ground mode (milestone 5). Not read yet.
var hip_target := Vector3.ZERO
var hip_active := false
var foot_target: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var foot_active: Array[bool] = [false, false]


func reset() -> void:
	focus = Focus.HANDS
	lead = RIGHT
	hand_active = [false, false]
	hand_effort = [Vector3.ZERO, Vector3.ZERO]
	arm_tone = [1.0, 1.0]
	grip = [false, false]
	weight_shift = Vector2.ZERO
	turn = 0.0
	torso_lean = 0.0
	foot_effort = [Vector3.ZERO, Vector3.ZERO]
	leg_tone = [1.0, 1.0]
	leg_clamp = [false, false]
	leg_stand = [false, false]
	tension = 0.0
	hip_active = false
	foot_active = [false, false]
	move = Vector2.ZERO
	face_dir = Vector2.ZERO
	crouch = 0.0
	hips = Vector2.ZERO
	upper = Vector2.ZERO
	full_body = true
