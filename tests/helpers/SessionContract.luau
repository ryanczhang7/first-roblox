--!strict
--[[
	SLICE-003 AC-1..AC-5 and the story's Contract pins, written once as checks
	over a SESSION MODULE handed in as a parameter rather than over
	`src/server/session/Session.luau` by name - the `TurnRequestsContract`
	arrangement, for the same reason. `tests/server/session_test.luau` applies
	these to the real module; `tests/server/session_controls_test.luau` applies
	them to a reference stand-in and to stand-ins with exactly one defect each,
	so that in RED - where the module does not exist, the real file fails at
	`require`, and not one assertion in it has executed - every check here has
	still been EXECUTED and observed to reject the implementation it exists to
	catch.

	A `Session` here is anything with two plain field functions, called with a
	dot exactly as the story's Contract writes them:

	    S.new(config, seed, roundId, sessionId) -> SessionState
	    S.step(state, event, now) -> (SessionState, { SessionEffect })

	THE ORACLE IS THE M1/M2 MODULES THEMSELVES, STEPPED HERE, INDEPENDENTLY.
	`run` drives a scripted plan through the session under test and, beside
	it, through `PhaseMachine.step` directly: one machine step per event, and
	a second with `{ kind = "SeatsAssigned" }` when the first emitted
	`AssignSeats`. The expected ring is `Ring.assign(effect.players,
	Rng.fromSeed(effect.seed))` for THAT effect, withdrawn with `Ring.withdraw`
	when the machine unseats a seated player in Round, cleared on entering
	Lobby; the expected seat views are `Projection.forPlayer` on it. Nothing
	below reads an expected value off the session's own output: a session
	whose state drifts from the machine's is caught by `roundStateFollows...`,
	and every other check compares against the oracle's state, not the
	subject's.

	THE ORACLE PARTITION (story `## Contract`): AC-1, AC-2, AC-3 and AC-5 are
	MECHANICAL - compared to the M2 functions' own output, never a hand copy.
	AC-4 is SETTLED - the durations and the player bounds are read through
	`RoundConfig.fromTuning(Tuning)`; no literal below is a duration or a
	count.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local PhaseMachine = require("../../src/server/round/PhaseMachine")
local Projection = require("../../src/server/seats/Projection")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/shared/Rng")
local RoundConfig = require("../../src/server/round/RoundConfig")
local Tuning = require("../../src/shared/Tuning")

local SessionContract = {}

export type Session = any

-- The seed every scripted session starts from. The two deals in `lifecycle`
-- differ because the machine re-derives the seed on entering Lobby. This
-- value was CHOSEN (RED, 2026-10-02, measured over a dozen candidates) so
-- that on BOTH deals the real ring differs from the one `Rng.fromSeed(0)`
-- deals and from the one the FIRST round's seed deals: with four players
-- there are only six rings, and 7919 collided with seed 0 on the second
-- deal. The fixtures test in the controls file asserts all three.
SessionContract.SEED = 20261002
SessionContract.ROUND_ID = "round-1"
SessionContract.SESSION_ID = "session-A"

-- Six names: `playersMax` of them join in `lifecycle`, and the fixtures test
-- asserts the count matches the config rather than assuming it.
SessionContract.PLAYERS = { "ann", "bob", "cat", "dan", "eve", "fay" }
SessionContract.STRANGER = "zed"
SessionContract.SURPLUS = "gus"

-- `Projection.PublicSeatView`'s key set: what a Broadcast must never carry.
SessionContract.SEAT_VIEW_KEYS =
	{ "playerId", "keyClasses", "lensClass", "supplierId", "dependentId", "seatOrder" }

-- The RoundView key set the Contract pins, sorted. `secondsLeft` is absent
-- when nil, so the expected list is built per step. WIDENED by VIEW-003
-- (C-1, C-10): the five SLICE-003 keys plus progress, instability, dark,
-- pings and machines. The five are still checked by value below; the five
-- new ones are checked here for presence and type only - their contents are
-- `RoundView.public`'s and are pinned in `tests/server/round_view_test.luau`.
SessionContract.ROUND_VIEW_KEYS = {
	"dark",
	"instability",
	"machines",
	"phase",
	"pings",
	"players",
	"playersMax",
	"playersMin",
	"progress",
	"secondsLeft",
}
SessionContract.SLICE3_ROUND_VIEW_KEYS =
	{ "phase", "players", "playersMax", "playersMin", "secondsLeft" }
-- VIEW-003's five: key -> the Luau type it must carry.
SessionContract.VIEW3_ROUND_VIEW_TYPES = {
	progress = "table",
	instability = "number",
	dark = "table",
	pings = "table",
	machines = "table",
}

SessionContract.SEND_TO_KEYS = { "kind", "payload", "payloadKind", "playerId" }
SessionContract.BROADCAST_KEYS = { "kind", "payload", "payloadKind" }

function SessionContract.config(): RoundConfig.RoundConfig
	return RoundConfig.fromTuning(Tuning)
end

--[[ ------------------------------------------------------------------------
     Small instruments.
     --------------------------------------------------------------------- ]]

function SessionContract.keysOf(value: any): { string }
	local keys: { string } = {}
	for key in pairs(value :: { [any]: any }) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end

local function contains(list: { string }, item: string): boolean
	for _, candidate in list do
		if candidate == item then
			return true
		end
	end
	return false
end

-- Does `value` look like a seat view, at any depth up to `depth`? A table
-- carrying any `PublicSeatView` key counts, and so does a list or map of
-- such tables - the shape a "broadcast all the views" defect takes.
function SessionContract.looksLikeSeatView(value: any, depth: number?): boolean
	local remaining = if depth == nil then 4 else depth
	if typeof(value) ~= "table" or remaining < 0 then
		return false
	end
	for _, key in SessionContract.SEAT_VIEW_KEYS do
		if value[key] ~= nil then
			return true
		end
	end
	for _, item in pairs(value :: { [any]: any }) do
		if SessionContract.looksLikeSeatView(item, remaining - 1) then
			return true
		end
	end
	return false
end

function SessionContract.sendTos(effects: { any }): { any }
	local out: { any } = {}
	for _, effect in effects do
		if typeof(effect) == "table" and effect.kind == "SendTo" then
			table.insert(out, effect)
		end
	end
	return out
end

function SessionContract.broadcasts(effects: { any }): { any }
	local out: { any } = {}
	for _, effect in effects do
		if typeof(effect) == "table" and effect.kind == "Broadcast" then
			table.insert(out, effect)
		end
	end
	return out
end

--[[
	The phase machine's own effect kinds - `Emit`, `PromptRematch`,
	`ComputeTrace` and `AssignSeats` - in order: what the session claims to
	have passed through from the machine. `AssignSeats` is kept so that the
	control "passes AssignSeats through as well" still fires.

	NARROWED IN SLICE-005's RED (C-6). It used to be "everything that is
	neither a SendTo nor a Broadcast", and SLICE-005's `Placed` effect would
	have failed AC-5's deep-equal on every dealing step. A kind this list does
	not name is a session effect, not a machine effect. The narrowing is earned
	by SLICE-005's D-4 (GATES): a Session that drops the machine's `Emit`s must
	still fail the pass-through check.
]]
local MACHINE_EFFECT_KINDS = { "Emit", "PromptRematch", "ComputeTrace", "AssignSeats" }

function SessionContract.passThroughOf(effects: { any }): { any }
	local out: { any } = {}
	for _, effect in effects do
		if typeof(effect) == "table" and table.find(MACHINE_EFFECT_KINDS, effect.kind) ~= nil then
			table.insert(out, effect)
		end
	end
	return out
end

local function requireModule(criterion: string, S: any)
	if typeof(S) ~= "table" then
		Contract.fail(`{criterion}: Session is {Deep.show(S)}, not a module table`)
	end
	for _, name in { "new", "step" } do
		if typeof(S[name]) ~= "function" then
			Contract.fail(`{criterion}: Session.{name} is {typeof(S[name])}, expected a function`)
		end
	end
end

--[[ ------------------------------------------------------------------------
     The scripted run: the subject and the oracle, side by side.
     --------------------------------------------------------------------- ]]

export type Plan = { { label: string, event: any, now: number } }

export type Step = {
	label: string,
	event: any,
	now: number,
	-- The subject's side. `before` and `after` are DEEP SNAPSHOTS taken at the
	-- step, so a later step that mutates a table it was handed cannot change
	-- what an earlier step is seen to have done; the live tables are kept for
	-- the two checks that need identity (purity, and the players alias).
	before: any,
	beforeLive: any,
	eventSnapshot: any,
	after: any,
	afterLive: any,
	effects: { any },
	-- The oracle's side, computed here from the M1/M2 modules alone.
	oracleBefore: any, -- PhaseMachine.RoundState
	oracleAfter: any,
	passThrough: { any }, -- the machine's effects minus AssignSeats, both machine steps
	assign: any?, -- the AssignSeats effect, when this is a dealing step
	assignBefore: any?, -- the Contract's assignment before the step
	assignAfter: any?, -- ... and after it
	leaver: string?, -- set when the machine unseated a seated player in Round
	recipients: { string }?, -- remaining players whose view changed, in new seat order
	entersLobby: boolean,
	wantsRoundView: boolean,
	noOp: boolean, -- the machine returned its input untouched with no effects
}

local function hasDuration(phase: string): boolean
	return phase == "Lobby" or phase == "Round" or phase == "Post"
end

--[[
	Drive `plan` through `S` and through the phase machine, recording both.

	Raises through `Contract.fail` - naming `criterion` - if the session
	cannot be constructed, returns something that is not a state, or raises on
	a step. A raise IS a failure of the criterion under test: D-4 in the story
	says so for the leaver's view, and the same holds for every other step.
]]
function SessionContract.run(S: Session, criterion: string, plan: Plan): { Step }
	requireModule(criterion, S)
	local config = SessionContract.config()
	local okNew, state = pcall(
		S.new,
		config,
		SessionContract.SEED,
		SessionContract.ROUND_ID,
		SessionContract.SESSION_ID
	)
	if not okNew then
		Contract.fail(`{criterion}: Session.new RAISED: {tostring(state)}`)
	end
	if typeof(state) ~= "table" or typeof(state.round) ~= "table" then
		Contract.fail(
			`{criterion}: Session.new returned {Deep.show(state)}, expected a SessionState with a round`
		)
	end

	local oracle: any = PhaseMachine.initial(
		config,
		SessionContract.SEED,
		SessionContract.ROUND_ID,
		SessionContract.SESSION_ID
	)
	local assignment: any = nil
	local steps: { Step } = {}

	for _, planned in plan do
		local event = planned.event
		local now = planned.now
		local stateSnapshot = Deep.copy(state)
		local eventSnapshot = Deep.copy(event)

		-- The oracle: one machine step, and a second on AssignSeats.
		local oracleBefore = oracle
		local oracleAfter, machineEffects = PhaseMachine.step(oracle, event, now)
		local assign: any = nil
		local passThrough: { any } = {}
		for _, effect in machineEffects do
			if effect.kind == "AssignSeats" then
				assign = effect
			else
				table.insert(passThrough, effect)
			end
		end
		if assign ~= nil then
			local roundState, more = PhaseMachine.step(oracleAfter, { kind = "SeatsAssigned" }, now)
			oracleAfter = roundState
			for _, effect in more do
				if effect.kind ~= "AssignSeats" then
					table.insert(passThrough, effect)
				end
			end
		end
		local assignBefore = assignment
		if assign ~= nil then
			assignment = Ring.assign(assign.players, Rng.fromSeed(assign.seed))
		end

		local leaver: string? = nil
		local recipients: { string }? = nil
		if
			event.kind == "PlayerLeft"
			and assignment ~= nil
			and contains(oracleBefore.players, event.playerId)
			and not contains(oracleAfter.players, event.playerId)
		then
			leaver = event.playerId
			local withdrawn = Ring.withdraw(assignment, event.playerId)
			local changed: { string } = {}
			for _, remaining in withdrawn.players do
				if
					not Deep.equal(
						Projection.forPlayer(withdrawn, remaining),
						Projection.forPlayer(assignment, remaining)
					)
				then
					table.insert(changed, remaining)
				end
			end
			recipients = changed
			assignment = withdrawn
		end

		local entersLobby = oracleAfter.phase == "Lobby" and oracleBefore.phase ~= "Lobby"
		if entersLobby then
			assignment = nil
		end

		local wantsRoundView = oracleAfter.phase ~= oracleBefore.phase
			or #oracleAfter.players ~= #oracleBefore.players
			or (event.kind == "Tick" and hasDuration(oracleAfter.phase))

		-- A pure no-op: the machine returned its input untouched with no
		-- effects, AND the Contract asks for no RoundView - a Tick that moves
		-- nothing in Lobby, Round or Post is a machine no-op the session still
		-- answers with a RoundView, so it is not one.
		local noOp = rawequal(oracleAfter, oracleBefore)
			and #machineEffects == 0
			and not wantsRoundView

		-- The subject.
		local ok, after, effects = pcall(S.step, state, event, now)
		if not ok then
			Contract.fail(
				`{criterion}: step "{planned.label}" ({Deep.show(event)} at {now}) RAISED: {tostring(
					after
				)}`
			)
		end
		if typeof(after) ~= "table" or typeof(after.round) ~= "table" then
			Contract.fail(
				`{criterion}: step "{planned.label}" returned {Deep.show(after)}, expected a SessionState with a round`
			)
		end
		if typeof(effects) ~= "table" then
			Contract.fail(
				`{criterion}: step "{planned.label}" returned effects {Deep.show(effects)}; the Contract says an effect list is always a table, empty rather than nil`
			)
		end

		table.insert(steps, {
			label = planned.label,
			event = event,
			now = now,
			before = stateSnapshot,
			beforeLive = state,
			eventSnapshot = eventSnapshot,
			after = Deep.copy(after),
			afterLive = after,
			effects = effects,
			oracleBefore = oracleBefore,
			oracleAfter = oracleAfter,
			passThrough = passThrough,
			assign = assign,
			assignBefore = assignBefore,
			assignAfter = assignment,
			leaver = leaver,
			recipients = recipients,
			entersLobby = entersLobby,
			wantsRoundView = wantsRoundView,
			noOp = noOp,
		})

		state = after
		oracle = oracleAfter
	end

	return steps
end

--[[ ------------------------------------------------------------------------
     The plans. Every time and count is a function of the config.
     --------------------------------------------------------------------- ]]

local function join(label: string, playerId: string, now: number)
	return { label = label, event = { kind = "PlayerJoined", playerId = playerId }, now = now }
end

local function leave(label: string, playerId: string, now: number)
	return { label = label, event = { kind = "PlayerLeft", playerId = playerId }, now = now }
end

local function tick(label: string, now: number)
	return { label = label, event = { kind = "Tick" }, now = now }
end

local function rematch(label: string, playerId: string, now: number)
	return { label = label, event = { kind = "RematchAccepted", playerId = playerId }, now = now }
end

local function seatsAssigned(label: string, now: number)
	return { label = label, event = { kind = "SeatsAssigned" }, now = now }
end

--[[
	A full lifecycle with `playersMax` players, two deals and every kind of
	non-dealing step the Contract names:

	  Lobby: joins below and at the minimum, fractional ticks (ceil vs floor),
	  joins to the maximum, a refused surplus join, a duplicate join, a
	  stranger's leave, an outside SeatsAssigned - then the first DEAL.
	  Round: a fractional tick, an outside SeatsAssigned, an ignored rematch,
	  a seated player's leave (quorum kept - the withdraw case), the same
	  leave again, a stranger's leave - then the clock ends the round.
	  Resolution: a leave (telemetry only, nobody unseated), then the tick
	  into Post with ComputeTrace.
	  Post: a rematch (Emit only), a leave (telemetry only), a fractional
	  tick, then the tick into Lobby with PromptRematch.
	  Lobby again: a seated player's leave (unseated, but the ring is gone),
	  then the second DEAL, from a different seed.

	The second deal needs `playersMax - 2 >= playersMin` (two players are
	unseated along the way); the controls' fixtures test asserts it.
]]
function SessionContract.lifecycle(): Plan
	local c = SessionContract.config()
	local P = SessionContract.PLAYERS
	local plan: Plan = {}

	for i = 1, c.playersMin - 1 do
		table.insert(plan, join(`join {P[i]} (below min)`, P[i], 0))
	end
	table.insert(plan, tick("tick in a short lobby", 0.5))
	table.insert(plan, join(`join {P[c.playersMin]} (reaches min)`, P[c.playersMin], 1))
	table.insert(plan, tick("fractional tick in a full-enough lobby", 1.5))
	for i = c.playersMin + 1, c.playersMax do
		table.insert(plan, join(`join {P[i]} (to max)`, P[i], 2))
	end
	table.insert(plan, join("surplus join refused", SessionContract.SURPLUS, 2))
	table.insert(plan, join("duplicate join refused", P[1], 2))
	table.insert(plan, leave("stranger leaves the lobby", SessionContract.STRANGER, 2))
	table.insert(plan, seatsAssigned("outside SeatsAssigned in Lobby", 2))

	local deal1 = c.lobbySeconds
	table.insert(plan, tick("DEAL 1", deal1))
	table.insert(plan, tick("fractional tick in Round", deal1 + 100.25))
	table.insert(plan, seatsAssigned("outside SeatsAssigned in Round", deal1 + 101))
	table.insert(plan, rematch("rematch in Round (ignored)", P[1], deal1 + 101))
	table.insert(plan, leave(`{P[3]} leaves the Round (quorum kept)`, P[3], deal1 + 101))
	table.insert(plan, leave(`{P[3]} leaves again (duplicate)`, P[3], deal1 + 102))
	table.insert(plan, leave("stranger leaves the Round", SessionContract.STRANGER, deal1 + 102))

	local resolved = deal1 + c.roundSeconds
	table.insert(plan, tick("clock ends the Round", resolved))
	table.insert(plan, leave(`{P[4]} leaves in Resolution`, P[4], resolved + 1))
	local post = resolved + 2
	table.insert(plan, tick("Resolution -> Post", post))
	table.insert(plan, rematch(`{P[1]} accepts a rematch in Post`, P[1], post + 1))
	table.insert(plan, leave(`{P[5]} leaves in Post`, P[5], post + 1))
	table.insert(plan, tick("fractional tick in Post", post + 10.5))

	local lobby = post + c.postRoundSeconds
	table.insert(plan, tick("Post -> Lobby", lobby))
	table.insert(plan, leave(`{P[6]} leaves the new Lobby`, P[6], lobby + 1))
	table.insert(plan, tick("DEAL 2", lobby + c.lobbySeconds))

	return plan
end

--[[
	`playersMin` players, dealt, then two leaves: the first keeps quorum
	(`playersMin - 1 >= minPlayersToContinue`, so the Round continues), the
	second drops below it and resolves the round in the same step. Both are
	withdrawals. The fixtures test asserts the two inequalities.
]]
function SessionContract.quorumDrop(): Plan
	local c = SessionContract.config()
	local P = SessionContract.PLAYERS
	local plan: Plan = {}
	for i = 1, c.playersMin do
		table.insert(plan, join(`join {P[i]}`, P[i], 0))
	end
	table.insert(plan, tick("DEAL", c.lobbySeconds))
	table.insert(plan, leave(`{P[2]} leaves (quorum kept)`, P[2], c.lobbySeconds + 5))
	table.insert(plan, leave(`{P[3]} leaves (below quorum)`, P[3], c.lobbySeconds + 6))
	return plan
end

local function dealSteps(steps: { Step }): { Step }
	local out: { Step } = {}
	for _, step in steps do
		if step.assign ~= nil then
			table.insert(out, step)
		end
	end
	return out
end

local function withdrawSteps(steps: { Step }): { Step }
	local out: { Step } = {}
	for _, step in steps do
		if step.leaver ~= nil then
			table.insert(out, step)
		end
	end
	return out
end

--[[ ------------------------------------------------------------------------
     Contract: `new`, and the round following the machine.
     --------------------------------------------------------------------- ]]

-- `Session.new` holds exactly `PhaseMachine.initial` on the same arguments,
-- and no assignment.
function SessionContract.newHoldsPhaseMachineInitialWithNoAssignment(S: Session)
	requireModule("Contract", S)
	local config = SessionContract.config()
	local ok, state = pcall(
		S.new,
		config,
		SessionContract.SEED,
		SessionContract.ROUND_ID,
		SessionContract.SESSION_ID
	)
	if not ok then
		Contract.fail(`Contract: Session.new RAISED: {tostring(state)}`)
	end
	local problems: { string } = {}
	if typeof(state) ~= "table" then
		Contract.fail(`Contract: Session.new returned {Deep.show(state)}, expected a SessionState`)
	end
	local want = PhaseMachine.initial(
		config,
		SessionContract.SEED,
		SessionContract.ROUND_ID,
		SessionContract.SESSION_ID
	)
	if not Deep.equal(state.round, want) then
		table.insert(
			problems,
			`state.round differs from PhaseMachine.initial(config, {SessionContract.SEED}, "{SessionContract.ROUND_ID}", "{SessionContract.SESSION_ID}"):\n{Deep.diff(
				want,
				state.round
			)}`
		)
	end
	if state.assignment ~= nil then
		table.insert(
			problems,
			`state.assignment is {Deep.show(state.assignment)}, expected nil before any deal`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`Contract: Session.new must hold PhaseMachine.initial(...) with assignment = nil:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- After every step, `state.round` deep-equals the phase machine stepped
-- directly on the same inputs (twice, on a dealing step).
function SessionContract.roundStateFollowsThePhaseMachineOnEveryStep(S: Session)
	local problems: { string } = {}
	for _, plan in { SessionContract.lifecycle(), SessionContract.quorumDrop() } do
		for _, step in SessionContract.run(S, "Contract", plan) do
			if not Deep.equal(step.after.round, step.oracleAfter) then
				table.insert(
					problems,
					`after "{step.label}": state.round differs from PhaseMachine.step on the same inputs:\n{Deep.diff(
						step.oracleAfter,
						step.after.round
					)}`
				)
			end
		end
	end
	if #problems > 0 then
		Contract.fail(
			`Contract: state.round must be exactly what PhaseMachine.step returns (with the SeatsAssigned step applied on a deal):\n{Contract.firstFew(
				problems,
				6
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-1: the deal.
     --------------------------------------------------------------------- ]]

--[[
	On the first deal: one step reaches Round, and `state.assignment`
	deep-equals `Ring.assign(effect.players, Rng.fromSeed(effect.seed))` for
	the AssignSeats effect the machine emitted on that step.
]]
function SessionContract.dealsRingAssignFromTheEffectsSeedAndReachesRoundInOneStep(S: Session)
	local steps = SessionContract.run(S, "AC-1", SessionContract.lifecycle())
	local deals = dealSteps(steps)
	if #deals < 1 then
		Contract.fail("AC-1 precondition: the lifecycle plan produced no AssignSeats effect")
	end
	local deal = deals[1]
	local problems: { string } = {}
	if deal.after.round.phase ~= "Round" then
		table.insert(
			problems,
			`after the dealing Tick the phase is "{tostring(deal.after.round.phase)}", expected "Round" in the same step`
		)
	end
	if deal.after.assignment == nil then
		table.insert(problems, "state.assignment is nil after the dealing step")
	elseif not Deep.equal(deal.after.assignment, deal.assignAfter) then
		table.insert(
			problems,
			`state.assignment differs from Ring.assign(effect.players, Rng.fromSeed({deal.assign.seed})) for the effect's players {Deep.show(
				deal.assign.players
			)}:\n{Deep.diff(deal.assignAfter, deal.after.assignment)}`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-1: the dealing step must reach Round and deal Ring.assign from the AssignSeats effect's seed:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[
	Two consecutive rounds: the AssignSeats seeds differ (a precondition on
	the machine, asserted), and each deal equals Ring.assign from ITS OWN
	effect's seed. The fixed-seed control fails here.
]]
function SessionContract.dealsEachOfTwoConsecutiveRoundsFromItsOwnSeed(S: Session)
	local steps = SessionContract.run(S, "AC-1", SessionContract.lifecycle())
	local deals = dealSteps(steps)
	if #deals ~= 2 then
		Contract.fail(`AC-1 precondition: the lifecycle plan produced {#deals} deal(s), expected 2`)
	end
	if deals[1].assign.seed == deals[2].assign.seed then
		Contract.fail(
			`AC-1 precondition: both AssignSeats effects carry seed {deals[1].assign.seed}; the machine was expected to re-derive it on entering Lobby`
		)
	end
	local problems: { string } = {}
	for i, deal in deals do
		if not Deep.equal(deal.after.assignment, deal.assignAfter) then
			table.insert(
				problems,
				`deal {i} ("{deal.label}", seed {deal.assign.seed}, players {Deep.show(
					deal.assign.players
				)}): state.assignment is not Ring.assign(effect.players, Rng.fromSeed(effect.seed)):\n{Deep.diff(
					deal.assignAfter,
					deal.after.assignment
				)}`
			)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-1: each round must be dealt from its own AssignSeats seed ({deals[1].assign.seed} then {deals[2].assign.seed}):\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-2: each player gets their own view, and nothing is broadcast.
     --------------------------------------------------------------------- ]]

