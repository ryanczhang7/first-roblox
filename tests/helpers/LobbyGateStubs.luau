--!strict
--[[
	The wrong lobbies ROUND-004's controls are aimed at, and the one baseline
	they are each one defect away from.

	AC-2 NAMES ITS CONTROL IN THE CRITERION: "an implementation that resets
	`phaseEnteredAt` on every join **must** fail this, and must pass AC-1". A
	criterion that names an implementation needs an implementation to point at,
	so unlike `MachineStubs.luau` - whose stubs are deliberately not machines -
	`LobbyGateStubs.holding` below really does seat, unseat and gate a lobby.

	WHAT IT IS NOT, and this matters because the next agent to read it is the one
	who has to write the real thing: it is NOT the production module and it is not
	a sketch of one. It implements the Lobby and nothing else - no Assignment, no
	Round, no Resolution, no Post, no seed derivation, no SeatsAssigned, no
	RoundResolved, no ComputeTrace, no PromptRematch. Driving it past the lobby
	does nothing at all. GREEN writes src/server/round/PhaseMachine.luau from the
	story's Contract, against the failing tests, and copying this file would
	produce a machine that fails every ROUND-003 criterion.

	`holding` is the BASELINE. Every wrong lobby below is `holding` with exactly
	ONE thing changed, and each is built by WRAPPING it rather than by restating
	it, so a control that fires is attributable to that one thing rather than to
	a stub that is broken in six ways.

	NOTHING HERE REQUIRES PRODUCTION CODE. That is the point: in RED these
	controls are EXECUTED, and tests/server/lobby_gate_controls_test.luau records
	what each one actually did rather than what it was expected to do.
]]

local LobbyGateStubs = {}

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

--[[
	The baseline: a Lobby that holds below `playersMin`, caps at `playersMax`,
	refuses a duplicate join, unseats in the Lobby only, and never rewrites
	`phaseEnteredAt` on a join or a leave.
]]
local holding = {}

function holding.initial(config: any, seed: number, roundId: string): any
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

function holding.step(state: any, event: any, now: number): (any, { any })
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
		local index = if state.phase == "Lobby" then indexOf(state.players, event.playerId) else nil
		if index == nil then
			return state, {}
		end
		local left = copyOf(state)
		table.remove(left.players, index)
		return left, {}
	end

	if event.kind == "Tick" then
		local elapsed = now - state.phaseEnteredAt
		if
			state.phase == "Lobby"
			and elapsed >= state.config.lobbySeconds
			and #state.players >= state.config.playersMin
		then
			local assignment = copyOf(state)
			assignment.phase = "Assignment"
			assignment.phaseEnteredAt = now
			return assignment,
				{
					{
						kind = "AssignSeats",
						seed = state.seed,
						players = table.clone(state.players),
					},
				}
		end
		return state, {}
	end

	return state, {}
end

LobbyGateStubs.holding = holding

--[[
	AC-2's control, named in the criterion: the hold turned into a reset.

	ONE defect, applied as a wrapper so the rest is identical to the baseline: a
	join that seats somebody also stamps `phaseEnteredAt` with the `now` of the
	join. It still gates on the count, so it passes AC-1 - the half that stops
	this being a stub that fails everything - and it still starts a round
	eventually, which is why a test asserting only "the round starts" cannot tell
	it from the real thing.
]]
LobbyGateStubs.resetting = {
	initial = holding.initial,
	step = function(state: any, event: any, now: number): (any, { any })
		local nextState, effects = holding.step(state, event, now)
		if event.kind == "PlayerJoined" and nextState ~= state then
			local reset = copyOf(nextState)
			reset.phaseEnteredAt = now
			return reset, effects
		end
		return nextState, effects
	end,
}

--[[
	AC-4's control: a lobby that makes room instead of refusing.

	It evicts the longest-seated player and appends the newcomer, so the seated
	list is still exactly `playersMax` long. A test that checks only the LENGTH
	passes this while a player who was already in the ring has been thrown out of
	it - which is why AC-4 asserts who is in the list as well as how many.
]]
LobbyGateStubs.evicting = {
	initial = holding.initial,
	step = function(state: any, event: any, now: number): (any, { any })
		if
			event.kind == "PlayerJoined"
			and state.phase == "Lobby"
			and not isSeated(state.players, event.playerId)
			and #state.players >= state.config.playersMax
		then
			local shuffled = copyOf(state)
			table.remove(shuffled.players, 1)
			table.insert(shuffled.players, event.playerId)
			return shuffled, {}
		end
		return holding.step(state, event, now)
	end,
}

--[[
	AC-5's control: the duplicate guard dropped, and nothing else.

	It is the baseline with the `isSeated` test removed from the join, which is
	the third mutation the story's Notes ask the orchestrator to run against the
	real machine at acceptance.
]]
LobbyGateStubs.reseating = {
	initial = holding.initial,
	step = function(state: any, event: any, now: number): (any, { any })
		if
			event.kind == "PlayerJoined"
			and state.phase == "Lobby"
			and isSeated(state.players, event.playerId)
			and #state.players < state.config.playersMax
		then
			local doubled = copyOf(state)
			table.insert(doubled.players, event.playerId)
			return doubled, {}
		end
		return holding.step(state, event, now)
	end,
}

--[[
	AC-6's control, and the whole reason AC-6 exists (Contract pin 4): removal by
	copying the LAST element over the hole and shortening.

	It is a correct SET removal - the right players are seated, and a membership
	or a length assertion cannot tell it from the baseline - and it scrambles the
	order SEAT-001 deals the ring from. Removing the last element leaves it
	indistinguishable from a real removal; removing from the middle of five does
	not, which is the shape AC-6's sequence is built to.
]]
LobbyGateStubs.swapping = {
	initial = holding.initial,
	step = function(state: any, event: any, now: number): (any, { any })
		if event.kind == "PlayerLeft" and state.phase == "Lobby" then
			local index = indexOf(state.players, event.playerId)
			if index == nil then
				return state, {}
			end
			local swapped = copyOf(state)
			local last = #swapped.players
			swapped.players[index] = swapped.players[last]
			swapped.players[last] = nil
			return swapped, {}
		end
		return holding.step(state, event, now)
	end,
}

--[[
	The purity control for the LEAVE path, which the order check cannot catch.

	It removes the right player, preserves the order of the rest, and returns a
	state whose `players` list is correct in every respect - by mutating the
	caller's array in place. Every assertion AC-6 makes about the CONTENT of the
	list passes; ROUND-003 AC-6's non-mutation check is the only thing that sees
	it.
]]
LobbyGateStubs.mutatingRemover = {
	initial = holding.initial,
	step = function(state: any, event: any, now: number): (any, { any })
		if event.kind == "PlayerLeft" and state.phase == "Lobby" then
			local index = indexOf(state.players, event.playerId)
			if index == nil then
				return state, {}
			end
			table.remove(state.players, index)
			return state, {}
		end
		return holding.step(state, event, now)
	end,
}

return LobbyGateStubs
