--!strict
--[[
	The negative controls for TEL-001, and the proof that each check in
	`tests/helpers/TelemetryContract.luau` refuses the module it exists to
	catch.

	THREE CRITERIA NAME THEIR CONTROL. AC-3: an implementation that defaults an
	unknown name to D1 "must fail this". AC-5: one that lets the error
	propagate "must fail this", and one that swallows it with no count "must
	fail the counted half". AC-5's two controls are what make it two checks:
	the swallow-and-miscount sink passes the no-propagation half and fails the
	counted-drop half, which is the single-assertion case the story's `## Notes`
	asks the orchestrator to run first.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half
	is the one that is easy to leave out and worth the most: a stub that fails
	EVERY check proves only that the checks reject something, and a control
	that fails everything is indistinguishable from a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the number
	measured here rather than predicted. `purchase` removed from BUCKETS
	(mutation 3 of `## Notes`) fails AC-2 as predicted AND AC-1 AND AC-3,
	because both of those construct a `purchase` event; the propagating
	dispatch fails BOTH halves of AC-5, because a dispatch that raised
	returned no result and so counted nothing. Those are properties of the
	defects, not of the checks, and they are in the story's mutation table.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/shared/telemetry/` does not exist and every test in
	`telemetry_event_test.luau` and `telemetry_sink_test.luau` fails before
	reaching its check. These controls need only `Clock.manual` from ROUND-001,
	which is merged, so the numbers below are measurements taken in RED rather
	than claims left for GREEN.
]]

local Contract = require("../helpers/TelemetryContract")
local Stubs = require("../helpers/TelemetryStubs")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local function accepts(check: Check, subject: any, what: string)
	local ok, err = pcall(check, subject)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: Check, subject: any, what: string): string
	local ok, err = pcall(check, subject)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

local function lacks(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) == nil,
		`{what}, but the failure message mentions "{fragment}":\n{message}`
	)
end

local EVENT_CHECKS: { Named } = {
	{ label = "AC-1", check = Contract.eventCarriesTheSuppliedValuesAndTheClocksTime },
	{ label = "AC-2", check = Contract.bucketsNameExactlyTheNineB6Events },
	{ label = "AC-3", check = Contract.unknownNameIsRefused },
	{ label = "AC-6", check = Contract.nonScalarFieldIsRefusedNamingTheKey },
}

local SINK_CHECKS: { Named } = {
	{ label = "AC-4", check = Contract.recordingSinkHoldsExactlyWhatWasEmittedInOrder },
	{ label = "dispatch", check = Contract.dispatchDeliversEveryEventToAWorkingSink },
	{ label = "AC-5 (no propagation)", check = Contract.raisingEmitDoesNotPropagate },
	{ label = "AC-5 (counted drop)", check = Contract.raisingEmitIsACountedDrop },
}

-- Every check, so a control is held to all of them except the ones it is
-- built to fail.
local function passesTheChecks(
	checks: { Named },
	subject: any,
	who: string,
	except: { [string]: boolean }
)
	for _, entry in checks do
		if not except[entry.label] then
			accepts(entry.check, subject, `{entry.label} on {who}`)
		end
	end
end

