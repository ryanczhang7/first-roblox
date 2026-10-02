--!strict
--[[
	PROC-002 AC-1 through AC-7 written once, as checks over a PROCEDURE MODULE
	rather than over `src/server/procedure/Procedure.luau` by name - the same
	arrangement as `TurnContract.luau` (PROC-001), whose fixture this file
	REUSES rather than inventing a second facility: tracks { 11, 12, 13 } and
	{ 14, 15, 16, 17 }, finale { 13, 17 }, decoys 18 and 19, the ring kim ->
	zed -> amy -> bob, class i at seat i.

	`tests/server/procedure_finale_test.luau` applies these to the real module.
	`tests/server/procedure_finale_controls_test.luau` applies them to a
	reference stand-in and to deliberately wrong stand-ins, so that in RED -
	where the production module LOADS but has no finale behaviour, and every
	check here fails on its first assertion against it - every check has still
	been EXECUTED and observed to reject the implementation it exists to catch.

	A `procedure` here is anything with the seven plain field functions the two
	stories' Contracts write, called with a dot:

	    P.start(facility, now, tuning, roundSeed, roundSeconds) -> ProcedureState
	    P.isLive(state, machineId)                         -> boolean
	    P.dial(state, machineId, now)                      -> DialView
	    P.turn(state, assignment, playerId, machineId,
	           setting, now, positions)                    -> (ProcedureState, TurnResult)
	    P.tick(state, assignment, now, positions)          -> (ProcedureState, Outcome?)
	    P.partnerLamps(state, assignment, positions)       -> { [finaleId]: boolean }
	    P.isComplete(state)                                -> boolean

	THE TUNING IS THE SHIPPED ONE WITH SEVEN OVERRIDES (F-2), so that every
	constant a check reads is distinct from every other and from its shipped
	value, and a check can tell which one was read and which was charged:
	`simultaneous_window_seconds` 5 -> 3, `partner_lamp_range_studs` 10 -> 4
	(not the fixture's `turn_range_studs` 7), `instability_per_failed_pair`
	1 -> 4, `instability_per_wrong_value` 1, `instability_per_out_of_order` 2,
	`actuation_reset_seconds` 3 -> 5. AC-3 and AC-4 are ALSO run under the
	shipped tuning, where they read out literally: +1, and "1, not 2".

	SINCE PROC-003 `start` takes `roundSeed` and `roundSeconds` (TurnContract's
	ROUND_SEED and ROUND_SECONDS, 1000 s), and the overrides raise
	`instability_max` 5 -> 100: the F-9 check charges failed pair 4 + wrong
	value 1 = 5, which under the shipped max would END THE ROUND (PROC-003 I-6)
	and turn the checks that follow into `refused / round_over`. These checks
	pin turn semantics, not round end, so the fixture is given room. The two
	shipped-tuning checks charge 1 and are unaffected.

	THE ORACLE PARTITION IS HONOURED HERE. Every criterion is SETTLED by
	`mechanics.md` §3.2 and §5 (G12) and the Contract's F-1..F-12; every check
	reads the rule out and is named after it. Nothing here invents a threshold.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Turn = require("./TurnContract")

local FinaleContract = {}

export type Procedure = Turn.Procedure
export type Vec = Turn.Vec
export type Tuning = Turn.Tuning
export type World = Turn.World

--[[ ------------------------------------------------------------------------
     The fixture: TurnContract's, with the finale's constants overridden.
     --------------------------------------------------------------------- ]]

FinaleContract.NOW = Turn.NOW
-- The instant A is armed in every "given A armed at t" scenario: after the
-- five ordinary commits, which run at NOW + 1 .. NOW + 5.
FinaleContract.T_ARM = Turn.NOW + 10

-- The finale, by role. A = track 1's last step (class 3, amy's), B = track
-- 2's (class 4, bob's). Every ordinary step, in the order the scenarios
-- commit them.
FinaleContract.A = Turn.FINALE[1]
FinaleContract.B = Turn.FINALE[2]
FinaleContract.ORDINARY = { 11, 12, 14, 15, 16 }

-- The overrides, named once. The controls file checks each differs from the
-- shipped value and from every other constant a check must tell it from.
FinaleContract.OVERRIDES = {
	instance = {
		turn_range_studs = 7,
		simultaneous_window_seconds = 3,
		partner_lamp_range_studs = 4,
	},
	actuation = {
		actuation_reset_seconds = 5,
		instability_per_wrong_value = 1,
		instability_per_out_of_order = 2,
		instability_per_failed_pair = 4,
		-- PROC-003: room below the max for the 5-point F-9 scenario (header).
		instability_max = 100,
	},
}

-- The shipped tuning with `overrides` applied, frozen like the module.
function FinaleContract.tuning(overrides: { [string]: { [string]: number } }): Tuning
	local fake: any = Deep.copy(MechanicsTuning)
	for tableName, keys in pairs(overrides) do
		for key, value in pairs(keys) do
			fake[tableName][key] = value
		end
	end
	fake.instance = table.freeze(fake.instance)
	fake.channel = table.freeze(fake.channel)
	fake.actuation = table.freeze(fake.actuation)
	return table.freeze(fake) :: Tuning
end

function FinaleContract.world(): World
	return {
		facility = Turn.facility(),
		assignment = Turn.assignment(),
		tuning = FinaleContract.tuning(FinaleContract.OVERRIDES),
	}
end

-- The same fixture under the SHIPPED tuning, for the checks that read out
-- mechanics.md §5 literally (+1, "not 2").
function FinaleContract.shippedWorld(): World
	return {
		facility = Turn.facility(),
		assignment = Turn.assignment(),
		tuning = FinaleContract.tuning({}),
	}
end

local function started(P: Procedure, w: World): any
	return P.start(w.facility, Turn.NOW, w.tuning, Turn.ROUND_SEED, Turn.ROUND_SECONDS)
end

-- F-1: the three functions this story adds. Checked before use so a missing
-- export fails on a line that names it, not on "attempt to call a nil value".
local function need(P: Procedure, name: string)
	if typeof(P[name]) ~= "function" then
		Contract.fail(`F-1: Procedure.{name} is {typeof(P[name])}, expected a function`)
	end
end

-- The holder, standing at the machine, turning it to its required setting at
-- `now`, expecting a COMMIT. Fails loudly otherwise, so a later assertion is
-- never reached on a state that is not the one the scenario says.
local function commit(
	P: Procedure,
	w: World,
	state: any,
	id: number,
	now: number,
	label: string
): any
	local holder = Turn.holderOf(w.facility, id)
	local next_, result = P.turn(
		state,
		w.assignment,
		holder,
		id,
		Turn.requiredSetting(w.facility, id),
		now,
		Turn.standingAt(w, holder, id)
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

-- Every ordinary step of both tracks committed, at NOW + 1 .. NOW + 5. The
-- state every finale scenario starts from.
function FinaleContract.liveFinale(P: Procedure, w: World, label: string): any
	local state = started(P, w)
	for i, id in FinaleContract.ORDINARY do
		state = commit(P, w, state, id, Turn.NOW + i, label)
	end
	return state
end

-- The holder of a finale machine turning it correctly at `now`, expecting
-- ARMED (F-4). The "given A armed at t" of AC-3, AC-4, AC-5 and AC-7.
function FinaleContract.arm(
	P: Procedure,
	w: World,
	state: any,
	id: number,
	now: number,
	label: string
): any
	local holder = Turn.holderOf(w.facility, id)
	local next_, result = P.turn(
		state,
		w.assignment,
		holder,
		id,
		Turn.requiredSetting(w.facility, id),
		now,
		Turn.standingAt(w, holder, id)
	)
	if not Deep.equal(result, { kind = "armed", machineId = id }) then
		Contract.fail(
			`{label}: setting up the scenario, {holder} turning live finale machine {id} to its required setting at {now} with neither machine armed returned {Deep.show(
				result
			)}, expected \{ kind = "armed", machineId = {id} }`
		)
	end
	return next_
end

-- The holder of `id` turning it to `setting` at `now`, in reach.
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

-- The positions handed to `tick` and `partnerLamps` when they do not matter:
-- both finale holders at their own machines.
local function bothAtTheirMachines(w: World): { [string]: Vec }
	local A, B = FinaleContract.A, FinaleContract.B
	return {
		[Turn.holderOf(w.facility, A)] = Turn.at(w, A),
		[Turn.holderOf(w.facility, B)] = Turn.at(w, B),
	}
end

-- The log's last entry, or nil.
local function lastLog(state: any): any
	return state.log[#state.log]
end

--[[ ------------------------------------------------------------------------
     F-1. The export shape.
     --------------------------------------------------------------------- ]]

-- `start` opens no window (`armed` is nil), `isComplete` answers a real
-- `false`, `tick` on a state with no window returns a deep-equal state and a
-- nil second value, and `partnerLamps` has exactly the two finale ids as keys
-- with real booleans - at start, where the finale is not live, both false.
function FinaleContract.startHasNoWindowAndTheNewExportsAnswerInShape(P: Procedure)
	need(P, "tick")
	need(P, "partnerLamps")
	need(P, "isComplete")
	local w = FinaleContract.world()
	local state = started(P, w)
	local problems: { string } = {}
	if state.armed ~= nil then
		table.insert(problems, `start's state.armed is {Deep.show(state.armed)}, expected nil`)
	end
	local complete = P.isComplete(state)
	if complete ~= false then
		table.insert(
			problems,
			`isComplete at start is {typeof(complete)} {Deep.show(complete)}, expected the boolean false`
		)
	end
	local positions = bothAtTheirMachines(w)
	local ticked, second = P.tick(state, w.assignment, Turn.NOW + 1, positions)
	if not Deep.equal(ticked, state) then
		table.insert(
			problems,
			`tick with no window open returned a state that differs from the one passed:\n{Deep.diff(
				state,
				ticked
			)}`
		)
	end
	if second ~= nil then
		table.insert(
			problems,
			`tick's second return is {Deep.show(second)}, expected nil in this story`
		)
	end
	local lamps = P.partnerLamps(state, w.assignment, positions)
	if typeof(lamps) ~= "table" then
		table.insert(problems, `partnerLamps returned {typeof(lamps)}, expected a table`)
	else
		local keys: { number } = {}
		for k, v in pairs(lamps) do
			table.insert(keys, k)
			if typeof(v) ~= "boolean" then
				table.insert(
					problems,
					`partnerLamps[{Deep.show(k)}] is {typeof(v)} {Deep.show(v)}, expected a boolean`
				)
			end
		end
		table.sort(keys)
		if not Deep.equal(keys, Turn.FINALE) then
			table.insert(
				problems,
				`partnerLamps has keys {Deep.show(keys)}, expected exactly the finale ids {Deep.show(
					Turn.FINALE
				)}`
			)
		end
		if not Deep.equal(lamps, { [FinaleContract.A] = false, [FinaleContract.B] = false }) then
			table.insert(
				problems,
				`partnerLamps at start is {Deep.show(lamps)}, expected both false - the finale is not live`
			)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`F-1: the new exports do not answer in the Contract's shape:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-1. Liveness (F-3): finale_live_together.
     --------------------------------------------------------------------- ]]

-- With track 2's ordinary steps all committed and ONE ordinary step left in
-- track 1, neither finale machine is live; the moment it commits, both are.
-- (The AC's own scenario. TurnContract's AC-1 check covers the other order:
-- track 1 done first, track 2 not.)
function FinaleContract.neitherFinaleMachineIsLiveUntilTheLastOrdinaryStepCommitsThenBothAre(
	P: Procedure
)
	local w = FinaleContract.world()
	local state = started(P, w)
	local t = Turn.NOW
	for _, id in { 11, 14, 15, 16 } do
		t += 1
		state = commit(P, w, state, id, t, "AC-1")
	end
	local ids = table.clone(Turn.ALL_IDS)
	table.insert(ids, Turn.UNKNOWN_ID)
	local live = Turn.liveSet(P, state, ids)
	if not Deep.equal(live, { 12 }) then
		Contract.fail(
			`AC-1: with track 2's ordinary steps committed and machine 12 left in track 1 the live set is {Deep.show(
				live
			)}, expected \{ 12 } - neither finale machine ({FinaleContract.A}, {FinaleContract.B}) is live while an ordinary step remains (finale_live_together)`
		)
	end
	state = commit(P, w, state, 12, t + 1, "AC-1")
	live = Turn.liveSet(P, state, ids)
	if not Deep.equal(live, Turn.FINALE) then
		Contract.fail(
			`AC-1: the moment the last ordinary step committed the live set is {Deep.show(live)}, expected exactly both finale machines {Deep.show(
				Turn.FINALE
			)} (finale_live_together)`
		)
	end
end

-- F-3: an armed machine is still live, and so is its unarmed partner; after
-- both commit, nothing is live.
function FinaleContract.anArmedMachineIsStillLiveAndACommittedFinaleIsNot(P: Procedure)
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local state = FinaleContract.liveFinale(P, w, "AC-1")
	state = FinaleContract.arm(P, w, state, A, FinaleContract.T_ARM, "AC-1")
	local live = Turn.liveSet(P, state, Turn.ALL_IDS)
	if not Deep.equal(live, Turn.FINALE) then
		Contract.fail(
			`AC-1/F-3: with machine {A} armed the live set is {Deep.show(live)}, expected still {Deep.show(
				Turn.FINALE
			)} - an armed machine is live; armed is a separate fact`
		)
	end
	local done, result =
		turnBy(P, w, state, B, Turn.requiredSetting(w.facility, B), FinaleContract.T_ARM + 1)
	if not Deep.equal(result, { kind = "committed", machineId = B }) then
		Contract.fail(
			`AC-1: setting up the scenario, completing the finale returned {Deep.show(result)}, expected committed`
		)
	end
	live = Turn.liveSet(P, done, Turn.ALL_IDS)
	if not Deep.equal(live, {}) then
		Contract.fail(
			`AC-1/F-3: after the finale committed the live set is {Deep.show(live)}, expected \{} - a committed finale machine is not live`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-2. Arming (F-4) and completing (F-5).
     --------------------------------------------------------------------- ]]

-- Everything an arming turn must do, for the machine `id` turned at `now`
-- from the live-finale state `state0`.
local function expectArmed(
	P: Procedure,
	w: World,
	label: string,
	state0: any,
	id: number,
	now: number
): any
	local required = Turn.requiredSetting(w.facility, id)
	local state, result = turnBy(P, w, state0, id, required, now)
	local problems: { string } = {}
	if not Deep.equal(result, { kind = "armed", machineId = id }) then
		table.insert(
			problems,
			`result is {Deep.show(result)}, expected \{ kind = "armed", machineId = {id} }`
		)
	end
	local window = w.tuning.instance.simultaneous_window_seconds
	if not Deep.equal(state.armed, { machineId = id, closesAt = now + window }) then
		table.insert(
			problems,
			`state.armed is {Deep.show(state.armed)}, expected \{ machineId = {id}, closesAt = {now} + simultaneous_window_seconds {window} = {now + window} }`
		)
	end
	if not Deep.equal(state.dials[id], { setting = required }) then
		table.insert(
			problems,
			`state.dials[{id}] is {Deep.show(state.dials[id])}, expected \{ setting = {required} }`
		)
	end
	if state.instability ~= state0.instability then
		table.insert(
			problems,
			`instability went {state0.instability} -> {Deep.show(state.instability)} on an arming turn; arming costs nothing`
		)
	end
	if not Deep.equal(state.committed, state0.committed) then
		table.insert(
			problems,
			`committed changed on an arming turn:\n{Deep.diff(state0.committed, state.committed)}`
		)
	end
	local holder = Turn.holderOf(w.facility, id)
	local wantEntry =
		{ playerId = holder, machineId = id, setting = required, at = now, result = "armed" }
	if #state.log ~= #state0.log + 1 or not Deep.equal(lastLog(state), wantEntry) then
		table.insert(
			problems,
			`the log went from {#state0.log} to {#state.log} entries, last {Deep.show(
				lastLog(state)
			)}; expected exactly one new entry {Deep.show(wantEntry)}`
		)
	end
	if #problems > 0 then
		Contract.fail(`AC-2/F-4: {label}:\n{Contract.firstFew(problems, 8)}`)
	end
	return state
end

-- A correct turn on a live finale machine, with neither armed, arms it: the
-- result, the window at now + simultaneous_window_seconds, the dial set, no
-- charge, no commit, one `armed` log entry. Either machine may arm first.
function FinaleContract.correctTurnOnALiveFinaleMachineWithNeitherArmedArmsIt(P: Procedure)
	local w = FinaleContract.world()
	local state = FinaleContract.liveFinale(P, w, "AC-2")
	expectArmed(
		P,
		w,
		`amy turning finale machine {FinaleContract.A} correctly first`,
		state,
		FinaleContract.A,
		FinaleContract.T_ARM
	)
	expectArmed(
		P,
		w,
		`bob turning finale machine {FinaleContract.B} correctly first`,
		state,
		FinaleContract.B,
		FinaleContract.T_ARM
	)
end

-- Everything a completing turn must do: B turned correctly at `now` from a
-- state with A armed.
local function expectCompleted(
	P: Procedure,
	w: World,
	label: string,
	armedState: any,
	armedId: number,
	otherId: number,
	now: number
)
	local required = Turn.requiredSetting(w.facility, otherId)
	local armedSetting = Turn.requiredSetting(w.facility, armedId)
	local state, result = turnBy(P, w, armedState, otherId, required, now)
	local problems: { string } = {}
	if not Deep.equal(result, { kind = "committed", machineId = otherId }) then
		table.insert(
			problems,
			`result is {Deep.show(result)}, expected \{ kind = "committed", machineId = {otherId} }`
		)
	end
	if state.committed[armedId] ~= true or state.committed[otherId] ~= true then
		table.insert(
			problems,
			`state.committed[{armedId}] = {Deep.show(state.committed[armedId])}, state.committed[{otherId}] = {Deep.show(
				state.committed[otherId]
			)}; expected both true - the finale commits together`
		)
	end
	if state.armed ~= nil then
		table.insert(
			problems,
			`state.armed is {Deep.show(state.armed)} after the finale committed, expected nil`
		)
	end
	if not Deep.equal(state.dials[otherId], { setting = required }) then
		table.insert(
			problems,
			`state.dials[{otherId}] is {Deep.show(state.dials[otherId])}, expected \{ setting = {required} }`
		)
	end
	local viewA = P.dial(state, armedId, now)
	if not Deep.equal(viewA, { setting = armedSetting, state = "committed" }) then
		table.insert(
			problems,
			`dial({armedId}) is {Deep.show(viewA)}, expected \{ setting = {armedSetting}, state = "committed" } - the armed machine keeps its setting`
		)
	end
	local viewB = P.dial(state, otherId, now)
	if not Deep.equal(viewB, { setting = required, state = "committed" }) then
		table.insert(
			problems,
			`dial({otherId}) is {Deep.show(viewB)}, expected \{ setting = {required}, state = "committed" }`
		)
	end
	if state.instability ~= armedState.instability then
		table.insert(
			problems,
			`instability went {armedState.instability} -> {Deep.show(state.instability)} on the completing turn`
		)
	end
	local holder = Turn.holderOf(w.facility, otherId)
	local wantEntry = {
		playerId = holder,
		machineId = otherId,
		setting = required,
		at = now,
		result = "committed",
	}
	if #state.log ~= #armedState.log + 1 or not Deep.equal(lastLog(state), wantEntry) then
		table.insert(
			problems,
			`the log went from {#armedState.log} to {#state.log} entries, last {Deep.show(
				lastLog(state)
			)}; expected exactly ONE new entry, {Deep.show(wantEntry)} - the armed machine's entry was written when it armed`
		)
	end
	local complete = P.isComplete(state)
	if complete ~= true then
		table.insert(
			problems,
			`isComplete is {Deep.show(complete)} after the finale committed, expected true`
		)
	end
	if #problems > 0 then
		Contract.fail(`AC-2/F-5: {label}:\n{Contract.firstFew(problems, 8)}`)
	end
