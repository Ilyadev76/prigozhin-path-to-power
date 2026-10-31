extends "res://mods/prigozhin_fork/ui/tabs/hq_tab_base.gd"

const ArmyOperations = preload("res://mods/prigozhin_fork/systems/army_operations.gd")
const PmcMandates = preload("res://mods/prigozhin_fork/systems/pmc_mandates.gd")
const PmcRecruitment = preload("res://mods/prigozhin_fork/systems/pmc_recruitment.gd")
const MovementControls = preload("res://mods/prigozhin_fork/ui/pmc_movement_controls.gd")
const PmcMovement = preload("res://mods/prigozhin_fork/systems/pmc_movement.gd")
const RecruitmentReview = preload("res://mods/prigozhin_fork/ui/pmc_recruitment_review.gd")
const CommanderControls = preload("res://mods/prigozhin_fork/ui/pmc_commander_controls.gd")
const SourceStatus = preload("res://mods/prigozhin_fork/ui/pmc_recruit_source_status.gd")
const PmcOrderBridge = preload("res://mods/prigozhin_fork/systems/pmc_order_bridge.gd")
const AirliftControls = preload("res://mods/prigozhin_fork/ui/pmc_airlift_controls.gd")

var _troops_list_container: VBoxContainer = null

func configure(main_mod, game, callbacks: Dictionary) -> void:
	configure_base(main_mod, game, callbacks)
	_build_troops_tab(self)
	refresh()

func refresh() -> void:
	_refresh_troops_tab()

func _build_troops_tab(parent: Control) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	parent.add_child(box)
	
	var header: Label = Label.new()
	header.text = _mod_tr("prigozhin_fork_troops_title")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	box.add_child(header)
	
	var sub: Label = Label.new()
	sub.text = _mod_tr("prigozhin_fork_troops_subtitle") + "\n" + _mod_tr("prigozhin_fork_recruit_queue_timing")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(sub)
	
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	
	_troops_list_container = VBoxContainer.new()
	_troops_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_troops_list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_troops_list_container)
	
	var btn_bar: HBoxContainer = HBoxContainer.new()
	btn_bar.add_theme_constant_override("separation", 12)
	box.add_child(btn_bar)
	
	var btn_refresh: Button = Button.new()
	btn_refresh.text = "🔄 Обновить статус подразделений"
	btn_refresh.custom_minimum_size = Vector2(250, 36)
	btn_refresh.pressed.connect(func(): _refresh_troops_tab())
	btn_bar.add_child(btn_refresh)

	var recruit_row: HBoxContainer = HBoxContainer.new()
	recruit_row.add_theme_constant_override("separation", 8)
	box.add_child(recruit_row)
	var recruit_name: LineEdit = LineEdit.new()
	recruit_name.placeholder_text = _mod_tr("prigozhin_fork_recruit_name")
	recruit_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recruit_name.max_length = 80
	recruit_row.add_child(recruit_name)
	var recruit_count: SpinBox = SpinBox.new()
	recruit_count.min_value = 1
	recruit_count.max_value = 5000
	recruit_count.step = 1
	recruit_count.value = 100
	recruit_count.custom_minimum_size = Vector2(100, 0)
	recruit_row.add_child(recruit_count)
	var recruit_days: SpinBox = SpinBox.new()
	recruit_days.min_value = 1
	recruit_days.max_value = 3650
	recruit_days.value = 14
	recruit_days.suffix = _mod_tr("prigozhin_fork_mandate_days_suffix")
	recruit_days.tooltip_text = _mod_tr("prigozhin_fork_recruit_queue_timing")
	recruit_row.add_child(recruit_days)
	var recruit_button: Button = Button.new()
	recruit_button.text = _mod_tr("prigozhin_fork_recruit_submit")
	recruit_button.pressed.connect(func():
		if not _game:
			return
		var unit_name: String = recruit_name.text.strip_edges()
		if unit_name.is_empty():
			_game.toast(_mod_tr("prigozhin_fork_recruit_name_required"))
			return
		var count: int = int(recruit_count.value)
		var result: Dictionary = PmcRecruitment.reserve(_main_mod, _game, unit_name, count, int(recruit_days.value))
		if bool(result.get("ok", false)):
			recruit_name.clear()
			_game.toast(_mod_tr("prigozhin_fork_recruit_queue_added"))
			_refresh_troops_tab()
		else:
			var reason: String = str(result.get("reason", "unavailable"))
			if reason == "reserve":
				_game.toast(_mod_tr("prigozhin_fork_recruit_pool_insufficient") % int(result.get("available", 0)))
			elif reason == "duplicate":
				_game.toast(_mod_tr("prigozhin_fork_recruit_preflight_duplicate"))
			elif reason == "legacy":
				_game.toast(_mod_tr("prigozhin_fork_recruit_preflight_legacy"))
			elif reason == "unsupported_role":
				_game.toast(_mod_tr("prigozhin_fork_recruit_queue_role"))
			elif reason in ["source_not_ready", "source_unavailable", "source_review"]:
				_game.toast(_mod_tr("prigozhin_fork_recruit_" + reason))
			else:
				_game.toast(_mod_tr("prigozhin_fork_recruit_preflight_unavailable"))

	)
	recruit_row.add_child(recruit_button)
	
	_refresh_troops_tab()

