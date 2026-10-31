extends RefCounted

const Airlift = preload("res://mods/prigozhin_fork/systems/pmc_airlift.gd")

static func armies(owner):
	if not owner._last_game or not owner._last_game.main:
		return null
	var runtime = owner._last_game.main
	if not runtime.model:
		return null
	return runtime.model.armies

# Read-only view of units controlled by the player's current side.
# Legacy name matching is a display heuristic, not authority to migrate a save.
static func player_units(owner) -> Array:
	var result: Array = []
	var service = armies(owner)
	if service == null or not owner._last_game:
		return result
	var side: String = owner._last_game.country()
	if side.is_empty():
		return result
	for unit in service.units:
		if not (unit is Dictionary) or not bool(unit.get("our", false)):
			continue
		if str(unit.get("whose", "")) != side:
			continue
		var name_lower: String = str(unit.get("name", "")).to_lower()
		if bool(unit.get("prigozhin_fork_pmc", false)) or "вагнер" in name_lower:
			result.append(unit)
	for view in Airlift.cargo_views(owner, side):
		if service.unit(int(view.get("id", 0))).is_empty():
			result.append(view)
	return result

# Candidate matching is informational only; names do not prove identity.
static func legacy_candidates(owner, legacy: Dictionary) -> Dictionary:
	if not owner or not owner._last_game or Pax.world_busy() or not armies(owner):
		return {"available": false, "ids": []}
	var wanted: String = str(legacy.get("name", "")).strip_edges().to_lower()
	if wanted.is_empty():
		return {"available": true, "ids": []}
	var ids: Array = []
	for unit in player_units(owner):
		if str(unit.get("name", "")).strip_edges().to_lower() == wanted:
			ids.append(int(unit.get("id", 0)))
	return {"available": true, "ids": ids}

# Admission check only. The game's army reserve is an upper bound, not a
# verified volunteer pool; game conditions can still change before execution.
static func native_recruit_preflight(owner, game: PaxGame, unit_name: String, count: int) -> Dictionary:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main):
		return {"ok": false, "reason": "unavailable"}
	var runtime: Node = game.main
	if not runtime.model or not runtime.model.armies or not runtime.model.resources or not runtime.rewind_state:
		return {"ok": false, "reason": "unavailable"}
	if runtime.rewind_state.rewinding:
		return {"ok": false, "reason": "rewinding"}
	var name_clean: String = unit_name.strip_edges()
	var side: String = game.country()
	if name_clean.is_empty() or count <= 0 or side.is_empty() or not runtime.has_method("bases"):
		return {"ok": false, "reason": "unavailable"}
	var faction_id: int = int(runtime.model.our_faction)
	var earth_id: int = int(runtime.model.earth_index)
	if faction_id < 0 or faction_id >= runtime.model.factions.size() or earth_id < 0 or earth_id >= runtime.model.bodies.size():
		return {"ok": false, "reason": "unavailable"}
	for unit in runtime.model.armies.units:
		if unit is Dictionary and str(unit.get("whose", "")) == side and str(unit.get("name", "")).strip_edges().to_lower() == name_clean.to_lower():
			return {"ok": false, "reason": "duplicate"}
	for legacy in owner._custom_wagner_detachments:
		if legacy is Dictionary and str(legacy.get("name", "")).strip_edges().to_lower() == name_clean.to_lower():
			return {"ok": false, "reason": "legacy"}
	var pending: int = 0
	for order in runtime.model.orders:
		if not (order is Dictionary) or str(order.get("status", "")) not in ["being_weighed", "awaits_ok", "queued", "under_way"]:
			continue
		var place = order.get("place", {})
		if not (place is Dictionary) or not bool(place.get("prigozhin_fork_recruit_request", false)) or str(place.get("recruit_side", "")) != side:
			continue
		if str(place.get("recruit_name", "")).strip_edges().to_lower() == name_clean.to_lower():
			return {"ok": false, "reason": "duplicate"}
		pending += maxi(0, int(place.get("recruit_count", 0)))
	var bases = runtime.bases()
	if not bases:
		return {"ok": false, "reason": "unavailable"}
	var available: int = maxi(0, int(floorf(bases.country_reserve(side))) - pending)
	if count > available:
		return {"ok": false, "reason": "reserve", "available": available}
	return {"ok": true, "side": side, "available": available}

static func get_armies_dict(owner) -> Dictionary:
	var service = armies(owner)
	if service == null:
		return {}
	return {"detachments": service.units}

static func spawn_wagner_detachment(owner, game: PaxGame, det_name: String, count: int) -> void:
	if not owner or not game:
		return
	var recruitment = preload("res://mods/prigozhin_fork/systems/pmc_recruitment.gd")
	var result: Dictionary = recruitment.reserve(owner, game, det_name, count, 14)
	if bool(result.get("ok", false)):
		game.toast(owner.tr_key("prigozhin_fork_recruit_queue_added"))
		owner._refresh_ui()
	elif str(result.get("reason", "")) == "unsupported_role":
		game.toast(owner.tr_key("prigozhin_fork_recruit_queue_role"))
	else:
		game.toast(owner.tr_key("prigozhin_fork_unit_order_rejected"))

