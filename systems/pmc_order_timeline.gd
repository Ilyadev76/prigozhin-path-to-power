extends "res://src/sim/RewindSystem.gd"

const RecruitBridge = preload("res://mods/prigozhin_fork/systems/pmc_order_bridge.gd")

func prigozhin_fork_recruit_bridge_version() -> int:
	return 1

# Preserve a managed ticket while its actual queue result is pending. Native
# cancellation and start_after dependencies then retain their ordinary meaning.
func _order_status_report(p: Dictionary, deeds_by_body: Dictionary, remaining: Array, reports: Array, days):
	var result = super._order_status_report(p, deeds_by_body, remaining, reports, days)
	if int(p.get("prigozhin_fork_recruit_queue_id", 0)) <= 0 or bool(p.get("prigozhin_fork_recruit_dispatch_failed", false)) or str(p.get("status", "")) not in ["queued", "under_way"]:
		return result
	var owner = Pax.get_mod("prigozhin_fork")
	if not owner:
		return result
	var entry: Dictionary = RecruitBridge.application(owner, int(p["prigozhin_fork_recruit_queue_id"]))
	if not entry.is_empty() and bool(entry.get("native_due", false)) and str(entry.get("status", "")) in ["pending", "blocked"]:
		p["status"] = "under_way"
		p["request"]["understood"] = owner.tr_key("prigozhin_fork_native_recruit_pending_summary") % int(entry["id"])
		if not remaining.has(p):
			remaining.append(p)
	return result
