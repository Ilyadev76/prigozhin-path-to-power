extends RefCounted

const Mandates = preload("res://mods/prigozhin_fork/systems/pmc_mandates.gd")
const Movement = preload("res://mods/prigozhin_fork/systems/pmc_movement.gd")
const MAX_DECISIONS: int = 8

static func exact_id(value) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return 0
	var number: int = int(value)
	return number if number > 0 and float(number) == float(value) else 0

static func active(owner, game: PaxGame, mandate_id: int) -> Dictionary:
	for record in owner._pmc_mandates:
		if record is Dictionary and int(record.get("id", 0)) == mandate_id and str(record.get("side", "")) == game.country() and str(record.get("status", "")) == "active" and game.day() < int(record.get("end_day", 0)):
			return record
	return {}

static func has_player_order(game: PaxGame, unit_id: int, owner = null) -> bool:
	if owner:
		for entry in owner._pmc_recruitment:
			if entry is Dictionary and int(entry.get("target_id", 0)) == unit_id and str(entry.get("side", "")) == game.country() and str(entry.get("status", "")) in ["pending", "blocked", "executing", "review"]:
				return true
	for order in game.main.model.orders:
		if not (order is Dictionary) or str(order.get("status", "")) not in ["being_weighed", "awaits_ok", "queued", "under_way"]:
			continue
		var recruitment = order.get("prigozhin_fork_recruit_proposal", {})
		if recruitment is Dictionary and exact_id(recruitment.get("target_id", 0)) == unit_id:
			return true
		var place = order.get("place", {})
		if place is Dictionary and exact_id(place.get("detachment", 0)) == unit_id:
			return true
		var request = order.get("request", {})
		if request is Dictionary:
			var actions = request.get("detachments", [])
			if actions is Array:
				for action in actions:
					if action is Dictionary and exact_id(action.get("id", 0)) == unit_id:
						return true
		var march = order.get("march", {})
		if march is Dictionary and Mandates.has_id(march.get("ids", []), unit_id):
			return true
	return false

static func add_destination(game: PaxGame, ids: Array, choices: Array, id: int) -> void:
	if id <= 0 or Mandates.has_id(ids, id):
		return
	var province: Dictionary = game.province(game.home_body(), id)
	if province.is_empty():
		return
	ids.append(id)
	choices.append({"id": id, "name": str(province.get("name", ""))})

# One batch per observed game day, only for explicitly delegated, idle units.
# Longer jumps do not invent decisions or movements in the skipped interval.
static func request_round(owner, game: PaxGame) -> bool:
	if not owner or not game or owner._last_game != game or owner._pmc_commander_pending or Pax.world_busy() or not is_instance_valid(game.main) or not game.main.model or not game.main.model.armies or game.main.rewind_state.rewinding:
		return false
	var records: Array = []
	for record in owner._pmc_mandates:
		if record is Dictionary and bool(record.get("movement_authority", false)) and not bool(record.get("commander_review_required", false)) and str(record.get("side", "")) == game.country() and str(record.get("status", "")) == "active" and game.day() < int(record.get("end_day", 0)) and int(record.get("commander_requested_day", -1)) != game.day():
			records.append(record)
	# Tasks that have waited longer get a turn before yesterday's batch.
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("commander_requested_day", -1)) < int(b.get("commander_requested_day", -1)))
	var assignments: Array = []
	var locks: Dictionary = {}
	for record in records:
		var ids = record.get("unit_ids", [])
		var territory = record.get("provinces", [])
		if not (ids is Array) or not (territory is Array):
			continue
		var previous_days = record.get("commander_unit_days", {})
		var unit_days: Dictionary = previous_days if previous_days is Dictionary else {}
		var ordered_ids: Array = ids.duplicate()
		ordered_ids.sort_custom(func(a, b) -> bool: return int(unit_days.get(str(exact_id(a)), -1)) < int(unit_days.get(str(exact_id(b)), -1)))
		for raw_id in ordered_ids:
			var unit_id: int = exact_id(raw_id)
			if locks.has(str(unit_id)) or has_player_order(game, unit_id, owner):
				continue
			var state: Dictionary = Movement.context(owner, game, unit_id)
			if not bool(state.get("ok", false)):
				continue
			var unit: Dictionary = state["unit"]
			var road = unit.get("road", [])
			if not (road is Array) or not road.is_empty() or not str(unit.get("group_id", "")).is_empty() or not state["army"].battle_with_unit(unit_id).is_empty() or not Movement.active_record(owner, game.country(), unit_id).is_empty():
				continue
			var destinations: Array = []
			var destination_ids: Array = []
			for sector in territory.slice(0, 64):
				add_destination(game, destination_ids, destinations, int(sector))
			var source: int = int(unit.get("province", 0))
			for sector in game.main.model.earth_provinces.neighbours(source):
				add_destination(game, destination_ids, destinations, int(sector))
			var mandate_id: int = int(record.get("id", 0))
			var stores = unit.get("provisions", {})
			assignments.append({"mandate_id": mandate_id, "unit_id": unit_id, "task": str(record.get("task", "")),
				"territory": territory.slice(0, 64), "candidates": destinations, "position": source,
				"humans": int(unit.get("humans", 0)), "provisions": stores.duplicate(true) if stores is Dictionary else {}})
			locks[str(unit_id)] = {"mandate_id": mandate_id, "revision": int(record.get("commander_revision", 0)),
				"source": source, "humans": int(unit.get("humans", 0)), "destination_ids": destination_ids}
			if assignments.size() >= MAX_DECISIONS:
				break
		if assignments.size() >= MAX_DECISIONS:
			break
	if assignments.is_empty():
		return false
	var observed_day: int = game.day()
	var generation: int = int(owner._pmc_commander_generation)
	for assignment in assignments:
		var record: Dictionary = active(owner, game, int(assignment["mandate_id"]))
		if not record.is_empty():
			record["commander_requested_day"] = observed_day
	owner._pmc_commander_pending = true
	var sent: bool = owner.ask_ai("pmc_commanders", owner.tr_key("prigozhin_fork_commander_prompt"), {"observed_day": observed_day, "assignments": assignments}, func(answer: Dictionary) -> void:
		if not is_instance_valid(owner) or owner._last_game != game or int(owner._pmc_commander_generation) != generation:
			return
		owner._pmc_commander_pending = false
		if Pax.world_busy() or not is_instance_valid(game.main) or game.main.rewind_state.rewinding or game.day() != observed_day:
			return
		apply_decisions(owner, game, answer, locks)
		owner._refresh_ui()
	)
	if not sent:
		owner._pmc_commander_pending = false
		for assignment in assignments:
			var record: Dictionary = active(owner, game, int(assignment["mandate_id"]))
			if not record.is_empty():
				record.erase("commander_requested_day")
		game.toast(owner.tr_key("prigozhin_fork_commander_no_reply"))
	else:
		for assignment in assignments:
			var record: Dictionary = active(owner, game, int(assignment["mandate_id"]))
			if record.is_empty():
				continue
			var days = record.get("commander_unit_days", {})
			if not (days is Dictionary):
				days = {}
			days[str(int(assignment["unit_id"]))] = observed_day
			record["commander_unit_days"] = days
	return sent

