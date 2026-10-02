--!strict
--[[
	The negative controls for PROC-001, and the proof that each check in
	`tests/helpers/TurnContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/procedure/Procedure.luau` does not exist, every test in
	`tests/server/procedure_test.luau` fails before its assertion runs, and so
	not one of that file's checks has been observed to accept or reject
	anything. The stand-ins below need only `Machines`, `Ring`, `MechanicsTuning`
	and `Deep`, which are merged, so what is asserted here is MEASURED in RED
	rather than claimed for GREEN. The story's handoff carries the table.

	THE STAND-INS. `standIn(defects)` is a small implementation of the Contract
	with named defects switched on. With none it is the REFERENCE, the positive
	control: every check must ACCEPT it, or the check (or the fixture) is wrong
	and the fix belongs HERE, in RED, not in GREEN where it would read as a
	defect in `Procedure`. Each control is the reference with EXACTLY ONE defect,
	so the set of checks that fire is attributable to that one defect, and each
	control pins that set EXACTLY - a check that fires on a control it should
	not is as much a finding as one that stays quiet.

	THE TWO CONTROLS THE STORY NAMES:
	  * AC-1: "a rule that makes every step of track 1 live must fail";
	  * AC-4: "an implementation that evaluates a turn by a non-holder (and so
	    charges instability) must fail".
	Four more are the obvious neighbours: D-1's and D-2's shapes applied to the
	stand-in (a charged refusal; liveness that is global rather than per track),
	one constant for both rejection reasons (P-8), and a closed reset window
	(P-6). D-1 and D-2 THEMSELVES are mutations of the real module and stay
	with GATES; what is measured here is that the checks WOULD see them.

	THE REFERENCE FOLLOWS PROC-002's F-3 FOR LIVENESS (since PROC-002 RED): the
	finale steps are live once every ordinary step of both tracks is
	committed. TurnContract's AC-1 check was corrected to say so at the same
	time, and this reference has to agree with it to stay a positive control.
	It still has no finale TURN behaviour - arming, the window, the lamps live
	in `procedure_finale_controls_test.luau`'s stand-in, which also passes
	every check here.

	WHAT THE REFERENCE IS NOT: `src/server/procedure/Procedure.luau`, or a
	sketch of one. It is untyped, copies state the slow way, and reads nothing
	the Contract does not name. GREEN writes the module from the story's
	Contract against `procedure_test.luau`; nothing here is to be copied.
]]

local Contract = require("../helpers/TurnContract")
local Deep = require("../helpers/Deep")
local Machines = require("../../src/server/facility/Machines")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")

type Defects = {
	everyTrackOneStepLive: boolean?, -- AC-1's named control
	onlyTrackOneHeadLive: boolean?, -- D-2's shape: liveness global, not per track
	evaluatesNonHolders: boolean?, -- AC-4's named control
	chargesOutOfReach: boolean?, -- D-1's shape: a refusal that costs a point
	flatCharge: boolean?, -- P-8: not_live charged as wrong_value
	closedResetWindow: boolean?, -- P-6: t == rejectedUntil still resetting
}

