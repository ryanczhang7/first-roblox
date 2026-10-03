--!strict
--[[
	The negative controls for VIEW-001, and the proof that each check in
	`tests/helpers/LensViewContract.luau` refuses the view it exists to catch -
	plus the controls for AC-6's text guard, which is a matcher over text and
	has to be shown to match.

	THE CRITERIA NAME THEIR CONTROLS. AC-1: "a view that gates on range only
	(any class) must fail the class clause. One that gates on class only (any
	range) must fail the range clause." The Contract adds three more (ignoring
	dark, committed and line of sight), the direction error D-1, the strict
	boundary D-3 and the early line-of-sight call D-4. Each is a one-defect
	view in `LensViewStubs.luau`.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half
	is the one that is easy to leave out and worth the most: a stub that fails
	EVERY check proves only that the checks reject something. Where a control
	fails more than one check, it is said so, with the set MEASURED here rather
	than predicted - `ignoreDark` fails AC-5 as well as AC-1 because AC-5's
	fixture is a dark room; `keyNotLens` fails every exact-view check because
	p1 then reads class 1, of which the fixtures put nothing where p1 stands.

	THE CONTROLS RUN OVER A SUB-SAMPLE. The checks accept a `cases` list; the
	real test holds `lensFor` to the full 200-per-n sample, and this file
	hands every view the first 12 facilities per n (36 facilities, 9,000
	calls) - same generator, same seeds - so that nineteen views times eight
	checks finishes in seconds. The audit numbers asserted below are the
	sub-sample's; the full-sample numbers are in the story's handoff.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. `Ring`, `Machines`,
	`Procedure` and `Generator` are merged, so every number here is a
	measurement taken in RED, not a claim left for GREEN.
]]

local Contract = require("../helpers/LensViewContract")
local Stubs = require("../helpers/LensViewStubs")

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

