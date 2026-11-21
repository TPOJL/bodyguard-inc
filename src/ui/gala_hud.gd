class_name GalaHud
extends CanvasLayer
## Sleek, Non-Intrusive AAA Broadcast HUD + Interactive Agency Upgrade Shop Overlay ([U]).
## Uses responsive anchors so nothing ever clips or blocks the center gameplay camera.

const AgencyProgressionLib := preload("res://src/core/agency_progression.gd")

signal upgrade_requested(upgrade_id: String)
signal shop_close_requested()
signal next_contract_requested()
signal restart_contract_requested()

var _top_title_lbl: Label = null
var _top_obj_lbl: Label = null
var _top_cash_lbl: Label = null
var _combo_toast_lbl: Label = null

var _vip_pill_lbl: Label = null
var _hp_bar: ProgressBar = null
var _susp_bar: ProgressBar = null
var _stamina_bar: ProgressBar = null
var _jaw_bar: ProgressBar = null
var _radio_lbl: Label = null
var _hotbar_lbl: Label = null

# Upgrade Shop Modal
var shop_panel: PanelContainer = null
var _shop_header_lbl: Label = null
var _shop_bank_lbl: Label = null
var _shop_buttons: Dictionary = {}
var _shop_action_btn: Button = null


func _ready() -> void:
	layer = 2
	_build_top_mission_strip()
	_build_bottom_left_vitals()
	_build_bottom_right_hotbar()
	_build_upgrade_shop_modal()


func set_shop_visible(is_open: bool, progression: AgencyProgressionLib, mission_ended: bool, was_victory: bool) -> void:
	if shop_panel == null:
		return
	shop_panel.visible = is_open
	if not is_open:
		return
	refresh_shop(progression, mission_ended, was_victory)


func refresh_shop(progression: AgencyProgressionLib, mission_ended: bool, was_victory: bool) -> void:
	if _shop_header_lbl == null or progression == null:
		return
	if mission_ended and was_victory:
		_shop_header_lbl.text = "🏆 CONTRACT COMPLETE — AGENCY ARMORY & UPGRADES"
		_shop_header_lbl.modulate = Color(0.32, 1.0, 0.62)
		_shop_action_btn.text = "▶ DEPLOY NIGHT %d CONTRACT (Higher Stakes & Payouts!)" % progression.contract_night
	elif mission_ended and not was_victory:
		_shop_header_lbl.text = "🚨 COVER BLOWN — UPGRADE GEAR & RETRY CONTRACT"
		_shop_header_lbl.modulate = Color(1.0, 0.35, 0.35)
		_shop_action_btn.text = "🔄 RETRY NIGHT %d CONTRACT [R]" % progression.contract_night
	else:
		_shop_header_lbl.text = "💼 BODYGUARD INC. ARMORY — SPEND FARMED CASH ([U] / ESC to Resume)"
		_shop_header_lbl.modulate = Color(1.0, 0.84, 0.32)
		_shop_action_btn.text = "▶ RESUME MISSION [U]"

	_shop_bank_lbl.text = (
		"AGENCY BANK: $%d   |   RANK: %s   |   CONTRACTS CLEARED: %d   |   CORPSE BLUFFS: %d   |   ASSASSINS KO: %d"
		% [
			progression.bank_cash,
			progression.get_agency_rank(),
			progression.total_contracts_cleared,
			progression.total_corpse_extractions,
			progression.total_assassins_ko,
		]
	)

	var idx: int = 1
	for entry: Dictionary in AgencyProgressionLib.UPGRADE_CATALOG:
		var uid: String = String(entry["id"])
		var btn: Button = _shop_buttons.get(uid, null)
		if btn == null:
			continue
		var lv: int = progression.get_level(uid)
		var cost: int = progression.get_upgrade_cost(uid)
		if lv >= AgencyProgressionLib.MAX_UPGRADE_LEVEL:
			btn.text = "[%d] %s (MAX Lv 5) — %s" % [idx, String(entry["name"]), String(entry["desc"])]
			btn.disabled = true
		else:
			btn.text = "[%d] %s (Lv %d/5) — $%d  |  %s" % [idx, String(entry["name"]), lv, cost, String(entry["desc"])]
			btn.disabled = not progression.can_purchase(uid)
		idx += 1


