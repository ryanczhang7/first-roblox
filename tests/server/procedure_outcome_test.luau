--!strict
--[[
	PROC-003: instability shortens the clock, darkens rooms and ends the round
	in a fixed order. AC-1 through AC-8, applied to the real
	`src/server/procedure/Procedure.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `procedure_test.luau` and `procedure_finale_test.luau` do.
	In this story's RED the module LOADS - PROC-001 and PROC-002 wrote it - but
	has no `deadline`, `isDark`, `blackoutWeights` or `drawRoom`, ignores the
	two new `start` arguments, charges no clock, darkens nothing and produces
	no outcome. So every test below fails on its own assertion rather than at
	import: the tests that read a new export fail on a `need()` guard naming
	it (`I-2: Procedure.deadline is nil, expected a function`), and the tests
	that use only PROC-001/002's exports fail on the first thing the module
	does not do (an outcome that stays nil, a turn on a decided round that is
	evaluated instead of refused). Per-criterion failures say which behaviours
	are missing, which is what GREEN needs.

	THE CHECKS AND THE FIXTURES LIVE IN `tests/helpers/OutcomeContract.luau`,
	reusing `TurnContract`'s facility (plus a hand-built three-room one for
	AC-3 and AC-4), and are exercised against a reference stand-in and
	deliberately wrong stand-ins in
	`tests/server/procedure_outcome_controls_test.luau`. That file is where
	each check is OBSERVED to fire and to accept, and where every negative
	control's value is measured.

	THE ORACLE PARTITION (story `## Contract`): AC-1, AC-2, AC-4, AC-6..AC-8
	and AC-3's first clause are settled by `mechanics.md` §5 and I-1..I-10;
	each test is named after the rule it pins and reads every number out of
	`MechanicsTuning` or `Tuning`. AC-3's second clause is oracle-free (a
	frequency with a uniform draw as its control). AC-5 and the export shape
	are mechanical.

	WHAT THIS FILE DOES NOT PIN: how the stream of I-1 is advanced internally
	(only that the k-th draw equals the k-th `nextInteger` of an independent
	`Rng.fromSeed(seed):derive("blackout")`), how `blackoutWeights` walks the
	placement, whether `dark` is stored as `{ [room] = true }` only or also
	carries explicit `false`s (`isDark` and `darkRooms` read `== true`), the
	text of any error, what `dial` answers in a dark room, and any field a
	later story adds.
]]

local Deep = require("../helpers/Deep")
local Outcome = require("../helpers/OutcomeContract")

local loaded, loadResult = pcall(require, "../../src/server/procedure/Procedure")

