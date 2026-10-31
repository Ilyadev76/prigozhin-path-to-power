extends RefCounted

# Recruitment market rules belong to the mod. Native country manpower is only
# its upper bound: no national troops or population are transferred by this code.
static func location(game: PaxGame, target_id: int = 0, expected_province: int = 0) -> Dictionary:
	if not game or Pax.world_busy() or not is_instance_valid(game.main):
		return {"ok": false, "reason": "unavailable"}
	var runtime: Node = game.main
	if not runtime.model or not runtime.model.armies or not runtime.player or not runtime.model.resources:
		return {"ok": false, "reason": "unavailable"}
	if str(runtime.player.player_role) not in ["person", "organization"]:
		return {"ok": false, "reason": "unsupported_role"}
	if int(runtime.model.earth_index) < 0 or int(runtime.model.earth_index) >= runtime.model.bodies.size() or int(runtime.model.our_faction) < 0 or int(runtime.model.our_faction) >= runtime.model.factions.size() or not runtime.model.factions_sim:
		return {"ok": false, "reason": "unavailable"}
	var unit: Dictionary = {}
	if target_id > 0:
		unit = runtime.model.armies.unit(target_id)
	elif runtime.has_method("army_for_model"):
		var roster = runtime.army_for_model()
		if roster:
			unit = roster.own_unit()
	if unit.is_empty() or not bool(unit.get("our", false)) or str(unit.get("whose", "")) != game.country() or str(unit.get("body", "")) != "":
		return {"ok": false, "reason": "source_not_ready"}
	if target_id == 0 and unit.has("body"):
		return {"ok": false, "reason": "source_not_ready"}
	var province: int = int(unit.get("province", 0))
	var road = unit.get("road", [])
	if province <= 0 or (expected_province > 0 and province != expected_province) or not (road is Array) or not road.is_empty() or not runtime.model.armies.battle_with_unit(int(unit.get("id", 0))).is_empty():
		return {"ok": false, "reason": "source_not_ready"}
	var data: Dictionary = game.province(game.home_body(), province)
	var country: String = str(data.get("owner", ""))
	if country.is_empty():
		return {"ok": false, "reason": "source_unavailable"}
	return {"ok": true, "side": game.country(), "source_country": country,
		"source_province": province, "place": str(data.get("name", ""))}

static func rules(owner) -> Dictionary:
	var data = owner.load_json("data/pmc_recruitment_rules.json")
	if not (data is Dictionary):
		return {}
	for key in ["initial_candidates", "candidates_per_period", "period_days", "max_waiting_candidates"]:
		var value = data.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1000000.0 or float(value) != float(int(value)):
			return {}
	if int(data["period_days"]) <= 0 or int(data["max_waiting_candidates"]) <= 0:
		return {}
	return data

static func snapshot(owner, game: PaxGame, target_id: int = 0, expected_province: int = 0) -> Dictionary:
	if not owner or owner._last_game != game:
		return {"ok": false, "reason": "unavailable"}
	var result: Dictionary = location(game, target_id, expected_province)
	if not bool(result.get("ok", false)):
		return result
	var config: Dictionary = rules(owner)
	if config.is_empty() or not game.main.has_method("bases"):
		return {"ok": false, "reason": "source_unavailable"}
	var source: String = str(result["source_country"])
	var bases = game.main.bases()
	if not bases:
		return {"ok": false, "reason": "source_unavailable"}
	var native_amount: float = bases.country_reserve(source)
	if not is_finite(native_amount):
		return {"ok": false, "reason": "source_unavailable"}
	var capacity: int = maxi(0, int(floorf(native_amount)))
	var today: int = game.day()
	var market: Dictionary = {}
	if owner._pmc_recruit_sources.has(source):
		var saved = owner._pmc_recruit_sources[source]
		if not (saved is Dictionary) or not saved.has("available") or not saved.has("consumed") or not saved.has("refill_day") or not (saved.get("receipts") is Dictionary):
			return {"ok": false, "reason": "source_review"}
		market = saved
		if today < int(market["refill_day"]) or int(market["available"]) < 0 or int(market["consumed"]) < 0 or int(market.get("uncertain_used", 0)) < 0 or not (market.get("uncertain_receipts", {}) is Dictionary):
			return {"ok": false, "reason": "source_review"}
	else:
		market = {"country": source, "opened_day": today, "refill_day": today,
			"available": mini(capacity, mini(int(config["initial_candidates"]), int(config["max_waiting_candidates"]))),
			"consumed": 0, "receipts": {}, "uncertain_used": 0, "uncertain_receipts": {}}
		owner._pmc_recruit_sources[source] = market
	if not advance_market(market, capacity, today, config):
		return {"ok": false, "reason": "source_review"}
	result["reserve"] = int(market["available"])
	result["native_capacity"] = capacity
	result["consumed"] = int(market["consumed"])
	result["uncertain_used"] = int(market.get("uncertain_used", 0))
	result["next_refill_day"] = int(market["refill_day"]) + int(config["period_days"])
	result["rules"] = config
	return result

