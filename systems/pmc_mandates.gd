extends RefCounted

# Godot JSON saves may restore numeric IDs as floats.
static func has_id(values, expected: int) -> bool:
	if not (values is Array):
		return false
	for value in values:
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == float(expected):
			return true
	return false

# Internal mandate only. This is not a signed agreement with an external party.
# No money, diplomacy or unit position is changed by this module.
static func create(owner, game: PaxGame, unit_ids: Array, provinces: Array, task: String, budget: float, duration: int) -> Dictionary:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main):
		return {"ok": false, "reason": "unavailable"}
	if not is_finite(budget) or budget < 0.0 or duration <= 0 or task.strip_edges().is_empty():
		return {"ok": false, "reason": "invalid_terms"}
	if unit_ids.is_empty() or provinces.is_empty() or not game.main.model or not game.main.model.armies:
		return {"ok": false, "reason": "missing_units_or_territory"}
	var side: String = game.country()
	var army = game.main.model.armies
	if side.is_empty():
		return {"ok": false, "reason": "unavailable"}
	var checked_units: Array = []
	for raw_id in unit_ids:
		if typeof(raw_id) not in [TYPE_INT, TYPE_FLOAT]:
			return {"ok": false, "reason": "invalid_unit"}
		var unit_id: int = int(raw_id)
		if unit_id <= 0 or checked_units.has(unit_id):
			return {"ok": false, "reason": "invalid_unit"}
		var unit: Dictionary = army.unit(unit_id)
		if unit.is_empty() or not army.units.has(unit) or not bool(unit.get("our", false)) or str(unit.get("whose", "")) != side:
			return {"ok": false, "reason": "invalid_unit"}
		for old in owner._pmc_mandates:
			if not (old is Dictionary):
				continue
			var old_units = old.get("unit_ids", [])
			if old_units is Array and str(old.get("status", "")) == "active" and int(old.get("end_day", 0)) > game.day() and str(old.get("side", "")) == side and has_id(old_units, unit_id):
				return {"ok": false, "reason": "unit_already_assigned"}
		checked_units.append(unit_id)
	var total: int = game.province_count(game.home_body())
	var checked_provinces: Array = []
	for raw_province in provinces:
		if typeof(raw_province) not in [TYPE_INT, TYPE_FLOAT]:
			return {"ok": false, "reason": "invalid_province"}
		var province: int = int(raw_province)
		if province <= 0 or province > total or checked_provinces.has(province):
			return {"ok": false, "reason": "invalid_province"}
		checked_provinces.append(province)
	var next_id: int = 1
	for old in owner._pmc_mandates:
		if old is Dictionary:
			next_id = maxi(next_id, int(old.get("id", 0)) + 1)
	var record: Dictionary = {"id": next_id, "side": side, "unit_ids": checked_units,
		"provinces": checked_provinces, "task": task.strip_edges(), "budget_limit": budget,
		"spent_confirmed": 0.0, "spending_known": false, "start_day": game.day(), "end_day": game.day() + duration, "status": "active"}
	owner._pmc_mandates.append(record)
	return {"ok": true, "id": next_id}

