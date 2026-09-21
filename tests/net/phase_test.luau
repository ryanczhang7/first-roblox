--!strict
--[[
	NET-002: phase legality, position 4 of the fixed check order. AC-1 through
	AC-6 applied to the real `src/net/Wrapper.luau` and `src/net/Remotes.luau`,
	driving the real `Schema` - the level at which the contract between the
	three lives, so the level at which the out-of-phase cases are asserted.

	THE MODULES EXIST ON ARRIVAL, unlike NET-001's RED: `src/net/` was built
	by NET-001 and declares `legalPhases` without reading it. So the tests
	below LOAD and RUN, and the ones that fail do so on their own assertion -
	"a valid call while the phase is Lobby -> ACCEPTED (returned nil)" - not
	on a missing import. The two that pass on arrival (AC-1, and nothing
	else among the criteria) are earned by the controls suite: a wrapper that
	rejects every phase fails AC-1 there and nowhere else among the positive
	checks.

	THE CHECKS LIVE IN `tests/helpers/PhaseContract.luau`, and every one of
	them has been OBSERVED to fire in `tests/net/phase_controls_test.luau`
	against the bundle it exists to catch - including the two the criteria
	name: AC-4 against a wrapper comparing only the first entry of
	`legalPhases`, AC-6 against one that captures the phase when the remote is
	guarded.

	NO ROBLOX, NO `Players`, NO ROUND. `GuardContext` is injected;
	`PhaseContract.world` builds one whose phase is a mutable field. Nothing
	here requires a module from `src/server/`: `architecture.md` section 1
	forbids `net` -> `server`, and the phase the tests supply is a string.
]]

local Contract = require("../helpers/PhaseContract")

local schemaLoaded, schemaResult = pcall(require, "../../src/net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/net/Remotes")
local wrapperLoaded, wrapperResult = pcall(require, "../../src/net/Wrapper")

local function net(): Contract.Net
	assert(schemaLoaded, `src/net/Schema.luau did not load: {tostring(schemaResult)}`)
	assert(remotesLoaded, `src/net/Remotes.luau did not load: {tostring(remotesResult)}`)
	assert(wrapperLoaded, `src/net/Wrapper.luau did not load: {tostring(wrapperResult)}`)
	return { Schema = schemaResult, Remotes = remotesResult, Wrapper = wrapperResult }
end

return {
	--[[ AC-1 ]]

	["AC-1: a remote legal only in Round, called by a seated player with valid arguments while the phase is Round, runs the handler once with those arguments"] = function()
		Contract.handlerRunsInTheOnlyLegalPhase(net())
	end,

	--[[ AC-2 ]]

	["AC-2: the same remote called while the phase is Lobby, Assignment, Resolution or Post is rejected for phase in every case, with a non-empty detail, and the handler never runs"] = function()
		Contract.outOfPhaseCallIsRejectedForPhase(net())
	end,

	--[[ AC-3 ]]

	["AC-3: out of phase, an unseated caller is identity, a malformed payload is shape, an out-of-range one is range, and only a payload that passed all three is phase - the schema is consulted exactly once before a phase rejection"] = function()
		Contract.earlierChecksWinOverPhase(net())
	end,

	--[[ AC-4 ]]

	["AC-4: a remote legal in Lobby, Round and Post runs in each of them and is rejected for phase in Assignment and Resolution - an implementation comparing one entry of legalPhases fails here"] = function()
		Contract.multiPhaseRemoteRunsInEachLegalPhaseAndNowhereElse(net())
	end,

	--[[ AC-5 ]]

	["AC-5: declaring a remote with an empty legalPhases fails naming the remote and the field, the registry does not grow, and the name is still free to declare with one legal phase"] = function()
		Contract.emptyLegalPhasesIsADeclarationError(net())
	end,

	--[[ AC-6 ]]

	["AC-6: a remote guarded once while the phase is Lobby is rejected in Lobby and Post and accepted in Round as the world moves, and one guarded in Round is rejected once the phase moves to Assignment - the phase is read at the moment of each call"] = function()
		Contract.phaseIsReadAtTheMomentOfEachCall(net())
	end,

	--[[ The Contract's own promises ]]

	["Contract: a phase rejection's detail names the current phase and every legal phase, names no other phase, and does not lead with a phase: prefix"] = function()
		Contract.phaseRejectionDetailNamesTheCurrentAndEveryLegalPhase(net())
	end,

	["Contract: context.phase() is not consulted when identity, shape or range has already fired, and is consulted for a call that reaches the phase check"] = function()
		Contract.phaseIsNotConsultedWhenAnEarlierCheckFails(net())
	end,
}
