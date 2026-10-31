extends PaxMod

# ==============================================================================
# ПРИГОЖИН: ПУТЬ К ВЛАСТИ — ОСНОВНОЙ СИСТЕМНЫЙ СКРИПТ (GODOT 4)
# ==============================================================================

# Хронометраж и симуляция
var _days_count: int = 0
var _days_accumulator: int = 0
var _early_elections_checked: bool = false
var _early_elections_called: bool = false
var _elections_concluded: bool = false

# Партия «Народный Фронт Возрождения» (НФВ) — Гражданский сектор
var _nfw_founded: bool = false
var _nfw_rating: float = 4.2       # Начальный рейтинг поддержки (ниже 5% барьера)
var _nfw_activists: int = 1500     # Безоружный гражданский актив (юристы, волонтёры)
var _nfw_regional_cells: int = 3   # Число региональных отделений (старт: 3 региона)
var _nfw_campaign_fund: float = 0.0 # Вложенные миллионы в кампанию
var _media_power: float = 0.0      # Медийный вес (сетка «Патриот», военкоры)

# Парламент (Смешанная система: 225 списки + 225 округа = 450 мест)
# ТЕХНИЧЕСКИЙ ДОЛГ: Коэффициент 1.18 для перераспределения мандатов партий ниже 5%
# является эвристикой. В будущем требуется полная модель распределения Хэйра/Д’Ондта.
var _duma_seats: int = 0
var _duma_list_seats: int = 0
var _duma_single_seats: int = 0

# ГК «Конкорд» (Бизнес-сектор и контрактная бухгалтерия)
var _concord_workers: int = 12000     # Гражданский персонал комбинатов питания
var _concord_annual_quota: float = 24.0 # Доступная годовая квота контрактов МО ($ млн)
var _concord_fulfilled_quota: float = 0.0 # Уже освоенный объём в текущем году
var _concord_inspections: int = 0    # Текущие активные проверки (0 или 1, сгорают со временем)

# Теневой сектор ЧВК «Вагнер» (Оценочные данные зарубежных контингентов)
var _wagner_fighters_estimate: int = 3500 # Оценочная численность в Сирии/Африке
var _gold_reserves: float = 12.0          # Оборотный баланс / казна структур Пригожина ($ млн)

# Раздельные счета (строго из существующего баланса gold_reserves, без создания ресурсов с нуля)
var _wallet_wagner_usd: float = 0.0       # Касса ЧВК
var _wallet_concord_usd: float = 0.0      # Безнал ГК «Конкорд»
var _wallet_nfv_usd: float = 0.0          # Фонд партии «НФВ»
var _barter_gold_kg: float = 0.0          # Золото (кг)
var _barter_oil_barrels: float = 0.0      # Нефть (баррелей)

# Операция переброски 1-й и 2-й ШГ в Бенгази (Ливия)
# Состояния: 'ready' (Туношна) -> 'preparing' (погрузка) -> 'transit' (перелёт) -> 'arrived' (Бенгази, выгрузка)
var _airlift_state: String = "ready"
var _airlift_days_in_flight: int = 0
var _airlift_cost_spent: float = 0.0
var _hafta_payment_received: bool = false
var _airlift_destination_missing_logged: bool = false

# Авторитет и своенравие командиров
var _cmd_lotos_trust: int = 80            # Доверие Антона Елизарова («Лотос»)
var _cmd_lotos_readiness: int = 85        # Готовность бойцов к штурмам
var _cmd_utkin_trust: int = 90            # Доверие Дмитрия Уткина («Вагнер»)

# Отношения и давление внешних институтов (Автономность мира)
var _kremlin_pressure: int = 15     # Внимание и противодействие Старой площади (0-100)
var _mironov_loyalty: int = 50      # Отношения с губернатором Дмитрием Мироновым (0-100)
var _comms_history: Dictionary = {}
var _deals: Array = []
var _pmc_recruitment: Array = []
var _pmc_recruit_sources: Dictionary = {}
var _pmc_mandates: Array = []
var _pmc_movements: Array = []
var _pmc_airlifts: Array = []
var _pmc_ai_facts: String = ""
var _pmc_commander_pending: bool = false
var _pmc_commander_generation: int = 0
var _pmc_commander_waiting: bool = false
var _pmc_native_finish_waiting: bool = false
var _custom_wagner_detachments: Array = []              # Журнал договоренностей: partner, title, terms, date, status, risk, cost
var _last_confirmed_order_hash: String = "" # Защита от повторного исполнения приказов
var _pending_orders: Array = []     # Активные распоряжения
var _autonomous_contact_pending: bool = false
var _autonomous_call_timer: int = 0 # Таймер автономных обращений NPC
var _redut_influence: int = 45      # Активность конкурентов из ЧВК «Редут» (0-100)
var _patriot_influence: int = 40    # Давление армейских конкурентов МО (0-100)
var _shoigu_hostile: bool = false

