--!strict
--[[
	The wrong machines ROUND-005's controls are aimed at, and the one baseline
	they are each one defect away from.

	TWO CRITERIA NAME THEIR CONTROL IN THE CRITERION. AC-3: "an implementation
	that records a quorum failure as `lost` **must** fail this". AC-6: "an
	implementation that keeps ticking a finished round emits a second
	`ComputeTrace` and **must** fail this". A criterion that names an
	implementation needs an implementation to point at, so - unlike
	`MachineStubs.luau`, whose stubs are deliberately not machines - the machines
	below really do run a round from a Lobby to a Lobby.

	WHAT THIS IS NOT, and it matters because the next agent to read it is the one
	who has to write the real thing: it is NOT the production module and it is
	not a sketch of one. It is written as a FACTORY over a table of defects
	rather than as a set of wrappers (which is how `LobbyGateStubs.luau` does it)
	because a whole lifecycle cannot be wrapped as cheaply as a lobby can, and a
	control assembled from five copies of a lifecycle is a control broken in five
	ways. `defects` is empty for the baseline and has exactly ONE field set for
	each control below, so a control that fires is attributable to that one
	field.

	It is also deliberately incomplete where completeness would make it a
	template: the returning Lobby carries the SAME seed rather than deriving the
	next round's from it through `Rng` (ROUND-003 AC-5), it has no types beyond
	`any`, and it enforces none of ROUND-003's purity reasoning beyond what these
	checks read. GREEN writes `src/server/round/PhaseMachine.luau` from the
	story's Contract, against the failing tests; copying this file would fail
	ROUND-003's suite.

	NOTHING HERE REQUIRES PRODUCTION CODE. That is the point: in RED these
	controls are EXECUTED, and
	`tests/server/round_ending_controls_test.luau` records what each one actually
	did rather than what it was expected to do.
]]

local RoundEndingStubs = {}

