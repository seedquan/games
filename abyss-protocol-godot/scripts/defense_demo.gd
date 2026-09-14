extends Control
## A finite, optional slow-motion diagram. Never simulates or changes combat.
signal playback_changed
const ART = preload("res://assets/ui/defense_demo.svg")
const DURATION := 5.0
const DODGE = preload("res://scripts/dodge_diagram.gd")
var mode := "parry"
var elapsed := DURATION
var has_played := false
var paused := false
var motion_enabled := true
var auto_pause_enabled := true

func _ready() -> void:
	custom_minimum_size = Vector2(1080, 166)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(false)
	resized.connect(queue_redraw)

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
	if elapsed >= DURATION: set_process(false)
	playback_changed.emit()

func toggle_playback() -> void:
	if not motion_enabled: return
	if elapsed >= DURATION:
		elapsed = 0.0
		has_played = true
		paused = false
	else:
		paused = not paused
	set_process(is_visible_in_tree() and not paused)
	queue_redraw()
	playback_changed.emit()

func select_mode(value: String) -> void:
	if value not in ["parry", "dodge"] or value == mode: return
	mode = value
	elapsed = DURATION
	has_played = false
	paused = false
	set_process(false)
	queue_redraw()
	playback_changed.emit()

func instruction(binding: String) -> String:
	if mode == "dodge":
		if elapsed >= DURATION: return "先走出橙色范围；来不及时按 %s 冲刺 · 已在安全处无需冲刺" % binding
		if elapsed < 1.5: return "守卫图标只在预告招式 · 先观察，不必立刻冲刺"
		if elapsed < 3.02: return "落点已锁定，内环正向外扩张 · 尽早走出范围，留住冲刺"
		if elapsed < 3.4: return "内环将碰到外沿 · 来不及走出时，按 %s 冲刺" % binding
		return "爆发结束再回身进攻 · 短暂无敌不会覆盖整个预告"
	if elapsed >= DURATION:
		return "来弹接近时按 %s 弹反 · 金色返弹携带武器元素与符文" % binding
	if elapsed < 2.3: return "看清来弹方向 · 接近时按 %s 弹反" % binding
	if elapsed < 2.6: return "此时按 %s · 短暂弹反窗口" % binding
	return "原路返还一枚 · 可接武器元素与符文联动"

func arrow(from: Vector2, to: Vector2, color: Color, width := 2.0) -> void:
	draw_line(from, to, color, width, true)
	var direction := from.direction_to(to)
	draw_polyline(PackedVector2Array([to - direction * 12 + direction.orthogonal() * 6, to, to - direction * 12 - direction.orthogonal() * 6]), color, width, true)

func _draw() -> void:
	var scale_factor := minf(size.x / 1080.0, size.y / 166.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
	if mode == "dodge":
		DODGE.draw_on(self, elapsed, elapsed >= DURATION or not motion_enabled)
		return
	var red := Color("ee947e")
	var gold := Color("e5ba7c")
	var still := elapsed >= DURATION or not motion_enabled
	draw_line(Vector2(35, 152), Vector2(1045, 152), Color("47534b"), 1, true)
	draw_texture_rect_region(ART, Rect2(64, 28, 96, 96), Rect2(0, 0, 96, 96))
	draw_texture_rect_region(ART, Rect2(868, 28, 96, 96), Rect2(96, 0, 96, 96))
	for x in range(190, 851, 30):
		draw_line(Vector2(x, 80), Vector2(x + 9, 80), Color("49564d"), 1, true)
	if still:
		arrow(Vector2(184, 60), Vector2(849, 60), red)
		arrow(Vector2(849, 103), Vector2(184, 103), gold)
	else:
		var outgoing := elapsed >= 2.6
		var progress := clampf((elapsed - 2.6) / 1.1 if outgoing else (elapsed - 0.6) / 2.0, 0.0, 1.0)
		var x := lerpf(850, 166, progress) if outgoing else lerpf(166, 850, progress)
		if elapsed >= 0.6 and elapsed < 3.7:
			var color := gold if outgoing else red
			var direction := -1.0 if outgoing else 1.0
			arrow(Vector2(x - direction * 28, 80), Vector2(x, 80), color, 3)
			if outgoing: draw_circle(Vector2(x, 80), 4, gold)
	# A short shield cue, never a strobe or full-screen flash.
	if still or (elapsed >= 2.3 and elapsed < 2.85):
		draw_arc(Vector2(916, 80), 60, PI * 0.65, PI * 1.35, 24, gold, 3, true)
		draw_circle(Vector2(850, 80), 7, gold)
