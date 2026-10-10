--!strict
--[[
	HUD-007: the lobby panel (C-26) - who is here, whether there are enough,
	and the state's glyph. There is no ready toggle.

	IMPURE AND STUDIO-VERIFIED (D-1). `models/LobbyModel.luau` decides what
	is shown; this view draws its Description, centred (`layout.md` §4):

	    slots   a row of `size.chip.player` circles. Needed slots have a
	            solid `stroke.control` border, optional ones a dashed one -
	            shape, not colour, not words (DN-2). A filled slot is the
	            player's portrait: the headshot in a `stroke.player` ring,
	            or the hue circle while loading and on error
	            (`RelationsStripView.portrait`, never a broken image).
	    glyph   the state's (`glyph.wait` below players_min, while the
	            countdown holds), as a placeholder TextLabel of the key.
	    words   `Words.lobby.alone` when exactly one player is present.

	The countdown itself is the phase clock's (SLICE-004); this panel does
	not restate it. Nothing here is `Active` or `Selectable`.
]]

local LobbyModel = require("../models/LobbyModel")
local RelationsStripView = require("./RelationsStripView")
local Theme = require("../Theme")
local Words = require("../Words")

export type LobbyPanelView = {
	render: (self: LobbyPanelView, description: LobbyModel.Description) -> (),
	hide: (self: LobbyPanelView) -> (),
}

local PANEL_WIDTH, PANEL_HEIGHT = 560, 320 -- layout.md §4, the maximum

local LobbyPanelView = {}

local function slotFrame(slot: LobbyModel.Slot, index: number): Frame
	local diameter = Theme.size["size.chip.player"].x
	local playerId, hueToken = slot.playerId, slot.hueToken
	local frame: Frame
	if playerId ~= nil and hueToken ~= nil then
		frame = RelationsStripView.portrait(playerId, hueToken, diameter)
	elseif slot.needed then
		frame = RelationsStripView.solidCircle(diameter)
	else
		frame = RelationsStripView.dashedCircle(diameter)
	end
	frame.Name = `Slot{index}`
	frame.LayoutOrder = index
	return frame
end

-- Builds the panel under `playerGui`, hidden until the first render.
function LobbyPanelView.mount(playerGui: Instance): LobbyPanelView
	local surface = Theme.color["color.surface.scrim"]
	local text = Theme.color["color.text.primary"]

	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyPanel"
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local panel = RelationsStripView.frame("Panel", UDim2.fromOffset(PANEL_WIDTH, 0))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = surface.transparency or 0
	panel.BackgroundColor3 = Color3.fromHex(surface.hex)
	panel.Parent = gui
	gui.Parent = playerGui

	local view = {}

	function view.render(_self: LobbyPanelView, description: LobbyModel.Description)
		panel:ClearAllChildren()
		local constraint = Instance.new("UISizeConstraint")
		constraint.MaxSize = Vector2.new(PANEL_WIDTH, PANEL_HEIGHT)
		constraint.Parent = panel
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = panel

		local glyph =
			RelationsStripView.glyph(description.glyph, Theme.size["size.icon.hud"].x, false)
		glyph.LayoutOrder = 1
		glyph.Parent = panel

		local row = RelationsStripView.frame("Slots", UDim2.fromOffset(0, 0))
		row.AutomaticSize = Enum.AutomaticSize.XY
		row.LayoutOrder = 2
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 12)
		rowLayout.Parent = row
		local present = 0
		for index, slot in description.slots do
			if slot.playerId ~= nil then
				present += 1
			end
			slotFrame(slot, index).Parent = row
		end
		row.Parent = panel

		if present == 1 then
			local words = Instance.new("TextLabel")
			words.Name = "Words"
			words.AutomaticSize = Enum.AutomaticSize.X
			words.Size = UDim2.fromOffset(0, Theme.type["type.label"] + 8)
			words.BackgroundTransparency = 1
			words.Text = Words.lobby.alone
			words.TextSize = Theme.type["type.label"]
			words.TextColor3 = Color3.fromHex(text.hex)
			words.LayoutOrder = 3
			words.Parent = panel
		end
		gui.Enabled = true
	end

	function view.hide(_self: LobbyPanelView)
		gui.Enabled = false
	end

	return view :: LobbyPanelView
end

return LobbyPanelView
