--!strict
--[[
	PROC-001 AC-1 through AC-6 written once, as checks over a PROCEDURE MODULE
	rather than over `src/server/procedure/Procedure.luau` by name - the same
	arrangement as `RingContract.luau` and `ProcedureContract.luau` (which,
	despite its name, is GEN-003's Steps helper), and for the same reason.

	`tests/server/procedure_test.luau` applies these to the real module.
	`tests/server/procedure_controls_test.luau` applies them to a reference
	stand-in and to deliberately wrong stand-ins, so that in RED - where the
	production module does not exist, the real file fails at `require`, and not
	one assertion in it has executed - every check here has still been EXECUTED
	and observed to reject the implementation it exists to catch.

	A `procedure` here is anything with four plain field functions, called with
	a dot exactly as the story's Contract writes them:

	    P.start(facility, now, tuning)                     -> ProcedureState
	    P.isLive(state, machineId)                         -> boolean
	    P.dial(state, machineId, now)                      -> DialView
	    P.turn(state, assignment, playerId, machineId,
	           setting, now, positions)                    -> (ProcedureState, TurnResult)

	THE FIXTURE IS HAND-BUILT and depends on no generator sample and no rng
	seed. Four players in a ring whose σ is written down, four rooms on a 2 x 2
	block, nine machines whose ids are NOT their list indices (P-2: a machine is
	found by `id`), two tracks of UNEQUAL length (3 and 4, finale included), two
	decoys. `Steps.check` would reject this facility - and that is the point:
	`Procedure` reads `tracks` as P-2 says and runs no generator invariant.

	THE TUNING IS THE SHIPPED ONE WITH FOUR OVERRIDES, so that a constant read
	from the module instead of from `state.tuning` (P-1), or two constants that
	cannot be told apart (P-8), fail here: `turn_range_studs` 10 -> 7,
	`actuation_reset_seconds` 3 -> 5, `instability_per_wrong_value` stays 1,
	`instability_per_out_of_order` 1 -> 2. The controls file asserts each
	override differs from the shipped value it exists to be told apart from.

	THE ORACLE PARTITION IS HONOURED HERE. AC-1 to AC-5 are SETTLED by
	`mechanics.md` §3.2 and §5 (G12) and the Contract's P-1..P-11; every check
	reads the rule out and is named after it. AC-6 is mechanical. Nothing here
	invents a threshold.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Ring = require("../../src/server/seats/Ring")

local TurnContract = {}

export type Procedure = any
export type Vec = { x: number, y: number, z: number }
export type Tuning = typeof(MechanicsTuning)
export type Assignment = Ring.Assignment

--[[ ------------------------------------------------------------------------
     The fixture.
     --------------------------------------------------------------------- ]]

-- The base instant every scenario starts from. Not 0, so that `at = now` is
-- distinguishable from `at = 0` (an unset field) in the log.
TurnContract.NOW = 100

-- Seat order and the ring: kim -> zed -> amy -> bob -> kim. Class i at seat i,
-- lens = k(σ(p)). kim's SUPPLIER (σ⁻¹) is bob, which AC-5 relies on.
TurnContract.PLAYERS = { "kim", "zed", "amy", "bob" }
TurnContract.HOLDER = { [1] = "kim", [2] = "zed", [3] = "amy", [4] = "bob" }
TurnContract.SUPPLIER_OF_KIM = "bob"

-- A player who is seated nowhere: absent from `keyClasses` (P-5).
TurnContract.STRANGER = "noone"

-- Machine ids by role. Track 1 is three steps long, track 2 four; the last of
-- each is its finale step. 18 and 19 are in no track.
TurnContract.TRACK_1 = { 11, 12, 13 }
TurnContract.TRACK_2 = { 14, 15, 16, 17 }
TurnContract.FINALE = { 13, 17 }
TurnContract.DECOYS = { 18, 19 }
TurnContract.ALL_IDS = { 11, 12, 13, 14, 15, 16, 17, 18, 19 }
TurnContract.UNKNOWN_ID = 99

-- The machines, in a list order that puts no machine at the index equal to
-- its id. `requiredSetting` is the fixture's secret per machine.
local MACHINES = {
	{ id = 15, room = 3, slot = 1, keyClass = 1, tag = 2, requiredSetting = 1 },
	{ id = 11, room = 1, slot = 1, keyClass = 1, tag = 1, requiredSetting = 2 },
	{ id = 18, room = 4, slot = 2, keyClass = 3, tag = 2, requiredSetting = 2 },
	{ id = 14, room = 2, slot = 2, keyClass = 4, tag = 1, requiredSetting = 4 },
	{ id = 12, room = 1, slot = 2, keyClass = 2, tag = 1, requiredSetting = 3 },
	{ id = 19, room = 1, slot = 3, keyClass = 1, tag = 3, requiredSetting = 4 },
	{ id = 17, room = 4, slot = 1, keyClass = 4, tag = 2, requiredSetting = 3 },
	{ id = 13, room = 2, slot = 1, keyClass = 3, tag = 1, requiredSetting = 1 },
	{ id = 16, room = 3, slot = 2, keyClass = 2, tag = 2, requiredSetting = 2 },
}

-- A fresh facility every call, so a check that mutates one cannot leak into
-- the next and the non-mutation check compares against a true snapshot.
function TurnContract.facility(): any
	return {
		layout = {
			rooms = {
				{ id = 1, column = 1, row = 1 },
				{ id = 2, column = 2, row = 1 },
				{ id = 3, column = 1, row = 2 },
				{ id = 4, column = 2, row = 2 },
			},
			doors = { { a = 1, b = 2 }, { a = 1, b = 3 }, { a = 2, b = 4 }, { a = 3, b = 4 } },
			spawnRoom = 1,
		},
		placement = {
			machines = Deep.copy(MACHINES),
			stepsPerClass = { [1] = 2, [2] = 2, [3] = 1, [4] = 2 },
		},
		steps = {
			tracks = { Deep.copy(TurnContract.TRACK_1), Deep.copy(TurnContract.TRACK_2) },
			finale = Deep.copy(TurnContract.FINALE),
		},
		spawnRoom = 1,
		par = 60,
		attempt = 1,
	}
end

-- The ring as dealt, fresh every call. `Ring.withdraw` accepts it as it
-- stands: it reads `players`, `sigma`, `keyClasses` and `lens` and no more.
function TurnContract.assignment(): Assignment
	return {
		players = table.clone(TurnContract.PLAYERS),
		sigma = { kim = "zed", zed = "amy", amy = "bob", bob = "kim" },
		keyClasses = { kim = { 1 }, zed = { 2 }, amy = { 3 }, bob = { 4 } },
		lens = { kim = 2, zed = 3, amy = 4, bob = 1 },
	}
end

-- The overrides, named once. The controls file checks each differs from the
-- shipped value where the difference is what a check relies on.
TurnContract.OVERRIDES = {
	instance = { turn_range_studs = 7 },
	actuation = {
		actuation_reset_seconds = 5,
		instability_per_wrong_value = 1,
		instability_per_out_of_order = 2,
	},
}

-- The shipped tuning with the overrides applied, frozen like the module.
function TurnContract.tuning(): Tuning
	local fake: any = Deep.copy(MechanicsTuning)
	for tableName, keys in pairs(TurnContract.OVERRIDES) do
		for key, value in pairs(keys) do
			fake[tableName][key] = value
		end
	end
	fake.instance = table.freeze(fake.instance)
	fake.channel = table.freeze(fake.channel)
	fake.actuation = table.freeze(fake.actuation)
	return table.freeze(fake) :: Tuning
end

export type World = { facility: any, assignment: Assignment, tuning: Tuning }

function TurnContract.world(): World
	return {
		facility = TurnContract.facility(),
		assignment = TurnContract.assignment(),
		tuning = TurnContract.tuning(),
	}
end

-- The machine with this `id`, or nil: found by the `id` FIELD, as P-2 says.
function TurnContract.machine(facility: any, id: number): any
	for _, m in facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- The machine, which the fixture must have.
local function known(facility: any, id: number): any
	local m = TurnContract.machine(facility, id)
	assert(m ~= nil, `the fixture has no machine {id}`)
	return m
end

function TurnContract.requiredSetting(facility: any, id: number): number
	return known(facility, id).requiredSetting
end

-- A setting that is NOT the machine's required one, inside 1..dial_settings.
function TurnContract.wrongSetting(facility: any, id: number, tuning: Tuning): number
	local required = TurnContract.requiredSetting(facility, id)
	local wrong = if required == 1 then 2 else 1
	assert(wrong <= tuning.instance.dial_settings, "the fixture needs dial_settings >= 2")
	return wrong
end

-- The holder of the machine's key class, in the ring AS DEALT.
function TurnContract.holderOf(facility: any, id: number): string
	return TurnContract.HOLDER[known(facility, id).keyClass]
end

-- The machine's world position through the REAL `Machines.positionOf`, plus
-- an offset. Reach tests never hardcode geometry.
function TurnContract.at(w: World, id: number, dx: number?, dy: number?, dz: number?): Vec
	local m = known(w.facility, id)
	local p = Machines.positionOf(w.facility.layout, m, w.tuning)
	return { x = p.x + (dx or 0), y = p.y + (dy or 0), z = p.z + (dz or 0) }
end

-- `{ [player] = position }` with one player standing exactly at a machine.
function TurnContract.standingAt(w: World, player: string, id: number): { [string]: Vec }
	return { [player] = TurnContract.at(w, id) }
end

-- The live set: every id in `ids` for which `isLive` answers exactly `true`.
-- A non-boolean answer is reported rather than coerced.
function TurnContract.liveSet(P: Procedure, state: any, ids: { number }): { number }
	local live: { number } = {}
	for _, id in ids do
		local answer = P.isLive(state, id)
		if typeof(answer) ~= "boolean" then
			Contract.fail(
				`AC-1: isLive({id}) returned {typeof(answer)} {Deep.show(answer)}, not a boolean`
			)
		end
		if answer then
			table.insert(live, id)
		end
	end
	table.sort(live)
	return live
end

-- Every fixture id plus one the fixture does not have.
local function allIdsAndUnknown(): { number }
	local ids = table.clone(TurnContract.ALL_IDS)
	table.insert(ids, TurnContract.UNKNOWN_ID)
	return ids
end

local function started(P: Procedure, w: World): any
	return P.start(w.facility, TurnContract.NOW, w.tuning)
end

-- The holder, standing at the machine, turning it to its required setting at
-- `now`. The one call every "given a committed step" scenario is built from;
-- it fails loudly when the commit does not happen, so a later assertion is
-- never reached on a state that is not the one the scenario says.
local function commit(
	P: Procedure,
	w: World,
	state: any,
	id: number,
	now: number,
	label: string
): any
	local holder = TurnContract.holderOf(w.facility, id)
	local next_, result = P.turn(
		state,
		w.assignment,
		holder,
		id,
		TurnContract.requiredSetting(w.facility, id),
		now,
		TurnContract.standingAt(w, holder, id)
	)
	if not Deep.equal(result, { kind = "committed", machineId = id }) then
		Contract.fail(
			`{label}: setting up the scenario, {holder} turning live machine {id} to its required setting at {now} returned {Deep.show(
				result
			)}, expected \{ kind = "committed", machineId = {id} }`
		)
	end
	return next_
end

-- The holder, standing at the machine, turning it to a WRONG setting at `now`.
local function reject(
	P: Procedure,
	w: World,
	state: any,
	id: number,
	now: number,
	label: string
): (any, number)
	local holder = TurnContract.holderOf(w.facility, id)
	local wrong = TurnContract.wrongSetting(w.facility, id, w.tuning)
	local next_, result =
		P.turn(state, w.assignment, holder, id, wrong, now, TurnContract.standingAt(w, holder, id))
	if not Deep.equal(result, { kind = "rejected", machineId = id, reason = "wrong_setting" }) then
		Contract.fail(
			`{label}: setting up the scenario, {holder} turning live machine {id} to wrong setting {wrong} at {now} returned {Deep.show(
				result
			)}, expected \{ kind = "rejected", machineId = {id}, reason = "wrong_setting" }`
		)
	end
	return next_, wrong
end

--[[ ------------------------------------------------------------------------
     The Contract's state shape.
     --------------------------------------------------------------------- ]]

-- `start` returns the Contract's `ProcedureState`: the facility, nothing
-- committed, no dial, instability 0, an empty log, and the tuning it was
-- handed (P-1). Fields PROC-002/003 will add are not forbidden here.
function TurnContract.startReturnsTheContractState(P: Procedure)
	local w = TurnContract.world()
	local state = started(P, w)
	if typeof(state) ~= "table" then
		Contract.fail(`Contract: start returned {typeof(state)}`)
	end
	local problems: { string } = {}
	local function expect(field: string, want: any)
		if not Deep.equal(state[field], want) then
			table.insert(
				problems,
				`state.{field} is {Deep.show(state[field])}, expected {Deep.show(want)}`
			)
		end
	end
	expect("facility", w.facility)
	expect("committed", {})
	expect("dials", {})
	expect("instability", 0)
	expect("log", {})
	expect("tuning", w.tuning)
	if #problems > 0 then
		Contract.fail(
			`Contract: start does not return the ProcedureState the Contract names:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-1. Liveness (P-3).
     --------------------------------------------------------------------- ]]

-- At start exactly the first step of each track is live: not the finale
-- steps, not the decoys, not an unknown id.
function TurnContract.liveSetAtStartIsExactlyTheTrackHeads(P: Procedure)
	local w = TurnContract.world()
	local state = started(P, w)
	local live = TurnContract.liveSet(P, state, allIdsAndUnknown())
	local want = { TurnContract.TRACK_1[1], TurnContract.TRACK_2[1] }
	if not Deep.equal(live, want) then
		Contract.fail(
			`AC-1: at start the live set is {Deep.show(live)}, expected exactly the two track heads {Deep.show(
				want
			)} - finale steps {Deep.show(TurnContract.FINALE)}, decoys {Deep.show(
				TurnContract.DECOYS
			)} and unknown id {TurnContract.UNKNOWN_ID} must not be live`
		)
	end
end

-- After the first step of track 1 commits, the second step of track 1 is
-- live, the first is not, and track 2 is untouched.
function TurnContract.committingTheHeadOfTrackOneMakesItsSecondStepLive(P: Procedure)
	local w = TurnContract.world()
	local state = commit(P, w, started(P, w), TurnContract.TRACK_1[1], TurnContract.NOW, "AC-1")
	local live = TurnContract.liveSet(P, state, allIdsAndUnknown())
	local want = { TurnContract.TRACK_1[2], TurnContract.TRACK_2[1] }
	if not Deep.equal(live, want) then
		Contract.fail(
			`AC-1: after machine {TurnContract.TRACK_1[1]} committed the live set is {Deep.show(
				live
			)}, expected {Deep.show(want)} - the step behind the commit in ITS track, and the other track's head`
		)
	end
end

-- Tracks advance independently, and a finale step is never live in this
-- story: with every ordinary step of both tracks committed, nothing is live.
function TurnContract.tracksAdvanceIndependentlyAndFinaleStepsStayWaiting(P: Procedure)
	local w = TurnContract.world()
	local state = started(P, w)
	local t = TurnContract.NOW
	for _, id in { 11, 12 } do
		t += 1
		state = commit(P, w, state, id, t, "AC-1")
	end
	local live = TurnContract.liveSet(P, state, allIdsAndUnknown())
	if not Deep.equal(live, { TurnContract.TRACK_2[1] }) then
		Contract.fail(
			`AC-1: with track 1's ordinary steps committed and track 2 untouched the live set is {Deep.show(
				live
			)}, expected \{ {TurnContract.TRACK_2[1]} } - track 1's finale step {TurnContract.FINALE[1]} is waiting (finale_live_together), not live`
		)
	end
	for _, id in { 14, 15, 16 } do
		t += 1
		state = commit(P, w, state, id, t, "AC-1")
	end
	live = TurnContract.liveSet(P, state, allIdsAndUnknown())
	if not Deep.equal(live, {}) then
		Contract.fail(
			`AC-1: with every ordinary step of both tracks committed the live set is {Deep.show(
				live
			)}, expected \{} - finale steps are waiting in PROC-001 and go live only in PROC-002`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-2. A commit (P-4, P-7, P-9).
     --------------------------------------------------------------------- ]]

-- The holder, in reach, on the required setting: `committed`, the machine is
-- committed, its dial shows the committing setting as committed, the step
-- behind it is live, and instability is untouched.
function TurnContract.holderInReachOnTheRequiredSettingCommits(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local required = TurnContract.requiredSetting(w.facility, id)
	local state0 = started(P, w)
	local state, result = P.turn(
		state0,
		w.assignment,
		"kim",
		id,
		required,
		TurnContract.NOW,
		TurnContract.standingAt(w, "kim", id)
	)
	local problems: { string } = {}
	if not Deep.equal(result, { kind = "committed", machineId = id }) then
		table.insert(
			problems,
			`result is {Deep.show(result)}, expected \{ kind = "committed", machineId = {id} }`
		)
	end
	if state.committed[id] ~= true then
		table.insert(
			problems,
			`state.committed[{id}] is {Deep.show(state.committed[id])}, expected true`
		)
	end
	local view = P.dial(state, id, TurnContract.NOW)
	if not Deep.equal(view, { setting = required, state = "committed" }) then
		table.insert(
			problems,
			`dial({id}) is {Deep.show(view)}, expected \{ setting = {required}, state = "committed" }`
		)
	end
	local later = P.dial(state, id, TurnContract.NOW + 1000)
	if not Deep.equal(later, { setting = required, state = "committed" }) then
		table.insert(
			problems,
			`dial({id}) 1000 s later is {Deep.show(later)}; a committed dial does not reset`
		)
	end
	if P.isLive(state, id) ~= false then
		table.insert(
			problems,
			`isLive({id}) is still {Deep.show(P.isLive(state, id))} after the commit`
		)
	end
	if P.isLive(state, TurnContract.TRACK_1[2]) ~= true then
		table.insert(
			problems,
			`isLive({TurnContract.TRACK_1[2]}) is {Deep.show(P.isLive(state, 12))}; the step behind the commit must be live`
		)
	end
	if state.instability ~= 0 then
		table.insert(
			problems,
			`instability is {Deep.show(state.instability)} after a commit, expected 0`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-2: kim turning live machine {id} to {required} in reach did not commit it cleanly:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- P-4: reach is inclusive at exactly `turn_range_studs`, horizontally, and
-- `y` is ignored. The range is the FIXTURE's (7), not the shipped 10.
function TurnContract.reachIsInclusiveAtTurnRangeStudsAndIgnoresY(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local required = TurnContract.requiredSetting(w.facility, id)
	local range = w.tuning.instance.turn_range_studs
	local cases = {
		{
			label = `exactly turn_range_studs ({range}) along x`,
			pos = TurnContract.at(w, id, range, 0, 0),
		},
		{
			label = `exactly turn_range_studs ({range}) along -z`,
			pos = TurnContract.at(w, id, 0, 0, -range),
		},
		{
			label = "1000 studs above the machine, horizontally on it",
			pos = TurnContract.at(w, id, 0, 1000, 0),
		},
		{
			label = `1000 studs below, {range} along x`,
			pos = TurnContract.at(w, id, range, -1000, 0),
		},
	}
	local problems: { string } = {}
	for _, case in cases do
		local state, result = P.turn(
			started(P, w),
			w.assignment,
			"kim",
			id,
			required,
			TurnContract.NOW,
			{ kim = case.pos }
		)
		if not Deep.equal(result, { kind = "committed", machineId = id }) then
			table.insert(problems, `{case.label}: {Deep.show(result)}`)
		elseif state.committed[id] ~= true then
			table.insert(
				problems,
				`{case.label}: committed but state.committed[{id}] is {Deep.show(
					state.committed[id]
				)}`
			)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-2/P-4: the holder is IN reach (<= turn_range_studs horizontally, y ignored) and the turn must commit, but:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-3. Rejections (P-6, P-8).
     --------------------------------------------------------------------- ]]

-- The common shape of a rejection: the result, the charge, the dial, and
-- that nothing committed and the live set did not move.
local function expectRejection(
	P: Procedure,
	w: World,
	label: string,
	state0: any,
	player: string,
	id: number,
	setting: number,
	now: number,
	reason: string,
	charge: number
)
	local state, result = P.turn(
		state0,
		w.assignment,
		player,
		id,
		setting,
		now,
		TurnContract.standingAt(w, player, id)
	)
	local problems: { string } = {}
	if not Deep.equal(result, { kind = "rejected", machineId = id, reason = reason }) then
		table.insert(
			problems,
			`result is {Deep.show(result)}, expected \{ kind = "rejected", machineId = {id}, reason = "{reason}" }`
		)
	end
	if state.instability ~= state0.instability + charge then
		table.insert(
			problems,
			`instability went {state0.instability} -> {Deep.show(state.instability)}, expected +{charge} (the {reason} constant)`
		)
	end
	if state.committed[id] then
		table.insert(
			problems,
			`state.committed[{id}] is {Deep.show(state.committed[id])} after a rejection`
		)
	end
	local reset = w.tuning.actuation.actuation_reset_seconds
	if not Deep.equal(state.dials[id], { setting = setting, rejectedUntil = now + reset }) then
		table.insert(
			problems,
			`state.dials[{id}] is {Deep.show(state.dials[id])}, expected \{ setting = {setting}, rejectedUntil = {now + reset} } (P-6)`
		)
	end
	local view = P.dial(state, id, now)
	if not Deep.equal(view, { setting = setting, state = "rejected" }) then
		table.insert(
			problems,
			`dial({id}) at {now} is {Deep.show(view)}, expected \{ setting = {setting}, state = "rejected" }`
		)
	end
	local before = TurnContract.liveSet(P, state0, TurnContract.ALL_IDS)
	local after = TurnContract.liveSet(P, state, TurnContract.ALL_IDS)
	if not Deep.equal(before, after) then
		table.insert(
			problems,
			`the live set moved {Deep.show(before)} -> {Deep.show(after)} on a rejection`
		)
	end
	if #problems > 0 then
		Contract.fail(`AC-3: {label}:\n{Contract.firstFew(problems, 8)}`)
	end
end

-- A live step turned to the wrong setting: `rejected / wrong_setting`,
-- charged `instability_per_wrong_value` (1 here, with out-of-order at 2).
function TurnContract.wrongSettingOnALiveStepIsRejectedAndChargesPerWrongValue(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local wrong = TurnContract.wrongSetting(w.facility, id, w.tuning)
	expectRejection(
		P,
		w,
		`kim turning LIVE machine {id} to wrong setting {wrong}`,
		started(P, w),
		"kim",
		id,
		wrong,
		TurnContract.NOW,
		"wrong_setting",
		w.tuning.actuation.instability_per_wrong_value
	)
end

-- A waiting step - the second of a track, or a finale step - is `not_live`
-- whatever the setting, and charged `instability_per_out_of_order` (2 here).
-- P-8: `not_live` wins when the setting is wrong as well.
function TurnContract.waitingStepIsNotLiveWhateverTheSetting(P: Procedure)
	local w = TurnContract.world()
	local charge = w.tuning.actuation.instability_per_out_of_order
	local second = TurnContract.TRACK_1[2]
	expectRejection(
		P,
		w,
		`zed turning WAITING machine {second} (track 1's second step) to its required setting`,
		started(P, w),
		"zed",
		second,
		TurnContract.requiredSetting(w.facility, second),
		TurnContract.NOW,
		"not_live",
		charge
	)
	expectRejection(
		P,
		w,
		`zed turning WAITING machine {second} to a wrong setting - not_live wins over wrong_setting (P-8)`,
		started(P, w),
		"zed",
		second,
		TurnContract.wrongSetting(w.facility, second, w.tuning),
		TurnContract.NOW,
		"not_live",
		charge
	)
	local finale = TurnContract.FINALE[1]
	expectRejection(
		P,
		w,
		`amy turning FINALE machine {finale} to its required setting while ordinary steps remain`,
		started(P, w),
		"amy",
		finale,
		TurnContract.requiredSetting(w.facility, finale),
		TurnContract.NOW,
		"not_live",
		charge
	)
	-- The finale stays waiting even when ITS track's ordinary steps are done.
	local state = started(P, w)
	state = commit(P, w, state, 11, TurnContract.NOW, "AC-3")
	state = commit(P, w, state, 12, TurnContract.NOW + 1, "AC-3")
	expectRejection(
		P,
		w,
		`amy turning FINALE machine {finale} to its required setting with track 1's ordinary steps committed but track 2's not`,
		state,
		"amy",
		finale,
		TurnContract.requiredSetting(w.facility, finale),
		TurnContract.NOW + 2,
		"not_live",
		charge
	)
end

-- A decoy is `not_live` whatever the setting, charged the out-of-order
-- constant. The decoy's holder is in reach, so nothing refuses first.
function TurnContract.decoyIsNotLiveWhateverTheSetting(P: Procedure)
	local w = TurnContract.world()
	local charge = w.tuning.actuation.instability_per_out_of_order
	local d1, d2 = TurnContract.DECOYS[1], TurnContract.DECOYS[2]
	expectRejection(
		P,
		w,
		`{TurnContract.holderOf(w.facility, d1)} turning DECOY {d1} to its own required setting`,
		started(P, w),
		TurnContract.holderOf(w.facility, d1),
		d1,
		TurnContract.requiredSetting(w.facility, d1),
		TurnContract.NOW,
		"not_live",
		charge
	)
	expectRejection(
		P,
		w,
		`{TurnContract.holderOf(w.facility, d2)} turning DECOY {d2} to a wrong setting`,
		started(P, w),
		TurnContract.holderOf(w.facility, d2),
		d2,
		TurnContract.wrongSetting(w.facility, d2, w.tuning),
		TurnContract.NOW,
		"not_live",
		charge
	)
end

-- Rejections accumulate: a wrong setting (1) then a decoy (2) is 3, and each
-- charge is the constant for ITS reason - a module that charges the same
-- constant for both reads 2 or 4.
function TurnContract.chargesAccumulateByReason(P: Procedure)
	local w = TurnContract.world()
	local a = w.tuning.actuation
	local state = started(P, w)
	state = reject(P, w, state, 11, TurnContract.NOW, "AC-3")
	local holder = TurnContract.holderOf(w.facility, 18)
	local state2, result = P.turn(
		state,
		w.assignment,
		holder,
		18,
		TurnContract.requiredSetting(w.facility, 18),
		TurnContract.NOW + 1,
		TurnContract.standingAt(w, holder, 18)
	)
	local want = a.instability_per_wrong_value + a.instability_per_out_of_order
	if
		not Deep.equal(result, { kind = "rejected", machineId = 18, reason = "not_live" })
		or state2.instability ~= want
	then
		Contract.fail(
			`AC-3: a wrong_setting rejection then a not_live rejection left instability at {Deep.show(
				state2.instability
			)} with the second result {Deep.show(result)}; expected {a.instability_per_wrong_value} + {a.instability_per_out_of_order} = {want}`
		)
	end
end

-- P-6, the half-open window. Rejected at `now`: the dial shows the setting as
-- rejected at every t < now + reset, and unset at t = now + reset exactly. A
-- turn inside the window is refused `resetting`; a turn AT the boundary is
-- evaluated (and commits when the setting is right).
function TurnContract.rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local reset = w.tuning.actuation.actuation_reset_seconds
	local now = TurnContract.NOW
	local state, wrong = reject(P, w, started(P, w), id, now, "AC-3")
	local problems: { string } = {}
	local function expectDial(t: number, want: any, why: string)
		local view = P.dial(state, id, t)
		if not Deep.equal(view, want) then
			table.insert(
				problems,
				`dial({id}) at now + {t - now} is {Deep.show(view)}, expected {Deep.show(want)} ({why})`
			)
		end
	end
	expectDial(now, { setting = wrong, state = "rejected" }, "the instant of the rejection")
	expectDial(now + reset / 2, { setting = wrong, state = "rejected" }, "inside the window")
	expectDial(
		now + reset - 0.001,
		{ setting = wrong, state = "rejected" },
		"just before the boundary"
	)
	expectDial(
		now + reset,
		{ setting = nil, state = "unset" },
		"AT the boundary: t >= rejectedUntil is after (P-6)"
	)
	expectDial(now + reset + 100, { setting = nil, state = "unset" }, "long after")

	local required = TurnContract.requiredSetting(w.facility, id)
	local inside, insideResult = P.turn(
		state,
		w.assignment,
		"kim",
		id,
		required,
		now + reset - 0.001,
		TurnContract.standingAt(w, "kim", id)
	)
	if not Deep.equal(insideResult, { kind = "refused", machineId = id, reason = "resetting" }) then
		table.insert(
			problems,
			`a turn just before the boundary returned {Deep.show(insideResult)}, expected refused / resetting`
		)
	elseif not Deep.equal(inside, state) then
		table.insert(
			problems,
			`a refused turn returned a state that differs from the one passed:\n{Deep.diff(
				state,
				inside
			)}`
		)
	end
	local atBoundary, boundaryResult = P.turn(
		state,
		w.assignment,
		"kim",
		id,
		required,
		now + reset,
		TurnContract.standingAt(w, "kim", id)
	)
	if not Deep.equal(boundaryResult, { kind = "committed", machineId = id }) then
		table.insert(
			problems,
			`a turn AT the boundary (now + {reset}) returned {Deep.show(boundaryResult)}, expected it evaluated and committed`
		)
	elseif atBoundary.committed[id] ~= true then
		table.insert(
			problems,
			`the boundary turn said committed but state.committed[{id}] is {Deep.show(
				atBoundary.committed[id]
			)}`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-3/P-6: the reset window after a rejection at {now} with actuation_reset_seconds = {reset} is not half-open [now, now + reset):\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-4. Refusals (P-5, P-9).
     --------------------------------------------------------------------- ]]

-- Everything a refusal must and must not do, in one place: the result, a
-- state deep-equal to the one passed (so instability, dials and log are
-- unchanged with it), and the dial view unchanged. Returns the message
-- fragments so an ordering test can collect them.
function TurnContract.refusalProblems(
	P: Procedure,
	w: World,
	label: string,
	state0: any,
	player: string,
	id: number,
	setting: number,
	now: number,
	positions: { [string]: Vec },
	reason: string
): { string }
	local exists = TurnContract.machine(w.facility, id) ~= nil
	local dialBefore = if exists then P.dial(state0, id, now) else nil
	local state, result = P.turn(state0, w.assignment, player, id, setting, now, positions)
	local problems: { string } = {}
	if not Deep.equal(result, { kind = "refused", machineId = id, reason = reason }) then
		table.insert(
			problems,
			`{label}: result is {Deep.show(result)}, expected \{ kind = "refused", machineId = {id}, reason = "{reason}" }`
		)
	end
	if not Deep.equal(state, state0) then
		table.insert(
			problems,
			`{label}: a refused turn must return a state deep-equal to the one passed (P-9), but:\n{Deep.diff(
				state0,
				state
			)}`
		)
	end
	if state.instability ~= state0.instability then
		table.insert(
			problems,
			`{label}: instability went {state0.instability} -> {Deep.show(state.instability)}; a refusal is never penalised`
		)
	end
	if #state.log ~= #state0.log then
		table.insert(
			problems,
			`{label}: the log grew from {#state0.log} to {#state.log} entries; a refusal is not logged (AC-6)`
		)
	end
	if exists then
		local dialAfter = P.dial(state, id, now)
		if not Deep.equal(dialBefore, dialAfter) then
			table.insert(
				problems,
				`{label}: dial({id}) went {Deep.show(dialBefore)} -> {Deep.show(dialAfter)}; a refusal does not touch the dial`
			)
		end
	end
	return problems
end

local function expectRefusal(
	P: Procedure,
	w: World,
	ac: string,
	label: string,
	state0: any,
	player: string,
	id: number,
	setting: number,
	now: number,
	positions: { [string]: Vec },
	reason: string
)
	local problems = TurnContract.refusalProblems(
		P,
		w,
		label,
		state0,
		player,
		id,
		setting,
		now,
		positions,
		reason
	)
	if #problems > 0 then
		Contract.fail(`{ac}: {reason} refusal:\n{Contract.firstFew(problems, 8)}`)
	end
end

function TurnContract.unknownMachineIsRefused(P: Procedure)
	local w = TurnContract.world()
	expectRefusal(
		P,
		w,
		"AC-4",
		`kim turning unknown machine {TurnContract.UNKNOWN_ID}`,
		started(P, w),
		"kim",
		TurnContract.UNKNOWN_ID,
		1,
		TurnContract.NOW,
		TurnContract.standingAt(w, "kim", 11),
		"unknown_machine"
	)
end

-- P-5. A seated player without the class, and a player absent from
-- `keyClasses` altogether. Both stand at the machine with the right setting,
-- so only the key check can refuse them - and nothing may be charged.
function TurnContract.nonHolderIsRefusedAndNotCharged(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local required = TurnContract.requiredSetting(w.facility, id)
	expectRefusal(
		P,
		w,
		"AC-4",
		`zed (class 2) turning live class-1 machine {id} in reach on the required setting`,
		started(P, w),
		"zed",
		id,
		required,
		TurnContract.NOW,
		TurnContract.standingAt(w, "zed", id),
		"not_key_holder"
	)
	expectRefusal(
		P,
		w,
		"AC-4",
		`{TurnContract.STRANGER} (absent from keyClasses) turning live machine {id} in reach on the required setting`,
		started(P, w),
		TurnContract.STRANGER,
		id,
		required,
		TurnContract.NOW,
		TurnContract.standingAt(w, TurnContract.STRANGER, id),
		"not_key_holder"
	)
	-- The same non-holder on a wrong setting: still a refusal, not a rejection.
	expectRefusal(
		P,
		w,
		"AC-4",
		`zed turning live class-1 machine {id} in reach on a WRONG setting - refused, not rejected`,
		started(P, w),
		"zed",
		id,
		TurnContract.wrongSetting(w.facility, id, w.tuning),
		TurnContract.NOW,
		TurnContract.standingAt(w, "zed", id),
		"not_key_holder"
	)
end

-- P-4's other side: just past the range horizontally, far on the diagonal,
-- and no accepted position at all.
function TurnContract.holderOutOfHorizontalReachOrWithoutAPositionIsRefused(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local required = TurnContract.requiredSetting(w.facility, id)
	local range = w.tuning.instance.turn_range_studs
	local cases = {
		{
			label = `kim {range + 0.001} studs along x (just past turn_range_studs)`,
			positions = { kim = TurnContract.at(w, id, range + 0.001, 0, 0) },
		},
		{
			label = `kim {range} along x AND {range} along z (sqrt(2) x range away)`,
			positions = { kim = TurnContract.at(w, id, range, 0, range) },
		},
		{
			label = `kim {range} along z and 0.5 along x`,
			positions = { kim = TurnContract.at(w, id, 0.5, 0, range) },
		},
		{ label = "kim with no accepted position (positions = {})", positions = {} },
		{
			label = "kim with no accepted position while zed has one at the machine",
			positions = { zed = TurnContract.at(w, id) },
		},
		{
			label = "kim at machine 17's position, rooms away",
			positions = { kim = TurnContract.at(w, 17) },
		},
	}
	local problems: { string } = {}
	for _, case in cases do
		for _, p in
			TurnContract.refusalProblems(
				P,
				w,
				case.label,
				started(P, w),
				"kim",
				id,
				required,
				TurnContract.NOW,
				case.positions,
				"out_of_reach"
			)
		do
			table.insert(problems, p)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-4: out_of_reach refusal (turn_range_studs = {range}, horizontal, no position = out of reach):\n{Contract.firstFew(
				problems,
				12
			)}`
		)
	end
end

function TurnContract.committedMachineIsRefused(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local state = commit(P, w, started(P, w), id, TurnContract.NOW, "AC-4")
	expectRefusal(
		P,
		w,
		"AC-4",
		`kim turning COMMITTED machine {id} again on its required setting`,
		state,
		"kim",
		id,
		TurnContract.requiredSetting(w.facility, id),
		TurnContract.NOW + 1,
		TurnContract.standingAt(w, "kim", id),
		"committed"
	)
	expectRefusal(
		P,
		w,
		"AC-4",
		`kim turning COMMITTED machine {id} on a wrong setting - refused, not rejected`,
		state,
		"kim",
		id,
		TurnContract.wrongSetting(w.facility, id, w.tuning),
		TurnContract.NOW + 1,
		TurnContract.standingAt(w, "kim", id),
		"committed"
	)
end

function TurnContract.resettingDialIsRefused(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local reset = w.tuning.actuation.actuation_reset_seconds
	local state = reject(P, w, started(P, w), id, TurnContract.NOW, "AC-4")
	for _, dt in { 0, reset / 2, reset - 0.001 } do
		expectRefusal(
			P,
			w,
			"AC-4",
			`kim turning machine {id} on its required setting {dt} s after a rejection (reset = {reset})`,
			state,
			"kim",
			id,
			TurnContract.requiredSetting(w.facility, id),
			TurnContract.NOW + dt,
			TurnContract.standingAt(w, "kim", id),
			"resetting"
		)
	end
end

-- The checks run unknown_machine, not_key_holder, out_of_reach, committed,
-- resetting, in that order, and the first failure wins. Each case below fails
-- two or three checks at once. (committed-before-resetting has no observable
-- case: a correct module cannot hold a commit inside a reset window.)
function TurnContract.refusalChecksRunInOrderAndTheFirstFailureWins(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local required = TurnContract.requiredSetting(w.facility, id)
	local range = w.tuning.instance.turn_range_studs
	local now = TurnContract.NOW
	local committedState = commit(P, w, started(P, w), id, now, "AC-4")
	local resettingState = reject(P, w, started(P, w), id, now, "AC-4")
	local far = { kim = TurnContract.at(w, id, range + 1, 0, 0) }
	local cases = {
		{
			label = "unknown id, by a stranger, with no position -> unknown_machine beats not_key_holder and out_of_reach",
			state = started(P, w),
			player = TurnContract.STRANGER,
			id = TurnContract.UNKNOWN_ID,
			positions = {},
			reason = "unknown_machine",
		},
		{
			label = `zed (non-holder), no position, on COMMITTED {id} -> not_key_holder beats out_of_reach and committed`,
			state = committedState,
			player = "zed",
			id = id,
			positions = {},
			reason = "not_key_holder",
		},
		{
			label = `kim out of reach on COMMITTED {id} -> out_of_reach beats committed`,
			state = committedState,
			player = "kim",
			id = id,
			positions = far,
			reason = "out_of_reach",
		},
		{
			label = `kim out of reach on RESETTING {id} -> out_of_reach beats resetting`,
			state = resettingState,
			player = "kim",
			id = id,
			positions = far,
			reason = "out_of_reach",
		},
		{
			label = `zed in reach on RESETTING {id} -> not_key_holder beats resetting`,
			state = resettingState,
			player = "zed",
			id = id,
			positions = TurnContract.standingAt(w, "zed", id),
			reason = "not_key_holder",
		},
		{
			label = `{TurnContract.STRANGER}, no position, on RESETTING {id} -> not_key_holder beats out_of_reach and resetting`,
			state = resettingState,
			player = TurnContract.STRANGER,
			id = id,
			positions = {},
			reason = "not_key_holder",
		},
	}
	local problems: { string } = {}
	for _, c in cases do
		for _, p in
			TurnContract.refusalProblems(
				P,
				w,
				c.label,
				c.state,
				c.player,
				c.id,
				required,
				now + 1,
				c.positions,
				c.reason
			)
		do
			table.insert(problems, p)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-4: the refusal order unknown_machine > not_key_holder > out_of_reach > committed > resetting is not kept:\n{Contract.firstFew(
				problems,
				12
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-5. A transferred key class, through the real `Ring.withdraw`.
     --------------------------------------------------------------------- ]]

function TurnContract.supplierIsJudgedKeyHolderAfterWithdraw(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1] -- class 1, kim's
	local required = TurnContract.requiredSetting(w.facility, id)
	local supplier = TurnContract.SUPPLIER_OF_KIM
	-- Before the withdrawal the supplier is refused: the check below must be
	-- able to tell "judged as the holder" from "everybody is a holder".
	expectRefusal(
		P,
		w,
		"AC-5",
		`{supplier} turning class-1 machine {id} BEFORE kim leaves`,
		started(P, w),
		supplier,
		id,
		required,
		TurnContract.NOW,
		TurnContract.standingAt(w, supplier, id),
		"not_key_holder"
	)

	local withdrawn = Ring.withdraw(w.assignment, "kim")
	if not Deep.equal(withdrawn.keyClasses[supplier], { 4, 1 }) then
		Contract.fail(
			`AC-5 precondition: Ring.withdraw moved kim's class to {Deep.show(withdrawn.keyClasses)}; the fixture's σ puts kim's supplier at {supplier}, who should now hold \{ 4, 1 }`
		)
	end
	local w2: World = { facility = w.facility, assignment = withdrawn, tuning = w.tuning }
	local state, result = P.turn(
		started(P, w2),
		withdrawn,
		supplier,
		id,
		required,
		TurnContract.NOW + 1,
		TurnContract.standingAt(w2, supplier, id)
	)
	if
		not Deep.equal(result, { kind = "committed", machineId = id })
		or state.committed[id] ~= true
	then
		Contract.fail(
			`AC-5: after Ring.withdraw(kim) the supplier {supplier} holds classes {Deep.show(
				withdrawn.keyClasses[supplier]
			)} and turning class-1 machine {id} to its required setting in reach must commit, but returned {Deep.show(
				result
			)} with state.committed[{id}] = {Deep.show(state.committed[id])}`
		)
	end
	-- The leaver is gone from keyClasses, so the leaver is now a non-holder.
	expectRefusal(
		P,
		w2,
		"AC-5",
		`kim (withdrawn) turning class-1 machine {id} after leaving`,
		started(P, w2),
		"kim",
		id,
		required,
		TurnContract.NOW + 1,
		TurnContract.standingAt(w2, "kim", id),
		"not_key_holder"
	)
	-- And the supplier still holds their own class.
	local own = TurnContract.TRACK_2[1] -- class 4, bob's
	local state3, result3 = P.turn(
		started(P, w2),
		withdrawn,
		supplier,
		own,
		TurnContract.requiredSetting(w.facility, own),
		TurnContract.NOW + 1,
		TurnContract.standingAt(w2, supplier, own)
	)
	if
		not Deep.equal(result3, { kind = "committed", machineId = own })
		or state3.committed[own] ~= true
	then
		Contract.fail(
			`AC-5: after the transfer {supplier} turning their OWN class-4 machine {own} returned {Deep.show(
				result3
			)}, expected committed`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-6. The log (P-10), and P-11.
     --------------------------------------------------------------------- ]]

-- A mixed sequence: three evaluated turns interleaved with five refusals, in
-- call order. The log is exactly the three, with `at = now` of each.
function TurnContract.logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals(P: Procedure)
	local w = TurnContract.world()
	local f = w.facility
	local now = TurnContract.NOW
	local reset = w.tuning.actuation.actuation_reset_seconds
	local range = w.tuning.instance.turn_range_studs
	local state = started(P, w)
	if not Deep.equal(state.log, {}) then
		Contract.fail(`AC-6: start's log is {Deep.show(state.log)}, expected \{}`)
	end
	local expectedKinds: { string } = {}
	local function step(
		player: string,
		id: number,
		setting: number,
		at: number,
		positions: { [string]: Vec },
		wantKind: string
	)
		local next_, result = P.turn(state, w.assignment, player, id, setting, at, positions)
		if typeof(result) ~= "table" or result.kind ~= wantKind then
			Contract.fail(
				`AC-6: setting up the sequence, {player} on {id} at {at} returned {Deep.show(result)}, expected kind "{wantKind}"`
			)
		end
		table.insert(expectedKinds, wantKind)
		state = next_
	end
	step("kim", TurnContract.UNKNOWN_ID, 1, now, TurnContract.standingAt(w, "kim", 11), "refused")
	step(
		"kim",
		11,
		TurnContract.requiredSetting(f, 11),
		now + 1,
		TurnContract.standingAt(w, "kim", 11),
		"committed"
	)
	step(
		"amy",
		12,
		TurnContract.requiredSetting(f, 12),
		now + 2,
		TurnContract.standingAt(w, "amy", 12),
		"refused"
	)
	local wrong12 = TurnContract.wrongSetting(f, 12, w.tuning)
	step("zed", 12, wrong12, now + 3, TurnContract.standingAt(w, "zed", 12), "rejected")
	step(
		"amy",
		18,
		TurnContract.requiredSetting(f, 18),
		now + 4,
		TurnContract.standingAt(w, "amy", 18),
		"rejected"
	)
	step(
		"bob",
		14,
		TurnContract.requiredSetting(f, 14),
		now + 5,
		{ bob = TurnContract.at(w, 14, range + 1, 0, 0) },
		"refused"
	)
	assert(reset > 1, "the fixture's reset window must outlast the 1 s between steps")
	step(
		"zed",
		12,
		TurnContract.requiredSetting(f, 12),
		now + 3 + reset / 2,
		TurnContract.standingAt(w, "zed", 12),
		"refused"
	)
	step(
		"kim",
		11,
		TurnContract.requiredSetting(f, 11),
		now + 6,
		TurnContract.standingAt(w, "kim", 11),
		"refused"
	)

	local want = {
		{
			playerId = "kim",
			machineId = 11,
			setting = TurnContract.requiredSetting(f, 11),
			at = now + 1,
			result = "committed",
		},
		{
			playerId = "zed",
			machineId = 12,
			setting = wrong12,
			at = now + 3,
			result = "wrong_setting",
		},
		{
			playerId = "amy",
			machineId = 18,
			setting = TurnContract.requiredSetting(f, 18),
			at = now + 4,
			result = "not_live",
		},
	}
	if not Deep.equal(state.log, want) then
		Contract.fail(
			`AC-6: after the sequence {Deep.show(expectedKinds)} the log is {Deep.show(state.log)}, expected exactly one entry per EVALUATED turn in call order:\n{Deep.diff(
				want,
				state.log
			)}`
		)
	end
	local a = w.tuning.actuation
	local wantInstability = a.instability_per_wrong_value + a.instability_per_out_of_order
	if state.instability ~= wantInstability then
		Contract.fail(
			`AC-6: after the sequence instability is {Deep.show(state.instability)}, expected {wantInstability} (one wrong_setting, one not_live, five refusals charged nothing)`
		)
	end
end

-- P-11: the state, assignment, positions and facility handed to any function
-- deep-equal their snapshots afterwards - for start, isLive, dial and every
-- kind of turn.
function TurnContract.noCallMutatesItsArguments(P: Procedure)
	local w = TurnContract.world()
	local id = TurnContract.TRACK_1[1]
	local required = TurnContract.requiredSetting(w.facility, id)
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

	guard("start", { facility = w.facility, tuning = w.tuning }, function()
		P.start(w.facility, TurnContract.NOW, w.tuning)
	end)
	local state0 = started(P, w)
	guard("isLive", { state = state0 }, function()
		for _, mid in TurnContract.ALL_IDS do
			P.isLive(state0, mid)
		end
	end)
	guard("dial", { state = state0 }, function()
		P.dial(state0, id, TurnContract.NOW)
	end)

	local atMachine = TurnContract.standingAt(w, "kim", id)
	local committedState: any = nil
	guard(
		"a committing turn",
		{ state = state0, assignment = w.assignment, positions = atMachine, facility = w.facility },
		function()
			committedState =
				P.turn(state0, w.assignment, "kim", id, required, TurnContract.NOW, atMachine)
		end
	)
	local rejectedState: any = nil
	local wrong = TurnContract.wrongSetting(w.facility, id, w.tuning)
	guard(
		"a rejecting turn (wrong_setting)",
		{ state = state0, assignment = w.assignment, positions = atMachine },
		function()
			rejectedState =
				P.turn(state0, w.assignment, "kim", id, wrong, TurnContract.NOW, atMachine)
		end
	)
	local zedAt = TurnContract.standingAt(w, "zed", 12)
	guard(
		"a rejecting turn (not_live)",
		{ state = state0, assignment = w.assignment, positions = zedAt },
		function()
			P.turn(
				state0,
				w.assignment,
				"zed",
				12,
				TurnContract.requiredSetting(w.facility, 12),
				TurnContract.NOW,
				zedAt
			)
		end
	)
	local zedAt11 = TurnContract.standingAt(w, "zed", id)
	guard(
		"a refused turn (not_key_holder)",
		{ state = state0, assignment = w.assignment, positions = zedAt11 },
		function()
			P.turn(state0, w.assignment, "zed", id, required, TurnContract.NOW, zedAt11)
		end
	)
	local none: { [string]: Vec } = {}
	guard(
		"a refused turn (out_of_reach)",
		{ state = state0, assignment = w.assignment, positions = none },
		function()
			P.turn(state0, w.assignment, "kim", id, required, TurnContract.NOW, none)
		end
	)
	if committedState ~= nil then
		guard(
			"a refused turn (committed)",
			{ state = committedState, assignment = w.assignment, positions = atMachine },
			function()
				P.turn(
					committedState,
					w.assignment,
					"kim",
					id,
					required,
					TurnContract.NOW + 1,
					atMachine
				)
			end
		)
	end
	if rejectedState ~= nil then
		guard(
			"a refused turn (resetting)",
			{ state = rejectedState, assignment = w.assignment, positions = atMachine },
			function()
				P.turn(
					rejectedState,
					w.assignment,
					"kim",
					id,
					required,
					TurnContract.NOW + 1,
					atMachine
				)
			end
		)
		guard("dial inside a reset window", { state = rejectedState }, function()
			P.dial(rejectedState, id, TurnContract.NOW + 1)
		end)
	end
	-- And the new state is not the old one with a shared table that a later
	-- call would write through: a second turn on the NEW state leaves the OLD
	-- state's committed/dials/log untouched.
	if committedState ~= nil then
		local snapshot = Deep.copy(committedState)
		P.turn(
			committedState,
			w.assignment,
			"zed",
			12,
			TurnContract.requiredSetting(w.facility, 12),
			TurnContract.NOW + 2,
			zedAt
		)
		local snapshot0 = Deep.copy(state0)
		if not Deep.equal(snapshot, committedState) then
			table.insert(
				problems,
				`a turn on a state mutated THAT state:\n{Deep.diff(snapshot, committedState)}`
			)
		end
		if not Deep.equal(snapshot0, state0) then
			table.insert(
				problems,
				`a turn two states downstream reached back into the start state:\n{Deep.diff(
					snapshot0,
					state0
				)}`
			)
		end
	end
	if #problems > 0 then
		Contract.fail(`P-11: an argument was mutated:\n{Contract.firstFew(problems, 8)}`)
	end
end

--[[ ------------------------------------------------------------------------
     The whole battery, named, so the controls can run every check against a
     stand-in and report exactly which ones fire.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Procedure) -> () }

TurnContract.CHECKS = {
	{
		name = "startReturnsTheContractState",
		ac = "Contract",
		run = TurnContract.startReturnsTheContractState,
	},
	{
		name = "liveSetAtStartIsExactlyTheTrackHeads",
		ac = "AC-1",
		run = TurnContract.liveSetAtStartIsExactlyTheTrackHeads,
	},
	{
		name = "committingTheHeadOfTrackOneMakesItsSecondStepLive",
		ac = "AC-1",
		run = TurnContract.committingTheHeadOfTrackOneMakesItsSecondStepLive,
	},
	{
		name = "tracksAdvanceIndependentlyAndFinaleStepsStayWaiting",
		ac = "AC-1",
		run = TurnContract.tracksAdvanceIndependentlyAndFinaleStepsStayWaiting,
	},
	{
		name = "holderInReachOnTheRequiredSettingCommits",
		ac = "AC-2",
		run = TurnContract.holderInReachOnTheRequiredSettingCommits,
	},
	{
		name = "reachIsInclusiveAtTurnRangeStudsAndIgnoresY",
		ac = "AC-2",
		run = TurnContract.reachIsInclusiveAtTurnRangeStudsAndIgnoresY,
	},
	{
		name = "wrongSettingOnALiveStepIsRejectedAndChargesPerWrongValue",
		ac = "AC-3",
		run = TurnContract.wrongSettingOnALiveStepIsRejectedAndChargesPerWrongValue,
	},
	{
		name = "waitingStepIsNotLiveWhateverTheSetting",
		ac = "AC-3",
		run = TurnContract.waitingStepIsNotLiveWhateverTheSetting,
	},
	{
		name = "decoyIsNotLiveWhateverTheSetting",
		ac = "AC-3",
		run = TurnContract.decoyIsNotLiveWhateverTheSetting,
	},
	{
		name = "chargesAccumulateByReason",
		ac = "AC-3",
		run = TurnContract.chargesAccumulateByReason,
	},
	{
		name = "rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset",
		ac = "AC-3",
		run = TurnContract.rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset,
	},
	{ name = "unknownMachineIsRefused", ac = "AC-4", run = TurnContract.unknownMachineIsRefused },
	{
		name = "nonHolderIsRefusedAndNotCharged",
		ac = "AC-4",
		run = TurnContract.nonHolderIsRefusedAndNotCharged,
	},
	{
		name = "holderOutOfHorizontalReachOrWithoutAPositionIsRefused",
		ac = "AC-4",
		run = TurnContract.holderOutOfHorizontalReachOrWithoutAPositionIsRefused,
	},
	{
		name = "committedMachineIsRefused",
		ac = "AC-4",
		run = TurnContract.committedMachineIsRefused,
	},
	{ name = "resettingDialIsRefused", ac = "AC-4", run = TurnContract.resettingDialIsRefused },
	{
		name = "refusalChecksRunInOrderAndTheFirstFailureWins",
		ac = "AC-4",
		run = TurnContract.refusalChecksRunInOrderAndTheFirstFailureWins,
	},
	{
		name = "supplierIsJudgedKeyHolderAfterWithdraw",
		ac = "AC-5",
		run = TurnContract.supplierIsJudgedKeyHolderAfterWithdraw,
	},
	{
		name = "logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals",
		ac = "AC-6",
		run = TurnContract.logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals,
	},
	{
		name = "noCallMutatesItsArguments",
		ac = "P-11",
		run = TurnContract.noCallMutatesItsArguments,
	},
} :: { Check }

-- Run every check against `P`; the names of those that raised, with their
-- messages, in CHECKS order.
function TurnContract.failures(P: Procedure): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in TurnContract.CHECKS do
		local ok, err = pcall(check.run, P)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return TurnContract
