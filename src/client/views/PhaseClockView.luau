--!strict
--[[
	SLICE-004: the phase clock on screen - one `TextLabel` on its own
	`ScreenGui`, showing the phase word beside its countdown.

	IMPURE AND STUDIO-VERIFIED (D-2). Nothing here decides what to say:
	`models/PhaseClockModel.luau` does, and this view draws its `Description`.
	Colours and sizes come from `Theme` (THEME-001), never a literal: the
	label is the primary text colour on the scrim surface, at the title type
	size, no shorter than the minimum target height.

	`voice.md` §2.1 calls this label provisional: a HUD story replaces it.
]]

local PhaseClockModel = require("../models/PhaseClockModel")
local Theme = require("../Theme")

export type PhaseClockView = {
	render: (self: PhaseClockView, description: PhaseClockModel.Description) -> (),
}

local PhaseClockView = {}

local function textOf(description: PhaseClockModel.Description): string
	if description.countdown == nil then
		return description.phaseKey
	end
	return `{description.phaseKey}  {description.countdown}`
end

-- Builds the label under `playerGui` and returns the handle that redraws it.
function PhaseClockView.mount(playerGui: Instance): PhaseClockView
	local surface = Theme.color["color.surface.scrim"]
	local text = Theme.color["color.text.primary"]
	local minTarget = Theme.size["size.target.min"]

	local gui = Instance.new("ScreenGui")
	gui.Name = "PhaseClock"
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Name = "PhaseClockLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0)
	label.Size = UDim2.fromOffset(0, minTarget.y)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = Color3.fromHex(surface.hex)
	label.BackgroundTransparency = surface.transparency or 0
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromHex(text.hex)
	label.TextTransparency = text.transparency or 0
	label.TextSize = Theme.type["type.title"]
	label.Text = ""

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, minTarget.x / 4)
	padding.PaddingRight = UDim.new(0, minTarget.x / 4)
	padding.Parent = label

	label.Parent = gui
	gui.Parent = playerGui

	local view = {}

	function view.render(_self: PhaseClockView, description: PhaseClockModel.Description)
		label.Text = textOf(description)
	end

	return view :: PhaseClockView
end

return PhaseClockView
