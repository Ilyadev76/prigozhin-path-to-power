extends RefCounted

const Native = preload("res://mods/prigozhin_fork/systems/native_supply_contracts.gd")
const GOODS = ["water", "food", "fuel", "medicine", "materials", "ammunition"]

static func ready(owner, game: PaxGame) -> bool:
	return owner != null and game != null and owner._last_game == game and not Pax.world_busy() and is_instance_valid(game.main) and game.main.model != null and not game.main.rewind_state.rewinding

# The native offer decides whether a real counterparty is willing to sell.
# The quote reserves neither stock nor money and must be checked at confirmation.
static func quote(owner, game: PaxGame, partner: String, key: String, quantity: float, months: int) -> Dictionary:
	if not ready(owner, game):
		return {"ok": false, "reason": "busy"}
	if key not in GOODS or partner.is_empty() or partner == game.country() or not is_finite(quantity) or quantity <= 0.0 or months < 1 or months > 120:
		return {"ok": false, "reason": "terms"}
	if not game.main.model.resources.stock(game.home_body()).has(key):
		return {"ok": false, "reason": "resource"}
	var offer: Dictionary = Native.offer(game.main, partner, key)
	if not bool(offer.get("want", false)):
		return {"ok": false, "reason": "refused", "why": str(offer.get("why", ""))}
	var price: float = float(offer.get("price", 0.0))
	var cap: float = float(offer.get("will_give", 0.0))
	if not is_finite(price) or not is_finite(cap) or price <= 0.0 or cap <= 0.0:
		return {"ok": false, "reason": "terms"}
	var amount: float = minf(quantity, cap)
	if not is_finite(amount * price):
		return {"ok": false, "reason": "terms"}
	return {"ok": true, "side": game.country(), "body": game.home_body(), "partner": partner, "key": key, "amount": amount, "price": price, "months": months, "monthly_cost": amount * price, "first_day": game.day() + 30}

static func confirm(owner, game: PaxGame, expected: Dictionary) -> Dictionary:
	var fresh: Dictionary = quote(owner, game, str(expected.get("partner", "")), str(expected.get("key", "")), float(expected.get("amount", 0.0)), int(expected.get("months", 0)))
	if not bool(fresh.get("ok", false)):
		return fresh
	for key in ["side", "body", "partner", "key", "amount", "price", "months", "monthly_cost", "first_day"]:
		if fresh.get(key) != expected.get(key):
			return {"ok": false, "reason": "changed"}
	for record in game.main.model.supplies:
		if record is Dictionary and str(record.get("dir", "sell")) == "buy" and str(record.get("recipient", "")) == str(fresh["partner"]) and str(record.get("key", "")) == str(fresh["key"]):
			return {"ok": false, "reason": "duplicate"}
	var result: Dictionary = Native.create(game.main, "buy", str(fresh["partner"]), str(fresh["key"]), float(fresh["amount"]), int(fresh["months"]))
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": "refused", "why": str(result.get("why", ""))}
	var record: Dictionary = result["record"]
	record["prigozhin_fork_supply_id"] = "%s:%d:%d" % [game.country(), game.day(), Time.get_ticks_usec()]
	record["prigozhin_fork_supply_side"] = game.country()
	return {"ok": true}

# The stable token is resolved immediately before cancellation; array indexes
# captured by the UI are never used after the world has changed.
static func cancel(owner, game: PaxGame, token: String) -> bool:
	if not ready(owner, game) or token.is_empty():
		return false
	for index in range(game.main.model.supplies.size()):
		var record = game.main.model.supplies[index]
		if record is Dictionary and str(record.get("prigozhin_fork_supply_id", "")) == token and str(record.get("prigozhin_fork_supply_side", "")) == game.country():
			Native.cancel(game.main, index)
			return true
	return false
