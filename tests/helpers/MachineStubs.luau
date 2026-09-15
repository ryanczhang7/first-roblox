--!strict
--[[
	The wrong machines ROUND-003's two required controls are aimed at.

	AC-6 and AC-7 each name one: an implementation that mutates and returns the
	input state, and one that raises on an unknown event. Both are required to
	FAIL the matching check in `PhaseMachineContract.luau`, and a control that is
	described and never run proves nothing - which in RED is the normal state of
	affairs, because the module under test does not exist, the real test file
	fails at `require`, and not one assertion in it has executed.

	These stubs need no production code, so the AC-6 and AC-7 checks ARE executed
	in RED against implementations whose defects are known.

	`MachineStubs.inert` is the baseline and it is what makes the controls mean
	something: each wrong machine below is the inert one with ONE thing broken, so
	a control that fires is attributable to that one thing rather than to a stub
	that is broken in six ways.

	NONE OF THESE IS A PHASE MACHINE. Not one implements a transition, a
	duration or an effect; `inert` returns its input and no effects for every
	event, which is a legal answer only for the unrecognised-event case. They
	exist to exercise the CHECKS. The implementation is GREEN's to write from the
	story's Contract, and nothing here is a sketch of it.
]]

local MachineStubs = {}

--[[
	The baseline: total, pure, non-mutating. It ignores every event, which makes
	it correct for AC-7's cases and correct-by-vacuity for AC-6's.
]]
MachineStubs.inert = {
	step = function(state: any, _event: any, _now: number): (any, { any })
		return state, {}
	end,
}

--[[
	AC-6's control, named in the criterion: mutates the state it was given and
	returns it.

	It still passes the DETERMINISM half - two identical calls return the same
	thing - which is the trap. Determinism is the half everybody writes, and it
	does not catch this.
]]
MachineStubs.mutating = {
	step = function(state: any, _event: any, _now: number): (any, { any })
		state.phase = "Assignment"
		state.phaseEnteredAt = 99
		return state, {}
	end,
}

--[[
	The reason AC-6's non-mutation check may not be an identity check.

	This machine mutates the caller's table AND returns a fresh copy, so
	`returned ~= given` is true, `returned.phase` is whatever the caller expects,
	and every reference-comparison test in the world goes green while the
	caller's state has been corrupted underneath it.
]]
MachineStubs.mutatingCopier = {
	step = function(state: any, _event: any, _now: number): (any, { any })
		state.players = { "mutated" }
		local copy = table.clone(state)
		copy.players = { "mutated" }
		return copy, {}
	end,
}

--[[
	AC-7's control, named in the criterion: raises on an event it does not
	recognise.

	It handles `Tick` so that it is a plausible machine rather than a function
	that only throws - a control has to be the correct implementation with one
	defect, or "the control failed" says nothing about which defect did it.
]]
MachineStubs.raising = {
	step = function(state: any, event: any, _now: number): (any, { any })
		if event.kind == "Tick" then
			return state, {}
		end
		error(`PhaseMachine: unhandled event {tostring(event.kind)}`)
	end,
}

--[[
	The second way to fail AC-7, which "no error was raised" does not catch: the
	event is ignored, the state comes back untouched, and the machine emits an
	effect for it anyway.
]]
MachineStubs.chatty = {
	step = function(state: any, _event: any, _now: number): (any, { any })
		return state, { { kind = "PromptRematch" } }
	end,
}

return MachineStubs
