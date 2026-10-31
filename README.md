# Grapple Prototype

Godot 4.4+ with Jolt physics at 120 ticks per second.

## Open it
1. Godot Project Manager > Import > pick this folder's `project.godot`.
2. Press F5 (Run Project).

## Controls
Whichever device you touched last drives the fighter.

### Controller (Xbox 360 layout, the main scheme)
Both thumbs stay on the sticks; the bumpers (index fingers) pick what the sticks move.

| Input | Action |
| --- | --- |
| Left / right stick | Move the left / right hand relative to your chest: sideways, and up = push forward, down = pull back. Hands sit at chest height; lean to reach lower. The hand stays where you leave it. |
| Hold RB (body) | Left stick shifts your weight over your feet. Right stick: up / down leans the torso forward / back, left / right turns the shoulders. They move at a steady speed and stay where you leave them, in every mode. Click either stick to recentre. |
| Hold LB (legs) | Sticks move the left / right foot relative to your hips: up pushes it out the way the knee points, down pulls the heel in (past 60% it clamps the knee), sideways is sideways. Works the same standing or on your back. Each leg stays in the pose you leave it in (a clamped knee stays bent). Click a stick to straighten that leg. |
| Hold RB + LB (body and legs) | Left stick shifts your weight / hips as in body mode. Right stick moves both legs together the way one stick moves a leg in legs mode, so pulling it down clamps both knees (a closed guard squeeze) while the left stick moves your hips. Click the left stick to recentre the hips, the right stick to straighten both legs. Clamping both knees while standing drops you. |
| LT / RT | Close the left / right hand, in every mode, so a grip holds through a throw |
| A (hold) | Tense up |
| D-pad left / right | Third person: swing the camera around. Up / down: zoom |
| Start (or V) | First person / third person |
| Back | Reset |

The camera starts in third person, close behind and a little above you so you can see
your whole body; first person (Start or V) sits just in front of the head. Arms run at 70% tone with a light muscle push; legs go loose
(15%) while their stick moves them. Stepping is not in yet, so lifting a foot while
standing usually ends in a fall.

### Mouse and keyboard (fallback)
Click the game window to take the mouse (Esc gives it back). Until then the arms hang.

| Input | Action |
| --- | --- |
| Hold left / right mouse button + move the mouse | Move the left / right arm the way the mouse moves on screen. Hold both to move both arms. A held button also closes that hand (grabbing comes with grips). Each hand stays where you leave it. |
| Hold a button + wheel | Reach out / pull in that arm |
| Mouse with no button held | Orbit the camera. Wheel zooms. |
| Q / E | Turn the shoulders |
| WASD | Weight shift (recorded in the intent; stepping comes in movement milestone 3) |
| Ctrl (hold) | Tense up: joint motors get 1.8x stronger |
| Tab | Swap the lead side |
| Shift / Space (hold) | Hips / legs focus (recorded; used from movement milestone 5) |

Dev keys: F small shove, G big shove, R reset, M reach drill (touch the three balls in order), J / L orbit the camera.

The overlay draws the center of mass (white cross), mat contacts (yellow), the
base polygon (green when balanced, red when the center of mass has left it), each
arm's IK target skeleton (shoulder, elbow, hand target; yellow when the hand is
closed, bigger cross on the lead hand) and the weight shift arrow (pink).

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
| `hip_target`, `hip_active`, `foot_target`, `foot_active` | | Reserved for ground mode | M5 |

Values other systems can read on `Fighter`: `tension`, `stamina`, `com`, `base_margin`,
`base_hull`, `assist`, `has_fallen` (signal `fell`), `arm_ik` (per-arm shoulder, elbow,
target, reachable point), and `heading_basis()` (yaw-only frame, -Z = facing).

## Movement milestones (workstream 1)
- [x] 1. FighterIntent and PlayerInput; test keys moved to `DevKeys`
- [x] 2. Hand IK on a hidden target skeleton, reach drill
- [ ] 3. Weight shift and stepping
- [ ] 4. Gi grips on a dummy
- [ ] 5. Ground mode
- [ ] 6. Two fighters and the core test
- [ ] 7. Stamina economy

Known limits: Jolt's joint motors misbehave when a joint is driven ~90 degrees or more
from the pose it was created in (arms flailed overhead, bent elbows buzzed). So the arms
are built half-raised with the elbow half-bent (`arm_build_pose`, `elbow_build_flex`) and
their limits shifted to match; a fighter spawns with its arms up and drops them in the
first fraction of a second. Reaches across a 75-point grid in front of the body land
within 3.5 cm on average (13 cm worst). The arm IK follows a smoothed copy of the chest
(`ik_chest_rate`) to stop a feedback buzz.

## Files
- `scripts/fighter.gd`: builds the 15-part ragdoll, joint limits, joint motors, base, upright assist, and turns the intent into joint targets (arm IK).
- `scripts/fighter_intent.gd`: the intent contract.
- `scripts/pad_input.gd`: controller to intent (muscle arms).
- `scripts/player_input.gd`: mouse and keyboard to intent.
- `scripts/dev_keys.gd`: shove, reset and the reach drill.
- `scripts/main.gd`: arena and HUD.
- `scripts/camera_rig.gd`: smoothed orbit camera (mouse with no button held, wheel zoom).
- `scripts/debug_overlay.gd`: balance and intent overlay.
- `tests/test_stand.gd`, `tests/test_controls.gd`: headless checks. Run `godot --headless --path . --script res://tests/<name>.gd`.
- `tests/screenshot.gd`, `tests/screenshot_reach.gd`: save screenshots (need a window, not `--headless`).

## Tuning knobs (Fighter inspector or top of fighter.gd)
- `pose_gain`: how fast joints chase their target.
- `elbow_pole`: where elbows point while reaching. `turn_deg`: how far Q/E twists. `max_tension`: Ctrl strength.
- `PlayerInput`: `mouse_sensitivity`, `offset_min` / `offset_max` (box the hands stay in), `anchor_rate`.
- `CameraRig`: `sensitivity`, `distance`, `follow_rate`, `turn_rate`.
- Controller feel (PadInput): `hand_speed`, `hand_lead`, `arm_tone`, `arm_push`, `leg_tone`, `clamp_at`; Fighter: `hand_muscle_force`, `foot_muscle_force`.
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
