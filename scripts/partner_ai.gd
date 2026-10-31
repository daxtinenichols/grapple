class_name PartnerAI
extends Node

## Drives a Fighter through the same FighterIntent the player's controller
## writes: hand targets, muscle pushes, tone, grips, weight, lean, turn, legs.
## It never moves bodies itself, so it is exactly as strong and as clumsy as
## the player.
##   DUMMY: a semi-stiff training partner. Hands up in a loose guard, arms
##     half-firm, never grips. Grab it, pull it, push it, drag it down.
##   SPAR: a real opponent. Faces you, hand-fights for a sleeve and a lapel,
##     strips your grips, then pulls, pushes, snaps you down, turns you and
##     tries foot sweeps, backing off when its own balance goes.

enum Mode { DUMMY, SPAR }
enum Act { GUARD, REACH, PULL, PUSH, SNAP, TURN, SWEEP, RECOVER, STRIP, DOWN }

const ACT_NAMES := ["guard", "reaching for grips", "pulling", "pushing", "snapping you down",
	"turning you", "foot sweep", "recovering balance", "breaking your grip", "down"]
## Hand box in the chest frame (x right, y up, -z forward), metres. Same as PadInput.
const HAND_MIN := Vector3(-0.55, -0.6, -0.65)
const HAND_MAX := Vector3(0.55, 0.35, -0.08)

@export var fighter: Fighter
@export var opponent: Fighter
@export var grips: GripSystem
@export var mode := Mode.DUMMY

@export_group("Dummy")
## How firmly the dummy's arms hold its guard (FighterIntent.arm_tone).
@export var dummy_arm_tone := 0.45

@export_group("Spar")
## Seconds before the AI reacts to a change (it thinks this often).
@export var reaction := 0.15
## How fast (m/s) its hand targets move, like PadInput.hand_speed.
@export var hand_speed := 1.1
## How far (m) a hand target may run ahead of the real hand.
@export var hand_lead := 0.22
@export var arm_tone := 0.75
## 0..1: how much of its tension it uses when it attacks.
@export var aggression := 0.8
## How likely (0..1) it tries to strip a grip you hold on it.
@export var grip_fighting := 0.6
## How far (m, chest to chest) it can reach to start grip fighting.
@export var engage_range := 1.35
## How close (m, chest to chest) it walks in before reaching for grips.
@export var close_range := 0.8
## Seconds it lies on the mat before getting up by itself.
@export var get_up_delay := 1.2
@export var seed := 0

var act := Act.GUARD
## Seconds left in the current action.
var act_time := 0.0
var _rng := RandomNumberGenerator.new()
var _think := 0.0
## Per-hand target, offset from the chest in the chest frame.
var _offset: Array[Vector3] = [Vector3(-0.18, -0.15, -0.3), Vector3(0.18, -0.15, -0.3)]
## Where each hand wants to go (chest frame offset), and extra push on it.
var _want: Array[Vector3] = [Vector3(-0.18, -0.15, -0.3), Vector3(0.18, -0.15, -0.3)]
var _push: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _grip_want: Array[bool] = [false, false]
## Which opponent part each hand goes for while reaching.
var _plan: Array[String] = ["", ""]
var _reach_time := 0.0
var _side := 1
var _lean := 0.0
var _turn := 0.0
var _shift := Vector2.ZERO
var _tension := 0.0
var _sweep_leg := -1
var _stand_pending: Array[bool] = [false, false]
## The arm yanking free of a grip during STRIP, -1 if none.
var _strip_arm := -1
var _fighter_seen: Fighter
var _down_time := 0.0


func _ready() -> void:
	# Write the intent before the grips and the fighters read it.
	process_physics_priority = -10
	_rng.seed = seed if seed != 0 else randi()


func set_mode(m: Mode) -> void:
	mode = m
	_start(Act.GUARD, 0.5)
	_grip_want = [false, false]


func status() -> String:
	if mode == Mode.DUMMY:
		return "dummy"
	return "spar: " + ACT_NAMES[act]


