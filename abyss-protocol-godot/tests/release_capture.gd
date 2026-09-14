extends SceneTree
## Native regression for the exact screenshot method used by release storage checks.

class CaptureCheck extends "res://scripts/release_check.gd":
	func _ready() -> void:
		# Exercise snapshot(), not the complete campaign or the normal player profile.
		set_process(false)

var checks := 0
var failures := 0
var canvas: ColorRect
var verifier: CaptureCheck
var fixture := ""

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func capture(name: String, expected: Color) -> void:
	var guard := Timer.new()
	guard.one_shot = true
	root.add_child(guard)
	var result := {"timed_out": false}
	guard.timeout.connect(func():
		result.timed_out = true
		# Let the old implementation unwind, so failures still end cleanly.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED))
	guard.start(2.5)
	await verifier.snapshot(name)
	guard.stop()
	guard.queue_free()
	check(not result.timed_out, name + " finishes while the test window is minimized")
	var screenshot := Image.load_from_file(fixture.path_join(name + ".png"))
	check(screenshot != null and not screenshot.is_empty(), name + " writes actual rendered pixels")
	if screenshot != null and not screenshot.is_empty():
		var pixel := screenshot.get_pixel(screenshot.get_width() / 2, screenshot.get_height() / 2)
		check(pixel.is_equal_approx(expected), name + " captures the new scene, not the previous framebuffer")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Release capture regression requires a native rendering window")
		quit(1)
		return
	root.size = Vector2i(640, 400)
	root.title = "深渊协议 · 发行截图验证"
	fixture = ProjectSettings.globalize_path("res://builds/qa/release-capture-%d-%d" % [Time.get_unix_time_from_system(), OS.get_process_id()])
	check(DirAccess.make_dir_recursive_absolute(fixture) == OK, "create a unique disposable capture fixture")
	var marker := FileAccess.open(fixture.path_join(".abyss-release-fixture"), FileAccess.WRITE)
	marker.store_string("Disposable capture verification data\n")
	marker.close()
	canvas = ColorRect.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.color = Color.RED
	root.add_child(canvas)
	verifier = CaptureCheck.new()
	verifier.game = {"verification_directory": fixture}
	root.add_child(verifier)
	await create_timer(0.3).timeout
	await capture("visible-red", Color.RED)
	for item in [["minimized-green", Color.GREEN], ["minimized-blue", Color.BLUE]]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		await create_timer(0.4).timeout
		canvas.color = item[1]
		await capture(item[0], item[1])
	check(verifier.failures == 0 and verifier.checks == 3, "all three real release screenshot writes succeed")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	verifier.queue_free()
	canvas.queue_free()
	await process_frame
	print("ABYSS RELEASE CAPTURE: %d checks, %d failures" % [checks, failures])
	print("ABYSS CAPTURE FIXTURE: " + fixture)
	quit(0 if failures == 0 else 1)
