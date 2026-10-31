extends "res://mods/prigozhin_fork/ui/tabs/hq_tab_base.gd"

const PmcFacts = preload("res://mods/prigozhin_fork/systems/pmc_facts.gd")

var _current_char_id: String = "mo"
var _char_list_box: VBoxContainer = null
var _lbl_char_name: Label = null
var _lbl_char_role: Label = null
var _lbl_char_status: Label = null
var _dialog_scroll: ScrollContainer = null
var _dialog_history_box: VBoxContainer = null
var _actions_box: VBoxContainer = null
var _input_line: LineEdit = null
var _btn_send: Button = null
var _chat_pending: bool = false
var _chat_history: Dictionary = {}

func configure(main_mod, game, callbacks: Dictionary) -> void:
	configure_base(main_mod, game, callbacks)
	if _main_mod:
		_chat_history = _main_mod._comms_history
	_build_comms_tab(self)
	refresh()

func refresh() -> void:
	if _main_mod:
		_chat_history = _main_mod._comms_history
	_refresh_character_view()

func _build_comms_tab(parent: Control) -> void:
	var content_split: HBoxContainer = HBoxContainer.new()
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_split.add_theme_constant_override("separation", 12)
	parent.add_child(content_split)
	
	# Левая колонка: абоненты
	var left_box: VBoxContainer = VBoxContainer.new()
	left_box.custom_minimum_size = Vector2(260, 480)
	left_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var left_header: Label = Label.new()
	left_header.text = "КАНАЛЫ СВЯЗИ И КОМАНДОВАНИЕ:"
	left_header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	left_box.add_child(left_header)
	
	_char_list_box = VBoxContainer.new()
	_char_list_box.add_theme_constant_override("separation", 6)
	left_box.add_child(_char_list_box)
	
	_add_character_btn("mo", "🎖 Министерство обороны РФ", "Генштаб / Кураторы операций")
	_add_character_btn("wagner", "⚔ Командиры «Вагнера»", "«Лотос», «Ратибор» / Сирия, Африка")
	_add_character_btn("mironov", "🌲 Губернатор Д. Миронов", "Ярославская область / резиденция в Туношне")
	_add_character_btn("kremlin", "🏛 Администрация Президента", "Старая площадь / Госдума 2019")
	_add_character_btn("concord", "📦 Дирекция «Конкорда»", "ГК «Конкорд» / Питание гарнизонов")
	
	content_split.add_child(left_box)
	
	var sep_v: VSeparator = VSeparator.new()
	content_split.add_child(sep_v)
	
	# Правая колонка
	var right_box: VBoxContainer = VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 8)
	
	var char_header_panel: PanelContainer = PanelContainer.new()
	char_header_panel.add_theme_stylebox_override("panel", _card_box_style(Color(0.12, 0.14, 0.18, 0.95), Color(0.4, 0.5, 0.6, 0.6)))
	
	var char_info_box: VBoxContainer = VBoxContainer.new()
	_lbl_char_name = Label.new()
	_lbl_char_name.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	char_info_box.add_child(_lbl_char_name)
	
	_lbl_char_role = Label.new()
	_lbl_char_role.add_theme_color_override("font_color", Color(0.70, 0.75, 0.80))
	char_info_box.add_child(_lbl_char_role)
	
	_lbl_char_status = Label.new()
	char_info_box.add_child(_lbl_char_status)
	char_header_panel.add_child(char_info_box)
	right_box.add_child(char_header_panel)
	
	# Лента диалога
	_dialog_scroll = ScrollContainer.new()
	_dialog_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialog_scroll.custom_minimum_size = Vector2(0, 200)
	
	_dialog_history_box = VBoxContainer.new()
	_dialog_history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_history_box.add_theme_constant_override("separation", 6)
	_dialog_scroll.add_child(_dialog_history_box)
	right_box.add_child(_dialog_scroll)
	
	# Действия
	_actions_box = VBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 4)
	right_box.add_child(_actions_box)
	
	# Ввод сообщения
	var input_row: HBoxContainer = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	
	_input_line = LineEdit.new()
	_input_line.placeholder_text = "Введите распоряжение, вопрос или предложение..."
	_input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_line.text_submitted.connect(func(_t: String):
		_send_player_message()
	)
	input_row.add_child(_input_line)
	
	_btn_send = Button.new()
	_btn_send.text = "✉ Отправить"
	_btn_send.pressed.connect(_send_player_message)
	input_row.add_child(_btn_send)
	right_box.add_child(input_row)
	
	content_split.add_child(right_box)
	_select_character("mo")

