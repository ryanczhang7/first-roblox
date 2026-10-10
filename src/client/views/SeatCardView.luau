--!strict
--[[
	HUD-007: the seat card (C-05). At the deal it shows, centred,
	`[helper, eye] -> [you, large] -> [partner, key]` and under it the two
	sample machines - yours (your hue, key) and the ones you can see (your
	partner's hue, eye) - with `voice.md`'s optional words under each.

	IMPURE AND STUDIO-VERIFIED (D-1). `models/SeatCardModel.luau` decides
	what is shown; this view draws its Description. People are drawn with
	`RelationsStripView.portrait`, so loading and error are the hue circle,
	"as C-04", and never a broken image.

	IT NEVER BLOCKS INPUT. The round clock is already running, so the card
	collapses after `design.seat_card_seconds` or on the first tap, click,
	Esc, `ButtonB` or movement input, whichever comes first. It LISTENS to
	`UserInputService` and binds nothing: no ContextActionService action, no
	`Active` or `Selectable` GuiObject, so the input that dismisses it still
	reaches the game.

	`design.seat_card_seconds` is `tokens.md` §7's 4 s. Theme carries no
	`design.*` table, so it is named here, with the token's name.
]]

local UserInputService = game:GetService("UserInputService")

local RelationsStripView = require("./RelationsStripView")
local SeatCardModel = require("../models/SeatCardModel")
local Theme = require("../Theme")
local Words = require("../Words")

export type SeatCardView = {
	show: (self: SeatCardView, description: SeatCardModel.Description) -> (),
	collapse: (self: SeatCardView) -> (),
}

local SEAT_CARD_SECONDS = 4 -- tokens.md §7 `design.seat_card_seconds`
local CARD_WIDTH, CARD_HEIGHT = 480, 200 -- layout.md §4
local STICK_DEADZONE = 0.2

local DISMISS_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Escape] = true,
	[Enum.KeyCode.ButtonB] = true,
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Space] = true,
}

local DISMISS_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.Touch] = true,
}

local SeatCardView = {}

local function dismisses(input: InputObject): boolean
	if DISMISS_TYPES[input.UserInputType] then
		return true
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		return input.Position.Magnitude > STICK_DEADZONE
	end
	return DISMISS_KEYS[input.KeyCode] == true
end

local function words(text: string, order: number, width: number): TextLabel
	local colour = Theme.color["color.text.primary"]
	local label = Instance.new("TextLabel")
	label.Name = "Words"
	label.Size = UDim2.fromOffset(width, Theme.type["type.label"] + 4)
	label.BackgroundTransparency = 1
	label.Active = false
	label.Selectable = false
	label.Text = text
	label.TextSize = Theme.type["type.label"]
	label.TextColor3 = Color3.fromHex(colour.hex)
	label.LayoutOrder = order
	return label
end

local function column(name: string, order: number): Frame
	local frame = RelationsStripView.frame(name, UDim2.fromOffset(0, 0))
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

local function row(name: string, order: number, padding: number): Frame
	local frame = RelationsStripView.frame(name, UDim2.fromOffset(0, 0))
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = frame
	return frame
end

local function person(
	name: string,
	who: SeatCardModel.Person,
	diameter: number,
	label: string,
	order: number
): Frame
	local holder = column(name, order)
	local top = row("Top", 1, 4)
	top.Parent = holder
	local portrait = RelationsStripView.portrait(who.playerId, who.hueToken, diameter)
	portrait.LayoutOrder = 1
	portrait.Parent = top
	local glyph = who.glyph
	if glyph ~= nil then
		local glyphLabel = RelationsStripView.glyph(glyph, Theme.size["size.icon.hud"].x, false)
		glyphLabel.LayoutOrder = 2
		glyphLabel.Parent = top
	end
	words(label, 2, diameter * 2).Parent = holder
	return holder
end

-- A sample machine: a housing tile trimmed in the sample's hue, with its glyph.
local function sample(
	name: string,
	which: SeatCardModel.Sample,
	label: string,
	order: number
): Frame
	local tile = Theme.size["size.icon.tile"].x
	local holder = column(name, order)
	local machine = RelationsStripView.frame("Machine", UDim2.fromOffset(tile, tile))
	machine.BackgroundTransparency = 0
	machine.BackgroundColor3 = Color3.fromHex(Theme.color["color.world.housing"].hex)
	machine.LayoutOrder = 1
	local trim = Instance.new("UIStroke")
	trim.Thickness = 3
	trim.Color = Color3.fromHex(Theme.color[which.hueToken].hex)
	trim.Parent = machine
	local glyphLabel = RelationsStripView.glyph(which.glyph, tile, false)
	glyphLabel.Parent = machine
	machine.Parent = holder
	words(label, 2, CARD_WIDTH / 2 - 16).Parent = holder
	return holder
end

local function arrow(order: number): TextLabel
	local label = RelationsStripView.glyph("glyph.next", Theme.size["size.icon.hud"].x, false)
	label.Name = "Arrow"
	label.Text = ">"
	label.LayoutOrder = order
	return label
end

-- Builds the card under `playerGui`, hidden until `show`.
function SeatCardView.mount(playerGui: Instance): SeatCardView
	local surface = Theme.color["color.surface.raised"]
	local gui = Instance.new("ScreenGui")
	gui.Name = "SeatCard"
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local card = RelationsStripView.frame("Card", UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT))
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundTransparency = surface.transparency or 0
	card.BackgroundColor3 = Color3.fromHex(surface.hex)
	card.Parent = gui
	gui.Parent = playerGui

	local generation = 0
	local connections: { RBXScriptConnection } = {}

	local view = {}

	local function stopListening()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	function view.collapse(_self: SeatCardView)
		generation += 1
		stopListening()
		gui.Enabled = false
	end

	function view.show(self: SeatCardView, description: SeatCardModel.Description)
		card:ClearAllChildren()
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = card

		local chip = Theme.size["size.chip.player"].x
		local people = row("People", 1, 8)
		person("Helper", description.helper, chip, Words.seat.helper, 1).Parent = people
		arrow(2).Parent = people
		person("You", description.you, chip * 1.5, Words.seat.you, 3).Parent = people
		arrow(4).Parent = people
		person("Partner", description.partner, chip, Words.seat.partner, 5).Parent = people
		people.Parent = card

		local samples = row("Samples", 2, 16)
		local labels = { Words.seat.yours, Words.seat.theirs }
		for i, which in description.samples do
			sample(`Sample{i}`, which, labels[i] or "", i).Parent = samples
		end
		samples.Parent = card

		generation += 1
		local mine = generation
		stopListening()
		local function onInput(input: InputObject)
			if dismisses(input) then
				self:collapse()
			end
		end
		-- Began for presses and keys; Changed for the movement stick.
		table.insert(connections, UserInputService.InputBegan:Connect(onInput))
		table.insert(connections, UserInputService.InputChanged:Connect(onInput))
		task.delay(SEAT_CARD_SECONDS, function()
			if generation == mine then
				self:collapse()
			end
		end)
		gui.Enabled = true
	end

	return view :: SeatCardView
end

return SeatCardView