var _last_game: PaxGame = null

# Интерактивный диалоговый центр (МО РФ, Вагнер, Миронов, АП)
const CharacterDialogClass = preload("res://mods/prigozhin_fork/ui/character_dialog_window.gd")
const ArmyOperations = preload("res://mods/prigozhin_fork/systems/army_operations.gd")
const PmcOrderGuard = preload("res://mods/prigozhin_fork/systems/pmc_order_guard.gd")
const PmcRecruitGuard = preload("res://mods/prigozhin_fork/systems/pmc_recruit_guard.gd")
const CivilianMarks = preload("res://mods/prigozhin_fork/systems/civilian_marks.gd")
const WorldCycle = preload("res://mods/prigozhin_fork/systems/world_cycle.gd")
const AiContacts = preload("res://mods/prigozhin_fork/systems/ai_contacts.gd")
const PmcFacts = preload("res://mods/prigozhin_fork/systems/pmc_facts.gd")
const PmcCommanders = preload("res://mods/prigozhin_fork/systems/pmc_commanders.gd")
const PmcOrderBridge = preload("res://mods/prigozhin_fork/systems/pmc_order_bridge.gd")
const NativeRecruitEvaluation = preload("res://mods/prigozhin_fork/systems/pmc_order_evaluation.gd")
const NativeRecruitExecution = preload("res://mods/prigozhin_fork/systems/pmc_order_execution.gd")
const NativeRecruitTimeline = preload("res://mods/prigozhin_fork/systems/pmc_order_timeline.gd")
const PmcAirlift = preload("res://mods/prigozhin_fork/systems/pmc_airlift.gd")
const NativeAirliftTreasury = preload("res://mods/prigozhin_fork/systems/pmc_airlift_treasury.gd")
var _dialog_ui: Control = null
var _dialog_panel: PanelContainer = null
var _top_hq_btn: Button = null
var _bottom_hq_btn: Button = null

func _mod_loaded() -> void:
	log_info("prigozhin_fork: loaded advanced political and economic simulation")
	var evaluation_error: String = Pax.replace_service("order_evaluation", NativeRecruitEvaluation.resource_path)
	var execution_error: String = Pax.replace_service("order_execution", NativeRecruitExecution.resource_path)
	var timeline_error: String = Pax.replace_service("rewind", NativeRecruitTimeline.resource_path)
	var airlift_error: String = Pax.replace_service("treasury", NativeAirliftTreasury.resource_path)
	if not airlift_error.is_empty():
		log_warning("prigozhin_fork airlift treasury: " + airlift_error)
	Pax.step_stage("prigozhin_fork_airlift", Callable(self, "_step_pmc_airlift"), {"after": "armies"})
	if not evaluation_error.is_empty() or not execution_error.is_empty() or not timeline_error.is_empty():
		log_warning("prigozhin_fork native recruitment services: " + evaluation_error + " " + execution_error + " " + timeline_error)
	
	Pax.bus.on("hud_built", Callable(self, "_on_hud_built"), 50, "prigozhin_fork")
	hook("order_parsed", func(data: Dictionary) -> void: PmcOrderGuard.apply(self, data))
	hook("order_parsed", func(data: Dictionary) -> void: PmcRecruitGuard.apply(self, data))
	hook("order_confirmed", func(data: Dictionary) -> void:
		var order = data.get("order")
		if _last_game and order is Dictionary:
			PmcOrderBridge.confirm(self, _last_game.main, order)
	)
	hook("order_card", func(data: Dictionary) -> void:
		var order = data.get("order")
		var lines = data.get("lines")
		if order is Dictionary and order.has("prigozhin_fork_recruit_proposal") and lines is Array:
			lines.append(tr_key("prigozhin_fork_native_recruit_quote") % str(snappedf(float(order.get("prigozhin_fork_recruit_quote", 0.0)), 0.000001)))
			lines.append(tr_key("prigozhin_fork_native_recruit_card"))
	)
	
	hook("ai_request", func(d: Dictionary) -> void:
		if not d.has("system"):
			return
		var sys: String = str(d["system"])
		if "[PRIGOZHIN_FORK_RULES_INJECTED]" in sys:
			return

		d["system"] = sys + "\n\n[PRIGOZHIN_FORK_RULES_INJECTED]\n" + tr_key("prigozhin_fork_system_prompt")
		var channel: String = str(d.get("channel", ""))
		if channel == "interpreter":
			d["system"] = str(d["system"]) + "\n" + tr_key("prigozhin_fork_native_recruit_ai_rule")
		if channel in ["talk", "interpreter", "report"] and not _pmc_ai_facts.is_empty():
			d["user"] = str(d.get("user", "")) + "\n" + tr_key("prigozhin_fork_pmc_facts_rules") + "\n" + _pmc_ai_facts
	)
	

