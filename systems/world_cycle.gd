extends RefCounted

const CivilianMarks = preload("res://mods/prigozhin_fork/systems/civilian_marks.gd")
const PmcMovement = preload("res://mods/prigozhin_fork/systems/pmc_movement.gd")
const AiContacts = preload("res://mods/prigozhin_fork/systems/ai_contacts.gd")
const PmcMandates = preload("res://mods/prigozhin_fork/systems/pmc_mandates.gd")
const PmcRecruitment = preload("res://mods/prigozhin_fork/systems/pmc_recruitment.gd")
const PmcAirlift = preload("res://mods/prigozhin_fork/systems/pmc_airlift.gd")

static func simulate_duma_election(owner, game: PaxGame) -> void:
	owner._elections_concluded = true
	if not owner._nfw_founded:
		owner._duma_seats = 0
		owner._duma_list_seats = 0
		owner._duma_single_seats = 0
		game.toast("Выборы в Государственную думу состоялись. НФВ не выдвигала списки. Баланс сил в парламенте сохранён.")
		owner._refresh_ui()
		return
	var effective_pct: float = owner._nfw_rating + randf_range(-1.5, 1.5)
	if effective_pct < 5.0:
		owner._duma_list_seats = 0
		game.toast("НФВ набрала %.1f%% голосов и НЕ преодолела 5%% избирательный барьер по спискам!" % effective_pct)
	else:
		owner._duma_list_seats = int((effective_pct / 100.0) * 225.0 * 1.18)
	owner._duma_single_seats = 0
	var win_probability: float = clampf(0.12 + (owner._nfw_campaign_fund * 0.02) + (owner._media_power * 0.04) - (owner._kremlin_pressure * 0.003), 0.05, 0.40)
	for i in range(owner._nfw_regional_cells):
		if randf() < win_probability:
			owner._duma_single_seats += 1
	owner._duma_seats = owner._duma_list_seats + owner._duma_single_seats
	game.toast("★ ИТОГИ ВЫБОРОВ В ГОСДУМУ: НФВ получает %d мест (Списки: %d, Округа: %d)!" % [
		owner._duma_seats, owner._duma_list_seats, owner._duma_single_seats
	])
	owner._refresh_ui()

static func finish_recruitment(owner, game: PaxGame) -> void:
	if not owner or not game or owner._last_game != game or Pax.world_busy():
		return
	PmcAirlift.flush(owner, game)
	PmcRecruitment.complete_due(owner, game)
	PmcMandates.record_costs(owner, game)
	var formed: int = 0
	for application in owner._pmc_recruitment:
		if application is Dictionary and str(application.get("status", "")) in ["complete", "partial"] and not bool(application.get("notice_sent", false)):
			application["notice_sent"] = true
			formed += 1
	if formed > 0:
		game.toast(owner.tr_key("prigozhin_fork_recruit_queue_formed") % formed)
	if not owner._pmc_recruitment.is_empty() or not owner._pmc_movements.is_empty() or not owner._pmc_airlifts.is_empty():
		owner._refresh_ui()

