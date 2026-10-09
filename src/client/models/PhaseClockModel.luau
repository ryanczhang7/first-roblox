--!strict
--[[
	SLICE-004 AC-3: what the phase clock says, as a pure function of the last
	`RoundView` received, the local time it arrived and the local time now.

	    phaseKey   Words.phase[view.phase] - `voice.md` §2.1's word. A phase
	               the table does not name RAISES, naming it, rather than
	               echoing an internal name onto the screen.
	    countdown  "%d:%02d" (minutes unpadded, seconds two digits) of
	               ceil(max(0, secondsLeft - (now - receivedAt))); nil when
	               the view carries no `secondsLeft`.

	Rounding UP is what makes the last second read "0:01" until it is over,
	and the clamp is what holds "0:00" between the server's last `Tick` and
	the next phase arriving.

	PURE: `now` is an argument (the client entry reads `Clock.real()`), and
	`view` is never mutated.
]]

local Words = require("../Words")

export type View = { phase: string, secondsLeft: number? }
export type Description = { phaseKey: string, countdown: string? }

local function countdown(secondsLeft: number, receivedAt: number, now: number): string
	local remaining = math.max(0, secondsLeft - (now - receivedAt))
	local whole = math.ceil(remaining)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function describe(view: View, receivedAt: number, now: number): Description
	local word = Words.phase[view.phase]
	if word == nil then
		local phase = tostring(view.phase)
		error(`PhaseClockModel.describe: voice.md §2.1 has no word for the phase "{phase}"`, 2)
	end
	local secondsLeft = view.secondsLeft
	return {
		phaseKey = word,
		countdown = if secondsLeft ~= nil then countdown(secondsLeft, receivedAt, now) else nil,
	}
end

return table.freeze({
	describe = describe,
})
