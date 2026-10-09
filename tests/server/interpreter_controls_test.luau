--!strict
--[[
	The negative controls for SLICE-004 AC-1 and AC-2, and the proof that
	each check in `tests/helpers/InterpreterContract.luau` refuses the
	interpreter it exists to catch.

	AC-1 NAMES ITS CONTROL: "an interpreter that turns a `SendTo` into a
	broadcast must fail, because `Transport` raises for a private kind" -
	`sendToBroadcasts`, which is also D-1's mutation. The rest are one-defect
	interpreters for the remaining clauses of the Contract's "Interpreter,
	exact semantics" block.

	EVERY CONTROL IS ASSERTED TO FAIL EXACTLY THE CHECKS IT SHOULD, and the
	baseline is asserted to pass every check: a control failing a check is
	then a control with ONE defect rather than a broken stub, and a control
	that starts failing a check it did not fail before is a change in what
	the suite discriminates, worth a red line. The sets below were MEASURED
	under `lune run test` in RED and pinned exactly here; the story's
	`## Handoff` carries the table.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. The interpreters are
	`InterpreterStubs.luau` over the merged `Transport`, so these controls
	EXECUTE in RED while `interpreter_test.luau`'s assertions against the
	real `src/server/session/Interpreter.luau` are red at require.
]]

local Contract = require("../helpers/InterpreterContract")
local Stubs = require("../helpers/InterpreterStubs")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local CHECKS: { Named } = {
	{ label = "AC-1 trace", check = Contract.everyKindMakesExactlyOneCallInListOrder },
	{ label = "AC-1 emit", check = Contract.emitIsAFreshOneElementListPerEffect },
	{ label = "AC-1 empty", check = Contract.anEmptyListMakesNoCall },
	{
		label = "AC-1 transport",
		check = Contract.theRealTransportRoutesASendToItsPlayerOnlyAndABroadcastToAll,
	},
	{ label = "AC-2 unknown", check = Contract.anUnknownKindRaisesNamingItAtThatEffect },
	{ label = "AC-2 AssignSeats", check = Contract.assignSeatsRaisesNamingIt },
}

-- Which checks each defect must fail, and no other. Measured, then pinned.
local EXPECTED: { [string]: { string } } = {
	sendToBroadcasts = { "AC-1 trace", "AC-1 transport" },
	sendToDotCall = { "AC-1 trace", "AC-1 transport" },
	sendsTwice = { "AC-1 trace", "AC-1 transport" },
	dropsEmit = { "AC-1 trace", "AC-1 emit" },
	emitsTheEventNotAList = { "AC-1 trace", "AC-1 emit" },
	-- Measured: the raise at the unknown effect aborts the list before the
	-- deferred batch is emitted, so AC-2's trace is still correct.
	emitsAllAtOnce = { "AC-1 trace", "AC-1 emit" },
	emitSharesOneList = { "AC-1 trace", "AC-1 emit" },
	copiesPayload = { "AC-1 trace", "AC-1 transport" },
	prevalidates = { "AC-2 unknown" },
	swallowsUnknown = { "AC-2 unknown", "AC-2 AssignSeats" },
	raiseOmitsKind = { "AC-2 unknown", "AC-2 AssignSeats" },
	continuesAfterRaise = { "AC-2 unknown" },
	acceptsAssignSeats = { "AC-2 AssignSeats" },
	reversesOrder = { "AC-1 trace", "AC-1 emit", "AC-2 unknown" },
	placeDropsPosition = { "AC-1 trace" },
	computeTraceDropsRoundId = { "AC-1 trace" },
}

local function failing(perform: any): ({ string }, { [string]: string })
	local labels: { string } = {}
	local messages: { [string]: string } = {}
	for _, named in CHECKS do
		local ok, err = pcall(named.check, perform)
		if not ok then
			table.insert(labels, named.label)
			messages[named.label] = tostring(err)
		end
	end
	return labels, messages
end

