extends Label

const Sources = preload("res://mods/prigozhin_fork/systems/pmc_recruit_sources.gd")
const Bridge = preload("res://mods/prigozhin_fork/systems/pmc_order_bridge.gd")

func configure(owner, game: PaxGame, target_id: int = 0) -> void:
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_color_override("font_color", Color(0.65, 0.78, 0.88))
	var state: Dictionary = Sources.snapshot(owner, game, target_id)
	if not bool(state.get("ok", false)):
		var reason: String = str(state.get("reason", "source_unavailable"))
		text = owner.tr_key("prigozhin_fork_recruit_queue_role") if reason == "unsupported_role" else owner.tr_key("prigozhin_fork_recruit_" + (reason if reason in ["source_not_ready", "source_unavailable", "source_review"] else "source_unavailable"))
		return
	var held: int = Sources.reserved(owner, game, str(state["source_country"]))
	var available: int = maxi(0, int(state["reserve"]) - held)
	text = owner.tr_key("prigozhin_fork_recruit_source_status") % [str(state["place"]), str(state["source_country"]), available, held, int(state["consumed"])]
	if int(state.get("uncertain_used", 0)) > 0:
		text += "\n" + (owner.tr_key("prigozhin_fork_recruit_source_uncertain_debit") % int(state["uncertain_used"]))
	if target_id == 0:
		var config: Dictionary = state["rules"]
		text += "\n" + (owner.tr_key("prigozhin_fork_recruit_source_rules") % [int(config["initial_candidates"]), int(config["candidates_per_period"]), int(config["period_days"]), int(config["max_waiting_candidates"])])
		text += "\n" + owner.tr_key("prigozhin_fork_native_recruit_active" if Bridge.ready(game.main) else "prigozhin_fork_native_recruit_reload")
