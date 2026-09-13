extends Control
## Three authored SVG tableaux animated by a finite, save-free timeline.
signal finished
const DURATION := 8.0
const SPACE = preload("res://assets/story/space.svg")
const STATION = preload("res://assets/story/station.svg")
const SHUTTLE = preload("res://assets/story/shuttle.svg")
const PUMP = preload("res://assets/story/pump.svg")
const ROTOR = preload("res://assets/story/rotor.svg")
const ROBOT = preload("res://assets/story/robot.svg")
const ARM = preload("res://assets/story/arm.svg")
var beat := "awakening"
var elapsed := 0.0
var paused := false
var motion_enabled := true
var auto_pause_enabled := true
signal playback_changed
var canvas_scale := 1.0
var canvas_origin := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	if not motion_enabled:
		elapsed = DURATION
		set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		set_process(is_visible_in_tree() and motion_enabled and not paused and elapsed < DURATION)
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and auto_pause_enabled and is_visible_in_tree():
		paused = true
		set_process(false)
		playback_changed.emit()

func _process(delta: float) -> void:
	if paused or not motion_enabled: return
	elapsed = minf(DURATION, elapsed + delta)
	queue_redraw()
	if elapsed >= DURATION:
		set_process(false)
		finished.emit()
		playback_changed.emit()

func toggle_playback() -> void:
	if not motion_enabled: return
	if elapsed >= DURATION:
		elapsed = 0
		paused = false
	else:
		paused = not paused
	set_process(not paused and is_visible_in_tree())
	queue_redraw()
	playback_changed.emit()

func progress(start: float, end: float) -> float:
	return smoothstep(start, end, elapsed)

func piece(texture: Texture2D, anchor: Vector2, dimensions: Vector2, angle := 0.0, opacity := 1.0, pivot := Vector2(-1, -1)) -> void:
	draw_set_transform(canvas_origin + anchor * canvas_scale, angle, Vector2.ONE * canvas_scale)
	var origin := dimensions * 0.5 if pivot.x < 0 else pivot
	draw_texture_rect(texture, Rect2(-origin, dimensions), false, Color(1, 1, 1, opacity))

func coordinates() -> void:
	draw_set_transform(canvas_origin, 0, Vector2.ONE * canvas_scale)

func _draw() -> void:
	canvas_scale = minf(size.x / 640.0, size.y / 720.0)
	canvas_origin = (size - Vector2(640, 720) * canvas_scale) * 0.5
	if beat == "calibration":
		draw_pumps()
	else:
		draw_orbit()

func draw_orbit() -> void:
	piece(SPACE, Vector2(320, 360), Vector2(640, 720))
	var arrival := beat == "awakening"
	var station_scale := lerpf(0.82, 1.0, progress(0, 6)) if arrival else 1.0
	var center := Vector2(320, 270)
	piece(STATION, center, Vector2(600, 450) * station_scale, -0.14)
	coordinates()
	if arrival:
		var p := progress(0.4, 6.6)
		var craft := Vector2(85, 590).bezier_interpolate(Vector2(435, 610), Vector2(450, 410), Vector2(342, 439), p)
		var craft_scale := lerpf(1.15, 0.38, p)
		piece(SHUTTLE, craft, Vector2(140, 70) * craft_scale, lerpf(-0.15, -PI * 0.5, smoothstep(0.55, 1.0, p)))
		coordinates()
		draw_circle(Vector2(342, 421), 3.5, Color(0.92, 0.72, 0.44, progress(5.8, 7.4)))
	else:
		# Light the habitat gradually; no strobe, flicker or additive full-screen flash.
		for i in range(16):
			var angle := float(i) / 16 * TAU
			var point := center + Vector2(cos(angle) * 214, sin(angle) * 102).rotated(-0.14)
			draw_circle(point, 2.4, Color(0.91, 0.76, 0.52, progress(i * 0.13, 1.5 + i * 0.13)))
		for i in range(6):
			var p := progress(0.7 + i * 0.42, 5.5 + i * 0.4)
			var destination := Vector2(545 - i * 21, 90 + i * 31)
			var craft := Vector2(342, 439).bezier_interpolate(Vector2(600, 450), Vector2(510, 210), destination, p)
			piece(SHUTTLE, craft, Vector2(140, 70) * lerpf(0.34, 0.15, p), -0.95, progress(0.4 + i * 0.42, 0.8 + i * 0.42))
	coordinates()

func draw_pumps() -> void:
	piece(PUMP, Vector2(320, 360), Vector2(640, 720))
	var rotation_time := maxf(0, elapsed - 2.5)
	var angle := rotation_time * rotation_time * 0.28
	piece(ROTOR, Vector2(213, 271), Vector2(174, 174), angle)
	piece(ROTOR, Vector2(431, 365), Vector2(156, 156), -angle * 0.8)
	piece(ROBOT, Vector2(201, 545), Vector2(112, 180))
	piece(ARM, Vector2(216, 521), Vector2(92, 64), lerpf(-0.65, 0, progress(0.5, 2.5)), 1, Vector2(11, 18))
	coordinates()
	var flow := progress(2.5, 7.5)
	var line := PackedVector2Array([Vector2(279, 551), Vector2(279, 562), Vector2(484, 562), Vector2(484, 439), Vector2(310, 439), Vector2(310, 177)])
	draw_polyline(line, Color(0.60, 0.76, 0.70, progress(2.5, 4) * 0.55), 3, true)
	if flow > 0:
		var distances := [11.0, 205.0, 123.0, 174.0, 262.0]
		var remaining := flow * 775.0
		for i in range(distances.size()):
			if remaining <= distances[i]:
				draw_circle(line[i].lerp(line[i + 1], remaining / distances[i]), 5, Color("d5cba4"))
				break
			remaining -= distances[i]
	for i in range(4):
		draw_line(Vector2(151 + i * 18, 458), Vector2(157 + i * 18, 458), Color(0.77, 0.87, 0.69, progress(3 + i * 0.6, 4 + i * 0.6)), 3, true)
