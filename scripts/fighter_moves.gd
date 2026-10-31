class_name FighterMoves
extends RefCounted

## The automatic layer between FighterIntent and the joint motors: keeps a
## standing fighter up (pelvis support, stepping to catch its balance, facing),
## walks it, couples the hips and legs to what the hands do (full-body moves),
## and on the mat turns two analog sticks into fundamental movements: bridge,
## shrimp, sit up, butt scoot, legs up, hip swing, push up, roll and stand up.
##
## Everything here is a blend of target poses plus capped "muscle" assists that
## only work while the right body parts touch the mat, so the moves are
## physical: they can fail, be blocked by an opponent, or blend into each other.
## Fighter owns one of these and calls update() every physics tick.

enum State { STAND, DOWN, RISING, SITTING_DOWN }
enum Ground { SUPINE, SIDE, PRONE, SITTING, ALL_FOURS }

const G := 9.8
## Leg geometry (metres): hip anchor in the pelvis frame, thigh, shin, ankle height.
const HIP := Vector3(0.11, -0.04, 0.0)
const THIGH := 0.44
const SHIN := 0.42
const ANKLE_Y := 0.08

var f: Fighter
var state := State.STAND
var ground := Ground.SUPINE
## Seconds in the current state.
var state_time := 0.0

# --- Tuning (Fighter forwards its exports here) ---
## Pelvis height (m) while standing tall, and at full crouch.
var stand_height := 0.95
var crouch_height := 0.66
## Walking speed (m/s) at full stick.
var walk_speed := 1.1
## Horizontal force cap (N) for walking and keeping the hips over the feet.
var balance_force := 260.0
## Share of body weight the support carries while a foot is down.
var support_share := 0.9
## Yaw torque cap (Nm) for facing.
var face_torque := 240.0
var step_time := 0.3
var step_height := 0.09
## Half the distance between the feet (m), and how much bracing widens it.
var stance_half := 0.13
var brace_widen := 0.07
## The pelvis tilt (degrees) or height (m) that counts as falling.
var fall_tilt := 50.0
var fall_height := 0.5
## Losing balance: centre-of-mass speed (m/s) or distance past the feet (m).
var lose_speed := 2.5
## How firmly the legs hold their ground poses (0..1).
var ground_leg_tone := 0.55
## Push (N) of a shrimp's hip escape at full stick.
var shrimp_force := 420.0
var lose_offset := 0.27

# --- Standing state ---
## Planted ankle position per foot (world).
var anchor: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var anchor_yaw: Array[float] = [0.0, 0.0]
## Foot in the air, -1 if none.
var swing := -1
var _swing_t := 0.0
var _swing_from := Vector3.ZERO
var _swing_yaw0 := 0.0
var _last_step := 0
var _face_yaw := 0.0
var _crouch_full_t := 0.0
## Full-body extras worked out from the hands (heading frame): lean, turn,
## hip shift (x right, y forward), sink, hip yaw (rad), brace 0..1.
var auto_lean := 0.0
var auto_turn := 0.0
var auto_shift := Vector2.ZERO
var auto_sink := 0.0
var auto_hip_yaw := 0.0
var brace := 0.0
## Smoothed versions so a flick of the stick doesn't jerk the body.
var _sm_lean := 0.0
var _sm_turn := 0.0
var _sm_shift := Vector2.ZERO
var _sm_sink := 0.0
var _sm_yaw := 0.0
var _sm_brace := 0.0
## Total torso lean and turn this tick (intent + full-body), read by the upright assist.
var lean_total := 0.0
var turn_total := 0.0
var com_vel := Vector3.ZERO

# --- Ground state ---
var _cycle := 0.0
var _rise_from := 0.0
var _rise_hold := 0.0
## What the fighter is doing on the mat this tick, for the HUD and the AI.
var move_name := ""


func _init(fighter: Fighter) -> void:
	f = fighter


func reset_stance() -> void:
	state = State.STAND
	state_time = 0.0
	swing = -1
	var hb := f.heading_basis()
	_face_yaw = _yaw_of(hb)
	for i in 2:
		anchor[i] = _ankle(i)
		anchor[i].y = ANKLE_Y
		anchor_yaw[i] = _face_yaw


func standing() -> bool:
	return state == State.STAND or state == State.RISING


func on_ground() -> bool:
	return state == State.DOWN or state == State.SITTING_DOWN


func update(delta: float) -> void:
	state_time += delta
	com_vel = _com_velocity()
	match state:
		State.STAND:
			_stand(delta)
		State.SITTING_DOWN:
			_sit_down(delta)
		State.DOWN:
			_down(delta)
		State.RISING:
			_rise(delta)


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	_cycle = 0.0
	if s == State.STAND:
		reset_stance()