end

-- With A armed at t, B turned correctly at t' <= t + window commits both,
-- together, at t', and the Procedure is complete - at t' = t, mid-window and
-- just before the end. (Exactly the end is AC-7's own check.)
function FinaleContract.correctTurnOnTheOtherMachineInsideTheWindowCommitsBoth(P: Procedure)
	need(P, "isComplete")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local window = w.tuning.instance.simultaneous_window_seconds
	local t = FinaleContract.T_ARM
	local armedA = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-2"), A, t, "AC-2")
	for _, dt in { 0, window / 2, window - 0.001 } do
		expectCompleted(
			P,
			w,
			`A ({A}) armed at {t}, B ({B}) turned correctly at t + {dt} (window {window})`,
			armedA,
			A,
			B,
			t + dt
		)
	end
	-- And the other way round: B arms, A completes.
	local armedB = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-2"), B, t, "AC-2")
	expectCompleted(
		P,
		w,
		`B ({B}) armed at {t}, A ({A}) turned correctly at t + 1`,
		armedB,
		B,
		A,
		t + 1
	)
end

--[[ ------------------------------------------------------------------------
     AC-7. The window is inclusive at its end (F-5, F-8).
     --------------------------------------------------------------------- ]]

-- B turned at EXACTLY t + simultaneous_window_seconds commits both.
function FinaleContract.turnOnTheOtherMachineAtExactlyTheWindowsEndCommitsBoth(P: Procedure)
	need(P, "isComplete")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local window = w.tuning.instance.simultaneous_window_seconds
	local t = FinaleContract.T_ARM
	local armedA = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-7"), A, t, "AC-7")
	expectCompleted(
		P,
		w,
		`A ({A}) armed at {t}, B ({B}) turned correctly at EXACTLY t + simultaneous_window_seconds ({t + window}) - the window is inclusive at its end (AC-7)`,
		armedA,
		A,
		B,
		t + window
	)
end

-- `tick` at or before the window's end - at t, mid-window, and at EXACTLY
-- closesAt - returns a state deep-equal to the one passed, and nil.
function FinaleContract.tickAtOrBeforeTheWindowsEndChangesNothing(P: Procedure)
	need(P, "tick")
	local w = FinaleContract.world()
	local A = FinaleContract.A
	local window = w.tuning.instance.simultaneous_window_seconds
	local t = FinaleContract.T_ARM
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-7"), A, t, "AC-7")
	local positions = bothAtTheirMachines(w)
	local problems: { string } = {}
	for _, dt in { 0, window / 2, window } do
		local state, second = P.tick(armed, w.assignment, t + dt, positions)
		if not Deep.equal(state, armed) then
			table.insert(
				problems,
				`tick at t + {dt} (closesAt = t + {window}) returned a state that differs from the one passed:\n{Deep.diff(
					armed,
					state
				)}`
			)
		end
		if second ~= nil then
			table.insert(
				problems,
				`tick at t + {dt} returned a second value {Deep.show(second)}, expected nil`
			)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-7/F-8: with A ({A}) armed at {t} and the window {window} s, a tick at or before closesAt must change nothing (now > closesAt, strictly):\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-3. Expiry, by tick (F-8).
     --------------------------------------------------------------------- ]]

