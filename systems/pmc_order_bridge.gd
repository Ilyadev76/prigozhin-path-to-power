extends RefCounted

const Recruitment = preload("res://mods/prigozhin_fork/systems/pmc_recruitment.gd")
const META_KEYS: Array = ["understood", "work_kind", "plausible", "why_not", "days", "phases", "magnitude", "rung", "needs", "detachments", "difficulty", "chance", "success_chance", "risk", "reason", "description", "prigozhin_fork_recruit_proposal"]

static func number(value) -> int:
	if value is String:
		return int(value) if value.is_valid_int() else -1
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != float(int(value)):
		return -1
	return int(value)

static func empty_effect(value, depth: int = 0) -> bool:
	if depth > 8:
		return false
	if value == null:
		return true
	if value is Dictionary or value is Array:
		var values: Array = value.values() if value is Dictionary else value
		for item in values:
			if not empty_effect(item, depth + 1):
				return false
		return true
	if value is String:
		return value.strip_edges().is_empty()
	if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		return float(value) == 0.0
	return false

static func candidate(runtime, request: Dictionary, place: Dictionary = {}) -> bool:
	var actions = request.get("detachments", [])
	if not (actions is Array):
		return false
	var personal: bool = runtime.player and str(runtime.player.player_role) in ["person", "organization"]
	# Older Prigozhin saves incorrectly used a country role. Recognize that
	# scenario's side without applying PMC rules to unrelated country campaigns.
	if not personal and runtime.has_method("country_name"):
		var side_name: String = str(runtime.country_name().our_name()).to_lower()
		for marker in ["пригожин", "prigozhin_fork", "народный фронт возрождения", "нфв", "nfw"]:
			if side_name.contains(marker):
				personal = true
				break
	for action in actions:
		if not (action is Dictionary) or str(action.get("action", "")) not in ["create", "reinforce"]:
			continue
		var id: int = number(action.get("id", place.get("detachment", 0)))
		var unit: Dictionary = runtime.model.armies.unit(id) if runtime.model and runtime.model.armies and id > 0 else {}
		var composition = action.get("make_up", {})
		# Arming the single player-person is not hiring another PMC unit.
		if runtime.player and str(runtime.player.player_role) == "person" and str(action.get("action", "")) == "reinforce" and bool(unit.get("self", false)) and composition is Dictionary:
			var self_count: int = 0
			var only_armed: bool = true
			for key in composition:
				if str(key) in ["fighters", "soldiers", "militiamen"] and number(composition[key]) >= 0:
					self_count += number(composition[key])
				elif not empty_effect(composition[key]):
					only_armed = false
			if only_armed and self_count == 1:
				continue
		var name_text: String = str(action.get("name", "")).to_lower()
		if name_text.contains("вагнер") or name_text.contains("wagner") or bool(place.get("prigozhin_fork_recruit_request", false)):
			return true
		if runtime.model and runtime.model.armies and id > 0:
			var unit_name: String = str(unit.get("name", "")).to_lower()
			if bool(unit.get("prigozhin_fork_pmc", false)) or unit_name.contains("вагнер") or unit_name.contains("wagner"):
				return true
		if personal and composition is Dictionary:
			for key in ["fighters", "soldiers", "militiamen"]:
				if not empty_effect(composition.get(key)):
					return true
	return false

static func ready(runtime) -> bool:
	if not runtime or not runtime.has_method("order_evaluation") or not runtime.has_method("order_execution") or not runtime.has_method("rewind"):
		return false
	var evaluation = runtime.order_evaluation()
	var execution = runtime.order_execution()
	var timeline = runtime.rewind()
	return evaluation and execution and timeline and evaluation.has_method("prigozhin_fork_recruit_bridge_version") and execution.has_method("prigozhin_fork_recruit_bridge_version") and timeline.has_method("prigozhin_fork_recruit_bridge_version") and int(evaluation.prigozhin_fork_recruit_bridge_version()) == 1 and int(execution.prigozhin_fork_recruit_bridge_version()) == 1 and int(timeline.prigozhin_fork_recruit_bridge_version()) == 1