# Pure calendar/accounting operation: no game, money or unit changes.
static func advance_market(market: Dictionary, capacity: int, today: int, config: Dictionary) -> bool:
	var period: int = int(config.get("period_days", 0))
	if period <= 0 or not market.has("refill_day") or today < int(market["refill_day"]):
		return false
	var elapsed: int = today - int(market["refill_day"])
	var periods: int = int(floorf(float(elapsed) / float(period)))
	if periods > 0:
		market["available"] = mini(int(config["max_waiting_candidates"]), int(market.get("available", 0)) + periods * int(config["candidates_per_period"]))
		market["refill_day"] = int(market["refill_day"]) + periods * period
	# Used candidates remain used after death or disbanding; no instant refund.
	var remaining_capacity: int = maxi(0, capacity - int(market.get("consumed", 0)) - int(market.get("uncertain_used", 0)))
	market["available"] = mini(maxi(0, int(market.get("available", 0))), mini(remaining_capacity, int(config["max_waiting_candidates"])))
	return true

static func already_consumed(owner, source: String, request_id: int) -> int:
	var pool = owner._pmc_recruit_sources.get(source, {})
	if not (pool is Dictionary):
		return 0
	var receipts = pool.get("receipts", {})
	return maxi(0, int(receipts.get(str(request_id), 0))) if receipts is Dictionary else 0

static func already_accounted(owner, source: String, request_id: int) -> int:
	var known: int = already_consumed(owner, source, request_id)
	var market = owner._pmc_recruit_sources.get(source, {})
	var uncertain = market.get("uncertain_receipts", {}) if market is Dictionary else {}
	return known + (maxi(0, int(uncertain.get(str(request_id), 0))) if uncertain is Dictionary else 0)

# Unsettled uncertain outcomes keep their reservation. Settled uncertain debits
# are already accounted for, so they cannot be reused or freeze future cohorts.
static func reserved(owner, game: PaxGame, source: String, ignore_request: int = 0, ignore_native_order: int = 0) -> int:
	var amount: int = 0
	for entry in owner._pmc_recruitment:
		if not (entry is Dictionary) or int(entry.get("id", 0)) == ignore_request or str(entry.get("side", "")) != game.country() or str(entry.get("source_country", "")) != source:
			continue
		if int(entry.get("native_order_id", 0)) > 0 and not native_ticket_present(game, entry):
			continue
		amount += reservation_amount(entry, already_accounted(owner, source, int(entry.get("id", 0))))
	# Compatibility with marked requests from the earlier native-order form.
	for order in game.main.model.orders:
		if not (order is Dictionary) or str(order.get("status", "")) not in ["being_weighed", "awaits_ok", "queued", "under_way"]:
			continue
		if int(order.get("id", 0)) == ignore_native_order or int(order.get("prigozhin_fork_recruit_queue_id", 0)) > 0:
			continue
		var place = order.get("place", {})
		if place is Dictionary and bool(place.get("prigozhin_fork_recruit_request", false)) and str(place.get("recruit_side", "")) == game.country():
			amount += maxi(0, int(place.get("recruit_count", 0)))
	return amount

static func native_ticket_present(game: PaxGame, entry: Dictionary) -> bool:
	for order in game.main.model.orders:
		if order is Dictionary and int(order.get("id", 0)) == int(entry.get("native_order_id", 0)):
			return int(order.get("prigozhin_fork_recruit_queue_id", 0)) == int(entry.get("id", 0)) and str(order.get("text", "")) == str(entry.get("native_original", "")) and str(order.get("status", "")) not in ["impossible", "being_weighed"] and not bool(order.get("prigozhin_fork_recruit_dispatch_failed", false))
	return false

static func reservation_amount(entry: Dictionary, processed: int) -> int:
	if str(entry.get("status", "")) in ["pending", "blocked", "executing", "review"] or bool(entry.get("native_uncertain", false)):
		return maxi(0, int(entry.get("requested", 0)) - processed)
	return 0

static func consume(owner, entry: Dictionary, count: int) -> bool:
	var source: String = str(entry.get("source_country", ""))
	var request_id: int = int(entry.get("id", 0))
	var market = owner._pmc_recruit_sources.get(source)
	if not (market is Dictionary) or not (market.get("receipts") is Dictionary) or request_id <= 0 or count <= 0 or count > int(entry.get("requested", 0)) or already_accounted(owner, source, request_id) > 0 or int(market.get("available", 0)) < count:
		return false
	market["available"] = int(market["available"]) - count
	market["consumed"] = int(market.get("consumed", 0)) + count
	market["receipts"][str(request_id)] = count
	entry["pool_consumed"] = count
	return true

# Closing an uncertain hiring result consumes the remaining reservation as an
# explicit conservative debit, not as confirmed hires. New cohorts can then
# arrive without this record freezing the waiting pool forever. No money moves.
static func settle_uncertain(owner, entry: Dictionary) -> bool:
	if not bool(entry.get("native_uncertain", false)) or str(entry.get("source_country", "")).is_empty():
		return true
	var source: String = str(entry["source_country"])
	var request_id: int = int(entry.get("id", 0))
	var market = owner._pmc_recruit_sources.get(source)
	if not (market is Dictionary) or request_id <= 0:
		return false
	var amount: int = maxi(0, int(entry.get("requested", 0)) - already_accounted(owner, source, request_id))
	if amount == 0:
		return true
	var previous = market.get("uncertain_receipts", {})
	if not (previous is Dictionary):
		return false
	market["available"] = maxi(0, int(market.get("available", 0)) - amount)
	market["uncertain_used"] = maxi(0, int(market.get("uncertain_used", 0))) + amount
	previous[str(request_id)] = int(previous.get(str(request_id), 0)) + amount
	market["uncertain_receipts"] = previous
	entry["pool_uncertain_debit"] = int(previous[str(request_id)])
	return true
