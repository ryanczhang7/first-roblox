--!strict
--[[
	The negative controls for VIEW-004, and the proof that each check in
	`tests/helpers/PositionsContract.luau` refuses the rule or the session it
	exists to catch.

	NOTHING HERE REQUIRES THIS STORY'S PRODUCTION CODE. In RED
	`src/server/session/Positions.luau` does not exist, `Session.luau` stores
	samples unfiltered, and every test in `positions_test.luau` and
	`session_positions_test.luau` fails at its export check before one
	assertion has run. The stand-ins below (`PositionsStubs.luau`,
	`SessionRoundStubs.luau`) need only the merged pure modules, so what is
	asserted here is MEASURED in RED rather than claimed for GREEN. The
	story's handoff carries the table.

	THREE BATTERIES. The module checks against the reference rule and
	fourteen one-defect rules (D-1's tolerance, D-2's exclusive bound, D-5's
	inclusive resync, and the rest of the Contract's clauses); the
	session-level checks against the reference session composed with the
	reference rule, with one-defect rules, and with one-defect wirings (D-3's
	raw store, SLICE-005's replacing store, every way a resync can go wrong,
	the deal's tracks, the tuning); and SLICE-005's scripted rounds against a
	session whose rule refuses every offer (D-4's shape), where the WIN check
	must fire because nobody can leave the spawn room.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half
	is the one worth the most: a stub that fails EVERY check proves only that
	the checks reject something. Where a control fails more than one check it
	is said so, with the set MEASURED here rather than predicted. A rule that
	is wrong by a CONSTANT (D-1) passes every check that reads its constants
	from it - that is the point of AC-1's settled controls, the one place a
	literal is allowed - and the table below records exactly which.

	THE WALKING BUDGET IS MEASURED HERE TOO: the simulated seconds SLICE-005's
	scripts now spend walking, over every seed they run, against the round.
]]

local Deep = require("../helpers/Deep")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PositionsContract = require("../helpers/PositionsContract")
local PositionsStubs = require("../helpers/PositionsStubs")
local RoundContract = require("../helpers/SessionRoundContract")
local ScriptedRound = require("../helpers/ScriptedRound")
local SessionRoundStubs = require("../helpers/SessionRoundStubs")

local standIn = SessionRoundStubs.standIn
local reference = SessionRoundStubs.reference
local P0 = PositionsStubs.reference

local function sortedNames(
	failures: { { name: string, message: string } }
): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in failures do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

local function expectExactly(
	who: string,
	names: { string },
	messages: { [string]: string },
	expected: { string },
	checks: { any }
): { [string]: string }
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
	local byName: { [string]: any } = {}
	for _, check in checks do
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

-- A one-defect RULE fires exactly these module checks.
local function ruleFires(who: string, P: any, expected: { string }): { [string]: string }
	local names, messages = sortedNames(PositionsContract.moduleFailures(P))
	return expectExactly(who, names, messages, expected, PositionsContract.MODULE_CHECKS)
end

-- A one-defect SESSION (composed with the reference rule unless `defects`
-- says otherwise) fires exactly these session checks, read with the
-- reference rule's constants.
local function sessionFires(who: string, defects: any, expected: { string }): { [string]: string }
	local names, messages = sortedNames(PositionsContract.sessionFailures(standIn(defects), P0))
	return expectExactly(who, names, messages, expected, PositionsContract.SESSION_CHECKS)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

local SHAPE = "exportsTheContractShape"
local SETTLED = "settledControlsRefuse200AndAccept1_5"
local INCLUSIVE = "boundIsInclusive"
local Y = "yIsIgnored"
local DT = "dtIsMeasuredFromTheLastAcceptedSample"
local CLAMP = "nowBeforeAcceptedAtClampsDtToZero"
local PLACED = "placedResetsTheBaseline"
local NOBASE = "noBaselineMeansNoAcceptanceAndNoRefusal"
local RESYNC = "needsResyncIsStrictlyAfterResyncSeconds"
local PURE = "isPureAndReturnsFreshTables"

local DEAL = "dealPlacementIsTheBaseline"
local UNPLACED = "unplacedPlayerIsAbsentAndOutOfReach"
local SRESYNC = "resyncPlacesBackInRoundOnly"
local TURN = "implausibleSampleDoesNotReachATurn"
local TRACKS = "tracksFromNewAndTheDeal"
local MERGE = "samplesMergeIntoFreshAcceptedCopies"
local SPEED = "walkSpeedIsReadFromTheSessionsTuning"

return {
	--[[ ================================================================
	     The module checks: the reference rule, then one defect at a time.
	     ================================================================ ]]

	["baseline: the reference rule passes every module check"] = function()
		local n, messages = sortedNames(PositionsContract.moduleFailures(P0))
		local shown: { string } = {}
		for _, name in n do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		assert(
			#n == 0,
			`the reference rule fails {#n} module check(s), so the check is wrong:\n{table.concat(
				shown,
				"\n"
			)}`
		)
		print(
			`        [measured] reference rule fails 0 of {#PositionsContract.MODULE_CHECKS} module checks; bound at 0.1 s = {PositionsContract.bound(
				P0,
				PositionsContract.walkSpeed(),
				0.1
			)}, at 1 s = {PositionsContract.bound(P0, PositionsContract.walkSpeed(), 1)}`
		)
	end,

	["control (Contract): a rule exporting TOLERANCE = 0.5 while computing with 1.5 fails the shape check (the floor) and the checks that compute the bound from the exported constant"] = function()
		local lying: any = table.clone(P0)
		lying.TOLERANCE = 0.5
		local messages = ruleFires("TOLERANCE = 0.5 exported", lying, { SHAPE, INCLUSIVE, DT })
		names(messages[SHAPE], "below 1", "the floor is named")
	end,

	["control (D-1's shape, AC-1): a rule whose TOLERANCE is a hundred times too wide fails the SETTLED 200-stud control, the placement control and the resync check (a 1,000-stud jump is accepted) - and PASSES the inclusive-bound and dt checks, which read the constant from the rule; that is why AC-1's controls are literals"] = function()
		local messages =
			ruleFires("tolerance100", PositionsStubs.tolerance100, { SETTLED, PLACED, RESYNC })
		names(
			messages[SETTLED],
			"200 studs away 0.1 s later was ACCEPTED",
			"D-1 fires the settled control"
		)
	end,

	["control (D-2's shape, AC-1): a rule comparing with < rather than <= fails exactly the inclusive-bound check and the dt-clamp check (a candidate exactly SLACK_STUDS away at dt 0)"] = function()
		local messages =
			ruleFires("exclusiveBound", PositionsStubs.exclusiveBound, { INCLUSIVE, CLAMP })
		names(messages[INCLUSIVE], "EXACTLY the bound", "D-2 fires on the exact boundary")
	end,

	["control (AC-1): a rule that counts y fails exactly the y check"] = function()
		local messages = ruleFires("countsY", PositionsStubs.countsY, { Y })
		names(messages[Y], "straight up", "the vertical move is refused")
	end,

	["control (AC-1): a rule measuring dt from the last OFFERED sample fails exactly the dt check (the walk is never plausible after refusals)"] = function()
		local messages = ruleFires("dtFromLastOffer", PositionsStubs.dtFromLastOffer, { DT })
		names(messages[DT], "last offered sample", "the dt check names the defect")
	end,

	["control (AC-1): a rule with no dt clamp (negative dt) fails exactly the clamp check, as does one taking |dt|"] = function()
		local negative = ruleFires("negativeDt", PositionsStubs.negativeDt, { CLAMP })
		names(negative[CLAMP], "SLACK_STUDS", "the negative-dt failure names the slack bound")
		ruleFires("absoluteDt", PositionsStubs.absoluteDt, { CLAMP })
	end,

	["control (AC-3): a rule that trusts a first sample fails exactly the no-baseline check, as does one that counts it as a refusal"] = function()
		local trusting =
			ruleFires("acceptsWithoutBaseline", PositionsStubs.acceptsWithoutBaseline, { NOBASE })
		names(trusting[NOBASE], "was accepted", "a trusted first sample is named")
		local counting = ruleFires(
			"countsNoBaselineAsRefusal",
			PositionsStubs.countsNoBaselineAsRefusal,
			{ NOBASE }
		)
		names(counting[NOBASE], "refusals", "a counted first sample is named")
	end,

	["control (AC-2): a placement that keeps the refusal run, or drops the refusal count, fails exactly the placement check"] = function()
		ruleFires("placedKeepsRefusedSince", PositionsStubs.placedKeepsRefusedSince, { PLACED })
		ruleFires("placedDropsRefusals", PositionsStubs.placedDropsRefusals, { PLACED })
	end,

	["control (AC-1, AC-4): a rule that restarts the run on every refusal fails the dt check and the placement check (refusedSince moves); one that keeps the run after an acceptance fails the dt check and the resync check"] = function()
		ruleFires(
			"refusedSinceRestartsEachRefusal",
			PositionsStubs.refusedSinceRestartsEachRefusal,
			{ DT, PLACED }
		)
		ruleFires(
			"acceptanceKeepsRefusedSince",
			PositionsStubs.acceptanceKeepsRefusedSince,
			{ DT, RESYNC }
		)
	end,

	["control (D-5's shape, AC-4): a rule whose resync is >= rather than > fails exactly the resync check, on the exact-RESYNC_SECONDS case; one that ignores the run fails the same check"] = function()
		local messages = ruleFires("resyncInclusive", PositionsStubs.resyncInclusive, { RESYNC })
		names(messages[RESYNC], "exactly RESYNC_SECONDS", "D-5 fires on the exact boundary")
		ruleFires("resyncWithoutRefusals", PositionsStubs.resyncWithoutRefusals, { RESYNC })
	end,

	["control (Contract): a rule that mutates the track it is handed fails the purity check and every check that reuses a track after offering from it; one that stores the candidate table itself fails the purity and placement checks"] = function()
		local messages = ruleFires(
			"mutatesTrack",
			PositionsStubs.mutatesTrack,
			{ PURE, SETTLED, INCLUSIVE, PLACED, RESYNC, Y, CLAMP }
		)
		names(messages[PURE], "mutated", "the purity failure names the mutation")
		ruleFires("aliasesCandidate", PositionsStubs.aliasesCandidate, { PURE, PLACED })
	end,

	["control (D-4's shape): a rule that refuses every candidate fails every module check but the shape and purity checks"] = function()
		ruleFires(
			"refusesEverything",
			PositionsStubs.refusesEverything,
			{ SETTLED, INCLUSIVE, Y, DT, CLAMP, PLACED, NOBASE, RESYNC }
		)
	end,

	--[[ ================================================================
	     The session checks: the reference session, then one defect at a time.
	     ================================================================ ]]

	["baseline: the reference session, composed with the reference rule, passes every session check and every SLICE-005 check"] = function()
		local n, messages = sortedNames(PositionsContract.sessionFailures(reference, P0))
		local shown: { string } = {}
		for _, name in n do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		assert(
			#n == 0,
			`the reference session fails {#n} session check(s), so the check is wrong:\n{table.concat(
				shown,
				"\n"
			)}`
		)
		local old, oldMessages = sortedNames(RoundContract.failures(reference))
		local shownOld: { string } = {}
		for _, name in old do
			table.insert(shownOld, `{name}: {oldMessages[name]}`)
		end
		assert(
			#old == 0,
			`the reference session fails {#old} SLICE-005 check(s):\n{table.concat(shownOld, "\n")}`
		)
		print(
			`        [measured] reference session fails 0 of {#PositionsContract.SESSION_CHECKS} session checks and 0 of {#RoundContract.CHECKS} SLICE-005 checks`
		)
	end,

	["control (D-3's shape): a session that stores every sample as the position, past the rule, fails the deal, unplaced, resync, turn and tuning checks - and passes the tracks and merge checks, whose samples are all plausible"] = function()
		local messages = sessionFires(
			"storesRawSamples",
			{ storesRawSamples = true },
			{ DEAL, UNPLACED, SRESYNC, TURN, SPEED }
		)
		names(messages[TURN], "expected refused / out_of_reach", "D-3 fires AC-5's turn")
		names(messages[UNPLACED], "no accepted sample", "D-3 fires AC-3's absence")
	end,

	["control (SLICE-005's store): a session that replaces the accepted positions with the batch fails the deal, resync and merge checks (players absent from a batch are dropped) - and passes the turn check, whose refused sample keeps the accepted centre either way"] = function()
		sessionFires("replacesSamples", { replacesSamples = true }, { DEAL, SRESYNC, MERGE })
	end,

	["control (D-1's shape, in Session): a session composed with the hundred-fold tolerance fails the resync, turn, tracks and tuning checks (every jump is plausible) and passes the deal check, whose jump is still outside even that bound"] = function()
		sessionFires(
			"positions = tolerance100",
			{ positions = PositionsStubs.tolerance100 },
			{ SRESYNC, TURN, TRACKS, SPEED }
		)
	end,

	["control (D-4's shape, in Session): a session composed with a rule that refuses every offer fails the deal, resync, turn, merge and tuning checks"] = function()
		local messages = sessionFires(
			"positions = refusesEverything",
			{ positions = PositionsStubs.refusesEverything },
			{ DEAL, SRESYNC, TURN, MERGE, SPEED }
		)
		names(messages[TURN], "positive control", "D-4 fires AC-5's positive control")
	end,

	["control (D-5's shape, in Session): a session composed with an inclusive resync fails exactly the resync check, on the exact-RESYNC_SECONDS sample"] = function()
		local messages = sessionFires(
			"positions = resyncInclusive",
			{ positions = PositionsStubs.resyncInclusive },
			{ SRESYNC }
		)
		names(messages[SRESYNC], "exactly RESYNC_SECONDS", "D-5 fires on the exact boundary")
	end,

	["control (AC-4): every way a resync can go wrong fails exactly the resync check - never firing, firing in the Lobby, placing at the sample, descending by playerId, also broadcasting, aliasing the position"] = function()
		local never = sessionFires("noResync", { noResync = true }, { SRESYNC })
		names(never[SRESYNC], "expected exactly", "a missing Placed is named")
		local lobby = sessionFires("resyncEverywhere", { resyncEverywhere = true }, { SRESYNC })
		names(lobby[SRESYNC], "no resync outside Round", "a Lobby placement is named")
		sessionFires("resyncAtTheSample", { resyncAtTheSample = true }, { SRESYNC })
		local order = sessionFires("resyncDescending", { resyncDescending = true }, { SRESYNC })
		names(order[SRESYNC], "ascending playerId", "the order is named")
		sessionFires("resyncAlsoBroadcasts", { resyncAlsoBroadcasts = true }, { SRESYNC })
		local alias = sessionFires(
			"resyncAliasesPosition",
			{ resyncAliasesPosition = true },
			{ SRESYNC }
		)
		names(alias[SRESYNC], "aliased", "the alias is named")
	end,

	["control (Contract): a deal that keeps stale tracks, or starts every track from nil, fails exactly the tracks check; so does a new without tracks (every later step rebuilds them)"] = function()
		local stale = sessionFires("dealKeepsOldTracks", { dealKeepsOldTracks = true }, { TRACKS })
		names(stale[TRACKS], "left", "the leaver's stale track is named")
		local dropped = sessionFires("dealDropsRefusals", { dealDropsRefusals = true }, { TRACKS })
		names(dropped[TRACKS], "after deal 2", "the dropped count is named")
		local missing = sessionFires(
			"tracksMissingFromNew",
			{ tracksMissingFromNew = true },
			{ TRACKS }
		)
		names(missing[TRACKS], "from new", "the missing tracks are named")
	end,

	["control (Contract): a session reading the walk speed from the shipped tuning fails exactly the tuning check; one storing the event's tables fails exactly the merge check"] = function()
		local shipped = sessionFires(
			"walkSpeedFromShippedTuning",
			{ walkSpeedFromShippedTuning = true },
			{ SPEED }
		)
		names(shipped[SPEED], "not accepted", "the fast tuning's move is named")
		local aliased = sessionFires(
			"storesSamplesByReference",
			{ storesSamplesByReference = true },
			{ MERGE }
		)
		names(aliased[MERGE], "the same table", "the alias is named")
	end,

	--[[ ================================================================
	     The scripted rounds walk: D-4's shape on the stand-in, and the budget.
	     ================================================================ ]]

	["control (D-4's shape on the stand-in): with every offer refused, SLICE-005's scripted WIN check fires (every turn out_of_reach from the spawn room), and so do the instability and clock scripts that need a turn to land; the spawn-room control still holds"] = function()
		local n, messages = sortedNames(
			RoundContract.failures(standIn({ positions = PositionsStubs.refusesEverything }))
		)
		print(`        [measured] positions = refusesEverything fires SLICE-005: {Deep.show(n)}`)
		local WIN = "winsEveryScriptedRoundInTheStepThatTakesTheCompletingTurn"
		local SPAWN = "neverWinsFromTheSpawnRoomAndLosesToTheClock"
		assert(table.find(n, WIN) ~= nil, `the WIN check did not fire: {Deep.show(n)}`)
		names(messages[WIN], "expected committed", "the frozen turns are refused")
		names(messages[WIN], "out_of_reach", "the refusal is out_of_reach")
		assert(
			table.find(n, SPAWN) == nil,
			`the spawn-room control fired; everyone frozen at the centre still loses to the clock:\n{messages[SPAWN]}`
		)
	end,

	["fixtures: the walking scripts fit inside the round - over every seed SLICE-005 runs, the win script's walking and turning, the instability script's walk and five wrong turns, and the clock script's charging all end well before the Procedure's earliest penalised deadline"] = function()
		local c = RoundContract.config()
		local t = MechanicsTuning
		local maxPenalty = (t.actuation.instability_max - 1)
			* t.actuation.instability_clock_penalty_seconds
		local earliestDeadline = c.roundSeconds - maxPenalty
		local W = ScriptedRound.maxMoveSeconds(t)
		local maxWalk, maxElapsed, rounds = 0, 0, 0
		for _, n in RoundContract.PLAYER_COUNTS do
			for seed = 1, RoundContract.SEEDS do
				local run = ScriptedRound.win(reference, seed, n)
				rounds += 1
				maxWalk = math.max(maxWalk, run.walkSeconds)
				maxElapsed = math.max(maxElapsed, run.elapsed)
			end
		end
		local maxLose = 0
		for _, n in RoundContract.PLAYER_COUNTS do
			for _, seed in RoundContract.LOSS_SEEDS do
				local run = ScriptedRound.loseByInstability(reference, seed, n)
				maxLose = math.max(maxLose, run.elapsed)
			end
		end
		local maxCharge = 0
		for k = 0, t.actuation.instability_max - 1 do
			for _, seed in { RoundContract.LOSS_SEEDS[1], RoundContract.LOSS_SEEDS[2] } do
				local run =
					ScriptedRound.clockOut(reference, seed, RoundContract.PLAYER_COUNTS[1], k)
				maxCharge = math.max(maxCharge, run.chargedAt - run.startedAt)
			end
		end
		print(
			`        [measured] walking budget: one move <= {W} s ({ScriptedRound.maxMoveStuds(t)} studs at {t.instance.walk_speed_studs_per_second} studs/s); win script over {rounds} rounds: max {maxWalk} s walking, max {maxElapsed} s deal-to-Post; instability script max {maxLose} s; clock script charging max {maxCharge} s; earliest penalised deadline {earliestDeadline} s into the round ({c.roundSeconds} - {maxPenalty})`
		)
		assert(
			maxElapsed < earliestDeadline,
			`the win script took {maxElapsed} s, past the earliest penalised deadline {earliestDeadline}`
		)
		assert(
			maxLose < earliestDeadline,
			`the instability script took {maxLose} s, past the earliest penalised deadline {earliestDeadline}`
		)
		assert(
			maxCharge < earliestDeadline,
			`the clock script's charging took {maxCharge} s, past the earliest penalised deadline {earliestDeadline}`
		)
		assert(maxWalk > 0, "no script walked at all; the rewrite is not in use")
	end,
}
