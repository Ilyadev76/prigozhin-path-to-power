extends "res://mods/prigozhin_fork/ui/tabs/hq_tab_base.gd"

const ArmyOperations = preload("res://mods/prigozhin_fork/systems/army_operations.gd")
const PmcFacts = preload("res://mods/prigozhin_fork/systems/pmc_facts.gd")

var _lbl_duma: Label = null
var _lbl_wagner: Label = null
var _lbl_region: Label = null
var _lbl_rivals: Label = null
var _lbl_ops_briefing: Label = null

func configure(main_mod, game, callbacks: Dictionary) -> void:
	configure_base(main_mod, game, callbacks)
	_build_dashboard_tab(self)
	refresh()

func refresh() -> void:
	if Pax.world_busy():
		return
	_update_dashboard_cards()
	_update_operational_briefing()

func _build_dashboard_tab(parent: Control) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	parent.add_child(box)
	
	# Подзаголовок
	var role_lbl: Label = Label.new()
	role_lbl.text = _mod_tr("prigozhin_fork_role")
	role_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	box.add_child(role_lbl)
	
	var intro: Label = Label.new()
	intro.text = _mod_tr("prigozhin_fork_scenario_intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(0.82, 0.85, 0.90))
	box.add_child(intro)

	# Сетка 4 карточек
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	
	# Карточка 1: Дума и Партия
	var c1: PanelContainer = PanelContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c1.custom_minimum_size = Vector2(400, 95)
	c1.add_theme_stylebox_override("panel", _card_box_style(Color(0.09, 0.12, 0.16, 0.95), Color(0.25, 0.45, 0.75, 0.8)))
	_lbl_duma = Label.new()
	_lbl_duma.add_theme_color_override("font_color", Color(0.45, 0.75, 1.0))
	c1.add_child(_lbl_duma)
	grid.add_child(c1)
	
	# Карточка 2: Конкорд и Вагнер
	var c2: PanelContainer = PanelContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c2.custom_minimum_size = Vector2(400, 95)
	c2.add_theme_stylebox_override("panel", _card_box_style(Color(0.15, 0.09, 0.09, 0.95), Color(0.85, 0.25, 0.25, 0.8)))
	_lbl_wagner = Label.new()
	_lbl_wagner.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	c2.add_child(_lbl_wagner)
	grid.add_child(c2)
	
	# Карточка 3: Миронов и Туношна
	var c3: PanelContainer = PanelContainer.new()
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c3.custom_minimum_size = Vector2(400, 95)
	c3.add_theme_stylebox_override("panel", _card_box_style(Color(0.08, 0.14, 0.10, 0.95), Color(0.25, 0.75, 0.45, 0.8)))
	_lbl_region = Label.new()
	_lbl_region.add_theme_color_override("font_color", Color(0.50, 0.90, 0.60))
	c3.add_child(_lbl_region)
	grid.add_child(c3)
	
	# Карточка 4: АП и Конкуренты
	var c4: PanelContainer = PanelContainer.new()
	c4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c4.custom_minimum_size = Vector2(400, 95)
	c4.add_theme_stylebox_override("panel", _card_box_style(Color(0.14, 0.12, 0.08, 0.95), Color(0.85, 0.55, 0.20, 0.8)))
	_lbl_rivals = Label.new()
	_lbl_rivals.add_theme_color_override("font_color", Color(0.95, 0.75, 0.40))
	c4.add_child(_lbl_rivals)
	grid.add_child(c4)

	var briefing_panel: PanelContainer = PanelContainer.new()
	briefing_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing_panel.custom_minimum_size = Vector2(0, 96)
	briefing_panel.add_theme_stylebox_override("panel", _card_box_style(Color(0.11, 0.12, 0.15, 0.98), Color(0.78, 0.62, 0.28, 0.85)))
	var briefing_box: VBoxContainer = VBoxContainer.new()
	briefing_box.add_theme_constant_override("separation", 4)
	briefing_panel.add_child(briefing_box)
	var briefing_title: Label = Label.new()
	briefing_title.text = _mod_tr("prigozhin_fork_briefing_title")
	briefing_title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.25))
	briefing_title.add_theme_font_size_override("font_size", 14)
	briefing_box.add_child(briefing_title)
	_lbl_ops_briefing = Label.new()
	_lbl_ops_briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_ops_briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_ops_briefing.add_theme_color_override("font_color", Color(0.84, 0.86, 0.90))
	_lbl_ops_briefing.add_theme_font_size_override("font_size", 12)
	briefing_box.add_child(_lbl_ops_briefing)
	box.add_child(briefing_panel)
	
	var sep := HSeparator.new()
	box.add_child(sep)
	
	# Кнопки быстрых решений штаба
	# Динамический пульт управления штаба
	var act_header: Label = Label.new()
	act_header.text = "⚡ ОПЕРАТИВНОЕ КОМАНДОВАНИЕ И РАСПОРЯЖЕНИЯ:"
	act_header.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	box.add_child(act_header)

	var btn_grid: GridContainer = GridContainer.new()
	btn_grid.columns = 2
	btn_grid.add_theme_constant_override("h_separation", 12)
	btn_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(btn_grid)

	_add_dash_btn(btn_grid, _mod_tr("prigozhin_fork_movement_open"), func():
		select_tab(2)
	)
	_add_dash_btn(btn_grid, _mod_tr("prigozhin_fork_request_recruit"), func():
		select_tab(2)
	)

	_add_dash_btn(btn_grid, "🏭 Официальные переговоры с губернатором Мироновым (Сметы ИИ)", func():
		request_mironov_protocol()
	)

	_add_dash_btn(btn_grid, "🧠 Запросить у ИИ оперативные задачи по текущей обстановке", func():
		var g = _game if _game else (_main_mod._last_game if _main_mod else null)
		if _main_mod and g:
			_main_mod._request_ai_scenario(g)
	)

	_add_dash_btn(btn_grid, "📞 Открыть терминал закрытой связи с командованием", func():
		select_tab(1)
	)

	_add_dash_btn(btn_grid, _mod_tr("prigozhin_fork_newspaper_copy_open"), func():
		_show_newspaper_text()
	)

	_add_dash_btn(btn_grid, "📜 Открыть реестр действующих договоров и обязательств", func():
		select_tab(3)
	)

