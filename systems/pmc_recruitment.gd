extends RefCounted

const Mandates = preload("res://mods/prigozhin_fork/systems/pmc_mandates.gd")
const Sources = preload("res://mods/prigozhin_fork/systems/pmc_recruit_sources.gd")
const Airlift = preload("res://mods/prigozhin_fork/systems/pmc_airlift.gd")

# Recruitment is finalized at a safe main-thread boundary after time advances.
# The source country supplies a manpower ceiling; the mod has a finite market.
static func reserve_snapshot(owner, game: PaxGame, target_id: int = 0, expected_province: int = 0) -> Dictionary:
	return Sources.snapshot(owner, game, target_id, expected_province)

# Admission reserves capacity, not money; native hiring charges at formation.
static func reserve(owner, game: PaxGame, unit_name: String, count: int, duration: int, target_id: int = 0, native_order_id: int = 0) -> Dictionary:
	if not owner or not game or owner._last_game != game or target_id < 0 or unit_name.strip_edges().is_empty() or count <= 0 or count > 5000 or duration <= 0 or duration > 3650 or unit_name.strip_edges().length() > 80:
		return {"ok": false, "reason": "invalid"}
	var state: Dictionary = reserve_snapshot(owner, game, target_id)
	if not bool(state.get("ok", false)):
		return {"ok": false, "reason": str(state.get("reason", "unavailable"))}
	if native_order_id > 0:
		var confirmed: bool = false
		for order in game.main.model.orders:
			if order is Dictionary and int(order.get("id", 0)) == native_order_id and str(order.get("status", "")) == "queued" and order.has("prigozhin_fork_recruit_proposal"):
				confirmed = true
				break
		if not confirmed:
			return {"ok": false, "reason": "unavailable"}
	if game.main.rewind_state.rewinding and (native_order_id <= 0 or not game.main.rewind_state.waiting_estimates):
		return {"ok": false, "reason": "rewinding"}
	var name_clean: String = unit_name.strip_edges()
	if target_id == 0 and Airlift.name_in_transit(owner, game.country(), name_clean):
		return {"ok": false, "reason": "duplicate"}
	var target: Dictionary = {}
	if target_id > 0:
		target = game.main.model.armies.unit(target_id)
		if not valid_target(target, game.country()) or int(target.get("province", 0)) <= 0 or str(target.get("body", "")) != "":
			return {"ok": false, "reason": "target"}
		var target_road = target.get("road", [])
		if not (target_road is Array) or not target_road.is_empty() or not game.main.model.armies.battle_with_unit(target_id).is_empty():
			return {"ok": false, "reason": "target_not_ready"}
		name_clean = str(target.get("name", "")).strip_edges()
	var waiting: int = Sources.reserved(owner, game, str(state["source_country"]), 0, native_order_id)
	for existing in owner._pmc_recruitment:
		if not (existing is Dictionary):
			continue
		if str(existing.get("status", "")) not in ["pending", "blocked", "executing", "review"]:
			continue
		if str(existing.get("side", "")) == str(state["side"]):
			if (target_id == 0 and str(existing.get("name", "")).to_lower() == name_clean.to_lower()) or (target_id > 0 and int(existing.get("target_id", 0)) == target_id):
				return {"ok": false, "reason": "duplicate"}
	var service = game.main.model.armies if game.main.model else null
	if not service:
		return {"ok": false, "reason": "unavailable"}
	for unit in service.units:
		if target_id == 0 and unit is Dictionary and str(unit.get("whose", "")) == str(state["side"]) and str(unit.get("name", "")).to_lower() == name_clean.to_lower():
			return {"ok": false, "reason": "duplicate"}
	for legacy in owner._custom_wagner_detachments:
		if target_id == 0 and legacy is Dictionary and str(legacy.get("name", "")).strip_edges().to_lower() == name_clean.to_lower():
			return {"ok": false, "reason": "legacy"}
	for order in game.main.model.orders:
		if not (order is Dictionary) or str(order.get("status", "")) not in ["being_weighed", "awaits_ok", "queued", "under_way"]:
			continue
		if native_order_id > 0 and int(order.get("id", 0)) == native_order_id:
			continue
		var place = order.get("place", {})
		if not (place is Dictionary) or not bool(place.get("prigozhin_fork_recruit_request", false)) or str(place.get("recruit_side", "")) != str(state["side"]):
			continue
		if str(place.get("recruit_name", "")).strip_edges().to_lower() == name_clean.to_lower():
			return {"ok": false, "reason": "duplicate"}
	var available: int = maxi(0, int(state["reserve"]) - waiting)
	if count > available:
		return {"ok": false, "reason": "reserve", "available": available}
	var next_id: int = 1
	for previous in owner._pmc_recruitment:
		if previous is Dictionary:
			next_id = maxi(next_id, int(previous.get("id", 0)) + 1)
	var record: Dictionary = {"id": next_id, "name": name_clean, "side": str(state["side"]), "requested": count,
		"start_day": game.day(), "due_day": game.day() + duration, "status": "pending"}
	record["source_country"] = str(state["source_country"])
	record["source_province"] = int(state["source_province"])
	if native_order_id > 0:
		record["native_order_id"] = native_order_id
		record["native_due"] = false
	if target_id > 0:
		record["target_id"] = target_id
		record["source_province"] = int(target["province"])
		record["mode"] = "reinforce"
		for mandate in owner._pmc_mandates:
			if mandate is Dictionary and str(mandate.get("side", "")) == str(state["side"]) and str(mandate.get("status", "")) == "active" and game.day() < int(mandate.get("end_day", 0)) and Mandates.has_id(mandate.get("unit_ids", []), target_id):
				record["mandate_id"] = int(mandate.get("id", 0))
				break
	owner._pmc_recruitment.append(record)
	return {"ok": true, "record": record}

