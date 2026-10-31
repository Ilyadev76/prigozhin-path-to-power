extends VBoxContainer

const Airlift = preload("res://mods/prigozhin_fork/systems/pmc_airlift.gd")

var _owner = null
var _game: PaxGame = null
var _units: Dictionary = {}
var _search: LineEdit
var _destinations: OptionButton
var _details: Label
var _confirm: Button
var _preview: Dictionary = {}

func text_key(key: String) -> String:
	return str(_owner.tr_key(key))

func configure(owner, game: PaxGame) -> void:
	_owner = owner
	_game = game
	add_theme_constant_override("separation", 6)
	var title: Label = Label.new()
	title.text = text_key("prigozhin_fork_airlift_title")
	title.add_theme_color_override("font_color", Color(0.90, 0.78, 0.46))
	add_child(title)
	var note: Label = Label.new()
	note.text = text_key("prigozhin_fork_airlift_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	if not game.main.player or str(game.main.player.player_role) not in ["person", "organization"]:
		note.text += "\n" + text_key("prigozhin_fork_airlift_role")
		return
	for unit in game.main.model.armies.units:
		if not (unit is Dictionary) or not bool(unit.get("our", false)) or str(unit.get("whose", "")) != game.country() or bool(unit.get("self", false)):
			continue
		if not bool(unit.get("prigozhin_fork_pmc", false)) and not str(unit.get("name", "")).to_lower().contains("вагнер"):
			continue
		var id: int = int(unit.get("id", 0))
		var choice: CheckBox = CheckBox.new()
		choice.text = "#%d · %s · %d" % [id, str(unit.get("name", "")), int(unit.get("humans", 0))]
		choice.toggled.connect(func(_checked: bool): invalidate())
		_units[id] = choice
		add_child(choice)
	var row: HBoxContainer = HBoxContainer.new()
	add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = text_key("prigozhin_fork_movement_destination")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.max_length = 100
	_search.text_changed.connect(func(_value: String):
		invalidate()
		if is_instance_valid(_destinations):
			_destinations.clear()
	)
	_search.text_submitted.connect(func(_value: String): find_destination())
	row.add_child(_search)
	var find_button: Button = Button.new()
	find_button.text = text_key("prigozhin_fork_airlift_calculate")
	find_button.pressed.connect(find_destination)
	row.add_child(find_button)
	_destinations = OptionButton.new()
	_destinations.item_selected.connect(func(_index: int): calculate())
	add_child(_destinations)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_details)
	_confirm = Button.new()
	_confirm.text = text_key("prigozhin_fork_airlift_book")
	_confirm.disabled = true
	_confirm.pressed.connect(confirm_booking)
	add_child(_confirm)
	for flight in owner._pmc_airlifts:
		if not (flight is Dictionary) or str(flight.get("side", "")) != game.country():
			continue
		var history: Label = Label.new()
		history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		history.text = text_key("prigozhin_fork_airlift_history") % [int(flight.get("id", 0)), text_key("prigozhin_fork_airlift_" + str(flight.get("status", "review"))), int(flight.get("people", 0)), int(flight.get("aircraft", 0)), int(flight.get("source", 0)), int(flight.get("destination", 0))]
		history.text += "\n" + (text_key("prigozhin_fork_airlift_finance") % [str(flight.get("paid", 0)), str(flight.get("refunded", 0))])
		if flight.has("actual_arrival_day"):
			history.text += "\n" + (text_key("prigozhin_fork_airlift_arrival_record") % [int(flight["actual_arrival_day"]), int(flight.get("landed_province", 0))])
		add_child(history)
		if str(flight.get("status", "")) == "loading" and game.day() < int(flight.get("takeoff_day", 0)):
			var id: int = int(flight.get("id", 0))
			var cancel_button: Button = Button.new()
			cancel_button.text = text_key("prigozhin_fork_airlift_cancel")
			cancel_button.pressed.connect(func():
				if not Airlift.cancel(owner, game, id):
					game.toast(text_key("prigozhin_fork_airlift_changed"))
			)
			add_child(cancel_button)

func invalidate() -> void:
	_preview.clear()
	if is_instance_valid(_confirm):
		_confirm.disabled = true

func find_destination() -> void:
	invalidate()
	_destinations.clear()
	var query: String = _search.text.strip_edges().to_lower()
	if query.is_empty():
		return
	var total: int = _game.province_count(_game.home_body())
	if query.is_valid_int():
		var id: int = int(query)
		if id > 0 and id <= total:
			var province: Dictionary = _game.province(_game.home_body(), id)
			if not province.is_empty():
				_destinations.add_item("%s · #%d" % [str(province.get("name", "")), id], id)
	else:
		for id in range(1, total + 1):
			var province: Dictionary = _game.province(_game.home_body(), id)
			if str(province.get("name", "")).to_lower().contains(query):
				_destinations.add_item("%s · #%d" % [str(province["name"]), id], id)
				if _destinations.item_count >= 30:
					break
	if _destinations.item_count == 0:
		_details.text = text_key("prigozhin_fork_movement_destination_error")
		return
	_destinations.select(0)
	calculate()

func calculate() -> void:
	invalidate()
	var ids: Array = []
	for id in _units:
		if _units[id].button_pressed:
			ids.append(int(id))
	var result: Dictionary = Airlift.preview(_owner, _game, ids, _destinations.get_selected_id())
	if not bool(result.get("ok", false)):
		_details.text = text_key("prigozhin_fork_airlift_" + str(result.get("reason", "unavailable")))
		return
	_preview = result
	_details.text = (text_key("prigozhin_fork_airlift_route_quote") % [int(result["source"]), int(result["destination"])]) + "\n" + (text_key("prigozhin_fork_airlift_preview") % [int(result["people"]), int(result["aircraft"]), int(result["loading_days"]), int(result["flight_days"]), str(result["fee"]), str(result["reserve"]), str(result["total"])])
	_confirm.disabled = false

func confirm_booking() -> void:
	_confirm.disabled = true
	var result: Dictionary = Airlift.book(_owner, _game, _preview)
	_preview.clear()
	if not bool(result.get("ok", false)):
		_details.text = text_key("prigozhin_fork_airlift_" + str(result.get("reason", "unavailable")))