func update_hud_state(state_data: Dictionary) -> void:
	if _top_title_lbl == null:
		return
	_top_title_lbl.text = String(state_data["title"])
	_top_obj_lbl.text = String(state_data["objective"])
	_top_cash_lbl.text = String(state_data["cash_line"])

	var toast: String = String(state_data["toast"])
	_combo_toast_lbl.visible = (toast != "")
	_combo_toast_lbl.text = toast

	_vip_pill_lbl.text = String(state_data["vip_pill"])
	_vip_pill_lbl.modulate = state_data["vip_pill_color"]

	_hp_bar.max_value = float(state_data["vip_max_hp"])
	_hp_bar.value = float(state_data["vip_hp"])
	_susp_bar.value = float(state_data["suspicion"])
	_stamina_bar.value = float(state_data["stamina"])
	_jaw_bar.value = float(state_data["jaw_deg"])

	_radio_lbl.text = String(state_data["radio"])
	_hotbar_lbl.text = String(state_data["hotbar"])


func _make_card_style(border_col: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.085, 0.82)
	s.border_color = border_col
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s


func _build_top_mission_strip() -> void:
	var top_panel: PanelContainer = PanelContainer.new()
	top_panel.anchor_left = 0.02
	top_panel.anchor_right = 0.98
	top_panel.anchor_top = 0.015
	top_panel.anchor_bottom = 0.015
	top_panel.offset_bottom = 66.0
	top_panel.add_theme_stylebox_override("panel", _make_card_style(Color(0.86, 0.68, 0.28, 0.75)))
	add_child(top_panel)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	top_panel.add_child(hbox)

	var left_v: VBoxContainer = VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_v)

	_top_title_lbl = Label.new()
	_top_title_lbl.add_theme_font_size_override("font_size", 15)
	_top_title_lbl.modulate = Color(0.95, 0.80, 0.35)
	left_v.add_child(_top_title_lbl)

	_top_obj_lbl = Label.new()
	_top_obj_lbl.add_theme_font_size_override("font_size", 14)
	_top_obj_lbl.modulate = Color(0.92, 0.96, 1.0)
	left_v.add_child(_top_obj_lbl)

	_top_cash_lbl = Label.new()
	_top_cash_lbl.add_theme_font_size_override("font_size", 16)
	_top_cash_lbl.modulate = Color(0.35, 1.0, 0.62)
	_top_cash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(_top_cash_lbl)

	# Slim floating event/combo toast right below top bar
	_combo_toast_lbl = Label.new()
	_combo_toast_lbl.anchor_left = 0.15
	_combo_toast_lbl.anchor_right = 0.85
	_combo_toast_lbl.anchor_top = 0.015
	_combo_toast_lbl.offset_top = 74.0
	_combo_toast_lbl.offset_bottom = 102.0
	_combo_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_toast_lbl.add_theme_font_size_override("font_size", 16)
	_combo_toast_lbl.modulate = Color(1.0, 0.92, 0.42)
	add_child(_combo_toast_lbl)


func _build_bottom_left_vitals() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.02
	panel.anchor_right = 0.02
	panel.anchor_top = 0.985
	panel.anchor_bottom = 0.985
	panel.offset_top = -164.0
	panel.offset_right = 455.0
	panel.add_theme_stylebox_override("panel", _make_card_style(Color(0.32, 0.72, 0.95, 0.65)))
	add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)

	_vip_pill_lbl = Label.new()
	_vip_pill_lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(_vip_pill_lbl)

	_hp_bar = _make_bar_row(vb, "VIP HP", Color(0.22, 0.88, 0.46), 100.0)
	_susp_bar = _make_bar_row(vb, "SUSPICION", Color(0.95, 0.24, 0.24), 100.0)
	_stamina_bar = _make_bar_row(vb, "STAMINA", Color(0.96, 0.76, 0.24), 100.0)
	_jaw_bar = _make_bar_row(vb, "VOICE JAW", Color(0.28, 0.85, 1.0), 42.0)

	_radio_lbl = Label.new()
	_radio_lbl.add_theme_font_size_override("font_size", 12)
	_radio_lbl.modulate = Color(1.0, 0.88, 0.45)
	_radio_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_radio_lbl)