# A reservation has not spent money; cancellation does not create a refund.
static func cancel(owner, game: PaxGame, record_id: int) -> bool:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or record_id <= 0 or not is_instance_valid(game.main) or game.main.rewind_state.rewinding:
		return false
	for entry in owner._pmc_recruitment:
		if entry is Dictionary and int(entry.get("id", 0)) == record_id:
			if str(entry.get("side", "")) != game.country() or str(entry.get("status", "")) not in ["pending", "blocked"]:
				return false
			entry["status"] = "cancelled"
			entry.erase("reason")
			if int(entry.get("native_order_id", 0)) > 0 and owner.has_method("_cancel_pmc_native_ticket"):
				owner._cancel_pmc_native_ticket(int(entry["native_order_id"]), record_id)
			return true
	return false

static func native_ticket_present(game: PaxGame, entry: Dictionary) -> bool:
	return Sources.native_ticket_present(game, entry)

# An interrupted native call must be inspected, not retried automatically.
static func recover_interrupted(records: Array) -> void:
	for entry in records:
		if entry is Dictionary and str(entry.get("status", "")) == "executing":
			entry["status"] = "review"
			entry["reason"] = "interrupted_native_hire"

# Due day is earliest readiness. Formation occurs at the actual end of a jump,
# never retroactively; native upkeep begins from actual unit creation.
static func complete_due(owner, game: PaxGame) -> void:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main):
		return
	var runtime: Node = game.main
	if not runtime.model or not runtime.model.armies or not runtime.player or not runtime.has_method("jobs"):
		return
	if str(runtime.player.player_role) not in ["person", "organization"]:
		return
	for entry in owner._pmc_recruitment:
		if not (entry is Dictionary):
			continue
		if str(entry.get("status", "")) not in ["pending", "blocked"]:
			continue
		if int(entry.get("native_order_id", 0)) > 0:
			if not native_ticket_present(game, entry):
				entry["status"] = "cancelled"
				entry["reason"] = "native_cancelled"
				continue
			if not bool(entry.get("native_due", false)):
				continue
		if not entry.has("start_day") or not entry.has("due_day") or int(entry["due_day"]) <= int(entry["start_day"]):
			entry["status"] = "review"
			entry["reason"] = "invalid_dates"
			continue
		if game.day() < int(entry["due_day"]):
			continue
		var target_id: int = int(entry.get("target_id", 0))
		if str(entry.get("source_country", "")).is_empty() or int(entry.get("source_province", 0)) <= 0:
			entry["status"] = "blocked"
			entry["reason"] = "source_required"
			continue
		var state: Dictionary = reserve_snapshot(owner, game, target_id, int(entry["source_province"]))
		if not bool(state.get("ok", false)) or str(entry.get("side", "")) != str(state.get("side", "")):
			entry["status"] = "blocked"
			entry["reason"] = str(state.get("reason", "source_unavailable"))
			continue
		if str(entry["source_country"]) != str(state["source_country"]):
			entry["status"] = "blocked"
			entry["reason"] = "source_changed"
			continue
		if Sources.already_accounted(owner, str(entry["source_country"]), int(entry.get("id", 0))) > 0:
			entry["status"] = "review"
			entry["reason"] = "source_already_processed"
			continue
		var requested: int = int(entry.get("requested", 0))
		var unit_name: String = str(entry.get("name", "")).strip_edges()
		if (target_id > 0 and str(entry.get("mode", "")) != "reinforce") or (str(entry.get("mode", "")) == "reinforce" and target_id <= 0):
			entry["status"] = "review"
			entry["reason"] = "invalid_target"
			continue
		var target: Dictionary = {}
		if str(entry.get("mode", "create")) == "reinforce":
			target = runtime.model.armies.unit(target_id)
			if target_id <= 0 or not valid_target(target, game.country()):
				entry["status"] = "blocked"
				entry["reason"] = "target"
				continue
			var road = target.get("road", [])
			if str(target.get("body", "")) != "" or int(target.get("province", 0)) != int(entry.get("source_province", 0)) or not (road is Array) or not road.is_empty() or not runtime.model.armies.battle_with_unit(target_id).is_empty():
				entry["status"] = "blocked"
				entry["reason"] = "target_not_ready"
				continue
		var available: int = maxi(0, int(state.get("reserve", 0)) - Sources.reserved(owner, game, str(state["source_country"]), int(entry.get("id", 0))))
		if requested <= 0 or requested > 5000 or unit_name.is_empty() or unit_name.length() > 80 or requested > available:
			entry["status"] = "blocked"
			entry["reason"] = "reserve"
			continue
		if int(entry.get("mandate_id", 0)) > 0:
			var authorized: bool = false
			for mandate in owner._pmc_mandates:
				if mandate is Dictionary and int(mandate.get("id", 0)) == int(entry["mandate_id"]) and str(mandate.get("side", "")) == game.country() and str(mandate.get("status", "")) == "active" and game.day() < int(mandate.get("end_day", 0)) and Mandates.has_id(mandate.get("unit_ids", []), target_id):
					authorized = true
					break
			if not authorized:
				entry["status"] = "blocked"
				entry["reason"] = "mandate_inactive"
				continue
		var duplicate: bool = false
		if target_id == 0 and Airlift.name_in_transit(owner, game.country(), unit_name):
			duplicate = true
		for unit in runtime.model.armies.units:
			if target_id == 0 and unit is Dictionary and str(unit.get("whose", "")) == game.country() and str(unit.get("name", "")).to_lower() == unit_name.to_lower():
				duplicate = true
				break
		if duplicate:
			entry["status"] = "blocked"
			entry["reason"] = "duplicate"
			continue
		if game.money() <= 0.0:
			entry["status"] = "blocked"
			entry["reason"] = "funds"
			continue
		# Persisting an interrupted in-flight call must never trigger another charge.
		entry["status"] = "executing"
		entry["native_uncertain"] = true
		var before_money: float = game.money()
		var before_humans: int = int(target.get("humans", 0))
		var action: String = "reinforce" if not target.is_empty() else "create"
		var request: Dictionary = {"action": action, "name": unit_name,
			"make_up": {"fighters": requested}, "machinery": {}}
		if not str(entry.get("description", "")).is_empty():
			request["description"] = str(entry["description"])
		var hired = runtime.jobs().hire(request, action, target, 1.0)
		if not (hired is Dictionary) or hired.is_empty():
			if game.money() < before_money:
				entry["status"] = "review"
				entry["reason"] = "native_charge_without_unit"
			else:
				entry["status"] = "blocked"
				entry["reason"] = "native_hire_rejected"
				entry["native_uncertain"] = false
			continue
		var actual: int = int(hired.get("humans", 0)) - before_humans
		if actual <= 0 or actual > requested or int(hired.get("id", 0)) <= 0 or (target_id > 0 and int(hired.get("id", 0)) != target_id) or int(hired.get("province", 0)) != int(entry["source_province"]) or str(hired.get("body", "")) != "" or not runtime.model.armies.units.has(hired) or not bool(hired.get("our", false)) or str(hired.get("whose", "")) != game.country():
			entry["status"] = "review"
			entry["reason"] = "unexpected_native_result"
			continue
		entry["native_note"] = str(hired.get("_said", ""))
		hired.erase("_said")
		hired["prigozhin_fork_pmc"] = true
		hired["prigozhin_fork_last_reinforcement_id" if target_id > 0 else "prigozhin_fork_recruitment_id"] = int(entry.get("id", 0))
		entry["hired"] = actual
		entry["unit_id"] = int(hired.get("id", 0))
		entry["spent"] = maxf(0.0, before_money - game.money())
		entry["completed_day"] = game.day()
		if not Sources.consume(owner, entry, actual):
			entry["status"] = "review"
			entry["reason"] = "source_commit_failed"
			continue
		entry["native_uncertain"] = false
		entry["status"] = "complete" if actual >= requested else "partial"
		entry.erase("reason")
		if runtime.has_method("show_queue"):
			runtime.show_queue().map_changed()

