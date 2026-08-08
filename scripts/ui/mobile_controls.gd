extends Control

signal look_dragged(screen_delta: Vector2)

@export var show_on_desktop := false
@export_range(0.1, 1.0, 0.05) var opacity := 0.55
@export_range(0.2, 1.0, 0.05) var joystick_deadzone := 0.18

const JOYSTICK_ROLE := &"_joystick"
const LOOK_ROLE := &"_look"
const MOVE_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_forward",
	&"move_backward",
]
const BUTTON_ACTIONS: Array[StringName] = [
	&"run",
	&"jump",
	&"attack_left",
	&"attack_right",
]

var touch_roles: Dictionary = {}
var joystick_knob := Vector2.ZERO


func _ready() -> void:
	# emulate_touch_from_mouse is enabled for testing, which can make
	# is_touchscreen_available() report a false positive on desktop. Exported
	# mobile builds are the reliable production signal.
	visible = OS.has_feature("mobile") or show_on_desktop
	set_process_input(visible)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	joystick_knob = _joystick_center()
	queue_redraw()


func _exit_tree() -> void:
	# Only release actions this instance actually owns. Every network player has
	# a controls scene, and a remote player's teardown must not cancel the local
	# player's keyboard or touch input.
	if _is_role_active(JOYSTICK_ROLE):
		_release_movement()
	for action in BUTTON_ACTIONS:
		if _is_role_active(action):
			Input.action_release(action)
	touch_roles.clear()


func _on_viewport_size_changed() -> void:
	if not _is_role_active(JOYSTICK_ROLE):
		joystick_knob = _joystick_center()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _is_touch_over_blocking_ui(event.position):
			return
		var action := _button_at(event.position)
		if action != &"" and not _is_role_active(action):
			touch_roles[event.index] = action
			Input.action_press(action)
		elif (
			event.position.x < _screen_size().x * 0.46
				and not _is_role_active(JOYSTICK_ROLE)
				and event.position.distance_to(_joystick_center())
					<= _joystick_radius() * 1.65
		):
			touch_roles[event.index] = JOYSTICK_ROLE
			_update_joystick(event.position)
		elif not _is_role_active(LOOK_ROLE):
			touch_roles[event.index] = LOOK_ROLE
		else:
			return
	else:
		if not touch_roles.has(event.index):
			return
		var role: StringName = touch_roles[event.index]
		touch_roles.erase(event.index)
		if role == JOYSTICK_ROLE:
			_release_movement()
			joystick_knob = _joystick_center()
		elif role != LOOK_ROLE:
			Input.action_release(role)

	queue_redraw()
	get_viewport().set_input_as_handled()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if not touch_roles.has(event.index):
		return
	var role: StringName = touch_roles[event.index]
	if role == JOYSTICK_ROLE:
		_update_joystick(event.position)
	elif role == LOOK_ROLE:
		look_dragged.emit(event.screen_relative)
	queue_redraw()
	get_viewport().set_input_as_handled()


func _update_joystick(touch_position: Vector2) -> void:
	var center := _joystick_center()
	var displacement := touch_position - center
	var radius := _joystick_radius()
	if displacement.length() > radius:
		displacement = displacement.normalized() * radius
	joystick_knob = center + displacement

	var direction := displacement / radius
	if direction.length() < joystick_deadzone:
		direction = Vector2.ZERO
	else:
		direction = direction.normalized() * inverse_lerp(
			joystick_deadzone,
			1.0,
			direction.length()
		)
	_set_action_strength(&"move_left", maxf(-direction.x, 0.0))
	_set_action_strength(&"move_right", maxf(direction.x, 0.0))
	_set_action_strength(&"move_forward", maxf(-direction.y, 0.0))
	_set_action_strength(&"move_backward", maxf(direction.y, 0.0))


func _set_action_strength(action: StringName, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_movement() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


func _is_role_active(role: StringName) -> bool:
	return role in touch_roles.values()


func _is_touch_over_blocking_ui(point: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group(&"touch_input_blocker"):
		var control := node as Control
		if (
			control != null
				and control.is_visible_in_tree()
				and control.get_global_rect().has_point(point)
		):
			return true
	return false


func _button_at(point: Vector2) -> StringName:
	for action in BUTTON_ACTIONS:
		if point.distance_to(_button_center(action)) <= _button_radius(action):
			return action
	return &""


func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _ui_scale() -> float:
	var viewport_size := _screen_size()
	return clampf(
		minf(viewport_size.x / 1280.0, viewport_size.y / 720.0),
		0.62,
		1.4
	)


func _joystick_center() -> Vector2:
	var viewport_size := _screen_size()
	var ui_scale := _ui_scale()
	return Vector2(135.0 * ui_scale, viewport_size.y - 135.0 * ui_scale)


func _joystick_radius() -> float:
	return 78.0 * _ui_scale()


func _button_center(action: StringName) -> Vector2:
	var viewport_size := _screen_size()
	var ui_scale := _ui_scale()
	match action:
		&"attack_right":
			return Vector2(
				viewport_size.x - 100.0 * ui_scale,
				viewport_size.y - 145.0 * ui_scale
			)
		&"attack_left":
			return Vector2(
				viewport_size.x - 215.0 * ui_scale,
				viewport_size.y - 92.0 * ui_scale
			)
		&"jump":
			return Vector2(
				viewport_size.x - 105.0 * ui_scale,
				viewport_size.y - 275.0 * ui_scale
			)
		&"run":
			return Vector2(
				viewport_size.x - 260.0 * ui_scale,
				viewport_size.y - 215.0 * ui_scale
			)
	return Vector2.ZERO


func _button_radius(action: StringName) -> float:
	return (54.0 if action == &"attack_right" else 46.0) * _ui_scale()


func _draw() -> void:
	if not visible:
		return
	var base_color := Color(0.08, 0.11, 0.16, opacity)
	var active_color := Color(0.15, 0.55, 0.95, minf(opacity + 0.2, 0.9))
	var outline_color := Color(1.0, 1.0, 1.0, minf(opacity + 0.15, 0.85))
	var center := _joystick_center()
	var radius := _joystick_radius()
	draw_circle(center, radius, base_color)
	draw_arc(center, radius, 0.0, TAU, 48, outline_color, 3.0 * _ui_scale())
	draw_circle(
		joystick_knob,
		radius * 0.42,
		active_color if _is_role_active(JOYSTICK_ROLE) else base_color
	)
	draw_arc(
		joystick_knob,
		radius * 0.42,
		0.0,
		TAU,
		32,
		outline_color,
		2.0 * _ui_scale()
	)

	_draw_action_button(&"run", "RUN", base_color, active_color, outline_color)
	_draw_action_button(&"jump", "JUMP", base_color, active_color, outline_color)
	_draw_action_button(&"attack_left", "JAB", base_color, active_color, outline_color)
	_draw_action_button(&"attack_right", "HIT", base_color, active_color, outline_color)


func _draw_action_button(
	action: StringName,
	label: String,
	base_color: Color,
	active_color: Color,
	outline_color: Color
) -> void:
	var center := _button_center(action)
	var radius := _button_radius(action)
	draw_circle(center, radius, active_color if _is_role_active(action) else base_color)
	draw_arc(center, radius, 0.0, TAU, 32, outline_color, 2.0 * _ui_scale())
	var font := ThemeDB.fallback_font
	var font_size := maxi(roundi(17.0 * _ui_scale()), 12)
	draw_string(
		font,
		Vector2(center.x - radius, center.y + font_size * 0.35),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		radius * 2.0,
		font_size,
		Color.WHITE
	)
