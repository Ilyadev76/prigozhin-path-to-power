extends "res://mods/prigozhin_fork/ui/tabs/hq_tab_base.gd"

const SupplyControls = preload("res://mods/prigozhin_fork/ui/supply_contract_controls.gd")
const BusinessControls = preload("res://mods/prigozhin_fork/ui/business_controls.gd")

var _deals_list_container: VBoxContainer = null

func configure(main_mod, game, callbacks: Dictionary) -> void:
	configure_base(main_mod, game, callbacks)
	_build_deals_tab(self)
	refresh()

func refresh() -> void:
	_refresh_deals_tab()

func _build_deals_tab(parent: Control) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	parent.add_child(box)

	var header: Label = Label.new()
	header.text = _mod_tr("prigozhin_fork_records_title")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	box.add_child(header)

	var sub: Label = Label.new()
	sub.text = _mod_tr("prigozhin_fork_records_description")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(sub)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	_deals_list_container = VBoxContainer.new()
	_deals_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deals_list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_deals_list_container)

	var btn_bar: HBoxContainer = HBoxContainer.new()
	btn_bar.add_theme_constant_override("separation", 12)
	box.add_child(btn_bar)

	var btn_refresh: Button = Button.new()
	btn_refresh.text = "🔄 Обновить статус договоров"
	btn_refresh.custom_minimum_size = Vector2(250, 36)
	btn_refresh.pressed.connect(func(): _refresh_deals_tab())
	btn_bar.add_child(btn_refresh)

	_refresh_deals_tab()

func _refresh_deals_tab() -> void:
	if not _deals_list_container or Pax.world_busy():
		return
	for c in _deals_list_container.get_children():
		_deals_list_container.remove_child(c)
		c.queue_free()
	if _main_mod and _game:
		var procurement: VBoxContainer = SupplyControls.new()
		_deals_list_container.add_child(procurement)
		procurement.configure(_main_mod, _game)
		var businesses: VBoxContainer = BusinessControls.new()
		_deals_list_container.add_child(businesses)
		businesses.configure(_main_mod, _game, _send_order_callback)

	var contracts_header: Label = Label.new()
	contracts_header.text = _mod_tr("prigozhin_fork_native_contracts")
	contracts_header.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
	_deals_list_container.add_child(contracts_header)
	var contracts_available: bool = _game != null and _game.main != null and _game.main.model != null
	if not contracts_available:
		var unavailable: Label = Label.new()
		unavailable.text = _mod_tr("prigozhin_fork_contracts_unavailable")
		_deals_list_container.add_child(unavailable)
	else:
		var contracts: Array = _game.main.model.supplies
		if contracts.is_empty():
			var no_contracts: Label = Label.new()
			no_contracts.text = _mod_tr("prigozhin_fork_contracts_empty")
			_deals_list_container.add_child(no_contracts)
		for item in contracts:
			if not (item is Dictionary):
				continue
			var line: Label = Label.new()
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var direction: String = _mod_tr("prigozhin_fork_contract_buy") if str(item.get("dir", "sell")) == "buy" else _mod_tr("prigozhin_fork_contract_sell")
			line.text = _mod_tr("prigozhin_fork_contract_line") % [direction, str(item.get("recipient", "")), str(item.get("key", "")), str(item.get("v_month", 0)), str(item.get("price", 0)), int(item.get("disrupted", 0))]
			_deals_list_container.add_child(line)
	_add_mandate_history()
	var notes_header: Label = Label.new()
	notes_header.text = _mod_tr("prigozhin_fork_records_title")
	notes_header.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	_deals_list_container.add_child(notes_header)

	var deals: Array = []
	if _main_mod and "_deals" in _main_mod:
		deals = _main_mod._deals

	if deals.is_empty():
		var empty_card: PanelContainer = PanelContainer.new()
		empty_card.add_theme_stylebox_override("panel", _card_box_style(Color(0.12, 0.14, 0.18, 0.9), Color(0.3, 0.35, 0.45, 0.6)))
		var lbl: Label = Label.new()
		lbl.text = _mod_tr("prigozhin_fork_records_empty")
		lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		empty_card.add_child(lbl)
		_deals_list_container.add_child(empty_card)
		return

	for deal in deals:
		if typeof(deal) != TYPE_DICTIONARY:
			continue
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var st: String = str(deal.get("status", "active"))
		var border_col: Color = Color(0.25, 0.75, 0.45, 0.9) if st == "active" else (Color(0.9, 0.6, 0.2, 0.9) if st == "delayed" else Color(0.85, 0.3, 0.3, 0.9))
		card.add_theme_stylebox_override("panel", _card_box_style(Color(0.10, 0.12, 0.16, 0.95), border_col))

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 5)
		card.add_child(vbox)

		var top_h: HBoxContainer = HBoxContainer.new()
		vbox.add_child(top_h)

		var title_lbl: RichTextLabel = RichTextLabel.new()
		title_lbl.fit_content = true
		title_lbl.selection_enabled = true
		title_lbl.bbcode_enabled = true
		var partner: String = str(deal.get("partner", ""))
		var p_name: String = "Губернатор Д. Миронов" if partner == "mironov" else ("Минобороны РФ" if partner == "mo" else ("Кремль (АП)" if partner == "kremlin" else partner))
		var badge_col: String = "#40cc70" if st == "active" else "#e0a030"
		var st_text: String = _mod_tr("prigozhin_fork_ai_report_title") if st == "report" else _mod_tr("prigozhin_fork_record_unverified")

		title_lbl.text = "[b][color=#f2f2f5]" + str(deal.get("title", "Соглашение")) + "[/color][/b]  [color=" + badge_col + "]● " + st_text + "[/color]  | Партнёр: [color=#85b5ff]" + p_name + "[/color]"
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_h.add_child(title_lbl)

		var terms_lbl: RichTextLabel = RichTextLabel.new()
		terms_lbl.fit_content = true
		terms_lbl.selection_enabled = true
		terms_lbl.bbcode_enabled = true
		terms_lbl.text = str(deal.get("terms", ""))

		vbox.add_child(terms_lbl)


		_deals_list_container.add_child(card)

func _add_mandate_history() -> void:
	if not _main_mod or not _game or _main_mod._pmc_mandates.is_empty():
		return
	var header: Label = Label.new()
	header.text = _mod_tr("prigozhin_fork_mandate_history_title")
	header.add_theme_color_override("font_color", Color(0.90, 0.78, 0.46))
	_deals_list_container.add_child(header)
	for record in _main_mod._pmc_mandates:
		if not (record is Dictionary) or str(record.get("side", "")) != _game.country():
			continue
		var status: String = str(record.get("status", "review"))
		if status not in ["active", "expired", "closed", "review"]:
			status = "review"
		var text: PackedStringArray = PackedStringArray()
		text.append(_mod_tr("prigozhin_fork_mandate_history_line") % [int(record.get("id", 0)), _mod_tr("prigozhin_fork_mandate_state_" + status), str(record.get("task", ""))])
		text.append(_mod_tr("prigozhin_fork_mandate_confirmed_costs") % str(record.get("confirmed_direct_cost", 0.0)))
		var receipts = record.get("confirmed_receipts", [])
		if receipts is Array:
			for receipt in receipts:
				if receipt is Dictionary:
					text.append(_mod_tr("prigozhin_fork_mandate_receipt") % [int(receipt.get("recruitment_id", 0)), int(receipt.get("unit_id", 0)), int(receipt.get("hired", 0)), str(receipt.get("amount", 0.0)), int(receipt.get("day", 0))])
		var line: Label = Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "\n".join(text)
		_deals_list_container.add_child(line)
