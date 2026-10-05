extends Node
class_name InputSource

var jump_edge_latched := false
var tackle_edge_latched := false
var stop_ball_edge_latched := false
var shoot_edge_latched := false
var latch_edge_latched := false
var assist_pass_edge_latched := false
var ability_toggle_edge_latched := false
var ability_a1_edge_latched := false
var ability_a3_edge_latched := false

var _is_mobile = OS.has_feature("mobile")
var _tackle_cd_local := 0.0
var _pass_cd_local := 0.0

var _mouse_delta := Vector2.ZERO

func _input(event):
	if event is InputEventMouseMotion:
		if not GameState.is_paused:
			_mouse_delta += event.relative

func get_mouse_delta() -> Vector2:
	var m_delta = _mouse_delta
	end_frame()
	return m_delta

func get_inputs() -> Dictionary:
	var result := {
		"jump_pressed": jump_edge_latched,
		"tackle_pressed": tackle_edge_latched,
		"stop_ball": stop_ball_edge_latched,
		"shoot_up": shoot_edge_latched,
		"latch_toggle": latch_edge_latched,
		"assist_pass_pressed": assist_pass_edge_latched,
		"ability_toggle": ability_toggle_edge_latched,
		"ability_action1": ability_a1_edge_latched,
		"ability_action3": ability_a3_edge_latched,
	}
	_reset_inputs()
	return result

func end_frame():
	_mouse_delta = Vector2.ZERO

func _physics_process(delta: float) -> void:
	_update_inputs()

func _update_inputs() -> void:
	var gm := false
	if Input.is_action_just_pressed("jump") and not jump_edge_latched:
		jump_edge_latched = true
	if Input.is_action_just_pressed("tackle") and not tackle_edge_latched:
		if _tackle_cd_local <= 0.0:
			tackle_edge_latched = true
	if Input.is_action_just_pressed("stop_ball") and not stop_ball_edge_latched:
		stop_ball_edge_latched = true		
	# Only allow shoot edge when NOT grappling
	if !gm and Input.is_action_just_released(_shoot_action()) and not shoot_edge_latched:
		shoot_edge_latched = true
	# ⬇️ NEW: toggle input (press once = "edge" event)
	if Input.is_action_just_pressed("ball_latch") and not latch_edge_latched:
		 
		latch_edge_latched = true
	if Input.is_action_just_pressed("assist_pass") and not assist_pass_edge_latched:
		
		if _pass_cd_local <= 0.0:
			print("CAPPPPPPPPPPP!!!!!!+")
			assist_pass_edge_latched = true

		# --- Ability inputs (edge-latched like everything else) ---
	if Input.is_action_just_pressed("ability_toggle") and not ability_toggle_edge_latched:
		ability_toggle_edge_latched = true

	if Input.is_action_just_pressed("ability_action1") and not ability_a1_edge_latched:
		ability_a1_edge_latched = true	
		print("WORLD: ability_action1 pressed")

	if Input.is_action_just_pressed("ability_action3") and not ability_a3_edge_latched:
		ability_a3_edge_latched = true

func _shoot_action() -> String:
	return "shoot_touch" if _is_mobile else "shoot"

func _reset_inputs() -> void:
	jump_edge_latched = false
	tackle_edge_latched = false
	stop_ball_edge_latched = false
	shoot_edge_latched = false
	latch_edge_latched = false     # ⬅️ NEW
	assist_pass_edge_latched = false
	ability_toggle_edge_latched = false
	ability_a1_edge_latched = false
	ability_a3_edge_latched = false
