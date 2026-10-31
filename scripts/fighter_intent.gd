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
## Hand closed (grip button held). Grabs a grip zone once GripSystem exists.
var grip: Array[bool] = [false, false]

## Weight shift, -1..1 per axis, in the fighter's heading frame: x = right, y = forward.
var weight_shift := Vector2.ZERO
## Shoulder turn, -1 (left) .. 1 (right).
var turn := 0.0
## Body tension, 0 relaxed .. 1 fully tense.
var tension := 0.0

## Reserved for ground mode (milestone 5). Not read yet.
var hip_target := Vector3.ZERO
var hip_active := false
var foot_target: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var foot_active: Array[bool] = [false, false]


func reset() -> void:
	focus = Focus.HANDS
	lead = RIGHT
	hand_active = [false, false]
	grip = [false, false]
	weight_shift = Vector2.ZERO
	turn = 0.0
	tension = 0.0
	hip_active = false
	foot_active = [false, false]
