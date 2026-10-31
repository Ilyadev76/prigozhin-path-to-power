extends RefCounted

const Commanders = preload("res://mods/prigozhin_fork/systems/pmc_commanders.gd")
const Mandates = preload("res://mods/prigozhin_fork/systems/pmc_mandates.gd")

# Hired civilian transport, not ownership of Russian military aircraft.
# Like the native ExpeditionSystem passenger flow, real unit dictionaries leave
# the ground roster during transport and return with their original IDs.
const ACTIVE: Array = ["loading", "in_flight", "returning", "review"]

static func rules(owner) -> Dictionary:
	var data = owner.load_json("data/pmc_airlift_rules.json")
	if not (data is Dictionary) or not (data.get("cargo_aircraft_per_item") is Dictionary):
		return {}
	for key in ["loading_days", "km_per_day", "personnel_per_aircraft", "max_concurrent_aircraft", "fee_per_aircraft", "return_reserve_ratio"]:
		var value = data.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return {}
	if float(data["km_per_day"]) <= 0.0 or int(data["personnel_per_aircraft"]) <= 0 or int(data["max_concurrent_aircraft"]) <= 0 or float(data["fee_per_aircraft"]) <= 0.0:
		return {}
	for key in ["loading_days", "personnel_per_aircraft", "max_concurrent_aircraft"]:
		if float(data[key]) != float(int(data[key])):
			return {}
	for value in data["cargo_aircraft_per_item"].values():
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return {}
	return data