func _add_character_btn(id: String, title: String, subtitle: String) -> void:
	var btn: Button = Button.new()
	btn.text = "%s\n[%s]" % [title, subtitle]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(250, 48)
	btn.pressed.connect(func():
		_select_character(id)
	)
	_char_list_box.add_child(btn)

func _select_character(id: String) -> void:
	_current_char_id = id
	_refresh_character_view()

func _refresh_character_view() -> void:
	if not _lbl_char_name:
		return
		
	if _current_char_id == "mo":
		_lbl_char_name.text = "Министерство обороны РФ (Оперативное управление / Генштаб)"
		_lbl_char_role.text = "Фрунзенская набережная, Москва • Согласование сирийских и зарубежных задач"
		_lbl_char_status.text = "Давление МО («Патриот»): %d/100  |  Квота контрактов питания: $%.1f / $%.1f млн" % [
			_main_mod._patriot_influence if _main_mod else 40,
			_main_mod._concord_fulfilled_quota if _main_mod else 0.0,
			_main_mod._concord_annual_quota if _main_mod else 24.0
		]
		_lbl_char_status.add_theme_color_override("font_color", Color(0.9, 0.45, 0.3))
	elif _current_char_id == "wagner":
		_lbl_char_name.text = "Совет командиров ЧВК «Вагнер» («Лотос», «Ратибор», «Седой»)"
		_lbl_char_role.text = "Полевой командный пункт • Управление экспедиционными корпусами в Сирии и Африке"
		var facts: Dictionary = PmcFacts.capture(_main_mod, _game)
		_lbl_char_status.text = (_mod_tr("prigozhin_fork_pmc_native_count") % [int(facts.get("total_native_pmc_units", 0)), int(facts.get("total_native_pmc_humans", 0))]) if bool(facts.get("available", false)) else _mod_tr("prigozhin_fork_units_unavailable")
		_lbl_char_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	elif _current_char_id == "mironov":
		_lbl_char_name.text = "Дмитрий Юрьевич Миронов (Губернатор Ярославской области)"
		_lbl_char_role.text = "Здание правительства области, Ярославль • Бывший замминистра МВД РФ"
		var loyalty: int = _main_mod._mironov_loyalty if _main_mod else 35
		var inspections: int = _main_mod._concord_inspections if _main_mod else 0
		var mood: String = "Конструктивный" if loyalty >= 60 else ("Напряжённый" if loyalty >= 30 else "Враждебный")
		_lbl_char_status.text = "Лояльность губернатора: %d/100 (%s)  |  Проверки аэродрома: %s" % [
			loyalty, mood, "АКТИВНЫ" if inspections > 0 else "СВЁРНУТЫ"
		]
		_lbl_char_status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5) if loyalty >= 50 else Color(0.9, 0.4, 0.4))
	elif _current_char_id == "kremlin":
		_lbl_char_name.text = "Администрация Президента РФ (Куратор внутренней политики)"
		_lbl_char_role.text = "Старая площадь, Москва • Контроль выборов в Госдуму и баланса элит"
		_lbl_char_status.text = "Давление Кремля на НФВ: %d/100  |  Партийный рейтинг: %.1f%%  |  Мест в Думе: %d" % [
			_main_mod._kremlin_pressure if _main_mod else 15,
			_main_mod._nfw_rating if _main_mod else 4.2,
			_main_mod._duma_seats if _main_mod else 0
		]
		_lbl_char_status.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
	elif _current_char_id == "concord":
		_lbl_char_name.text = "Дирекция снабжения ГК «Конкорд»"
		_lbl_char_role.text = "Комбинаты армейского питания и тыловая логистика"
		_lbl_char_status.text = _mod_tr("prigozhin_fork_supply_cash") % (_game.money() if _game else 0.0)
		_lbl_char_status.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))

	_render_chat_history()
	_render_action_buttons()