--[[
	One field per control, and each one is a single edit to the machine below.

	  * `quorumAtOrBelow`     - `<=` where the Contract says `<` (AC-7, and
	                            mutation 1 of the story's `## Notes`)
	  * `clockBeforeQuorum`   - the precedence list reordered so `clock` precedes
	                            `below_quorum` (AC-5, mutation 2)
	  * `quorumResultIsLost`  - the quorum ending recorded as a loss (AC-3,
	                            mutation 3)
	  * `traceOnTheWayOut`    - a `ComputeTrace` emitted from the `Round` branch
	                            on the way out, so the `Resolution -> Post` tick
	                            emits a second one (AC-6)
	  * `clockBeforeTheEvent` - the clock outranking a `RoundResolved` that
	                            arrived on the same step (AC-4)
]]
export type Defects = {
	quorumAtOrBelow: boolean?,
	clockBeforeQuorum: boolean?,
	quorumResultIsLost: boolean?,
	traceOnTheWayOut: boolean?,
	clockBeforeTheEvent: boolean?,
}

local function isSeated(players: { string }, playerId: string): boolean
	for _, id in players do
		if id == playerId then
			return true
		end
	end
	return false
end

local function indexOf(players: { string }, playerId: string): number?
	for index, id in players do
		if id == playerId then
			return index
		end
	end
	return nil
end

-- A copy sharing no mutable table with its original, exactly as ROUND-003 AC-6
-- requires of the real machine.
local function copyOf(state: any): any
	local copy = table.clone(state)
	copy.players = table.clone(state.players)
	return copy
end

local function entering(state: any, phase: string, now: number): any
	local entered = copyOf(state)
	entered.phase = phase
	entered.phaseEnteredAt = now
	return entered
end

local function makeMachine(defects: Defects): any
	local machine = {}

	function machine.initial(config: any, seed: number, roundId: string): any
		return {
			phase = "Lobby",
			phaseEnteredAt = 0,
			roundId = roundId,
			seed = seed,
			players = {},
			outcome = nil,
			config = config,
		}
	end

	local function belowQuorum(state: any): boolean
		if defects.quorumAtOrBelow then
			return #state.players <= state.config.minPlayersToContinue
		end
		return #state.players < state.config.minPlayersToContinue
	end

	local function clockExpired(state: any, now: number): boolean
		return now - state.phaseEnteredAt >= state.config.roundSeconds
	end

	local function quorumOutcome(): any
		return {
			result = if defects.quorumResultIsLost then "lost" else "no_contest",
			reason = "below_quorum",
		}
	end

	local function clockOutcome(): any
		return { result = "lost", reason = "clock" }
	end

	--[[
		The precedence list of the story's Contract, in ONE place so that each
		control can disturb exactly it and nothing else.

		`consultTheClock` is false on the `PlayerLeft` path: Contract pin 1 says
		that step unseats and then evaluates QUORUM, and no criterion says the
		clock is read there. No check in `RoundEndingContract.luau` combines a
		departure with an expired clock, so nothing here is pinned by it either
		way.
	]]
	local function terminalOutcome(state: any, carried: any, now: number, clock: boolean): any
		if
			defects.clockBeforeTheEvent
			and carried ~= nil
			and clock
			and clockExpired(state, now)
		then
			return clockOutcome()
		end
		if carried ~= nil then
			return carried
		end
		if defects.clockBeforeQuorum and clock and clockExpired(state, now) then
			return clockOutcome()
		end
		if belowQuorum(state) then
			return quorumOutcome()
		end
		if clock and clockExpired(state, now) then
			return clockOutcome()
		end
		return nil
	end

	local function resolveIfTerminal(
		state: any,
		carried: any,
		now: number,
		clock: boolean
	): (any, { any })
		local outcome = terminalOutcome(state, carried, now, clock)
		if outcome == nil then
			return state, {}
		end
		local resolution = entering(state, "Resolution", now)
		resolution.outcome = outcome
		if defects.traceOnTheWayOut then
			return resolution, { { kind = "ComputeTrace", roundId = state.roundId } }
		end
		return resolution, {}
	end

	function machine.step(state: any, event: any, now: number): (any, { any })
		if event.kind == "PlayerJoined" then
			if
				state.phase ~= "Lobby"
				or isSeated(state.players, event.playerId)
				or #state.players >= state.config.playersMax
			then
				return state, {}
			end
			local seated = copyOf(state)
			table.insert(seated.players, event.playerId)
			return seated, {}
		end

		if event.kind == "PlayerLeft" then
			if state.phase ~= "Lobby" and state.phase ~= "Round" then
				return state, {}
			end
			local seat = indexOf(state.players, event.playerId)
			if seat == nil then
				return state, {}
			end
			local remaining = copyOf(state)
			table.remove(remaining.players, seat)
			if state.phase == "Round" then
				return resolveIfTerminal(remaining, nil, now, false)
			end
			return remaining, {}
		end

		if event.kind == "SeatsAssigned" then
			if state.phase ~= "Assignment" then
				return state, {}
			end
			return entering(state, "Round", now), {}
		end

		if event.kind == "RoundResolved" then
			if state.phase ~= "Round" then
				return state, {}
			end
			return resolveIfTerminal(state, event.outcome, now, true)
		end

		if event.kind == "Tick" then
			if
				state.phase == "Lobby"
				and now - state.phaseEnteredAt >= state.config.lobbySeconds
				and #state.players >= state.config.playersMin
			then
				return entering(state, "Assignment", now),
					{
						{
							kind = "AssignSeats",
							seed = state.seed,
							players = table.clone(state.players),
						},
					}
			end

			if state.phase == "Round" then
				return resolveIfTerminal(state, nil, now, true)
			end

			if state.phase == "Resolution" then
				return entering(state, "Post", now),
					{ { kind = "ComputeTrace", roundId = state.roundId } }
			end

			if
				state.phase == "Post"
				and now - state.phaseEnteredAt >= state.config.postRoundSeconds
			then
				local lobby = entering(state, "Lobby", now)
				lobby.outcome = nil
				return lobby, { { kind = "PromptRematch" } }
			end

			return state, {}
		end

		return state, {}
	end

	return machine
end

RoundEndingStubs.makeMachine = makeMachine

--[[
	The baseline: the three endings, in the Contract's precedence order, with the
	strict comparison and the ending step emitting nothing.

	Every control below is this machine with exactly one defect set.
]]
RoundEndingStubs.ending = makeMachine({})

--[[
	AC-3's control, named in the criterion: the quorum ending recorded as `lost`.

	It ENDS the round, on the right step, with the right reason - only the
	`result` differs - which is the trap. A test asserting "the round ended", or
	even "the round ended below_quorum", is green for it, and the difference is
	whether three players lose season progress because a fourth person's
	connection dropped (`mechanics.md` section 8, amendment 9).
]]
RoundEndingStubs.losing = makeMachine({ quorumResultIsLost = true })

--[[
	AC-6's control, named in the criterion: a machine that keeps ticking a
	finished round.

	It emits a `ComputeTrace` from the `Round` branch on the way out AND still
	emits one on the `Resolution -> Post` tick, so the ending sequence carries
	two. Every outcome it records is correct, so AC-1 to AC-5 and AC-7 are green
	for it and only the effect count sees it.
]]
RoundEndingStubs.doubleTracing = makeMachine({ traceOnTheWayOut = true })

--[[
	AC-5's control: the precedence list reordered so `clock` precedes
	`below_quorum`.

	This is mutation 2 of the story's `## Notes`. A `RoundResolved` still wins,
	and a departure that takes the count below the threshold before the clock is
	due still ends the round `no_contest` - so AC-2, AC-3, AC-4 and AC-7 are
	green for it. Only the single step on which BOTH hold tells them apart, which
	is why AC-5 is checked on one step rather than two.
]]
RoundEndingStubs.clockFirst = makeMachine({ clockBeforeQuorum = true })

--[[
	AC-7's control: `<=` where the Contract says `<`.

	This is mutation 1 of the story's `## Notes`, and it is the off-by-one that
	would silently end every three-player round. It records the right outcome
	whenever it does end a round, so AC-3, AC-5 and AC-6 are green for it: only
	the count at which the round ends is wrong.
]]
RoundEndingStubs.atOrBelow = makeMachine({ quorumAtOrBelow = true })

--[[
	AC-4's control: the clock outranking a `RoundResolved` that arrived on the
	same step.

	The event is dropped and the round is recorded as `lost(clock)`. Every
	ending that is NOT simultaneous with the clock is correct, so AC-1, AC-2,
	AC-3, AC-5, AC-6 and AC-7 are green for it - and a test that advances the
	clock and then sends the event is green for it too, because by then the round
	has already ended and the event is arriving at a `Resolution`. That is the
	whole reason AC-4 is checked on one step.
]]
RoundEndingStubs.eventLoses = makeMachine({ clockBeforeTheEvent = true })

return RoundEndingStubs
