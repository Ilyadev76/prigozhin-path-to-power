extends MarginContainer

var _main_mod = null
var _game = null
var _send_order_callback: Callable = Callable()
var _select_tab_callback: Callable = Callable()
var _protocol_callback: Callable = Callable()

func configure_base(main_mod, game, callbacks: Dictionary) -> void:
	_main_mod = main_mod
	_game = game
	var send_order_callback: Callable = callbacks.get("send_order", Callable())
	var select_tab_callback: Callable = callbacks.get("select_tab", Callable())
	var protocol_callback: Callable = callbacks.get("protocol", Callable())
	_send_order_callback = send_order_callback
	_select_tab_callback = select_tab_callback
	_protocol_callback = protocol_callback
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("margin_top", 8)
	add_theme_constant_override("margin_bottom", 8)
	add_theme_constant_override("margin_left", 8)
	add_theme_constant_override("margin_right", 8)

func send_order_to_game(text_order: String, pre_days: int = 2, place: Dictionary = {}) -> bool:
	if _send_order_callback.is_valid():
		return bool(_send_order_callback.call(text_order, pre_days, place))
	return false

func select_tab(tab_index: int) -> void:
	if _select_tab_callback.is_valid():
		_select_tab_callback.call(tab_index)

func request_mironov_protocol() -> void:
	if _protocol_callback.is_valid():
		_protocol_callback.call()

func _mod_tr(key: String) -> String:
	if _main_mod and _main_mod.has_method("tr_key"):
		return str(_main_mod.tr_key(key))
	return key

func _card_box_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 14
	sb.content_margin_top = 12
	sb.content_margin_right = 14
	sb.content_margin_bottom = 12
	return sb