func _render_chat_history() -> void:
	if not _dialog_history_box:
		return
	for child in _dialog_history_box.get_children():
		child.queue_free()
		
	var history: Array = _chat_history.get(_current_char_id, [])
	if history.is_empty():
		var empty: Label = Label.new()
		empty.text = _mod_tr("prigozhin_fork_comms_empty")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_dialog_history_box.add_child(empty)

	for msg in history:
		var row: PanelContainer = PanelContainer.new()
		var r_sb: StyleBoxFlat = StyleBoxFlat.new()
		r_sb.corner_radius_top_left = 4
		r_sb.corner_radius_top_right = 4
		r_sb.corner_radius_bottom_left = 4
		r_sb.corner_radius_bottom_right = 4
		r_sb.content_margin_left = 8
		r_sb.content_margin_top = 6
		r_sb.content_margin_right = 8
		r_sb.content_margin_bottom = 6
		
		var is_player: bool = (msg.get("role") == "player")
		var is_system: bool = (msg.get("role") == "system")
		if is_player:
			r_sb.bg_color = Color(0.14, 0.18, 0.24, 0.9)
			r_sb.border_color = Color(0.3, 0.6, 0.9, 0.8)
			r_sb.border_width_left = 3
		else:
			r_sb.bg_color = Color(0.12, 0.12, 0.14, 0.85)
			r_sb.border_color = Color(0.7, 0.6, 0.2, 0.7)
			r_sb.border_width_left = 3
			
		row.add_theme_stylebox_override("panel", r_sb)
		
		var msg_box: VBoxContainer = VBoxContainer.new()
		msg_box.add_theme_constant_override("separation", 6)
		row.add_child(msg_box)

		var msg_lbl: RichTextLabel = RichTextLabel.new()
		msg_lbl.fit_content = true
		msg_lbl.selection_enabled = true
		msg_lbl.context_menu_enabled = true
		msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var author: String = _mod_tr("prigozhin_fork_comms_system") if is_system else ("Евгений Пригожин" if is_player else _get_char_title())
		var col_hex: String = "#e5f2ff" if is_player else "#f2d9b3"
		msg_lbl.bbcode_enabled = true
		var raw_msg_text: String = str(msg.get("text", ""))
		msg_lbl.text = "[color=" + col_hex + "]▶ " + author + ": \n" + raw_msg_text + "[/color]"
		msg_box.add_child(msg_lbl)

		# Для ответов собеседников (Лотос, Шойгу, Миронов, Кириенко) добавляем кнопку отправки договорённости в приказы
		if not is_player and not is_system:
			var btn_deal_to_orders: Button = Button.new()
			btn_deal_to_orders.text = _mod_tr("prigozhin_fork_comms_reply_to_order")
			btn_deal_to_orders.custom_minimum_size = Vector2(240, 28)
			btn_deal_to_orders.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var partner_name: String = author
			btn_deal_to_orders.pressed.connect(func():
				var clean_text = raw_msg_text.replace("\n", " ").strip_edges()
				var order_text: String = _mod_tr("prigozhin_fork_comms_order_from_reply") % [partner_name, clean_text]
				var accepted: bool = send_order_to_game(order_text)
				if accepted and _game:
					_game.toast(_mod_tr("prigozhin_fork_comms_order_accepted"))
			)
			msg_box.add_child(btn_deal_to_orders)

		_dialog_history_box.add_child(row)
		
	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	if _dialog_scroll:
		var bar: VScrollBar = _dialog_scroll.get_v_scroll_bar()
		if bar:
			_dialog_scroll.scroll_vertical = int(bar.max_value)

func _get_char_title() -> String:
	if _current_char_id == "mo": return "Представитель Минобороны РФ"
	elif _current_char_id == "wagner": return "Командир «Лотос»"
	elif _current_char_id == "mironov": return "Губернатор Дмитрий Миронов"
	elif _current_char_id == "kremlin": return "Куратор Администрации Президента"
	return "Дирекция ГК «Конкорд»"