func _mod_unloaded() -> void:
	_pmc_commander_generation += 1
	_pmc_commander_pending = false
	_pmc_commander_waiting = false
	_pmc_native_finish_waiting = false
	_last_game = null

func _world_ready(game: PaxGame) -> void:
	_last_game = game
	_pmc_commander_generation += 1
	_pmc_commander_pending = false
	_pmc_commander_waiting = false
	_pmc_native_finish_waiting = false
	_pmc_ai_facts = ""
	PmcOrderBridge.synchronize(self, game)
	_capture_pmc_facts()
	_setup_hud(game)

func _on_hud_built(game: PaxGame) -> void:
	_last_game = game
	if not is_instance_valid(_dialog_panel):
		_setup_hud(game)

func _setup_hud(game: PaxGame) -> void:
	if not game:
		return
	if is_instance_valid(_dialog_panel):
		return
		
	# Создание единого интерфейса штаба как штатного окна игры
	_dialog_ui = CharacterDialogClass.new()
	_dialog_ui.setup(self, game)
	_dialog_panel = game.add_window("★ Штаб связи и приказов", _dialog_ui, Vector2(960, 640))
	if _dialog_panel:
		_dialog_panel.visible = false

func _toggle_dialog_window() -> void:
	if not _dialog_panel or not is_instance_valid(_dialog_panel):
		if _last_game:
			_setup_hud(_last_game)
	if _dialog_panel and is_instance_valid(_dialog_panel):
		_dialog_panel.visible = not _dialog_panel.visible
		if _dialog_panel.visible:
			_dialog_panel.move_to_front()
			if _dialog_ui and is_instance_valid(_dialog_ui):
				_dialog_ui.visible = true
				if _dialog_ui.has_method("refresh_all"):
					_dialog_ui.refresh_all()

func _refresh_ui() -> void:
	if _last_game:
		PmcOrderBridge.synchronize(self, _last_game)
		PmcAirlift.flush(self, _last_game)
	_capture_pmc_facts()
	if _dialog_ui and is_instance_valid(_dialog_ui) and _dialog_ui.has_method("refresh_all"):
		_dialog_ui.refresh_all()

func _capture_pmc_facts() -> void:
	var facts: Dictionary = PmcFacts.capture(self, _last_game)
	if bool(facts.get("available", false)):
		_pmc_ai_facts = JSON.stringify(facts)

func _step_pmc_airlift(ctx: Dictionary) -> void:
	PmcAirlift.advance(self, ctx)

func _cancel_pmc_native_ticket(native_id: int, queue_id: int) -> void:
	if not _last_game or Pax.world_busy() or not is_instance_valid(_last_game.main) or _last_game.main.rewind_state.rewinding:
		return
	for order in _last_game.main.model.orders:
		if order is Dictionary and int(order.get("id", 0)) == native_id and int(order.get("prigozhin_fork_recruit_queue_id", 0)) == queue_id:
			_last_game.main.orders_panel().cancel_order(native_id)
			return