static func days_passed(owner, game: PaxGame, _from_day: int, days: int) -> void:
	var finish_after_world: bool = Pax.world_busy()
	owner._days_count += days
	owner._days_accumulator += days
	PmcMovement.observe(owner, game)
	finish_recruitment(owner, game)

	# 1. Подавление коммунального спама
	CivilianMarks.clean(game)

	# Старый цикл переброски не запускается: его статус не подтверждает
	# существование маршрута и может переместить отряды без разрешений.
	# Сохранённое состояние остаётся доступным для последующей сверки.

	# Internal mandates expire after the world step; no funds or unit orders are changed.
	var expired_mandates: Array = PmcMandates.expire(owner, game)
	if not expired_mandates.is_empty():
		game.toast(owner.tr_key("prigozhin_fork_mandates_expired") % expired_mandates.size())
	var observations: Array = PmcMandates.observe(owner, game)
	var new_reports: int = 0
	for observation in observations:
		if not (observation is Dictionary):
			continue
		var mandate_id: int = int(observation.get("mandate_id", 0))
		var unit_id: int = int(observation.get("unit_id", 0))
		var kind: String = str(observation.get("kind", ""))
		if mandate_id <= 0 or unit_id <= 0:
			continue
		var report_id: String = "pmc_observation_%d_%d_%d_%s" % [mandate_id, unit_id, game.day(), kind]
		var duplicate: bool = false
		for old in owner._deals:
			if old is Dictionary and str(old.get("id", "")) == report_id:
				duplicate = true
				break
		if duplicate:
			continue
		var summary: String = ""
		if kind == "outside":
			summary = owner.tr_key("prigozhin_fork_mandate_observed_outside") % [str(observation.get("name", "")), int(observation.get("province", 0))]
		elif kind == "inside":
			summary = owner.tr_key("prigozhin_fork_mandate_observed_return") % [str(observation.get("name", "")), int(observation.get("province", 0))]
		elif kind == "unavailable":
			summary = owner.tr_key("prigozhin_fork_mandate_observed_missing") % unit_id
		if summary.is_empty():
			continue
		owner._deals.append({"id": report_id, "partner": owner.tr_key("prigozhin_fork_ai_hq"),
			"title": owner.tr_key("prigozhin_fork_mandate_observation_title"), "terms": summary,
			"cost": 0.0, "risk": 0, "status": "report"})
		new_reports += 1
	if new_reports > 0:
		game.toast(owner.tr_key("prigozhin_fork_mandate_observation_notice") % new_reports)
		owner._refresh_ui()

	# 3. Автономные звонки и депеши ИИ (каждые 14 дней)
	if owner._days_count % 14 < days:
		AiContacts.trigger_autonomous_contact(owner, game)

	# 5. Месячный глобальный тик (каждые 30 дней: Дума, выборы, Кремль)
	while owner._days_accumulator >= 30:
		owner._days_accumulator -= 30
		var boundary_day: int = owner._days_count - owner._days_accumulator
		monthly_tick(owner, game, boundary_day)
	if owner._dialog_ui and is_instance_valid(owner._dialog_ui) and owner._dialog_ui.has_method("refresh_operational_briefing"):
		owner._dialog_ui.refresh_operational_briefing()
	# Start only after the rewind callback has returned to the main event loop.
	owner.call_deferred("_request_pmc_commanders", game)
	if finish_after_world:
		owner.call_deferred("_finish_pmc_native_recruitment", game)

static func monthly_tick(owner, game: PaxGame, boundary_day: int = -1) -> void:
	var effective_day: int = boundary_day if boundary_day >= 0 else owner._days_count
	# 1. Ежегодный сброс квоты контрактов МО (каждые 360 дней)
	if effective_day % 360 < 30:
		owner._concord_fulfilled_quota = 0.0
		
	# 2. Развилка досрочных выборов (Месяц 10-12, лето 2019)
	if effective_day >= 300 and not owner._early_elections_checked:
		owner._early_elections_checked = true
		if owner._kremlin_pressure > 45 or randf() < 0.40:
			owner._early_elections_called = false
			game.toast("Кремль принял решение: досрочного роспуска Госдумы в 2019 году НЕ будет. Регулярные выборы состоятся в 2021 году.")
		else:
			owner._early_elections_called = true
			game.toast("Объявлены досрочные парламентские выборы на осень 2019 года! Кампания началась.")
			
	# 3. День голосования (осень 2019, если были назначены)
	if owner._early_elections_called and not owner._elections_concluded and effective_day >= 390:
		simulate_duma_election(owner, game)
		
	# 4. Автономные ходы Кремля (АП) с естественным остыванием (decay)
	if owner._nfw_rating > 18.0:
		owner._kremlin_pressure = mini(85, owner._kremlin_pressure + 2)
	else:
		# Естественное угасание напряжённости при отсутствии провокаций
		owner._kremlin_pressure = maxi(10, owner._kremlin_pressure - 1)
		
	# 5. Автономные ходы губернатора Миронова (проверки сгорают со временем)
	if owner._concord_inspections > 0:
		# Проверка длится 1-2 месяца и завершается
		if randf() < 0.50:
			owner._concord_inspections = 0
	elif owner._mironov_loyalty < 30 and randf() < 0.20:
		owner._concord_inspections = 1
		game.toast("Губернатор Миронов и УФСБ инициировали проверку земельных участков и объектов в Туношне.")
		
	# 6. Автономное соперничество ЧВК (колеблется в жестких границах)
	owner._redut_influence = clampi(owner._redut_influence + int(randf_range(-2, 3)), 15, 80)
	owner._patriot_influence = clampi(owner._patriot_influence + int(randf_range(-2, 2)), 15, 75)
		
	owner._refresh_ui()
