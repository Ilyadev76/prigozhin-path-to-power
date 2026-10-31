extends VBoxContainer

const Recruitment = preload("res://mods/prigozhin_fork/systems/pmc_recruitment.gd")
const ArmyOperations = preload("res://mods/prigozhin_fork/systems/army_operations.gd")

func configure(owner, game: PaxGame, record_id: int, refresh_callback: Callable) -> void:
	var note: Label = Label.new()
	note.text = owner.tr_key("prigozhin_fork_recruit_review_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var row: HBoxContainer = HBoxContainer.new()
	add_child(row)
	var choices: OptionButton = OptionButton.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for unit in ArmyOperations.player_units(owner):
		if unit is Dictionary and int(unit.get("id", 0)) > 0:
			choices.add_item("#%d · %s · %d" % [int(unit["id"]), str(unit.get("name", "")), int(unit.get("humans", 0))], int(unit["id"]))
	row.add_child(choices)
	var acknowledge: CheckBox = CheckBox.new()
	acknowledge.text = owner.tr_key("prigozhin_fork_recruit_review_ack")
	add_child(acknowledge)
	var bind_button: Button = Button.new()
	bind_button.text = owner.tr_key("prigozhin_fork_recruit_review_bind")
	bind_button.disabled = true
	acknowledge.toggled.connect(func(checked: bool): bind_button.disabled = not checked or choices.item_count == 0)
	bind_button.pressed.connect(func():
		if not acknowledge.button_pressed or choices.selected < 0:
			return
		if Recruitment.reconcile(owner, game, record_id, choices.get_selected_id()):
			game.toast(owner.tr_key("prigozhin_fork_recruit_review_bound"))
			refresh_callback.call()
		else:
			game.toast(owner.tr_key("prigozhin_fork_recruit_review_rejected"))
	)
	row.add_child(bind_button)
	var archive_button: Button = Button.new()
	archive_button.text = owner.tr_key("prigozhin_fork_recruit_review_archive")
	archive_button.pressed.connect(func():
		if Recruitment.archive_review(owner, game, record_id):
			refresh_callback.call()
		else:
			game.toast(owner.tr_key("prigozhin_fork_recruit_source_review"))
	)
	add_child(archive_button)
