--!strict
--[[
	The wrong modules TUNE-001's negative controls are aimed at.

	AC-2 names three ("`dial_settings` = 5 must fail, naming 4 and 5"; "an extra
	key `vocabulary_size` must fail, naming it"; "missing `ping_display_seconds`
	must fail, naming it"), AC-4 one ("`procedure_length` 9 must fail the
	`per_operation_seconds` relation") and AC-5 implies the rest (an unfrozen
	module, a module frozen only at the root). All are stated as mutations of a
	module that does not exist during RED, so the controls that demonstrate them
	cannot run against it: `mechanics_tuning_spec_test.luau` fails at `require`
	and no assertion in it executes.

	These tables exist so the checks in `MechanicsTuningSpec.luau` ARE executed
	during RED, against modules whose defects are known.

	`correct()` is the baseline, and every wrong module is that baseline with
	EXACTLY ONE thing changed, so a control that fires is attributable to that
	one thing. It is built from the rows PARSED FROM THE REAL `tuning.md` -
	number and boolean rows take their value, reference rows take their
	referent's - rather than from a list of numbers: TUNE-001's criteria name no
	value, and a list here would be the one copy of the document the story
	forbids. That makes the baseline's spec -> module comparison a tautology for
	VALUES, and that is accepted: what the baseline earns is the structure
	(reference resolution, rule absence, no extra key, every relation) and the
	attribution of each control to its one change.

	IT IS NOT A SPECIFICATION OF THE MODULE. Nothing here pins how
	`src/shared/MechanicsTuning.luau` is written - only what it must contain.
	`correct()` is NOT frozen; `frozen()` and `frozenRootOnly()` are the AC-5
	fixtures and say so.
]]

local MechanicsTuningSpec = require("./MechanicsTuningSpec")

local MechanicsTuningFakes = {}

-- Parsed once, on first use (HARNESS-022: a GatedFs read is a spawn, and
-- `lune run test -- --list` must not pay it).
local memo: MechanicsTuningSpec.Parsed? = nil

function MechanicsTuningFakes.spec(): MechanicsTuningSpec.Parsed
	if memo == nil then
		memo = MechanicsTuningSpec.read()
	end
	return memo :: MechanicsTuningSpec.Parsed
end

-- The row for `name`, from the real document. Raises if there is none, so a
-- control built on a row that has vanished says so rather than comparing nil.
function MechanicsTuningFakes.row(name: string): MechanicsTuningSpec.Row
	local row = MechanicsTuningSpec.byName(MechanicsTuningFakes.spec().rows)[name]
	assert(
		row ~= nil,
		`tuning.md §2-§4 has no row named {name}; this control has lost its subject`
	)
	return row :: MechanicsTuningSpec.Row
end

-- A fresh, correct, module-shaped, UNFROZEN table. Fresh every call so that a
-- control that mutates one cannot leak into the next.
function MechanicsTuningFakes.correct(): any
	local parsed = MechanicsTuningFakes.spec()
	local byName = MechanicsTuningSpec.byName(parsed.rows)
	local fake: { [string]: { [string]: any } } = {}
	for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
		fake[tableName] = {}
	end

	local function resolve(row: MechanicsTuningSpec.Row, depth: number): any
		if row.kind == "reference" then
			assert(depth < 8, `reference chain from {row.name} does not terminate`)
			local referent = byName[row.ref :: string]
			assert(
				referent ~= nil,
				`{row.name} references \`{row.ref :: string}\`, which no row of tuning.md §2-§4 names`
			)
			return resolve(referent :: MechanicsTuningSpec.Row, depth + 1)
		end
		return row.value
	end

	for _, row in parsed.rows do
		if row.kind ~= "rule" then
			fake[row.tableName][row.name] = resolve(row, 0)
		end
	end
	return fake
end

--[[
	The baseline with one key set to `value`:

		with("instance", "dial_settings", 5)             -- AC-2: a value that drifted
		with("channel", "vocabulary_size", 16)           -- AC-2: in the module, not in §3
		with("channel", "ping_display_seconds", nil)     -- AC-2: in §3, absent from the module
		with("instance", "procedure_length", 9)          -- AC-4: a relation that no longer holds
]]
function MechanicsTuningFakes.with(tableName: string, key: string, value: any): any
	local fake = MechanicsTuningFakes.correct()
	fake[tableName][key] = value
	return fake
end

-- The baseline, frozen at every level - what AC-5 asks of the real module.
function MechanicsTuningFakes.frozen(): any
	local fake = MechanicsTuningFakes.correct()
	for _, tableName in MechanicsTuningSpec.TABLE_NAMES do
		fake[tableName] = table.freeze(fake[tableName])
	end
	return table.freeze(fake)
end

-- The baseline frozen at the root ONLY: `MechanicsTuning.instance = {}` raises,
-- `MechanicsTuning.instance.room_count = 7` does not. The defect AC-5's
-- "or to a nested value" exists to catch.
function MechanicsTuningFakes.frozenRootOnly(): any
	return table.freeze(MechanicsTuningFakes.correct())
end

-- The baseline with ONE table left unfrozen.
function MechanicsTuningFakes.frozenExcept(tableName: string): any
	local fake = MechanicsTuningFakes.correct()
	for _, other in MechanicsTuningSpec.TABLE_NAMES do
		if other ~= tableName then
			fake[other] = table.freeze(fake[other])
		end
	end
	return table.freeze(fake)
end

-- The module every comparison is vacuously true of.
function MechanicsTuningFakes.empty(): any
	return { instance = {}, channel = {}, actuation = {} }
end

return MechanicsTuningFakes
