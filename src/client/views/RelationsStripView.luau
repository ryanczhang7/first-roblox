--!strict
--[[
	HUD-007: the relations strip (C-04) - helper chip, arrow, you swatch,
	arrow, partner chip - in region A for the whole round, so nothing about
	who helps whom has to be remembered (`loop.md` §1a).

	IMPURE AND STUDIO-VERIFIED (D-1). Nothing here decides what to show:
	`models/RelationsModel.luau` does, and this view draws its Description.
	It is not a control and not a focus stop: nothing in it is `Selectable`
	or `Active`, so focus navigation skips it and input passes through.

	THE PORTRAIT LIVES HERE. C-05 and C-26 draw their people "as C-04"
	(`components.md`), so the chip drawing - a hue circle with a
	`stroke.player` ring, the headshot over it once fetched - and the
	headshot cache are exported for `SeatCardView` and `LobbyPanelView`:

	    headshots   `Players:GetUserThumbnailAsync` inside `pcall`, at most
	                once per player id for the life of the client. A failure
	                is `error` and leaves the hue circle showing; the image is
	                assigned only from a successful fetch, so there is never a
	                broken image.
	    onFetchState(fn)  fn(playerId, state) on every change of an id's
	                fetch state (loading -> present | error), deferred, so a
	                listener that re-renders never re-enters a render. The
	                client entry builds `presence` from it.

	Stroke widths are `tokens.md` §6 (`stroke.player` 3 px, `stroke.control`
	2 px): Theme carries colours, not widths, so they are named here.
	Glyphs are drawn as their Theme icon key in a placeholder TextLabel (M3:
	the key, not the art, is the decision). States per DN-5..DN-8: `away` is
	the chip at 50% opacity with its overlay glyph over it; a struck glyph
	carries a slash; `none` is a dashed `stroke.control` circle.
]]

local Players = game:GetService("Players")

local RelationsModel = require("../models/RelationsModel")
local Theme = require("../Theme")

export type FetchState = "loading" | "present" | "error"

export type RelationsStripView = {
	render: (self: RelationsStripView, description: RelationsModel.Description) -> (),
	hide: (self: RelationsStripView) -> (),
}

local STROKE_PLAYER_PX = 3 -- tokens.md §6 `stroke.player`
local STROKE_CONTROL_PX = 2 -- tokens.md §6 `stroke.control`
local AWAY_TRANSPARENCY = 0.5 -- C-04 `away`: the chip at 50% opacity
local DASHES = 8 -- dots around a dashed circle

local RelationsStripView = {}

--[[ Headshots ]]

type Entry = { state: FetchState, image: string?, waiters: { (image: string?) -> () } }

local entries: { [string]: Entry } = {}
local listeners: { (playerId: string, state: FetchState) -> () } = {}

local function announce(playerId: string, state: FetchState)
	for _, listener in listeners do
		task.defer(listener, playerId, state)
	end
end

local function fetch(playerId: string, entry: Entry)
	local userId = tonumber(playerId)
	local ok, image = false, nil
	if userId ~= nil then
		ok, image = pcall(function(): string
			local content = Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
			return content
		end)
	end
	if ok and typeof(image) == "string" and image ~= "" then
		entry.state = "present"
		entry.image = image
	else
		entry.state = "error"
		entry.image = nil
	end
	local waiters = entry.waiters
	entry.waiters = {}
	for _, waiter in waiters do
		waiter(entry.image)
	end
	announce(playerId, entry.state)
end

-- Calls `onImage` with the headshot once it is known (nil on failure): now if
-- it already is, otherwise when the one fetch for this id completes.
local function headshot(playerId: string, onImage: (image: string?) -> ())
	local entry = entries[playerId]
	if entry == nil then
		local fresh: Entry = { state = "loading", image = nil, waiters = { onImage } }
		entries[playerId] = fresh
		announce(playerId, "loading")
		task.spawn(fetch, playerId, fresh)
	elseif entry.state == "loading" then
		table.insert(entry.waiters, onImage)
	else
		onImage(entry.image)
	end
end

-- Subscribes to every fetch-state change, for the client entry's `presence`.
function RelationsStripView.onFetchState(listener: (playerId: string, state: FetchState) -> ())
	table.insert(listeners, listener)
end

