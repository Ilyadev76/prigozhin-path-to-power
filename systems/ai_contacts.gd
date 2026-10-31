extends RefCounted

const PmcFacts = preload("res://mods/prigozhin_fork/systems/pmc_facts.gd")

static func _record_report(owner, game: PaxGame, sender: String, summary: String) -> void:
	if not is_instance_valid(owner) or not game or owner._last_game != game or summary.strip_edges().is_empty():
		return
	owner._deals.append({"id": "report_" + str(Time.get_ticks_usec()), "partner": sender,
		"title": owner.tr_key("prigozhin_fork_ai_report_title") + ": " + sender,
		"terms": summary, "cost": 0.0, "risk": 0, "status": "report"})
	game.toast(owner.tr_key("prigozhin_fork_ai_report_notice") % sender)
	owner._refresh_ui()

static func request_ai_scenario(owner, game: PaxGame) -> void:
	if not owner or not game:
		return
	var prompt: String = "Prepare a concise situational briefing based only on provided data. Suggestions are not completed actions. Return JSON: {\"summary\": \"text\"}."
	var data: Dictionary = {"party_rating": owner._nfw_rating, "duma_seats": owner._duma_seats,
		"governor_relations": owner._mironov_loyalty, "kremlin_pressure": owner._kremlin_pressure}
	data["pmc_observation"] = PmcFacts.capture(owner, game)
	var sent: bool = owner.ask_ai("hq_briefing", prompt, data, func(answer: Dictionary) -> void:
		if not is_instance_valid(owner):
			return
		var summary: String = str(answer.get("summary", "")).strip_edges()
		if summary.is_empty():
			game.toast(owner.tr_key("prigozhin_fork_comms_no_reply"))
			return
		_record_report(owner, game, owner.tr_key("prigozhin_fork_ai_hq"), summary)
	)
	if not sent:
		game.toast(owner.tr_key("prigozhin_fork_comms_no_reply"))

static func trigger_autonomous_contact(owner, game: PaxGame) -> void:
	if not owner or not game or owner._autonomous_contact_pending:
		return
	var prompt: String = "Write a brief plausible message from a relevant contact. Use supplied facts; do not claim unconfirmed actions happened. A quiet situation is acceptable. Return JSON: {\"sender\": \"name\", \"summary\": \"text\"}."
	var data: Dictionary = {"party_rating": owner._nfw_rating, "governor_relations": owner._mironov_loyalty,
		"kremlin_pressure": owner._kremlin_pressure, "pmc_observation": PmcFacts.capture(owner, game)}
	owner._autonomous_contact_pending = true
	var sent: bool = owner.ask_ai("hq_contact", prompt, data, func(answer: Dictionary) -> void:
		if not is_instance_valid(owner) or owner._last_game != game:
			return
		owner._autonomous_contact_pending = false
		var sender: String = str(answer.get("sender", "")).strip_edges()
		var summary: String = str(answer.get("summary", "")).strip_edges()
		if sender.is_empty() or summary.is_empty():
			return
		_record_report(owner, game, sender, summary)
	)
	if not sent:
		owner._autonomous_contact_pending = false

static func get_recent_talk_summary(owner, char_name: String, max_msgs: int = 4) -> String:
	if not owner._last_game:
		return ""
	var runtime: Node = owner._last_game.main
	if runtime == null or runtime.model == null:
		return ""
	var feed: Dictionary = runtime.model.talk_feeds
	if not feed.has(char_name):
		return ""

	var arr: Array = feed[char_name]
	if arr.is_empty():
		return ""
		
	var slice: Array = arr.slice(maxi(0, arr.size() - max_msgs))
	var res: String = ""
	for item in slice:
		if typeof(item) == TYPE_ARRAY and item.size() >= 2:
			var speaker: String = "Пригожин" if item[0] == "player" else char_name
			res += "- " + speaker + ": \"" + str(item[1]) + "\"\n"
	return res

static func check_shoigu_quarrel(_owner) -> bool:
	# A keyword in a conversation is not evidence of a real diplomatic outcome.
	return false