func _physics_process(delta: float) -> void:
	if not is_instance_valid(fighter) or not fighter.parts.has("chest"):
		return
	if _fighter_seen != fighter:
		_fighter_seen = fighter
		_offset = PlayerInput.GUARD.duplicate()
		_want = PlayerInput.GUARD.duplicate()
		_start(Act.GUARD, 0.6)
	if mode == Mode.DUMMY:
		_dummy(delta)
	else:
		_spar(delta)


func _dummy(delta: float) -> void:
	var it := fighter.intent
	it.tension = 0.0
	it.turn = 0.0
	it.torso_lean = 0.0
	it.weight_shift = Vector2.ZERO
	it.move = Vector2.ZERO
	it.hips = Vector2.ZERO
	it.upper = Vector2.ZERO
	it.crouch = 0.0
	it.face_dir = _face_dir()
	for i in 2:
		_want[i] = PlayerInput.GUARD[i]
		_push[i] = Vector3.ZERO
		it.grip[i] = false
		it.foot_effort[i] = Vector3.ZERO
		it.leg_tone[i] = 1.0
		it.leg_clamp[i] = false
		it.leg_stand[i] = false
	_move_hands(delta, dummy_arm_tone)


# --- Sparring ----------------------------------------------------------------

func _spar(delta: float) -> void:
	var it := fighter.intent
	act_time -= delta
	_think -= delta
	if _think <= 0.0:
		_think = reaction * _rng.randf_range(0.7, 1.3)
		_decide()
	_do_act()
	it.tension = _tension
	it.torso_lean = _lean
	it.weight_shift = _shift.limit_length(1.0)
	it.turn = clampf(_turn, -1.0, 1.0)
	it.face_dir = _face_dir()
	_footwork()
	for i in 2:
		it.grip[i] = _grip_want[i]
	_move_hands(delta, arm_tone if act != Act.DOWN else 0.1)
	if act == Act.DOWN:
		for i in 2:
			it.hand_active[i] = false
		_get_up()


## Steps in to grip range when nothing is held, and back out when crowded.
## The fighter does the stepping (FighterMoves); this only sets the walk.
func _footwork() -> void:
	var it := fighter.intent
	it.move = Vector2.ZERO
	if act == Act.DOWN or not is_instance_valid(opponent) or not opponent.parts.has("chest"):
		return
	var d := _distance()
	var to: Vector3 = opponent.parts.chest.global_position - fighter.parts.chest.global_position
	to.y = 0.0
	if to.length() < 0.01:
		return
	var dir := Vector2(to.x, to.z).normalized()
	if _held_count() == 0 and d > close_range and d < engage_range * 2.5 and act in [Act.GUARD, Act.REACH]:
		it.move = dir * clampf((d - close_range) * 1.5, 0.0, 0.6)
	elif d < 0.45:
		it.move = -dir * 0.4


## On the mat: sit up, then drive the hips up into a stand-up, the same way
## the player does it with the sticks.
func _get_up() -> void:
	var it := fighter.intent
	it.move = Vector2.ZERO
	if not fighter.on_ground():
		it.upper = Vector2.ZERO
		it.hips = Vector2.ZERO
		return
	_down_time += 1.0 / Engine.physics_ticks_per_second
	if _down_time < get_up_delay:
		it.upper = Vector2.ZERO
		it.hips = Vector2.ZERO
		return
	var g := fighter.moves.ground
	it.upper = Vector2(0, 1)
	it.hips = Vector2(0, -1) if g == FighterMoves.Ground.SITTING or g == FighterMoves.Ground.ALL_FOURS else Vector2.ZERO


func _face_dir() -> Vector2:
	if not is_instance_valid(opponent) or not opponent.parts.has("chest"):
		return Vector2.ZERO
	var to: Vector3 = opponent.parts.chest.global_position - fighter.parts.chest.global_position
	to.y = 0.0
	return Vector2(to.x, to.z).normalized() if to.length() > 0.05 else Vector2.ZERO