-- Everything an expiry must do, for A armed at `t` in `armed` and a tick at
-- `now` > closesAt. Returns the problems so the shipped-tuning check can
-- share it.
local function expiryProblems(
	P: Procedure,
	w: World,
	armed: any,
	A: number,
	B: number,
	now: number
): ({ string }, any)
	local positions = bothAtTheirMachines(w)
	local state, second = P.tick(armed, w.assignment, now, positions)
	local a = w.tuning.actuation
	local armedSetting = Turn.requiredSetting(w.facility, A)
	local problems: { string } = {}
	if second ~= nil then
		table.insert(
			problems,
			`tick's second return is {Deep.show(second)}, expected nil in this story`
		)
	end
	if state.armed ~= nil then
		table.insert(
			problems,
			`state.armed is {Deep.show(state.armed)} after the window closed, expected nil`
		)
	end
	local want = armed.instability + a.instability_per_failed_pair
	if state.instability ~= want then
		table.insert(
			problems,
			`instability went {armed.instability} -> {Deep.show(state.instability)}, expected +instability_per_failed_pair ({a.instability_per_failed_pair}) = {want}`
		)
	end
	local wantDial = { setting = armedSetting, rejectedUntil = now + a.actuation_reset_seconds }
	if not Deep.equal(state.dials[A], wantDial) then
		table.insert(
			problems,
			`state.dials[{A}] is {Deep.show(state.dials[A])}, expected {Deep.show(wantDial)} - the TICK's now ({now}) + actuation_reset_seconds ({a.actuation_reset_seconds}), not closesAt`
		)
	end
	if not Deep.equal(state.dials[B], armed.dials[B]) then
		table.insert(
			problems,
			`state.dials[{B}] went {Deep.show(armed.dials[B])} -> {Deep.show(state.dials[B])}; the unturned machine's dial is untouched`
		)
	end
	if not Deep.equal(state.committed, armed.committed) then
		table.insert(
			problems,
			`committed changed on expiry:\n{Deep.diff(armed.committed, state.committed)}`
		)
	end
	if not Deep.equal(state.log, armed.log) then
		table.insert(
			problems,
			`the log went from {#armed.log} to {#state.log} entries on expiry; expiry is not a turn and writes no entry`
		)
	end
	local view = P.dial(state, A, now)
	if not Deep.equal(view, { setting = armedSetting, state = "rejected" }) then
		table.insert(
			problems,
			`dial({A}) at the tick is {Deep.show(view)}, expected \{ setting = {armedSetting}, state = "rejected" }`
		)
	end
	local reset = a.actuation_reset_seconds
	local before = P.dial(state, A, now + reset - 0.001)
	if not Deep.equal(before, { setting = armedSetting, state = "rejected" }) then
		table.insert(
			problems,
			`dial({A}) just before now + actuation_reset_seconds is {Deep.show(before)}, expected still rejected`
		)
	end
	local after = P.dial(state, A, now + reset)
	if not Deep.equal(after, { setting = nil, state = "unset" }) then
		table.insert(
			problems,
			`dial({A}) at now + actuation_reset_seconds ({now + reset}) is {Deep.show(after)}, expected \{ state = "unset" } (P-6, half-open)`
		)
	end
	local viewB = P.dial(state, B, now)
	if not Deep.equal(viewB, { setting = nil, state = "unset" }) then
		table.insert(
			problems,
			`dial({B}) after expiry is {Deep.show(viewB)}, expected unset - it was never turned`
		)
	end
	local live = Turn.liveSet(P, state, Turn.ALL_IDS)
	if not Deep.equal(live, Turn.FINALE) then
		table.insert(
			problems,
			`the live set after expiry is {Deep.show(live)}, expected {Deep.show(Turn.FINALE)} - both machines are back to live`
		)
	end
	return problems, state
