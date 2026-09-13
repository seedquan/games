extends Control

const MINT := Color("e6b879")
const DISPLAY_FONT = preload("res://assets/fonts/NotoSerifCJKsc-SemiBold.otf")
const COMBAT_ACTIONS = preload("res://assets/ui/combat_actions.svg")
const ACTIONS := ["slash", "bolt", "dash", "freeze", "parry"]
const ACTION_NAMES := ["主武器", "等离子", "冲刺", "冰冻", "弹反"]
const CROSSHAIR = preload("res://assets/crosshair.svg")
const BUILD_SYMBOLS = preload("res://assets/ui/build_symbols.svg")
const INK := Color("111d22")
const MUTED := Color("afb8b5")
const BOON_COLORS := {"damage": "e8b27a", "health": "b5caa0", "speed": "92c4d0", "fire": "e7a274", "ice": "9bcbd9", "shock": "dccb83", "poison": "b2bf82", "leech": "d6a0a0", "execute": "c4aed8"}
var game
var hud_backdrop: Control
var partner_panel: VBoxContainer
var partner_vitals: Label
var partner_integrity: ProgressBar
var partner_energy: ProgressBar
var partner_loadout: Label
var skill_row: HBoxContainer
var partner_skills: Array[Label] = []
var skill_icons: Array[TextureRect] = []
var partner_skill_icons: Array[TextureRect] = []
var partner_skill_group: HBoxContainer
var first_seat: Label
var integrity: ProgressBar
var energy: ProgressBar
var vitals: Label
var sector: Label
var counters: Label
var announcement: Label
var skills: Array[Label] = []
var overlay: ColorRect
var menu_margin: MarginContainer
var dashboard: MarginContainer
var loadout: Label
var controls_hint: Label
var settings_view
var story_scene
var settings_feedback: Label
var save_notice: Label
var tutorial: Label
var boss_panel: VBoxContainer
var boss_name: Label
var boss_mark: TextureRect
var boss_integrity: ProgressBar

func build() -> void:
	get_viewport().size_changed.connect(refresh_settings_visuals)
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 16
	theme_resource.default_font = preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	theme = theme_resource
	hud_backdrop = preload("res://scripts/hud_backdrop.gd").new()
	add_child(hud_backdrop)
	hud_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dashboard = margin(self, 24)
	dashboard.add_theme_constant_override("margin_bottom", 16)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	dashboard.add_child(stack)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 30)
	stack.add_child(top)
	var status := VBoxContainer.new()
	status.custom_minimum_size.x = 260
	top.add_child(status)
	loadout = label("", 16, MINT)
	status.add_child(loadout)
	vitals = label("机体耐久  100 / 100", 18, Color("ece8d9"))
	status.add_child(vitals)
	integrity = bar(Color("b9cfac"), 10)
	status.add_child(integrity)
	energy = bar(Color("8bb5bf"), 6)
	status.add_child(energy)
	sector = label("", 18, Color("d5e8ea"))
	sector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sector.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(sector)
	counters = label("", 16, MUTED)
	counters.custom_minimum_size.x = 140
	counters.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(counters)
	partner_panel = VBoxContainer.new()
	partner_panel.custom_minimum_size.x = 260
	top.add_child(partner_panel)
	partner_loadout = label("", 16, MINT)
	partner_panel.add_child(partner_loadout)
	partner_vitals = label("", 18, Color("ece8d9"))
	partner_panel.add_child(partner_vitals)
	partner_integrity = bar(MINT, 10)
	partner_panel.add_child(partner_integrity)
	partner_energy = bar(Color("8bb5bf"), 6)
	partner_panel.add_child(partner_energy)
	partner_panel.hide()
	announcement = label("", 21, MINT)
	announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(announcement)
	save_notice = label("", 14, Color("ffd27a"))
	save_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(save_notice)
	tutorial = label("", 20, Color("ede4cc"))
	tutorial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(tutorial)
	boss_panel = VBoxContainer.new()
	boss_panel.custom_minimum_size.x = 540
	boss_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(boss_panel)
	var boss_heading := HBoxContainer.new()
	boss_heading.alignment = BoxContainer.ALIGNMENT_CENTER
	boss_panel.add_child(boss_heading)
	boss_mark = TextureRect.new()
	boss_mark.custom_minimum_size = Vector2(30, 30)
	boss_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	boss_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boss_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var boss_atlas := AtlasTexture.new()
	boss_atlas.atlas = preload("res://assets/ui/boss_signatures.svg")
	boss_atlas.region = Rect2(0, 0, 64, 64)
	boss_mark.texture = boss_atlas
	boss_heading.add_child(boss_mark)
	boss_name = label("", 18, Color("ffb2dc"))
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_heading.add_child(boss_name)
	boss_integrity = bar(Color("e68eef"), 10)
	boss_panel.add_child(boss_integrity)
	boss_panel.hide()
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(spacer)
	skill_row = HBoxContainer.new()
	skill_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skill_row.add_theme_constant_override("separation", 24)
	stack.add_child(skill_row)
	var primary_group := HBoxContainer.new()
	primary_group.add_theme_constant_override("separation", 8)
	skill_row.add_child(primary_group)
	first_seat = label("Ⅰ", 20, Color("8bb5bf"))
	primary_group.add_child(first_seat)
	build_action_strip(primary_group, skills, skill_icons)
	partner_skill_group = HBoxContainer.new()
	partner_skill_group.add_theme_constant_override("separation", 8)
	skill_row.add_child(partner_skill_group)
	partner_skill_group.add_child(label("Ⅱ", 20, MINT))
	build_action_strip(partner_skill_group, partner_skills, partner_skill_icons)
	partner_skill_group.hide()
	controls_hint = label("鼠标瞄准　·　Tab 构筑　·　Esc 暂停", 14, MUTED)
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(controls_hint)
	set_mouse_passthrough(dashboard)
	overlay = ColorRect.new()
	overlay.color = Color(0.037, 0.060, 0.070, 0.99)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_margin = margin(overlay, 90)

