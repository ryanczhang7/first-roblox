--!strict
--[[
	The negative controls for VIEW-002, and the proof that each check in
	`tests/helpers/TurnCuesContract.luau` refuses the view it exists to catch.

	THE CRITERIA NAME THEIR CONTROLS. AC-1: "a view that lists every live
	machine must fail." AC-3: "a lookahead of 2 must produce extra cues on a
	fixture built for it", plus the Contract's requirement that a view reading
	the shipped constant instead of `procedure.tuning` fails the lookahead-2
	test and nothing else. D-1..D-4 name the direction error, the strict
	boundary, position-0-as-live and next-not-excluding-live. Each is a
	one-defect view in `TurnCuesStubs.luau`.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half
	is the one that is easy to leave out and worth the most: a stub that fails
	EVERY check proves only that the checks reject something. Where a control
	fails more than one check, it is said so, with the set MEASURED here rather
	than predicted - `nextIncludesLive` fails AC-4 as well as AC-3 because a
	live finale is then also next; `strictLookahead` fails AC-5 because the
	supplier's inherited position-1 cues are the ones it drops.

	THE CONTROLS RUN OVER A SUB-SAMPLE. The checks accept a `cases` list; the
	real test holds `turnCuesFor` to the full 200-per-n sample, and this file
	hands every view the first 12 facilities per n (36 facilities, 720
	states, 3,600 calls) - same generator, same seeds - so that thirteen views
	times eight checks finishes in a few seconds. The audit numbers asserted
	below are the sub-sample's; the full-sample numbers are pinned by the
	second baseline test.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. `Ring`, `Procedure` and
	`Generator` are merged, so every number here is a measurement taken in
	RED, not a claim left for GREEN.
]]

local Contract = require("../helpers/TurnCuesContract")
local Stubs = require("../helpers/TurnCuesStubs")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local small = Contract.sample(Contract.CONTROL_FACILITIES_PER_N)

local function accepts(check: Check, view: any, what: string)
	local ok, err = pcall(check, view)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: Check, view: any, what: string): string
	local ok, err = pcall(check, view)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

local function bound(check: (any, any) -> ()): Check
	return function(view)
		check(view, small)
	end
end

-- Every check, bound to the sub-sample where it takes one.
local ALL: { Named } = {
	{ label = "AC-1", check = bound(Contract.cuesNameOnlyTheirOwnMachines) },
	{ label = "AC-2", check = bound(Contract.liveIsExactlyProcedureIsLive) },
	{ label = "AC-3", check = bound(Contract.nextIsExactlyTheLookaheadWindow) },
	{ label = "AC-3/lookahead-2", check = Contract.lookaheadTwoSeesTheExtraCue },
	{ label = "AC-4", check = bound(Contract.waitingFinaleIsNextNotLive) },
	{ label = "AC-4/fixture", check = Contract.fixtureCuesAtShippedLookahead },
	{ label = "AC-5", check = bound(Contract.supplierCuesIncludeTheTransferredClass) },
	{ label = "AC-6", check = bound(Contract.cuesHaveExactlyTheContractShape) },
}

local function checkNamed(label: string): Check
	for _, entry in ALL do
		if entry.label == label then
			return entry.check
		end
	end
	error(`no check labelled {label}`)
end

-- Every check except the ones a control is built to fail - and exactly those
-- must fail, so a control that fails more than it says is caught too.
local function failsExactly(view: any, who: string, expected: { string })
	local except: { [string]: boolean } = {}
	for _, label in expected do
		except[label] = true
	end
	for _, entry in ALL do
		if except[entry.label] then
			refuses(entry.check, view, `{entry.label} must refuse {who}`)
		else
			accepts(entry.check, view, `{entry.label} on {who}`)
		end
	end
end

local function cleanAudit(audit: any): boolean
	return audit.malformed == 0
		and #audit.ownership == 0
		and #audit.live == 0
		and #audit.nextIds == 0
		and #audit.decoy == 0
		and #audit.ac4 == 0
		and #audit.armed == 0
end

local function measured(what: string, got: number, want: number)
	assert(got == want, `{what}: measured {want} in RED, got {got}`)
end

-- The two fixture checks, which every exact-view defect fails as well.
local FIXTURES = { "AC-3/lookahead-2", "AC-4/fixture" }

local function withFixtures(labels: { string }): { string }
	local out = table.clone(labels)
	for _, label in FIXTURES do
		table.insert(out, label)
	end
	return out
