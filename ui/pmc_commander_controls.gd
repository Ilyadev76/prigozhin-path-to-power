extends VBoxContainer

const Mandates = preload("res://mods/prigozhin_fork/systems/pmc_mandates.gd")
const Commanders = preload("res://mods/prigozhin_fork/systems/pmc_commanders.gd")

func configure(owner, game: PaxGame, mandate_id: int, refresh_callback: Callable) -> void:
	var record: Dictionary = Commanders.active(owner, game, mandate_id)
	if record.is_empty():
		return
	var delegation: CheckButton = CheckButton.new()
	delegation.text = owner.tr_key("prigozhin_fork_commander_delegate")
	delegation.button_pressed = bool(record.get("movement_authority", false))
	delegation.toggled.connect(func(enabled: bool):
		if Mandates.set_movement_authority(owner, game, mandate_id, enabled):
			if enabled:
				owner._request_pmc_commanders(game)
			refresh_callback.call()
		else:
			game.toast(owner.tr_key("prigozhin_fork_mandate_invalid"))
			refresh_callback.call()
	)
	add_child(delegation)
	var note: Label = Label.new()
	note.text = owner.tr_key("prigozhin_fork_commander_scope")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	if record.has("commander_last_status"):
		var status: String = str(record.get("commander_last_status", "rejected"))
		if status not in ["hold", "rejected", "marching", "submitted"]:
			status = "rejected"
		var last: Label = Label.new()
		last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		last.text = owner.tr_key("prigozhin_fork_commander_last_decision") % [int(record.get("commander_last_day", 0)), int(record.get("commander_last_unit_id", 0)), owner.tr_key("prigozhin_fork_commander_status_" + status), str(record.get("commander_last_reason", ""))]
		add_child(last)
	if bool(record.get("commander_review_required", false)):
		var warning: Label = Label.new()
		var reasons = record.get("commander_review_reasons", [])
		var budget_review: bool = reasons is Array and reasons.has("budget")
		var territory_review: bool = not (reasons is Array) or reasons.is_empty() or reasons.has("territory")
		warning.text = owner.tr_key("prigozhin_fork_commander_budget_review") if budget_review else ""
		if territory_review:
			warning.text += ("\n" if not warning.text.is_empty() else "") + owner.tr_key("prigozhin_fork_commander_outside_report")
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.add_theme_color_override("font_color", Color(0.95, 0.69, 0.35))
		add_child(warning)
		var acknowledge: Button = Button.new()
		acknowledge.text = owner.tr_key("prigozhin_fork_commander_acknowledge")
		acknowledge.pressed.connect(func():
			if Mandates.set_movement_authority(owner, game, mandate_id, true, true):
				owner._request_pmc_commanders(game)
				refresh_callback.call()
		)
		add_child(acknowledge)
