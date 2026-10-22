extends CharacterBody3D

@export_category("Character")
@export var character_profile: CharacterProfile

@export_category("Movement")
@export var speed := 1.0
@export var run_speed := 5.0
@export var walk_acceleration := 12.0
@export var run_acceleration := 8.0
@export var deceleration := 3.0
@export_range(45.0, 180.0, 1.0) var sharp_turn_angle := 105.0
@export_range(0.1, 1.0, 0.05) var sharp_turn_speed_multiplier := 0.45
@export var turn_speed := 10.0
@export var jump_velocity := 6.0

@export_category("Camera")
@export var mouse_sensitivity := 0.002
@export var touch_look_sensitivity := 0.0025
@export var camera_height := 1.0

@export_category("Locomotion Animation")
@export_range(0.05, 1.0, 0.01) var start_to_walk_time := 0.35
@export_range(0.0, 5.0, 0.05) var run_animation_entry_speed := 2.8
@export_range(0.25, 1.5, 0.05) var locomotion_min_playback_speed := 0.75
@export_range(1.0, 2.0, 0.05) var locomotion_max_playback_speed := 1.25
@export_range(0.0, 0.5, 0.01) var locomotion_blend_time := 0.12
@export_range(0.0, 0.5, 0.01) var idle_start_blend_time := 0.2
@export_range(0.0, 0.5, 0.01) var gait_change_blend_time := 0.25
@export_range(0.0, 0.5, 0.01) var stopping_blend_time := 0.12
@export_range(0.0, 0.5, 0.01) var stop_idle_blend_time := 0.2
@export_range(0.0, 1.0, 0.01) var stop_animation_delay := 0.0
@export_range(0.1, 3.0, 0.05) var stop_animation_playback_speed := 1.0
@export_range(0.1, 2.0, 0.05) var stop_animation_max_duration := 0.65
@export_range(0.0, 5.0, 0.05) var stop_animation_trigger_speed := 1.0
@export_range(0.0, 1.0, 0.01) var stop_animation_trigger_time := 0.25
@export_range(0.25, 2.0, 0.05) var stop_step_max_input_time := 0.8

@export_category("Combat Animation")
@export_range(0.0, 0.5, 0.01) var punch_fade_in_time := 0.08
@export_range(0.0, 0.5, 0.01) var punch_fade_out_time := 0.12
@export var upper_body_root_bone: StringName = &"mixamorig_Spine"

@export_category("Animation Optimization")
@export_range(0.0, 200.0, 1.0) var remote_animation_cull_distance := 45.0
@export_range(0.05, 1.0, 0.05) var remote_animation_check_interval := 0.25

@export_category("Temporary Combat")
@export_range(1, 1000, 1) var max_health := 100
@export_range(1, 1000, 1) var punch_damage := 25
@export_range(0.5, 5.0, 0.05) var punch_range := 1.75
@export_range(10.0, 180.0, 1.0) var punch_half_angle := 70.0
@export_range(0.1, 2.0, 0.05) var punch_cooldown := 0.45
@export_range(0.0, 5.0, 0.1) var respawn_protection := 1.0
## Extra distance a server-validated player may travel beyond the distance
## its own movement explains. Covers replication jitter, where the server can
## receive a position that is one replication interval ahead of the last one
## it accepted.
@export_range(0.1, 10.0, 0.1) var server_movement_slack := 1.5
## Longest stretch of movement the server credits when deciding whether a
## position is reachable. The credit is capped so a client cannot wait for a
## slow server and then claim a position it never travelled to.
@export_range(0.05, 2.0, 0.05) var server_max_movement_window := 0.25
## Maximum vertical rise a server-validated player may gain in one check. A
## jump cannot exceed this, so a client cannot fly upwards.
@export_range(0.1, 10.0, 0.1) var server_max_vertical_step := 1.0

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)
var current_move_speed := 0.0
var camera_yaw := 0.0
var camera_pitch := 0.0
var idle_animation: StringName
var current_character_animation: StringName
var was_moving := false
var was_running := false
var stop_animation_pending := false
var stop_animation_time_left := 0.0
var pending_stop_animation: StringName
var last_move_direction := Vector3.ZERO
var movement_input_time := 0.0
var synchronized_stop_deceleration := 0.0
var jump_animation_active := false
var locomotion_playback: AnimationNodeStateMachinePlayback
var punch_animation_node: AnimationNodeAnimation
var _remote_animation_check_time := 0.0
var health := 100:
	set(value):
		health = clampi(value, 0, max_health)
		if is_node_ready():
			_update_health_display()
