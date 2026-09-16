--!strict
--[[
	The negative controls for ROUND-004, and the proof that each check in
	`tests/helpers/LobbyGateContract.luau` refuses the implementation it exists to
	catch.

	AC-2 NAMES ITS CONTROL IN THE CRITERION - "an implementation that resets
	`phaseEnteredAt` on every join **must** fail this, and must pass AC-1" - and
	both halves are asserted here. The second half is the one that is easy to
	leave out and worth the most: a stub that fails EVERY check proves only that
	the checks reject something, and a control that fails everything is
	indistinguishable from a broken stub.

	The other four controls are the same discipline applied to the criteria whose
	wrong implementations the story names: a full lobby that evicts somebody to
	make room (AC-4), a join without the duplicate guard (AC-5), a removal that
	copies the last element over the hole (AC-6, Contract pin 4), and a removal
	that is correct in every visible respect and mutates the caller's array
	(ROUND-003 AC-6 on the path this story adds).

	NOTHING HERE REQUIRES PRODUCTION CODE. Unlike an ordinary RED - where the
	module under test does not exist, the real suite fails at `require` and not
	one assertion in it has executed - `src/server/round/PhaseMachine.luau` is
	merged and `tests/server/lobby_gate_test.luau` loads. These controls would
	still run if it did not, which is why the numbers they produce are
	measurements rather than claims.
]]

local Deep = require("../helpers/Deep")
local Lobby = require("../helpers/LobbyGateContract")
local Stubs = require("../helpers/LobbyGateStubs")

-- The same fixture the real suite injects. See `lobby_gate_test.luau`'s header:
-- settled numbers, read out of here and never written into an assertion.
local CONFIG = {
	lobbySeconds = 3,
	postRoundSeconds = 2,
	roundSeconds = 20,
	playersMin = 4,
	playersMax = 6,
	minPlayersToContinue = 3,
}