local function Procedure(): any
	assert(loaded, `src/server/procedure/Procedure.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Procedure exports deadline, isDark, blackoutWeights and drawRoom as plain field functions, alongside PROC-001/002's seven"] = function()
		local P = Procedure()
		local missing: { string } = {}
		for _, name in
			{
				"start",
				"isLive",
				"dial",
				"turn",
				"tick",
				"partnerLamps",
				"isComplete",
				"deadline",
				"isDark",
				"blackoutWeights",
				"drawRoom",
			}
		do
			if typeof(P[name]) ~= "function" then
				table.insert(missing, `Procedure.{name} is {typeof(P[name])}`)
			end
		end
		assert(
			#missing == 0,
			`the Contract's exports are not all functions: {table.concat(missing, ", ")}`
		)
	end,

	["Contract/I-1/I-2: start(facility, now, tuning, roundSeed, roundSeconds) carries startedAt, roundSeconds, penaltySeconds 0, dark {}, outcome nil, roundSeed and blackoutDraws 0; deadline is startedAt + roundSeconds; no room is dark; blackoutWeights is { 7, 7, 4, 2 }; tick at start returns the state and nil"] = function()
		Outcome.startCarriesTheRoundFieldsAndTheNewExportsAnswerInShape(Procedure())
	end,

	["Contract: start stores the roundSeed and roundSeconds it was handed, not constants - two starts with different values differ in exactly those fields and in deadline"] = function()
		local P = Procedure()
		local w = Outcome.world()
		local a = P.start(w.facility, Outcome.NOW, w.tuning, 11, 300)
		local b = P.start(w.facility, Outcome.NOW, w.tuning, 12, 400)
		assert(
			a.roundSeed == 11 and b.roundSeed == 12,
			`roundSeed is {Deep.show(a.roundSeed)} / {Deep.show(b.roundSeed)}, expected 11 / 12`
		)
		assert(
			a.roundSeconds == 300 and b.roundSeconds == 400,
			`roundSeconds is {Deep.show(a.roundSeconds)} / {Deep.show(b.roundSeconds)}, expected 300 / 400`
		)
		assert(
			typeof(P.deadline) == "function",
			`Procedure.deadline is {typeof(P.deadline)}, expected a function`
		)
		assert(
			P.deadline(a) == Outcome.NOW + 300 and P.deadline(b) == Outcome.NOW + 400,
			`deadline is {Deep.show(P.deadline(a))} / {Deep.show(P.deadline(b))}, expected {Outcome.NOW + 300} / {Outcome.NOW + 400}`
		)
	end,

	--[[ AC-1 ]]

	["AC-1/I-3: deadline is startedAt + roundSeconds minus instability_clock_penalty_seconds (the fixture's 7, not 20) per point, charged by a wrong setting, a not_live decoy (2 points at once) and an expired finale window alike; penaltySeconds carries the sum"] = function()
		Outcome.deadlineIsStartPlusRoundSecondsLessThePenaltyPerPoint(Procedure())
	end,

	["AC-1 under the SHIPPED tuning: with round_seconds 420 the deadline is t0 + 420, then 500 after one point and 480 after two (tuning.md: 20 s per point)"] = function()
		Outcome.underTheShippedTuningTheDeadlineReadsLiterally(Procedure())
	end,

	--[[ AC-2 ]]

	["AC-2: rising to 1 and to 2 (threshold 3) darkens nothing and draws nothing"] = function()
		Outcome.risingToJustBelowTheThresholdDarkensNothing(Procedure())
	end,

	['AC-2/I-5: rising from 2 to 3 darkens EXACTLY blackout_rooms_per_threshold (2) rooms - the two drawRoom(blackoutWeights(s), stream) returns on an independent Rng.fromSeed(seed):derive("blackout") stream, the first removed before the second draw - and records two draws; a dark room is no longer a key of blackoutWeights'] = function()
		Outcome.crossingTheThresholdDarkensExactlyRoomsPerThresholdByTheWeightedDraw(Procedure())
	end,

	["AC-2/I-4: a 2-point charge from 2 to 4 skips the value 3 but still crosses it once (two rooms dark), and 4 -> 5 darkens nothing more"] = function()
		Outcome.aChargeThatJumpsOverTheMultipleStillCrossesIt(Procedure())
	end,

	["AC-2/AC-6: reaching instability_max (6, a multiple of threshold 3) is lost / instability with no blackout at the max - still two rooms dark, still two draws - and the turn itself is the ordinary rejection"] = function()
		Outcome.reachingInstabilityMaxEndsTheRoundWithoutAnotherBlackout(Procedure())
	end,

	--[[ AC-3 ]]

	["AC-3: with every uncommitted step in one lit room and the other lit rooms at weight 0 (decoys, a committed step), the crossing darkens that room on every one of 40 seeds"] = function()
		Outcome.oneLitRoomHoldingEveryUncommittedStepIsAlwaysTheOneDarkened(Procedure())
	end,

	['AC-3 (oracle-free): over 20,000 draws of drawRoom({ [4] = 3, [7] = 1 }) on one "blackout" stream, room 4 is drawn with frequency 0.75 +/- 0.02'] = function()
		Outcome.theHeavierOfTwoRoomsIsDrawnThreeTimesInFour(Procedure())
	end,

	["AC-3/I-5: drawRoom is exactly one nextInteger(1, W) mapped to the first room in ascending id whose cumulative weight reaches it (zero-weight rooms skipped), nextInteger(1, #rooms) when every weight is 0, nil with no draw for no rooms, and never mutates its weights"] = function()
		Outcome.drawRoomMapsTheDrawToTheFirstRoomWhoseCumulativeWeightReachesIt(Procedure())
	end,

	--[[ AC-4 ]]

	["AC-4/I-4: with every lit room at weight 0 a crossing still darkens one lit room (uniform, as drawRoom predicts); with every room dark a crossing darkens nothing, draws nothing and raises nothing; a dark room is never drawn again"] = function()
		Outcome.everyLitRoomAtWeightZeroStillDarkensOneAndNoneLitDoesNothing(Procedure())
	end,

	--[[ AC-5 ]]

	['AC-5/I-1: one seed replays four crossings as the same four rooms in the same order, and that order is what drawRoom predicts on an independent "blackout" stream - for two seeds'] = function()
		Outcome.theSameSeedReplaysTheSameRoomsInTheSameOrder(Procedure())
	end,

	['AC-5: Generator.generate with seed s deep-equals itself before and after a Procedure on roundSeed s drew four blackouts, and the "instance" stream of s is untouched'] = function()
		Outcome.drawingFromTheBlackoutStreamMovesNoGeneratorDraw(Procedure())
	end,

	--[[ AC-6 ]]

	["AC-6: the last finale commit at deadline - 0.001 is won / procedure_complete on the state and on every later tick; the same turn at exactly the deadline is refused / round_over on a state that is lost / clock with nothing committed and no log entry"] = function()
		Outcome.theLastFinaleCommitBeforeTheDeadlineWinsAndAtTheDeadlineItIsRoundOver(Procedure())
	end,

	["AC-6/I-6: a wrong turn that reaches instability_max AND whose penalty takes the clock to exactly 0, or below it, records lost / instability - never lost / clock"] = function()
		Outcome.instabilityMaxAndTheClockInOneTurnRecordInstability(Procedure())
	end,

	["AC-6/I-3/I-8: tick at deadline - 0.001 changes nothing; at exactly the deadline it is lost / clock, as tick's second value and as state.outcome, with nothing else changed; after a penalty the instant moves with the deadline; a turn arriving at the deadline is refused / round_over on that lost / clock state"] = function()
		Outcome.theDeadlinePassingByTimeAloneIsLostClockAtExactlyTheDeadline(Procedure())
	end,

	["AC-6 under the SHIPPED tuning: five wrong turns lose by instability (max 5) with the clock at 320 s, one room dark after the second and a second after the fourth, none added at the fifth"] = function()
		Outcome.underTheShippedTuningFiveWrongTurnsLoseByInstabilityWithTwoRoomsDark(Procedure())
	end,

	["I-6 step 2: an expired finale window charges through the clock (7 s), crosses the threshold (two rooms dark, via tick) and at the max ends the round - tick's second value and state.outcome both lost / instability"] = function()
		Outcome.tickExpiryChargesTheClockCrossesTheThresholdAndCanEndTheRound(Procedure())
	end,

	--[[ AC-7 ]]

	["AC-7/I-7: once won, lost / instability or lost / clock, every later turn - wrong, correct, decoy, finale, unknown id, non-holder - is refused / round_over on a deep-equal state, and every later tick returns the same outcome and the same state"] = function()
		Outcome.aDecidedRoundStaysDecided(Procedure())
	end,

	--[[ AC-8 ]]

	["AC-8/I-9: a dark room reads isDark true through commits, a tick, arming, completing and the win; lit rooms and an unknown room id read false; the dark set never shrinks"] = function()
		Outcome.isDarkIsTrueForTheRestOfTheRound(Procedure())
	end,

	--[[ I-10 ]]

	["I-10: deadline, isDark, blackoutWeights, drawRoom's weights, a crossing turn, a clock-ending tick and a round_over turn leave their arguments deep-equal, and a crossing downstream does not reach back into an earlier state"] = function()
		Outcome.noOutcomeCallMutatesItsArguments(Procedure())
	end,
}