## Picks what to do next from what it sees. Called every `reaction` seconds.
func _decide() -> void:
	var down: bool = fighter.has_fallen or fighter.parts.pelvis.global_position.y < 0.6
	if down or fighter.on_ground() or fighter.moves.state == FighterMoves.State.RISING:
		if act != Act.DOWN:
			_down_time = 0.0
			_start(Act.DOWN, 999.0)
		return
	if act == Act.DOWN:
		it_clear_ground()
		_start(Act.GUARD, 0.5)
	var foe_ok := is_instance_valid(opponent) and opponent.parts.has("chest") and not opponent.has_fallen
	if not foe_ok or _distance() > engage_range:
		if act != Act.GUARD:
			_start(Act.GUARD, 0.5)
		return
	# Own balance first: back off whatever it was doing.
	if fighter.base_margin < 0.015 and act in [Act.PULL, Act.PUSH, Act.SNAP, Act.TURN, Act.SWEEP]:
		_start(Act.RECOVER, 0.6)
		return
	if act_time > 0.0:
		if act == Act.REACH:
			_reach_time += reaction
			if _held_count() == 2 or (_held_count() == 1 and _reach_time > 1.2):
				_start(_pick_attack(), _rng.randf_range(0.8, 1.4))
		return
	# The current action ran out: choose the next one.
	var theirs := grips.grips_on(fighter) if grips else ([] as Array[Dictionary])
	if not theirs.is_empty() and _rng.randf() < grip_fighting and act != Act.STRIP:
		_start(Act.STRIP, 0.45)
		_strip_target(theirs[_rng.randi() % theirs.size()])
		return
	if _held_count() == 0:
		_start(Act.REACH, _rng.randf_range(2.0, 3.0))
		return
	if act in [Act.PULL, Act.PUSH, Act.SNAP, Act.TURN, Act.SWEEP, Act.STRIP]:
		_start(Act.RECOVER, _rng.randf_range(0.4, 0.9))
	else:
		_start(_pick_attack(), _rng.randf_range(0.8, 1.4))


func _pick_attack() -> Act:
	var r := _rng.randf()
	if r < 0.28:
		return Act.PULL
	if r < 0.45:
		return Act.PUSH
	if r < 0.65:
		return Act.SNAP
	if r < 0.83:
		return Act.TURN
	return Act.SWEEP


func _start(a: Act, t: float) -> void:
	act = a
	act_time = t
	_reach_time = 0.0
	_side = 1 if _rng.randf() < 0.5 else -1
	if a == Act.REACH:
		# Same-side hand on the sleeve, the other on the cross lapel, or both
		# on the lapels now and then.
		var lapels := _rng.randf() < 0.3
		var sleeve_hand := 0 if _rng.randf() < 0.6 else 1
		for i in 2:
			if _held(i):
				_plan[i] = ""
			elif lapels or i != sleeve_hand:
				_plan[i] = "lapel"
			else:
				_plan[i] = "sleeve"
	if a == Act.SWEEP:
		_sweep_leg = 0 if _rng.randf() < 0.5 else 1
	elif _sweep_leg >= 0:
		# Plant the sweeping leg again.
		_stand_pending[_sweep_leg] = true
		_sweep_leg = -1


