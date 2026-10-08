--!strict
--[[
	The negative controls for SLICE-005, and the proof that each check in
	`tests/helpers/SessionRoundContract.luau` means what it says.

	NOTHING HERE REQUIRES THIS STORY'S PRODUCTION CODE. In RED
	`src/server/session/Session.luau` holds none of the round behaviour, every
	test in `tests/server/session_round_test.luau` fails before most of its
	assertions run, and so not one of that file's checks has been observed to
	accept or reject anything. The stand-ins below need only the merged pure
	modules, so what is asserted here is MEASURED in RED rather than claimed
	for GREEN. The story's handoff carries the table.

	THE STAND-INS live in `tests/helpers/SessionRoundStubs.luau` (moved there
	by VIEW-004, which aims the same stand-ins at its own session-level
	checks). `standIn(defects)` is a small implementation of the Contract
	(SLICE-003's behaviour plus C-2..C-5, and VIEW-004's Positions wiring
	through `PositionsStubs.reference`) with named defects switched on. With
	none it is the REFERENCE, the positive control: every check must ACCEPT
	it - SLICE-003's battery included, which is where C-6's narrowed
	`passThroughOf` is seen to tolerate `Placed` - or the check (or the plan)
	is wrong and the fix belongs HERE, in RED. Each control is the reference
	with EXACTLY ONE defect, and pins the set of checks that fire EXACTLY.

	THE STORY NAMES ITS CONTROLS: a session that ticks the Procedure but feeds
	RoundResolved only on the NEXT tick (AC-6's penalised cases; k = 0 stays
	green, which the test asserts on the message), one that routes outcomes
	only on Tick and never on a turn (D-2's shape), one whose secondsLeft uses
	config.roundSeconds (D-3's shape; SLICE-003's payload check stays green),
	one that passes `{}` as the turn's positions, one that generates from a
	seed that is not the AssignSeats effect's, one that emits Placed at the
	wrong place. D-1..D-4 THEMSELVES mutate the real module and stay with GATES.

	VIEW-004 REWROTE THE SAMPLE CONTROLS. SLICE-005's `mergesSamples` defect
	is gone - a merge IS the rule now - and its place is taken by
	`replacesSamples` (SLICE-005's own store, which VIEW-004's rewritten C-3
	check must refuse) and `storesRawSamples` (D-3's shape, a store past the
	plausibility rule; on the tolerance-free lifecycle it is caught only by
	the empty-Lobby sample, which has no baseline). The rest of VIEW-004's
	session-level controls are in `tests/server/positions_controls_test.luau`.

	WHAT THE REFERENCE IS NOT: `src/server/session/Session.luau`, or a sketch
	of one. GREEN writes the module from the story's Contract; nothing here is
	to be copied.
]]

local Deep = require("../helpers/Deep")
local Generator = require("../../src/server/facility/Generator")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")
local RoundContract = require("../helpers/SessionRoundContract")
local ScriptedRound = require("../helpers/ScriptedRound")
local SessionContract = require("../helpers/SessionContract")
local SessionRoundStubs = require("../helpers/SessionRoundStubs")

local standIn = SessionRoundStubs.standIn

local function contains(list: { string }, item: string): boolean
	return table.find(list, item) ~= nil
end

local reference = standIn({})

local function failingNames(S: any): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in RoundContract.failures(S) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(who: string, S: any, expected: { string }): { [string]: string }
	local names, messages = failingNames(S)
	local want = table.clone(expected)
	table.sort(want)
	print(`        [measured] {who} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`{who} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{table.concat(
				shown,
				"\n"
			)}`,
			0
		)
	end
	local byName: { [string]: RoundContract.Check } = {}
	for _, check in RoundContract.CHECKS do
		byName[check.name] = check
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac, 1, true) ~= nil,
			`{who}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end
	return messages
end

local NEW = "newHoldsNoFacilityNoProcedureEmptyPositionsAndAcceptsOptions"
local FOLLOWS = "roundFacilityProcedureAndPositionsFollowTheOracleOnEveryStep"
local GEN = "generatesTheFacilityFromTheDealSeedAndStartsTheProcedureAtThatStep"
local PLACED = "placesEverySeatedPlayerAtTheSpawnRoomCentreInSeatOrder"
local GENFAIL = "resolvesAFailedGenerationAsNoContestInTheDealingStep"
local TURN = "handlesATurnAgainstTheStoredPositionsAndRepliesToTheCallerAlone"
local SAMPLES = "mergesAcceptedSamplesAndEmitsOnlyResyncPlacements"
local IGNORES = "ignoresATurnOutsideRoundOrWithoutAProcedure"
local CLEARS = "clearsFacilityAndProcedureOnEnteringLobbyAndKeepsPositions"
local ORDER = "ordersPassThroughPlacedSeatViewsTurnResultThenRoundViewLast"
local SECONDS = "secondsLeftReadsTheProcedureDeadlineInRound"
local WIN = "winsEveryScriptedRoundInTheStepThatTakesTheCompletingTurn"
local SPAWN = "neverWinsFromTheSpawnRoomAndLosesToTheClock"
local INSTAB = "losesByInstabilityOnTheMaxThWrongTurnWithThePenaltyOnTheNextRoundView"
local CLOCK = "losesByTheClockOnTheProcedureDeadlineAtEveryPenaltyLevel"
local PURE = "stepMutatesNeitherStateNorEventOnRoundEvents"

local SLICE3_PASS = "passesThroughTheMachinesEffectsUnchangedInOrderAndConsumesAssignSeats"
local SLICE3_PAYLOAD = "roundViewCarriesExactlyTheTenKeysWithACeilingSecondsLeftFromConfig"

-- An unrouted clock-out leaves the lifecycle in Round past its penalised
-- deadline, so every pin on the second half of the plan (the ignored turns in
-- Resolution and Post, the clearing, the second deal and its Placed, the
-- order and the secondsLeft of its RoundView) fires as a cascade; the
-- machine's own backstop ends that round late. The sharp assertion is the
-- AC-6 message: every penalised k named, k = 0 not.
local LATE_ROUTING_CASCADE = { CLOCK, FOLLOWS, SECONDS, CLEARS, GEN, IGNORES, ORDER, PLACED }

-- With no turn ever in reach, no point is ever charged: the lifecycle's
-- penalised deadline never comes, the round runs to the backstop, and the
-- late-routing cascade above follows - plus the three scripts that need a
-- turn to land (the win, the loss by instability, the penalised clock).
local NO_REACH_CASCADE =
	{ TURN, FOLLOWS, SECONDS, WIN, INSTAB, CLOCK, CLEARS, GEN, IGNORES, ORDER, PLACED }

local function slice3Failures(S: any): { string }
	local names: { string } = {}
	for _, f in SessionContract.failures(S) do
		table.insert(names, f.name)
	end
	table.sort(names)
	return names
end

return {
	--[[ ================================================================
	     The reference. Everything below is this stand-in with one defect.
	     ================================================================ ]]

	["baseline: the reference stand-in passes every check in SessionRoundContract AND every SLICE-003 check in SessionContract - C-6's narrowed passThroughOf tolerates the Placed effects it emits"] = function()
		local names, messages = failingNames(reference)
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		if #names > 0 then
			error(
				`the reference fails {#names} SLICE-005 check(s), so the check or the plan is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		local old = slice3Failures(reference)
		if #old > 0 then
			local shownOld: { string } = {}
			for _, f in SessionContract.failures(reference) do
				table.insert(shownOld, `{f.name}: {f.message}`)
			end
			error(
				`the reference fails {#old} SLICE-003 check(s):\n{table.concat(shownOld, "\n")}`,
				0
			)
		end
		print(
			`        [measured] reference fails 0 of {#RoundContract.CHECKS} SLICE-005 checks and 0 of {#SessionContract.CHECKS} SLICE-003 checks`
		)
	end,

	--[[ ================================================================
	     The plans' and scripts' assumptions, checked against their source.
	     ================================================================ ]]

	["fixtures: the baselines the scripts rely on hold - every seed 1..50 at n = 4, 5, 6 generates on attempt 1, no machine is within turn_range_studs of the spawn centre, the lifecycle's penalised deadline lands before the backstop and on a whole second, and the reset window and dial range leave a wrong setting to turn"] = function()
		local t = MechanicsTuning
		local c = RoundContract.config()
		local problems: { string } = {}
		local minDistance = math.huge
		for _, n in RoundContract.PLAYER_COUNTS do
			for seed = 1, RoundContract.SEEDS do
				local players = table.move(RoundContract.PLAYERS, 1, n, 1, {})
				local a = Ring.assign(players, Rng.fromSeed(seed))
				local r = Generator.generate(a, seed, t)
				if r.kind ~= "facility" then
					table.insert(problems, `seed {seed} at n = {n} failed to generate`)
					continue
				end
				local centre = ScriptedRound.spawnCentre(r.facility, t)
				for _, m in r.facility.placement.machines do
					local p = Machines.positionOf(r.facility.layout, m, t)
					minDistance = math.min(
						minDistance,
						math.sqrt((p.x - centre.x) ^ 2 + (p.z - centre.z) ^ 2)
					)
				end
			end
		end
		print(
			`        [measured] nearest machine to a spawn centre: {minDistance} studs; turn_range_studs {t.instance.turn_range_studs}`
		)
		if minDistance <= t.instance.turn_range_studs then
			table.insert(
				problems,
				`a machine sits {minDistance} studs from a spawn centre, inside turn_range_studs {t.instance.turn_range_studs}; the AC-4 control could win`
			)
		end
		local penalty = t.actuation.instability_clock_penalty_seconds
		if penalty <= 0 or penalty % 1 ~= 0 or c.roundSeconds % 1 ~= 0 then
			table.insert(
				problems,
				`penalty {penalty} / roundSeconds {c.roundSeconds} are not whole positive seconds; the deadline ticks would miss`
			)
		end
		if (t.actuation.instability_max - 1) * penalty >= c.roundSeconds - 110 then
			table.insert(
				problems,
				"the maximum penalty reaches back past the lifecycle's last Round step"
			)
		end
		if t.instance.dial_settings < 2 then
			table.insert(problems, "dial_settings < 2: no wrong setting exists")
		end
		if t.actuation.instability_per_wrong_value ~= 1 then
			table.insert(
				problems,
				`instability_per_wrong_value is {t.actuation.instability_per_wrong_value}; the scripts count one point per wrong turn`
			)
		end
		assert(#problems == 0, `the fixtures no longer hold:\n{table.concat(problems, "\n")}`)
	end,

	["fixtures: driven through the reference, the lifecycle's oracle resolves committed, wrong_setting, not_key_holder, unknown_machine and out_of_reach turns, charges exactly one point, and ends the Round on the Procedure's penalised deadline, 20 s before the backstop"] = function()
		local steps = RoundContract.run(reference, "fixtures", RoundContract.lifecycle())
		local kinds: { string } = {}
		local resolvedAt: number? = nil
		local penalty: number? = nil
		for _, step in steps do
			if step.meta.turn then
				local r = step.meta.turn.result
				table.insert(kinds, if r.reason then `{r.kind}/{r.reason}` else r.kind)
			end
			if step.meta.routed and step.event.kind == "Tick" then
				resolvedAt = step.now
				penalty = step.oracleBefore.procedure.penaltySeconds
			end
		end
		print(
			`        [measured] lifecycle turns: {Deep.show(kinds)}; routed clock-out at {Deep.show(
				resolvedAt
			)} with {Deep.show(penalty)} s of penalty`
		)
		assert(
			Deep.equal(kinds, {
				"committed",
				"rejected/wrong_setting",
				"refused/not_key_holder",
				"refused/unknown_machine",
				"refused/out_of_reach",
			}),
			`turn results are {Deep.show(kinds)}`
		)
		local c = RoundContract.config()
		assert(
			penalty == MechanicsTuning.actuation.instability_clock_penalty_seconds,
			`penalty {Deep.show(penalty)}`
		)
		assert(
			resolvedAt == c.lobbySeconds + c.roundSeconds - (penalty :: number),
			`resolved at {Deep.show(resolvedAt)}`
		)
	end,

	--[[ ================================================================
	     Routing: the story's controls, D-1's and D-2's shapes.
	     ================================================================ ]]

	["control (the story's, AC-6): a session that ticks the Procedure but feeds RoundResolved only on the NEXT tick fails the clock check on every penalised k and NOT on k = 0 (the backstop's tick); the lifecycle's unrouted clock-out cascades into the follows, secondsLeft, clears, second-deal, ignored-turn, order and Placed checks"] = function()
		local messages = expectFires(
			"routesTickOutcomeOnNextTickOnly",
			standIn({ routesTickOutcomeOnNextTickOnly = true }),
			LATE_ROUTING_CASCADE
		)
		local clock = messages[CLOCK]
		for k = 1, MechanicsTuning.actuation.instability_max - 1 do
			assert(
				string.find(clock, `k = {k} `, 1, true) ~= nil,
				`the AC-6 failure does not name k = {k}:\n{clock}`
			)
		end
		assert(
			string.find(clock, "k = 0 ", 1, true) == nil,
			`the AC-6 failure names k = 0, which the backstop should keep green:\n{clock}`
		)
	end,

	["control (D-1's shape): a session whose Tick path never feeds RoundResolved fails the same set as the late router - the backstop still ends the k = 0 round"] = function()
		local messages = expectFires(
			"skipsRoutingOnTick",
			standIn({ skipsRoutingOnTick = true }),
			LATE_ROUTING_CASCADE
		)
		assert(
			string.find(messages[CLOCK], "k = 0 ", 1, true) == nil,
			`k = 0 fired:\n{messages[CLOCK]}`
		)
	end,

	["control (D-2's shape): a session that routes outcomes only on Tick, never on the turn that produced them, fails exactly AC-4's and AC-5's same-step assertions, and nothing about the clock"] = function()
		local messages = expectFires(
			"skipsRoutingOnTurn",
			standIn({ skipsRoutingOnTurn = true }),
			{ WIN, INSTAB }
		)
		assert(string.find(messages[WIN], "IN THAT STEP", 1, true) ~= nil, messages[WIN])
		assert(string.find(messages[INSTAB], "IN THAT STEP", 1, true) ~= nil, messages[INSTAB])
	end,

	["control: a session that advances the Procedure BEFORE the machine takes the Tick moves a clock-ended round straight on to Post - the follows, clock (phase at the resolving tick) and spawn-control checks fire, and so does SLICE-003's round-follows check"] = function()
		local messages = expectFires(
			"procedureBeforeMachine",
			standIn({ procedureBeforeMachine = true }),
			{ FOLLOWS, CLOCK, SPAWN }
		)
		assert(string.find(messages[CLOCK], "expected Resolution", 1, true) ~= nil, messages[CLOCK])
		local old = slice3Failures(standIn({ procedureBeforeMachine = true }))
		assert(
			contains(old, "roundStateFollowsThePhaseMachineOnEveryStep"),
			`SLICE-003 fired {Deep.show(old)}`
		)
	end,

	--[[ ================================================================
	     C-5: secondsLeft.
	     ================================================================ ]]

	["control (D-3's shape): a session whose Round secondsLeft uses config.roundSeconds fails AC-5's drop and the C-5 check, and passes SLICE-003's payload check"] = function()
		expectFires(
			"secondsLeftFromConfig",
			standIn({ secondsLeftFromConfig = true }),
			{ INSTAB, SECONDS }
		)
		local old = slice3Failures(standIn({ secondsLeftFromConfig = true }))
		assert(
			not contains(old, SLICE3_PAYLOAD),
			`SLICE-003's payload check fired on config-based secondsLeft: {Deep.show(old)}`
		)
		assert(#old == 0, `SLICE-003 fired {Deep.show(old)}`)
	end,

	--[[ ================================================================
	     AC-3: the turn.
	     ================================================================ ]]

	["control (the story's, AC-3): a session that passes {} as the turn's positions fails the turn check (the in-reach turn is refused out_of_reach), every script that needs a turn to land, and - with no penalty ever charged - the lifecycle's clock-out cascade"] = function()
		local messages = expectFires(
			"turnsWithEmptyPositions",
			standIn({ turnsWithEmptyPositions = true }),
			NO_REACH_CASCADE
		)
		assert(string.find(messages[TURN], "out_of_reach", 1, true) ~= nil, messages[TURN])
		assert(string.find(messages[WIN], "expected committed", 1, true) ~= nil, messages[WIN])
	end,

	["control: a session that judges turns against the Placed centres, ignoring every sample, fails the same set - no machine is in reach of a room centre"] = function()
		local messages = expectFires(
			"turnsWithPlacedPositions",
			standIn({ turnsWithPlacedPositions = true }),
			NO_REACH_CASCADE
		)
		assert(string.find(messages[TURN], "out_of_reach", 1, true) ~= nil, messages[TURN])
	end,

	["control: a session that sends the TurnResult to every seated player fails exactly the turn check"] = function()
		expectFires(
			"sendsTurnResultToEveryone",
			standIn({ sendsTurnResultToEveryone = true }),
			{ TURN }
		)
	end,

	["control: a session that broadcasts a RoundView on every turn fails exactly the turn check (a Broadcast on a turn whose phase did not change)"] = function()
		expectFires("broadcastsOnEveryTurn", standIn({ broadcastsOnEveryTurn = true }), { TURN })
	end,

	--[[ ================================================================
	     C-3: samples (rewritten by VIEW-004).
	     ================================================================ ]]

	["control (SLICE-005's own store): a session that REPLACES the accepted positions with the batch fails the samples check (players absent from a batch are dropped) and the follows check; the turn check holds, because the lifecycle's out_of_reach turn is reached by walking away rather than by omission"] = function()
		local messages = expectFires(
			"replacesSamples",
			standIn({ replacesSamples = true }),
			{ SAMPLES, FOLLOWS }
		)
		assert(
			string.find(messages[SAMPLES], "absent from the batch", 1, true) ~= nil
				or string.find(messages[SAMPLES], "merged", 1, true) ~= nil,
			messages[SAMPLES]
		)
	end,

	["control (D-3's shape): a session that stores every sample past the plausibility rule fails the samples check and the follows check on the empty-Lobby sample alone (no baseline, yet stored); every Round sample in the lifecycle is walkable, which is why VIEW-004's implausible cases live in positions_controls_test"] = function()
		local messages = expectFires(
			"storesRawSamples",
			standIn({ storesRawSamples = true }),
			{ SAMPLES, FOLLOWS }
		)
		assert(
			string.find(messages[SAMPLES], "sample in an empty Lobby", 1, true) ~= nil,
			messages[SAMPLES]
		)
	end,

	["control: a session that stores event.samples' tables by reference fails exactly the samples check"] = function()
		expectFires(
			"storesSamplesByReference",
			standIn({ storesSamplesByReference = true }),
			{ SAMPLES }
		)
	end,

	--[[ ================================================================
	     AC-1: the facility, the Procedure, the Placed.
	     ================================================================ ]]

	["control (the story's, AC-1): a session that generates every round from the session's initial seed fails the generate check on the SECOND deal only, the follows check, and the Placed check (the second facility's spawn room differs) - the first round, where the seeds coincide, is clean"] = function()
		local messages = expectFires(
			"generatesFromTheSessionSeed",
			standIn({ generatesFromTheSessionSeed = true }),
			{ GEN, FOLLOWS, PLACED }
		)
		assert(
			string.find(messages[GEN], "deal 2", 1, true) ~= nil
				and string.find(messages[GEN], "deal 1", 1, true) == nil,
			messages[GEN]
		)
	end,

	["control: a session that generates from a fixed seed 0 fails the generate check on BOTH deals; the oracle's machines are not the subject's, so the lifecycle's in-reach turns miss and the no-penalty cascade follows (the scripts, which read the subject's own facility, still win)"] = function()
		local messages = expectFires(
			"generatesFromAFixedSeed",
			standIn({ generatesFromAFixedSeed = true }),
			{ GEN, FOLLOWS, PLACED, TURN, SECONDS, CLEARS, IGNORES, ORDER }
		)
		assert(string.find(messages[GEN], "deal 1", 1, true) ~= nil, messages[GEN])
	end,

	["control (the story's, AC-1): a session that places everyone at the first machine instead of the spawn room's centre fails the Placed check and the follows check (positions), and nothing else"] = function()
		local messages = expectFires(
			"placesAtTheFirstMachine",
			standIn({ placesAtTheFirstMachine = true }),
			{ PLACED, FOLLOWS }
		)
		assert(
			string.find(messages[PLACED], "spawn room's centre", 1, true) ~= nil,
			messages[PLACED]
		)
	end,

	["control: a session that hands one centre table to every Placed and to state.positions fails exactly the Placed check (aliasing)"] = function()
		local messages = expectFires(
			"aliasesPlacedPositions",
			standIn({ aliasesPlacedPositions = true }),
			{ PLACED }
		)
		assert(string.find(messages[PLACED], "SAME table", 1, true) ~= nil, messages[PLACED])
	end,

	["control: a session that starts the Procedure at time 0 instead of the dealing step's now fails the generate check (Procedure.start's now), the follows, turn and secondsLeft checks (every Procedure state carries startedAt), the clock check and the spawn control (the round ends lobbySeconds early); the win and the relative instability drops are unaffected"] = function()
		expectFires(
			"startsTheProcedureAtTimeZero",
			standIn({ startsTheProcedureAtTimeZero = true }),
			{ GEN, FOLLOWS, SECONDS, CLOCK, SPAWN, TURN }
		)
	end,

	--[[ ================================================================
	     AC-2: generation fails.
	     ================================================================ ]]

	["control: a session that never hands the predicate to Generator.generate fails the AC-2 check (the round starts), the follows check and the ignored-turn check on that plan (the turn is handled)"] = function()
		local messages = expectFires(
			"ignoresThePredicate",
			standIn({ ignoresThePredicate = true }),
			{ GENFAIL, FOLLOWS, IGNORES }
		)
		assert(
			string.find(messages[GENFAIL], "expected Resolution in the same step", 1, true) ~= nil,
			messages[GENFAIL]
		)
	end,

	["control: a session that stays in Round with no facility when generation fails fails the AC-2 check and the follows check"] = function()
		local messages = expectFires(
			"staysInRoundOnGenerationFailure",
			standIn({ staysInRoundOnGenerationFailure = true }),
			{ GENFAIL, FOLLOWS }
		)
		assert(
			string.find(messages[GENFAIL], "expected Resolution in the same step", 1, true) ~= nil,
			messages[GENFAIL]
		)
	end,

	--[[ ================================================================
	     Clearing, and SLICE-003's pass-through on a Placed-emitting session.
	     ================================================================ ]]

	["control: a session that keeps facility and procedure through the next Lobby fails the clears check and the follows check"] = function()
		expectFires(
			"keepsFacilityAndProcedureInLobby",
			standIn({ keepsFacilityAndProcedureInLobby = true }),
			{ CLEARS, FOLLOWS }
		)
	end,

	["control (D-4's shape, on the stand-in): a session that emits Placed AND drops the machine's Emit effects still fails SLICE-003's pass-through check through the narrowed passThroughOf, and this story's AC-2 check (the failed deal's machine effects)"] = function()
		expectFires("dropsEmits", standIn({ dropsEmits = true }), { GENFAIL })
		local old = slice3Failures(standIn({ dropsEmits = true }))
		assert(
			Deep.equal(old, { SLICE3_PASS }),
			`SLICE-003 fired {Deep.show(old)}, expected exactly the pass-through check`
		)
	end,

	--[[ ================================================================
	     Purity. Today's Session is pure, so these two checks pass on
	     arrival in RED; the controls are what earn them.
	     ================================================================ ]]

	["control: a session that writes the new positions into its input state on a sample fails exactly the purity check"] = function()
		expectFires("mutatesStateOnSample", standIn({ mutatesStateOnSample = true }), { PURE })
	end,

	["control: a session that marks a TurnRequested's args handled fails exactly the purity check"] = function()
		expectFires("mutatesTurnEvent", standIn({ mutatesTurnEvent = true }), { PURE })
	end,

	["control: a module missing step is rejected by every check, and one missing new too - each naming the absent function"] = function()
		local names, messages = failingNames({ new = reference.new })
		assert(
			#names == #RoundContract.CHECKS,
			`{#names} of {#RoundContract.CHECKS} checks fired without step`
		)
		for _, name in names do
			assert(
				string.find(messages[name], "Session.step is nil", 1, true) ~= nil,
				`{name}: {messages[name]}`
			)
		end
		local names2, messages2 = failingNames({ step = reference.step })
		assert(
			#names2 == #RoundContract.CHECKS,
			`{#names2} of {#RoundContract.CHECKS} checks fired without new`
		)
		assert(
			string.find(messages2[NEW], "Session.new is nil", 1, true) ~= nil,
			`{NEW}: {messages2[NEW]}`
		)
	end,
}