func build_action_strip(parent: HBoxContainer, captions: Array[Label], icons: Array[TextureRect]) -> void:
	for i in range(ACTIONS.size()):
		var item := HBoxContainer.new()
		item.custom_minimum_size = Vector2(112, 44)
		item.add_theme_constant_override("separation", 8)
		parent.add_child(item)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var atlas := AtlasTexture.new()
		atlas.atlas = COMBAT_ACTIONS
		atlas.region = Rect2(i * 48, 0, 48, 48)
		icon.texture = atlas
		item.add_child(icon)
		icons.append(icon)
		var caption := label("", 15, Color("ece8d9"))
		caption.custom_minimum_size.x = 76
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.clip_text = true
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		item.add_child(caption)
		captions.append(caption)

func update_action_strip(member, captions: Array[Label], icons: Array[TextureRect]) -> void:
	var cooldowns := [member.slash_cooldown, member.bolt_cooldown, member.dash_cooldown, member.freeze_cooldown, member.parry_cooldown]
	for i in range(ACTIONS.size()):
		var ready: bool = cooldowns[i] <= 0.0 and member.hp > 0
		var value: String = game.CONTROLS.PAD_LABELS[ACTIONS[i]] if game.coop.enabled else game.action_label(ACTIONS[i])
		if member.hp <= 0:
			value = "—"
		elif cooldowns[i] > 0:
			value = "%.1f 秒" % cooldowns[i]
		if i == 1 and member.energy < 24 and member.hp > 0:
			value = "能量不足"
			ready = false
		if i == 0 and member.weapon.drawing and member.hp > 0:
			value = "%d%%" % int(member.weapon.charge / float(member.weapon.definition.charge) * 100)
		captions[i].text = ACTION_NAMES[i] + "\n" + value
		icons[i].modulate = MINT if ready else MUTED

