--!strict
--[[
	The negative controls for PROC-005 AC-4 and AC-5, and the proof that each
	check in `tests/helpers/TurnRequestsContract.luau` means what it says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/procedure/TurnRequests.luau` does not exist, every test in
	`tests/server/turn_requests_test.luau` fails before its assertion runs, and
	so not one of that file's checks has been observed to accept or reject
	anything. The stand-ins below need only `Procedure`, `Machines`, `Ring`,
	`MechanicsTuning` and `Deep`, which are merged, so what is asserted here is
	MEASURED in RED rather than claimed for GREEN. The story's handoff carries
	the table.

	THE STAND-INS. `standIn(defects)` is a small implementation of the
	Contract with named defects switched on. With none it is the REFERENCE,
	the positive control: every check must ACCEPT it, or the check (or the
	fixture) is wrong and the fix belongs HERE, in RED. Each control is the
	reference with EXACTLY ONE defect, so the set of checks that fire is
	attributable to that one defect, and each control pins that set EXACTLY.

	THE STORY NAMES ITS AC-5 CONTROL: "a reply that copies the machine record
	must fail, because it would carry requiredSetting" - `copiesTheMachineRecord`
	below, and ALSO run as a hand-written reply straight through the exact
	key-set checker, with a wrong `kind` beside it, because the brief asks for
	the checker itself to be observed rejecting in RED. The deferred
	verifications' shapes are here as defects: D-1 (positions built from
	`args`) is `readsPositionFromArgs` / `readsPositionsFromArgs`; D-2's extra
	field and wrong value are `leaksRequiredSetting` and `hardcodesKind`. D-1
	and D-2 THEMSELVES mutate the real module and stay with GATES.

	WHAT THE REFERENCE IS NOT: `src/server/procedure/TurnRequests.luau`, or a
	sketch of one. GREEN writes the module from the story's Contract against
	`turn_requests_test.luau`; nothing here is to be copied.
]]

local Contract = require("../helpers/TurnRequestsContract")
local Deep = require("../helpers/Deep")
local Procedure = require("../../src/server/procedure/Procedure")
local TurnContract = require("../helpers/TurnContract")

type Defects = {
	readsPositionFromArgs: boolean?, -- D-1's shape: `{ [player] = args.position }`
	readsPositionsFromArgs: boolean?, -- D-1's other shape: `args.positions`
	swapsMachineAndSetting: boolean?,
	hardcodesSettingOne: boolean?,
	hardcodesTheMachine: boolean?,
	readsPlayerFromArgs: boolean?,
	returnsOnlyTheResult: boolean?,
	copiesTheMachineRecord: boolean?, -- AC-5's named control
	leaksRequiredSetting: boolean?, -- D-2's extra field
	hardcodesKind: boolean?, -- D-2's wrong value
	dropsReason: boolean?,
	passesTheResultThrough: boolean?,
	mutatesItsArguments: boolean?,
}

local function standIn(defects: Defects): Contract.TurnRequests
	local T = {}

	function T.handle(
		procedure: any,
		assignment: any,
		playerId: string,
		args: any,
		now: number,
		positions: any
	): (any, any)
		local who = playerId
		if defects.readsPlayerFromArgs and args.player ~= nil then
			who = args.player
		end
		local machine, setting = args.machine, args.setting
		if defects.swapsMachineAndSetting then
			machine, setting = setting, machine
		end
		if defects.hardcodesSettingOne then
			setting = 1
		end
		if defects.hardcodesTheMachine then
			machine = Contract.MACHINE
		end
		local judged = positions
		if defects.readsPositionFromArgs and args.position ~= nil then
			judged = { [who] = args.position }
		end
		if defects.readsPositionsFromArgs and args.positions ~= nil then
			judged = args.positions
		end
		local next_, result =
			Procedure.turn(procedure, assignment, who, machine, setting, now, judged)
		if defects.mutatesItsArguments then
			-- After the judgement, so every other check still sees the right
			-- result; only the purity check can notice.
			args.setting = nil
			positions[who] = nil
		end
		if defects.returnsOnlyTheResult then
			return result, nil
		end
		return next_, result
	end

	function T.reply(result: any): any
		if defects.passesTheResultThrough then
			return result
		end
		local out: { [string]: any }
		if defects.copiesTheMachineRecord then
			-- The story's control: the machine record carries requiredSetting.
			local record = TurnContract.machine(TurnContract.facility(), result.machineId)
			out = if record ~= nil then table.clone(record) else {}
			out.machineId = result.machineId
			out.kind = result.kind
			out.reason = result.reason
		else
			out = { machineId = result.machineId, kind = result.kind, reason = result.reason }
		end
		if defects.dropsReason then
			out.reason = nil
		end
		if defects.leaksRequiredSetting then
			out.requiredSetting = 1
		end
		if defects.hardcodesKind then
			out.kind = "committed"
		end
		return out
	end

	return T
end

local reference = standIn({})

local function failingNames(T: Contract.TurnRequests): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Contract.failures(T) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(who: string, T: Contract.TurnRequests, expected: { string })
	local names, messages = failingNames(T)
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

local RETURNS = "handleReturnsTheStateAndResultProcedureTurnReturns"
local REACH = "handleJudgesReachAgainstTheAcceptedPositionsNotThePayload"
local FORWARDS = "handleForwardsTheRequestedMachineAndSettingUnswapped"
local CALLER = "handleUsesTheCallersIdNotAPlayerKeyInThePayload"
local PURE = "handleDoesNotMutateItsArguments"
local COMMITTED_ARMED = "replyToCommittedAndArmedIsExactlyMachineIdAndKind"
local REJECTED_REFUSED = "replyToRejectedAndRefusedIsExactlyMachineIdKindAndReason"
local REAL_RESULTS = "replyToARealWrongSettingRejectionCarriesNoRequiredSetting"
local FIELD_BY_FIELD = "replyIsBuiltFieldByFieldNotByCopyingTheResult"

return {
	--[[ ================================================================
	     The reference. Everything below is this stand-in with one defect.
	     ================================================================ ]]

	["baseline: the reference stand-in passes every check in TurnRequestsContract - the checks accept a correct implementation of the Contract"] = function()
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
		print(`        [measured] reference fails 0 of {#Contract.CHECKS} checks`)
	end,

	--[[ ================================================================
	     The fixture's assumptions, checked against what they are read from.
	     ================================================================ ]]

	["fixtures: the far position is past turn_range_studs and the at-machine one is in reach through the real Procedure; machine 14 has a different holder and required setting from machine 11; the wrong setting differs from the required one"] = function()
		local w = TurnContract.world()
		local id = Contract.MACHINE
		local holder = Contract.HOLDER
		local required = TurnContract.requiredSetting(w.facility, id)
		local start = Procedure.start(
			w.facility,
			TurnContract.NOW,
			w.tuning,
			TurnContract.ROUND_SEED,
			TurnContract.ROUND_SECONDS
		)
		local problems: { string } = {}
		local _, far = Procedure.turn(
			start,
			w.assignment,
			holder,
			id,
			required,
			TurnContract.NOW,
			{ [holder] = Contract.farFrom(w, id) }
		)
		if not Deep.equal(far, { kind = "refused", machineId = id, reason = "out_of_reach" }) then
			table.insert(problems, `farFrom is not out of reach: {Deep.show(far)}`)
		end
		local _, near = Procedure.turn(
			start,
			w.assignment,
			holder,
			id,
			required,
			TurnContract.NOW,
			TurnContract.standingAt(w, holder, id)
		)
		if not Deep.equal(near, { kind = "committed", machineId = id }) then
			table.insert(problems, `standing at the machine does not commit: {Deep.show(near)}`)
		end
		local other = Contract.OTHER_MACHINE
		if TurnContract.holderOf(w.facility, other) == holder then
			table.insert(problems, `machine {other} has the same holder as {id}`)
		end
		if TurnContract.requiredSetting(w.facility, other) == required then
			table.insert(
				problems,
				`machine {other} has the same required setting as {id}; a hard-coded setting would pass`
			)
		end
		if TurnContract.wrongSetting(w.facility, id, w.tuning) == required then
			table.insert(problems, "wrongSetting equals the required setting")
		end
		if TurnContract.holderOf(w.facility, id) ~= holder then
			table.insert(problems, `machine {id}'s holder is not {holder}`)
		end
		assert(
			#problems == 0,
			`the fixture no longer discriminates:\n{table.concat(problems, "\n")}`
		)
	end,

	--[[ ================================================================
	     The AC-5 checker, observed directly on hand-written replies.
	     ================================================================ ]]

	["control (AC-5, the story's): a hand-written reply that copies the machine record - id, room, slot, keyClass, tag, requiredSetting plus kind and reason - is REJECTED by the exact key-set checker, naming requiredSetting"] = function()
		local record = TurnContract.machine(TurnContract.facility(), Contract.MACHINE)
		assert(
			record ~= nil and record.requiredSetting ~= nil,
			"the fixture's machine record carries requiredSetting"
		)
		local bad = table.clone(record)
		bad.machineId = Contract.MACHINE
		bad.kind = "rejected"
		bad.reason = "wrong_setting"
		local problems = Contract.replyProblems(
			"copied machine record",
			bad,
			{ machineId = Contract.MACHINE, kind = "rejected", reason = "wrong_setting" }
		)
		print(
			`        [measured] copied machine record: {#problems} problem(s): {Deep.show(problems)}`
		)
		assert(#problems > 0, "the checker ACCEPTED a reply carrying the whole machine record")
		assert(
			string.find(problems[1], "requiredSetting", 1, true) ~= nil,
			`the problem does not name requiredSetting:\n{problems[1]}`
		)
		assert(
			string.find(problems[1], "AC-5", 1, true) ~= nil,
			`the problem does not name AC-5:\n{problems[1]}`
		)
	end,

	["control (AC-5): a hand-written reply with the right key set and a wrong kind value is REJECTED, naming kind; one with a wrong machineId is rejected too; the correct reply is ACCEPTED with zero problems"] = function()
		local want = { machineId = 11, kind = "rejected", reason = "wrong_setting" }
		local wrongKind = Contract.replyProblems(
			"wrong kind",
			{ machineId = 11, kind = "committed", reason = "wrong_setting" },
			want
		)
		print(`        [measured] wrong kind: {#wrongKind} problem(s): {Deep.show(wrongKind)}`)
		assert(#wrongKind == 1, `expected exactly one problem for a wrong kind, got {#wrongKind}`)
		assert(
			string.find(wrongKind[1], "reply.kind", 1, true) ~= nil,
			`does not name kind:\n{wrongKind[1]}`
		)

		local wrongId = Contract.replyProblems(
			"wrong machineId",
			{ machineId = 12, kind = "rejected", reason = "wrong_setting" },
			want
		)
		print(`        [measured] wrong machineId: {#wrongId} problem(s)`)
		assert(#wrongId == 1, `expected exactly one problem for a wrong machineId, got {#wrongId}`)

		local missing =
			Contract.replyProblems("missing reason", { machineId = 11, kind = "rejected" }, want)
		print(`        [measured] missing reason: {#missing} problem(s)`)
		assert(
			#missing == 2,
			`expected a key-set problem and a value problem for a missing reason, got {#missing}`
		)

		local notATable = Contract.replyProblems("a string", "rejected", want)
		assert(#notATable == 1, `expected one problem for a non-table reply, got {#notATable}`)

		local good = Contract.replyProblems(
			"correct",
			{ machineId = 11, kind = "rejected", reason = "wrong_setting" },
			want
		)
		print(`        [measured] correct reply: {#good} problem(s)`)
		assert(#good == 0, `the checker rejected the correct reply:\n{table.concat(good, "\n")}`)
	end,

	--[[ ================================================================
	     AC-4's controls: a handle that reads the payload.
	     ================================================================ ]]

	["control (D-1's shape): a handle that judges reach from args.position commits where the accepted positions say out of reach, and is refused where they say in reach - it fails exactly the reach check"] = function()
		expectFires("readsPositionFromArgs", standIn({ readsPositionFromArgs = true }), { REACH })
	end,

	["control (D-1's other shape): a handle that judges reach from args.positions fails exactly the reach check"] = function()
		expectFires("readsPositionsFromArgs", standIn({ readsPositionsFromArgs = true }), { REACH })
	end,

	["control: a handle that swaps machine and setting fails the pass-through, reach, forwarding and caller checks"] = function()
		expectFires("swapsMachineAndSetting", standIn({ swapsMachineAndSetting = true }), {
			RETURNS,
			REACH,
			FORWARDS,
			CALLER,
		})
	end,

	["control: a handle that hard-codes setting = 1 fails the pass-through, reach, forwarding and caller checks - every required-setting turn is rejected"] = function()
		expectFires("hardcodesSettingOne", standIn({ hardcodesSettingOne = true }), {
			RETURNS,
			REACH,
			FORWARDS,
			CALLER,
		})
	end,

	["control: a handle that hard-codes machine 11 fails exactly the forwarding check - bob's turn on 14 lands on 11"] = function()
		expectFires("hardcodesTheMachine", standIn({ hardcodesTheMachine = true }), { FORWARDS })
	end,

	["control: a handle that takes the caller's id from args.player fails exactly the caller check"] = function()
		expectFires("readsPlayerFromArgs", standIn({ readsPlayerFromArgs = true }), { CALLER })
	end,

	["control: a handle that returns only the result fails every handle check that reads the state"] = function()
		expectFires("returnsOnlyTheResult", standIn({ returnsOnlyTheResult = true }), {
			RETURNS,
			REACH,
			FORWARDS,
			CALLER,
		})
	end,

	--[[ ================================================================
	     AC-5's controls: a reply that carries too much, or the wrong thing.
	     ================================================================ ]]

	["control (AC-5, the story's): a reply that copies the machine record fails every reply check - it carries requiredSetting"] = function()
		expectFires("copiesTheMachineRecord", standIn({ copiesTheMachineRecord = true }), {
			COMMITTED_ARMED,
			REJECTED_REFUSED,
			REAL_RESULTS,
			FIELD_BY_FIELD,
		})
	end,

	["control (D-2's extra field): a reply that adds requiredSetting fails every reply check"] = function()
		expectFires("leaksRequiredSetting", standIn({ leaksRequiredSetting = true }), {
			COMMITTED_ARMED,
			REJECTED_REFUSED,
			REAL_RESULTS,
			FIELD_BY_FIELD,
		})
	end,

	["control (D-2's wrong value): a reply whose kind is always committed fails every reply check - the hand-built armed result comes back as committed, so committed/armed fires too (measured in RED; predicted not to)"] = function()
		expectFires("hardcodesKind", standIn({ hardcodesKind = true }), {
			COMMITTED_ARMED,
			REJECTED_REFUSED,
			REAL_RESULTS,
			FIELD_BY_FIELD,
		})
	end,

	["control: a reply that drops reason fails the rejected/refused check, the real-results check and the field-by-field check, and passes committed/armed"] = function()
		expectFires("dropsReason", standIn({ dropsReason = true }), {
			REJECTED_REFUSED,
			REAL_RESULTS,
			FIELD_BY_FIELD,
		})
	end,

	["control: a handle that clears args.setting and the caller's position after judging the turn fails exactly the purity check"] = function()
		expectFires("mutatesItsArguments", standIn({ mutatesItsArguments = true }), { PURE })
	end,

	["control: a reply that returns the result table itself passes every key-set check and fails exactly the field-by-field (D8) check"] = function()
		expectFires("passesTheResultThrough", standIn({ passesTheResultThrough = true }), {
			FIELD_BY_FIELD,
		})
	end,
}