## Sets this tick's hand goals, pushes, posture and legs for the current action.
func _do_act() -> void:
	var it := fighter.intent
	for i in 2:
		it.leg_stand[i] = _stand_pending[i]
		_stand_pending[i] = false
		it.foot_effort[i] = Vector3.ZERO
		it.leg_tone[i] = 1.0
		it.leg_clamp[i] = false
		_push[i] = Vector3.ZERO
	var cf := fighter.chest_frame()
	var hard := lerpf(0.3, 1.0, aggression)
	match act:
		Act.GUARD, Act.DOWN:
			_want = PlayerInput.GUARD.duplicate()
			_grip_want = [false, false]
			_relax()
		Act.RECOVER:
			for i in 2:
				_want[i] = Vector3(0.2 * (i * 2 - 1), -0.12, -0.32) if _held(i) else PlayerInput.GUARD[i]
			_relax()
		Act.REACH:
			_relax()
			_lean = 0.25
			for i in 2:
				if _held(i):
					_want[i] = Vector3(0.18 * (i * 2 - 1), -0.1, -0.35)
					continue
				var spot := _grip_spot(i)
				_want[i] = cf.inverse() * (spot - fighter.parts.chest.global_position)
				# Push through the spot a little so the hand actually lands on it.
				_want[i] += (_want[i] - Vector3(0.2 * (i * 2 - 1), 0.1, 0)).normalized() * 0.06
				var hand: Vector3 = _hand(i).global_position
				_grip_want[i] = hand.distance_to(spot) < 0.16
				_push[i] = (spot - hand).normalized() * 0.35
		Act.PULL:
			_lean = -0.6
			_tension = hard
			_shift = Vector2(0, -0.6)
			for i in 2:
				_want[i] = Vector3(0.2 * (i * 2 - 1), -0.15, -0.12)
				_push[i] = cf * Vector3(0, -0.1, 1).normalized() * hard
		Act.PUSH:
			_lean = 0.6
			_tension = hard
			_shift = Vector2(0, 0.7)
			for i in 2:
				_want[i] = Vector3(0.15 * (i * 2 - 1), -0.05, -0.62)
				_push[i] = cf * Vector3(0, 0, -1) * hard
		Act.SNAP:
			_lean = 0.8
			_tension = hard
			_shift = Vector2(0, -0.4)
			for i in 2:
				_want[i] = Vector3(0.15 * (i * 2 - 1), -0.6, -0.2)
				_push[i] = cf * Vector3(0, -1, 0.4).normalized() * hard
		Act.TURN:
			_tension = hard
			_turn = _side * 1.0
			_shift = Vector2(-_side * 0.6, -0.3)
			_lean = -0.2
			# One hand pulls across and back, the other pushes forward.
			for i in 2:
				var pulling := (i == 1) == (_side < 0)
				if pulling:
					_want[i] = Vector3(_side * 0.45, -0.2, -0.15)
					_push[i] = cf * Vector3(_side, 0, 0.6).normalized() * hard
				else:
					_want[i] = Vector3(_side * 0.2, 0.0, -0.55)
					_push[i] = cf * Vector3(_side * 0.4, 0, -1).normalized() * hard
		Act.SWEEP:
			_tension = hard
			var leg := _sweep_leg
			var other := 1 - leg
			_shift = Vector2(-0.9 if leg == 1 else 0.9, -0.2)
			_lean = -0.3
			for i in 2:
				_want[i] = Vector3(0.22 * (i * 2 - 1), -0.15, -0.18)
				_push[i] = cf * Vector3(0, 0, 0.6) * hard
			# Kick the foot into the opponent's nearest foot, across and low.
			var foe_foot := _nearest_foe_foot(leg)
			var foot: Vector3 = fighter.parts[("l_" if leg == 0 else "r_") + "foot"].global_position
			var d := foe_foot - foot
			d.y = 0.0
			it.foot_effort[leg] = (d.normalized() + Vector3(0, 0.15, 0)).normalized()
			it.leg_tone[leg] = 0.15
			it.foot_effort[other] = Vector3.ZERO
		Act.STRIP:
			_tension = 1.0
			# _strip_target set the arm; yank it down and back hard.
			for i in 2:
				if _strip_arm == i:
					_want[i] = Vector3(0.35 * (i * 2 - 1), -0.55, -0.1)
					_push[i] = cf * Vector3(i * 2 - 1, -1, 0.8).normalized()
					_grip_want[i] = false
	if act == Act.STRIP and act_time <= 0.0:
		_strip_arm = -1