func _show_newspaper_text() -> void:
	if not _game or not _game.main or not _game.main.model:
		return
	var issue = _game.main.model.newspaper_issue
	if not (issue is Dictionary) or issue.is_empty():
		_game.toast(_mod_tr("prigozhin_fork_newspaper_copy_empty"))
		return
	var pieces: PackedStringArray = PackedStringArray()
	for section_key in ["local", "worldwide"]:
		var section = issue.get(section_key, {})
		if not (section is Dictionary):
			continue
		var title: String = str(section.get("title_name", "")).strip_edges()
		if not title.is_empty():
			pieces.append(title)
		var entries: Array = []
		if section.get("main") is Dictionary:
			entries.append(section["main"])
		if section.get("articles") is Array:
			entries.append_array(section["articles"])
		for article in entries:
			if not (article is Dictionary):
				continue
			for field in ["title", "subtitle", "text"]:
				var value: String = str(article.get(field, "")).strip_edges()
				if not value.is_empty():
					pieces.append(value)
			pieces.append("")
	if pieces.is_empty():
		_game.toast(_mod_tr("prigozhin_fork_newspaper_copy_empty"))
		return
	var text_box: TextEdit = TextEdit.new()
	text_box.editable = false
	text_box.text = "\n".join(pieces)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var window = _game.add_window(_mod_tr("prigozhin_fork_newspaper_copy_title"), text_box, Vector2(760, 560))
	if window:
		window.visible = true