# =============================================================================
# Standing
# =============================================================================

func _stand(delta: float) -> void:
	var it := f.intent
	move_name = ""
	var pel: RigidBody3D = f.parts.pelvis
	var tilt := rad_to_deg(pel.global_basis.y.normalized().angle_to(Vector3.UP))
	if tilt > fall_tilt or pel.global_position.y < fall_height:
		_set_state(State.DOWN)
		return
	# Knocked off balance: moving too fast, or the hips too far past the feet
	# for a step to catch. The fighter goes loose and falls.
	var mid := (_ankle(0) + _ankle(1)) * 0.5
	var off := Vector2(f.com.x - mid.x, f.com.z - mid.z).length()
	var grace := 1.6 if state_time < 0.8 else 1.0
	if Vector2(com_vel.x, com_vel.z).length() > lose_speed * grace or off > lose_offset * grace:
		_set_state(State.DOWN)
		return

	_full_body(delta)

	# Facing: the intent's direction, plus the hips turning into a throw.
	if it.face_dir.length_squared() > 0.0001:
		_face_yaw = atan2(-it.face_dir.x, -it.face_dir.y)
	var hb := Basis(Vector3.UP, _face_yaw)
	var yaw_want := _face_yaw - _sm_yaw
	_apply_yaw(yaw_want)

	# Crouch (level change); held all the way down it sits you on the mat.
	var crouch := clampf(it.crouch + _sm_sink, 0.0, 1.0)
	var height := lerpf(stand_height, crouch_height, crouch)
	if it.crouch >= 0.999:
		_crouch_full_t += delta
		if _crouch_full_t > 0.45:
			_crouch_full_t = 0.0
			_set_state(State.SITTING_DOWN)
			return
	else:
		_crouch_full_t = 0.0

	_gait(delta, hb, height)


## Hands lead, the body follows (the Half Sword lesson): reaching far leans the
## torso in and drives the hips forward, pulling to the chest sinks and drops
## the hips back, hands swung to one side turn the shoulders and the hips that
## way (a throw), and any of these widens and braces the stance.
func _full_body(delta: float) -> void:
	var it := f.intent
	auto_lean = 0.0
	auto_turn = 0.0
	auto_shift = Vector2.ZERO
	auto_sink = 0.0
	auto_hip_yaw = 0.0
	brace = 0.0
	var n := 0
	var fwd := 0.0
	var side := 0.0
	# Measured in the chest's own frame, so the turn this causes doesn't
	# feed back into it.
	var cf := f.chest_frame()
	var chest: Vector3 = f.parts.chest.global_position
	for i in 2:
		if not it.hand_active[i]:
			continue
		var o := cf.inverse() * (it.hand_target[i] - chest)
		fwd += -o.z
		side += o.x
		n += 1
	if it.full_body and n > 0:
		fwd /= n
		side /= n
		var reach := clampf((fwd - 0.4) / 0.22, 0.0, 1.0)
		var pull := clampf((0.24 - fwd) / 0.14, 0.0, 1.0)
		var swing_side := clampf(side / 0.3, -1.0, 1.0)
		if absf(swing_side) < 0.25:
			swing_side = 0.0
		else:
			swing_side = (absf(swing_side) - 0.25) / 0.75 * signf(swing_side)
		auto_lean = reach * 0.8 - pull * 0.45
		auto_turn = swing_side * 0.9
		auto_shift = Vector2(0.0, reach * 0.6 - pull * 0.7)
		auto_sink = pull * 0.3 + reach * 0.15 + absf(swing_side) * 0.15
		auto_hip_yaw = swing_side * deg_to_rad(30.0)
		brace = maxf(maxf(pull, reach), absf(swing_side))
	var k := 1.0 - exp(-8.0 * delta)
	_sm_lean = lerpf(_sm_lean, auto_lean, k)
	_sm_turn = lerpf(_sm_turn, auto_turn, k)
	_sm_shift = _sm_shift.lerp(auto_shift, k)
	_sm_sink = lerpf(_sm_sink, auto_sink, k)
	_sm_yaw = lerpf(_sm_yaw, auto_hip_yaw, k)
	_sm_brace = lerpf(_sm_brace, brace, k)
	lean_total = clampf(it.torso_lean + _sm_lean, -1.0, 1.0)
	turn_total = clampf(it.turn + _sm_turn, -1.0, 1.0)
	_set_torso(lean_total, turn_total)


func _set_torso(lean: float, turn: float, side_bend := 0.0) -> void:
	# Forward lean is negative flex for the spine (positive tips it back).
	f.set_target("abdomen", Vector3(-lean * f.lean_deg, -turn * f.turn_deg, side_bend * 15.0))
	f.set_target("chest", Vector3(-lean * f.lean_deg * 0.7, -turn * f.turn_deg, side_bend * 10.0))


