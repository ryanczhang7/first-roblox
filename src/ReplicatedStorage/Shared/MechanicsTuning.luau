--!strict
--[[
	The instance, channel and actuation constants, per TUNE-001.

	`docs/wiki/game/tuning.md` IS THE SPECIFICATION; this module is source. If a
	value here and a value there disagree, that is a defect to raise with the
	Lead PO rather than to fix by editing either side.
	`tests/shared/mechanics_tuning_spec_test.luau` is the guard: it parses §2, §3
	and §4 off disk and compares them to this module by name, in both
	directions. Keys are the specification's own snake_case names, verbatim.

	SCOPE is `tuning.md` §2 (the instance, including "The layout") -> `instance`,
	§3 (the channel) -> `channel`, and §4 (actuation and instability, including
	"What the HUD shows of the round") -> `actuation`. §1 and §5 live in
	`Tuning.luau` (architecture.md D19: a second module, so ROUND-002's guard on
	`Tuning` stays exact). §6 is not here.

	ABSENT ON PURPOSE. The document's rule rows are rules, not constants, and
	the guard requires them absent: `key_classes`, `actuators_per_class`,
	`spawn_room` (§2), `channel_limiter_consumed_by`, `ping_budget_per_player`
	(§3), `blackout_selection`, `hud_round_clock_form` (§4). Each is implemented
	by the mechanic that applies it.

	REFERENCE ROWS. Where the document says `= other_name`, the value is written
	out here, with a comment naming the referent. The guard, not this module,
	proves each equals its referent's value.

	LABELS. Each comment carries the document's label - derived, taste or
	placeholder - so that a reader of this file knows which values a playtest
	may move. The rationale is in the document; it is not repeated here.

	FREEZING. `table.freeze` is applied to each of the three tables AND to the
	module table, as in `Tuning.luau`.
]]

export type InstanceTuning = {
	-- §2, main table
	room_count: number,
	actuator_count: number,
	actuator_redundancy: number,
	procedure_length: number,
	procedure_tracks: number,
	steps_per_track: number,
	finale_paired_ops: number,
	machines_per_class_max: number,
	procedure_length_depends_on_n: boolean,
	tag_alphabet_size: number,
	dial_settings: number,
	turn_cue_lookahead: number,
	progress_bar_segments: number,
	progress_bar_split_by_track: boolean,
	progress_bar_marks_finale: boolean,
	lens_read_range_studs: number,
	simultaneous_window_seconds: number,
	paired_room_distance_min: number,
	room_traversal_seconds: number,
	schedule_slack: number,
	par_ping_seconds: number,
	par_turn_seconds: number,
	trace_headline_min_wait_seconds: number,
	generator_attempts_max: number,
	-- §2, "The layout"
	layout_grid_columns: number,
	layout_grid_rows: number,
	layout_loop_door_chance: number,
	room_pitch_studs: number,
	room_footprint_studs: number,
	room_ceiling_studs: number,
	doorway_width_studs: number,
	doorway_height_studs: number,
	machine_slots_per_room: number,
	machines_per_room_min: number,
	machines_per_room_max: number,
	machine_spacing_min_studs: number,
	walk_speed_studs_per_second: number,
	turn_range_studs: number,
	partner_lamp_range_studs: number,
	trace_position_sample_seconds: number,
}

export type ChannelTuning = {
	presets_plus_pings_max: number,
	preset_count: number,
	ping_kinds: number,
	preset_rate_limit_seconds: number,
	preset_display_seconds: number,
	preset_reveals_sender: boolean,
	preset_reveals_sender_position: boolean,
	ping_rate_limit_seconds: number,
	ping_display_seconds: number,
	active_pings_per_player: number,
	ping_range_studs: number,
	ping_reveals_sender: boolean,
	ping_settings_live_only: boolean,
	channel_attempt_min_interval_seconds: number,
}

export type ActuationTuning = {
	-- §4, main table
	actuation_reset_seconds: number,
	actuation_failure_is_diagnostic: boolean,
	instability_max: number,
	instability_per_wrong_value: number,
	instability_per_out_of_order: number,
	instability_per_failed_pair: number,
	instability_clock_penalty_seconds: number,
	instability_blackout_threshold: number,
	blackout_rooms_per_threshold: number,
	blackout_permanent: boolean,
	blackout_weight_live_step: number,
	blackout_weight_waiting_step: number,
	blackout_repeat_allowed: boolean,
	turn_rate_limit_seconds: number,
	finale_live_together: boolean,
	-- §4, "What the HUD shows of the round"
	hud_shows_round_clock: boolean,
	hud_clock_separate_from_progress: boolean,
	hud_shows_instability: boolean,
	hud_marks_blackout_thresholds: boolean,
}

export type MechanicsTuning = {
	instance: InstanceTuning,
	channel: ChannelTuning,
	actuation: ActuationTuning,
}