func set_mouse_passthrough(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		set_mouse_passthrough(child)

func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		# Input retains custom cursor textures outside the scene's lifetime.
		Input.set_custom_mouse_cursor(null)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func label(text: String, size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	set_label_color(node, color)
	return node

func set_label_color(node: Label, color: Color) -> void:
	node.set_meta("standard_font_color", color)
	style_label(node)

func style_label(node: Label) -> void:
	var enhanced: bool = game.settings.values.high_contrast
	var color: Color = node.get_meta("standard_font_color")
	node.add_theme_color_override("font_color", color.lightened(0.4) if enhanced else color)
	node.add_theme_color_override("font_outline_color", Color("0b1419"))
	node.add_theme_constant_override("outline_size", 2 if enhanced else 0)

func apply_text_contrast() -> void:
	for node in find_children("*", "Label", true, false):
		if node.has_meta("standard_font_color"):
			style_label(node)

func margin(parent: Node, amount: int) -> MarginContainer:
	var node := MarginContainer.new()
	parent.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		node.add_theme_constant_override("margin_" + side, amount)
	return node

func style(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

func bar(color: Color, height: int) -> ProgressBar:
	var node := ProgressBar.new()
	node.show_percentage = false
	node.custom_minimum_size.y = height
	node.add_theme_stylebox_override("background", style(Color("1c303c"), Color.TRANSPARENT, 0))
	node.add_theme_stylebox_override("fill", style(color, Color.TRANSPARENT, 0))
	return node

func button(text: String, callback: Callable, primary := false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(300, 58)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_stylebox_override("normal", style(MINT if primary else INK, MINT if primary else Color("34505d"), 18))
	node.add_theme_stylebox_override("hover", style(Color("f1d5a6") if primary else Color("2b393d"), MINT, 18))
	node.add_theme_stylebox_override("pressed", style(Color("d4a665"), MINT, 18))
	node.add_theme_stylebox_override("disabled", style(Color("11202b"), Color("34424b"), 18))
	node.add_theme_color_override("font_disabled_color", Color("788d95"))
	node.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), Color("f1e7cc"), 18))
	node.add_theme_color_override("font_color", INK if primary else Color("e4e5dc"))
	node.add_theme_color_override("font_hover_color", INK if primary else Color.WHITE)
	node.add_theme_color_override("font_focus_color", INK if primary else Color("e4e5dc"))
	node.add_theme_color_override("font_pressed_color", INK)
	node.add_theme_font_size_override("font_size", 17)
	node.pressed.connect(func(): game.sound.play_cue("ui", 0.12))
	node.pressed.connect(callback)
	return node

func show_menu(kind: String) -> void:
	settings_view = null
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null)
	overlay.show()
	dashboard.visible = kind != "title"
	for child in menu_margin.get_children():
		menu_margin.remove_child(child)
		child.queue_free()
	if kind == "coop_lobby":
		build_coop_lobby()
		return
	if kind == "title":
		build_title()
		return
	if kind == "settings":
		build_settings()
		return
	if kind == "help":
		build_help()
		return
	if kind == "build":
		build_run_overview()
		return
	if kind == "confirm":
		build_confirmation()
		return
	if kind == "armory":
		build_armory()
		return
	if kind == "story":
		build_story()
		return
	if kind in ["route", "shop", "rest", "workbench"]:
		build_progress_menu(kind)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 65)
	menu_margin.add_child(row)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	row.add_child(content)
	content.add_child(label("穹灯空间站 / 应急救援终端", 14, MINT))
	var title := "深渊\n协议"
	var description := "穹灯站失联七天，三百一十二人仍困在休眠舱。\n穿过五个区域、三十个舱室，解除封锁，带他们回家。"
	match kind:
		"paused":
			title = "连接\n已暂停"
			description = "休整片刻，七号。恢复连接后继续救援。\n退出或返回船坞后，将从本舱入口的存档继续。"
		"reward":
			title = "选择强化协议"
			description = "舱室已清理，选择一项全队共享强化。\n两人各恢复十二点耐久，并补满能量。" if game.coop.enabled else "舱室已清理，选择一项本局强化。\n每次选择还会恢复十二点耐久，并补满能量。"
		"dead":
			title = "机体\n已离线"
			description = "最后的维修记录已传回船坞。新机体将带着它再次出发。"
		"victory":
			title = "救援\n已完成"
			description = "封锁解除，三百一十二名乘客正在归航。"
	var heading := label(title, 42 if kind == "reward" else 54, Color("ece8d9"))
	heading.add_theme_font_override("font", DISPLAY_FONT)
	content.add_child(heading)
	content.add_child(label(description, 18, MUTED))
	if kind == "reward":
		var choices := HBoxContainer.new()
		choices.add_theme_constant_override("separation", 15)
		content.add_child(choices)
		for i in range(game.boon_choices.size()):
			var boon: Dictionary = game.boon_choices[i]
			var details: String = upgrade_details(boon, game.player)
			if game.coop.enabled:
				var partner_details: String = upgrade_details(boon, game.companion)
				if partner_details != details:
					details = "一号席：" + details + "\n二号席：" + partner_details
			var option := button("%d / %s\n\n%s\n\n%s" % [i + 1, boon.tag, boon.name, details], game.choose_boon.bind(i))
			option.tooltip_text = option.text
			if "accessibility_name" in option: option.set("accessibility_name", option.text)
			option.text = ""
			option.custom_minimum_size = Vector2(350, 360 if game.coop.enabled else 260)
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.add_theme_font_size_override("font_size", 16)
			var accent := Color(BOON_COLORS.get(boon.stat, "e6b879"))
			var card := style(Color("17262c"), Color(accent, 0.5), 20)
			card.border_width_top = 4
			option.add_theme_stylebox_override("normal", card)
			option.add_theme_stylebox_override("hover", style(Color("27383b"), accent, 20))
			# Child labels retain their light colors while the card is held down.
			var pressed_card := style(Color("203036"), accent, 20)
			option.add_theme_stylebox_override("pressed", pressed_card)
			option.add_theme_stylebox_override("hover_pressed", pressed_card)
			choices.add_child(option)
			var inset := margin(option, 22)
			var card_content := VBoxContainer.new()
			card_content.alignment = BoxContainer.ALIGNMENT_CENTER
			card_content.add_theme_constant_override("separation", 14)
			inset.add_child(card_content)
			card_content.add_child(label("%02d  /  %s" % [i + 1, boon.tag], 14, accent))
			var card_title := label(boon.name, 28, Color("ece8d9"))
			card_title.add_theme_font_override("font", DISPLAY_FONT)
			card_content.add_child(card_title)
			var effect_text := label(details, 16, MUTED)
			effect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card_content.add_child(effect_text)
			set_mouse_passthrough(inset)
			if i == 0:
				option.grab_focus()
		var shortcuts: Array[String] = []
		for index in range(game.boon_choices.size()): shortcuts.append(str(index + 1))
		var footer := HBoxContainer.new()
		content.add_child(footer)
		var hint := label("点击卡片，或按 " + " / ".join(shortcuts) + " 选择", 13, MUTED)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(hint)
		add_build_button(footer)
	else:
		if kind in ["dead", "victory"]:
			content.add_child(label("抵达第 %02d 舱　/　清除 %d 个目标　/　用时 %s\n本局已保存 %d 枚核心　/　航线编号 %d" % [game.room, game.kills, elapsed_text(), game.earned_cores, game.run_seed], 15, MINT))
		var can_continue: bool = kind == "title" and not game.profile.checkpoint.is_empty()
		var action_caption := "继续救援 / 第 %02d 舱" % game.profile.checkpoint.room.depth if can_continue else "开始救援 / 回车"
		var action := button("恢复连接 / Esc" if kind == "paused" else action_caption, game.resume_run if kind == "paused" else game.continue_saved_run if can_continue else game.request_new_run, true)
		action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var actions := HBoxContainer.new()
		content.add_child(actions)
		actions.add_child(action)
		if kind == "paused": add_build_button(actions)
		action.grab_focus()
		if can_continue:
			var fresh := button("开始新的救援", game.start_single_rescue)
			fresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			content.add_child(fresh)
		if kind == "paused":
			var restart := button("重新派遣机体", game.request_new_run)
			restart.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			content.add_child(restart)
			var retreat := button("保存并返回船坞", game.abandon_to_title)
			retreat.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			content.add_child(retreat)
		else:
			var utility_row := HBoxContainer.new()
			utility_row.add_theme_constant_override("separation", 12)
			content.add_child(utility_row)
			var armory := button("双人装备 / 重新配对" if game.coop.enabled else "武器库 / " + game.WEAPONS.find(game.selected_weapon).name, game.open_coop if game.coop.enabled else game.open_armory)
			armory.custom_minimum_size.x = 290
			armory.add_theme_font_size_override("font_size", 14)
			utility_row.add_child(armory)
			var workbench := button("工作台 / %d 核心" % game.profile.cores, game.open_workbench)
			workbench.custom_minimum_size.x = 270
			workbench.add_theme_font_size_override("font_size", 14)
			utility_row.add_child(workbench)
		var support := HBoxContainer.new()
		content.add_child(support)
		if kind in ["dead", "victory"]:
			var dock := button("返回船坞", game.leave_result)
			dock.custom_minimum_size = Vector2(150, 50)
			support.add_child(dock)
		for item in [["设置", game.open_settings], ["操作指南", game.open_help], ["退出游戏", game.request_quit]]:
			var option := button(item[0], item[1])
			option.custom_minimum_size = Vector2(140, 50)
			option.flat = true
			support.add_child(option)
		add_fullscreen_button(support)
		content.add_child(label("移动、瞄准、闪避，寻找封锁系统的破绽。", 14, MUTED))
		var art_column := VBoxContainer.new()
		art_column.alignment = BoxContainer.ALIGNMENT_CENTER
		art_column.custom_minimum_size.x = 360
		row.add_child(art_column)
		var art := preload("res://scripts/station_portrait.gd").new()
		art.custom_minimum_size = Vector2(360, 430)
		art_column.add_child(art)
		var art_caption := "穹灯空间站 / 七号通信链路"
		if kind == "victory":
			art_caption = "救援链路已恢复 / 归航程序启动"
		elif kind == "dead":
			art_caption = "维修记录已收回 / 等待再次派遣"
		var caption := label(art_caption, 15, MINT)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_column.add_child(caption)
	if kind == "title":
		content.add_child(label("十八种武器 / 单人救援　·　版本 " + ProjectSettings.get_setting("application/config/version", "0.9.0"), 12, Color("617e8b")))
	if not game.save_warning.is_empty():
		var warning := label(game.save_warning, 13, Color("ffba79"))
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(warning)

