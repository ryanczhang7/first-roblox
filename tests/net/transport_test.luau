--!strict
--[[
	SLICE-002: every declared remote is bound through the wrapper and secrets
	reach only their player. AC-1 through AC-6 and the Contract blocks C-1
	through C-7 applied to the real `src/ReplicatedStorage/Net/Transport.luau`
	and `src/ReplicatedStorage/Net/ClientTransport.luau`, driving the real
	`Wrapper` and `Schema` behind injected fakes of `RemoteEvent`.

	THE TWO MODULES DO NOT EXIST IN RED, so both requires below fail and every
	test here FAILS naming the module that did not load. That is the right
	failure: the modules are the first thing the story requires. The checks
	themselves live in `tests/helpers/TransportContract.luau`, and every one
	of them has been OBSERVED to fire in `tests/net/transport_controls_test.luau`
	against the transport it exists to catch - including the two the criteria
	name: AC-1 against a bind with no guard, AC-3 against a sendTo that
	broadcasts.

	THE CLIENT SIDE IS MODULE STATE (C-7), so "on or send before any init
	raises" can be observed exactly once per process. The runner sorts a
	file's test names, and `(` sorts before every letter and digit, so the
	name below beginning "AC-6 (first)" runs before every other test in this
	file that calls `ClientTransport.init`. No other file inits it.

	NO ROBLOX. `Ports` is `TransportStubs.ports`, a recorder; the context is
	a seated-id list with a fixed phase and a constant clock.
]]

local Contract = require("../helpers/TransportContract")

local transportLoaded, transportResult = pcall(require, "@game/ReplicatedStorage/Net/Transport")
local clientLoaded, clientResult = pcall(require, "@game/ReplicatedStorage/Net/ClientTransport")

local function bundle(): Contract.Bundle
	assert(
		transportLoaded,
		`src/ReplicatedStorage/Net/Transport.luau did not load: {tostring(transportResult)}`
	)
	assert(
		clientLoaded,
		`src/ReplicatedStorage/Net/ClientTransport.luau did not load: {tostring(clientResult)}`
	)
	return { Transport = transportResult, ClientTransport = clientResult }
end