-- The SendTo/SeatView problems of one step against `assignment` and the
-- recipient list `expected` (seat order). Shared by AC-2 and AC-3.
local function seatViewProblems(
	criterion: string,
	step: Step,
	assignment: any,
	expected: { string },
	problems: { string }
)
	local byPlayer: { [string]: { any } } = {}
	for _, effect in SessionContract.sendTos(step.effects) do
		local keys = SessionContract.keysOf(effect)
		if not Deep.equal(keys, SessionContract.SEND_TO_KEYS) then
			table.insert(
				problems,
				`{criterion}: "{step.label}": a SendTo effect's key set is {Deep.show(keys)}, expected exactly {Deep.show(
					SessionContract.SEND_TO_KEYS
				)}`
			)
		end
		if effect.payloadKind ~= "SeatView" then
			table.insert(
				problems,
				`{criterion}: "{step.label}": a SendTo to {Deep.show(effect.playerId)} has payloadKind {Deep.show(
					effect.payloadKind
				)}; the Contract names only "SeatView"`
			)
		end
		local id = tostring(effect.playerId)
		byPlayer[id] = byPlayer[id] or {}
		table.insert(byPlayer[id], effect)
	end

	for _, playerId in expected do
		local got = byPlayer[playerId] or {}
		if #got ~= 1 then
			table.insert(
				problems,
				`{criterion}: "{step.label}": {#got} SendTo/SeatView effect(s) addressed to {playerId}, expected exactly 1`
			)
		end
		local want = Projection.forPlayer(assignment, playerId)
		for _, effect in got do
			if not Deep.equal(effect.payload, want) then
				table.insert(
					problems,
					`{criterion}: "{step.label}": the SeatView sent to {playerId} is not Projection.forPlayer(assignment, "{playerId}"):\n{Deep.diff(
						want,
						effect.payload
					)}`
				)
			end
		end
		byPlayer[playerId] = nil
	end
	for playerId, got in pairs(byPlayer) do
		table.insert(
			problems,
			`{criterion}: "{step.label}": {#got} SendTo effect(s) addressed to {playerId}, who must receive none on this step`
		)
	end