func _finish_pmc_native_recruitment(game: PaxGame) -> void:
	if not game or _last_game != game or not is_instance_valid(game.main):
		return
	if Pax.world_busy():
		if not _pmc_native_finish_waiting:
			_pmc_native_finish_waiting = true
			game.when_world_free(Callable(self, "_resume_pmc_native_recruitment").bind(game, _pmc_commander_generation))
		return
	WorldCycle.finish_recruitment(self, game)

func _resume_pmc_native_recruitment(game: PaxGame, generation: int) -> void:
	if generation != _pmc_commander_generation or _last_game != game:
		return
	_pmc_native_finish_waiting = false
	_finish_pmc_native_recruitment(game)

func _request_pmc_commanders(game: PaxGame) -> void:
	if not game or _last_game != game or not is_instance_valid(game.main) or _pmc_commander_pending:
		return
	var delegated: bool = false
	for record in _pmc_mandates:
		if record is Dictionary and bool(record.get("movement_authority", false)) and str(record.get("status", "")) == "active" and not bool(record.get("commander_review_required", false)):
			delegated = true
			break
	if not delegated:
		return
	if Pax.world_busy() or game.main.rewind_state.rewinding:
		if not _pmc_commander_waiting and game.main.is_inside_tree():
			_pmc_commander_waiting = true
			game.main.get_tree().create_timer(1.0).timeout.connect(Callable(self, "_resume_pmc_commanders").bind(game, _pmc_commander_generation))
		return
	PmcCommanders.request_round(self, game)

func _resume_pmc_commanders(game: PaxGame, generation: int) -> void:
	if generation != _pmc_commander_generation or _last_game != game:
		return
	_pmc_commander_waiting = false
	_request_pmc_commanders(game)


# Domain modules keep the mod entry focused on state, hooks, and lifecycle.
func _get_armies_dict() -> Dictionary:
	return ArmyOperations.get_armies_dict(self)

func spawn_wagner_detachment(game: PaxGame, det_name: String, count: int) -> void:
	ArmyOperations.spawn_wagner_detachment(self, game, det_name, count)

func _clean_civilian_marks(game: PaxGame) -> void:
	CivilianMarks.clean(game)

func _check_and_clear_mark(mark: Dictionary) -> void:
	CivilianMarks.clear_mark(mark)

func _days_passed(game: PaxGame, from_day: int, days: int) -> void:
	WorldCycle.days_passed(self, game, from_day, days)

func _simulate_duma_election(game: PaxGame) -> void:
	WorldCycle.simulate_duma_election(self, game)

func _monthly_world_tick(game: PaxGame) -> void:
	WorldCycle.monthly_tick(self, game)

func _request_ai_scenario(game: PaxGame) -> void:
	AiContacts.request_ai_scenario(self, game)

func _trigger_autonomous_npc_contact(game: PaxGame) -> void:
	AiContacts.trigger_autonomous_contact(self, game)

func get_recent_talk_summary(char_name: String, max_msgs: int = 4) -> String:
	return AiContacts.get_recent_talk_summary(self, char_name, max_msgs)

func check_shoigu_quarrel() -> bool:
	return AiContacts.check_shoigu_quarrel(self)

func _init_world_wars(game: PaxGame) -> void:
	if not game:
		return
	var f_list: Array = game.factions()
	var f_map: Dictionary = {}
	for f in f_list:
		if typeof(f) == TYPE_DICTIONARY and f.has("name"):
			f_map[f["name"]] = f
			
	# Связываем войну Сирии
	if f_map.has("Сирия") and f_map.has("Сирийские боевики и ИГИЛ"):
		var s_links = f_map["Сирия"].setdefault("links", {})
		s_links["Сирийские боевики и ИГИЛ"] = "at_war"
		var r_links = f_map["Сирийские боевики и ИГИЛ"].setdefault("links", {})
		r_links["Сирия"] = "at_war"
		
	# Связываем войну ЦАР
	if f_map.has("Центрально-Африканская Республика") and f_map.has("Повстанцы Селека (ЦАР)"):
		var c_links = f_map["Центрально-Африканская Республика"].setdefault("links", {})
		c_links["Повстанцы Селека (ЦАР)"] = "at_war"
		var p_links = f_map["Повстанцы Селека (ЦАР)"].setdefault("links", {})
		p_links["Центрально-Африканская Республика"] = "at_war"
		
	# Связываем войну Ливии
	if f_map.has("Ливия") and f_map.has("Ливийская национальная армия"):
		var l_links = f_map["Ливия"].setdefault("links", {})
		l_links["Ливийская национальная армия"] = "at_war"
		var h_links = f_map["Ливийская национальная армия"].setdefault("links", {})
		h_links["Ливия"] = "at_war"


