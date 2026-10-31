class_name TrainingPartner
extends Node3D

## Puts a second fighter in front of the player, driven by PartnerAI, and owns
## the grips between them. Y on the controller or P on the keyboard switches
## the partner between the semi-stiff dummy and the sparring AI. A partner that
## stays down for down_reset seconds gets back up at its spot (respawned).
## main.gd adds one of these and calls respawn() whenever the player respawns.

## The player (or whoever the partner faces).
@export var opponent: Fighter
@export var grips: GripSystem
## Spawn this far (m) in front of the opponent's spawn, facing it.
@export var distance := 0.85
@export var mode := PartnerAI.Mode.DUMMY
## Seconds the partner can lie on the mat before it respawns.
@export var down_reset := 4.0
## Render layer for the partner skin's head (the player's is 19).
@export var head_layer := 20
## The dummy's standing assist, as a share of a normal fighter's (1.0). Lower
## is easier to pull over. The sparring AI always stands with the full assist.
@export var dummy_balance := 0.5

var fighter: Fighter
var skin: FighterSkin
var ai: PartnerAI
var _spawn := Transform3D.IDENTITY
var _down_time := 0.0
var _label: Label
## A fresh fighter's standing assist: stiffness, damping, max torque.
var _balance0: Array[float] = []


func _ready() -> void:
	ai = PartnerAI.new()
	ai.name = "PartnerAI"
	ai.mode = mode
	add_child(ai)
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 16
	_label.offset_top = -40
	layer.add_child(_label)
	add_child(layer)


## Spawns (or respawns) the partner facing the opponent, `distance` in front
## of where the opponent stands now.
func respawn() -> void:
	if not is_instance_valid(opponent):
		return
	var base := opponent.global_transform
	var fwd := -base.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	_spawn = Transform3D(Basis.looking_at(-fwd, Vector3.UP), base.origin + fwd * distance)
	_spawn_at(_spawn)


func _spawn_at(t: Transform3D) -> void:
	if is_instance_valid(fighter):
		if grips:
			grips.remove_fighter(fighter)
		fighter.queue_free()
	if is_instance_valid(skin):
		skin.queue_free()
	fighter = Fighter.new()
	fighter.name = "Partner"
	fighter.transform = t
	get_parent().add_child(fighter)
	skin = FighterSkin.new()
	skin.name = "PartnerSkin"
	skin.gi_color = Color(0.16, 0.3, 0.68)
	skin.belt_color = Color(0.42, 0.25, 0.12)
	skin.skin_tone = Color(0.55, 0.37, 0.25)
	skin.hair_color = Color(0.08, 0.06, 0.05)
	skin.head_layer = head_layer
	get_parent().add_child(skin)
	skin.attach(fighter)
	_apply_balance()
	ai.fighter = fighter
	ai.opponent = opponent
	ai.grips = grips
	_down_time = 0.0
	if grips:
		grips.add_fighter(fighter)
		if is_instance_valid(opponent):
			grips.add_fighter(opponent)


## Takes the partner off the mat (solo tests). respawn() brings it back.
func remove() -> void:
	if is_instance_valid(fighter):
		if grips:
			grips.remove_fighter(fighter)
		fighter.queue_free()
	if is_instance_valid(skin):
		skin.queue_free()
	fighter = null
	skin = null
	ai.fighter = null


func set_mode(m: PartnerAI.Mode) -> void:
	mode = m
	ai.set_mode(m)
	_apply_balance()


func _apply_balance() -> void:
	if not is_instance_valid(fighter):
		return
	if _balance0.is_empty():
		_balance0 = [fighter.upright_stiffness, fighter.upright_damping, fighter.upright_max_torque]
	var k := dummy_balance if mode == PartnerAI.Mode.DUMMY else 1.0
	fighter.upright_stiffness = _balance0[0] * k
	fighter.upright_damping = _balance0[1] * k
	fighter.upright_max_torque = _balance0[2] * k


func toggle_mode() -> void:
	set_mode(PartnerAI.Mode.SPAR if mode == PartnerAI.Mode.DUMMY else PartnerAI.Mode.DUMMY)


func _unhandled_input(event: InputEvent) -> void:
	var hit := false
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		hit = true
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		hit = true
	if hit:
		toggle_mode()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(fighter) or not fighter.parts.has("pelvis"):
		return
	if fighter.parts.head.global_position.y < 0.9:
		_down_time += delta
		if _down_time > down_reset:
			# Get back up where it started (no getting-up move yet).
			_spawn_at(_spawn)
	else:
		_down_time = 0.0


func _process(_delta: float) -> void:
	if _label and ai:
		_label.text = "Partner: %s   (Y / P: %s)" % [ai.status(),
			"spar with the AI" if mode == PartnerAI.Mode.DUMMY else "back to the dummy"]