end

return {
	--[[ The baseline, and the sample it is measured on. ]]

	["baseline: the reference view passes every VIEW-002 check on the control sample, and the sample exercised every clause"] = function()
		failsExactly(Stubs.reference, "the reference view", {})
		local audit = Contract.audit(Stubs.reference, small)
		assert(cleanAudit(audit), Contract.describeAudit(audit))
		-- MEASURED in RED over this seeded sub-sample; a different number is a
		-- change to the sample, which is a change to what the criterion is
		-- held over. 36 facilities x 20 states x n players.
		measured("facilities", audit.cases, 36)
		measured("calls", audit.calls, 3600)
		measured("calls expecting a cue", audit.nonEmpty, 2130)
		measured("calls expecting a live cue", audit.nonEmptyLive, 1137)
		measured("calls expecting a next cue", audit.nonEmptyNext, 1103)
		measured("calls with a cue in each track", audit.bothTracks, 186)
		measured("owned steps at position lookahead + 1", audit.excludedByOne, 615)
		measured("calls where the player owns a decoy", audit.ownedDecoyCalls, 3600)
		measured("calls expecting a finale step in next", audit.waitingFinale, 537)
		measured("(state, holder) pairs with exactly one track done", audit.ac4States, 276)
		measured("(state, holder) pairs with the holder's finale armed", audit.armedStates, 36)
	end,

	["baseline: the full sample is 600 facilities, 12000 states, 60000 calls, and holds the per-facility floors with room to spare"] = function()
		local full = Contract.sample()
		assert(#full == 600, `{#full} facilities, expected 200 at each of n = 4, 5, 6`)
		local states = 0
		for _, case in full do
			states += #case.states
		end
		assert(states == 12000, `{states} states, expected 20 per facility`)
		local audit = Contract.audit(Stubs.reference)
		assert(cleanAudit(audit), Contract.describeAudit(audit))
		-- MEASURED in RED against the reference view. The floors are per
		-- facility x 600; the smallest margin is excluded-by-one at 5.7x its
		-- floor (10275 against 1800), then AC-4 states at 3.9x (4725 against
		-- 1200).
		measured("calls", audit.calls, 60000)
		measured("calls expecting a cue", audit.nonEmpty, 34988)
		measured("calls expecting a live cue", audit.nonEmptyLive, 18727)
		measured("calls expecting a next cue", audit.nonEmptyNext, 18234)
		measured("calls with a cue in each track", audit.bothTracks, 3487)
		measured("owned steps at position lookahead + 1", audit.excludedByOne, 10275)
		measured("calls expecting a finale step in next", audit.waitingFinale, 8925)
		measured("(state, holder) pairs with exactly one track done", audit.ac4States, 4725)
		measured("(state, holder) pairs with the holder's finale armed", audit.armedStates, 600)
	end,

	--[[ AC-1's named control. ]]

	["AC-1 control: a view listing every live machine (anyone's) fails AC-1 naming a class the player does not hold, and AC-2, AC-5 and the exact fixtures with it"] = function()
		local view = Stubs.everyLive
		failsExactly(view, "the every-live-machine view", withFixtures({ "AC-1", "AC-2", "AC-5" }))
		local message = refuses(checkNamed("AC-1"), view, "every-live must fail AC-1")
		names(message, "AC-1:", "the AC-1 check fires")
		names(
			message,
			"live cue 9 is of class 3, not one of p1's key classes [1]",
			"the failure names the class the player does not hold"
		)
		names(
			refuses(checkNamed("AC-2"), view, "every-live must fail AC-2"),
			"extra live cue 13 (not p1's)",
			"AC-2 names the extra cue as another player's"
		)
		local audit = Contract.audit(view, small)
		measured("ownership violations", #audit.ownership, 4656)
		measured("live violations", #audit.live, 3297)
		measured("next violations", #audit.nextIds, 0)
	end,

	--[[ D-1: the direction error. ]]

	["D-1 control: a view owning by Ring.lensOf instead of keyClasses fails AC-1 on the generated sample and every exact check with it, passing only the shape check"] = function()
		local view = Stubs.lensNotKey
		failsExactly(
			view,
			"the lens-not-key view",
			withFixtures({ "AC-1", "AC-2", "AC-3", "AC-4", "AC-5" })
		)
		local audit = Contract.audit(view, small)
		-- MEASURED: every cue it lists is of the lens class, which is never the
		-- player's own key on a dealt ring, so every cue is an ownership hit.
		measured("ownership violations", #audit.ownership, 2316)
		measured("live violations", #audit.live, 2140)
		measured("next violations", #audit.nextIds, 1967)
		measured("AC-4 violations", #audit.ac4, 564)
		measured("armed violations", #audit.armed, 36)
		names(
			refuses(checkNamed("AC-1"), view, "lens-not-key must fail AC-1"),
			"next cue 4 is of class 2, not one of p3's key classes [3]",
			"the failure names the lens class the cue is of and the key class it is not"
		)
	end,

	--[[ D-2: the boundary. ]]

	["D-2 control: a strict (<) lookahead fails AC-3 on the sample (every position-1 cue missing), AC-5 (the supplier's inherited position-1 cues) and both fixtures, and passes AC-1, AC-2, AC-4 and AC-6"] = function()
		local view = Stubs.strictLookahead
		failsExactly(view, "the strict-lookahead view", withFixtures({ "AC-3", "AC-5" }))
		local message = refuses(checkNamed("AC-3"), view, "strict must fail AC-3")
		names(
			message,
			"expected next [12] at lookahead 1, got []: missing next cue 12",
			"the failure names the position-1 cue it dropped"
		)
		local audit = Contract.audit(view, small)
		measured("next violations", #audit.nextIds, 845)
		measured("live violations", #audit.live, 0)
		names(
			refuses(
				checkNamed("AC-3/lookahead-2"),
				view,
				"strict must fail the lookahead-2 fixture"
			),
			"S0 nothing committed, p4: expected { live = {  }, next = { 1 = 7, 2 = 8 } }, got "
				.. "{ live = {  }, next = { 1 = 8 } }",
			"the fixture names machine 7 at position 2, which < 2 drops"
		)
	end,

	["AC-3 control: a view reading turn_cue_lookahead from MechanicsTuning (1) rather than procedure.tuning (2) passes every sample check and the shipped-lookahead fixture, and fails ONLY the lookahead-2 fixture test"] = function()
		local view = Stubs.shippedLookahead
		failsExactly(view, "the shipped-lookahead view", { "AC-3/lookahead-2" })
		local message =
			refuses(checkNamed("AC-3/lookahead-2"), view, "shipped lookahead must fail the fixture")
		names(
			message,
			"turn_cue_lookahead = 2 (from procedure.tuning)",
			"the failure names the tuning it read"
		)
		names(message, "in 6 of 24 cases", "six (state, player) pairs see an extra cue at 2")
		names(
			message,
			"S0 nothing committed, p2: expected { live = { 1 = 6 }, next = { 1 = 5 } }, got "
				.. "{ live = { 1 = 6 }, next = {  } }",
			"the fixture wanted machine 5 at position 2"
		)
	end,

	--[[ D-3: liveness is Procedure's. ]]

	["D-3 control: a view taking live as position 0 instead of Procedure.isLive fails AC-4 (a waiting finale shows as live), AC-2, AC-3 (next then lacks it), AC-5 and the fixtures"] = function()
		local view = Stubs.positionZeroAsLive
		failsExactly(
			view,
			"the position-0-as-live view",
			withFixtures({ "AC-2", "AC-3", "AC-4", "AC-5" })
		)
		names(
			refuses(checkNamed("AC-4"), view, "position-0 must fail AC-4"),
			"finale machine 1's track 1 is done and the other is not, so it must be in next and "
				.. "not live; live [1], next []",
			"AC-4 names the waiting finale shown as live"
		)
		names(
			refuses(checkNamed("AC-2"), view, "position-0 must fail AC-2"),
			"extra live cue 1 (Procedure.isLive is false)",
			"AC-2 attributes the extra live cue to Procedure's answer"
		)
		local audit = Contract.audit(view, small)
		-- One of each per (state, holder) pair with exactly one track done.
		measured("live violations", #audit.live, 276)
		measured("next violations", #audit.nextIds, 276)
		measured("AC-4 violations", #audit.ac4, 276)
		measured("AC-4 states", audit.ac4States, 276)
	end,

	--[[ D-4: next excludes live. ]]

	["D-4 control: a view whose next does not exclude live fails AC-3 (every live step is also next), AC-4 (a live finale is also next), AC-5 and the fixtures"] = function()
		local view = Stubs.nextIncludesLive
		failsExactly(view, "the next-includes-live view", withFixtures({ "AC-3", "AC-4", "AC-5" }))
		names(
			refuses(checkNamed("AC-3"), view, "next-includes-live must fail AC-3"),
			"extra next cue 12, which is live",
			"the failure says the extra next cue is live"
		)
		names(
			refuses(checkNamed("AC-4"), view, "next-includes-live must fail AC-4"),
			"every ordinary step is done, so finale machine 1 must be live and not next; live [1], next [1]",
			"AC-4 names the live finale that is also next"
		)
		local audit = Contract.audit(view, small)
		measured("next violations (one per non-empty live)", #audit.nextIds, 1137)
		measured("AC-4 violations", #audit.ac4, 288)
	end,

	--[[ AC-3: decoys. ]]

	["AC-3 control: a view appending the player's decoys to next fails AC-3 on every call naming the decoy, AC-5, and the fixtures (decoys 2 and 10)"] = function()
		local view = Stubs.decoyIncluded
		failsExactly(view, "the decoy-included view", withFixtures({ "AC-3", "AC-5" }))
		names(
			refuses(checkNamed("AC-3"), view, "decoy must fail AC-3"),
			"extra next cue 6, which is a decoy",
			"the failure names the decoy"
		)
		local audit = Contract.audit(view, small)
		measured("next violations (every call: every player owns a decoy)", #audit.nextIds, 3600)
		measured("decoy cues", #audit.decoy, 5760)
	end,

	--[[ AC-6. ]]

	["AC-6 control: lists in descending order pass every membership check and fail AC-6 (76 two-cue lists on the control sample) and the fixtures"] = function()
		local view = Stubs.descending
		failsExactly(view, "the descending view", withFixtures({ "AC-6" }))
		local message = refuses(checkNamed("AC-6"), view, "descending must fail AC-6")
		names(message, "in 76 of 3600 calls", "every list with two cues is reversed")
		names(
			message,
			"live[2] 9 does not ascend past 13 (ascending, unique)",
			"the failure names the order"
		)
	end,

	["AC-6 control: lists in track order, never sorted, pass every membership check and fail AC-6 on the sample (30 calls where track 1's id is above track 2's) and the fixture ([9, 4])"] = function()
		local view = Stubs.trackOrder
		failsExactly(view, "the track-order view", withFixtures({ "AC-6" }))
		names(
			refuses(checkNamed("AC-6"), view, "track order must fail AC-6"),
			"in 30 of 3600 calls",
			"track order is ascending by accident on all but 30 calls"
		)
		names(
			refuses(checkNamed("AC-4/fixture"), view, "track order must fail the fixture"),
			"p1: expected { live = {  }, next = { 1 = 4, 2 = 9 } }, got { live = {  }, next = { 1 = 9, 2 = 4 } }",
			"the fixture shows [9, 4] where [4, 9] was wanted"
		)
	end,

	["AC-6 control: an extra key on the view fails AC-6 on every call and the exact fixtures, and nothing else"] = function()
		local view = Stubs.extraKey
		failsExactly(view, "the extra-key view", withFixtures({ "AC-6" }))
		names(
			refuses(checkNamed("AC-6"), view, "an extra key must fail AC-6"),
			"the view's keys are [live,next,playerId], not exactly [live, next]",
			"AC-6 lists the keys it found"
		)
	end,

	["AC-6 control: the same two lists handed back on every call fail AC-6's freshness pin alone"] = function()
		local view = Stubs.sharedLists
		failsExactly(view, "the shared-lists view", { "AC-6" })
		local message = refuses(checkNamed("AC-6"), view, "shared lists must fail AC-6")
		names(message, "the same live list was returned twice", "AC-6 names the live aliasing")
		names(message, "the same next list was returned twice", "AC-6 names the next aliasing")
		names(message, "in 900 of 3600 calls", "one call in FRESHNESS_STRIDE is checked twice")
	end,

	["AC-6 control: a live cue listed twice passes every membership check and fails AC-6's unique clause on every non-empty live, and the fixtures"] = function()
		local view = Stubs.duplicateCue
		failsExactly(view, "the duplicate-cue view", withFixtures({ "AC-6" }))
		local message = refuses(checkNamed("AC-6"), view, "a duplicate must fail AC-6")
		names(message, "in 1137 of 3600 calls", "one per non-empty live")
		names(
			message,
			"live[2] 12 does not ascend past 12 (ascending, unique)",
			"the failure names uniqueness"
		)
	end,
}