static func apply_decisions(owner, game: PaxGame, answer: Dictionary, locks: Dictionary) -> void:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or not game.main.model or not game.main.model.armies or game.main.rewind_state.rewinding:
		return
	var decisions = answer.get("decisions", [])
	if not (decisions is Array) or decisions.is_empty():
		game.toast(owner.tr_key("prigozhin_fork_commander_no_reply"))
		return
	var seen: Dictionary = {}
	var handled: int = 0
	for decision in decisions.slice(0, MAX_DECISIONS):
		if not (decision is Dictionary):
			continue
		var raw_id = decision.get("unit_id", 0)
		if typeof(raw_id) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_id)) or float(raw_id) != float(int(raw_id)):
			continue
		var key: String = str(int(raw_id))
		if not locks.has(key) or seen.has(key):
			continue
		seen[key] = true
		var locked: Dictionary = locks[key]
		var record: Dictionary = active(owner, game, int(locked["mandate_id"]))
		if record.is_empty() or int(record.get("commander_revision", 0)) != int(locked["revision"]) or not bool(record.get("movement_authority", false)) or bool(record.get("commander_review_required", false)) or exact_id(decision.get("mandate_id", 0)) != int(record.get("id", 0)) or not Mandates.has_id(record.get("unit_ids", []), int(raw_id)):
			continue
		var state: Dictionary = Movement.context(owner, game, int(raw_id))
		if not bool(state.get("ok", false)) or int(state["unit"].get("province", 0)) != int(locked["source"]) or int(state["unit"].get("humans", 0)) != int(locked["humans"]) or has_player_order(game, int(raw_id), owner):
			continue
		var reason: String = str(decision.get("reason", "")).strip_edges().left(400)
		handled += 1
		record["commander_last_reason"] = reason
		record["commander_last_day"] = game.day()
		record["commander_last_unit_id"] = int(raw_id)
		var action: String = str(decision.get("action", ""))
		if action == "hold":
			record["commander_last_status"] = "hold"
			continue
		var destination = decision.get("destination", 0)
		if action != "move" or typeof(destination) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(destination)) or float(destination) != float(int(destination)) or not Mandates.has_id(locked["destination_ids"], int(destination)):
			record["commander_last_status"] = "rejected"
			continue
		var preview: Dictionary = Movement.preview(owner, game, int(raw_id), int(destination))
		if not bool(preview.get("ok", false)):
			record["commander_last_status"] = "rejected"
			continue
		var outside: bool = false
		for sector in preview["road"]:
			if not Mandates.has_id(record.get("provinces", []), int(sector)):
				outside = true
		var result: Dictionary = Movement.begin(owner, game, preview)
		if not bool(result.get("ok", false)):
			record["commander_last_status"] = "rejected"
			continue
		result["record"]["mandate_id"] = int(record["id"])
		result["record"]["origin"] = "commander"
		result["record"]["reason"] = reason
		record["commander_last_status"] = str(result["record"]["status"])
		if outside:
			Mandates.require_review(record, "territory")
			record["commander_exception_day"] = game.day()
		var text: String = owner.tr_key("prigozhin_fork_commander_move_report") % [str(state["unit"].get("name", "")), int(destination), owner.tr_key("prigozhin_fork_movement_" + str(result["record"]["status"])), reason]
		if outside:
			text += "\n" + owner.tr_key("prigozhin_fork_commander_outside_report")
		owner._deals.append({"id": "pmc_commander_%d_%d_%d" % [int(record["id"]), int(raw_id), game.day()],
			"partner": owner.tr_key("prigozhin_fork_ai_hq"), "title": owner.tr_key("prigozhin_fork_commander_title"),
			"terms": text, "status": "report", "cost": 0.0, "risk": 0})
		game.toast(text)
	if handled == 0:
		game.toast(owner.tr_key("prigozhin_fork_commander_no_reply"))
