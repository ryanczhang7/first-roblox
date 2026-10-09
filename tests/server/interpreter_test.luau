--!strict
--[[
	SLICE-004 AC-1 and AC-2 applied to the real
	`src/server/session/Interpreter.luau`.

	THE MODULE DOES NOT EXIST IN RED, so the require below fails and every
	test here FAILS naming the module that did not load. That is the right
	failure: the module is the first thing the story requires. The checks
	themselves live in `tests/helpers/InterpreterContract.luau`, and every
	one of them has been OBSERVED to fire in
	`tests/server/interpreter_controls_test.luau` against the interpreter it
	exists to catch - including the one AC-1 names, a `SendTo` turned into a
	broadcast, which the real `Transport` refuses.

	The export shape pinned here (nothing below is a suggestion; a wrong name
	is a nil call):

	    Interpreter.perform(effects: { Session.SessionEffect }, ports: Ports) -> ()

	with `Ports` as the story's `## Contract` declares it: `transport`
	(`Transport.Bound`, called as METHODS), `emit`, `promptRematch`,
	`computeTrace`, `place`.

	D-1 (GATES): with `sendTo` and `broadcast` swapped in the interpreter,
	the two AC-1 cases naming the trace and the real transport go red.
]]

local Contract = require("../helpers/InterpreterContract")

local MODULE = "src/server/session/Interpreter.luau"

local loaded, loadResult = pcall(require, "@game/server/session/Interpreter")

local function perform(): Contract.Perform
	assert(loaded, `{MODULE} did not load: {tostring(loadResult)}`)
	local Interpreter = loadResult :: any
	assert(
		typeof(Interpreter) == "table" and typeof(Interpreter.perform) == "function",
		`{MODULE} must export perform as a function; it exports {typeof(Interpreter)}`
	)
	return Interpreter.perform
end

return {
	--[[ AC-1 ]]

	["AC-1: over a mixed list of every effect kind, each makes exactly one port call, in list order, with the effect's own payload, position and event tables"] = function()
		Contract.everyKindMakesExactlyOneCallInListOrder(perform())
	end,

	["AC-1: each Emit is one ports.emit call carrying a fresh one-element list holding that effect's event"] = function()
		Contract.emitIsAFreshOneElementListPerEffect(perform())
	end,

	["AC-1: an empty effect list makes no port call and does not raise"] = function()
		Contract.anEmptyListMakesNoCall(perform())
	end,

	["AC-1 control: through the real Transport.bind over fake RemoteEvents, a SendTo of SeatView fires FireClient once on the SeatView event to that player's object, a Broadcast of RoundView fires FireAllClients once on its event, and no other event fires"] = function()
		Contract.theRealTransportRoutesASendToItsPlayerOnlyAndABroadcastToAll(perform())
	end,

	--[[ AC-2 ]]

	['AC-2: an effect of kind "Frobnicate" raises naming it, after the two effects before it were performed and before the one after it'] = function()
		Contract.anUnknownKindRaisesNamingItAtThatEffect(perform())
	end,

	["AC-2: an AssignSeats effect raises naming AssignSeats and makes no port call"] = function()
		Contract.assignSeatsRaisesNamingIt(perform())
	end,
}