end

-- Any Broadcast that carries a seat view, by payloadKind or by shape.
local function broadcastLeakProblems(criterion: string, step: Step, problems: { string })
	for _, effect in SessionContract.broadcasts(step.effects) do
		if effect.payloadKind ~= "RoundView" then
			table.insert(
				problems,
				`{criterion}: "{step.label}": a Broadcast has payloadKind {Deep.show(
					effect.payloadKind
				)}; the Contract names only "RoundView"`
			)
		end
		if SessionContract.looksLikeSeatView(effect.payload) then
			table.insert(
				problems,
				`{criterion}: "{step.label}": a Broadcast ({Deep.show(effect.payloadKind)}) carries a seat view - a PublicSeatView key was found in its payload: {Deep.show(
					effect.payload
				)}`
			)
		end
	end
end

--[[
	On each dealing step: exactly one SendTo/SeatView per seated player,
	addressed to them, payload deep-equal to `Projection.forPlayer`, nobody
	else addressed, and no Broadcast carrying anything shaped like a seat
	view.
]]
function SessionContract.sendsEachSeatedPlayerExactlyTheirOwnSeatViewAndBroadcastsNone(S: Session)
	local steps = SessionContract.run(S, "AC-2", SessionContract.lifecycle())
	local deals = dealSteps(steps)
	if #deals < 1 then
		Contract.fail("AC-2 precondition: the lifecycle plan produced no deal")
	end
	local problems: { string } = {}
	for _, deal in deals do
		seatViewProblems("AC-2", deal, deal.assignAfter, deal.assignAfter.players, problems)
		broadcastLeakProblems("AC-2", deal, problems)
	end
	-- A seat view is a per-player secret on every step, not only on deals.
	for _, step in steps do
		broadcastLeakProblems("AC-2", step, problems)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-2: one SendTo/SeatView per seated player with Projection.forPlayer's payload, and no Broadcast carrying a seat view:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-3: a seated player leaves.
     --------------------------------------------------------------------- ]]

