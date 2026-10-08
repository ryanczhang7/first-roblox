--!strict
--[[
	TEL-001: where telemetry events go, and the one function a driver calls.

	EMISSION IS AN EFFECT, NOT A CALL (`architecture.md` §6, D3). Pure code
	returns `{ kind = "Emit", event }` and a driver hands the batch to a sink.
	Three things follow, and they are the reason this module is a parameter
	rather than a global: telemetry is verified with no sink at all, a sink
	failure cannot break a round, and the events become part of the phase
	machine's tested output rather than a side channel nobody asserts on.

	`Sink.dispatch` IS THE ONLY FUNCTION A DRIVER CALLS, and it is where AC-5
	lives. Each `emit` is isolated with `pcall`, a raise is counted as a
	dropped event, and nothing reaches the caller. Both halves are load-bearing
	and an implementation can get one right and the other wrong:

	  * telemetry that can crash a round is worse than no telemetry - a sink
	    talking to an analytics service will fail eventually, and a round that
	    ends because a metric could not be posted is a defect caused entirely
	    by the instrument;
	  * telemetry that silently drops is worse than either - the numbers keep
	    arriving, smaller than the truth, and nothing distinguishes "the event
	    did not happen" from "the event could not be sent".

	SO THE ISOLATION BELONGS HERE AND NOT IN A SINK. `recording` deliberately
	has no `pcall` of its own: a driver hands events to whatever sink it was
	given - an M5 analytics adapter nobody in this repository wrote - and the
	guarantee has to hold for those too. A sink that protected itself would
	only protect the sinks that remembered to.

	WHAT IS NOT HERE: batching, sampling, back-pressure, retry, and any real
	destination. All of those belong with a real sink, which is an M5 decision
	with request-budget consequences. `noop` and `recording` are sufficient
	here precisely because emission is an effect.
]]

local Event = require("./Event")

local Sink = {}

export type TelemetryEvent = Event.TelemetryEvent

--[[
	`emit` is a PLAIN FIELD FUNCTION - `sink.emit(event)`, no `self` - which is
	what lets a table literal written at a call site be a sink without
	inheriting anything.
]]
export type Sink = {
	emit: (TelemetryEvent) -> (),
}

export type RecordingSink = Sink & {
	events: { TelemetryEvent },
	clear: (self: RecordingSink) -> (),
}

export type DispatchResult = {
	delivered: number, -- emits that returned
	dropped: number, -- emits that raised; delivered + dropped == #events
}

-- A sink that accepts everything and keeps nothing. The default for a server
-- that has no analytics destination configured, and the thing a test injects
-- when it cares that a round works rather than what it reported.
function Sink.noop(): Sink
	return {
		emit = function(_event: TelemetryEvent) end,
	}
end

--[[
	A sink that holds what it was given, in order, for a test to read back.

	One list per sink, closed over rather than read off `self`, so that `clear`
	and `emit` can never end up pointing at different tables - which is what
	happens the moment someone assigns `sink.events = {}` while `emit` is still
	appending to the original.
]]
function Sink.recording(): RecordingSink
	local events: { TelemetryEvent } = {}

	local recording: RecordingSink = {
		events = events,

		emit = function(event: TelemetryEvent)
			table.insert(events, event)
		end,

		clear = function(_self: RecordingSink)
			table.clear(events)
		end,
	}

	return recording
end

--[[
	Hand every event to the sink, isolating each one, and report what happened.

	The loop does not stop at the first failure: a sink that raises on one
	event says nothing about the next, and a batch truncated at the first
	problem loses events for a reason unrelated to them. The error value is
	discarded rather than re-raised or logged - there is nowhere to log it that
	is not itself a sink - but it is never discarded SILENTLY: it is the
	difference between `delivered` and `#events`.
]]
function Sink.dispatch(sink: Sink, events: { TelemetryEvent }): DispatchResult
	local delivered = 0
	local dropped = 0

	for _, event in events do
		if pcall(sink.emit, event) then
			delivered += 1
		else
			dropped += 1
		end
	end

	return { delivered = delivered, dropped = dropped }
end

return Sink