end

-- A armed at t; tick at t + window + ε: both disarm, instability rises by
-- exactly instability_per_failed_pair (the fixture's 4, so a module charging
-- wrong_value 1 or out_of_order 2 reads wrong), A's dial shows rejected until
-- the tick's now + actuation_reset_seconds, B's dial and the log untouched.
-- A LATE tick (t + window + 10) dates the rejection from its own now.
function FinaleContract.tickPastTheWindowDisarmsBothAndChargesExactlyOneFailedPair(P: Procedure)
	need(P, "tick")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local window = w.tuning.instance.simultaneous_window_seconds
	local t = FinaleContract.T_ARM
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-3"), A, t, "AC-3")
	for _, dt in { window + 0.001, window + 10 } do
		local problems = expiryProblems(P, w, armed, A, B, t + dt)
		if #problems > 0 then
			Contract.fail(
				`AC-3/F-8: A ({A}) armed at {t}, window {window} s, tick at t + {dt} with B ({B}) unturned:\n{Contract.firstFew(
					problems,
					10
				)}`
			)
		end
	end
end

-- After expiry the finale is live again and A is an ordinary resetting dial:
-- a turn on A inside the reset window is refused / resetting (and, no window
-- having expired at that now, returns the state passed - P-9); a turn at the
-- boundary arms A again.
function FinaleContract.afterExpiryTheArmedMachineResetsLikeAnyRejectionThenCanArmAgain(
	P: Procedure
)
	need(P, "tick")
	local w = FinaleContract.world()
	local A = FinaleContract.A
	local window = w.tuning.instance.simultaneous_window_seconds
	local reset = w.tuning.actuation.actuation_reset_seconds
	local t = FinaleContract.T_ARM
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-3"), A, t, "AC-3")
	local tickAt = t + window + 1
	local expired = P.tick(armed, w.assignment, tickAt, bothAtTheirMachines(w))
	local required = Turn.requiredSetting(w.facility, A)
	local holder = Turn.holderOf(w.facility, A)
	local problems = Turn.refusalProblems(
		P,
		w,
		`{holder} turning disarmed machine {A} {reset - 0.001} s after the expiry tick`,
		expired,
		holder,
		A,
		required,
		tickAt + reset - 0.001,
		Turn.standingAt(w, holder, A),
		"resetting"
	)
	local again, result = turnBy(P, w, expired, A, required, tickAt + reset)
	if not Deep.equal(result, { kind = "armed", machineId = A }) then
		table.insert(
			problems,
			`{holder} turning machine {A} correctly at the reset boundary (tick + {reset}) returned {Deep.show(
				result
			)}, expected armed again`
		)
	elseif not Deep.equal(again.armed, { machineId = A, closesAt = tickAt + reset + window }) then
		table.insert(
			problems,
			`re-arming set state.armed to {Deep.show(again.armed)}, expected \{ machineId = {A}, closesAt = {tickAt + reset + window} }`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-3/F-8: a disarmed machine's dial resets after actuation_reset_seconds like any rejection:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- The same expiry under the SHIPPED tuning (window 5, failed pair 1, reset
-- 3), where mechanics.md §5 reads out literally: instability rises by 1.
function FinaleContract.underTheShippedTuningAnExpiredWindowCostsExactlyOne(P: Procedure)
	need(P, "tick")
	local w = FinaleContract.shippedWorld()
	local A, B = FinaleContract.A, FinaleContract.B
	local window = w.tuning.instance.simultaneous_window_seconds
	local t = FinaleContract.T_ARM
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-3"), A, t, "AC-3")
	local problems, state = expiryProblems(P, w, armed, A, B, t + window + 0.001)
	if state.instability ~= 1 then
		table.insert(
			problems,
			`instability is {Deep.show(state.instability)}, expected exactly 1 (mechanics.md §5: "both disarm, +1")`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-3: under the SHIPPED tuning (simultaneous_window_seconds {window}, instability_per_failed_pair {w.tuning.actuation.instability_per_failed_pair}) an expired window:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-4. A wrong turn with a window open (F-7).
     --------------------------------------------------------------------- ]]

-- Everything F-7 says, for A armed in `armed` and a wrong turn on B at `now`.
local function wrongWithWindowProblems(
	P: Procedure,
	w: World,
	armed: any,
	A: number,
	B: number,
	now: number
): ({ string }, any)
	local a = w.tuning.actuation
	local wrong = Turn.wrongSetting(w.facility, B, w.tuning)
	local armedSetting = Turn.requiredSetting(w.facility, A)
	local state, result = turnBy(P, w, armed, B, wrong, now)
	local problems: { string } = {}
	if not Deep.equal(result, { kind = "rejected", machineId = B, reason = "wrong_setting" }) then
		table.insert(
			problems,
			`result is {Deep.show(result)}, expected \{ kind = "rejected", machineId = {B}, reason = "wrong_setting" }`
		)
	end
	local want = armed.instability + a.instability_per_wrong_value
	if state.instability ~= want then
		table.insert(
			problems,
			`instability went {armed.instability} -> {Deep.show(state.instability)}, expected +instability_per_wrong_value ({a.instability_per_wrong_value}) = {want} and NOT also instability_per_failed_pair ({a.instability_per_failed_pair}) - one failed attempt, one penalty`
		)
	end
	if state.armed ~= nil then
		table.insert(
			problems,
			`state.armed is {Deep.show(state.armed)} after a wrong turn with the window open, expected nil`
		)
	end
	local reset = a.actuation_reset_seconds
	local wantB = { setting = wrong, rejectedUntil = now + reset }
	if not Deep.equal(state.dials[B], wantB) then
		table.insert(
			problems,
			`state.dials[{B}] is {Deep.show(state.dials[B])}, expected {Deep.show(wantB)} (P-6)`
		)
	end
	local wantA = { setting = armedSetting, rejectedUntil = now + reset }
	if not Deep.equal(state.dials[A], wantA) then
		table.insert(
			problems,
			`state.dials[{A}] is {Deep.show(state.dials[A])}, expected {Deep.show(wantA)} - the armed machine disarms into a reset window too`
		)
	end
	if not Deep.equal(state.committed, armed.committed) then
		table.insert(problems, `committed changed:\n{Deep.diff(armed.committed, state.committed)}`)
	end
	local holder = Turn.holderOf(w.facility, B)
	local wantEntry =
		{ playerId = holder, machineId = B, setting = wrong, at = now, result = "wrong_setting" }
	if #state.log ~= #armed.log + 1 or not Deep.equal(lastLog(state), wantEntry) then
		table.insert(
			problems,
			`the log went from {#armed.log} to {#state.log} entries, last {Deep.show(lastLog(state))}; expected exactly one new entry {Deep.show(
				wantEntry
			)}`
		)
	end
	local viewA = P.dial(state, A, now)
	if not Deep.equal(viewA, { setting = armedSetting, state = "rejected" }) then
		table.insert(
			problems,
			`dial({A}) is {Deep.show(viewA)}, expected \{ setting = {armedSetting}, state = "rejected" }`
		)
	end
	local viewB = P.dial(state, B, now)
	if not Deep.equal(viewB, { setting = wrong, state = "rejected" }) then
		table.insert(
			problems,
			`dial({B}) is {Deep.show(viewB)}, expected \{ setting = {wrong}, state = "rejected" }`
		)
	end
	return problems, state