## Yaw torque on the pelvis (and a share on the chest) toward `yaw`.
func _apply_yaw(yaw: float, cap := -1.0) -> void:
	if cap < 0.0:
		cap = face_torque
	var pel: RigidBody3D = f.parts.pelvis
	var err := angle_difference(_yaw_of(f.heading_basis()), yaw)
	var tq := clampf(err * 260.0 - pel.angular_velocity.y * 30.0, -cap, cap)
	pel.apply_torque(Vector3(0, tq * 0.7, 0))
	f.parts.chest.apply_torque(Vector3(0, tq * 0.3, 0))


## Pelvis support, walking force and stepping.
func _gait(delta: float, hb: Basis, height: float) -> void:
	var it := f.intent
	var pel: RigidBody3D = f.parts.pelvis
	var mass := _mass()
	var free := [it.foot_effort[0].length_squared() > 0.0001, it.foot_effort[1].length_squared() > 0.0001]
	var planted := [swing != 0 and not free[0], swing != 1 and not free[1]]
	var grounded := [planted[0] and _foot_low(0), planted[1] and _foot_low(1)]
	var support: int = int(grounded[0]) + int(grounded[1])

	# Where the hips should be: over the planted feet, shifted by the intent and
	# the full-body moves, and carried along by walking.
	var feet_mid := Vector3.ZERO
	var nf := 0
	for i in 2:
		if planted[i]:
			feet_mid += anchor[i]
			nf += 1
	feet_mid = feet_mid / nf if nf > 0 else pel.global_position
	var shift := (it.weight_shift.limit_length(1.0) * 0.07) + _sm_shift * 0.12
	var hip_goal := feet_mid + hb.x * shift.x - hb.z * shift.y
	var move := Vector3(it.move.x, 0.0, it.move.y).limit_length(1.0)
	var v_want := move * walk_speed

	if support > 0:
		# Hold the pelvis at the standing (or crouched) height.
		var y := pel.global_position.y
		var a := 70.0 * (height - y) - 14.0 * pel.linear_velocity.y
		var fy := clampf(mass * (G * support_share + a), 0.0, mass * G * 1.8)
		pel.apply_central_force(Vector3(0, fy, 0))
		# Walk, or keep the hips over the feet when not walking.
		var v := Vector3(com_vel.x, 0.0, com_vel.z)
		var acc := (v_want - v) * 5.0
		if move.length() < 0.05:
			var to_goal := hip_goal - f.com
			to_goal.y = 0.0
			acc += to_goal * 30.0
		var fh := (acc * mass).limit_length(balance_force)
		pel.apply_central_force(fh * 0.6)
		f.parts.chest.apply_central_force(fh * 0.4)

	# --- Stepping ---
	var width := stance_half + brace_widen * _sm_brace
	var lead := com_vel * 0.18
	lead.y = 0.0
	if swing >= 0:
		_swing_t += delta / step_time
		if _swing_t >= 1.0:
			anchor[swing] = _step_goal(swing, hb, width, lead)
			anchor_yaw[swing] = _face_yaw
			_last_step = swing
			swing = -1
	elif support > 0:
		var best := -1
		var best_err := 0.0
		var com_h := Vector2(f.com.x, f.com.z)
		for i in 2:
			if free[i] or not planted[1 - i]:
				continue
			var goal := _step_goal(i, hb, width, lead)
			var e := Vector2(goal.x - anchor[i].x, goal.z - anchor[i].z).length()
			var yaw_e := absf(angle_difference(anchor_yaw[i], _face_yaw))
			var thresh := 0.06 if move.length() > 0.1 else 0.15
			# Braced (throwing, pulling) the feet stay planted unless balance goes.
			thresh += 0.12 * _sm_brace
			if f.base_margin < -0.03:
				thresh = 0.04
			var score := e / thresh + yaw_e / deg_to_rad(35.0)
			if i == _last_step:
				score *= 0.7
			if score > 1.0 and score > best_err:
				best = i
				best_err = score
		if best >= 0:
			swing = best
			_swing_t = 0.0
			_swing_from = anchor[best]
			_swing_yaw0 = anchor_yaw[best]

	# --- Leg joint targets ---
	for i in 2:
		if free[i]:
			_hold_leg(i)
			continue
		var ankle := anchor[i]
		var yaw := anchor_yaw[i]
		if swing == i:
			var t := clampf(_swing_t, 0.0, 1.0)
			var to := _step_goal(i, hb, width, lead)
			var s := t * t * (3.0 - 2.0 * t)
			ankle = _swing_from.lerp(to, s)
			ankle.y = ANKLE_Y + sin(t * PI) * step_height
			yaw = lerp_angle(_swing_yaw0, _face_yaw, s)
		leg_ik(i, ankle, Basis(Vector3.UP, yaw), hb, 0.1, height)