var _server_last_attack_msec := -1000000
var _server_invulnerable_until_msec := 0
## Last position the server accepted for this player. Used to reject movement
## that is faster than any legitimate speed, which stops a client from
## teleporting to reach a target for a punch.
var _server_validated_position := Vector3.ZERO
var _server_has_validated_position := false
## Wall-clock time of the last accepted position, used to derive how far a
## player could legitimately have travelled since then.
var _server_validated_at_msec := 0
## Current animation name replicated to all peers via [MultiplayerSynchronizer].
## Updated automatically by [method _play_character_animation].
## Remote players read this in [method _process] to drive their local animation.
var net_anim: StringName = &""

const ANIMATION_IDLE := &"idle"
const ANIMATION_START_WALK := &"start_walk"
const ANIMATION_WALK := &"walk"
const ANIMATION_RUN := &"run"
const ANIMATION_STOP_STEP := &"stop_step"
const ANIMATION_STOP_WALK := &"stop_walk"
const ANIMATION_STOP_RUN := &"stop_run"
const ANIMATION_JUMP := &"jump_run"
const ANIMATION_LEFT_JAB := &"left_jab"
const ANIMATION_RIGHT_PUNCH := &"right_punch"

@onready var head: Node3D = $Head
@onready var model_root: Node3D = $ModelRoot
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
@onready var mobile_controls: Control = $MobileControlsLayer/MobileControls
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel


var profile_index := 0:
	set(value):
		# The value replicates from the owning client, so clamp it to a real
		# profile instead of trusting it. An out-of-range index would
		# otherwise leave character_profile unset or point at the wrong model.
		if CharacterRegistry.profiles.is_empty():
			# The registry has not populated yet. Keep the raw value so a
			# legitimate selection is not lost, and resolve the profile once
			# the registry is ready.
			profile_index = value
			return
		var clamped := clampi(value, 0, CharacterRegistry.profiles.size() - 1)
		profile_index = clamped
		character_profile = CharacterRegistry.profiles[clamped]


func _enter_tree() -> void:
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())
	# Movement/profile state follows the owning client, while health is always
	# published by peer 1 (the host or dedicated server).
	var health_synchronizer := get_node_or_null("HealthSynchronizer")
	if health_synchronizer != null:
		health_synchronizer.set_multiplayer_authority(
			MultiplayerPeer.TARGET_PEER_SERVER
		)


func _ready() -> void:
	health = max_health
	if profile_index >= 0 and profile_index < CharacterRegistry.profiles.size():
		character_profile = CharacterRegistry.profiles[profile_index]
	if NetworkManager.is_dedicated_server():
		_configure_dedicated_server_proxy()
		return

	if not _setup_character_profile():
		return
	_setup_character_animations()
	_setup_animation_tree()
	_play_character_animation(idle_animation, 0.0)
	_update_health_display()

	if not is_multiplayer_authority():
		# ── Remote player ─────────────────────────────────────────────────
		# Completely remove MobileControlsLayer so it cannot steal touch
		# events from the local player's MobileControls via set_input_as_handled.
		$MobileControlsLayer.queue_free()
		$HealthLayer.queue_free()
		return

	# ── Local authority player ─────────────────────────────────────────────
	$Head/SpringArm3D/Camera3D.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var initial_camera_transform := head.global_transform
	head.top_level = true
	_server_validated_position = global_position
	_server_has_validated_position = true
	head.global_transform = initial_camera_transform
	camera_yaw = head.global_rotation.y
	camera_pitch = head.global_rotation.x
	_update_camera_rig()
	# Hidden controls do not process input, so this connection is safe on every
	# platform and avoids unreliable hardware-feature heuristics.
	mobile_controls.connect(
		"look_dragged",
		Callable(self, "_on_mobile_look_dragged")
	)


func _configure_dedicated_server_proxy() -> void:
	# Dedicated servers need collision and synchronized state, not imported
	# meshes, animation graphs, cameras, audio, or input UI. Avoiding those
	# resources also keeps headless Dummy rendering out of entity teardown.
	for node_path: NodePath in [
		NodePath("ModelRoot"),
		NodePath("AnimationPlayer"),
		NodePath("AnimationTree"),
		NodePath("Head"),
		NodePath("MobileControlsLayer"),
		NodePath("HealthLayer"),
	]:
		var presentation_node := get_node_or_null(node_path)
		if presentation_node != null:
			presentation_node.queue_free()
	set_process(false)
	set_physics_process(false)
	set_process_input(false)


