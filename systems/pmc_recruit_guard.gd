extends RefCounted

const RecruitBridge = preload("res://mods/prigozhin_fork/systems/pmc_order_bridge.gd")

# Fail closed for ordinary armed hiring until the coordinated services are
# active. The HQ queue is independent and remains available in a loaded party.
static func apply(owner, data: Dictionary) -> void:
    if not owner or not owner._last_game or not is_instance_valid(owner._last_game.main):
        return
    var runtime: Node = owner._last_game.main
    var request = data.get("request", {})
    if not (request is Dictionary) or not runtime.model or not runtime.model.armies:
        return
    if RecruitBridge.candidate(runtime, request) and (not runtime.player or str(runtime.player.player_role) not in ["person", "organization"] or not RecruitBridge.ready(runtime)):
        data["cancel"] = true
        data["reason"] = owner.tr_key("prigozhin_fork_native_recruit_role" if not runtime.player or str(runtime.player.player_role) not in ["person", "organization"] else "prigozhin_fork_native_recruit_reload")
