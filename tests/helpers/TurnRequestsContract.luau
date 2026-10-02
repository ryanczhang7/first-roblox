--!strict
--[[
	PROC-005 AC-4 and AC-5, written once as checks over a TURN-REQUESTS MODULE
	handed in as a parameter rather than over
	`src/server/procedure/TurnRequests.luau` by name - the `TurnContract.luau`
	arrangement, for the same reason. `tests/server/turn_requests_test.luau`
	applies these to the real module; `tests/server/turn_requests_controls_test.luau`
	applies them to a reference stand-in and to stand-ins with exactly one
	defect each, so that in RED - where the module does not exist, the real
	file fails at `require`, and not one assertion in it has executed - every
	check here has still been EXECUTED and observed to reject the
	implementation it exists to catch.

	A `TurnRequests` here is anything with two plain field functions, called
	with a dot exactly as the story's Contract writes them:

	    T.handle(procedure, assignment, playerId, args, now, positions)
	        -> (ProcedureState, TurnResult)
	    T.reply(result) -> TurnReply

	THE ORACLE FOR AC-4 IS BEHAVIOURAL, as the Contract prefers. The REAL
	`Procedure` judges reach against the positions table it is handed, so a
	`handle` that read a position out of `args` would be visible as a commit
	where the accepted positions say out of reach, and the mirror. Nothing
	here spies on `Procedure.turn` or replaces a module field, so `handle` may
	call it however it likes.

	THE FIXTURE IS `TurnContract`'s: the hand-built four-player facility, the
	shipped tuning with its overrides, machine 11 as the live class-1 step
	whose holder is kim, and positions through the real `Machines.positionOf`.
	`turn_range_studs` is read from the fixture tuning (7, not the shipped 10).

	THE AC-5 CHECKER IS EXACT. `replyProblems` enumerates the reply's keys
	with `pairs` and compares the sorted list to the sorted expected list -
	never "has field X" - and then compares each value. The controls file runs
	it directly on hand-written bad replies (a copied machine record, a wrong
	kind) so the instrument itself is observed to reject in RED, where nothing
	else in this file can run against the shipped module.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Procedure = require("../../src/server/procedure/Procedure")
local TurnContract = require("./TurnContract")

local TurnRequestsContract = {}

export type TurnRequests = any
export type Vec = TurnContract.Vec
export type World = TurnContract.World

-- The machine every reach scenario turns: track 1's head, live at start,
-- class 1, kim's.
TurnRequestsContract.MACHINE = TurnContract.TRACK_1[1]
TurnRequestsContract.HOLDER = "kim"

-- A second live machine with a different holder and a different required
-- setting, so "forwards the machine" is distinguishable from "always 11".
TurnRequestsContract.OTHER_MACHINE = TurnContract.TRACK_2[1]

-- The key-set the Contract pins per kind.
TurnRequestsContract.KEYS_WITHOUT_REASON = { "kind", "machineId" }
TurnRequestsContract.KEYS_WITH_REASON = { "kind", "machineId", "reason" }

-- Every refused reason `Procedure.TurnResult` can carry today.
TurnRequestsContract.REFUSED_REASONS = {
	"unknown_machine",
	"not_key_holder",
	"out_of_reach",
	"committed",
	"resetting",
	"armed",
	"round_over",
}
TurnRequestsContract.REJECTED_REASONS = { "wrong_setting", "not_live" }

local function started(w: World): any
	return Procedure.start(
		w.facility,
		TurnContract.NOW,
		w.tuning,
		TurnContract.ROUND_SEED,
		TurnContract.ROUND_SECONDS
	)
end

-- A position just past turn_range_studs along x: out of reach.
function TurnRequestsContract.farFrom(w: World, id: number): Vec
	return TurnContract.at(w, id, w.tuning.instance.turn_range_studs + 1, 0, 0)
end

local function requireModule(criterion: string, T: any)
	if typeof(T) ~= "table" then
		Contract.fail(`{criterion}: TurnRequests is {Deep.show(T)}, not a module table`)
	end
	for _, name in { "handle", "reply" } do
		if typeof(T[name]) ~= "function" then
			Contract.fail(
				`{criterion}: TurnRequests.{name} is {typeof(T[name])}, expected a function`
			)
		end
	end
end

-- `handle` and `Procedure.turn` on identical inputs: the two results and the
-- two states, compared deeply. Returns the problems and the handle result.
local function compareWithDirectTurn(
	T: TurnRequests,
	label: string,
	state: any,
	assignment: any,
	playerId: string,
	args: any,
	now: number,
	positions: { [string]: Vec }
): ({ string }, any, any)
	local problems: { string } = {}
	local wantState, wantResult =
		Procedure.turn(state, assignment, playerId, args.machine, args.setting, now, positions)
	local gotState, gotResult = T.handle(state, assignment, playerId, args, now, positions)
	if not Deep.equal(gotResult, wantResult) then
		table.insert(
			problems,
			`{label}: handle returned result {Deep.show(gotResult)}; Procedure.turn on the same inputs returns {Deep.show(
				wantResult
			)}`
		)
	end
	if not Deep.equal(gotState, wantState) then
		table.insert(
			problems,
			`{label}: handle's returned state differs from Procedure.turn's on the same inputs:\n{Deep.diff(
				wantState,
				gotState
			)}`
		)
	end
	return problems, gotState, gotResult
end

--[[ ------------------------------------------------------------------------
     The Contract's shape: two values, the ones Procedure.turn returns.
     --------------------------------------------------------------------- ]]

function TurnRequestsContract.handleReturnsTheStateAndResultProcedureTurnReturns(T: TurnRequests)
	requireModule("Contract", T)
	local w = TurnContract.world()
	local id = TurnRequestsContract.MACHINE
	local holder = TurnRequestsContract.HOLDER
	local args = { machine = id, setting = TurnContract.requiredSetting(w.facility, id) }
	local positions = TurnContract.standingAt(w, holder, id)
	local state = started(w)
	local gotState, gotResult =
		T.handle(state, w.assignment, holder, args, TurnContract.NOW, positions)
	if typeof(gotState) ~= "table" then
		Contract.fail(
			`Contract: handle's first return is {Deep.show(gotState)}, expected a ProcedureState`
		)
	end
	if typeof(gotResult) ~= "table" or typeof(gotResult.kind) ~= "string" then
		Contract.fail(
			`Contract: handle's second return is {Deep.show(gotResult)}, expected a TurnResult with a string kind`
		)
	end
	local problems = compareWithDirectTurn(
		T,
		"the holder in reach on the required setting",
		state,
		w.assignment,
		holder,
		args,
		TurnContract.NOW,
		positions
	)
	if #problems > 0 then
		Contract.fail(
			`Contract: handle is not a pass-through to Procedure.turn:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-4: reach is judged against the ACCEPTED positions, never the payload.
     --------------------------------------------------------------------- ]]

--[[
	Case A: the accepted positions put kim out of reach; `args` smuggles an
	in-reach `position`, a `positions` table and bare `x`/`y`/`z`. The result
	must be refused / out_of_reach with the state returned unchanged. Case B,
	the mirror: accepted positions in reach, a far position smuggled; the
	result must be committed. Both are compared to a direct `Procedure.turn`.
]]
function TurnRequestsContract.handleJudgesReachAgainstTheAcceptedPositionsNotThePayload(
	T: TurnRequests
)
	requireModule("AC-4", T)
	local w = TurnContract.world()
	local id = TurnRequestsContract.MACHINE
	local holder = TurnRequestsContract.HOLDER
	local required = TurnContract.requiredSetting(w.facility, id)
	local atMachine = TurnContract.at(w, id)
	local far = TurnRequestsContract.farFrom(w, id)
	local problems: { string } = {}

	-- Case A.
	local state = started(w)
	local smuggledIn = {
		machine = id,
		setting = required,
		position = atMachine,
		positions = { [holder] = atMachine },
		x = atMachine.x,
		y = atMachine.y,
		z = atMachine.z,
	}
	local accepted: { [string]: Vec } = { [holder] = far }
	local aProblems, aState, aResult = compareWithDirectTurn(
		T,
		"case A",
		state,
		w.assignment,
		holder,
		smuggledIn,
		TurnContract.NOW,
		accepted
	)
	for _, p in aProblems do
		table.insert(problems, p)
	end
	if not Deep.equal(aResult, { kind = "refused", machineId = id, reason = "out_of_reach" }) then
		table.insert(
			problems,
			`case A: accepted positions put {holder} {w.tuning.instance.turn_range_studs + 1} studs from machine {id} while args smuggled an in-reach position; handle returned {Deep.show(
				aResult
			)}, expected refused / out_of_reach - the payload's position was read`
		)
	end
	if typeof(aState) == "table" and not Deep.equal(aState, state) then
		table.insert(
			problems,
			`case A: a refused turn must return the state unchanged, but:\n{Deep.diff(state, aState)}`
		)
	end

	-- Case B.
	local state2 = started(w)
	local smuggledOut = {
		machine = id,
		setting = required,
		position = far,
		positions = { [holder] = far },
		x = far.x,
		y = far.y,
		z = far.z,
	}
	local bProblems, bState, bResult = compareWithDirectTurn(
		T,
		"case B",
		state2,
		w.assignment,
		holder,
		smuggledOut,
		TurnContract.NOW,
		{ [holder] = atMachine }
	)
	for _, p in bProblems do
		table.insert(problems, p)
	end
	if not Deep.equal(bResult, { kind = "committed", machineId = id }) then
		table.insert(
			problems,
			`case B: accepted positions put {holder} at machine {id} while args smuggled a far position; handle returned {Deep.show(
				bResult
			)}, expected committed`
		)
	elseif typeof(bState) ~= "table" or bState.committed[id] ~= true then
		table.insert(
			problems,
			`case B: committed, but the returned state's committed[{id}] is {Deep.show(
				if typeof(bState) == "table" then bState.committed[id] else bState
			)}`
		)
	end

	if #problems > 0 then
		Contract.fail(
			`AC-4: handle must judge reach against the session's ACCEPTED positions and ignore any position in the payload:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[
	`args.machine` and `args.setting` are forwarded as themselves: a wrong
	setting on machine 11 is rejected / wrong_setting with that setting on the
	dial, and bob turning machine 14 commits 14 - so neither is hard-coded and
	the two are not swapped.
]]
function TurnRequestsContract.handleForwardsTheRequestedMachineAndSettingUnswapped(T: TurnRequests)
	requireModule("AC-4", T)
	local w = TurnContract.world()
	local id = TurnRequestsContract.MACHINE
	local holder = TurnRequestsContract.HOLDER
	local wrong = TurnContract.wrongSetting(w.facility, id, w.tuning)
	local problems: { string } = {}

	local state = started(w)
	local p1, s1, r1 = compareWithDirectTurn(
		T,
		`a wrong setting ({wrong}) on machine {id}`,
		state,
		w.assignment,
		holder,
		{ machine = id, setting = wrong },
		TurnContract.NOW,
		TurnContract.standingAt(w, holder, id)
	)
	for _, p in p1 do
		table.insert(problems, p)
	end
	if not Deep.equal(r1, { kind = "rejected", machineId = id, reason = "wrong_setting" }) then
		table.insert(
			problems,
			`{holder} turning machine {id} to wrong setting {wrong}: handle returned {Deep.show(r1)}, expected rejected / wrong_setting`
		)
	elseif typeof(s1) ~= "table" or s1.dials[id] == nil or s1.dials[id].setting ~= wrong then
		table.insert(
			problems,
			`the rejected dial shows setting {Deep.show(
				if typeof(s1) == "table" and s1.dials[id] then s1.dials[id].setting else s1
			)}, expected the forwarded {wrong}`
		)
	end

	local other = TurnRequestsContract.OTHER_MACHINE
	local otherHolder = TurnContract.holderOf(w.facility, other)
	local otherRequired = TurnContract.requiredSetting(w.facility, other)
	local state2 = started(w)
	local p2, s2, r2 = compareWithDirectTurn(
		T,
		`{otherHolder} turning machine {other}`,
		state2,
		w.assignment,
		otherHolder,
		{ machine = other, setting = otherRequired },
		TurnContract.NOW,
		TurnContract.standingAt(w, otherHolder, other)
	)
	for _, p in p2 do
		table.insert(problems, p)
	end
	if not Deep.equal(r2, { kind = "committed", machineId = other }) then
		table.insert(
			problems,
			`{otherHolder} turning machine {other} to {otherRequired} in reach: handle returned {Deep.show(
				r2
			)}, expected committed`
		)
	elseif typeof(s2) ~= "table" or s2.committed[other] ~= true then
		table.insert(problems, `machine {other} was not the one committed`)
	end

	if #problems > 0 then
		Contract.fail(
			`AC-4: handle must forward args.machine and args.setting as given:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[
	The caller's id is the `playerId` argument, never a `player` key in the
	payload: kim with `player = "zed"` commits; zed with `player = "kim"` is
	refused / not_key_holder.
]]
function TurnRequestsContract.handleUsesTheCallersIdNotAPlayerKeyInThePayload(T: TurnRequests)
	requireModule("AC-4", T)
	local w = TurnContract.world()
	local id = TurnRequestsContract.MACHINE
	local required = TurnContract.requiredSetting(w.facility, id)
	local problems: { string } = {}

	local p1, _, r1 = compareWithDirectTurn(
		T,
		'kim with player = "zed"',
		started(w),
		w.assignment,
		"kim",
		{ machine = id, setting = required, player = "zed" },
		TurnContract.NOW,
		TurnContract.standingAt(w, "kim", id)
	)
	for _, p in p1 do
		table.insert(problems, p)
	end
	if not Deep.equal(r1, { kind = "committed", machineId = id }) then
		table.insert(
			problems,
			`kim (the holder) with args.player = "zed": handle returned {Deep.show(r1)}, expected committed - the payload's player key was read`
		)
	end

	local p2, _, r2 = compareWithDirectTurn(
		T,
		'zed with player = "kim"',
		started(w),
		w.assignment,
		"zed",
		{ machine = id, setting = required, player = "kim" },
		TurnContract.NOW,
		TurnContract.standingAt(w, "zed", id)
	)
	for _, p in p2 do
		table.insert(problems, p)
	end
	if not Deep.equal(r2, { kind = "refused", machineId = id, reason = "not_key_holder" }) then
		table.insert(
			problems,
			`zed (not the holder) with args.player = "kim": handle returned {Deep.show(r2)}, expected refused / not_key_holder`
		)
	end

	if #problems > 0 then
		Contract.fail(
			`AC-4: handle must call Procedure.turn with the CALLER's id:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- `handle` mutates none of its arguments (the Procedure's P-11, kept through
-- the pass-through): state, assignment, args and positions deep-equal their
-- snapshots afterwards.
function TurnRequestsContract.handleDoesNotMutateItsArguments(T: TurnRequests)
	requireModule("AC-4", T)
	local w = TurnContract.world()
	local id = TurnRequestsContract.MACHINE
	local holder = TurnRequestsContract.HOLDER
	local state = started(w)
	local args = {
		machine = id,
		setting = TurnContract.requiredSetting(w.facility, id),
		position = TurnContract.at(w, id),
	}
	local positions = TurnContract.standingAt(w, holder, id)
	local before = {
		state = Deep.copy(state),
		assignment = Deep.copy(w.assignment),
		args = Deep.copy(args),
		positions = Deep.copy(positions),
	}
	T.handle(state, w.assignment, holder, args, TurnContract.NOW, positions)
	local after: { [string]: any } =
		{ state = state, assignment = w.assignment, args = args, positions = positions }
	local problems: { string } = {}
	for name, snapshot in pairs(before) do
		if not Deep.equal(snapshot, after[name]) then
			table.insert(problems, `handle mutated its {name}:\n{Deep.diff(snapshot, after[name])}`)
		end
	end
	if #problems > 0 then
		Contract.fail(`AC-4: an argument was mutated:\n{Contract.firstFew(problems, 8)}`)
	end
end

--[[ ------------------------------------------------------------------------
     AC-5: the reply is exactly { machineId, kind, reason? }.
     --------------------------------------------------------------------- ]]

-- The reply's keys, as strings, sorted. `pairs`, so a key of any type counts.
function TurnRequestsContract.keysOf(value: any): { string }
	local keys: { string } = {}
	for key in pairs(value :: { [any]: any }) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end

-- The reply the Contract says `result` maps to.
function TurnRequestsContract.expectedReply(result: any): any
	local want: { [string]: any } = { machineId = result.machineId, kind = result.kind }
	if result.kind == "rejected" or result.kind == "refused" then
		want.reason = result.reason
	end
	return want
end

--[[
	THE EXACT KEY-SET CHECKER. `reply` must be a table whose key set is
	exactly `want`'s and whose every value equals `want`'s. One line per
	problem, each naming AC-5.
]]
function TurnRequestsContract.replyProblems(label: string, reply: any, want: any): { string }
	local problems: { string } = {}
	if typeof(reply) ~= "table" then
		table.insert(problems, `AC-5: {label}: reply is {Deep.show(reply)}, not a table`)
		return problems
	end
	local got = TurnRequestsContract.keysOf(reply)
	local wantKeys = TurnRequestsContract.keysOf(want)
	if not Deep.equal(got, wantKeys) then
		table.insert(
			problems,
			`AC-5: {label}: the reply's key set is {Deep.show(got)}, expected exactly {Deep.show(
				wantKeys
			)} - reply {Deep.show(reply)}`
		)
	end
	for key, value in pairs(want :: { [string]: any }) do
		if reply[key] ~= value then
			table.insert(
				problems,
				`AC-5: {label}: reply.{key} is {Deep.show(reply[key])}, expected {Deep.show(value)}`
			)
		end
	end
	return problems
end

local function replyMatches(T: TurnRequests, label: string, result: any, problems: { string })
	local ok, reply = pcall(T.reply, result)
	if not ok then
		table.insert(problems, `AC-5: {label}: reply RAISED: {tostring(reply)}`)
		return
	end
	for _, p in
		TurnRequestsContract.replyProblems(label, reply, TurnRequestsContract.expectedReply(result))
	do
		table.insert(problems, p)
	end
end

-- Hand-built committed and armed results: exactly { machineId, kind }.
function TurnRequestsContract.replyToCommittedAndArmedIsExactlyMachineIdAndKind(T: TurnRequests)
	requireModule("AC-5", T)
	local problems: { string } = {}
	replyMatches(T, "committed", { kind = "committed", machineId = 11 }, problems)
	replyMatches(T, "armed", { kind = "armed", machineId = 13 }, problems)
	if #problems > 0 then
		Contract.fail(
			`AC-5: the reply to committed / armed must be exactly \{ machineId, kind }:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

-- Hand-built rejected and refused results, every reason: exactly
-- { machineId, kind, reason } with the reason string unchanged.
function TurnRequestsContract.replyToRejectedAndRefusedIsExactlyMachineIdKindAndReason(
	T: TurnRequests
)
	requireModule("AC-5", T)
	local problems: { string } = {}
	for _, reason in TurnRequestsContract.REJECTED_REASONS do
		replyMatches(
			T,
			`rejected / {reason}`,
			{ kind = "rejected", machineId = 12, reason = reason },
			problems
		)
	end
	for i, reason in TurnRequestsContract.REFUSED_REASONS do
		replyMatches(
			T,
			`refused / {reason}`,
			{ kind = "refused", machineId = 10 + i, reason = reason },
			problems
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-5: the reply to rejected / refused must be exactly \{ machineId, kind, reason }:\n{Contract.firstFew(
				problems,
				12
			)}`
		)
	end
end

--[[
	Results produced by the REAL `Procedure.turn`: a wrong_setting rejection
	(whose reply must not carry the required setting), a commit, and an
	out_of_reach refusal. The exact key set is what excludes `requiredSetting`
	and `setting`; the two are named again so the message says what leaked.
]]
function TurnRequestsContract.replyToARealWrongSettingRejectionCarriesNoRequiredSetting(
	T: TurnRequests
)
	requireModule("AC-5", T)
	local w = TurnContract.world()
	local id = TurnRequestsContract.MACHINE
	local holder = TurnRequestsContract.HOLDER
	local required = TurnContract.requiredSetting(w.facility, id)
	local wrong = TurnContract.wrongSetting(w.facility, id, w.tuning)
	local at = TurnContract.standingAt(w, holder, id)
	local problems: { string } = {}

	local _, rejected =
		Procedure.turn(started(w), w.assignment, holder, id, wrong, TurnContract.NOW, at)
	if
		not Deep.equal(rejected, { kind = "rejected", machineId = id, reason = "wrong_setting" })
	then
		Contract.fail(
			`AC-5 precondition: Procedure.turn on wrong setting {wrong} returned {Deep.show(
				rejected
			)}, expected rejected / wrong_setting`
		)
	end
	replyMatches(T, "a real wrong_setting rejection", rejected, problems)
	local ok, reply = pcall(T.reply, rejected)
	if ok and typeof(reply) == "table" then
		for _, leak in { "requiredSetting", "setting" } do
			if reply[leak] ~= nil then
				table.insert(
					problems,
					`AC-5: the reply to a wrong_setting rejection carries {leak} = {Deep.show(
						reply[leak]
					)}; the correct setting ({required}) must not be told to the turner`
				)
			end
		end
	end

	local _, committed =
		Procedure.turn(started(w), w.assignment, holder, id, required, TurnContract.NOW, at)
	replyMatches(T, "a real commit", committed, problems)

	local _, refused = Procedure.turn(
		started(w),
		w.assignment,
		holder,
		id,
		required,
		TurnContract.NOW,
		{ [holder] = TurnRequestsContract.farFrom(w, id) }
	)
	replyMatches(T, "a real out_of_reach refusal", refused, problems)

	if #problems > 0 then
		Contract.fail(
			`AC-5: replies to real Procedure.turn results:\n{Contract.firstFew(problems, 8)}`
		)
	end
end

--[[
	Contract: "reply builds the reply field by field (D8), never by copying a
	record." A result carrying a smuggled extra field is mapped to a reply
	WITHOUT it, and the reply is a fresh table: not the result itself, and
	writing to it leaves the result untouched.
]]
function TurnRequestsContract.replyIsBuiltFieldByFieldNotByCopyingTheResult(T: TurnRequests)
	requireModule("Contract (D8)", T)
	local problems: { string } = {}
	local tainted: any =
		{ kind = "rejected", machineId = 11, reason = "wrong_setting", requiredSetting = 2 }
	local ok, reply = pcall(T.reply, tainted)
	if not ok then
		Contract.fail(
			`Contract (D8): reply RAISED on a result with an extra field: {tostring(reply)}`
		)
	end
	for _, p in
		TurnRequestsContract.replyProblems(
			"a result carrying an extra requiredSetting field",
			reply,
			{ kind = "rejected", machineId = 11, reason = "wrong_setting" }
		)
	do
		table.insert(problems, p)
	end
	local plain: any = { kind = "committed", machineId = 11 }
	local ok2, reply2 = pcall(T.reply, plain)
	if ok2 and rawequal(reply2, plain) then
		table.insert(
			problems,
			"Contract (D8): reply returned the result table itself rather than a reply built from it"
		)
	elseif ok2 and typeof(reply2) == "table" then
		reply2.kind = "tampered"
		if plain.kind ~= "committed" then
			table.insert(
				problems,
				"Contract (D8): writing to the reply changed the result; the two share a table"
			)
		end
	end
	if #problems > 0 then
		Contract.fail(
			`Contract (D8): reply must be built field by field from an allowlist, never by copying or passing through a record:\n{Contract.firstFew(
				problems,
				8
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     The battery, named.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (TurnRequests) -> () }

TurnRequestsContract.CHECKS = {
	{
		name = "handleReturnsTheStateAndResultProcedureTurnReturns",
		ac = "Contract",
		run = TurnRequestsContract.handleReturnsTheStateAndResultProcedureTurnReturns,
	},
	{
		name = "handleJudgesReachAgainstTheAcceptedPositionsNotThePayload",
		ac = "AC-4",
		run = TurnRequestsContract.handleJudgesReachAgainstTheAcceptedPositionsNotThePayload,
	},
	{
		name = "handleForwardsTheRequestedMachineAndSettingUnswapped",
		ac = "AC-4",
		run = TurnRequestsContract.handleForwardsTheRequestedMachineAndSettingUnswapped,
	},
	{
		name = "handleUsesTheCallersIdNotAPlayerKeyInThePayload",
		ac = "AC-4",
		run = TurnRequestsContract.handleUsesTheCallersIdNotAPlayerKeyInThePayload,
	},
	{
		name = "handleDoesNotMutateItsArguments",
		ac = "AC-4",
		run = TurnRequestsContract.handleDoesNotMutateItsArguments,
	},
	{
		name = "replyToCommittedAndArmedIsExactlyMachineIdAndKind",
		ac = "AC-5",
		run = TurnRequestsContract.replyToCommittedAndArmedIsExactlyMachineIdAndKind,
	},
	{
		name = "replyToRejectedAndRefusedIsExactlyMachineIdKindAndReason",
		ac = "AC-5",
		run = TurnRequestsContract.replyToRejectedAndRefusedIsExactlyMachineIdKindAndReason,
	},
	{
		name = "replyToARealWrongSettingRejectionCarriesNoRequiredSetting",
		ac = "AC-5",
		run = TurnRequestsContract.replyToARealWrongSettingRejectionCarriesNoRequiredSetting,
	},
	{
		name = "replyIsBuiltFieldByFieldNotByCopyingTheResult",
		ac = "Contract (D8)",
		run = TurnRequestsContract.replyIsBuiltFieldByFieldNotByCopyingTheResult,
	},
} :: { Check }

function TurnRequestsContract.failures(T: TurnRequests): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in TurnRequestsContract.CHECKS do
		local ok, err = pcall(check.run, T)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return TurnRequestsContract