func _input(event: InputEvent) -> void:
	# Only the authority processes its own input.
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseButton and event.pressed:
		if get_viewport().gui_get_hovered_control() != null:
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if (
		event is InputEventMouseMotion
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		_apply_camera_look(event.relative, mouse_sensitivity)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		_remote_animation_check_time -= delta
		if _remote_animation_check_time <= 0.0:
			_remote_animation_check_time = remote_animation_check_interval
			_update_remote_animation_visibility()
		if animation_tree == null or not animation_tree.active:
			return
		# Remote player: drive animation from the replicated net_anim value.
		if net_anim != &"" and net_anim != current_character_animation:
			_play_character_animation(net_anim)
		return
	_update_camera_rig()


func _physics_process(delta: float) -> void:
	# Remote players receive position/rotation via MultiplayerSynchronizer;
	# skip all physics and input on non-authority peers.
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_blocked := _is_gameplay_input_blocked()
	if (
		not input_blocked
			and Input.is_action_just_pressed("jump")
			and is_on_floor()
	):
		jump_animation_active = _has_animation(ANIMATION_JUMP)
		if jump_animation_active:
			_cancel_upper_body_punch()
		velocity.y = jump_velocity

	# Attacks are sent as reliable RPCs so all peers see the animation.
	if (
		not input_blocked
			and not _is_full_body_jump_active()
			and Input.is_action_just_pressed("attack_left")
	):
		_request_attack.rpc(ANIMATION_LEFT_JAB)
	elif (
		not input_blocked
			and not _is_full_body_jump_active()
			and Input.is_action_just_pressed("attack_right")
	):
		_request_attack.rpc(ANIMATION_RIGHT_PUNCH)

	var input := Vector2.ZERO
	if not input_blocked:
		input = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_backward"
		)
	var camera_basis := Basis(Vector3.UP, camera_yaw)
	var direction := (
		camera_basis * Vector3(input.x, 0, input.y)
	).normalized()
	var has_input := input.length_squared() >= 0.001
	if has_input:
		last_move_direction = direction
	var wants_to_run := (
		Input.is_action_pressed("run")
			and has_input
	)
	var target_speed := run_speed if wants_to_run else speed
	target_speed *= input.length()
	var acceleration := (
		run_acceleration if wants_to_run else walk_acceleration
	)

	if has_input:
		var body_forward := -global_transform.basis.z
		body_forward.y = 0.0
		body_forward = body_forward.normalized()
		var turn_alignment := body_forward.dot(direction)
		var sharp_turn_threshold := cos(deg_to_rad(sharp_turn_angle))
		if turn_alignment < sharp_turn_threshold:
			var turn_factor := clampf(
				inverse_lerp(-1.0, sharp_turn_threshold, turn_alignment),
				0.0,
				1.0
			)
			target_speed *= lerpf(
				sharp_turn_speed_multiplier,
				1.0,
				turn_factor
			)
		synchronized_stop_deceleration = 0.0
		current_move_speed = move_toward(
			current_move_speed,
			target_speed,
			acceleration * delta
		)
		var target_body_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(
			rotation.y,
			target_body_yaw,
			1.0 - exp(-turn_speed * delta)
		)
	else:
		var active_deceleration := (
			synchronized_stop_deceleration
				if synchronized_stop_deceleration > 0.0
				else deceleration
		)
		current_move_speed = move_toward(
			current_move_speed,
			0.0,
			active_deceleration * delta
		)

	var movement_direction := (
		direction if has_input else last_move_direction
	)
	velocity.x = movement_direction.x * current_move_speed
	velocity.z = movement_direction.z * current_move_speed
	if not has_input and is_zero_approx(current_move_speed):
		last_move_direction = Vector3.ZERO
	move_and_slide()
	_update_character_animation(has_input, wants_to_run, delta)


func _update_camera_rig() -> void:
	head.global_position = global_position + Vector3.UP * camera_height
	head.global_rotation = Vector3(camera_pitch, camera_yaw, 0.0)


func _is_gameplay_input_blocked() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return true
	return (
		get_viewport().gui_get_hovered_control() != null
			and (
				Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
					or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			)
	)


