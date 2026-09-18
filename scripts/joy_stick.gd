extends Control

@export var radius: float = 110.0
@export var deadzone: float = 0.12
@export var overdrive_distance: float = 20.0

# Public API
var vector: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.ZERO
var mag: float = 0.0
var is_active: bool = false
var is_sprinting: bool = false

var _touch_id: int = -1
var _prev_mag: float = 0.0
var _is_sprinting_previous: bool = false

@onready var _knob: Control = ($Knob as Control) if has_node("Knob") else null
@onready var _base: Control = ($Base as Control) if has_node("Base") else null

signal vector_changed(vec: Vector2, mag: float)
signal pressed()
signal released()

func _ready() -> void:
	if _knob:
		_knob.pivot_offset = _knob.size * 0.5
		_knob.position = size * 0.5 - _knob.size * 0.5
	if _base:
		_base.position = Vector2.ZERO
		_base.size = size

func _gui_input(event: InputEvent) -> void:
	# Mouse (optional for desktop)
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
		if _touch_id == -1 and is_active:
			_update_vector((event as InputEventMouseMotion).position)
		return

	# Touch (mobile)
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
	dir = Vector2.ZERO
	mag = 0.0
	is_sprinting = false
	_prev_mag = 0.0
	_is_sprinting_previous = false
	_move_knob(Vector2.ZERO)
	vector_changed.emit(vector, mag)
	released.emit()

func _update_vector(local_pos: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var delta_local: Vector2 = local_pos - center
	var v_raw := Vector2(delta_local.x, -delta_local.y)
	var raw_length := v_raw.length()
	var sprint_radius := radius + overdrive_distance
	is_sprinting = raw_length >= sprint_radius

	var v := v_raw
	if raw_length > radius:
		v = v_raw.normalized() * radius

	var new_mag := v.length() / radius
	var out := v / radius

	if new_mag < deadzone:
		out = Vector2.ZERO
		new_mag = 0.0
		is_sprinting = false

	var magnitude_changed := not is_equal_approx(new_mag, _prev_mag)
	if out != vector or magnitude_changed or is_sprinting != _is_sprinting_previous:
		vector = out
		_prev_mag = new_mag
		mag = new_mag
		dir = (vector.normalized() if mag > 0.0 else Vector2.ZERO)
		vector_changed.emit(vector, mag)

	_is_sprinting_previous = is_sprinting
	_move_knob(v)

func _move_knob(v_game_up: Vector2) -> void:
	if _knob:
		_knob.position = (size * 0.5) + Vector2(v_game_up.x, -v_game_up.y) - _knob.size * 0.5
