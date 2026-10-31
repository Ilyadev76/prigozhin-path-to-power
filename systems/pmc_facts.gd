extends RefCounted

const ArmyOperations = preload("res://mods/prigozhin_fork/systems/army_operations.gd")
const Sources = preload("res://mods/prigozhin_fork/systems/pmc_recruit_sources.gd")

# Main-thread observation only. Never substitute old narrative flags or the
# legacy virtual roster for actual units. Bounded payload keeps calls compact.
static func capture(owner, game: PaxGame) -> Dictionary:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or not game.main.model or not game.main.model.armies:
		return {"available": false}
	var units: Array = ArmyOperations.player_units(owner)
	var roster: Array = []
	var total: int = 0
	var in_transit: int = 0
	for unit in units:
		total += maxi(0, int(unit.get("humans", 0)))
		if int(unit.get("prigozhin_fork_in_airlift", 0)) > 0:
			in_transit += 1
			if roster.size() < 32:
				roster.append({"id": int(unit.get("id", 0)), "name": str(unit.get("name", "")), "humans": int(unit.get("humans", 0)),
					"in_transport": true, "on_ground": false, "transport_id": int(unit["prigozhin_fork_in_airlift"]),
					"transport_status": str(unit.get("airlift_status", "review")), "source": int(unit.get("airlift_source", 0)),
					"planned_destination": int(unit.get("airlift_destination", 0)), "arrival_confirmed": false})
			continue
		if roster.size() >= 32:
			continue
		var province_id: int = int(unit.get("province", 0))
		var body: String = str(unit.get("body", ""))
		var map_body: String = game.home_body() if body.is_empty() else body
		var place: Dictionary = game.province(map_body, province_id) if province_id > 0 else {}
		var road = unit.get("road", [])
		var row: Dictionary = {"id": int(unit.get("id", 0)), "name": str(unit.get("name", "")),
			"body": map_body, "province": province_id, "place": str(place.get("name", "")),
			"humans": int(unit.get("humans", 0)), "losses": float(unit.get("losses", 0.0)),
			"in_battle": not game.main.model.armies.battle_with_unit(int(unit.get("id", 0))).is_empty()}
		if road is Array and not road.is_empty():
			row["next_sector"] = int(road[0])
			row["destination"] = int(road[-1])
			row["remaining_sectors"] = road.size()
		else:
			row["destination"] = null
		var stores = unit.get("provisions", {})
		if stores is Dictionary:
			row["provisions"] = stores.duplicate(true)
		roster.append(row)
	var recruitment: Dictionary = {"available": false}
	var transport_ready: bool = false
	if game.main.player and str(game.main.player.player_role) in ["person", "organization"]:
		var treasury = game.main.treasury()
		transport_ready = treasury and treasury.has_method("prigozhin_fork_airlift_upkeep_version") and int(treasury.prigozhin_fork_airlift_upkeep_version()) == 1
	var source: Dictionary = Sources.snapshot(owner, game)
	if bool(source.get("ok", false)):
		var held: int = Sources.reserved(owner, game, str(source["source_country"]))
		recruitment = {"available": true, "source_country": source["source_country"], "province": source["source_province"],
			"modelled_candidates": maxi(0, int(source["reserve"]) - held), "reserved": held,
			"not_hired_or_confirmed_people": true, "next_refill_day": source["next_refill_day"]}
	return {"available": true, "observed_day": game.day(), "side": game.country(), "local_recruitment": recruitment,
		"total_native_pmc_units": units.size(), "total_native_pmc_humans": total,
		"units_in_transport": in_transit,
		"roster_truncated": units.size() > roster.size(), "units": roster,
		"legacy_airlift_status_is_not_evidence": true, "charter_air_transport_connected": transport_ready,
		"dialogue_does_not_execute_actions": true}