static func valid_target(unit: Dictionary, side: String) -> bool:
	if unit.is_empty() or not bool(unit.get("our", false)) or str(unit.get("whose", "")) != side or bool(unit.get("self", false)) or float(unit.get("humans", 0.0)) < 1.0:
		return false
	return bool(unit.get("prigozhin_fork_pmc", false)) or str(unit.get("name", "")).to_lower().contains("вагнер")

# Manual reconciliation never calls hire or reconstructs spending from the
# treasury. The player explicitly selects an existing, controlled PMC unit.
static func reconcile(owner, game: PaxGame, record_id: int, unit_id: int) -> bool:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main):
		return false
	if game.main.rewind_state.rewinding or not game.main.model or not game.main.model.armies:
		return false
	var record: Dictionary = {}
	for entry in owner._pmc_recruitment:
		if entry is Dictionary and int(entry.get("id", 0)) == record_id and str(entry.get("side", "")) == game.country() and str(entry.get("status", "")) == "review":
			record = entry
			break
	if record.is_empty():
		return false
	var target_id: int = int(record.get("target_id", 0))
	if target_id > 0 and target_id != unit_id:
		return false
	var unit: Dictionary = game.main.model.armies.unit(unit_id)
	if unit.is_empty() or not bool(unit.get("our", false)) or str(unit.get("whose", "")) != game.country() or bool(unit.get("self", false)):
		return false
	if not bool(unit.get("prigozhin_fork_pmc", false)) and not str(unit.get("name", "")).to_lower().contains("вагнер"):
		return false
	var linked_request: int = int(unit.get("prigozhin_fork_recruitment_id", 0))
	if target_id == 0 and linked_request > 0 and linked_request != record_id:
		return false
	for other in owner._pmc_recruitment:
		if target_id == 0 and other is Dictionary and int(other.get("id", 0)) != record_id and int(other.get("unit_id", 0)) == unit_id and str(other.get("side", "")) == game.country():
			return false
	if not Sources.settle_uncertain(owner, record):
		return false
	record["unit_id"] = unit_id
	record["observed_humans"] = int(unit.get("humans", 0))
	record["reconciled_day"] = game.day()
	record["status"] = "reconciled"
	record["accounting_known"] = record.has("spent")
	unit["prigozhin_fork_last_reinforcement_id" if target_id > 0 else "prigozhin_fork_recruitment_id"] = record_id
	unit["prigozhin_fork_pmc"] = true
	return true

# Close an uncertain record explicitly; preserve evidence and never refund or
# repeat a charge whose actual outcome is unknown.
static func archive_review(owner, game: PaxGame, record_id: int) -> bool:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or game.main.rewind_state.rewinding:
		return false
	for entry in owner._pmc_recruitment:
		if entry is Dictionary and int(entry.get("id", 0)) == record_id and str(entry.get("side", "")) == game.country() and str(entry.get("status", "")) == "review":
			if not Sources.settle_uncertain(owner, entry):
				return false
			entry["status"] = "archived"
			entry["archived_day"] = game.day()
			return true
	return false