local function withdrawProblems(step: Step, problems: { string })
	local leaver = step.leaver :: string
	local recipients = step.recipients :: { string }
	if not Deep.equal(step.after.assignment, step.assignAfter) then
		table.insert(
			problems,
			`AC-3: "{step.label}": state.assignment is not Ring.withdraw(old, "{leaver}"):\n{Deep.diff(
				step.assignAfter,
				step.after.assignment
			)}`
		)
	end
	seatViewProblems("AC-3", step, step.assignAfter, recipients, problems)
	for _, effect in SessionContract.sendTos(step.effects) do
		if effect.playerId == leaver then
			table.insert(
				problems,
				`AC-3: "{step.label}": a SendTo was addressed to the leaver {leaver}, who is no longer seated`
			)
		end
	end
end

--[[
	The lifecycle's leave in Round (quorum kept): `Ring.withdraw` applied, a
	SeatView to exactly the remaining players whose `Projection.forPlayer`
	differs between the old and new ring (computed here - today every one of
	them, PO decision 2), none to the leaver.
]]
function SessionContract.withdrawsTheLeaverAndSendsViewsToExactlyThoseWhoseViewChanged(S: Session)
	local steps = SessionContract.run(S, "AC-3", SessionContract.lifecycle())
	local withdraws = withdrawSteps(steps)
	if #withdraws ~= 1 then
		Contract.fail(
			`AC-3 precondition: the lifecycle plan unseated {#withdraws} player(s) in Round, expected 1`
		)
	end
	local step = withdraws[1]
	local recipients = step.recipients :: { string }
	print(
		`        [measured] "{step.label}": {#recipients} of {#step.assignAfter.players} remaining views changed`
	)
	local problems: { string } = {}
	withdrawProblems(step, problems)
	if #problems > 0 then
		Contract.fail(
			`AC-3: on a seated leave in Round the session must apply Ring.withdraw and send a SeatView to exactly the remaining players whose view changed, never the leaver:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[
	The quorum plan: a leave that keeps quorum and then one that drops below
	it and resolves the round in the same step. Both withdraw; the second
	ends in Resolution (a precondition on the machine, asserted).
]]
function SessionContract.withdrawsOnTheLeaveThatDropsBelowQuorumToo(S: Session)
	local steps = SessionContract.run(S, "AC-3", SessionContract.quorumDrop())
	local withdraws = withdrawSteps(steps)
	if #withdraws ~= 2 then
		Contract.fail(
			`AC-3 precondition: the quorum plan unseated {#withdraws} player(s) in Round, expected 2`
		)
	end
	if withdraws[2].oracleAfter.phase ~= "Resolution" then
		Contract.fail(
			`AC-3 precondition: the second leave left the machine in {withdraws[2].oracleAfter.phase}, expected Resolution`
		)
	end
	local problems: { string } = {}
	for _, step in withdraws do
		withdrawProblems(step, problems)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-3: a leave that drops the round below quorum still withdraws the leaver and sends views to the remaining players:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[
	Every step that is neither a deal, nor a withdrawal, nor the entry into
	Lobby: no SendTo at all, and the assignment deep-equal to what it was.
	That is the leave in Resolution, the leave in Post, the stranger's
	leaves, the duplicate leave, every tick and join, and the leave in the
	second Lobby (where the ring is already gone).
]]
function SessionContract.sendsNoSeatViewAndKeepsTheRingWhenNobodyIsUnseated(S: Session)
	local problems: { string } = {}
	local covered = 0
	for _, step in SessionContract.run(S, "AC-3", SessionContract.lifecycle()) do
		if step.assign ~= nil or step.leaver ~= nil or step.entersLobby then
			continue
		end
		covered += 1
		local sent = SessionContract.sendTos(step.effects)
		if #sent > 0 then
			local to: { string } = {}
			for _, effect in sent do
				table.insert(to, tostring(effect.playerId))
			end
			table.insert(
				problems,
				`AC-3: "{step.label}": {#sent} SendTo effect(s) (to {table.concat(to, ", ")}) on a step that unseated nobody`
			)
		end
		-- Against the subject's OWN previous ring: whether that ring was dealt
		-- correctly is AC-1's question, so a wrong deal does not fire here.
		if not Deep.equal(step.after.assignment, step.before.assignment) then
			table.insert(
				problems,
				`AC-3: "{step.label}": state.assignment changed on a step that unseated nobody:\n{Deep.diff(
					step.before.assignment,
					step.after.assignment
				)}`
			)
		end
	end
	if covered < 10 then
		Contract.fail(`AC-3 precondition: only {covered} non-unseating steps in the plan`)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-3: a leave in Resolution or Post, a stranger's leave, a duplicate leave, and every other non-unseating step send no SeatView and leave the ring as it was:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[
	Contract pin: the step that enters Lobby clears the assignment to nil, and
	a seated player's leave in that Lobby - which the machine DOES unseat -
	sends no SeatView and leaves it nil. The next deal sets it again.
]]
function SessionContract.clearsTheAssignmentOnEnteringLobby(S: Session)
	local steps = SessionContract.run(S, "AC-3", SessionContract.lifecycle())
	local problems: { string } = {}
	local entered: Step? = nil
	local enteredAt = 0
	for i, step in steps do
		if step.entersLobby then
			entered = step
			enteredAt = i
		end
	end
	if entered == nil then
		Contract.fail("AC-3 precondition: the lifecycle plan never re-entered Lobby")
	end
	local lobby = entered :: Step
	if lobby.after.assignment ~= nil then
		table.insert(
			problems,
			`AC-3: "{lobby.label}": state.assignment is still {Deep.show(lobby.after.assignment)} after entering Lobby, expected nil`
		)
	end
	local sawLobbyLeave = false
	for i = enteredAt + 1, #steps do
		local step = steps[i]
		if step.assign ~= nil then
			break
		end
		if
			step.event.kind == "PlayerLeft"
			and #step.oracleAfter.players < #step.oracleBefore.players
		then
			sawLobbyLeave = true
			if step.after.assignment ~= nil then
				table.insert(
					problems,
					`AC-3: "{step.label}": state.assignment is {Deep.show(step.after.assignment)} after a leave in the new Lobby, expected nil`
				)
			end
			local sent = SessionContract.sendTos(step.effects)
			if #sent > 0 then
				table.insert(
					problems,
					`AC-3: "{step.label}": {#sent} SendTo effect(s) on a leave in the new Lobby, where no ring exists`
				)
			end
		end
	end
	if not sawLobbyLeave then
		Contract.fail(
			"AC-3 precondition: the lifecycle plan has no unseating leave in the second Lobby"
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-3: the step that enters Lobby must clear the assignment, so a stale ring cannot be withdrawn from in the next lobby:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-4: the RoundView.
     --------------------------------------------------------------------- ]]

