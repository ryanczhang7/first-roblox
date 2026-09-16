--!strict
--[[
	ROUND-004: the lobby holds below players_min and admits no more than
	players_max. AC-1 through AC-6, applied to the real machine.

	THIS IS NOT AN ORDINARY RED. `ROUND-003` is merged, its 137 tests are frozen
	and green, and `src/server/round/PhaseMachine.luau` already exists and already
	works - so this file LOADS, every assertion in it RUNS, and the failures below
	are real assertion failures rather than one import error wearing eight
	criteria. Two consequences follow and both are recorded in the story:

	  * a handful of assertions here are GREEN ON ARRIVAL, because the machine
	    already does that part (a duplicate join is already refused;
	    `phaseEnteredAt` is already never rewritten by a join, because a join does
	    not touch it). A test that has never been observed to fail is not a test,
	    so each one is earned by a reverted `scripts/mutate.sh` probe of the
	    specific production behaviour it claims to pin, pasted into the story's
	    `## Regressions`.
	  * the negative controls in `tests/server/lobby_gate_controls_test.luau` run
	    for real in RED rather than being promised for GREEN, because they need no
	    production code at all.

	THE CONFIG IS INJECTED AND TINY, and it is deliberately the SAME fixture
	`tests/server/phase_machine_test.luau` uses: a whole lobby runs in simulated
	seconds, and a machine reaching for `Tuning` instead of the config it was
	handed fails rather than merely running slowly.

	THE NUMBERS ARE SETTLED AND NOTHING HERE CALIBRATES ONE. `players_min` 4 and
	`players_max` 6 are derived and ratified (`docs/wiki/game/tuning.md` section
	1, product-brief section 0c R1). `players_max` is SOFT - playtest P-N may move
	it - so no assertion below writes 4 or 6: the thresholds are read out of
	`CONFIG`, through the checks in `tests/helpers/LobbyGateContract.luau`, and
	these tests should still pass unchanged the day `tuning.md` moves the number.
]]

local Contract = require("../helpers/PhaseMachineContract")
local Deep = require("../helpers/Deep")
local Lobby = require("../helpers/LobbyGateContract")
local PhaseMachine = require("../../src/server/round/PhaseMachine")

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

local function outcome(): any
	return { result = "no_contest", reason = "reason-b9k2-set-by-the-caller-not-the-machine" }
end

--[[
	One state per phase past the Lobby, reached by driving the machine.

	The lobby is seated with exactly `playersMin` players, so this journey is
	valid both before this story lands - when the machine ignores the count
	entirely - and after it, when the count is what lets the round start. A
	journey that needed a different lobby on either side of GREEN would be
	testing the fixture.
]]
local function journeyPastTheLobby(): { [string]: any }
	local lobby = Lobby.lobbyOf(Machine, CONFIG, CONFIG.playersMin)
	local assignment = Machine.step(lobby, Lobby.tick(), CONFIG.lobbySeconds * 1.5)
	local round = Machine.step(assignment, { kind = "SeatsAssigned" }, 5)
	local resolution = Machine.step(round, { kind = "RoundResolved", outcome = outcome() }, 6)
	local post = Machine.step(resolution, Lobby.tick(), 6)

	local reached = {
		Assignment = assignment,
		Round = round,
		Resolution = resolution,
		Post = post,
	}
	for phase, state in reached do
		assert(
			typeof(state) == "table" and state.phase == phase,
			`fixture: driving the machine to {phase} produced {Deep.show(state)}`
		)
	end
	return reached
end