func build_title() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	menu_margin.add_child(row)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 600
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	row.add_child(content)
	content.add_child(label("穹灯空间站　／　应急救援任务", 17, MINT))
	var title := label("深渊协议", 82, Color("ece8d9"))
	title.add_theme_font_override("font", DISPLAY_FONT)
	content.add_child(title)
	var subtitle := label("失联的第七天，仍有人等待归航。", 23, Color("d4d7c9"))
	content.add_child(subtitle)
	var premise := label("你是维修机器人七号。\n穿过五大区域，解除封锁，带三百一十二人回家。", 18, MUTED)
	premise.add_theme_constant_override("line_spacing", 9)
	content.add_child(premise)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	content.add_child(gap)
	var can_continue: bool = not game.profile.checkpoint.is_empty()
	var action := button("继续救援　／　第 %02d 舱" % game.profile.checkpoint.room.depth if can_continue else "开始救援　→", game.continue_saved_run if can_continue else game.start_single_rescue, true)
	action.custom_minimum_size = Vector2(450, 64)
	action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(action)
	action.grab_focus()
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 12)
	content.add_child(modes)
	if can_continue:
		var fresh := button("开始新的救援", game.start_single_rescue)
		fresh.custom_minimum_size = Vector2(242, 48)
		fresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		modes.add_child(fresh)
	var together := button("双人手柄救援　→", game.open_coop)
	together.custom_minimum_size = Vector2(242, 48)
	together.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	modes.add_child(together)
	var equipment := HBoxContainer.new()
	equipment.add_theme_constant_override("separation", 12)
	content.add_child(equipment)
	for item in [["武器库 · " + game.WEAPONS.find(game.selected_weapon).name, game.open_armory], ["工作台 · %d 核心" % game.profile.cores, game.open_workbench]]:
		var option := button(item[0], item[1])
		option.custom_minimum_size = Vector2(242, 54)
		equipment.add_child(option)
	var support := HBoxContainer.new()
	support.add_theme_constant_override("separation", 8)
	content.add_child(support)
	for item in [["设置", game.open_settings], ["操作指南", game.open_help], ["退出", game.request_quit]]:
		var option := button(item[0], item[1])
		option.flat = true
		option.custom_minimum_size = Vector2(140, 42)
		support.add_child(option)
	add_fullscreen_button(support)
	content.add_child(label("单人 / 本地双人　·　十八种武器　·　版本 " + ProjectSettings.get_setting("application/config/version", "0.9.0"), 14, MUTED))
	if not game.save_warning.is_empty():
		var warning := label(game.save_warning, 16, MINT)
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(warning)
	var art_column := VBoxContainer.new()
	art_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(art_column)
	var art := preload("res://scripts/station_portrait.gd").new()
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_column.add_child(art)
	var caption := label("穹灯 / 轨道栖居站\n生命维持处于低功耗状态", 17, MUTED)
	caption.add_theme_constant_override("line_spacing", 6)
	art_column.add_child(caption)

func route_map(parent: Node) -> void:
	var chapter := clampi((game.room - 1) / 6, 0, game.run_length / 6 - 1)
	var chapters := HBoxContainer.new()
	chapters.add_theme_constant_override("separation", 16)
	parent.add_child(chapters)
	for index in range(game.run_length / 6):
		var title: String = game.ROOMS.CHAPTERS.REGIONS[index].name if game.campaign_version == 2 else ["失联空间站", "下层熔炉区"][index]
		var mark := "已通过" if index < chapter else "当前区域" if index == chapter else "未抵达"
		var region := label("%d / %s\n%s" % [index + 1, title, mark], 15, MINT if index == chapter else MUTED)
		region.custom_minimum_size.x = 142
		chapters.add_child(region)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	for depth in range(chapter * 6 + 1, mini(chapter * 6 + 7, game.run_length + 1)):
		var type: String = game.route_history[depth - 1] if depth <= game.route_history.size() else ("boss" if depth % 6 == 0 else "unknown")
		var marks := {"combat": "战", "elite": "精", "shop": "补", "rest": "修", "boss": "守", "unknown": "·"}
		var node := label("%02d\n%s" % [depth, marks[type]], 16, MINT if depth <= game.room else MUTED)
		node.custom_minimum_size = Vector2(66, 48)
		node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(node)
	parent.add_child(label("战：战斗　精：精英　补：补给　修：维修　守：守卫", 12, MUTED))

