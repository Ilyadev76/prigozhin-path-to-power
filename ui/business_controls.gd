extends VBoxContainer

const Supplies = preload("res://mods/prigozhin_fork/systems/supply_contracts.gd")
var _owner = null
var _game: PaxGame
var _send: Callable
var _status: Label
var _list: VBoxContainer

func t(key: String) -> String:
	return _owner.tr_key("prigozhin_fork_business_" + key)

func configure(owner, game: PaxGame, send_order: Callable) -> void:
	_owner = owner
	_game = game
	_send = send_order
	add_theme_constant_override("separation", 8)
	var title: Label = Label.new()
	title.text = t("title")
	add_child(title)
	var help: Label = Label.new()
	help.text = t("help")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_list = VBoxContainer.new()
	add_child(_list)
	refresh()
	var request: LineEdit = LineEdit.new()
	request.placeholder_text = t("placeholder")
	request.max_length = 2000
	add_child(request)
	var button: Button = Button.new()
	button.text = t("submit")
	button.pressed.connect(func():
		if _submit(request.text, 0):
			request.clear()
	)
	add_child(button)

func _submit(instruction: String, deed_id: int) -> bool:
	if not Supplies.ready(_owner, _game) or not _send.is_valid():
		_status.text = t("busy")
		return false
	if str(_game.main.player_role) not in ["person", "organization"]:
		_status.text = t("role")
		return false
	if instruction.strip_edges().is_empty():
		return false
	var target: Dictionary = {}
	if deed_id > 0:
		for deed in _game.main.model.deeds:
			if deed is Dictionary and int(deed.get("id", 0)) == deed_id:
				target = deed
				break
		if target.is_empty():
			_status.text = t("changed")
			return false
	var text: String = t("order") % instruction.strip_edges()
	if not target.is_empty():
		text = t("target") % [deed_id, str(target.get("title_name", ""))] + "\n" + text
	var accepted: bool = bool(_send.call(text, 2, {"prigozhin_fork_business_deed": deed_id}))
	_status.text = t("pending") if accepted else t("busy")
	return accepted

func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if not Supplies.ready(_owner, _game):
		_status.text = t("busy")
		return
	if str(_game.main.player_role) not in ["person", "organization"]:
		_status.text = t("role")
		return
	var count: int = 0
	for deed in _game.main.model.deeds:
		if not (deed is Dictionary) or str(deed.get("kind", "")) not in ["business", "jobs"]:
			continue
		count += 1
		var id: int = int(deed.get("id", 0))
		var report: PackedStringArray = PackedStringArray()
		report.append(t("record") % [id, str(deed.get("title_name", "")), int(deed.get("where", 0)), int(deed.get("employees", 0)), str(deed.get("buyer", ""))])
		var outcome = deed.get("outcome_weeks", {})
		if outcome is Dictionary and not outcome.is_empty():
			var income: float = float(outcome.get("income", 0.0))
			var expense: float = float(outcome.get("expense", 0.0))
			report.append(t("outcome") % [income, expense, income - expense, float(outcome.get("issue", 0.0)), float(outcome.get("sold", 0.0))])
		else:
			report.append(t("no_outcome"))
		var label: Label = Label.new()
		label.text = "\n".join(report)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(label)
		var line: LineEdit = LineEdit.new()
		line.placeholder_text = t("deed_placeholder")
		line.max_length = 2000
		_list.add_child(line)
		var button: Button = Button.new()
		button.text = t("submit")
		button.pressed.connect(func():
			if _submit(line.text, id):
				line.clear()
		)
		_list.add_child(button)
	if count == 0:
		var empty: Label = Label.new()
		empty.text = t("empty")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