func _on_mobile_look_dragged(screen_delta: Vector2) -> void:
	_apply_camera_look(screen_delta, touch_look_sensitivity)


func _apply_camera_look(relative: Vector2, sensitivity: float) -> void:
	camera_yaw -= relative.x * sensitivity
	camera_pitch -= relative.y * sensitivity
	camera_pitch = clamp(camera_pitch, -0.9, 0.55)


func _setup_character_profile() -> bool:
	if character_profile == null:
		push_error("The player has no CharacterProfile")
		return false
	var character_model := model_root.get_node_or_null("CharacterModel")
	animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	animation_tree = get_node_or_null("AnimationTree") as AnimationTree
	if character_model == null:
		push_error(
			"%s player scene has no ModelRoot/CharacterModel"
				% character_profile.display_name
		)
		return false
	if animation_player == null or animation_tree == null:
		push_error(
			"%s player scene needs AnimationPlayer and AnimationTree nodes"
				% character_profile.display_name
		)
		return false
	current_character_animation = &""
	jump_animation_active = false
	stop_animation_pending = false
	pending_stop_animation = &""
	return true


func _setup_character_animations() -> void:
	idle_animation = ANIMATION_IDLE

	if not animation_player.has_animation(idle_animation):
		push_error("The humanoid animation library has no idle animation")
		return

	var animation := animation_player.get_animation(idle_animation)
	animation.loop_mode = Animation.LOOP_LINEAR
	_set_animation_loop(ANIMATION_WALK, Animation.LOOP_LINEAR)
	_set_animation_loop(ANIMATION_RUN, Animation.LOOP_LINEAR)
	_set_animation_loop(ANIMATION_JUMP, Animation.LOOP_NONE)
	_set_animation_loop(ANIMATION_START_WALK, Animation.LOOP_NONE)
	_set_animation_loop(ANIMATION_STOP_STEP, Animation.LOOP_NONE)
	_set_animation_loop(ANIMATION_STOP_WALK, Animation.LOOP_NONE)
	_set_animation_loop(ANIMATION_STOP_RUN, Animation.LOOP_NONE)
	_set_animation_loop(ANIMATION_LEFT_JAB, Animation.LOOP_NONE)
	_set_animation_loop(ANIMATION_RIGHT_PUNCH, Animation.LOOP_NONE)


func _setup_animation_tree() -> void:
	var blend_tree := AnimationNodeBlendTree.new()
	var locomotion_state_machine := AnimationNodeStateMachine.new()
	locomotion_state_machine.allow_transition_to_self = true

	var locomotion_animations: Array[StringName] = [
		ANIMATION_IDLE,
		ANIMATION_START_WALK,
		ANIMATION_WALK,
		ANIMATION_RUN,
		ANIMATION_STOP_STEP,
		ANIMATION_STOP_WALK,
		ANIMATION_STOP_RUN,
		ANIMATION_JUMP,
	]
	var available_animations: Array[StringName] = []
	for animation_name in locomotion_animations:
		if not _has_animation(animation_name):
			continue
		var animation_node := AnimationNodeAnimation.new()
		animation_node.animation = animation_name
		locomotion_state_machine.add_node(
			animation_name,
			animation_node
		)
		available_animations.append(animation_name)

	for from_animation in available_animations:
		for to_animation in available_animations:
			if from_animation == to_animation:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = _get_animation_blend_time(
				from_animation,
				to_animation
			)
			transition.reset = true
			transition.advance_mode = (
				AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			)
			locomotion_state_machine.add_transition(
				from_animation,
				to_animation,
				transition
			)

	var locomotion_speed := AnimationNodeTimeScale.new()
	punch_animation_node = AnimationNodeAnimation.new()
	punch_animation_node.animation = ANIMATION_LEFT_JAB

	var upper_body_punch := AnimationNodeOneShot.new()
	upper_body_punch.fadein_time = punch_fade_in_time
	upper_body_punch.fadeout_time = punch_fade_out_time
	upper_body_punch.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	upper_body_punch.filter_enabled = true
	_add_upper_body_tracks_to_filter(
		upper_body_punch,
		ANIMATION_LEFT_JAB
	)
	_add_upper_body_tracks_to_filter(
		upper_body_punch,
		ANIMATION_RIGHT_PUNCH
	)

	blend_tree.add_node(
		&"Locomotion",
		locomotion_state_machine,
		Vector2(0.0, 160.0)
	)
	blend_tree.add_node(
		&"LocomotionSpeed",
		locomotion_speed,
		Vector2(220.0, 160.0)
	)
	blend_tree.add_node(
		&"Punch",
		punch_animation_node,
		Vector2(220.0, 360.0)
	)
	blend_tree.add_node(
		&"UpperBodyPunch",
		upper_body_punch,
		Vector2(450.0, 180.0)
	)
	blend_tree.connect_node(
		&"LocomotionSpeed",
		0,
		&"Locomotion"
	)
	blend_tree.connect_node(
		&"UpperBodyPunch",
		0,
		&"LocomotionSpeed"
	)
	blend_tree.connect_node(
		&"UpperBodyPunch",
		1,
		&"Punch"
	)
	blend_tree.connect_node(
		&"output",
		0,
		&"UpperBodyPunch"
	)

	animation_player.speed_scale = 1.0
	animation_tree.tree_root = blend_tree
	animation_tree.active = true
	locomotion_playback = animation_tree.get(
		"parameters/Locomotion/playback"
	) as AnimationNodeStateMachinePlayback
	if locomotion_playback == null:
		push_error("Could not initialize the locomotion animation tree")