-- The five SLICE-003 fields the Contract says the END state of `step`
-- produces at `now`. VIEW-003 C-7 clamps every non-nil secondsLeft at 0;
-- no step of SLICE-003's plan reaches a negative value, so the clamp
-- changes no expected number here and is written for consistency with
-- `RoundViewContract.expectedSecondsLeft`.
function SessionContract.expectedRoundView(step: Step): any
	local c = SessionContract.config()
	local round = step.oracleAfter
	local elapsed = step.now - round.phaseEnteredAt
	local secondsLeft: number? = nil
	if round.phase == "Lobby" and #round.players >= c.playersMin then
		secondsLeft = math.max(0, math.ceil(c.lobbySeconds - elapsed))
	elseif round.phase == "Round" then
		secondsLeft = math.max(0, math.ceil(c.roundSeconds - elapsed))
	elseif round.phase == "Post" then
		secondsLeft = math.max(0, math.ceil(c.postRoundSeconds - elapsed))
	end
	return {
		phase = round.phase,
		secondsLeft = secondsLeft,
		players = round.players,
		playersMin = c.playersMin,
		playersMax = c.playersMax,
	}
end

local function roundViews(effects: { any }): { any }
	local out: { any } = {}
	for _, effect in SessionContract.broadcasts(effects) do
		if effect.payloadKind == "RoundView" then
			table.insert(out, effect)
		end
	end
	return out
