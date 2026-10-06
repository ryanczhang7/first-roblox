--!strict
--[[
	The negative controls for CHAN-004 AC-4 (pure half), AC-5 and AC-6, and
	the proof that each check in `tests/helpers/PresetSendsContract.luau`
	means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/channel/PresetSends.luau` does not exist, every test in
	`tests/server/preset_sends_test.luau` fails before its assertion runs, and
	so not one of that file's checks has been observed to accept or refuse
	anything. `PresetSendsStubs.luau` needs only `Presets` (CHAN-002), which
	is merged, so what is asserted here is MEASURED in RED rather than claimed
	for GREEN. The story's handoff carries the table.

	THE REFERENCE is the Contract's C-4 and C-5 written out. Every check must
	ACCEPT it, or the check is wrong and the fix belongs HERE, in RED. Each
	control is the reference with EXACTLY ONE thing changed, so the set of
	checks that fire is attributable to that one change, and each control
	pins that set EXACTLY - a check that fires on a control it should not is
	as much a finding as one that stays quiet.

	THE DEFERRED VERIFICATIONS' SHAPES ARE HERE AS IMPLEMENTATIONS. D-2 is
	`showsWordOnFilterFailure`, D-3 is `noDeclineOnFilterFailure`, D-4 is
	`skipsPhaseCheck`. What is measured here is that the checks WOULD see
	them; D-2..D-4 THEMSELVES stay with GATES.

	WHAT THIS IS NOT: `src/server/channel/PresetSends.luau`, or a sketch of one.
]]

local Contract = require("../helpers/PresetSendsContract")
local Deep = require("../helpers/Deep")
local PhaseUnion = require("../helpers/PhaseUnion")
local Presets = require("../../src/shared/channel/Presets")
local Stubs = require("../helpers/PresetSendsStubs")

local function failingNames(P: any): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Contract.failures(P) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(defect: Stubs.Defect, expected: { string }): { [string]: string }
	local names, messages = failingNames(Stubs.with(defect))
	local want = table.clone(expected)
	table.sort(want)
	print(`        [measured] {defect} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`{defect} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{table.concat(
				shown,
				"\n"
			)}`,
			0
		)
	end
	local byName: { [string]: Contract.Check } = {}
	for _, check in Contract.CHECKS do
		byName[check.name] = check
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac, 1, true) ~= nil,
			`{defect}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end
	return messages
end

local function contains(haystack: string, needle: string, what: string)
	assert(
		string.find(haystack, needle, 1, true) ~= nil,
		`{what}: expected the message to contain "{needle}", got:\n{haystack}`
	)
end

local NEW = "newIsAnEmptyLog"
local PHASE = "outOfPhasePresetIsFailedForPhaseDeclinedOnceAndNeverFiltered"
local SHOWN = "legalPresetIsShownWithTheFiltersTextAndLogged"
local FRESH = "positionsInTheResultAndTheLogAreFreshCopies"
local FILTER = "filterFailureIsFailedForFilterDeclinedOnceAndNothingIsShownOrLogged"
local ACCUMULATES = "theLogAccumulatesEveryShownSendInOrder"

return {
	--[[ ================================================================
	     The input domain, as read.
	     ================================================================ ]]

	["fixtures: the preset table has 10 rows, every phase it names is known to the phase machine, Well played excludes Round, at least two presets are legal in Round, and the stand-in filters answer as labelled"] = function()
		assert(#Presets.ALL == 10, `Presets.ALL has {#Presets.ALL} rows; the story's wheel has 10`)
		local wellPlayed: any = nil
		local roundLegal = 0
		local illegalCases = 0
		for _, preset in Presets.ALL do
			for _, phase in preset.phases do
				assert(
					table.find(PhaseUnion.KNOWN, phase) ~= nil,
					`preset {preset.word} names the unknown phase {phase}`
				)
			end
			if preset.word == "Well played" then
				wellPlayed = preset
			end
			if table.find(preset.phases, "Round") ~= nil then
				roundLegal += 1
			end
			illegalCases += #Contract.illegalPhasesOf(preset)
		end
		assert(wellPlayed ~= nil, "no preset is Well played")
		assert(
			table.find(wellPlayed.phases, "Round") == nil,
			`Well played lists Round: {Deep.show(wellPlayed.phases)}`
		)
		assert(roundLegal >= 2, `only {roundLegal} preset(s) are legal in Round; AC-7 needs two`)
		assert(illegalCases > 0, "no preset excludes any phase")
		local echo, echoRecord = Contract.echo()
		local hashed = Contract.hashed()
		local okE, textE = echo("kim", "Ready")
		local okH, textH = hashed("kim", "Ready")
		assert(okE == true and textE == "Ready", "echo does not echo")
		assert(okH == true and textH == Contract.HASHED, "hashed does not hash")
		assert(
			#echoRecord.calls == 1 and echoRecord.calls[1].text == "Ready",
			"echo did not record"
		)
		for _, failing in Contract.failingFilters() do
			local filter, record = failing.make()
			local ok, okFiltered, text = pcall(filter, "kim", "Ready")
			assert(#record.calls == 1, `{failing.label} did not record its call`)
			assert(
				not ok or okFiltered ~= true or typeof(text) ~= "string",
				`{failing.label} answered ({tostring(okFiltered)}, {tostring(text)}), which is a success`
			)
		end
		print(
			`        [measured] presets {#Presets.ALL}, out-of-phase cases {illegalCases}, Round-legal {roundLegal}, failing filters {#Contract.failingFilters()}`
		)
	end,

	--[[ ================================================================
	     The reference. Everything below is this implementation with one edit.
	     ================================================================ ]]

	["baseline: the reference implementation - C-4 and C-5 written out - passes every check in PresetSendsContract"] = function()
		local names, messages = failingNames(Stubs.reference)
		if #names > 0 then
			local shown: { string } = {}
			for _, name in names do
				table.insert(shown, `{name}: {messages[name]}`)
			end
			error(
				`the reference fails {#names} check(s), so the check or the fixture is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#Contract.CHECKS} checks`)
	end,

	--[[ ================================================================
	     C-10's five named controls.
	     ================================================================ ]]

	["control (C-10, D-2's shape): a send that shows the unfiltered word when the filter fails fires the filter-failure check (shown, not declined, logged) and the accumulation check, nothing else"] = function()
		local messages = expectFires("showsWordOnFilterFailure", { FILTER, ACCUMULATES })
		contains(
			messages[FILTER],
			'value.kind: expected "failed", got "shown"',
			"the word was shown"
		)
		contains(messages[FILTER], "call.decline() was called 0 time(s)", "no decline")
	end,

	["control (C-10, D-3's shape): a send that does not decline on a filter failure fires exactly the filter-failure check, on the decline count"] = function()
		local messages = expectFires("noDeclineOnFilterFailure", { FILTER })
		contains(
			messages[FILTER],
			"call.decline() was called 0 time(s), expected exactly once",
			"the decline count"
		)
	end,

	["control (C-10): a send that calls the filter for an out-of-phase preset fires exactly the phase check, on the filter call count"] = function()
		local messages = expectFires("filtersOutOfPhase", { PHASE })
		contains(
			messages[PHASE],
			"the filter was called 1 time(s) for a preset refused by its own phase list",
			"the filter count"
		)
	end,

	["control (C-10): a send that consumes nothing and shows nothing - every send declined and failed for filter without asking the filter - fires the shown, fresh-copy, accumulation and filter-failure (the filter was never called) checks, nothing else"] = function()
		local messages = expectFires("showsNothing", { SHOWN, FRESH, FILTER, ACCUMULATES })
		contains(messages[SHOWN], 'reason = "filter"', "the refusal where a send was expected")
		contains(
			messages[FILTER],
			"the filter was called 0 time(s), expected exactly once",
			"the filter was never asked"
		)
	end,

	["control (C-10): a send that appends into the state it was given fires the shown and accumulation checks on the snapshot, nothing else"] = function()
		local messages = expectFires("mutatesState", { SHOWN, ACCUMULATES })
		contains(messages[SHOWN], "send wrote into the state it was given (C-5)", "the snapshot")
		contains(
			messages[ACCUMULATES],
			"the state new() returned was written to by later sends (C-5)",
			"the first state"
		)
	end,

	--[[ ================================================================
	     D-4's shape and the rest of C-4.
	     ================================================================ ]]

	["control (D-4's shape): a send that skips the per-preset phase check fires exactly the phase check and the accumulation check - Well played in Round is shown"] = function()
		local messages = expectFires("skipsPhaseCheck", { PHASE, ACCUMULATES })
		contains(messages[PHASE], "Well played", "the out-of-phase preset")
		contains(messages[PHASE], 'value.kind: expected "failed", got "shown"', "it was shown")
	end,

	["control: an out-of-phase refusal that does not decline fires exactly the phase check, on the decline count"] = function()
		local messages = expectFires("noDeclineOnPhase", { PHASE })
		contains(
			messages[PHASE],
			"call.decline() was called 0 time(s), expected exactly once",
			"the decline count"
		)
	end,

	["control: shown.text as the table's word rather than the filter's returned string fires exactly the shown check - every hashed send names ####"] = function()
		local messages = expectFires("showsWordNotFilterText", { SHOWN })
		contains(messages[SHOWN], `expected "{Contract.HASHED}"`, "the returned string")
	end,

	["control: a filter called twice per send fires the shown check and the filter-failure check, on the call count"] = function()
		local messages = expectFires("filterTwice", { SHOWN, FILTER })
		contains(
			messages[SHOWN],
			"the filter was called 2 time(s), expected exactly once",
			"the call count"
		)
	end,

	["control: (true, nil) from the filter treated as a success fires exactly the filter-failure check - the word is shown"] = function()
		local messages = expectFires("acceptsTrueNil", { FILTER })
		contains(messages[FILTER], "a filter returning (true, nil)", "the (true, nil) case")
		contains(messages[FILTER], 'value.kind: expected "failed", got "shown"', "it was shown")
	end,

	["control: a filter raise that escapes send fires exactly the filter-failure check, on the raise"] = function()
		local messages = expectFires("raiseEscapes", { FILTER })
		contains(messages[FILTER], "send RAISED: ", "the raise")
		contains(messages[FILTER], "a filter failure never escapes send", "the clause")
	end,

	["control: a failed send that is logged anyway fires the filter-failure check and the accumulation check"] = function()
		local messages = expectFires("logsOnFailure", { FILTER, ACCUMULATES })
		contains(messages[FILTER], "something was logged", "the log")
	end,

	["control: a filter failure that declines twice fires exactly the filter-failure check, on the decline count"] = function()
		local messages = expectFires("declinesTwiceOnFailure", { FILTER })
		contains(
			messages[FILTER],
			"call.decline() was called 2 time(s), expected exactly once",
			"the decline count"
		)
	end,

	--[[ ================================================================
	     C-5: exact keys, fresh copies, new states.
	     ================================================================ ]]

	["control: a shown send that declines too fires exactly the shown check"] = function()
		local messages = expectFires("declinesOnShown", { SHOWN })
		contains(messages[SHOWN], "on a SHOWN preset; expected never", "the decline")
	end,

	["control: positions that alias the caller's table fire exactly the fresh-copy check, on both the identity and the later write"] = function()
		local messages = expectFires("sharesPosition", { FRESH })
		contains(messages[FRESH], "shown.position IS the caller's table", "the identity")
		contains(
			messages[FRESH],
			"writing to the caller's position afterwards moved shown.position",
			"the later write"
		)
	end,

	["control: a log entry without `at` fires the shown and accumulation checks"] = function()
		local messages = expectFires("logOmitsAt", { SHOWN, ACCUMULATES })
		contains(messages[SHOWN], "at: expected 100, got nil", "the missing at")
	end,

	["control: a PresetFailed carrying a third key fires the phase and filter-failure checks on the exact shape"] = function()
		local messages = expectFires("failedCarriesWord", { PHASE, FILTER })
		contains(messages[PHASE], "word: unexpected", "the extra key")
	end,

	["control: a failed result that returns the given state table itself (aliased, unmodified) passes every check - identity of a failed state is unconstrained (C-5)"] = function()
		expectFires("sharesLog", {})
	end,

	["control: a check that would catch new() returning a shared or non-empty state - the check exists, and the reference passes it"] = function()
		local fakeNew = {
			new = function(): any
				return { log = { 1 } }
			end,
			send = Stubs.reference.send,
		}
		local names = failingNames(fakeNew)
		assert(
			table.find(names, NEW) ~= nil,
			`a new() returning a non-empty log did not fire {NEW}: {Deep.show(names)}`
		)
		local shared = { log = {} }
		local sharedNew = {
			new = function(): any
				return shared
			end,
			send = Stubs.reference.send,
		}
		local names2 = failingNames(sharedNew)
		assert(
			table.find(names2, NEW) ~= nil,
			`a new() returning one shared table did not fire {NEW}: {Deep.show(names2)}`
		)
		print(
			`        [measured] non-empty new fires {Deep.show(names)}; shared new fires {Deep.show(
				names2
			)}`
		)
	end,
}
