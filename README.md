# Grapple Prototype

Godot 4.4+ with Jolt physics at 120 ticks per second.

## Open it
1. Godot Project Manager > Import > pick this folder's `project.godot`.
2. Press F5 (Run Project).

## Controls
Whichever device you touched last drives the fighter.

### Controller (Xbox 360 layout, the main scheme)
The arms are muscle-driven: a stick pushes its hand with a force (pulling back on the
shoulder), and the arm is otherwise loose, so it swings, sags and stays roughly where
you leave it.

| Input | Action |
| --- | --- |
| Left / right stick | Push the left / right hand: sideways (relative to the camera) and up / down |
| Hold LB / RB | That stick pushes forward / pulls back instead of up / down |
| LT / RT | Close the left / right hand |
| A (hold) | Tense up |
| X / B | Turn the shoulders left / right |
| D-pad left / right | Swing the camera around the fighter. Up / down: zoom |
| Back | Reset |

The camera follows on its own and eases round behind the fighter as they turn.
Legs, hips and stepping are not on the controller yet; WASD still shifts weight.

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
| `weight_shift` | `Vector2`, -1..1 | Lean/step direction in the heading frame: x right, y forward | M3 |
| `turn` | float, -1..1 | Shoulder turn, left to right (25 deg at the abdomen and chest each) | M1 |
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
- Muscle arms: `hand_muscle_force` (Fighter), `arm_tone` and `settle_rate` (PadInput).
- `upright_*`: the standing assist. Lower it for a wobblier, goofier fighter.
- `assist_give_up_margin`: how far the center of mass can leave the base before the fighter is allowed to fall.
- Per-joint `strength` and `lim` in the BODY / LIMB tables.

## Workflow
The build is split into four workstreams, one Claude thread each, described in the
[build roadmap](https://claude.ai/artifact/FtVGoowuGNJBfffd9bnZuo). Each works on its own branch
(`ws1-movement`, `ws2-rules`, `ws3-ai`, `ws4-scene`) and merges into `main` through a pull request
per milestone. Movement owns `scripts/fighter.gd` and the intent contract; the other streams add
their own scripts. Record new intent fields, exposed values and signals in this README.