## Where foot i should land: under its hip, ahead by the body's speed, plus a
## catch step when the centre of mass is leaving the base.
func _step_goal(i: int, hb: Basis, width: float, lead: Vector3) -> Vector3:
	var side := -1.0 if i == 0 else 1.0
	var pel: Vector3 = f.parts.pelvis.global_position
	var shift := (f.intent.weight_shift.limit_length(1.0) * 0.07) + _sm_shift * 0.12
	var hip := pel - hb.x * shift.x + hb.z * shift.y
	# Bracing (pulling or throwing) puts one foot a little ahead of the other.
	var stagger := 0.06 * _sm_brace * (1.0 if i == 1 else -1.0)
	var g := hip + hb.x * side * width - hb.z * stagger + lead.limit_length(0.35)
	g.y = ANKLE_Y
	return g


func _hold_leg(i: int) -> void:
	var p := "l_" if i == 0 else "r_"
	for n in ["thigh", "shin", "foot"]:
		var j: Dictionary = f.joint_entry(p + n)
		f.set_target_quat(p + n, f.joint_rotation(j))


## Two-bone leg IK: joint targets that put the ankle at `ankle` with the knee
## pointing along `frame`'s forward and the foot turned to `foot_basis`.
## `pelvis_y` (if >= 0) solves as if the pelvis were at that height, so the
## legs themselves raise or lower the body toward it.
func leg_ik(i: int, ankle: Vector3, foot_basis: Basis, frame: Basis, knee_out := 0.1, pelvis_y := -1.0) -> void:
	var side := -1.0 if i == 0 else 1.0
	var p := "l_" if i == 0 else "r_"
	var pb: Basis = f.parts.pelvis.global_basis.orthonormalized()
	var pel: Vector3 = f.parts.pelvis.global_position
	if pelvis_y >= 0.0:
		pel.y = pelvis_y
	var hip: Vector3 = pel + pb * Vector3(HIP.x * side, HIP.y, HIP.z)
	var to := ankle - hip
	var d := clampf(to.length(), 0.22, THIGH + SHIN - 0.004)
	var u := to.normalized() if to.length() > 0.001 else -pb.y
	var pole := -frame.z + frame.x * side * knee_out
	var pp := pole - u * pole.dot(u)
	if pp.length_squared() < 0.0001:
		pp = -pb.z - u * (-pb.z).dot(u)
	pp = pp.normalized()
	var a := acos(clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0))
	var knee := PI - acos(clampf((THIGH * THIGH + SHIN * SHIN - d * d) / (2.0 * THIGH * SHIN), -1.0, 1.0))
	var up_dir := (u * cos(a) + pp * sin(a)).normalized()
	var k := hip + up_dir * THIGH
	var bend := (hip + u * d - k).normalized()
	bend = bend - up_dir * bend.dot(up_dir)
	if bend.length_squared() < 0.0001:
		bend = -pp
	var y := -up_dir
	var z := bend.normalized()
	var thigh_w := Basis(y.cross(z), y, z).orthonormalized()
	f.set_target_quat(p + "thigh", (pb.inverse() * thigh_w).get_rotation_quaternion())
	var shin_q := Quaternion(Vector3.RIGHT, -knee)
	f.set_target_quat(p + "shin", shin_q)
	var shin_w := thigh_w * Basis(shin_q)
	f.set_target_quat(p + "foot", (shin_w.inverse() * foot_basis).get_rotation_quaternion())


# =============================================================================
# Sitting down from a full crouch
# =============================================================================

func _sit_down(delta: float) -> void:
	move_name = "sitting down"
	var pel: RigidBody3D = f.parts.pelvis
	var hb := Basis(Vector3.UP, _face_yaw)
	var k := clampf(state_time / 0.8, 0.0, 1.0)
	var target := lerpf(crouch_height, 0.2, k)
	var mass := _mass()
	var a := 30.0 * (target - pel.global_position.y) - 8.0 * pel.linear_velocity.y
	pel.apply_central_force(Vector3(0, clampf(mass * (G * 0.8 + a), 0.0, mass * G), 0))
	# Hips go back behind the heels as you sit.
	var back := hb.z * 0.4 * k
	var mid := (anchor[0] + anchor[1]) * 0.5 + back
	var to := mid - pel.global_position
	to.y = 0.0
	pel.apply_central_force((to * 600.0 - Vector3(pel.linear_velocity.x, 0, pel.linear_velocity.z) * 60.0).limit_length(200.0))
	_set_torso(0.3 * (1.0 - k), 0.0)
	# Keep the chest from pitching forward over the knees.
	_tip_chest(Vector3.UP + hb.z * 0.3 * k, 260.0)
	for i in 2:
		leg_ik(i, anchor[i], Basis(Vector3.UP, anchor_yaw[i]), hb, 0.3, target)
	if pel.global_position.y < 0.5 or state_time > 1.8:
		_set_state(State.DOWN)


