--!strict
--[[
	SLICE-002 AC-1 through AC-6 and the Contract blocks C-1 through C-7,
	written once as checks over a bundle - `{ Transport, ClientTransport }` -
	handed in as a parameter rather than over `src/ReplicatedStorage/Net/
	Transport.luau` by name. The same arrangement as `DeclineContract.luau`:
	`tests/net/transport_test.luau` applies these to the real modules and
	`tests/net/transport_controls_test.luau` applies them to the deliberately
	wrong transports in `TransportStubs.luau`, so that every check here has
	been EXECUTED and observed to refuse the implementation it exists to
	catch before GREEN writes a line.

	EVERY CRITERION IS MECHANICAL (`## Contract`, "Oracle partition"): each
	check pins exact calls on the recording fakes - which method, which
	arguments, how many times - and nothing here is designed or thresholded.

	THE DECLARATIONS ARE PLAIN `RemoteDefinition` TABLES, not `Remotes.define`
	calls: the registry is module-level and refuses a duplicate name, and
	every check here declares the same two remotes against every bundle. The
	schema is the real `Schema`, so `shape` is the wrapper's own verdict on a
	payload with a string where an integer belongs. The context is built here
	rather than borrowed from `NetContract.context` because C-3 needs to see
	a `nil` handed to `isSeated`, and `table.insert(list, nil)` records
	nothing.

	THE NEEDLES. Every "raises, naming X" check requires the message to
	contain a name chosen to appear nowhere else - `Orphaned_Declared`,
	`Stray_Handler`, the kind - so a raise for a different reason cannot
	satisfy it. "Fires nothing" is asserted as a count of zero over EVERY
	fake the harness built, not over the one event the call named.
]]

local Schema = require("../../src/ReplicatedStorage/Net/Schema")
local Stubs = require("./TransportStubs")

local TransportContract = {}

export type Bundle = { Transport: any, ClientTransport: any }

local PRIVATE = Stubs.PRIVATE
local PUBLIC = Stubs.PUBLIC
local UNKNOWN_KINDS = { "Nonsense", "seatview", "RoundViews", "" }

-- The two remotes every check declares. `token` is the one field, so a
-- string where the integer belongs is a `shape` failure and nothing else.
local function definitions(): { any }
	return {
		{
			name = "Ping",
			args = Schema.shape({ token = Schema.integer(1, 16) }),
			legalPhases = { "Round" },
		},
		{
			name = "SendPreset",
			args = Schema.shape({ token = Schema.integer(1, 16) }),
			legalPhases = { "Round" },
		},
	}
end

local VALID = { token = 4 }
local MALFORMED = { token = "four" }

type Context = { context: any, asked: { { value: any } } }

-- A GuardContext over a list of seated ids, recording every `isSeated`
-- argument - including nil - as a wrapper so the count is honest.
local function context(seated: { string }): Context
	local seatedSet: { [any]: boolean } = {}
	for _, id in seated do
		seatedSet[id] = true
	end
	local asked: { { value: any } } = {}
	local ctx = {
		isSeated = function(playerId: any): boolean
			table.insert(asked, { value = playerId })
			return seatedSet[playerId] == true
		end,
		phase = function(): string
			return "Round"
		end,
		clock = {
			now = function()
				return 0
			end,
		},
	}
	return { context = ctx, asked = asked }
end

type Call = { playerId: any, args: any, call: any, n: number }

local function recorder(): (any, { Call })
	local calls: { Call } = {}
	local handler = function(...: any)
		local playerId, args, call = ...
		table.insert(calls, { playerId = playerId, args = args, call = call, n = select("#", ...) })
	end
	return handler, calls
end

local function players(): { [string]: any }
	return {
		p1 = { Name = "player one", UserId = 1 },
		p2 = { Name = "player two", UserId = 2 },
	}
end

-- A bound transport over the two remotes, both handled by recorders.
type World = {
	bound: any,
	harness: Stubs.Harness,
	ctx: Context,
	calls: { [string]: { Call } },
	connected: { [string]: any },
}