end

--[[
	Exactly one Broadcast/RoundView on every step whose end phase or player
	count differs from its start, and on every Tick ending in Lobby, Round or
	Post; none on any other step.
]]
function SessionContract.broadcastsRoundViewExactlyWhenThePhaseOrCountChangesOrATickHasADuration(
	S: Session
)
	local problems: { string } = {}
	local wanted, unwanted = 0, 0
	for _, step in SessionContract.run(S, "AC-4", SessionContract.lifecycle()) do
		local got = #roundViews(step.effects)
		local want = if step.wantsRoundView then 1 else 0
		if want == 1 then
			wanted += 1
		else
			unwanted += 1
		end
		if got ~= want then
			table.insert(
				problems,
				`AC-4: "{step.label}" ({step.oracleBefore.phase}/{#step.oracleBefore.players} -> {step.oracleAfter.phase}/{#step.oracleAfter.players}, {step.event.kind}): {got} Broadcast/RoundView effect(s), expected {want}`
			)
		end
	end
	if wanted < 8 or unwanted < 6 then
		Contract.fail(
			`AC-4 precondition: the plan has {wanted} RoundView steps and {unwanted} silent ones; too few to discriminate`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-4: one RoundView on every phase or count change and on every Tick in a phase with a duration, none otherwise:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[
	Where a RoundView is emitted, its payload is exactly
	`{ phase, secondsLeft?, players, playersMin, playersMax, progress,
	instability, dark, pings, machines }`: the key set enumerated with
	`pairs`, `secondsLeft` the ceiling against the config's duration (nil in
	Resolution and in a short Lobby), `players` deep-equal to the round's and
	not the same table, and VIEW-003's five keys present with the right type.
	WIDENED by VIEW-003 under PO decision 1 (C-1, C-10) from SLICE-003's
	five-key set; nothing SLICE-003 asserted was dropped.
]]
function SessionContract.roundViewCarriesExactlyTheTenKeysWithACeilingSecondsLeftFromConfig(
	S: Session
)
	local problems: { string } = {}
	local checked = 0
	for _, step in SessionContract.run(S, "AC-4", SessionContract.lifecycle()) do
		local views = roundViews(step.effects)
		if #views ~= 1 then
			continue
		end
		checked += 1
		local effect = views[1]
		local want = SessionContract.expectedRoundView(step)
		local effectKeys = SessionContract.keysOf(effect)
		if not Deep.equal(effectKeys, SessionContract.BROADCAST_KEYS) then
			table.insert(
				problems,
				`AC-4: "{step.label}": the Broadcast effect's key set is {Deep.show(effectKeys)}, expected exactly {Deep.show(
					SessionContract.BROADCAST_KEYS
				)}`
			)
		end
		local payload = effect.payload
		if typeof(payload) ~= "table" then
			table.insert(
				problems,
				`AC-4: "{step.label}": the RoundView payload is {Deep.show(payload)}, not a table`
			)
			continue
		end
		local gotKeys = SessionContract.keysOf(payload)
		local wantKeys = table.clone(SessionContract.ROUND_VIEW_KEYS)
		if want.secondsLeft == nil then
			table.remove(wantKeys, table.find(wantKeys, "secondsLeft") :: number)
		end
		if not Deep.equal(gotKeys, wantKeys) then
			table.insert(
				problems,
				`AC-4: "{step.label}": the RoundView key set is {Deep.show(gotKeys)}, expected exactly {Deep.show(
					wantKeys
				)} (secondsLeft {if want.secondsLeft == nil then "nil" else "present"} in {want.phase}; VIEW-003 widened SLICE-003's five keys to ten)`
			)
		end
		for key, kind in pairs(SessionContract.VIEW3_ROUND_VIEW_TYPES) do
			if typeof(payload[key]) ~= kind then
				table.insert(
					problems,
					`AC-4: "{step.label}": RoundView.{key} is {Deep.show(payload[key])}, expected a {kind} (VIEW-003)`
				)
			end
		end
		if payload.phase ~= want.phase then
			table.insert(
				problems,
				`AC-4: "{step.label}": RoundView.phase is {Deep.show(payload.phase)}, expected "{want.phase}"`
			)
		end
		if payload.secondsLeft ~= want.secondsLeft then
			table.insert(
				problems,
				`AC-4: "{step.label}": RoundView.secondsLeft is {Deep.show(payload.secondsLeft)}, expected {Deep.show(
					want.secondsLeft
				)} = ceil(duration - ({step.now} - {step.oracleAfter.phaseEnteredAt})) in {want.phase}`
			)
		end
		if payload.playersMin ~= want.playersMin or payload.playersMax ~= want.playersMax then
			table.insert(
				problems,
				`AC-4: "{step.label}": RoundView.playersMin/playersMax are {Deep.show(
					payload.playersMin
				)}/{Deep.show(payload.playersMax)}, expected {want.playersMin}/{want.playersMax}`
			)
		end
		if not Deep.equal(payload.players, want.players) then
			table.insert(
				problems,
				`AC-4: "{step.label}": RoundView.players is {Deep.show(payload.players)}, expected the round's players {Deep.show(
					want.players
				)}`
			)
		elseif rawequal(payload.players, step.afterLive.round.players) then
			table.insert(
				problems,
				`AC-4: "{step.label}": RoundView.players IS state.round.players (the same table); the Contract wants a copy`
			)
		end
	end
	if checked < 8 then
		Contract.fail(`AC-4 precondition: only {checked} RoundView payload(s) to check`)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-4: the RoundView is exactly \{ phase, secondsLeft, players, playersMin, playersMax, progress, instability, dark, pings, machines } with secondsLeft = ceil(duration - elapsed) from RoundConfig:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-5: pass-through.
     --------------------------------------------------------------------- ]]

