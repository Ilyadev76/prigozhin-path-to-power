extends MarginContainer

const DashboardTabClass = preload("res://mods/prigozhin_fork/ui/tabs/dashboard_tab.gd")
const CommsTabClass = preload("res://mods/prigozhin_fork/ui/tabs/comms_tab.gd")
const TroopsTabClass = preload("res://mods/prigozhin_fork/ui/tabs/troops_tab.gd")
const DealsTabClass = preload("res://mods/prigozhin_fork/ui/tabs/deals_tab.gd")
const OrderDispatch = preload("res://mods/prigozhin_fork/systems/order_dispatch.gd")

var _main_mod = null
var _game = null
var _tab_container: TabContainer = null
var _dashboard_tab = null
var _comms_tab = null
var _troops_tab = null
var _deals_tab = null

func _init() -> void:
	custom_minimum_size = Vector2(920, 600)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	visible = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		refresh_all()

func setup(main_mod, game) -> void:
	_main_mod = main_mod
	_game = game
	visible = true
	_build_ui()
	refresh_all()

func refresh_all() -> void:
	visible = true
	if _dashboard_tab and is_instance_valid(_dashboard_tab):
		_dashboard_tab.refresh()
	if _comms_tab and is_instance_valid(_comms_tab):
		_comms_tab.refresh()
	if _troops_tab and is_instance_valid(_troops_tab):
		_troops_tab.refresh()

func refresh_operational_briefing() -> void:
	if _dashboard_tab and is_instance_valid(_dashboard_tab):
		_dashboard_tab.refresh_operational_briefing()

func select_tab(tab_index: int) -> void:
	if _tab_container:
		_tab_container.current_tab = tab_index

func open_mironov_protocol_window() -> void:
	if _comms_tab and is_instance_valid(_comms_tab):
		_comms_tab.open_mironov_protocol_window()

func _refresh_selected_tab(tab_index: int) -> void:
	match tab_index:
		0:
			_dashboard_tab.refresh()
		1:
			_comms_tab.refresh()
		2:
			_troops_tab.refresh()
		3:
			_deals_tab.refresh()

func _build_ui() -> void:
	visible = true
	for child in get_children():
		child.queue_free()
	add_theme_constant_override("margin_top", 8)
	add_theme_constant_override("margin_bottom", 8)
	add_theme_constant_override("margin_left", 10)
	add_theme_constant_override("margin_right", 10)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.custom_minimum_size = Vector2(900, 580)
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	var top_bar: HBoxContainer = HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 32)
	var win_title: Label = Label.new()
	win_title.text = "★ СИТУАЦИОННЫЙ ШТАБ Е. В. ПРИГОЖИНА (ТУНОШНА) ★"
	win_title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.25))
	top_bar.add_child(win_title)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	var close_btn: Button = Button.new()
	close_btn.text = "✕ Закрыть"
	close_btn.pressed.connect(func():
		var p: Node = get_parent()
		while p and not (p is PanelContainer) and not (p is Window):
			p = p.get_parent()
		if p:
			p.visible = false
	)
	top_bar.add_child(close_btn)
	main_vbox.add_child(top_bar)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.custom_minimum_size = Vector2(900, 520)
	_tab_container.tab_changed.connect(func(idx_tab: int): _refresh_selected_tab(idx_tab))
	main_vbox.add_child(_tab_container)

	var callbacks: Dictionary = {
		"send_order": Callable(self, "send_order_to_game"),
		"select_tab": Callable(self, "select_tab"),
		"protocol": Callable(self, "open_mironov_protocol_window")
	}
	_dashboard_tab = DashboardTabClass.new()
	_comms_tab = CommsTabClass.new()
	_troops_tab = TroopsTabClass.new()
	_deals_tab = DealsTabClass.new()
	_dashboard_tab.configure(_main_mod, _game, callbacks)
	_comms_tab.configure(_main_mod, _game, callbacks)
	_troops_tab.configure(_main_mod, _game, callbacks)
	_deals_tab.configure(_main_mod, _game, callbacks)
	_tab_container.add_child(_dashboard_tab)
	_tab_container.set_tab_title(0, "📊 Обстановка и Ресурсы")
	_tab_container.add_child(_comms_tab)
	_tab_container.set_tab_title(1, "📞 Терминал связи")
	_tab_container.add_child(_troops_tab)
	_tab_container.set_tab_title(2, "⚔ Штурмовые группы (Туношна)")
	_tab_container.add_child(_deals_tab)
	_tab_container.set_tab_title(3, "📜 Договорённости и Контракты")

func send_order_to_game(text_order: String, pre_days: int = 2, place: Dictionary = {}) -> bool:
	var g = _game if _game else (_main_mod._last_game if _main_mod else null)
	if not g:
		return false
	return OrderDispatch.send(g, text_order, pre_days, place)