local function bindWorld(bundle: Bundle, seated: { string }?): World
	local harness = Stubs.ports(players())
	local ctx = context(seated or { "p1", "p2" })
	local pingHandler, pingCalls = recorder()
	local presetHandler, presetCalls = recorder()
	local bound = bundle.Transport.bind(
		definitions(),
		ctx.context,
		{ Ping = pingHandler, SendPreset = presetHandler },
		harness.ports
	)
	local connected: { [string]: any } = {}
	for _, name in { "Ping", "SendPreset" } do
		local event = harness.events[name]
		assert(event ~= nil, `bind never asked ports.remoteEvent for "{name}"`)
		assert(
			#event.serverConnections == 1,
			`"{name}" has {#event.serverConnections} OnServerEvent connection(s); expected exactly 1`
		)
		connected[name] = event.serverConnections[1]
	end
	return {
		bound = bound,
		harness = harness,
		ctx = ctx,
		calls = { Ping = pingCalls, SendPreset = presetCalls },
		connected = connected,
	}
end

local function sortedKeys(set: { [string]: any }): { string }
	local keys: { string } = {}
	for key in set do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function describeRejection(result: any): string
	if typeof(result) ~= "table" then
		return `{typeof(result)} {tostring(result)}`
	end
	return `\{ reason = {tostring(result.reason)}, detail = {tostring(result.detail)} \}`
end

local function expectReason(result: any, reason: string, what: string)
	assert(
		typeof(result) == "table" and result.reason == reason,
		`{what}: expected a Rejection with reason "{reason}", got {describeRejection(result)}`
	)
end

-- Totals over EVERY fake the harness built, so "nothing fired" is global.
local function fireCounts(harness: Stubs.Harness): (number, number)
	local clients, all = 0, 0
	for _, event in harness.events do
		clients += #event.fireClientCalls
		all += #event.fireAllCalls
	end
	return clients, all
end

local function expectNothingFired(harness: Stubs.Harness, what: string)
	local clients, all = fireCounts(harness)
	assert(
		clients == 0 and all == 0,
		`{what}: expected nothing fired, but FireClient was called {clients} time(s) and `
			.. `FireAllClients {all} time(s) across every event`
	)
end

local function countOf(list: { string }, wanted: string): number
	local n = 0
	for _, item in list do
		if item == wanted then
			n += 1
		end
	end
	return n
end

local function expectRaiseNaming(fn: () -> (), name: string, what: string): string
	local ok, err = pcall(fn)
	assert(not ok, `{what}: expected a raise naming "{name}", but it returned`)
	local message = tostring(err)
	assert(
		string.find(message, name, 1, true) ~= nil,
		`{what}: the raise does not name "{name}":\n{message}`
	)
	return message
end

--[[ AC-1 ]]

function TransportContract.bindConnectsEachDeclaredRemoteExactlyOnce(bundle: Bundle)
	local world = bindWorld(bundle)
	for _, name in { "Ping", "SendPreset" } do
		local event = world.harness.events[name]
		assert(
			#event.serverConnections == 1,
			`"{name}" has {#event.serverConnections} OnServerEvent connection(s); expected exactly 1`
		)
		assert(
			#event.clientConnections == 0,
			`bind connected OnClientEvent on "{name}" {#event.clientConnections} time(s) on the server`
		)
	end
	for _, kind in PRIVATE do
		local event = world.harness.events[kind]
		assert(event ~= nil, `bind never asked ports.remoteEvent for the kind "{kind}"`)
		assert(
			#event.serverConnections == 0,
			`bind connected OnServerEvent on the payload event "{kind}" {#event.serverConnections} time(s)`
		)
	end
	for _, kind in PUBLIC do
		local event = world.harness.events[kind]
		assert(event ~= nil, `bind never asked ports.remoteEvent for the kind "{kind}"`)
		assert(
			#event.serverConnections == 0,
			`bind connected OnServerEvent on the payload event "{kind}" {#event.serverConnections} time(s)`
		)
	end
end