local function same(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	local x, y = table.clone(a), table.clone(b)
	table.sort(x)
	table.sort(y)
	for i, v in x do
		if y[i] ~= v then
			return false
		end
	end
	return true
end

local tests: { [string]: () -> () } = {}

tests["baseline: a correct interpreter passes every AC-1 and AC-2 check"] = function()
	local labels, messages = failing(Stubs.build({}))
	local detail: { string } = {}
	for _, label in labels do
		table.insert(detail, `{label}: {messages[label]}`)
	end
	assert(#labels == 0, `the baseline failed {#labels} check(s):\n` .. table.concat(detail, "\n"))
end

tests["every defect in InterpreterStubs.DEFECTS has an expected set here, and the reverse"] = function()
	local missing: { string } = {}
	for _, defect in Stubs.DEFECTS do
		if EXPECTED[defect] == nil then
			table.insert(missing, defect)
		end
	end
	assert(#missing == 0, `no expected set for: {table.concat(missing, ", ")}`)
	local stray: { string } = {}
	for defect in EXPECTED do
		if table.find(Stubs.DEFECTS, defect) == nil then
			table.insert(stray, defect)
		end
	end
	assert(
		#stray == 0,
		`expected sets for defects the stubs do not build: {table.concat(stray, ", ")}`
	)
end

for _, defect in Stubs.DEFECTS do
	tests[`control {defect}: fails exactly [{table.concat(EXPECTED[defect] or {}, ", ")}]`] = function()
		local want = EXPECTED[defect]
		assert(want ~= nil, `no expected set for {defect}`)
		local labels, messages = failing(Stubs.build({ [defect] = true }))
		if not same(labels, want :: { string }) then
			local detail: { string } = {}
			for _, label in labels do
				table.insert(detail, `  {label}: {messages[label]}`)
			end
			error(
				`{defect} failed [{table.concat(labels, ", ")}], expected [{table.concat(
					want :: { string },
					", "
				)}]\n` .. table.concat(detail, "\n"),
				0
			)
		end
	end
end

-- AC-1's named control, spelled out: the real transport's own refusal is
-- what reports a broadcast SendTo, and the message is Transport's.
tests["AC-1 control: a SendTo turned into a broadcast is refused by the real Transport with 'is not a public payload kind'"] = function()
	local ok, err = pcall(
		Contract.theRealTransportRoutesASendToItsPlayerOnlyAndABroadcastToAll,
		Stubs.build({ sendToBroadcasts = true })
	)
	assert(ok == false, "the check passed over an interpreter that broadcasts secrets")
	local message = tostring(err)
	assert(
		string.find(
			message,
			'Transport.broadcast: "SeatView" is not a public payload kind',
			1,
			true
		) ~= nil,
		`the refusal is not Transport's own; it said: {message}`
	)
end

-- AC-2's wording: the kind appears verbatim in the raise.
tests["AC-2 control: a raise that omits the kind is reported as not naming Frobnicate"] = function()
	local ok, err = pcall(
		Contract.anUnknownKindRaisesNamingItAtThatEffect,
		Stubs.build({ raiseOmitsKind = true })
	)
	assert(ok == false, "the check passed over a raise with no kind in it")
	assert(
		string.find(tostring(err), 'does not name the kind "Frobnicate"', 1, true) ~= nil,
		`unexpected message: {tostring(err)}`
	)
end

-- The at-that-effect clause: pre-validation performs nothing before the
-- raise, and the trace in the message shows it.
tests["AC-2 control: a pre-validating interpreter is reported with an empty trace"] = function()
	local ok, err = pcall(
		Contract.anUnknownKindRaisesNamingItAtThatEffect,
		Stubs.build({ prevalidates = true })
	)
	assert(ok == false, "the check passed over a pre-validating interpreter")
	assert(
		string.find(tostring(err), "the trace was [], wanted [broadcast, promptRematch]", 1, true)
			~= nil,
		`unexpected message: {tostring(err)}`
	)
end

return tests
