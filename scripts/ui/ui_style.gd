class_name UiStyle
extends RefCounted
## 게임 UI 공통 스타일: 색, 테마(버튼·패널·스크롤), 굵은 글꼴, 등급 색.
## 버튼 변형(theme_type_variation): "PrimaryButton"(금색), "GoButton"(초록), "DangerButton"(빨강),
## "TabButton"(시트 탭), "TabButtonOn"(선택된 탭), 기본 Button 은 남색.

const NAVY_DEEP := Color(0.07, 0.09, 0.15)
const NAVY := Color(0.12, 0.15, 0.24)
const NAVY_LIGHT := Color(0.19, 0.23, 0.35)
const EDGE := Color(0.30, 0.37, 0.55)
const GOLD := Color(1.0, 0.79, 0.29)
const GOLD_DARK := Color(0.69, 0.48, 0.07)
const RED := Color(1.0, 0.37, 0.33)
const GREEN := Color(0.37, 0.82, 0.41)
const BLUE := Color(0.30, 0.64, 1.0)
const TEXT := Color(0.95, 0.96, 0.98)
const MUTED := Color(0.62, 0.67, 0.78)

const FONT_PATH := "res://assets/fonts/NotoSansKR.ttf"
const WGHT := 2003265652  # OpenType 'wght' 태그

static var _bold: FontVariation
static var _regular: FontVariation


static func font(weight: int = 500) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(FONT_PATH)
	f.variation_opentype = {WGHT: weight}
	return f


static func bold() -> FontVariation:
	if _bold == null:
		_bold = font(800)
	return _bold


static func regular() -> FontVariation:
	if _regular == null:
		_regular = font(500)
	return _regular


## 가격대별 등급: 0 일반(2~3), 1 고급(4~5), 2 희귀(6~7), 3 전설(8~10)
static func rarity(cost: int) -> int:
	if cost >= 8:
		return 3
	if cost >= 6:
		return 2
	if cost >= 4:
		return 1
	return 0


static func rarity_color(cost: int) -> Color:
	return [Color(0.62, 0.66, 0.74), Color(0.25, 0.60, 1.0), Color(0.72, 0.38, 1.0), Color(1.0, 0.62, 0.12)][rarity(cost)]


static func rarity_name(cost: int) -> String:
	return ["일반", "고급", "희귀", "전설"][rarity(cost)]


## 둥근 상자. bottom 이 크면 아래 테두리가 두꺼워져 입체 버튼처럼 보인다.
static func box(bg: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 12, bottom: int = -1, margin: float = 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	if width > 0 or bottom > 0:
		sb.border_color = border
		sb.set_border_width_all(width)
		if bottom >= 0:
			sb.border_width_bottom = bottom
	sb.anti_aliasing = true
	return sb


static func shadow(sb: StyleBoxFlat, size: int = 8, alpha: float = 0.35) -> StyleBoxFlat:
	sb.shadow_color = Color(0, 0, 0, alpha)
	sb.shadow_size = size
	sb.shadow_offset = Vector2(0, 3)
	return sb


## 입체 버튼 스타일 4종을 테마에 넣는다.
static func _button_styles(theme: Theme, type: String, face: Color, edge: Color, text: Color) -> void:
	var normal := box(face, edge, 2, 12, 6, 8.0)
	normal.content_margin_bottom = 12.0
	var hover := box(face.lightened(0.08), edge, 2, 12, 6, 8.0)
	hover.content_margin_bottom = 12.0
	var pressed := box(face.darkened(0.08), edge, 2, 12, 2, 8.0)
	pressed.content_margin_top = 12.0
	pressed.content_margin_bottom = 8.0
	var disabled := box(face.lerp(NAVY, 0.7), edge.lerp(NAVY, 0.6), 2, 12, 6, 8.0)
	disabled.content_margin_bottom = 12.0
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(c, type, text)
	theme.set_color("font_disabled_color", type, Color(text, 0.4))
	theme.set_color("font_outline_color", type, Color(0, 0, 0, 0.45))
	theme.set_constant("outline_size", type, 4 if text == TEXT else 0)
	if type != "Button":
		theme.set_type_variation(type, "Button")


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = regular()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	_button_styles(theme, "Button", NAVY_LIGHT, EDGE.darkened(0.3), TEXT)
	_button_styles(theme, "PrimaryButton", GOLD, GOLD_DARK, Color(0.25, 0.15, 0.02))
	_button_styles(theme, "GoButton", GREEN, Color(0.13, 0.48, 0.20), TEXT)
	_button_styles(theme, "DangerButton", Color(0.80, 0.28, 0.26), Color(0.45, 0.12, 0.12), TEXT)
	_button_styles(theme, "TabButton", NAVY, NAVY_DEEP, MUTED)
	_button_styles(theme, "TabButtonOn", GOLD, GOLD_DARK, Color(0.25, 0.15, 0.02))
	theme.set_font("font", "Button", bold())
	theme.set_stylebox("panel", "PanelContainer", box(NAVY, EDGE, 2, 12))
	# 얇은 스크롤바
	var grabber := box(EDGE, Color.TRANSPARENT, 0, 4, -1, 0.0)
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD_DARK, Color.TRANSPARENT, 0, 4, -1, 0.0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, Color.TRANSPARENT, 0, 4, -1, 0.0))
	var track := box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 0, 4, -1, 0.0)
	track.content_margin_left = 3.0
	track.content_margin_right = 3.0
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("panel", "TooltipPanel", box(NAVY_DEEP, GOLD_DARK, 2, 8))
	return theme