--[[
	On every step the effects that are neither SendTo nor Broadcast deep-equal
	the phase machine's own effects on the same inputs (both machine steps on
	a deal) with AssignSeats removed, in order - and AssignSeats appears
	nowhere.
]]
function SessionContract.passesThroughTheMachinesEffectsUnchangedInOrderAndConsumesAssignSeats(
	S: Session
)
	local problems: { string } = {}
	local nonEmpty = 0
	for _, plan in { SessionContract.lifecycle(), SessionContract.quorumDrop() } do
		for _, step in SessionContract.run(S, "AC-5", plan) do
			for _, effect in step.effects do
				if typeof(effect) == "table" and effect.kind == "AssignSeats" then
					table.insert(
						problems,
						`AC-5: "{step.label}": an AssignSeats effect reached the session's output; the session consumes it`
					)
				end
			end
			local got = SessionContract.passThroughOf(step.effects)
			if #step.passThrough > 0 then
				nonEmpty += 1
			end
			if not Deep.equal(got, step.passThrough) then
				table.insert(
					problems,
					`AC-5: "{step.label}": the passed-through effects are {Deep.show(
						Deep.kinds(got)
					)}, the machine emitted {Deep.show(Deep.kinds(step.passThrough))} (minus AssignSeats):\n{Deep.diff(
						step.passThrough,
						got
					)}`
				)
			end
		end
	end
	if nonEmpty < 8 then
		Contract.fail(
			`AC-5 precondition: only {nonEmpty} steps with machine effects to pass through`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-5: Emit, PromptRematch and ComputeTrace pass through unchanged and in order; AssignSeats never appears:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     Contract: outside events, no-ops, order, purity.
     --------------------------------------------------------------------- ]]

--[[
	A SeatsAssigned event from outside is ignored - in Lobby and Round
	(scripted) and in a hand-built Assignment state, where forwarding it
	would move the machine to Round with no ring - and so is every step the
	machine itself treats as a no-op: the same state back, effects `{}`.
]]
function SessionContract.ignoresASeatsAssignedEventFromOutsideAndEveryNoOp(S: Session)
	local problems: { string } = {}
	local noOps = 0
	for _, step in SessionContract.run(S, "Contract", SessionContract.lifecycle()) do
		if not (step.noOp or step.event.kind == "SeatsAssigned") then
			continue
		end
		noOps += 1
		if not Deep.equal(step.after, step.before) then
			table.insert(
				problems,
				`Contract: "{step.label}": the returned state differs from the input on a step the machine ignores:\n{Deep.diff(
					step.before,
					step.after
				)}`
			)
		end
		if #step.effects ~= 0 then
			table.insert(
				problems,
				`Contract: "{step.label}": {#step.effects} effect(s) {Deep.show(
					Deep.kinds(step.effects)
				)} on a step the machine ignores, expected \{}`
			)
		end
	end
	if noOps < 6 then
		Contract.fail(`Contract precondition: only {noOps} ignored steps in the plan`)
	end

	-- The hand-built Assignment state: the machine's own, one Tick before
	-- SeatsAssigned, with no ring dealt.
	local c = SessionContract.config()
	local round: any = PhaseMachine.initial(
		c,
		SessionContract.SEED,
		SessionContract.ROUND_ID,
		SessionContract.SESSION_ID
	)
	for i = 1, c.playersMin do
		round = PhaseMachine.step(
			round,
			{ kind = "PlayerJoined", playerId = SessionContract.PLAYERS[i] },
			0
		)
	end
	local pending = PhaseMachine.step(round, { kind = "Tick" }, c.lobbySeconds)
	if pending.phase ~= "Assignment" then
		Contract.fail(
			`Contract precondition: the hand-built state is in {pending.phase}, not Assignment`
		)
	end
	local state = { round = pending, assignment = nil }
	local snapshot = Deep.copy(state)
	local ok, after, effects = pcall(S.step, state, { kind = "SeatsAssigned" }, c.lobbySeconds)
	if not ok then
		table.insert(
			problems,
			`Contract: an outside SeatsAssigned on an Assignment-phase state RAISED: {tostring(
				after
			)}`
		)
	else
		if not Deep.equal(after, snapshot) then
			table.insert(
				problems,
				`Contract: an outside SeatsAssigned on an Assignment-phase state changed it (forwarded to the machine?):\n{Deep.diff(
					snapshot,
					after
				)}`
			)
		end
		if typeof(effects) ~= "table" or #effects ~= 0 then
			table.insert(
				problems,
				`Contract: an outside SeatsAssigned on an Assignment-phase state produced {Deep.show(
					effects
				)}, expected \{}`
			)
		end
	end

	if #problems > 0 then
		Contract.fail(
			`Contract: a SeatsAssigned from outside and every ignored event return the same state with \{} effects:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[
	Effect order within a step: pass-through first, then the SendTo/SeatView
	effects in the ring's seat order (the new ring's, on a withdrawal), then
	at most one Broadcast, last.
]]
function SessionContract.ordersPassThroughThenSeatViewsThenRoundViewLast(S: Session)
	local problems: { string } = {}
	local withSends = 0
	for _, plan in { SessionContract.lifecycle(), SessionContract.quorumDrop() } do
		for _, step in SessionContract.run(S, "Contract", plan) do
			local kinds = Deep.kinds(step.effects)
			local firstSend, lastSend, lastPass = nil, nil, nil
			local sendOrder: { string } = {}
			local broadcastCount = 0
			for i, effect in step.effects do
				local kind = if typeof(effect) == "table" then effect.kind else nil
				if kind == "SendTo" then
					firstSend = firstSend or i
					lastSend = i
					table.insert(sendOrder, tostring(effect.playerId))
				elseif kind == "Broadcast" then
					broadcastCount += 1
					if i ~= #step.effects then
						table.insert(
							problems,
							`Contract: "{step.label}": a Broadcast at position {i} of {#step.effects} ({Deep.show(
								kinds
							)}); it must be last`
						)
					end
				else
					lastPass = i
				end
			end
			if broadcastCount > 1 then
				table.insert(
					problems,
					`Contract: "{step.label}": {broadcastCount} Broadcast effects, at most one is allowed`
				)
			end
			if firstSend ~= nil then
				withSends += 1
				if lastPass ~= nil and lastPass > firstSend then
					table.insert(
						problems,
						`Contract: "{step.label}": a pass-through effect follows a SendTo ({Deep.show(
							kinds
						)}); pass-through comes first`
					)
				end
				if lastSend ~= nil and lastSend - firstSend + 1 ~= #sendOrder then
					table.insert(
						problems,
						`Contract: "{step.label}": the SendTo effects are not contiguous ({Deep.show(
							kinds
						)})`
					)
				end
				local expected = if step.leaver ~= nil
					then step.recipients
					elseif step.assignAfter ~= nil then step.assignAfter.players
					else {}
				if not Deep.equal(sendOrder, expected) then
					table.insert(
						problems,
						`Contract: "{step.label}": SendTo order is {Deep.show(sendOrder)}, expected seat order {Deep.show(
							expected
						)}`
					)
				end
			end
		end
	end
	if withSends < 3 then
		Contract.fail(`Contract precondition: only {withSends} steps with SendTo effects`)
	end
	if #problems > 0 then
		Contract.fail(
			`Contract: effects are ordered pass-through, then SendTo/SeatView in seat order, then at most one Broadcast last:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- `step` mutates neither its `state` nor its `event`: deep snapshots taken