# =============================================================================
# On the mat
# =============================================================================

## The fighter's own frame on the mat: spine (pelvis to chest), right, front.
func _body_axes() -> Dictionary:
	var pel: RigidBody3D = f.parts.pelvis
	var chest: RigidBody3D = f.parts.chest
	var spine: Vector3 = (chest.global_position - pel.global_position).normalized()
	var right: Vector3 = pel.global_basis.x.normalized()
	var front: Vector3 = -chest.global_basis.z.normalized()
	return {"spine": spine, "right": right, "front": front}


func classify_ground() -> Ground:
	var ax := _body_axes()
	var pel_y: float = f.parts.pelvis.global_position.y
	var chest_y: float = f.parts.chest.global_position.y
	if ax.spine.y > 0.55 and ax.front.y > -0.5:
		return Ground.SITTING
	if ax.front.y < -0.5:
		return Ground.ALL_FOURS if chest_y > 0.42 and pel_y > 0.42 else Ground.PRONE
	if ax.front.y > 0.5:
		return Ground.SUPINE
	return Ground.SIDE


func _down(delta: float) -> void:
	var it := f.intent
	# Caught before reaching the mat (a grip, a lucky stumble): still upright
	# with the feet under you, so take the balance back.
	var pel0: RigidBody3D = f.parts.pelvis
	if pel0.global_position.y > 0.8 and state_time > 0.3 and _feet_down() == 2 \
			and pel0.global_basis.y.normalized().angle_to(Vector3.UP) < deg_to_rad(20.0):
		_set_state(State.STAND)
		return
	ground = classify_ground()
	var hips := it.hips.limit_length(1.0)
	var upper := it.upper.limit_length(1.0)
	var ax := _body_axes()
	var pel: RigidBody3D = f.parts.pelvis
	var chest: RigidBody3D = f.parts.chest
	var mass := _mass()
	_cycle += delta
	lean_total = 0.0
	turn_total = 0.0
	var names: Array[String] = []

	# ---- Legs: a blend of poses ----
	# thigh flex, knee bend, splay (degrees) per leg.
	var flex := [25.0, 25.0]
	var knee := [35.0, 35.0]
	var splay := [8.0, 8.0]
	var leg_up := maxf(hips.y, 0.0)
	var bridge := maxf(-hips.y, 0.0)
	if leg_up > 0.0:
		names.append("legs up")
		for i in 2:
			flex[i] = lerpf(flex[i], 85.0, leg_up)
			knee[i] = lerpf(knee[i], 70.0, leg_up)
	# Swing the hips and legs to one side.
	var sw := hips.x
	if absf(sw) > 0.05:
		names.append("hip swing " + ("right" if sw > 0.0 else "left"))
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			# Leg on the swing side opens out, the other crosses in.
			splay[i] += sw * side * (30.0 if side * sw > 0.0 else 18.0)
	var torso_lean := 0.0
	var side_bend := 0.0

	match ground:
		Ground.SUPINE, Ground.SIDE:
			if bridge > 0.0:
				names.append("bridge" + (" left" if hips.x < -0.3 else " right" if hips.x > 0.3 else ""))
				for i in 2:
					# Feet planted, knees bent, the hips extend to lift.
					flex[i] = lerpf(flex[i], 30.0 - 30.0 * bridge, bridge)
					knee[i] = lerpf(knee[i], 85.0, bridge)
				if _feet_down() > 0:
					var up := bridge * 520.0 * f.stamina
					pel.apply_central_force(Vector3(0, up, 0))
					chest.apply_central_force(Vector3(0, up * 0.2, 0))
					# Over a shoulder: roll toward that side.
					if absf(hips.x) > 0.2:
						_roll_to(-hips.x * 0.75, bridge, ax)
			if absf(sw) > 0.05:
				# Pivot on the back: turn the body around the mat normal.
				var tq: float = -sw * 170.0 - pel.angular_velocity.y * 20.0
				pel.apply_torque(Vector3(0, tq, 0))
				chest.apply_torque(Vector3(0, tq * 0.8, 0))
			_upper_on_back(upper, ax, flex, knee, names)
		Ground.SITTING:
			# Sitting: hips flexed, legs out in front.
			for i in 2:
				flex[i] = maxf(flex[i], 60.0 + 25.0 * leg_up)
				knee[i] = maxf(knee[i], 30.0)
			torso_lean = 0.4
			if upper.y > -0.2:
				_hold_upright(0.75, 220.0)
			if absf(sw) > 0.05:
				var tq: float = -sw * 90.0
				pel.apply_torque(Vector3(0, tq, 0))
				chest.apply_torque(Vector3(0, tq * 0.5, 0))
			if upper.y > 0.3:
				# Already up: keep pushing up to butt scoot forward.
				names.append("butt scoot")
				var phase := fmod(_cycle, 0.7) / 0.7
				var fwd: Vector3 = ax.front
				fwd.y = 0.0
				fwd = fwd.normalized()
				if phase < 0.45:
					for i in 2:
						knee[i] = lerpf(knee[i], 85.0, upper.y)
				else:
					pel.apply_central_force(fwd * 230.0 * upper.y)
					pel.apply_central_force(Vector3(0, 220.0 * upper.y, 0))
			elif upper.y < -0.2:
				names.append("lying back")
				torso_lean = -0.3
				for i in 2:
					flex[i] = 30.0
				_tip_chest(-ax.front, -upper.y * 320.0)
			if absf(upper.x) > 0.2:
				_shrimp(upper.x, ax, flex, knee, names)
			if bridge > 0.3:
				names.append("standing up")
				_rise_hold += delta
				if _rise_hold > 0.25:
					_start_rise()
					return
			else:
				_rise_hold = 0.0
		Ground.PRONE, Ground.ALL_FOURS:
			if upper.y > 0.2 or ground == Ground.ALL_FOURS:
				names.append("push up" if ground == Ground.PRONE else "on hands and knees")
				var k := maxf(upper.y, 0.0) if ground == Ground.PRONE else 1.0
				for i in 2:
					flex[i] = lerpf(flex[i], 85.0, k)
					knee[i] = lerpf(knee[i], 85.0, k)
				var feet_hands := _hands_down() + _knees_down()
				if feet_hands > 0:
					var lift := upper.y if ground == Ground.PRONE else maxf(upper.y, 0.4)
					_lift_part(pel, 0.48, lift * 600.0)
					_lift_part(chest, 0.52, lift * 500.0)
					_hold_level(lift)
			if absf(upper.x) > 0.2:
				names.append("rolling " + ("right" if upper.x > 0.0 else "left"))
				var roll: Vector3 = ax.spine * (-upper.x) * 170.0
				pel.apply_torque(roll)
				chest.apply_torque(roll)
			if bridge > 0.3 and (ground == Ground.ALL_FOURS or pel.global_position.y > 0.38):
				names.append("standing up")
				_rise_hold += delta
				if _rise_hold > 0.25:
					_start_rise()
					return
			else:
				_rise_hold = 0.0
			torso_lean = 0.2

	# Pose the legs. Tone ramps up after landing so a fall doesn't turn into
	# a leg-powered launch.
	var tone := lerpf(0.15, ground_leg_tone, clampf(state_time / 0.8, 0.0, 1.0))
	f.set_auto_leg_tone(tone)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p := "l_" if i == 0 else "r_"
		var sp := clampf(splay[i], -14.0, 44.0)
		f.set_target(p + "thigh", Vector3(clampf(flex[i], -25.0, 88.0), 0.0, sp * side))
		f.set_target(p + "shin", Vector3(-clampf(knee[i], 0.0, 88.0), 0.0, 0.0))
		f.set_target(p + "foot", Vector3(clampf(knee[i] - flex[i], -40.0, 25.0) * 0.5, 0.0, 0.0))
	if ground != Ground.SUPINE and ground != Ground.SIDE:
		_set_torso(torso_lean, 0.0, side_bend)
	_auto_hands(upper, ax)
	move_name = ", ".join(names)


