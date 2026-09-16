--!strict
--[[
	ROUND-003 AC-6 and AC-7 written once, as checks over a MACHINE rather than
	over a module - the same arrangement as `ClockContract.luau` and
	`RngContract.luau`, and for the same reason.

	`tests/server/phase_machine_test.luau` applies these to the real
	`src/server/round/PhaseMachine.luau`.
	`tests/server/phase_machine_controls_test.luau` applies them to the wrong
	machines in `MachineStubs.luau`, so that in RED - where the production module
	does not exist and the real file's assertions cannot run at all - these
	checks have still been EXECUTED and observed to reject a machine that mutates
	its input and one that raises on an unknown event.

	A `machine` here is anything with a `step(state, event, now)` field function.
	The Contract writes `PhaseMachine.step(state, event, now)`, a dot call on a
	plain field, and these helpers call it that way on purpose: a story that
	injects this machine somewhere else will write the call one way and only one.

	Every message names its criterion, because the controls assert on the text.
]]

local Deep = require("./Deep")

local PhaseMachineContract = {}

export type Case = {
	label: string,
	state: any,
	event: any,
	now: number,
}

--[[
	A RoundState-shaped table owing nothing to any implementation.

	The controls need a state to feed a stub and must not wait for a real
	machine to produce one; the real suite builds its states by driving the
	machine, which is the only honest way to reach a phase.
]]
function PhaseMachineContract.sampleState(): any
	return {
		phase = "Lobby",
		phaseEnteredAt = 0,
		roundId = "round-sample",
		seed = 4242,
		players = { "p1", "p2", "p3", "p4" },
		outcome = nil,
	}
end

--[[
	AC-6, the half that will be violated first and noticed last.

	NOT an identity check. `returned ~= given` passes for a machine that mutates
	the caller's table and hands back a fresh copy of it - see
	`MachineStubs.mutatingCopier`, which is exactly that machine and exactly why
	this takes a deep snapshot first and deep-compares against it after.
]]
function PhaseMachineContract.stepDoesNotMutateItsInput(machine: any, case: Case)
	local snapshot = Deep.copy(case.state)

	machine.step(case.state, case.event, case.now)

	local difference = Deep.diff(snapshot, case.state)
	assert(
		difference == "",
		`AC-6: step mutated the state it was given ({case.label}).\n`
			.. `The input state before the call and after it differ:\n{difference}`
	)
end

-- AC-6: same `(state, event, now)`, same state out and same effects out.
function PhaseMachineContract.stepIsDeterministic(machine: any, case: Case)
	local firstState, firstEffects = machine.step(case.state, case.event, case.now)
	local secondState, secondEffects = machine.step(case.state, case.event, case.now)

	local stateDifference = Deep.diff(firstState, secondState)
	assert(
		stateDifference == "",
		`AC-6: two identical steps returned different states ({case.label}):\n{stateDifference}`
	)

	local effectDifference = Deep.diff(firstEffects, secondEffects)
	assert(
		effectDifference == "",
		`AC-6: two identical steps returned different effects ({case.label}):\n{effectDifference}`
	)
end

--[[
	AC-7: an event the phase does not recognise returns the state unchanged with
	an empty effect list and raises nothing.

	All three halves are asserted. A machine that swallows the event but emits an
	effect anyway, and one that returns a subtly different state, both satisfy
	"no error was raised" - and "no error was raised" is the only half most
	totality tests check.
]]
function PhaseMachineContract.eventIsIgnored(machine: any, case: Case)
	local snapshot = Deep.copy(case.state)

	local ok, result, effects = pcall(machine.step, case.state, case.event, case.now)
	assert(ok, `AC-7: step raised on {case.label} instead of ignoring it: {tostring(result)}`)

	local difference = Deep.diff(snapshot, result)
	assert(
		difference == "",
		`AC-7: {case.label} was not ignored - the returned state differs from the one given:\n`
			.. difference
	)

	assert(
		typeof(effects) == "table",
		`AC-7: step returned {typeof(effects)} for its effect list on {case.label}`
	)
	local list = effects :: { any }
	assert(
		#list == 0,
		`AC-7: {case.label} produced {#list} effect(s) and must produce none: `
			.. Deep.show(Deep.kinds(list))
	)
end

return PhaseMachineContract