func _execute_concord_contract(game: PaxGame) -> void:
	# Compatibility entry point: a legacy button must not mint a random profit.
	if game and _last_game == game:
		game.toast(tr_key("prigozhin_fork_supply_open_records"))

func _save_state(_game: PaxGame) -> Dictionary:
	return {
		"deals": _deals,
		"comms_history": _comms_history,
		"pending_orders": _pending_orders,
		"custom_wagner_detachments": _custom_wagner_detachments,
		"pmc_recruitment": _pmc_recruitment,
		"pmc_recruit_sources": _pmc_recruit_sources,
		"pmc_mandates": _pmc_mandates,
		"pmc_movements": _pmc_movements,
		"pmc_airlifts": _pmc_airlifts,
		"wallet_wagner_usd": _wallet_wagner_usd,
		"wallet_concord_usd": _wallet_concord_usd,
		"wallet_nfv_usd": _wallet_nfv_usd,
		"barter_gold_kg": _barter_gold_kg,
		"barter_oil_barrels": _barter_oil_barrels,
		"cmd_lotos_trust": _cmd_lotos_trust,
		"cmd_lotos_readiness": _cmd_lotos_readiness,
		"cmd_utkin_trust": _cmd_utkin_trust,
		"airlift_state": _airlift_state,
		"airlift_days_in_flight": _airlift_days_in_flight,
		"airlift_cost_spent": _airlift_cost_spent,
		"hafta_payment_received": _hafta_payment_received,
		"days_count": _days_count,
		"days_accumulator": _days_accumulator,
		"early_elections_checked": _early_elections_checked,
		"early_elections_called": _early_elections_called,
		"elections_concluded": _elections_concluded,
		"nfw_founded": _nfw_founded,
		"nfw_rating": _nfw_rating,
		"nfw_activists": _nfw_activists,
		"nfw_regional_cells": _nfw_regional_cells,
		"nfw_campaign_fund": _nfw_campaign_fund,
		"media_power": _media_power,
		"duma_seats": _duma_seats,
		"duma_list_seats": _duma_list_seats,
		"duma_single_seats": _duma_single_seats,
		"concord_workers": _concord_workers,
		"concord_annual_quota": _concord_annual_quota,
		"concord_fulfilled_quota": _concord_fulfilled_quota,
		"concord_inspections": _concord_inspections,
		"wagner_fighters_estimate": _wagner_fighters_estimate,
		"gold_reserves": _gold_reserves,
		"kremlin_pressure": _kremlin_pressure,
		"mironov_loyalty": _mironov_loyalty,
		"redut_influence": _redut_influence,
		"patriot_influence": _patriot_influence,
		"shoigu_hostile": _shoigu_hostile
	}