func _add_dash_btn(parent: Control, text: String, fn: Callable) -> void:
	var btn: Button = Button.new()
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(420, 42)

	# Apple Glassmorphism Button Style
	var normal_sb: StyleBoxFlat = StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.12, 0.16, 0.22, 0.85)
	normal_sb.border_color = Color(0.25, 0.45, 0.75, 0.5)
	normal_sb.border_width_left = 1
	normal_sb.border_width_top = 1
	normal_sb.border_width_right = 1
	normal_sb.border_width_bottom = 1
	normal_sb.corner_radius_top_left = 8
	normal_sb.corner_radius_top_right = 8
	normal_sb.corner_radius_bottom_left = 8
	normal_sb.corner_radius_bottom_right = 8
	normal_sb.content_margin_left = 14
	normal_sb.content_margin_right = 14
	btn.add_theme_stylebox_override("normal", normal_sb)

	var hover_sb: StyleBoxFlat = normal_sb.duplicate()
	hover_sb.bg_color = Color(0.18, 0.25, 0.35, 0.95)
	hover_sb.border_color = Color(0.4, 0.7, 1.0, 0.9)
	btn.add_theme_stylebox_override("hover", hover_sb)

	var pressed_sb: StyleBoxFlat = normal_sb.duplicate()
	pressed_sb.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	pressed_sb.border_color = Color(0.3, 0.6, 0.9, 0.8)
	btn.add_theme_stylebox_override("pressed", pressed_sb)

	btn.pressed.connect(fn)
	parent.add_child(btn)

func _actual_wagner_position() -> String:
	if not _game or not _game.main or not _game.main.model or not _game.main.model.armies:
		return _mod_tr("prigozhin_fork_units_unavailable")
	var lines: PackedStringArray = PackedStringArray()
	var native_units: Array = ArmyOperations.player_units(_main_mod)
	for unit in native_units.slice(0, 6):
		var unit_name: String = str(unit.get("name", ""))
		if int(unit.get("prigozhin_fork_in_airlift", 0)) > 0:
			lines.append(_mod_tr("prigozhin_fork_airlift_unit") % [int(unit.get("id", 0)), unit_name, int(unit.get("humans", 0)), int(unit["prigozhin_fork_in_airlift"]), _mod_tr("prigozhin_fork_airlift_" + str(unit.get("airlift_status", "review")))])
			continue
		var province_id: int = int(unit.get("province", 0))
		var province_info: Dictionary = _game.province(_game.home_body(), province_id)
		var place: String = str(province_info.get("name", ""))
		if place.is_empty():
			place = _mod_tr("prigozhin_fork_units_sector") % province_id
		lines.append(_mod_tr("prigozhin_fork_pmc_position_line") % [int(unit.get("id", 0)), unit_name, place, int(unit.get("humans", 0))])
	if native_units.size() > 6:
		lines.append(_mod_tr("prigozhin_fork_pmc_position_more") % (native_units.size() - 6))
	if lines.is_empty():
		return _mod_tr("prigozhin_fork_troops_empty")
	return " / ".join(lines)

# Only a Russian government state can substantiate claims about its parliament.
func _native_nfw_status() -> String:
	if not _game or not _game.main or not _game.main.power:
		return _mod_tr("prigozhin_fork_native_politics_unavailable")
	var state: Dictionary = _game.main.power.state_
	if str(state.get("country", "")).to_lower() not in ["россия", "российская федерация", "russia", "russian federation"]:
		return _mod_tr("prigozhin_fork_native_politics_unavailable")
	var parliament = state.get("parliament", {})
	if not (parliament is Dictionary) or not (parliament.get("parties") is Array):
		return _mod_tr("prigozhin_fork_native_politics_unavailable")
	for party in parliament["parties"]:
		if not (party is Dictionary):
			continue
		var party_name: String = str(party.get("name", "")).to_lower()
		if "народный фронт возрождения" in party_name or party_name == "нфв":
			return _mod_tr("prigozhin_fork_native_politics_found") % int(party.get("seats", 0))
	return _mod_tr("prigozhin_fork_native_politics_absent")

