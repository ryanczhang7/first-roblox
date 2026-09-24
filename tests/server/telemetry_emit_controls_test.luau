--!strict
--[[
	The negative controls for TEL-002, and the proof that each check in
	`tests/helpers/TelemetryEmitContract.luau` refuses the implementation it
	exists to catch.

	WHY THIS FILE CARRIES THE STORY'S EVIDENCE IN RED. The real machine emits
	nothing today, so against it AC-5 ("no bounce in Resolution or Post") and
	every "at most once" half of AC-1, AC-4, AC-6, AC-7 and AC-8 pass
	VACUOUSLY: a suite of checks that only ever saw an empty list has proved
	nothing about exactly-once. The wrong machines in `TelemetryEmitStubs.luau`
	emit - wrongly, one defect each - and this file records what each check
	actually did with them. The story's Contract §6 names five controls; every
	one is here, plus one measured for the deferred verification D2.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half
	is the one that is easy to leave out and worth the most: a stub that fails
	EVERY check proves only that the checks reject something, and a control
	that fails everything is indistinguishable from a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the number
	measured here rather than predicted, because the story's `## Notes` predict
	a single red test per mutation and GATES will run those mutations:

	  * `bouncingEverywhere` (D1) fails AC-5 AND AC-8, because a departure in
	    Resolution or Post that bounces has not emitted its `session_end` - and
	    AC-9, whose vacuity guard demands every emitter fired over the
	    lifecycle and finds `session_end` never did.
	  * `forgetfulLeave` (D2 as the Contract reads it) fails AC-6 AND AC-8:
	    the duplicate `PlayerLeft` in Post emits a second `session_end`.
	  * `noDepartedMap` (D2 taken literally) fails AC-6, AC-7 and AC-8 as well,
	    because the map also guards `first_round_complete` and
	    `rematch_accepted` (Contract P3).
	  * `realClock` (D3) fails AC-9 AND ROUND-003 AC-6's determinism, because
	    two identical steps stamped from a real clock return different effects.
	  * every wrong emitter but `realClock` fails the P5 golden sequence, which
	    jointly covers AC-1..AC-8 and is why it is not a control's target.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. The stubs wrap the merged
	`PhaseMachine` and build events with the merged `Event`, so the numbers
	below are measurements taken in RED rather than claims left for GREEN.
	GREEN confirms each measured fragment against the shipped module by running
	the story's deferred verifications D1-D3.
]]

local Stubs = require("../helpers/TelemetryEmitStubs")
local Telemetry = require("../helpers/TelemetryEmitContract")

-- The same fixture the real suite injects. See `telemetry_emit_test.luau`.
local CONFIG = {
	lobbySeconds = 3,
	postRoundSeconds = 2,
	roundSeconds = 20,
	playersMin = 4,
	playersMax = 6,
	minPlayersToContinue = 3,
}

type Check = (any, any) -> ()
type Named = { label: string, check: Check }

-- Every check the contract exports, so the baseline is asserted against ALL
-- of them and a check added later without a control is caught by name.
local CHECKS: { Named } = {
	{ label = "Contract §2 (sessionId)", check = Telemetry.initialCarriesTheSessionId },
	{ label = "AC-1", check = Telemetry.joinIsEmittedOncePerPlayerPerSession },
	{ label = "AC-2", check = Telemetry.roundCompleteIsEmittedOnceOnEnteringResolution },
	{ label = "AC-3", check = Telemetry.noContestIsDistinguishableFromALoss },
	{ label = "AC-4", check = Telemetry.bounceIsEmittedOnceForALeaverBeforeResolution },
	{ label = "AC-5", check = Telemetry.noBounceIsEmittedInResolutionOrPost },
	{ label = "AC-6", check = Telemetry.bounceIsEmittedOncePerDeparturePerRound },
	{ label = "AC-7", check = Telemetry.firstRoundCompleteIsEmittedOncePerPlayerPerSession },
	{ label = "AC-8", check = Telemetry.rematchAndSessionEndAreEmittedOnceInPost },
	{ label = "AC-9", check = Telemetry.everyEmitCarriesTheStepsNowAndAKnownName },
	{ label = "P5 (golden sequence)", check = Telemetry.lifecycleEmitsExactlyTheContractsSequence },
	{ label = "ROUND-003 AC-6 (purity)", check = Telemetry.emittingStepsArePureAndDeterministic },
}

