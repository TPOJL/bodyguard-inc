class_name LevelThemes
extends RefCounted
## Defines 5 escalating high-style venues (and endless Prestige scaling after Level 5).
## Each level shifts architectural palette, sky mood, enemy HP scaling, and contract payouts.


static func get_level_config(level_num: int) -> Dictionary:
	var lv: int = maxi(1, level_num)
	var theme_idx: int = (lv - 1) % 5
	var prestige_tier: int = int((lv - 1) / 5)

	var themes: Array[Dictionary] = [
		{
			"venue_name": "THE OBSIDIAN PENTHOUSE GALA",
			"carpet_color": Color(0.54, 0.06, 0.12),
			"marble_tint": Color(0.20, 0.22, 0.29),
			"accent_color": Color(0.92, 0.74, 0.28),
			"sky_top": Color(0.035, 0.055, 0.13),
			"sky_horizon": Color(0.20, 0.16, 0.26),
			"key_color": Color(0.88, 0.92, 1.0),
			"rim_color": Color(1.0, 0.82, 0.58),
		},
		{
			"venue_name": "NEON TOKYO SKY-LOUNGE",
			"carpet_color": Color(0.42, 0.08, 0.48),
			"marble_tint": Color(0.14, 0.18, 0.28),
			"accent_color": Color(0.18, 0.90, 1.0),
			"sky_top": Color(0.04, 0.02, 0.12),
			"sky_horizon": Color(0.28, 0.10, 0.30),
			"key_color": Color(0.78, 0.94, 1.0),
			"rim_color": Color(1.0, 0.42, 0.85),
		},
		{
			"venue_name": "MONACO CASINO ROYALE",
			"carpet_color": Color(0.07, 0.36, 0.20),
			"marble_tint": Color(0.22, 0.20, 0.18),
			"accent_color": Color(1.0, 0.80, 0.22),
			"sky_top": Color(0.03, 0.07, 0.11),
			"sky_horizon": Color(0.24, 0.20, 0.14),
			"key_color": Color(1.0, 0.96, 0.86),
			"rim_color": Color(0.95, 0.78, 0.36),
		},
		{
			"venue_name": "ALPINE ICE PALACE SUMMIT",
			"carpet_color": Color(0.10, 0.24, 0.48),
			"marble_tint": Color(0.26, 0.32, 0.42),
			"accent_color": Color(0.45, 0.92, 1.0),
			"sky_top": Color(0.05, 0.10, 0.20),
			"sky_horizon": Color(0.22, 0.34, 0.46),
			"key_color": Color(0.86, 0.96, 1.0),
			"rim_color": Color(0.55, 0.85, 1.0),
		},
		{
			"venue_name": "ORBITAL BILLIONAIRE YACHT",
			"carpet_color": Color(0.28, 0.10, 0.36),
			"marble_tint": Color(0.16, 0.16, 0.24),
			"accent_color": Color(1.0, 0.56, 0.22),
			"sky_top": Color(0.02, 0.02, 0.07),
			"sky_horizon": Color(0.24, 0.14, 0.22),
			"key_color": Color(0.94, 0.92, 1.0),
			"rim_color": Color(1.0, 0.68, 0.35),
		},
	]

	var cfg: Dictionary = themes[theme_idx].duplicate()
	var prestige_tag: String = (" [PRESTIGE +%d]" % prestige_tier) if prestige_tier > 0 else ""
	cfg["level_num"] = lv
	cfg["display_name"] = "LVL %d: %s%s" % [lv, String(cfg["venue_name"]), prestige_tag]
	# Enemy HP & speed escalate sharply across levels so weapon upgrades feel vital!
	cfg["guard_max_hp"] = 100.0 + float(lv - 1) * 65.0
	cfg["assassin_max_hp"] = 140.0 + float(lv - 1) * 90.0
	cfg["enemy_speed_mult"] = minf(1.85, 1.0 + float(lv - 1) * 0.10)
	cfg["payout_bonus"] = (lv - 1) * 2000
	return cfg