func _update_dashboard_cards() -> void:
	if not _lbl_duma or not _main_mod:
		return
		
	var status: String = "НЕ ОБЪЯВЛЕНЫ"
	if _main_mod._early_elections_called and not _main_mod._elections_concluded:
		status = "ИДЁТ КАМПАНИЯ (2019)"
	elif _main_mod._elections_concluded:
		status = "ИТОГИ ПОДВЕДЕНЫ"
	elif _main_mod._early_elections_checked and not _main_mod._early_elections_called:
		status = "ПЛАНОВЫЕ (2021 ГОД)"
		
	_lbl_duma.text = _mod_tr("prigozhin_fork_politics_estimates") % [
		status, _main_mod._nfw_rating, _main_mod._duma_seats, _main_mod._duma_list_seats, _main_mod._duma_single_seats
	]
	_lbl_duma.text += "\n• " + _native_nfw_status()
	
	var actual_units: String = _actual_wagner_position()
	var game_balance: String = _mod_tr("prigozhin_fork_balance_unavailable")
	if _game:
		game_balance = str(snappedf(_game.money(), 0.01))
	_lbl_wagner.text = "⚔ %s\n• %s: %s\n• %s" % [
		_mod_tr("prigozhin_fork_units_sector_header"), _mod_tr("prigozhin_fork_game_balance"), game_balance,
		actual_units
	]

	var mood: String = "Напряжённый"
	if _main_mod._mironov_loyalty >= 60: mood = "Конструктивный"
	elif _main_mod._mironov_loyalty < 30: mood = "Враждебный"
	_lbl_region.text = "🌲 ЯРОСЛАВСКАЯ ОБЛАСТЬ И ТУНОШНА\n• Губернатор Д. Миронов: %d/100 (%s)\n• Проверки силовиков: %s\n• Резиденция: Туношна, Ярославская область" % [
		_main_mod._mironov_loyalty, mood, "АКТИВНЫ" if _main_mod._concord_inspections > 0 else "СВЁРНУТЫ"
	]
	
	_lbl_rivals.text = "🏛 СТАРАЯ ПЛОЩАДЬ И КОНКУРЕНТЫ\n• Давление Кремля на НФВ: %d/100\n• Влияние ЧВК «Редут»: %d/100 (Сирия)\n• Давление генералов МО («Патриот»): %d/100" % [
		_main_mod._kremlin_pressure, _main_mod._redut_influence, _main_mod._patriot_influence
	]

func refresh_operational_briefing() -> void:
	_update_operational_briefing()

func _update_operational_briefing() -> void:
	if not _lbl_ops_briefing or not _main_mod:
		return

	var airlift_status: String = _actual_wagner_position()

	var inspections_status: String = _mod_tr("prigozhin_fork_briefing_inspections_clear")
	if _main_mod._concord_inspections > 0:
		inspections_status = _mod_tr("prigozhin_fork_briefing_inspections_active")

	var risks: PackedStringArray = PackedStringArray()
	if _main_mod._kremlin_pressure >= 60:
		risks.append(_mod_tr("prigozhin_fork_briefing_risk_pressure") % [_main_mod._kremlin_pressure])
	if _main_mod._concord_inspections > 0:
		risks.append(_mod_tr("prigozhin_fork_briefing_risk_inspections"))
	if _main_mod._mironov_loyalty < 30:
		risks.append(_mod_tr("prigozhin_fork_briefing_risk_mironov") % [_main_mod._mironov_loyalty])
	if _main_mod._airlift_state == "preparing" or _main_mod._airlift_state == "transit":
		risks.append(_mod_tr("prigozhin_fork_legacy_airlift_unverified"))
	if not _main_mod._elections_concluded and _main_mod._nfw_rating < 5.0:
		risks.append(_mod_tr("prigozhin_fork_briefing_risk_election") % [_main_mod._nfw_rating])
	var actual_money: float = _game.money() if _game else 0.0
	if actual_money < 2.0:
		risks.append(_mod_tr("prigozhin_fork_briefing_risk_reserves") % [actual_money])

	var risks_text: String = _mod_tr("prigozhin_fork_briefing_risk_none")
	if not risks.is_empty():
		risks_text = " • ".join(risks)

	var lines: PackedStringArray = PackedStringArray([
		_native_pmc_summary() + "\n" + airlift_status,
		_mod_tr("prigozhin_fork_briefing_base") % [inspections_status, actual_money],
		_mod_tr("prigozhin_fork_briefing_politics") % [_main_mod._kremlin_pressure, _main_mod._mironov_loyalty],
		_mod_tr("prigozhin_fork_briefing_risks") % [risks_text]
	])
	_lbl_ops_briefing.text = "\n".join(lines)

func _native_pmc_summary() -> String:
	var facts: Dictionary = PmcFacts.capture(_main_mod, _game)
	if not bool(facts.get("available", false)):
		return _mod_tr("prigozhin_fork_units_unavailable")
	return _mod_tr("prigozhin_fork_pmc_native_count") % [int(facts["total_native_pmc_units"]), int(facts["total_native_pmc_humans"])]