-- before each step deep-equal the arguments afterwards.
function SessionContract.stepMutatesNeitherStateNorEvent(S: Session)
	local problems: { string } = {}
	for _, plan in { SessionContract.lifecycle(), SessionContract.quorumDrop() } do
		for _, step in SessionContract.run(S, "Contract", plan) do
			if not Deep.equal(step.beforeLive, step.before) then
				table.insert(
					problems,
					`Contract: "{step.label}": step mutated its state argument:\n{Deep.diff(
						step.before,
						step.beforeLive
					)}`
				)
			end
			if not Deep.equal(step.event, step.eventSnapshot) then
				table.insert(
					problems,
					`Contract: "{step.label}": step mutated its event argument:\n{Deep.diff(
						step.eventSnapshot,
						step.event
					)}`
				)
			end
		end
	end
	if #problems > 0 then
		Contract.fail(
			`Contract: step must mutate neither state nor event:\n{Contract.firstFew(problems, 8)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     The battery, named.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Session) -> () }

SessionContract.CHECKS = {
	{
		name = "newHoldsPhaseMachineInitialWithNoAssignment",
		ac = "Contract",
		run = SessionContract.newHoldsPhaseMachineInitialWithNoAssignment,
	},
	{
		name = "roundStateFollowsThePhaseMachineOnEveryStep",
		ac = "Contract",
		run = SessionContract.roundStateFollowsThePhaseMachineOnEveryStep,
	},
	{
		name = "dealsRingAssignFromTheEffectsSeedAndReachesRoundInOneStep",
		ac = "AC-1",
		run = SessionContract.dealsRingAssignFromTheEffectsSeedAndReachesRoundInOneStep,
	},
	{
		name = "dealsEachOfTwoConsecutiveRoundsFromItsOwnSeed",
		ac = "AC-1",
		run = SessionContract.dealsEachOfTwoConsecutiveRoundsFromItsOwnSeed,
	},
	{
		name = "sendsEachSeatedPlayerExactlyTheirOwnSeatViewAndBroadcastsNone",
		ac = "AC-2",
		run = SessionContract.sendsEachSeatedPlayerExactlyTheirOwnSeatViewAndBroadcastsNone,
	},
	{
		name = "withdrawsTheLeaverAndSendsViewsToExactlyThoseWhoseViewChanged",
		ac = "AC-3",
		run = SessionContract.withdrawsTheLeaverAndSendsViewsToExactlyThoseWhoseViewChanged,
	},
	{
		name = "withdrawsOnTheLeaveThatDropsBelowQuorumToo",
		ac = "AC-3",
		run = SessionContract.withdrawsOnTheLeaveThatDropsBelowQuorumToo,
	},
	{
		name = "sendsNoSeatViewAndKeepsTheRingWhenNobodyIsUnseated",
		ac = "AC-3",
		run = SessionContract.sendsNoSeatViewAndKeepsTheRingWhenNobodyIsUnseated,
	},
	{
		name = "clearsTheAssignmentOnEnteringLobby",
		ac = "AC-3",
		run = SessionContract.clearsTheAssignmentOnEnteringLobby,
	},
	{
		name = "broadcastsRoundViewExactlyWhenThePhaseOrCountChangesOrATickHasADuration",
		ac = "AC-4",
		run = SessionContract.broadcastsRoundViewExactlyWhenThePhaseOrCountChangesOrATickHasADuration,
	},
	{
		name = "roundViewCarriesExactlyTheTenKeysWithACeilingSecondsLeftFromConfig",
		ac = "AC-4",
		run = SessionContract.roundViewCarriesExactlyTheTenKeysWithACeilingSecondsLeftFromConfig,
	},
	{
		name = "passesThroughTheMachinesEffectsUnchangedInOrderAndConsumesAssignSeats",
		ac = "AC-5",
		run = SessionContract.passesThroughTheMachinesEffectsUnchangedInOrderAndConsumesAssignSeats,
	},
	{
		name = "ignoresASeatsAssignedEventFromOutsideAndEveryNoOp",
		ac = "Contract",
		run = SessionContract.ignoresASeatsAssignedEventFromOutsideAndEveryNoOp,
	},
	{
		name = "ordersPassThroughThenSeatViewsThenRoundViewLast",
		ac = "Contract",
		run = SessionContract.ordersPassThroughThenSeatViewsThenRoundViewLast,
	},
	{
		name = "stepMutatesNeitherStateNorEvent",
		ac = "Contract",
		run = SessionContract.stepMutatesNeitherStateNorEvent,
	},
} :: { Check }

function SessionContract.failures(S: Session): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in SessionContract.CHECKS do
		local ok, err = pcall(check.run, S)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return SessionContract
