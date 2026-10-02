--!strict
--[[
	PROC-003 AC-1 through AC-8 written once, as checks over a PROCEDURE MODULE
	rather than over `src/server/procedure/Procedure.luau` by name - the same
	arrangement as `TurnContract.luau` (PROC-001) and `FinaleContract.luau`
	(PROC-002), whose fixture this file REUSES for everything but AC-3/AC-4:
	tracks { 11, 12, 13 } and { 14, 15, 16, 17 }, finale { 13, 17 }, decoys 18
	and 19, four rooms (11, 12, 19 in room 1; 13, 14 in room 2; 15, 16 in room
	3; 17, 18 in room 4), the ring kim -> zed -> amy -> bob, class i at seat i.

	`tests/server/procedure_outcome_test.luau` applies these to the real module.
	`tests/server/procedure_outcome_controls_test.luau` applies them to a
	reference stand-in and to deliberately wrong stand-ins, so that in RED -
	where the production module LOADS but has none of this story's exports or
	behaviour - every check here has still been EXECUTED and observed to accept
	a correct implementation and to reject the defect it exists to catch.

	A `procedure` here is anything with the plain field functions the three
	stories' Contracts write, called with a dot:

	    P.start(facility, now, tuning, roundSeed, roundSeconds) -> ProcedureState
	    P.isLive / P.dial / P.turn / P.tick / P.partnerLamps / P.isComplete
	    P.deadline(state)                                  -> number
	    P.isDark(state, room)                              -> boolean
	    P.blackoutWeights(state)                           -> { [room]: weight }
	    P.drawRoom(weights, rng)                           -> room?

	THE TUNING IS THE SHIPPED ONE WITH ELEVEN OVERRIDES, so that every constant a
	check reads is distinct from its shipped value and from every other it must
	be told from: clock penalty 20 -> 7, blackout threshold 2 -> 3, rooms per
	threshold 1 -> 2 (so "exactly blackout_rooms_per_threshold" is not satisfied
	by 1), instability_max 5 -> 6 (a MULTIPLE of the threshold, so a blackout
	fired at the max is visible), live weight 1 -> 5, waiting weight 1 -> 2,
	plus PROC-001/002's turn range 7, window 3, reset 5, wrong value 1, out of
	order 2, failed pair 1. Under those weights the fixture's rooms weigh
	{ 1 = 7, 2 = 7, 3 = 4, 4 = 2 } at start. AC-1 and AC-6 are ALSO run under
	the shipped tuning, where they read out literally (520, 500, 480; five wrong
	turns lose). `roundSeconds` is passed to `start` (I-2): 200 here, so the
	deadline is 300 at start, and `Tuning.round.round_seconds` for the shipped
	rows.

	A SECOND, HAND-BUILT FACILITY for AC-3's first clause and AC-4: three rooms
	in a row, every track step in room 1, a decoy in room 2, a committed-able
	step and a decoy in room 3. With 31 committed, room 1 holds every
	uncommitted step and rooms 2 and 3 weigh 0; once room 1 is dark, every lit
	room weighs 0.

	THE ORACLE PARTITION IS HONOURED HERE. AC-1, AC-2, AC-4, AC-6..AC-8 and
	AC-3's first clause are SETTLED by `mechanics.md` §5 and the Contract's
	I-1..I-10; every such check reads the rule out and is named after it. AC-3's
	second clause is the one ORACLE-FREE check (a frequency, 0.75 ± 0.02 over
	20,000 draws of `drawRoom`, with a uniform draw as its control). AC-5 and
	the export shape are MECHANICAL. Nothing else here invents a threshold.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Finale = require("./FinaleContract")
local Generator = require("../../src/server/facility/Generator")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Rng = require("../../src/shared/Rng")
local Tuning = require("../../src/shared/Tuning")
local Turn = require("./TurnContract")

local OutcomeContract = {}

export type Procedure = Turn.Procedure
export type Vec = Turn.Vec
export type Tuning = Turn.Tuning
export type World = Turn.World

--[[ ------------------------------------------------------------------------
     The fixture.
     --------------------------------------------------------------------- ]]

OutcomeContract.NOW = Turn.NOW
OutcomeContract.ROUND_SEED = 9001
OutcomeContract.ROUND_SECONDS = 200

-- The overrides, named once. The controls file checks each differs from the
-- shipped value and from every other constant a check must tell it from.
OutcomeContract.OVERRIDES = {
	instance = { turn_range_studs = 7, simultaneous_window_seconds = 3 },
	actuation = {
		actuation_reset_seconds = 5,
		instability_per_wrong_value = 1,
		instability_per_out_of_order = 2,
		instability_per_failed_pair = 1,
		instability_clock_penalty_seconds = 7,
		instability_blackout_threshold = 3,
		blackout_rooms_per_threshold = 2,
		instability_max = 6,
		blackout_weight_live_step = 5,
		blackout_weight_waiting_step = 2,
	},
}

-- The weights the TurnContract fixture has at start under the overrides, by
-- hand: room 1 = 11 live (5) + 12 waiting (2) + decoy 19 (0); room 2 = 14
-- live (5) + finale 13 waiting (2); room 3 = 15, 16 waiting (2 + 2); room 4 =
-- finale 17 waiting (2) + decoy 18 (0).
OutcomeContract.WEIGHTS_AT_START = { [1] = 7, [2] = 7, [3] = 4, [4] = 2 }
OutcomeContract.ROOMS = { 1, 2, 3, 4 }
OutcomeContract.UNKNOWN_ROOM = 99

-- `OVERRIDES` with `extra` actuation keys on top.
local function overridesWith(extra: { [string]: number }): { [string]: { [string]: number } }
	local merged: { [string]: { [string]: number } } =
		{ instance = table.clone(OutcomeContract.OVERRIDES.instance), actuation = {} }
	for k, v in pairs(OutcomeContract.OVERRIDES.actuation) do
		merged.actuation[k] = v
	end
	for k, v in pairs(extra) do
		merged.actuation[k] = v
	end
	return merged
end

function OutcomeContract.world(): World
	return {
		facility = Turn.facility(),
		assignment = Turn.assignment(),
		tuning = Finale.tuning(OutcomeContract.OVERRIDES),
	}
end

-- The same fixture under the SHIPPED tuning, for the checks that read out
-- tuning.md §4 and §5 literally.
function OutcomeContract.shippedWorld(): World
	return {
		facility = Turn.facility(),
		assignment = Turn.assignment(),
		tuning = Finale.tuning({}),
	}
end

-- The TurnContract fixture with a threshold of 1 and one room per crossing,
-- so every point is a crossing and four points darken all four rooms.
OutcomeContract.EVERY_POINT_OVERRIDES = overridesWith({
	instability_blackout_threshold = 1,
	blackout_rooms_per_threshold = 1,
	instability_max = 10,
})

function OutcomeContract.everyPointWorld(): World
	return {
		facility = Turn.facility(),
		assignment = Turn.assignment(),
		tuning = Finale.tuning(OutcomeContract.EVERY_POINT_OVERRIDES),
	}
end

-- The hand-built facility for AC-3's first clause and AC-4 (header). Three
-- rooms in a row; ids are not list indices (P-2).
OutcomeContract.ONE_TRACK_1 = { 31, 21, 23 }
OutcomeContract.ONE_TRACK_2 = { 22, 24 }
OutcomeContract.ONE_FINALE = { 23, 24 }
OutcomeContract.ONE_DECOYS = { 25, 32 }
OutcomeContract.ONE_ROOMS = { 1, 2, 3 }
-- The room holding every track step; the committed-able step in room 3.
OutcomeContract.ONE_STEP_ROOM = 1
OutcomeContract.ONE_FIRST = 31
-- The live step in room 1 the wrong turns are made on (zed's, class 2).
OutcomeContract.ONE_WRONG = 21

local ONE_MACHINES = {
	{ id = 22, room = 1, slot = 2, keyClass = 3, tag = 1, requiredSetting = 2 },
	{ id = 31, room = 3, slot = 1, keyClass = 1, tag = 1, requiredSetting = 3 },
	{ id = 25, room = 2, slot = 1, keyClass = 3, tag = 2, requiredSetting = 1 },
	{ id = 21, room = 1, slot = 1, keyClass = 2, tag = 1, requiredSetting = 1 },
	{ id = 24, room = 1, slot = 4, keyClass = 1, tag = 2, requiredSetting = 4 },
	{ id = 32, room = 3, slot = 2, keyClass = 2, tag = 2, requiredSetting = 2 },
	{ id = 23, room = 1, slot = 3, keyClass = 4, tag = 1, requiredSetting = 2 },
}

function OutcomeContract.oneRoomFacility(): any
	return {
		layout = {
			rooms = {
				{ id = 1, column = 1, row = 1 },
				{ id = 2, column = 2, row = 1 },
				{ id = 3, column = 3, row = 1 },
			},
			doors = { { a = 1, b = 2 }, { a = 2, b = 3 } },
			spawnRoom = 2,
		},
		placement = {
			machines = Deep.copy(ONE_MACHINES),
			stepsPerClass = { [1] = 2, [2] = 1, [3] = 1, [4] = 1 },
		},
		steps = {
			tracks = {
				Deep.copy(OutcomeContract.ONE_TRACK_1),
				Deep.copy(OutcomeContract.ONE_TRACK_2),
			},
			finale = Deep.copy(OutcomeContract.ONE_FINALE),
		},
		spawnRoom = 2,
		par = 60,
		attempt = 1,
	}
end

-- With 31 committed: room 1 = 21 live (5) + 22 live (5) + 23, 24 waiting
-- finale (2 + 2); rooms 2 and 3 hold a decoy, or a decoy and a committed step.
OutcomeContract.ONE_WEIGHTS_AFTER_31 = { [1] = 14, [2] = 0, [3] = 0 }

function OutcomeContract.oneRoomWorld(): World
	return {
		facility = OutcomeContract.oneRoomFacility(),
		assignment = Turn.assignment(),
		tuning = Finale.tuning(OutcomeContract.EVERY_POINT_OVERRIDES),
	}
end

--[[ ------------------------------------------------------------------------
     Scenario helpers.
     --------------------------------------------------------------------- ]]

local function started(P: Procedure, w: World, roundSeconds: number?, seed: number?): any
	return P.start(
		w.facility,
		OutcomeContract.NOW,
		w.tuning,
		seed or OutcomeContract.ROUND_SEED,
		roundSeconds or OutcomeContract.ROUND_SECONDS
	)
end

-- I-2's shape guard: a missing export fails on a line that names it.
local function need(P: Procedure, name: string)
	if typeof(P[name]) ~= "function" then
		Contract.fail(`I-2: Procedure.{name} is {typeof(P[name])}, expected a function`)
	end
end

-- The holder of `id`, standing at it, turning it to `setting` at `now`.
local function turnBy(
	P: Procedure,
	w: World,
	state: any,
	id: number,
	setting: number,
	now: number
): (any, any)
	local holder = Turn.holderOf(w.facility, id)
	return P.turn(state, w.assignment, holder, id, setting, now, Turn.standingAt(w, holder, id))
end

-- A commit, failing loudly when it does not happen so no later assertion
-- runs on a state the scenario did not reach.
local function commit(
	P: Procedure,
	w: World,
	state: any,
	id: number,
	now: number,
	label: string
): any
	local next_, result = turnBy(P, w, state, id, Turn.requiredSetting(w.facility, id), now)
	if not Deep.equal(result, { kind = "committed", machineId = id }) then
		Contract.fail(
			`{label}: setting up the scenario, {Turn.holderOf(w.facility, id)} turning live machine {id} to its required setting at {now} returned {Deep.show(
				result
			)}, expected \{ kind = "committed", machineId = {id} }`
		)
	end
	return next_
end

-- A rejection for `reason`: a live step on a wrong setting (`wrong_setting`)
-- or a waiting step / decoy on its required setting (`not_live`).
local function reject(
	P: Procedure,
	w: World,
	state: any,
	id: number,
	now: number,
	reason: string,
	label: string
): any
	local setting = if reason == "wrong_setting"
		then Turn.wrongSetting(w.facility, id, w.tuning)
		else Turn.requiredSetting(w.facility, id)
	local next_, result = turnBy(P, w, state, id, setting, now)
	if not Deep.equal(result, { kind = "rejected", machineId = id, reason = reason }) then
		Contract.fail(
			`{label}: setting up the scenario, {Turn.holderOf(w.facility, id)} turning machine {id} to {setting} at {now} returned {Deep.show(
				result
			)}, expected \{ kind = "rejected", machineId = {id}, reason = "{reason}" }`
		)
	end
	return next_
end

-- Every ordinary step of the TurnContract fixture committed, at NOW + 1 ..
-- NOW + 5, from `state0` (which carries the scenario's own roundSeconds).
local function liveFinale(P: Procedure, w: World, state0: any, label: string): any
	local state = state0
	for i, id in Finale.ORDINARY do
		state = commit(P, w, state, id, OutcomeContract.NOW + i, label)
	end
	return state
end

local function arm(P: Procedure, w: World, state: any, id: number, now: number, label: string): any
	local next_, result = turnBy(P, w, state, id, Turn.requiredSetting(w.facility, id), now)
	if not Deep.equal(result, { kind = "armed", machineId = id }) then
		Contract.fail(
			`{label}: setting up the scenario, arming finale machine {id} at {now} returned {Deep.show(
				result
			)}, expected \{ kind = "armed", machineId = {id} }`
		)
	end
	return next_
end

-- The independently built stream of I-1: the k-th blackout draw of a round
-- is the k-th `nextInteger` of this.
function OutcomeContract.blackoutStream(seed: number): Rng.Rng
	return Rng.fromSeed(seed):derive("blackout")
end

-- The rooms `count` successive draws from `stream` over `weights` return,
-- through the module's own `drawRoom`, each drawn room removed before the
-- next draw (I-4: the lit set is recomputed between draws, and a wrong turn
-- commits nothing, so only the dark set moves).
function OutcomeContract.predictDraws(
	P: Procedure,
	weights: { [number]: number },
	stream: Rng.Rng,
	count: number
): { number }
	local left = table.clone(weights)
	local drawn: { number } = {}
	for _ = 1, count do
		local room = P.drawRoom(left, stream)
		if room == nil then
			break
		end
		table.insert(drawn, room)
		left[room] = nil
	end
	return drawn
end

-- The dark rooms of `state`, ascending.
function OutcomeContract.darkRooms(state: any): { number }
	local out: { number } = {}
	for room, isDark in pairs(state.dark or {}) do
		if isDark == true then
			table.insert(out, room)
		end
	end
	table.sort(out)
	return out
end

local function asSet(rooms: { number }): { [number]: boolean }
	local set: { [number]: boolean } = {}
	for _, room in rooms do
		set[room] = true
	end
	return set
end

local WON = { result = "won", reason = "procedure_complete" }
local LOST_INSTABILITY = { result = "lost", reason = "instability" }
local LOST_CLOCK = { result = "lost", reason = "clock" }

local NOBODY: { [string]: Vec } = {}

--[[ ------------------------------------------------------------------------
     The export shape and the state fields (Contract, I-1, I-2, I-8).
     --------------------------------------------------------------------- ]]

-- `start` carries the round fields the Contract names, deep-equal; the four
-- new exports exist; `deadline` is startedAt + roundSeconds; no room is dark;
-- `blackoutWeights` is the hand-computed map; `tick` at start returns a
-- deep-equal state and nil, and that nil is `state.outcome` (I-8).
function OutcomeContract.startCarriesTheRoundFieldsAndTheNewExportsAnswerInShape(P: Procedure)
	for _, name in { "deadline", "isDark", "blackoutWeights", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.world()
	local state = started(P, w)
	local problems: { string } = {}
	local function expect(field: string, want: any)
		if not Deep.equal(state[field], want) then
			table.insert(
				problems,
				`state.{field} is {Deep.show(state[field])}, expected {Deep.show(want)}`
			)
		end
	end
	expect("startedAt", OutcomeContract.NOW)
	expect("roundSeconds", OutcomeContract.ROUND_SECONDS)
	expect("penaltySeconds", 0)
	expect("dark", {})
	expect("outcome", nil)
	expect("roundSeed", OutcomeContract.ROUND_SEED)
	expect("blackoutDraws", 0)
	local deadline = P.deadline(state)
	if deadline ~= OutcomeContract.NOW + OutcomeContract.ROUND_SECONDS then
		table.insert(
			problems,
			`deadline(start) is {Deep.show(deadline)}, expected startedAt {OutcomeContract.NOW} + roundSeconds {OutcomeContract.ROUND_SECONDS} = {OutcomeContract.NOW + OutcomeContract.ROUND_SECONDS}`
		)
	end
	for _, room in { 1, 2, 3, 4, OutcomeContract.UNKNOWN_ROOM } do
		local answer = P.isDark(state, room)
		if answer ~= false then
			table.insert(
				problems,
				`isDark({room}) at start is {typeof(answer)} {Deep.show(answer)}, expected the boolean false`
			)
		end
	end
	local weights = P.blackoutWeights(state)
	if not Deep.equal(weights, OutcomeContract.WEIGHTS_AT_START) then
		table.insert(
			problems,
			`blackoutWeights(start) is {Deep.show(weights)}, expected {Deep.show(
				OutcomeContract.WEIGHTS_AT_START
			)} (live 5, waiting 2, decoys 0; every lit room present)`
		)
	end
	local ticked, second = P.tick(state, w.assignment, OutcomeContract.NOW + 1, NOBODY)
	if not Deep.equal(ticked, state) then
		table.insert(
			problems,
			`tick at start returned a state that differs from the one passed:\n{Deep.diff(
				state,
				ticked
			)}`
		)
	end
	if second ~= nil or ticked.outcome ~= nil then
		table.insert(
			problems,
			`tick at start returned {Deep.show(second)} with state.outcome {Deep.show(
				ticked.outcome
			)}, expected nil and nil (I-8)`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`Contract/I-1/I-2: start does not carry the round fields, or the new exports do not answer in shape:\n{Contract.firstFew(
				problems,
				12
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-1. The clock (I-3).
     --------------------------------------------------------------------- ]]

-- Each point charged, by any path, removes instability_clock_penalty_seconds
-- (the fixture's 7): a wrong setting (1 point), a not_live decoy (2 points
-- at once), and an expired finale window (failed pair, 1 point).
function OutcomeContract.deadlineIsStartPlusRoundSecondsLessThePenaltyPerPoint(P: Procedure)
	need(P, "deadline")
	local w = OutcomeContract.world()
	local a = w.tuning.actuation
	local penalty = a.instability_clock_penalty_seconds
	local t0 = OutcomeContract.NOW
	local R = OutcomeContract.ROUND_SECONDS
	local problems: { string } = {}
	local function expectClock(state: any, points: number, label: string)
		local want = t0 + R - points * penalty
		local got = P.deadline(state)
		if got ~= want then
			table.insert(
				problems,
				`{label}: deadline is {Deep.show(got)}, expected {t0} + {R} - {points} x {penalty} = {want}`
			)
		end
		if state.penaltySeconds ~= points * penalty then
			table.insert(
				problems,
				`{label}: state.penaltySeconds is {Deep.show(state.penaltySeconds)}, expected {points} x {penalty} = {points * penalty}`
			)
		end
	end
	local state = started(P, w)
	expectClock(state, 0, "at start")
	state = reject(P, w, state, 11, t0, "wrong_setting", "AC-1")
	expectClock(state, a.instability_per_wrong_value, "after one wrong setting")
	state = reject(P, w, state, 18, t0 + 1, "not_live", "AC-1")
	expectClock(
		state,
		a.instability_per_wrong_value + a.instability_per_out_of_order,
		"after a not_live decoy (2 points in one charge)"
	)
	-- The expiry path: the finale armed and left to expire charges
	-- instability_per_failed_pair through the same clock.
	local live = liveFinale(P, w, started(P, w), "AC-1")
	expectClock(live, 0, "with every ordinary step committed (commits charge nothing)")
	local armed = arm(P, w, live, Finale.A, Finale.T_ARM, "AC-1")
	expectClock(armed, 0, "with A armed (arming charges nothing)")
	local window = w.tuning.instance.simultaneous_window_seconds
	local expired = P.tick(armed, w.assignment, Finale.T_ARM + window + 1, NOBODY)
	expectClock(expired, a.instability_per_failed_pair, "after the window expired by tick")
	if #problems > 0 then
		Contract.fail(
			`AC-1/I-3: deadline = startedAt + roundSeconds - penaltySeconds, every point charged adding instability_clock_penalty_seconds ({penalty}):\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- Under the shipped tuning the deadline reads out literally: t0 + 420, then
-- 500 after one point, 480 after two (tuning.md §5 round_seconds 420, §4
-- instability_clock_penalty_seconds 20).
function OutcomeContract.underTheShippedTuningTheDeadlineReadsLiterally(P: Procedure)
	need(P, "deadline")
	local w = OutcomeContract.shippedWorld()
	local t0 = OutcomeContract.NOW
	local state = started(P, w, Tuning.round.round_seconds)
	local problems: { string } = {}
	local function expectClock(s: any, want: number, label: string)
		local got = P.deadline(s)
		if got ~= want then
			table.insert(problems, `{label}: deadline is {Deep.show(got)}, expected {want}`)
		end
	end
	expectClock(state, t0 + 420, "at start")
	state = reject(P, w, state, 11, t0, "wrong_setting", "AC-1")
	expectClock(state, t0 + 420 - 20, "after one wrong turn")
	state = reject(P, w, state, 14, t0 + 1, "wrong_setting", "AC-1")
	expectClock(state, t0 + 420 - 40, "after two wrong turns")
	if #problems > 0 then
		Contract.fail(
			`AC-1 under the SHIPPED tuning (round_seconds 420, instability_clock_penalty_seconds 20):\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-2. Crossings (I-4), with the weighted draw (I-5) on I-1's stream.
     --------------------------------------------------------------------- ]]

-- Two wrong turns (11 at t0, 14 at t0 + 1): instability 2 = threshold - 1.
local function twoPoints(P: Procedure, w: World, label: string): any
	local t0 = OutcomeContract.NOW
	local state = reject(P, w, started(P, w), 11, t0, "wrong_setting", label)
	return reject(P, w, state, 14, t0 + 1, "wrong_setting", label)
end

-- The dark set, draw count and isDark of `state` against `wantDark`.
local function expectDark(
	P: Procedure,
	state: any,
	wantDark: { number },
	wantDraws: number,
	rooms: { number },
	label: string,
	problems: { string }
)
	local dark = OutcomeContract.darkRooms(state)
	if not Deep.equal(dark, wantDark) then
		table.insert(
			problems,
			`{label}: the dark rooms are {Deep.show(dark)}, expected {Deep.show(wantDark)}`
		)
	end
	if state.blackoutDraws ~= wantDraws then
		table.insert(
			problems,
			`{label}: state.blackoutDraws is {Deep.show(state.blackoutDraws)}, expected {wantDraws}`
		)
	end
	local want = asSet(wantDark)
	for _, room in rooms do
		local answer = P.isDark(state, room)
		if answer ~= (want[room] == true) then
			table.insert(
				problems,
				`{label}: isDark({room}) is {Deep.show(answer)}, expected {Deep.show(
					want[room] == true
				)}`
			)
		end
	end
end

-- Instability 1 and 2 (threshold 3) darken nothing and draw nothing.
function OutcomeContract.risingToJustBelowTheThresholdDarkensNothing(P: Procedure)
	need(P, "isDark")
	local w = OutcomeContract.world()
	local t0 = OutcomeContract.NOW
	local problems: { string } = {}
	local one = reject(P, w, started(P, w), 11, t0, "wrong_setting", "AC-2")
	expectDark(P, one, {}, 0, OutcomeContract.ROOMS, "at instability 1", problems)
	local two = reject(P, w, one, 14, t0 + 1, "wrong_setting", "AC-2")
	expectDark(P, two, {}, 0, OutcomeContract.ROOMS, "at instability 2 (threshold 3)", problems)
	if two.outcome ~= nil then
		table.insert(
			problems,
			`at instability 2 the outcome is {Deep.show(two.outcome)}, expected nil`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-2: rising to a non-multiple of instability_blackout_threshold (3) must darken nothing:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- 2 -> 3 darkens EXACTLY blackout_rooms_per_threshold (2) rooms: the two
-- that `drawRoom(blackoutWeights(s), stream)` returns on an independently
-- built `Rng.fromSeed(seed):derive("blackout")` stream, the first room
-- removed before the second draw (I-1, I-4, I-5). Two draws are recorded.
function OutcomeContract.crossingTheThresholdDarkensExactlyRoomsPerThresholdByTheWeightedDraw(
	P: Procedure
)
	for _, name in { "isDark", "blackoutWeights", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.world()
	local t0 = OutcomeContract.NOW
	local two = twoPoints(P, w, "AC-2")
	local problems: { string } = {}
	local weights = P.blackoutWeights(two)
	if not Deep.equal(weights, OutcomeContract.WEIGHTS_AT_START) then
		table.insert(
			problems,
			`blackoutWeights at instability 2 is {Deep.show(weights)}, expected {Deep.show(
				OutcomeContract.WEIGHTS_AT_START
			)} - rejections commit nothing, so the weights are start's`
		)
	end
	local stream = OutcomeContract.blackoutStream(OutcomeContract.ROUND_SEED)
	local predicted = OutcomeContract.predictDraws(P, OutcomeContract.WEIGHTS_AT_START, stream, 2)
	if #predicted ~= 2 or predicted[1] == predicted[2] then
		table.insert(
			problems,
			`predicting the crossing through drawRoom gave {Deep.show(predicted)}, expected two distinct rooms`
		)
	end
	table.sort(predicted)
	-- 11 was rejected at t0 and resets at t0 + 5; the boundary turn is evaluated (P-6).
	local three = reject(P, w, two, 11, t0 + 5, "wrong_setting", "AC-2")
	if three.instability ~= 3 then
		table.insert(problems, `instability is {Deep.show(three.instability)}, expected 3`)
	end
	expectDark(P, three, predicted, 2, OutcomeContract.ROOMS, "at the crossing 2 -> 3", problems)
	if three.outcome ~= nil then
		table.insert(
			problems,
			`the outcome at instability 3 is {Deep.show(three.outcome)}, expected nil`
		)
	end
	local after = P.blackoutWeights(three)
	local lit: { number } = {}
	for room in pairs(after) do
		table.insert(lit, room)
	end
	table.sort(lit)
	local wantLit: { number } = {}
	for _, room in OutcomeContract.ROOMS do
		if not table.find(predicted, room) then
			table.insert(wantLit, room)
		end
	end
	if not Deep.equal(lit, wantLit) then
		table.insert(
			problems,
			`blackoutWeights after the crossing has keys {Deep.show(lit)}, expected exactly the lit rooms {Deep.show(
				wantLit
			)} - a dark room is not a key`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-2/I-5: crossing instability_blackout_threshold (3) darkens exactly blackout_rooms_per_threshold (2) rooms, drawn by weight {Deep.show(
				OutcomeContract.WEIGHTS_AT_START
			)} from the "blackout" stream of seed {OutcomeContract.ROUND_SEED}:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- A 2-point charge from 2 to 4 skips the value 3 but still crosses it (I-4:
-- every v in old+1..new), and 4 -> 5 darkens nothing more.
function OutcomeContract.aChargeThatJumpsOverTheMultipleStillCrossesIt(P: Procedure)
	for _, name in { "isDark", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.world()
	local t0 = OutcomeContract.NOW
	local two = twoPoints(P, w, "I-4")
	local stream = OutcomeContract.blackoutStream(OutcomeContract.ROUND_SEED)
	local predicted = OutcomeContract.predictDraws(P, OutcomeContract.WEIGHTS_AT_START, stream, 2)
	table.sort(predicted)
	local problems: { string } = {}
	local four = reject(P, w, two, 18, t0 + 2, "not_live", "I-4")
	if four.instability ~= 4 then
		table.insert(problems, `instability is {Deep.show(four.instability)}, expected 2 + 2 = 4`)
	end
	expectDark(P, four, predicted, 2, OutcomeContract.ROOMS, "after the jump 2 -> 4", problems)
	-- A single point 4 -> 5: a wrong setting on 14 (rejected at t0 + 1, reset 5).
	local five = reject(P, w, four, 14, t0 + 6, "wrong_setting", "I-4")
	expectDark(
		P,
		five,
		predicted,
		2,
		OutcomeContract.ROOMS,
		"after 4 -> 5 (not a multiple)",
		problems
	)
	if five.outcome ~= nil then
		table.insert(
			problems,
			`the outcome at instability 5 is {Deep.show(five.outcome)}, expected nil`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-2/I-4: a charge of 2 that jumps from 2 to 4 still crosses 3 once, and 4 -> 5 darkens nothing:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- Reaching instability_max (6, a multiple of the threshold) ends the round
-- lost / instability and darkens nothing more: the two rooms from the
-- crossing at 3 are the only dark ones, and no third draw was made.
function OutcomeContract.reachingInstabilityMaxEndsTheRoundWithoutAnotherBlackout(P: Procedure)
	for _, name in { "isDark", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.world()
	local t0 = OutcomeContract.NOW
	local stream = OutcomeContract.blackoutStream(OutcomeContract.ROUND_SEED)
	local predicted = OutcomeContract.predictDraws(P, OutcomeContract.WEIGHTS_AT_START, stream, 2)
	table.sort(predicted)
	local state = twoPoints(P, w, "AC-2")
	state = reject(P, w, state, 18, t0 + 2, "not_live", "AC-2") -- 4
	state = reject(P, w, state, 11, t0 + 5, "wrong_setting", "AC-2") -- 5
	local problems: { string } = {}
	if state.outcome ~= nil then
		table.insert(
			problems,
			`at instability 5 the outcome is {Deep.show(state.outcome)}, expected nil`
		)
	end
	local lost, result =
		turnBy(P, w, state, 14, Turn.wrongSetting(w.facility, 14, w.tuning), t0 + 6)
	if not Deep.equal(result, { kind = "rejected", machineId = 14, reason = "wrong_setting" }) then
		table.insert(
			problems,
			`the turn that reaches the max returned {Deep.show(result)}, expected the ordinary rejected / wrong_setting - the turn is evaluated, and the outcome rides on the state`
		)
	end
	if lost.instability ~= 6 then
		table.insert(
			problems,
			`instability is {Deep.show(lost.instability)}, expected 6 = instability_max`
		)
	end
	if not Deep.equal(lost.outcome, LOST_INSTABILITY) then
		table.insert(
			problems,
			`state.outcome is {Deep.show(lost.outcome)}, expected {Deep.show(LOST_INSTABILITY)}`
		)
	end
	expectDark(P, lost, predicted, 2, OutcomeContract.ROOMS, "at instability_max 6", problems)
	if #problems > 0 then
		Contract.fail(
			`AC-2/AC-6: reaching instability_max (6, a multiple of threshold 3) is lost / instability with NO blackout at the max:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-3. The weighting: settled first clause, oracle-free second.
     --------------------------------------------------------------------- ]]

-- With 31 committed, room 1 holds every uncommitted step and rooms 2 and 3
-- weigh 0. Over 40 seeds, the crossing darkens room 1 every time; a uniform
-- draw picks a zero-weight room about two times in three.
function OutcomeContract.oneLitRoomHoldingEveryUncommittedStepIsAlwaysTheOneDarkened(P: Procedure)
	for _, name in { "isDark", "blackoutWeights" } do
		need(P, name)
	end
	local w = OutcomeContract.oneRoomWorld()
	local t0 = OutcomeContract.NOW
	local problems: { string } = {}
	local wrongRooms: { string } = {}
	for seed = 1, 40 do
		local state = commit(P, w, started(P, w, nil, seed), OutcomeContract.ONE_FIRST, t0, "AC-3")
		if seed == 1 then
			local weights = P.blackoutWeights(state)
			if not Deep.equal(weights, OutcomeContract.ONE_WEIGHTS_AFTER_31) then
				table.insert(
					problems,
					`blackoutWeights with 31 committed is {Deep.show(weights)}, expected {Deep.show(
						OutcomeContract.ONE_WEIGHTS_AFTER_31
					)}`
				)
			end
		end
		local crossed =
			reject(P, w, state, OutcomeContract.ONE_WRONG, t0 + 1, "wrong_setting", "AC-3")
		local dark = OutcomeContract.darkRooms(crossed)
		if not Deep.equal(dark, { OutcomeContract.ONE_STEP_ROOM }) then
			table.insert(wrongRooms, `seed {seed}: {Deep.show(dark)}`)
		end
	end
	if #wrongRooms > 0 then
		table.insert(
			problems,
			`{#wrongRooms} of 40 seeds darkened something other than room {OutcomeContract.ONE_STEP_ROOM} alone:\n{Contract.firstFew(
				wrongRooms,
				6
			)}`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-3: with every uncommitted step in room {OutcomeContract.ONE_STEP_ROOM} and the other lit rooms at weight 0, the crossing must always darken that room (a zero-weight room is never drawn while a positive weight exists, I-5):\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- ORACLE-FREE. Rooms 4 (weight 3) and 7 (weight 1); 20,000 draws of
-- `drawRoom` on one "blackout" stream; room 4 is drawn with frequency 0.75 ±
-- 0.02. A uniform draw scores about 0.5 and fails. The measured frequency is
-- in the message either way, so the controls file can record it.
OutcomeContract.FREQUENCY_DRAWS = 20000
OutcomeContract.FREQUENCY_BAND = { low = 0.73, high = 0.77 }

function OutcomeContract.heavierRoomFrequency(P: Procedure, seed: number): number
	local rng = OutcomeContract.blackoutStream(seed)
	local heavy = 0
	local other = 0
	for _ = 1, OutcomeContract.FREQUENCY_DRAWS do
		local room = P.drawRoom({ [4] = 3, [7] = 1 }, rng)
		if room == 4 then
			heavy += 1
		elseif room ~= 7 then
			other += 1
		end
	end
	if other > 0 then
		Contract.fail(
			`AC-3: drawRoom over \{ [4] = 3, [7] = 1 } returned something other than 4 or 7 on {other} of {OutcomeContract.FREQUENCY_DRAWS} draws`
		)
	end
	return heavy / OutcomeContract.FREQUENCY_DRAWS
end

function OutcomeContract.theHeavierOfTwoRoomsIsDrawnThreeTimesInFour(P: Procedure)
	need(P, "drawRoom")
	local f = OutcomeContract.heavierRoomFrequency(P, OutcomeContract.ROUND_SEED)
	local band = OutcomeContract.FREQUENCY_BAND
	if f < band.low or f > band.high then
		Contract.fail(
			`AC-3: over {OutcomeContract.FREQUENCY_DRAWS} draws of drawRoom(\{ [4] = 3, [7] = 1 }) on the "blackout" stream of seed {OutcomeContract.ROUND_SEED}, room 4 was drawn with frequency {f}, expected 0.75 +/- 0.02 ([{band.low}, {band.high}])`
		)
	end
end

-- A scripted rng: `nextInteger` returns the queued values in order and
-- records every call, so the r -> room mapping of I-5 is pinned exactly.
local function scripted(values: { number }): (any, { { number } })
	local calls: { { number } } = {}
	local i = 0
	local rng: any = {}
	rng.nextInteger = function(_self: any, min: number, max: number): number
		i += 1
		table.insert(calls, { min, max })
		local v = values[i]
		assert(v ~= nil, "the scripted rng ran out of values")
		return v
	end
	rng.nextNumber = function(_self: any): number
		error("drawRoom must draw through nextInteger (I-5), not nextNumber", 0)
	end
	rng.shuffle = function(_self: any, _list: any): any
		error("drawRoom must not shuffle (I-5)", 0)
	end
	rng.derive = function(_self: any, _label: string): any
		error("drawRoom is handed the stream; it must not derive from it (I-1)", 0)
	end
	return rng, calls
end

-- I-5 exactly: rooms in ascending id; W > 0 -> r = nextInteger(1, W) and the
-- first room whose cumulative weight >= r; all zero -> rooms[nextInteger(1,
-- #rooms)]; empty -> nil and no draw; one call per non-nil draw; `weights`
-- untouched (I-10).
function OutcomeContract.drawRoomMapsTheDrawToTheFirstRoomWhoseCumulativeWeightReachesIt(
	P: Procedure
)
	need(P, "drawRoom")
	local problems: { string } = {}
	local function case(
		label: string,
		weights: { [number]: number },
		r: number?,
		wantRoom: number?,
		wantCall: { number }?
	)
		local snapshot = Deep.copy(weights)
		local rng, calls = scripted(if r then { r } else {})
		local ok, got = pcall(P.drawRoom, weights, rng)
		if not ok then
			table.insert(problems, `{label}: drawRoom raised: {tostring(got)}`)
			return
		end
		if got ~= wantRoom then
			table.insert(
				problems,
				`{label}: returned {Deep.show(got)}, expected {Deep.show(wantRoom)}`
			)
		end
		local wantCalls = if wantCall then { wantCall } else {}
		if not Deep.equal(calls, wantCalls) then
			table.insert(
				problems,
				`{label}: nextInteger calls were {Deep.show(calls)}, expected {Deep.show(wantCalls)}`
			)
		end
		if not Deep.equal(weights, snapshot) then
			table.insert(
				problems,
				`{label}: drawRoom mutated its weights:\n{Deep.diff(snapshot, weights)}`
			)
		end
	end
	-- Weights { 1 = 3, 2 = 1 }: cumulative 3, 4.
	case("{1=3, 2=1}, r = 1", { [1] = 3, [2] = 1 }, 1, 1, { 1, 4 })
	case("{1=3, 2=1}, r = 3 (exactly the first cumulative)", { [1] = 3, [2] = 1 }, 3, 1, { 1, 4 })
	case("{1=3, 2=1}, r = 4", { [1] = 3, [2] = 1 }, 4, 2, { 1, 4 })
	-- Zero-weight rooms are skipped: { 1 = 0, 2 = 3, 3 = 0, 4 = 1 }: cumulative 0, 3, 3, 4.
	case("{1=0, 2=3, 3=0, 4=1}, r = 1", { [1] = 0, [2] = 3, [3] = 0, [4] = 1 }, 1, 2, { 1, 4 })
	case("{1=0, 2=3, 3=0, 4=1}, r = 3", { [1] = 0, [2] = 3, [3] = 0, [4] = 1 }, 3, 2, { 1, 4 })
	case(
		"{1=0, 2=3, 3=0, 4=1}, r = 4 (room 3 at weight 0 is skipped)",
		{ [1] = 0, [2] = 3, [3] = 0, [4] = 1 },
		4,
		4,
		{ 1, 4 }
	)
	-- Ids out of order in the table are drawn in ASCENDING id: { 9 = 1, 2 = 2 }: rooms 2, 9.
	case("{9=1, 2=2}, r = 2 -> room 2 (ascending id)", { [9] = 1, [2] = 2 }, 2, 2, { 1, 3 })
	case("{9=1, 2=2}, r = 3 -> room 9", { [9] = 1, [2] = 2 }, 3, 9, { 1, 3 })
	-- All zero: uniform over the rooms by index, ascending id.
	case("{2=0, 5=0, 9=0}, i = 1 -> room 2", { [2] = 0, [5] = 0, [9] = 0 }, 1, 2, { 1, 3 })
	case("{2=0, 5=0, 9=0}, i = 3 -> room 9", { [2] = 0, [5] = 0, [9] = 0 }, 3, 9, { 1, 3 })
	case("{6=0}, i = 1 -> room 6", { [6] = 0 }, 1, 6, { 1, 1 })
	-- Empty: nil, and no draw at all.
	case("{} -> nil, no draw", {}, nil, nil, nil)
	if #problems > 0 then
		Contract.fail(
			`AC-3/I-5: drawRoom(weights, rng) is one nextInteger(1, W) mapped to the first room (ascending id) whose cumulative weight reaches it, or nextInteger(1, #rooms) when every weight is 0, or nil with no draw when there is no room:\n{Contract.firstFew(
				problems,
				12
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-4. Every lit room at weight 0; no lit room at all.
     --------------------------------------------------------------------- ]]

-- The hand-built facility, threshold 1, one room per crossing: the first
-- crossing darkens room 1 (every step); the second finds both lit rooms at
-- weight 0 and still darkens one, uniformly; the third darkens the last; the
-- fourth finds nothing lit, darkens nothing, draws nothing and raises
-- nothing. A dark room is never drawn twice.
function OutcomeContract.everyLitRoomAtWeightZeroStillDarkensOneAndNoneLitDoesNothing(P: Procedure)
	for _, name in { "isDark", "blackoutWeights", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.oneRoomWorld()
	local t0 = OutcomeContract.NOW
	local reset = w.tuning.actuation.actuation_reset_seconds
	local problems: { string } = {}
	local state = commit(P, w, started(P, w), OutcomeContract.ONE_FIRST, t0, "AC-4")
	-- The expected order, through drawRoom on the independent stream.
	local stream = OutcomeContract.blackoutStream(OutcomeContract.ROUND_SEED)
	local predicted =
		OutcomeContract.predictDraws(P, OutcomeContract.ONE_WEIGHTS_AFTER_31, stream, 3)
	if #predicted ~= 3 or predicted[1] ~= OutcomeContract.ONE_STEP_ROOM then
		table.insert(
			problems,
			`predicting three draws through drawRoom gave {Deep.show(predicted)}, expected room {OutcomeContract.ONE_STEP_ROOM} first and then the two zero-weight rooms`
		)
	end
	local expectedDark: { number } = {}
	for k = 1, 4 do
		local now = t0 + 1 + (k - 1) * (reset + 1)
		local ok, next_, result = pcall(
			turnBy,
			P,
			w,
			state,
			OutcomeContract.ONE_WRONG,
			Turn.wrongSetting(w.facility, OutcomeContract.ONE_WRONG, w.tuning),
			now
		)
		if not ok then
			table.insert(problems, `crossing {k}: the turn raised: {tostring(next_)}`)
			break
		end
		if
			not Deep.equal(result, {
				kind = "rejected",
				machineId = OutcomeContract.ONE_WRONG,
				reason = "wrong_setting",
			})
		then
			table.insert(
				problems,
				`crossing {k}: the turn returned {Deep.show(result)}, expected rejected / wrong_setting`
			)
		end
		state = next_
		if k <= 3 and predicted[k] ~= nil then
			table.insert(expectedDark, predicted[k])
		end
		local sorted = table.clone(expectedDark)
		table.sort(sorted)
		local weightsBefore = if k == 2
			then "both lit rooms at weight 0"
			elseif k == 3 then "one lit room at weight 0"
			elseif k == 4 then "no lit room"
			else "room 1 at weight 14"
		expectDark(
			P,
			state,
			sorted,
			math.min(k, 3),
			OutcomeContract.ONE_ROOMS,
			`crossing {k} ({weightsBefore})`,
			problems
		)
		if k == 2 then
			local weights = P.blackoutWeights(state)
			local keys: { number } = {}
			for room, weight in pairs(weights) do
				table.insert(keys, room)
				if weight ~= 0 then
					table.insert(
						problems,
						`after crossing 2, lit room {room} weighs {weight}, expected 0`
					)
				end
			end
			if #keys ~= 1 then
				table.insert(
					problems,
					`after crossing 2, blackoutWeights has keys {Deep.show(keys)}, expected exactly one lit room`
				)
			end
		end
		if k == 4 then
			if not Deep.equal(P.blackoutWeights(state), {}) then
				table.insert(
					problems,
					`with every room dark, blackoutWeights is {Deep.show(P.blackoutWeights(state))}, expected \{}`
				)
			end
			if state.instability ~= 4 or state.outcome ~= nil then
				table.insert(
					problems,
					`after crossing 4 instability is {Deep.show(state.instability)} and the outcome {Deep.show(
						state.outcome
					)}; expected 4 and nil - the charge still lands, only the blackout has nothing to do`
				)
			end
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-4/I-4: every lit room at weight 0 still darkens one lit room (uniform); every room dark darkens nothing and draws nothing; a dark room is never drawn again:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-5. Determinism (mechanical).
     --------------------------------------------------------------------- ]]

-- The rooms darkened, in crossing order, by four wrong turns on 11 under the
-- every-point tuning from `state0`.
local function darkOrder(P: Procedure, w: World, state0: any, label: string): { number }
	local t0 = OutcomeContract.NOW
	local reset = w.tuning.actuation.actuation_reset_seconds
	local order: { number } = {}
	local state = state0
	local seen: { [number]: boolean } = {}
	for k = 1, 4 do
		state = reject(P, w, state, 11, t0 + (k - 1) * (reset + 1), "wrong_setting", label)
		for _, room in OutcomeContract.darkRooms(state) do
			if not seen[room] then
				seen[room] = true
				table.insert(order, room)
			end
		end
	end
	return order
end

-- Same seed, same sequence: the same four rooms in the same order, twice,
-- and that order is what drawRoom predicts on the independent "blackout"
-- stream with the dark room removed before each draw.
function OutcomeContract.theSameSeedReplaysTheSameRoomsInTheSameOrder(P: Procedure)
	for _, name in { "isDark", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.everyPointWorld()
	local first = darkOrder(P, w, started(P, w), "AC-5")
	local second = darkOrder(P, w, started(P, w), "AC-5")
	local stream = OutcomeContract.blackoutStream(OutcomeContract.ROUND_SEED)
	local predicted = OutcomeContract.predictDraws(P, OutcomeContract.WEIGHTS_AT_START, stream, 4)
	local problems: { string } = {}
	if #first ~= 4 then
		table.insert(
			problems,
			`four crossings darkened {Deep.show(first)}, expected four distinct rooms`
		)
	end
	if not Deep.equal(first, second) then
		table.insert(
			problems,
			`replaying seed {OutcomeContract.ROUND_SEED} darkened {Deep.show(second)} where the first run darkened {Deep.show(
				first
			)}`
		)
	end
	if not Deep.equal(first, predicted) then
		table.insert(
			problems,
			`the order darkened was {Deep.show(first)}; drawRoom on an independent Rng.fromSeed({OutcomeContract.ROUND_SEED}):derive("blackout") predicts {Deep.show(
				predicted
			)} (I-1: the k-th blackout draw is the k-th nextInteger of that stream)`
		)
	end
	-- Another seed, for the record: the mechanism is seeded, not fixed.
	local other = darkOrder(P, w, started(P, w, nil, OutcomeContract.ROUND_SEED + 1), "AC-5")
	local otherPredicted = OutcomeContract.predictDraws(
		P,
		OutcomeContract.WEIGHTS_AT_START,
		OutcomeContract.blackoutStream(OutcomeContract.ROUND_SEED + 1),
		4
	)
	if not Deep.equal(other, otherPredicted) then
		table.insert(
			problems,
			`seed {OutcomeContract.ROUND_SEED + 1} darkened {Deep.show(other)}, drawRoom on its "blackout" stream predicts {Deep.show(
				otherPredicted
			)}`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-5/I-1: one seed replays one blackout order:\n{Contract.firstFew(problems, 8)}`
		)
	end
end

-- Generating a facility with seed s before and after running a Procedure
-- with roundSeed s through four crossings gives deep-equal facilities, and
-- the "instance" stream of s is untouched: the blackout draw moves no
-- generator draw.
function OutcomeContract.drawingFromTheBlackoutStreamMovesNoGeneratorDraw(P: Procedure)
	need(P, "isDark")
	local w = OutcomeContract.everyPointWorld()
	local seed = OutcomeContract.ROUND_SEED
	local function sample(): { number }
		local s = Rng.fromSeed(seed):derive("instance")
		local out: { number } = {}
		for _ = 1, 8 do
			table.insert(out, s:nextInteger(1, 1000000))
		end
		return out
	end
	local before = Generator.generate(w.assignment, seed, MechanicsTuning)
	local streamBefore = sample()
	local order = darkOrder(P, w, started(P, w, nil, seed), "AC-5")
	local after = Generator.generate(w.assignment, seed, MechanicsTuning)
	local streamAfter = sample()
	local problems: { string } = {}
	if before.kind ~= "facility" then
		table.insert(
			problems,
			`Generator.generate(seed {seed}) did not produce a facility: {Deep.show(before)}`
		)
	end
	if #order ~= 4 then
		table.insert(problems, `the Procedure darkened {Deep.show(order)}, expected four rooms`)
	end
	if not Deep.equal(before, after) then
		table.insert(
			problems,
			`Generator.generate(seed {seed}) differs after the Procedure drew four blackouts on roundSeed {seed}:\n{Deep.diff(
				before,
				after
			)}`
		)
	end
	if not Deep.equal(streamBefore, streamAfter) then
		table.insert(
			problems,
			`Rng.fromSeed({seed}):derive("instance") reads {Deep.show(streamAfter)} after the blackouts, {Deep.show(
				streamBefore
			)} before`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-5: drawing from the "blackout" sub-stream moves no generator draw:\n{Contract.firstFew(
				problems,
				6
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-6. The outcomes and their order (I-6, I-3, I-7, I-8).
     --------------------------------------------------------------------- ]]

-- A 50 s round (deadline 150). The finale armed at 149 and completed at
-- 149.999: won / procedure_complete on the state, and on every later tick.
-- Completed at exactly 150 instead: refused / round_over, lost / clock,
-- nothing committed by that turn.
function OutcomeContract.theLastFinaleCommitBeforeTheDeadlineWinsAndAtTheDeadlineItIsRoundOver(
	P: Procedure
)
	need(P, "deadline")
	local w = OutcomeContract.world()
	local R = 50
	local t0 = OutcomeContract.NOW
	local deadline = t0 + R
	local A, B = Finale.A, Finale.B
	local problems: { string } = {}
	local live = liveFinale(P, w, started(P, w, R), "AC-6")
	if P.deadline(live) ~= deadline then
		table.insert(
			problems,
			`deadline with every ordinary step committed is {Deep.show(P.deadline(live))}, expected {deadline}`
		)
	end
	local armed = arm(P, w, live, A, deadline - 1, "AC-6")

	local won, result =
		turnBy(P, w, armed, B, Turn.requiredSetting(w.facility, B), deadline - 0.001)
	if not Deep.equal(result, { kind = "committed", machineId = B }) then
		table.insert(
			problems,
			`B at deadline - 0.001: result is {Deep.show(result)}, expected committed`
		)
	end
	if not Deep.equal(won.outcome, WON) then
		table.insert(
			problems,
			`B at deadline - 0.001: state.outcome is {Deep.show(won.outcome)}, expected {Deep.show(
				WON
			)}`
		)
	end
	if P.isComplete(won) ~= true then
		table.insert(
			problems,
			`after the win isComplete is {Deep.show(P.isComplete(won))}, expected true`
		)
	end
	local ticked, second = P.tick(won, w.assignment, deadline + 100, NOBODY)
	if not Deep.equal(second, WON) or not Deep.equal(ticked.outcome, WON) then
		table.insert(
			problems,
			`a tick 100 s past the deadline on the won state returned {Deep.show(second)} with state.outcome {Deep.show(
				ticked.outcome
			)}, expected {Deep.show(WON)} twice (I-8) - a win is not undone by the clock`
		)
	end

	local over, result2 = turnBy(P, w, armed, B, Turn.requiredSetting(w.facility, B), deadline)
	if not Deep.equal(result2, { kind = "refused", machineId = B, reason = "round_over" }) then
		table.insert(
			problems,
			`B at EXACTLY the deadline ({deadline}): result is {Deep.show(result2)}, expected refused / round_over (I-3: the clock is out at now >= deadline; I-6 step 3)`
		)
	end
	if not Deep.equal(over.outcome, LOST_CLOCK) then
		table.insert(
			problems,
			`B at exactly the deadline: state.outcome is {Deep.show(over.outcome)}, expected {Deep.show(
				LOST_CLOCK
			)}`
		)
	end
	if over.committed[B] or over.committed[A] then
		table.insert(
			problems,
			`B at exactly the deadline committed something: {Deep.show(over.committed)}`
		)
	end
	if #over.log ~= #armed.log then
		table.insert(
			problems,
			`B at exactly the deadline grew the log from {#armed.log} to {#over.log}; round_over writes no entry (I-7)`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-6: the last finale commit before the deadline is won / procedure_complete; at the deadline the turn is refused / round_over and the round is lost / clock:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- The state five points in with the clock arranged so the SIXTH point's
-- penalty takes it to `remaining` seconds (0 or below), at the turn's now.
-- Points: 11 wrong (1), 14 wrong (2), decoy 18 (4, crossing), 11 wrong (5);
-- the sixth is 14 wrong at `finalNow`.
local function fivePointsThen(P: Procedure, w: World, roundSeconds: number, label: string): any
	local t0 = OutcomeContract.NOW
	local state = reject(P, w, started(P, w, roundSeconds), 11, t0, "wrong_setting", label)
	state = reject(P, w, state, 14, t0 + 1, "wrong_setting", label)
	state = reject(P, w, state, 18, t0 + 2, "not_live", label)
	state = reject(P, w, state, 11, t0 + 5, "wrong_setting", label)
	return state
end

-- The sixth wrong turn reaches instability_max (6) AND its 7 s penalty takes
-- the clock to exactly 0 (round 50 s, turn at 108: deadline 100 + 50 - 42 =
-- 108) or below it (round 49 s, turn at 110: deadline 107). Both record
-- lost / instability, never lost / clock. The round was alive before.
function OutcomeContract.instabilityMaxAndTheClockInOneTurnRecordInstability(P: Procedure)
	need(P, "deadline")
	local w = OutcomeContract.world()
	local penalty = w.tuning.actuation.instability_clock_penalty_seconds
	local t0 = OutcomeContract.NOW
	local problems: { string } = {}
	for _, c in
		{
			{
				roundSeconds = 50,
				finalNow = 108,
				label = "the penalty takes the clock to exactly 0",
			},
			{ roundSeconds = 49, finalNow = 110, label = "the penalty takes the clock below 0" },
		}
	do
		local five = fivePointsThen(P, w, c.roundSeconds, "AC-6")
		local before = P.deadline(five)
		if before <= c.finalNow then
			table.insert(
				problems,
				`{c.label}: precondition - at five points the deadline is {before}, which the final turn at {c.finalNow} has already passed; the scenario must reach the max and the clock in ONE turn`
			)
		end
		if five.outcome ~= nil then
			table.insert(
				problems,
				`{c.label}: at five points the outcome is {Deep.show(five.outcome)}, expected nil`
			)
		end
		local after = t0 + c.roundSeconds - 6 * penalty
		if after > c.finalNow then
			table.insert(
				problems,
				`{c.label}: precondition - after six points the deadline would be {after} > {c.finalNow}; the clock would not be out`
			)
		end
		local lost, result =
			turnBy(P, w, five, 14, Turn.wrongSetting(w.facility, 14, w.tuning), c.finalNow)
		if
			not Deep.equal(result, { kind = "rejected", machineId = 14, reason = "wrong_setting" })
		then
			table.insert(
				problems,
				`{c.label}: the sixth turn returned {Deep.show(result)}, expected rejected / wrong_setting`
			)
		end
		if lost.instability ~= 6 then
			table.insert(
				problems,
				`{c.label}: instability is {Deep.show(lost.instability)}, expected 6`
			)
		end
		if P.deadline(lost) ~= after then
			table.insert(
				problems,
				`{c.label}: deadline after the sixth point is {Deep.show(P.deadline(lost))}, expected {after}`
			)
		end
		if not Deep.equal(lost.outcome, LOST_INSTABILITY) then
			table.insert(
				problems,
				`{c.label}: state.outcome is {Deep.show(lost.outcome)}, expected {Deep.show(
					LOST_INSTABILITY
				)} - instability resolves before the clock (mechanics.md §5, same-tick ordering)`
			)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-6/I-6: a wrong turn that reaches instability_max and zeroes the clock records lost / instability:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- Time alone: tick just before the deadline changes nothing; at exactly the
-- deadline (I-3, >=) it is lost / clock, with tick's second value equal to
-- state.outcome (I-8); after a penalty the deadline has moved and the same
-- holds at the new instant; a turn arriving at the deadline on an undecided
-- round is refused / round_over on a state that is lost / clock and
-- otherwise unchanged (I-6 step 3, I-7).
function OutcomeContract.theDeadlinePassingByTimeAloneIsLostClockAtExactlyTheDeadline(P: Procedure)
	need(P, "deadline")
	local w = OutcomeContract.world()
	local t0 = OutcomeContract.NOW
	local deadline = t0 + OutcomeContract.ROUND_SECONDS
	local problems: { string } = {}
	local state = started(P, w)
	local before, beforeOutcome = P.tick(state, w.assignment, deadline - 0.001, NOBODY)
	if not Deep.equal(before, state) or beforeOutcome ~= nil then
		table.insert(
			problems,
			`tick at deadline - 0.001 returned {Deep.show(beforeOutcome)} and a state that differs from the one passed:\n{Deep.diff(
				state,
				before
			)}`
		)
	end
	local at, atOutcome = P.tick(state, w.assignment, deadline, NOBODY)
	if not Deep.equal(atOutcome, LOST_CLOCK) or not Deep.equal(at.outcome, LOST_CLOCK) then
		table.insert(
			problems,
			`tick at EXACTLY the deadline ({deadline}) returned {Deep.show(atOutcome)} with state.outcome {Deep.show(
				at.outcome
			)}, expected {Deep.show(LOST_CLOCK)} twice (I-3: out at now >= deadline; I-8)`
		)
	end
	local expectedAt = Deep.copy(state)
	expectedAt.outcome = LOST_CLOCK
	if not Deep.equal(at, expectedAt) then
		table.insert(
			problems,
			`tick at the deadline changed more than the outcome:\n{Deep.diff(expectedAt, at)}`
		)
	end
	local late, lateOutcome = P.tick(state, w.assignment, deadline + 1000, NOBODY)
	if not Deep.equal(lateOutcome, LOST_CLOCK) or not Deep.equal(late.outcome, LOST_CLOCK) then
		table.insert(
			problems,
			`tick long after the deadline returned {Deep.show(lateOutcome)}, expected {Deep.show(
				LOST_CLOCK
			)}`
		)
	end
	-- After a penalty the instant moves with the deadline.
	local penalty = w.tuning.actuation.instability_clock_penalty_seconds
	local one = reject(P, w, state, 11, t0, "wrong_setting", "AC-6")
	local moved = deadline - penalty
	local stillOn = P.tick(one, w.assignment, moved - 0.001, NOBODY)
	if not Deep.equal(stillOn, one) then
		table.insert(
			problems,
			`after one point, tick at the moved deadline - 0.001 ({moved - 0.001}) changed the state:\n{Deep.diff(
				one,
				stillOn
			)}`
		)
	end
	local out, outOutcome = P.tick(one, w.assignment, moved, NOBODY)
	if not Deep.equal(outOutcome, LOST_CLOCK) then
		table.insert(
			problems,
			`after one point, tick at the moved deadline ({moved}) returned {Deep.show(outOutcome)}, expected {Deep.show(
				LOST_CLOCK
			)}`
		)
	end
	if not Deep.equal(out.outcome, LOST_CLOCK) then
		table.insert(
			problems,
			`after one point, tick at the moved deadline left state.outcome {Deep.show(out.outcome)}`
		)
	end
	-- A turn at the deadline on an undecided round.
	local turned, result = turnBy(P, w, state, 11, Turn.requiredSetting(w.facility, 11), deadline)
	if not Deep.equal(result, { kind = "refused", machineId = 11, reason = "round_over" }) then
		table.insert(
			problems,
			`a correct turn arriving at the deadline returned {Deep.show(result)}, expected refused / round_over (I-6 step 3, I-7)`
		)
	end
	if not Deep.equal(turned, expectedAt) then
		table.insert(
			problems,
			`a turn arriving at the deadline returned a state that is not the input plus lost / clock:\n{Deep.diff(
				expectedAt,
				turned
			)}`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-6/I-3: the deadline passing by time alone is lost / clock, at exactly now >= deadline:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- Under the shipped tuning (max 5, threshold 2, one room per crossing, 20 s
-- per point, round 420): five wrong turns at 100..104 lose by instability
-- with the clock still at 320 s, one room dark after the second and a
-- second after the fourth, no third at the fifth.
function OutcomeContract.underTheShippedTuningFiveWrongTurnsLoseByInstabilityWithTwoRoomsDark(
	P: Procedure
)
	for _, name in { "deadline", "isDark" } do
		need(P, name)
	end
	local w = OutcomeContract.shippedWorld()
	local t0 = OutcomeContract.NOW
	local problems: { string } = {}
	local state = started(P, w, Tuning.round.round_seconds)
	local sequence = { 11, 14, 18, 19, 11 }
	local reasons = { "wrong_setting", "wrong_setting", "not_live", "not_live", "wrong_setting" }
	local wantDark = { 0, 1, 1, 2, 2 }
	for k, id in sequence do
		local now = t0 + k - 1
		local next_, result = turnBy(
			P,
			w,
			state,
			id,
			if reasons[k] == "wrong_setting"
				then Turn.wrongSetting(w.facility, id, w.tuning)
				else Turn.requiredSetting(w.facility, id),
			now
		)
		if not Deep.equal(result, { kind = "rejected", machineId = id, reason = reasons[k] }) then
			table.insert(
				problems,
				`turn {k} on {id} at {now} returned {Deep.show(result)}, expected rejected / {reasons[k]}`
			)
		end
		state = next_
		if state.instability ~= k then
			table.insert(
				problems,
				`after turn {k} instability is {Deep.show(state.instability)}, expected {k}`
			)
		end
		local dark = OutcomeContract.darkRooms(state)
		if #dark ~= wantDark[k] then
			table.insert(
				problems,
				`after turn {k} (instability {k}) {#dark} room(s) are dark ({Deep.show(dark)}), expected {wantDark[k]} (threshold 2, one room per crossing, none at the max)`
			)
		end
		if k < 5 and state.outcome ~= nil then
			table.insert(
				problems,
				`after turn {k} the outcome is {Deep.show(state.outcome)}, expected nil`
			)
		end
	end
	if not Deep.equal(state.outcome, LOST_INSTABILITY) then
		table.insert(
			problems,
			`after five wrong turns state.outcome is {Deep.show(state.outcome)}, expected {Deep.show(
				LOST_INSTABILITY
			)} (instability_max 5)`
		)
	end
	if P.deadline(state) ~= t0 + 420 - 100 then
		table.insert(
			problems,
			`the deadline after five points is {Deep.show(P.deadline(state))}, expected {t0 + 420 - 100} - the clock was not out; the loss is instability's alone`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-6 under the SHIPPED tuning (instability_max 5, threshold 2, 1 room per crossing, 20 s per point, round 420 s):\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- Expiry by tick is a charge like any other (I-6 step 2): it moves the clock,
-- crosses the threshold (two rooms dark, via tick), and at the max it ends
-- the round - tick's second value and state.outcome both lost / instability.
function OutcomeContract.tickExpiryChargesTheClockCrossesTheThresholdAndCanEndTheRound(P: Procedure)
	for _, name in { "deadline", "isDark", "blackoutWeights", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.world()
	local a = w.tuning.actuation
	local window = w.tuning.instance.simultaneous_window_seconds
	local reset = a.actuation_reset_seconds
	local A, B = Finale.A, Finale.B
	local problems: { string } = {}
	local live = liveFinale(P, w, started(P, w), "I-6")
	-- Two wrong finale turns (no window open: ordinary rejections, +1 each).
	local t = Finale.T_ARM
	local two = reject(P, w, live, A, t, "wrong_setting", "I-6")
	two = reject(P, w, two, B, t + 1, "wrong_setting", "I-6")
	local weights = P.blackoutWeights(two)
	-- With every ordinary step committed only the finale rooms weigh anything.
	local wantWeights =
		{ [1] = 0, [2] = a.blackout_weight_live_step, [3] = 0, [4] = a.blackout_weight_live_step }
	if not Deep.equal(weights, wantWeights) then
		table.insert(
			problems,
			`blackoutWeights with the finale live is {Deep.show(weights)}, expected {Deep.show(
				wantWeights
			)}`
		)
	end
	local armed = arm(P, w, two, A, t + reset, "I-6")
	local tickAt = t + reset + window + 0.001
	local expired, second = P.tick(armed, w.assignment, tickAt, NOBODY)
	if second ~= nil or expired.outcome ~= nil then
		table.insert(
			problems,
			`the first expiry tick returned {Deep.show(second)}, expected nil (instability 3 of 6)`
		)
	end
	if expired.instability ~= 3 then
		table.insert(
			problems,
			`after the expiry instability is {Deep.show(expired.instability)}, expected 2 + failed pair 1 = 3`
		)
	end
	local wantDeadline = OutcomeContract.NOW
		+ OutcomeContract.ROUND_SECONDS
		- 3 * a.instability_clock_penalty_seconds
	if P.deadline(expired) ~= wantDeadline then
		table.insert(
			problems,
			`after the expiry the deadline is {Deep.show(P.deadline(expired))}, expected {wantDeadline} (3 points x {a.instability_clock_penalty_seconds})`
		)
	end
	local predicted = OutcomeContract.predictDraws(
		P,
		wantWeights,
		OutcomeContract.blackoutStream(OutcomeContract.ROUND_SEED),
		2
	)
	table.sort(predicted)
	expectDark(
		P,
		expired,
		predicted,
		2,
		OutcomeContract.ROOMS,
		"after the expiry crossed 3",
		problems
	)
	-- To the max by the same path: 3 -> 5 by two wrong finale turns, then an
	-- armed window left to expire -> 6.
	local u = tickAt + reset
	local five = reject(P, w, expired, A, u, "wrong_setting", "I-6")
	five = reject(P, w, five, B, u + 1, "wrong_setting", "I-6")
	local armedAgain = arm(P, w, five, A, u + reset, "I-6")
	local lost, lostOutcome = P.tick(armedAgain, w.assignment, u + reset + window + 0.001, NOBODY)
	if
		not Deep.equal(lostOutcome, LOST_INSTABILITY)
		or not Deep.equal(lost.outcome, LOST_INSTABILITY)
	then
		table.insert(
			problems,
			`the expiry that reaches the max returned {Deep.show(lostOutcome)} with state.outcome {Deep.show(
				lost.outcome
			)}, expected {Deep.show(LOST_INSTABILITY)} twice`
		)
	end
	if lost.instability ~= 6 or lost.armed ~= nil then
		table.insert(
			problems,
			`after the final expiry instability is {Deep.show(lost.instability)} and armed {Deep.show(
				lost.armed
			)}, expected 6 and nil`
		)
	end
	expectDark(
		P,
		lost,
		predicted,
		2,
		OutcomeContract.ROOMS,
		"at the max by expiry (no blackout at the max)",
		problems
	)
	if #problems > 0 then
		Contract.fail(
			`I-6 step 2: an expired window charges through the clock, the crossing and the outcome like any other point:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-7. A decided round stays decided (I-6 step 1, I-7).
     --------------------------------------------------------------------- ]]

-- The three decided states: won (finale completed), lost / instability (six
-- points), lost / clock (a tick at the deadline with A armed, so the window
-- is still open on the decided state).
local function decidedStates(
	P: Procedure,
	w: World,
	label: string
): { { name: string, state: any, outcome: any } }
	local t0 = OutcomeContract.NOW
	local A, B = Finale.A, Finale.B
	local live = liveFinale(P, w, started(P, w), label)
	local armed = arm(P, w, live, A, Finale.T_ARM, label)
	local won = turnBy(P, w, armed, B, Turn.requiredSetting(w.facility, B), Finale.T_ARM + 1)
	local five = fivePointsThen(P, w, OutcomeContract.ROUND_SECONDS, label)
	local lostInstability =
		turnBy(P, w, five, 14, Turn.wrongSetting(w.facility, 14, w.tuning), t0 + 6)
	local deadline = t0 + OutcomeContract.ROUND_SECONDS
	local armedLate = arm(P, w, liveFinale(P, w, started(P, w), label), A, deadline - 1, label)
	-- Half a second past the deadline, not AT it: this check is about the
	-- guard, and the exact instant is I-3's own check's business.
	local lostClock = P.tick(armedLate, w.assignment, deadline + 0.5, NOBODY)
	return {
		{ name = "won", state = won, outcome = WON },
		{ name = "lost / instability", state = lostInstability, outcome = LOST_INSTABILITY },
		{ name = "lost / clock (with A still armed)", state = lostClock, outcome = LOST_CLOCK },
	}
end

function OutcomeContract.aDecidedRoundStaysDecided(P: Procedure)
	local w = OutcomeContract.world()
	local t0 = OutcomeContract.NOW
	local far = t0 + OutcomeContract.ROUND_SECONDS + 500
	local problems: { string } = {}
	for _, d in decidedStates(P, w, "AC-7") do
		if not Deep.equal(d.state.outcome, d.outcome) then
			table.insert(
				problems,
				`{d.name}: precondition - state.outcome is {Deep.show(d.state.outcome)}, expected {Deep.show(
					d.outcome
				)}`
			)
			continue
		end
		local snapshot = Deep.copy(d.state)
		local turns = {
			{
				label = "a wrong turn on live machine 11",
				player = "kim",
				id = 11,
				setting = Turn.wrongSetting(w.facility, 11, w.tuning),
			},
			{
				label = "a correct turn on 11",
				player = "kim",
				id = 11,
				setting = Turn.requiredSetting(w.facility, 11),
			},
			{
				label = "a correct turn on decoy 18",
				player = "amy",
				id = 18,
				setting = Turn.requiredSetting(w.facility, 18),
			},
			{
				label = "a turn on finale B by its holder",
				player = "bob",
				id = Finale.B,
				setting = Turn.requiredSetting(w.facility, Finale.B),
			},
			{
				label = `a turn on unknown machine {Turn.UNKNOWN_ID}`,
				player = "kim",
				id = Turn.UNKNOWN_ID,
				setting = 1,
			},
			{
				label = "a non-holder's turn on 11",
				player = "zed",
				id = 11,
				setting = Turn.requiredSetting(w.facility, 11),
			},
		}
		for _, c in turns do
			for _, now in { far, far + 100 } do
				local positions = if c.id == Turn.UNKNOWN_ID
					then Turn.standingAt(w, c.player, 11)
					else Turn.standingAt(w, c.player, c.id)
				local state, result =
					P.turn(d.state, w.assignment, c.player, c.id, c.setting, now, positions)
				if
					not Deep.equal(
						result,
						{ kind = "refused", machineId = c.id, reason = "round_over" }
					)
				then
					table.insert(
						problems,
						`{d.name}: {c.label} at {now} returned {Deep.show(result)}, expected \{ kind = "refused", machineId = {c.id}, reason = "round_over" }`
					)
				end
				if not Deep.equal(state, snapshot) then
					table.insert(
						problems,
						`{d.name}: {c.label} at {now} returned a state that differs from the decided one:\n{Deep.diff(
							snapshot,
							state
						)}`
					)
				end
			end
		end
		for _, now in { t0 + 1, far, far + 1000 } do
			local state, outcome = P.tick(d.state, w.assignment, now, NOBODY)
			if not Deep.equal(outcome, d.outcome) then
				table.insert(
					problems,
					`{d.name}: tick at {now} returned {Deep.show(outcome)}, expected {Deep.show(
						d.outcome
					)}`
				)
			end
			if not Deep.equal(state, snapshot) then
				table.insert(
					problems,
					`{d.name}: tick at {now} returned a state that differs from the decided one:\n{Deep.diff(
						snapshot,
						state
					)}`
				)
			end
		end
		if not Deep.equal(d.state, snapshot) then
			table.insert(
				problems,
				`{d.name}: the decided state itself was mutated:\n{Deep.diff(snapshot, d.state)}`
			)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-7/I-7: once decided, every later turn is refused / round_over on a deep-equal state and every later tick returns the same outcome:\n{Contract.firstFew(
				problems,
				12
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-8. isDark for the rest of the round (I-9).
     --------------------------------------------------------------------- ]]

-- After the crossing at 3 the two dark rooms read true through commits, a
-- tick, an arming, a completion and the win; lit rooms and an unknown id
-- read false; `dark` never shrinks.
function OutcomeContract.isDarkIsTrueForTheRestOfTheRound(P: Procedure)
	for _, name in { "isDark", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.world()
	local t0 = OutcomeContract.NOW
	local A, B = Finale.A, Finale.B
	local problems: { string } = {}
	local state = reject(P, w, twoPoints(P, w, "AC-8"), 11, t0 + 5, "wrong_setting", "AC-8")
	local dark = OutcomeContract.darkRooms(state)
	if #dark ~= 2 then
		table.insert(
			problems,
			`precondition - after the crossing {Deep.show(dark)} are dark, expected two rooms`
		)
	end
	local darkSet = asSet(dark)
	local function expectStill(s: any, label: string)
		for _, room in OutcomeContract.ROOMS do
			local want = darkSet[room] == true
			if P.isDark(s, room) ~= want then
				table.insert(
					problems,
					`{label}: isDark({room}) is {Deep.show(P.isDark(s, room))}, expected {Deep.show(
						want
					)}`
				)
			end
		end
		if P.isDark(s, OutcomeContract.UNKNOWN_ROOM) ~= false then
			table.insert(
				problems,
				`{label}: isDark({OutcomeContract.UNKNOWN_ROOM}) is {Deep.show(
					P.isDark(s, OutcomeContract.UNKNOWN_ROOM)
				)}, expected false for an unknown room`
			)
		end
		if not Deep.equal(OutcomeContract.darkRooms(s), dark) then
			table.insert(
				problems,
				`{label}: the dark set is {Deep.show(OutcomeContract.darkRooms(s))}, expected still {Deep.show(
					dark
				)}`
			)
		end
	end
	expectStill(state, "right after the crossing")
	local t = t0 + 10
	for _, id in Finale.ORDINARY do
		t += 1
		state = commit(P, w, state, id, t, "AC-8")
		expectStill(state, `after committing {id}`)
	end
	state = P.tick(state, w.assignment, t + 1, NOBODY)
	expectStill(state, "after a tick")
	state = arm(P, w, state, A, t + 2, "AC-8")
	expectStill(state, "with A armed")
	state = turnBy(P, w, state, B, Turn.requiredSetting(w.facility, B), t + 3)
	expectStill(state, "after the finale committed (won)")
	if #problems > 0 then
		Contract.fail(
			`AC-8/I-9: a dark room stays dark for the rest of the round:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     I-10. Non-mutation.
     --------------------------------------------------------------------- ]]

function OutcomeContract.noOutcomeCallMutatesItsArguments(P: Procedure)
	for _, name in { "deadline", "isDark", "blackoutWeights", "drawRoom" } do
		need(P, name)
	end
	local w = OutcomeContract.world()
	local t0 = OutcomeContract.NOW
	local problems: { string } = {}
	local function guard(label: string, values: { [string]: any }, run: () -> ())
		local before: { [string]: any } = {}
		for name, v in pairs(values) do
			before[name] = Deep.copy(v)
		end
		run()
		for name, v in pairs(values) do
			if not Deep.equal(before[name], v) then
				table.insert(problems, `{label} mutated its {name}:\n{Deep.diff(before[name], v)}`)
			end
		end
	end
	local two = twoPoints(P, w, "I-10")
	guard("deadline", { state = two }, function()
		P.deadline(two)
	end)
	guard("isDark", { state = two }, function()
		for _, room in OutcomeContract.ROOMS do
			P.isDark(two, room)
		end
	end)
	guard("blackoutWeights", { state = two }, function()
		P.blackoutWeights(two)
	end)
	local weights = { [1] = 3, [2] = 0, [3] = 1 }
	guard("drawRoom", { weights = weights }, function()
		P.drawRoom(weights, OutcomeContract.blackoutStream(1))
	end)
	local at = Turn.standingAt(w, "kim", 11)
	local wrong = Turn.wrongSetting(w.facility, 11, w.tuning)
	local three: any = nil
	guard(
		"a crossing turn",
		{ state = two, assignment = w.assignment, positions = at, facility = w.facility },
		function()
			three = P.turn(two, w.assignment, "kim", 11, wrong, t0 + 5, at)
		end
	)
	guard(
		"a tick that ends the round by the clock",
		{ state = three, assignment = w.assignment },
		function()
			P.tick(three, w.assignment, t0 + 10000, NOBODY)
		end
	)
	local decided = P.tick(three, w.assignment, t0 + 10000, NOBODY)
	guard(
		"a round_over turn",
		{ state = decided, assignment = w.assignment, positions = at },
		function()
			P.turn(decided, w.assignment, "kim", 11, wrong, t0 + 10001, at)
		end
	)
	-- The crossing's new state shares no writable table with the old: darkening
	-- again downstream leaves `three` and `two` as they were.
	if three ~= nil then
		local snapshotThree = Deep.copy(three)
		local snapshotTwo = Deep.copy(two)
		local w2 = OutcomeContract.everyPointWorld()
		local s = started(P, w2)
		local s2 = reject(P, w2, s, 11, t0, "wrong_setting", "I-10")
		local snapshotS = Deep.copy(s)
		reject(P, w2, s2, 11, t0 + 6, "wrong_setting", "I-10")
		if not Deep.equal(snapshotS, s) then
			table.insert(
				problems,
				`a crossing two states downstream reached back into the start state:\n{Deep.diff(
					snapshotS,
					s
				)}`
			)
		end
		if not Deep.equal(snapshotThree, three) or not Deep.equal(snapshotTwo, two) then
			table.insert(problems, "the crossing's input or output changed after later calls")
		end
	end
	if #problems > 0 then
		Contract.fail(`I-10: an argument was mutated:\n{Contract.firstFew(problems, 8)}`)
	end
end

--[[ ------------------------------------------------------------------------
     The whole battery, named, so the controls can run every check against a
     stand-in and report exactly which ones fire.
     --------------------------------------------------------------------- ]]

export type Check = Turn.Check

OutcomeContract.CHECKS = {
	{
		name = "startCarriesTheRoundFieldsAndTheNewExportsAnswerInShape",
		ac = "Contract",
		run = OutcomeContract.startCarriesTheRoundFieldsAndTheNewExportsAnswerInShape,
	},
	{
		name = "deadlineIsStartPlusRoundSecondsLessThePenaltyPerPoint",
		ac = "AC-1",
		run = OutcomeContract.deadlineIsStartPlusRoundSecondsLessThePenaltyPerPoint,
	},
	{
		name = "underTheShippedTuningTheDeadlineReadsLiterally",
		ac = "AC-1",
		run = OutcomeContract.underTheShippedTuningTheDeadlineReadsLiterally,
	},
	{
		name = "risingToJustBelowTheThresholdDarkensNothing",
		ac = "AC-2",
		run = OutcomeContract.risingToJustBelowTheThresholdDarkensNothing,
	},
	{
		name = "crossingTheThresholdDarkensExactlyRoomsPerThresholdByTheWeightedDraw",
		ac = "AC-2",
		run = OutcomeContract.crossingTheThresholdDarkensExactlyRoomsPerThresholdByTheWeightedDraw,
	},
	{
		name = "aChargeThatJumpsOverTheMultipleStillCrossesIt",
		ac = "AC-2",
		run = OutcomeContract.aChargeThatJumpsOverTheMultipleStillCrossesIt,
	},
	{
		name = "reachingInstabilityMaxEndsTheRoundWithoutAnotherBlackout",
		ac = "AC-2",
		run = OutcomeContract.reachingInstabilityMaxEndsTheRoundWithoutAnotherBlackout,
	},
	{
		name = "oneLitRoomHoldingEveryUncommittedStepIsAlwaysTheOneDarkened",
		ac = "AC-3",
		run = OutcomeContract.oneLitRoomHoldingEveryUncommittedStepIsAlwaysTheOneDarkened,
	},
	{
		name = "theHeavierOfTwoRoomsIsDrawnThreeTimesInFour",
		ac = "AC-3",
		run = OutcomeContract.theHeavierOfTwoRoomsIsDrawnThreeTimesInFour,
	},
	{
		name = "drawRoomMapsTheDrawToTheFirstRoomWhoseCumulativeWeightReachesIt",
		ac = "AC-3",
		run = OutcomeContract.drawRoomMapsTheDrawToTheFirstRoomWhoseCumulativeWeightReachesIt,
	},
	{
		name = "everyLitRoomAtWeightZeroStillDarkensOneAndNoneLitDoesNothing",
		ac = "AC-4",
		run = OutcomeContract.everyLitRoomAtWeightZeroStillDarkensOneAndNoneLitDoesNothing,
	},
	{
		name = "theSameSeedReplaysTheSameRoomsInTheSameOrder",
		ac = "AC-5",
		run = OutcomeContract.theSameSeedReplaysTheSameRoomsInTheSameOrder,
	},
	{
		name = "drawingFromTheBlackoutStreamMovesNoGeneratorDraw",
		ac = "AC-5",
		run = OutcomeContract.drawingFromTheBlackoutStreamMovesNoGeneratorDraw,
	},
	{
		name = "theLastFinaleCommitBeforeTheDeadlineWinsAndAtTheDeadlineItIsRoundOver",
		ac = "AC-6",
		run = OutcomeContract.theLastFinaleCommitBeforeTheDeadlineWinsAndAtTheDeadlineItIsRoundOver,
	},
	{
		name = "instabilityMaxAndTheClockInOneTurnRecordInstability",
		ac = "AC-6",
		run = OutcomeContract.instabilityMaxAndTheClockInOneTurnRecordInstability,
	},
	{
		name = "theDeadlinePassingByTimeAloneIsLostClockAtExactlyTheDeadline",
		ac = "AC-6",
		run = OutcomeContract.theDeadlinePassingByTimeAloneIsLostClockAtExactlyTheDeadline,
	},
	{
		name = "underTheShippedTuningFiveWrongTurnsLoseByInstabilityWithTwoRoomsDark",
		ac = "AC-6",
		run = OutcomeContract.underTheShippedTuningFiveWrongTurnsLoseByInstabilityWithTwoRoomsDark,
	},
	{
		name = "tickExpiryChargesTheClockCrossesTheThresholdAndCanEndTheRound",
		ac = "I-6",
		run = OutcomeContract.tickExpiryChargesTheClockCrossesTheThresholdAndCanEndTheRound,
	},
	{
		name = "aDecidedRoundStaysDecided",
		ac = "AC-7",
		run = OutcomeContract.aDecidedRoundStaysDecided,
	},
	{
		name = "isDarkIsTrueForTheRestOfTheRound",
		ac = "AC-8",
		run = OutcomeContract.isDarkIsTrueForTheRestOfTheRound,
	},
	{
		name = "noOutcomeCallMutatesItsArguments",
		ac = "I-10",
		run = OutcomeContract.noOutcomeCallMutatesItsArguments,
	},
} :: { Check }

-- Run every check against `P`; the names of those that raised, with their
-- messages, in CHECKS order.
function OutcomeContract.failures(P: Procedure): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in OutcomeContract.CHECKS do
		local ok, err = pcall(check.run, P)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return OutcomeContract
