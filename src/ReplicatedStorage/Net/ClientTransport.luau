--!strict
--[[
	SLICE-002: the client half of `Transport`, and the one module on the
	client allowed to touch a `RemoteEvent` (`architecture.md` section 4, D6;
	`tests/net/raw_remote_guard_test.luau` forbids `.OnClientEvent` anywhere
	outside `src/ReplicatedStorage/Net/`).

	EACH PAYLOAD KIND HAS ITS OWN EVENT, as on the server: `on(kind, fn)`
	listens on the event named by the kind and nothing else, so a listener for
	`RoundView` is never handed a `LensView`. A kind in neither of
	`Transport`'s sets raises - a typo would otherwise be a listener that never
	fires.

	`send(remoteName, args)` fires the remote's event with `args` as the ONE
	payload, which is the shape `Wrapper.guard` validates on the other side.
	The client does not validate: the server does not trust it anyway.

	MODULE STATE WITH EXPLICIT INIT (C-7). The ports arrive through `init` so
	the tests can pass fakes; `on` or `send` before `init` raises naming the
	call, and a second `init` replaces the ports outright.

	The kind sets are `Transport`'s own (C-7 permits the require), so the two
	sides cannot disagree about what a kind is.
]]

local Transport = require("./Transport")

local ClientTransport = {}

export type Ports = {
	remoteEvent: (name: string) -> any,
}

local ports: Ports? = nil

local function portsFor(call: string): Ports
	if ports == nil then
		error(`{call}: called before ClientTransport.init`, 3)
	end
	return ports
end

function ClientTransport.init(newPorts: Ports)
	ports = newPorts
end

function ClientTransport.on(kind: Transport.PayloadKind, fn: (payload: any) -> ())
	local current = portsFor("ClientTransport.on")
	if Transport.PRIVATE_KINDS[kind] ~= true and Transport.PUBLIC_KINDS[kind] ~= true then
		error(`ClientTransport.on: "{kind}" is not a payload kind`, 2)
	end
	current.remoteEvent(kind).OnClientEvent:Connect(fn)
end

function ClientTransport.send(remoteName: string, args: any)
	local current = portsFor("ClientTransport.send")
	current.remoteEvent(remoteName):FireServer(args)
end

return ClientTransport
