extends SceneTree
## Real audio retirement must outlive scene deletion and accelerated test clocks.

class ShutdownCheck extends "res://scripts/release_check.gd":
	func _ready() -> void:
		set_process(false)

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Release shutdown regression requires native audio lifecycle")
		quit(1)
		return
	root.title = "深渊协议 · 发行退出验证"
	root.size = Vector2i(640, 400)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var verifier := ShutdownCheck.new()
	root.add_child(verifier)
	var previous_scale := Engine.time_scale
	for scale in [1.0, 32.0]:
		var shell := Node.new()
		var sound = load("res://scripts/sound.gd").new()
		shell.add_child(sound)
		root.add_child(shell)
		sound.update_gain(0.35, 0.2)
		var stream: WeakRef = weakref(sound.ambience.stream)
		var playback: WeakRef = weakref(sound.ambience.get_stream_playback())
		var timing := {"scene_exited": 0}
		shell.tree_exited.connect(func(): timing.scene_exited = Time.get_ticks_msec())
		verifier.game = shell
		Engine.time_scale = scale
		await verifier.dispose_game()
		Engine.time_scale = previous_scale
		await process_frame
		var elapsed: int = Time.get_ticks_msec() - timing.scene_exited
		check(timing.scene_exited > 0 and not is_instance_valid(shell), "game scene exits before verifier returns")
		check(elapsed >= 200, "mixer receives 200 real milliseconds after deletion at time scale " + str(scale))
		check(stream.get_ref() == null and playback.get_ref() == null, "ambient stream and playback retire before exit")
		print("ABYSS SHUTDOWN TIMING: scale=%s elapsed_ms=%d" % [scale, elapsed])
		await create_timer(0.25, true, false, true).timeout
	verifier.queue_free()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await process_frame
	print("ABYSS RELEASE SHUTDOWN: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