func _build_bottom_right_hotbar() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.98
	panel.anchor_right = 0.98
	panel.anchor_top = 0.985
	panel.anchor_bottom = 0.985
	panel.offset_left = -540.0
	panel.offset_top = -84.0
	panel.add_theme_stylebox_override("panel", _make_card_style(Color(0.86, 0.68, 0.28, 0.60)))
	add_child(panel)

	_hotbar_lbl = Label.new()
	_hotbar_lbl.add_theme_font_size_override("font_size", 12)
	_hotbar_lbl.modulate = Color(0.84, 0.92, 1.0)
	_hotbar_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_hotbar_lbl)


func _build_upgrade_shop_modal() -> void:
	shop_panel = PanelContainer.new()
	shop_panel.anchor_left = 0.14
	shop_panel.anchor_right = 0.86
	shop_panel.anchor_top = 0.14
	shop_panel.anchor_bottom = 0.86
	shop_panel.add_theme_stylebox_override("panel", _make_card_style(Color(1.0, 0.82, 0.28, 0.95)))
	shop_panel.visible = false
	add_child(shop_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	shop_panel.add_child(vb)

	_shop_header_lbl = Label.new()
	_shop_header_lbl.add_theme_font_size_override("font_size", 21)
	_shop_header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_shop_header_lbl)

	_shop_bank_lbl = Label.new()
	_shop_bank_lbl.add_theme_font_size_override("font_size", 14)
	_shop_bank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_bank_lbl.modulate = Color(0.35, 1.0, 0.62)
	vb.add_child(_shop_bank_lbl)

	for entry: Dictionary in AgencyProgressionLib.UPGRADE_CATALOG:
		var uid: String = String(entry["id"])
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(0.0, 44.0)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_upgrade_btn_pressed.bind(uid))
		vb.add_child(btn)
		_shop_buttons[uid] = btn

	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 18)
	vb.add_child(footer)

	_shop_action_btn = Button.new()
	_shop_action_btn.custom_minimum_size = Vector2(360.0, 46.0)
	_shop_action_btn.pressed.connect(_on_shop_action_pressed)
	footer.add_child(_shop_action_btn)

	var close_btn: Button = Button.new()
	close_btn.text = "Close [U]"
	close_btn.custom_minimum_size = Vector2(120.0, 46.0)
	close_btn.pressed.connect(func() -> void: shop_close_requested.emit())
	footer.add_child(close_btn)


func _on_upgrade_btn_pressed(uid: String) -> void:
	upgrade_requested.emit(uid)


func _on_shop_action_pressed() -> void:
	if _shop_action_btn.text.contains("DEPLOY NIGHT"):
		next_contract_requested.emit()
	elif _shop_action_btn.text.contains("RETRY"):
		restart_contract_requested.emit()
	else:
		shop_close_requested.emit()


func _make_bar_row(parent: VBoxContainer, label_txt: String, col: Color, max_v: float) -> ProgressBar:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	parent.add_child(hb)

	var lbl: Label = Label.new()
	lbl.text = label_txt
	lbl.custom_minimum_size = Vector2(88.0, 0.0)
	lbl.add_theme_font_size_override("font_size", 12)
	hb.add_child(lbl)

	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = max_v
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(220.0, 15.0)
	bar.show_percentage = false
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.11, 0.16)
	bg.set_corner_radius_all(4)
	var fg: StyleBoxFlat = StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	hb.add_child(bar)
	return bar