# Closed, narrow contract: one armed hire, without purchases, movement or other
# world effects. Mixed requests are rejected intact, never partially executed.
static func describe(owner, runtime, p: Dictionary, request: Dictionary) -> Dictionary:
	if not owner or not owner._last_game or owner._last_game.main != runtime or not runtime.model or not runtime.model.armies:
		return {"ok": false, "reason": "unavailable"}
	if not runtime.player or str(runtime.player.player_role) not in ["person", "organization"]:
		return {"ok": false, "reason": "role"}
	if runtime.mp != null:
		return {"ok": false, "reason": "context"}
	if str(p.get("body", "")) != owner._last_game.home_body():
		return {"ok": false, "reason": "context"}
	for key in ["plea", "point", "quest", "faction_deed", "operation", "march", "base", "megaproject"]:
		if p.has(key):
			return {"ok": false, "reason": "context"}
	for key in request:
		if str(key) not in META_KEYS and not empty_effect(request[key]):
			return {"ok": false, "reason": "mixed"}
	if str(request.get("work_kind", "")) not in ["", "military", "army", "recruitment", "personnel"]:
		return {"ok": false, "reason": "mixed"}
	var needs = request.get("needs", {})
	if not (needs is Dictionary):
		return {"ok": false, "reason": "mixed"}
	for key in needs:
		if str(key) != "money" and not empty_effect(needs[key]):
			return {"ok": false, "reason": "mixed"}
	var actions = request.get("detachments", [])
	if not (actions is Array) or actions.size() != 1 or not (actions[0] is Dictionary):
		return {"ok": false, "reason": "mixed"}
	var action: Dictionary = actions[0]
	var deed: String = str(action.get("action", ""))
	if deed not in ["create", "reinforce"]:
		return {"ok": false, "reason": "mixed"}
	for key in action:
		if str(key) not in ["action", "id", "name", "make_up", "description"] and not empty_effect(action[key]):
			if str(key) not in ["genus", "kind"] or str(action[key]) != "infantry":
				return {"ok": false, "reason": "mixed"}
	var makeup = action.get("make_up", {})
	if not (makeup is Dictionary):
		return {"ok": false, "reason": "count"}
	var count: int = 0
	for key in makeup:
		if str(key) not in ["fighters", "soldiers", "militiamen"]:
			if not empty_effect(makeup[key]):
				return {"ok": false, "reason": "mixed"}
			continue
		var amount: int = number(makeup[key])
		if amount < 0 or amount > 5000:
			return {"ok": false, "reason": "count"}
		count += amount
	if count <= 0 or count > 5000:
		return {"ok": false, "reason": "count"}
	var target_id: int = 0
	var name_text: String = str(action.get("name", "")).strip_edges()
	if deed == "reinforce":
		var place = p.get("place", {})
		target_id = number(action.get("id", 0))
		if target_id <= 0 and place is Dictionary:
			target_id = number(place.get("detachment", 0))
		if target_id <= 0 and not name_text.is_empty():
			for unit in runtime.model.armies.units:
				if unit is Dictionary and str(unit.get("name", "")).to_lower() == name_text.to_lower() and bool(unit.get("our", false)) and str(unit.get("whose", "")) == owner._last_game.country():
					if target_id > 0:
						return {"ok": false, "reason": "target"}
					target_id = int(unit.get("id", 0))
		var target: Dictionary = runtime.model.armies.unit(target_id)
		if target_id <= 0 or not Recruitment.valid_target(target, owner._last_game.country()):
			return {"ok": false, "reason": "target"}
		name_text = str(target.get("name", ""))
	elif name_text.is_empty():
		name_text = owner.tr_key("prigozhin_fork_native_recruit_name") % int(p.get("id", 0))
	if name_text.length() > 80:
		return {"ok": false, "reason": "target"}
	var duration: int = number(request.get("days", 0))
	if duration < 0 and not empty_effect(request.get("days")):
		return {"ok": false, "reason": "term"}
	var phases = request.get("phases", [])
	if not (phases is Array) and not empty_effect(phases):
		return {"ok": false, "reason": "term"}
	if phases is Array and not phases.is_empty():
		var phase_days: int = 0
		for phase in phases:
			if not (phase is Dictionary) or number(phase.get("days", 0)) < 0 or number(phase.get("days", 0)) > 3650:
				return {"ok": false, "reason": "term"}
			phase_days += number(phase.get("days", 0))
			if phase_days > 3650:
				return {"ok": false, "reason": "term"}
		if phase_days > 0:
			duration = phase_days
	if duration <= 0:
		duration = 14
	if duration > 3650:
		return {"ok": false, "reason": "term"}
	return {"ok": true, "name": name_text, "count": count, "target_id": target_id, "days": duration,
		"description": str(action.get("description", "")).left(400)}

static func reject(owner, p: Dictionary, reason: String) -> void:
	p["status"] = "impossible"
	p["request"] = {"understood": str(p.get("text", "")), "plausible": false, "needs": {}, "deltas": {},
		"why_not": owner.tr_key("prigozhin_fork_native_recruit_" + reason)}

static func application(owner, id: int) -> Dictionary:
	for entry in owner._pmc_recruitment:
		if entry is Dictionary and int(entry.get("id", 0)) == id:
			return entry
	return {}

# Main-thread confirmation/admission, before any native execution or money use.
static func confirm(owner, runtime, p: Dictionary) -> void:
	if not owner or not owner._last_game or owner._last_game.main != runtime or Pax.world_busy() or not p.has("prigozhin_fork_recruit_proposal") or str(p.get("status", "")) != "queued":
		return
	if not ready(runtime):
		reject(owner, p, "reload")
		return
	if int(p.get("prigozhin_fork_recruit_queue_id", 0)) > 0:
		return
	var request = p.get("prigozhin_fork_recruit_payload", {})
	var data: Dictionary = describe(owner, runtime, p, request if request is Dictionary else {})
	if not bool(data.get("ok", false)):
		reject(owner, p, str(data.get("reason", "mixed")))
		return
	var result: Dictionary = Recruitment.reserve(owner, owner._last_game, str(data["name"]), int(data["count"]), int(p.get("days", data["days"])), int(data["target_id"]), int(p.get("id", 0)))
	if not bool(result.get("ok", false)):
		reject(owner, p, "admission")
		return
	var entry: Dictionary = result["record"]
	entry["native_original"] = str(p.get("text", ""))
	entry["description"] = str(data.get("description", ""))
	p["prigozhin_fork_recruit_queue_id"] = int(entry["id"])
	owner._last_game.toast(owner.tr_key("prigozhin_fork_native_recruit_accepted") % int(entry["id"]))
	owner.call_deferred("_refresh_ui")

