extends VBoxContainer

const Movement = preload("res://mods/prigozhin_fork/systems/pmc_movement.gd")

var _owner = null
var _game: PaxGame = null
var _unit_id: int = 0
var _preview: Dictionary = {}
var _destination: LineEdit
var _choices: OptionButton
var _details: Label
var _confirm: Button
var _refresh: Callable

func configure(owner, game: PaxGame, unit_id: int, refresh_callback: Callable) -> void:
	_owner = owner
	_game = game
	_unit_id = unit_id
	_refresh = refresh_callback
	add_theme_constant_override("separation", 6)
	var heading: Label = Label.new()
	heading.text = _t("prigozhin_fork_movement_title")
	heading.add_theme_color_override("font_color", Color(0.90, 0.78, 0.46))
	add_child(heading)
	var note: Label = Label.new()
	note.text = _t("prigozhin_fork_movement_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var search_row: HBoxContainer = HBoxContainer.new()
	add_child(search_row)
	_destination = LineEdit.new()
	_destination.placeholder_text = _t("prigozhin_fork_movement_destination")
	_destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_destination.max_length = 100
	_destination.text_changed.connect(func(_value: String): _invalidate())
	search_row.add_child(_destination)
	var search: Button = Button.new()
	search.text = _t("prigozhin_fork_movement_search")
	search.pressed.connect(_search)
	search_row.add_child(search)
	_destination.text_submitted.connect(func(_value: String): _search())
	_choices = OptionButton.new()
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices.item_selected.connect(func(_index: int): _show_preview())
	_choices.visible = false
	add_child(_choices)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_details)
	_confirm = Button.new()
	_confirm.text = _t("prigozhin_fork_movement_confirm")
	_confirm.disabled = true
	_confirm.pressed.connect(_begin)
	add_child(_confirm)
	var last: Dictionary = {}
	for entry in _owner._pmc_movements:
		if entry is Dictionary and int(entry.get("unit_id", 0)) == unit_id and str(entry.get("side", "")) == _game.country():
			last = entry
	if not last.is_empty():
		var status: Label = Label.new()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.text = _t("prigozhin_fork_movement_record") % [int(last.get("id", 0)), _t("prigozhin_fork_movement_" + str(last.get("status", "submitted"))), int(last.get("destination", 0))]
		if last.has("losses_delta"):
			status.text += "\n" + (_t("prigozhin_fork_movement_losses") % [int(last.get("humans", 0)), str(last.get("losses_delta", 0))])
		add_child(status)
		if str(last.get("status", "")) in ["marching", "engaged"]:
			var stop: Button = Button.new()
			stop.text = _t("prigozhin_fork_movement_stop")
			stop.pressed.connect(func():
				if Movement.stop(_owner, _game, _unit_id):
					_refresh.call()
				else:
					_game.toast(_t("prigozhin_fork_movement_changed"))
			)
			add_child(stop)

func _t(key: String) -> String:
	return str(_owner.tr_key(key))

func _invalidate() -> void:
	_preview.clear()
	if is_instance_valid(_confirm):
		_confirm.disabled = true
	if is_instance_valid(_choices):
		_choices.visible = false
	if is_instance_valid(_details):
		_details.text = ""

func _search() -> void:
	_invalidate()
	var state: Dictionary = Movement.context(_owner, _game, _unit_id)
	if not bool(state.get("ok", false)):
		_details.text = _t("prigozhin_fork_movement_unavailable")
		return
	var query: String = _destination.text.strip_edges().to_lower()
	_choices.clear()
	if query.is_empty():
		return
	if query.is_valid_int():
		var sector: int = int(query)
		var data: Dictionary = _game.province(_game.home_body(), sector) if sector > 0 and sector <= _game.province_count(_game.home_body()) else {}
		if not data.is_empty():
			_choices.add_item("%s · #%d" % [str(data.get("name", "")), sector], sector)
	else:
		for sector in range(1, _game.province_count(_game.home_body()) + 1):
			var data: Dictionary = _game.province(_game.home_body(), sector)
			var name_text: String = str(data.get("name", ""))
			if name_text.to_lower().contains(query):
				_choices.add_item("%s · #%d" % [name_text, sector], sector)
				if _choices.item_count >= 30:
					break
	_choices.visible = _choices.item_count > 0
	if _choices.item_count == 0:
		_details.text = _t("prigozhin_fork_movement_destination_error")
	else:
		_choices.select(0)
		_show_preview()

func _show_preview() -> void:
	_confirm.disabled = true
	_preview.clear()
	if _choices.selected < 0:
		return
	var result: Dictionary = Movement.preview(_owner, _game, _unit_id, _choices.get_selected_id())
	if not bool(result.get("ok", false)):
		var reason: String = str(result.get("reason", "unavailable"))
		_details.text = _t("prigozhin_fork_movement_destination_error" if reason == "destination" else "prigozhin_fork_movement_" + reason)
		return
	_preview = result
	_details.text = _t("prigozhin_fork_movement_preview") % [int(result["source"]), int(result["destination"]), int(result["days"]), int(result["crossings"])]
	_confirm.disabled = false

func _begin() -> void:
	_confirm.disabled = true
	var result: Dictionary = Movement.begin(_owner, _game, _preview)
	_preview.clear()
	if bool(result.get("ok", false)):
		_game.toast(_t("prigozhin_fork_movement_" + str(result["record"]["status"])))
		_refresh.call()
	else:
		var reason: String = str(result.get("reason", "unavailable"))
		_details.text = _t("prigozhin_fork_movement_destination_error" if reason == "destination" else "prigozhin_fork_movement_" + reason)
