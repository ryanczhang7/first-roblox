--!strict
--[[
	THEME-001: the root `UIScale` and the breakpoint, as pure functions of the
	safe-area size.

	`docs/wiki/design/layout.md` §2 IS THE SPECIFICATION:

	    uiScale(safeW, safeH) = clamp(min(safeW, safeH) / 390, 0.9, 1.3)
	    breakpoint            = "compact" when the short side < 480, else "regular"

	The 0.9 floor is what `accessibility.md` A-1 and A-2 multiply the base
	sizes in `Theme` by, so changing it here without the documents moves every
	target and type floor. `tests/client/theme_test.luau` (PT-L1) pins the
	values layout.md states at 568 × 262, 667 × 339, 1024 × 700 and
	1920 × 1000, and the formula's clamp and breakpoint edges.

	PURE: no Instance, no camera read. The caller passes the safe-area size it
	measured; that is what lets the formula be tested without a screen.
]]

local BASE = 390
local MIN_SCALE = 0.9
local MAX_SCALE = 1.3
local COMPACT_BELOW = 480

export type Breakpoint = "compact" | "regular"

local function uiScale(width: number, height: number): number
	return math.clamp(math.min(width, height) / BASE, MIN_SCALE, MAX_SCALE)
end

local function breakpoint(width: number, height: number): Breakpoint
	if math.min(width, height) < COMPACT_BELOW then
		return "compact"
	end
	return "regular"
end

return table.freeze({
	uiScale = uiScale,
	breakpoint = breakpoint,
})