func _add_upper_body_tracks_to_filter(
	one_shot: AnimationNodeOneShot,
	animation_name: StringName
) -> void:
	if not _has_animation(animation_name):
		return
	var skeleton := model_root.find_child(
		"Skeleton3D",
		true,
		false
	) as Skeleton3D
	if skeleton == null:
		push_warning("Player animation setup could not find Skeleton3D")
		return
	var upper_body_root := skeleton.find_bone(upper_body_root_bone)
	if upper_body_root < 0:
		push_warning(
			"Player skeleton has no upper-body root bone '%s'"
				% upper_body_root_bone
		)
		return
	var animation := animation_player.get_animation(animation_name)
	for track_index in range(animation.get_track_count()):
		var track_path := animation.track_get_path(track_index)
		if track_path.get_subname_count() == 0:
			continue
		var bone_name := StringName(track_path.get_subname(0))
		var bone_index := skeleton.find_bone(bone_name)
		if _is_bone_or_descendant(skeleton, bone_index, upper_body_root):
			one_shot.set_filter_path(track_path, true)


func _is_bone_or_descendant(
	skeleton: Skeleton3D,
	bone_index: int,
	ancestor_index: int
) -> bool:
	var current_index := bone_index
	while current_index >= 0:
		if current_index == ancestor_index:
			return true
		current_index = skeleton.get_bone_parent(current_index)
	return false


func _update_remote_animation_visibility() -> void:
	if animation_tree == null or remote_animation_cull_distance <= 0.0:
		return
	var active_camera := get_viewport().get_camera_3d()
	if active_camera == null:
		animation_tree.active = true
		return
	animation_tree.active = (
		global_position.distance_squared_to(active_camera.global_position)
			<= remote_animation_cull_distance * remote_animation_cull_distance
	)


