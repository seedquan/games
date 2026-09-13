extends SceneTree
## Critical signals survive the compact HUD in solo and cooperative play.
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for i in range(count): await physics_frame
	await process_frame

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	check(root.get_texture().get_image().save_png("res://builds/qa/hud-" + name + ".png") == OK, "Save native HUD evidence")

func reset_case(cooperative := false) -> void:
	game.coop.enabled = cooperative
	game.coop.devices.assign([1, 3] if cooperative else [-1, -1])
	game.coop.weapons.assign(["rail", "frost"])
	game.selected_weapon = "rail"
	game.configure_input()
	game.start_run(931)
	game.encounter.cancel()
	game.room_awarded = true
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	for member in game.team():
		member.set_physics_process(false)
		member.position = Vector2(800 + member.seat * 90, 650)
	game.elapsed = 60
	game.announcement_left = 0
	await frames(70 if DisplayServer.get_name() != "headless" else 3)

func bounds() -> void:
	var viewport: Rect2 = game.get_viewport_rect().grow(1)
	for control in [game.hud.loadout, game.hud.vitals, game.hud.sector, game.hud.counters, game.hud.skill_row, game.hud.controls_hint]:
		check(viewport.encloses(control.get_global_rect()), "Primary HUD fits " + str(root.size))
	if game.coop.enabled:
		check(viewport.encloses(game.hud.partner_panel.get_global_rect()), "Partner vitals fit " + str(root.size))
	check(game.hud.skill_row.get_global_rect().position.y >= viewport.end.y - 104, "Action strip stays inside its compact backing")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.persistence_enabled = false
	game.auto_pause_enabled = false
	game.narrative_enabled = false
	root.add_child(game)
	await frames()
	await reset_case()
	game.settings.keys.slash = KEY_F
	game.player.energy = 10
	game.player.dash_cooldown = 1.5
	game.hud.update_status()
	check("F" in game.hud.skills[0].text, "Rebound primary key remains discoverable")
	check("能量不足" in game.hud.skills[1].text and "1.5 秒" in game.hud.skills[2].text, "Energy shortage and cooldown remain explicit")
	game.player.weapon.tick(0.4, true, false)
	game.hud.update_status()
	check("%" in game.hud.skills[0].text, "Charge is visible while holding attack")
	check("Tab 构筑" in game.hud.controls_hint.text, "Detailed build has a persistent entry hint")
	check(not game.hud.partner_skill_group.visible, "Solo has only one skill strip")
	for dimensions in [Vector2i(960, 600), Vector2i(1280, 800)]:
		root.size = dimensions
		await frames()
		bounds()
	await snapshot("solo")
	await reset_case(true)
	game.player.dash_cooldown = 2
	game.companion.freeze_cooldown = 6
	game.companion.energy = 10
	game.hud.update_status()
	check("2.0 秒" in game.hud.skills[2].text and "下键" in game.hud.partner_skills[2].text, "Each seat retains independent dash readiness")
	check("6.0 秒" in game.hud.partner_skills[3].text and "能量不足" in game.hud.partner_skills[1].text, "Partner cooldown and energy are visible")
	check(game.hud.partner_panel.visible and game.hud.partner_skill_group.visible, "Both partner vitals and skills are visible")
	for dimensions in [Vector2i(960, 600), Vector2i(1280, 800), Vector2i(2560, 1440)]:
		root.size = dimensions
		await frames()
		bounds()
	await snapshot("coop")
	# Freeze only this diagnostic snapshot; co-op repair advances in game._process.
	game.set_process(false)
	game.companion.hp = 0
	game.companion.revive_progress = 1.5
	game.save_warning = "无法保存，请检查磁盘空间"
	game.settings.values.high_contrast = true
	game.hud.apply_text_contrast()
	game.hud.update_status()
	await frames()
	check("修复 50%" in game.hud.partner_vitals.text, "Downed partner retains revive progress")
	check("—" in game.hud.partner_skills[0].text, "Downed partner has no ready attack prompt")
	check(game.hud.save_notice.visible and "无法保存" in game.hud.save_notice.text, "Save failure stays visible")
	await snapshot("revive")
	game.queue_free()
	await create_timer(0.2).timeout
	print("ABYSS COMBAT HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
