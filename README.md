# Grapple Prototype (milestone 2: a ragdoll that stands)

Godot 4.4+ with Jolt physics at 120 ticks per second.

## Open it
1. Godot Project Manager > Import > pick this folder's `project.godot`.
2. Press F5 (Run Project).

## Controls
| Key | Action |
| --- | --- |
| F | Small shove (away from the camera). The fighter recovers. |
| G | Big shove. The fighter falls. |
| R | Reset |
| Ctrl (hold) | Tense up: joint motors get 1.8x stronger |
| J / L | Orbit the camera |

The overlay draws the center of mass (white cross), mat contacts (yellow) and the
base polygon (green when balanced, red when the center of mass has left it).

## Files
- `scripts/fighter.gd`: builds the 15-part ragdoll, joint limits, joint motors, base and the upright assist.
- `scripts/main.gd`: arena, camera, HUD and test keys.
- `scripts/debug_overlay.gd`: balance overlay.
- `tests/test_stand.gd`: headless checks. Run `godot --headless --path . --script res://tests/test_stand.gd`.
- `tests/screenshot.gd`: saves standing / falling / down screenshots.

## Tuning knobs (Fighter inspector or top of fighter.gd)
- `pose_gain`: how fast joints chase their target.
- `upright_*`: the standing assist. Lower it for a wobblier, goofier fighter.
- `assist_give_up_margin`: how far the center of mass can leave the base before the fighter is allowed to fall.
- Per-joint `strength` and `lim` in the BODY / LIMB tables.

## Workflow
The build is split into four workstreams, one Claude thread each, described in the
[build roadmap](https://claude.ai/artifact/FtVGoowuGNJBfffd9bnZuo). Each works on its own branch
(`ws1-movement`, `ws2-rules`, `ws3-ai`, `ws4-scene`) and merges into `main` through a pull request
per milestone. Movement owns `scripts/fighter.gd` and the intent contract; the other streams add
their own scripts. Record new intent fields, exposed values and signals in this README.

## Scene and fighter look (workstream 4)
Open `scenes/match.tscn` and press F6 (Run Current Scene). `main.tscn` is unchanged.

- `scenes/arena.tscn` + `scripts/arena.gd` (`Arena`): an 8 x 8 m blue combat area inside a 2 m yellow safety border (`materials/mat.gdshader`), tile seams, start marks, lights, a floor, and `SpawnA` / `SpawnB` facing each other. `watch(fighter)` makes it emit `fighter_left_mat(fighter)` when the pelvis crosses the combat edge; `is_on_mat(point)` and `spawn_transform(i)` are there for the rules thread.
- `scripts/fighter_skin.gd` (`FighterSkin`): a gi jacket, pants, belt, bare hands and feet, and a face with googly eyes, each piece following one ragdoll part. It adds no bodies, shapes or joints and never writes to the fighter; it only hides the ragdoll's own debug meshes. Colors are exports (`gi_color`, `belt_color`, `skin_tone`, `hair_color`). The head pieces sit on render layer 20 (`FighterSkin.HEAD_LAYER`), so a first-person camera can hide its own head with `cam.cull_mask &= ~FighterSkin.HEAD_LAYER`.
- `scripts/match.gd`: spawns two skinned fighters and resets both to their spawns when one leaves the combat area. Dev keys: F / G shove fighter A, R reset, K skin or plain ragdoll, J / L orbit. Its J / L camera is a debug viewer only; the main (first-person) camera comes from movement.
- `tests/test_scene.gd`: headless checks (facing, no extra physics, skin follows parts, edge reset). `tests/screenshot_match.gd` saves screenshots (needs a window).

Scene milestones: [x] 1. match scene · [ ] 2. camera (with movement) · [ ] 3. HUD · [x] 4. fighter look (first pass) · [ ] 5. match flow, menus, sound