## Upper body on the back or side: sit up, lie flat, shrimp.
func _upper_on_back(upper: Vector2, ax: Dictionary, flex: Array, knee: Array, names: Array[String]) -> void:
	var lean := 0.0
	if upper.y > 0.05:
		names.append("sitting up")
		lean = upper.y
		for i in 2:
			flex[i] = lerpf(flex[i], 55.0, upper.y)
		# Curl the chest up toward sitting.
		_tip_chest(Vector3.UP, upper.y * 340.0)
		f.parts.chest.apply_central_force(Vector3(0, upper.y * 170.0, 0))
	elif upper.y < -0.05:
		names.append("flat")
		lean = upper.y * 0.4
	if absf(upper.x) > 0.2:
		_shrimp(upper.x, ax, flex, knee, names)
	_set_torso(lean, upper.x * 0.5)


## Shrimp (hip escape) to one side: turn onto that side, then in pulses the
## bottom foot pushes and the hips shoot away, back toward the feet.
func _shrimp(x: float, ax: Dictionary, flex: Array, knee: Array, names: Array[String]) -> void:
	names.append("shrimp " + ("right" if x > 0.0 else "left"))
	var pel: RigidBody3D = f.parts.pelvis
	var chest: RigidBody3D = f.parts.chest
	var amount := absf(x)
	var side := signf(x)
	# Roll onto that side (the right hip comes up for a left shrimp).
	_roll_to(-side * 0.85, amount, ax)
	var want: Vector3 = ax.right * side
	var phase := fmod(_cycle, 0.8) / 0.8
	var top := 1 if side < 0.0 else 0
	var bottom := 1 - top
	if phase < 0.45:
		# Load: bottom foot planted near the butt, top knee in as a frame.
		knee[bottom] = lerpf(knee[bottom], 85.0, amount)
		flex[bottom] = lerpf(flex[bottom], 35.0, amount)
		knee[top] = lerpf(knee[top], 75.0, amount)
		flex[top] = lerpf(flex[top], 65.0, amount)
	else:
		# Push: the bottom leg extends and the hips shoot away from the side
		# you face, back toward your feet.
		knee[bottom] = lerpf(knee[bottom], 10.0, amount)
		flex[bottom] = lerpf(flex[bottom], 5.0, amount)
		knee[top] = lerpf(knee[top], 75.0, amount)
		flex[top] = lerpf(flex[top], 65.0, amount)
		if pel.global_position.y < 0.42:
			var away: Vector3 = -ax.front - ax.spine * 0.5
			away.y = 0.0
			var push: Vector3 = away.normalized() * shrimp_force * amount * f.stamina
			pel.apply_central_force(push)
			f.parts.abdomen.apply_central_force(push * 0.4)
			chest.apply_central_force(push * 0.15)


