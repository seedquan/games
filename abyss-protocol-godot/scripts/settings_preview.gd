extends Control
## A local illustration preview: no world simulation, settings writes or timers.
const ART := {
	"display": preload("res://assets/ui/settings_display.svg"),
	"audio": preload("res://assets/ui/settings_audio.svg"),
	"keys": preload("res://assets/ui/settings_keyboard.svg"),
	"controller": preload("res://assets/ui/settings_controller.svg"),
}
var game
var kind := "display"
var demo_left := 0.0
var preview_offset := Vector2.ZERO
var preview_flash := 0.0
var channel_levels: Array[float] = []

func demonstrate() -> void:
	demo_left = 1.2
	queue_redraw()

func _process(delta: float) -> void:
	if demo_left > 0:
		demo_left = maxf(0, demo_left - delta)
		queue_redraw()

func caption(text: String, point: Vector2, color := Color("cbd2c7"), font_size := 28) -> void:
	draw_string(game.hud.theme.default_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	if not is_instance_valid(game): return
	var scale := minf(size.x / 600.0, size.y / 380.0)
	draw_set_transform((size - Vector2(600, 380) * scale) * 0.5, 0, Vector2.ONE * scale)
	draw_texture_rect(ART[kind], Rect2(0, 0, 600, 380), false)
	match kind:
		"display":
			preview_offset = Vector2(sin(demo_left * 91), cos(demo_left * 67)) * 8.0 * game.settings.values.shake * minf(1, demo_left)
			preview_flash = maxf(0, 1.0 - absf(demo_left - 0.7) * 9) * game.settings.values.flash
			var deck := Rect2(Vector2(77, 57), Vector2(446, 233))
			draw_rect(deck, Color("1c3035"))
			for x in [135, 390]:
				draw_rect(Rect2(Vector2(x, 110) + preview_offset, Vector2(55, 100)), Color("3d5050"))
			draw_line(Vector2(95, 78) + preview_offset, Vector2(190, 78) + preview_offset, Color("b5caa0"), 6)
			var player := Vector2(279, 191) + preview_offset
			draw_circle(player, 18, Color("8bb5bf"))
			draw_line(player, player + Vector2(40, -23), Color("ece8d9"), 6)
			draw_arc(Vector2(349, 147) + preview_offset, 24, 0, TAU, 24, Color("e6b879"), 3, true)
			if preview_flash > 0: draw_rect(deck, Color(0.95, 0.83, 0.65, preview_flash * 0.6))
			caption("机体耐久", Vector2(95, 107) + preview_offset, Color("f3eee0") if game.settings.values.high_contrast else Color("cbd2c7"))
		"audio":
			var master: float = 0.0 if game.muted else game.settings.values.volume
			channel_levels.assign([master, master * game.settings.values.effects_volume, master * game.settings.values.ambience_volume])
			for i in range(3):
				for segment in range(12):
					var lit := float(segment) / 12 < channel_levels[i]
					draw_rect(Rect2(149 + i * 126, 278 - segment * 17, 50, 10), Color("e6b879") if lit else Color("26393d"))
				caption(["总输出", "战斗", "环境"][i], Vector2(145 + i * 126, 328), Color("cbd2c7"), 26)
		"keys":
			var rows := ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
			for row in range(3):
				for i in range(rows[row].length()):
					var letter: String = rows[row][i]
					var used: bool = letter.unicode_at(0) in game.settings.keys.values()
					var point := Vector2(44 + row * 12 + i * 45, 93 + row * 59)
					draw_style_box(game.hud.style(Color("c4a272") if used else Color("203238"), Color("627571"), 0), Rect2(point, Vector2(37, 42)))
					caption(letter, point + Vector2(10, 28), Color("111d22") if used else Color("cbd2c7"), 22)
			for item in [[KEY_SPACE, "空格", Rect2(149, 278, 242, 38), Vector2(241, 304)], [KEY_CTRL, "Ctrl", Rect2(36, 278, 80, 38), Vector2(48, 304)], [KEY_SHIFT, "Shift", Rect2(424, 278, 90, 38), Vector2(438, 304)]]:
				var used: bool = item[0] in game.settings.keys.values()
				if used: draw_style_box(game.hud.style(Color("c4a272"), Color("627571"), 0), item[2])
				caption(item[1], item[3], Color("111d22") if used else Color("cbd2c7"), 26)
		"controller":
			caption("等离子弹", Vector2(80, 35))
			caption("主武器", Vector2(438, 35))
			caption("移动", Vector2(110, 220))
			caption("瞄准", Vector2(347, 301))
			caption("暂停", Vector2(280, 99), Color("cbd2c7"), 26)
			caption("冰冻", Vector2(360, 138), Color("92c4d0"), 26)
			caption("弹反", Vector2(487, 168), Color("d6a0a0"), 26)
			caption("冲刺", Vector2(435, 234), Color("e6b879"), 26)