static func json_unit(value, depth: int = 0) -> bool:
	if depth > 20:
		return false
	if value is Dictionary:
		for key in value:
			if not (key is String) or not json_unit(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for item in value:
			if not json_unit(item, depth + 1):
				return false
		return true
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return is_finite(float(value))
	return value == null or typeof(value) in [TYPE_BOOL, TYPE_STRING]

static func allowed(army, side: String, province: int, unit: Dictionary) -> bool:
	if province <= 0 or not army.can_pass(side, province, unit):
		return false
	var country: String = str(army.model.earth_provinces.whose(province))
	return not army.enemies(side, country) and army.enemies_in(side, province).is_empty()

static func preview(owner, game: PaxGame, ids: Array, destination: int) -> Dictionary:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or not game.main.model or not game.main.model.armies or game.main.rewind_state.rewinding:
		return {"ok": false, "reason": "unavailable"}
	if not game.main.player or str(game.main.player.player_role) not in ["person", "organization"]:
		return {"ok": false, "reason": "role"}
	var treasury = game.main.treasury()
	if not treasury or not treasury.has_method("prigozhin_fork_airlift_upkeep_version") or int(treasury.prigozhin_fork_airlift_upkeep_version()) != 1:
		return {"ok": false, "reason": "reload"}
	var budget: Dictionary = treasury.breakdown(game.home_body())
	if not bool(budget.get("exists", false)):
		return {"ok": false, "reason": "unavailable"}
	var config: Dictionary = rules(owner)
	if config.is_empty() or ids.is_empty() or destination <= 0 or destination > game.province_count(game.home_body()):
		return {"ok": false, "reason": "selection"}
	var army = game.main.model.armies
	var checked: Array = []
	var source: int = 0
	var people: float = 0.0
	var cargo_aircraft: int = 0
	for raw_id in ids:
		if typeof(raw_id) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_id)) or float(raw_id) != float(int(raw_id)):
			return {"ok": false, "reason": "selection"}
		var id: int = int(raw_id)
		var unit: Dictionary = army.unit(id)
		if id <= 0 or checked.has(id) or unit.is_empty() or not army.units.has(unit) or not bool(unit.get("our", false)) or str(unit.get("whose", "")) != game.country() or bool(unit.get("self", false)) or str(unit.get("body", "")) != "" or float(unit.get("humans", 0.0)) < 1.0:
			return {"ok": false, "reason": "selection"}
		if not bool(unit.get("prigozhin_fork_pmc", false)) and not str(unit.get("name", "")).to_lower().contains("вагнер"):
			return {"ok": false, "reason": "selection"}
		var branch: Dictionary = army._kind(unit)
		if str(branch.get("env", "land")) != "land" or (unit.has("ships") and not unit["ships"].is_empty()):
			return {"ok": false, "reason": "cargo"}
		var road = unit.get("road", [])
		if not (road is Array) or not road.is_empty() or not army.battle_with_unit(id).is_empty() or not str(unit.get("group_id", "")).is_empty() or not json_unit(unit):
			return {"ok": false, "reason": "busy"}
		if Commanders.has_player_order(game, id, owner):
			return {"ok": false, "reason": "busy"}
		for operation in game.main.model.operation_list:
			if operation is Dictionary and Mandates.has_id(operation.get("ids", []), id):
				return {"ok": false, "reason": "busy"}
		for application in owner._pmc_recruitment:
			if application is Dictionary and int(application.get("target_id", 0)) == id and str(application.get("status", "")) in ["pending", "blocked", "executing", "review"]:
				return {"ok": false, "reason": "busy"}
		if source == 0:
			source = int(unit.get("province", 0))
		if source <= 0 or int(unit.get("province", 0)) != source or destination == source:
			return {"ok": false, "reason": "selection"}
		if not allowed(army, game.country(), source, unit) or not allowed(army, game.country(), destination, unit):
			return {"ok": false, "reason": "passage"}
		var machinery = unit.get("machinery", {})
		if not (machinery is Dictionary):
			return {"ok": false, "reason": "cargo"}
		for key in machinery:
			var amount = machinery[key]
			if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)) or float(amount) < 0.0:
				return {"ok": false, "reason": "cargo"}
			if float(amount) <= 0.0:
				continue
			if not config["cargo_aircraft_per_item"].has(str(key)):
				return {"ok": false, "reason": "cargo"}
			cargo_aircraft += int(ceil(float(amount) * float(config["cargo_aircraft_per_item"][str(key)])))
		people += float(unit["humans"])
		if not is_finite(people) or people > float(config["personnel_per_aircraft"]) * float(config["max_concurrent_aircraft"]):
			return {"ok": false, "reason": "capacity"}
		checked.append(id)
	var occupied: int = 0
	for flight in owner._pmc_airlifts:
		if flight is Dictionary and str(flight.get("status", "")) in ACTIVE:
			occupied += maxi(0, int(flight.get("aircraft", 0)))
	var aircraft: int = int(ceil(people / float(config["personnel_per_aircraft"]))) + cargo_aircraft
	if aircraft <= 0 or aircraft > maxi(0, int(config["max_concurrent_aircraft"]) - occupied):
		return {"ok": false, "reason": "capacity"}
	var km: float = army.km_between(source, destination)
	if not is_finite(km) or km < 0.0:
		return {"ok": false, "reason": "selection"}
	var days: int = maxi(1, int(ceil(km / float(config["km_per_day"]))))
	var fee: float = float(aircraft) * float(config["fee_per_aircraft"])
	var reserve: float = fee * float(config["return_reserve_ratio"])
	if not is_finite(fee + reserve):
		return {"ok": false, "reason": "funds"}
	return {"ok": true, "unit_ids": checked, "source": source, "destination": destination,
		"people": people, "aircraft": aircraft, "loading_days": int(config["loading_days"]),
		"flight_days": days, "fee": fee, "reserve": reserve, "total": fee + reserve}

