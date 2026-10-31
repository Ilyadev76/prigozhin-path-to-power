extends "res://src/ai/OrderEvaluation.gd"

const RecruitBridge = preload("res://mods/prigozhin_fork/systems/pmc_order_bridge.gd")

func prigozhin_fork_recruit_bridge_version() -> int:
	return 1

func _accept_request(request: Dictionary, p: Dictionary) -> bool:
	if bool(p.get("reassess", false)):
		return super._accept_request(request, p)
	var owner = Pax.get_mod("prigozhin_fork")
	if not owner or not owner._last_game or owner._last_game.main != game:
		return super._accept_request(request, p)
	if request.has("error"):
		request = _without_model(request, p)
	if int(p.get("prigozhin_fork_recruit_queue_id", 0)) > 0:
		var previous: Dictionary = RecruitBridge.application(owner, int(p["prigozhin_fork_recruit_queue_id"]))
		if not previous.is_empty() and str(previous.get("status", "")) in ["pending", "blocked", "cancelled"] and not bool(previous.get("native_due", false)) and not bool(previous.get("native_uncertain", false)):
			previous["status"] = "cancelled"
		else:
			RecruitBridge.reject(owner, p, "changed")
			return false
		p.erase("prigozhin_fork_recruit_queue_id")
	p.erase("prigozhin_fork_recruit_proposal")
	p.erase("prigozhin_fork_recruit_payload")
	p.erase("prigozhin_fork_recruit_quote")
	p.erase("prigozhin_fork_recruit_dispatch_failed")
	var place = p.get("place", {})
	if not RecruitBridge.candidate(game, request, place if place is Dictionary else {}):
		return super._accept_request(request, p)
	if not RecruitBridge.ready(game):
		RecruitBridge.reject(owner, p, "reload")
		return false
	var hook_data: Dictionary = game._pax_hook("order_parsed", {"order": str(p.get("text", "")), "request": request, "cancel": false})
	if bool(hook_data.get("cancel", false)):
		RecruitBridge.reject(owner, p, "mixed")
		p["request"]["why_not"] = str(hook_data.get("reason", owner.tr_key("prigozhin_fork_native_recruit_mixed")))
		return false
	if hook_data.get("request") is Dictionary:
		request = hook_data["request"]
	if not bool(request.get("plausible", true)):
		RecruitBridge.reject(owner, p, "admission")
		p["request"]["why_not"] = str(request.get("why_not", owner.tr_key("prigozhin_fork_native_recruit_admission")))
		return false
	var data: Dictionary = RecruitBridge.describe(owner, game, p, request)
	if not bool(data.get("ok", false)):
		RecruitBridge.reject(owner, p, str(data.get("reason", "mixed")))
		return false
	var quote: float = PlayerRoleScript.hire_price({"fighters": int(data["count"])})
	if not is_finite(quote) or quote < 0.0:
		RecruitBridge.reject(owner, p, "admission")
		return false
	var action: Dictionary = {"action": "reinforce" if int(data["target_id"]) > 0 else "create",
		"name": data["name"], "make_up": {"fighters": int(data["count"])}, "machinery": {}, "description": data["description"]}
	if int(data["target_id"]) > 0:
		action["id"] = int(data["target_id"])
	# Keep the hire blueprint outside the generic request. If the mod is disabled
	# later, the saved native ticket cannot hire or charge through the base executor.
	var clean: Dictionary = {"understood": owner.tr_key("prigozhin_fork_native_recruit_summary") % [str(data["name"]), int(data["count"]), int(data["days"])],
		"work_kind": "military", "plausible": true, "magnitude": 0.0, "days": int(data["days"]),
		"needs": {}, "detachments": [action]}
	p["prigozhin_fork_recruit_payload"] = clean
	p["prigozhin_fork_recruit_quote"] = quote
	p["request"] = {"understood": clean["understood"], "plausible": true, "magnitude": 0.0, "days": int(data["days"]), "needs": {}, "deltas": {}}
	p["prigozhin_fork_recruit_proposal"] = data.duplicate(true)
	p["days"] = int(data["days"])
	p["elapsed"] = 0
	p["status"] = "awaits_ok" if needs_confirmation(p) else "queued"
	if str(p.get("status", "")) == "queued":
		RecruitBridge.confirm(owner, game, p)
	return false
