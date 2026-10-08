--!strict
--[[
	SLICE-002: the one module on the server allowed to touch a `RemoteEvent`
	(`architecture.md` section 4, D6). It binds every declared remote through
	`Wrapper.guard` and routes server->client payloads by kind, so that the two
	trust rules of M3 are structural rather than remembered:

	EVERY CALL GOES THROUGH THE WRAPPER (AC-1). `bind` connects, per declared
	remote, exactly one function, and that function is the guarded handler and
	nothing else. It RETURNS the guard's result (C-2) - Roblox discards it, but
	it is the only place a `shape` or `identity` rejection is observable from
	outside. The handler is handed to `Wrapper.guard` as is, so the
	`CallControl` the wrapper builds reaches it (C-1): a transport that dropped
	the third argument would make every `call.decline()` unreachable.

	THE RAW PLAYER OBJECT NEVER REACHES THE GUARD (C-3). `ports.idOf` is asked
	once per call, and its answer - a string, or nil for a player this server
	does not know - is the guard's `playerId`. There is NO second identity
	check here: `Wrapper`'s check 1 already rejects a non-string id
	(`describeCaller`), and a second one is a second rule that can drift.

	A DECLARED REMOTE WITHOUT A HANDLER, OR A HANDLER WITHOUT A DECLARATION,
	RAISES (AC-2) before any port is read (C-5): the first is a silently dead
	wire, the second an unvalidated one.

	A PER-PLAYER PAYLOAD IS SENT TO ITS PLAYER ONLY (AC-3, `architecture.md`
	9.7, D13). Each payload kind travels on its own `RemoteEvent`, named by the
	kind, so a client listening for `RoundView` cannot be handed a `LensView`.
	`sendTo` accepts only the private kinds and fires `FireClient`; `broadcast`
	accepts only the public kinds and fires `FireAllClients`. Either one given
	a kind from the other set, or from neither, raises and fires nothing (AC-4,
	C-6). A `playerId` with no player object is a no-op: a player may leave
	between building a view and sending it.

	PORTS ARE READ AT BIND (C-4). Every event - one per declared remote, one
	per kind - is fetched once in `bind`; `sendTo` and `broadcast` use what
	was fetched and never call `ports.remoteEvent`.
]]

local Remotes = require("./Remotes")
local Wrapper = require("./Wrapper")

local Transport = {}

export type PayloadKind =
	-- per-player: sendTo only
	"SeatView"
	| "LensView"
	| "TurnCues"
	| "TurnResult"
	| "PresetFailed"
	| "PingRefused"
	-- public: broadcast only
	| "RoundView"
	| "FacilityView"
	| "PresetShown"
	| "TraceView"

export type RemoteEventLike = {
	OnServerEvent: { Connect: (self: any, fn: (player: any, payload: any) -> ...any) -> any },
	FireClient: (self: any, player: any, payload: any) -> (),
	FireAllClients: (self: any, payload: any) -> (),
}

export type Ports = {
	remoteEvent: (name: string) -> RemoteEventLike,
	idOf: (player: any) -> string?, -- nil: not a player this server knows
	playerFor: (playerId: string) -> any?,
}

export type Bound = {
	sendTo: (self: Bound, playerId: string, kind: PayloadKind, payload: any) -> (),
	broadcast: (self: Bound, kind: PayloadKind, payload: any) -> (),
}

export type Handler = (playerId: Wrapper.PlayerId, args: any, call: Wrapper.CallControl) -> ()

Transport.PRIVATE_KINDS = {
	SeatView = true,
	LensView = true,
	TurnCues = true,
	TurnResult = true,
	PresetFailed = true,
	PingRefused = true,
} :: { [string]: true }

Transport.PUBLIC_KINDS = {
	RoundView = true,
	FacilityView = true,
	PresetShown = true,
	TraceView = true,
} :: { [string]: true }

--[[
	AC-2 / C-5. Both directions, before anything is fetched or connected, and
	each raise names the remote it is about.
]]
local function validate(definitions: { Remotes.RemoteDefinition }, handlers: { [string]: Handler })
	local declared: { [string]: boolean } = {}
	for _, definition in definitions do
		declared[definition.name] = true
		if handlers[definition.name] == nil then
			error(
				`Transport.bind: the remote "{definition.name}" is declared but has no handler; `
					.. `it would be a silently dead wire`,
				3
			)
		end
	end
	for name in handlers do
		if not declared[name] then
			error(
				`Transport.bind: the handler for "{name}" names a remote that is not declared; `
					.. `it would be an unvalidated one`,
				3
			)
		end
	end
end

--[[
	Binds every declared remote through `Wrapper.guard` and returns the
	server->client side. `definitions` and `handlers` must name the same
	remotes, exactly.
]]
function Transport.bind(
	definitions: { Remotes.RemoteDefinition },
	context: Wrapper.GuardContext,
	handlers: { [string]: Handler },
	ports: Ports
): Bound
	validate(definitions, handlers)

	for _, definition in definitions do
		local event = ports.remoteEvent(definition.name)
		local guarded = Wrapper.guard(definition, context, handlers[definition.name])
		event.OnServerEvent:Connect(function(player: any, payload: any): Wrapper.Rejection?
			-- C-3: one lookup, and the guard sees its answer, never `player`.
			-- `idOf` answers nil for a stranger; the guard's identity check
			-- rejects a non-string id, so the cast states what the wire can
			-- carry rather than what the parameter is typed.
			local playerId: any = ports.idOf(player)
			return guarded(playerId, payload)
		end)
	end

	-- C-4: every kind's event, once, here.
	local kindEvents: { [string]: RemoteEventLike } = {}
	for kind in Transport.PRIVATE_KINDS do
		kindEvents[kind] = ports.remoteEvent(kind)
	end
	for kind in Transport.PUBLIC_KINDS do
		kindEvents[kind] = ports.remoteEvent(kind)
	end

	local bound = {}

	function bound.sendTo(_self: Bound, playerId: string, kind: PayloadKind, payload: any)
		if Transport.PRIVATE_KINDS[kind] ~= true then
			error(`Transport.sendTo: "{kind}" is not a per-player payload kind`, 2)
		end
		local player = ports.playerFor(playerId)
		if player == nil then
			return
		end
		kindEvents[kind]:FireClient(player, payload)
	end

	function bound.broadcast(_self: Bound, kind: PayloadKind, payload: any)
		if Transport.PUBLIC_KINDS[kind] ~= true then
			error(`Transport.broadcast: "{kind}" is not a public payload kind`, 2)
		end
		kindEvents[kind]:FireAllClients(payload)
	end

	return bound :: Bound
end

return Transport