func _refresh_troops_tab() -> void:
	if not _troops_list_container or Pax.world_busy():
		return
	PmcOrderBridge.synchronize(_main_mod, _game)
	PmcMovement.observe(_main_mod, _game)
	if _main_mod:
		_main_mod._capture_pmc_facts()
	for c in _troops_list_container.get_children():
		c.queue_free()
		
	if _main_mod and _game:
		var queue_title: Label = Label.new()
		queue_title.text = _mod_tr("prigozhin_fork_recruit_queue_title")
		_troops_list_container.add_child(queue_title)
		for application in _main_mod._pmc_recruitment:
			if not (application is Dictionary) or str(application.get("side", "")) != _game.country():
				continue
			var status: String = str(application.get("status", "review"))
			if status not in ["pending", "blocked", "executing", "review", "complete", "partial", "cancelled", "reconciled", "archived"]:
				status = "review"
			var application_id: int = int(application.get("id", 0))
			var queue_line: Label = Label.new()
			queue_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			queue_line.text = _mod_tr("prigozhin_fork_recruit_queue_line") % [application_id, str(application.get("name", "")), int(application.get("requested", 0)), int(application.get("due_day", 0)), _mod_tr("prigozhin_fork_recruit_status_" + status)]
			if int(application.get("native_order_id", 0)) > 0:
				queue_line.text += "\n" + (_mod_tr("prigozhin_fork_native_recruit_link") % int(application["native_order_id"]))
				if status in ["pending", "blocked"] and not bool(application.get("native_due", false)):
					queue_line.text += "\n" + _mod_tr("prigozhin_fork_native_recruit_wait_native")
			if str(application.get("mode", "")) == "reinforce":
				queue_line.text += "\n" + (_mod_tr("prigozhin_fork_reinforce_queue_target") % [int(application.get("target_id", 0)), int(application.get("source_province", 0))])
			if int(application.get("mandate_id", 0)) > 0:
				queue_line.text += "\n" + (_mod_tr("prigozhin_fork_reinforce_linked_mandate") % int(application["mandate_id"]))
			if not str(application.get("source_country", "")).is_empty():
				queue_line.text += "\n" + (_mod_tr("prigozhin_fork_recruit_source_binding") % [str(application["source_country"]), int(application.get("source_province", 0))])
			if bool(application.get("native_uncertain", false)):
				queue_line.text += "\n" + _mod_tr("prigozhin_fork_recruit_source_uncertain")
			if status in ["complete", "partial"]:
				queue_line.text += "\n" + (_mod_tr("prigozhin_fork_recruit_queue_result") % [int(application.get("hired", 0)), int(application.get("unit_id", 0)), str(application.get("spent", 0)), int(application.get("completed_day", 0))])
			elif status == "reconciled":
				queue_line.text += "\n" + (_mod_tr("prigozhin_fork_recruit_review_result") % [int(application.get("unit_id", 0)), int(application.get("observed_humans", 0)), int(application.get("reconciled_day", 0))])
			elif status == "blocked":
				var why: String = str(application.get("reason", ""))
				if why == "funds" or why == "native_hire_rejected":
					queue_line.text += "\n" + _mod_tr("prigozhin_fork_recruit_queue_funds")
				elif why == "reserve":
					queue_line.text += "\n" + _mod_tr("prigozhin_fork_recruit_source_waiting")
				elif why == "duplicate":
					queue_line.text += "\n" + _mod_tr("prigozhin_fork_recruit_preflight_duplicate")
				elif why in ["target", "target_not_ready"]:
					queue_line.text += "\n" + _mod_tr("prigozhin_fork_reinforce_" + why)
				elif why == "mandate_inactive":
					queue_line.text += "\n" + _mod_tr("prigozhin_fork_reinforce_mandate_inactive")
				elif why in ["source_required", "source_not_ready", "source_changed", "source_unavailable", "source_review"]:
					queue_line.text += "\n" + _mod_tr("prigozhin_fork_recruit_" + why)
				else:
					queue_line.text += "\n" + _mod_tr("prigozhin_fork_recruit_preflight_unavailable")
			_troops_list_container.add_child(queue_line)
			if status == "review" and application_id > 0:
				var review_ui = RecruitmentReview.new()
				review_ui.configure(_main_mod, _game, application_id, Callable(self, "_refresh_troops_tab"))
				_troops_list_container.add_child(review_ui)
			if status in ["pending", "blocked"]:
				var cancel_button: Button = Button.new()
				cancel_button.text = _mod_tr("prigozhin_fork_recruit_queue_cancel")
				cancel_button.disabled = application_id <= 0
				cancel_button.pressed.connect(func():
					if PmcRecruitment.cancel(_main_mod, _game, application_id):
						_refresh_troops_tab()
				)
				_troops_list_container.add_child(cancel_button)

	var our_units: Array = ArmyOperations.player_units(_main_mod) if _main_mod else []
	if _main_mod and _game and _game.main and _game.main.model:
		var airlift_controls = AirliftControls.new()
		airlift_controls.configure(_main_mod, _game)
		_troops_list_container.add_child(airlift_controls)
	# Native budget includes every player-side unit, not just Wagner.
	if _game and _game.main and _game.main.has_method("treasury"):
		var treasury = _game.main.treasury()
		if treasury:
			var budget: Dictionary = treasury.breakdown(_game.home_body())
			if bool(budget.get("exists", false)):
				var budget_line: Label = Label.new()
				budget_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				budget_line.text = _mod_tr("prigozhin_fork_unit_native_budget") % [str(snappedf(float(budget.get("treasury", 0.0)), 0.01)), str(snappedf(float(budget.get("on_army", 0.0)), 0.01)), str(snappedf(float(budget.get("debt", 0.0)), 0.01))]
				budget_line.add_theme_color_override("font_color", Color(0.65, 0.78, 0.88))
				_troops_list_container.add_child(budget_line)
	if _main_mod and _game:
		var source_status = SourceStatus.new()
		source_status.configure(_main_mod, _game)
		_troops_list_container.add_child(source_status)
	# Old mod-only records are shown separately; never turn them into units here.
	if _main_mod and not _main_mod._custom_wagner_detachments.is_empty():
		var legacy_header: Label = Label.new()
		legacy_header.text = _mod_tr("prigozhin_fork_legacy_units_header")
		legacy_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		legacy_header.add_theme_color_override("font_color", Color(0.95, 0.72, 0.35))
		_troops_list_container.add_child(legacy_header)
		for legacy in _main_mod._custom_wagner_detachments:
			if not (legacy is Dictionary):
				continue
			var legacy_label: Label = Label.new()
			legacy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			legacy_label.text = _mod_tr("prigozhin_fork_legacy_units_line") % [str(legacy.get("name", "")), str(legacy.get("humans", ""))]
			var candidates: Dictionary = ArmyOperations.legacy_candidates(_main_mod, legacy)
			if not bool(candidates.get("available", false)):
				legacy_label.text += "\n" + _mod_tr("prigozhin_fork_legacy_compare_unavailable")
			else:
				var candidate_ids: Array = candidates.get("ids", [])
				if candidate_ids.is_empty():
					legacy_label.text += "\n" + _mod_tr("prigozhin_fork_legacy_compare_none")
				elif candidate_ids.size() == 1:
					legacy_label.text += "\n" + (_mod_tr("prigozhin_fork_legacy_compare_one") % int(candidate_ids[0]))
				else:
					legacy_label.text += "\n" + (_mod_tr("prigozhin_fork_legacy_compare_many") % candidate_ids.size())
			_troops_list_container.add_child(legacy_label)

	if our_units.is_empty():
		var empty: Label = Label.new()
		empty.text = _mod_tr("prigozhin_fork_troops_empty")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_troops_list_container.add_child(empty)
		return

	for unit in our_units:
		if int(unit.get("prigozhin_fork_in_airlift", 0)) > 0:
			var transit: Label = Label.new()
			transit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			transit.text = _mod_tr("prigozhin_fork_airlift_unit") % [int(unit.get("id", 0)), str(unit.get("name", "")), int(unit.get("humans", 0)), int(unit["prigozhin_fork_in_airlift"]), _mod_tr("prigozhin_fork_airlift_" + str(unit.get("airlift_status", "review")))]
			transit.add_theme_color_override("font_color", Color(0.60, 0.80, 1.0))
			_troops_list_container.add_child(transit)
			continue
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _card_box_style(Color(0.10, 0.13, 0.18, 0.95), Color(0.75, 0.60, 0.20, 0.85)))
		
		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		card.add_child(vbox)
		
		var uname: String = str(unit.get("name", "Безымянный отряд"))
		var humans: int = int(unit.get("humans", 0))
		var morale: String = _mod_tr("prigozhin_fork_troops_unknown")
		if unit.has("morale"):
			morale = "%.0f%%" % (float(unit["morale"]) * 100.0)
		var exp: String = _mod_tr("prigozhin_fork_troops_unknown")
		if unit.has("experience"):
			exp = "%.0f%%" % (float(unit["experience"]) * 100.0)
		var task: String = str(unit.get("task", "")).strip_edges()
		if task.is_empty():
			task = _mod_tr("prigozhin_fork_troops_unknown")
		var prov_id: int = int(unit.get("province", 0))
		var place: String = _mod_tr("prigozhin_fork_units_sector") % prov_id
		if _game and prov_id > 0:
			var province: Dictionary = _game.province(_game.home_body(), prov_id)
			var province_name: String = str(province.get("name", ""))
			if not province_name.is_empty():
				place = province_name
		
		var title_lbl: Label = Label.new()
		title_lbl.text = "★ %s  •  Личный состав: %d бойцов" % [uname, humans]
		title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		vbox.add_child(title_lbl)
		
		var info_lbl: Label = Label.new()
		info_lbl.text = _mod_tr("prigozhin_fork_troops_info") % [place, morale, exp, task]
		info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		vbox.add_child(info_lbl)

		var state_line: Label = Label.new()
		state_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var loss_text: String = _mod_tr("prigozhin_fork_troops_unknown")
		if unit.has("losses"):
			loss_text = str(snappedf(float(unit["losses"]), 0.01))
		var route_text: String = _mod_tr("prigozhin_fork_troops_unknown")
		var road = unit.get("road")
		if road is Array:
			if road.is_empty():
				route_text = _mod_tr("prigozhin_fork_unit_no_route")
			else:
				var destination_id: int = int(road[road.size() - 1])
				var destination: String = _mod_tr("prigozhin_fork_units_sector") % destination_id
				if _game and destination_id > 0:
					var destination_info: Dictionary = _game.province(_game.home_body(), destination_id)
					if not str(destination_info.get("name", "")).is_empty():
						destination = str(destination_info["name"])
				route_text = _mod_tr("prigozhin_fork_unit_route_to") % destination
		state_line.text = _mod_tr("prigozhin_fork_unit_actual_state") % [loss_text, route_text]
		state_line.add_theme_color_override("font_color", Color(0.65, 0.78, 0.88))
		vbox.add_child(state_line)

		var supply_line: Label = Label.new()
		supply_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var supply_parts: PackedStringArray = PackedStringArray()
		var stores = unit.get("provisions")
		if stores is Dictionary:
			for resource_key in stores:
				var amount = stores[resource_key]
				if typeof(amount) in [TYPE_INT, TYPE_FLOAT]:
					supply_parts.append("%s: %s" % [str(resource_key), str(snappedf(float(amount), 0.01))])
		var supply_text: String = ", ".join(supply_parts) if not supply_parts.is_empty() else _mod_tr("prigozhin_fork_troops_unknown")
		var haulage: String = _mod_tr("prigozhin_fork_troops_unknown")
		if unit.has("haulage"):
			haulage = "%.0f%%" % (float(unit["haulage"]) * 100.0)
		supply_line.text = _mod_tr("prigozhin_fork_unit_actual_supply") % [supply_text, haulage]
		supply_line.add_theme_color_override("font_color", Color(0.65, 0.78, 0.88))
		vbox.add_child(supply_line)
		
		var act_h: HBoxContainer = HBoxContainer.new()
		act_h.add_theme_constant_override("separation", 8)
		vbox.add_child(act_h)
		
		var btn_loc: Button = Button.new()
		btn_loc.text = _mod_tr("prigozhin_fork_troops_map")
		btn_loc.disabled = prov_id <= 0
		btn_loc.pressed.connect(func():
			if _game and "main" in _game and _game.main and _game.main.has_method("army_map_view"):
				var amv = _game.main.army_map_view()
				if amv and amv.has_method("show_province_on_map"):
					amv.show_province_on_map(prov_id)
					if _main_mod and is_instance_valid(_main_mod._dialog_panel):
						_main_mod._dialog_panel.visible = false
		)
		act_h.add_child(btn_loc)

		var unit_id: int = int(unit.get("id", 0))
		var movement_ui = MovementControls.new()
		movement_ui.configure(_main_mod, _game, unit_id, Callable(self, "_refresh_troops_tab"))
		vbox.add_child(movement_ui)
		_add_reinforcement_form(vbox, unit_id)
		var btn_supply: Button = Button.new()
		btn_supply.text = _mod_tr("prigozhin_fork_unit_supply")
		btn_supply.disabled = unit_id <= 0
		btn_supply.pressed.connect(func():
			if not _game or not _game.main or not _game.main.model or not _game.main.model.armies:
				return
			var current: Dictionary = _game.main.model.armies.unit(unit_id)
			if current.is_empty() or not bool(current.get("our", false)) or str(current.get("whose", "")) != _game.country():
				_game.toast(_mod_tr("prigozhin_fork_unit_missing"))
				_refresh_troops_tab()
				return
			var order_text: String = _mod_tr("prigozhin_fork_unit_supply_order") % [str(current.get("name", "")), unit_id]
			if send_order_to_game(order_text, 2, {"detachment": unit_id, "prigozhin_fork_unit_card": true}):
				_game.toast(_mod_tr("prigozhin_fork_comms_order_accepted"))
			else:
				_game.toast(_mod_tr("prigozhin_fork_unit_order_rejected"))
		)
		act_h.add_child(btn_supply)

		var order_row: HBoxContainer = HBoxContainer.new()
		order_row.add_theme_constant_override("separation", 8)
		var order_input: LineEdit = LineEdit.new()
		order_input.placeholder_text = _mod_tr("prigozhin_fork_unit_order_placeholder")
		order_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		order_row.add_child(order_input)
		var btn_order: Button = Button.new()
		btn_order.text = _mod_tr("prigozhin_fork_unit_order_button")
		btn_order.disabled = unit_id <= 0
		btn_order.pressed.connect(func():
			if not _game or not _game.main or not _game.main.model or not _game.main.model.armies:
				return
			var instruction: String = order_input.text.strip_edges()
			if instruction.is_empty():
				return
			var current: Dictionary = _game.main.model.armies.unit(unit_id)
			if current.is_empty() or not bool(current.get("our", false)) or str(current.get("whose", "")) != _game.country():
				_game.toast(_mod_tr("prigozhin_fork_unit_missing"))
				_refresh_troops_tab()
				return
			var order_text: String = _mod_tr("prigozhin_fork_unit_order_template") % [str(current.get("name", "")), unit_id, instruction]
			if send_order_to_game(order_text, 2, {"detachment": unit_id, "prigozhin_fork_unit_card": true}):
				order_input.clear()
				_game.toast(_mod_tr("prigozhin_fork_comms_order_accepted"))
			else:
				_game.toast(_mod_tr("prigozhin_fork_unit_order_rejected"))
		)
		order_row.add_child(btn_order)
		vbox.add_child(order_row)

		# This is an internal plan, not an external contract or an automatic order.
		var mandate_note: Label = Label.new()
		mandate_note.text = _mod_tr("prigozhin_fork_mandate_note")
		mandate_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mandate_note.add_theme_color_override("font_color", Color(0.72, 0.77, 0.84))
		vbox.add_child(mandate_note)
		if _main_mod and _game:
			for record in _main_mod._pmc_mandates:
				if not (record is Dictionary) or str(record.get("status", "")) != "active":
					continue
				var assigned = record.get("unit_ids", [])
				if not PmcMandates.has_id(assigned, unit_id) or str(record.get("side", "")) != _game.country():
					continue
				var details: Label = Label.new()
				details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				details.text = _mod_tr("prigozhin_fork_mandate_details") % [str(record.get("task", "")), str(record.get("provinces", [])), str(record.get("budget_limit", 0.0)), int(record.get("end_day", 0))]
				vbox.add_child(details)
				var costs: Label = Label.new()
				costs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				costs.text = _mod_tr("prigozhin_fork_mandate_confirmed_costs") % str(record.get("confirmed_direct_cost", 0.0))
				vbox.add_child(costs)
				var mandate_id: int = int(record.get("id", 0))
				var commander_controls = CommanderControls.new()
				commander_controls.configure(_main_mod, _game, mandate_id, Callable(self, "_refresh_troops_tab"))
				vbox.add_child(commander_controls)
				var close_mandate: Button = Button.new()
				close_mandate.text = _mod_tr("prigozhin_fork_mandate_close")
				close_mandate.pressed.connect(func():
					if PmcMandates.close(_main_mod, _game, mandate_id):
						_game.toast(_mod_tr("prigozhin_fork_mandate_closed"))
						_refresh_troops_tab()
					else:
						_game.toast(_mod_tr("prigozhin_fork_mandate_invalid"))
				)
				vbox.add_child(close_mandate)
		var mandate_task: LineEdit = LineEdit.new()
		mandate_task.placeholder_text = _mod_tr("prigozhin_fork_mandate_task")
		mandate_task.max_length = 240
		vbox.add_child(mandate_task)
		var mandate_row: HBoxContainer = HBoxContainer.new()
		mandate_row.add_theme_constant_override("separation", 8)
		var mandate_provinces: LineEdit = LineEdit.new()
		mandate_provinces.placeholder_text = _mod_tr("prigozhin_fork_mandate_provinces")
		mandate_provinces.text = str(prov_id) if prov_id > 0 else ""
		mandate_provinces.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mandate_row.add_child(mandate_provinces)
		var mandate_budget: SpinBox = SpinBox.new()
		mandate_budget.min_value = 0
		mandate_budget.max_value = 1000000
		mandate_budget.step = 0.1
		mandate_budget.suffix = _mod_tr("prigozhin_fork_mandate_budget_suffix")
		mandate_budget.tooltip_text = _mod_tr("prigozhin_fork_mandate_budget_tip")
		mandate_row.add_child(mandate_budget)
		var mandate_days: SpinBox = SpinBox.new()
		mandate_days.min_value = 1
		mandate_days.max_value = 3650
		mandate_days.value = 30
		mandate_days.suffix = _mod_tr("prigozhin_fork_mandate_days_suffix")
		mandate_row.add_child(mandate_days)
		var mandate_button: Button = Button.new()
		mandate_button.text = _mod_tr("prigozhin_fork_mandate_create")
		mandate_button.disabled = unit_id <= 0
		mandate_button.pressed.connect(func():
			if not _main_mod or not _game:
				return
			var province_ids: Array = []
			for part in mandate_provinces.text.split(",", false):
				var cleaned: String = str(part).strip_edges()
				if not cleaned.is_valid_int():
					_game.toast(_mod_tr("prigozhin_fork_mandate_invalid"))
					return
				province_ids.append(int(cleaned))
			var result: Dictionary = PmcMandates.create(_main_mod, _game, [unit_id], province_ids, mandate_task.text, mandate_budget.value, int(mandate_days.value))
			if bool(result.get("ok", false)):
				_game.toast(_mod_tr("prigozhin_fork_mandate_created"))
				_refresh_troops_tab()
			else:
				_game.toast(_mod_tr("prigozhin_fork_mandate_invalid"))
		)
		mandate_row.add_child(mandate_button)
		vbox.add_child(mandate_row)

		_troops_list_container.add_child(card)

