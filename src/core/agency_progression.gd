class_name AgencyProgression
extends RefCounted
## Persistent Agency Bank, Farming Economy, 6 Upgrade Trees (Lv 0..5) & Night Escalation.
## Deterministic in `--headless` test mode (skips disk I/O when headless).

const SAVE_PATH: String = "user://bodyguard_inc_save.json"
const MAX_UPGRADE_LEVEL: int = 5

const UPGRADE_CATALOG: Array[Dictionary] = [
	{
		"id": "exo_grip",
		"name": "Exo-Grip Servos",
		"desc": "+12% Carry Speed & +0.35m Grab Reach per level",
		"base_cost": 1200,
		"cost_step": 900,
	},
	{
		"id": "cardio",
		"name": "Kevlar Cardio",
		"desc": "+12% Sprint Speed & +20% Stamina Regen per level",
		"base_cost": 1000,
		"cost_step": 800,
	},
	{
		"id": "voice_mod",
		"name": "Ventriloquist Modulator",
		"desc": "+25% Voice Bluff [V] Drain & -12% Guard Suspicion Gain",
		"base_cost": 1500,
		"cost_step": 1100,
	},
	{
		"id": "utility_belt",
		"name": "Tactical Utility Belt",
		"desc": "+1 Max Decoy Bottle [Q] & +1.2s Distraction Duration",
		"base_cost": 1400,
		"cost_step": 1000,
	},
	{
		"id": "vip_kevlar",
		"name": "VIP Kevlar Tuxedo",
		"desc": "+35 VIP Max HP & -8% Suicidal Wander Speed",
		"base_cost": 1800,
		"cost_step": 1200,
	},
	{
		"id": "stun_baton",
		"name": "Shock Taser [G]",
		"desc": "+1.2s Assassin/Guard Stun & Faster Taser Cooldown",
		"base_cost": 1600,
		"cost_step": 1150,
	},
]

var bank_cash: int = 0
var contract_night: int = 1
var total_contracts_cleared: int = 0
var total_corpse_extractions: int = 0
var total_assassins_ko: int = 0
var upgrade_levels: Dictionary = {
	"exo_grip": 0,
	"cardio": 0,
	"voice_mod": 0,
	"utility_belt": 0,
	"vip_kevlar": 0,
	"stun_baton": 0,
}


func get_level(upgrade_id: String) -> int:
	return int(upgrade_levels.get(upgrade_id, 0))


func get_upgrade_cost(upgrade_id: String) -> int:
	var lv: int = get_level(upgrade_id)
	for entry: Dictionary in UPGRADE_CATALOG:
		if String(entry["id"]) == upgrade_id:
			return int(entry["base_cost"]) + lv * int(entry["cost_step"])
	return 99999


func can_purchase(upgrade_id: String) -> bool:
	var lv: int = get_level(upgrade_id)
	if lv >= MAX_UPGRADE_LEVEL:
		return false
	return bank_cash >= get_upgrade_cost(upgrade_id)


func purchase_upgrade(upgrade_id: String) -> bool:
	if not can_purchase(upgrade_id):
		return false
	var cost: int = get_upgrade_cost(upgrade_id)
	bank_cash -= cost
	upgrade_levels[upgrade_id] = get_level(upgrade_id) + 1
	save_to_disk()
	return true


func add_cash(amount: int) -> void:
	if amount > 0:
		bank_cash += amount


func record_contract_victory(was_corpse: bool) -> int:
	var base_payout: int = 4500 + (contract_night - 1) * 1800
	var style_bonus: int = 3500 if was_corpse else 2500
	var total_award: int = base_payout + style_bonus
	bank_cash += total_award
	total_contracts_cleared += 1
	if was_corpse:
		total_corpse_extractions += 1
	contract_night += 1
	save_to_disk()
	return total_award


func get_agency_rank() -> String:
	if total_contracts_cleared >= 8:
		return "SHADOW DIRECTOR"
	if total_contracts_cleared >= 5:
		return "EXECUTIVE PROTECTOR"
	if total_contracts_cleared >= 3:
		return "SENIOR AGENT"
	if total_contracts_cleared >= 1:
		return "FIELD BODYGUARD"
	return "ROOKIE INTERN"


func get_carry_speed_multiplier() -> float:
	return 1.0 + float(get_level("exo_grip")) * 0.12


func get_grab_range_bonus() -> float:
	return float(get_level("exo_grip")) * 0.35


func get_sprint_speed_multiplier() -> float:
	return 1.0 + float(get_level("cardio")) * 0.12


func get_stamina_regen_multiplier() -> float:
	return 1.0 + float(get_level("cardio")) * 0.20


func get_voice_bluff_multiplier() -> float:
	return 1.0 + float(get_level("voice_mod")) * 0.25


func get_suspicion_gain_multiplier() -> float:
	return maxf(0.40, 1.0 - float(get_level("voice_mod")) * 0.12)


func get_max_decoy_bottles() -> int:
	return 3 + get_level("utility_belt")


func get_decoy_duration_sec() -> float:
	return 5.0 + float(get_level("utility_belt")) * 1.2


func get_vip_max_hp() -> float:
	return 100.0 + float(get_level("vip_kevlar")) * 35.0


func get_vip_wander_multiplier() -> float:
	return maxf(0.55, 1.0 - float(get_level("vip_kevlar")) * 0.08)


func get_taser_stun_duration() -> float:
	return 3.5 + float(get_level("stun_baton")) * 1.2


func get_taser_cooldown() -> float:
	return maxf(2.0, 5.5 - float(get_level("stun_baton")) * 0.65)


func save_to_disk() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var payload: Dictionary = {
		"bank_cash": bank_cash,
		"contract_night": contract_night,
		"total_contracts_cleared": total_contracts_cleared,
		"total_corpse_extractions": total_corpse_extractions,
		"total_assassins_ko": total_assassins_ko,
		"upgrade_levels": upgrade_levels,
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()


func load_from_disk() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	bank_cash = int(data.get("bank_cash", 0))
	contract_night = maxi(1, int(data.get("contract_night", 1)))
	total_contracts_cleared = int(data.get("total_contracts_cleared", 0))
	total_corpse_extractions = int(data.get("total_corpse_extractions", 0))
	total_assassins_ko = int(data.get("total_assassins_ko", 0))
	var saved_ups: Variant = data.get("upgrade_levels", {})
	if typeof(saved_ups) == TYPE_DICTIONARY:
		var ups_dict: Dictionary = saved_ups
		for k: Variant in upgrade_levels.keys():
			var ks: String = String(k)
			if ups_dict.has(ks):
				upgrade_levels[ks] = clampi(int(ups_dict[ks]), 0, MAX_UPGRADE_LEVEL)