## A grip the opponent holds on us: pick the arm (or chest side) it's on and
## yank that arm away.
func _strip_target(g: Dictionary) -> void:
	var n: String = grips.part_name(g)
	if n.begins_with("l_"):
		_strip_arm = 0
	elif n.begins_with("r_"):
		_strip_arm = 1
	else:
		# A lapel grip: the hand on that side knocks their wrist down.
		var local: Vector3 = fighter.chest_frame().inverse() * (g.body.to_global(g.anchor) - fighter.parts.chest.global_position)
		_strip_arm = 0 if local.x < 0.0 else 1
	_grip_want[_strip_arm] = false


func _relax() -> void:
	_lean = move_toward(_lean, 0.0, 0.05)
	_turn = 0.0
	_shift = _shift.move_toward(Vector2.ZERO, 0.05)
	_tension = 0.0


## Hand targets chase _want at hand_speed (never more than hand_lead ahead of
## the real hand), the same way PadInput moves them, plus the muscle push.
func _move_hands(delta: float, tone: float) -> void:
	var it := fighter.intent
	var cf := fighter.chest_frame()
	var chest: Vector3 = fighter.parts.chest.global_position
	for i in 2:
		var here := cf.inverse() * (_hand(i).global_position - chest)
		var o := _offset[i].move_toward(_want[i].clamp(HAND_MIN, HAND_MAX), hand_speed * delta)
		o = here + (o - here).limit_length(hand_lead)
		_offset[i] = o.clamp(HAND_MIN, HAND_MAX)
		it.hand_target[i] = chest + cf * _offset[i]
		it.hand_active[i] = true
		it.arm_tone[i] = tone
		it.hand_effort[i] = _push[i].limit_length(1.0)


# --- What it sees -------------------------------------------------------------

func _hand(i: int) -> RigidBody3D:
	return fighter.parts["l_hand" if i == 0 else "r_hand"]


func _held(i: int) -> bool:
	return grips != null and not grips.holding(fighter, i).is_empty()


func _held_count() -> int:
	return int(_held(0)) + int(_held(1))


func _distance() -> float:
	var d: Vector3 = opponent.parts.chest.global_position - fighter.parts.chest.global_position
	d.y = 0.0
	return d.length()


func it_clear_ground() -> void:
	fighter.intent.upper = Vector2.ZERO
	fighter.intent.hips = Vector2.ZERO


## Turn needed to square up to the opponent, -1..1 (the fighter can twist
## about 50 degrees at the shoulders).
func _facing() -> float:
	if not is_instance_valid(opponent) or not opponent.parts.has("chest"):
		return 0.0
	var local: Vector3 = fighter.heading_basis().inverse() * (opponent.parts.chest.global_position - fighter.parts.pelvis.global_position)
	return clampf(atan2(local.x, -local.z) / deg_to_rad(fighter.turn_deg * 2.0), -1.0, 1.0)


## Where hand i is going: the opponent's sleeve (their forearm across from
## it, i.e. on the same side of our view) or their lapel.
func _grip_spot(i: int) -> Vector3:
	var o := opponent
	var ob: Basis = o.parts.chest.global_basis.orthonormalized()
	if _plan[i] == "sleeve":
		# Our left hand takes their right sleeve (they face us), and vice versa.
		var fore: RigidBody3D = o.parts["r_forearm" if i == 0 else "l_forearm"]
		return fore.global_position - fore.global_basis.y * 0.05
	# Lapel: front of their chest, the side across from this hand.
	var x := 0.09 if i == 0 else -0.09
	return o.parts.chest.global_position + ob * Vector3(x, 0.04, -0.13)


func _nearest_foe_foot(leg: int) -> Vector3:
	var mine: Vector3 = fighter.parts[("l_" if leg == 0 else "r_") + "foot"].global_position
	var a: Vector3 = opponent.parts.l_foot.global_position
	var b: Vector3 = opponent.parts.r_foot.global_position
	return a if mine.distance_to(a) < mine.distance_to(b) else b
