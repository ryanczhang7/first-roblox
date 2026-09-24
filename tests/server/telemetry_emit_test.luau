--!strict
--[[
	TEL-002: the round lifecycle emits the B6 events a server round can observe.
	AC-1 through AC-9, applied to the real machine.

	THIS IS NOT AN ORDINARY RED. `src/server/round/PhaseMachine.luau` is merged
	(ROUND-003 to ROUND-005), so this file LOADS, every assertion in it RUNS,
	and the failures are real assertion failures - "emitted 0 telemetry
	event(s), wanted 1" - rather than one import error wearing nine criteria.
	Two consequences, both recorded in the story:

	  * AGAINST A MACHINE THAT EMITS NOTHING, AC-5 and every "at most once"
	    half of AC-1, AC-4, AC-6, AC-7 and AC-8 pass VACUOUSLY. So the checks
	    live in `tests/helpers/TelemetryEmitContract.luau` and
	    `tests/server/telemetry_emit_controls_test.luau` runs them against the
	    deliberately wrong machines in `TelemetryEmitStubs.luau`, where each
	    one is OBSERVED refusing the implementation it exists to catch. That
	    file is green in RED and its refusals are the story's evidence.
	  * nothing here is green on arrival. Every test below demands an `Emit`
	    the machine does not produce, or a `sessionId` `initial` does not take.

	THE CENTRAL RISK IS EXACTLY-ONCE. Five of the nine criteria are about an
	event firing once rather than twice or never, and "drive the lifecycle,
	assert the event is present" cannot see a double emission. Every check
	asserts the WHOLE list of telemetry a step produced, and the lifecycle
	checks count over the whole run.

	THE CONFIG IS INJECTED AND TINY, and it is deliberately the SAME fixture
	`phase_machine_test.luau`, `lobby_gate_test.luau` and `round_ending_test.luau`
	use. Nothing here calibrates a number: every threshold is read out of
	`CONFIG` through the checks in the contract helper.
]]

local PhaseMachine = require("../../src/server/round/PhaseMachine")
local Telemetry = require("../helpers/TelemetryEmitContract")

local Machine: any = PhaseMachine

-- Fixture durations and thresholds, not specification values. See the header.
local CONFIG = {
	lobbySeconds = 3,
	postRoundSeconds = 2,
	roundSeconds = 20,
	playersMin = 4,
	playersMax = 6,
	minPlayersToContinue = 3,
}

return {
	--[[ The Contract's shape change, pinned first: a wrong guess here is a
	     compile error in GREEN rather than a puzzle. ]]

	["Contract §2: initial takes a sessionId as its 4th argument and every state carries it unchanged, Post -> Lobby included"] = function()
		Telemetry.initialCarriesTheSessionId(Machine, CONFIG)
	end,

	--[[ AC-1. Whole lists per join; one join per player per session. ]]

	["AC-1: an accepted PlayerJoined emits exactly one join (D1) for that player, and a duplicate, a refused or a rejoining PlayerJoined emits none"] = function()
		Telemetry.joinIsEmittedOncePerPlayerPerSession(Machine, CONFIG)
	end,

	--[[ AC-2. The step that enters Resolution, by each of the three paths. ]]

	["AC-2: entering Resolution by event, clock or quorum emits exactly one round_complete (D2_7) carrying result, reason and roundId, and no later step emits another"] = function()
		Telemetry.roundCompleteIsEmittedOnceOnEnteringResolution(Machine, CONFIG)
	end,

	--[[ AC-3. The field a retention report reads. ]]

	["AC-3: a no_contest round's round_complete carries result no_contest and is distinguishable from a clock loss by that field alone"] = function()
		Telemetry.noContestIsDistinguishableFromALoss(Machine, CONFIG)
	end,

	--[[ AC-4. Settled by A5 and the Contract; the control is in the controls
	     suite. ]]

	["AC-4: a seated player leaving in Lobby, Assignment or Round emits exactly one bounce_before_resolution (D1) carrying the phase, and a never-seated player emits none"] = function()
		Telemetry.bounceIsEmittedOnceForALeaverBeforeResolution(Machine, CONFIG)
	end,

	--[[ AC-5. The criterion names its control: bounce on every PlayerLeft.
	     Against today's machine this is GREEN ONLY BECAUSE nothing is emitted;
	     the controls suite is where it is seen to refuse. ]]

	["AC-5: a player leaving in Resolution or Post emits no bounce_before_resolution, counted over the whole post-resolution sequence"] = function()
		Telemetry.noBounceIsEmittedInResolutionOrPost(Machine, CONFIG)
	end,

	--[[ AC-6. Once per departure per round: the Round duplicate, the
	     Assignment duplicate (the departed guard's own case) and the next
	     round. ]]

	["AC-6: a duplicate PlayerLeft emits no second bounce_before_resolution in the same round, and a player who leaves in two rounds bounces once per round"] = function()
		Telemetry.bounceIsEmittedOncePerDeparturePerRound(Machine, CONFIG)
	end,

	--[[ AC-7. Per session, said in the payload; the P3 Assignment leaver and
	     the P2a rejoiner both included. ]]

	["AC-7: the resolving step emits exactly one first_round_complete (D1, scope = session) per seated first-rounder, none for a later-round player or an Assignment leaver"] = function()
		Telemetry.firstRoundCompleteIsEmittedOncePerPlayerPerSession(Machine, CONFIG)
	end,

	--[[ AC-8. Post's two events, with every guard exercised. ]]

	["AC-8: a RematchAccepted in Post emits exactly one rematch_accepted (D2_7) per player per round, and a player leaving in Resolution or Post emits exactly one session_end (D1)"] = function()
		Telemetry.rematchAndSessionEndAreEmittedOnceInPost(Machine, CONFIG)
	end,

	--[[ AC-9. A manual clock through non-integer nows, every emitter fired. ]]

	["AC-9: over a two-round lifecycle on a manual clock every Emit's at is the step's now, every name is in Event.BUCKETS under its bucket, and every sessionId is the one given"] = function()
		Telemetry.everyEmitCarriesTheStepsNowAndAKnownName(Machine, CONFIG)
	end,

	--[[ Contract §3 P5, over the whole lifecycle: the golden sequence. ]]

	["P5: a two-round lifecycle emits exactly the Contract's telemetry sequence, in order"] = function()
		Telemetry.lifecycleEmitsExactlyTheContractsSequence(Machine, CONFIG)
	end,

	--[[ ROUND-003 AC-6 on the steps that now emit. ]]

	["ROUND-003 AC-6: every emitting step is still pure and deterministic"] = function()
		Telemetry.emittingStepsArePureAndDeterministic(Machine, CONFIG)
	end,
}
