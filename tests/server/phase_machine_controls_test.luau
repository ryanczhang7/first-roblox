--!strict
--[[
	The negative controls for ROUND-003 AC-6 and AC-7, and the checks on the
	instrument both of them are built out of.

	The story's oracle partition makes AC-6 and AC-7 "mechanical, with a control
	each", and both controls are named in the criteria themselves: an
	implementation that mutates and returns the input state must fail AC-6, and
	one that raises on an unknown event must fail AC-7.

	NOTHING HERE REQUIRES PRODUCTION CODE, deliberately. In RED
	`src/server/round/PhaseMachine.luau` does not exist,
	`tests/server/phase_machine_test.luau` cannot load its subject, and not one
	assertion in that file runs - which is the condition
	`.claude/harness/rules.md` warns leaves every threshold in a suite unverified
	for a whole phase. The checks in `PhaseMachineContract.luau` are the same
	objects the real suite uses, so running them here against known-wrong
	machines is a real measurement of whether they discriminate, taken now rather
	than promised for later.

	Each control asserts BOTH directions: the wrong machine passes the check the
	story says it passes, and fails the one the story says catches it. Only the
	second half is the control; the first half is what proves the stub is
	plausible rather than merely broken.
]]

local Contract = require("../helpers/PhaseMachineContract")
local Deep = require("../helpers/Deep")
local MachineStubs = require("../helpers/MachineStubs")

local function caseFor(label: string, event: any, now: number): Contract.Case
	return { label = label, state = Contract.sampleState(), event = event, now = now }
end

local function accepts(
	check: (any, Contract.Case) -> (),
	machine: any,
	case: Contract.Case,
	what: string
)
	local ok, err = pcall(check, machine, case)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(
	check: (any, Contract.Case) -> (),
	machine: any,
	case: Contract.Case,
	what: string
): string
	local ok, err = pcall(check, machine, case)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

--[[
	The identity check AC-6 must NOT be. Written out here rather than described,
	because the whole point of `MachineStubs.mutatingCopier` is that this passes
	for it while the real check fails.
]]
local function weakIdentityCheck(machine: any, case: Contract.Case)
	local returned = machine.step(case.state, case.event, case.now)
	assert(returned ~= case.state, "step returned the very table it was given")
end