return {
	--[[ AC-1. The lobby holds below the minimum, and the empty case is the same
	     criterion at zero. ]]

	["AC-1: a lobby one short of players_min stays in Lobby however far the clock runs"] = function()
		Lobby.lobbyHoldsBelowMinimum(Machine, CONFIG)
	end,

	["AC-1: an empty lobby is still in Lobby well past lobbySeconds and has emitted nothing"] = function()
		local empty = Machine.initial(CONFIG, Lobby.SEED, Lobby.ROUND_ID)
		local wellPast = CONFIG.lobbySeconds * 5
		local after, effects = Machine.step(empty, Lobby.tick(), wellPast)
		assert(
			after.phase == "Lobby",
			`AC-1: a lobby seating nobody is in {tostring(after.phase)} at now = {wellPast}, `
				.. `with lobbySeconds = {CONFIG.lobbySeconds} and playersMin = `
				.. `{CONFIG.playersMin}`
		)
		assert(
			#effects == 0,
			`AC-1: an empty lobby emitted {Deep.show(Deep.kinds(effects))} at now = {wellPast}; `
				.. `an AssignSeats here would hand the driver a ring of nobody`
		)
	end,

	--[[ AC-2. The hold, and the one criterion a wrong implementation passes half
	     of. The `now` at which the round starts is asserted, not merely that it
	     starts - see LobbyGateContract, and LobbyGateStubs.resetting, which is
	     the implementation the criterion names. ]]

	["AC-2: reaching players_min starts the round on the next tick, without serving another lobbySeconds"] = function()
		Lobby.roundStartsOnTheTickAfterReachingMinimum(Machine, CONFIG)
	end,

	--[[
		The same property stated directly on the field, because the hold is one
		line and this is that line.

		GREEN ON ARRIVAL: today's machine never touches `phaseEnteredAt` on a
		join, because a join is the only event it handles that builds a state
		without entering a phase. Earned by the first probe in the story's
		`## Regressions` - `seated.phaseEnteredAt = now` inserted into the
		PlayerJoined branch, which is mutation 1 of the story's `## Notes`.
	]]
	["AC-2: a PlayerJoined never rewrites phaseEnteredAt, whatever the now"] = function()
		local state = Machine.initial(CONFIG, Lobby.SEED, Lobby.ROUND_ID)
		local enteredAt = state.phaseEnteredAt
		local joinTimes = { 0, 7, 11.5, CONFIG.lobbySeconds * 9 }

		for index, now in joinTimes do
			local id = `p{index}`
			state = Machine.step(state, Lobby.joined(id), now)
			assert(
				#state.players == index,
				`AC-2: joining {id} at now = {now} left {Deep.show(state.players)} seated`
			)
			assert(
				state.phaseEnteredAt == enteredAt,
				`AC-2: seating {id} at now = {now} moved phaseEnteredAt from {enteredAt} to `
					.. `{tostring(state.phaseEnteredAt)}. The lobby timer HOLDS: the elapsed `
					.. `lobby time already served is never discarded by a join, or a lobby that `
					.. `gains and loses a player every thirty seconds never starts (M6)`
			)
		end
	end,

	--[[ AC-3. A departure below the minimum holds the lobby; restoring the count
	     starts the round on the next tick, and the restored lobby does not serve
	     another lobbySeconds either. ]]

	["AC-3: a departure below players_min holds the lobby, and restoring the count starts the round on the next tick"] = function()
		Lobby.lobbyHoldsWhenTheCountFallsAndStartsWhenRestored(Machine, CONFIG)
	end,

	--[[ AC-4. The cap, asserted as who is seated and not only how many. ]]

	["AC-4: a join into a lobby holding players_max leaves exactly players_max seated and the surplus player unseated"] = function()
		Lobby.fullLobbyRefusesTheSurplusJoin(Machine, CONFIG)
	end,

	--[[ AC-5. Mechanical, and green on arrival - see the story's
	     `## Regressions` for the probe that earns it. ]]

	["AC-5: the same PlayerJoined applied twice seats that player once, in a lobby at neither threshold"] = function()
		Lobby.duplicateJoinSeatsOnce(Machine, CONFIG)
	end,

	--[[ AC-6. Removal is a removal, not a swap. ]]

	["AC-6: joins and leaves in any order leave the seated list a subsequence of the join order"] = function()
		Lobby.removalPreservesJoinOrder(Machine, CONFIG)
	end,

	["AC-3/AC-6: a PlayerLeft that unseats a player does not mutate the state it was given"] = function()
		Lobby.leaveDoesNotMutateItsInput(Machine, CONFIG)
	end,

	--[[
		Contract pin 2, and a non-goal pinned because it is cheap: `PlayerLeft`
		unseats in the Lobby and NOWHERE ELSE. What a mid-round departure means
		is ROUND-005's story - it is the one that needs the count against
		`min_players_to_continue` - and unseating here would silently change the
		seated list AFTER `AssignSeats` has already carried it, which is the ring
		SEAT-001 deals.

		GREEN ON ARRIVAL: today `PlayerLeft` is ignored in every phase including
		the Lobby, so this passes for the wrong reason. Earned by the fourth
		probe in the story's `## Regressions`, which gives the machine an
		unconditional unseating `PlayerLeft` branch and watches this go red while
		the Lobby tests stay red for their own reasons.
	]]
	["Contract pin 2: a PlayerLeft outside the Lobby is ignored - a mid-round departure is ROUND-005"] = function()
		local reached = journeyPastTheLobby()
		local offending: { string } = {}
		local first = ""

		for phase, state in reached do
			local ok, err = pcall(Contract.eventIsIgnored, Machine, {
				label = `a PlayerLeft naming the seated player p2, in {phase}`,
				state = state,
				event = Lobby.left("p2"),
				now = 7,
			})
			if not ok then
				table.insert(offending, phase)
				if first == "" then
					first = tostring(err)
				end
			end
		end
		table.sort(offending)

		--[[
			The phases are named in the headline and only the FIRST violation is
			quoted, because Luau truncates an assert message at roughly 500
			characters and four quoted violations take the headline with them.
			Measured on this suite in RED; see the story's `## Handoff`.
		]]
		assert(
			#offending == 0,
			`Contract pin 2: a PlayerLeft was acted on in {#offending} phase(s) past the Lobby `
				.. `({table.concat(offending, ", ")}). ROUND-004 unseats in the LOBBY and nowhere `
				.. `else; a mid-round departure is ROUND-005's. The first:\n{first}`
		)
	end,
}
