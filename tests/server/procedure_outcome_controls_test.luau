--!strict
--[[
	The negative controls for PROC-003, and the proof that each check in
	`tests/helpers/OutcomeContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/procedure/Procedure.luau` LOADS but has no `deadline`,
	`isDark`, `blackoutWeights` or `drawRoom` and no clock, blackout or
	outcome, so every test in `tests/server/procedure_outcome_test.luau` fails
	on its first assertion - and not one of that file's checks has been
	observed to ACCEPT anything. The stand-ins below need only `Machines`,
	`Rng`, `MechanicsTuning`, `Tuning` and `Deep`, which are merged, so what is
	asserted here is MEASURED in RED rather than claimed for GREEN. The story's
	handoff carries the table.

	THE STAND-INS. `standIn(defects)` is a small implementation of PROC-001's
	P-1..P-11, PROC-002's F-1..F-12 and this story's I-1..I-10 with named
	defects switched on. With none it is the REFERENCE, the positive control:
	every OutcomeContract check AND every TurnContract and FinaleContract check
	must ACCEPT it - the second half is the mechanical form of the story's
	"re-read every PROC-001/002 check against I-6" audit. Each control is the
	reference with EXACTLY ONE defect, so the set of checks that fire is
	attributable to that one defect, and each control pins that set EXACTLY -
	a check that fires on a control it should not is as much a finding as one
	that stays quiet.

	THE CONTROLS THE STORY AND THE RED BRIEF NAME:
	  * AC-3: a UNIFORM draw must fail both clauses - it picks the zero-weight
	    rooms, and scores about 0.5 on the frequency (the number is printed);
	  * AC-6: an implementation that checks the clock BEFORE instability must
	    fail the second clause;
	  * AC-7: no outcome guard - a decided round keeps evaluating;
	  * AC-2: a blackout fired AT instability_max;
	  * AC-5 / I-1: the draw reads the wrong sub-stream, or ignores
	    `blackoutDraws` and reads the first value every time;
	  * I-3: the clock out at `now > deadline` instead of `>=`.
	D-1..D-4 THEMSELVES are mutations of the real module and stay with GATES;
	what is measured here is that the checks WOULD see them.

	WHAT THE REFERENCE IS NOT: `src/server/procedure/Procedure.luau`, or a
	sketch of one. It is untyped, copies state the slow way, and reads nothing
	the Contract does not name. GREEN writes the module from the story's
	Contract against `procedure_outcome_test.luau`; nothing here is to be copied.
]]

local Deep = require("../helpers/Deep")
local Finale = require("../helpers/FinaleContract")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Outcome = require("../helpers/OutcomeContract")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")
local Tuning = require("../../src/ReplicatedStorage/Shared/Tuning")
local Turn = require("../helpers/TurnContract")

type Defects = {
	uniformDraw: boolean?, -- AC-3: drawRoom ignores the weights
	clockBeforeInstability: boolean?, -- AC-6: lost / clock judged before lost / instability
	noOutcomeGuard: boolean?, -- AC-7: turn and tick keep working on a decided round
	blackoutAtMax: boolean?, -- AC-2: a crossing at v == instability_max
	wrongStream: boolean?, -- I-1: derive("instance") instead of "blackout"
	ignoresBlackoutDraws: boolean?, -- I-1: every draw is the stream's first
	clockOutStrictlyAfter: boolean?, -- I-3: out at now > deadline
}

