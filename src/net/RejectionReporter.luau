--!strict
--[[
	TEL-003: turns the `Rejection`s `Wrapper.guard` returns into
	`remote_rejected` telemetry events.

	IT NEVER READS A CLOCK. `now` is a parameter of `record` and `flush`, as it
	is of `RateLimiter.allow`, so a 100 Hz flood is an instant test.

	ONLY `rate` IS COALESCED (PO decision 3). `identity`, `shape`, `range` and
	`phase` each produce one event per call with `count = 1` (AC-1). A `rate`
	rejection is coalesced per `(playerId, remoteName)`: the first in a window
	- no window yet, or `now - windowStart >= intervalSeconds`, INCLUSIVE as
	`RateLimiter` is - returns an event carrying itself plus everything
	suppressed since the last one, and opens a new window; the rest only
	count. `flush(now)` reports the suppressed rejections of every window that
	has any, and leaves the window start where it was. Without the count a
	flood's size is lost; without the bound, telemetry amplifies the flood the
	limiter refused (AC-5).

	THE EVENT CARRIES `remote`, `reason` AND `count`, AND NOTHING ELSE. No
	argument value and no `Rejection.detail`, which quotes the payload
	verbatim (AC-4, PO decision 2) - `record` does not take either, so the leak
	cannot be written. A caller id that is not a string is attacker-chosen and
	goes nowhere: the event carries `playerId = nil`.

	`Reason` is re-declared rather than imported from `Wrapper`: `Wrapper`
	requires this module, and the reverse edge would be a cycle.
]]

local Event = require("@shared/telemetry/Event")

local RejectionReporter = {}

-- `rejection_report_interval_seconds`: an engineering constant, not a
-- game-tuning one, so it lives here and not in `tuning.md`.
RejectionReporter.INTERVAL_SECONDS = 1

export type Reason = "identity" | "shape" | "range" | "phase" | "rate"

export type RejectionReporter = {
	record: (
		self: RejectionReporter,
		playerId: any,
		remoteName: string,
		reason: Reason,
		now: number
	) -> Event.TelemetryEvent?,
	flush: (self: RejectionReporter, now: number) -> { Event.TelemetryEvent },
}

type Window = { start: number, pending: number }

local EVENT_NAME = "remote_rejected"

function RejectionReporter.new(intervalSeconds: number, sessionId: string): RejectionReporter
	-- Only `rate` windows live here; the caller id keying them is a string,
	-- because a non-string id is rejected for `identity` before check 5.
	local windows: { [any]: { [string]: Window } } = {}

	local function event(
		playerId: any,
		remoteName: string,
		reason: Reason,
		count: number,
		now: number
	): Event.TelemetryEvent
		local id: string? = if typeof(playerId) == "string" then playerId else nil
		local fields: Event.Fields = {
			remote = remoteName,
			reason = reason,
			count = count,
		}
		return Event.new(EVENT_NAME, now, sessionId, id, fields)
	end

	local reporter: RejectionReporter = {
		record = function(
			_self: RejectionReporter,
			playerId: any,
			remoteName: string,
			reason: Reason,
			now: number
		): Event.TelemetryEvent?
			if reason ~= "rate" then
				return event(playerId, remoteName, reason, 1, now)
			end

			local remotes = windows[playerId] or {}
			windows[playerId] = remotes
			local window = remotes[remoteName]
			if window == nil or now - window.start >= intervalSeconds then
				local count = 1 + (if window ~= nil then window.pending else 0)
				remotes[remoteName] = { start = now, pending = 0 }
				return event(playerId, remoteName, reason, count, now)
			end
			window.pending += 1
			return nil
		end,

		flush = function(_self: RejectionReporter, now: number): { Event.TelemetryEvent }
			local due: { { playerId: any, remoteName: string, window: Window } } = {}
			for playerId, remotes in windows do
				for remoteName, window in remotes do
					if window.pending > 0 then
						table.insert(
							due,
							{ playerId = playerId, remoteName = remoteName, window = window }
						)
					end
				end
			end
			-- Deterministic: by player, then remote, ascending.
			table.sort(due, function(a, b)
				local pa, pb = tostring(a.playerId), tostring(b.playerId)
				if pa ~= pb then
					return pa < pb
				end
				return a.remoteName < b.remoteName
			end)

			local events: { Event.TelemetryEvent } = {}
			for _, entry in due do
				table.insert(
					events,
					event(entry.playerId, entry.remoteName, "rate", entry.window.pending, now)
				)
				entry.window.pending = 0
			end
			return events
		end,
	}

	return reporter
end

return RejectionReporter
