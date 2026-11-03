class_name GameMenus
extends CanvasLayer

## CanvasLayer UI overlay displaying the Escape-togglable Pause Menu
## ('Resume', 'Save', 'Quit', Load, Restart, Settings), Tier progress bar,
## and the "Nothing Left to Eat" Win Screen overlay.
## Runs with `PROCESS_MODE_ALWAYS` so Escape and buttons work while paused.

signal resume_requested
signal save_requested
signal load_requested
signal restart_requested
signal delete_save_requested
signal settings_changed(volume_db: float, ssao: bool, sdfgi: bool)

@export_group("Nodes")
@export var tier_bar: ProgressBar
@export var reaction_label: Label
@export var toast_label: Label
@export var menu_button: Button
@export var pause_panel: PanelContainer
@export var win_panel: PanelContainer
@export var win_stats_label: Label
@export var resume_button: Button
@export var save_button: Button
@export var quit_button: Button
@export var load_button: Button
@export var delete_save_button: Button
@export var volume_slider: HSlider
@export var ssao_check: CheckBox
@export var sdfgi_check: CheckBox

var _toast_timer := 0.0
var _win_dismissed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if tier_bar == null:
		tier_bar = get_node_or_null("Overlay/TopRight/TierBar") as ProgressBar
	if reaction_label == null:
		reaction_label = get_node_or_null("Overlay/TopRight/ReactionLabel") as Label
	if toast_label == null:
		toast_label = get_node_or_null("Overlay/TopRight/ToastLabel") as Label
	if menu_button == null:
		menu_button = get_node_or_null("Overlay/TopRight/MenuButton") as Button
	if pause_panel == null:
		pause_panel = get_node_or_null("Overlay/PausePanel") as PanelContainer
	if win_panel == null:
		win_panel = get_node_or_null("Overlay/WinPanel") as PanelContainer
	if win_stats_label == null:
		win_stats_label = get_node_or_null("Overlay/WinPanel/Margin/VBox/StatsLabel") as Label
	if resume_button == null:
		resume_button = get_node_or_null("Overlay/PausePanel/Margin/VBox/ResumeButton") as Button
	if save_button == null:
		save_button = get_node_or_null("Overlay/PausePanel/Margin/VBox/SaveButton") as Button
	if quit_button == null:
		quit_button = get_node_or_null("Overlay/PausePanel/Margin/VBox/QuitButton") as Button
	if load_button == null:
		load_button = get_node_or_null("Overlay/PausePanel/Margin/VBox/LoadButton") as Button
	if delete_save_button == null:
		delete_save_button = get_node_or_null("Overlay/PausePanel/Margin/VBox/DeleteSaveButton") as Button
	if volume_slider == null:
		volume_slider = get_node_or_null("Overlay/PausePanel/Margin/VBox/VolumeRow/VolumeSlider") as HSlider
	if ssao_check == null:
		ssao_check = get_node_or_null("Overlay/PausePanel/Margin/VBox/SSAOCheck") as CheckBox
	if sdfgi_check == null:
		sdfgi_check = get_node_or_null("Overlay/PausePanel/Margin/VBox/SDFGICheck") as CheckBox

	_wire_buttons()
	if pause_panel != null:
		pause_panel.visible = false
	if win_panel != null:
		win_panel.visible = false
	if toast_label != null:
		toast_label.visible = false
	refresh_save_buttons()


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
		if _toast_timer <= 0.0 and toast_label != null:
			toast_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("pause") and event.is_action_pressed("pause"):
		toggle_pause_menu()
		get_viewport().set_input_as_handled()
		return
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_ESCAPE:
		toggle_pause_menu()
		get_viewport().set_input_as_handled()