type Check = (any, any) -> ()

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
	The weak reading of AC-6 that `LobbyGateStubs.swapping` is built to pass: the
	right players are seated, and there are the right number of them.

	Written out here rather than described, because the whole point of the
	swapping stub is that this is green for it while the real check is red.
]]
local function weakSetRemovalCheck(machine: any, config: any)
	local state = Lobby.lobbyOf(machine, config, 5)
	local after = machine.step(state, Lobby.left("p3"), 1)

	assert(#after.players == 4, `the set check: {#after.players} seated, wanted 4`)
	local seen: { [string]: boolean } = {}
	for _, id in after.players do
		seen[id] = true
	end
	for _, id in { "p1", "p2", "p4", "p5" } do
		assert(seen[id] == true, `the set check: {id} is missing from {Deep.show(after.players)}`)
	end
	assert(seen["p3"] ~= true, `the set check: p3 is still seated`)
end

return {
	--[[ The baseline. Every control below is this lobby with exactly one thing
	     changed, so a control that fires is attributable to that one thing. ]]

	["baseline: a lobby that holds, caps, refuses duplicates and removes in place order passes every ROUND-004 check"] = function()
		accepts(Lobby.lobbyHoldsBelowMinimum, Stubs.holding, "AC-1 on the holding lobby")
		accepts(
			Lobby.roundStartsOnTheTickAfterReachingMinimum,
			Stubs.holding,
			"AC-2 on the holding lobby"
		)
		accepts(
			Lobby.lobbyHoldsWhenTheCountFallsAndStartsWhenRestored,
			Stubs.holding,
			"AC-3 on the holding lobby"
		)
		accepts(Lobby.fullLobbyRefusesTheSurplusJoin, Stubs.holding, "AC-4 on the holding lobby")
		accepts(Lobby.duplicateJoinSeatsOnce, Stubs.holding, "AC-5 on the holding lobby")
		accepts(Lobby.removalPreservesJoinOrder, Stubs.holding, "AC-6 on the holding lobby")
		accepts(
			Lobby.leaveDoesNotMutateItsInput,
			Stubs.holding,
			"the non-mutation check on the holding lobby's leave path"
		)
	end,

	--[[
		AC-2's control, named in the criterion itself.

		Both halves. It PASSES AC-1, because it still gates on the count - that is
		what stops it being a stub that fails everything - and it FAILS AC-2,
		because the elapsed lobby time is discarded by the join that completes the
		count. It also passes AC-4, AC-5 and AC-6, so the failure is attributable
		to the one line that differs.
	]]
	["AC-2 control: a lobby that restamps phaseEnteredAt on every join passes AC-1 and fails AC-2"] = function()
		accepts(
			Lobby.lobbyHoldsBelowMinimum,
			Stubs.resetting,
			"a resetting lobby still holds below players_min, so it passes AC-1"
		)
		accepts(Lobby.fullLobbyRefusesTheSurplusJoin, Stubs.resetting, "AC-4 on a resetting lobby")
		accepts(Lobby.duplicateJoinSeatsOnce, Stubs.resetting, "AC-5 on a resetting lobby")
		accepts(Lobby.removalPreservesJoinOrder, Stubs.resetting, "AC-6 on a resetting lobby")

		local message = refuses(
			Lobby.roundStartsOnTheTickAfterReachingMinimum,
			Stubs.resetting,
			"a lobby that resets phaseEnteredAt on every join must fail AC-2"
		)
		names(message, "AC-2", "the AC-2 control fires")
	end,

	--[[
		The half of AC-2 that a weaker test would miss, made explicit: the
		resetting lobby DOES start a round. It starts it one full lobbySeconds
		after the join instead of on the next tick, so a test asserting only "it
		eventually starts" is green for it.
	]]
	["AC-2 control: the resetting lobby does start a round eventually, which is why AC-2 asserts the now"] = function()
		local machine = Stubs.resetting
		local state = Lobby.lobbyOf(machine, CONFIG, CONFIG.playersMin - 1)
		local joinAt = CONFIG.lobbySeconds * 3

		local afterJoin = machine.step(state, Lobby.joined(`p{CONFIG.playersMin}`), joinAt)
		assert(
			afterJoin.phaseEnteredAt == joinAt,
			`the resetting stub did not reset: phaseEnteredAt is `
				.. `{tostring(afterJoin.phaseEnteredAt)}, wanted {joinAt}`
		)

		local soon = machine.step(afterJoin, Lobby.tick(), joinAt + CONFIG.lobbySeconds / 4)
		assert(
			soon.phase == "Lobby",
			`the resetting stub started the round on the next tick; it is supposed to make the `
				.. `lobby serve another lobbySeconds`
		)

		local eventually = machine.step(afterJoin, Lobby.tick(), joinAt + CONFIG.lobbySeconds)
		assert(
			eventually.phase == "Assignment",
			`the resetting stub never starts a round at all ({tostring(eventually.phase)} a `
				.. `full lobbySeconds after the join), which would make it a stub that fails `
				.. `everything rather than the control AC-2 names`
		)
	end,

	--[[
		AC-4's control: a full lobby that makes room instead of refusing.

		The trap is asserted first - the evicting lobby really is exactly
		players_max long afterwards, so a length check alone is green for it - and
		then the real check is watched refusing it.
	]]
	["AC-4 control: a lobby that evicts a seated player to make room passes AC-1 and a length check, and fails AC-4"] = function()
		accepts(
			Lobby.lobbyHoldsBelowMinimum,
			Stubs.evicting,
			"an evicting lobby still holds below players_min, so it passes AC-1"
		)
		accepts(
			Lobby.roundStartsOnTheTickAfterReachingMinimum,
			Stubs.evicting,
			"AC-2 on an evicting lobby"
		)

		local full = Lobby.lobbyOf(Stubs.evicting, CONFIG, CONFIG.playersMax)
		local after = Stubs.evicting.step(full, Lobby.joined(`p{CONFIG.playersMax + 1}`), 1)
		assert(
			#after.players == CONFIG.playersMax,
			`the evicting stub left {#after.players} seated, not playersMax `
				.. `({CONFIG.playersMax}); a length check must be GREEN for it or it is not the `
				.. `control AC-4 needs`
		)

		local message = refuses(
			Lobby.fullLobbyRefusesTheSurplusJoin,
			Stubs.evicting,
			"a lobby that evicts somebody to seat the surplus player must fail AC-4"
		)
		names(message, "AC-4", "the AC-4 control fires")
	end,

	--[[ AC-5's control: the duplicate guard dropped, and nothing else. ]]

	["AC-5 control: a lobby that appends on a duplicate join passes AC-1 and fails AC-5"] = function()
		accepts(
			Lobby.lobbyHoldsBelowMinimum,
			Stubs.reseating,
			"a reseating lobby still holds below players_min, so it passes AC-1"
		)
		accepts(Lobby.removalPreservesJoinOrder, Stubs.reseating, "AC-6 on a reseating lobby")

		local message = refuses(
			Lobby.duplicateJoinSeatsOnce,
			Stubs.reseating,
			"a lobby that appends on a duplicate join must fail AC-5"
		)
		names(message, "AC-5", "the AC-5 control fires")
	end,

	--[[
		AC-6's control, and the reason AC-6 exists at all (Contract pin 4).

		Removal by copying the last element over the hole is a CORRECT SET
		REMOVAL: the weak check below is green for it, and so are AC-1, AC-2 and
		AC-4. Only relative order sees it, and only because the sequence removes
		from the middle of five - `removalPreservesJoinOrder` says so in its own
		comment, and this is where that claim is measured.
	]]
	["AC-6 control: a lobby that removes by swapping the last element over the hole passes a set check and fails AC-6"] = function()
		accepts(Lobby.lobbyHoldsBelowMinimum, Stubs.swapping, "AC-1 on a swapping lobby")
		accepts(
			Lobby.roundStartsOnTheTickAfterReachingMinimum,
			Stubs.swapping,
			"AC-2 on a swapping lobby"
		)
		accepts(Lobby.fullLobbyRefusesTheSurplusJoin, Stubs.swapping, "AC-4 on a swapping lobby")
		accepts(
			weakSetRemovalCheck,
			Stubs.swapping,
			"a swap-with-the-last removal seats exactly the right set of players"
		)

		local message = refuses(
			Lobby.removalPreservesJoinOrder,
			Stubs.swapping,
			"a removal that copies the last element over the hole must fail AC-6"
		)
		names(message, "AC-6", "the AC-6 control fires")
	end,

	--[[
		The purity control for the leave path.

		It removes the right player and preserves the order of the rest, so every
		assertion AC-6 makes about the CONTENT of the list is green - including
		the subsequence one. ROUND-003 AC-6's non-mutation check is the only thing
		that sees it, and that is the defect rules.md calls the one violated first
		and noticed last.
	]]
	["purity control: a lobby that unseats by mutating the caller's array passes AC-6 and fails the non-mutation check"] = function()
		accepts(
			Lobby.removalPreservesJoinOrder,
			Stubs.mutatingRemover,
			"an in-place removal still produces the right list in the right order"
		)

		local message = refuses(
			Lobby.leaveDoesNotMutateItsInput,
			Stubs.mutatingRemover,
			"a PlayerLeft that removes the player from the caller's own array must fail the "
				.. "non-mutation check"
		)
		names(message, "AC-6", "the purity control fires with ROUND-003 AC-6's message")
		names(message, "players", "the purity control names the field that was mutated")
	end,
}
