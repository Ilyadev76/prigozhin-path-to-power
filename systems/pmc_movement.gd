extends RefCounted

# Use the map's native marching pipeline. Never assign a province or turn
# infantry into aircraft. The engine owns travel, provisions, battles and loss.
const ACTIVE: Array = ["submitted", "marching", "engaged"]

static func context(owner, game: PaxGame, unit_id: int, require_idle: bool = true) -> Dictionary:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main):
		return {"ok": false, "reason": "unavailable"}
	var runtime: Node = game.main
	if not runtime.model or not runtime.model.armies or not runtime.has_method("army_map_view"):
		return {"ok": false, "reason": "unavailable"}
	if not runtime.model.earth_provinces or not runtime.model.earth_provinces.exists():
		return {"ok": false, "reason": "unavailable"}
	if require_idle and runtime.rewind_state.rewinding:
		return {"ok": false, "reason": "unavailable"}
	var army = runtime.model.armies
	var unit: Dictionary = army.unit(unit_id)
	if unit.is_empty() or not bool(unit.get("our", false)) or str(unit.get("whose", "")) != game.country() or bool(unit.get("self", false)):
		return {"ok": false, "reason": "missing"}
	if not bool(unit.get("prigozhin_fork_pmc", false)) and not str(unit.get("name", "")).to_lower().contains("вагнер"):
		return {"ok": false, "reason": "missing"}
	if str(unit.get("body", "")) != "":
		return {"ok": false, "reason": "unavailable"}
	if float(unit.get("humans", 0.0)) < 1.0:
		return {"ok": false, "reason": "missing"}
	return {"ok": true, "unit": unit, "army": army}

static func active_record(owner, side: String, unit_id: int) -> Dictionary:
	for entry in owner._pmc_movements:
		if entry is Dictionary and str(entry.get("side", "")) == side and int(entry.get("unit_id", 0)) == unit_id and str(entry.get("status", "")) in ACTIVE:
			return entry
	return {}

# Route estimates use a detached dictionary; preview does not change the unit.
static func preview(owner, game: PaxGame, unit_id: int, destination: int) -> Dictionary:
	var state: Dictionary = context(owner, game, unit_id)
	if not bool(state.get("ok", false)):
		return state
	var unit: Dictionary = state["unit"]
	var army = state["army"]
	if not active_record(owner, game.country(), unit_id).is_empty():
		return {"ok": false, "reason": "active"}
	for operation in game.main.model.operation_list:
		if not (operation is Dictionary):
			continue
		var ids = operation.get("ids", [])
		if ids is Array:
			for id in ids:
				if int(id) == unit_id:
					return {"ok": false, "reason": "active"}
	if not str(unit.get("group_id", "")).is_empty():
		return {"ok": false, "reason": "grouped"}
	if not army.battle_with_unit(unit_id).is_empty():
		return {"ok": false, "reason": "battle"}
	var old_road = unit.get("road", [])
	if not (old_road is Array) or not old_road.is_empty():
		return {"ok": false, "reason": "active"}
	if destination <= 0 or destination > game.province_count(game.home_body()) or game.province(game.home_body(), destination).is_empty():
		return {"ok": false, "reason": "destination"}
	var source: int = int(unit.get("province", 0))
	if source <= 0:
		return {"ok": false, "reason": "missing"}
	if destination == source:
		return {"ok": false, "reason": "already_here"}
	var road: Array = army.path_for(unit, destination)
	if road.is_empty() or int(road[-1]) != destination:
		return {"ok": false, "reason": "no_route"}
	var crossings: int = 0
	var previous: int = source
	for step in road:
		var sector: int = int(step)
		if not army.can_pass(game.country(), sector, unit):
			return {"ok": false, "reason": "no_route"}
		# This control orders a transfer, not an assault through hostile territory.
		var land_owner: String = str(game.main.model.earth_provinces.whose(sector))
		if army.enemies(game.country(), land_owner) or not army.enemies_in(game.country(), sector).is_empty():
			return {"ok": false, "reason": "hostile"}
		if army.is_by_sea(previous, sector):
			crossings += 1
		previous = sector
	var probe: Dictionary = unit.duplicate(true)
	probe["road"] = road.duplicate()
	var days: int = maxi(1, int(army.route_days(probe)))
	return {"ok": true, "unit_id": unit_id, "source": source, "destination": destination,
		"road": road.duplicate(), "days": days, "crossings": crossings, "humans": int(unit.get("humans", 0))}