func build_progress_menu(kind: String) -> void:
	if kind == "workbench":
		dashboard.hide()
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12 if kind == "route" else 22)
	menu_margin.add_child(column)
	var titles := {"route": "选择前进路线", "shop": "补给交换站", "rest": "机体修复完成", "workbench": "船坞工作台"}
	column.add_child(label("船坞 / " + titles[kind], 40, Color("e7f3f0")))
	if kind == "workbench":
		column.add_child(label("已保存 %d 枚核心　/　派遣 %d 次　/　成功救援 %d 次\n技术升级永久保留，下一次派遣时生效。" % [game.profile.cores, game.profile.runs, game.profile.wins], 18, MINT))
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 16)
		column.add_child(cards)
		for item in game.PROGRESSION.UPGRADES:
			var level: int = game.profile.upgrades[item.id]
			var cost: int = game.profile.upgrade_cost(item.id)
			var price := "已达最高级" if level >= 5 else "%d 枚核心" % cost
			var option := button("%s\n等级 %d / 5\n\n%s\n\n%s" % [item.name, level, item.description, price], game.buy_meta.bind(item.id))
			option.custom_minimum_size = Vector2(375, 200)
			option.add_theme_font_size_override("font_size", 15)
			option.disabled = level >= 5 or game.profile.cores < cost
			cards.add_child(option)
		var back := button("返回船坞", game.workbench_back, true)
		column.add_child(back)
		back.grab_focus()
		if not game.save_warning.is_empty():
			column.add_child(label(game.save_warning, 14, Color("ffba79")))
		return
	route_map(column)
	var health := "耐久 %d / %d" % [game.player.hp, game.player.max_hp]
	if game.coop.enabled and is_instance_valid(game.companion):
		health = "一号耐久 %d / %d　·　二号耐久 %d / %d" % [game.player.hp, game.player.max_hp, game.companion.hp, game.companion.max_hp]
	column.add_child(label("第 %02d / %02d 舱　·　%s　·　废料 %d　·　已保存核心 %d" % [game.room, game.run_length, health, game.scrap, game.profile.cores], 16, MINT))
	if kind == "route":
		column.add_child(label("舱门标出下一战的地形与奖励方向。选择路线后，奖励预告保持不变。", 17, MUTED))
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 20)
		column.add_child(cards)
		for i in range(game.route_choices.size()):
			var destination: Dictionary = game.route_choices[i]
			var type: Dictionary = game.ROOMS.TYPES[destination.kind]
			var reward: Dictionary = game.ROOMS.reward_for(destination)
			var card := VBoxContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.add_theme_constant_override("separation", 0)
			cards.add_child(card)
			var preview = preload("res://scripts/room_preview.gd").new()
			preview.room = destination
			preview.custom_minimum_size = Vector2(520, 118)
			card.add_child(preview)
			var subtitle: String = destination.get("tactic", destination.name)
			var reward_text: String = reward.description if destination.has("reward") else type.description
			if destination.kind == "elite": reward_text += "\n精英守卫 · 舱室废料与核心双倍"
			var option := button("%d / %s · %s\n%s\n\n%s\n%s" % [i + 1, type.title, reward.name, destination.name, subtitle, reward_text], game.choose_route.bind(i))
			option.custom_minimum_size = Vector2(520, 184)
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.add_theme_font_size_override("font_size", 15)
			option.add_theme_stylebox_override("normal", style(INK, Color(type.color), 18))
			card.add_child(option)
			if i == 0:
				option.grab_focus()
		column.add_child(label("点击路线，或按 1 / 2 前进", 13, MUTED))
	elif kind == "shop":
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 16)
		column.add_child(cards)
		for i in range(game.shop_stock.size()):
			var item: Dictionary = game.shop_stock[i]
			var price: String = "已购完" if item.id in game.purchased else "%d 份废料" % item.cost
			var description: String = ("全队：" if game.coop.enabled else "") + item.description
			if game.campaign_version >= 2 and item.id != "repair":
				description = upgrade_details({"stat": item.id}, game.player)
				if game.coop.enabled:
					var partner_details := upgrade_details({"stat": item.id}, game.companion)
					if partner_details != description:
						description = "一号：" + description + "\n二号：" + partner_details
			var option := button("%d / %s\n\n%s\n\n%s" % [i + 1, item.name, description, price], game.buy_item.bind(i))
			option.custom_minimum_size = Vector2(380, 200)
			option.add_theme_font_size_override("font_size", 14)
			option.disabled = not game.can_buy(i)
			cards.add_child(option)
		column.add_child(label("每项补给限购一次。机体受损时才可购买维修。", 14, MUTED))
		var depart := button("继续救援", game.leave_supply, true)
		column.add_child(depart)
		depart.grab_focus()
	else:
		column.add_child(label("已恢复最大耐久的百分之三十五，最高不超过上限。\n能量已补满。每次抵达维修站只执行一次修复。", 21, MUTED))
		var depart := button("继续救援", game.leave_supply, true)
		column.add_child(depart)
		depart.grab_focus()
	add_build_button(column)

func upgrade_details(boon: Dictionary, member) -> String:
	var details: String = game.PROGRESSION.describe(boon, member, game.campaign_version)
	if boon.stat in ["damage", "tuning"]:
		var changes: Dictionary = game.PROGRESSION.effects(boon, member, game.campaign_version)
		return game.BUILD_INFO.damage_comparison(member, changes.damage) + "\n基础攻击 %.1f → %.1f\n主武器与等离子弹同步增强。" % [member.damage, member.damage + changes.damage]
	if boon.stat in game.PROGRESSION.ELEMENTS:
		var rank := int(member.enchantments.get(boon.stat, 0))
		var next := mini(3, rank + 1)
		var innate: bool = member.weapon.definition.get("element", "") == boon.stat
		var prefix := "符文 %d → %d 级" % [rank, next] if rank < 3 else "符文已满级"
		if innate: prefix += " · 武器自带同元素"
		var hint: String = game.BUILD_INFO.reaction_hint(boon.stat, game.campaign_version)
		return prefix + "\n" + game.BUILD_INFO.rune_comparison(boon.stat, rank, innate, game.campaign_version) + ("\n" + hint if not hint.is_empty() else "")
	return details

func add_build_button(parent: Control) -> void:
	var inspect := button("局内构筑 / Tab", game.open_build)
	inspect.custom_minimum_size = Vector2(225, 42)
	inspect.add_theme_font_size_override("font_size", 16)
	parent.add_child(inspect)

func menu_buttons() -> Array[BaseButton]:
	var result: Array[BaseButton] = []
	for node in menu_margin.find_children("*", "BaseButton", true, false):
		if not node.disabled and node.is_visible_in_tree(): result.append(node)
	return result

func restore_menu_focus(index: int, expected_state := "") -> void:
	var buttons := menu_buttons()
	if game.state == (game.build_return if expected_state.is_empty() else expected_state) and index >= 0 and index < buttons.size():
		buttons[index].grab_focus()