func _update_character_animation(
	has_input: bool,
	wants_to_run: bool,
	delta: float
) -> void:
	if animation_player == null:
		return

	var started_moving := has_input and not was_moving
	var stopped_moving := not has_input and was_moving
	var stopped_from_run := stopped_moving and was_running
	was_moving = has_input

	if has_input:
		was_running = (
			wants_to_run
				and current_move_speed >= run_animation_entry_speed
		)
		movement_input_time += delta
		stop_animation_pending = false
		stop_animation_time_left = 0.0
		pending_stop_animation = &""
	elif stopped_moving:
		stop_animation_pending = (
			current_move_speed >= stop_animation_trigger_speed
				and movement_input_time >= stop_animation_trigger_time
		)
		if stop_animation_pending:
			if movement_input_time <= stop_step_max_input_time:
				pending_stop_animation = ANIMATION_STOP_STEP
			elif stopped_from_run:
				pending_stop_animation = ANIMATION_STOP_RUN
			else:
				pending_stop_animation = ANIMATION_STOP_WALK
		else:
			pending_stop_animation = &""
		was_running = false
		stop_animation_time_left = (
			stop_animation_delay if stop_animation_pending else 0.0
		)
		movement_input_time = 0.0
		if not stop_animation_pending:
			current_move_speed = 0.0
			last_move_direction = Vector3.ZERO

	if not is_on_floor():
		_play_character_animation(ANIMATION_JUMP)
		return

	if jump_animation_active:
		if current_character_animation != ANIMATION_JUMP:
			_play_character_animation(ANIMATION_JUMP)
		if (
			locomotion_playback != null
				and (
					locomotion_playback.get_current_play_position()
						< locomotion_playback.get_current_length() - 0.001
				)
		):
			return
		jump_animation_active = false

	if (
		wants_to_run
			and current_move_speed >= run_animation_entry_speed
	):
		_play_character_animation(
			ANIMATION_RUN,
			-1.0,
			false,
			_locomotion_playback_speed(ANIMATION_RUN)
		)
		return

	if has_input:
		if (
			current_character_animation == ANIMATION_START_WALK
				and movement_input_time < start_to_walk_time
		):
			return
		if started_moving and _has_animation(ANIMATION_START_WALK):
			_play_character_animation(
				ANIMATION_START_WALK,
				-1.0
			)
		else:
			_play_character_animation(
				ANIMATION_WALK,
				-1.0,
				false,
				_locomotion_playback_speed(ANIMATION_WALK)
			)
		return

	if stop_animation_pending:
		stop_animation_time_left = maxf(
			stop_animation_time_left - delta,
			0.0
		)
		if stop_animation_time_left > 0.0:
			return
		stop_animation_pending = false
		if _has_animation(pending_stop_animation):
			_play_synchronized_stop_animation(pending_stop_animation)
			return

	if (
		(
			current_character_animation == ANIMATION_STOP_STEP
				or current_character_animation == ANIMATION_STOP_WALK
				or current_character_animation == ANIMATION_STOP_RUN
		)
			and locomotion_playback != null
			and (
				locomotion_playback.get_current_play_position()
					< locomotion_playback.get_current_length() - 0.001
			)
	):
		return
	synchronized_stop_deceleration = 0.0
	_play_character_animation(idle_animation)


## RPC: triggers an attack animation on every peer that has a copy of this
## player node. Only the [member is_multiplayer_authority] may initiate the call
## (mode = "authority"). [code]call_local[/code] ensures the authority also
## plays the animation locally.
@rpc("authority", "call_local", "reliable")
func _request_attack(animation_name: StringName) -> void:
	if (
		animation_name != ANIMATION_LEFT_JAB
			and animation_name != ANIMATION_RIGHT_PUNCH
	):
		return
	# A sprint dive is a full-body action. Do not let its owner or a delayed
	# network attack place the upper-body punch layer back over the roll.
	if _is_full_body_jump_active():
		return
	_play_attack(animation_name)
	if multiplayer.is_server():
		_server_try_punch()


func _server_try_punch() -> void:
	if not multiplayer.is_server() or health <= 0:
		return
	var now := Time.get_ticks_msec()
	if now - _server_last_attack_msec < roundi(punch_cooldown * 1000.0):
		return
	_server_last_attack_msec = now

	# Position and rotation replicate from the owning client, so a client
	# could otherwise teleport next to a target and land server-resolved
	# damage. Only accept the strike when the server considers the attacker's
	# position reachable.
	var attacker_position := _server_trusted_position()
	var attacker_forward := _server_validated_forward()
	if not attacker_forward.is_finite():
		return

	var minimum_facing := cos(deg_to_rad(punch_half_angle))
	var closest_target: Node3D = null
	var closest_distance := INF
	for candidate in get_parent().get_children():
		if candidate == self or not candidate.has_method("_server_take_damage"):
			continue
		var target := candidate as Node3D
		if target == null or int(target.get("health")) <= 0:
			continue
		# The target is measured from the position the server trusts for it,
		# so a target cannot be dragged into reach by its own owner.
		var trusted_target_position: Vector3 = target.call(
			"_server_trusted_position"
		)
		var to_target := trusted_target_position - attacker_position
		if absf(to_target.y) > 1.4:
			continue
		to_target.y = 0.0
		var distance := to_target.length()
		if distance <= 0.001 or distance > punch_range:
			continue
		if attacker_forward.dot(to_target / distance) < minimum_facing:
			continue
		if distance < closest_distance:
			closest_distance = distance
			closest_target = target
	if closest_target != null:
		closest_target.call("_server_take_damage", punch_damage)


## Returns the horizontal forward direction derived from the server's
## validated rotation, or an invalid vector when it cannot be determined.
func _server_validated_forward() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return Vector3.ZERO
	return forward.normalized()


