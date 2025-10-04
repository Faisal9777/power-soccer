extends Control

@export var radius: float = 110.0      # thumb travel in pixels inside this control
@export var deadzone: float = 0.12     # 0..1 (fraction of radius)

# Public API
var vector: Vector2 = Vector2.ZERO     # -1..1 (x,y), with y+=up (game-style)
var dir: Vector2 = Vector2.ZERO        # unit direction (or ZERO if mag==0)
var mag: float = 0.0                   # 0..1 how far the stick is pushed
var is_active: bool = false

var _touch_id: int = -1
var _prev_mag: float = 0.0             # for change detection

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
	# Mouse (optional for desktop)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if _touch_id == -1:
				_claim_pointer(-1, mb.position)      # LOCAL pos
		else:
			if _touch_id == -1:
				_release_pointer()
		return

	if event is InputEventMouseMotion:
		if _touch_id == -1 and is_active:
			_update_vector((event as InputEventMouseMotion).position)  # LOCAL pos
		return

	# Touch (mobile)
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _touch_id == -1:
				_claim_pointer(st.index, st.position)  # LOCAL pos
		else:
			if st.index == _touch_id:
				_release_pointer()
		return

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch_id:
			_update_vector(sd.position)                # LOCAL pos
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
	_prev_mag = mag
	mag = 0.0
	_move_knob(Vector2.ZERO)
	vector_changed.emit(vector, mag)
	released.emit()

func _update_vector(local_pos: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var delta_local: Vector2 = local_pos - center

	# Build a game-style vector where +Y is up (UI Y+ is down, so flip here)
	var v: Vector2 = Vector2(delta_local.x, -delta_local.y)

	# Clamp to radius in UI units, then convert to normalized stick output
	if v.length() > radius:
		v = v.normalized() * radius

	var new_mag := v.length() / radius
	var out: Vector2 = (v / radius)  # now in -1..1

	# Deadzone
	if new_mag < deadzone:
		out = Vector2.ZERO
		new_mag = 0.0

	# Update public API
	var magnitude_changed := not is_equal_approx(new_mag, _prev_mag)
	if out != vector or magnitude_changed:
		vector = out
		_prev_mag = mag
		mag = new_mag
		dir = (vector.normalized() if mag > 0.0 else Vector2.ZERO)
		vector_changed.emit(vector, mag)

	# Move knob (convert back to UI coords: UI Y+ is down → negate game Y)
	_move_knob(v)

func _move_knob(v_game_up: Vector2) -> void:
	if _knob:
		# v_game_up uses +Y = up; UI uses +Y = down → flip Y to place
		_knob.position = (size * 0.5) + Vector2(v_game_up.x, -v_game_up.y)
