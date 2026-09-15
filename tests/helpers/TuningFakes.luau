--!strict
--[[
	The wrong modules ROUND-002's negative controls are aimed at.

	AC-4 names one ("changing `lobby_seconds` from 60 to 61 must make the guard
	fail and must name `lobby_seconds`") and AC-5 names another ("adding
	`vote_seconds = 30` must make this fail"). Both are stated as mutations of a
	module that does not exist during RED, so the controls that would demonstrate
	them cannot run against it: `tuning_test.luau` and `tuning_spec_test.luau`
	fail at `require` and no assertion in either file executes.

	These tables exist so the AC-4 and AC-5 checks in `TuningSpec.luau` ARE
	executed during RED, against modules whose defects are known.

	`TuningFakes.correct()` is the baseline and it is what makes each control
	specific: every wrong module below is that baseline with EXACTLY ONE thing
	changed, so a control that fires is attributable to that one thing.

	It is built from `TuningSpec.ACCEPTANCE` rather than from a fresh list of
	numbers, deliberately: a fourth copy of the thirteen values would be a fourth
	thing to keep in step, and the baseline's job is to be correct, not to be an
	independent statement of what correct is. What makes the baseline meaningful
	is that the rows it is compared against are parsed from the REAL
	`docs/wiki/game/tuning.md`.

	IT IS NOT A SPECIFICATION OF THE MODULE. Nothing here pins how
	`src/shared/Tuning.luau` is written - only what it must contain. In
	particular these tables are NOT frozen; AC-3 is asserted against the real
	module, where freezing is the implementer's obligation.
]]

local TuningSpec = require("./TuningSpec")

local TuningFakes = {}

-- A fresh, correct, module-shaped table. Fresh every call - and a clone of each
-- inner table, not a reference - so a control that mutates one cannot leak into
-- the next, and none of them can reach back into `TuningSpec.ACCEPTANCE`.
function TuningFakes.correct(): any
	return {
		session = table.clone(TuningSpec.ACCEPTANCE.session),
		round = table.clone(TuningSpec.ACCEPTANCE.round),
	}
end

--[[
	The baseline with one key set to `value`. Three of the four controls are this
	one call:

		with("session", "lobby_seconds", 61)   -- AC-4: a value that drifted
		with("session", "vote_seconds", 30)    -- AC-5: a constant §7 forbids
		with("round", "warmup_seconds", 15)    -- AC-4: in the module, not in §5

	`nil` removes the key, which is the fourth - in the spec, absent from the
	module.
]]
function TuningFakes.with(tableName: string, key: string, value: any): any
	local fake = TuningFakes.correct()
	fake[tableName][key] = value
	return fake
end

-- The module every absence assertion is vacuously true of.
function TuningFakes.empty(): any
	return { session = {}, round = {} }
end

return TuningFakes
