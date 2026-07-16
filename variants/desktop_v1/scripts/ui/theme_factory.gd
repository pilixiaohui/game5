extends RefCounted

const BG := Color("071014")
const SURFACE := Color("0e1a1e")
const SURFACE_ALT := Color("142328")
const BORDER := Color("294047")
const TEXT := Color("e8efea")
const MUTED := Color("93a6a6")
const GREEN := Color("82d67b")
const CYAN := Color("57c4c3")
const AMBER := Color("e2ba60")
const MAGENTA := Color("c77ba7")
const RED := Color("dc785f")

static func build() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "PingFang SC", "WenQuanYi Micro Hei", "sans-serif"])
	font.font_weight = 450
	theme.default_font = font
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_font_size("font_size", "Label", 16)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", BG)
	theme.set_color("font_disabled_color", "Button", Color(MUTED, 0.52))
	theme.set_font_size("font_size", "Button", 16)
	theme.set_stylebox("normal", "Button", _box(SURFACE_ALT, BORDER, 1, 6, 10))
	theme.set_stylebox("hover", "Button", _box(Color("193137"), CYAN, 1, 6, 10))
	theme.set_stylebox("pressed", "Button", _box(GREEN, GREEN, 1, 6, 10))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), AMBER, 2, 6, 8))
	theme.set_stylebox("disabled", "Button", _box(Color("101a1d"), Color("1b2a2e"), 1, 6, 10))

	theme.set_stylebox("panel", "Panel", _box(SURFACE, BORDER, 1, 6, 12))
	theme.set_stylebox("panel", "PanelContainer", _box(SURFACE, BORDER, 1, 6, 14))
	theme.set_stylebox("normal", "LineEdit", _box(SURFACE_ALT, BORDER, 1, 4, 8))
	theme.set_stylebox("normal", "TextEdit", _box(SURFACE_ALT, BORDER, 1, 4, 8))
	theme.set_stylebox("normal", "ProgressBar", _box(Color("091215"), BORDER, 1, 4, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(GREEN, GREEN, 0, 4, 0))
	theme.set_color("font_color", "ProgressBar", TEXT)
	theme.set_stylebox("normal", "OptionButton", _box(SURFACE_ALT, BORDER, 1, 6, 10))
	theme.set_stylebox("hover", "OptionButton", _box(Color("193137"), CYAN, 1, 6, 10))
	theme.set_stylebox("pressed", "OptionButton", _box(GREEN, GREEN, 1, 6, 10))
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_stylebox("panel", "PopupMenu", _box(SURFACE_ALT, BORDER, 1, 4, 6))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", BG)
	theme.set_stylebox("hover", "PopupMenu", _box(GREEN, GREEN, 0, 3, 4))
	theme.set_stylebox("grabber_area", "HSlider", _box(Color("142328"), Color("142328"), 0, 2, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(Color("1b3539"), Color("1b3539"), 0, 2, 0))

	_add_variation(theme, "Title", "Label", 32, TEXT)
	_add_variation(theme, "GameTitle", "Label", 44, TEXT)
	_add_variation(theme, "PageTitle", "Label", 24, TEXT)
	_add_variation(theme, "Section", "Label", 18, GREEN)
	_add_variation(theme, "Muted", "Label", 14, MUTED)
	_add_variation(theme, "Metric", "Label", 20, TEXT)
	_add_variation(theme, "Warning", "Label", 14, AMBER)
	for variation in ["GameTitle", "PageTitle", "Section"]:
		theme.set_color("font_outline_color", variation, Color(BG, 0.92))
		theme.set_constant("outline_size", variation, 4 if variation != "GameTitle" else 6)
	_add_button_variation(theme, "PrimaryButton", GREEN, BG)
	_add_button_variation(theme, "DangerButton", RED, Color.WHITE)
	_add_button_variation(theme, "NavButton", SURFACE, TEXT)
	_add_button_variation(theme, "NavActiveButton", Color("1c3534"), GREEN)
	return theme

static func _box(background: Color, border: Color, width: int, radius: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = max(4, padding - 3)
	box.content_margin_bottom = max(4, padding - 3)
	return box

static func _add_variation(theme: Theme, variation: String, base: String, size: int, color: Color) -> void:
	theme.set_type_variation(variation, base)
	theme.set_font_size("font_size", variation, size)
	theme.set_color("font_color", variation, color)

static func _add_button_variation(theme: Theme, variation: String, fill: Color, text_color: Color) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_color("font_color", variation, text_color)
	theme.set_color("font_hover_color", variation, text_color)
	theme.set_color("font_pressed_color", variation, text_color)
	theme.set_stylebox("normal", variation, _box(fill, fill.lightened(0.12), 1, 6, 10))
	theme.set_stylebox("hover", variation, _box(fill.lightened(0.08), fill.lightened(0.22), 1, 6, 10))
	theme.set_stylebox("pressed", variation, _box(fill.darkened(0.08), fill, 1, 6, 10))
	theme.set_stylebox("focus", variation, _box(Color(0, 0, 0, 0), AMBER, 2, 6, 8))
