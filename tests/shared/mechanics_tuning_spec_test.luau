--!strict
--[[
	TUNE-001 AC-1 to AC-5: `docs/wiki/game/tuning.md` §2, §3 and §4 against
	`src/shared/MechanicsTuning.luau`, with `src/shared/Tuning.luau` supplying
	the §1 and §5 operands of AC-4's relations.

	The document's first paragraph says it IS the specification and that a
	disagreement with the module is a defect. `MechanicsTuningSpec` parses the
	three sections and compares every row it classifies to the module, naming
	anything present in one and missing or different in the other. No number
	from the document appears in this file or in the helper: AC-2 and AC-4 are
	SETTLED criteria, read out, never restated.

	THE FAILURE MODE THIS FILE IS SHAPED AROUND. A markdown-table parser that
	matches nothing parses zero rows, compares all zero of them successfully and
	reports green forever. So the first two tests are about the GUARD rather than
	about the module - every row classified, every section non-empty - and both
	are green the moment they are written, because `tuning.md` already exists.
	They are earned by the fixture controls in
	`mechanics_tuning_controls_test.luau`, which drive the same parser over
	documents that are wrong on purpose, and by the `scripts/mutate.sh` probes
	against the real document recorded in TUNE-001's handoff. The module-side
	direction (AC-2, "no key that no row names") is the other half: a parser that
	dropped rows would report the module's keys as unspecified once the module
	exists.

	Nothing here pins HOW the module is written: not the key order, not whether
	each table has a precise record type, not which of `table.freeze` or a
	`__newindex` metatable provides AC-5. Only that the attempt fails.

	Loaded through a `pcall` for the reason `tuning_test.luau` gives: in RED the
	module does not exist, and one LOAD FAIL covering five criteria is worse
	evidence than a dozen failures naming them.
]]

local MechanicsTuningSpec = require("../helpers/MechanicsTuningSpec")
local Tuning = require("../../src/shared/Tuning")

local loaded, loadResult = pcall(require, "../../src/shared/MechanicsTuning")

local function MechanicsTuning(): any
	assert(loaded, `src/shared/MechanicsTuning.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

local memo: MechanicsTuningSpec.Parsed? = nil

local function spec(): MechanicsTuningSpec.Parsed
	if memo == nil then
		memo = MechanicsTuningSpec.read()
	end
	return memo :: MechanicsTuningSpec.Parsed
end

return {
	--[[ AC-1 and AC-3: the guard's own liveness, before any comparison. ]]

	["AC-1: every backticked row of tuning.md §2-§4 is exactly one of number, boolean, reference or rule"] = function()
		MechanicsTuningSpec.assertNoParseProblems(spec())
	end,

	["AC-3: the guard parses at least one row from each of tuning.md §2, §3 and §4"] = function()
		MechanicsTuningSpec.assertEverySectionHasRows(spec())
	end,

	--[[ AC-2: the comparison, in both directions. ]]

	["AC-2: every constant row of tuning.md §2-§4 is in MechanicsTuning with its specified value, and no rule row is"] = function()
		MechanicsTuningSpec.assertEverySectionHasRows(spec())
		MechanicsTuningSpec.assertNoFindings(
			MechanicsTuningSpec.missingOrMismatched(spec().rows, MechanicsTuning()),
			"AC-2: tuning.md §2-§4 and src/shared/MechanicsTuning.luau disagree"
		)
	end,

	["AC-2: every key MechanicsTuning exposes is named by a constant row of tuning.md §2-§4"] = function()
		MechanicsTuningSpec.assertEverySectionHasRows(spec())
		MechanicsTuningSpec.assertNoFindings(
			MechanicsTuningSpec.unspecified(spec().rows, MechanicsTuning()),
			"AC-2: the module carries constants the specification does not name"
		)
	end,

	["AC-2: MechanicsTuning exposes exactly the tables instance, channel and actuation"] = function()
		local module = MechanicsTuning()
		assert(typeof(module) == "table", `MechanicsTuning is {typeof(module)}, expected a table`)
		local keys = MechanicsTuningSpec.sortedKeys(module)
		local expected = table.clone(MechanicsTuningSpec.TABLE_NAMES)
		table.sort(expected)
		assert(
			table.concat(keys, ",") == table.concat(expected, ","),
			`AC-2: MechanicsTuning's keys are [{table.concat(keys, ", ")}], expected `
				.. `[{table.concat(expected, ", ")}]`
		)
		for _, tableName in expected do
			assert(
				typeof(module[tableName]) == "table",
				`AC-2: MechanicsTuning.{tableName} is {typeof(module[tableName])}, expected a table`
			)
		end
	end,

	--[[ AC-4: the derived relations, computed from module values. ]]

	["AC-4: every derived relation tuning.md states holds between MechanicsTuning and Tuning values"] = function()
		local findings = MechanicsTuningSpec.relationFindings(MechanicsTuning(), Tuning)
		MechanicsTuningSpec.assertNoFindings(
			findings,
			"AC-4: a derived relation the specification states does not hold on module values"
		)
	end,

	--[[ AC-5: the whole structure is frozen. ]]

	["AC-5: assigning to MechanicsTuning, to any of its three tables, or to any nested value raises and changes nothing"] = function()
		local module = MechanicsTuning()
		local findings = MechanicsTuningSpec.freezeFindings(module)
		MechanicsTuningSpec.assertNoFindings(
			findings,
			"AC-5: MechanicsTuning accepted a write; the whole structure must be frozen, as Tuning is"
		)
	end,
}