local function standIn(defects: Defects): Contract.Procedure
	local P = {}

	local function machineOf(facility: any, id: number): any
		for _, m in facility.placement.machines do
			if m.id == id then
				return m
			end
		end
		return nil
	end

	function P.start(facility: any, _now: number, tuning: any): any
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
		local tracks = state.facility.steps.tracks
		if defects.everyTrackOneStepLive and table.find(tracks[1], id) ~= nil then
			return true
		end
		-- PROC-002 F-3 (brought up to date in its RED, 2026-10-02): a finale
		-- step is live iff every ordinary step of EVERY track is committed and
		-- it is not itself committed. PROC-001's reference read "never live".
		if table.find(state.facility.steps.finale, id) ~= nil then
			if state.committed[id] then
				return false
			end
			for _, track in tracks do
				for k = 1, #track - 1 do
					if not state.committed[track[k]] then
						return false
					end
				end
			end
			return true
		end
		for t, track in tracks do
			if defects.onlyTrackOneHeadLive and t ~= 1 then
				continue
			end
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
		if d == nil or d.rejectedUntil == nil then
			return false
		end
		return if defects.closedResetWindow then now <= d.rejectedUntil else now < d.rejectedUntil
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
		}
	end

	function P.turn(
		state: any,
		assignment: any,
		playerId: string,
		id: number,
		setting: number,
		now: number,
		positions: any
	): (any, any)
		local tuning = state.tuning
		local facility = state.facility
		local m = machineOf(facility, id)
		if m == nil then
			return state, { kind = "refused", machineId = id, reason = "unknown_machine" }
		end
		if not defects.evaluatesNonHolders then
			local held = assignment.keyClasses[playerId]
			if held == nil or table.find(held, m.keyClass) == nil then
				return state, { kind = "refused", machineId = id, reason = "not_key_holder" }
			end
		end
		local p = positions[playerId]
		local inReach = false
		if p ~= nil then
			local mp = Machines.positionOf(facility.layout, m, tuning)
			local dx, dz = p.x - mp.x, p.z - mp.z
			inReach = math.sqrt(dx * dx + dz * dz) <= tuning.instance.turn_range_studs
		end
		if not inReach then
			if defects.chargesOutOfReach then
				local charged = copy(state)
				charged.instability += 1
				return charged, { kind = "refused", machineId = id, reason = "out_of_reach" }
			end
			return state, { kind = "refused", machineId = id, reason = "out_of_reach" }
		end
		if state.committed[id] then
			return state, { kind = "refused", machineId = id, reason = "committed" }
		end
		if resetting(state, id, now) then
			return state, { kind = "refused", machineId = id, reason = "resetting" }
		end

		local next_ = copy(state)
		local a = tuning.actuation
		if P.isLive(state, id) then
			if setting == m.requiredSetting then
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
			next_.instability += a.instability_per_wrong_value
			next_.dials[id] = { setting = setting, rejectedUntil = now + a.actuation_reset_seconds }
			table.insert(next_.log, {
				playerId = playerId,
				machineId = id,
				setting = setting,
				at = now,
				result = "wrong_setting",
			})
			return next_, { kind = "rejected", machineId = id, reason = "wrong_setting" }
		end
		next_.instability += if defects.flatCharge
			then a.instability_per_wrong_value
			else a.instability_per_out_of_order
		next_.dials[id] = { setting = setting, rejectedUntil = now + a.actuation_reset_seconds }
		table.insert(next_.log, {
			playerId = playerId,
			machineId = id,
			setting = setting,
			at = now,
			result = "not_live",
		})
		return next_, { kind = "rejected", machineId = id, reason = "not_live" }
	end

	return P
end

local reference = standIn({})

local function failingNames(P: Contract.Procedure): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Contract.failures(P) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(who: string, P: Contract.Procedure, expected: { string })
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
	local byName: { [string]: Contract.Check } = {}
	for _, check in Contract.CHECKS do
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

