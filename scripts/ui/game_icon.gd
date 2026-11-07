class_name GameIcon
extends Control
## 도형으로 그리는 작은 아이콘 (이미지 파일 없이).
## kind: heart, coin, sword, shield, bolt, plus, bow, flag, skull, refresh, star, flame, sell

var kind: String = "coin"
var color: Color = Color.WHITE


static func make(p_kind: String, p_size: float = 24.0, p_color: Color = Color.TRANSPARENT) -> GameIcon:
	var icon := GameIcon.new()
	icon.kind = p_kind
	icon.color = p_color if p_color.a > 0.0 else default_color(p_kind)
	icon.custom_minimum_size = Vector2.ONE * p_size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


static func default_color(p_kind: String) -> Color:
	match p_kind:
		"heart":
			return UiStyle.RED
		"coin":
			return UiStyle.GOLD
		"sword":
			return Color(0.85, 0.88, 0.95)
		"shield":
			return UiStyle.BLUE
		"bolt":
			return Color(1.0, 0.9, 0.3)
		"plus":
			return UiStyle.GREEN
		"bow":
			return Color(0.85, 0.62, 0.35)
		"flame":
			return Color(1.0, 0.55, 0.15)
		"skull":
			return Color(0.92, 0.92, 0.92)
	return UiStyle.TEXT


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var ol := Color(0, 0, 0, 0.55)
	match kind:
		"heart":
			var pts := PackedVector2Array()
			for i in 40:
				var t := TAU * i / 40.0
				var x := 16.0 * pow(sin(t), 3)
				var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
				pts.append(c + Vector2(x, y) * s / 36.0)
			draw_colored_polygon(pts, color)
			draw_polyline(pts + PackedVector2Array([pts[0]]), ol, 1.5, true)
			draw_circle(c + Vector2(-0.2, -0.15) * s, s * 0.08, Color(1, 1, 1, 0.5))
		"coin":
			draw_circle(c, s * 0.46, color.darkened(0.35))
			draw_circle(c + Vector2(0, -s * 0.03), s * 0.42, color)
			draw_circle(c + Vector2(0, -s * 0.03), s * 0.28, color.darkened(0.12))
			draw_rect(Rect2(c + Vector2(-s * 0.05, -s * 0.2), Vector2(s * 0.1, s * 0.34)), color.lightened(0.35))
		"sword":
			var tip := c + Vector2(s * 0.36, -s * 0.36)
			var base := c + Vector2(-s * 0.18, s * 0.18)
			draw_line(base, tip, color, s * 0.14, true)
			draw_line(c + Vector2(-s * 0.34, s * 0.02), c + Vector2(-s * 0.02, s * 0.34), Color(0.75, 0.55, 0.25), s * 0.12, true)
			draw_line(base, c + Vector2(-s * 0.38, s * 0.38), Color(0.55, 0.35, 0.2), s * 0.12, true)
		"shield":
			var pts := PackedVector2Array([
				c + Vector2(-0.38, -0.4) * s, c + Vector2(0.38, -0.4) * s, c + Vector2(0.36, 0.05) * s,
				c + Vector2(0, 0.45) * s, c + Vector2(-0.36, 0.05) * s])
			draw_colored_polygon(pts, color)
			draw_polyline(pts + PackedVector2Array([pts[0]]), ol, 1.5, true)
			draw_line(c + Vector2(0, -0.32) * s, c + Vector2(0, 0.32) * s, Color(1, 1, 1, 0.35), s * 0.08)
		"bolt":
			var pts := PackedVector2Array([
				c + Vector2(0.12, -0.46) * s, c + Vector2(-0.3, 0.06) * s, c + Vector2(-0.02, 0.06) * s,
				c + Vector2(-0.14, 0.46) * s, c + Vector2(0.3, -0.08) * s, c + Vector2(0.02, -0.08) * s])
			draw_colored_polygon(pts, color)
			draw_polyline(pts + PackedVector2Array([pts[0]]), ol, 1.2, true)
		"plus":
			draw_rect(Rect2(c - Vector2(s * 0.12, s * 0.4), Vector2(s * 0.24, s * 0.8)), color)
			draw_rect(Rect2(c - Vector2(s * 0.4, s * 0.12), Vector2(s * 0.8, s * 0.24)), color)
		"bow":
			draw_arc(c + Vector2(-s * 0.12, 0), s * 0.4, -PI / 2.6, PI / 2.6, 16, color, s * 0.1, true)
			var top := c + Vector2(-s * 0.12, 0) + Vector2.from_angle(-PI / 2.6) * s * 0.4
			var bot := c + Vector2(-s * 0.12, 0) + Vector2.from_angle(PI / 2.6) * s * 0.4
			draw_line(top, bot, Color(0.95, 0.95, 0.95), 1.5)
			draw_line(c + Vector2(-s * 0.35, 0), c + Vector2(s * 0.42, 0), Color(0.9, 0.9, 0.9), 2.0)
		"flag":
			draw_line(c + Vector2(-0.3, -0.42) * s, c + Vector2(-0.3, 0.45) * s, Color(0.85, 0.85, 0.85), s * 0.08)
			var pts := PackedVector2Array([c + Vector2(-0.28, -0.42) * s, c + Vector2(0.4, -0.25) * s, c + Vector2(-0.28, -0.05) * s])
			draw_colored_polygon(pts, color)
		"skull":
			draw_circle(c + Vector2(0, -s * 0.06), s * 0.36, color)
			draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.15), Vector2(s * 0.4, s * 0.22)), color)
			draw_circle(c + Vector2(-s * 0.13, -s * 0.06), s * 0.09, Color(0.1, 0.1, 0.12))
			draw_circle(c + Vector2(s * 0.13, -s * 0.06), s * 0.09, Color(0.1, 0.1, 0.12))
		"refresh":
			draw_arc(c, s * 0.32, 0.3, TAU - 0.6, 24, color, s * 0.11, true)
			var a := c + Vector2.from_angle(0.3) * s * 0.32
			draw_colored_polygon(PackedVector2Array([a + Vector2(-s * 0.16, -s * 0.02), a + Vector2(s * 0.14, -s * 0.04), a + Vector2(0, s * 0.18)]), color)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := s * (0.46 if i % 2 == 0 else 0.2)
				pts.append(c + Vector2.from_angle(-PI / 2 + i * PI / 5) * r)
			draw_colored_polygon(pts, color)
		"flame":
			var pts := PackedVector2Array()
			for i in 32:
				var t := TAU * i / 32.0
				var r := s * (0.3 + 0.12 * maxf(0.0, -sin(t)) * (1.0 + 0.6 * absf(cos(t * 2.0))))
				pts.append(c + Vector2(cos(t) * s * 0.3, sin(t) * r + s * 0.08))
			draw_colored_polygon(pts, color)
			draw_circle(c + Vector2(0, s * 0.14), s * 0.14, Color(1, 0.9, 0.4))
		"sell":
			draw_circle(c, s * 0.42, color.darkened(0.3))
			draw_string(UiStyle.bold(), c + Vector2(-s * 0.2, s * 0.2), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.6), Color.WHITE)