end

-- A armed; B turned to a wrong setting inside the window: rejected /
-- wrong_setting, charged instability_per_wrong_value (1) ONCE - not also
-- instability_per_failed_pair (4) - both disarm into reset windows, one log
-- entry.
function FinaleContract.wrongTurnOnTheOtherMachineInsideTheWindowIsRejectedOnceAndDisarmsBoth(
	P: Procedure
)
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local t = FinaleContract.T_ARM
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-4"), A, t, "AC-4")
	local problems = wrongWithWindowProblems(P, w, armed, A, B, t + 1)
	if #problems > 0 then
		Contract.fail(
			`AC-4/F-7: A ({A}) armed at {t}, B ({B}) turned to a WRONG setting at t + 1 inside the window:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- The same under the SHIPPED tuning, where it reads out literally:
-- instability rises by exactly 1 in total, not 2.
function FinaleContract.underTheShippedTuningAWrongTurnWithTheWindowOpenCostsOneNotTwo(P: Procedure)
	local w = FinaleContract.shippedWorld()
	local A, B = FinaleContract.A, FinaleContract.B
	local t = FinaleContract.T_ARM
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-4"), A, t, "AC-4")
	local problems, state = wrongWithWindowProblems(P, w, armed, A, B, t + 1)
	if state.instability ~= 1 then
		table.insert(
			problems,
			`instability is {Deep.show(state.instability)}, expected exactly 1 in total, not 2 (mechanics.md §5: "no second penalty")`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-4: under the SHIPPED tuning (wrong value 1, failed pair 1) a wrong turn on B with A armed:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- F-7's last sentence: a wrong turn on a live finale machine with NO window
-- open is an ordinary rejection - charged wrong_value, the other machine's
-- dial untouched, armed still nil.
function FinaleContract.wrongTurnOnALiveFinaleMachineWithNoWindowOpenIsAnOrdinaryRejection(
	P: Procedure
)
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local a = w.tuning.actuation
	local live = FinaleContract.liveFinale(P, w, "AC-4")
	local wrong = Turn.wrongSetting(w.facility, B, w.tuning)
	local now = FinaleContract.T_ARM
	local state, result = turnBy(P, w, live, B, wrong, now)
	local problems: { string } = {}
	if not Deep.equal(result, { kind = "rejected", machineId = B, reason = "wrong_setting" }) then
		table.insert(problems, `result is {Deep.show(result)}, expected rejected / wrong_setting`)
	end
	if state.instability ~= live.instability + a.instability_per_wrong_value then
		table.insert(
			problems,
			`instability went {live.instability} -> {Deep.show(state.instability)}, expected +instability_per_wrong_value ({a.instability_per_wrong_value})`
		)
	end
	if state.armed ~= nil then
		table.insert(problems, `state.armed is {Deep.show(state.armed)}, expected nil`)
	end
	if
		not Deep.equal(
			state.dials[B],
			{ setting = wrong, rejectedUntil = now + a.actuation_reset_seconds }
		)
	then
		table.insert(
			problems,
			`state.dials[{B}] is {Deep.show(state.dials[B])}, expected the ordinary rejection (P-6)`
		)
	end
	if state.dials[A] ~= nil then
		table.insert(
			problems,
			`state.dials[{A}] is {Deep.show(state.dials[A])}, expected nil - no window was open, so {A} is untouched`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-4/F-7: a wrong turn on live finale machine {B} with NO window open:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-5. The armed refusal (F-6).
     --------------------------------------------------------------------- ]]

-- A turn on the armed machine itself - right setting or wrong, inside the
-- window - is refused / armed, free, and returns the state passed (P-9).
function FinaleContract.turnOnTheArmedMachineIsRefusedArmedAtNoCost(P: Procedure)
	local w = FinaleContract.world()
	local A = FinaleContract.A
	local t = FinaleContract.T_ARM
	local window = w.tuning.instance.simultaneous_window_seconds
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-5"), A, t, "AC-5")
	local holder = Turn.holderOf(w.facility, A)
	local problems: { string } = {}
	local cases = {
		{
			label = "its required setting at t + 1",
			setting = Turn.requiredSetting(w.facility, A),
			now = t + 1,
		},
		{
			label = "a wrong setting at t + 1",
			setting = Turn.wrongSetting(w.facility, A, w.tuning),
			now = t + 1,
		},
		{
			label = `its required setting at exactly closesAt (t + {window})`,
			setting = Turn.requiredSetting(w.facility, A),
			now = t + window,
		},
	}
	for _, c in cases do
		for _, p in
			Turn.refusalProblems(
				P,
				w,
				`{holder} turning ARMED machine {A} again on {c.label}`,
				armed,
				holder,
				A,
				c.setting,
				c.now,
				Turn.standingAt(w, holder, A),
				"armed"
			)
		do
			table.insert(problems, p)
		end
	end
	if #problems > 0 then
		Contract.fail(`AC-5/F-6: the armed refusal:\n{Contract.firstFew(problems, 10)}`)
	end
end

-- F-6: `armed` is the LAST refusal. A non-holder or an out-of-reach holder on
-- the armed machine is refused for that reason, not `armed`.
function FinaleContract.armedIsTheLastRefusalChecked(P: Procedure)
	local w = FinaleContract.world()
	local A = FinaleContract.A
	local t = FinaleContract.T_ARM
	local range = w.tuning.instance.turn_range_studs
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "AC-5"), A, t, "AC-5")
	local holder = Turn.holderOf(w.facility, A)
	local required = Turn.requiredSetting(w.facility, A)
	local problems: { string } = {}
	local cases = {
		{
			label = `zed (non-holder), no position, on ARMED {A} -> not_key_holder beats out_of_reach and armed`,
			player = "zed",
			positions = {},
			reason = "not_key_holder",
		},
		{
			label = `{Turn.STRANGER} in reach on ARMED {A} -> not_key_holder beats armed`,
			player = Turn.STRANGER,
			positions = { [Turn.STRANGER] = Turn.at(w, A) },
			reason = "not_key_holder",
		},
		{
			label = `{holder} out of reach on ARMED {A} -> out_of_reach beats armed`,
			player = holder,
			positions = { [holder] = Turn.at(w, A, range + 1, 0, 0) },
			reason = "out_of_reach",
		},
		{
			label = `{holder} with no position on ARMED {A} -> out_of_reach beats armed`,
			player = holder,
			positions = {},
			reason = "out_of_reach",
		},
	}
	for _, c in cases do
		for _, p in
			Turn.refusalProblems(
				P,
				w,
				c.label,
				armed,
				c.player,
				A,
				required,
				t + 1,
				c.positions,
				c.reason
			)
		do
			table.insert(problems, p)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`AC-5/F-6: the refusal order unknown_machine > not_key_holder > out_of_reach > committed > resetting > armed is not kept:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     F-9. A turn applies an expired window first.
     --------------------------------------------------------------------- ]]