# Re-evaluate at confirmation: permissions, position and route may have changed.
static func begin(owner, game: PaxGame, expected: Dictionary) -> Dictionary:
	var unit_id: int = int(expected.get("unit_id", 0))
	var fresh: Dictionary = preview(owner, game, unit_id, int(expected.get("destination", 0)))
	if not bool(fresh.get("ok", false)):
		return fresh
	if int(fresh["source"]) != int(expected.get("source", 0)) or int(fresh["humans"]) != int(expected.get("humans", -1)) or int(fresh["days"]) != int(expected.get("days", -1)) or not same_route(fresh["road"], expected.get("road", [])):
		return {"ok": false, "reason": "changed"}
	var map_view = game.main.army_map_view()
	if not map_view or not map_view.has_method("move_units"):
		return {"ok": false, "reason": "unavailable"}
	var unit: Dictionary = game.main.model.armies.unit(unit_id)
	var next_id: int = 1
	for old in owner._pmc_movements:
		if old is Dictionary:
			next_id = maxi(next_id, int(old.get("id", 0)) + 1)
	var record: Dictionary = {"id": next_id, "unit_id": unit_id, "name": str(unit.get("name", "")),
		"side": game.country(), "source": fresh["source"], "destination": fresh["destination"],
		"road": fresh["road"].duplicate(), "start_day": game.day(), "estimated_days": fresh["days"],
		"start_humans": int(unit.get("humans", 0)), "start_losses": float(unit.get("losses", 0.0)),
		"status": "submitted"}
	owner._pmc_movements.append(record)
	# This also creates the native march order in the Orders panel. In a network
	# game it may only send to the host; do not label that as a completed march.
	map_view.move_units([unit_id], int(fresh["destination"]))
	if same_route(unit.get("road", []), fresh["road"]):
		record["status"] = "marching"
	return {"ok": true, "record": record}

static func same_route(left, right) -> bool:
	if not (left is Array) or not (right is Array) or left.size() != right.size():
		return false
	for i in range(left.size()):
		if int(left[i]) != int(right[i]):
			return false
	return true

# A native march consumes its route from the front; another destination or
# a different route is not silently claimed as this operation's progress.
static func is_remaining(road, original) -> bool:
	if not (road is Array) or not (original is Array) or road.is_empty() or road.size() > original.size():
		return false
	return same_route(road, original.slice(original.size() - road.size()))

static func observe(owner, game: PaxGame) -> void:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or not game.main.model or not game.main.model.armies:
		return
	var army = game.main.model.armies
	for entry in owner._pmc_movements:
		if not (entry is Dictionary) or str(entry.get("side", "")) != game.country() or str(entry.get("status", "")) not in ACTIVE:
			continue
		var before: String = str(entry["status"])
		var unit: Dictionary = army.unit(int(entry.get("unit_id", 0)))
		if unit.is_empty():
			entry["status"] = "missing"
		elif not bool(unit.get("our", false)) or str(unit.get("whose", "")) != game.country():
			entry["status"] = "ownership_changed"
		else:
			entry["observed_day"] = game.day()
			entry["province"] = int(unit.get("province", 0))
			entry["humans"] = int(unit.get("humans", 0))
			entry["losses_delta"] = maxf(0.0, float(unit.get("losses", 0.0)) - float(entry.get("start_losses", 0.0)))
			var road = unit.get("road", [])
			if not str(unit.get("group_id", "")).is_empty() or str(unit.get("body", "")) != "":
				entry["status"] = "overridden"
			elif not army.battle_with_unit(int(entry["unit_id"])).is_empty():
				entry["status"] = "engaged"
			elif road is Array and not road.is_empty() and not is_remaining(road, entry.get("road", [])):
				entry["status"] = "overridden"
			elif int(unit.get("province", 0)) == int(entry.get("destination", 0)):
				entry["status"] = "arrived"
			elif is_remaining(road, entry.get("road", [])):
				entry["status"] = "marching"
			elif before != "submitted":
				entry["status"] = "stopped"
			elif game.day() > int(entry.get("start_day", game.day())):
				entry["status"] = "unconfirmed"
		if str(entry["status"]) != before:
			publish(owner, game, entry)

# Stop only the exact remaining route belonging to this record. Never cancel
# an unacknowledged network request or a newer native order.
static func stop(owner, game: PaxGame, unit_id: int) -> bool:
	var state: Dictionary = context(owner, game, unit_id)
	if not bool(state.get("ok", false)):
		return false
	var entry: Dictionary = active_record(owner, game.country(), unit_id)
	if entry.is_empty() or str(entry.get("status", "")) == "submitted":
		return false
	var unit: Dictionary = state["unit"]
	if not str(unit.get("group_id", "")).is_empty() or not is_remaining(unit.get("road", []), entry.get("road", [])):
		return false
	game.main.army_map_view().move_units([unit_id], int(unit["province"]))
	if not (unit.get("road", []) as Array).is_empty():
		return false
	entry["status"] = "cancelled"
	publish(owner, game, entry)
	return true

static func publish(owner, game: PaxGame, entry: Dictionary) -> void:
	var status: String = str(entry.get("status", "submitted"))
	var text: String = owner.tr_key("prigozhin_fork_movement_report") % [str(entry.get("name", "")), owner.tr_key("prigozhin_fork_movement_" + status), int(entry.get("province", entry.get("source", 0))), int(entry.get("destination", 0))]
	owner._deals.append({"id": "pmc_move_%d_%d_%s" % [int(entry.get("id", 0)), game.day(), status],
		"partner": owner.tr_key("prigozhin_fork_ai_hq"), "title": owner.tr_key("prigozhin_fork_movement_title"),
		"terms": text, "status": "report", "cost": 0.0, "risk": 0})
	game.toast(text)