function TransportContract.malformedCallIsRejectedForShapeAndNeverReachesTheHandler(bundle: Bundle)
	local world = bindWorld(bundle)
	local result = world.connected.Ping(world.harness.players.p1, MALFORMED)
	expectReason(result, "shape", 'a seated player sending { token = "four" } on "Ping"')
	assert(
		#world.calls.Ping == 0,
		`the malformed call reached the "Ping" handler {#world.calls.Ping} time(s); it must be `
			.. `rejected by Wrapper.guard before the handler`
	)
	assert(#world.calls.SendPreset == 0, "the malformed call reached the SendPreset handler")

	-- A non-table payload is `shape` too, and still never reaches the handler.
	local other = world.connected.SendPreset(world.harness.players.p2, "not a table")
	expectReason(other, "shape", 'a seated player sending "not a table" on "SendPreset"')
	assert(#world.calls.SendPreset == 0, "the non-table payload reached the SendPreset handler")
end

function TransportContract.wellFormedCallReachesTheHandlerWithTheMappedIdAndACallControl(
	bundle: Bundle
)
	local world = bindWorld(bundle)
	local result = world.connected.Ping(world.harness.players.p2, VALID)
	assert(
		result == nil,
		`an accepted call must return nil from the connected function; got {describeRejection(
			result
		)}`
	)
	assert(#world.calls.Ping == 1, `the "Ping" handler ran {#world.calls.Ping} time(s); expected 1`)
	assert(#world.calls.SendPreset == 0, `the "SendPreset" handler ran for a "Ping" call`)
	local call = world.calls.Ping[1]
	assert(
		call.playerId == "p2",
		`the handler received playerId {tostring(call.playerId)} ({typeof(call.playerId)}); `
			.. `expected the mapped id "p2"`
	)
	assert(call.args == VALID, "the handler did not receive the payload table the call carried")
	-- C-1: the third argument is the wrapper's CallControl.
	assert(
		call.n >= 3 and typeof(call.call) == "table" and typeof(call.call.decline) == "function",
		`the handler received {call.n} argument(s) and call = {tostring(call.call)}; expected a `
			.. `CallControl with a decline function as the third (C-1)`
	)
end

function TransportContract.aHandlerThatDeclinesMakesTheConnectedFunctionReturnDeclined(
	bundle: Bundle
)
	local harness = Stubs.ports(players())
	local ctx = context({ "p1" })
	local declines = 0
	local bound = bundle.Transport.bind(definitions(), ctx.context, {
		Ping = function(_playerId: any, _args: any, call: any)
			declines += 1
			call.decline()
		end,
		SendPreset = function() end,
	}, harness.ports)
	assert(bound ~= nil, "bind returned nil")
	local connected = harness.events.Ping.serverConnections[1]
	assert(connected ~= nil, 'bind connected nothing on "Ping"')
	local result = connected(harness.players.p1, VALID)
	assert(declines == 1, `the declining handler ran {declines} time(s)`)
	expectReason(result, "declined", 'a seated player whose "Ping" handler calls call.decline()')
end

--[[ AC-2 / C-5 ]]

function TransportContract.bindRaisesNamingADeclaredRemoteWithNoHandlerBeforeTouchingPorts(
	bundle: Bundle
)
	local harness = Stubs.ports(players())
	local ctx = context({ "p1" })
	local defs = definitions()
	table.insert(defs, {
		name = "Orphaned_Declared",
		args = Schema.shape({ token = Schema.integer(1, 16) }),
		legalPhases = { "Round" },
	})
	expectRaiseNaming(function()
		bundle.Transport.bind(defs, ctx.context, {
			Ping = function() end,
			SendPreset = function() end,
		}, harness.ports)
	end, "Orphaned_Declared", "bind with a declared remote that has no handler")
	assert(
		#harness.remoteEventCalls == 0,
		`bind called ports.remoteEvent {#harness.remoteEventCalls} time(s) before raising (C-5): `
			.. table.concat(harness.remoteEventCalls, ", ")
	)
	for name, event in harness.events do
		assert(
			#event.serverConnections == 0,
			`bind connected "{name}" before raising on the unhandled remote (C-5)`
		)
	end
end

function TransportContract.bindRaisesNamingAHandlerForAnUndeclaredRemoteBeforeTouchingPorts(
	bundle: Bundle
)
	local harness = Stubs.ports(players())
	local ctx = context({ "p1" })
	expectRaiseNaming(function()
		bundle.Transport.bind(definitions(), ctx.context, {
			Ping = function() end,
			SendPreset = function() end,
			Stray_Handler = function() end,
		}, harness.ports)
	end, "Stray_Handler", "bind with a handler for a remote that was never declared")
	assert(
		#harness.remoteEventCalls == 0,
		`bind called ports.remoteEvent {#harness.remoteEventCalls} time(s) before raising (C-5): `
			.. table.concat(harness.remoteEventCalls, ", ")
	)
	for name, event in harness.events do
		assert(
			#event.serverConnections == 0,
			`bind connected "{name}" before raising on the undeclared handler (C-5)`
		)
	end
end

--[[ C-4 ]]

function TransportContract.bindReadsEveryPortExactlyOnceAndSendsReadNone(bundle: Bundle)
	local world = bindWorld(bundle)
	local calls = world.harness.remoteEventCalls
	local expected = { "Ping", "SendPreset" }
	for _, kind in PRIVATE do
		table.insert(expected, kind)
	end
	for _, kind in PUBLIC do
		table.insert(expected, kind)
	end
	for _, name in expected do
		local n = countOf(calls, name)
		assert(
			n == 1,
			`bind called ports.remoteEvent("{name}") {n} time(s); expected exactly once (C-4). `
				.. `All calls: {table.concat(calls, ", ")}`
		)
	end
	assert(
		#calls == #expected,
		`bind called ports.remoteEvent {#calls} time(s); expected {#expected} (two remotes and `
			.. `ten kinds): {table.concat(calls, ", ")}`
	)

	local before = #calls
	for _, kind in PRIVATE do
		world.bound:sendTo("p1", kind, { kind = kind })
	end
	for _, kind in PUBLIC do
		world.bound:broadcast(kind, { kind = kind })
	end
	world.bound:sendTo("nobody", "SeatView", {})
	assert(
		#calls == before,
		`sendTo/broadcast called ports.remoteEvent {#calls - before} time(s) (C-4): `
			.. table.concat(calls, ", ", before + 1)
	)
end

--[[ AC-3 ]]

function TransportContract.sendToFiresEachPrivateKindOnItsOwnEventToThatPlayerOnly(bundle: Bundle)
	local world = bindWorld(bundle)
	local harness = world.harness
	for index, kind in PRIVATE do
		local payload = { kind = kind, index = index }
		local target = if index % 2 == 1 then "p1" else "p2"
		world.bound:sendTo(target, kind, payload)

		-- The secret-keeping half first, so a broadcast is named as one.
		local _, allBefore = fireCounts(harness)
		assert(
			allBefore == 0,
			`sendTo("{target}", "{kind}") called FireAllClients ({allBefore} call(s) across every `
				.. `event) for a per-player payload (AC-3); a secret must never be broadcast`
		)
		local event = harness.events[kind]
		assert(event ~= nil, `no event named "{kind}" was ever built`)
		assert(
			#event.fireClientCalls == 1,
			`sendTo("{target}", "{kind}") called FireClient on "{kind}" {#event.fireClientCalls} `
				.. `time(s); expected exactly 1`
		)
		local fired = event.fireClientCalls[1]
		assert(
			fired.player == harness.players[target],
			`sendTo("{target}", "{kind}") fired to {tostring(fired.player and fired.player.Name)}, `
				.. `not ports.playerFor("{target}")'s object`
		)
		assert(fired.payload == payload, `sendTo("{target}", "{kind}") fired a different payload`)

		local clients, all = fireCounts(harness)
		assert(
			clients == index,
			`after {index} send(s), FireClient has been called {clients} time(s) across every `
				.. `event; a send must reach exactly one event once`
		)
		assert(
			all == 0,
			`FireAllClients was called {all} time(s) for a per-player payload (AC-3); a secret `
				.. `must never be broadcast`
		)
	end
	-- Every send landed on its own kind's event and nowhere else.
	for name, event in harness.events do
		local expected = if table.find(PRIVATE, name) ~= nil then 1 else 0
		assert(
			#event.fireClientCalls == expected,
			`"{name}" saw {#event.fireClientCalls} FireClient call(s); expected {expected}`
		)
	end
end

function TransportContract.sendToForAPlayerWithNoObjectIsANoOp(bundle: Bundle)
	local world = bindWorld(bundle)
	local ok, err = pcall(function()
		world.bound:sendTo("ghost", "SeatView", { gone = true })
		world.bound:sendTo("ghost", "PingRefused", { gone = true })
	end)
	assert(ok, `sendTo for a playerId with no player object raised: {tostring(err)}`)
	assert(
		countOf(world.harness.playerForCalls, "ghost") == 2,
		`sendTo asked ports.playerFor("ghost") {countOf(world.harness.playerForCalls, "ghost")} `
			.. `time(s); expected once per send`
	)
	expectNothingFired(world.harness, "sendTo for a player who has left")
end

--[[ AC-4 ]]

function TransportContract.broadcastWithAPrivateKindRaisesNamingItAndFiresNothing(bundle: Bundle)
	local world = bindWorld(bundle)
	for _, kind in PRIVATE do
		expectRaiseNaming(function()
			world.bound:broadcast(kind, { kind = kind })
		end, kind, `broadcast("{kind}")`)
	end
	expectNothingFired(world.harness, "broadcast of the six per-player kinds")
end

function TransportContract.broadcastFiresEachPublicKindOnceOnItsOwnEvent(bundle: Bundle)
	local world = bindWorld(bundle)
	local harness = world.harness
	for index, kind in PUBLIC do
		local payload = { kind = kind }
		world.bound:broadcast(kind, payload)
		local event = harness.events[kind]
		assert(event ~= nil, `no event named "{kind}" was ever built`)
		assert(
			#event.fireAllCalls == 1,
			`broadcast("{kind}") called FireAllClients on "{kind}" {#event.fireAllCalls} time(s); `
				.. `expected exactly 1`
		)
		assert(
			event.fireAllCalls[1].payload == payload,
			`broadcast("{kind}") fired a different payload`
		)
		local clients, all = fireCounts(harness)
		assert(clients == 0, `broadcast called FireClient {clients} time(s)`)
		assert(
			all == index,
			`after {index} broadcast(s), FireAllClients has been called {all} time(s) across every event`
		)
	end
	for name, event in harness.events do
		local expected = if table.find(PUBLIC, name) ~= nil then 1 else 0
		assert(
			#event.fireAllCalls == expected,
			`"{name}" saw {#event.fireAllCalls} FireAllClients call(s); expected {expected}`
		)
	end
end

function TransportContract.kindSetsAreExactlyTheSixAndTheFour(bundle: Bundle)
	local Transport = bundle.Transport
	assert(typeof(Transport.PRIVATE_KINDS) == "table", "Transport.PRIVATE_KINDS is not a table")
	assert(typeof(Transport.PUBLIC_KINDS) == "table", "Transport.PUBLIC_KINDS is not a table")
	local privateKeys = sortedKeys(Transport.PRIVATE_KINDS)
	local publicKeys = sortedKeys(Transport.PUBLIC_KINDS)
	local expectedPrivate = table.clone(PRIVATE)
	local expectedPublic = table.clone(PUBLIC)
	table.sort(expectedPrivate)
	table.sort(expectedPublic)
	assert(
		table.concat(privateKeys, ",") == table.concat(expectedPrivate, ","),
		`PRIVATE_KINDS is \{ {table.concat(privateKeys, ", ")} \}; expected exactly `
			.. `\{ {table.concat(expectedPrivate, ", ")} \}`
	)
	assert(
		table.concat(publicKeys, ",") == table.concat(expectedPublic, ","),
		`PUBLIC_KINDS is \{ {table.concat(publicKeys, ", ")} \}; expected exactly `
			.. `\{ {table.concat(expectedPublic, ", ")} \}`
	)
	for _, kind in PRIVATE do
		assert(Transport.PRIVATE_KINDS[kind] == true, `PRIVATE_KINDS["{kind}"] is not true`)
	end
	for _, kind in PUBLIC do
		assert(Transport.PUBLIC_KINDS[kind] == true, `PUBLIC_KINDS["{kind}"] is not true`)
	end
end

--[[ C-6 ]]

function TransportContract.sendToWithAPublicOrUnknownKindRaisesNamingItAndFiresNothing(
	bundle: Bundle
)
	local world = bindWorld(bundle)
	for _, kind in PUBLIC do
		expectRaiseNaming(function()
			world.bound:sendTo("p1", kind, { kind = kind })
		end, kind, `sendTo("p1", "{kind}") with a public kind`)
	end
	for _, kind in UNKNOWN_KINDS do
		expectRaiseNaming(function()
			world.bound:sendTo("p1", kind, { kind = kind })
		end, kind, `sendTo("p1", "{kind}") with a kind in neither set`)
	end
	expectNothingFired(world.harness, "sendTo with a public or unknown kind")
end

function TransportContract.broadcastWithAnUnknownKindRaisesNamingItAndFiresNothing(bundle: Bundle)
	local world = bindWorld(bundle)
	for _, kind in UNKNOWN_KINDS do
		expectRaiseNaming(function()
			world.bound:broadcast(kind, { kind = kind })
		end, kind, `broadcast("{kind}") with a kind in neither set`)
	end
	expectNothingFired(world.harness, "broadcast with an unknown kind")
end

--[[ AC-5 / C-3 ]]

function TransportContract.unmappedPlayerIsRejectedForIdentityAndTheRawObjectReachesNothing(
	bundle: Bundle
)
	local world = bindWorld(bundle)
	local stranger = { Name = "stranger", UserId = 99 }
	local result = world.connected.Ping(stranger, VALID)
	expectReason(result, "identity", "a well-formed call from a player object idOf cannot map")
	assert(
		#world.calls.Ping == 0,
		`the unmapped player's call reached the "Ping" handler {#world.calls.Ping} time(s)`
	)
	assert(
		#world.harness.idOfCalls == 1 and world.harness.idOfCalls[1].player == stranger,
		`ports.idOf was called {#world.harness.idOfCalls} time(s) for one call; expected once, `
			.. `with the raw player object (C-3)`
	)
	assert(
		#world.ctx.asked == 1,
		`context.isSeated was asked {#world.ctx.asked} time(s) for one call; expected once`
	)
	local seen = world.ctx.asked[1].value
	assert(
		seen ~= stranger and typeof(seen) ~= "table",
		`context.isSeated received the raw player object ({typeof(seen)}); the transport must `
			.. `pass idOf's result - nil here - never the object (C-3)`
	)
end

function TransportContract.mappedPlayerIsIdentifiedOncePerCallAndNeverSeenRaw(bundle: Bundle)
	local world = bindWorld(bundle, { "p1" })
	local p1 = world.harness.players.p1
	local p2 = world.harness.players.p2
	-- Seated: accepted. Mapped but unseated: identity, with the id not the object.
	local accepted = world.connected.Ping(p1, VALID)
	assert(accepted == nil, `the seated call was not accepted: {describeRejection(accepted)}`)
	local unseated = world.connected.Ping(p2, VALID)
	expectReason(unseated, "identity", "a well-formed call from a mapped but unseated player")
	assert(
		#world.harness.idOfCalls == 2,
		`ports.idOf was called {#world.harness.idOfCalls} time(s) for two calls; expected once each`
	)
	assert(
		world.harness.idOfCalls[1].player == p1 and world.harness.idOfCalls[2].player == p2,
		"ports.idOf was not handed the raw player object of each call"
	)
	assert(
		#world.ctx.asked == 2,
		`context.isSeated was asked {#world.ctx.asked} time(s); expected 2`
	)
	assert(
		world.ctx.asked[1].value == "p1" and world.ctx.asked[2].value == "p2",
		`context.isSeated received {tostring(world.ctx.asked[1].value)} and `
			.. `{tostring(world.ctx.asked[2].value)}; expected the mapped ids "p1" and "p2" (C-3)`
	)
	assert(#world.calls.Ping == 1, `the handler ran {#world.calls.Ping} time(s); expected 1`)
	assert(
		world.calls.Ping[1].playerId == "p1",
		`the handler received {tostring(world.calls.Ping[1].playerId)}, not "p1"`
	)
end

--[[ AC-6 / C-7 ]]

-- The first thing done to a FRESH ClientTransport: in the real module, which
-- is module state, this check is meaningful only before any `init`.
function TransportContract.clientOnAndSendBeforeInitRaiseNamingTheCall(bundle: Bundle)
	local Client = bundle.ClientTransport
	local onMessage = expectRaiseNaming(function()
		Client.on("RoundView", function() end)
	end, "init", "ClientTransport.on before init")
	assert(
		string.find(onMessage, "ClientTransport.on", 1, true) ~= nil,
		`the raise does not name the call "ClientTransport.on":\n{onMessage}`
	)
	local sendMessage = expectRaiseNaming(function()
		Client.send("Ping", { token = 1 })
	end, "init", "ClientTransport.send before init")
	assert(
		string.find(sendMessage, "ClientTransport.send", 1, true) ~= nil,
		`the raise does not name the call "ClientTransport.send":\n{sendMessage}`
	)
end

function TransportContract.clientOnDeliversEachKindsPayloadToItsOwnListener(bundle: Bundle)
	local Client = bundle.ClientTransport
	local harness = Stubs.ports({})
	Client.init(harness.ports)

	local received: { [string]: { any } } = {}
	local kinds: { string } = {}
	for _, kind in PRIVATE do
		table.insert(kinds, kind)
	end
	for _, kind in PUBLIC do
		table.insert(kinds, kind)
	end
	for _, kind in kinds do
		received[kind] = {}
		local mine = kind
		Client.on(kind, function(payload: any)
			table.insert(received[mine], payload)
		end)
	end
	for _, kind in kinds do
		local event = harness.events[kind]
		assert(event ~= nil, `on("{kind}") never asked ports.remoteEvent for "{kind}"`)
		assert(
			#event.clientConnections == 1,
			`on("{kind}") made {#event.clientConnections} OnClientEvent connection(s) on "{kind}"; `
				.. `expected exactly 1`
		)
		assert(#event.serverConnections == 0, `on("{kind}") connected OnServerEvent on the client`)
	end
	-- Fire each kind's event once, then every listener holds its own payload
	-- and nobody else's.
	for _, kind in kinds do
		harness.events[kind].clientConnections[1]({ kind = kind })
	end
	for _, kind in kinds do
		local got = received[kind]
		assert(
			#got == 1 and got[1].kind == kind,
			`the "{kind}" listener received {#got} payload(s)`
				.. (if #got > 0 then ` (first for "{tostring(got[1].kind)}")` else "")
				.. `; expected exactly one, for "{kind}"`
		)
	end
end

function TransportContract.clientSendCallsFireServerWithArgsAsTheSinglePayload(bundle: Bundle)
	local Client = bundle.ClientTransport
	local harness = Stubs.ports({})
	Client.init(harness.ports)
	local args = { token = 7 }
	Client.send("Ping", args)
	local event = harness.events.Ping
	assert(event ~= nil, 'send("Ping") never asked ports.remoteEvent for "Ping"')
	assert(
		#event.fireServerCalls == 1,
		`send("Ping") called FireServer {#event.fireServerCalls} time(s); expected exactly 1`
	)
	local fired = event.fireServerCalls[1]
	assert(
		fired.n == 1 and fired.args[1] == args,
		`FireServer received {fired.n} argument(s) after self, the first being `
			.. `{tostring(fired.args[1])}; expected exactly one, the args table itself`
	)
	local clients, all = fireCounts(harness)
	assert(clients == 0 and all == 0, "send called a server-side fire method")
	for name, other in harness.events do
		if name ~= "Ping" then
			assert(#other.fireServerCalls == 0, `send("Ping") fired on "{name}"`)
		end
	end
end

function TransportContract.clientOnWithAKindInNeitherSetRaisesNamingIt(bundle: Bundle)
	local Client = bundle.ClientTransport
	local harness = Stubs.ports({})
	Client.init(harness.ports)
	for _, kind in UNKNOWN_KINDS do
		expectRaiseNaming(function()
			Client.on(kind, function() end)
		end, kind, `ClientTransport.on("{kind}")`)
	end
	assert(
		#harness.remoteEventCalls == 0,
		`on with an unknown kind asked ports.remoteEvent {#harness.remoteEventCalls} time(s): `
			.. table.concat(harness.remoteEventCalls, ", ")
	)
end

function TransportContract.clientInitAgainReplacesThePorts(bundle: Bundle)
	local Client = bundle.ClientTransport
	local first = Stubs.ports({})
	local second = Stubs.ports({})
	Client.init(first.ports)
	Client.on("RoundView", function() end)
	Client.init(second.ports)
	Client.on("FacilityView", function() end)
	Client.send("Ping", { token = 1 })

	assert(
		first.events.RoundView ~= nil and #first.events.RoundView.clientConnections == 1,
		"the first ports did not receive the RoundView connection made before the second init"
	)
	assert(
		first.events.FacilityView == nil and first.events.Ping == nil,
		`the first ports were still used after init was called again: `
			.. table.concat(first.remoteEventCalls, ", ")
	)
	assert(
		second.events.FacilityView ~= nil and #second.events.FacilityView.clientConnections == 1,
		"the second ports did not receive the FacilityView connection made after the second init"
	)
	assert(
		second.events.Ping ~= nil and #second.events.Ping.fireServerCalls == 1,
		"the second ports did not receive the send made after the second init"
	)
end

return TransportContract
