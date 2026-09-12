extends RefCounted
## Local seats bind OS device IDs only for this session, never in player saves.

var game
var enabled := false
var devices: Array[int] = [-1, -1]
var weapons: Array[String] = ["blade", "rifle"]
var return_state := "title"
var restoring := false

func ready_to_play() -> bool:
	return devices[0] >= 0 and devices[1] >= 0 and devices[0] != devices[1]

func open_lobby(resume_existing := false) -> void:
	restoring = resume_existing
	return_state = game.state
	if not resume_existing:
		devices.assign([-1, -1])
		weapons[0] = game.selected_weapon
	game.show_menu("coop_lobby")

func route(event: InputEvent) -> bool:
	if game.state == "coop_lobby":
		if event is InputEventKey and event.is_pressed() and event.keycode == KEY_ESCAPE:
			game.show_menu(return_state)
			return true
		elif event is InputEventJoypadButton and event.pressed:
			var seat := devices.find(event.device)
			if event.button_index == JOY_BUTTON_A and seat < 0:
				seat = devices.find(-1)
				if seat >= 0:
					devices[seat] = event.device
			elif seat >= 0 and event.button_index == JOY_BUTTON_B:
				devices[seat] = -1
			elif seat < 0 and event.button_index == JOY_BUTTON_B:
				game.show_menu(return_state)
				return true
			elif seat >= 0 and not restoring and event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
				var ids: Array = []
				for form in game.WEAPONS.FORMS:
					ids.append(form.id)
				var step := -1 if event.button_index == JOY_BUTTON_DPAD_LEFT else 1
				weapons[seat] = ids[posmod(ids.find(weapons[seat]) + step, ids.size())]
			elif seat >= 0 and event.button_index == JOY_BUTTON_START and ready_to_play():
				enabled = true
				game.configure_input()
				if restoring:
					if return_state == "playing":
						game.show_menu("paused")
					else:
						game.show_menu(return_state)
				else:
					game.request_new_run()
				return true
			game.hud.show_menu("coop_lobby")
		return event is InputEventJoypadButton or event is InputEventJoypadMotion
	if enabled and not ready_to_play() and is_instance_valid(game.player) and not game.result_recorded:
		open_lobby(true)
		return true
	if not enabled or not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return false
	var seat := devices.find(event.device)
	if seat < 0:
		return true
	# Either player may pause; a single menu pilot avoids conflicting purchases.
	var pilot := 1 if is_instance_valid(game.player) and game.player.hp <= 0.0 and is_instance_valid(game.companion) and game.companion.hp > 0.0 else 0
	return game.state != "playing" and seat != pilot and not event.is_action_pressed("pause_run")

func disconnected(device: int) -> void:
	var seat := devices.find(device)
	if seat < 0:
		return
	devices[seat] = -1
	game.configure_input()
	if game.state == "coop_lobby":
		game.hud.show_menu("coop_lobby")
	elif enabled and is_instance_valid(game.player) and not game.result_recorded:
		if game.state == "playing":
			game.show_menu("paused")
		open_lobby(true)

func tick(delta: float) -> void:
	if not enabled or game.state != "playing":
		return
	for member in game.team():
		if member.hp > 0.0:
			continue
		var helper = game.nearest_player(member.position)
		var rescuing: bool = is_instance_valid(helper) and helper.position.distance_to(member.position) < 90.0 and helper.velocity.length() < 45.0 and helper.invulnerable <= 0.0 and game.has_sight(helper.position, member.position)
		member.revive_progress = minf(3.0, member.revive_progress + delta) if rescuing else 0.0
		if member.revive_progress >= 3.0:
			member.revive()
		member.queue_redraw()

func frame_camera(delta: float) -> void:
	var members: Array = game.team()
	if members.size() != 2:
		return
	var bounds := Rect2(members[0].position, Vector2.ZERO)
	bounds = bounds.expand(members[1].position)
	if is_instance_valid(game.active_boss):
		bounds = bounds.expand(game.active_boss.position)
	var viewport: Vector2 = game.get_viewport_rect().size
	var available := (viewport - Vector2(260, 360)).max(Vector2(100, 100))
	var zoom := minf(1.0, minf(available.x / (bounds.size.x + 230), available.y / (bounds.size.y + 230)))
	var deck: Rect2 = game.arena.bounds
	game.camera.limit_left = -int(deck.size.x * 2)
	game.camera.limit_right = int(deck.end.x * 3)
	game.camera.limit_top = -int(deck.size.y * 2)
	game.camera.limit_bottom = int(deck.end.y * 3)
	game.camera.position = bounds.get_center()
	# Zoom out immediately to keep a dashing partner visible; ease back in.
	var eased: float = lerpf(game.camera.zoom.x, zoom, 1.0 - exp(-4.0 * delta))
	game.camera.zoom = Vector2.ONE * minf(zoom, eased)
