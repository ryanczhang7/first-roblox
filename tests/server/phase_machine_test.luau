--!strict
--[[
	ROUND-003: the round phase machine, AC-1 through AC-8.

	`src/server/round/PhaseMachine.luau` is required through a `pcall` at the top
	and re-checked inside every test. That is not defensive dressing: in RED the
	module does not exist, and a bare top-level `require` would make this whole
	file a single LOAD FAIL - one line of red covering eight criteria. Per-
	criterion failures say which behaviours are missing, which is what GREEN
	needs. It is not a skip either: every test below still FAILS, loudly, naming
	the module that did not load.

	THE CONFIG IS INJECTED AND TINY ON PURPOSE. `CONFIG.lobbySeconds` is 3, not
	`Tuning.session.lobby_seconds`' 60, so a whole lifecycle runs in simulated
	seconds - and so that a machine which reaches for `Tuning` instead of the
	config it was handed FAILS rather than merely running slowly. That is the
	property the injection exists for and there is a test named after it.

	The durations themselves are SETTLED (`ROUND-002`, `docs/wiki/game/tuning.md`).
	Nothing here chooses or calibrates one: the real numbers are read out of
	`Tuning` in `tests/server/round_config_test.luau`, and the numbers here are
	test-fixture durations that the machine is told about, which is a different
	thing entirely.

	The AC-6 and AC-7 checks live in `tests/helpers/PhaseMachineContract.luau` and
	are exercised against deliberately wrong machines in
	`tests/server/phase_machine_controls_test.luau`. That file is where those
	checks are OBSERVED to fail; this file is where they are applied to the real
	one.
]]

local Clock = require("../../src/shared/Clock")
local Contract = require("../helpers/PhaseMachineContract")
local Deep = require("../helpers/Deep")

local loaded, loadResult = pcall(require, "../../src/server/round/PhaseMachine")