func _game_loaded(_game: PaxGame, state: Dictionary) -> void:
	_last_game = _game
	_pmc_commander_generation += 1
	_pmc_commander_pending = false
	_pmc_commander_waiting = false
	_pmc_native_finish_waiting = false
	_pmc_ai_facts = ""
	_days_count = int(state.get("days_count", 0))
	_days_accumulator = int(state.get("days_accumulator", 0))
	_early_elections_checked = bool(state.get("early_elections_checked", false))
	_early_elections_called = bool(state.get("early_elections_called", false))
	_elections_concluded = bool(state.get("elections_concluded", false))
	_nfw_founded = bool(state.get("nfw_founded", false))
	_nfw_rating = float(state.get("nfw_rating", 4.2))
	_nfw_activists = int(state.get("nfw_activists", 1500))
	_nfw_regional_cells = int(state.get("nfw_regional_cells", 3))
	_nfw_campaign_fund = float(state.get("nfw_campaign_fund", 0.0))
	_media_power = float(state.get("media_power", 0.0))
	_duma_seats = int(state.get("duma_seats", 0))
	_duma_list_seats = int(state.get("duma_list_seats", 0))
	_duma_single_seats = int(state.get("duma_single_seats", 0))
	_concord_workers = int(state.get("concord_workers", 12000))
	_concord_annual_quota = float(state.get("concord_annual_quota", 24.0))
	_concord_fulfilled_quota = float(state.get("concord_fulfilled_quota", 0.0))
	_concord_inspections = int(state.get("concord_inspections", 0))
	_wagner_fighters_estimate = int(state.get("wagner_fighters_estimate", 3500))
	_gold_reserves = float(state.get("gold_reserves", 12.0))
	# Строгий перенос существующего баланса казны без создания лишних виртуальных ресурсов
	if state.has("wallet_wagner_usd"):
		_wallet_wagner_usd = float(state.get("wallet_wagner_usd", _gold_reserves * 0.5))
		_wallet_concord_usd = float(state.get("wallet_concord_usd", _gold_reserves * 0.35))
		_wallet_nfv_usd = float(state.get("wallet_nfv_usd", _gold_reserves * 0.15))
	else:
		_wallet_wagner_usd = _gold_reserves * 0.5
		_wallet_concord_usd = _gold_reserves * 0.35
		_wallet_nfv_usd = _gold_reserves * 0.15
	_barter_gold_kg = float(state.get("barter_gold_kg", 0.0))
	_barter_oil_barrels = float(state.get("barter_oil_barrels", 0.0))
	_cmd_lotos_trust = int(state.get("cmd_lotos_trust", 80))
	_cmd_lotos_readiness = int(state.get("cmd_lotos_readiness", 85))
	_cmd_utkin_trust = int(state.get("cmd_utkin_trust", 90))
	_airlift_state = str(state.get("airlift_state", "ready"))
	_airlift_days_in_flight = int(state.get("airlift_days_in_flight", 0))
	_airlift_cost_spent = float(state.get("airlift_cost_spent", 0.0))
	_hafta_payment_received = bool(state.get("hafta_payment_received", false))
	_kremlin_pressure = int(state.get("kremlin_pressure", 15))
	_mironov_loyalty = int(state.get("mironov_loyalty", 50))
	_redut_influence = int(state.get("redut_influence", 45))
	_patriot_influence = int(state.get("patriot_influence", 40))
	_shoigu_hostile = bool(state.get("shoigu_hostile", false))
	_autonomous_contact_pending = false
	_last_confirmed_order_hash = ""
	var saved_history = state.get("comms_history", {})
	_comms_history = saved_history.duplicate(true) if saved_history is Dictionary else {}
	var saved_deals = state.get("deals", [])
	_deals = saved_deals.duplicate(true) if saved_deals is Array else []

	var saved_pending = state.get("pending_orders", [])
	_pending_orders = saved_pending.duplicate(true) if saved_pending is Array else []
	var saved_mandates = state.get("pmc_mandates", [])
	_pmc_mandates = saved_mandates.duplicate(true) if saved_mandates is Array else []
	var saved_movements = state.get("pmc_movements", [])
	_pmc_movements = saved_movements.duplicate(true) if saved_movements is Array else []
	var saved_airlifts = state.get("pmc_airlifts", [])
	_pmc_airlifts = saved_airlifts.duplicate(true) if saved_airlifts is Array else []
	var saved_recruitment = state.get("pmc_recruitment", [])
	_pmc_recruitment = saved_recruitment.duplicate(true) if saved_recruitment is Array else []
	var saved_sources = state.get("pmc_recruit_sources", {})
	_pmc_recruit_sources = saved_sources.duplicate(true) if saved_sources is Dictionary else {}
	for recruitment in _pmc_recruitment:
		if recruitment is Dictionary and str(recruitment.get("status", "")) == "executing":
			recruitment["status"] = "review"
			recruitment["reason"] = "interrupted_native_hire"
	var saved_wagner = state.get("custom_wagner_detachments", [])
	_custom_wagner_detachments = saved_wagner.duplicate(true) if saved_wagner is Array else []
	_refresh_ui()

# ------------------------------------------------------------------------------
# АВТОНОМНЫЕ ВЫЗОВЫ NPC НА ПЕРЕМОТКЕ ВРЕМЕНИ (ЖИВАЯ ГЕНЕРАЦИЯ ИИ)
# ------------------------------------------------------------------------------