local function accepts(check: Check, machine: any, what: string)
	local ok, err = pcall(check, machine, CONFIG)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: Check, machine: any, what: string): string
	local ok, err = pcall(check, machine, CONFIG)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

--[[
	Runs every check against a machine and returns the labels that refused
	it, sorted - the MEASURED footprint of a defect. Each control test asserts
	its footprint exactly, so a check that quietly stops seeing a defect, or a
	defect that quietly grows, both show up as a changed list.
]]
local function footprint(machine: any): { string }
	local refused: { string } = {}
	for _, named in CHECKS do
		local ok = pcall(named.check, machine, CONFIG)
		if not ok then
			table.insert(refused, named.label)
		end
	end
	table.sort(refused)
	return refused
end

local function sameList(actual: { string }, expected: { string }): boolean
	if #actual ~= #expected then
		return false
	end
	for index, item in expected do
		if actual[index] ~= item then
			return false
		end
	end
	return true
end

local function assertFootprint(machine: any, expected: { string }, what: string)
	local sorted = table.clone(expected)
	table.sort(sorted)
	local actual = footprint(machine)
	assert(
		sameList(actual, sorted),
		`{what}: the checks that refused it are [{table.concat(actual, ", ")}], measured; this `
			.. `file records [{table.concat(sorted, ", ")}]. A footprint that shrank is a check `
			.. `that stopped seeing the defect; one that grew belongs in the story's handoff`
	)
end

--[[
	The weak reading of AC-6 that `forgetfulLeave` is built to pass: after a
	departure and its duplicate, a bounce for that player WAS emitted. "At
	least one" is the assertion everybody writes; AC-6 says exactly one.
]]
local function weakABounceWasEmittedCheck(machine: any, config: any)
	local s = Telemetry.lobbyOf(machine, config, config.playersMin)
	Telemetry.toAssignment(s)
	s.apply(Telemetry.left("p4"), s.last + 0.125)
	s.apply(Telemetry.left("p4"), s.last + 0.125)
	assert(
		Telemetry.count(s.all(), "bounce_before_resolution", "p4") >= 1,
		"the weak check: no bounce_before_resolution for p4 at all"
	)
end

--[[
	The weak reading of AC-5 that `bouncingEverywhere` is built to pass: AC-4
	in full. A machine that bounces on every departure bounces on every
	departure before resolution too.
]]
local function weakAC4OnlyCheck(machine: any, config: any)
	Telemetry.bounceIsEmittedOnceForALeaverBeforeResolution(machine, config)
end

