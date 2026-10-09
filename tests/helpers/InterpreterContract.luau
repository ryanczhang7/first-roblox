--!strict
--[[
	SLICE-004 AC-1 and AC-2 written once, as checks over a `perform` function,
	so that `tests/server/interpreter_test.luau` can apply them to the real
	`src/server/session/Interpreter.luau` and
	`tests/server/interpreter_controls_test.luau` can apply them to the wrong
	interpreters in `InterpreterStubs.luau` - and in RED, where the real
	module does not exist and its test file is red at `require`, every check
	here has still been OBSERVED to refuse the interpreter it exists to catch.

	A `Perform` is `(effects: { SessionEffect }, ports: Ports) -> ()`, with
	`Ports` exactly as the story's `## Contract` declares it:

	    transport:     Transport.Bound    -- sendTo(self, playerId, kind, payload),
	                                      -- broadcast(self, kind, payload): METHODS
	    emit:          ({ TelemetryEvent }) -> ()
	    promptRematch: () -> ()
	    computeTrace:  (roundId: string) -> ()
	    place:         (playerId: string, position: Vec) -> ()

	THE RECORDER IS ONE TRACE. Every port call appends `{ port, args }` to a
	single list, so "exactly one call per effect, in list order" is one
	comparison of two sequences rather than six counters that could each be
	right while the order is wrong. Payloads, positions and events are
	compared BY IDENTITY (`==` on the table), because the Contract says the
	interpreter neither copies nor inspects them. The transport methods also
	record `self`, so an interpreter that calls `ports.transport.sendTo(...)`
	with a dot - shifting every argument one place - is caught by the
	argument comparison and named.

	ONE CHECK USES THE REAL `Transport.bind` (merged in SLICE-002) over
	`TransportStubs.ports`' fake `RemoteEvent`s, with no remotes declared
	(P-2). That is AC-1's control as the criterion words it: an interpreter
	that turns a `SendTo` into a broadcast meets `Transport.broadcast`'s
	refusal of a private kind and raises, and a per-player FireClient reaches
	one player object and no other.

	The effect tables are built here, shaped exactly as `Session.SessionEffect`
	and `PhaseMachine.Effect` declare them; the payloads are opaque tables,
	because the interpreter must not look inside them.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Transport = require("@game/ReplicatedStorage/Net/Transport")
local TransportStubs = require("./TransportStubs")

local InterpreterContract = {}

export type Perform = (effects: { any }, ports: any) -> ()

export type Call = { port: string, args: { any }, n: number }

export type Recorder = {
	ports: any,
	calls: { Call },
}

-- The Contract's `Ports`, every member recording into one trace.
function InterpreterContract.recorder(): Recorder
	local calls: { Call } = {}
	local function record(port: string, ...: any)
		table.insert(calls, { port = port, args = { ... }, n = select("#", ...) })
	end
	local transport = {}
	function transport.sendTo(self: any, playerId: any, kind: any, payload: any)
		record("sendTo", self, playerId, kind, payload)
	end
	function transport.broadcast(self: any, kind: any, payload: any)
		record("broadcast", self, kind, payload)
	end
	local ports = {
		transport = transport,
		emit = function(events: any)
			record("emit", events)
		end,
		promptRematch = function()
			record("promptRematch")
		end,
		computeTrace = function(roundId: any)
			record("computeTrace", roundId)
		end,
		place = function(playerId: any, position: any)
			record("place", playerId, position)
		end,
	}
	return { ports = ports, calls = calls }
end

-- The fixture: one effect of every kind `Session.step` can emit, twice for
-- the two routed kinds, with an `Emit` at each end so that order is not
-- merely grouping. Fresh tables on every call, so identity comparisons
-- are against this call's effects.
export type Fixture = {
	effects: { any },
	expected: { Call }, -- the trace a correct interpreter leaves, `self` as the transport
}

local function kindsOf(calls: { Call }): string
	local names: { string } = {}
	for _, call in calls do
		table.insert(names, call.port)
	end
	return table.concat(names, ", ")
end

function InterpreterContract.fixture(transport: any): Fixture
	local event1 = { name = "round_started", fields = { seed = 1 } }
	local event2 = { name = "round_ended", fields = { seed = 1 } }
	local seatView = { playerId = "p1", seatOrder = { "p1", "p2" } }
	local lensView = { visible = {} }
	local roundView = { phase = "Round", secondsLeft = 420 }
	local facilityView = { rooms = {} }
	local position = { x = 1, y = 2, z = 3 }
	local effects = {
		{ kind = "Emit", event = event1 },
		{ kind = "PromptRematch" },
		{ kind = "ComputeTrace", roundId = "r-7" },
		{ kind = "Placed", playerId = "p2", position = position },
		{ kind = "SendTo", playerId = "p1", payloadKind = "SeatView", payload = seatView },
		{ kind = "SendTo", playerId = "p2", payloadKind = "LensView", payload = lensView },
		{ kind = "Broadcast", payloadKind = "RoundView", payload = roundView },
		{ kind = "Broadcast", payloadKind = "FacilityView", payload = facilityView },
		{ kind = "Emit", event = event2 },
	}
	local expected: { Call } = {
		{ port = "emit", args = { { event1 } }, n = 1 },
		{ port = "promptRematch", args = {}, n = 0 },
		{ port = "computeTrace", args = { "r-7" }, n = 1 },
		{ port = "place", args = { "p2", position }, n = 2 },
		{ port = "sendTo", args = { transport, "p1", "SeatView", seatView }, n = 4 },
		{ port = "sendTo", args = { transport, "p2", "LensView", lensView }, n = 4 },
		{ port = "broadcast", args = { transport, "RoundView", roundView }, n = 3 },
		{ port = "broadcast", args = { transport, "FacilityView", facilityView }, n = 3 },
		{ port = "emit", args = { { event2 } }, n = 1 },
	}
	return { effects = effects, expected = expected }
end

-- One recorded call against one expected call. `emit`'s argument is a list
-- whose single element is compared by identity; everything else is `==`.
local function mismatch(index: number, got: Call?, want: Call): string?
	if got == nil then
		return `call {index}: missing; wanted {want.port}`
	end
	if got.port ~= want.port then
		return `call {index}: got {got.port}, wanted {want.port}`
	end
	if got.n ~= want.n then
		return `call {index} ({want.port}): got {got.n} argument(s), wanted {want.n}`
	end
	for i = 1, want.n do
		local g, w = got.args[i], want.args[i]
		if want.port == "emit" and i == 1 then
			if typeof(g) ~= "table" then
				return `call {index} (emit): argument is a {typeof(g)}, wanted a one-element list`
			end
			if #g ~= 1 or g[1] ~= w[1] then
				return `call {index} (emit): got a list of {#g} with [1] = {Deep.show(g[1])}, wanted the effect's own event as the single element`
			end
		elseif g ~= w then
			return `call {index} ({want.port}): argument {i} is {Deep.show(g)}, wanted {Deep.show(w)} (same table, not a copy)`
		end
	end
	return nil
end

local function compareTrace(calls: { Call }, expected: { Call }, header: string)
	local violations: { string } = {}
	for index, want in expected do
		local found = mismatch(index, calls[index], want)
		if found ~= nil then
			table.insert(violations, found)
		end
	end
	if #calls > #expected then
		table.insert(
			violations,
			`{#calls - #expected} extra call(s) after the last effect: {kindsOf(calls)}`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`{header}: {#violations} mismatch(es) over {#expected} effect(s); the trace was [{kindsOf(
				calls
			)}]:\n` .. Contract.firstFew(violations, 10)
		)
	end
end

--[[ AC-1 ]]

-- Every kind, once each (twice for the two routed ones), in list order, with
-- the effect's own tables as arguments. Pinned per-port counts fall out of
-- the trace: a duplicated or dropped call shifts every later index.
function InterpreterContract.everyKindMakesExactlyOneCallInListOrder(perform: Perform)
	local recorder = InterpreterContract.recorder()
	local fixture = InterpreterContract.fixture(recorder.ports.transport)
	perform(fixture.effects, recorder.ports)
	compareTrace(recorder.calls, fixture.expected, "AC-1")
end

-- `Emit` is one call per effect carrying a FRESH one-element list. An
-- interpreter that batches events into one call, or reuses one list table,
-- passes a count and fails here.
function InterpreterContract.emitIsAFreshOneElementListPerEffect(perform: Perform)
	local recorder = InterpreterContract.recorder()
	local a = { name = "a" }
	local b = { name = "b" }
	perform({ { kind = "Emit", event = a }, { kind = "Emit", event = b } }, recorder.ports)
	local calls = recorder.calls
	if #calls ~= 2 or calls[1].port ~= "emit" or calls[2].port ~= "emit" then
		Contract.fail(
			`AC-1 Emit: two Emit effects left the trace [{kindsOf(calls)}], wanted [emit, emit]`
		)
	end
	local first, second = calls[1].args[1], calls[2].args[1]
	if typeof(first) ~= "table" or typeof(second) ~= "table" then
		Contract.fail(
			`AC-1 Emit: emit was handed {typeof(first)} and {typeof(second)}, wanted lists`
		)
	end
	if first == second then
		Contract.fail(
			"AC-1 Emit: both emit calls were handed the SAME list table; each must be fresh"
		)
	end
	if #first ~= 1 or first[1] ~= a then
		Contract.fail(`AC-1 Emit: first list is {Deep.show(first)}, wanted exactly the first event`)
	end
	if #second ~= 1 or second[1] ~= b then
		Contract.fail(
			`AC-1 Emit: second list is {Deep.show(second)}, wanted exactly the second event`
		)
	end
end

-- Zero effects, zero calls, and no raise.
function InterpreterContract.anEmptyListMakesNoCall(perform: Perform)
	local recorder = InterpreterContract.recorder()
	local ok, err = pcall(perform, {}, recorder.ports)
	if not ok then
		Contract.fail(`AC-1: perform(\{}) raised: {tostring(err)}`)
	end
	if #recorder.calls ~= 0 then
		Contract.fail(
			`AC-1: perform(\{}) made {#recorder.calls} call(s): [{kindsOf(recorder.calls)}]`
		)
	end
end

--[[
	AC-1's control, through the real `Transport.bind`. Two players, no remotes
	declared (P-2), the other four ports recording. A `SendTo` of a private
	kind must reach `FireClient` on that kind's event with p1's object and
	the payload table itself, once; a `Broadcast` of a public kind must reach
	`FireAllClients` on its event once; no other event fires. An interpreter
	that broadcasts a `SendTo` raises inside `Transport.broadcast` ("is not a
	public payload kind") and is reported with that message.
]]
function InterpreterContract.theRealTransportRoutesASendToItsPlayerOnlyAndABroadcastToAll(
	perform: Perform
)
	local p1, p2 = { Name = "p1" }, { Name = "p2" }
	local harness = TransportStubs.ports({ p1 = p1, p2 = p2 })
	local context: any = {
		isSeated = function()
			return true
		end,
		phase = function()
			return "Lobby"
		end,
		clock = {
			now = function()
				return 0
			end,
		},
	}
	local bound = Transport.bind({}, context, {}, harness.ports)
	local recorder = InterpreterContract.recorder()
	local ports = recorder.ports
	ports.transport = bound

	local seatView = { playerId = "p1" }
	local roundView = { phase = "Lobby" }
	local ok, err = pcall(perform, {
		{ kind = "SendTo", playerId = "p1", payloadKind = "SeatView", payload = seatView },
		{ kind = "Broadcast", payloadKind = "RoundView", payload = roundView },
	}, ports)
	if not ok then
		Contract.fail(
			`AC-1 control: the real transport refused the interpreter's routing: {tostring(err)}`
		)
	end

	local violations: { string } = {}
	local seat = harness.events.SeatView
	local round = harness.events.RoundView
	if #seat.fireClientCalls ~= 1 then
		table.insert(
			violations,
			`SeatView: FireClient called {#seat.fireClientCalls} time(s), wanted 1`
		)
	elseif seat.fireClientCalls[1].player ~= p1 then
		table.insert(
			violations,
			`SeatView: FireClient went to {Deep.show(seat.fireClientCalls[1].player)}, wanted p1's object`
		)
	elseif seat.fireClientCalls[1].payload ~= seatView then
		table.insert(
			violations,
			"SeatView: FireClient carried a different table from the effect's payload"
		)
	end
	if #round.fireAllCalls ~= 1 then
		table.insert(
			violations,
			`RoundView: FireAllClients called {#round.fireAllCalls} time(s), wanted 1`
		)
	elseif round.fireAllCalls[1].payload ~= roundView then
		table.insert(
			violations,
			"RoundView: FireAllClients carried a different table from the effect's payload"
		)
	end
	for name, event in harness.events do
		local clients = #event.fireClientCalls
		local all = #event.fireAllCalls
		if name == "SeatView" then
			if all ~= 0 then
				table.insert(
					violations,
					`SeatView: FireAllClients called {all} time(s); a private kind must never be broadcast`
				)
			end
		elseif name == "RoundView" then
			if clients ~= 0 then
				table.insert(violations, `RoundView: FireClient called {clients} time(s), wanted 0`)
			end
		elseif clients + all ~= 0 then
			table.insert(
				violations,
				`{name}: fired {clients + all} time(s) with no effect of that kind`
			)
		end
	end
	if #recorder.calls ~= 0 then
		table.insert(violations, `the other ports were called: [{kindsOf(recorder.calls)}]`)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-1 control: {#violations} routing fault(s):\n` .. Contract.firstFew(violations, 8)
		)
	end
end

--[[ AC-2 ]]

-- An unknown kind raises naming it verbatim, AT that effect: the two before
-- it have been performed and the one after it has not. No pre-validation.
function InterpreterContract.anUnknownKindRaisesNamingItAtThatEffect(perform: Perform)
	local recorder = InterpreterContract.recorder()
	local payload = {}
	local ok, err = pcall(perform, {
		{ kind = "Broadcast", payloadKind = "RoundView", payload = payload },
		{ kind = "PromptRematch" },
		{ kind = "Frobnicate", playerId = "p1" },
		{ kind = "Emit", event = { name = "after" } },
	}, recorder.ports)
	if ok then
		Contract.fail(
			`AC-2: an effect of kind "Frobnicate" was performed without raising; the trace was [{kindsOf(
				recorder.calls
			)}]`
		)
	end
	local message = tostring(err)
	if string.find(message, "Frobnicate", 1, true) == nil then
		Contract.fail(`AC-2: the raise does not name the kind "Frobnicate"; it said: {message}`)
	end
	local trace = kindsOf(recorder.calls)
	if trace ~= "broadcast, promptRematch" then
		Contract.fail(
			`AC-2: the effects before the unknown one must be performed and the one after it must not; the trace was [{trace}], wanted [broadcast, promptRematch]`
		)
	end
end

-- `AssignSeats` is consumed by `Session`; one reaching the interpreter is a
-- bug and is refused by name, exactly as an unknown kind is.
function InterpreterContract.assignSeatsRaisesNamingIt(perform: Perform)
	local recorder = InterpreterContract.recorder()
	local ok, err = pcall(perform, {
		{ kind = "AssignSeats", seed = 42, players = { "p1", "p2", "p3", "p4" } },
	}, recorder.ports)
	if ok then
		Contract.fail(`AC-2: AssignSeats was accepted; the trace was [{kindsOf(recorder.calls)}]`)
	end
	local message = tostring(err)
	if string.find(message, "AssignSeats", 1, true) == nil then
		Contract.fail(`AC-2: the raise does not name AssignSeats; it said: {message}`)
	end
	if #recorder.calls ~= 0 then
		Contract.fail(
			`AC-2: AssignSeats made {#recorder.calls} port call(s) before raising: [{kindsOf(
				recorder.calls
			)}]`
		)
	end
end

return InterpreterContract
