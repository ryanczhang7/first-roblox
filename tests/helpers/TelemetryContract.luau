--!strict
--[[
	TEL-001 AC-1 through AC-6 written once, as checks over an EVENT module and a
	SINK module handed in as parameters rather than over
	`src/shared/telemetry/Event.luau` and `src/shared/telemetry/Sink.luau` by
	name - the same arrangement as `ProjectionContract.luau`, for the same
	reason.

	`tests/shared/telemetry_event_test.luau` and
	`tests/shared/telemetry_sink_test.luau` apply these to the real modules.
	`tests/shared/telemetry_controls_test.luau` applies them to the deliberately
	wrong modules in `TelemetryStubs.luau`, so that in RED - where the
	production modules do not exist, the real files fail to load, and not one
	assertion in them has executed - every check here has still been EXECUTED
	and observed to reject the implementation it exists to catch.

	THE ORACLE PARTITION IS HONOURED HERE. AC-2 is SETTLED: the nine names and
	their buckets below are read out of brief B6 as `architecture.md` §6
	tabulates them, and they are not designed here. AC-1, AC-4 and AC-6 are
	mechanical and pinned exactly. AC-3 and AC-5 are mechanical with the
	controls the criteria name, and `TelemetryStubs.luau` writes those controls
	out. AC-5 is TWO checks, because the criterion has two halves and an
	implementation can pass one while failing the other.

	An `Event` here is anything with the Contract's two exports, called with a
	dot exactly as the story writes them:

	    Event.BUCKETS : { [string]: Bucket }
	    Event.new(name, at, sessionId, playerId?, fields?) -> TelemetryEvent

	and a `Sink` module is anything with the Contract's three:

	    Sink.noop() -> Sink
	    Sink.recording() -> RecordingSink   (.events, :clear())
	    Sink.dispatch(sink, events) -> { delivered, dropped }

	The sink checks build their events BY HAND, as literal tables of the
	Contract's `TelemetryEvent` shape, so that a sink can be checked with no
	Event module at all - which is what lets the sink controls run in RED.

	Every message names its criterion, because the controls assert on the text.
]]

local Clock = require("../../src/shared/Clock")
local Deep = require("./Deep")

local TelemetryContract = {}

export type EventModule = any
export type SinkModule = any

--[[
	AC-2, SETTLED. Brief B6's nine events and A5's three buckets, exactly as
	`docs/wiki/architecture.md` §6 tabulates them. Three of these have no
	emitter until M5 (`day_n_return`, `co_play_with_known_player`, `purchase`)
	and are in the mapping anyway, so that M5 adds an emitter rather than a
	vocabulary. Nothing here asserts that a name has an emitter.
]]
local BUCKETS: { [string]: string } = {
	join = "D1",
	first_round_complete = "D1",
	bounce_before_resolution = "D1",
	session_end = "D1",
	round_complete = "D2_7",
	rematch_accepted = "D2_7",
	day_n_return = "D8_28",
	co_play_with_known_player = "D8_28",
	purchase = "D8_28",
}

-- The same nine in a fixed order, for messages and for cycling through cases.
local NAMES: { string } = {
	"join",
	"first_round_complete",
	"bounce_before_resolution",
	"session_end",
	"round_complete",
	"rematch_accepted",
	"day_n_return",
	"co_play_with_known_player",
	"purchase",
}

TelemetryContract.BUCKETS = BUCKETS
TelemetryContract.NAMES = NAMES

local VALID_BUCKETS: { [string]: boolean } = { D1 = true, D2_7 = true, D8_28 = true }

