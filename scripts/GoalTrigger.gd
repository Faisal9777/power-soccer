# GoalTrigger.gd (attach to Goal_A and Goal_B)
extends Node3D

enum Team { BLUE, PURPLE }

@export var score_for: Team = Team.PURPLE        # Goal_A -> Purple; Goal_B -> Blue
@export var score_zone_path: NodePath = NodePath("ScoreZone")
@export var cooldown_sec: float = 1.0            # ignore re-triggers for a moment
@export var require_forward_entry: bool = true   # only count if ball comes from field side
@export var ball_path: NodePath
@export var ball_reset_pos: Vector3
@export var ball_reset_impulse: Vector3 = Vector3.ZERO
@export var ball_spawn_path: NodePath

@onready var _spawn: Marker3D = get_node(ball_spawn_path)
@onready var _ball: RigidBody3D = get_node_or_null(ball_path)
@onready var _zone: Area3D     = get_node(score_zone_path)

var _locked: bool = false

func _ready() -> void:
	var spawn_pos: Vector3 = _spawn.global_transform.origin  # or: _spawn.global_position
	print("Spawn at: ", spawn_pos)
	_zone.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _locked: return
	if !(body is RigidBody3D): return
	if !body.is_in_group("ball"): return

	# Optional: only count if ball is moving "into" the goal from the pitch side
	if require_forward_entry:
		var goal_forward: Vector3 = -global_transform.basis.z  # face from goal towards pitch
		var vel: Vector3 = (body as RigidBody3D).linear_velocity
		if goal_forward.dot(vel) <= 0.0:
			return  # ball is moving out of the goal; ignore