local function standIn(defects: Defects): Turn.Procedure
	local P = {}

	local function machineOf(facility: any, id: number): any
		for _, m in facility.placement.machines do
			if m.id == id then
				return m
			end
		end
		return nil
	end

	local function isFinale(facility: any, id: number): boolean
		return table.find(facility.steps.finale, id) ~= nil
	end

	local function inATrack(facility: any, id: number): boolean
		for _, track in facility.steps.tracks do
			if table.find(track, id) ~= nil then
				return true
			end
		end
		return false
	end

	local function ordinaryDone(state: any): boolean
		for _, track in state.facility.steps.tracks do
			for k = 1, #track - 1 do
				if not state.committed[track[k]] then
					return false
				end
			end
		end
		return true
	end

	function P.start(
		facility: any,
		now: number,
		tuning: any,
		roundSeed: number,
		roundSeconds: number
	): any
		return {
			facility = facility,
			committed = {},
			dials = {},
			instability = 0,
			log = {},
			tuning = tuning,
			startedAt = now,
			roundSeconds = roundSeconds,
			penaltySeconds = 0,
			dark = {},
			outcome = nil,
			roundSeed = roundSeed,
			blackoutDraws = 0,
		}
	end

	function P.isLive(state: any, id: number): boolean
		local facility = state.facility
		if isFinale(facility, id) then
			return not state.committed[id] and ordinaryDone(state)
		end
		for _, track in facility.steps.tracks do
			for k, stepId in track do
				if not state.committed[stepId] then
					if stepId == id and k < #track then
						return true
					end
					break
				end
			end
		end
		return false
	end

	local function resetting(state: any, id: number, now: number): boolean
		local d = state.dials[id]
		return d ~= nil and d.rejectedUntil ~= nil and now < d.rejectedUntil
	end

	function P.dial(state: any, id: number, now: number): any
		local d = state.dials[id]
		if state.committed[id] then
			return { setting = d.setting, state = "committed" }
		end
		if resetting(state, id, now) then
			return { setting = d.setting, state = "rejected" }
		end
		return { setting = nil, state = "unset" }
	end

	local function copy(state: any): any
		local next_ = table.clone(state)
		next_.committed = table.clone(state.committed)
		next_.dials = Deep.copy(state.dials)
		next_.log = table.clone(state.log)
		next_.dark = table.clone(state.dark)
		next_.armed = if state.armed then table.clone(state.armed) else nil
		next_.outcome = if state.outcome then table.clone(state.outcome) else nil
		return next_
	end

	function P.isComplete(state: any): boolean
		for _, track in state.facility.steps.tracks do
			for _, id in track do
				if not state.committed[id] then
					return false
				end
			end
		end
		return true
	end

	-- I-3.
	function P.deadline(state: any): number
		return state.startedAt + state.roundSeconds - state.penaltySeconds
	end

	local function clockOut(state: any, now: number): boolean
		return if defects.clockOutStrictlyAfter
			then now > P.deadline(state)
			else now >= P.deadline(state)
	end

	-- I-9.
	function P.isDark(state: any, room: number): boolean
		return state.dark[room] == true
	end

	-- I-5: every lit room -> the sum over its uncommitted track machines.
	function P.blackoutWeights(state: any): any
		local a = state.tuning.actuation
		local weights = {}
		for _, room in state.facility.layout.rooms do
			if not state.dark[room.id] then
				weights[room.id] = 0
			end
		end
		for _, m in state.facility.placement.machines do
			if
				weights[m.room] ~= nil
				and inATrack(state.facility, m.id)
				and not state.committed[m.id]
			then
				weights[m.room] += if P.isLive(state, m.id)
					then a.blackout_weight_live_step
					else a.blackout_weight_waiting_step
			end
		end
		return weights
	end

	-- I-5: one nextInteger per non-nil draw.
	function P.drawRoom(weights: any, rng: any): number?
		local rooms = {}
		local total = 0
		for room, weight in pairs(weights) do
			table.insert(rooms, room)
			total += weight
		end
		table.sort(rooms)
		if #rooms == 0 then
			return nil
		end
		if total > 0 and not defects.uniformDraw then
			local r = rng:nextInteger(1, total)
			local cumulative = 0
			for _, room in rooms do
				cumulative += weights[room]
				if cumulative >= r then
					return room
				end
			end
		end
		return rooms[rng:nextInteger(1, #rooms)]
	end

	-- I-1: the stream, advanced by the draws already made.
	local function stream(state: any): any
		local s = Rng.fromSeed(state.roundSeed)
			:derive(if defects.wrongStream then "instance" else "blackout")
		if not defects.ignoresBlackoutDraws then
			for _ = 1, state.blackoutDraws do
				s:nextNumber()
			end
		end
		return s
	end

	-- I-3, I-4 and I-6's post-charge check, on a fresh copy `next_`.
	local function charge(next_: any, points: number, now: number)
		local a = next_.tuning.actuation
		local old = next_.instability
		local new = old + points
		next_.instability = new
		next_.penaltySeconds += points * a.instability_clock_penalty_seconds
		for v = old + 1, new do
			if
				v % a.instability_blackout_threshold == 0
				and (v < a.instability_max or defects.blackoutAtMax)
			then
				for _ = 1, a.blackout_rooms_per_threshold do
					local room = P.drawRoom(P.blackoutWeights(next_), stream(next_))
					if room == nil then
						break
					end
					next_.dark[room] = true
					next_.blackoutDraws += 1
				end
			end
		end
		if next_.outcome ~= nil then
			return
		end
		if defects.clockBeforeInstability then
			if clockOut(next_, now) then
				next_.outcome = { result = "lost", reason = "clock" }
			elseif new >= a.instability_max then
				next_.outcome = { result = "lost", reason = "instability" }
			end
		elseif new >= a.instability_max then
			next_.outcome = { result = "lost", reason = "instability" }
		elseif clockOut(next_, now) then
			next_.outcome = { result = "lost", reason = "clock" }
		end
	end

	local function expired(state: any, now: number): boolean
		return state.armed ~= nil and now > state.armed.closesAt
	end

	-- F-8 on a state whose window HAS expired at `now`, charged through I-3/I-4.
	local function expire(state: any, now: number): any
		local a = state.tuning.actuation
		local next_ = copy(state)
		local A = state.armed.machineId
		next_.dials[A] =
			{ setting = state.dials[A].setting, rejectedUntil = now + a.actuation_reset_seconds }
		next_.armed = nil
		charge(next_, a.instability_per_failed_pair, now)
		return next_
	end

	-- I-6 steps 1..3, shared by tick and turn. Returns the state to continue
	-- from and whether the round is decided at the end of step 3.
	local function settle(state: any, now: number): (any, boolean)
		local decidedBefore = state.outcome ~= nil
		if decidedBefore and not defects.noOutcomeGuard then
			return state, true
		end
		local s = state
		if expired(s, now) then
			s = expire(s, now)
		end
		if s.outcome == nil and clockOut(s, now) then
			s = copy(s)
			s.outcome = { result = "lost", reason = "clock" }
		end
		if defects.noOutcomeGuard and decidedBefore then
			-- The defect: a decided round is treated as live.
			return s, false
		end
		return s, s.outcome ~= nil
	end

	function P.tick(state: any, _assignment: any, now: number, _positions: any): (any, any)
		local s = settle(state, now)
		return s, s.outcome
	end

	local function within(p: any, m: any, range: number): boolean
		local dx, dz = p.x - m.x, p.z - m.z
		return math.sqrt(dx * dx + dz * dz) <= range
	end

	function P.partnerLamps(state: any, assignment: any, positions: any): any
		local facility = state.facility
		local tuning = state.tuning
		local lamps = {}
		local finale = facility.steps.finale
		local live = P.isLive(state, finale[1]) and P.isLive(state, finale[2])
		for i, id in finale do
			local partner = machineOf(facility, finale[3 - i])
			local lit = false
			if live then
				local mp = Machines.positionOf(facility.layout, partner, tuning)
				for player, classes in pairs(assignment.keyClasses) do
					local p = positions[player]
					if
						p ~= nil
						and table.find(classes, partner.keyClass) ~= nil
						and within(p, mp, tuning.instance.partner_lamp_range_studs)
					then
						lit = true
					end
				end
			end
			lamps[id] = lit
		end
		return lamps
	end

	local function rejected(
		state: any,
		playerId: string,
		id: number,
		setting: number,
		now: number,
		reason: string
	): (any, any)
		local a = state.tuning.actuation
		local next_ = copy(state)
		next_.dials[id] = { setting = setting, rejectedUntil = now + a.actuation_reset_seconds }
		table.insert(
			next_.log,
			{ playerId = playerId, machineId = id, setting = setting, at = now, result = reason }
		)
		if state.armed ~= nil then
			-- F-7: the window closes, both disarm, no second penalty.
			local A = state.armed.machineId
			next_.dials[A] = {
				setting = state.dials[A].setting,
				rejectedUntil = now + a.actuation_reset_seconds,
			}
			next_.armed = nil
		end
		charge(
			next_,
			if reason == "not_live"
				then a.instability_per_out_of_order
				else a.instability_per_wrong_value,
			now
		)
		return next_, { kind = "rejected", machineId = id, reason = reason }
	end

	function P.turn(
		state0: any,
		assignment: any,
		playerId: string,
		id: number,
		setting: number,
		now: number,
		positions: any
	): (any, any)
		local state, decided = settle(state0, now)
		if decided then
			return state, { kind = "refused", machineId = id, reason = "round_over" }
		end
		local tuning = state.tuning
		local facility = state.facility
		local m = machineOf(facility, id)
		if m == nil then
			return state, { kind = "refused", machineId = id, reason = "unknown_machine" }
		end
		local held = assignment.keyClasses[playerId]
		if held == nil or table.find(held, m.keyClass) == nil then
			return state, { kind = "refused", machineId = id, reason = "not_key_holder" }
		end
		local p = positions[playerId]
		if
			p == nil
			or not within(
				p,
				Machines.positionOf(facility.layout, m, tuning),
				tuning.instance.turn_range_studs
			)
		then
			return state, { kind = "refused", machineId = id, reason = "out_of_reach" }
		end
		if state.committed[id] then
			return state, { kind = "refused", machineId = id, reason = "committed" }
		end
		if resetting(state, id, now) then
			return state, { kind = "refused", machineId = id, reason = "resetting" }
		end
		if state.armed ~= nil and state.armed.machineId == id then
			return state, { kind = "refused", machineId = id, reason = "armed" }
		end

		if not P.isLive(state, id) then
			return rejected(state, playerId, id, setting, now, "not_live")
		end
		if setting ~= m.requiredSetting then
			return rejected(state, playerId, id, setting, now, "wrong_setting")
		end

		local next_ = copy(state)
		if isFinale(facility, id) then
			if state.armed == nil then
				next_.armed =
					{ machineId = id, closesAt = now + tuning.instance.simultaneous_window_seconds }
				next_.dials[id] = { setting = setting }
				table.insert(next_.log, {
					playerId = playerId,
					machineId = id,
					setting = setting,
					at = now,
					result = "armed",
				})
				return next_, { kind = "armed", machineId = id }
			end
			next_.committed[state.armed.machineId] = true
			next_.armed = nil
		end
		next_.committed[id] = true
		next_.dials[id] = { setting = setting }
		table.insert(next_.log, {
			playerId = playerId,
			machineId = id,
			setting = setting,
			at = now,
			result = "committed",
		})
		if P.isComplete(next_) then
			next_.outcome = { result = "won", reason = "procedure_complete" }
		end
		return next_, { kind = "committed", machineId = id }
	end

	return P
end

local reference = standIn({})

local function failingNames(P: Turn.Procedure): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Outcome.failures(P) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(who: string, P: Turn.Procedure, expected: { string })
	local names, messages = failingNames(P)
	local want = table.clone(expected)
	table.sort(want)
	print(`        [measured] {who} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`{who} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{table.concat(
				shown,
				"\n"
			)}`,
			0
		)
	end
	local byName: { [string]: Outcome.Check } = {}
	for _, check in Outcome.CHECKS do
		byName[check.name] = check
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac, 1, true) ~= nil,
			`{who}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end
end

-- The outcome a stand-in records when the sixth point reaches the max and
-- its penalty takes a 49 s round's clock below 0 - the AC-6 control's
-- NUMBER, measured here rather than described.
local function sixthPointOutcome(P: Turn.Procedure): string
	local w = Outcome.world()
	local t0 = Outcome.NOW
	local function wrongOn(state: any, id: number, now: number): any
		local holder = Turn.holderOf(w.facility, id)
		return (
			P.turn(
				state,
				w.assignment,
				holder,
				id,
				Turn.wrongSetting(w.facility, id, w.tuning),
				now,
				Turn.standingAt(w, holder, id)
			)
		)
	end
	local function decoyOn(state: any, id: number, now: number): any
		local holder = Turn.holderOf(w.facility, id)
		return (
			P.turn(
				state,
				w.assignment,
				holder,
				id,
				Turn.requiredSetting(w.facility, id),
				now,
				Turn.standingAt(w, holder, id)
			)
		)
	end
	local state = P.start(w.facility, t0, w.tuning, Outcome.ROUND_SEED, 49)
	state = wrongOn(state, 11, t0)
	state = wrongOn(state, 14, t0 + 1)
	state = decoyOn(state, 18, t0 + 2)
	state = wrongOn(state, 11, t0 + 5)
	state = wrongOn(state, 14, t0 + 110 - 100)
	return if state.outcome then `{state.outcome.result} / {state.outcome.reason}` else "nil"
end

-- The number of dark rooms a stand-in has once the sixth point reaches the
-- max (threshold 3, two rooms per crossing): 2 for the reference, 4 for a
-- blackout fired at the max.
local function darkAtMax(P: Turn.Procedure): number
	local w = Outcome.world()
	local t0 = Outcome.NOW
	local function turnOn(state: any, id: number, setting: number, now: number): any
		local holder = Turn.holderOf(w.facility, id)
		return (
			P.turn(state, w.assignment, holder, id, setting, now, Turn.standingAt(w, holder, id))
		)
	end
	local wrong = function(id: number): number
		return Turn.wrongSetting(w.facility, id, w.tuning)
	end
	local state = P.start(w.facility, t0, w.tuning, Outcome.ROUND_SEED, Outcome.ROUND_SECONDS)
	state = turnOn(state, 11, wrong(11), t0)
	state = turnOn(state, 14, wrong(14), t0 + 1)
	state = turnOn(state, 18, Turn.requiredSetting(w.facility, 18), t0 + 2)
	state = turnOn(state, 11, wrong(11), t0 + 5)
	state = turnOn(state, 14, wrong(14), t0 + 6)
	return #Outcome.darkRooms(state)
end

return {
	--[[ ================================================================
	     The reference. Everything below is this stand-in with one defect.
	     ================================================================ ]]

	["baseline: the reference stand-in passes every check in OutcomeContract - the checks accept a correct implementation of I-1..I-10"] = function()
		local names, messages = failingNames(reference)
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		if #names > 0 then
			error(
				`the reference fails {#names} check(s), so the check or the fixture is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#Outcome.CHECKS} outcome checks`)
	end,

	["audit: the outcome reference stand-in also passes every PROC-001 check in TurnContract and every PROC-002 check in FinaleContract - I-1..I-10 leave both stories' criteria intact once their fixtures carry roundSeconds and room below the max"] = function()
		local shown: { string } = {}
		for _, f in Turn.failures(reference) do
			table.insert(shown, `TurnContract.{f.name}: {f.message}`)
		end
		for _, f in Finale.failures(reference) do
			table.insert(shown, `FinaleContract.{f.name}: {f.message}`)
		end
		if #shown > 0 then
			error(
				`the outcome reference fails {#shown} PROC-001/002 check(s), so a check there still pins behaviour I-6 changes:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(
			`        [measured] reference fails 0 of {#Turn.CHECKS} PROC-001 checks and 0 of {#Finale.CHECKS} PROC-002 checks`
		)
	end,

	--[[ ================================================================
	     The fixture's assumptions, checked against what they are read from.
	     ================================================================ ]]

	["fixtures: every override differs from its shipped value and from every other constant a check must tell it from; the max is a multiple of the threshold; the shipped values the literal checks read are what tuning.md says"] = function()
		local t = Outcome.world().tuning
		local s = MechanicsTuning
		local problems: { string } = {}
		local function distinct(label: string, a: number, b: number)
			if a == b then
				table.insert(problems, `{label}: both {a}`)
			end
		end
		distinct(
			"instability_clock_penalty_seconds vs shipped",
			t.actuation.instability_clock_penalty_seconds,
			s.actuation.instability_clock_penalty_seconds
		)
		distinct(
			"instability_blackout_threshold vs shipped",
			t.actuation.instability_blackout_threshold,
			s.actuation.instability_blackout_threshold
		)
		distinct(
			"blackout_rooms_per_threshold vs shipped",
			t.actuation.blackout_rooms_per_threshold,
			s.actuation.blackout_rooms_per_threshold
		)
		distinct(
			"instability_max vs shipped",
			t.actuation.instability_max,
			s.actuation.instability_max
		)
		distinct(
			"blackout_weight_live_step vs waiting",
			t.actuation.blackout_weight_live_step,
			t.actuation.blackout_weight_waiting_step
		)
		distinct(
			"blackout_weight_live_step vs shipped",
			t.actuation.blackout_weight_live_step,
			s.actuation.blackout_weight_live_step
		)
		distinct(
			"blackout_weight_waiting_step vs shipped",
			t.actuation.blackout_weight_waiting_step,
			s.actuation.blackout_weight_waiting_step
		)
		distinct(
			"instability_per_wrong_value vs out_of_order",
			t.actuation.instability_per_wrong_value,
			t.actuation.instability_per_out_of_order
		)
		if t.actuation.blackout_rooms_per_threshold < 2 then
			table.insert(
				problems,
				`blackout_rooms_per_threshold override is {t.actuation.blackout_rooms_per_threshold}; "exactly blackout_rooms_per_threshold" needs at least 2 to be told from 1`
			)
		end
		if t.actuation.instability_max % t.actuation.instability_blackout_threshold ~= 0 then
			table.insert(
				problems,
				`instability_max {t.actuation.instability_max} is not a multiple of the threshold {t.actuation.instability_blackout_threshold}; a blackout fired at the max would be invisible`
			)
		end
		if t.actuation.instability_max ~= 6 or t.actuation.instability_blackout_threshold ~= 3 then
			table.insert(problems, "the AC-2/AC-6 scenarios are written for max 6, threshold 3")
		end
		-- What the literal shipped-tuning checks read out.
		local shipped = {
			{ "Tuning.round.round_seconds", Tuning.round.round_seconds, 420 },
			{
				"instability_clock_penalty_seconds",
				s.actuation.instability_clock_penalty_seconds,
				20,
			},
			{ "instability_max", s.actuation.instability_max, 5 },
			{ "instability_blackout_threshold", s.actuation.instability_blackout_threshold, 2 },
			{ "blackout_rooms_per_threshold", s.actuation.blackout_rooms_per_threshold, 1 },
			{ "instability_per_wrong_value", s.actuation.instability_per_wrong_value, 1 },
			{ "instability_per_out_of_order", s.actuation.instability_per_out_of_order, 1 },
		}
		for _, row in shipped do
			if row[2] ~= row[3] then
				table.insert(
					problems,
					`the shipped {row[1]} is {row[2]}; the literal AC-1/AC-6 checks assume {row[3]} (tuning.md)`
				)
			end
		end
		assert(
			#problems == 0,
			`the fixture's tuning no longer discriminates:\n{table.concat(problems, "\n")}`
		)
	end,

	["fixtures: WEIGHTS_AT_START is what the TurnContract facility weighs under the overrides, recomputed here from the placement and the tracks without the module"] = function()
		local w = Outcome.world()
		local a = w.tuning.actuation
		local f = w.facility
		local weights: { [number]: number } = {}
		for _, room in f.layout.rooms do
			weights[room.id] = 0
		end
		for t, track in f.steps.tracks do
			for k, id in track do
				local m = Turn.machine(f, id)
				assert(m ~= nil, `track {t} names machine {id}, which the placement lacks`)
				-- At start the head of each track is live; every other step waits.
				weights[m.room] += if k == 1
					then a.blackout_weight_live_step
					else a.blackout_weight_waiting_step
			end
		end
		assert(
			Deep.equal(weights, Outcome.WEIGHTS_AT_START),
			`the fixture weighs {Deep.show(weights)} at start, but WEIGHTS_AT_START says {Deep.show(
				Outcome.WEIGHTS_AT_START
			)}`
		)
	end,

	["fixtures: the hand-built three-room facility puts every track step in room 1, only a decoy in room 2, the first step of track 1 and a decoy in room 3, with no machine at the list index equal to its id"] = function()
		local f = Outcome.oneRoomFacility()
		local problems: { string } = {}
		local byId: { [number]: any } = {}
		for i, m in f.placement.machines do
			if m.id == i then
				table.insert(problems, `machines[{i}].id == {i}`)
			end
			if byId[m.id] then
				table.insert(problems, `id {m.id} appears twice`)
			end
			byId[m.id] = m
		end
		local inTrack: { [number]: boolean } = {}
		for t, track in f.steps.tracks do
			for _, id in track do
				inTrack[id] = true
				local m = byId[id]
				if m == nil then
					table.insert(problems, `track {t} names {id}, which the placement lacks`)
				elseif id ~= Outcome.ONE_FIRST and m.room ~= Outcome.ONE_STEP_ROOM then
					table.insert(
						problems,
						`step {id} is in room {m.room}, expected room {Outcome.ONE_STEP_ROOM}`
					)
				end
			end
		end
		if byId[Outcome.ONE_FIRST].room ~= 3 then
			table.insert(
				problems,
				`machine {Outcome.ONE_FIRST} is in room {byId[Outcome.ONE_FIRST].room}, expected 3`
			)
		end
		if f.steps.tracks[1][1] ~= Outcome.ONE_FIRST then
			table.insert(problems, `track 1 does not start with {Outcome.ONE_FIRST}`)
		end
		local decoyRooms: { [number]: number } = {}
		for _, id in Outcome.ONE_DECOYS do
			if inTrack[id] then
				table.insert(problems, `decoy {id} is in a track`)
			end
			decoyRooms[byId[id].room] = (decoyRooms[byId[id].room] or 0) + 1
		end
		if not Deep.equal(decoyRooms, { [2] = 1, [3] = 1 }) then
			table.insert(
				problems,
				`decoys sit in rooms {Deep.show(decoyRooms)}, expected one in room 2 and one in room 3`
			)
		end
		for id, m in pairs(byId) do
			if not inTrack[id] and table.find(Outcome.ONE_DECOYS, id) == nil then
				table.insert(
					problems,
					`machine {id} (room {m.room}) is neither a step nor a listed decoy`
				)
			end
		end
		if
			not Deep.equal(
				f.steps.finale,
				{ f.steps.tracks[1][#f.steps.tracks[1]], f.steps.tracks[2][#f.steps.tracks[2]] }
			)
		then
			table.insert(problems, "finale is not the tracks' last steps")
		end
		-- Every machine's position is distinct, and reachable by its holder at it.
		local seen: { [string]: number } = {}
		local w = Outcome.oneRoomWorld()
		for id in pairs(byId) do
			local p = Turn.at(w, id)
			local key = `{p.x},{p.z}`
			if seen[key] then
				table.insert(problems, `machines {seen[key]} and {id} share position ({key})`)
			end
			seen[key] = id
		end
		assert(
			#problems == 0,
			`the hand-built facility is not what AC-3/AC-4 assume:\n{table.concat(problems, "\n")}`
		)
	end,

	--[[ ================================================================
	     The controls. Each fires exactly the checks named.
	     ================================================================ ]]

	["AC-3 control: a UNIFORM draw scores about 0.5 on the frequency (measured, printed), picks zero-weight rooms, and fails exactly the zero-weight check, the frequency check and the drawRoom mapping check"] = function()
		local P = standIn({ uniformDraw = true })
		local uniform = Outcome.heavierRoomFrequency(P, Outcome.ROUND_SEED)
		local weighted = Outcome.heavierRoomFrequency(reference, Outcome.ROUND_SEED)
		print(
			`        [measured] heavier-room frequency over {Outcome.FREQUENCY_DRAWS} draws, seed {Outcome.ROUND_SEED}: reference {weighted}, uniform control {uniform}`
		)
		local band = Outcome.FREQUENCY_BAND
		assert(
			weighted >= band.low and weighted <= band.high,
			`the reference's frequency {weighted} is outside [{band.low}, {band.high}]`
		)
		assert(
			uniform > 0.45 and uniform < 0.55,
			`the uniform control's frequency {uniform} is not about 0.5`
		)
		expectFires("uniform-draw", P, {
			"oneLitRoomHoldingEveryUncommittedStepIsAlwaysTheOneDarkened",
			"theHeavierOfTwoRoomsIsDrawnThreeTimesInFour",
			"drawRoomMapsTheDrawToTheFirstRoomWhoseCumulativeWeightReachesIt",
		})
	end,

	["AC-6 control: checking the clock BEFORE instability records lost / clock where the sixth point reaches the max and zeroes the clock (measured), and fails exactly the ordering check"] = function()
		local P = standIn({ clockBeforeInstability = true })
		local control = sixthPointOutcome(P)
		local ref = sixthPointOutcome(reference)
		print(
			`        [measured] sixth-point outcome, 49 s round: reference {ref}, clock-first control {control}`
		)
		assert(
			ref == "lost / instability",
			`the reference records {ref}, expected lost / instability`
		)
		assert(
			control == "lost / clock",
			`the clock-first control records {control}, expected lost / clock`
		)
		expectFires("clock-before-instability", P, {
			"instabilityMaxAndTheClockInOneTurnRecordInstability",
		})
	end,

	["AC-7 control: no outcome guard - a decided round keeps evaluating turns and expiring windows - fails exactly the decided-round check"] = function()
		expectFires("no-outcome-guard", standIn({ noOutcomeGuard = true }), {
			"aDecidedRoundStaysDecided",
		})
	end,

	["AC-2 control: a blackout fired AT instability_max darkens four rooms where two are expected (measured), and fails exactly the max-darkens-nothing check and the expiry-to-the-max check"] = function()
		local P = standIn({ blackoutAtMax = true })
		local control = darkAtMax(P)
		local ref = darkAtMax(reference)
		print(
			`        [measured] dark rooms at the max (threshold 3, 2 per crossing): reference {ref}, blackout-at-max control {control}`
		)
		assert(ref == 2, `the reference has {ref} dark rooms at the max, expected 2`)
		assert(
			control == 4,
			`the blackout-at-max control has {control} dark rooms at the max, expected 4`
		)
		expectFires("blackout-at-max", P, {
			"reachingInstabilityMaxEndsTheRoundWithoutAnotherBlackout",
			"tickExpiryChargesTheClockCrossesTheThresholdAndCanEndTheRound",
		})
	end,

	['I-1 control: drawing from derive("instance") instead of derive("blackout") fails the five checks that predict WHICH rooms go dark on the independent stream, and nothing else'] = function()
		-- Not `tickExpiryCharges...`: there the only weighted rooms are the two
		-- finale rooms and two draws take both, whatever the stream says. Not
		-- `isDarkIsTrue...`: it pins persistence, not which rooms.
		expectFires("wrong-stream", standIn({ wrongStream = true }), {
			"crossingTheThresholdDarkensExactlyRoomsPerThresholdByTheWeightedDraw",
			"aChargeThatJumpsOverTheMultipleStillCrossesIt",
			"reachingInstabilityMaxEndsTheRoundWithoutAnotherBlackout",
			"everyLitRoomAtWeightZeroStillDarkensOneAndNoneLitDoesNothing",
			"theSameSeedReplaysTheSameRoomsInTheSameOrder",
		})
	end,

	["I-1 control: a draw that ignores blackoutDraws (every draw is the stream's first value) fails exactly the four-crossing replay check - the only check whose third draw can differ"] = function()
		-- MEASURED, not predicted: on seed 9001 the stream's first value maps
		-- to the same room as the reference's second draw in every two-draw
		-- check (room 1 then 2 over { 7, 7, 4, 2 }; room 1 then the same
		-- zero-weight room on the three-room facility), so those stay green;
		-- the four-crossing check predicts { 1, 2, 4, 3 } and this control
		-- darkens { 1, 2, 3, 4 }. One check is enough, and it is AC-5's own.
		expectFires("ignores-blackout-draws", standIn({ ignoresBlackoutDraws = true }), {
			"theSameSeedReplaysTheSameRoomsInTheSameOrder",
		})
	end,

	["I-3 control: the clock out at now > deadline instead of >= fails the two checks that read the exact instant (the finale at the deadline, the tick at the deadline), and nothing else"] = function()
		expectFires("clock-out-strictly-after", standIn({ clockOutStrictlyAfter = true }), {
			"theLastFinaleCommitBeforeTheDeadlineWinsAndAtTheDeadlineItIsRoundOver",
			"theDeadlinePassingByTimeAloneIsLostClockAtExactlyTheDeadline",
		})
	end,
}
