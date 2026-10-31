extends "res://src/economy/Treasury.gd"

const Airlift = preload("res://mods/prigozhin_fork/systems/pmc_airlift.gd")

func prigozhin_fork_airlift_upkeep_version() -> int:
	return 1

func breakdown(body: String) -> Dictionary:
	var result: Dictionary = super.breakdown(body)
	var owner = Pax.get_mod("prigozhin_fork")
	if not owner or not bool(result.get("exists", false)) or not PlayerRoleScript.own_f(player.player_role) or not model.armies or int(model.earth_index) < 0 or body != str(model.bodies[model.earth_index]["name"]):
		return result
	var people: float = Airlift.cargo_people(owner, model.armies, game.country_name().our_name())
	if people <= 0.0:
		return result
	# Those units are absent from the native ground roster, so the inherited
	# wage line has not counted them. Budget/debt handling remains native.
	var wages: float = people * PlayerRoleScript.WAGE_PER_WEEK
	result["on_army"] = float(result.get("on_army", 0.0)) + wages
	result["fighters_of"] = int(result.get("fighters_of", 0)) + int(ceil(people))
	result["expense"] = float(result.get("expense", 0.0)) + wages
	result["remainder"] = float(result.get("remainder", 0.0)) - wages
	return result