local function Machine(): any
	assert(loaded, `src/server/round/PhaseMachine.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- Fixture durations, not specification values. See the header.
local CONFIG = {
	lobbySeconds = 3,
	postRoundSeconds = 2,
	roundSeconds = 20,
	playersMin = 4,
	playersMax = 6,
	minPlayersToContinue = 3,
}

local SEED = 20260915
local ROUND_ID = "round-ROUND-003-a"
local PLAYERS = { "p1", "p2", "p3", "p4" }

--[[
	A `reason` no implementation would invent. AC-3 says the machine records the
	outcome UNCHANGED - it must not inspect it, compute it or override it - and a
	reason of "lost" or "clock" could plausibly be produced by a machine that
	decided the outcome itself. This one cannot.
]]
local function outcome(): any
	return { result = "no_contest", reason = "reason-x7f3-set-by-the-caller-not-the-machine" }
end

local function tick(): any
	return { kind = "Tick" }
end

local function joined(playerId: string): any
	return { kind = "PlayerJoined", playerId = playerId }
end

local function seatsAssigned(): any
	return { kind = "SeatsAssigned" }
end

local function roundResolved(result: any): any
	return { kind = "RoundResolved", outcome = result }
end

-- A fresh Lobby with `playersMin` players seated, entered at t = 0.
local function seatedLobby(): any
	local machine = Machine()
	local state = machine.initial(CONFIG, SEED, ROUND_ID)
	for _, id in PLAYERS do
		state = machine.step(state, joined(id), 0)
	end
	return state
end

--[[
	One state per phase, reached by driving the machine rather than by writing a
	state down. Writing them down would test the machine against my idea of what
	its states look like; driving it tests the machine against itself.

	The phase of each is asserted here so that a machine which fails to transition
	produces one clear failure rather than five confusing ones downstream.
]]
type Journey = {
	lobby: any,
	assignment: any,
	round: any,
	resolution: any,
	post: any,
}

local function journey(): Journey
	local machine = Machine()

	local lobby = seatedLobby()
	local assignment = machine.step(lobby, tick(), 3.5)
	local round = machine.step(assignment, seatsAssigned(), 4)
	local resolution = machine.step(round, roundResolved(outcome()), 6)
	local post = machine.step(resolution, tick(), 6)

	local reached: Journey = {
		lobby = lobby,
		assignment = assignment,
		round = round,
		resolution = resolution,
		post = post,
	}

	for _, expected in { "Lobby", "Assignment", "Round", "Resolution", "Post" } do
		local state = (reached :: any)[string.lower(expected)]
		assert(
			typeof(state) == "table" and state.phase == expected,
			`driving the machine to {expected} produced {Deep.show(state)}`
		)
	end

	return reached
end

type Lifecycle = {
	phases: { string },
	effects: { string },
	final: any,
}

--[[
	AC-8's lifecycle, driven end to end by a MANUAL CLOCK from `ROUND-001`.

	The tick sequence is deliberately IRREGULAR - 0.5, then 3.0, then 1.5, 1.0,
	0, 1.0, 1.5 - because a machine that measures a phase from "the last step"
	rather than from "the step that entered the phase" passes a regular sequence
	and fails this one. Post is entered at t = 6 with `postRoundSeconds` of 2; it
	is ticked at 7 and then at 8.5, and a machine measuring from the previous step
	would still be sitting in Post at 8.5.
]]
local function runLifecycle(seed: number, roundId: string): Lifecycle
	local machine = Machine()
	local clock = Clock.manual(0)
	local state = machine.initial(CONFIG, seed, roundId)

	local phases: { string } = { state.phase }
	local effects: { string } = {}

	local function apply(event: any)
		local nextState, produced = machine.step(state, event, clock.now())
		assert(
			typeof(produced) == "table",
			`step returned {typeof(produced)} for its effect list at t = {clock.now()}`
		)
		for _, kind in Deep.kinds(produced) do
			table.insert(effects, kind)
		end
		if nextState.phase ~= state.phase then
			table.insert(phases, nextState.phase)
		end
		state = nextState
	end

	for _, id in PLAYERS do
		apply(joined(id))
	end

	clock:advance(0.5)
	apply(tick()) -- t = 0.5  Lobby, 2.5 short of lobbySeconds
	clock:advance(3.0)
	apply(tick()) -- t = 3.5  past lobbySeconds = 3, entered at 0  -> Assignment
	apply(seatsAssigned()) -- t = 3.5                              -> Round
	clock:advance(1.5)
	apply(tick()) -- t = 5.0  Round, well inside roundSeconds
	clock:advance(1.0)
	apply(roundResolved(outcome())) -- t = 6.0                     -> Resolution
	apply(tick()) -- t = 6.0  the clock has not moved              -> Post
	clock:advance(1.0)
	apply(tick()) -- t = 7.0  Post, 1 short of postRoundSeconds
	clock:advance(1.5)
	apply(tick()) -- t = 8.5  past postRoundSeconds = 2, entered at 6 -> Lobby

	return { phases = phases, effects = effects, final = state }
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and because a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: PhaseMachine exports initial and step as plain field functions"] = function()
		local machine = Machine()
		assert(
			typeof(machine.initial) == "function",
			`PhaseMachine.initial is {typeof(machine.initial)}, wanted a function`
		)
		assert(
			typeof(machine.step) == "function",
			`PhaseMachine.step is {typeof(machine.step)}, wanted a function`
		)
	end,

	["Contract: initial returns a Lobby entered at 0, with no players, no outcome, and the seed and round id it was given"] = function()
		local state = Machine().initial(CONFIG, SEED, ROUND_ID)
		assert(state.phase == "Lobby", `a fresh machine is in {tostring(state.phase)}`)
		assert(
			state.phaseEnteredAt == 0,
			`a fresh Lobby was entered at {tostring(state.phaseEnteredAt)}; initial takes no `
				.. `now, so the only self-consistent answer is 0`
		)
		assert(state.seed == SEED, `initial kept the seed as {tostring(state.seed)}`)
		assert(state.roundId == ROUND_ID, `initial kept the round id as {tostring(state.roundId)}`)
		assert(
			Deep.equal(state.players, {}),
			`a fresh Lobby seats {Deep.show(state.players)} and should seat nobody`
		)
		assert(state.outcome == nil, `a fresh Lobby carries an outcome: {Deep.show(state.outcome)}`)
	end,

	["Contract: PlayerJoined seats a player, in arrival order"] = function()
		local state = seatedLobby()
		assert(
			Deep.equal(state.players, PLAYERS),
			`after four PlayerJoined events the seats are {Deep.show(state.players)}, `
				.. `wanted {Deep.show(PLAYERS)}`
		)
	end,

	--[[ AC-1. The boundary is `now - phaseEnteredAt >= duration`, inclusive, and
	     both sides of it are pinned. The test below is the one a `>`
	     implementation must break, so it is a SINGLE assertion and nothing else
	     in this suite sits exactly on the Lobby boundary. ]]

	["AC-1: the Lobby leaves for Assignment at exactly lobbySeconds elapsed"] = function()
		local after = Machine().step(seatedLobby(), tick(), CONFIG.lobbySeconds)
		assert(
			after.phase == "Assignment",
			`at exactly lobbySeconds ({CONFIG.lobbySeconds}) elapsed the phase is `
				.. `{tostring(after.phase)}; the comparison is >=, not >`
		)
	end,

	["AC-1: at a tenth of a second short of lobbySeconds the machine is still in Lobby and has emitted nothing"] = function()
		local after, effects = Machine().step(seatedLobby(), tick(), CONFIG.lobbySeconds - 0.1)
		assert(
			after.phase == "Lobby",
			`at lobbySeconds - 0.1 the phase is already {tostring(after.phase)}`
		)
		assert(
			#effects == 0,
			`at lobbySeconds - 0.1 the machine emitted {Deep.show(Deep.kinds(effects))}`
		)
	end,

	["AC-1: the lobby duration is measured from the step that entered the phase, not from the previous step"] = function()
		local machine = Machine()

		local nearly = machine.step(seatedLobby(), tick(), 2.9)
		assert(nearly.phase == "Lobby", `at t = 2.9 the phase is already {tostring(nearly.phase)}`)

		local after = machine.step(nearly, tick(), 3.5)
		assert(
			after.phase == "Assignment",
			`the Lobby was entered at 0 and ticked at 2.9 and 3.5. At 3.5 the phase is `
				.. `{tostring(after.phase)}: 3.5 elapsed since entry is past lobbySeconds = 3, `
				.. `and only a machine measuring from the LAST step (2.9) is still waiting`
		)
		assert(
			after.phaseEnteredAt == 3.5,
			`Assignment was entered by the step at now = 3.5 and records `
				.. `phaseEnteredAt = {tostring(after.phaseEnteredAt)}`
		)
	end,

	["AC-1: the machine obeys the config it was injected with, not Tuning's sixty-second lobby"] = function()
		local after = Machine().step(seatedLobby(), tick(), 4)
		assert(
			after.phase == "Assignment",
			`with an injected lobbySeconds of {CONFIG.lobbySeconds}, the phase at t = 4 is `
				.. `{tostring(after.phase)}. A machine reading Tuning.session.lobby_seconds (60) `
				.. `instead of its config is exactly this failure`
		)
	end,

	--[[ AC-2 ]]

	["AC-2: entering Assignment emits exactly one AssignSeats, carrying the round seed and the seated players"] = function()
		local lobby = seatedLobby()
		local assignment, effects = Machine().step(lobby, tick(), 3.5)

		assert(assignment.phase == "Assignment", `the phase is {tostring(assignment.phase)}`)
		assert(
			#effects == 1,
			`entering Assignment emitted {#effects} effect(s): {Deep.show(Deep.kinds(effects))}; `
				.. `AC-2 says exactly one`
		)
		assert(
			effects[1].kind == "AssignSeats",
			`the effect is {tostring(effects[1].kind)}, wanted AssignSeats`
		)
		assert(
			effects[1].seed == lobby.seed,
			`AssignSeats carries seed {tostring(effects[1].seed)}, wanted the round's own `
				.. `{tostring(lobby.seed)}`
		)
		assert(
			Deep.equal(effects[1].players, PLAYERS),
			`AssignSeats carries {Deep.show(effects[1].players)}, wanted the seated players `
				.. `{Deep.show(PLAYERS)}`
		)
	end,

	["AC-2: a further step inside Assignment does not emit AssignSeats a second time"] = function()
		local machine = Machine()
		local assignment = machine.step(seatedLobby(), tick(), 3.5)
		local _, effects = machine.step(assignment, tick(), 3.6)
		assert(
			#effects == 0,
			`a second step inside Assignment emitted {Deep.show(Deep.kinds(effects))}. `
				.. `AssignSeats is emitted on ENTERING the phase, not once per step`
		)
	end,

	["AC-2: Assignment is a step and not a pause - it waits for SeatsAssigned however long the clock runs"] = function()
		local machine = Machine()
		local assignment = machine.step(seatedLobby(), tick(), 3.5)
		local later = machine.step(assignment, tick(), 3.5 + 1000)
		assert(
			later.phase == "Assignment",
			`a thousand seconds after entering Assignment the phase is {tostring(later.phase)}; `
				.. `Assignment has no duration and leaves only on SeatsAssigned`
		)
	end,

	["AC-2: SeatsAssigned moves Assignment to Round and emits nothing"] = function()
		local machine = Machine()
		local assignment = machine.step(seatedLobby(), tick(), 3.5)
		local round, effects = machine.step(assignment, seatsAssigned(), 4)

		assert(round.phase == "Round", `SeatsAssigned left the machine in {tostring(round.phase)}`)
		assert(
			round.phaseEnteredAt == 4,
			`Round records phaseEnteredAt = {tostring(round.phaseEnteredAt)}, wanted 4`
		)
		assert(
			#effects == 0,
			`SeatsAssigned produced {Deep.show(Deep.kinds(effects))}; AC-8 fixes the whole `
				.. `effect sequence at AssignSeats, ComputeTrace, PromptRematch`
		)
	end,

	--[[ AC-3. The outcome is the caller's, verbatim. ]]

	["AC-3: RoundResolved moves Round to Resolution and records the outcome unchanged"] = function()
		local machine = Machine()
		local round = journey().round
		local given = outcome()

		local resolution = machine.step(round, roundResolved(given), 6)

		assert(
			resolution.phase == "Resolution",
			`RoundResolved left the machine in {tostring(resolution.phase)}`
		)
		assert(
			typeof(resolution.outcome) == "table",
			`the outcome is {Deep.show(resolution.outcome)}`
		)
		assert(
			resolution.outcome.result == given.result,
			`the recorded result is {tostring(resolution.outcome.result)}, wanted `
				.. `{tostring(given.result)} - the machine does not compute an outcome`
		)
		assert(
			resolution.outcome.reason == given.reason,
			`the recorded reason is {tostring(resolution.outcome.reason)}, wanted the opaque `
				.. `string the caller supplied: {tostring(given.reason)}`
		)
		assert(
			Deep.equal(resolution.outcome, given),
			`the recorded outcome differs from the one supplied:\n{Deep.diff(
				given,
				resolution.outcome
			)}`
		)
	end,

	["AC-3: an outcome of a different result is recorded just as unchanged"] = function()
		local machine = Machine()
		local given = { result = "won", reason = "reason-q41z-the-machine-cannot-have-derived" }
		local resolution = machine.step(journey().round, roundResolved(given), 6)
		assert(
			Deep.equal(resolution.outcome, given),
			`the machine altered an outcome it was handed:\n{Deep.diff(given, resolution.outcome)}`
		)
	end,

	--[[ AC-4. Resolution has no duration. ]]

	["AC-4: Resolution moves to Post on the next step with the clock standing still, emitting exactly one ComputeTrace"] = function()
		local machine = Machine()
		local resolution = journey().resolution
		assert(
			resolution.phaseEnteredAt == 6,
			`Resolution was entered at {tostring(resolution.phaseEnteredAt)}, wanted 6`
		)

		-- The same `now` the phase was entered at: nothing has waited.
		local post, effects = machine.step(resolution, tick(), resolution.phaseEnteredAt)

		assert(
			post.phase == "Post",
			`with the clock unmoved since entering Resolution the phase is {tostring(post.phase)}; `
				.. `Resolution transitions on the next step and does not wait on the clock`
		)
		assert(
			#effects == 1 and effects[1].kind == "ComputeTrace",
			`leaving Resolution emitted {Deep.show(Deep.kinds(effects))}, wanted exactly one `
				.. `ComputeTrace`
		)
	end,

	["AC-4: the ComputeTrace effect carries the round id the machine was given"] = function()
		local machine = Machine()
		local resolution = journey().resolution
		local _, effects = machine.step(resolution, tick(), resolution.phaseEnteredAt)
		assert(
			effects[1].roundId == ROUND_ID,
			`ComputeTrace carries roundId {tostring(effects[1].roundId)}, wanted {ROUND_ID}`
		)
	end,

	--[[ AC-5 ]]

	["AC-5: past postRoundSeconds the machine returns to Lobby, emitting exactly one PromptRematch"] = function()
		local post = journey().post
		local lobby, effects = Machine().step(post, tick(), post.phaseEnteredAt + 2.5)

		assert(lobby.phase == "Lobby", `past postRoundSeconds the phase is {tostring(lobby.phase)}`)
		assert(
			#effects == 1 and effects[1].kind == "PromptRematch",
			`leaving Post emitted {Deep.show(Deep.kinds(effects))}, wanted exactly one PromptRematch`
		)
	end,

	["AC-5: the Post phase leaves at exactly postRoundSeconds elapsed"] = function()
		local post = journey().post
		local after = Machine().step(post, tick(), post.phaseEnteredAt + CONFIG.postRoundSeconds)
		assert(
			after.phase == "Lobby",
			`at exactly postRoundSeconds ({CONFIG.postRoundSeconds}) elapsed the phase is `
				.. `{tostring(after.phase)}; the comparison is >=, not >`
		)
	end,

	["AC-5: at a tenth of a second short of postRoundSeconds the machine is still in Post"] = function()
		local post = journey().post
		local after =
			Machine().step(post, tick(), post.phaseEnteredAt + CONFIG.postRoundSeconds - 0.1)
		assert(
			after.phase == "Post",
			`at postRoundSeconds - 0.1 the phase is already {tostring(after.phase)}`
		)
	end,

	["AC-5: the returning Lobby carries a seed distinct from the round that just ended"] = function()
		local post = journey().post
		local lobby = Machine().step(post, tick(), post.phaseEnteredAt + 2.5)
		assert(
			typeof(lobby.seed) == "number",
			`the returning Lobby's seed is {typeof(lobby.seed)}: {Deep.show(lobby.seed)}`
		)
		assert(
			lobby.seed ~= post.seed,
			`the returning Lobby reuses the previous round's seed ({tostring(post.seed)}); `
				.. `AC-5 requires a NEW one`
		)
	end,

	["AC-5: the next round's seed is derived deterministically - the same lifecycle replayed produces the same seed"] = function()
		local first = runLifecycle(SEED, ROUND_ID)
		local second = runLifecycle(SEED, ROUND_ID)
		assert(
			first.final.seed == second.final.seed,
			`two identical lifecycles produced next-round seeds {tostring(first.final.seed)} and `
				.. `{tostring(second.final.seed)}. AC-6's purity depends on this derivation not `
				.. `reaching for a real random source`
		)
	end,

	["AC-5: a different round seed derives a different next-round seed"] = function()
		local first = runLifecycle(SEED, ROUND_ID)
		local other = runLifecycle(SEED + 1, ROUND_ID)
		assert(
			first.final.seed ~= other.final.seed,
			`two lifecycles seeded {SEED} and {SEED + 1} both ended at seed `
				.. `{tostring(first.final.seed)}. A constant is deterministic and distinct from `
				.. `one previous seed, and is still not a new seed per round`
		)
	end,

	--[[ AC-6. The checks are in PhaseMachineContract and are observed failing in
	     phase_machine_controls_test.luau; here they are applied to the real
	     machine, over one case per transition rather than over no-op steps -
	     mutation happens where work happens. ]]

	["AC-6: two identical steps return equal states and equal effect lists, in every phase"] = function()
		local machine = Machine()
		local reached = journey()
		local cases: { Contract.Case } = {
			{
				label = "a seating PlayerJoined in Lobby",
				state = reached.lobby,
				event = joined("p5"),
				now = 1,
			},
			{
				label = "the Tick that leaves Lobby",
				state = reached.lobby,
				event = tick(),
				now = 3.5,
			},
			{
				label = "SeatsAssigned in Assignment",
				state = reached.assignment,
				event = seatsAssigned(),
				now = 4,
			},
			{
				label = "RoundResolved in Round",
				state = reached.round,
				event = roundResolved(outcome()),
				now = 6,
			},
			{
				label = "the Tick that leaves Resolution",
				state = reached.resolution,
				event = tick(),
				now = 6,
			},
			{
				label = "the Tick that leaves Post",
				state = reached.post,
				event = tick(),
				now = 8.5,
			},
		}

		for _, case in cases do
			Contract.stepIsDeterministic(machine, case)
		end
	end,

	--[[ THE assertion of this story. A deep snapshot of the input taken before
	     the call, deep-compared against the input after it - never an identity
	     check, which `MachineStubs.mutatingCopier` passes while corrupting the
	     caller's state. Violations are accumulated so one run names every phase
	     that mutates rather than the first. ]]

	["AC-6: step does not mutate the state it was given, in any phase"] = function()
		local machine = Machine()
		local reached = journey()
		local cases: { Contract.Case } = {
			{
				label = "a seating PlayerJoined in Lobby",
				state = reached.lobby,
				event = joined("p5"),
				now = 1,
			},
			{
				label = "the Tick that leaves Lobby",
				state = reached.lobby,
				event = tick(),
				now = 3.5,
			},
			{
				label = "SeatsAssigned in Assignment",
				state = reached.assignment,
				event = seatsAssigned(),
				now = 4,
			},
			{
				label = "RoundResolved in Round",
				state = reached.round,
				event = roundResolved(outcome()),
				now = 6,
			},
			{
				label = "the Tick that leaves Resolution",
				state = reached.resolution,
				event = tick(),
				now = 6,
			},
			{
				label = "the Tick that leaves Post",
				state = reached.post,
				event = tick(),
				now = 8.5,
			},
		}

		local violations: { string } = {}
		for _, case in cases do
			local ok, err = pcall(Contract.stepDoesNotMutateItsInput, machine, case)
			if not ok then
				table.insert(violations, tostring(err))
			end
		end

		assert(
			#violations == 0,
			`step mutated its input in {#violations} of {#cases} case(s):\n`
				.. table.concat(violations, "\n")
		)
	end,

	--[[
		The same assertion on ONE state that needed no cross-phase setup to
		reach, so that it fires with its own message.

		The test above drives the machine through five phases first, and a
		machine that mutates and returns its input cannot be driven anywhere:
		all five states are one table and `journey()`'s own phase assertions
		fail before the AC-6 check runs. That is still a failure, but it is
		attributed to the wrong thing. This one is reached by four seating steps
		in a single phase, so the mutation the criterion names produces the
		message the criterion names.
	]]
	["AC-6: the step that leaves the Lobby does not mutate the state it was given"] = function()
		Contract.stepDoesNotMutateItsInput(Machine(), {
			label = "the Tick that leaves Lobby",
			state = seatedLobby(),
			event = tick(),
			now = 3.5,
		})
	end,

	--[[ AC-7. Totality, one test per case the story names. ]]

	["AC-7: SeatsAssigned applied a second time is ignored"] = function()
		local machine = Machine()
		local round = journey().round
		Contract.eventIsIgnored(machine, {
			label = "a second SeatsAssigned, already consumed on entering Round",
			state = round,
			event = seatsAssigned(),
			now = 4.5,
		})
	end,

	["AC-7: RoundResolved in Lobby is ignored"] = function()
		Contract.eventIsIgnored(Machine(), {
			label = "a RoundResolved in Lobby",
			state = seatedLobby(),
			event = roundResolved(outcome()),
			now = 1,
		})
	end,

	["AC-7: RematchAccepted in Round is ignored"] = function()
		Contract.eventIsIgnored(Machine(), {
			label = "a RematchAccepted in Round",
			state = journey().round,
			event = { kind = "RematchAccepted", playerId = "p1" },
			now = 5,
		})
	end,

	["AC-7: an event naming a player who was never seated is ignored"] = function()
		Contract.eventIsIgnored(Machine(), {
			label = "a PlayerLeft naming a player who was never seated",
			state = seatedLobby(),
			event = { kind = "PlayerLeft", playerId = "never-seated-p99" },
			now = 1,
		})
	end,

	["AC-7: a duplicate PlayerJoined does not seat the same player twice"] = function()
		Contract.eventIsIgnored(Machine(), {
			label = "a PlayerJoined for a player already seated",
			state = seatedLobby(),
			event = joined(PLAYERS[1]),
			now = 1,
		})
	end,

	["AC-7: an event whose kind is not in the union is ignored"] = function()
		Contract.eventIsIgnored(Machine(), {
			label = "an event whose kind is a string the union does not contain",
			state = seatedLobby(),
			event = { kind = "DetonateTheReactor", playerId = "p1" },
			now = 1,
		})
	end,

	--[[
		AC-7 read literally, and deliberately so: the state comes back unchanged
		even when the phase's duration is already due.

		`now = 9` is past the Lobby's 3 seconds (entered at 0) and past Post's 2
		(entered at 6). A machine that evaluates its timers on EVERY step rather
		than on the events the phase recognises - `Tick` - transitions here, and
		AC-7 says an unrecognised event returns the state unchanged. This is the
		one place in the suite where those two readings differ, and the criterion
		decides it. Recorded in the story's `## Contract` and `## Handoff`.
	]]
	["AC-7: an unrecognised event is ignored in every phase, even when the phase's duration is due"] = function()
		local machine = Machine()
		local reached = journey()
		local violations: { string } = {}

		for _, phase in { "lobby", "assignment", "round", "resolution", "post" } do
			local ok, err = pcall(Contract.eventIsIgnored, machine, {
				label = `an event whose kind is not in the union, in {phase}, at now = 9`,
				state = (reached :: any)[phase],
				event = { kind = "NotAnEventKind" },
				now = 9,
			})
			if not ok then
				table.insert(violations, tostring(err))
			end
		end

		assert(
			#violations == 0,
			`an unrecognised event was not ignored in {#violations} phase(s). A phase duration `
				.. `that is due is not a reason to act on an event the phase does not recognise; `
				.. `the timer belongs to Tick:\n`
				.. table.concat(violations, "\n")
		)
	end,

	--[[ AC-8. Whole lists, not membership checks. ]]

	["AC-8: a full lifecycle on a manual clock passes through exactly Lobby, Assignment, Round, Resolution, Post, Lobby"] = function()
		local lifecycle = runLifecycle(SEED, ROUND_ID)
		local expected = { "Lobby", "Assignment", "Round", "Resolution", "Post", "Lobby" }
		assert(
			Deep.equal(lifecycle.phases, expected),
			`the lifecycle visited {Deep.show(lifecycle.phases)}, wanted {Deep.show(expected)}`
		)
	end,

	["AC-8: a full lifecycle emits exactly AssignSeats, ComputeTrace, PromptRematch, in that order"] = function()
		local lifecycle = runLifecycle(SEED, ROUND_ID)
		local expected = { "AssignSeats", "ComputeTrace", "PromptRematch" }
		assert(
			Deep.equal(lifecycle.effects, expected),
			`the lifecycle emitted {Deep.show(lifecycle.effects)}, wanted {Deep.show(expected)}`
		)
	end,
}