-- A armed at t; B turned CORRECTLY after the window: the expiry applies
-- (+failed_pair, A into a reset window), and then the turn arms B. Nothing
-- commits - a session that forgot to tick cannot commit a late finale.
function FinaleContract.aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt(
	P: Procedure
)
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local a = w.tuning.actuation
	local window = w.tuning.instance.simultaneous_window_seconds
	local t = FinaleContract.T_ARM
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "F-9"), A, t, "F-9")
	local now = t + window + 1
	local required = Turn.requiredSetting(w.facility, B)
	local state, result = turnBy(P, w, armed, B, required, now)
	local problems: { string } = {}
	if not Deep.equal(result, { kind = "armed", machineId = B }) then
		table.insert(
			problems,
			`result is {Deep.show(result)}, expected \{ kind = "armed", machineId = {B} } - the window had closed, so this turn opens a new one rather than completing`
		)
	end
	if state.committed[A] or state.committed[B] then
		table.insert(
			problems,
			`committed[{A}] = {Deep.show(state.committed[A])}, committed[{B}] = {Deep.show(
				state.committed[B]
			)}; a late turn must not commit the finale`
		)
	end
	local want = armed.instability + a.instability_per_failed_pair
	if state.instability ~= want then
		table.insert(
			problems,
			`instability went {armed.instability} -> {Deep.show(state.instability)}, expected +instability_per_failed_pair ({a.instability_per_failed_pair}) = {want} for the expired window`
		)
	end
	if not Deep.equal(state.armed, { machineId = B, closesAt = now + window }) then
		table.insert(
			problems,
			`state.armed is {Deep.show(state.armed)}, expected \{ machineId = {B}, closesAt = {now + window} }`
		)
	end
	local wantA = {
		setting = Turn.requiredSetting(w.facility, A),
		rejectedUntil = now + a.actuation_reset_seconds,
	}
	if not Deep.equal(state.dials[A], wantA) then
		table.insert(
			problems,
			`state.dials[{A}] is {Deep.show(state.dials[A])}, expected {Deep.show(wantA)} (F-8, at the turn's now)`
		)
	end
	if not Deep.equal(state.dials[B], { setting = required }) then
		table.insert(
			problems,
			`state.dials[{B}] is {Deep.show(state.dials[B])}, expected \{ setting = {required} }`
		)
	end
	local holder = Turn.holderOf(w.facility, B)
	local wantEntry =
		{ playerId = holder, machineId = B, setting = required, at = now, result = "armed" }
	if #state.log ~= #armed.log + 1 or not Deep.equal(lastLog(state), wantEntry) then
		table.insert(
			problems,
			`the log went from {#armed.log} to {#state.log} entries, last {Deep.show(lastLog(state))}; expected exactly one new entry {Deep.show(
				wantEntry
			)} - expiry writes none`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`F-9: A ({A}) armed at {t}, window {window} s, B ({B}) turned CORRECTLY at t + {window + 1}:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

-- A armed at t; A turned again after the window: the expiry applies and the
-- turn is then refused / resetting - and the state returned is the
-- POST-EXPIRY state (deep-equal to what tick at that now returns), not the
-- one passed. A wrong turn on B after the window is expiry plus an ordinary
-- rejection: failed_pair + wrong_value.
function FinaleContract.aTurnAfterTheWindowReturnsThePostExpiryState(P: Procedure)
	need(P, "tick")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local a = w.tuning.actuation
	local window = w.tuning.instance.simultaneous_window_seconds
	local t = FinaleContract.T_ARM
	local armed = FinaleContract.arm(P, w, FinaleContract.liveFinale(P, w, "F-9"), A, t, "F-9")
	local now = t + window + 1
	local expired = P.tick(armed, w.assignment, now, bothAtTheirMachines(w))
	local problems: { string } = {}

	local state, result = turnBy(P, w, armed, A, Turn.requiredSetting(w.facility, A), now)
	if not Deep.equal(result, { kind = "refused", machineId = A, reason = "resetting" }) then
		table.insert(
			problems,
			`{Turn.holderOf(w.facility, A)} turning A ({A}) again at t + {window + 1}: result is {Deep.show(
				result
			)}, expected refused / resetting - its window expired at this now, so it is a resetting dial`
		)
	end
	if state.armed ~= nil then
		table.insert(
			problems,
			`after the late turn on A, state.armed is {Deep.show(state.armed)}, expected nil`
		)
	end
	if state.instability ~= armed.instability + a.instability_per_failed_pair then
		table.insert(
			problems,
			`after the late turn on A, instability is {Deep.show(state.instability)}, expected {armed.instability} + instability_per_failed_pair ({a.instability_per_failed_pair}) - the refusal is free but the expiry it applied first is not`
		)
	end
	if not Deep.equal(state, expired) then
		table.insert(
			problems,
			`the state a late refused turn returns differs from the post-expiry state tick returns at the same now:\n{Deep.diff(
				expired,
				state
			)}`
		)
	end

	local wrong = Turn.wrongSetting(w.facility, B, w.tuning)
	local state2, result2 = turnBy(P, w, armed, B, wrong, now)
	if not Deep.equal(result2, { kind = "rejected", machineId = B, reason = "wrong_setting" }) then
		table.insert(
			problems,
			`a WRONG turn on B ({B}) after the window: result is {Deep.show(result2)}, expected rejected / wrong_setting`
		)
	end
	local want2 = armed.instability + a.instability_per_failed_pair + a.instability_per_wrong_value
	if state2.instability ~= want2 then
		table.insert(
			problems,
			`a WRONG turn on B after the window left instability at {Deep.show(state2.instability)}, expected {armed.instability} + failed_pair ({a.instability_per_failed_pair}) + wrong_value ({a.instability_per_wrong_value}) = {want2}: the window had already closed, so this is an ordinary rejection after the expiry`
		)
	end
	if state2.armed ~= nil then
		table.insert(
			problems,
			`after the late wrong turn on B, state.armed is {Deep.show(state2.armed)}, expected nil`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`F-9: a turn arriving after the window applies the expiry first:\n{Contract.firstFew(
				problems,
				10
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-6. The partner lamps (F-11).
     --------------------------------------------------------------------- ]]

local function lampsAre(
	P: Procedure,
	w: World,
	state: any,
	positions: { [string]: Vec },
	want: { [number]: boolean },
	label: string,
	problems: { string }
)
	local lamps = P.partnerLamps(state, w.assignment, positions)
	if not Deep.equal(lamps, want) then
		table.insert(
			problems,
			`{label}: partnerLamps is {Deep.show(lamps)}, expected {Deep.show(want)}`
		)
	end
end

-- Both lamps are dark while the finale is not live - at start, with one
-- ordinary step left, and after the finale committed - even with both
-- holders standing at the partner machines.
function FinaleContract.bothLampsAreDarkWhileTheFinaleIsNotLive(P: Procedure)
	need(P, "partnerLamps")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local holderA, holderB = Turn.holderOf(w.facility, A), Turn.holderOf(w.facility, B)
	local positions = { [holderA] = Turn.at(w, A), [holderB] = Turn.at(w, B) }
	local dark = { [A] = false, [B] = false }
	local problems: { string } = {}
	lampsAre(P, w, started(P, w), positions, dark, "at start", problems)
	local state = started(P, w)
	local t = Turn.NOW
	for _, id in { 11, 14, 15, 16 } do
		t += 1
		state = commit(P, w, state, id, t, "AC-6")
	end
	lampsAre(P, w, state, positions, dark, "with ordinary step 12 left in track 1", problems)
	local live = commit(P, w, state, 12, t + 1, "AC-6")
	lampsAre(
		P,
		w,
		live,
		positions,
		{ [A] = true, [B] = true },
		"the moment the finale went live (both holders at their machines)",
		problems
	)
	local armed = FinaleContract.arm(P, w, live, A, FinaleContract.T_ARM, "AC-6")
	local done =
		turnBy(P, w, armed, B, Turn.requiredSetting(w.facility, B), FinaleContract.T_ARM + 1)
	lampsAre(P, w, done, positions, dark, "after the finale committed", problems)
	if #problems > 0 then
		Contract.fail(
			`AC-6/F-11: lamps while the finale is not live:\n{Contract.firstFew(problems, 8)}`
		)
	end
end

-- With the finale live: A's lamp is lit exactly when the holder of B's class
-- is within partner_lamp_range_studs of B (the fixture's 4, not turn range
-- 7), horizontally and inclusively, y ignored; a player absent from
-- positions is out of range; and B's lamp the same way round. `armed` does
-- not change the answer.
function FinaleContract.aLampIsLitExactlyWhenThePartnersHolderIsWithinLampRangeOfThePartnerMachine(
	P: Procedure
)
	need(P, "partnerLamps")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local holderA, holderB = Turn.holderOf(w.facility, A), Turn.holderOf(w.facility, B)
	local lamp = w.tuning.instance.partner_lamp_range_studs
	local reach = w.tuning.instance.turn_range_studs
	local live = FinaleContract.liveFinale(P, w, "AC-6")
	local armed = FinaleContract.arm(P, w, live, A, FinaleContract.T_ARM, "AC-6")
	local problems: { string } = {}
	local cases = {
		{
			label = `{holderB} at B ({B}), {holderA} absent`,
			positions = { [holderB] = Turn.at(w, B) },
			want = { [A] = true, [B] = false },
		},
		{
			label = `{holderA} at A ({A}), {holderB} absent`,
			positions = { [holderA] = Turn.at(w, A) },
			want = { [A] = false, [B] = true },
		},
		{ label = "nobody has a position", positions = {}, want = { [A] = false, [B] = false } },
		{
			label = `{holderB} exactly partner_lamp_range_studs ({lamp}) along x from B`,
			positions = { [holderB] = Turn.at(w, B, lamp, 0, 0) },
			want = { [A] = true, [B] = false },
		},
		{
			label = `{holderB} exactly partner_lamp_range_studs ({lamp}) along -z from B, 1000 studs up`,
			positions = { [holderB] = Turn.at(w, B, 0, 1000, -lamp) },
			want = { [A] = true, [B] = false },
		},
		{
			label = `{holderB} {lamp + 0.001} along x from B (just past the lamp range)`,
			positions = { [holderB] = Turn.at(w, B, lamp + 0.001, 0, 0) },
			want = { [A] = false, [B] = false },
		},
		{
			label = `{holderB} {lamp} along x AND {lamp} along z from B (sqrt(2) x range)`,
			positions = { [holderB] = Turn.at(w, B, lamp, 0, lamp) },
			want = { [A] = false, [B] = false },
		},
		{
			label = `{holderB} {reach} along x from B - inside turn_range_studs ({reach}) but outside partner_lamp_range_studs ({lamp})`,
			positions = { [holderB] = Turn.at(w, B, reach, 0, 0) },
			want = { [A] = false, [B] = false },
		},
		{
			label = `{holderB} standing at A ({A}) and {holderA} standing at B ({B}) - each at the OTHER machine`,
			positions = { [holderB] = Turn.at(w, A), [holderA] = Turn.at(w, B) },
			want = { [A] = false, [B] = false },
		},
		{
			label = `both holders at their own machines, a non-holder (kim) at B too`,
			positions = {
				[holderA] = Turn.at(w, A),
				[holderB] = Turn.at(w, B),
				kim = Turn.at(w, B),
			},
			want = { [A] = true, [B] = true },
		},
		{
			label = `only kim (holds neither finale class) at B`,
			positions = { kim = Turn.at(w, B) },
			want = { [A] = false, [B] = false },
		},
	}
	for _, c in cases do
		lampsAre(P, w, live, c.positions, c.want, `live, neither armed: {c.label}`, problems)
		lampsAre(P, w, armed, c.positions, c.want, `live, A armed: {c.label}`, problems)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-6/F-11: A's lamp is lit iff the holder of B's class is within partner_lamp_range_studs ({lamp}) of B, horizontally and inclusively, and B's the same way round:\n{Contract.firstFew(
				problems,
				12
			)}`
		)
	end
end

-- F-11: "some player p" - any holder of the class in range lights the lamp,
-- and one player holding both classes is not a special case: at B they light
-- A's lamp and not B's.
function FinaleContract.anyHolderOfThePartnersClassInRangeLightsTheLampAndOnePlayerHoldingBothIsNoSpecialCase(
	P: Procedure
)
	need(P, "partnerLamps")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local classA = Turn.machine(w.facility, A).keyClass
	local classB = Turn.machine(w.facility, B).keyClass
	local live = FinaleContract.liveFinale(P, w, "AC-6")
	local problems: { string } = {}

	-- Two holders of B's class (kim has been handed it); only kim is at B.
	local shared = Turn.assignment()
	shared.keyClasses.kim = { 1, classB }
	local w2: World = { facility = w.facility, assignment = shared, tuning = w.tuning }
	lampsAre(
		P,
		w2,
		live,
		{ kim = Turn.at(w, B), bob = Turn.at(w, 11) },
		{ [A] = true, [B] = false },
		`kim, holding classes \{ 1, {classB} }, at B while bob is rooms away`,
		problems
	)

	-- One player, bob, holding BOTH finale classes; amy is gone.
	local both = Turn.assignment()
	both.keyClasses.amy = nil
	both.keyClasses.bob = { classB, classA }
	local w3: World = { facility = w.facility, assignment = both, tuning = w.tuning }
	lampsAre(
		P,
		w3,
		live,
		{ bob = Turn.at(w, B) },
		{ [A] = true, [B] = false },
		`bob holding \{ {classB}, {classA} } standing at B`,
		problems
	)
	lampsAre(
		P,
		w3,
		live,
		{ bob = Turn.at(w, A) },
		{ [A] = false, [B] = true },
		`bob holding \{ {classB}, {classA} } standing at A`,
		problems
	)
	lampsAre(
		P,
		w3,
		live,
		{ bob = Turn.at(w, 11) },
		{ [A] = false, [B] = false },
		`bob holding \{ {classB}, {classA} } at neither`,
		problems
	)
	if #problems > 0 then
		Contract.fail(
			`AC-6/F-11: the lamp reads every holder of the partner's class:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     F-10. isComplete.
     --------------------------------------------------------------------- ]]