func _wire_buttons() -> void:
	if menu_button != null:
		menu_button.pressed.connect(toggle_pause_menu)
	if resume_button != null:
		resume_button.pressed.connect(func() -> void:
			set_paused(false)
			resume_requested.emit()
		)
	if save_button != null:
		save_button.pressed.connect(func() -> void: save_requested.emit())
	if load_button != null:
		load_button.pressed.connect(func() -> void:
			set_paused(false)
			load_requested.emit()
		)
	var restart_btn := get_node_or_null("Overlay/PausePanel/Margin/VBox/RestartButton") as Button
	if restart_btn != null:
		restart_btn.pressed.connect(func() -> void:
			set_paused(false)
			restart_requested.emit()
		)
	if delete_save_button != null:
		delete_save_button.pressed.connect(func() -> void:
			delete_save_requested.emit()
			refresh_save_buttons()
		)
	if quit_button != null:
		quit_button.pressed.connect(func() -> void:
			set_paused(false)
			get_tree().quit()
		)

	var win_restart_btn := get_node_or_null("Overlay/WinPanel/Margin/VBox/Buttons/RestartWorldButton") as Button
	if win_restart_btn != null:
		win_restart_btn.pressed.connect(func() -> void:
			set_paused(false)
			restart_requested.emit()
		)
	var win_keep_btn := get_node_or_null("Overlay/WinPanel/Margin/VBox/Buttons/KeepRoamingButton") as Button
	if win_keep_btn != null:
		win_keep_btn.pressed.connect(func() -> void:
			_win_dismissed = true
			if win_panel != null:
				win_panel.visible = false
		)

	if volume_slider != null:
		volume_slider.value_changed.connect(func(_val: float) -> void: _emit_settings())
	if ssao_check != null:
		ssao_check.toggled.connect(func(_on: bool) -> void: _emit_settings())
	if sdfgi_check != null:
		sdfgi_check.toggled.connect(func(_on: bool) -> void: _emit_settings())


func _emit_settings() -> void:
	var vol := volume_slider.value if volume_slider != null else -6.0
	var ssao := ssao_check.button_pressed if ssao_check != null else false
	var sdfgi := sdfgi_check.button_pressed if sdfgi_check != null else false
	settings_changed.emit(vol, ssao, sdfgi)


func sync_settings_controls(volume_db: float, ssao: bool, sdfgi: bool) -> void:
	if volume_slider != null:
		volume_slider.set_value_no_signal(volume_db)
	if ssao_check != null:
		ssao_check.set_pressed_no_signal(ssao)
	if sdfgi_check != null:
		sdfgi_check.set_pressed_no_signal(sdfgi)


func toggle_pause_menu() -> void:
	var target_pause := not (pause_panel != null and pause_panel.visible)
	set_paused(target_pause)


func set_paused(paused: bool) -> void:
	if pause_panel != null:
		pause_panel.visible = paused
	if paused and resume_button != null and is_inside_tree():
		resume_button.grab_focus()
	refresh_save_buttons()
	if is_inside_tree():
		get_tree().paused = paused


func refresh_save_buttons() -> void:
	var exists := SaveManager.has_save()
	if load_button != null:
		load_button.disabled = not exists
	if delete_save_button != null:
		delete_save_button.disabled = not exists


func show_toast(message: String, duration: float = 2.2) -> void:
	if toast_label == null:
		return
	toast_label.text = message
	toast_label.visible = true
	_toast_timer = duration


func update_progression(
		player_size: float,
		tier_small: float,
		tier_medium: float,
		top_tier: float,
		remaining: int,
		total_spawned: int
	) -> void:
	if tier_bar != null:
		var ratio := clampf((player_size - 0.8) / maxf(top_tier - 0.8, 0.01), 0.0, 1.0)
		tier_bar.value = ratio * 100.0

	if reaction_label != null:
		if remaining <= 0:
			reaction_label.text = "The village is silent."
		elif player_size >= top_tier:
			reaction_label.text = "Your eyes go blank · All life flees (%d left)" % remaining
		elif player_size >= tier_medium:
			reaction_label.text = "Villagers flee in panic (%d left)" % remaining
		elif player_size >= tier_small:
			reaction_label.text = "Birds flee · Villagers still bite (%d left)" % remaining
		else:
			reaction_label.text = "Tiny prey · Watch out for birds & villagers (%d/%d)" % [remaining, total_spawned]


func show_win_screen(
		final_size: float,
		eaten_count: int,
		elapsed_sec: float,
		best_sec: float,
		worlds_eaten: int
	) -> void:
	if _win_dismissed or win_panel == null:
		return
	win_panel.visible = true
	if win_stats_label != null:
		win_stats_label.text = (
			"Final Size: %.2f m   ·   Swallowed: %d\n"
			+ "Time Elapsed: %s   ·   Fastest Empty World: %s\n"
			+ "Worlds Devoured: %d"
		) % [
			final_size,
			eaten_count,
			_format_time(elapsed_sec),
			_format_time(best_sec),
			worlds_eaten,
		]


static func _format_time(seconds: float) -> String:
	var total := maxi(int(round(seconds)), 0)
	var mins := total / 60
	var secs := total % 60
	return "%02d:%02d" % [mins, secs]
