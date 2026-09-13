extends RefCounted
## Settings presentation owns no preferences: all changes use the game service.
const SYMBOLS = preload("res://assets/ui/settings_symbols.svg")
const KNOB = preload("res://assets/ui/settings_knob.svg")
const PREVIEW = preload("res://scripts/settings_preview.gd")
const TABS := [["display", "画面与舒适度"], ["audio", "声音"], ["keys", "键盘按键"], ["controller", "手柄与辅助"]]
var game
var hud
var preview
var preview_caption: Label
var mode_buttons: Array[Button] = []
var toggles: Dictionary = {}
var capture_button: Button

static func symbol(index: int) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = SYMBOLS
	result.region = Rect2(index * 64, 0, 64, 64)
	return result

func text(parent: Node, value: String, font_size := 16, color := Color("afb8b5")) -> Label:
	var node: Label = hud.label(value, font_size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(node)
	return node

func build() -> void:
	hud.dashboard.hide()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	hud.menu_margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := text(header, "终端设置", 44, Color("ece8d9"))
	title.add_theme_font_override("font", hud.DISPLAY_FONT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var identity := text(header, "七号 / 个人终端\n即时生效 · 自动保存", 15, hud.MINT)
	identity.custom_minimum_size.x = 220
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	column.add_child(body)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 204
	navigation.add_theme_constant_override("separation", 12)
	body.add_child(navigation)
	var selected: Button
	for index in range(TABS.size()):
		var item: Array = TABS[index]
		var active: bool = game.settings_tab == item[0]
		var tab: Button = hud.button(item[1], game.choose_settings_tab.bind(item[0]), active)
		tab.custom_minimum_size = Vector2(204, 62)
		tab.icon = symbol(index)
		tab.expand_icon = true
		tab.add_theme_constant_override("icon_max_width", 25)
		tab.add_theme_constant_override("h_separation", 12)
		for state in ["normal", "hover", "focus", "pressed"]:
			tab.add_theme_color_override("icon_" + state + "_color", Color("243135") if active or state == "pressed" else Color.WHITE)
		navigation.add_child(tab)
		if active: selected = tab
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	navigation.add_child(space)
	text(navigation, "按 Esc 或手柄右键返回。\n战斗将在退出设置后\n继续保持暂停。" if game.settings_return == "paused" else "按 Esc 或手柄右键返回。\n所有调整会记住，\n下次游玩无需重设。", 14)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", hud.style(Color("111d22"), Color("304247"), 24))
	body.add_child(panel)
	var inside := HBoxContainer.new()
	inside.add_theme_constant_override("separation", 28)
	panel.add_child(inside)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	inside.add_child(scroll)
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 485
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 20)
	scroll.add_child(form)
	var visual := VBoxContainer.new()
	visual.custom_minimum_size.x = 292
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual.size_flags_stretch_ratio = 0.58
	visual.add_theme_constant_override("separation", 16)
	inside.add_child(visual)
	preview = PREVIEW.new()
	preview.game = game
	preview.kind = game.settings_tab
	preview.custom_minimum_size = Vector2(292, 218)
	visual.add_child(preview)
	preview_caption = text(visual, "", 16, hud.MINT)
	match game.settings_tab:
		"display":
			text(form, "显示方式", 23, Color("ece8d9"))
			var modes := HBoxContainer.new()
			modes.add_theme_constant_override("separation", 12)
			form.add_child(modes)
			for full in [false, true]:
				var option: Button = hud.button("无边框全屏" if full else "窗口", func(): game.set_setting("fullscreen", full))
				option.custom_minimum_size = Vector2(212, 48)
				modes.add_child(option)
				mode_buttons.append(option)
			text(form, "全屏跟随桌面分辨率；F11 随时切换。", 14)
			slider_row(form, "shake", "屏幕震动", "保留打击感，或调至零让画面保持稳定。")
			slider_row(form, "flash", "命中闪光", "降低命中亮度，不影响攻击范围提示。")
			toggle_row(form, "high_contrast", "高对比文字", "提高文字亮度，并增加清晰描边。")
			var demo: Button = hud.button("预览震动与闪光", preview.demonstrate)
			demo.custom_minimum_size = Vector2(240, 48)
			visual.add_child(demo)
			text(visual, "仅在上方小画面演示，\n不会推进战斗或消耗资源。", 14)
		"audio":
			text(form, "声音混音", 23, Color("ece8d9"))
			slider_row(form, "volume", "总音量", "统一控制所有声音的输出。")
			slider_row(form, "effects_volume", "战斗音效", "武器、命中与操作提示的相对音量。")
			slider_row(form, "ambience_volume", "空间站环境声", "让空间站的低鸣保持在合适的背景位置。")
			var listen: Button = hud.button("试听战斗提示音", func(): game.sound.play_cue("ui", 0.18))
			listen.custom_minimum_size = Vector2(240, 48)
			visual.add_child(listen)
			# Left/right on sliders changes values. Continue down to reach audition.
			var last_slider: HSlider = form.find_child("ambience_volume", true, false)
			last_slider.focus_neighbor_bottom = last_slider.get_path_to(listen)
			listen.focus_neighbor_top = listen.get_path_to(last_slider)
			text(visual, "音量表显示设置后的输出比例。\n按 M 临时静音，再按一次恢复。", 14)
		"keys":
			text(form, "键盘按键", 23, Color("ece8d9"))
			text(form, "选中操作后按新键；Esc 取消。\n方向键、鼠标和菜单快捷键始终可用。", 15)
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
			form.add_child(grid)
			for action in game.SETTINGS.KEYS:
				var waiting: bool = game.rebind_action == action
				var option: Button = hud.button(game.SETTINGS.LABELS[action] + " / " + ("等待按键…" if waiting else game.settings.key_label(action)), game.begin_rebind.bind(action), waiting)
				option.custom_minimum_size = Vector2(236, 56)
				grid.add_child(option)
				if waiting: capture_button = option
			var reset: Button = hud.button("恢复默认按键", game.reset_controls)
			reset.custom_minimum_size = Vector2(236, 48)
			form.add_child(reset)
			text(visual, "暖色按键已分配给主要操作。\n鼠标左键攻击，右键释放等离子弹。", 15)
		"controller":
			text(form, "瞄准与提示", 23, Color("ece8d9"))
			toggle_row(form, "aim_assist", "辅助瞄准", "鼠标闲置时辅助锁定；右摇杆可直接瞄准。")
			toggle_row(form, "tutorial", "首舱操作提示", "显示移动、攻击和闪避的短提示。")
			text(form, "双人同屏", 23, Color("ece8d9"))
			text(form, "在船坞选择“双人手柄救援”，两只手柄分别按下键加入。\n一号席操作共享菜单，离线时由二号席接管；两人均可暂停。", 17)
			text(form, "设备断开时会暂停，重新配对即可继续。", 15)
			text(visual, "菜单：十字键选择，下键确认，右键返回。\n战斗：左右摇杆负责移动与瞄准。", 15)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	column.add_child(footer)
	var back: Button = hud.button("完成并返回 / Esc", game.close_settings)
	back.custom_minimum_size = Vector2(260, 50)
	footer.add_child(back)
	for action in visual.get_children():
		if action is Button:
			action.focus_neighbor_bottom = action.get_path_to(back)
			back.focus_neighbor_top = back.get_path_to(action)
	hud.settings_feedback = text(footer, game.settings_notice, 15, hud.MINT)
	hud.settings_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh()
	(capture_button if is_instance_valid(capture_button) else selected).grab_focus()

func slider_row(parent: Control, id: String, title: String, help: String) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var name_label := text(heading, title, 18, Color("e4e5dc"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := text(heading, "%d%%" % (game.settings.values[id] * 100), 18, hud.MINT)
	value.custom_minimum_size.x = 60
	var slider := HSlider.new()
	slider.name = id
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = game.settings.values[id] * 100
	slider.custom_minimum_size = Vector2(420, 28)
	if "accessibility_name" in slider: slider.set("accessibility_name", title)
	for key in ["grabber", "grabber_highlight", "grabber_disabled"]: slider.add_theme_icon_override(key, KNOB)
	for item in [["slider", Color("4b5e5d")], ["grabber_area", hud.MINT], ["grabber_area_highlight", Color("f1d5a6")]]:
		var track: StyleBoxFlat = hud.style(item[1], Color.TRANSPARENT, 0)
		track.content_margin_top = 2
		track.content_margin_bottom = 2
		slider.add_theme_stylebox_override(item[0], track)
	column.add_child(slider)
	text(column, help, 14)
	slider.value_changed.connect(func(amount: float):
		value.text = "%d%%" % amount
		game.set_setting(id, amount / 100.0)
	)

func toggle_row(parent: Control, id: String, title: String, help: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description)
	text(description, title, 18, Color("e4e5dc"))
	text(description, help, 14)
	var toggle: Button = hud.button("", func(): game.set_setting(id, not game.settings.values[id]))
	toggle.name = id
	toggle.custom_minimum_size = Vector2(100, 48)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if "accessibility_name" in toggle: toggle.set("accessibility_name", title)
	row.add_child(toggle)
	toggles[id] = toggle

func selected_style(control: Button, active: bool) -> void:
	control.add_theme_stylebox_override("normal", hud.style(hud.MINT if active else Color("17282f"), Color("61756f"), 12))
	control.add_theme_stylebox_override("hover", hud.style(Color("f1d5a6") if active else Color("2b393d"), hud.MINT, 12))
	control.add_theme_color_override("font_color", hud.INK if active else Color("e4e5dc"))
	control.add_theme_color_override("font_focus_color", hud.INK if active else Color("e4e5dc"))
	control.add_theme_color_override("font_hover_color", hud.INK if active else Color("e4e5dc"))

func refresh() -> void:
	if not is_instance_valid(preview) or not is_instance_valid(preview_caption): return
	for index in range(mode_buttons.size()): selected_style(mode_buttons[index], game.settings.values.fullscreen == bool(index))
	for id in toggles:
		var active: bool = game.settings.values[id]
		toggles[id].text = "已开启" if active else "已关闭"
		selected_style(toggles[id], active)
	match game.settings_tab:
		"display":
			var output: Vector2i = game.get_viewport().get_window().size
			preview_caption.text = ("无边框全屏" if game.settings.values.fullscreen else "窗口模式") + "\n当前输出 %d × %d" % [output.x, output.y]
		"audio": preview_caption.text = "已静音 / 按 M 恢复" if game.muted else "当前输出比例"
		"keys": preview_caption.text = "主要操作 / 当前键位"
		"controller": preview_caption.text = "已连接 %d 只手柄" % Input.get_connected_joypads().size()
	preview.queue_redraw()
