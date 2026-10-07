--!strict
--[[
	The negative controls for SLICE-003, and the proof that each check in
	`tests/helpers/SessionContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/session/Session.luau` does not exist, every test in
	`tests/server/session_test.luau` fails before its assertion runs, and so
	not one of that file's checks has been observed to accept or reject
	anything. The stand-ins below need only `PhaseMachine`, `Ring`,
	`Projection`, `Rng`, `RoundConfig`, `Tuning` and `Deep`, which are merged,
	so what is asserted here is MEASURED in RED rather than claimed for GREEN.
	The story's handoff carries the table.

	THE STAND-INS. `standIn(defects)` is a small implementation of the
	Contract with named defects switched on. With none it is the REFERENCE,
	the positive control: every check must ACCEPT it, or the check (or the
	plan) is wrong and the fix belongs HERE, in RED. Each control is the
	reference with EXACTLY ONE defect, so the set of checks that fire is
	attributable to that one defect, and each control pins that set EXACTLY.

	THE STORY NAMES ITS CONTROLS: a fixed-seed deal (AC-1, D-2's shape), a
	session that broadcasts the list of all seat views (AC-2), one that sends
	every view to the first player (D-1's shape), one that sends to the
	leaver (AC-3, D-4's shape), one that does not withdraw (AC-3, stale
	views), a floored secondsLeft and a Round timed from lobbySeconds (D-3's
	two shapes). D-1..D-4 THEMSELVES mutate the real module and stay with
	GATES.

	WHAT THE REFERENCE IS NOT: `src/server/session/Session.luau`, or a sketch
	of one. GREEN writes the module from the story's Contract against
	`session_test.luau`; nothing here is to be copied.
]]

local Contract = require("../helpers/SessionContract")
local Deep = require("../helpers/Deep")
local PhaseMachine = require("../../src/server/round/PhaseMachine")
local Projection = require("../../src/server/seats/Projection")
local Ring = require("../../src/server/seats/Ring")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Rng = require("../../src/shared/Rng")

type Defects = {
	-- AC-1
	fixedSeed: boolean?, -- D-2's shape: deals from Rng.fromSeed(0), not the effect's seed
	reusesTheFirstSeed: boolean?, -- D-2's subtler shape: every round from the session's initial seed
	skipsSeatsAssigned: boolean?, -- deals, but never feeds SeatsAssigned back: stays in Assignment
	-- AC-2
	broadcastsAllSeatViews: boolean?, -- the story's control: one Broadcast with every view
	sendsEveryViewToFirstPlayer: boolean?, -- D-1's shape
	sendsTheAssignment: boolean?, -- the payload is the Assignment (sigma included)
	sendsTheSuppliersView: boolean?, -- each player gets their supplier's view
	resendsViewsOnEveryTick: boolean?, -- SeatViews again on every Tick in Round
	-- AC-3
	sendsToTheLeaver: boolean?, -- D-4's shape: the old ring's players, leaver included
	skipsWithdraw: boolean?, -- keeps the old ring; views are stale
	withdrawsInPostToo: boolean?, -- withdraws on a leave the machine did not unseat
	keepsTheRingInLobby: boolean?, -- never clears the assignment on entering Lobby
	sendsOnlyToTheSupplier: boolean?, -- the "at least" read as "only"
	-- AC-4
	broadcastsOnEveryStep: boolean?, -- a RoundView on no-ops too
	noRoundViewOnTicks: boolean?, -- only on phase/count changes
	floorsSecondsLeft: boolean?, -- D-3's first shape
	roundTimedFromLobbySeconds: boolean?, -- D-3's second shape
	secondsLeftInShortLobby: boolean?, -- a countdown while the timer holds
	absoluteDeadline: boolean?, -- phaseEnteredAt + duration, not seconds left
	aliasesPlayers: boolean?, -- RoundView.players IS round.players
	leaksSeedInRoundView: boolean?, -- an extra key
	-- AC-5
	dropsEmits: boolean?, -- filters telemetry out
	leaksAssignSeats: boolean?, -- passes AssignSeats through as well
	reversesPassThrough: boolean?,
	-- Contract
	acceptsOutsideSeatsAssigned: boolean?, -- forwards it to the machine
	roundViewFirst: boolean?, -- the Broadcast before the pass-through
	mutatesState: boolean?, -- writes the new assignment into the input state
	mutatesEvent: boolean?,
}

local function has(list: { string }, item: string): boolean
	return table.find(list, item) ~= nil
end

local function standIn(defects: Defects): Contract.Session
	local S = {}
	local initialSeed = 0

	-- SLICE-006 C-2 moved `ports` into the fifth argument; SLICE-003's
	-- stand-in reads nothing from it.
	function S.new(config: any, seed: number, roundId: string, sessionId: string, _ports: any): any
		initialSeed = seed
		return { round = PhaseMachine.initial(config, seed, roundId, sessionId), assignment = nil }
	end

	local function seatView(assignment: any, playerId: string): any
		return {
			kind = "SendTo",
			playerId = playerId,
			payloadKind = "SeatView",
			payload = Projection.forPlayer(assignment, playerId),
		}
	end

	function S.step(state: any, event: any, now: number): (any, { any })
		if event.kind == "SeatsAssigned" and not defects.acceptsOutsideSeatsAssigned then
			return state, {}
		end
		local config = state.round.config
		local round, machineEffects = PhaseMachine.step(state.round, event, now)
		local passThrough: { any } = {}
		local sends: { any } = {}
		local extraBroadcasts: { any } = {}
		local assignment = state.assignment

		for _, effect in machineEffects do
			if effect.kind == "AssignSeats" then
				local seed = if defects.fixedSeed
					then 0
					elseif defects.reusesTheFirstSeed then initialSeed
					else effect.seed
				assignment = Ring.assign(effect.players, Rng.fromSeed(seed))
				if not defects.skipsSeatsAssigned then
					local more
					round, more = PhaseMachine.step(round, { kind = "SeatsAssigned" }, now)
					for _, e in more do
						if e.kind ~= "AssignSeats" then
							table.insert(passThrough, e)
						end
					end
				end
				for _, p in assignment.players do
					local view = seatView(assignment, p)
					if defects.sendsTheSuppliersView then
						view.payload =
							Projection.forPlayer(assignment, Ring.supplierOf(assignment, p))
					end
					table.insert(sends, view)
				end
				if defects.broadcastsAllSeatViews then
					local all: { any } = {}
					for _, p in assignment.players do
						table.insert(all, Projection.forPlayer(assignment, p))
					end
					table.insert(
						extraBroadcasts,
						{ kind = "Broadcast", payloadKind = "SeatViews", payload = all }
					)
				end
				if defects.leaksAssignSeats then
					table.insert(passThrough, effect)
				end
			elseif not (defects.dropsEmits and effect.kind == "Emit") then
				table.insert(passThrough, effect)
			end
		end

		if event.kind == "PlayerLeft" and assignment ~= nil then
			local unseated = has(state.round.players, event.playerId)
				and not has(round.players, event.playerId)
			local wasSeatedInRing = has(assignment.players, event.playerId)
			if
				(unseated or (defects.withdrawsInPostToo and wasSeatedInRing)) and wasSeatedInRing
			then
				local old = assignment
				local new = if defects.skipsWithdraw
					then old
					else Ring.withdraw(old, event.playerId)
				assignment = new
				if defects.sendsOnlyToTheSupplier then
					table.insert(sends, seatView(new, Ring.supplierOf(old, event.playerId)))
				else
					for _, p in new.players do
						if
							not Deep.equal(
								Projection.forPlayer(new, p),
								Projection.forPlayer(old, p)
							)
						then
							table.insert(sends, seatView(new, p))
						end
					end
				end
				if defects.sendsToTheLeaver then
					-- The old ring is the only one that can project the leaver.
					table.insert(sends, seatView(old, event.playerId))
				end
			end
		end

		if
			defects.resendsViewsOnEveryTick
			and event.kind == "Tick"
			and round.phase == "Round"
			and assignment ~= nil
			and #sends == 0
		then
			for _, p in assignment.players do
				table.insert(sends, seatView(assignment, p))
			end
		end

		if
			round.phase == "Lobby"
			and state.round.phase ~= "Lobby"
			and not defects.keepsTheRingInLobby
		then
			assignment = nil
		end

		if defects.sendsEveryViewToFirstPlayer and assignment ~= nil then
			for _, send in sends do
				send.playerId = assignment.players[1]
			end
		end
		if defects.sendsTheAssignment and assignment ~= nil then
			for _, send in sends do
				send.payload = assignment
			end
		end

		local phaseChanged = round.phase ~= state.round.phase
		local countChanged = #round.players ~= #state.round.players
		local timedTick = event.kind == "Tick"
			and (round.phase == "Lobby" or round.phase == "Round" or round.phase == "Post")
		local wants = phaseChanged or countChanged or timedTick
		if defects.noRoundViewOnTicks then
			wants = phaseChanged or countChanged
		end
		if defects.broadcastsOnEveryStep then
			wants = true
		end

		local broadcasts: { any } = {}
		if wants then
			local duration: number? = nil
			if
				round.phase == "Lobby"
				and (#round.players >= config.playersMin or defects.secondsLeftInShortLobby)
			then
				duration = config.lobbySeconds
			elseif round.phase == "Round" then
				duration = if defects.roundTimedFromLobbySeconds
					then config.lobbySeconds
					else config.roundSeconds
			elseif round.phase == "Post" then
				duration = config.postRoundSeconds
			end
			local secondsLeft: number? = nil
			if duration ~= nil then
				local raw = duration - (now - round.phaseEnteredAt)
				secondsLeft = if defects.floorsSecondsLeft then math.floor(raw) else math.ceil(raw)
				if defects.absoluteDeadline then
					secondsLeft = round.phaseEnteredAt + duration
				end
			end
			local players: { string } = if defects.aliasesPlayers
				then round.players
				else table.clone(round.players)
			-- VIEW-003 (C-1, C-10) widened the payload to ten keys. This
			-- stand-in never holds a Procedure, so the five new ones are the
			-- Contract's defaults (C-3) and pings is {} as Session sends it
			-- until SLICE-006.
			local payload: { [string]: any } = {
				phase = round.phase,
				secondsLeft = secondsLeft,
				players = players,
				playersMin = config.playersMin,
				playersMax = config.playersMax,
				progress = { committed = 0, total = MechanicsTuning.instance.procedure_length },
				instability = 0,
				dark = {},
				pings = {},
				machines = {},
			}
			if defects.leaksSeedInRoundView then
				payload.seed = round.seed
			end
			table.insert(
				broadcasts,
				{ kind = "Broadcast", payloadKind = "RoundView", payload = payload }
			)
		end

		if defects.reversesPassThrough then
			local reversed: { any } = {}
			for i = #passThrough, 1, -1 do
				table.insert(reversed, passThrough[i])
			end
			passThrough = reversed
		end

		local effects: { any } = {}
		if defects.roundViewFirst then
			for _, e in broadcasts do
				table.insert(effects, e)
			end
			broadcasts = {}
		end
		for _, e in passThrough do
			table.insert(effects, e)
		end
		for _, e in sends do
			table.insert(effects, e)
		end
		for _, e in extraBroadcasts do
			table.insert(effects, e)
		end
		for _, e in broadcasts do
			table.insert(effects, e)
		end

		if defects.mutatesState then
			state.assignment = assignment
		end
		if defects.mutatesEvent then
			event.handled = true
		end
		return { round = round, assignment = assignment }, effects
	end

	return S
end

local reference = standIn({})

local function failingNames(S: Contract.Session): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Contract.failures(S) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(who: string, S: Contract.Session, expected: { string })
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
	local byName: { [string]: Contract.Check } = {}
	for _, check in Contract.CHECKS do
		byName[check.name] = check
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac, 1, true) ~= nil,
			`{who}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end
end

local NEW = "newHoldsPhaseMachineInitialWithNoAssignment"
local FOLLOWS = "roundStateFollowsThePhaseMachineOnEveryStep"
local DEAL = "dealsRingAssignFromTheEffectsSeedAndReachesRoundInOneStep"
local TWO_ROUNDS = "dealsEachOfTwoConsecutiveRoundsFromItsOwnSeed"
local OWN_VIEW = "sendsEachSeatedPlayerExactlyTheirOwnSeatViewAndBroadcastsNone"
local WITHDRAW = "withdrawsTheLeaverAndSendsViewsToExactlyThoseWhoseViewChanged"
local QUORUM = "withdrawsOnTheLeaveThatDropsBelowQuorumToo"
local NO_WITHDRAW = "sendsNoSeatViewAndKeepsTheRingWhenNobodyIsUnseated"
local CLEARS = "clearsTheAssignmentOnEnteringLobby"
local RV_WHEN = "broadcastsRoundViewExactlyWhenThePhaseOrCountChangesOrATickHasADuration"
local RV_PAYLOAD = "roundViewCarriesExactlyTheTenKeysWithACeilingSecondsLeftFromConfig"
local PASS = "passesThroughTheMachinesEffectsUnchangedInOrderAndConsumesAssignSeats"
local IGNORES = "ignoresASeatsAssignedEventFromOutsideAndEveryNoOp"
local ORDER = "ordersPassThroughThenSeatViewsThenRoundViewLast"
local PURE = "stepMutatesNeitherStateNorEvent"

return {
	--[[ ================================================================
	     The reference. Everything below is this stand-in with one defect.
	     ================================================================ ]]

	["baseline: the reference stand-in passes every check in SessionContract - the checks accept a correct implementation of the Contract"] = function()
		local names, messages = failingNames(reference)
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		if #names > 0 then
			error(
				`the reference fails {#names} check(s), so the check or the plan is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#Contract.CHECKS} checks`)
	end,

	--[[ ================================================================
	     The plans' assumptions, checked against what they are read from.
	     ================================================================ ]]

	["fixtures: the plans fit RoundConfig.fromTuning(Tuning) - six names cover playersMax, two unseatings still leave playersMin, playersMin - 1 keeps quorum and playersMin - 2 drops it, roundSeconds differs from lobbySeconds, and every fractional tick distinguishes ceil from floor"] = function()
		local c = Contract.config()
		local problems: { string } = {}
		if #Contract.PLAYERS ~= c.playersMax then
			table.insert(problems, `{#Contract.PLAYERS} names but playersMax is {c.playersMax}`)
		end
		if c.playersMax - 2 < c.playersMin then
			table.insert(
				problems,
				`playersMax - 2 = {c.playersMax - 2} is below playersMin {c.playersMin}; the second deal would not happen`
			)
		end
		if c.playersMin - 1 < c.minPlayersToContinue then
			table.insert(
				problems,
				`playersMin - 1 = {c.playersMin - 1} does not keep quorum ({c.minPlayersToContinue})`
			)
		end
		if c.playersMin - 2 >= c.minPlayersToContinue then
			table.insert(
				problems,
				`playersMin - 2 = {c.playersMin - 2} does not drop below quorum ({c.minPlayersToContinue})`
			)
		end
		if c.roundSeconds == c.lobbySeconds then
			table.insert(
				problems,
				"roundSeconds equals lobbySeconds; D-3's second shape would pass"
			)
		end
		-- The fractional elapsed times the lifecycle uses, per phase.
		for _, pair in
			{
				{ c.lobbySeconds, 0.5 },
				{ c.lobbySeconds, 1.5 },
				{ c.roundSeconds, 100.25 },
				{ c.postRoundSeconds, 10.5 },
			}
		do
			local raw = pair[1] - pair[2]
			if math.ceil(raw) == math.floor(raw) then
				table.insert(
					problems,
					`duration {pair[1]} - elapsed {pair[2]} = {raw} is whole; ceil and floor agree`
				)
			end
		end
		assert(
			#problems == 0,
			`the plans no longer fit the config:\n{table.concat(problems, "\n")}`
		)
	end,

	["fixtures: driven through the reference, the lifecycle deals twice with different seeds, the seed-0 ring AND the first-seed ring differ from the real one on both deals, and the quorum plan ends in Resolution"] = function()
		local steps = Contract.run(reference, "fixtures", Contract.lifecycle())
		local deals: { Contract.Step } = {}
		for _, step in steps do
			if step.assign ~= nil then
				table.insert(deals, step)
			end
		end
		assert(#deals == 2, `the lifecycle dealt {#deals} time(s), expected 2`)
		assert(deals[1].assign.seed ~= deals[2].assign.seed, "the two AssignSeats seeds are equal")
		for i, deal in deals do
			local fixed = Ring.assign(deal.assign.players, Rng.fromSeed(0))
			local first = Ring.assign(deal.assign.players, Rng.fromSeed(Contract.SEED))
			local fixedDiffers = not Deep.equal(fixed, deal.assignAfter)
			local firstDiffers = i == 1 or not Deep.equal(first, deal.assignAfter)
			print(
				`        [measured] deal {i}: seed {deal.assign.seed}, {#deal.assign.players} players, seed-0 ring differs: {fixedDiffers}, first-seed ring differs: {firstDiffers}`
			)
			assert(
				fixedDiffers,
				`deal {i}: Rng.fromSeed(0) happens to deal the same ring as seed {deal.assign.seed}; the fixed-seed control would not fire`
			)
			assert(
				firstDiffers,
				`deal {i}: the first round's seed {Contract.SEED} happens to deal the same ring as seed {deal.assign.seed}; the reused-seed control would not fire`
			)
		end
		local quorum = Contract.run(reference, "fixtures", Contract.quorumDrop())
		assert(
			quorum[#quorum].oracleAfter.phase == "Resolution",
			`the quorum plan ends in {quorum[#quorum].oracleAfter.phase}`
		)
		local withdrawn = 0
		for _, step in quorum do
			if step.leaver ~= nil then
				withdrawn += 1
				assert(
					#(step.recipients :: { string }) == #step.assignAfter.players,
					`"{step.label}": {#(step.recipients :: { string })} recipients of {#step.assignAfter.players} remaining (PO decision 2 says all)`
				)
			end
		end
		assert(withdrawn == 2, `the quorum plan withdrew {withdrawn} time(s)`)
	end,

	["instrument: looksLikeSeatView recognises a view, a list of views and a map of views at depth, and rejects a RoundView payload and a plain list of ids"] = function()
		local view = {
			playerId = "ann",
			keyClasses = { 1 },
			lensClass = 2,
			supplierId = "bob",
			dependentId = "cat",
			seatOrder = { "ann", "bob", "cat" },
		}
		assert(Contract.looksLikeSeatView(view), "a view")
		assert(Contract.looksLikeSeatView({ view }), "a list of views")
		assert(
			Contract.looksLikeSeatView({ views = { ann = view } }),
			"a map of views one level down"
		)
		assert(Contract.looksLikeSeatView({ lensClass = 1 }), "a single PublicSeatView key")
		assert(not Contract.looksLikeSeatView({
			phase = "Round",
			secondsLeft = 3,
			players = { "ann" },
			playersMin = 4,
			playersMax = 6,
		}), "a RoundView")
		assert(not Contract.looksLikeSeatView({ "ann", "bob" }), "a list of ids")
		assert(not Contract.looksLikeSeatView("SeatView"), "a string")
	end,

	--[[ ================================================================
	     AC-1's controls.
	     ================================================================ ]]

	["control (AC-1, the story's, D-2's shape): a session that deals from Rng.fromSeed(0) instead of the effect's seed fails the single-deal check, the two-round check, AC-2's own-view check and both withdraw checks - every ring-derived expectation"] = function()
		expectFires(
			"fixedSeed",
			standIn({ fixedSeed = true }),
			{ DEAL, TWO_ROUNDS, OWN_VIEW, WITHDRAW, QUORUM }
		)
	end,

	["control (D-2's subtler shape): a session that deals every round from the session's INITIAL seed passes the single-deal check and fails the two-round check and the own-view check (which runs on both deals) - the second round is what catches it"] = function()
		expectFires(
			"reusesTheFirstSeed",
			standIn({ reusesTheFirstSeed = true }),
			{ TWO_ROUNDS, OWN_VIEW }
		)
	end,

	["control: a session that deals but never feeds SeatsAssigned back stays in Assignment - every check that reads the round, the ring, a view or a RoundView fires; only new, the no-op check, the no-withdraw check and purity do not"] = function()
		expectFires("skipsSeatsAssigned", standIn({ skipsSeatsAssigned = true }), {
			DEAL,
			TWO_ROUNDS,
			FOLLOWS,
			OWN_VIEW,
			WITHDRAW,
			QUORUM,
			CLEARS,
			RV_WHEN,
			RV_PAYLOAD,
			PASS,
			ORDER,
		})
	end,

	--[[ ================================================================
	     AC-2's controls.
	     ================================================================ ]]

	["control (AC-2, the story's): a session that ALSO broadcasts the list of all seat views fails exactly the own-view check (a Broadcast carries a seat view, by kind and by shape); since SLICE-006 C-3 narrowed the order check to RoundView broadcasts, the second Broadcast no longer fires it - that story's own order check refuses the unknown kind"] = function()
		expectFires(
			"broadcastsAllSeatViews",
			standIn({ broadcastsAllSeatViews = true }),
			{ OWN_VIEW }
		)
	end,

	["control (D-1's shape): a session that addresses every SeatView to the first seated player fails the own-view check, both withdraw checks and the order check"] = function()
		expectFires(
			"sendsEveryViewToFirstPlayer",
			standIn({ sendsEveryViewToFirstPlayer = true }),
			{ OWN_VIEW, WITHDRAW, QUORUM, ORDER }
		)
	end,

	["control: a session whose SeatView payload is the whole Assignment (sigma included) fails the own-view check and both withdraw checks"] = function()
		expectFires(
			"sendsTheAssignment",
			standIn({ sendsTheAssignment = true }),
			{ OWN_VIEW, WITHDRAW, QUORUM }
		)
	end,

	["control: a session that sends each player their SUPPLIER's view fails exactly the own-view check"] = function()
		expectFires(
			"sendsTheSuppliersView",
			standIn({ sendsTheSuppliersView = true }),
			{ OWN_VIEW }
		)
	end,

	["control: a session that resends every SeatView on every Tick in Round fails exactly the no-withdraw check"] = function()
		expectFires(
			"resendsViewsOnEveryTick",
			standIn({ resendsViewsOnEveryTick = true }),
			{ NO_WITHDRAW }
		)
	end,

	--[[ ================================================================
	     AC-3's controls.
	     ================================================================ ]]

	["control (AC-3, the story's, D-4's shape): a session that also sends a SeatView to the leaver fails both withdraw checks and the order check"] = function()
		expectFires(
			"sendsToTheLeaver",
			standIn({ sendsToTheLeaver = true }),
			{ WITHDRAW, QUORUM, ORDER }
		)
	end,

	["control (AC-3, the story's): a session that does not withdraw - stale ring, stale views - fails both withdraw checks"] = function()
		expectFires("skipsWithdraw", standIn({ skipsWithdraw = true }), { WITHDRAW, QUORUM })
	end,

	["control: a session that withdraws on a leave in Resolution or Post, which the machine did not unseat, fails the no-withdraw check and the order check (SendTos where the oracle expects none)"] = function()
		expectFires(
			"withdrawsInPostToo",
			standIn({ withdrawsInPostToo = true }),
			{ NO_WITHDRAW, ORDER }
		)
	end,

	["control: a session that never clears the assignment on entering Lobby fails the clears check and, through the stale ring's withdrawal on the lobby leave, the no-withdraw check and the order check"] = function()
		expectFires(
			"keepsTheRingInLobby",
			standIn({ keepsTheRingInLobby = true }),
			{ CLEARS, NO_WITHDRAW, ORDER }
		)
	end,

	["control: a session that sends only to the leaver's supplier fails both withdraw checks and the order check"] = function()
		expectFires(
			"sendsOnlyToTheSupplier",
			standIn({ sendsOnlyToTheSupplier = true }),
			{ WITHDRAW, QUORUM, ORDER }
		)
	end,

	--[[ ================================================================
	     AC-4's controls.
	     ================================================================ ]]

	["control: a session that broadcasts a RoundView on every step, no-ops included, fails the when-check and the ignores check"] = function()
		expectFires(
			"broadcastsOnEveryStep",
			standIn({ broadcastsOnEveryStep = true }),
			{ RV_WHEN, IGNORES }
		)
	end,

	["control: a session that broadcasts only on phase or count changes, never on a timed Tick, fails exactly the when-check"] = function()
		expectFires("noRoundViewOnTicks", standIn({ noRoundViewOnTicks = true }), { RV_WHEN })
	end,

	["control (D-3's first shape): a session that floors secondsLeft fails exactly the payload check, on the fractional ticks"] = function()
		expectFires("floorsSecondsLeft", standIn({ floorsSecondsLeft = true }), { RV_PAYLOAD })
	end,

	["control (D-3's second shape): a session that times the Round from lobbySeconds fails exactly the payload check, on the dealing step"] = function()
		expectFires(
			"roundTimedFromLobbySeconds",
			standIn({ roundTimedFromLobbySeconds = true }),
			{ RV_PAYLOAD }
		)
	end,

	["control: a session that counts down in a Lobby below playersMin fails exactly the payload check"] = function()
		expectFires(
			"secondsLeftInShortLobby",
			standIn({ secondsLeftInShortLobby = true }),
			{ RV_PAYLOAD }
		)
	end,

	["control: a session that sends an absolute deadline as secondsLeft fails exactly the payload check"] = function()
		expectFires("absoluteDeadline", standIn({ absoluteDeadline = true }), { RV_PAYLOAD })
	end,

	["control: a session whose RoundView.players is state.round.players itself fails exactly the payload check"] = function()
		expectFires("aliasesPlayers", standIn({ aliasesPlayers = true }), { RV_PAYLOAD })
	end,

	["control: a session whose RoundView carries an extra seed key fails exactly the payload check (key set by pairs)"] = function()
		expectFires(
			"leaksSeedInRoundView",
			standIn({ leaksSeedInRoundView = true }),
			{ RV_PAYLOAD }
		)
	end,

	--[[ ================================================================
	     AC-5's controls.
	     ================================================================ ]]

	["control: a session that drops the machine's Emit effects fails the pass-through check and, on the steps that become empty, the ignores check is unaffected - exactly the pass-through check"] = function()
		expectFires("dropsEmits", standIn({ dropsEmits = true }), { PASS })
	end,

	["control: a session that passes AssignSeats through as well fails exactly the pass-through check (the order check counts it as pass-through, where it sits)"] = function()
		expectFires("leaksAssignSeats", standIn({ leaksAssignSeats = true }), { PASS })
	end,

	["control: a session that reverses the machine's effects fails exactly the pass-through check (order matters on the round-ending step)"] = function()
		expectFires("reversesPassThrough", standIn({ reversesPassThrough = true }), { PASS })
	end,

	--[[ ================================================================
	     The Contract's controls.
	     ================================================================ ]]

	["control: a session that forwards an outside SeatsAssigned to the machine fails exactly the ignores check, on the hand-built Assignment state"] = function()
		expectFires(
			"acceptsOutsideSeatsAssigned",
			standIn({ acceptsOutsideSeatsAssigned = true }),
			{ IGNORES }
		)
	end,

	["control: a session that puts the RoundView before the pass-through fails exactly the order check"] = function()
		expectFires("roundViewFirst", standIn({ roundViewFirst = true }), { ORDER })
	end,

	["control: a session that writes the new assignment into its input state fails exactly the purity check"] = function()
		expectFires("mutatesState", standIn({ mutatesState = true }), { PURE })
	end,

	["control: a session that marks its event handled fails exactly the purity check"] = function()
		expectFires("mutatesEvent", standIn({ mutatesEvent = true }), { PURE })
	end,

	["control: a module missing step is rejected by every check, and one missing new too - each naming the absent function"] = function()
		local names, messages = failingNames({ new = reference.new })
		assert(
			#names == #Contract.CHECKS,
			`{#names} of {#Contract.CHECKS} checks fired without step`
		)
		for _, name in names do
			assert(
				string.find(messages[name], "Session.step is nil", 1, true) ~= nil,
				`{name}: {messages[name]}`
			)
		end
		local names2, messages2 = failingNames({ step = reference.step })
		assert(
			#names2 == #Contract.CHECKS,
			`{#names2} of {#Contract.CHECKS} checks fired without new`
		)
		assert(
			string.find(messages2[NEW], "Session.new is nil", 1, true) ~= nil,
			`{NEW}: {messages2[NEW]}`
		)
	end,
}