func build_run_overview() -> void:
	var member = game.team()[clampi(game.build_seat, 0, game.team().size() - 1)]
	var column := utility_column("局内构筑 / 第 %02d 舱" % game.room)
	var seats := HBoxContainer.new()
	column.add_child(seats)
	for seat in range(game.team().size()):
		var tab := button(("一号席" if seat == 0 else "二号席") + " · " + game.team()[seat].weapon.definition.name, game.choose_build_seat.bind(seat), seat == game.build_seat)
		tab.custom_minimum_size = Vector2(300, 48)
		seats.add_child(tab)
		if seat == game.build_seat: tab.grab_focus()
	var scroll := ScrollContainer.new()
	scroll.name = "BuildScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var definition: Dictionary = member.weapon.definition
	build_info_card(grid, definition.name, game.BUILD_INFO.attack_text(definition, member.damage) + "\n" + definition.description.replace("\n", " ") + "\n以上为常态直接伤害；元素、终结与临时增伤另计。", MINT, 0)
	var status := "耐久 %.0f / %.0f　·　能量 %.0f / 100\n移动速度 %.0f　·　冲刺冷却 %.2f 秒\n能量每秒回复 %.0f　·　基础攻击 %.1f" % [member.hp, member.max_hp, member.energy, member.move_speed, member.dash_recharge, member.energy_regen, member.damage]
	if member.empowered > 0: status += "\n临时增伤 50%% · 剩余 %.1f 秒" % member.empowered
	if member.hp <= 0: status += "\n机体离线，等待队友修复。"
	build_info_card(grid, "机体状态", status, MINT, 1)
	for id in game.PROGRESSION.ELEMENTS:
		var rank := int(member.enchantments.get(id, 0))
		var innate: bool = definition.get("element", "") == id
		build_info_card(grid, game.BUILD_INFO.element_heading(id, rank, innate, game.campaign_version), game.BUILD_INFO.element_detail(id, rank, innate, game.campaign_version), Color(BOON_COLORS[id]), 2 + game.PROGRESSION.ELEMENTS.find(id), rank)
	var diagram = preload("res://assets/ui/element_combos.svg") if game.BUILD_INFO.has_reaction(member) else null
	build_info_card(grid, "战斗联动", "\n".join(game.BUILD_INFO.synergies(member)), MINT, 8, -1, diagram)
	build_info_card(grid, "本局成长", "废料 %d · 本局已传回 %d 枚核心\n船坞升级在派遣时已计入机体属性。\n祝福由全队共享，实际收益取决于各自武器与属性。" % [game.scrap, game.earned_cores], MINT, 9)
	var back := button("返回原界面 / Esc · Tab", game.close_build)
	column.add_child(back)

func build_info_card(parent: Control, heading: String, body: String, accent: Color, symbol: int, rank := -1, diagram: Texture2D = null) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 460
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.focus_mode = Control.FOCUS_ALL
	var normal := style(INK, Color(accent, 0.45), 16)
	var focused := style(Color("203036"), accent, 16)
	panel.add_theme_stylebox_override("panel", normal)
	panel.focus_entered.connect(func(): panel.add_theme_stylebox_override("panel", focused))
	panel.focus_exited.connect(func(): panel.add_theme_stylebox_override("panel", normal))
	if "accessibility_name" in panel: panel.set("accessibility_name", heading + "。" + body)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	if diagram != null:
		var illustration := TextureRect.new()
		illustration.texture = diagram
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		illustration.custom_minimum_size.y = 126
		illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(illustration)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var icon := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = BUILD_SYMBOLS
	atlas.region = Rect2(symbol * 64, 0, 64, 64)
	icon.texture = atlas
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = accent
	header.add_child(icon)
	var title := label(heading, 19, accent)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if rank >= 0:
		for level in range(3):
			var mark := ColorRect.new()
			mark.custom_minimum_size = Vector2(8, 18)
			mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			mark.color = accent if level < rank else Color("34424b")
			header.add_child(mark)
	var detail := label(body, 17, MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail)
	set_mouse_passthrough(content)