-- `tuning.md` §2. The instance.
local instance: InstanceTuning = table.freeze({
	room_count = 6, -- placeholder: replace when players never leave a room, or walk aimlessly
	actuator_count = 16, -- derived: procedure_length × actuator_redundancy
	actuator_redundancy = 2, -- placeholder: one decoy per step; replace on decoy mis-turns
	procedure_length = 8, -- placeholder: tune together with Tuning.round.round_seconds
	procedure_tracks = 2, -- derived: the minimum at which turner and helper overlap
	steps_per_track = 4, -- derived: procedure_length / procedure_tracks
	finale_paired_ops = 1, -- derived: one paired operation joins the tracks
	machines_per_class_max = 4, -- derived: ceil(procedure_length / players_min) × actuator_redundancy
	procedure_length_depends_on_n = false, -- derived (G3): throughput is bounded by tracks
	tag_alphabet_size = 4, -- derived (G4): = machines_per_class_max
	dial_settings = 4, -- placeholder: guessing a real choice; playtest P-G
	turn_cue_lookahead = 1, -- taste (operator, 2026-09-30, T10)
	progress_bar_segments = 8, -- derived: = procedure_length
	progress_bar_split_by_track = false, -- derived: the operator rejected T10 (b)
	progress_bar_marks_finale = true, -- derived: the finale is the last commits by construction
	lens_read_range_studs = 12, -- placeholder: replace from the M3 slice
	simultaneous_window_seconds = 5, -- placeholder: the finale window
	paired_room_distance_min = 2, -- derived: at 1, one player could sprint between them
	room_traversal_seconds = 8, -- placeholder: replace with the measured median edge time
	schedule_slack = 1.5, -- placeholder: INV_traversal's slack; replace via win_rate_target
	par_ping_seconds = 10, -- derived (G6): one full rate-limit interval per step
	par_turn_seconds = 3, -- placeholder (G6): replace with the measured median turn time
	trace_headline_min_wait_seconds = 8, -- derived (Q-G6): = room_traversal_seconds
	generator_attempts_max = 64, -- placeholder (G11): 0.75^64 ≈ 1e-8 exhaustion

	-- §2, "The layout" (G1, G2).
	layout_grid_columns = 3, -- placeholder: smallest square grid with more cells than room_count
	layout_grid_rows = 3, -- placeholder: as above
	layout_loop_door_chance = 0.25, -- placeholder: extra doorways beyond the spanning tree
	room_pitch_studs = 64, -- placeholder: replace with room_traversal_seconds once measured
	room_footprint_studs = 64, -- derived: = room_pitch_studs (rooms abut)
	room_ceiling_studs = 16, -- placeholder: Lead Designer may change
	doorway_width_studs = 8, -- placeholder: Lead Designer may change
	doorway_height_studs = 10, -- placeholder: Lead Designer may change
	machine_slots_per_room = 4, -- placeholder: the four quadrant centres
	machines_per_room_min = 1, -- placeholder: an empty room is a corridor
	machines_per_room_max = 4, -- derived: = machine_slots_per_room
	machine_spacing_min_studs = 20, -- derived: 2 × turn_range_studs
	walk_speed_studs_per_second = 16, -- derived: the platform's default R15 WalkSpeed
	turn_range_studs = 10, -- placeholder (G5): the server's proximity check for a turn
	partner_lamp_range_studs = 10, -- derived (G5): = turn_range_studs
	trace_position_sample_seconds = 1, -- placeholder: replace if telemetry cost says otherwise
})

-- `tuning.md` §3. The channel - pings and presets.
local channel: ChannelTuning = table.freeze({
	presets_plus_pings_max = 12, -- derived: the guideline's ceiling of 12, ping included
	preset_count = 10, -- taste (operator, 2026-09-30, T12)
	ping_kinds = 1, -- derived: one text-free marker
	preset_rate_limit_seconds = 10, -- derived: the guideline, 10 s per send
	preset_display_seconds = 5, -- placeholder: presets should expire quickly
	preset_reveals_sender = true, -- derived: attribution makes `Help` mean something
	preset_reveals_sender_position = true, -- derived: each preset must stand alone (CA-3)
	ping_rate_limit_seconds = 10, -- derived: Lead PO decision on CA-1, the stricter reading
	ping_display_seconds = 15, -- placeholder: long enough for a partner two rooms away
	active_pings_per_player = 1, -- derived: a new ping replaces the old one
	ping_range_studs = 12, -- derived: = instance.lens_read_range_studs
	ping_reveals_sender = true, -- derived: a ping's meaning comes from who made it
	ping_settings_live_only = false, -- taste (operator, 2026-09-30, T20)
	channel_attempt_min_interval_seconds = 1, -- placeholder (G9): the per-player attempt floor
})

-- `tuning.md` §4. Actuation and instability.
local actuation: ActuationTuning = table.freeze({
	actuation_reset_seconds = 3, -- placeholder: a rejected dial returns to unset
	actuation_failure_is_diagnostic = true, -- taste (operator, 2026-09-30, T13)
	instability_max = 5, -- placeholder: the round is lost at 5 wrong turns
	instability_per_wrong_value = 1, -- derived: wrong setting and not-live cost the same
	instability_per_out_of_order = 1, -- derived: as above
	instability_per_failed_pair = 1, -- derived: one operation, one penalty
	instability_clock_penalty_seconds = 20, -- placeholder: 5 errors remove about 24% of the round
	instability_blackout_threshold = 2, -- placeholder: blackouts at 2 and 4
	blackout_rooms_per_threshold = 1, -- placeholder: replace alongside the threshold
	blackout_permanent = true, -- taste (operator, 2026-09-30, T15)
	blackout_weight_live_step = 1, -- placeholder (G7): playtest P-I
	blackout_weight_waiting_step = 1, -- placeholder (G7): equal to the live weight for now
	blackout_repeat_allowed = false, -- derived (G7): a dark room is never picked again
	turn_rate_limit_seconds = 1, -- placeholder: the turn remote's per-player rate (B4)
	finale_live_together = true, -- derived (G12): both finale steps go live at once

	-- §4, "What the HUD shows of the round" (G8).
	hud_shows_round_clock = true, -- derived: pressure must be perceivable
	hud_clock_separate_from_progress = true, -- derived: no forecast on the bar
	hud_shows_instability = true, -- derived: a loss by an unseen meter teaches nothing
	hud_marks_blackout_thresholds = true, -- derived: the cost of failure stated in advance
})

local MechanicsTuning: MechanicsTuning = table.freeze({
	instance = instance,
	channel = channel,
	actuation = actuation,
})

return MechanicsTuning
