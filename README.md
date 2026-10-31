# Grapple Prototype

Godot 4.4+ with Jolt physics at 120 ticks per second.

## Open it
1. Godot Project Manager > Import > pick this folder's `project.godot`.
2. Press F5 (Run Project).

## Controls
Whichever device you touched last drives the fighter. Controls are built around
fundamental moves: one stick is your base, the other your upper body, and the
fighter balances, steps and blends the moves itself (design doc:
https://claude.ai/artifact/V48926KUJ4AoSziN9xjo5n).

### Controller (Xbox 360 layout, the main scheme)

**Standing**

| Input | Action |
| --- | --- |
| Left stick | Walk, relative to the camera. You face your partner automatically when it is within 3 m, otherwise you turn the way you walk. The legs step by themselves, and also step to catch you after a shove. |
| Right stick | Both hands: sideways, up = push / reach forward, down = pull back to your chest. The whole body follows: reaching far leans you in and drives the hips forward, pulling sinks you and drops the hips back, swinging both hands to one side turns the shoulders and hips together like a throw while the feet widen and stay planted. |
| Hold LB / RB | The right stick moves only the left / right hand; the other one stays. |
| LT / RT | Close the left / right hand (grip), standing or on the mat. |
| Hold B | Lower your stance (level change). Hold it all the way down to sit on the mat. |
| Hold A | Tense up. |
| Right stick click | Hands back to your guard. |
| D-pad left / right, up / down | Swing the camera, zoom. |
| Start (or V) | First person / third person. |
| Back | Reset. |

**On the mat** (the sticks switch by themselves when you go down)

| Stick | Up | Down | Left / right |
| --- | --- | --- | --- |
| Left (hips and legs) | Knees and feet up toward your partner (guard, frames) | Bridge; down-left / down-right bridges over that shoulder | Swing your hips and legs that way (pivot on your back, turn on your butt) |
| Right (chest) | Sit up; keep holding once sitting to butt scoot forward. Face down: push up onto hands and knees | Lie back down | Shrimp: turn onto that side and push the hips away. Face down: roll that way |

- **Stand up:** sit up (right stick up) and push the left stick down to drive the hips up, a technical stand-up. From hands and knees, left stick down also stands you up.
- **Hands on the mat** post and frame by themselves (behind you when sitting, a frame in front on your back, under the shoulders when you push up). Hold LB / RB to move that hand with the right stick instead.
- If a shove or a pull knocks you off balance you go loose and fall; a big shove (G) always puts you down, a small one (F) you catch with a step.

### Mouse and keyboard (fallback)
Click the game window to take the mouse (Esc gives it back).

| Input | Action |
| --- | --- |
| WASD | Walk (camera relative). On the mat: the hips and legs, like the left stick (W legs up, S bridge, A / D hip swing). |
| Arrow keys | On the mat: the chest, like the right stick (up sit up / scoot, down lie back, left / right shrimp). |
| Hold left / right mouse button + move the mouse | Move the left / right arm the way the mouse moves on screen (both buttons: both arms). A held button also closes that hand. On the mat the hands post by themselves unless a button is held. |
| Hold a button + wheel | Reach out / pull in that arm |
| Mouse with no button held | Orbit the camera. Wheel zooms. |
| Hold C | Lower your stance; all the way down sits you on the mat. |
| Q / E | Turn the shoulders |
| Ctrl (hold) | Tense up |

Dev keys: F small shove, G big shove, R reset, M reach drill (touch the three balls in order), J / L orbit the camera.

The overlay draws the center of mass (white cross), mat contacts (yellow), the
base polygon (green when balanced, red when the center of mass has left it), each
arm's IK target skeleton and the weight shift arrow (pink).

## FighterIntent (the contract)
`Fighter` never reads `Input`. Each tick something writes `fighter.intent`
(`scripts/fighter_intent.gd`) and the fighter turns it into joint targets.
`PlayerInput` does it from mouse and keyboard; the AI writes the same object.
Positions are world space; arrays are `[left, right]`.

| Field | Type | Meaning | Read by fighter since |
| --- | --- | --- | --- |
| `focus` | `Focus.HANDS / HIPS / LEGS` | Which body group the controller is working with | recorded only |
| `lead` | `0` left / `1` right | Lead hand (and later leg) | recorded only |
| `hand_target` | `Vector3[2]` | Where each hand should go | M2 |
| `hand_active` | `bool[2]` | Hand chases its target; false relaxes the arm to hanging | M2 |
| `hand_effort` | `Vector3[2]`, length 0..1 | Muscle push on each hand (x `hand_muscle_force` N); the equal and opposite force goes on the shoulder | M2 |
| `arm_tone` | `float[2]`, 0..1 | How firmly each arm holds its pose; scales the arm joint motors | M2 |
| `grip` | `bool[2]` | Hand closed | M4 (grips) |
| `weight_shift` | `Vector2`, -1..1 | Shift the hips over the feet in the heading frame (x right, y forward), up to `weight_shift_deg`; stepping comes in M3 | M2 |
| `turn` | float, -1..1 | Shoulder turn, left to right (25 deg at the abdomen and chest each) | M1 |
| `torso_lean` | float, -1..1 | Lean back .. forward (`lean_deg` at the abdomen, 70% at the chest) | M2 |
| `foot_effort` | `Vector3[2]`, length 0..1 | Muscle push on each foot (x `foot_muscle_force` N), reaction on the hip | M2 |
| `leg_tone` | `float[2]`, 0..1 | How firmly each leg holds its pose | M2 |
| `leg_clamp` | `bool[2]` | Bend that knee hard (hooks, closed guard) | M2 |
| `tension` | float, 0..1 | Relaxed to fully tense; strength x1.0 to x`max_tension` | M1 |
| `move` | `Vector2`, world (x, z), length 0..1 | Walk; the fighter steps by itself (`FighterMoves.walk_speed` at 1) | moves |
| `face_dir` | `Vector2`, world (x, z) | Direction to face; zero keeps the current heading | moves |
| `crouch` | float, 0..1 | Level change; held at 1 it sits the fighter down | moves |
| `hips` | `Vector2`, -1..1 | On the mat: y up legs up, y down bridge (diagonal: over that shoulder), x hip swing. Sitting / on hands and knees, y down stands up | moves |
| `upper` | `Vector2`, -1..1 | On the mat: y up sit up (sitting: butt scoot; face down: push up), y down lie back, x shrimp (face down: roll) | moves |
| `full_body` | bool | Hips and legs follow the hands (default on) | moves |
| `hip_target`, `hip_active`, `foot_target`, `foot_active` | | Reserved for ground mode | M5 |

With `auto_move` on (the default) the legs and torso are driven by `FighterMoves`
(`fighter.moves`): `weight_shift` shifts the hips over the planted feet, `turn` and
`torso_lean` add to the full-body lean and turn, and a leg with `foot_effort` is
let go by the stepping so it can kick or sweep. `leg_clamp` / `leg_stand` are only
read with `auto_move` off.

`fighter.moves` exposes `state` (`STAND`, `DOWN`, `RISING`, `SITTING_DOWN`),
`ground` (`SUPINE`, `SIDE`, `PRONE`, `SITTING`, `ALL_FOURS`), `move_name` (what it
is doing on the mat), `standing()` and `on_ground()`; `Fighter.on_ground()` and the
`got_up` signal too.

Values other systems can read on `Fighter`: `tension`, `stamina`, `com`, `base_margin`,
`base_hull`, `assist`, `has_fallen` (signal `fell`), `arm_ik` (per-arm shoulder, elbow,
target, reachable point), and `heading_basis()` (yaw-only frame, -Z = facing).

## Movement milestones (workstream 1)
- [x] 1. FighterIntent and PlayerInput; test keys moved to `DevKeys`
- [x] 2. Hand IK on a hidden target skeleton, reach drill
- [x] 3. Weight shift and stepping (FighterMoves: balance, catch steps, walking, facing, full-body moves)
- [x] 4. Gi grips on a dummy (GripSystem, AI workstream)
- [x] 5. Ground mode (bridge, shrimp, sit up, butt scoot, legs up, hip swing, push up, roll, stand up)
- [ ] 6. Two fighters and the core test
- [ ] 7. Stamina economy

Known limits: Jolt's joint motors misbehave when a joint is driven ~90 degrees or more
from the pose it was created in (arms flailed overhead, bent elbows buzzed). So the arms
are built half-raised with the elbow half-bent (`arm_build_pose`, `elbow_build_flex`) and
their limits shifted to match; a fighter spawns with its arms up and drops them in the
first fraction of a second. Reaches across a 75-point grid in front of the body land
within 3.5 cm on average (13 cm worst). The arm IK follows a smoothed copy of the chest
(`ik_chest_rate`) to stop a feedback buzz.

How the automatic layer works (`scripts/fighter_moves.gd`): standing, a capped
vertical force holds the pelvis at stand / crouch height while a foot is down, a
capped horizontal force walks the body or keeps the centre of mass over the feet,
and a yaw torque turns it to `face_dir`. The legs run two-bone IK to planted ankle
anchors; a foot steps (lifted arc, `step_time` 0.3 s) when its anchor falls behind
where it should be, when the facing turns, or at once when the centre of mass
leaves the base. Moving faster than `lose_speed` or leaning past `lose_offset`
drops the fighter (assists off). On the mat each move is a blend of leg and spine
poses plus capped assists that only push while the right parts touch the mat
(the bridge needs planted feet, the shrimp a pelvis on the mat, the push up hands
or knees down), so moves can be blocked or fail. Tuning lives at the top of
`FighterMoves` (`walk_speed`, `balance_force`, `stance_half`, `lose_speed`,
`shrimp_force`, ...).

## Files
- `scripts/fighter.gd`: builds the 15-part ragdoll, joint limits, joint motors, base, upright assist, and turns the intent into joint targets (arm IK).
- `scripts/fighter_intent.gd`: the intent contract.
- `scripts/fighter_moves.gd`: the automatic layer: balance, stepping, walking, facing, full-body moves, ground moves, stand-up.
- `scripts/pad_input.gd`: controller to intent (fundamental-move mapping).
- `scripts/player_input.gd`: mouse and keyboard to intent.
- `scripts/dev_keys.gd`: shove, reset and the reach drill.
- `scripts/main.gd`: arena and HUD.
- `scripts/camera_rig.gd`: smoothed orbit camera (mouse with no button held, wheel zoom).
- `scripts/debug_overlay.gd`: balance and intent overlay.
- `tests/test_stand.gd`, `tests/test_controls.gd`, `tests/test_moves.gd` (29 checks of balance, walking, full-body and ground moves, plus the AI walking in and getting up): headless checks. Run `godot --headless --path . --script res://tests/<name>.gd` (test_moves takes one test name after `--` to run just that one).
- `tests/screenshot_moves.gd`: screenshots of the moves (needs a window).
- `tests/screenshot.gd`, `tests/screenshot_reach.gd`: save screenshots (need a window, not `--headless`).

## Tuning knobs (Fighter inspector or top of fighter.gd)
- `pose_gain`: how fast joints chase their target.
- `elbow_pole`: where elbows point while reaching. `turn_deg`: how far Q/E twists. `max_tension`: Ctrl strength.
- `PlayerInput`: `mouse_sensitivity`, `offset_min` / `offset_max` (box the hands stay in), `anchor_rate`.
- `CameraRig`: `sensitivity`, `distance`, `follow_rate`, `turn_rate`.
- Controller feel (PadInput): `hand_speed`, `hand_lead`, `arm_tone`, `arm_push`, `face_range`, `crouch_down_speed`; Fighter: `hand_muscle_force`, `foot_muscle_force`; FighterMoves: `walk_speed`, `step_time`, `balance_force`, `lose_speed`, `shrimp_force`.
- First person (CameraRig): `fp_look_down`, `fp_follow_rate`. The scene thread's `FighterSkin` puts heads on their own render layer, so a first-person camera can hide just the player's head with `cam.cull_mask &= ~skin.head_layer_mask()`.
- `upright_*`: the standing assist. Lower it for a wobblier, goofier fighter.
- `assist_give_up_margin`: how far the center of mass can leave the base before the fighter is allowed to fall.
- Per-joint `strength` and `lim` in the BODY / LIMB tables.

## Workflow
The build is split into four workstreams, one Claude thread each, described in the
[build roadmap](https://claude.ai/artifact/FtVGoowuGNJBfffd9bnZuo). Each works on its own branch
(`ws1-movement`, `ws2-rules`, `ws3-ai`, `ws4-scene`) and merges into `main` through a pull request
per milestone. Movement owns `scripts/fighter.gd` and the intent contract; the other streams add
their own scripts. Record new intent fields, exposed values and signals in this README.

## Scene, fighter look and sound (workstream 4)
The main game (F5) runs in the gym with the gi skin on the fighter. `scenes/match.tscn` (F6) shows two skinned fighters with the mat-edge reset.

Keys anywhere the gym is loaded: **N** cycles the gym (Academy, Garage gym, Competition hall; the choice is saved in `user://settings.cfg`). In the match scene: F / G shove fighter A, R reset (with a whistle), K skin or plain ragdoll, J / L orbit, **1 / 2** change fighter A / B's look.

- `scenes/gym.tscn` + `scripts/gym.gd` (`Gym`, extends `Arena`): three rooms built in code around the competition square. Academy: padded walls, belt rack, posters, trophy shelf, cubbies with bags, ceiling fans, a real-time clock and a round timer. Garage gym: red and black puzzle mats on concrete, block walls, roll-up door, rafters, swinging bulbs, workbench and pegboard, heavy bag, couch, fridge, box fan. Competition hall: the mat under spotlights, bleachers with a crowd that bounces and cheers when a fighter falls or leaves the mat, scoreboards, sponsor boards and banners. Each room has its own room tone. Only the floor and walls collide. The `Mat` body always collides over the middle 12 x 12 m (the size the movement tests are tuned on; a bigger Jolt box changed the ground contacts enough to fail a leg test), and `MatBorder` strips carry the rest. Signal `variant_changed(name)`, `next_variant()`, `react(strength)`.
- `scripts/fighter_skin.gd` (`FighterSkin`): a lofted body in a gi with a cotton weave, thick collar, lapels, skirt, knee patches, cuffs, patches and a belt with a rank bar; hands whose fingers curl while `intent.grip` is on; feet with toes; a face that blinks, squints and grits its teeth with `intent.tension`, and gapes when the head moves fast; googly eyes. Five looks in `FighterSkin.LOOKS` (`apply_look(name)` before `attach`), each with its own hair, beard, build and voice pitch. It adds no bodies, shapes or joints and never writes to the fighter; it only hides the ragdoll's own debug meshes. Each skin puts its head on its own render layer (`head_layer`, 1-20, set before `attach`), so a first-person camera hides only its own head with `cam.cull_mask &= ~skin.head_layer_mask()`.
- `scripts/fighter_audio.gd` (`FighterAudio`, added by the skin): reads the ragdoll's motion, so nothing has to report contacts. Parts that stop falling at the mat slap (limbs), thud (torso, head) or pat (feet); the gi rustles with limb speed; the fighter exhales or grunts when it tenses, says "oof" on a hard landing, and yelps on `fell`.
- `audio/`: 32 sounds, all synthesized by `tools/gen_sounds.py` (no outside assets). Re-run it after tweaking: `python3 tools/gen_sounds.py` (needs numpy).
- `main.gd` loads the gym instead of building its own mat, adds a `FighterSkin` (head layer 19), and hides the fighter's own head while `cam.first_person` is on.
- Tests: `tests/test_scene.gd` (facing, no extra physics, skin follows parts, falling makes sounds, every gym builds, edge reset). Screenshots: `tests/screenshot_match.gd`, `tests/screenshot_gym.gd`, `tests/screenshot_looks.gd` (need a window).

Scene milestones: [x] 1. match scene · [ ] 2. camera (with movement) · [ ] 3. HUD · [x] 4. fighter look · [ ] 5. match flow and menus · [x] sound effects and room tone

## Training partner and AI (workstream 3)
The main game (F5) puts a training partner in a blue gi in front of you.

| Input | Action |
| --- | --- |
| Y (controller) / P (keyboard) | Switch the partner between the dummy and the sparring AI |
| LT / RT (or the held mouse buttons) | Close a hand. A closed hand that touches the partner grabs whatever it touches (sleeve, lapel, wrist, belt) |

- **Dummy**: a semi-stiff ragdoll. Hands up in a loose guard, arms at 45% tone, half the normal standing assist, never grips back. Grab it and pull, push or drag it down. If it stays down 4 s it pops back up where it started (the sparring AI gets 10 s to get up by itself).
- **Spar**: an AI that writes the same `FighterIntent` you do (it never touches bodies, `Input` or forces; a test checks). It squares up, hand-fights for a sleeve and a lapel, strips your grips, then pulls, pushes, snaps you down, turns you and tries foot sweeps, backing off when its own balance goes. The HUD's bottom line shows what it is doing. It faces you, walks in to grip range when it holds nothing, backs off when crowded, and when it ends up on the mat it sits up and stands back up with the same moves you use.
- **Grips** (`scripts/grip_system.gd`, `GripSystem`): while `intent.grip[i]` is held and that hand touches another fighter, the hand grabs the spot it touches. A stiff spring (a bit of gi slack, `stiffness`, capped at `max_force` x stamina) pulls hand and spot together, equal and opposite. If the spot is pulled more than `break_stretch` (17 cm) from the hand the grip tears, and the trigger has to be let go and pressed again. A yellow ball marks each held grip. Read it with `holding(fighter, hand)`, `grips_on(fighter)` and the `grabbed` / `released(fighter, hand, torn)` signals.
- `scripts/partner_ai.gd` (`PartnerAI`): the AI. Feel knobs: `reaction`, `hand_speed`, `arm_tone`, `aggression`, `grip_fighting`, `engage_range`, `dummy_arm_tone`.
- `scripts/training_partner.gd` (`TrainingPartner`): spawns the partner 0.85 m in front of you, owns the mode switch, the get-back-up and the bottom HUD line. `remove()` takes it off the mat (the solo movement tests do this). `dummy_balance` sets how easily the dummy goes over.
- `main.gd` adds a `GripSystem` and a `TrainingPartner` and respawns the partner whenever you respawn (R / Back).
- `tests/test_partner.gd`: headless checks (grabbing, pulling, releasing, tearing, the get-back-up, the AI gets grips and moves you without falling over every round). `tests/screenshot_partner.gd` saves screenshots (needs a window).

AI milestones: [x] 1. dummy partner and grips · [x] 2. standing sparring AI · [x] 3. footwork (walks in, faces you, gets up) · [ ] 4. ground game and goals (after rules)