return {
	--[[ AC-1 ]]

	["AC-1: after bind, each declared remote's event has exactly one OnServerEvent connection, every one of the ten kind events has none, and none has an OnClientEvent connection"] = function()
		Contract.bindConnectsEachDeclaredRemoteExactlyOnce(bundle())
	end,

	['AC-1: a seated player\'s { token = "four" } on "Ping", and a non-table payload on "SendPreset", return a Rejection with reason "shape" from the connected function and never reach either handler'] = function()
		Contract.malformedCallIsRejectedForShapeAndNeverReachesTheHandler(bundle())
	end,

	['AC-1 / C-1 / C-2: a seated player\'s well-formed call returns nil and reaches its handler exactly once with the mapped id "p2", the payload table, and a CallControl with a decline function as the third argument'] = function()
		Contract.wellFormedCallReachesTheHandlerWithTheMappedIdAndACallControl(bundle())
	end,

	['C-1: a handler that calls call.decline() makes the connected function return a Rejection with reason "declined" - the wrapper\'s own CallControl reached it'] = function()
		Contract.aHandlerThatDeclinesMakesTheConnectedFunctionReturnDeclined(bundle())
	end,

	--[[ AC-2 / C-5 ]]

	["AC-2 / C-5: bind with a declared remote Orphaned_Declared that has no handler raises naming it, with zero ports.remoteEvent calls and nothing connected"] = function()
		Contract.bindRaisesNamingADeclaredRemoteWithNoHandlerBeforeTouchingPorts(bundle())
	end,

	["AC-2 / C-5: bind with a handler Stray_Handler for a remote never declared raises naming it, with zero ports.remoteEvent calls and nothing connected"] = function()
		Contract.bindRaisesNamingAHandlerForAnUndeclaredRemoteBeforeTouchingPorts(bundle())
	end,

	--[[ C-4 ]]

	["C-4: bind calls ports.remoteEvent exactly once for each of the two declared remotes and each of the ten kinds - twelve calls - and six sends, four broadcasts and a send to a departed player add none"] = function()
		Contract.bindReadsEveryPortExactlyOnceAndSendsReadNone(bundle())
	end,

	--[[ AC-3 ]]

	["AC-3: sendTo for each of the six per-player kinds calls FireClient exactly once on that kind's own event with playerFor's object and the payload, no other event fires, and FireAllClients is never called"] = function()
		Contract.sendToFiresEachPrivateKindOnItsOwnEventToThatPlayerOnly(bundle())
	end,

	["Contract: sendTo for a playerId whose playerFor answers nil asks playerFor once per send, raises nothing and fires nothing"] = function()
		Contract.sendToForAPlayerWithNoObjectIsANoOp(bundle())
	end,

	--[[ AC-4 ]]

	["AC-4: broadcast with each of the six per-player kinds raises naming the kind, and nothing is fired on any event"] = function()
		Contract.broadcastWithAPrivateKindRaisesNamingItAndFiresNothing(bundle())
	end,

	["AC-4: broadcast with each of the four public kinds calls FireAllClients exactly once on that kind's own event with the payload, and FireClient never"] = function()
		Contract.broadcastFiresEachPublicKindOnceOnItsOwnEvent(bundle())
	end,

	["AC-4: Transport.PRIVATE_KINDS is exactly { SeatView, LensView, TurnCues, TurnResult, PresetFailed, PingRefused } and PUBLIC_KINDS exactly { RoundView, FacilityView, PresetShown, TraceView }, each key true"] = function()
		Contract.kindSetsAreExactlyTheSixAndTheFour(bundle())
	end,

	--[[ C-6 ]]

	["C-6: sendTo with each public kind, and with a kind in neither set, raises naming the kind and fires nothing"] = function()
		Contract.sendToWithAPublicOrUnknownKindRaisesNamingItAndFiresNothing(bundle())
	end,

	["C-6: broadcast with a kind in neither set raises naming the kind and fires nothing"] = function()
		Contract.broadcastWithAnUnknownKindRaisesNamingItAndFiresNothing(bundle())
	end,

	--[[ AC-5 / C-3 ]]

	['AC-5 / C-3: a well-formed call from a player object idOf maps to nil returns a Rejection with reason "identity", never reaches the handler, calls idOf once with the object, and context.isSeated receives idOf\'s nil - never the object'] = function()
		Contract.unmappedPlayerIsRejectedForIdentityAndTheRawObjectReachesNothing(bundle())
	end,

	['C-3: across a seated and an unseated mapped player, idOf is called once per call with each raw object and context.isSeated receives the mapped ids "p1" and "p2"; the seated call reaches the handler as "p1", the unseated one is "identity"'] = function()
		Contract.mappedPlayerIsIdentifiedOncePerCallAndNeverSeenRaw(bundle())
	end,

	--[[ AC-6 / C-7 ]]

	["AC-6 (first) C-7: on and send before any init raise, each naming its own call and init"] = function()
		Contract.clientOnAndSendBeforeInitRaiseNamingTheCall(bundle())
	end,

	["AC-6: after init, on(kind, fn) for each of the ten kinds makes exactly one OnClientEvent connection on that kind's event, and firing each event delivers its payload to its own listener only"] = function()
		Contract.clientOnDeliversEachKindsPayloadToItsOwnListener(bundle())
	end,

	['AC-6: send("Ping", args) calls FireServer on the "Ping" event exactly once with args as the single argument after self, and fires nothing else'] = function()
		Contract.clientSendCallsFireServerWithArgsAsTheSinglePayload(bundle())
	end,

	["C-7: on with a kind in neither set raises naming the kind and asks ports.remoteEvent for nothing"] = function()
		Contract.clientOnWithAKindInNeitherSetRaisesNamingIt(bundle())
	end,

	["C-7: init called again replaces the ports - connections and sends after it reach the second ports and never the first"] = function()
		Contract.clientInitAgainReplacesThePorts(bundle())
	end,
}
