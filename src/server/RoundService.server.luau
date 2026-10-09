--!strict
--[[
	SLICE-004: the driver (`architecture.md` §9.1, §9.6). Impure and
	LOGIC-FREE: it builds the real ports, feeds runtime events into the pure
	`Session.step`, and hands every step's effects to `Interpreter.perform`.
	Every `if` here concerns the runtime, never a game rule; a game decision
	found here belongs in `Session`.

	THE PORTS, per the story's PO decisions:
	  - `Clock.real()`, read through one offset so that `now` starts at 0 when
	    this script starts. `PhaseMachine.initial` enters the first Lobby at 0
	    because it takes no `now`; a clock with a different epoch would make
	    the first lobby's dwell already elapsed.
	  - `Sink.noop()`, dispatched through `Sink.dispatch` (M5 brings a sink).
	  - a `RoundConfig` from `Tuning`.
	  - P-2: `Transport.bind({}, context, {}, ports)` - no game remote is bound
	    here (SLICE-007 owns that). Binding creates one `RemoteEvent` per
	    payload kind under `ReplicatedStorage.Remotes`, before any player can
	    join.
	  - P-3: `lineOfSight` is a stub that sees nothing, until SLICE-007.
	  - P-1: `place`, `promptRematch` and `computeTrace` are no-op ports.

	EVENTS: `PlayerJoined` / `PlayerLeft` from `Players`, and a `Tick` on the
	first `RunService.Heartbeat` of each whole second of `now` (P-5): `Session`
	is built for a per-second `Tick`, and broadcasts `RoundView` on each one in
	a timed phase. Player ids are `tostring(player.UserId)`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require("@game/ReplicatedStorage/Shared/Clock")
local Interpreter = require("./session/Interpreter")
local RoundConfig = require("./round/RoundConfig")
local Session = require("./session/Session")
local Sink = require("@game/ReplicatedStorage/Shared/telemetry/Sink")
local Transport = require("@game/ReplicatedStorage/Net/Transport")
local Tuning = require("@game/ReplicatedStorage/Shared/Tuning")
local Wrapper = require("@game/ReplicatedStorage/Net/Wrapper")

local REMOTES_FOLDER = "Remotes"
local FIRST_ROUND_ID = "1"
local STUDIO_SESSION_ID = "studio" -- `game.JobId` is empty in Studio
local MICROSECONDS_PER_SECOND = 1e6

local real = Clock.real()
local startedAt = real.now()
local clock: Clock.Clock = {
	now = function(): number
		return real.now() - startedAt
	end,
}

local sink = Sink.noop()
local config = RoundConfig.fromTuning(Tuning)
local sessionId = if game.JobId ~= "" then game.JobId else STUDIO_SESSION_ID

-- The seed comes from the one real time source the source guard permits, in
-- whole microseconds: `Rng` floors its seed, and whole seconds since process
-- start would hand most servers the same handful of seeds.
local seed = math.floor(startedAt * MICROSECONDS_PER_SECOND)

local state = Session.new(config, seed, FIRST_ROUND_ID, sessionId, {
	lineOfSight = function(_from, _to): boolean
		return false -- P-3: no sight until SLICE-007
	end,
})

local function idOf(player: Player): string
	return tostring(player.UserId)
end

local remotes = Instance.new("Folder")
remotes.Name = REMOTES_FOLDER
remotes.Parent = ReplicatedStorage

local transportPorts: Transport.Ports = {
	remoteEvent = function(name: string): Transport.RemoteEventLike
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = remotes
		return event :: any
	end,
	idOf = function(player: any): string?
		if typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players then
			return idOf(player)
		end
		return nil -- not a player this server knows
	end,
	playerFor = function(playerId: string): any?
		local userId = tonumber(playerId)
		if userId == nil then
			return nil
		end
		return Players:GetPlayerByUserId(userId)
	end,
}

local context: Wrapper.GuardContext = {
	isSeated = function(playerId: string): boolean
		return table.find(state.round.players, playerId) ~= nil
	end,
	phase = function()
		return state.round.phase
	end,
	clock = clock,
}

local ports: Interpreter.Ports = {
	transport = Transport.bind({}, context, {}, transportPorts),
	emit = function(events)
		Sink.dispatch(sink, events)
	end,
	promptRematch = function() end, -- P-1: the card is driven by RoundView
	computeTrace = function(_roundId: string) end, -- P-1: until TRACE-001
	place = function(_playerId: string, _position) end, -- P-1: until SLICE-007
}

local function feed(event: Session.SessionEvent)
	local effects
	state, effects = Session.step(state, event, clock.now())
	Interpreter.perform(effects, ports)
end

Players.PlayerAdded:Connect(function(player: Player)
	feed({ kind = "PlayerJoined", playerId = idOf(player) })
end)

Players.PlayerRemoving:Connect(function(player: Player)
	feed({ kind = "PlayerLeft", playerId = idOf(player) })
end)

-- A player who arrived before the connections above still joins.
for _, player in Players:GetPlayers() do
	feed({ kind = "PlayerJoined", playerId = idOf(player) })
end

-- P-5: runtime cadence, not a game rule. One `Tick` per whole second of the
-- driver clock, on the first Heartbeat that crosses into it; `Session` decides
-- what a `Tick` means. Nil until the first Heartbeat, so that one ticks.
local lastTickSecond: number? = nil

RunService.Heartbeat:Connect(function()
	local second = math.floor(clock.now())
	if second == lastTickSecond then
		return
	end
	lastTickSecond = second
	feed({ kind = "Tick" })
end)