## Rolls the body about its spine until the right hip's height reads
## `right_up` (sin of the roll: 0 flat on the back, 1 on the left side, -1 on
## the right side), with `amount` of the strength.
func _roll_to(right_up: float, amount: float, ax: Dictionary) -> void:
	var pel: RigidBody3D = f.parts.pelvis
	var chest: RigidBody3D = f.parts.chest
	var err: float = right_up - ax.right.y
	var spin: float = (pel.angular_velocity + chest.angular_velocity).dot(ax.spine) * 0.5
	var roll: Vector3 = ax.spine * (clampf(err * 3.0, -1.0, 1.0) * 170.0 * amount - spin * 25.0)
	pel.apply_torque(roll)
	chest.apply_torque(roll * 0.7)


## The hands on the mat look after themselves unless a bumper hands one to
## the right stick: they post when you sit, frame when you're on your back or
## shrimp, and plant under the shoulders when you push up.
func _auto_hands(upper: Vector2, ax: Dictionary) -> void:
	var it := f.intent
	var chest: Vector3 = f.parts.chest.global_position
	var pel: Vector3 = f.parts.pelvis.global_position
	for i in 2:
		if it.hand_active[i]:
			continue
		var side := -1.0 if i == 0 else 1.0
		var t := Vector3.ZERO
		match ground:
			Ground.SITTING:
				t = pel + ax.right * side * 0.32 - ax.front * 0.12
				t.y = 0.04
			Ground.PRONE, Ground.ALL_FOURS:
				t = chest + ax.right * side * 0.2 + ax.spine * 0.12
				t.y = 0.04
			_:
				# Frame: forearms up in front of the chest, a bit toward the shrimp side.
				t = chest + ax.front * 0.3 + ax.right * (side * 0.14 + upper.x * 0.15) + ax.spine * 0.1
		f.drive_hand(i, t, 0.8)


## Torque on the chest (and pelvis) that tips its spine axis toward `dir`.
func _tip_chest(dir: Vector3, strength: float) -> void:
	var chest: RigidBody3D = f.parts.chest
	var up: Vector3 = chest.global_basis.y.normalized()
	var axis := up.cross(dir.normalized())
	if axis.length_squared() < 0.000001:
		return
	var w := chest.angular_velocity
	var tq := axis.normalized() * minf(axis.length() * 3.0, 1.0) * strength - w * 20.0
	chest.apply_torque(tq)
	f.parts.pelvis.apply_torque(tq * 0.5)


## Keeps a sitting torso from falling back over (pelvis and chest toward a
## spine `tilt` of upright, 1 = straight up).
func _hold_upright(min_up: float, strength: float) -> void:
	var chest: RigidBody3D = f.parts.chest
	var up: Vector3 = chest.global_basis.y.normalized()
	if up.y < min_up:
		_tip_chest(Vector3.UP, strength)


## Holds the trunk roughly level on hands and knees.
func _hold_level(k: float) -> void:
	var chest: RigidBody3D = f.parts.chest
	var pel: RigidBody3D = f.parts.pelvis
	var spine: Vector3 = chest.global_position - pel.global_position
	var flat := spine
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var axis := spine.normalized().cross(flat.normalized())
	var tq := axis * 300.0 * k - chest.angular_velocity * 15.0 * k
	chest.apply_torque(tq)
	pel.apply_torque(tq * 0.5)