return {
	--[[ The baseline. Every control below is this machine with exactly one thing
	     broken, so a control that fires is attributable to that one thing. ]]

	["baseline: an inert machine passes the AC-6 and AC-7 checks"] = function()
		local tick = caseFor("a Tick in Lobby", { kind = "Tick" }, 1)
		accepts(Contract.stepDoesNotMutateItsInput, MachineStubs.inert, tick, "AC-6 non-mutation")
		accepts(Contract.stepIsDeterministic, MachineStubs.inert, tick, "AC-6 determinism")
		accepts(
			Contract.eventIsIgnored,
			MachineStubs.inert,
			caseFor("a SeatsAssigned in Lobby", { kind = "SeatsAssigned" }, 1),
			"AC-7 totality"
		)
	end,

	--[[ AC-6's control, named in the criterion. ]]

	["AC-6 control: a machine that mutates and returns the input state is deterministic and is still rejected"] = function()
		accepts(
			Contract.stepIsDeterministic,
			MachineStubs.mutating,
			caseFor("a Tick in Lobby", { kind = "Tick" }, 1),
			"a mutating machine must pass AC-6's determinism half - that is the trap"
		)

		local message = refuses(
			Contract.stepDoesNotMutateItsInput,
			MachineStubs.mutating,
			caseFor("a Tick in Lobby", { kind = "Tick" }, 1),
			"a machine that mutates the state it was given must fail AC-6's non-mutation half"
		)
		assert(
			string.find(message, "AC-6", 1, true) ~= nil,
			`the AC-6 failure does not name the criterion: {message}`
		)
		assert(
			string.find(message, "step mutated the state it was given", 1, true) ~= nil,
			`the AC-6 failure does not say what is wrong: {message}`
		)
		assert(
			string.find(message, "phase", 1, true) ~= nil,
			`the AC-6 failure does not name the field that changed: {message}`
		)
	end,

	--[[ The reason the check above is written the way it is. This is the single
	     most important assertion in the story, and this test is what stops it
	     being written as the version that proves nothing. ]]

	["AC-6 control: a machine that mutates the input and returns a fresh copy passes an identity check and is still rejected"] = function()
		accepts(
			weakIdentityCheck,
			MachineStubs.mutatingCopier,
			caseFor("a Tick in Lobby", { kind = "Tick" }, 1),
			"a copy-returning mutator must pass the identity check - that is exactly why "
				.. "AC-6 may not be written as one"
		)

		local message = refuses(
			Contract.stepDoesNotMutateItsInput,
			MachineStubs.mutatingCopier,
			caseFor("a Tick in Lobby", { kind = "Tick" }, 1),
			"a machine that corrupts the caller's state and returns a fresh copy must fail "
				.. "AC-6's non-mutation half"
		)
		assert(
			string.find(message, "players", 1, true) ~= nil,
			`the AC-6 failure does not name the nested field that was mutated: {message}`
		)
	end,

	--[[ AC-7's control, named in the criterion. ]]

	["AC-7 control: a machine that raises on an unknown event is rejected and the failure names the event"] = function()
		accepts(
			Contract.eventIsIgnored,
			MachineStubs.raising,
			caseFor("a Tick in Lobby", { kind = "Tick" }, 1),
			"the raising machine must handle Tick - a stub that only throws controls nothing"
		)

		local message = refuses(
			Contract.eventIsIgnored,
			MachineStubs.raising,
			caseFor("a RoundResolved in Lobby", { kind = "RoundResolved" }, 1),
			"a machine that raises on an unknown event must fail AC-7"
		)
		assert(
			string.find(message, "AC-7", 1, true) ~= nil,
			`the AC-7 failure does not name the criterion: {message}`
		)
		assert(
			string.find(message, "a RoundResolved in Lobby", 1, true) ~= nil,
			`the AC-7 failure does not name the case that raised: {message}`
		)
	end,

	["AC-7 control: a machine that ignores an event but emits an effect for it is rejected"] = function()
		local message = refuses(
			Contract.eventIsIgnored,
			MachineStubs.chatty,
			caseFor("a RematchAccepted in Round", { kind = "RematchAccepted", playerId = "p9" }, 1),
			"AC-7 requires an EMPTY effect list, not merely an unchanged state"
		)
		assert(
			string.find(message, "PromptRematch", 1, true) ~= nil,
			`the AC-7 failure does not name the effect that should not exist: {message}`
		)
	end,

	--[[ The instrument. A deep comparison that cannot tell two states apart
	     turns AC-6, AC-7 and AC-8 green while proving nothing, and in RED it is
	     the only part of that machinery that can be measured at all. ]]

	["instrument: the comparator accepts a state and an independent deep copy of it"] = function()
		local state = Contract.sampleState()
		assert(
			Deep.equal(state, Deep.copy(state)),
			`a deep copy did not compare equal:\n{Deep.diff(state, Deep.copy(state))}`
		)
	end,

	["instrument: the comparator rejects a changed leaf, a missing key, an extra key and a wrong type"] = function()
		assert(
			not Deep.equal({ phase = "Lobby" }, { phase = "Round" }),
			"a changed leaf compared equal"
		)
		assert(
			not Deep.equal({ phase = "Lobby", seed = 1 }, { phase = "Lobby" }),
			"a missing key compared equal"
		)
		assert(
			not Deep.equal({ phase = "Lobby" }, { phase = "Lobby", seed = 1 }),
			"an extra key compared equal"
		)
		assert(not Deep.equal({ seed = 3 }, { seed = "3" }), "a number and a string compared equal")
	end,

	["instrument: the comparator rejects a difference nested two levels down and a longer list"] = function()
		local a = {
			outcome = { result = "won", reason = "procedure-complete" },
			players = { "p1", "p2" },
		}
		local b = { outcome = { result = "won", reason = "clock" }, players = { "p1", "p2" } }
		assert(not Deep.equal(a, b), "a nested difference compared equal")
		assert(
			string.find(Deep.diff(a, b), "reason", 1, true) ~= nil,
			`the difference does not name the nested field: {Deep.diff(a, b)}`
		)

		local longer = { outcome = a.outcome, players = { "p1", "p2", "p3" } }
		assert(not Deep.equal(a, longer), "a longer list compared equal")
	end,

	["instrument: a deep copy shares no table with the value it was taken from"] = function()
		local state = Contract.sampleState()
		local snapshot = Deep.copy(state)

		state.players[1] = "changed"
		assert(snapshot.players[1] == "p1", "the snapshot's nested list aliased the original")

		snapshot.phase = "Post"
		assert(state.phase == "Lobby", "writing to the snapshot changed the original")
	end,

	["instrument: the effect-kind list is the kinds in order"] = function()
		local kinds = Deep.kinds({
			{ kind = "AssignSeats", seed = 1, players = {} },
			{ kind = "ComputeTrace", roundId = "r" },
		})
		assert(
			Deep.equal(kinds, { "AssignSeats", "ComputeTrace" }),
			`the kinds are {Deep.show(kinds)}`
		)
	end,
}
