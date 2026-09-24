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

--[[
	`eventIsIgnored` for a `PlayerLeft` that TEL-002 turns into telemetry.

	ROUND-004 Contract pin 2 and ROUND-005 Contract pin 5 say a departure in
	`Assignment`, `Resolution` or `Post` is ignored: nobody is unseated, no
	control effect is produced, `phaseEnteredAt` and `outcome` are untouched.
	TEL-002 keeps every word of that (its Contract, P3) and adds two things the
	old check cannot see past: the step emits a `bounce_before_resolution` or a
	`session_end`, and it records the departure in the `departed` guard map so
	that a duplicate `PlayerLeft` emits nothing (P2). So this check compares the
	state with `departed` EXCLUDED on both sides and the effects with `Emit`
	EXCLUDED, and asserts every other half of `eventIsIgnored` unchanged. What
	`departed` and the `Emit` must be is TEL-002's suite's to pin
	(`TelemetryEmitContract.luau`), not this check's to wave through.

	Only `departed` is excluded, deliberately. A `PlayerLeft` has no business
	touching `rematched` or `roundsSeated`, and a machine that did would still
	fail here.
]]
function PhaseMachineContract.eventIsIgnoredExceptTelemetry(machine: any, case: Case)
	local snapshot = Deep.copy(case.state)

	local ok, result, effects = pcall(machine.step, case.state, case.event, case.now)
	assert(ok, `AC-7: step raised on {case.label} instead of ignoring it: {tostring(result)}`)

	local expected = Deep.copy(snapshot)
	local actual = Deep.copy(result)
	if typeof(expected) == "table" then
		expected.departed = nil
	end
	if typeof(actual) == "table" then
		actual.departed = nil
	end
	local difference = Deep.diff(expected, actual)
	assert(
		difference == "",
		`AC-7: {case.label} was not ignored - the returned state differs from the one given `
			.. `(telemetry's departed guard excluded from the comparison):\n{difference}`
	)

	assert(
		typeof(effects) == "table",
		`AC-7: step returned {typeof(effects)} for its effect list on {case.label}`
	)
	local control = Deep.controlEffects(effects :: { any })
	assert(
		#control == 0,
		`AC-7: {case.label} produced {#control} control effect(s) and must produce none `
			.. `(telemetry Emit effects excluded; TEL-002 pins those): `
			.. Deep.show(Deep.kinds(control))
	)
end

return PhaseMachineContract
