extends Control

@export var radius: float = 110.0      # thumb travel in pixels inside this control
@export var deadzone: float = 0.12     # 0..1 (fraction of radius)

# Public API
var vector: Vector2 = Vector2.ZERO     # normalized direction (-1..1 in x,y, y+ = up)
var mag: float = 0.0                   # 0..1 magnitude (how far the stick is pushed)
var is_active: bool = false

var _touch_id: int = -1

@onready var _knob: Control = ($Knob as Control) if has_node("Knob") else null
@onready var _base: Control = ($Base as Control) if has_node("Base") else null

signal vector_changed(vec: Vector2, mag: float)
signal pressed()
signal released()

func _ready() -> void:
	# Center visuals
	if _knob:
		_knob.pivot_offset = _knob.size * 0.5
		_knob.position = size * 0.5
	if _base:
		_base.position = Vector2.ZERO
		_base.size = size

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if _touch_id == -1:
				_claim_pointer(-1, mb.position)
		else:
			if _touch_id == -1:
				_release_pointer()
		return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _touch_id == -1 and is_active:
			_update_vector(mm.position)
		return

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _touch_id == -1:
				_claim_pointer(st.index, st.position)
		else:
			if st.index == _touch_id:
				_release_pointer()
		return

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch_id:
			_update_vector(sd.position)
		return

func _claim_pointer(id: int, local_pos: Vector2) -> void:
	_touch_id = id
	is_active = true
	pressed.emit()
	_update_vector(local_pos)

func _release_pointer() -> void:
	_touch_id = -1
	is_active = false
	vector = Vector2.ZERO
	mag = 0.0
	_move_knob(Vector2.ZERO)
	vector_changed.emit(vector, mag)
	released.emit()

func _update_vector(local_pos: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var delta_local: Vector2 = local_pos - center

	# Flip Y so up is +Y
	var v: Vector2 = Vector2(delta_local.x, -delta_local.y)

	# Clamp to radius
	if v.length() > radius:
		v = v.normalized() * radius

	# Compute magnitude 0..1
	mag = v.length() / radius

	# Normalized output direction (-1..1 range)
	var out: Vector2 = (v / radius)

	# Deadzone
	if mag < deadzone:
		out = Vector2.ZERO
		mag = 0.0

	if out != vector or not is_equal_approx(mag, mag):
		vector = out
		vector_changed.emit(vector, mag)

	_move_knob(v)

func _move_knob(delta_local: Vector2) -> void:
	if _knob:
		_knob.position = (size * 0.5) + Vector2(delta_local.x, -delta_local.y)
