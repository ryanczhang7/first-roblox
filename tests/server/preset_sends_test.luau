--!strict
--[[
	CHAN-004: a preset is filtered once, shown with the filter's text and its
	sender's position, logged, and refused by its own phase list or a failed
	filter without a send. AC-4 (the pure half), AC-5 and AC-6, plus the
	Contract's C-5, applied to the real `src/server/channel/PresetSends.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as every suite here does. In RED `PresetSends.luau` does not
	exist, and a bare top-level `require` would make this whole file a single
	LOAD FAIL - one line of red covering three criteria. Per-criterion
	failures say which behaviours are missing. It is not a skip: every test
	below still FAILS, loudly, naming the module that did not load.

	THE CHECKS LIVE IN `tests/helpers/PresetSendsContract.luau` and are
	exercised in `tests/server/preset_sends_controls_test.luau` against
	`PresetSendsStubs.luau`'s reference and implementations with exactly one
	defect each. That file is where each check is OBSERVED to fire - which
	matters in RED, because the pcall above means not one assertion in THIS
	file executes until GREEN writes the module.

	THE ORACLE PARTITION (story `## Contract`): every criterion here is
	mechanical. The input domain is read out of `Presets.ALL` - every preset
	in every phase it excludes, and in every phase it lists - and the filter
	is a stand-in function (C-8).

	WHAT THIS FILE DOES NOT PIN: whether `shown.position` and the log entry's
	position are one copy or two (both must be fresh), the identity of the
	state a `failed` result returns (its log must equal the old one by value),
	what `send` does with an unknown preset id (C-4 step 1: may raise, never
	driven), and how `send` is wired into `Session` (`SLICE-006`).
]]

local Contract = require("../helpers/PresetSendsContract")

local sendsLoaded, sendsResult = pcall(require, "../../src/server/channel/PresetSends")

local function presetSends(): any
	assert(sendsLoaded, `src/server/channel/PresetSends.luau did not load: {tostring(sendsResult)}`)
	return sendsResult
end

return {
	["Contract (C-5): PresetSends.new() is exactly { log = {} }, fresh on every call"] = function()
		Contract.newIsAnEmptyLog(presetSends())
	end,

	["AC-4: every preset sent in a phase its row excludes (Well played in Round among them) is failed with reason phase_for_preset, declined exactly once, the filter is never called, the log is unchanged and the given state untouched"] = function()
		Contract.outOfPhasePresetIsFailedForPhaseDeclinedOnceAndNeverFiltered(presetSends())
	end,

	["AC-5: every preset sent in a phase its row lists through a filter returning #### is shown as exactly { senderId, presetId, position, text = #### }, appended to the log as exactly { senderId, presetId, position, at = now }, the filter is called exactly once with (senderId, word), the call is never declined, and an echo filter shows the word"] = function()
		Contract.legalPresetIsShownWithTheFiltersTextAndLogged(presetSends())
	end,

	["Contract (C-5): the position in PresetShown and in the log entry is a fresh copy - not the caller's table, and unmoved when the caller's table is written to afterwards"] = function()
		Contract.positionsInTheResultAndTheLogAreFreshCopies(presetSends())
	end,

	["AC-6: a filter returning (false, nil), (true, nil), (false, word) or (true, 42), or raising, never escapes send; the result is failed with reason filter, the call is declined exactly once, the filter was called exactly once, nothing is shown and nothing is logged"] = function()
		Contract.filterFailureIsFailedForFilterDeclinedOnceAndNothingIsShownOrLogged(presetSends())
	end,

	["AC-5: from new(), three shown sends by two senders with a phase refusal and a filter refusal between them leave a log of exactly those three entries in order, and no earlier state is written to"] = function()
		Contract.theLogAccumulatesEveryShownSendInOrder(presetSends())
	end,
}