func build_armory() -> void:
	dashboard.hide()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	menu_margin.add_child(column)
	column.add_child(label("船坞 / 武器库", 34, Color("e7f3f0")))
	column.add_child(label("为下一次救援选择武器。全部基础形态均可自由使用，战斗中不能换装。", 16, MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var focus_button: Button
	for form in game.WEAPONS.FORMS:
		var selected: bool = form.id == game.selected_weapon
		var text: String = ("【已装备】" if selected else "") + form.name + "\n" + game.WEAPONS.family_label(form.family)
		var option := button(text, game.select_weapon.bind(form.id), selected)
		option.custom_minimum_size = Vector2(350, 68)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_font_size_override("font_size", 14)
		option.add_theme_stylebox_override("normal", style(MINT if selected else INK, Color(form.color), 10))
		grid.add_child(option)
		if selected:
			focus_button = option
	var chosen: Dictionary = game.WEAPONS.find(game.selected_weapon)
	column.add_child(label(chosen.name + "  /  " + chosen.description.replace("\n", " "), 16, Color(chosen.color)))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	actions.add_child(button("带上装备，开始救援", game.request_new_run, true))
	actions.add_child(button("返回 / Esc", game.armory_back))
	if focus_button:
		focus_button.grab_focus()

func build_story() -> void:
	dashboard.hide()
	story_scene = null
	if game.story_id in ["awakening", "calibration", "ending"]:
		build_animated_story()
		return
	var beat: Dictionary = game.STORY.BEATS[game.story_id]
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	menu_margin.add_child(column)
	column.add_child(label("穹灯空间站 · 维修日志", 17, MINT))
	column.add_child(label(beat.chapter, 40, Color("e7f3f0")))
	column.add_child(label(beat.speaker, 18, Color("ffd27a")))
	var text := label(beat.body, 23, Color("bfd1d4"))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	var proceed := button(beat.action, game.continue_story, true)
	proceed.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(proceed)
	proceed.grab_focus()

func build_animated_story() -> void:
	var beat: Dictionary = game.STORY.BEATS[game.story_id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	menu_margin.add_child(row)
	var artwork := VBoxContainer.new()
	artwork.custom_minimum_size.x = 520
	artwork.add_theme_constant_override("separation", 8)
	row.add_child(artwork)
	story_scene = preload("res://scripts/story_scene.gd").new()
	story_scene.name = "StoryScene"
	story_scene.beat = game.story_id
	story_scene.motion_enabled = game.settings.values.story_motion
	story_scene.auto_pause_enabled = game.auto_pause_enabled
	story_scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	artwork.add_child(story_scene)
	var playback := button("暂停", story_scene.toggle_playback)
	playback.name = "StoryPlayback"
	playback.custom_minimum_size = Vector2(132, 42)
	playback.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	playback.flat = true
	playback.expand_icon = true
	playback.add_theme_constant_override("icon_max_width", 18)
	playback.visible = story_scene.motion_enabled
	artwork.add_child(playback)
	var scene = story_scene
	var refresh_playback := func():
		var frame := 2 if scene.elapsed >= scene.DURATION else (1 if scene.paused else 0)
		var icon := AtlasTexture.new()
		icon.atlas = preload("res://assets/story/playback.svg")
		icon.region = Rect2(frame * 48, 0, 48, 48)
		playback.icon = icon
		playback.text = ["暂停", "播放", "重播"][frame]
		playback.tooltip_text = playback.text + "过场动画"
	scene.playback_changed.connect(refresh_playback)
	refresh_playback.call()
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 20)
	row.add_child(column)
	var title := label(beat.chapter, 34, Color("ece8d9"))
	title.add_theme_font_override("font", DISPLAY_FONT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var speaker := label(beat.speaker, 16, MINT)
	speaker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(speaker)
	var scroll := ScrollContainer.new()
	scroll.name = "StoryText"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	column.add_child(scroll)
	var body := label(beat.body, 21, Color("bfd1d4"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("line_spacing", 5)
	scroll.add_child(body)
	var proceed := button(beat.action, game.continue_story, true)
	proceed.name = "StoryContinue"
	column.add_child(proceed)
	proceed.focus_neighbor_top = proceed.get_path_to(scroll)
	scroll.focus_neighbor_bottom = scroll.get_path_to(proceed)
	if playback.visible:
		proceed.focus_neighbor_left = proceed.get_path_to(playback)
		playback.focus_neighbor_right = playback.get_path_to(proceed)
	proceed.grab_focus()

func utility_column(title: String) -> VBoxContainer:
	dashboard.hide()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	menu_margin.add_child(column)
	column.add_child(label(title, 36, Color("e7f3f0")))
	return column

func build_settings() -> void:
	settings_view = preload("res://scripts/settings_menu.gd").new()
	settings_view.game = game
	settings_view.hud = self
	settings_view.build()

func refresh_settings_visuals() -> void:
	if not is_instance_valid(menu_margin): return
	if settings_view != null:
		settings_view.refresh()
	for option in menu_margin.find_children("FullscreenAction", "Button", true, false):
		option.text = "退出全屏" if game.settings.values.fullscreen else "全屏"

func add_fullscreen_button(parent: Control, width := 140) -> void:
	var option := button("", func(): game.set_setting("fullscreen", not game.settings.values.fullscreen))
	option.name = "FullscreenAction"
	option.custom_minimum_size = Vector2(width, 42)
	option.icon = preload("res://scripts/settings_menu.gd").symbol(4)
	option.expand_icon = true
	option.add_theme_constant_override("icon_max_width", 22)
	option.add_theme_color_override("icon_pressed_color", INK)
	option.tooltip_text = "无边框全屏 / F11"
	parent.add_child(option)
	refresh_settings_visuals()

func build_help() -> void:
	var column := utility_column("七号 · 救援操作指南")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	scroll.follow_focus = true
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 22)
	scroll.add_child(content)
	content.add_child(preload("res://scripts/danger_guide.gd").new())
	for section in [
		["先观察，再出手", "方向键或自定义移动键控制机体；鼠标决定攻击方向。\n按住主武器连续攻击；轨道炮和长弓需要按住蓄力、松开发射。"],
		["看懂危险，保住机体", "红色扇区覆盖近身攻击范围；带箭头的射线预示弹道方向。\n首领周围的三环预示地面锁定，随后出现的橙色地面圈才是爆炸落点。\n冲刺有短暂无敌时间；弹反只挡短窗口内的攻击，地面爆炸需要躲开。\n完美闪避返还冲刺并短暂增伤。冰冻新星适合被包围时脱身。"],
		["沿途补给，完成救援", "等离子弹消耗能量，能量会自动恢复；主武器不消耗能量。\n废料用于本局商店，技术核心用于船坞永久升级。\n战斗后选择一项强化，再决定下一舱的路线。维修与补给路线更适合休整。"],
		["双人同屏", "标题页选择双人手柄救援，两只手柄分别按下键加入，十字键左右选武器，菜单键出发。\n两人共享镜头、废料与强化，各自保留武器和耐久；没有友军伤害。\n队友离线时，靠近并停留三秒修复，移动或受击会中断；清舱也会救回队友。\n共享菜单由一号席操作，一号离线时二号接管；两人均可暂停。\n续档和断线后重新认领手柄席位，设备编号变化不影响进度。"],
		["手柄操作", "左摇杆移动，右摇杆瞄准；右肩键主武器、左肩键等离子。\n右侧四键：下键冲刺、左键冰冻、右键弹反；菜单键暂停。\n菜单使用十字键选择、下键确认、右键返回。手柄断开会自动暂停。"],
	]:
		content.add_child(label(section[0], 23, MINT))
		var body := label(section[1], 20, Color("bfd1d4"))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.focus_mode = Control.FOCUS_ALL
		content.add_child(body)
	var back := button("返回", func(): game.show_menu(game.info_return), true)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(back)
	back.grab_focus()

func build_confirmation() -> void:
	var column := utility_column("确认操作")
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var text := {
		"restart": "重新派遣会结束当前救援。\n本局的武器强化和废料会清空，已传回船坞的技术核心保留。",
		"abandon": "返回船坞会结束当前救援。\n本局的武器强化和废料会清空，已传回船坞的技术核心保留。",
		"quit": "退出后可在船坞继续这次救援。\n战斗中的进度会回到本舱入口的存档；已保存的强化和交易保留。",
	}
	column.add_child(label(text.get(game.pending_action, ""), 24, Color("bfd1d4")))
	var back := button("取消，保留当前救援", game.cancel_confirmation, true)
	column.add_child(back)
	back.grab_focus()
	column.add_child(button("确认继续", game.accept_confirmation))

func hide_menu() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(CROSSHAIR, Input.CURSOR_ARROW, Vector2(16, 16))
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	overlay.hide()
	dashboard.show()

func elapsed_text() -> String:
	return "%02d:%02d" % [int(game.elapsed) / 60, int(game.elapsed) % 60]

func update_status() -> void:
	if DisplayServer.get_name() != "headless":
		var cursor_mode := Input.MOUSE_MODE_HIDDEN if game.using_gamepad and not overlay.visible else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != cursor_mode:
			Input.mouse_mode = cursor_mode
	hud_backdrop.visible = dashboard.visible and not overlay.visible
	save_notice.text = game.save_warning
	save_notice.visible = not game.save_warning.is_empty()
	boss_panel.visible = is_instance_valid(game.active_boss) and game.state == "playing"
	if boss_panel.visible:
		var boss = game.active_boss
		boss_mark.visible = game.campaign_version >= 2
		(boss_mark.texture as AtlasTexture).region = Rect2(clampi((game.room - 1) / 6, 0, 4) * 64, 0, 64, 64)
		var phase := "过载阶段" if boss.kind == "boss" and boss.hp < boss.max_hp * 0.5 else "防御阶段"
		boss_name.text = game.room_data.get("name", "深渊主控体" if boss.kind == "boss" else "封锁卫士") + "　/　" + phase
		if boss.attacking:
			boss_name.text += "　·　" + str(boss.ATTACK_LABELS[boss.next_attack()])
		boss_integrity.max_value = boss.max_hp
		boss_integrity.value = boss.hp
	partner_panel.visible = game.coop.enabled and is_instance_valid(game.companion)
	controls_hint.text = "摇杆瞄准　·　菜单键 暂停 / 构筑" if game.using_gamepad else "鼠标瞄准　·　Tab 构筑　·　Esc 暂停"
	if game.muted:
		controls_hint.text += "　【已静音】"
	announcement.visible = game.announcement_left > 0.0 and game.state == "playing"
	if not is_instance_valid(game.player):
		return
	var player = game.player
	var aim_label: String = {"mouse": "鼠标瞄准", "stick": "摇杆瞄准", "assist": "辅助锁定", "heading": "移动朝向"}.get(player.aim_mode, "瞄准")
	controls_hint.text = ("%s　·　菜单键 暂停 / 构筑" if game.using_gamepad else "%s　·　Tab 构筑　·　Esc 暂停") % aim_label
	if game.muted:
		controls_hint.text += "　【已静音】"
	tutorial.visible = game.state == "playing" and game.room == 1 and game.elapsed < 40 and game.settings.values.tutorial and player.tutorial_step < 3
	if tutorial.visible:
		var tips := ["方向键移动，鼠标指向目标" if not game.using_gamepad else "左摇杆移动，右摇杆指向目标", "按住 %s 攻击，清理封锁守卫" % game.action_label("slash"), "出现红色前摇时，按 %s 冲刺脱离" % game.action_label("dash")]
		tutorial.text = "七号自检 %d / 3　·　%s" % [player.tutorial_step + 1, tips[player.tutorial_step]]
	integrity.max_value = player.max_hp
	integrity.value = player.hp
	energy.value = player.energy
	vitals.text = "耐久 %d / %d　能量 %d" % [player.hp, player.max_hp, player.energy]
	sector.text = "%02d / %02d 舱" % [game.room, game.run_length]
	if not boss_panel.visible:
		sector.text += "　" + str(game.room_data.get("name", ""))
	if game.state == "playing" and game.encounter.waves.size() > 1:
		sector.text += "\n增援 %d / %d" % [game.encounter.wave, game.encounter.waves.size()]
	counters.text = "废料 %d\n核心 %d" % [game.scrap, game.profile.cores]
	loadout.text = player.weapon.definition.name
	update_action_strip(player, skills, skill_icons)
	update_coop_status()

func build_coop_lobby() -> void:
	dashboard.hide()
	var column := utility_column("双人救援 / 连接机体")
	column.add_child(label("两只手柄分别按下键加入；先加入为一号席，后加入为二号席。", 20, MUTED))
	column.add_child(label("十字键左右选武器，菜单键出发。右键退出席位，再按返回。" if not game.coop.restoring else "重新配对只恢复控制权，武器、耐久与进度保持原样。菜单键返回救援。", 18, MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	for seat in range(2):
		var color := Color("8bb5bf") if seat == 0 else MINT
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", style(INK, color, 28))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(panel)
		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_theme_constant_override("separation", 24)
		panel.add_child(card)
		card.add_child(label("一号席 / 七号" if seat == 0 else "二号席 / 协作机体", 28, color))
		var joined: bool = game.coop.devices[seat] >= 0
		card.add_child(label("手柄已连接" if joined else "等待手柄 · 按下键加入", 22, Color("ece8d9")))
		var chosen: Dictionary = game.WEAPONS.find(game.coop.weapons[seat])
		card.add_child(label(chosen.name, 40, color))
		card.add_child(label(chosen.description, 18, MUTED))
		card.add_child(label("←  十字键选择武器  →" if joined and not game.coop.restoring else "独立移动、瞄准、攻击与技能", 16, MUTED))
	column.add_child(label("共享废料与强化 · 无友军伤害 · 队友离线后靠近停留三秒修复 · 清舱自动救回队友", 17, MINT))
	column.add_child(label("菜单键开始" if game.coop.ready_to_play() else "等待两只手柄就绪", 24, Color("ece8d9")))
	column.add_child(button("返回 / Esc", func(): game.show_menu(game.coop.return_state)))

func update_coop_status() -> void:
	var active: bool = game.coop.enabled and is_instance_valid(game.companion)
	partner_skill_group.visible = active
	first_seat.visible = active
	if not active:
		return
	var partner = game.companion
	loadout.text = "Ⅰ　" + game.player.weapon.definition.name
	partner_loadout.text = "Ⅱ　" + partner.weapon.definition.name
	partner_vitals.text = "耐久 %d / %d　能量 %d" % [partner.hp, partner.max_hp, partner.energy]
	partner_integrity.max_value = partner.max_hp
	partner_integrity.value = partner.hp
	partner_energy.value = partner.energy
	for member in game.team():
		if member.hp <= 0:
			var target: Label = vitals if member.seat == 0 else partner_vitals
			target.text = "离线 · 靠近修复 %d%%" % int(member.revive_progress / 3.0 * 100)
	update_action_strip(partner, partner_skills, partner_skill_icons)
	controls_hint.text = "摇杆瞄准　·　菜单键 暂停 / 构筑" + ("　【已静音】" if game.muted else "")
	tutorial.visible = false
