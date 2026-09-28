--!strict
--[[
	TEL-003: every rejected remote call emits a telemetry event naming the
	reason. AC-1 through AC-6 and the Contract's promises applied to the real
	`src/net/Wrapper.luau` and the new `src/net/RejectionReporter.luau`,
	driving the real `Schema`, `Remotes`, `RateLimiter` and the real
	`src/shared/telemetry/Event.luau`.

	THREE RIGHT REASONS TO BE RED, and the file is arranged so each surfaces
	as its own assertion rather than as one LOAD FAIL:

	  * `src/net/RejectionReporter.luau` does NOT exist on arrival. It is
	    required through a `pcall` and carried as nil, so the reporter unit
	    tests fail on "did not load" - the module is the story's artifact.
	  * `Wrapper.guard` does not read `context.telemetry`. The WIRING tests
	    drive it with a spy reporter that needs no production module, so they
	    fail on "emit was called 0 time(s)" - the wrapper half of the story.
	  * `remote_rejected` is not in `Event.BUCKETS`. Every end-to-end test
	    reconstructs its events through the real `Event.new`, so once the
	    reporter and wiring exist the missing entry is its own violation line;
	    `tests/shared/telemetry_event_test.luau` AC-2 pins it directly.

	THE CHECKS LIVE IN `tests/helpers/RejectionContract.luau`, and every one of
	them has been OBSERVED to fire in `tests/net/rejection_controls_test.luau`
	against the bundle it exists to catch - the unbounded reporter, the one
	that drops the count, the wrapper that emits on accepts, the ones that
	copy `rawArgs` and `detail` into the log.

	NO ROBLOX, NO `Players`, NO ROUND, AND NO REAL TIME. `GuardContext` is
	injected with a `Clock.manual`; the reporter takes `now` as a parameter.
	A thousand calls at 10 ms is instant.
]]

local Contract = require("../helpers/RejectionContract")

local schemaLoaded, schemaResult = pcall(require, "../../src/net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/net/Remotes")
local wrapperLoaded, wrapperResult = pcall(require, "../../src/net/Wrapper")
local limiterLoaded, limiterResult = pcall(require, "../../src/net/RateLimiter")
local eventLoaded, eventResult = pcall(require, "../../src/shared/telemetry/Event")
local reporterLoaded, reporterResult = pcall(require, "../../src/net/RejectionReporter")

-- The merged modules are required for every check; `RejectionReporter` is
-- carried as nil until GREEN writes it, so a wiring test fails on its own
-- assertion rather than on the module the reporter tests alone need.
local function bundle(): Contract.Bundle
	assert(schemaLoaded, `src/net/Schema.luau did not load: {tostring(schemaResult)}`)
	assert(remotesLoaded, `src/net/Remotes.luau did not load: {tostring(remotesResult)}`)
	assert(wrapperLoaded, `src/net/Wrapper.luau did not load: {tostring(wrapperResult)}`)
	assert(limiterLoaded, `src/net/RateLimiter.luau did not load: {tostring(limiterResult)}`)
	assert(eventLoaded, `src/shared/telemetry/Event.luau did not load: {tostring(eventResult)}`)
	return {
		Schema = schemaResult,
		Remotes = remotesResult,
		Wrapper = wrapperResult,
		RateLimiter = limiterResult,
		RejectionReporter = if reporterLoaded then reporterResult else nil,
		Event = eventResult,
	}
end

