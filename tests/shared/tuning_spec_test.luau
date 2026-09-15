--!strict
--[[
	ROUND-002 AC-4: the link between `docs/wiki/game/tuning.md` and
	`src/shared/Tuning.luau`.

	That file's first paragraph says it IS the specification and that a
	disagreement with the module is a defect. This guard is what makes the claim
	enforceable rather than aspirational: it parses §1 and §5 and compares every
	constant it finds to the module, naming anything present in one and missing
	from the other.

	Parsing a document inside a test is unusual, and the Contract justifies it:
	the alternative is a duplicated list of thirteen values in the test, which is
	a third copy for the two documents to disagree with.

	THE FAILURE MODE THIS FILE IS SHAPED AROUND. A markdown-table parser that
	matches nothing parses zero rows, compares all zero of them successfully, and
	reports green forever. So two assertions here are about the GUARD rather than
	about the module - the row floor and the expected names - and they are the
	ones that matter. The near miss is worth naming: §2 has exactly 13 constant
	rows of its own, so a parser pointed at the wrong section would satisfy a
	count-only floor. Hence both.

	Those two, and the two below them, are green the moment they are written,
	because `tuning.md` already exists. They are earned in ROUND-002's
	`## Regressions` by `scripts/mutate.sh` runs against the specification file -
	one that breaks the §1 heading, one that moves a value - and by the controls
	in `tuning_controls_test.luau`, which drive the same check objects against
	modules that are wrong on purpose.
]]

local fs = require("@lune/fs")
local TuningSpec = require("../helpers/TuningSpec")

local loaded, loadResult = pcall(require, "../../src/shared/Tuning")

local function Tuning(): any
	assert(loaded, `src/shared/Tuning.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

local memo: TuningSpec.Parsed? = nil

local function spec(): TuningSpec.Parsed
	if memo == nil then
		memo = TuningSpec.read()
	end
	return memo :: TuningSpec.Parsed
end

return {
	--[[ AC-4, the guard's own liveness. ]]

	["AC-4: the guard parses at least thirteen constants from tuning.md §1 and §5"] = function()
		TuningSpec.assertEnoughRows(spec())
	end,

	["AC-4: the constants the guard parsed include every one §1 and §5 name"] = function()
		TuningSpec.assertExpectedNames(spec())
	end,

	["AC-4: no row of tuning.md §1 or §5 was left unread"] = function()
		TuningSpec.assertNoParseProblems(spec())
	end,

	["AC-4: tuning.md §1 and §5 still hold the values ROUND-002's criteria freeze"] = function()
		TuningSpec.assertNoFindings(
			TuningSpec.specDriftFindings(spec()),
			"AC-4: the specification has moved under frozen acceptance criteria. This is not a "
				.. "test to edit: rules.md says an acceptance criterion changes only through an "
				.. "`## Amendments` entry, and tuning.md says a disagreement goes to the Lead PO"
		)
	end,

	--[[ AC-4, the comparison itself, in both directions. ]]

	["AC-4: every constant tuning.md §1 and §5 names is in the module with a matching value"] = function()
		TuningSpec.assertNoFindings(
			TuningSpec.missingOrMismatched(spec().rows, Tuning()),
			"AC-4: tuning.md and src/shared/Tuning.luau disagree"
		)
	end,

	["AC-4: every constant the module exposes is named in tuning.md §1 or §5"] = function()
		TuningSpec.assertNoFindings(
			TuningSpec.unspecified(spec().rows, Tuning()),
			"AC-4: the module carries constants the specification does not name"
		)
	end,

	--[[
		AC-5's anchor. The absence rules in `TuningSpec.ABSENT_RULES` are a
		transcription of §7, and a transcription can go stale silently: if §7 were
		rewritten, the rules would keep passing over a module the design no longer
		forbids. This ties them back to the text they came from.
	]]
	["AC-5: tuning.md §7 still records the absences the guard's rules encode"] = function()
		local section = TuningSpec.section(fs.readFile(TuningSpec.SPEC_PATH), 7)
		assert(
			#section > 0,
			`AC-5: {TuningSpec.SPEC_PATH} has no §7; the absence rules have nothing behind them`
		)
		for _, needle in { "hidden_faction_ratio", "vote_", "score", "rank", "MMR", "ladder" } do
			assert(
				string.find(section, needle, 1, true) ~= nil,
				`AC-5: {TuningSpec.SPEC_PATH} §7 no longer mentions "{needle}", but `
					.. `TuningSpec.ABSENT_RULES still rejects it. One of the two has moved.`
			)
		end
	end,
}