return {
	--[[ ================================================================
	     The reference. Everything below is this stand-in with one defect.
	     ================================================================ ]]

	["baseline: the reference stand-in passes every check in TurnContract - the checks accept a correct implementation of the Contract"] = function()
		local names, messages = failingNames(reference)
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		if #names > 0 then
			-- error at level 0, not assert: assert keeps 511 characters (Contract.luau).
			error(
				`the reference fails {#names} check(s), so the check or the fixture is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#Contract.CHECKS} checks`)
	end,

	--[[ ================================================================
	     The fixture's assumptions, checked against what they are read from.
	     ================================================================ ]]

	["fixtures: every override differs from the shipped constant it must be told apart from - range, reset, and the two rejection charges from each other"] = function()
		local t = Contract.tuning()
		local shipped = MechanicsTuning
		local problems: { string } = {}
		if t.instance.turn_range_studs == shipped.instance.turn_range_studs then
			table.insert(
				problems,
				`turn_range_studs override {t.instance.turn_range_studs} equals the shipped value; a module reading MechanicsTuning instead of state.tuning would pass P-4`
			)
		end
		if t.actuation.actuation_reset_seconds == shipped.actuation.actuation_reset_seconds then
			table.insert(
				problems,
				`actuation_reset_seconds override {t.actuation.actuation_reset_seconds} equals the shipped value; P-6 would not detect a module reading the shipped constant`
			)
		end
		if t.actuation.instability_per_wrong_value == t.actuation.instability_per_out_of_order then
			table.insert(
				problems,
				`instability_per_wrong_value and instability_per_out_of_order are both {t.actuation.instability_per_wrong_value}; P-8 cannot tell which was charged`
			)
		end
		if
			shipped.actuation.instability_per_wrong_value
			~= shipped.actuation.instability_per_out_of_order
		then
			table.insert(
				problems,
				"the shipped charges now differ; P-1's comment that the shipped values are both 1 is stale and the override may no longer be needed"
			)
		end
		assert(
			#problems == 0,
			`the fixture's tuning no longer discriminates:\n{table.concat(problems, "\n")}`
		)
	end,

	["fixtures: no machine sits at the list index equal to its id, every id is unique, every machine is in exactly one track or is a decoy, and the tracks are of unequal length"] = function()
		local f = Contract.facility()
		local problems: { string } = {}
		local seen: { [number]: boolean } = {}
		for i, m in f.placement.machines do
			if m.id == i then
				table.insert(
					problems,
					`machines[{i}].id == {i}: an implementation indexing by position would find it`
				)
			end
			if seen[m.id] then
				table.insert(problems, `id {m.id} appears twice`)
			end
			seen[m.id] = true
		end
		local inTrack: { [number]: number } = {}
		for t, track in f.steps.tracks do
			for _, id in track do
				if inTrack[id] then
					table.insert(problems, `machine {id} is in tracks {inTrack[id]} and {t}`)
				end
				inTrack[id] = t
				if not seen[id] then
					table.insert(
						problems,
						`track {t} names machine {id}, which the placement lacks`
					)
				end
			end
		end
		for _, id in Contract.DECOYS do
			if inTrack[id] then
				table.insert(problems, `decoy {id} is in track {inTrack[id]}`)
			end
		end
		for _, id in Contract.ALL_IDS do
			if not seen[id] then
				table.insert(problems, `ALL_IDS names {id}, which the placement lacks`)
			end
		end
		if seen[Contract.UNKNOWN_ID] then
			table.insert(problems, `UNKNOWN_ID {Contract.UNKNOWN_ID} exists in the placement`)
		end
		if #f.steps.tracks[1] == #f.steps.tracks[2] then
			table.insert(
				problems,
				"the tracks are the same length; P-2's `i < #tracks[t]` would not be exercised per track"
			)
		end
		if
			not Deep.equal(
				f.steps.finale,
				{ f.steps.tracks[1][#f.steps.tracks[1]], f.steps.tracks[2][#f.steps.tracks[2]] }
			)
		then
			table.insert(problems, "finale is not the tracks' last steps")
		end
		assert(
			#problems == 0,
			`the hand-built facility is not what the checks assume:\n{table.concat(problems, "\n")}`
		)
	end,

	["fixtures: every machine's position through the real Machines.positionOf is distinct, and every other machine is farther than turn_range_studs from machine 11"] = function()
		local w = Contract.world()
		local range = w.tuning.instance.turn_range_studs
		local p11 = Contract.at(w, 11)
		local problems: { string } = {}
		local positions: { [string]: number } = {}
		for _, id in Contract.ALL_IDS do
			local p = Contract.at(w, id)
			local key = `{p.x},{p.z}`
			if positions[key] then
				table.insert(problems, `machines {positions[key]} and {id} share position ({key})`)
			end
			positions[key] = id
			if id ~= 11 then
				local d = math.sqrt((p.x - p11.x) ^ 2 + (p.z - p11.z) ^ 2)
				if d <= range then
					table.insert(
						problems,
						`machine {id} is {d} studs from machine 11, inside turn_range_studs {range}`
					)
				end
			end
		end
		assert(
			#problems == 0,
			`the fixture's geometry is not what the reach checks assume:\n{table.concat(
				problems,
				"\n"
			)}`
		)
	end,

	["fixtures: the hand-built ring is one 4-cycle with class i at seat i, and Ring.withdraw(kim) hands class 1 to bob"] = function()
		local a = Contract.assignment()
		local seen: { [string]: boolean } = {}
		local p = a.players[1]
		for _ = 1, #a.players do
			assert(not seen[p], `σ revisits {p} before covering every player`)
			seen[p] = true
			p = a.sigma[p]
		end
		assert(p == a.players[1], `σ is not one cycle: after {#a.players} steps it is at {p}`)
		for i, player in a.players do
			assert(
				Deep.equal(a.keyClasses[player], { i }),
				`{player} holds {Deep.show(a.keyClasses[player])}, expected \{ {i} }`
			)
			assert(
				a.lens[player] == a.keyClasses[a.sigma[player]][1],
				`{player}'s lens is not k(σ(p))`
			)
		end
		assert(
			a.sigma[Contract.SUPPLIER_OF_KIM] == "kim",
			`{Contract.SUPPLIER_OF_KIM} is not kim's supplier`
		)
	end,

	--[[ ================================================================
	     The controls. Each fires exactly the checks named.
	     ================================================================ ]]

	["AC-1 control: a liveness rule that makes every step of track 1 live fails the three AC-1 checks, the AC-2 commit check (11 stays live after its commit) and the waiting-step check, and nothing else (measured: see the run log)"] = function()
		expectFires("every-track-1-step-live", standIn({ everyTrackOneStepLive = true }), {
			"liveSetAtStartIsExactlyTheTrackHeads",
			"committingTheHeadOfTrackOneMakesItsSecondStepLive",
			"tracksAdvanceIndependentlyAndFinaleStepsStayWaiting",
			"holderInReachOnTheRequiredSettingCommits",
			"waitingStepIsNotLiveWhateverTheSetting",
		})
	end,

	["D-2's shape as a control: liveness that is global - only track 1's head, never track 2's - fails the three AC-1 checks and AC-5 (bob's own machine 14 heads track 2), and nothing else"] = function()
		expectFires("only-track-1-head-live", standIn({ onlyTrackOneHeadLive = true }), {
			"liveSetAtStartIsExactlyTheTrackHeads",
			"committingTheHeadOfTrackOneMakesItsSecondStepLive",
			"tracksAdvanceIndependentlyAndFinaleStepsStayWaiting",
			"supplierIsJudgedKeyHolderAfterWithdraw",
		})
	end,

	["AC-4 control: an implementation that evaluates a turn by a non-holder (and so commits or charges) fails the not_key_holder check, the ordering check, AC-5 and AC-6, and nothing else (measured: see the run log)"] = function()
		expectFires("evaluates-non-holders", standIn({ evaluatesNonHolders = true }), {
			"nonHolderIsRefusedAndNotCharged",
			"refusalChecksRunInOrderAndTheFirstFailureWins",
			"supplierIsJudgedKeyHolderAfterWithdraw",
			"logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals",
		})
	end,

	["D-1's shape as a control: an out_of_reach refusal that charges a point fails the out_of_reach check, the ordering check and AC-6, and leaves AC-3 green"] = function()
		expectFires("charges-out-of-reach", standIn({ chargesOutOfReach = true }), {
			"holderOutOfHorizontalReachOrWithoutAPositionIsRefused",
			"refusalChecksRunInOrderAndTheFirstFailureWins",
			"logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals",
		})
	end,

	["P-8 control: charging instability_per_wrong_value for not_live fails the waiting-step, decoy, accumulation and log checks, and nothing else"] = function()
		expectFires("flat-charge", standIn({ flatCharge = true }), {
			"waitingStepIsNotLiveWhateverTheSetting",
			"decoyIsNotLiveWhateverTheSetting",
			"chargesAccumulateByReason",
			"logHoldsOneEntryPerEvaluatedTurnInCallOrderAndNoneForRefusals",
		})
	end,

	["P-6 control: a closed reset window (t <= rejectedUntil still resetting) fails exactly the boundary check"] = function()
		expectFires("closed-reset-window", standIn({ closedResetWindow = true }), {
			"rejectedDialShowsTheSettingUntilTheResetBoundaryThenUnset",
		})
	end,
}