func _lift_part(b: RigidBody3D, h: float, cap: float) -> void:
	var a := 40.0 * (h - b.global_position.y) - 6.0 * b.linear_velocity.y
	b.apply_central_force(Vector3(0, clampf(b.mass * 3.0 * (G + a), 0.0, cap), 0))


# =============================================================================
# Standing up
# =============================================================================

func _start_rise() -> void:
	_rise_hold = 0.0
	_rise_from = f.parts.pelvis.global_position.y
	var hb := f.heading_basis()
	_face_yaw = _yaw_of(hb)
	var pel: Vector3 = f.parts.pelvis.global_position
	# Plant the feet under the hips (a technical stand-up).
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		anchor[i] = pel + hb.x * side * stance_half + hb.z * 0.05
		anchor[i].y = ANKLE_Y
		anchor_yaw[i] = _face_yaw
	swing = -1
	state = State.RISING
	state_time = 0.0
	move_name = "standing up"


func _rise(_delta: float) -> void:
	move_name = "standing up"
	var pel: RigidBody3D = f.parts.pelvis
	var mass := _mass()
	var t := clampf(state_time / 1.1, 0.0, 1.0)
	var s := t * t * (3.0 - 2.0 * t)
	var height := lerpf(_rise_from, stand_height, s)
	var a := 50.0 * (height - pel.global_position.y) - 10.0 * pel.linear_velocity.y
	pel.apply_central_force(Vector3(0, clampf(mass * (G * 0.95 + a), 0.0, mass * G * 1.6), 0))
	f.parts.chest.apply_central_force(Vector3(0, 120.0 * (1.0 - s), 0))
	var hb := Basis(Vector3.UP, _face_yaw)
	_apply_yaw(_face_yaw)
	var mid := (anchor[0] + anchor[1]) * 0.5
	var to := mid - f.com
	to.y = 0.0
	var v := Vector3(com_vel.x, 0, com_vel.z)
	var fh := ((to * 40.0 - v * 8.0) * mass).limit_length(300.0)
	pel.apply_central_force(fh * 0.6)
	f.parts.chest.apply_central_force(fh * 0.4)
	_set_torso(0.3 * (1.0 - s), 0.0)
	# Keep the trunk coming up, not pitching over the knees.
	_tip_chest(Vector3.UP, 380.0)
	var pb: Vector3 = pel.global_basis.y.normalized()
	var ax := pb.cross(Vector3.UP)
	if ax.length_squared() > 0.000001:
		pel.apply_torque(ax.normalized() * minf(ax.length() * 3.0, 1.0) * 220.0 - pel.angular_velocity * 15.0)
	for i in 2:
		leg_ik(i, anchor[i], Basis(Vector3.UP, anchor_yaw[i]), hb, 0.1, height)
	var tilt := rad_to_deg(pel.global_basis.y.normalized().angle_to(Vector3.UP))
	if t >= 1.0 and pel.global_position.y > stand_height - 0.12 and tilt < 30.0:
		_set_state(State.STAND)
		f.stood_up()
	elif state_time > 2.5:
		# Didn't make it: back down.
		_set_state(State.DOWN)


# =============================================================================
# Helpers
# =============================================================================

func _mass() -> float:
	var m := 0.0
	for p: RigidBody3D in f.parts.values():
		m += p.mass
	return m


func _com_velocity() -> Vector3:
	var m := 0.0
	var v := Vector3.ZERO
	for p: RigidBody3D in f.parts.values():
		m += p.mass
		v += p.linear_velocity * p.mass
	return v / m


func _yaw_of(b: Basis) -> float:
	var fwd := -b.z
	return atan2(-fwd.x, -fwd.z)


func _ankle(i: int) -> Vector3:
	var foot: RigidBody3D = f.parts["l_foot" if i == 0 else "r_foot"]
	# The ankle joint sits 4 cm above and 5 cm behind the foot's centre.
	return foot.global_transform * Vector3(0, 0.04, 0.05)


func _foot_low(i: int) -> bool:
	var foot: RigidBody3D = f.parts["l_foot" if i == 0 else "r_foot"]
	return foot.global_position.y < 0.15


func _feet_down() -> int:
	return int(_foot_low(0)) + int(_foot_low(1))


func _hands_down() -> int:
	return int(f.parts.l_hand.global_position.y < 0.12) + int(f.parts.r_hand.global_position.y < 0.12)


func _knees_down() -> int:
	var n := 0
	for p in ["l_shin", "r_shin"]:
		var b: RigidBody3D = f.parts[p]
		if (b.global_transform * Vector3(0, 0.2, 0)).y < 0.14:
			n += 1
	return n