-- The fetch state of `playerId` so far; nil if nothing has asked for it.
function RelationsStripView.fetchState(playerId: string): FetchState?
	local entry = entries[playerId]
	return if entry ~= nil then entry.state else nil
end

--[[ Drawing, shared with C-05 and C-26 ]]

local function hex(token: string): Color3
	return Color3.fromHex(Theme.color[token].hex)
end

local function round(gui: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = gui
end

-- A transparent, inert frame: never selectable, never sinks input.
function RelationsStripView.frame(name: string, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Selectable = false
	return frame
end

-- A glyph, drawn as its Theme icon key (placeholder art), optionally struck through.
function RelationsStripView.glyph(key: string, size: number, struck: boolean): TextLabel
	local text = Theme.color["color.text.primary"]
	local label = Instance.new("TextLabel")
	label.Name = key
	label.Size = UDim2.fromOffset(size, size)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Active = false
	label.Selectable = false
	label.Text = key
	label.TextScaled = true
	label.TextColor3 = Color3.fromHex(text.hex)
	if struck then
		local slash = Instance.new("Frame")
		slash.Name = "Struck"
		slash.AnchorPoint = Vector2.new(0.5, 0.5)
		slash.Position = UDim2.fromScale(0.5, 0.5)
		slash.Size = UDim2.new(1.2, 0, 0, STROKE_PLAYER_PX)
		slash.Rotation = -45
		slash.BackgroundColor3 = Color3.fromHex(text.hex)
		slash.BorderSizePixel = 0
		slash.Parent = label
	end
	return label
end

-- A dashed `stroke.control` circle of `diameter`: dots around the rim.
function RelationsStripView.dashedCircle(diameter: number): Frame
	local ring = RelationsStripView.frame("Dashed", UDim2.fromOffset(diameter, diameter))
	local radius = diameter / 2
	for i = 1, DASHES do
		local angle = (i - 1) * 2 * math.pi / DASHES
		local dot = Instance.new("Frame")
		dot.Name = `Dash{i}`
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position =
			UDim2.fromOffset(radius + radius * math.cos(angle), radius + radius * math.sin(angle))
		dot.Size = UDim2.fromOffset(STROKE_CONTROL_PX * 2, STROKE_CONTROL_PX * 2)
		dot.BackgroundColor3 = hex("color.stroke.control")
		dot.BorderSizePixel = 0
		dot.Parent = ring
		round(dot)
	end
	return ring
end

-- A solid `stroke.control` circle of `diameter`, empty inside.
function RelationsStripView.solidCircle(diameter: number): Frame
	local ring = RelationsStripView.frame("Solid", UDim2.fromOffset(diameter, diameter))
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = STROKE_CONTROL_PX
	stroke.Color = hex("color.stroke.control")
	stroke.Parent = ring
	round(ring)
	return ring
end

--[[
	A person: a filled circle in their hue with a `stroke.player` ring, and
	the headshot over it once fetched. Loading and error show the hue circle
	alone (C-04); the image is set only from a successful fetch.
]]
function RelationsStripView.portrait(playerId: string, hueToken: string, diameter: number): Frame
	local circle =
		RelationsStripView.frame(`Portrait{playerId}`, UDim2.fromOffset(diameter, diameter))
	circle.BackgroundTransparency = 0
	circle.BackgroundColor3 = hex(hueToken)
	round(circle)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = STROKE_PLAYER_PX
	stroke.Color = hex(hueToken)
	stroke.Parent = circle

	local image = Instance.new("ImageLabel")
	image.Name = "Headshot"
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Active = false
	image.Selectable = false
	image.Visible = false
	image.Parent = circle
	round(image)

	headshot(playerId, function(content: string?)
		if content ~= nil and image.Parent ~= nil then
			image.Image = content
			image.Visible = true
		end
	end)
	return circle
end

--[[ The strip ]]

-- The name beside a chip (C-04, `regular`): the player's DisplayName while
-- they are in `Players`, nothing otherwise. Ids are `tostring(UserId)`.
local function nameOf(playerId: string?): string?
	local userId = if playerId ~= nil then tonumber(playerId) else nil
	if userId == nil then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	return if player ~= nil then player.DisplayName else nil
end

local function arrow(order: number): TextLabel
	local label = RelationsStripView.glyph("glyph.next", Theme.size["size.icon.hud"].x / 2, false)
	label.Name = "Arrow"
	label.Text = ">"
	label.LayoutOrder = order
	return label
end

local function chip(
	name: string,
	chipDescription: RelationsModel.Chip,
	order: number,
	label: string?
): Frame
	local diameter = Theme.size["size.chip.player"].x
	local glyphSize = Theme.size["size.icon.hud"].x
	local holder = RelationsStripView.frame(name, UDim2.fromOffset(0, diameter))
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = holder

	local body: Frame
	local playerId, hueToken = chipDescription.playerId, chipDescription.hueToken
	if chipDescription.state == "none" or playerId == nil or hueToken == nil then
		body = RelationsStripView.dashedCircle(diameter)
	else
		body = RelationsStripView.portrait(playerId, hueToken, diameter)
	end
	body.LayoutOrder = 1
	body.Parent = holder

	local glyph = chipDescription.glyph
	if glyph ~= nil then
		local glyphLabel = RelationsStripView.glyph(glyph, glyphSize, chipDescription.struck)
		glyphLabel.LayoutOrder = 2
		glyphLabel.Parent = holder
	end
	local overlay = chipDescription.overlay
	if overlay ~= nil then
		local overlayLabel = RelationsStripView.glyph(overlay, glyphSize, false)
		overlayLabel.Name = "Overlay"
		overlayLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		overlayLabel.Position = UDim2.fromScale(0.5, 0.5)
		overlayLabel.Parent = body
	end
	if label ~= nil then
		local text = Theme.color["color.text.primary"]
		local words = Instance.new("TextLabel")
		words.Name = "Words"
		words.AutomaticSize = Enum.AutomaticSize.X
		words.Size = UDim2.fromOffset(0, diameter)
		words.BackgroundTransparency = 1
		words.Text = label
		words.TextSize = Theme.type["type.caption"]
		words.TextColor3 = Color3.fromHex(text.hex)
		words.LayoutOrder = 3
		words.Parent = holder
	end
	if chipDescription.state == "away" then
		for _, item in holder:GetDescendants() do
			if item:IsA("GuiObject") and item.Name ~= "Overlay" and item.Parent ~= nil then
				local gui = item :: GuiObject
				if gui.BackgroundTransparency < 1 then
					gui.BackgroundTransparency = AWAY_TRANSPARENCY
				end
				if gui:IsA("TextLabel") then
					(gui :: TextLabel).TextTransparency = AWAY_TRANSPARENCY
				elseif gui:IsA("ImageLabel") then
					(gui :: ImageLabel).ImageTransparency = AWAY_TRANSPARENCY
				end
			end
		end
	end
	return holder
end

-- Builds the strip under `playerGui`, hidden until the first render.
function RelationsStripView.mount(playerGui: Instance): RelationsStripView
	local surface = Theme.color["color.surface.scrim"]
	local gui = Instance.new("ScreenGui")
	gui.Name = "RelationsStrip"
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local strip =
		RelationsStripView.frame("Strip", UDim2.fromOffset(0, Theme.size["size.chip.player"].y))
	strip.AnchorPoint = Vector2.new(0, 0)
	strip.Position = UDim2.fromOffset(16, 16) -- layout.md §3 region A
	strip.AutomaticSize = Enum.AutomaticSize.X
	strip.BackgroundTransparency = surface.transparency or 0
	strip.BackgroundColor3 = Color3.fromHex(surface.hex)
	strip.Parent = gui
	gui.Parent = playerGui

	local view = {}

	function view.render(_self: RelationsStripView, description: RelationsModel.Description)
		strip:ClearAllChildren()
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = strip

		chip("Helper", description.helper, 1, nameOf(description.helper.playerId)).Parent = strip
		arrow(2).Parent = strip
		local you = description.you
		local youHue = you.hueToken
		if youHue ~= nil then
			local swatch = RelationsStripView.frame("You", UDim2.fromOffset(16, 16))
			swatch.BackgroundTransparency = 0
			swatch.BackgroundColor3 = hex(youHue)
			swatch.LayoutOrder = 3
			round(swatch)
			swatch.Parent = strip
		end
		local partner = description.partner
		if partner ~= nil then
			arrow(4).Parent = strip
			chip("Partner", partner, 5, nameOf(partner.playerId)).Parent = strip
		end
		gui.Enabled = true
	end

	function view.hide(_self: RelationsStripView)
		gui.Enabled = false
	end

	return view :: RelationsStripView
end

return RelationsStripView
