extends RefCounted

# Scope only requests originating from this mod's unit cards. The game hook
# supplies text rather than the order ID, so ambiguous concurrent text fails closed.
static func apply(owner, data: Dictionary) -> void:
	if not owner or not owner._last_game or not is_instance_valid(owner._last_game.main):
		return
	var runtime: Node = owner._last_game.main
	if not runtime.model or not runtime.model.armies:
		return
	var text: String = str(data.get("order", ""))
	var unit_id: int = 0
	var marked: bool = false
	var unmarked: bool = false
	for order in runtime.model.orders:
		if not (order is Dictionary) or str(order.get("status", "")) != "being_weighed" or str(order.get("text", "")) != text:
			continue
		var place = order.get("place", {})
		if not (place is Dictionary) or not bool(place.get("prigozhin_fork_unit_card", false)):
			unmarked = true
			continue
		marked = true
		var candidate: int = int(place.get("detachment", 0))
		if candidate <= 0 or (unit_id > 0 and unit_id != candidate):
			data["cancel"] = true
			data["reason"] = owner.tr_key("prigozhin_fork_unit_order_guard")
			return
		unit_id = candidate
	if not marked:
		return
	if unmarked or unit_id <= 0:
		data["cancel"] = true
		data["reason"] = owner.tr_key("prigozhin_fork_unit_order_guard")
		return
	var army = runtime.model.armies
	var same_id: int = 0
	for candidate_unit in army.units:
		if candidate_unit is Dictionary and int(candidate_unit.get("id", 0)) == unit_id:
			same_id += 1
	if same_id != 1:
		data["cancel"] = true
		data["reason"] = owner.tr_key("prigozhin_fork_unit_order_guard")
		return
	var unit: Dictionary = army.unit(unit_id)
	if unit.is_empty() or not army.units.has(unit) or not bool(unit.get("our", false)) or str(unit.get("whose", "")) != owner._last_game.country():
		data["cancel"] = true
		data["reason"] = owner.tr_key("prigozhin_fork_unit_order_guard")
		return
	var request = data.get("request", {})
	if not (request is Dictionary) or not request.has("detachments"):
		return
	var detachments = request["detachments"]
	if not (detachments is Array):
		data["cancel"] = true
		data["reason"] = owner.tr_key("prigozhin_fork_unit_order_guard")
		return
	for action in detachments:
		if not (action is Dictionary) or str(action.get("action", "")) == "create":
			data["cancel"] = true
			data["reason"] = owner.tr_key("prigozhin_fork_unit_order_guard")
			return
		action["id"] = unit_id
		# Early march resolves a name before place.detachment. Leaving a name
		# here could select a different unit with the same name.
		action.erase("name")