# Evaluate proposed action without executing it or treating its estimate as paid.
static func evaluate(owner, game: PaxGame, mandate_id: int, unit_id: int, province: int, estimate: float) -> Dictionary:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main):
		return {"ok": false, "reason": "unavailable"}
	if not is_finite(estimate) or estimate < 0.0:
		return {"ok": false, "reason": "invalid_estimate"}
	for record in owner._pmc_mandates:
		if not (record is Dictionary) or int(record.get("id", 0)) != mandate_id:
			continue
		if str(record.get("side", "")) != game.country() or str(record.get("status", "")) != "active" or game.day() >= int(record.get("end_day", 0)):
			return {"ok": false, "reason": "inactive"}
		var assigned = record.get("unit_ids", [])
		var territory = record.get("provinces", [])
		if not (assigned is Array) or not (territory is Array):
			return {"ok": false, "reason": "invalid_record"}
		if not has_id(assigned, unit_id):
			return {"ok": false, "reason": "unit_not_assigned"}
		if not game.main.model or not game.main.model.armies:
			return {"ok": false, "reason": "unavailable"}
		var current: Dictionary = game.main.model.armies.unit(unit_id)
		if current.is_empty() or not game.main.model.armies.units.has(current) or not bool(current.get("our", false)) or str(current.get("whose", "")) != game.country():
			return {"ok": false, "reason": "unit_unavailable"}
		var reasons: Array = []
		if not has_id(territory, province):
			reasons.append("outside_territory")
		var limit: float = float(record.get("budget_limit", 0.0))
		var known: bool = bool(record.get("spending_known", false))
		if not is_finite(limit) or limit < 0.0:
			return {"ok": false, "reason": "invalid_record"}
		if known:
			var spent: float = float(record.get("spent_confirmed", 0.0))
			if not is_finite(spent) or spent < 0.0:
				return {"ok": false, "reason": "invalid_record"}
			if spent + estimate > limit:
				reasons.append("over_budget")
		elif estimate + maxf(0.0, float(record.get("confirmed_direct_cost", 0.0))) > limit:
			reasons.append("over_budget")
		else:
			reasons.append("spending_unknown")
		return {"ok": true, "within": reasons.is_empty(), "spending_known": known, "reasons": reasons}
	return {"ok": false, "reason": "not_found"}

# Update only the internal record; expiry does not move units or terminate an
# external contract. Safe to call after any length of time advance.
static func expire(owner, game: PaxGame) -> Array:
	var expired: Array = []
	if not owner or not game or owner._last_game != game or Pax.world_busy():
		return expired
	for record in owner._pmc_mandates:
		if not (record is Dictionary) or str(record.get("status", "")) != "active":
			continue
		if str(record.get("side", "")) != game.country():
			continue
		if not record.has("start_day") or not record.has("end_day") or int(record["end_day"]) <= int(record["start_day"]):
			record["status"] = "review"
			continue
		if game.day() >= int(record["end_day"]):
			record["status"] = "expired"
			expired.append(int(record.get("id", 0)))
	return expired

# Closing a mandate never refunds or debits money; it is not contract settlement.
static func close(owner, game: PaxGame, mandate_id: int) -> bool:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or mandate_id <= 0:
		return false
	for record in owner._pmc_mandates:
		if not (record is Dictionary) or int(record.get("id", 0)) != mandate_id:
			continue
		if str(record.get("side", "")) != game.country() or str(record.get("status", "")) != "active":
			return false
		record["status"] = "closed"
		record["closed_day"] = game.day()
		return true
	return false

# Movement authority is an explicit, narrow delegation. It does not authorize
# purchases or claim that total mission spending has been measured.
static func set_movement_authority(owner, game: PaxGame, mandate_id: int, enabled: bool, acknowledge_review: bool = false) -> bool:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or game.main.rewind_state.rewinding:
		return false
	for record in owner._pmc_mandates:
		if not (record is Dictionary) or int(record.get("id", 0)) != mandate_id:
			continue
		if str(record.get("side", "")) != game.country() or str(record.get("status", "")) != "active" or game.day() >= int(record.get("end_day", 0)):
			return false
		record["movement_authority"] = enabled
		record["commander_revision"] = int(record.get("commander_revision", 0)) + 1
		if acknowledge_review:
			record["commander_review_required"] = false
			record["commander_review_reasons"] = []
			record["commander_review_day"] = game.day()
			record.erase("commander_requested_day")
		return true
	return false

static func require_review(record: Dictionary, reason: String) -> void:
	record["commander_review_required"] = true
	var previous = record.get("commander_review_reasons", [])
	var reasons: Array = previous if previous is Array else []
	if not reasons.has(reason):
		reasons.append(reason)
	record["commander_review_reasons"] = reasons