-- False at start, with every ordinary step committed, and with A armed; true
-- once both finale machines commit, decoys notwithstanding.
function FinaleContract.isCompleteIsTrueExactlyWhenEveryTrackMachineIsCommitted(P: Procedure)
	need(P, "isComplete")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local problems: { string } = {}
	local function expect(state: any, want: boolean, label: string)
		local got = P.isComplete(state)
		if got ~= want then
			table.insert(
				problems,
				`{label}: isComplete is {Deep.show(got)}, expected {Deep.show(want)}`
			)
		end
	end
	expect(started(P, w), false, "at start")
	local live = FinaleContract.liveFinale(P, w, "F-10")
	expect(live, false, "with every ordinary step committed and the finale live")
	local armed = FinaleContract.arm(P, w, live, A, FinaleContract.T_ARM, "F-10")
	expect(armed, false, `with {A} armed`)
	local done =
		turnBy(P, w, armed, B, Turn.requiredSetting(w.facility, B), FinaleContract.T_ARM + 1)
	expect(done, true, "with both finale machines committed (decoys 18 and 19 never turned)")
	if #problems > 0 then
		Contract.fail(`F-10: isComplete:\n{Contract.firstFew(problems, 8)}`)
	end
end

--[[ ------------------------------------------------------------------------
     F-12. Non-mutation.
     --------------------------------------------------------------------- ]]

