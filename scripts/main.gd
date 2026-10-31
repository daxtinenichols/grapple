extends Node3D

## Test arena. Player controls live in PlayerInput, test keys in DevKeys.

var fighter: Fighter
var player: PlayerInput
var pad: PadInput
## True while the controller drives the fighter, false for mouse and keyboard.
var pad_mode := false
var dev: DevKeys
var overlay: DebugOverlay
var hud: Label
var cam: CameraRig
## Gi model over the fighter (scenes workstream); see FighterSkin.
var skin: FighterSkin
## Grips between fighters and the training partner (AI workstream).
var grips: GripSystem
var partner: TrainingPartner


func _ready() -> void:
	_build_world()
	_spawn_fighter()


func _build_world() -> void:
	# The gym (scene workstream): mats, walls, lights. Its Mat body is the floor.
	add_child(load("res://scenes/gym.tscn").instantiate())

	cam = CameraRig.new()
	cam.name = "Camera"
	add_child(cam)

	overlay = DebugOverlay.new()
	add_child(overlay)

	player = PlayerInput.new()
	player.name = "PlayerInput"
	player.camera = cam
	add_child(player)

	pad = PadInput.new()
	pad.name = "PadInput"
	pad.camera = cam
	add_child(pad)
	_set_pad_mode(not Input.get_connected_joypads().is_empty())

	grips = GripSystem.new()
	grips.name = "Grips"
	add_child(grips)
	partner = TrainingPartner.new()
	partner.name = "TrainingPartner"
	partner.grips = grips
	add_child(partner)

	dev = DevKeys.new()
	dev.name = "DevKeys"
	dev.camera = cam
	dev.reset_requested.connect(_spawn_fighter)
	add_child(dev)

	hud = Label.new()
	hud.position = Vector2(16, 12)
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)


func _spawn_fighter() -> void:
	if fighter:
		fighter.queue_free()
	fighter = Fighter.new()
	fighter.name = "Fighter"
	add_child(fighter)
	skin = FighterSkin.new()
	skin.name = "Skin"
	skin.head_layer = 19
	add_child(skin)
	skin.attach(fighter)
	overlay.fighter = fighter
	player.fighter = fighter
	pad.fighter = fighter
	dev.fighter = fighter
	dev.clear_drill()
	cam.target = fighter
	cam.snap()
	grips.clear()
	grips.add_fighter(fighter)
	partner.opponent = fighter
	partner.respawn()


## Whichever device was touched last drives the fighter.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		_set_pad_mode(true)
	elif event is InputEventMouseButton or (event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_set_pad_mode(false)


func _set_pad_mode(on: bool) -> void:
	pad_mode = on
	pad.set_physics_process(on)
	player.set_physics_process(not on)


func _process(_delta: float) -> void:
	# In first person, hide our own head from our own camera.
	if is_instance_valid(skin):
		var head := skin.head_layer_mask()
		cam.cull_mask = (cam.cull_mask & ~head) if cam.first_person else (cam.cull_mask | head)
	# Both inputs turn you to face the training partner when it's near.
	var foe: Fighter = partner.fighter if is_instance_valid(partner) and is_instance_valid(partner.fighter) else null
	pad.opponent = foe
	player.opponent = foe
	if fighter and fighter.parts.has("pelvis"):
		var it := fighter.intent
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var arms := player.controlled()
		var ground := fighter.on_ground()
		var help := ""
		if pad_mode:
			help = ("on the mat: left stick hips and legs (down bridge, up legs up, sideways hip swing)   right stick chest (up sit up / scoot, down lie back, sideways shrimp)\nsit up + left stick down: stand up   hold LB / RB: right stick moves that hand   LT/RT grip" if ground else
				"left stick walk   right stick both hands (push / pull / swing)   hold LB / RB: just that hand   LT/RT grip   hold B: lower stance (all the way: sit)") + \
				"\nA tense   right stick click: hands to guard   D-pad camera   Start first / third person   Back reset"
		else:
			help = "%s\nhold left / right mouse + move: move that arm (both buttons: both arms)   + wheel: reach   no button: camera, wheel zooms\n%s   Q/E turn   Ctrl tense" % [
				"" if captured else ">>> click the window to take the mouse (or pick up the controller) <<<",
				"WASD hips and legs (S bridge, W legs up, A/D hip swing)   arrows chest (up sit up, down lie back, left/right shrimp)   sit up + S: stand" if ground else
				"WASD walk   hold C: lower stance (all the way: sit)"]
		var doing := pad.mode_text if pad_mode else ("moving both arms" if arms[0] and arms[1] else "moving left arm" if arms[0] else "moving right arm" if arms[1] else "moving camera")
		if not pad_mode and ground:
			doing += "   on the mat: " + fighter.moves.move_name
		hud.text = "%s\nF shove   G big shove   R reset   M reach drill   Esc free mouse\n\n%s   grips %s %s   base margin %.2f m   tension %.1f   %s" % [
			help, doing,
			"L" if it.grip[0] else "-", "R" if it.grip[1] else "-",
			fighter.base_margin, fighter.tension, dev.drill_status()]
