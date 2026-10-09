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
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientTransport = require("@game/ReplicatedStorage/Net/ClientTransport")
local Clock = require("@game/ReplicatedStorage/Shared/Clock")
local PhaseClockModel = require("./models/PhaseClockModel")
local PhaseClockView = require("./views/PhaseClockView")

type Received = { view: PhaseClockModel.View, receivedAt: number }

local clock = Clock.real()
local remotes = ReplicatedStorage:WaitForChild("Remotes")

ClientTransport.init({
	remoteEvent = function(name: string): any
		return remotes:WaitForChild(name)
	end,
})

local localPlayer = Players.LocalPlayer
local view = PhaseClockView.mount(localPlayer:WaitForChild("PlayerGui"))

local last: Received? = nil

local function redraw()
	local received = last
	if received == nil then
		return -- nothing has arrived yet
	end
	view:render(PhaseClockModel.describe(received.view, received.receivedAt, clock.now()))
end

ClientTransport.on("RoundView", function(payload: any)
	last = { view = payload, receivedAt = clock.now() }
	redraw()
end)

RunService.RenderStepped:Connect(redraw)
