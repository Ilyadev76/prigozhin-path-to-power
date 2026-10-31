extends VBoxContainer

const Supplies = preload("res://mods/prigozhin_fork/systems/supply_contracts.gd")
var _owner = null
var _game: PaxGame = null
var _partner: OptionButton
var _goods: OptionButton
var _amount: SpinBox
var _months: SpinBox
var _terms: Label
var _confirm: Button
var _quote: Dictionary = {}
var _list: VBoxContainer

func t(key: String) -> String:
	return _owner.tr_key("prigozhin_fork_supply_" + key)

func configure(owner, game: PaxGame) -> void:
	_owner = owner
	_game = game
	add_theme_constant_override("separation", 8)
	var title: Label = Label.new()
	title.text = t("title")
	add_child(title)
	var help: Label = Label.new()
	help.text = t("help")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	_partner = OptionButton.new()
	for name in game.countries():
		if name != game.country():
			_partner.add_item(name)
	add_child(_partner)
	_goods = OptionButton.new()
	for key in Supplies.GOODS:
		_goods.add_item(t("good_" + key))
	add_child(_goods)
	var row: HBoxContainer = HBoxContainer.new()
	add_child(row)
	_amount = SpinBox.new()
	_amount.min_value = 0.01
	_amount.max_value = 1000000.0
	_amount.step = 0.01
	_amount.value = 10.0
	_amount.prefix = t("amount")
	row.add_child(_amount)
	_months = SpinBox.new()
	_months.min_value = 1
	_months.max_value = 120
	_months.value = 3
	_months.suffix = t("months")
	row.add_child(_months)
	var calculate: Button = Button.new()
	calculate.text = t("calculate")
	calculate.pressed.connect(_calculate)
	add_child(calculate)
	_terms = Label.new()
	_terms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_terms)
	_confirm = Button.new()
	_confirm.text = t("confirm")
	_confirm.disabled = true
	_confirm.pressed.connect(_book)
	add_child(_confirm)
	_partner.item_selected.connect(func(_i: int): _invalidate())
	_goods.item_selected.connect(func(_i: int): _invalidate())
	_amount.value_changed.connect(func(_v: float): _invalidate())
	_months.value_changed.connect(func(_v: float): _invalidate())
	_list = VBoxContainer.new()
	add_child(_list)
	refresh()

func _invalidate() -> void:
	_quote = {}
	_confirm.disabled = true
	_terms.text = ""

func _calculate() -> void:
	_invalidate()
	if _partner.selected < 0 or _goods.selected < 0:
		_terms.text = t("terms")
		return
	var result: Dictionary = Supplies.quote(_owner, _game, _partner.get_item_text(_partner.selected), Supplies.GOODS[_goods.selected], _amount.value, int(_months.value))
	if not bool(result.get("ok", false)):
		_terms.text = t(str(result.get("reason", "terms")))
		return
	_quote = result
	_terms.text = t("quote") % [str(result["partner"]), float(result["amount"]), t("good_" + str(result["key"])), float(result["monthly_cost"]), int(result["months"]), int(result["first_day"])]
	_confirm.disabled = false

func _book() -> void:
	if _quote.is_empty():
		return
	var result: Dictionary = Supplies.confirm(_owner, _game, _quote)
	_invalidate()
	_terms.text = t("created") if bool(result.get("ok", false)) else t(str(result.get("reason", "terms")))
	refresh()

func refresh() -> void:
	if not _list:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if not Supplies.ready(_owner, _game):
		return
	for record in _game.main.model.supplies:
		if not (record is Dictionary) or str(record.get("dir", "sell")) != "buy":
			continue
		var line: Label = Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = t("record") % [str(record.get("recipient", "")), str(record.get("key", "")), float(record.get("v_month", 0.0)), int(record.get("months_left", 0)), int(record.get("next_day", 0)), float(record.get("delivered", 0.0)), int(record.get("disrupted", 0))]
		_list.add_child(line)
		var token: String = str(record.get("prigozhin_fork_supply_id", ""))
		if token.is_empty() or str(record.get("prigozhin_fork_supply_side", "")) != _game.country():
			continue
		var button: Button = Button.new()
		button.text = t("cancel")
		button.pressed.connect(func():
			if button.text != t("cancel_confirm"):
				button.text = t("cancel_confirm")
				return
			var cancelled: bool = Supplies.cancel(_owner, _game, token)
			_terms.text = t("cancelled") if cancelled else t("changed")
			refresh()
		)
		_list.add_child(button)
