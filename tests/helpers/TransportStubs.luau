--!strict
--[[
	The wrong transports SLICE-002's controls are aimed at, and the one
	baseline each of them is a single defect away from.

	THE STORY NAMES TWO CONTROLS. AC-1: "a `bind` that connects the handler
	directly (no guard) must fail this AC" - `bindBypassesGuard`, which is
	also D-1's second mutation. AC-3: "a `sendTo` implemented with
	`FireAllClients` must fail this AC" - `sendToFiresAll`, D-1's first. The
	rest are one-defect transports for the Contract blocks C-1 through C-7
	the remaining checks would otherwise have no control for.

	IT IS A FACTORY OVER A TABLE OF DEFECTS, as `DeclineStubs.luau` and
	`NetStubs.luau` are: `defects` is empty for the baseline and has exactly
	ONE field set for every control, so a control that fires is attributable
	to that one field. Every call to `build` makes a fresh module pair, so the
	client side's "module state with explicit init" (C-7) can be exercised
	from "never initialised" in every control.

	THE FAKES ARE RECORDERS. `fakeRemoteEvent(name)` answers a table with the
	four members the Contract's `RemoteEventLike` needs on the server
	(`OnServerEvent.Connect`, `FireClient`, `FireAllClients`) and the two the
	client needs (`OnClientEvent.Connect`, `FireServer`), each of which
	appends to a list the checks read: which method, which arguments, how
	many times. `ports(players)` builds the Contract's `Ports` over a map of
	player id -> player object, recording every `remoteEvent` and `idOf` call,
	and keeps one fake per name so a repeated `remoteEvent(name)` is counted
	(C-4) rather than hidden.

	THE BASELINE DRIVES THE REAL `Wrapper.guard`. That module is merged, so
	the `shape`, `identity` and `declined` reasons the checks read are the
	wrapper's own and not a stub's guess at them - the one thing the
	transport must get right is to hand the guard the mapped id, the payload
	and the handler, and that is what every defect below breaks in one way.

	WHAT THIS IS NOT: `src/ReplicatedStorage/Net/Transport.luau` or a sketch
	of it. GREEN writes the real modules from the story's `## Contract`,
	against the failing tests in `tests/net/transport_test.luau`; the types
	here are all `any` and the failure strings are whatever fell out. Nothing
	here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/net/transport_controls_test.luau` records
	what each one actually did.
]]

local Wrapper = require("../../src/ReplicatedStorage/Net/Wrapper")

local TransportStubs = {}

TransportStubs.PRIVATE =
	{ "SeatView", "LensView", "TurnCues", "TurnResult", "PresetFailed", "PingRefused" }
TransportStubs.PUBLIC = { "RoundView", "FacilityView", "PresetShown", "TraceView" }

--[[
	One field per control, each a single edit to the baseline below.

	  Transport.bind
	  * `bindBypassesGuard`         - the handler is connected directly, no
	                                  `Wrapper.guard` (AC-1's control; D-1)
	  * `bindConnectsTwice`         - each remote's event gets two connections
	  * `bindAcceptsUnhandled`      - a declared remote with no handler is
	                                  silently skipped (AC-2)
	  * `bindAcceptsUndeclared`     - a handler for an undeclared name is
	                                  silently ignored (AC-2)
	  * `bindReadsPortsFirst`       - the remote events are fetched and
	                                  connected before the AC-2 check (C-5)
	  * `bindRaiseOmitsName`        - the AC-2 raise does not name the remote
	  * `dropsCallControl`          - the handler is called with two
	                                  arguments; `call` is nil (C-1)
	  * `connectedReturnsNil`       - the connected function discards the
	                                  guard's result (C-2)
	  * `passesRawPlayer`           - the raw player object goes to the guard;
	                                  `idOf` is never called (C-3, AC-5)
	  * `idOfCalledTwice`           - `idOf` is consulted twice per call (C-3)
	  * `kindEventsReadLazily`      - the kind events are fetched on first
	                                  send, not at bind (C-4)
	  Bound.sendTo
	  * `sendToFiresAll`            - `FireAllClients` instead of `FireClient`
	                                  (AC-3's control; D-1)
	  * `sendToOnSharedEvent`       - every private kind travels on one event
	                                  (the "own RemoteEvent" clause)
	  * `sendToRaisesWithoutPlayer` - `playerFor` -> nil raises (the no-op
	                                  clause)
	  * `sendToAcceptsPublicKind`   - a public kind is sent with FireClient
	                                  (C-6)
	  * `sendToFiresTwice`          - two FireClient calls per send
	  Bound.broadcast
	  * `broadcastAcceptsPrivate`   - a private kind is broadcast (AC-4)
	  * `broadcastFiresTwice`       - two FireAllClients calls per broadcast
	  * `broadcastOnSharedEvent`    - every public kind travels on one event
	  * `unknownKindAccepted`       - a kind in neither set is sent or
	                                  broadcast on an event of that name (C-6)
	  Kind sets
	  * `privateKindsMissingOne`    - PRIVATE_KINDS lacks PingRefused (AC-4)
	  * `publicKindsHaveExtra`      - PUBLIC_KINDS also holds LensView (AC-4)
	  ClientTransport
	  * `clientNoInitCheck`         - `on`/`send` before `init` index nil
	                                  instead of raising by name (C-7)
	  * `clientOnAcceptsUnknownKind`- `on` connects an event of any name (C-7)
	  * `clientSendWrapsArgs`       - FireServer receives `{ args }` (AC-6)
	  * `clientInitKeepsFirstPorts` - a second `init` is ignored (C-7)
	  * `clientOnSharedEvent`       - every kind's `on` connects one event
]]
TransportStubs.DEFECTS = {
	"bindBypassesGuard",
	"bindConnectsTwice",
	"bindAcceptsUnhandled",
	"bindAcceptsUndeclared",
	"bindReadsPortsFirst",
	"bindRaiseOmitsName",
	"dropsCallControl",
	"connectedReturnsNil",
	"passesRawPlayer",
	"idOfCalledTwice",
	"kindEventsReadLazily",
	"sendToFiresAll",
	"sendToOnSharedEvent",
	"sendToRaisesWithoutPlayer",
	"sendToAcceptsPublicKind",
	"sendToFiresTwice",
	"broadcastAcceptsPrivate",
	"broadcastFiresTwice",
	"broadcastOnSharedEvent",
	"unknownKindAccepted",
	"privateKindsMissingOne",
	"publicKindsHaveExtra",
	"clientNoInitCheck",
	"clientOnAcceptsUnknownKind",
	"clientSendWrapsArgs",
	"clientInitKeepsFirstPorts",
	"clientOnSharedEvent",
}

export type FakeRemoteEvent = {
	name: string,
	serverConnections: { (player: any, payload: any) -> any },
	clientConnections: { (payload: any) -> () },
	fireClientCalls: { { player: any, payload: any } },
	fireAllCalls: { { payload: any } },
	fireServerCalls: { { n: number, args: { any } } },
	OnServerEvent: any,
	OnClientEvent: any,
	FireClient: any,
	FireAllClients: any,
	FireServer: any,
}

export type Harness = {
	ports: any,
	events: { [string]: FakeRemoteEvent },
	remoteEventCalls: { string },
	idOfCalls: { { player: any } },
	playerForCalls: { string },
	players: { [string]: any },
}

-- A recording stand-in for one `RemoteEvent`, both sides at once.
function TransportStubs.fakeRemoteEvent(name: string): FakeRemoteEvent
	local fake: any = {
		name = name,
		serverConnections = {},
		clientConnections = {},
		fireClientCalls = {},
		fireAllCalls = {},
		fireServerCalls = {},
	}
	fake.OnServerEvent = {
		Connect = function(_self: any, fn: any)
			table.insert(fake.serverConnections, fn)
			return { Disconnect = function() end }
		end,
	}
	fake.OnClientEvent = {
		Connect = function(_self: any, fn: any)
			table.insert(fake.clientConnections, fn)
			return { Disconnect = function() end }
		end,
	}
	fake.FireClient = function(_self: any, player: any, payload: any)
		table.insert(fake.fireClientCalls, { player = player, payload = payload })
	end
	fake.FireAllClients = function(_self: any, payload: any)
		table.insert(fake.fireAllCalls, { payload = payload })
	end
	fake.FireServer = function(_self: any, ...: any)
		table.insert(fake.fireServerCalls, { n = select("#", ...), args = { ... } })
	end
	return fake :: FakeRemoteEvent
end

--[[
	The Contract's `Ports` over a map of player id -> player object. `idOf`
	answers the id of an object in the map and nil for anything else;
	`playerFor` answers the object. Every call to all three is recorded.
]]
function TransportStubs.ports(players: { [string]: any }): Harness
	local events: { [string]: FakeRemoteEvent } = {}
	local remoteEventCalls: { string } = {}
	local idOfCalls: { { player: any } } = {}
	local playerForCalls: { string } = {}
	local byObject: { [any]: string } = {}
	for id, object in players do
		byObject[object] = id
	end
	local ports = {
		remoteEvent = function(name: string): any
			table.insert(remoteEventCalls, name)
			if events[name] == nil then
				events[name] = TransportStubs.fakeRemoteEvent(name)
			end
			return events[name]
		end,
		idOf = function(player: any): string?
			table.insert(idOfCalls, { player = player })
			return byObject[player]
		end,
		playerFor = function(playerId: string): any
			table.insert(playerForCalls, playerId)
			return players[playerId]
		end,
	}
	return {
		ports = ports,
		events = events,
		remoteEventCalls = remoteEventCalls,
		idOfCalls = idOfCalls,
		playerForCalls = playerForCalls,
		players = players,
	}
end

local function setOf(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, item in list do
		set[item] = true
	end
	return set
end

local function build(defects: { [string]: boolean }): any
	local privateKinds = setOf(TransportStubs.PRIVATE)
	local publicKinds = setOf(TransportStubs.PUBLIC)
	if defects.privateKindsMissingOne then
		privateKinds.PingRefused = nil
	end
	if defects.publicKindsHaveExtra then
		publicKinds.LensView = true
	end
	local allKinds: { string } = {}
	for _, kind in TransportStubs.PRIVATE do
		table.insert(allKinds, kind)
	end
	for _, kind in TransportStubs.PUBLIC do
		table.insert(allKinds, kind)
	end

	local Transport: any = {}
	Transport.PRIVATE_KINDS = privateKinds
	Transport.PUBLIC_KINDS = publicKinds

	local function validate(definitions: { any }, handlers: { [string]: any })
		local declared: { [string]: boolean } = {}
		for _, definition in definitions do
			declared[definition.name] = true
			if handlers[definition.name] == nil and not defects.bindAcceptsUnhandled then
				if defects.bindRaiseOmitsName then
					error("Transport.bind: a declared remote has no handler", 2)
				end
				error(
					`Transport.bind: the remote "{definition.name}" is declared but has no handler`,
					2
				)
			end
		end
		if not defects.bindAcceptsUndeclared then
			for name in handlers do
				if not declared[name] then
					if defects.bindRaiseOmitsName then
						error("Transport.bind: a handler names a remote that is not declared", 2)
					end
					error(
						`Transport.bind: the handler for "{name}" names a remote that is not declared`,
						2
					)
				end
			end
		end
	end

	function Transport.bind(
		definitions: { any },
		context: any,
		handlers: { [string]: any },
		ports: any
	): any
		if not defects.bindReadsPortsFirst then
			validate(definitions, handlers)
		end

		for _, definition in definitions do
			local event = ports.remoteEvent(definition.name)
			local handler = handlers[definition.name]
			if handler == nil then
				continue
			end
			local connected: any
			if defects.bindBypassesGuard then
				connected = function(player: any, payload: any)
					local playerId = ports.idOf(player)
					return handler(playerId, payload, { decline = function() end })
				end
			else
				local inner = handler
				if defects.dropsCallControl then
					inner = function(playerId: any, args: any)
						handler(playerId, args)
					end
				end
				local guarded = Wrapper.guard(definition, context, inner)
				connected = function(player: any, payload: any)
					local playerId: any
					if defects.passesRawPlayer then
						playerId = player
					else
						playerId = ports.idOf(player)
						if defects.idOfCalledTwice then
							playerId = ports.idOf(player)
						end
					end
					local result = guarded(playerId, payload)
					if defects.connectedReturnsNil then
						return nil
					end
					return result
				end
			end
			event.OnServerEvent:Connect(connected)
			if defects.bindConnectsTwice then
				event.OnServerEvent:Connect(connected)
			end
		end

		if defects.bindReadsPortsFirst then
			validate(definitions, handlers)
		end

		local kindEvents: { [string]: any } = {}
		if not defects.kindEventsReadLazily then
			for _, kind in allKinds do
				kindEvents[kind] = ports.remoteEvent(kind)
			end
		end
		local function eventFor(kind: string): any
			if kindEvents[kind] == nil then
				kindEvents[kind] = ports.remoteEvent(kind)
			end
			return kindEvents[kind]
		end

		local bound: any = {}

		function bound.sendTo(_self: any, playerId: string, kind: string, payload: any)
			local allowed = privateKinds[kind] == true
			if defects.sendToAcceptsPublicKind and publicKinds[kind] then
				allowed = true
			end
			if defects.unknownKindAccepted and not publicKinds[kind] then
				allowed = true
			end
			if not allowed then
				error(`Transport.sendTo: "{kind}" is not a per-player payload kind`, 2)
			end
			local player = ports.playerFor(playerId)
			if player == nil then
				if defects.sendToRaisesWithoutPlayer then
					error(`Transport.sendTo: no player for "{playerId}"`, 2)
				end
				return
			end
			local event = if defects.sendToOnSharedEvent
				then eventFor("SeatView")
				else eventFor(kind)
			if defects.sendToFiresAll then
				event:FireAllClients(payload)
				return
			end
			event:FireClient(player, payload)
			if defects.sendToFiresTwice then
				event:FireClient(player, payload)
			end
		end

		function bound.broadcast(_self: any, kind: string, payload: any)
			local allowed = publicKinds[kind] == true
			if defects.broadcastAcceptsPrivate and privateKinds[kind] then
				allowed = true
			end
			if defects.unknownKindAccepted and not privateKinds[kind] then
				allowed = true
			end
			if not allowed then
				error(`Transport.broadcast: "{kind}" is not a public payload kind`, 2)
			end
			local event = if defects.broadcastOnSharedEvent
				then eventFor("RoundView")
				else eventFor(kind)
			event:FireAllClients(payload)
			if defects.broadcastFiresTwice then
				event:FireAllClients(payload)
			end
		end

		return bound
	end

	-- The client side: module state with explicit init (C-7), fresh per build.
	local ClientTransport: any = {}
	local clientPorts: any = nil

	function ClientTransport.init(ports: any)
		if defects.clientInitKeepsFirstPorts and clientPorts ~= nil then
			return
		end
		clientPorts = ports
	end

	function ClientTransport.on(kind: string, fn: (any) -> ())
		if clientPorts == nil and not defects.clientNoInitCheck then
			error("ClientTransport.on: called before ClientTransport.init", 2)
		end
		if not defects.clientOnAcceptsUnknownKind then
			if privateKinds[kind] ~= true and publicKinds[kind] ~= true then
				error(`ClientTransport.on: "{kind}" is not a payload kind`, 2)
			end
		end
		local name = if defects.clientOnSharedEvent then "RoundView" else kind
		clientPorts.remoteEvent(name).OnClientEvent:Connect(fn)
	end

	function ClientTransport.send(remoteName: string, args: any)
		if clientPorts == nil and not defects.clientNoInitCheck then
			error("ClientTransport.send: called before ClientTransport.init", 2)
		end
		local event = clientPorts.remoteEvent(remoteName)
		if defects.clientSendWrapsArgs then
			event:FireServer({ args })
			return
		end
		event:FireServer(args)
	end

	return { Transport = Transport, ClientTransport = ClientTransport }
end

-- The baseline: every Contract clause met, as far as the checks can see.
function TransportStubs.correct(): any
	return build({})
end

-- The baseline with exactly one of `DEFECTS` applied.
function TransportStubs.with(defect: string): any
	assert(table.find(TransportStubs.DEFECTS, defect) ~= nil, `no such defect: {defect}`)
	return build({ [defect] = true })
end

return TransportStubs