func _render_action_buttons() -> void:
	if not _actions_box:
		return
	for child in _actions_box.get_children():
		child.queue_free()
		
	_add_action_btn("💬 Вызвать на прямой разговор (системный экран игры)", func():
		_open_native_talk()
	)
		
	if _current_char_id == "mo":
		_add_action_btn(_mod_tr("prigozhin_fork_request_mo_coord"), func():
			send_order_to_game(_mod_tr("prigozhin_fork_request_mo_coord_order"))
		)
		_add_action_btn(_mod_tr("prigozhin_fork_request_mo_supply"), func():
			send_order_to_game(_mod_tr("prigozhin_fork_request_mo_supply_order"))
		)
	elif _current_char_id == "wagner":
		_add_action_btn(_mod_tr("prigozhin_fork_movement_open"), func():
			select_tab(2)
		)
		_add_action_btn(_mod_tr("prigozhin_fork_request_recruit"), func():
			select_tab(2)
		)
		_add_action_btn(_mod_tr("prigozhin_fork_request_supply"), func():
			send_order_to_game(_mod_tr("prigozhin_fork_request_supply_order"))
		)
	elif _current_char_id == "mironov":
		_add_action_btn(_mod_tr("prigozhin_fork_request_roads"), func():
			send_order_to_game(_mod_tr("prigozhin_fork_request_roads_order"))
		)
		_add_action_btn(_mod_tr("prigozhin_fork_request_mironov_agenda"), func():
			open_mironov_protocol_window()
		)
	elif _current_char_id == "kremlin":
		_add_action_btn(_mod_tr("prigozhin_fork_request_party"), func():
			send_order_to_game(_mod_tr("prigozhin_fork_request_party_order"))
		)
		_add_action_btn(_mod_tr("prigozhin_fork_request_media"), func():
			send_order_to_game(_mod_tr("prigozhin_fork_request_media_order"))
		)
	elif _current_char_id == "concord":
		_add_action_btn(_mod_tr("prigozhin_fork_request_concord"), func():
			send_order_to_game(_mod_tr("prigozhin_fork_request_concord_order"))
		)

func _add_action_btn(text: String, fn: Callable) -> void:
	var btn: Button = Button.new()
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 32)
	btn.pressed.connect(fn)
	_actions_box.add_child(btn)

func _send_player_message() -> void:
	if not _input_line or _chat_pending:
		return
	var text: String = _input_line.text.strip_edges()
	if text == "":
		return
	_input_line.text = ""
	_add_chat_message("player", text)
	
	if _btn_send:
		_btn_send.disabled = true
	# Подтягиваем реальную историю переписки из игры для любого персонажа
	var real_npc_name: String = ""
	if _current_char_id == "mo": real_npc_name = "Сергей Шойгу"
	elif _current_char_id == "wagner": real_npc_name = "Антон Елизаров («Лотос»)"
	elif _current_char_id == "mironov": real_npc_name = "Дмитрий Миронов"
	elif _current_char_id == "kremlin": real_npc_name = "Сергей Кириенко"

	var history_context: String = ""
	if _main_mod and _main_mod.has_method("get_recent_talk_summary") and real_npc_name != "":
		history_context = _main_mod.get_recent_talk_summary(real_npc_name, 4)

	var prompt: String = "Ролевая переписка в альтернативной истории России с сентября 2018 года. Собеседник — " + _get_char_title() + ". "
	prompt += "Персонаж действует самостоятельно, учитывает собственные интересы и не обязан соглашаться. "
	prompt += "Используй доступные факты и историю, не придумывай подтверждённые изменения игры или совершённые сделки. "
	prompt += "Если сведений недостаточно, укажи неопределённость. Отвечай по существу, длина зависит от запроса.\n"
	if history_context != "":
		prompt += "История разговора:\n" + history_context + "\n"
	var current_history: Array = _chat_history.get(_current_char_id, [])
	var first: int = maxi(0, current_history.size() - 6)
	for i in range(first, current_history.size()):
		var item: Dictionary = current_history[i]
		prompt += str(item.get("role", "")) + ": " + str(item.get("text", "")) + "\n"

	var target_id: String = _current_char_id
	prompt += "\nОтвечай только JSON: {\"reply\": \"text\"}. Не утверждай, что действие выполнено, если это не подтверждено состоянием игры."
	if not _main_mod:
		if _btn_send:
			_btn_send.disabled = false
		return
	_chat_pending = true
	var request_game = _game
	var requested: bool = _main_mod.ask_ai("hq_comms", prompt, {"pmc_observation": PmcFacts.capture(_main_mod, request_game)}, func(answer: Dictionary) -> void:
		if not is_instance_valid(self):
			return
		if not _main_mod or _main_mod._last_game != request_game:
			_chat_pending = false
			if _btn_send:
				_btn_send.disabled = false
			return
		_chat_pending = false
		if _btn_send:
			_btn_send.disabled = false
		var reply: String = str(answer.get("reply", "")).strip_edges()
		var reply_role: String = target_id
		if reply.is_empty():
			reply = _mod_tr("prigozhin_fork_comms_no_reply")
			reply_role = "system"
		if not _chat_history.has(target_id):
			_chat_history[target_id] = []
		_chat_history[target_id].append({"role": reply_role, "text": reply})
		if _current_char_id == target_id:
			_render_chat_history()
	)
	if not requested:
		_chat_pending = false
		if _btn_send:
			_btn_send.disabled = false
		if _game:
			_game.toast(_mod_tr("prigozhin_fork_comms_no_reply"))