# Called by the native executor on the world thread. Only JSON state is changed;
# native hiring remains on the common queue's safe post-step boundary.
static func dispatch(owner, runtime, p: Dictionary) -> Dictionary:
	var base: Dictionary = {"id": p.get("id", 0), "order_cmd": str(p.get("text", "")), "body": str(p.get("body", ""))}
	p["prigozhin_fork_recruit_dispatch_failed"] = true
	if not owner or not owner._last_game or owner._last_game.main != runtime:
		base.merge({"state": "impossible", "why": Pax.tr_key("prigozhin_fork_native_recruit_unavailable")}, true)
		return base
	var entry: Dictionary = application(owner, int(p.get("prigozhin_fork_recruit_queue_id", 0)))
	var request = p.get("prigozhin_fork_recruit_payload", {})
	var data: Dictionary = describe(owner, runtime, p, request if request is Dictionary else {})
	if entry.is_empty() or not bool(data.get("ok", false)) or int(entry.get("native_order_id", 0)) != int(p.get("id", 0)) or str(entry.get("side", "")) != owner._last_game.country() or str(entry.get("native_original", "")) != str(p.get("text", "")) or int(entry.get("requested", 0)) != int(data.get("count", -1)) or int(entry.get("target_id", 0)) != int(data.get("target_id", -1)) or (int(entry.get("target_id", 0)) == 0 and str(entry.get("name", "")) != str(data.get("name", ""))):
		base.merge({"state": "impossible", "why": owner.tr_key("prigozhin_fork_native_recruit_changed")}, true)
		return base
	if str(entry.get("status", "")) not in ["pending", "blocked"] or bool(entry.get("native_uncertain", false)):
		base.merge({"state": "impossible", "why": owner.tr_key("prigozhin_fork_native_recruit_changed")}, true)
		return base
	entry["native_due"] = true
	p["prigozhin_fork_recruit_dispatch_failed"] = false
	owner.call_deferred("_finish_pmc_native_recruitment", owner._last_game)
	base.merge({"state": "under_way", "understood": owner.tr_key("prigozhin_fork_native_recruit_handoff") % int(entry["id"]),
		"remaining": owner.tr_key("prigozhin_fork_native_recruit_processing"), "done_percent": 0}, true)
	return base

static func synchronize(owner, game: PaxGame) -> void:
	if not owner or not game or owner._last_game != game or Pax.world_busy() or not is_instance_valid(game.main) or not game.main.model or not game.main.model.armies:
		return
	for entry in owner._pmc_recruitment:
		if entry is Dictionary and str(entry.get("status", "")) in ["pending", "blocked"] and int(entry.get("native_order_id", 0)) > 0 and not Recruitment.native_ticket_present(game, entry):
			entry["status"] = "cancelled"
			entry["reason"] = "native_cancelled"
	# Previously accepted orders must not bypass a pool installed later.
	var changed: bool = false
	for i in range(game.main.model.orders.size() - 1, -1, -1):
		var ticket = game.main.model.orders[i]
		if not (ticket is Dictionary) or int(ticket.get("prigozhin_fork_recruit_queue_id", 0)) <= 0:
			continue
		var entry: Dictionary = application(owner, int(ticket["prigozhin_fork_recruit_queue_id"]))
		if not entry.is_empty() and int(entry.get("native_order_id", 0)) == int(ticket.get("id", 0)) and str(ticket.get("text", "")) == str(entry.get("native_original", "")) and str(ticket.get("status", "")) in ["queued", "under_way"] and str(entry.get("status", "")) in ["complete", "partial", "cancelled", "archived", "reconciled"]:
			game.main.model.orders.remove_at(i)
			changed = true
	for p in game.main.model.orders:
		if not (p is Dictionary) or str(p.get("status", "")) not in ["queued", "under_way", "awaits_ok"]:
			continue
		var request = p.get("request", {})
		var place = p.get("place", {})
		if p.has("prigozhin_fork_recruit_proposal") and not ready(game.main):
			reject(owner, p, "reload")
			changed = true
			continue
		if request is Dictionary and candidate(game.main, request, place if place is Dictionary else {}) and (not p.has("prigozhin_fork_recruit_proposal") or not ready(game.main)):
			reject(owner, p, "role" if not game.main.player or str(game.main.player.player_role) not in ["person", "organization"] else "legacy")
			changed = true
	if changed:
		var show = game.main.show_queue()
		if show:
			show.orders_changed()