# Only completed, explicitly linked native reinforcement receipts are summed.
# This is a confirmed subtotal, not a reconstructed total mission budget.
static func record_costs(owner, game: PaxGame) -> void:
	if not owner or not game or owner._last_game != game or Pax.world_busy():
		return
	for application in owner._pmc_recruitment:
		if not (application is Dictionary) or str(application.get("status", "")) not in ["complete", "partial"] or str(application.get("mode", "")) != "reinforce" or str(application.get("side", "")) != game.country() or int(application.get("mandate_id", 0)) <= 0:
			continue
		var cost = application.get("spent")
		if typeof(cost) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(cost)) or float(cost) < 0.0:
			continue
		for record in owner._pmc_mandates:
			if not (record is Dictionary) or int(record.get("id", 0)) != int(application["mandate_id"]) or str(record.get("side", "")) != game.country():
				continue
			var receipts_value = record.get("confirmed_receipts", [])
			var receipts: Array = receipts_value if receipts_value is Array else []
			var receipt_id: int = int(application.get("id", 0))
			var exists: bool = false
			for receipt in receipts:
				if receipt is Dictionary and int(receipt.get("recruitment_id", 0)) == receipt_id:
					exists = true
					break
			if exists or receipt_id <= 0:
				break
			receipts.append({"recruitment_id": receipt_id, "unit_id": int(application.get("unit_id", 0)),
				"amount": float(cost), "hired": int(application.get("hired", 0)), "day": int(application.get("completed_day", 0))})
			record["confirmed_receipts"] = receipts
			var subtotal: float = 0.0
			for receipt in receipts:
				if receipt is Dictionary:
					subtotal += maxf(0.0, float(receipt.get("amount", 0.0)))
			record["confirmed_direct_cost"] = subtotal
			if subtotal > float(record.get("budget_limit", 0.0)):
				require_review(record, "budget")
				game.toast(owner.tr_key("prigozhin_fork_mandate_cost_overrun") % [int(record["id"]), str(subtotal), str(record.get("budget_limit", 0.0))])
			break

# Observe only the final world snapshot; do not infer who caused movement.
static func observe(owner, game: PaxGame) -> Array:
	var events: Array = []
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main):
		return events
	var runtime: Node = game.main
	if not runtime.model or not runtime.model.armies:
		return events
	var army = runtime.model.armies
	var side: String = game.country()
	if side.is_empty():
		return events
	for record in owner._pmc_mandates:
		if not (record is Dictionary) or str(record.get("status", "")) != "active" or str(record.get("side", "")) != side:
			continue
		if game.day() >= int(record.get("end_day", 0)):
			continue
		var assigned = record.get("unit_ids", [])
		var territory = record.get("provinces", [])
		if not (assigned is Array) or not (territory is Array):
			continue
		var previous = record.get("observations", {})
		if not (previous is Dictionary):
			previous = {}
		record["observations"] = previous
		for raw_id in assigned:
			if typeof(raw_id) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_id)):
				continue
			var unit_id: int = int(raw_id)
			if unit_id <= 0 or float(unit_id) != float(raw_id):
				continue
			var current: Dictionary = army.unit(unit_id)
			var state: String = "unavailable"
			var province: int = 0
			var unit_name: String = ""
			if not current.is_empty() and army.units.has(current) and bool(current.get("our", false)) and str(current.get("whose", "")) == side:
				unit_name = str(current.get("name", ""))
				province = int(current.get("province", 0))
				if province > 0 and province <= game.province_count(game.home_body()):
					state = "inside" if has_id(territory, province) else "outside"
			var key: String = str(unit_id)
			var was: String = str(previous.get(key, ""))
			if state != was:
				if state == "outside" or state == "unavailable" or (state == "inside" and was == "outside"):
					events.append({"kind": state, "unit_id": unit_id, "name": unit_name,
						"province": province, "mandate_id": int(record.get("id", 0)), "day": game.day()})
				previous[key] = state
	return events
