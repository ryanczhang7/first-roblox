--!strict
--[[
	VIEW-004: the plausibility rule wired into `Session.step`. AC-2 through
	AC-5 as the Session shows them, and the Contract's `Session` semantics -
	`tracks`, the merge, fresh copies, the walk speed from `state.tuning` -
	applied to the real `src/server/session/Session.luau` with the real
	`src/server/session/Positions.luau` read for its constants.

	Both modules are required through a `pcall` at the top and re-checked
	inside every test. In RED `Positions.luau` does not exist, so every test
	below fails at that check, naming the missing module - a counted failure
	per criterion rather than one LOAD FAIL. Were the module present and the
	Session unchanged, every test would still fail on its own assertion:
	today's Session stores every sample unfiltered, carries no `tracks`, and
	never emits a resync `Placed`.

	THE CHECKS LIVE IN `tests/helpers/PositionsContract.luau` (SESSION_CHECKS)
	and are exercised against the reference stand-in session and one-defect
	stand-ins in `tests/server/positions_controls_test.luau`, where each is
	OBSERVED to fire. The scripted rounds that WALK (SLICE-005's AC-4..AC-6,
	rewritten by VIEW-004 PO-3) stay in `session_round_test.luau`; what earns
	them is VIEW-004 D-4, in GATES.

	THE ORACLE PARTITION (story `## Contract`): mechanical. Constants are read
	from `Positions`; the walk speed from the tuning in use; the implausible
	jump is a literal the check first shows to be outside the bound it reads.

	WHAT THIS FILE DOES NOT PIN: whether `tracks[p]` exists (as `{ refusals =
	0 }`) or is nil for a player sampled with no baseline; the internal
	order in which `Session.step` offers a batch; the text of any error.
]]

local Contract = require("../helpers/PositionsContract")

local sessionLoaded, sessionResult = pcall(require, "../../src/server/session/Session")
local positionsLoaded, positionsResult = pcall(require, "../../src/server/session/Positions")

local function Session(): any
	assert(sessionLoaded, `src/server/session/Session.luau did not load: {tostring(sessionResult)}`)
	return sessionResult
end

local function Positions(): any
	assert(
		positionsLoaded,
		`src/server/session/Positions.luau did not load: {tostring(positionsResult)} - VIEW-004's Contract exports `
			.. `TOLERANCE, SLACK_STUDS and RESYNC_SECONDS, which these Session-level checks read`
	)
	return positionsResult
end

return {
	--[[ AC-2 ]]

	["AC-2: the deal's placement is the baseline - everyone sampled at the spawn centre 0.1 s after the deal is accepted (tracks moved, nothing emitted), a far jump right after is refused (positions kept, one refusal, the run started), and the same jump in a Lobby with no deal is not stored"] = function()
		Contract.dealPlacementIsTheBaseline(Session(), Positions())
	end,

	--[[ AC-3 ]]

	["AC-3: a player with no accepted sample is absent from state.positions - a sample AT a machine is not stored and not a refusal, and their turn on it is refused out_of_reach"] = function()
		Contract.unplacedPlayerIsAbsentAndOutOfReach(Session(), Positions())
	end,

	--[[ AC-4 ]]

	["AC-4: in Round, refused continuously for longer than RESYNC_SECONDS, the next sample emits exactly one Placed { playerId, position = last accepted } per such player (ascending playerId, fresh tables, nothing else) and resets the baseline there; at exactly RESYNC_SECONDS nothing is placed; in the next Lobby nothing is placed however long the run"] = function()
		Contract.resyncPlacesBackInRoundOnly(Session(), Positions())
	end,

	--[[ AC-5 ]]

	["AC-5: the turner of T1[1], last accepted at the spawn centre, sends an implausible sample AT the machine; their turn is refused out_of_reach and state.positions still holds the centre - and after walking there at walk speed the same turn commits"] = function()
		Contract.implausibleSampleDoesNotReachATurn(Session(), Positions())
	end,

	--[[ Contract: tracks, the merge, fresh copies, the tuning ]]

	["Contract: state.tracks is {} from new; the deal replaces it with exactly the dealt players placed at the centre at the deal's now with their refusal counts carried - a leaver absent, a newcomer at 0 - and positions is exactly the centre for them"] = function()
		Contract.tracksFromNewAndTheDeal(Session(), Positions())
	end,

	["Contract: a PositionsSampled naming one player merges - that player moves, every other accepted position and track is untouched - into fresh copies, and mutates neither state nor event"] = function()
		Contract.samplesMergeIntoFreshAcceptedCopies(Session(), Positions())
	end,

	["Contract: the walk speed is state.tuning.instance.walk_speed_studs_per_second - under a tuning ten times faster a jump just past the shipped bound is accepted; under the shipped tuning it is refused"] = function()
		Contract.walkSpeedIsReadFromTheSessionsTuning(Session(), Positions())
	end,
}