func _add_chat_message(role: String, text: String) -> void:
	if not _chat_history.has(_current_char_id):
		_chat_history[_current_char_id] = []
	_chat_history[_current_char_id].append({"role": role, "text": text})
	_render_chat_history()

func _open_native_talk() -> void:
	if not _game:
		return
	if _main_mod:
		_main_mod._capture_pmc_facts()
	var b: String = _game.home_body() if _game.has_method("home_body") else "Земля"
	var char_name: String = "Сергей Шойгу"
	var who: String = "Министр обороны РФ"
	var lore: String = "Глава Минобороны РФ. Контролирует группировку в Сирии и квоты поставок."
	var char_trait: String = "Министр обороны действует самостоятельно, учитывая полномочия ведомства, интересы и историю отношений."
	
	if _current_char_id == "wagner":
		char_name = "Антон Елизаров («Лотос»)"
		who = "Старший командир штурмовиков ЧВК «Вагнер»"
		lore = "Герой России, кадровый офицер. Командует штурмами в Сирии и Африке."
		char_trait = "Командир учитывает положение подразделений, интересы бойцов и собственные отношения с Пригожиным."
	elif _current_char_id == "mironov":
		char_name = "Дмитрий Миронов"
		who = "Губернатор Ярославской области"
		lore = "Генерал-лейтенант полиции. Руководит областью, где находится резиденция в Туношне."
		char_trait = "Губернатор действует самостоятельно, учитывает интересы региона, закон и историю отношений."
	elif _current_char_id == "kremlin":
		char_name = "Сергей Кириенко"
		who = "Первый замруководителя Администрации Президента РФ"
		lore = "Куратор внутренней политики Кремля. Ведает выборами в Госдуму."
		char_trait = "Представитель администрации учитывает полномочия и интересы федеральной власти; его реакция зависит от обстоятельств."
	elif _current_char_id == "concord":
		char_name = "Дирекция «Конкорда»"
		who = "Начальник службы тыла и питания"
		lore = "Служба тылового снабжения военных гарнизонов."
		char_trait = "Деловой снабженец отделяет подтверждённые сведения от оценок и уточняет недостающие данные."
		
	if _game.has_character(char_name) and _game.main and _game.main.has_method("conversation"):
		_game.main.conversation().open("person", char_name, who)
		return
	var opened: bool = _game.add_character(b, {
		"name": char_name,
		"who": who,
		"lore": lore,
		"character": char_trait,
		"age": 50,
		"чем_занят": who,
		"wants": "Координация с Пригожиным"
	}, "", true)
	if not opened:
		_game.toast(_mod_tr("prigozhin_fork_comms_no_reply"))

# ==============================================================================
# ВКЛАДКА: ШТУРМОВЫЕ ГРУППЫ И ВОЙСКА ЧВК (ТУНОШНА)
# ==============================================================================
var _troops_list_container: VBoxContainer = null

func open_mironov_protocol_window() -> void:
	var g = _game if _game else (_main_mod._last_game if _main_mod else null)
	if not g or not _main_mod:
		return
	var prompt: String = "As the governor of Yaroslavl region, outline possible topics for a conversation with Prigozhin. Treat any prices and commitments as unverified proposals. Do not claim a deal exists or an action has happened. Return JSON: {\"summary\": \"text\"}."
	var data: Dictionary = {"governor_relations": _main_mod._mironov_loyalty, "actual_game_money_millions": g.money()}
	var sent: bool = _main_mod.ask_ai("mironov_agenda", prompt, data, func(answer: Dictionary) -> void:
		if not is_instance_valid(self) or not _main_mod or _main_mod._last_game != g:
			return
		var summary: String = str(answer.get("summary", "")).strip_edges()
		if summary.is_empty():
			g.toast(_mod_tr("prigozhin_fork_comms_no_reply"))
			return
		if not _chat_history.has("mironov"):
			_chat_history["mironov"] = []
		_chat_history["mironov"].append({"role": "mironov", "text": summary})
		if _current_char_id == "mironov":
			_render_chat_history()
		g.toast(_mod_tr("prigozhin_fork_mironov_agenda_ready"))
	)
	if not sent:
		g.toast(_mod_tr("prigozhin_fork_comms_no_reply"))