return {
	--[[ The reporter: src/net/RejectionReporter.luau ]]

	["Contract: RejectionReporter exports INTERVAL_SECONDS = 1 and new(intervalSeconds, sessionId) returning a reporter with record and flush methods"] = function()
		Contract.reporterExportsTheIntervalAndAConstructor(bundle())
	end,

	["AC-1 (reporter): identity, shape, range and phase are never coalesced - five of each at one instant each return an event with count 1 and the Contract's exact envelope, and a table caller id yields playerId nil with nothing about the caller in fields"] = function()
		Contract.nonRateReasonsAreNeverCoalesced(bundle())
	end,

	["AC-5 (bound): 1,000 rate rejections from one player on one remote at now = i / 100 then flush(10) yield exactly 11 events - windows at 0..9 carrying 1, 100 x 9, and the flush carrying 99"] = function()
		Contract.floodIsBoundedToElevenEvents(bundle())
	end,

	["AC-5 (sum): over every event the same flood produced, sum(fields.count) is exactly 1,000 - a coalescer that drops the count is losing the measurement it exists to preserve"] = function()
		Contract.floodCountsSumToEveryRejection(bundle())
	end,

	["Contract: a rate window re-opens when now - w >= 1, inclusive, and flush reports the pending count, zeroes it, and leaves the window start unchanged"] = function()
		Contract.windowIsInclusiveAndFlushLeavesItsStart(bundle())
	end,

	["AC-6: coalescing is per player and per remote - B's flood does not suppress A's first rate rejection on the same remote, A's flood does not suppress A's first on another remote, and flush orders by playerId then remoteName"] = function()
		Contract.coalescingIsPerPlayerAndPerRemote(bundle())
	end,

	["Contract: flush with nothing pending returns {} - fresh, after a window opened, after non-rate rejections, and immediately after a draining flush"] = function()
		Contract.flushWithNothingPendingReturnsAnEmptyList(bundle())
	end,

	--[[ The wiring: Wrapper.guard reads context.telemetry (spy reporter, no
	     production reporter needed) ]]

	["Contract (wiring): for each of the five reasons the wrapper calls reporter:record(playerId, remoteName, reason, now) exactly once and emit({ event }) exactly once with the event record returned, and emits nothing when record answers nil"] = function()
		Contract.wrapperRecordsEachRejectionAndEmitsItsEventOnce(bundle())
	end,

	["AC-2: ten accepted calls across a rate-limited and an unlimited remote call reporter:record zero times and emit zero times, and the positive control - one shape rejection - calls each once"] = function()
		Contract.acceptedCallProducesNoEventAndNoRecord(bundle())
	end,

	["Contract: telemetry = nil in the context means nothing is recorded or emitted and the six verdicts are unchanged (green on arrival; earned by the assumesTelemetry control)"] = function()
		Contract.contextWithoutTelemetryIsUnchanged(bundle())
	end,

	--[[ End to end: the real wrapper with the real reporter, reconstructed
	     through the real Event.new ]]

	["AC-1/AC-3: each of the five reasons in turn produces exactly one batch of one remote_rejected event (D1) carrying the remote name, the caller's id and fields.reason equal to the returned Rejection's reason, count 1, at = the clock's value"] = function()
		Contract.everyReasonProducesExactlyOneEventNamingRemoteReasonAndPlayer(bundle())
	end,

	["AC-4: a needle the schema quotes verbatim into Rejection.detail - a hostile string, an out-of-range number, a bare string payload, an unexpected key - never reaches the event's fields, which carry exactly remote, reason, count"] = function()
		Contract.noArgumentValueEntersTheEvent(bundle())
	end,

	["AC-4 (scalar fields): a table payload - where an integer belongs, where a boolean belongs, nested, 40 deep - does not raise, and the event's fields are TEL-001's flat scalars that Event.new accepts"] = function()
		Contract.tablePayloadYieldsScalarFieldsAndNoRaise(bundle())
	end,

	["AC-5 (wrapper): 1,000 calls at 100 Hz on a remote limited at 1.5 s produce at most 10 emits, at most 11 events with the flush, one event per batch, and sum(count) equal to the number of rate Rejections the wrapper returned"] = function()
		Contract.floodThroughTheWrapperIsBoundedAndCounted(bundle())
	end,

	["Contract: a table, a number or nil sent as the caller id is rejected for identity and the event carries playerId nil, exactly three fields, and nothing about the caller"] = function()
		Contract.tableCallerIdIsNotPutInTheEvent(bundle())
	end,
}