static func book(owner, game: PaxGame, expected: Dictionary) -> Dictionary:
	var fresh: Dictionary = preview(owner, game, expected.get("unit_ids", []), int(expected.get("destination", 0)))
	if not bool(fresh.get("ok", false)):
		return fresh
	for key in ["source", "people", "aircraft", "loading_days", "flight_days", "total"]:
		if fresh[key] != expected.get(key):
			return {"ok": false, "reason": "changed"}
	var stock: Dictionary = game.main.model.resources.stock(game.home_body())
	var money: float = float(stock.get("money", 0.0))
	if not is_finite(money) or money < float(fresh["total"]):
		return {"ok": false, "reason": "funds"}
	var cargo: Array = []
	for id in fresh["unit_ids"]:
		cargo.append(game.main.model.armies.unit(int(id)))
	var next_id: int = 1
	for old in owner._pmc_airlifts:
		if old is Dictionary:
			next_id = maxi(next_id, int(old.get("id", 0)) + 1)
	var flight: Dictionary = fresh.duplicate(true)
	flight.erase("ok")
	flight.merge({"id": next_id, "side": game.country(), "body": game.home_body(), "status": "loading",
		"booked_day": game.day(), "takeoff_day": game.day() + int(fresh["loading_days"]),
		"earliest_arrival": game.day() + int(fresh["loading_days"]) + int(fresh["flight_days"]),
		"cargo": cargo, "paid": float(fresh["total"]), "refunded": 0.0}, true)
	stock["money"] = money - float(fresh["total"])
	for unit in cargo:
		game.main.model.armies.units.erase(unit)
	owner._pmc_airlifts.append(flight)
	game.main.show_queue().map_changed()
	owner._refresh_ui()
	return {"ok": true, "flight": flight}

static func restore(flight: Dictionary, runtime, province: int, status: String, day: int) -> bool:
	if not runtime.model.earth_provinces or province <= 0 or province > runtime.model.earth_provinces.amount():
		flight["status"] = "review"
		return false
	var cargo = flight.get("cargo", [])
	if not (cargo is Array) or cargo.is_empty():
		flight["status"] = "review"
		return false
	var seen: Dictionary = {}
	for unit in cargo:
		if not (unit is Dictionary) or int(unit.get("id", 0)) <= 0 or seen.has(int(unit.get("id", 0))) or not runtime.model.armies.unit(int(unit["id"])).is_empty():
			flight["status"] = "review"
			return false
		seen[int(unit["id"])] = true
	var people: float = 0.0
	for unit in cargo:
		unit["province"] = province
		unit["road"] = []
		unit["progress"] = 0.0
		unit["our"] = str(unit.get("whose", "")) == runtime.country_name().our_name()
		people += float(unit.get("humans", 0.0))
		runtime.model.armies.units.append(unit)
	flight["cargo"] = []
	flight["status"] = status
	flight["actual_arrival_day"] = day
	flight["landed_province"] = province
	flight["arrived_people"] = people
	return true

# World-thread stage; no UI calls. Arrivals occur at the current simulation
# boundary after ground combat, never retroactively before the flight ended.
static func advance(owner, ctx: Dictionary) -> void:
	var runtime = ctx.get("game")
	if not runtime or not runtime.model or not runtime.model.armies:
		return
	var today: int = int(runtime.model.sim.day)
	for flight in owner._pmc_airlifts:
		if not (flight is Dictionary) or str(flight.get("status", "")) not in ["loading", "in_flight", "returning"]:
			continue
		var cargo = flight.get("cargo", [])
		if not (cargo is Array) or cargo.is_empty() or not (cargo[0] is Dictionary):
			flight["status"] = "review"
			continue
		if str(flight["status"]) == "loading" and today >= int(flight.get("takeoff_day", today)):
			if not allowed(runtime.model.armies, str(flight.get("side", "")), int(flight["source"]), cargo[0]):
				if restore(flight, runtime, int(flight["source"]), "loading_interrupted", today):
					flight["refund_due"] = float(flight.get("paid", 0.0))
				continue
			flight["status"] = "in_flight"
		if today < int(flight.get("earliest_arrival", today)):
			continue
		var returning: bool = str(flight["status"]) == "returning"
		var destination: int = int(flight["source"] if returning else flight["destination"])
		var access: bool = allowed(runtime.model.armies, str(flight.get("side", "")), destination, cargo[0])
		if not returning and not access:
			flight["status"] = "returning"
			flight["return_started_day"] = today
			flight["earliest_arrival"] = today + maxi(1, int(flight.get("flight_days", 1)))
			continue
		var result: String = "returned" if returning else "arrived"
		if returning and not access:
			result = "emergency_return"
		if restore(flight, runtime, destination, result, today) and not returning:
			flight["refund_due"] = float(flight.get("reserve", 0.0))