## Resets the server's validated position to the player's current position.
##
## Called by the server when a player spawns or respawns, so the new position
## is trusted as the starting point of the next movement check.
func _server_reset_validated_position() -> void:
	_server_validated_position = global_position
	_server_has_validated_position = true
	_server_validated_at_msec = Time.get_ticks_msec()


## Advances the server's validated position for this player when the
## replicated movement stays within a reachable distance.
##
## Called on the server for every player it tracks. Returns [code]true[/code]
## when the movement was accepted.
##
## The allowed distance is derived from elapsed wall-clock time, not from the
## physics tick, because replicated positions arrive in bursts rather than
## one update per tick. A tick-based budget would reject legitimate
## movement whenever several updates land between two server ticks.
##
## The node's own position is never rewritten here. The replicated position
## stays authoritative for rendering and collision, while this validated copy
## is used for server-side hit detection. A teleport therefore leaves the
## validated copy behind, and the melee range check fails.
func _server_validate_movement(delta: float) -> bool:
	if not multiplayer.is_server():
		return true
	var current := global_position
	var now := Time.get_ticks_msec()
	if not _server_has_validated_position:
		_server_validated_position = current
		_server_has_validated_position = true
		_server_validated_at_msec = now
		return true

	# The server owns its own player, so that position is server-authored and
	# always trusted. Only positions that arrive from a remote client are
	# measured against the distance the player could have travelled.
	if get_multiplayer_authority() == multiplayer.get_unique_id():
		_server_validated_position = current
		_server_validated_at_msec = now
		return true

	var elapsed_seconds := float(maxi(now - _server_validated_at_msec, 0)) / 1000.0
	var offset := current - _server_validated_position
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	var horizontal_distance := horizontal.length()
	# Only the time the player has actually been moving counts towards the
	# budget, and that credit is capped. Idle time is not credited, so a
	# client cannot teleport and then wait for the budget to grow until the
	# new position looks reachable.
	var credited_seconds := minf(elapsed_seconds, server_max_movement_window)
	var maximum_horizontal := (
		run_speed * credited_seconds + server_movement_slack
	)
	if horizontal_distance > maximum_horizontal:
		# Not reachable. The validated position and its timestamp stay where
		# they are, so waiting does not make the claim valid.
		return false
	# A jump cannot climb faster than the configured gravity allows, so a
	# large upward step in one interval is not legitimate.
	var maximum_vertical := (
		absf(gravity) * credited_seconds * credited_seconds * 0.5
			+ server_max_vertical_step
	)
	if offset.y > maximum_vertical:
		return false

	if horizontal_distance > 0.001 or absf(offset.y) > 0.001:
		# The player moved, so the next check measures from now. Idle time is
		# not credited as movement.
		_server_validated_at_msec = now
	_server_validated_position = current
	return true


## Returns the position the server trusts for this player.
##
## For a remote client that is the last position the server accepted, so a
## teleport stays behind. For a player the server owns it is the current
## position, which the server wrote itself.
func _server_trusted_position() -> Vector3:
	if not _server_has_validated_position:
		return global_position
	return _server_validated_position


func _server_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0 or health <= 0:
		return
	if Time.get_ticks_msec() < _server_invulnerable_until_msec:
		return
	health -= amount
	if health > 0:
		return
	var game_manager := get_node_or_null("../../GameManager")
	if game_manager != null and game_manager.has_method("respawn_player"):
		game_manager.call("respawn_player", self)