return {
	--[[ The baseline. Every control below is this machine with exactly one
	     defect set, so a control that fires is attributable to that one thing.
	     It is also the proof that the checks are BUILDABLE: a machine exists
	     that passes all of them at once. ]]

	["baseline: a machine emitting exactly what Contract §3 says passes every TEL-002 check"] = function()
		local machine = Stubs.emitting
		for _, named in CHECKS do
			accepts(named.check, machine, `{named.label} on the emitting machine`)
		end
	end,

	--[[
		AC-5's control, named in the criterion: bounce on every `PlayerLeft`.

		It passes AC-4 in full - "an implementation emitting on every PlayerLeft
		passes AC-4" - and fails AC-5. It also fails AC-8, because the departure
		in Resolution or Post that bounced did not emit its `session_end`; the
		golden sequence, for the same reason; and AC-9, whose vacuity guard
		requires all six emitters to have fired over the lifecycle and finds
		`session_end` never did. Measured, not predicted - and the AC-9 refusal
		is the guard doing its job, not `at` being wrong.
	]]
	["AC-5 control (D1): a machine that bounces on every PlayerLeft passes AC-4 and fails AC-5"] = function()
		local machine = Stubs.bouncingEverywhere
		accepts(weakAC4OnlyCheck, machine, "a machine that bounces everywhere still passes AC-4")
		accepts(
			Telemetry.joinIsEmittedOncePerPlayerPerSession,
			machine,
			"AC-1 on the bouncing machine"
		)
		accepts(
			Telemetry.roundCompleteIsEmittedOnceOnEnteringResolution,
			machine,
			"AC-2 on the bouncing machine"
		)
		accepts(
			Telemetry.bounceIsEmittedOncePerDeparturePerRound,
			machine,
			"AC-6 on the bouncing machine"
		)
		accepts(
			Telemetry.firstRoundCompleteIsEmittedOncePerPlayerPerSession,
			machine,
			"AC-7 on the bouncing machine"
		)
		names(
			refuses(
				Telemetry.everyEmitCarriesTheStepsNowAndAKnownName,
				machine,
				"AC-9's vacuity guard must notice that session_end never fired"
			),
			"but never session_end",
			"AC-9 refuses the bouncing machine for the missing emitter, not for at"
		)

		local message = refuses(
			Telemetry.noBounceIsEmittedInResolutionOrPost,
			machine,
			"a machine emitting bounce_before_resolution on every PlayerLeft must fail AC-5"
		)
		names(message, "AC-5", "the AC-5 control fires")
		-- The MEASURED emission: a bounce carrying the phase Resolution, where
		-- the Contract says session_end.
		names(
			message,
			"bounce_before_resolution<p1>{phase=Resolution}",
			"the AC-5 failure names the bounce the control actually emitted"
		)

		assertFootprint(
			machine,
			{ "AC-5", "AC-8", "AC-9", "P5 (golden sequence)" },
			"the bouncing machine"
		)
	end,

	--[[
		AC-6's control (D2, as the Contract reads it): `departed` is written
		but never consulted on a `PlayerLeft`.

		It passes the weak "a bounce was emitted" reading and AC-4 (one
		departure each, no duplicates) and AC-5 (no bounce after resolution).
		AC-6 refuses it on the ASSIGNMENT duplicate: the Round duplicate is
		refused by P1's seated gate on any machine, which is why AC-6 includes
		a phase in which the leaver stays seated. AC-8 refuses it too, on the
		duplicate `PlayerLeft` in Post.
	]]
	["AC-6 control (D2): a machine whose PlayerLeft never consults departed passes an at-least-one check and fails AC-6"] = function()
		local machine = Stubs.forgetfulLeave
		accepts(weakABounceWasEmittedCheck, machine, "a forgetful machine still emits a bounce")
		accepts(
			Telemetry.joinIsEmittedOncePerPlayerPerSession,
			machine,
			"AC-1 on the forgetful machine"
		)
		accepts(
			Telemetry.roundCompleteIsEmittedOnceOnEnteringResolution,
			machine,
			"AC-2 on the forgetful machine"
		)
		accepts(
			Telemetry.bounceIsEmittedOnceForALeaverBeforeResolution,
			machine,
			"AC-4 on the forgetful machine"
		)
		accepts(
			Telemetry.noBounceIsEmittedInResolutionOrPost,
			machine,
			"AC-5 on the forgetful machine"
		)
		accepts(
			Telemetry.firstRoundCompleteIsEmittedOncePerPlayerPerSession,
			machine,
			"AC-7 on the forgetful machine"
		)
		accepts(
			Telemetry.everyEmitCarriesTheStepsNowAndAKnownName,
			machine,
			"AC-9 on the forgetful machine"
		)

		local message = refuses(
			Telemetry.bounceIsEmittedOncePerDeparturePerRound,
			machine,
			"a machine that emits twice on a duplicate PlayerLeft must fail AC-6"
		)
		names(message, "AC-6", "the AC-6 control fires")
		-- The MEASURED count: a second bounce on the duplicate, where the
		-- Contract says none.
		names(
			message,
			"a duplicate PlayerLeft for p4, still seated in Assignment (the departed guard) emitted 1 telemetry event(s), wanted 0",
			"the AC-6 failure names the duplicate the control actually emitted on"
		)

		assertFootprint(
			machine,
			{ "AC-6", "AC-8", "P5 (golden sequence)" },
			"the forgetful machine"
		)
	end,

	--[[
		D2 taken literally: no `departed` map at all. Recorded so that GATES,
		running "remove the departed guard" against the real module, reads the
		footprint it should expect rather than a surprise: the map also stops
		an Assignment leaver collecting a `first_round_complete` (AC-7, P3) and
		a departed player a `rematch_accepted` (AC-8).
	]]
	["AC-6 control (D2, literal): a machine with no departed map fails AC-6, AC-7 and AC-8, measured"] = function()
		local machine = Stubs.noDepartedMap
		accepts(
			Telemetry.bounceIsEmittedOnceForALeaverBeforeResolution,
			machine,
			"AC-4 on the no-map machine"
		)
		accepts(
			Telemetry.noBounceIsEmittedInResolutionOrPost,
			machine,
			"AC-5 on the no-map machine"
		)

		names(
			refuses(
				Telemetry.bounceIsEmittedOncePerDeparturePerRound,
				machine,
				"AC-6 must refuse a machine with no departed map"
			),
			"AC-6",
			"AC-6 fires on the no-map machine"
		)
		names(
			refuses(
				Telemetry.firstRoundCompleteIsEmittedOncePerPlayerPerSession,
				machine,
				"AC-7 must refuse it too"
			),
			"AC-7",
			"AC-7 fires on the no-map machine (the Assignment leaver collected a first_round_complete)"
		)

		assertFootprint(
			machine,
			{ "AC-6", "AC-7", "AC-8", "P5 (golden sequence)" },
			"the no-map machine"
		)
	end,

	--[[
		AC-9's control, named in the criterion: `at` from a real clock.

		Every SHAPE it emits is right, so AC-1 to AC-8 and the golden sequence -
		all of which drop `at` - are green for it. Only AC-9 reads `at`, and
		ROUND-003 AC-6's determinism check sees it too, because two identical
		steps stamped from a real clock return different effects.
	]]
	["AC-9 control (D3): a machine stamping at from os.clock passes every shape check and fails AC-9 under a manual clock"] = function()
		local machine = Stubs.realClock
		for _, named in CHECKS do
			if named.label ~= "AC-9" and named.label ~= "ROUND-003 AC-6 (purity)" then
				accepts(named.check, machine, `{named.label} on the real-clock machine`)
			end
		end

		local message = refuses(
			Telemetry.everyEmitCarriesTheStepsNowAndAKnownName,
			machine,
			"a machine reading a real clock for at must fail AC-9 under a manual clock"
		)
		names(message, "AC-9", "the AC-9 control fires")
		-- The MEASURED result: EVERY event's at is wrong, not one of them - a
		-- dyadic fraction handed in by a manual clock never equals os.clock().
		names(
			message,
			"22 of 22 event(s) carry an at that is not the now of the step",
			"the AC-9 failure counts every event the lifecycle emitted"
		)

		assertFootprint(machine, { "AC-9", "ROUND-003 AC-6 (purity)" }, "the real-clock machine")
	end,

	--[[
		AC-1's control (d): `join` on every `PlayerJoined`, including the ones
		the lobby refused.
	]]
	["AC-1 control: a machine emitting join on every PlayerJoined fails AC-1 on the duplicate"] = function()
		local machine = Stubs.joiningTwice
		accepts(
			Telemetry.roundCompleteIsEmittedOnceOnEnteringResolution,
			machine,
			"AC-2 on the joining-twice machine"
		)
		accepts(
			Telemetry.bounceIsEmittedOnceForALeaverBeforeResolution,
			machine,
			"AC-4 on the joining-twice machine"
		)
		accepts(
			Telemetry.noBounceIsEmittedInResolutionOrPost,
			machine,
			"AC-5 on the joining-twice machine"
		)
		accepts(
			Telemetry.bounceIsEmittedOncePerDeparturePerRound,
			machine,
			"AC-6 on the joining-twice machine"
		)
		accepts(
			Telemetry.rematchAndSessionEndAreEmittedOnceInPost,
			machine,
			"AC-8 on the joining-twice machine"
		)
		accepts(
			Telemetry.everyEmitCarriesTheStepsNowAndAKnownName,
			machine,
			"AC-9 on the joining-twice machine"
		)

		local message = refuses(
			Telemetry.joinIsEmittedOncePerPlayerPerSession,
			machine,
			"a machine emitting join on a duplicate PlayerJoined must fail AC-1"
		)
		names(message, "AC-1", "the AC-1 control fires")
		-- The MEASURED emission: a second join for p1 on the duplicate.
		names(
			message,
			"a duplicate PlayerJoined for p1, already seated emitted 1 telemetry event(s), wanted 0",
			"the AC-1 failure names the duplicate the control actually emitted on"
		)

		assertFootprint(machine, { "AC-1", "P5 (golden sequence)" }, "the joining-twice machine")
	end,

	--[[
		AC-7's control (e): `first_round_complete` for every seated player on
		every resolving step.

		In a first round with nobody departed that IS the Contract's list, so
		AC-2 - which resolves first rounds only - is green for it. AC-7 drives a
		second round and an Assignment leaver, and both tell it apart.
	]]
	["AC-7 control: a machine emitting first_round_complete for every seated player every round passes AC-2 and fails AC-7"] = function()
		local machine = Stubs.firstRoundForEveryone
		accepts(
			Telemetry.joinIsEmittedOncePerPlayerPerSession,
			machine,
			"AC-1 on the everyone machine"
		)
		accepts(
			Telemetry.roundCompleteIsEmittedOnceOnEnteringResolution,
			machine,
			"AC-2 on the everyone machine"
		)
		accepts(
			Telemetry.noContestIsDistinguishableFromALoss,
			machine,
			"AC-3 on the everyone machine"
		)
		accepts(
			Telemetry.bounceIsEmittedOnceForALeaverBeforeResolution,
			machine,
			"AC-4 on the everyone machine"
		)
		accepts(
			Telemetry.noBounceIsEmittedInResolutionOrPost,
			machine,
			"AC-5 on the everyone machine"
		)
		accepts(
			Telemetry.bounceIsEmittedOncePerDeparturePerRound,
			machine,
			"AC-6 on the everyone machine"
		)
		accepts(
			Telemetry.rematchAndSessionEndAreEmittedOnceInPost,
			machine,
			"AC-8 on the everyone machine"
		)
		accepts(
			Telemetry.everyEmitCarriesTheStepsNowAndAKnownName,
			machine,
			"AC-9 on the everyone machine"
		)

		local message = refuses(
			Telemetry.firstRoundCompleteIsEmittedOncePerPlayerPerSession,
			machine,
			"a machine emitting first_round_complete for everybody must fail AC-7"
		)
		names(message, "AC-7", "the AC-7 control fires")
		-- The MEASURED emission: the Assignment leaver p4, who the Contract
		-- (P3) says earns nothing, at index 5 of round one's list.
		names(
			message,
			"got first_round_complete<p4>{roundId=round-TEL-002-a,scope=session}",
			"the AC-7 failure names the first_round_complete the control wrongly emitted"
		)

		assertFootprint(machine, { "AC-7", "P5 (golden sequence)" }, "the everyone machine")
	end,
}
