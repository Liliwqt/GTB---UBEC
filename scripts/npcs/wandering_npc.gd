extends CharacterBody3D

@export_category("Wandering")
@export var walk_speed := 1.4
@export var acceleration := 6.0
@export var turn_speed := 6.0
@export_range(0.5, 20.0, 0.5) var wander_radius := 3.0
@export_range(0.1, 2.0, 0.05) var arrival_distance := 0.35
@export_range(0.0, 10.0, 0.1) var minimum_idle_time := 1.0
@export_range(0.0, 10.0, 0.1) var maximum_idle_time := 3.5

@export_category("Animation")
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"
@export var animation_blend_time := 0.2
@export var walk_animation_reference_speed := 2.3

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)
var home_position := Vector3.ZERO
var target_position := Vector3.ZERO
var idle_time_left := 0.0
var is_wandering := false
var current_animation: StringName
var random := RandomNumberGenerator.new()

@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	random.randomize()
	home_position = global_position
	if NetworkManager.is_dedicated_server():
		_configure_dedicated_server_proxy()
	else:
		_setup_animations()
	if multiplayer.is_server():
		_enter_idle(random.randf_range(0.2, maximum_idle_time))


func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		# On clients, drive local animation based on movement velocity from sync.
		var horizontal_velocity := Vector2(velocity.x, velocity.z)
		if horizontal_velocity.length_squared() > 0.01:
			_play_animation(walk_animation)
		else:
			_play_animation(idle_animation)


func _physics_process(delta: float) -> void:
	# Server only runs NPC AI and movement decisions.
	if not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	if is_wandering:
		_update_wandering(delta)
	else:
		_update_idle(delta)

	move_and_slide()

	if is_wandering and is_on_wall():
		_enter_idle(0.4)


func _update_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	idle_time_left -= delta
	if idle_time_left <= 0.0:
		_choose_wander_target()


func _update_wandering(delta: float) -> void:
	var offset := target_position - global_position
	offset.y = 0.0
	if offset.length() <= arrival_distance:
		_enter_idle(_random_idle_duration())
		return

	var direction := offset.normalized()
	if not _has_ground_ahead(direction):
		_enter_idle(0.4)
		return

	var target_velocity := direction * walk_speed
	velocity.x = move_toward(
		velocity.x,
		target_velocity.x,
		acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		target_velocity.z,
		acceleration * delta
	)
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(
		rotation.y,
		target_yaw,
		1.0 - exp(-turn_speed * delta)
	)


func _choose_wander_target() -> void:
	var angle := random.randf_range(0.0, TAU)
	var distance := random.randf_range(
		wander_radius * 0.35,
		wander_radius
	)
	target_position = home_position + Vector3(
		cos(angle) * distance,
		0.0,
		sin(angle) * distance
	)
	is_wandering = true
	_play_animation(walk_animation)


func _enter_idle(duration: float) -> void:
	is_wandering = false
	idle_time_left = maxf(duration, 0.0)
	_play_animation(idle_animation)


func _random_idle_duration() -> float:
	return random.randf_range(
		minimum_idle_time,
		maxf(minimum_idle_time, maximum_idle_time)
	)


func _has_ground_ahead(direction: Vector3) -> bool:
	var probe_start := (
		global_position
			+ direction * 0.65
			+ Vector3.UP * 0.5
	)
	var query := PhysicsRayQueryParameters3D.create(
		probe_start,
		probe_start + Vector3.DOWN * 2.0,
		collision_mask
	)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(
		query
	).is_empty()


func _setup_animations() -> void:
	if animation_player.has_animation(idle_animation):
		animation_player.get_animation(
			idle_animation
		).loop_mode = Animation.LOOP_LINEAR
	if animation_player.has_animation(walk_animation):
		animation_player.get_animation(
			walk_animation
		).loop_mode = Animation.LOOP_LINEAR


func _play_animation(animation_name: StringName) -> void:
	if (
		animation_player == null
			or not is_instance_valid(animation_player)
			or not animation_player.has_animation(animation_name)
			or current_animation == animation_name
	):
		return
	current_animation = animation_name
	animation_player.speed_scale = (
		clampf(
			walk_speed / maxf(walk_animation_reference_speed, 0.01),
			0.65,
			1.15
		)
			if animation_name == walk_animation
			else 1.0
	)
	animation_player.play(animation_name, animation_blend_time)


func _configure_dedicated_server_proxy() -> void:
	# AI, collision, and synchronized transforms stay active on the server;
	# imported meshes and animation playback are client presentation only.
	var model_root := get_node_or_null("ModelRoot")
	if model_root != null:
		model_root.queue_free()
	if animation_player != null:
		animation_player.queue_free()
	animation_player = null
