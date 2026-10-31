extends RefCounted

# PaxGame has no order-submission method; this adapter uses its documented
# raw Main access until the facade exposes one. Keep engine internals here.
static func send(game: PaxGame, text_order: String, _pre_days: int = 2, place: Dictionary = {}) -> bool:
	if game == null or text_order.strip_edges().is_empty():
		return false
	var runtime: Node = game.main
	if runtime == null or not runtime.has_method("order_evaluation"):
		return false
	var body_name: String = str(runtime._where_to_order())
	if body_name.is_empty():
		return false
	var evaluator: Object = runtime.order_evaluation()
	if evaluator == null:
		return false
	var accepted: bool = bool(evaluator.charge(body_name, text_order, place))
	if not accepted:
		return false
	# charge() owns IDs, validation, AI evaluation and deferred/network orders.
	# Never fabricate entries or bypass a rejected native order.
	runtime.ui.orders_window.visible = true
	runtime.orders_panel().refresh_orders()
	return true
