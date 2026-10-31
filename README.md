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

When the balance assist gives up, the joints fade to `floppy_strength` (12%) so the fighter flops instead of falling like a plank.

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