-- Every check, bound to the sub-sample where it takes one.
local ALL: { Named } = {
	{
		label = "AC-1",
		check = function(view)
			Contract.viewIsExactlyTheFiveClauseFilter(view, small)
		end,
	},
	{
		label = "AC-1/sight-order",
		check = function(view)
			Contract.lineOfSightIsConsultedLastAndAtMostOnce(view, small)
		end,
	},
	{ label = "AC-1/boundary", check = Contract.rangeIsInclusiveAtTheBoundaryAndIgnoresY },
	{
		label = "AC-2",
		check = function(view)
			Contract.distinctPlayersShareNoMachine(view, small)
		end,
	},
	{ label = "AC-3", check = Contract.noPositionIsEmptyAndConsultsNothing },
	{
		label = "AC-4",
		check = function(view)
			Contract.readingsHaveExactlyTheContractShape(view, small)
		end,
	},
	{ label = "AC-4/many", check = Contract.manyReadingsAscendByMachineId },
	{ label = "AC-5", check = Contract.darkRoomRemovesTheReading },
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

-- The extras tally of an audit, by clause, in the Contract's order.
local function extraTally(view: any): { [string]: number }
	return Contract.audit(view, small).extraBy
end

local function onlyClause(tally: { [string]: number }, clause: string, who: string)
	for _, name in Contract.CLAUSES do
		if name == clause then
			assert(tally[name] > 0, `{who}: no extra reading violates the {clause} clause`)
		else
			assert(
				tally[name] == 0,
				`{who}: {tally[name]} extra reading(s) violate the {name} clause, which this view gates`
			)
		end
	end
end

return {
	--[[ The baseline, and the sample it is measured on. ]]

	["baseline: the reference five-clause view passes every VIEW-001 check on the control sample, and the sample exercised every clause"] = function()
		failsExactly(Stubs.reference, "the reference view", {})
		local audit = Contract.audit(Stubs.reference, small)
		assert(audit.calls == 9000, `{audit.calls} calls over the control sample, expected 9000`)
		assert(audit.extra == 0 and audit.missing == 0, Contract.describeAudit(audit))
		-- MEASURED in RED over this seeded sub-sample; a different number is a
		-- change to the sample, which is a change to what the criterion is
		-- held over.
		assert(
			audit.nonEmptyExpected == 363,
			`{audit.nonEmptyExpected} non-empty expected views, measured 363`
		)
		for _, name in Contract.CLAUSES do
			assert(
				audit.soleExclusions[name] >= Contract.SOLE_EXCLUSIONS_PER_FACILITY * audit.cases,
				`clause {name} excluded only {audit.soleExclusions[name]} alone: `
					.. Contract.describeAudit(audit)
			)
		end
	end,

	["baseline: the full AC-1 sample is 600 facilities, 150000 calls, and holds the per-facility floors with room to spare"] = function()
		local full = Contract.sample()
		assert(#full == 600, `{#full} facilities, expected 200 at each of n = 4, 5, 6`)
		local audit = Contract.audit(Stubs.reference)
		assert(audit.calls == 150000, `{audit.calls} calls, expected 150000`)
		assert(audit.extra == 0 and audit.missing == 0, Contract.describeAudit(audit))
		-- MEASURED in RED. The floors are 600 sole exclusions per clause and
		-- 1800 non-empty views; the smallest measured clause is 2.6x its floor.
		assert(audit.nonEmptyExpected == 5392, `{audit.nonEmptyExpected} non-empty, measured 5392`)
		assert(
			audit.soleExclusions.lit == 2526,
			`lit alone excluded {audit.soleExclusions.lit}, measured 2526`
		)
		assert(
			audit.soleExclusions.committed == 1562,
			`committed alone excluded {audit.soleExclusions.committed}, measured 1562`
		)
		assert(
			audit.soleExclusions.sight == 2458,
			`sight alone excluded {audit.soleExclusions.sight}, measured 2458`
		)
	end,

	--[[ AC-1's two named controls. ]]

	["AC-1 control: a view gating on range only (any class) fails the class clause - every extra reading violates class and none violates range - and AC-2, since it reads other lenses' machines"] = function()
		local view = Stubs.rangeOnly
		failsExactly(view, "the range-only view", { "AC-1", "AC-1/sight-order", "AC-2" })
		local message = refuses(checkNamed("AC-1"), view, "range-only must fail AC-1")
		names(message, "AC-1", "the AC-1 check fires")
		names(
			message,
			"which violates: class",
			"the failure attributes an extra reading to the class clause"
		)
		onlyClause(extraTally(view), "class", "the range-only view")
		names(
			refuses(checkNamed("AC-2"), view, "range-only must fail AC-2"),
			"is read by both",
			"AC-2 names the machine two players share"
		)
	end,

	["AC-1 control: a view gating on class only (any range) fails the range clause - every extra reading violates range and none violates class"] = function()
		local view = Stubs.classOnly
		failsExactly(
			view,
			"the class-only view",
			{ "AC-1", "AC-1/sight-order", "AC-1/boundary", "AC-5" }
		)
		local message = refuses(checkNamed("AC-1"), view, "class-only must fail AC-1")
		names(
			message,
			"which violates: range",
			"the failure attributes an extra reading to the range clause"
		)
		onlyClause(extraTally(view), "range", "the class-only view")
	end,

	--[[ The other three clauses. ]]

	["AC-1 control: a view ignoring dark rooms fails the lit clause alone in AC-1, and AC-5 (D-2)"] = function()
		local view = Stubs.ignoreDark
		failsExactly(view, "the ignore-dark view", { "AC-1", "AC-1/sight-order", "AC-5" })
		names(
			refuses(checkNamed("AC-1"), view, "ignore-dark must fail AC-1"),
			"which violates: lit",
			"the failure attributes the extra reading to the lit clause"
		)
		onlyClause(extraTally(view), "lit", "the ignore-dark view")
		names(
			refuses(checkNamed("AC-5"), view, "ignore-dark must fail AC-5"),
			"after room 1 went dark",
			"AC-5 names the room that went dark"
		)
	end,

	["AC-1 control: a view ignoring committed machines fails the committed clause alone in AC-1"] = function()
		local view = Stubs.ignoreCommitted
		failsExactly(view, "the ignore-committed view", { "AC-1", "AC-1/sight-order", "AC-4/many" })
		names(
			refuses(checkNamed("AC-1"), view, "ignore-committed must fail AC-1"),
			"which violates: committed",
			"the failure attributes the extra reading to the committed clause"
		)
		onlyClause(extraTally(view), "committed", "the ignore-committed view")
	end,

	["AC-1 control: a view ignoring line of sight fails the sight clause alone in AC-1, and the call-order check because it never asks"] = function()
		local view = Stubs.ignoreSight
		failsExactly(view, "the ignore-sight view", { "AC-1", "AC-1/sight-order" })
		names(
			refuses(checkNamed("AC-1"), view, "ignore-sight must fail AC-1"),
			"which violates: sight",
			"the failure attributes the extra reading to the sight clause"
		)
		onlyClause(extraTally(view), "sight", "the ignore-sight view")
		names(
			refuses(checkNamed("AC-1/sight-order"), view, "ignore-sight never consults"),
			"lineOfSight was never consulted",
			"the call-order check says the view never asked"
		)
	end,

	--[[ D-1: the direction error. ]]

	["D-1 control: a view comparing against the player's own KEY class (keyClasses[p]) instead of Ring.lensOf fails AC-1 with every expected reading missing and as many extra"] = function()
		local view = Stubs.keyNotLens
		failsExactly(view, "the key-not-lens view", {
			"AC-1",
			"AC-1/sight-order",
			"AC-1/boundary",
			"AC-4/many",
			"AC-5",
		})
		local audit = Contract.audit(view, small)
		assert(
			audit.missing == 363 and audit.extra == 363,
			`measured 363 missing and 363 extra on the control sample; got {audit.missing} / {audit.extra}`
		)
		names(
			refuses(checkNamed("AC-1"), view, "key-not-lens must fail AC-1"),
			"missing reading of machine",
			"the failure names a missing reading"
		)
	end,

	--[[ D-3 and D-4: the boundary and the call order, which the random sample
	     CANNOT see - measured here, which is why the fixture and the spy exist. ]]

	["D-3 control: a strict (<) range passes AC-1's random sample and fails only the boundary check, at exactly the range"] = function()
		local view = Stubs.strictRange
		failsExactly(view, "the strict-range view", { "AC-1/boundary" })
		local message =
			refuses(checkNamed("AC-1/boundary"), view, "strict range must fail the boundary")
		names(
			message,
			"exactly the range (9 studs)",
			"the boundary failure names the exact-range stand"
		)
		names(
			message,
			"not inclusive at exactly lens_read_range_studs (9",
			"the message names the fixture's constant"
		)
	end,

	["D-3 control: a range read from MechanicsTuning (12) rather than procedure.tuning (9) passes the random sample and fails only the boundary check"] = function()
		local view = Stubs.shippedRange
		failsExactly(view, "the shipped-range view", { "AC-1/boundary" })
		names(
			refuses(checkNamed("AC-1/boundary"), view, "shipped range must fail the boundary"),
			"just past the range (9 + 0.001 studs)",
			"the boundary failure names the just-past stand, which a 12-stud range reads"
		)
	end,

	["D-3 control: a 3-D distance fails the boundary's y-offset stands and AC-1 (readings missing where y is drawn)"] = function()
		local view = Stubs.threeDRange
		failsExactly(view, "the 3-D-range view", { "AC-1", "AC-1/boundary" })
		names(
			refuses(checkNamed("AC-1/boundary"), view, "3-D range must fail the boundary"),
			"with y + 500",
			"the boundary failure names the y-offset stand"
		)
		local audit = Contract.audit(view, small)
		assert(
			audit.missing == 234 and audit.extra == 0,
			`measured 234 missing; got {audit.missing}`
		)
	end,

	["D-4 control: a view that asks line of sight before the class check fails only the call-order check, naming the clause the machine already failed"] = function()
		local view = Stubs.sightFirst
		failsExactly(view, "the sight-first view", { "AC-1/sight-order" })
		local message =
			refuses(checkNamed("AC-1/sight-order"), view, "sight-first must fail the call order")
		names(
			message,
			"which already fails: class",
			"the failure names a machine that already failed class"
		)
	end,

	["D-4 control: a view that asks line of sight twice per machine fails only the call-order check"] = function()
		local view = Stubs.sightTwice
		failsExactly(view, "the sight-twice view", { "AC-1/sight-order" })
		names(
			refuses(checkNamed("AC-1/sight-order"), view, "sight-twice must fail the call order"),
			"consulted 2 times for machine",
			"the failure counts the second call"
		)
	end,

	--[[ AC-3. ]]

	["AC-3 control: {} for a missing position (no readings key) fails AC-3 alone"] = function()
		local view = Stubs.nilPositionNotEmpty
		failsExactly(view, "the nil-position-not-empty view", { "AC-3" })
		names(
			refuses(checkNamed("AC-3"), view, "{} must fail AC-3"),
			"not exactly { readings = {} }",
			"AC-3 names the exact shape it wanted"
		)
	end,

	["AC-3 control: a view that consults line of sight with no position fails AC-3 alone"] = function()
		local view = Stubs.nilPositionConsultsSight
		failsExactly(view, "the nil-position-consults-sight view", { "AC-3" })
		names(
			refuses(checkNamed("AC-3"), view, "consulting with no position must fail AC-3"),
			"called lineOfSight",
			"AC-3 counts the calls"
		)
	end,

	--[[ AC-4. ]]

	["AC-4 control: an extra field on each reading fails AC-4, and every exact-view check with it"] = function()
		local view = Stubs.extraKeyOnReading
		failsExactly(view, "the extra-key-on-reading view", {
			"AC-1/boundary",
			"AC-4",
			"AC-4/many",
			"AC-5",
		})
		names(
			refuses(checkNamed("AC-4"), view, "an extra reading key must fail AC-4"),
			"has keys [machineId,room,setting], not exactly [machineId, setting]",
			"AC-4 lists the keys it found"
		)
	end,

	["AC-4 control: an extra field on the view fails AC-4, and every exact-view check with it"] = function()
		local view = Stubs.extraKeyOnView
		failsExactly(view, "the extra-key-on-view view", {
			"AC-1/boundary",
			"AC-4",
			"AC-4/many",
			"AC-5",
		})
		names(
			refuses(checkNamed("AC-4"), view, "an extra view key must fail AC-4"),
			"keys are [playerId,readings], not exactly [readings]",
			"AC-4 lists the view's keys"
		)
	end,

	["AC-4 control: a setting that is the tag rather than requiredSetting fails AC-4 and every exact-view check"] = function()
		local view = Stubs.settingIsTag
		failsExactly(view, "the setting-is-tag view", {
			"AC-1/boundary",
			"AC-4",
			"AC-4/many",
			"AC-5",
		})
		names(
			refuses(checkNamed("AC-4"), view, "a wrong setting must fail AC-4"),
			"requiredSetting is",
			"AC-4 names the machine's real setting"
		)
	end,

	["AC-4 control: readings in descending machineId pass every sample-based check - no generated view holds two readings - and fail the crowded-room check alone"] = function()
		local view = Stubs.descending
		failsExactly(view, "the descending view", { "AC-4/many" })
		local message =
			refuses(checkNamed("AC-4/many"), view, "descending must fail the crowded room")
		names(message, "ascending by machineId", "the failure says what order it wanted")
		names(
			message,
			"readings.1.machineId: expected 1, got 4",
			"the diff shows the reversed first entry"
		)
	end,

	["AC-4 control: readings in placement order, never sorted, pass every generated case - Machines.generate puts machines[i].id == i - and fail the crowded-room check alone, whose machines are listed 3, 1, 4, 2"] = function()
		local view = Stubs.listOrder
		failsExactly(view, "the list-order view", { "AC-4/many" })
		names(
			refuses(checkNamed("AC-4/many"), view, "list order must fail the crowded room"),
			"readings.2.machineId: expected 2, got 4",
			"the diff shows the placement's order (1, 4, 2 with 3 committed) where ascending is wanted"
		)
	end,

	["AC-4 control: the same readings list handed back on every call fails AC-4's freshness pin alone"] = function()
		local view = Stubs.sharedList
		failsExactly(view, "the shared-list view", { "AC-4" })
		names(
			refuses(checkNamed("AC-4"), view, "a shared list must fail AC-4"),
			"the same readings list was returned twice",
			"AC-4 names the aliasing"
		)
	end,

	--[[ AC-6's needle, probed both ways: the frontier-anchored pattern must
	     match the whole word and nothing containing it. ]]

	["AC-6 control: the whole-word matcher hits pairings and fragments as words, in backticks, brackets and at line ends, and reports the line"] = function()
		local text = table.concat({
			"--!strict",
			"-- what M3 adds: `pairings` (this player's lens contents) and",
			"-- `fragments` (order fragments)",
			"local view = {}",
			"-- (pairings) again, and fragments.",
			"return view",
		}, "\n")
		local p = Contract.wholeWordHits(text, "pairings")
		local f = Contract.wholeWordHits(text, "fragments")
		assert(
			table.concat(p, ",") == "2,5",
			`pairings hit lines {table.concat(p, ",")}, expected 2,5`
		)
		assert(
			table.concat(f, ",") == "3,5",
			`fragments hit lines {table.concat(f, ",")}, expected 3,5`
		)
	end,

	["AC-6 control: the whole-word matcher stays quiet on pairingsX, subfragments, my_pairings, fragments_ and pairings2"] = function()
		local text = table.concat({
			"local pairingsX = 1",
			"local subfragments = 2",
			"local my_pairings = 3",
			"local fragments_ = 4",
			"local pairings2 = 5",
			"-- repairings and fragmentsOf and _pairings",
		}, "\n")
		for _, word in { "pairings", "fragments" } do
			local hits = Contract.wholeWordHits(text, word)
			assert(
				#hits == 0,
				`"{word}" matched inside a longer identifier on line(s) {table.concat(hits, ",")}`
			)
		end
	end,

	["AC-6 control: the matcher finds the two stale words in the SEAT-002 header text verbatim, so the guard's red on arrival is the header and not an artefact"] = function()
		-- Lines 45-47 of Projection.luau as SEAT-002 wrote them.
		local header = table.concat({
			"\tWHAT M3 ADDS, and where: `pairings` (this player's lens contents) and",
			"\t`fragments` (this player's order fragments), both per-player secrets, both",
			"\tadded to the list below BY NAME.",
		}, "\n")
		-- Lines, not occurrences: `fragments` appears twice on its one line.
		local p = Contract.wholeWordHits(header, "pairings")
		local f = Contract.wholeWordHits(header, "fragments")
		assert(
			table.concat(p, ",") == "1",
			`pairings hit lines {table.concat(p, ",")} of the header text, expected 1`
		)
		assert(
			table.concat(f, ",") == "2",
			`fragments hit lines {table.concat(f, ",")} of the header text, expected 2`
		)
	end,
}