--[[
	The final assertion of every check goes through this rather than `assert`.
	MEASURED in SEAT-002's RED: under Lune, `assert(false, message)` truncates
	the message to 512 characters after the location prefix and `error` does
	not. The checks accumulate every violation, and a control whose needle lies
	beyond the cut can never match. Level 2 attributes the failure to the test
	that called the check.
]]
local function check(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function firstFew(list: { string }, count: number): string
	local shown: { string } = {}
	for i = 1, math.min(count, #list) do
		shown[i] = list[i]
	end
	local more = #list - #shown
	return table.concat(shown, "\n") .. (if more > 0 then `\n  ... and {more} more` else "")
end

local function indent(text: string): string
	return (string.gsub(text, "\n", "\n    "))
end

--[[
	A `TelemetryEvent` built by hand, for the sink checks. Not `Event.new`: the
	sink checks must run with no Event module, and a sink is handed records of
	this shape by the driver whatever built them.
]]
export type Fields = { [string]: any }

function TelemetryContract.event(name: string, at: number, fields: Fields): any
	return {
		name = name,
		at = at,
		bucket = BUCKETS[name],
		sessionId = "session-1",
		playerId = "123456",
		fields = fields,
	}
end

-- The three events AC-4 says "three events" over: distinct names, distinct
-- times, and fields that between them carry every scalar type.
function TelemetryContract.threeEvents(): { any }
	return {
		TelemetryContract.event("join", 0, { seat = 1 }),
		TelemetryContract.event("round_complete", 42.5, { winner = "amy", contested = true }),
		TelemetryContract.event("session_end", 99, { seconds = 99, reason = "left" }),
	}
end

-- A sink that records into a list of its own and raises on the events a
-- predicate picks out. The oracle side of AC-5: the list is the check's, not
-- the sink module's.
local function raisingSink(shouldRaise: (any) -> boolean): ({ emit: (any) -> () }, { any })
	local seen: { any } = {}
	local sink = {
		emit = function(event: any)
			if shouldRaise(event) then
				error(`sink exploded on {tostring(event.name)}`)
			end
			table.insert(seen, event)
		end,
	}
	return sink, seen
end

--[[
	AC-1. An event constructed with the injected clock's `t` carries exactly
	`at = t`, and its `name`, `bucket`, `sessionId`, `playerId` and `fields`
	are the values supplied - and nothing else.

	`t` comes from `Clock.manual(t).now()`, as the driver will supply it, and
	the times are chosen so that a constant, a clock the module reads for
	itself, and the real time of the run all differ from every one of them.
	`Deep.diff` against the expected record is the whole assertion: a missing
	field, a wrong value and an EXTRA field all show up, by name. The last case
	omits `playerId` and `fields`, which the Contract makes optional: an event
	with no player carries `nil`, and one with no fields carries an EMPTY
	table, because `TelemetryEvent.fields` is not optional.
]]
type ConstructionCase = {
	label: string,
	name: string,
	t: number,
	sessionId: string,
	playerId: string?,
	fields: Fields?,
}

local CONSTRUCTION_CASES: { ConstructionCase } = {
	{
		label = "at t = 0",
		name = "join",
		t = 0,
		sessionId = "session-a",
		playerId = "1",
		fields = { seat = 1 },
	},
	{
		label = "at a fractional t",
		name = "round_complete",
		t = 1234.5,
		sessionId = "session-b",
		playerId = "987654321",
		fields = { winner = "amy", seconds = 61.25, contested = false },
	},
	{
		label = "at a large t",
		name = "bounce_before_resolution",
		t = 2 ^ 31,
		sessionId = "session-c",
		playerId = "42",
		fields = { phase = "Lobby" },
	},
	{
		label = "for an M5 event with no emitter yet",
		name = "purchase",
		t = 7,
		sessionId = "session-d",
		playerId = "7",
		fields = { product = "lantern", robux = 25 },
	},
	{
		label = "with no player and no fields",
		name = "session_end",
		t = 300,
		sessionId = "session-e",
		playerId = nil,
		fields = nil,
	},
}

function TelemetryContract.eventCarriesTheSuppliedValuesAndTheClocksTime(Event: EventModule)
	local violations: { string } = {}

	for _, case in CONSTRUCTION_CASES do
		local clock = Clock.manual(case.t)
		local ok, result =
			pcall(Event.new, case.name, clock.now(), case.sessionId, case.playerId, case.fields)
		if not ok then
			table.insert(
				violations,
				`  {case.label} ({case.name}): construction raised: {tostring(result)}`
			)
			continue
		end

		local expected = {
			name = case.name,
			at = case.t,
			bucket = BUCKETS[case.name],
			sessionId = case.sessionId,
			playerId = case.playerId,
			fields = if case.fields == nil then {} else Deep.copy(case.fields),
		}
		local diff = Deep.diff(expected, result)
		if diff ~= "" then
			table.insert(violations, `  {case.label} ({case.name}):\n    {indent(diff)}`)
		end
	end

	check(
		#violations == 0,
		`AC-1: the event is not exactly the supplied values with at = the clock's t, in `
			.. `{#violations} of {#CONSTRUCTION_CASES} cases:\n{firstFew(violations, 6)}`
	)
end

--[[
	AC-2. `Event.BUCKETS` names all nine B6 events with exactly the settled
	buckets, contains NOTHING else, and is frozen.

	Both directions: every one of the nine present with the right bucket, and
	exactly nine entries, so an invented tenth event fails as loudly as a
	missing one. Frozen is observed rather than asked about: a write to an
	existing key and a write to a new key must both raise and both leave the
	table unchanged, which is what frozen means to a caller whether it was
	`table.freeze` or a metatable.
]]
function TelemetryContract.bucketsNameExactlyTheNineB6Events(Event: EventModule)
	local buckets = Event.BUCKETS
	check(
		typeof(buckets) == "table",
		`AC-2: Event.BUCKETS is {typeof(buckets)}, not a table of name -> bucket`
	)

	local violations: { string } = {}
	for _, name in NAMES do
		local want = BUCKETS[name]
		local got = buckets[name]
		if got ~= want then
			table.insert(
				violations,
				`  {name}: expected {want}, got {if got == nil
					then "nil (missing)"
					else Deep.show(got)}`
			)
		end
	end

	local extras: { string } = {}
	local count = 0
	for key, value in pairs(buckets :: { [any]: any }) do
		count += 1
		if BUCKETS[key] == nil then
			table.insert(extras, `  {tostring(key)} = {Deep.show(value)} is not a B6 event`)
		elseif not VALID_BUCKETS[value] then
			table.insert(
				extras,
				`  {tostring(key)} = {Deep.show(value)} is not one of D1, D2_7, D8_28`
			)
		end
	end
	table.sort(extras)

	local frozen: { string } = {}
	local before = buckets.join
	local wroteExisting = pcall(function()
		buckets.join = "D8_28"
	end)
	if wroteExisting or buckets.join ~= before then
		table.insert(
			frozen,
			`  assigning BUCKETS.join = "D8_28" {if wroteExisting then "did not raise" else "raised"}`
				.. ` and the value is now {Deep.show(buckets.join)}`
		)
		pcall(function()
			buckets.join = before
		end)
	end
	-- A key no B6 event and no control stub carries, so that a tenth entry
	-- already in the table is reported as an extra rather than as a write.
	local NEW_KEY = "not_a_b6_event"
	local beforeNew = buckets[NEW_KEY]
	local wroteNew = pcall(function()
		buckets[NEW_KEY] = "D1"
	end)
	if wroteNew or buckets[NEW_KEY] ~= beforeNew then
		table.insert(
			frozen,
			`  assigning a new key BUCKETS.{NEW_KEY} {if wroteNew then "did not raise" else "raised"}`
				.. ` and the key is now {Deep.show(buckets[NEW_KEY])}`
		)
		pcall(function()
			buckets[NEW_KEY] = beforeNew
		end)
	end

	check(
		#violations == 0 and #extras == 0 and count == 9 and #frozen == 0,
		`AC-2: BUCKETS does not name exactly the nine B6 events with their settled buckets. `
			.. `{#violations} of 9 wrong or missing:\n{table.concat(violations, "\n")}\n`
			.. `{#extras} extra or malformed entries ({count} entries in all, 9 expected):\n`
			.. `{table.concat(extras, "\n")}\n`
			.. `{#frozen} way(s) it is not frozen:\n{table.concat(frozen, "\n")}`
	)
end

--[[
	AC-3. A name not in the mapping is REFUSED at construction - no event, no
	guessed bucket, no absent bucket - and the refusal names the name.

	The strangers are the ways a call site gets a name wrong: a typo, the wrong
	case, trailing whitespace, a plausible event nobody declared, and the empty
	string. The positive half, without which a constructor that always raises
	passes: every one of the nine still constructs.
]]
local STRANGERS: { string } = {
	"joins",
	"Join",
	"round_complete ",
	"purchase_refund",
	"level_up",
	"",
}

function TelemetryContract.unknownNameIsRefused(Event: EventModule)
	local violations: { string } = {}

	for _, stranger in STRANGERS do
		local ok, result = pcall(Event.new, stranger, 1, "session-1", "1", {})
		if ok then
			local bucket = if typeof(result) == "table"
				then Deep.show(result.bucket)
				else "<no event>"
			table.insert(
				violations,
				`  Event.new("{stranger}", ...) returned an event with bucket {bucket} instead of `
					.. `raising; a guessed bucket is a metric quietly measuring the wrong thing`
			)
		elseif stranger ~= "" and string.find(tostring(result), stranger, 1, true) == nil then
			table.insert(
				violations,
				`  Event.new("{stranger}", ...) raised, but the error does not name the `
					.. `offending name:\n    {tostring(result)}`
			)
		end
	end

	for _, name in NAMES do
		local ok, result = pcall(Event.new, name, 1, "session-1", "1", {})
		if not ok then
			table.insert(
				violations,
				`  Event.new("{name}", ...) raised for a B6 event: {tostring(result)}`
			)
		end
	end

	check(
		#violations == 0,
		`AC-3: an unknown event name is not refused by construction, in {#violations} case(s):\n`
			.. table.concat(violations, "\n")
	)
end

--[[
	AC-6. A `fields` value that is not a string, number or boolean is refused
	at construction, and the refusal NAMES THE OFFENDING KEY.

	Refused: a nested table, a function, a thread - each alone, and a table
	among three legitimate scalars so that the key named has to be the right
	one. Accepted: each scalar type, including the edge values that are falsy
	or empty (`false`, `0`, `""`), an empty map, and no map at all.
]]
type RejectedCase = { label: string, key: string, fields: Fields }
type AcceptedCase = { label: string, fields: Fields? }

local function rejectedCases(): { RejectedCase }
	return {
		{ label = "a nested table", key = "payload", fields = { payload = { x = 1 } } },
		{ label = "an empty nested table", key = "extra", fields = { extra = {} } },
		{ label = "a function", key = "callback", fields = { callback = function() end } },
		{
			label = "a thread",
			key = "job",
			fields = { job = coroutine.create(function() end) },
		},
		{
			label = "a table among three scalars",
			key = "nested",
			fields = { ok = "yes", count = 2, flag = true, nested = { deep = true } },
		},
	}
end

local ACCEPTED_CASES: { AcceptedCase } = {
	{ label = "a string", fields = { reason = "left" } },
	{ label = "an empty string", fields = { reason = "" } },
	{ label = "a number", fields = { seconds = 61.25 } },
	{ label = "zero", fields = { seconds = 0 } },
	{ label = "a negative number", fields = { delta = -3 } },
	{ label = "true", fields = { contested = true } },
	{ label = "false", fields = { contested = false } },
	{ label = "one of each", fields = { winner = "amy", seconds = 42, contested = true } },
	{ label = "an empty map", fields = {} },
	{ label = "no map at all", fields = nil },
}

function TelemetryContract.nonScalarFieldIsRefusedNamingTheKey(Event: EventModule)
	local violations: { string } = {}

	local rejected = rejectedCases()
	for _, case in rejected do
		local ok, result = pcall(Event.new, "join", 1, "session-1", "1", case.fields)
		if ok then
			table.insert(
				violations,
				`  {case.label} under key "{case.key}" was ACCEPTED; the event carries `
					.. `fields = {Deep.show(
						if typeof(result) == "table" then result.fields else result
					)}`
			)
		elseif string.find(tostring(result), case.key, 1, true) == nil then
			table.insert(
				violations,
				`  {case.label} under key "{case.key}" was refused, but the error does not name `
					.. `the key:\n    {tostring(result)}`
			)
		end
	end

	for _, case in ACCEPTED_CASES do
		local ok, result = pcall(Event.new, "join", 1, "session-1", "1", case.fields)
		if not ok then
			table.insert(violations, `  {case.label} was REFUSED: {tostring(result)}`)
		else
			local expected = if case.fields == nil then {} else Deep.copy(case.fields)
			local diff =
				Deep.diff(expected, if typeof(result) == "table" then result.fields else result)
			if diff ~= "" then
				table.insert(
					violations,
					`  {case.label} was accepted but not carried intact:\n    {indent(diff)}`
				)
			end
		end
	end

	check(
		#violations == 0,
		`AC-6: a non-scalar field value is not refused naming its key, or a scalar one is not `
			.. `accepted intact, in {#violations} of {#rejected + #ACCEPTED_CASES} cases:\n`
			.. firstFew(violations, 8)
	)
end

--[[
	AC-4. A recording sink holds exactly the events emitted to it, in the
	order they were emitted, with their fields intact; a fresh one holds
	nothing; `clear` empties it; and two recording sinks do not share a list.

	"In order" is a positional deep comparison of the whole list, and "fields
	intact" is the same comparison reaching into each event's `fields` - a
	length check would pass a sink that stored three of anything.
]]
function TelemetryContract.recordingSinkHoldsExactlyWhatWasEmittedInOrder(Sink: SinkModule)
	local violations: { string } = {}

	local sink = Sink.recording()
	check(
		typeof(sink) == "table" and typeof(sink.emit) == "function",
		`AC-4: Sink.recording() returned {Deep.show(sink)}; a sink is a table with an emit function`
	)
	check(
		typeof(sink.events) == "table",
		`AC-4: a recording sink's events is {typeof(sink.events)}, not a list`
	)
	if #sink.events ~= 0 then
		table.insert(violations, `  a fresh recording sink already holds {#sink.events} event(s)`)
	end

	local three = TelemetryContract.threeEvents()
	for _, event in three do
		sink.emit(event)
	end
	local diff = Deep.diff(three, sink.events)
	if diff ~= "" then
		table.insert(
			violations,
			`  after emitting three events the sink holds something else (positional, fields `
				.. `included):\n    {indent(diff)}`
		)
	end

	local other = Sink.recording()
	if #other.events ~= 0 then
		table.insert(
			violations,
			`  a second recording sink holds {#other.events} event(s) emitted to the first; `
				.. `the list is shared`
		)
	end

	local cleared, clearError = pcall(function()
		sink:clear()
	end)
	if not cleared then
		table.insert(violations, `  sink:clear() raised: {tostring(clearError)}`)
	elseif #sink.events ~= 0 then
		table.insert(violations, `  after clear() the sink still holds {#sink.events} event(s)`)
	else
		sink.emit(three[2])
		local one = Deep.diff({ three[2] }, sink.events)
		if one ~= "" then
			table.insert(
				violations,
				`  one event emitted after clear() is not held alone:\n    {indent(one)}`
			)
		end
	end

	check(
		#violations == 0,
		`AC-4: the recording sink does not hold exactly what was emitted, in order, with fields `
			.. `intact:\n{table.concat(violations, "\n")}`
	)
end

--[[
	The positive half of dispatch, which AC-5's counted drop needs to mean
	anything: through a sink that never raises, every event is delivered and
	none is dropped - for zero, one and three events, through `recording` and
	through `noop` - and the recording sink holds them in order.
]]
function TelemetryContract.dispatchDeliversEveryEventToAWorkingSink(Sink: SinkModule)
	local violations: { string } = {}
	local three = TelemetryContract.threeEvents()
	local batches: { { label: string, events: { any } } } = {
		{ label = "no events", events = {} },
		{ label = "one event", events = { three[1] } },
		{ label = "three events", events = three },
	}

	for _, batch in batches do
		local recording = Sink.recording()
		local ok, result = pcall(Sink.dispatch, recording, batch.events)
		if not ok then
			table.insert(
				violations,
				`  dispatching {batch.label} to a recording sink raised: {tostring(result)}`
			)
			continue
		end
		if
			typeof(result) ~= "table"
			or result.delivered ~= #batch.events
			or result.dropped ~= 0
		then
			table.insert(
				violations,
				`  dispatching {batch.label} to a recording sink returned {Deep.show(result)}; `
					.. `expected delivered = {#batch.events}, dropped = 0`
			)
		end
		local diff = Deep.diff(batch.events, recording.events)
		if diff ~= "" then
			table.insert(
				violations,
				`  after dispatching {batch.label} the recording sink holds something else:\n    {indent(
					diff
				)}`
			)
		end

		local noop = Sink.noop()
		if typeof(noop) ~= "table" or typeof(noop.emit) ~= "function" then
			table.insert(violations, `  Sink.noop() returned {Deep.show(noop)}`)
			continue
		end
		local noopOk, noopResult = pcall(Sink.dispatch, noop, batch.events)
		if not noopOk then
			table.insert(
				violations,
				`  dispatching {batch.label} to the noop sink raised: {tostring(noopResult)}`
			)
		elseif
			typeof(noopResult) ~= "table"
			or noopResult.delivered ~= #batch.events
			or noopResult.dropped ~= 0
		then
			table.insert(
				violations,
				`  dispatching {batch.label} to the noop sink returned {Deep.show(noopResult)}; `
					.. `expected delivered = {#batch.events}, dropped = 0`
			)
		end
	end

	check(
		#violations == 0,
		`dispatch: a working sink does not receive every event with none dropped:\n`
			.. table.concat(violations, "\n")
	)
end

--[[
	AC-5, first half. A sink whose `emit` raises does NOT propagate the raise
	to the caller of `Sink.dispatch`. Nothing here reads the result: this half
	is only "the caller survives", so that the control which propagates fails
	here and the control which swallows-and-miscounts does not.
]]
function TelemetryContract.raisingEmitDoesNotPropagate(Sink: SinkModule)
	local violations: { string } = {}
	local three = TelemetryContract.threeEvents()

	local always = raisingSink(function()
		return true
	end)
	local ok, err = pcall(Sink.dispatch, always, three)
	if not ok then
		table.insert(
			violations,
			`  a sink that raises on every event: dispatch let the raise reach the caller:\n    `
				.. tostring(err)
		)
	end

	local second = raisingSink(function(event)
		return event.name == "round_complete"
	end)
	ok, err = pcall(Sink.dispatch, second, three)
	if not ok then
		table.insert(
			violations,
			`  a sink that raises on the second of three: dispatch let the raise reach the `
				.. `caller:\n    {tostring(err)}`
		)
	end

	-- An error value that is not a string. A dispatch that isolates emit with
	-- pcall never sees the difference; one that re-raises after inspecting a
	-- string does.
	local tableError = {
		emit = function()
			error({ code = 503 })
		end,
	}
	ok, err = pcall(Sink.dispatch, tableError, { three[1] })
	if not ok then
		table.insert(
			violations,
			`  a sink that raises a table: dispatch let the raise reach the caller:\n    `
				.. Deep.show(err)
		)
	end

	check(
		#violations == 0,
		`AC-5 (no propagation): a raising emit reached the caller of Sink.dispatch in `
			.. `{#violations} case(s):\n{table.concat(violations, "\n")}`
	)
end

--[[
	AC-5, second half. The failure is recorded as a COUNTED DROP: `dropped`
	counts exactly the emits that raised, `delivered` counts exactly the ones
	that did not, the two sum to the batch, and every emit is ISOLATED - a
	raise on one event does not cost the events after it.

	If dispatch raised instead of returning, nothing was counted, and that is
	a failure of this half too: a drop that was never recorded is the silent
	drop the criterion is about.
]]
function TelemetryContract.raisingEmitIsACountedDrop(Sink: SinkModule)
	local violations: { string } = {}
	local three = TelemetryContract.threeEvents()

	type DropCase = {
		label: string,
		raiseOn: (any) -> boolean,
		delivered: number,
		dropped: number,
		survivors: { any },
	}
	local cases: { DropCase } = {
		{
			label = "raises on every event",
			raiseOn = function()
				return true
			end,
			delivered = 0,
			dropped = 3,
			survivors = {},
		},
		{
			label = "raises on the second of three",
			raiseOn = function(event)
				return event.name == "round_complete"
			end,
			delivered = 2,
			dropped = 1,
			survivors = { three[1], three[3] },
		},
		{
			label = "raises on the first of three",
			raiseOn = function(event)
				return event.name == "join"
			end,
			delivered = 2,
			dropped = 1,
			survivors = { three[2], three[3] },
		},
		{
			label = "raises on the only event",
			raiseOn = function()
				return true
			end,
			delivered = 0,
			dropped = 1,
			survivors = {},
		},
	}

	for _, case in cases do
		local batch = if case.label == "raises on the only event" then { three[1] } else three
		local sink, seen = raisingSink(case.raiseOn)
		local ok, result = pcall(Sink.dispatch, sink, batch)
		if not ok then
			table.insert(
				violations,
				`  a sink that {case.label}: dispatch raised instead of returning a result, so `
					.. `nothing was counted:\n    {tostring(result)}`
			)
			continue
		end
		local problems: { string } = {}
		if typeof(result) ~= "table" then
			table.insert(problems, `dispatch returned {typeof(result)}`)
		else
			if result.dropped ~= case.dropped then
				table.insert(
					problems,
					`dropped = {Deep.show(result.dropped)}, expected {case.dropped}`
				)
			end
			if result.delivered ~= case.delivered then
				table.insert(
					problems,
					`delivered = {Deep.show(result.delivered)}, expected {case.delivered}`
				)
			end
		end
		local diff = Deep.diff(case.survivors, seen)
		if diff ~= "" then
			table.insert(
				problems,
				`the events that did not raise were not all delivered, in order:\n      {indent(
					indent(diff)
				)}`
			)
		end
		if #problems > 0 then
			table.insert(violations, `  a sink that {case.label}: {table.concat(problems, "; ")}`)
		end
	end

	check(
		#violations == 0,
		`AC-5 (counted drop): a raising emit is not recorded as exactly one drop with the rest `
			.. `delivered, in {#violations} of {#cases} cases:\n{table.concat(violations, "\n")}`
	)
end

return TelemetryContract
