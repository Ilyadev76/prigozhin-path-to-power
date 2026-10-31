extends "res://src/ai/OrderExecution.gd"

const RecruitBridge = preload("res://mods/prigozhin_fork/systems/pmc_order_bridge.gd")

func prigozhin_fork_recruit_bridge_version() -> int:
	return 1

func execute(p: Dictionary) -> Dictionary:
	var owner = Pax.get_mod("prigozhin_fork")
	if p.has("prigozhin_fork_recruit_proposal") or int(p.get("prigozhin_fork_recruit_queue_id", 0)) > 0:
		return RecruitBridge.dispatch(owner, game, p)
	var request = p.get("request", {})
	var place = p.get("place", {})
	if owner and request is Dictionary and RecruitBridge.candidate(game, request, place if place is Dictionary else {}):
		return {"id": p.get("id", 0), "order_cmd": str(p.get("text", "")), "body": str(p.get("body", "")),
			"state": "impossible", "why": owner.tr_key("prigozhin_fork_native_recruit_legacy")}
	return super.execute(p)