func _add_reinforcement_form(parent: VBoxContainer, unit_id: int) -> void:
	var note: Label = Label.new()
	note.text = _mod_tr("prigozhin_fork_reinforce_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)
	var source_status = SourceStatus.new()
	source_status.configure(_main_mod, _game, unit_id)
	parent.add_child(source_status)
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var count_input: SpinBox = SpinBox.new()
	count_input.min_value = 1
	count_input.max_value = 5000
	count_input.value = 50
	row.add_child(count_input)
	var days_input: SpinBox = SpinBox.new()
	days_input.min_value = 1
	days_input.max_value = 3650
	days_input.value = 14
	days_input.suffix = _mod_tr("prigozhin_fork_mandate_days_suffix")
	row.add_child(days_input)
	var submit: Button = Button.new()
	submit.text = _mod_tr("prigozhin_fork_reinforce_submit")
	submit.pressed.connect(func():
		if not _game or not _main_mod or Pax.world_busy() or not _game.main or not _game.main.model or not _game.main.model.armies:
			return
		var unit: Dictionary = _game.main.model.armies.unit(unit_id)
		var result: Dictionary = PmcRecruitment.reserve(_main_mod, _game, str(unit.get("name", "")), int(count_input.value), int(days_input.value), unit_id)
		if bool(result.get("ok", false)):
			_game.toast(_mod_tr("prigozhin_fork_recruit_queue_added"))
			_refresh_troops_tab()
		else:
			var reason: String = str(result.get("reason", "unavailable"))
			if reason in ["target", "target_not_ready"]:
				_game.toast(_mod_tr("prigozhin_fork_reinforce_" + reason))
			elif reason == "reserve":
				_game.toast(_mod_tr("prigozhin_fork_recruit_pool_insufficient") % int(result.get("available", 0)))
			elif reason == "duplicate":
				_game.toast(_mod_tr("prigozhin_fork_recruit_preflight_duplicate"))
			elif reason == "unsupported_role":
				_game.toast(_mod_tr("prigozhin_fork_recruit_queue_role"))
			elif reason in ["source_not_ready", "source_unavailable", "source_review"]:
				_game.toast(_mod_tr("prigozhin_fork_recruit_" + reason))
			else:
				_game.toast(_mod_tr("prigozhin_fork_recruit_preflight_unavailable"))
	)
	row.add_child(submit)
