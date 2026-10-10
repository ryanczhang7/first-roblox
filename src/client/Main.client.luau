--!strict
--[[
	SLICE-004: the client entry. Impure glue with no game logic, verified in
	Studio (D-2) and read by the `typecheck` and `build` gates (AC-4).

	It waits for the driver's `ReplicatedStorage.Remotes`, initialises
	`ClientTransport` with a port that waits for each kind's event, and
	listens for `RoundView`. Each payload is stamped with the LOCAL time it
	arrived, and the phase clock is redrawn on each payload and on each
	`RenderStepped`, so the countdown runs between the server's broadcasts.

	The time is `Clock.real()`'s: the source guard permits a real time source
	only there, and `PhaseClockModel` takes `now` as an argument.

	HUD-007 adds the seat HUD (D-1, Studio-verified). It listens to `SeatView`
	too, and keeps:

	    seat   the latest SeatView;
	    dealt  the first SeatView after the phase leaves `Lobby` (PO-1, PO-2:
	           "your helper has left" and the hues are read against it). A
	           SeatView that lands while this client still believes `Lobby`
	           (the deal can overtake the RoundView announcing it) becomes
	           `dealt` when the phase leaves. All three reset on `Lobby`.

	The lobby panel shows in `Lobby` and hides otherwise; the seat card shows
	once per deal; the strip renders from `Round` on while a SeatView is held.
	Presence is the headshot fetch state, overridden to `away` when no
	`Player` with that UserId is in `Players` (ids are `tostring(UserId)`).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientTransport = require("@game/ReplicatedStorage/Net/ClientTransport")
local Clock = require("@game/ReplicatedStorage/Shared/Clock")
local Tuning = require("@game/ReplicatedStorage/Shared/Tuning")
local LobbyModel = require("./models/LobbyModel")
local LobbyPanelView = require("./views/LobbyPanelView")
local PhaseClockModel = require("./models/PhaseClockModel")
local PhaseClockView = require("./views/PhaseClockView")
local RelationsModel = require("./models/RelationsModel")
local RelationsStripView = require("./views/RelationsStripView")
local SeatCardModel = require("./models/SeatCardModel")
local SeatCardView = require("./views/SeatCardView")

type Received = { view: PhaseClockModel.View, receivedAt: number }
type SeatViewLike = SeatCardModel.SeatViewLike

-- The phases from which the strip is drawn ("from Round onwards").
local STRIP_PHASES: { [string]: boolean } = { Round = true, Resolution = true, Post = true }

local clock = Clock.real()
local remotes = ReplicatedStorage:WaitForChild("Remotes")

ClientTransport.init({
	remoteEvent = function(name: string): any
		return remotes:WaitForChild(name)
	end,
})

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local view = PhaseClockView.mount(playerGui)
local lobbyPanel = LobbyPanelView.mount(playerGui)
local seatCard = SeatCardView.mount(playerGui)
local strip = RelationsStripView.mount(playerGui)

local last: Received? = nil
local phase: string? = nil
local seat: SeatViewLike? = nil
local dealt: SeatViewLike? = nil
local cardShown = false

local function redraw()
	local received = last
	if received == nil then
		return -- nothing has arrived yet
	end
	view:render(PhaseClockModel.describe(received.view, received.receivedAt, clock.now()))
end

local function isHere(playerId: string): boolean
	local userId = tonumber(playerId)
	return userId ~= nil and Players:GetPlayerByUserId(userId) ~= nil
end

local function presenceFor(current: SeatViewLike): RelationsModel.Presence
	local presence: RelationsModel.Presence = {}
	for _, playerId in { current.supplierId, current.dependentId } do
		if not isHere(playerId) then
			presence[playerId] = "away"
		else
			local state: RelationsStripView.FetchState? = RelationsStripView.fetchState(playerId)
			if state ~= nil then
				presence[playerId] = state
			end
		end
	end
	return presence
end

local function redrawSeat()
	local deal, current = dealt, seat
	if deal == nil or current == nil then
		strip:hide()
		return
	end
	if not cardShown then
		cardShown = true
		seatCard:show(SeatCardModel.describe(deal))
	end
	if phase ~= nil and STRIP_PHASES[phase] then
		strip:render(RelationsModel.describe(current, presenceFor(current), deal))
	else
		strip:hide()
	end
end

local function onRoundView(payload: any)
	local previous = phase
	phase = payload.phase
	if phase == "Lobby" then
		if previous ~= "Lobby" then
			seat, dealt, cardShown = nil, nil, false
			seatCard:collapse()
			strip:hide()
		end
		local playersMin = payload.playersMin or Tuning.session.players_min
		local playersMax = payload.playersMax or Tuning.session.players_max
		lobbyPanel:render(LobbyModel.describe(payload, playersMin, playersMax))
		return
	end
	lobbyPanel:hide()
	if dealt == nil and seat ~= nil then
		dealt = seat -- the deal overtook the RoundView that left Lobby
	end
	redrawSeat()
end

ClientTransport.on("RoundView", function(payload: any)
	last = { view = payload, receivedAt = clock.now() }
	redraw()
	onRoundView(payload)
end)

ClientTransport.on("SeatView", function(payload: any)
	seat = payload
	if dealt == nil and phase ~= nil and phase ~= "Lobby" then
		dealt = payload
	end
	redrawSeat()
end)

-- A headshot arriving, or a relation leaving or rejoining, changes presence.
RelationsStripView.onFetchState(function()
	redrawSeat()
end)
Players.PlayerAdded:Connect(function()
	redrawSeat()
end)
Players.PlayerRemoving:Connect(function()
	task.defer(redrawSeat) -- the leaver is still in Players while this fires
end)

RunService.RenderStepped:Connect(redraw)