-- tick (idle and expiring), partnerLamps, isComplete, and every finale kind
-- of turn (arming, completing, wrong-with-window, armed refusal, late turn)
-- leave their arguments deep-equal; and a later call on the NEW state does
-- not reach back into the old one.
function FinaleContract.noFinaleCallMutatesItsArguments(P: Procedure)
	need(P, "tick")
	need(P, "partnerLamps")
	need(P, "isComplete")
	local w = FinaleContract.world()
	local A, B = FinaleContract.A, FinaleContract.B
	local window = w.tuning.instance.simultaneous_window_seconds
	local t = FinaleContract.T_ARM
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
	local live = FinaleContract.liveFinale(P, w, "F-12")
	local positions = bothAtTheirMachines(w)
	local holderA, holderB = Turn.holderOf(w.facility, A), Turn.holderOf(w.facility, B)
	local reqA, reqB = Turn.requiredSetting(w.facility, A), Turn.requiredSetting(w.facility, B)

	guard(
		"partnerLamps",
		{ state = live, assignment = w.assignment, positions = positions },
		function()
			P.partnerLamps(live, w.assignment, positions)
		end
	)
	guard("isComplete", { state = live }, function()
		P.isComplete(live)
	end)
	local armed: any = nil
	guard(
		"an arming turn",
		{ state = live, assignment = w.assignment, positions = positions },
		function()
			armed = P.turn(live, w.assignment, holderA, A, reqA, t, positions)
		end
	)
	guard(
		"tick with the window open",
		{ state = armed, assignment = w.assignment, positions = positions },
		function()
			P.tick(armed, w.assignment, t + 1, positions)
		end
	)
	guard(
		"tick past the window",
		{ state = armed, assignment = w.assignment, positions = positions },
		function()
			P.tick(armed, w.assignment, t + window + 1, positions)
		end
	)
	guard(
		"a completing turn",
		{ state = armed, assignment = w.assignment, positions = positions },
		function()
			P.turn(armed, w.assignment, holderB, B, reqB, t + 1, positions)
		end
	)
	guard(
		"a wrong turn with the window open",
		{ state = armed, assignment = w.assignment, positions = positions },
		function()
			P.turn(
				armed,
				w.assignment,
				holderB,
				B,
				Turn.wrongSetting(w.facility, B, w.tuning),
				t + 1,
				positions
			)
		end
	)
	guard(
		"a refused turn (armed)",
		{ state = armed, assignment = w.assignment, positions = positions },
		function()
			P.turn(armed, w.assignment, holderA, A, reqA, t + 1, positions)
		end
	)
	guard(
		"a late correct turn on B",
		{ state = armed, assignment = w.assignment, positions = positions },
		function()
			P.turn(armed, w.assignment, holderB, B, reqB, t + window + 1, positions)
		end
	)
	guard(
		"partnerLamps with A armed",
		{ state = armed, assignment = w.assignment, positions = positions },
		function()
			P.partnerLamps(armed, w.assignment, positions)
		end
	)
	-- A later call on the NEW state does not reach back: completing from
	-- `armed` leaves `armed` and `live` as they were.
	local snapshotArmed = Deep.copy(armed)
	local snapshotLive = Deep.copy(live)
	local done = P.turn(armed, w.assignment, holderB, B, reqB, t + 1, positions)
	P.tick(done, w.assignment, t + window + 5, positions)
	if not Deep.equal(snapshotArmed, armed) then
		table.insert(
			problems,
			`completing the finale mutated the armed state it was handed:\n{Deep.diff(
				snapshotArmed,
				armed
			)}`
		)
	end
	if not Deep.equal(snapshotLive, live) then
		table.insert(
			problems,
			`a call two states downstream reached back into the live-finale state:\n{Deep.diff(
				snapshotLive,
				live
			)}`
		)
	end
	if #problems > 0 then
		Contract.fail(`F-12: an argument was mutated:\n{Contract.firstFew(problems, 8)}`)
	end
end

--[[ ------------------------------------------------------------------------
     The whole battery, named, so the controls can run every check against a
     stand-in and report exactly which ones fire.
     --------------------------------------------------------------------- ]]

export type Check = Turn.Check

FinaleContract.CHECKS = {
	{
		name = "startHasNoWindowAndTheNewExportsAnswerInShape",
		ac = "F-1",
		run = FinaleContract.startHasNoWindowAndTheNewExportsAnswerInShape,
	},
	{
		name = "neitherFinaleMachineIsLiveUntilTheLastOrdinaryStepCommitsThenBothAre",
		ac = "AC-1",
		run = FinaleContract.neitherFinaleMachineIsLiveUntilTheLastOrdinaryStepCommitsThenBothAre,
	},
	{
		name = "anArmedMachineIsStillLiveAndACommittedFinaleIsNot",
		ac = "AC-1",
		run = FinaleContract.anArmedMachineIsStillLiveAndACommittedFinaleIsNot,
	},
	{
		name = "correctTurnOnALiveFinaleMachineWithNeitherArmedArmsIt",
		ac = "AC-2",
		run = FinaleContract.correctTurnOnALiveFinaleMachineWithNeitherArmedArmsIt,
	},
	{
		name = "correctTurnOnTheOtherMachineInsideTheWindowCommitsBoth",
		ac = "AC-2",
		run = FinaleContract.correctTurnOnTheOtherMachineInsideTheWindowCommitsBoth,
	},
	{
		name = "turnOnTheOtherMachineAtExactlyTheWindowsEndCommitsBoth",
		ac = "AC-7",
		run = FinaleContract.turnOnTheOtherMachineAtExactlyTheWindowsEndCommitsBoth,
	},
	{
		name = "tickAtOrBeforeTheWindowsEndChangesNothing",
		ac = "AC-7",
		run = FinaleContract.tickAtOrBeforeTheWindowsEndChangesNothing,
	},
	{
		name = "tickPastTheWindowDisarmsBothAndChargesExactlyOneFailedPair",
		ac = "AC-3",
		run = FinaleContract.tickPastTheWindowDisarmsBothAndChargesExactlyOneFailedPair,
	},
	{
		name = "afterExpiryTheArmedMachineResetsLikeAnyRejectionThenCanArmAgain",
		ac = "AC-3",
		run = FinaleContract.afterExpiryTheArmedMachineResetsLikeAnyRejectionThenCanArmAgain,
	},
	{
		name = "underTheShippedTuningAnExpiredWindowCostsExactlyOne",
		ac = "AC-3",
		run = FinaleContract.underTheShippedTuningAnExpiredWindowCostsExactlyOne,
	},
	{
		name = "wrongTurnOnTheOtherMachineInsideTheWindowIsRejectedOnceAndDisarmsBoth",
		ac = "AC-4",
		run = FinaleContract.wrongTurnOnTheOtherMachineInsideTheWindowIsRejectedOnceAndDisarmsBoth,
	},
	{
		name = "underTheShippedTuningAWrongTurnWithTheWindowOpenCostsOneNotTwo",
		ac = "AC-4",
		run = FinaleContract.underTheShippedTuningAWrongTurnWithTheWindowOpenCostsOneNotTwo,
	},
	{
		name = "wrongTurnOnALiveFinaleMachineWithNoWindowOpenIsAnOrdinaryRejection",
		ac = "AC-4",
		run = FinaleContract.wrongTurnOnALiveFinaleMachineWithNoWindowOpenIsAnOrdinaryRejection,
	},
	{
		name = "turnOnTheArmedMachineIsRefusedArmedAtNoCost",
		ac = "AC-5",
		run = FinaleContract.turnOnTheArmedMachineIsRefusedArmedAtNoCost,
	},
	{
		name = "armedIsTheLastRefusalChecked",
		ac = "AC-5",
		run = FinaleContract.armedIsTheLastRefusalChecked,
	},
	{
		name = "aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt",
		ac = "F-9",
		run = FinaleContract.aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt,
	},
	{
		name = "aTurnAfterTheWindowReturnsThePostExpiryState",
		ac = "F-9",
		run = FinaleContract.aTurnAfterTheWindowReturnsThePostExpiryState,
	},
	{
		name = "bothLampsAreDarkWhileTheFinaleIsNotLive",
		ac = "AC-6",
		run = FinaleContract.bothLampsAreDarkWhileTheFinaleIsNotLive,
	},
	{
		name = "aLampIsLitExactlyWhenThePartnersHolderIsWithinLampRangeOfThePartnerMachine",
		ac = "AC-6",
		run = FinaleContract.aLampIsLitExactlyWhenThePartnersHolderIsWithinLampRangeOfThePartnerMachine,
	},
	{
		name = "anyHolderOfThePartnersClassInRangeLightsTheLampAndOnePlayerHoldingBothIsNoSpecialCase",
		ac = "AC-6",
		run = FinaleContract.anyHolderOfThePartnersClassInRangeLightsTheLampAndOnePlayerHoldingBothIsNoSpecialCase,
	},
	{
		name = "isCompleteIsTrueExactlyWhenEveryTrackMachineIsCommitted",
		ac = "F-10",
		run = FinaleContract.isCompleteIsTrueExactlyWhenEveryTrackMachineIsCommitted,
	},
	{
		name = "noFinaleCallMutatesItsArguments",
		ac = "F-12",
		run = FinaleContract.noFinaleCallMutatesItsArguments,
	},
} :: { Check }

-- Run every check against `P`; the names of those that raised, with their
-- messages, in CHECKS order.
function FinaleContract.failures(P: Procedure): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in FinaleContract.CHECKS do
		local ok, err = pcall(check.run, P)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return FinaleContract
