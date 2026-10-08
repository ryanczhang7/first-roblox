--!strict
--[[
	The negative controls for PROC-002, and the proof that each check in
	`tests/helpers/FinaleContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/procedure/Procedure.luau` LOADS but has no `tick`,
	`partnerLamps` or `isComplete` and no finale behaviour, so every test in
	`tests/server/procedure_finale_test.luau` fails on its first assertion -
	and not one of that file's checks has been observed to ACCEPT anything. The
	stand-ins below need only `Machines`, `MechanicsTuning` and `Deep`, which
	are merged, so what is asserted here is MEASURED in RED rather than
	claimed for GREEN. The story's handoff carries the table.

	THE STAND-INS. `standIn(defects)` is a small implementation of PROC-001's
	Contract plus this story's F-3..F-12 with named defects switched on. With
	none it is the REFERENCE, the positive control: every FinaleContract check
	AND every TurnContract check must ACCEPT it - the second half is the
	mechanical form of the story's "read every TurnContract check against
	F-3..F-9" audit. Each control is the reference with EXACTLY ONE defect, so
	the set of checks that fire is attributable to that one defect, and each
	control pins that set EXACTLY.

	THE CONTROLS THE STORY NAMES:
	  * AC-1: "a rule that lights track 2's finale as soon as its own track is
	    done must fail";
	  * AC-4: "an implementation that charges the wrong turn and the closed
	    window separately must fail, scoring 2" (5 under the overrides);
	  * AC-6: "a lamp that reads the holder's distance to A must fail a
	    fixture where B's holder is standing at A".
	And the two the RED brief adds: an EXCLUSIVE window edge (AC-7, `>=` for
	`>`), and a turn that does not apply an expired window first (F-9: a late
	correct turn on B commits). Five neighbours are cheap once the stand-in
	exists: an armed machine reported not live (F-3), lamps that ignore
	liveness (AC-6's second half), a lamp reading turn_range_studs (F-2),
	expiry dating the rejection from closesAt rather than the tick (F-8), and
	a tick that logs the expiry (F-8). D-1..D-3 THEMSELVES are mutations of
	the real module and stay with GATES; what is measured here is that the
	checks WOULD see them.

	WHAT THE REFERENCE IS NOT: `src/server/procedure/Procedure.luau`, or a
	sketch of one. It is untyped, copies state the slow way, and reads nothing
	the Contract does not name. GREEN writes the module from the story's
	Contract against `procedure_finale_test.luau`; nothing here is to be copied.
]]

local Deep = require("../helpers/Deep")
local Finale = require("../helpers/FinaleContract")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Turn = require("../helpers/TurnContract")

type Defects = {
	perTrackFinale: boolean?, -- AC-1's named control
	doubleCharge: boolean?, -- AC-4's named control
	lampReadsOwnMachine: boolean?, -- AC-6's named control
	exclusiveWindowEdge: boolean?, -- AC-7: expiry at now >= closesAt
	lateTurnIgnoresExpiry: boolean?, -- F-9: a late correct turn on B commits
	armedNotLive: boolean?, -- F-3: isLive false for the armed machine
	lampsIgnoreLiveness: boolean?, -- F-11: lit while the finale is not live
	lampUsesTurnRange: boolean?, -- F-2: reads turn_range_studs for the lamp
	expiryDatedFromClosesAt: boolean?, -- F-8: rejectedUntil = closesAt + reset
	tickLogsExpiry: boolean?, -- F-8: expiry writes a log entry
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

	local function partnerOf(facility: any, id: number): number
		local f = facility.steps.finale
		return if f[1] == id then f[2] else f[1]
	end

	-- Every ordinary step of every track committed.
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

	-- PROC-003 added `roundSeed` and `roundSeconds` to `start`; this stand-in
	-- has no round end or blackout, so it accepts and ignores them.
	function P.start(
		facility: any,
		_now: number,
		tuning: any,
		_roundSeed: number,
		_roundSeconds: number
	): any
		return {
			facility = facility,
			committed = {},
			dials = {},
			instability = 0,
			log = {},
			tuning = tuning,
		}
	end

	function P.isLive(state: any, id: number): boolean
		local facility = state.facility
		if isFinale(facility, id) then
			if state.committed[id] then
				return false
			end
			if defects.armedNotLive and state.armed ~= nil and state.armed.machineId == id then
				return false
			end
			if defects.perTrackFinale then
				for _, track in facility.steps.tracks do
					if track[#track] == id then
						for k = 1, #track - 1 do
							if not state.committed[track[k]] then
								return false
							end
						end
						return true
					end
				end
			end
			return ordinaryDone(state)
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
		return {
			facility = state.facility,
			committed = table.clone(state.committed),
			dials = Deep.copy(state.dials),
			instability = state.instability,
			log = table.clone(state.log),
			tuning = state.tuning,
			armed = if state.armed then table.clone(state.armed) else nil,
		}
	end

	local function expired(state: any, now: number): boolean
		if state.armed == nil then
			return false
		end
		return if defects.exclusiveWindowEdge
			then now >= state.armed.closesAt
			else now > state.armed.closesAt
	end

	-- F-8 applied to a state whose window HAS expired at `now`.
	local function expire(state: any, now: number): any
		local a = state.tuning.actuation
		local next_ = copy(state)
		local A = state.armed.machineId
		local from = if defects.expiryDatedFromClosesAt then state.armed.closesAt else now
		next_.dials[A] =
			{ setting = state.dials[A].setting, rejectedUntil = from + a.actuation_reset_seconds }
		next_.instability += a.instability_per_failed_pair
		next_.armed = nil
		if defects.tickLogsExpiry then
			table.insert(next_.log, {
				playerId = "",
				machineId = A,
				setting = state.dials[A].setting,
				at = now,
				result = "wrong_setting",
			})
		end
		return next_
	end

	function P.tick(state: any, _assignment: any, now: number, _positions: any): (any, any)
		if expired(state, now) then
			return expire(state, now), nil
		end
		return state, nil
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

	local function within(p: any, m: any, range: number): boolean
		local dx, dz = p.x - m.x, p.z - m.z
		return math.sqrt(dx * dx + dz * dz) <= range
	end

	function P.partnerLamps(state: any, assignment: any, positions: any): any
		local facility = state.facility
		local tuning = state.tuning
		local lamps = {}
		local live = P.isLive(state, facility.steps.finale[1])
			and P.isLive(state, facility.steps.finale[2])
		local range = if defects.lampUsesTurnRange
			then tuning.instance.turn_range_studs
			else tuning.instance.partner_lamp_range_studs
		for _, id in facility.steps.finale do
			local partner = partnerOf(facility, id)
			local lit = false
			if live or defects.lampsIgnoreLiveness then
				local target =
					machineOf(facility, if defects.lampReadsOwnMachine then id else partner)
				local mp = Machines.positionOf(facility.layout, target, tuning)
				local class = machineOf(facility, partner).keyClass
				for player, classes in pairs(assignment.keyClasses) do
					local p = positions[player]
					if p ~= nil and table.find(classes, class) ~= nil and within(p, mp, range) then
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
		next_.instability += if reason == "not_live"
			then a.instability_per_out_of_order
			else a.instability_per_wrong_value
		next_.dials[id] = { setting = setting, rejectedUntil = now + a.actuation_reset_seconds }
		table.insert(
			next_.log,
			{ playerId = playerId, machineId = id, setting = setting, at = now, result = reason }
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
		local tuning = state0.tuning
		local facility = state0.facility
		local m = machineOf(facility, id)
		if m == nil then
			return state0, { kind = "refused", machineId = id, reason = "unknown_machine" }
		end
		-- F-9: the expired window is an event that precedes this turn.
		local state = state0
		if not defects.lateTurnIgnoresExpiry and expired(state0, now) then
			state = expire(state0, now)
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
		local a = tuning.actuation
		if setting ~= m.requiredSetting then
			local next_, result = rejected(state, playerId, id, setting, now, "wrong_setting")
			if state.armed ~= nil then
				-- F-7: the window closes, both disarm, no second penalty.
				local A = state.armed.machineId
				next_.dials[A] = {
					setting = state.dials[A].setting,
					rejectedUntil = now + a.actuation_reset_seconds,
				}
				next_.armed = nil
				if defects.doubleCharge then
					next_.instability += a.instability_per_failed_pair
				end
			end
			return next_, result
		end

		local next_ = copy(state)
		if isFinale(facility, id) then
			if state.armed == nil then
				-- F-4.
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
			-- F-5: the other machine, inside the window.
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
		return next_, { kind = "committed", machineId = id }
	end

	return P
end

local reference = standIn({})

local function failingNames(P: Turn.Procedure): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Finale.failures(P) do
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
	local byName: { [string]: Finale.Check } = {}
	for _, check in Finale.CHECKS do
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

-- The instability a control leaves after the AC-4 scenario (A armed, B wrong
-- inside the window) under `w`'s tuning - the NUMBER the handoff table
-- records, measured here rather than described.
local function wrongWithWindowScore(P: Turn.Procedure, w: Finale.World): number
	local A, B = Finale.A, Finale.B
	local armed = Finale.arm(P, w, Finale.liveFinale(P, w, "control"), A, Finale.T_ARM, "control")
	local holder = Turn.holderOf(w.facility, B)
	local state = P.turn(
		armed,
		w.assignment,
		holder,
		B,
		Turn.wrongSetting(w.facility, B, w.tuning),
		Finale.T_ARM + 1,
		Turn.standingAt(w, holder, B)
	)
	return state.instability
end

return {
	--[[ ================================================================
	     The reference. Everything below is this stand-in with one defect.
	     ================================================================ ]]

	["baseline: the reference stand-in passes every check in FinaleContract - the checks accept a correct implementation of F-1..F-12"] = function()
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
		print(`        [measured] reference fails 0 of {#Finale.CHECKS} finale checks`)
	end,

	["audit: the finale reference stand-in also passes every PROC-001 check in TurnContract - F-3..F-9 leave PROC-001's criteria intact once its AC-1 check reads the finale as live together"] = function()
		local shown: { string } = {}
		for _, f in Turn.failures(reference) do
			table.insert(shown, `{f.name}: {f.message}`)
		end
		if #shown > 0 then
			error(
				`the finale reference fails {#shown} TurnContract check(s), so a PROC-001 check still pins PROC-001's interim behaviour:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#Turn.CHECKS} PROC-001 checks`)
	end,

	--[[ ================================================================
	     The fixture's assumptions, checked against what they are read from.
	     ================================================================ ]]

	["fixtures: every finale override differs from its shipped value and from every other constant a check must tell it from (F-2)"] = function()
		local t = Finale.world().tuning
		local s = MechanicsTuning
		local problems: { string } = {}
		local function distinct(label: string, a: number, b: number)
			if a == b then
				table.insert(problems, `{label}: both {a}`)
			end
		end
		distinct(
			"simultaneous_window_seconds vs shipped",
			t.instance.simultaneous_window_seconds,
			s.instance.simultaneous_window_seconds
		)
		distinct(
			"partner_lamp_range_studs vs shipped",
			t.instance.partner_lamp_range_studs,
			s.instance.partner_lamp_range_studs
		)
		distinct(
			"partner_lamp_range_studs vs turn_range_studs",
			t.instance.partner_lamp_range_studs,
			t.instance.turn_range_studs
		)
		distinct(
			"instability_per_failed_pair vs shipped",
			t.actuation.instability_per_failed_pair,
			s.actuation.instability_per_failed_pair
		)
		distinct(
			"instability_per_failed_pair vs wrong_value",
			t.actuation.instability_per_failed_pair,
			t.actuation.instability_per_wrong_value
		)
		distinct(
			"instability_per_failed_pair vs out_of_order",
			t.actuation.instability_per_failed_pair,
			t.actuation.instability_per_out_of_order
		)
		distinct(
			"instability_per_wrong_value vs out_of_order",
			t.actuation.instability_per_wrong_value,
			t.actuation.instability_per_out_of_order
		)
		distinct(
			"actuation_reset_seconds vs shipped",
			t.actuation.actuation_reset_seconds,
			s.actuation.actuation_reset_seconds
		)
		distinct(
			"actuation_reset_seconds vs simultaneous_window_seconds",
			t.actuation.actuation_reset_seconds,
			t.instance.simultaneous_window_seconds
		)
		distinct(
			"turn_range_studs vs shipped",
			t.instance.turn_range_studs,
			s.instance.turn_range_studs
		)
		-- PROC-003: the max must clear the 5-point F-9 scenario (FinaleContract header).
		if t.actuation.instability_max <= 5 then
			table.insert(
				problems,
				`instability_max override {t.actuation.instability_max} does not clear the 5-point F-9 scenario; PROC-003 would end the round inside it`
			)
		end
		-- The shipped values the literal AC-3/AC-4 checks read out.
		if
			s.actuation.instability_per_failed_pair ~= 1
			or s.actuation.instability_per_wrong_value ~= 1
		then
			table.insert(
				problems,
				`the shipped failed-pair / wrong-value charges are {s.actuation.instability_per_failed_pair} / {s.actuation.instability_per_wrong_value}; the literal "+1" and "1, not 2" checks assume both are 1`
			)
		end
		assert(
			#problems == 0,
			`the fixture's tuning no longer discriminates:\n{table.concat(problems, "\n")}`
		)
	end,

	["fixtures: the two finale machines are farther apart than both turn_range_studs and partner_lamp_range_studs, under the overrides and the shipped tuning"] = function()
		for _, w in { Finale.world(), Finale.shippedWorld() } do
			local pa, pb = Turn.at(w, Finale.A), Turn.at(w, Finale.B)
			local d = math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2)
			local far = math.max(
				w.tuning.instance.turn_range_studs,
				w.tuning.instance.partner_lamp_range_studs
			)
			assert(
				d > far,
				`machines {Finale.A} and {Finale.B} are {d} studs apart, within {far}; a holder at one would be in range of the other`
			)
		end
	end,

	--[[ ================================================================
	     The controls. Each fires exactly the checks named.
	     ================================================================ ]]

	["AC-1 control: a finale step that goes live as soon as ITS OWN track's ordinary steps are done fails exactly the AC-1 liveness check here (17 is live with 12 left), and PROC-001's corrected AC-1 check and its finale-while-ordinary-steps-remain check in TurnContract"] = function()
		local P = standIn({ perTrackFinale = true })
		-- Only the liveness check: this stand-in's lamps still need BOTH
		-- machines live, so the lamps-dark check does not see one lit early.
		expectFires("per-track-finale", P, {
			"neitherFinaleMachineIsLiveUntilTheLastOrdinaryStepCommitsThenBothAre",
		})
		-- And TurnContract's corrected AC-1 check sees it too, from the other
		-- side: track 1 done first lights 13 alone.
		local turnNames: { string } = {}
		for _, f in Turn.failures(P) do
			table.insert(turnNames, f.name)
		end
		table.sort(turnNames)
		print(`        [measured] per-track-finale fires in TurnContract: {Deep.show(turnNames)}`)
		assert(
			Deep.equal(turnNames, {
				"tracksAdvanceIndependentlyAndFinaleStepsStayWaiting",
				"waitingStepIsNotLiveWhateverTheSetting",
			}),
			`per-track-finale fires {Deep.show(turnNames)} in TurnContract, expected the corrected AC-1 check and the finale-while-ordinary-steps-remain check`
		)
	end,

	["AC-4 control: charging the wrong turn AND the closed window separately scores 2 under the shipped tuning and 5 under the overrides, and fails the two AC-4 window checks and nothing else"] = function()
		local P = standIn({ doubleCharge = true })
		local shipped = wrongWithWindowScore(P, Finale.shippedWorld())
		local overridden = wrongWithWindowScore(P, Finale.world())
		print(
			`        [measured] double-charge scores {shipped} under the shipped tuning, {overridden} under the overrides (reference: {wrongWithWindowScore(
				reference,
				Finale.shippedWorld()
			)} / {wrongWithWindowScore(reference, Finale.world())})`
		)
		assert(
			shipped == 2,
			`the double-charge control scores {shipped} under the shipped tuning, expected 2`
		)
		assert(
			overridden == 5,
			`the double-charge control scores {overridden} under the overrides, expected 1 + 4 = 5`
		)
		expectFires("double-charge", P, {
			"wrongTurnOnTheOtherMachineInsideTheWindowIsRejectedOnceAndDisarmsBoth",
			"underTheShippedTuningAWrongTurnWithTheWindowOpenCostsOneNotTwo",
		})
	end,

	["AC-6 control: a lamp that measures the partner's holder against ITS OWN machine fails the lamp-geometry check (B's holder standing at A lights A's lamp), the both-classes check and the lamps-dark check's moment-of-going-live case, and nothing else"] = function()
		expectFires("lamp-reads-own-machine", standIn({ lampReadsOwnMachine = true }), {
			"aLampIsLitExactlyWhenThePartnersHolderIsWithinLampRangeOfThePartnerMachine",
			"anyHolderOfThePartnersClassInRangeLightsTheLampAndOnePlayerHoldingBothIsNoSpecialCase",
			"bothLampsAreDarkWhileTheFinaleIsNotLive",
		})
	end,

	["AC-7 control: an EXCLUSIVE window edge (expiry at now >= closesAt) fails the turn-at-exactly-closesAt check, the tick-at-closesAt check and the armed refusal at closesAt, and nothing else"] = function()
		expectFires("exclusive-window-edge", standIn({ exclusiveWindowEdge = true }), {
			"turnOnTheOtherMachineAtExactlyTheWindowsEndCommitsBoth",
			"tickAtOrBeforeTheWindowsEndChangesNothing",
			"turnOnTheArmedMachineIsRefusedArmedAtNoCost",
		})
	end,

	["F-9 control: a turn that does not apply an expired window first (so a late correct turn on B commits both) fails the two F-9 checks and nothing else"] = function()
		expectFires("late-turn-ignores-expiry", standIn({ lateTurnIgnoresExpiry = true }), {
			"aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt",
			"aTurnAfterTheWindowReturnsThePostExpiryState",
		})
	end,

	["F-3 control: an armed machine reported NOT live fails the armed-still-live check, the lamp checks (the lamp goes dark on arming) and the AC-5 armed refusal (not_live wins), and nothing else"] = function()
		expectFires("armed-not-live", standIn({ armedNotLive = true }), {
			"anArmedMachineIsStillLiveAndACommittedFinaleIsNot",
			"aLampIsLitExactlyWhenThePartnersHolderIsWithinLampRangeOfThePartnerMachine",
		})
	end,

	["F-11 control: lamps that ignore liveness fail the F-1 shape check (lit at start) and the lamps-dark check, and nothing else"] = function()
		expectFires("lamps-ignore-liveness", standIn({ lampsIgnoreLiveness = true }), {
			"startHasNoWindowAndTheNewExportsAnswerInShape",
			"bothLampsAreDarkWhileTheFinaleIsNotLive",
		})
	end,

	["F-2 control: a lamp that reads turn_range_studs (7) instead of partner_lamp_range_studs (4) fails exactly the lamp-geometry check"] = function()
		expectFires("lamp-uses-turn-range", standIn({ lampUsesTurnRange = true }), {
			"aLampIsLitExactlyWhenThePartnersHolderIsWithinLampRangeOfThePartnerMachine",
		})
	end,

	["F-8 control: expiry dating the rejection from closesAt rather than the tick's now fails the expiry check, the shipped-tuning expiry check, the reset-then-rearm check and the F-9 arm-after-expiry check, and nothing else"] = function()
		-- Not `aTurnAfterTheWindowReturnsThePostExpiryState`: tick and turn
		-- share the mis-dating, so they still agree and that check cannot see
		-- it. The four that fire pin the date against `now` directly.
		expectFires("expiry-dated-from-closesAt", standIn({ expiryDatedFromClosesAt = true }), {
			"tickPastTheWindowDisarmsBothAndChargesExactlyOneFailedPair",
			"underTheShippedTuningAnExpiredWindowCostsExactlyOne",
			"afterExpiryTheArmedMachineResetsLikeAnyRejectionThenCanArmAgain",
			"aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt",
		})
	end,

	["F-8 control: a tick that writes a log entry for the expiry fails the two expiry checks and the F-9 arm-after-expiry check (its log grows by two), and nothing else"] = function()
		expectFires("tick-logs-expiry", standIn({ tickLogsExpiry = true }), {
			"tickPastTheWindowDisarmsBothAndChargesExactlyOneFailedPair",
			"underTheShippedTuningAnExpiredWindowCostsExactlyOne",
			"aCorrectTurnOnTheOtherMachineAfterTheWindowAppliesExpiryThenArmsIt",
		})
	end,
}