static func cancel(owner, game: PaxGame, flight_id: int) -> bool:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or game.main.rewind_state.rewinding:
		return false
	for flight in owner._pmc_airlifts:
		if flight is Dictionary and int(flight.get("id", 0)) == flight_id and str(flight.get("side", "")) == game.country() and str(flight.get("status", "")) == "loading" and game.day() < int(flight.get("takeoff_day", 0)):
			if restore(flight, game.main, int(flight["source"]), "cancelled", game.day()):
				flight["refund_due"] = float(flight.get("paid", 0.0))
				flush(owner, game)
				game.main.show_queue().map_changed()
				owner._refresh_ui()
				return true
	return false

static func flush(owner, game: PaxGame) -> void:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or not game.main.model or not game.main.model.resources:
		return
	var changed: bool = false
	for flight in owner._pmc_airlifts:
		if not (flight is Dictionary) or str(flight.get("side", "")) != game.country():
			continue
		var refund: float = minf(float(flight.get("refund_due", 0.0)), maxf(0.0, float(flight.get("paid", 0.0)) - float(flight.get("refunded", 0.0))))
		if refund > 0.0 and str(flight.get("body", "")) == game.home_body():
			var stock: Dictionary = game.main.model.resources.stock(game.home_body())
			stock["money"] = float(stock.get("money", 0.0)) + refund
			flight["refunded"] = float(flight.get("refunded", 0.0)) + refund
			flight["refund_due"] = 0.0
			changed = true
		var status: String = str(flight.get("status", "review"))
		if str(flight.get("notified_status", "")) == status:
			continue
		flight["notified_status"] = status
		changed = true
		var text: String = owner.tr_key("prigozhin_fork_airlift_report") % [int(flight.get("id", 0)), owner.tr_key("prigozhin_fork_airlift_" + status), int(flight.get("source", 0)), int(flight.get("destination", 0))]
		text += "\n" + (owner.tr_key("prigozhin_fork_airlift_finance") % [str(flight.get("paid", 0.0)), str(flight.get("refunded", 0.0))])
		owner._deals.append({"id": "airlift_%d_%s_%d" % [int(flight.get("id", 0)), status, game.day()],
			"partner": owner.tr_key("prigozhin_fork_ai_hq"), "title": owner.tr_key("prigozhin_fork_airlift_title"),
			"terms": text, "status": "report", "cost": 0.0, "risk": 0})
		game.toast(text)
	if changed:
		game.main.show_queue().map_changed()

static func cargo_people(owner, army, side: String) -> float:
	var people: float = 0.0
	for flight in owner._pmc_airlifts:
		if not (flight is Dictionary) or str(flight.get("side", "")) != side or str(flight.get("status", "")) not in ACTIVE:
			continue
		for unit in flight.get("cargo", []):
			if unit is Dictionary and army.unit(int(unit.get("id", 0))).is_empty():
				people += maxf(0.0, float(unit.get("humans", 0.0)))
	return people

static func cargo_views(owner, side: String) -> Array:
	var result: Array = []
	for flight in owner._pmc_airlifts:
		if not (flight is Dictionary) or str(flight.get("side", "")) != side or str(flight.get("status", "")) not in ACTIVE:
			continue
		for unit in flight.get("cargo", []):
			if unit is Dictionary:
				var view: Dictionary = unit.duplicate(true)
				view["province"] = 0
				view["prigozhin_fork_in_airlift"] = int(flight.get("id", 0))
				view["airlift_status"] = str(flight["status"])
				view["airlift_source"] = int(flight["source"])
				view["airlift_destination"] = int(flight["destination"])
				result.append(view)
	return result

static func name_in_transit(owner, side: String, unit_name: String) -> bool:
	for view in cargo_views(owner, side):
		if str(view.get("name", "")).to_lower() == unit_name.to_lower():
			return true
	return false