return {
	--[[ The baselines. Every control below is one of these with exactly one
	     defect set, so a control that fires is attributable to that one thing.
	     This is also the proof that the checks are satisfiable at all. ]]

	["baseline: a correct Event module passes AC-1, AC-2, AC-3 and AC-6"] = function()
		passesTheChecks(EVENT_CHECKS, Stubs.correctEvent, "the baseline Event", {})
	end,

	["baseline: a correct Sink module passes AC-4, dispatch and both halves of AC-5"] = function()
		passesTheChecks(SINK_CHECKS, Stubs.correctSink, "the baseline Sink", {})
	end,

	--[[
		AC-3's control, named in the criterion, and mutation 1 of `## Notes`:
		an unknown name gets "D1" instead of a refusal. It fails AC-3 ALONE -
		AC-1, AC-2 and AC-6 never construct an unknown name - and the failure
		shows the guessed bucket for every stranger.
	]]
	["AC-3 control (mutation 1): defaulting an unknown name to D1 fails AC-3 alone, on all 6 strangers, naming the guessed bucket"] = function()
		local Event = Stubs.defaultUnknownToD1
		passesTheChecks(EVENT_CHECKS, Event, "the default-to-D1 Event", { ["AC-3"] = true })

		local message = refuses(
			Contract.unknownNameIsRefused,
			Event,
			"an Event that defaults an unknown name to D1 must fail AC-3"
		)
		names(message, "AC-3", "the AC-3 control fires")
		names(message, "in 6 case(s)", "the AC-3 failure counts every stranger")
		names(
			message,
			'Event.new("joins", ...) returned an event with bucket "D1" instead of raising',
			"the AC-3 failure names the typo and the guessed bucket"
		)
		names(
			message,
			'Event.new("Join", ...) returned an event with bucket "D1"',
			"the AC-3 failure catches the wrong case"
		)
		names(
			message,
			'Event.new("", ...) returned an event with bucket "D1"',
			"the AC-3 failure catches the empty string"
		)
	end,

	--[[
		AC-2's controls. Mutation 3 of `## Notes` is `purchase` removed;
		measured here, it fails AC-1 and AC-3 as well as AC-2, because both of
		those construct every B6 name and `purchase` is one. The other
		direction - a tenth, invented event - fails AC-2 on the count and AC-3
		on construction, because `level_up` is one of AC-3's strangers. A wrong
		bucket for the one event the story says to get right fails AC-2 and
		AC-1. An unfrozen table fails AC-2 alone, both ways it can be written.
	]]
	["AC-2 control (mutation 3): purchase missing from BUCKETS fails AC-2 naming the gap, and AC-1 and AC-3 by constructing it"] = function()
		local Event = Stubs.missingPurchase
		passesTheChecks(EVENT_CHECKS, Event, "the missing-purchase Event", {
			["AC-1"] = true,
			["AC-2"] = true,
			["AC-3"] = true,
		})

		local message = refuses(
			Contract.bucketsNameExactlyTheNineB6Events,
			Event,
			"a BUCKETS without purchase must fail AC-2"
		)
		names(message, "AC-2", "the AC-2 control fires")
		names(message, "1 of 9 wrong or missing", "the AC-2 failure counts the one gap")
		names(
			message,
			"purchase: expected D8_28, got nil (missing)",
			"the AC-2 failure names the missing event and its settled bucket"
		)
		names(message, "8 entries in all, 9 expected", "the AC-2 failure counts the entries")

		names(
			refuses(
				Contract.eventCarriesTheSuppliedValuesAndTheClocksTime,
				Event,
				"AC-1 constructs a purchase event"
			),
			"for an M5 event with no emitter yet (purchase): construction raised",
			"AC-1 fires on the M5 event that has no emitter and must still construct"
		)
		names(
			refuses(
				Contract.unknownNameIsRefused,
				Event,
				"AC-3's positive half constructs all nine"
			),
			'Event.new("purchase", ...) raised for a B6 event',
			"AC-3 fires on a B6 name that was refused"
		)
	end,

	["AC-2 control: a tenth invented event in BUCKETS fails AC-2 on the count and AC-3 by constructing it"] = function()
		local Event = Stubs.extraTenthEvent
		passesTheChecks(EVENT_CHECKS, Event, "the tenth-event Event", {
			["AC-2"] = true,
			["AC-3"] = true,
		})

		local message = refuses(
			Contract.bucketsNameExactlyTheNineB6Events,
			Event,
			"a BUCKETS with a tenth entry must fail AC-2"
		)
		names(message, "0 of 9 wrong or missing", "all nine are still right")
		names(
			message,
			"1 extra or malformed entries (10 entries in all, 9 expected)",
			"the count fires"
		)
		names(message, 'level_up = "D1" is not a B6 event', "the extra entry is named")
		names(
			message,
			"0 way(s) it is not frozen",
			"the tenth entry is not misread as an unfrozen write"
		)

		names(
			refuses(Contract.unknownNameIsRefused, Event, "AC-3 sees the invented name construct"),
			'Event.new("level_up", ...) returned an event with bucket "D1"',
			"AC-3 names the invented event"
		)
	end,

	["AC-2 control: bounce_before_resolution filed under D2_7 fails AC-2 and AC-1, naming the event"] = function()
		local Event = Stubs.bounceInD2_7
		passesTheChecks(EVENT_CHECKS, Event, "the bounce-in-D2_7 Event", {
			["AC-1"] = true,
			["AC-2"] = true,
		})

		local message = refuses(
			Contract.bucketsNameExactlyTheNineB6Events,
			Event,
			"the wrong bucket for the most valuable event must fail AC-2"
		)
		names(message, "1 of 9 wrong or missing", "one bucket is wrong")
		names(
			message,
			'bounce_before_resolution: expected D1, got "D2_7"',
			"the AC-2 failure names the event and both buckets"
		)
		names(message, "9 entries in all, 9 expected", "the count is still right")

		names(
			refuses(
				Contract.eventCarriesTheSuppliedValuesAndTheClocksTime,
				Event,
				"AC-1 sees the bucket on a constructed event"
			),
			'value.bucket: expected "D1", got "D2_7"',
			"AC-1 names the wrong bucket on the event"
		)
	end,

	["AC-2 control: a writable BUCKETS fails AC-2 alone, on an existing key and on a new key"] = function()
		local Event = Stubs.unfrozenBuckets
		passesTheChecks(EVENT_CHECKS, Event, "the unfrozen-BUCKETS Event", { ["AC-2"] = true })

		local message = refuses(
			Contract.bucketsNameExactlyTheNineB6Events,
			Event,
			"a BUCKETS that accepts writes must fail AC-2"
		)
		names(message, "0 of 9 wrong or missing", "the nine are right")
		names(message, "0 extra or malformed entries", "nothing extra")
		names(message, "2 way(s) it is not frozen", "both writes went through")
		names(
			message,
			'assigning BUCKETS.join = "D8_28" did not raise and the value is now "D8_28"',
			"the existing-key write is named"
		)
		names(
			message,
			'assigning a new key BUCKETS.not_a_b6_event did not raise and the key is now "D1"',
			"the new-key write is named"
		)
	end,

	--[[
		AC-6's controls. A module that carries a nested table fails on exactly
		the three table cases and no other; one that refuses but names no key
		fails on all five non-scalar cases, because "naming the offending key"
		is half the criterion.
	]]
	["AC-6 control: accepting a nested table in fields fails AC-6 alone, on the 3 table cases, showing what was carried"] = function()
		local Event = Stubs.acceptNestedTable
		passesTheChecks(EVENT_CHECKS, Event, "the accept-nested-table Event", { ["AC-6"] = true })

		local message = refuses(
			Contract.nonScalarFieldIsRefusedNamingTheKey,
			Event,
			"an Event that accepts a nested table must fail AC-6"
		)
		names(message, "AC-6", "the AC-6 control fires")
		names(message, "in 3 of 15 cases", "exactly the three table cases fire")
		names(
			message,
			'a nested table under key "payload" was ACCEPTED; the event carries fields = { payload = { x = 1 } }',
			"the AC-6 failure names the key and shows the payload nobody downstream can index"
		)
		names(
			message,
			'a table among three scalars under key "nested" was ACCEPTED',
			"the AC-6 failure picks the table out from among scalars"
		)
		lacks(message, "a function under key", "the function case still refuses")
		lacks(message, "a thread under key", "the thread case still refuses")
	end,

	["AC-6 control: refusing a non-scalar without naming its key fails AC-6 alone, on all 5 non-scalar cases"] = function()
		local Event = Stubs.refuseWithoutKey
		passesTheChecks(EVENT_CHECKS, Event, "the refuse-without-key Event", { ["AC-6"] = true })

		local message = refuses(
			Contract.nonScalarFieldIsRefusedNamingTheKey,
			Event,
			"a refusal that names no key must fail AC-6"
		)
		names(message, "in 5 of 15 cases", "all five non-scalar cases fire and no scalar case does")
		names(
			message,
			'a function under key "callback" was refused, but the error does not name the key',
			"the AC-6 failure says the key was not named"
		)
		names(
			message,
			'a thread under key "job" was refused, but the error does not name the key',
			"the thread case fires too"
		)
	end,

	--[[
		AC-1's control: `at` is a constant rather than the clock's `t`. Fails
		AC-1 alone, on every case whose t is not the constant - four of five.
	]]
	["AC-1 control: an event whose at is always 0 fails AC-1 alone, on the 4 cases where t is not 0, naming at"] = function()
		local Event = Stubs.atIsZero
		passesTheChecks(EVENT_CHECKS, Event, "the at-is-zero Event", { ["AC-1"] = true })

		local message = refuses(
			Contract.eventCarriesTheSuppliedValuesAndTheClocksTime,
			Event,
			"an Event that ignores the clock's t must fail AC-1"
		)
		names(message, "AC-1", "the AC-1 control fires")
		names(
			message,
			"in 4 of 5 cases",
			"the t = 0 case is indistinguishable and the other four fire"
		)
		names(message, "value.at: expected 1234.5, got 0", "the fractional t is named")
		names(message, "value.at: expected 2147483648, got 0", "the large t is named")
	end,

	--[[
		AC-5's controls, one per half, exactly as the criterion names them.

		The propagating dispatch fails the no-propagation half in all three
		cases - and the counted-drop half too, because a dispatch that raised
		returned nothing and counted nothing. MEASURED: 3 of 3 and 4 of 4.

		The swallow-and-miscount dispatch (mutation 2 of `## Notes`) passes the
		no-propagation half and fails the counted-drop half ALONE, in 4 of 4
		cases, with dropped = 0 every time. This is the single-assertion case
		the orchestrator runs first.
	]]
	["AC-5 control: a dispatch that lets emit's raise propagate fails the no-propagation half in 3 of 3 cases, and the counted-drop half because nothing was counted"] = function()
		local Sink = Stubs.propagateEmitError
		passesTheChecks(SINK_CHECKS, Sink, "the propagating Sink", {
			["AC-5 (no propagation)"] = true,
			["AC-5 (counted drop)"] = true,
		})

		local message = refuses(
			Contract.raisingEmitDoesNotPropagate,
			Sink,
			"a dispatch that propagates must fail AC-5's no-propagation half"
		)
		names(message, "AC-5 (no propagation)", "the no-propagation control fires")
		names(message, "in 3 case(s)", "all three raising sinks reach the caller")
		names(
			message,
			"a sink that raises on every event: dispatch let the raise reach the caller",
			"the always-raising case is named"
		)
		names(message, "sink exploded on join", "the sink's own error is quoted")
		names(
			message,
			"a sink that raises a table: dispatch let the raise reach the caller:\n    { code = 503 }",
			"a non-string error value propagates too"
		)

		local counted = refuses(
			Contract.raisingEmitIsACountedDrop,
			Sink,
			"a dispatch that raised returned no count"
		)
		names(counted, "AC-5 (counted drop)", "the counted-drop check fires too")
		names(counted, "in 4 of 4 cases", "every case is uncounted")
		names(
			counted,
			"dispatch raised instead of returning a result, so nothing was counted",
			"the counted-drop failure says why: no result, no count"
		)
	end,

	["AC-5 control (mutation 2): a dispatch that counts a raising emit as delivered passes the no-propagation half and fails the counted-drop half alone, 4 of 4 with dropped = 0"] = function()
		local Sink = Stubs.countRaiseAsDelivered
		passesTheChecks(SINK_CHECKS, Sink, "the count-as-delivered Sink", {
			["AC-5 (counted drop)"] = true,
		})
		accepts(
			Contract.raisingEmitDoesNotPropagate,
			Sink,
			"the swallowing dispatch must PASS the no-propagation half, or the control proves "
				.. "nothing about the counted half"
		)

		local message = refuses(
			Contract.raisingEmitIsACountedDrop,
			Sink,
			"a dispatch that swallows a raise with no count must fail AC-5's counted-drop half"
		)
		names(message, "AC-5 (counted drop)", "the counted-drop control fires")
		names(message, "in 4 of 4 cases", "every raising case is miscounted")
		names(
			message,
			"a sink that raises on every event: dropped = 0, expected 3; delivered = 3, expected 0",
			"the always-raising case shows the silent drop as delivery"
		)
		names(
			message,
			"a sink that raises on the second of three: dropped = 0, expected 1; delivered = 3, expected 2",
			"the one-of-three case shows the single miscounted event"
		)
		lacks(message, "dispatch raised instead of returning", "no case reached the caller")
	end,

	["AC-5 control: a dispatch that stops at the first raise fails the counted-drop half alone, in 3 of 4 cases, naming the events never attempted"] = function()
		local Sink = Stubs.stopAtFirstError
		passesTheChecks(SINK_CHECKS, Sink, "the stop-at-first-error Sink", {
			["AC-5 (counted drop)"] = true,
		})

		local message = refuses(
			Contract.raisingEmitIsACountedDrop,
			Sink,
			"a dispatch that does not isolate each emit must fail AC-5's counted-drop half"
		)
		names(
			message,
			"in 3 of 4 cases",
			"the only-event case is indistinguishable and the rest fire"
		)
		names(
			message,
			"a sink that raises on every event: dropped = 1, expected 3",
			"stopping early under-counts the drops"
		)
		names(
			message,
			"a sink that raises on the first of three: delivered = 0, expected 2; the events that did "
				.. "not raise were not all delivered, in order",
			"the events after the raise were never attempted"
		)
		names(
			message,
			'value.1: expected { at = 42.5, bucket = "D2_7"',
			"the first un-attempted event is named"
		)
	end,

	--[[
		AC-4's controls. Both fail the recording check AND the dispatch
		positive half, because dispatch's positive half reads the recording
		sink's contents back; measured, not predicted.
	]]
	["AC-4 control: a recording sink that prepends fails AC-4 and dispatch, naming the positions that swapped"] = function()
		local Sink = Stubs.recordingOutOfOrder
		passesTheChecks(SINK_CHECKS, Sink, "the out-of-order Sink", {
			["AC-4"] = true,
			["dispatch"] = true,
		})

		local message = refuses(
			Contract.recordingSinkHoldsExactlyWhatWasEmittedInOrder,
			Sink,
			"a recording sink that reverses the order must fail AC-4"
		)
		names(message, "AC-4", "the AC-4 control fires")
		names(
			message,
			'value.1.name: expected "join", got "session_end"',
			"the first slot is wrong"
		)
		names(
			message,
			'value.3.name: expected "session_end", got "join"',
			"the third slot is wrong"
		)
		lacks(message, "value.2.name", "the middle event is in place and not reported")

		names(
			refuses(
				Contract.dispatchDeliversEveryEventToAWorkingSink,
				Sink,
				"dispatch reads it back"
			),
			"after dispatching three events the recording sink holds something else",
			"dispatch's positive half sees the order"
		)
	end,

	["AC-4 control: a recording sink that stores the envelope without fields fails AC-4 and dispatch, naming every missing fields table"] = function()
		local Sink = Stubs.recordingDropsFields
		passesTheChecks(SINK_CHECKS, Sink, "the drops-fields Sink", {
			["AC-4"] = true,
			["dispatch"] = true,
		})

		local message = refuses(
			Contract.recordingSinkHoldsExactlyWhatWasEmittedInOrder,
			Sink,
			"a recording sink that loses fields must fail AC-4"
		)
		names(
			message,
			"value.1.fields: expected { seat = 1 }, got nil",
			"the first event's fields are gone"
		)
		names(
			message,
			'value.2.fields: expected { contested = true, winner = "amy" }, got nil',
			"the second event's fields are gone"
		)
		names(
			message,
			'value.3.fields: expected { reason = "left", seconds = 99 }, got nil',
			"the third event's fields are gone"
		)
		lacks(
			message,
			"value.1.name",
			"the envelope itself survived, so a length check would have passed"
		)
	end,
}