func server_respawn(respawn_position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	health = max_health
	velocity = Vector3.ZERO
	current_move_speed = 0.0
	position = respawn_position
	# The respawn position is server-chosen, so the validated copy must follow
	# it. Otherwise the next movement check would treat the jump from the
	# death position as an impossible teleport.
	_server_reset_validated_position()
	_server_invulnerable_until_msec = (
		Time.get_ticks_msec() + roundi(respawn_protection * 1000.0)
	)
	var owner_peer := get_multiplayer_authority()
	if (
		owner_peer != MultiplayerPeer.TARGET_PEER_SERVER
			and owner_peer in multiplayer.get_peers()
	):
		_receive_server_respawn.rpc_id(owner_peer, respawn_position)


@rpc("any_peer", "call_remote", "reliable")
func _receive_server_respawn(respawn_position: Vector3) -> void:
	if (
		multiplayer.get_remote_sender_id()
			!= MultiplayerPeer.TARGET_PEER_SERVER
			or not is_multiplayer_authority()
	):
		return
	velocity = Vector3.ZERO
	current_move_speed = 0.0
	position = respawn_position


func _update_health_display() -> void:
	if not is_instance_valid(health_bar) or not is_instance_valid(health_label):
		return
	health_bar.max_value = max_health
	health_bar.value = health
	health_label.text = "Health %d / %d" % [health, max_health]


func _play_attack(animation_name: StringName) -> void:
	if (
		animation_tree == null
			or punch_animation_node == null
			or _is_full_body_jump_active()
			or not _has_animation(animation_name)
	):
		return
	punch_animation_node.animation = animation_name
	animation_tree.set(
		"parameters/UpperBodyPunch/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


func _cancel_upper_body_punch() -> void:
	if animation_tree == null:
		return
	animation_tree.set(
		"parameters/UpperBodyPunch/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT
	)


func _is_full_body_jump_active() -> bool:
	return (
		jump_animation_active
			or current_character_animation == ANIMATION_JUMP
			or net_anim == ANIMATION_JUMP
	)


func _play_synchronized_stop_animation(
	animation_name: StringName
) -> void:
	var stop_animation := animation_player.get_animation(
		animation_name
	)
	var effective_playback_speed := maxf(
		stop_animation_playback_speed,
		stop_animation.length / maxf(
			stop_animation_max_duration,
			0.01
		)
	)
	var stop_duration := stop_animation.length / effective_playback_speed
	synchronized_stop_deceleration = current_move_speed / maxf(
		stop_duration,
		0.01
	)
	_play_character_animation(
		animation_name,
		-1.0,
		true,
		effective_playback_speed
	)


func _locomotion_playback_speed(animation_name: StringName) -> float:
	var reference_speed := (
		run_speed if animation_name == ANIMATION_RUN else speed
	)
	return clampf(
		current_move_speed / maxf(reference_speed, 0.01),
		locomotion_min_playback_speed,
		locomotion_max_playback_speed
	)


func _play_character_animation(
	animation_name: StringName,
	_blend_time := -1.0,
	restart := false,
	playback_speed := 1.0
) -> void:
	if (
		not _has_animation(animation_name)
			or animation_tree == null
			or locomotion_playback == null
	):
		return
	# Jump styles are full-body clips. This also covers a sprint jump/roll clip
	# assigned to the character library under the canonical `jump_run` name.
	if animation_name == ANIMATION_JUMP:
		_cancel_upper_body_punch()
	animation_tree.set(
		"parameters/LocomotionSpeed/scale",
		playback_speed
	)
	if current_character_animation == animation_name and not restart:
		return
	current_character_animation = animation_name
	# Keep net_anim in sync so MultiplayerSynchronizer broadcasts the change
	# to all remote peers (authority only; harmless for non-authority).
	net_anim = animation_name
	if not locomotion_playback.is_playing():
		locomotion_playback.start(animation_name, true)
	else:
		locomotion_playback.travel(animation_name, true)


func _get_animation_blend_time(
	from_animation: StringName,
	to_animation: StringName
) -> float:
	if from_animation == &"":
		return 0.0

	if (
		from_animation == ANIMATION_IDLE
			and (
				to_animation == ANIMATION_START_WALK
					or to_animation == ANIMATION_WALK
					or to_animation == ANIMATION_RUN
			)
	):
		return idle_start_blend_time

	if (
		(
			from_animation == ANIMATION_START_WALK
				or from_animation == ANIMATION_WALK
				or from_animation == ANIMATION_RUN
		)
			and (
				to_animation == ANIMATION_WALK
					or to_animation == ANIMATION_RUN
			)
	):
		return gait_change_blend_time

	if (
		to_animation == ANIMATION_STOP_STEP
			or to_animation == ANIMATION_STOP_WALK
			or to_animation == ANIMATION_STOP_RUN
	):
		return stopping_blend_time

	if (
		to_animation == ANIMATION_IDLE
			and (
				from_animation == ANIMATION_STOP_STEP
					or from_animation == ANIMATION_STOP_WALK
					or from_animation == ANIMATION_STOP_RUN
			)
	):
		return stop_idle_blend_time

	return locomotion_blend_time


func _set_animation_loop(
	animation_name: StringName,
	loop_mode: Animation.LoopMode
) -> void:
	if _has_animation(animation_name):
		animation_player.get_animation(animation_name).loop_mode = loop_mode


func _has_animation(animation_name: StringName) -> bool:
	return (
		animation_player != null
			and animation_player.has_animation(animation_name)
	)
