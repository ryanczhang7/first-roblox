--!strict
--[[
	TEL-003 AC-1 through AC-6, plus the promises the story's `## Contract` makes
	about `RejectionReporter` and the `telemetry` field of `GuardContext`,
	written once as checks over a bundle -
	`{ Schema, Remotes, Wrapper, RateLimiter, RejectionReporter, Event }` - handed
	in as a parameter rather than over `src/ReplicatedStorage/Net/*.luau` by name. The same
	arrangement as `RateContract.luau`, for the same reason:
	`tests/net/rejection_test.luau` applies these to the real modules and
	`tests/net/rejection_controls_test.luau` applies them to the deliberately
	wrong bundles in `RejectionStubs.luau`, so that every check here has been
	EXECUTED and observed to refuse the implementation it exists to catch
	before GREEN writes a line.

	THREE LEVELS, so that RED fails for three different right reasons:

	  * REPORTER checks are unit criteria on `src/ReplicatedStorage/Net/RejectionReporter.luau`,
	    which does not exist on arrival; each opens by saying so.
	  * WIRING checks drive the real `Wrapper.guard` with a SPY reporter that
	    needs no production module, so they fail on "emit was never called" -
	    the wrapper does not read `context.telemetry` today - and pin the exact
	    call shape: `reporter:record(playerId, remoteName, reason, now)` then
	    `emit({ event })`, once, and neither on an accepted call.
	  * END-TO-END checks drive the real wrapper with the real reporter and
	    reconstruct every event through the bundle's `Event.new`, which is how
	    "`remote_rejected` is missing from `Event.BUCKETS`" surfaces as an
	    assertion rather than a stack trace.

	THE ORACLE PARTITION IS HONOURED HERE. AC-1 and AC-3 are settled: the five
	reason strings are NET-001's and are read out of `REASONS` below, and every
	event's `fields.reason` is compared to the `reason` of the Rejection the
	wrapper actually returned - never to a string this file chose. AC-2, AC-4
	and AC-6 are mechanical with the controls the criteria name. AC-5 is the
	one oracle-free criterion and is implemented literally from PO decision 1:
	1,000 `rate` rejections at `now = i / 100`, computed and never accumulated,
	then `flush(10)`; exactly 11 events; `sum(count) == 1000` as ITS OWN check,
	because a coalescer that drops the count is losing the measurement it
	exists to preserve.

	AC-4 IS THE LEAST OBVIOUS CRITERION AND THE MOST CAREFULLY NEEDLED. The
	rejected arguments are hostile input and must not enter the log. The
	needle `HOSTILE_7f3a` is under `Schema.describe`'s 32-character limit, so
	the real schema echoes it VERBATIM into `Rejection.detail` (PO decision 2):
	an implementation that copies `detail` into `fields` leaks it exactly as one
	that copies `rawArgs` does, and both are asserted. Every case first proves
	the leak is POSSIBLE (the detail carries the needle) so that a case the
	schema happened to swallow cannot pass vacuously.

	NO TEST HERE SLEEPS, WAITS OR READS REAL TIME. Reporter checks pass `now`
	directly; wrapper checks drive `RateContract.world`'s manual clock.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local NetContract = require("./NetContract")
local RateContract = require("./RateContract")

local RejectionContract = {}

export type Bundle = {
	Schema: any,
	Remotes: any,
	Wrapper: any,
	RateLimiter: any,
	RejectionReporter: any,
	Event: any,
}

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
end

RejectionContract.SESSION_ID = "session-TEL-003-a"

-- NET-001's five reason strings, in check order. SETTLED: read out, never
-- reworded, and compared against the Rejection the wrapper returned.
RejectionContract.REASONS = { "identity", "shape", "range", "phase", "rate" }

-- AC-4's needle: distinctive, and under `Schema.describe`'s MAX_SHOWN (32), so
-- the schema quotes it verbatim into the detail.
RejectionContract.NEEDLE = "HOSTILE_7f3a"
RejectionContract.NEEDLE_NUMBER = 424242

-- AC-5's flood, from the criterion: 100 calls per second for 10 seconds.
RejectionContract.FLOOD_CALLS = 1000
RejectionContract.FLOOD_HZ = 100

local SESSION_ID = RejectionContract.SESSION_ID
local NEEDLE = RejectionContract.NEEDLE
local NEEDLE_NUMBER = RejectionContract.NEEDLE_NUMBER
local FLOOD_CALLS = RejectionContract.FLOOD_CALLS
local FLOOD_HZ = RejectionContract.FLOOD_HZ

local VALID = { token = 4, flag = true }

-- A start time that is not 0, so that `now - w` and `now` are different
-- numbers and an implementation comparing the wrong one is visible.
local START = 20

local SCALAR: { [string]: boolean } = { string = true, number = true, boolean = true }

-- The event's `fields`, exactly, and nothing else (Contract, "The event").
local FIELD_KEYS: { string } = { "count", "reason", "remote" }

--[[ ------------------------------------------------------------------------
     Rendering
     ------------------------------------------------------------------------ ]]

-- `remote_rejected<p1>{count=1,reason=rate,remote=R} at 3.5 (D1, session-x)`.
local function describeEvent(event: any): string
	if typeof(event) ~= "table" then
		return Deep.show(event)
	end
	local who = if event.playerId == nil then "-" else Deep.show(event.playerId)
	return `{tostring(event.name)}<{who}>{Deep.show(event.fields)} at {tostring(event.at)} `
		.. `({tostring(event.bucket)}, {tostring(event.sessionId)})`
end

local function describeEvents(events: { any }): string
	local parts: { string } = {}
	for _, event in events do
		table.insert(parts, describeEvent(event))
	end
	return `[{table.concat(parts, ", ")}]`
end

local function sortedKeys(fields: any): { string }
	local keys: { string } = {}
	if typeof(fields) == "table" then
		for key in pairs(fields :: { [any]: any }) do
			table.insert(keys, tostring(key))
		end
	end
	table.sort(keys)
	return keys
end

--[[
	The Contract's whole event, as a `Deep.diff` against what was produced: a
	missing field, a wrong value and an EXTRA key all show up, by name.
]]
local function expectedEvent(
	now: number,
	playerId: string?,
	remote: string,
	reason: string,
	count: number
): any
	return {
		name = "remote_rejected",
		at = now,
		bucket = "D1",
		sessionId = SESSION_ID,
		playerId = playerId,
		fields = { remote = remote, reason = reason, count = count },
	}
end

local function diffEvent(label: string, event: any, expected: any, violations: { string })
	local diff = Deep.diff(expected, event)
	if diff ~= "" then
		table.insert(violations, `{label}: the event is not the Contract's:\n{indent(diff)}`)
	end
end

--[[
	Every event must be constructible by the bundle's `Event.new` and come out
	identical: that is what proves the name is in `Event.BUCKETS` under D1 and
	the fields are TEL-001's flat scalars, using TEL-001's own instrument
	rather than a private copy of its rules.
]]
local function reconstructs(label: string, bundle: Bundle, event: any, violations: { string })
	if typeof(event) ~= "table" then
		return
	end
	local ok, rebuilt =
		pcall(bundle.Event.new, event.name, event.at, event.sessionId, event.playerId, event.fields)
	if not ok then
		table.insert(
			violations,
			`{label}: Event.new refuses the event the reporter produced - `
				.. `{describeEvent(event)}: {tostring(rebuilt)}`
		)
		return
	end
	local diff = Deep.diff(event, rebuilt)
	if diff ~= "" then
		table.insert(
			violations,
			`{label}: Event.new rebuilt the event differently:\n{indent(diff)}`
		)
	end
end

local function fieldKeysAreExactly(label: string, event: any, violations: { string })
	local keys = sortedKeys(if typeof(event) == "table" then event.fields else nil)
	if not Deep.equal(FIELD_KEYS, keys) then
		table.insert(
			violations,
			`{label}: fields carry keys {Deep.show(keys)}; exactly `
				.. `{Deep.show(FIELD_KEYS)} and nothing else`
		)
	end
end

-- Every key and every value, rendered, so a needle anywhere in `fields` is found.
local function fieldsMention(event: any, needle: string): boolean
	if typeof(event) ~= "table" or typeof(event.fields) ~= "table" then
		return false
	end
	for key, value in pairs(event.fields :: { [any]: any }) do
		if string.find(tostring(key), needle, 1, true) ~= nil then
			return true
		end
		if string.find(Deep.show(value), needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

--[[ ------------------------------------------------------------------------
     Reporter fixtures
     ------------------------------------------------------------------------ ]]

local function module(bundle: Bundle, criterion: string): any
	if bundle.RejectionReporter == nil then
		Contract.fail(
			`{criterion}: src/ReplicatedStorage/Net/RejectionReporter.luau did not load - the reporter is a new module `
				.. `and this check is a unit criterion on it`
		)
	end
	return bundle.RejectionReporter
end

local function newReporter(bundle: Bundle, criterion: string): (any, number)
	local Reporter = module(bundle, criterion)
	if typeof(Reporter.new) ~= "function" then
		Contract.fail(
			`{criterion}: RejectionReporter.new is {typeof(Reporter.new)}; expected a function`
		)
	end
	local interval = Reporter.INTERVAL_SECONDS
	if typeof(interval) ~= "number" then
		Contract.fail(
			`{criterion}: RejectionReporter.INTERVAL_SECONDS is {Deep.show(interval)}; expected a number`
		)
	end
	local reporter = Reporter.new(interval, SESSION_ID)
	if
		not (
			typeof(reporter) == "table"
			and typeof(reporter.record) == "function"
			and typeof(reporter.flush) == "function"
		)
	then
		Contract.fail(
			`{criterion}: RejectionReporter.new({interval}, "{SESSION_ID}") returned `
				.. `{Deep.show(reporter)}; expected a reporter with record and flush methods`
		)
	end
	return reporter, interval
end

-- One `record`, with a raise reported as an outcome rather than ending the check.
local function record(
	reporter: any,
	playerId: any,
	remote: string,
	reason: string,
	now: number
): (boolean, any)
	return pcall(function()
		return reporter:record(playerId, remote, reason, now)
	end)
end

local function flush(reporter: any, now: number): (boolean, any)
	return pcall(function()
		return reporter:flush(now)
	end)
end

--[[
	AC-5's flood, at the reporter: 1,000 `rate` rejections from one player on
	one remote at `now = i / 100`, `i = 0..999` - COMPUTED, never accumulated,
	because summing 0.01 a thousand times drifts - then `flush(10)`. Returns the
	events `record` produced and the events `flush` produced.
]]
local function flood(bundle: Bundle, criterion: string): ({ any }, { any })
	local reporter = newReporter(bundle, criterion)
	local fromRecord: { any } = {}
	local raised: string? = nil
	for i = 0, FLOOD_CALLS - 1 do
		local now = i / FLOOD_HZ
		local ok, result = record(reporter, "p1", "remote_flooded", "rate", now)
		if not ok then
			raised = raised or `{criterion}: record at now = {now} RAISED: {tostring(result)}`
		elseif result ~= nil then
			table.insert(fromRecord, result)
		end
	end
	if raised ~= nil then
		Contract.fail(raised or "")
	end
	local ok, flushed = flush(reporter, FLOOD_CALLS / FLOOD_HZ)
	if not ok then
		Contract.fail(`{criterion}: flush({FLOOD_CALLS / FLOOD_HZ}) RAISED: {tostring(flushed)}`)
	end
	if typeof(flushed) ~= "table" then
		Contract.fail(
			`{criterion}: flush({FLOOD_CALLS / FLOOD_HZ}) returned {Deep.show(flushed)}; expected a list`
		)
	end
	return fromRecord, flushed
end

local function sumOfCounts(events: { any }): (number, number)
	local total = 0
	local missing = 0
	for _, event in events do
		local count = if typeof(event) == "table" and typeof(event.fields) == "table"
			then event.fields.count
			else nil
		if typeof(count) == "number" then
			total += count
		else
			missing += 1
		end
	end
	return total, missing
end

--[[ ------------------------------------------------------------------------
     Reporter: the Contract's shape
     ------------------------------------------------------------------------ ]]

--[[
	Contract: `RejectionReporter.INTERVAL_SECONDS` is 1 -
	`rejection_report_interval_seconds`, an engineering constant that lives
	here and not in tuning.md - and `new(intervalSeconds, sessionId)` returns a
	reporter with `record` and `flush` methods.
]]
function RejectionContract.reporterExportsTheIntervalAndAConstructor(bundle: Bundle)
	local Reporter = module(bundle, "Contract")
	if Reporter.INTERVAL_SECONDS ~= 1 then
		Contract.fail(
			`Contract: RejectionReporter.INTERVAL_SECONDS is {Deep.show(Reporter.INTERVAL_SECONDS)}; `
				.. `rejection_report_interval_seconds is 1`
		)
	end
	newReporter(bundle, "Contract")
end

--[[
	Contract (PO decision 3), and AC-1's reporter half: `identity`, `shape`,
	`range` and `phase` are NEVER coalesced. Five rejections of each reason
	from one player on one remote at ONE instant each return an event with
	`count = 1`, the Contract's exact envelope, and fields of exactly three
	keys - and each reconstructs through `Event.new`. A non-string caller id
	on an `identity` rejection yields `playerId = nil` and nothing about the
	caller in `fields`.
]]
function RejectionContract.nonRateReasonsAreNeverCoalesced(bundle: Bundle)
	local reporter = newReporter(bundle, "AC-1")
	local violations: { string } = {}
	local remote = "remote_never_coalesced"
	local now = 3.25
	local produced = 0

	for _, reason in RejectionContract.REASONS do
		if reason == "rate" then
			continue
		end
		for i = 1, 5 do
			local label = `{reason} rejection {i} of 5 at now = {now}`
			local ok, event = record(reporter, "p1", remote, reason, now)
			if not ok then
				table.insert(violations, `AC-1: {label} -> record RAISED: {tostring(event)}`)
				continue
			end
			if event == nil then
				table.insert(
					violations,
					`AC-1: {label} -> record returned nil; only rate is coalesced (PO decision 3)`
				)
				continue
			end
			produced += 1
			diffEvent(
				`AC-1: {label}`,
				event,
				expectedEvent(now, "p1", remote, reason, 1),
				violations
			)
			fieldKeysAreExactly(`AC-1: {label}`, event, violations)
			reconstructs(`AC-1: {label}`, bundle, event, violations)
		end
	end

	-- An exploiter sending a table as the id. The wrapper survives it for
	-- `identity`; the reporter must not put it in the envelope or the fields.
	local caller = { HOSTILE = NEEDLE }
	local ok, event = record(reporter, caller, remote, "identity", now)
	if not ok then
		table.insert(violations, `Contract: a table caller id -> record RAISED: {tostring(event)}`)
	elseif event == nil then
		table.insert(violations, "Contract: a table caller id -> record returned nil")
	else
		if event.playerId ~= nil then
			table.insert(
				violations,
				`Contract: a table caller id -> the envelope's playerId is `
					.. `{Deep.show(event.playerId)}; a non-string caller id is not put in the envelope`
			)
		end
		fieldKeysAreExactly("Contract: a table caller id", event, violations)
		if fieldsMention(event, NEEDLE) or fieldsMention(event, tostring(caller)) then
			table.insert(
				violations,
				`Contract: a table caller id -> fields mention the caller: {Deep.show(event.fields)}`
			)
		end
		diffEvent(
			"Contract: a table caller id",
			event,
			expectedEvent(now, nil, remote, "identity", 1),
			violations
		)
		reconstructs("Contract: a table caller id", bundle, event, violations)
	end

	if #violations ~= 0 then
		Contract.fail(
			`AC-1: {#violations} violation(s) over 20 non-rate rejections and one table caller id `
				.. `({produced} event(s) produced) - a reporter that coalesces every reason, or `
				.. `whose envelope is not the Contract's, fails here:\n{indent(
					Contract.firstFew(violations, #violations)
				)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     Reporter: AC-5
     ------------------------------------------------------------------------ ]]

-- The expected window schedule of the flood: `record`'s ten openings at
-- 0, 1, ..., 9 and the flush at 10, as (at, count) pairs.
local function floodSchedule(): { { at: number, count: number } }
	local out: { { at: number, count: number } } = {}
	for k = 0, 9 do
		table.insert(
			out,
			{ at = (k * FLOOD_HZ) / FLOOD_HZ, count = if k == 0 then 1 else FLOOD_HZ }
		)
	end
	table.insert(out, { at = FLOOD_CALLS / FLOOD_HZ, count = FLOOD_HZ - 1 })
	return out
end

--[[
	AC-5, the bound: HOW MANY and WHEN. The flood yields exactly 11 events -
	10 from `record`, window openings at 0, 1, ..., 9, and 1 from `flush(10)`
	at 10 - each a `rate` event for p1 on the remote in the Contract's
	envelope. The unbounded control yields 1,000. What each event COUNTS is
	the sum check's, deliberately: the story's mutation 2 (drop the count)
	must leave this check green and turn that one red.

	The count of events is checked FIRST and alone, so that the message says
	the measured number; the timing follows.
]]
function RejectionContract.floodIsBoundedToElevenEvents(bundle: Bundle)
	local fromRecord, flushed = flood(bundle, "AC-5")
	if not (#fromRecord == 10 and #flushed == 1) then
		Contract.fail(
			`AC-5: record returned {#fromRecord} event(s) over {FLOOD_CALLS} rate rejections at `
				.. `{FLOOD_HZ} Hz ({FLOOD_CALLS / FLOOD_HZ} s) and flush({FLOOD_CALLS / FLOOD_HZ}) returned `
				.. `{#flushed}; wanted 10 and 1 - at most one rate event per player per remote per `
				.. `second, plus the trailing window. Telemetry that scales one-to-one with a flood is `
				.. `an amplifier`
		)
	end

	local violations: { string } = {}
	local all: { any } = table.clone(fromRecord)
	table.insert(all, flushed[1])
	for i, slot in floodSchedule() do
		local event = all[i]
		local label = if i <= 10
			then `AC-5: window {i} of 10 (opened at now = {slot.at})`
			else "AC-5: the flushed trailing window"
		if typeof(event) ~= "table" then
			table.insert(violations, `{label}: {Deep.show(event)}`)
			continue
		end
		-- The envelope with the count set aside for the sum check.
		local withoutCount = table.clone(event)
		if typeof(event.fields) == "table" then
			withoutCount.fields = table.clone(event.fields)
			withoutCount.fields.count = nil
		end
		local expected = expectedEvent(slot.at, "p1", "remote_flooded", "rate", 0)
		expected.fields.count = nil
		diffEvent(label, withoutCount, expected, violations)
	end
	if #violations ~= 0 then
		Contract.fail(
			`AC-5: 11 events, but {#violations} of them are not on the Contract's schedule (windows `
				.. `opening at 0..9, the flush at 10):\n{indent(
					Contract.firstFew(violations, #violations)
				)}`
		)
	end
end

--[[
	AC-5, the sum: WHAT THEY COUNT. Over every event the flood produced -
	`record`'s and `flush`'s - `sum(fields.count)` is exactly 1,000, checked
	FIRST and alone: a coalescer that drops the count is losing the
	measurement it exists to preserve, and the story's mutation 2 predicts this
	line red with the bound green. Then the schedule: 1, 100 x 9, and 99 on
	the flush, each event's `count` exactly, and no key in `fields` beyond
	`remote`, `reason`, `count`.
]]
function RejectionContract.floodCountsSumToEveryRejection(bundle: Bundle)
	local fromRecord, flushed = flood(bundle, "AC-5")
	local all: { any } = table.clone(fromRecord)
	for _, event in flushed do
		table.insert(all, event)
	end
	local total, missing = sumOfCounts(all)
	if total ~= FLOOD_CALLS then
		Contract.fail(
			`AC-5: the sum of fields.count over {#all} event(s) ({#fromRecord} from record, `
				.. `{#flushed} from flush) is {total}, and {missing} of them carry no numeric count; `
				.. `{FLOOD_CALLS} rejections were recorded and every one must be accounted for`
		)
	end

	local violations: { string } = {}
	local schedule = floodSchedule()
	if #all ~= #schedule then
		table.insert(violations, `AC-5: {#all} event(s) in all; the schedule has {#schedule}`)
	end
	for i, slot in schedule do
		local event = all[i]
		local label = if i <= 10
			then `AC-5: window {i} of 10 (opened at now = {slot.at})`
			else "AC-5: the flushed trailing window"
		local count = if typeof(event) == "table" and typeof(event.fields) == "table"
			then event.fields.count
			else nil
		if count ~= slot.count then
			table.insert(violations, `{label}: count is {Deep.show(count)}, expected {slot.count}`)
		end
		fieldKeysAreExactly(label, event, violations)
	end
	if #violations ~= 0 then
		Contract.fail(
			`AC-5: the counts sum to {FLOOD_CALLS}, but {#violations} event(s) are not the Contract's `
				.. `schedule (1, 100 x 9; the flush carrying 99):\n{indent(
					Contract.firstFew(violations, #violations)
				)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     Reporter: the window, inclusive, and what flush does to it
     ------------------------------------------------------------------------ ]]

--[[
	Contract: a `rate` window re-opens when `now - w >= intervalSeconds`,
	INCLUSIVE as `RateLimiter` is; `flush(now)` reports the pending count and
	zeroes it but leaves the window start where it was.

	One player, one remote, with the reporter at interval 1:
	  record 5.0  -> count 1 (window opens at 5)
	  record 5.5  -> nil
	  record 6.0  -> count 2 (6 - 5 == 1: inclusive; 1 + the pending 5.5)
	  record 6.5  -> nil
	  record 6.75 -> nil
	  flush  6.8  -> [count 2 at 6.8]
	  record 6.9  -> nil (the window still starts at 6: 0.9 < 1)
	  record 7.0  -> count 2 (7 - 6 == 1; 1 + the pending 6.9)
	  flush  7.5  -> {}
	A `>` comparison fails at 6.0; a flush that moves the window fails at 7.0;
	a flush that clears it fails at 6.9; one that keeps the pending count
	double-counts at 7.0.
]]
function RejectionContract.windowIsInclusiveAndFlushLeavesItsStart(bundle: Bundle)
	local reporter = newReporter(bundle, "Contract")
	local remote = "remote_window"
	local violations: { string } = {}

	type Step = { at: number, count: number?, flushes: { number }? }
	local steps: { Step } = {
		{ at = 5.0, count = 1 },
		{ at = 5.5 },
		{ at = 6.0, count = 2 },
		{ at = 6.5 },
		{ at = 6.75 },
		{ at = 6.8, flushes = { 2 } },
		{ at = 6.9 },
		{ at = 7.0, count = 2 },
		{ at = 7.5, flushes = {} },
	}
	for i, step in steps do
		if step.flushes ~= nil then
			local ok, result = flush(reporter, step.at)
			local label = `step {i}: flush({step.at})`
			if not ok then
				table.insert(violations, `{label} RAISED: {tostring(result)}`)
			elseif typeof(result) ~= "table" then
				table.insert(violations, `{label} returned {Deep.show(result)}; expected a list`)
			else
				local counts: { number } = {}
				for _, event in result do
					table.insert(
						counts,
						if typeof(event) == "table" then event.fields.count else -1
					)
				end
				if not Deep.equal(step.flushes, counts) then
					table.insert(
						violations,
						`{label} returned counts {Deep.show(counts)}, expected {Deep.show(
							step.flushes
						)}: ` .. describeEvents(result)
					)
				end
				for _, event in result do
					if typeof(event) == "table" and event.at ~= step.at then
						table.insert(
							violations,
							`{label} returned an event at {tostring(event.at)}; a flushed event carries `
								.. `at = the flush's now`
						)
					end
				end
			end
			continue
		end
		local ok, event = record(reporter, "p1", remote, "rate", step.at)
		local label = `step {i}: record at {step.at}`
		if not ok then
			table.insert(violations, `{label} RAISED: {tostring(event)}`)
		elseif step.count == nil then
			if event ~= nil then
				table.insert(
					violations,
					`{label} returned {describeEvent(event)}; expected nil (inside the window)`
				)
			end
		elseif event == nil then
			table.insert(
				violations,
				`{label} returned nil; expected an event with count {step.count} (the window `
					.. `re-opens when now - w >= 1, inclusive)`
			)
		else
			diffEvent(
				label,
				event,
				expectedEvent(step.at, "p1", remote, "rate", step.count),
				violations
			)
		end
	end

	if #violations ~= 0 then
		Contract.fail(
			`Contract: {#violations} violation(s) across {#steps} steps on one (player, remote) `
				.. `window - a > comparison, or a flush that moves, clears or fails to drain the `
				.. `window, fails here:\n{indent(Contract.firstFew(violations, #violations))}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     Reporter: AC-6
     ------------------------------------------------------------------------ ]]

--[[
	AC-6. Coalescing is per PLAYER and per REMOTE. B's first rejection on
	`remote_beta` at 0 opens B's window; A's flood on `remote_beta` at 0..0.99
	opens A's own window at 0 (not suppressed by B's) and suppresses 99; A's
	first on `remote_alpha` at 0.5 opens a third window (not suppressed by A's
	flood on the other remote); B's second and third on `remote_beta` are
	suppressed. `flush(1)` then reports the three pending windows ORDERED by
	playerId then remoteName - (A, alpha), (A, beta), (B, beta) - which is
	neither insertion order (B first) nor per-player insertion order (beta
	before alpha), each at 1. Every rejection is accounted for: 105 in, 105 out.
]]
function RejectionContract.coalescingIsPerPlayerAndPerRemote(bundle: Bundle)
	local reporter = newReporter(bundle, "AC-6")
	local violations: { string } = {}
	local recorded = 0

	local function expectEvent(
		label: string,
		playerId: string,
		remote: string,
		now: number,
		count: number
	)
		recorded += 1
		local ok, event = record(reporter, playerId, remote, "rate", now)
		if not ok then
			table.insert(violations, `AC-6: {label} -> record RAISED: {tostring(event)}`)
		elseif event == nil then
			table.insert(
				violations,
				`AC-6: {label} -> record returned nil; this is the first rate rejection in `
					.. `({playerId}, {remote})'s window and must be reported`
			)
		else
			diffEvent(
				`AC-6: {label}`,
				event,
				expectedEvent(now, playerId, remote, "rate", count),
				violations
			)
		end
	end
	local function expectSuppressed(label: string, playerId: string, remote: string, now: number)
		recorded += 1
		local ok, event = record(reporter, playerId, remote, "rate", now)
		if not ok then
			table.insert(violations, `AC-6: {label} -> record RAISED: {tostring(event)}`)
		elseif event ~= nil then
			table.insert(
				violations,
				`AC-6: {label} -> record returned {describeEvent(event)}; expected nil (inside `
					.. `({playerId}, {remote})'s window)`
			)
		end
	end

	expectEvent("B's first on remote_beta at 0", "B", "remote_beta", 0, 1)
	expectEvent(
		"A's first on remote_beta at 0, the instant B's window is open",
		"A",
		"remote_beta",
		0,
		1
	)
	for i = 1, 99 do
		expectSuppressed(
			`A's flood on remote_beta, call {i + 1} at {i / 100}`,
			"A",
			"remote_beta",
			i / 100
		)
	end
	expectEvent(
		"A's first on remote_alpha at 0.5, while A's remote_beta window is open",
		"A",
		"remote_alpha",
		0.5,
		1
	)
	expectSuppressed("A's second on remote_alpha at 0.6", "A", "remote_alpha", 0.6)
	expectSuppressed("B's second on remote_beta at 0.6", "B", "remote_beta", 0.6)
	expectSuppressed("B's third on remote_beta at 0.7", "B", "remote_beta", 0.7)

	local ok, flushed = flush(reporter, 1)
	if not ok then
		table.insert(violations, `AC-6: flush(1) RAISED: {tostring(flushed)}`)
	elseif typeof(flushed) ~= "table" then
		table.insert(violations, `AC-6: flush(1) returned {Deep.show(flushed)}; expected a list`)
	else
		local expected: { any } = {
			expectedEvent(1, "A", "remote_alpha", "rate", 1),
			expectedEvent(1, "A", "remote_beta", "rate", 99),
			expectedEvent(1, "B", "remote_beta", "rate", 2),
		}
		local diff = Deep.diff(expected, flushed)
		if diff ~= "" then
			table.insert(
				violations,
				`AC-6: flush(1) returned {describeEvents(flushed)}; expected (A, remote_alpha, 1), `
					.. `(A, remote_beta, 99), (B, remote_beta, 2) in that order - by playerId then `
					.. `remoteName:\n{indent(diff)}`
			)
		end
		local total = sumOfCounts(flushed)
		-- 3 window-opening events carried count 1 each; the flush carries the rest.
		if total + 3 ~= recorded then
			table.insert(
				violations,
				`AC-6: {recorded} rejections were recorded and {total + 3} were accounted for `
					.. `(3 on window openings, {total} on the flush)`
			)
		end
	end

	if #violations ~= 0 then
		Contract.fail(
			`AC-6: {#violations} violation(s) across {recorded} rejections by two players on two `
				.. `remotes - a reporter keyed by player alone, by remote alone, or flushing in `
				.. `insertion order fails here:\n{indent(Contract.firstFew(violations, #violations))}`
		)
	end
end

--[[
	Contract: a flush with nothing pending returns `{}` - on a fresh reporter,
	after a rate rejection that opened a window (nothing pending yet), after a
	non-rate rejection (never pending), and again immediately after a flush
	that drained something.
]]
function RejectionContract.flushWithNothingPendingReturnsAnEmptyList(bundle: Bundle)
	local reporter = newReporter(bundle, "Contract")
	local violations: { string } = {}

	local function expectEmpty(label: string, now: number)
		local ok, result = flush(reporter, now)
		if not ok then
			table.insert(violations, `{label}: flush({now}) RAISED: {tostring(result)}`)
		elseif typeof(result) ~= "table" or #result ~= 0 or next(result) ~= nil then
			table.insert(
				violations,
				`{label}: flush({now}) returned {Deep.show(result)}; expected an empty list`
			)
		end
	end

	expectEmpty("a fresh reporter", 0)
	record(reporter, "p1", "remote_a", "rate", 0.25)
	expectEmpty("after one rate rejection opened a window and nothing is pending", 0.5)
	record(reporter, "p1", "remote_a", "shape", 0.5)
	record(reporter, "p1", "remote_a", "identity", 0.5)
	expectEmpty("after two non-rate rejections, which are never pending", 0.75)
	record(reporter, "p1", "remote_a", "rate", 0.8)
	local ok, drained = flush(reporter, 0.9)
	if not ok or typeof(drained) ~= "table" or #drained ~= 1 then
		table.insert(
			violations,
			`Contract: a flush with one pending rejection returned {Deep.show(drained)}; expected one event`
		)
	end
	expectEmpty("immediately after a flush that drained one pending rejection", 0.95)

	if #violations ~= 0 then
		Contract.fail(
			`Contract: {#violations} violation(s) - flush with nothing pending returns {"{}"}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     Wrapper fixtures
     ------------------------------------------------------------------------ ]]

-- NET-001's test remote, legal in Round, declared under a unique name, with
-- the given `rateLimit` (or none). See `RateContract.remote`.
local function remote(bundle: Bundle, label: string, minIntervalSeconds: number?): any
	return RateContract.remote(bundle :: any, label, minIntervalSeconds)
end

--[[
	A `GuardContext` with the new `telemetry` field: `RateContract.world`'s
	context (manual clock, mutable phase) plus `{ reporter, emit }`, where
	`emit` appends every batch it is handed to `batches`.
]]
local function telemetryWorld(seated: { string }, reporter: any): (any, RateContract.World, { any })
	local context, world = RateContract.world(seated, "Round", START)
	local batches: { any } = {}
	context.telemetry = {
		reporter = reporter,
		emit = function(batch: any)
			table.insert(batches, batch)
		end,
	}
	return context, world, batches
end

-- Every event across every batch, in order.
local function eventsOf(batches: { any }): { any }
	local out: { any } = {}
	for _, batch in batches do
		if typeof(batch) == "table" then
			for _, event in batch do
				table.insert(out, event)
			end
		end
	end
	return out
end

--[[
	A spy reporter for the WIRING checks: it needs no production module,
	records every `record` call's arguments, and answers with a hand-built
	event of the Contract's shape (or nil for the reasons in `answersNil`), so
	that what the wrapper does with the answer is observable.
]]
local function spyReporter(answersNil: { [string]: boolean }?): (any, { any })
	local calls: { any } = {}
	local spy = {}
	function spy.record(_self: any, playerId: any, remoteName: any, reason: any, now: any): any
		table.insert(
			calls,
			{ playerId = playerId, remoteName = remoteName, reason = reason, now = now }
		)
		if answersNil ~= nil and answersNil[reason] then
			return nil
		end
		return expectedEvent(
			now,
			if typeof(playerId) == "string" then playerId else nil,
			remoteName,
			reason,
			1
		)
	end
	function spy.flush(_self: any, _now: any): { any }
		return {}
	end
	return spy, calls
end

type Case =
	{ label: string, at: number, phase: string, playerId: any, args: any, expected: string? }

--[[
	The five rejections, one per reason in check order, plus the acceptance
	the rate case needs first. `at` is an offset from START; the clock is SET,
	never accumulated. Identity uses the unseated p2; rate follows an
	acceptance at t + 1 by 1.4 s (the remote's limit is 1.5).
]]
local function fiveReasons(): { Case }
	return {
		{
			label = "unseated p2 at t -> identity",
			at = 0,
			phase = "Round",
			playerId = "p2",
			args = VALID,
			expected = "identity",
		},
		{
			label = "malformed {} at t -> shape",
			at = 0,
			phase = "Round",
			playerId = "p1",
			args = {},
			expected = "shape",
		},
		{
			label = "{ token = 99, flag = true } at t -> range",
			at = 0,
			phase = "Round",
			playerId = "p1",
			args = { token = 99, flag = true },
			expected = "range",
		},
		{
			label = "valid but in Lobby at t -> phase",
			at = 0,
			phase = "Lobby",
			playerId = "p1",
			args = VALID,
			expected = "phase",
		},
		{
			label = "valid at t + 1 -> accepted",
			at = 1,
			phase = "Round",
			playerId = "p1",
			args = VALID,
		},
		{
			label = "valid at t + 2.4, 1.4 s after the acceptance -> rate",
			at = 2.4,
			phase = "Round",
			playerId = "p1",
			args = VALID,
			expected = "rate",
		},
	}
end

local function call(guarded: any, playerId: any, args: any): (boolean, any)
	return pcall(guarded, playerId, args)
end

-- A violation line for a call expected to return a Rejection for `expected`.
local function expectRejection(
	criterion: string,
	label: string,
	ok: boolean,
	result: any,
	expected: string
): string?
	if not ok then
		return `{criterion}: {label} -> the guarded call RAISED: {tostring(result)}`
	end
	if typeof(result) ~= "table" or result.reason ~= expected then
		return `{criterion}: {label} -> returned {Deep.show(result)}, expected a Rejection for "{expected}"`
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     Wrapper: wiring, with a spy reporter (needs no RejectionReporter)
     ------------------------------------------------------------------------ ]]

--[[
	Contract, the wiring: for every call `guard` rejects, and only those, the
	wrapper calls `reporter:record(playerId, remoteName, reason, now)` - the
	caller's id as sent, the declaration's name, the Rejection's own reason,
	the clock's value at the call - and if that returns an event, calls
	`emit({ event })` exactly once with a batch of exactly that one event,
	before the Rejection is returned. If `record` returns nil, `emit` is not
	called. The five reasons are driven in turn (AC-1's wrapper half).
]]
function RejectionContract.wrapperRecordsEachRejectionAndEmitsItsEventOnce(bundle: Bundle)
	local definition = remote(bundle, "wiring", RateContract.MIN_INTERVAL_SECONDS)
	local handler = NetContract.recorder()
	local spy, calls = spyReporter()
	local context, world, batches = telemetryWorld({ "p1" }, spy)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	local violations: { string } = {}
	local rejections = 0

	for _, case in fiveReasons() do
		world.phase = case.phase
		world.clock:set(START + case.at)
		local callsBefore = #calls
		local batchesBefore = #batches
		local ok, result = call(guarded, case.playerId, case.args)
		if case.expected == nil then
			continue -- AC-2's check reads the accepted call; this one reads rejections
		end
		local expected = case.expected :: string
		rejections += 1
		local violation = expectRejection("Contract", case.label, ok, result, expected)
		if violation ~= nil then
			table.insert(violations, violation :: string)
			continue
		end
		local newCalls = #calls - callsBefore
		if newCalls ~= 1 then
			table.insert(
				violations,
				`Contract: {case.label} -> reporter:record was called {newCalls} time(s) during the `
					.. `call; exactly once per rejected call`
			)
		else
			local recorded = calls[#calls]
			local expectedCall = {
				playerId = case.playerId,
				remoteName = definition.name,
				reason = result.reason,
				now = world.clock.now(),
			}
			local diff = Deep.diff(expectedCall, recorded)
			if diff ~= "" then
				table.insert(
					violations,
					`Contract: {case.label} -> record(playerId, remoteName, reason, now) was called `
						.. `with the wrong arguments:\n{indent(diff)}`
				)
			end
		end
		local newBatches = #batches - batchesBefore
		if newBatches ~= 1 then
			table.insert(
				violations,
				`Contract: {case.label} -> emit was called {newBatches} time(s) during the call; `
					.. `exactly once, with the event record returned, before the Rejection is returned`
			)
		else
			local batch = batches[#batches]
			if typeof(batch) ~= "table" or #batch ~= 1 then
				table.insert(
					violations,
					`Contract: {case.label} -> emit was handed {Deep.show(batch)}; a batch of exactly `
						.. `one event, the shape Sink.dispatch consumes`
				)
			else
				local expectedEmitted = expectedEvent(
					world.clock.now(),
					if typeof(case.playerId) == "string" then case.playerId else nil,
					definition.name,
					result.reason,
					1
				)
				local diff = Deep.diff(expectedEmitted, batch[1])
				if diff ~= "" then
					table.insert(
						violations,
						`Contract: {case.label} -> the emitted event is not the one record returned:\n{indent(
							diff
						)}`
					)
				end
			end
		end
	end

	-- When record answers nil (a coalesced rate rejection), nothing is emitted.
	local quiet, quietCalls = spyReporter({ rate = true, shape = true })
	local quietContext, quietWorld, quietBatches = telemetryWorld({ "p1" }, quiet)
	local quietGuarded = bundle.Wrapper.guard(definition, quietContext, handler)
	quietWorld.clock:set(START + 10)
	call(quietGuarded, "p1", VALID) -- accepted (AC-2's check reads that call)
	local quietCallsBefore = #quietCalls
	local quietBatchesBefore = #quietBatches
	quietWorld.clock:set(START + 10.5)
	local ok, result = call(quietGuarded, "p1", VALID)
	local violation = expectRejection(
		"Contract",
		"valid at t + 10.5 after an acceptance at t + 10 -> rate (record answers nil)",
		ok,
		result,
		"rate"
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	ok, result = call(quietGuarded, "p1", {})
	violation = expectRejection(
		"Contract",
		"malformed {} -> shape (record answers nil)",
		ok,
		result,
		"shape"
	)
	if violation ~= nil then
		table.insert(violations, violation :: string)
	end
	if #quietCalls - quietCallsBefore ~= 2 then
		table.insert(
			violations,
			`Contract: with record answering nil, reporter:record was called `
				.. `{#quietCalls - quietCallsBefore} time(s) over 2 rejected calls; expected 2`
		)
	end
	if #quietBatches - quietBatchesBefore ~= 0 then
		table.insert(
			violations,
			`Contract: with record answering nil, emit was called `
				.. `{#quietBatches - quietBatchesBefore} time(s) over 2 rejected calls: `
				.. `{Deep.show(quietBatches)}; a nil from record means nothing to emit`
		)
	end

	if #violations ~= 0 then
		Contract.fail(
			`Contract: {#violations} violation(s) across {rejections} rejected calls through `
				.. `Wrapper.guard with a telemetry field - a wrapper that does not read `
				.. `context.telemetry, calls record with other arguments, emits a bare event, or emits `
				.. `twice fails here:\n{indent(Contract.firstFew(violations, #violations))}`
		)
	end
end

--[[
	AC-2. An ACCEPTED call produces no event and does not call
	`reporter:record`. Five accepted calls 2 s apart on a rate-limited remote
	and five at one instant on an unlimited one: the handler runs ten times,
	`record` is called zero times, `emit` is called zero times. Then the
	positive control inside the check - one rejection, which must record and
	emit - so that a wrapper that touches neither for ANY call cannot pass.
]]
function RejectionContract.acceptedCallProducesNoEventAndNoRecord(bundle: Bundle)
	local limited = remote(bundle, "ac2_limited", RateContract.MIN_INTERVAL_SECONDS)
	local unlimited = remote(bundle, "ac2_unlimited", nil)
	local handler, runs = NetContract.recorder()
	local spy, calls = spyReporter()
	local context, world, batches = telemetryWorld({ "p1" }, spy)
	local guardedLimited = bundle.Wrapper.guard(limited, context, handler)
	local guardedUnlimited = bundle.Wrapper.guard(unlimited, context, handler)
	local violations: { string } = {}

	for i = 0, 4 do
		world.clock:set(START + i * 2)
		local ok, result = call(guardedLimited, "p1", VALID)
		if not ok or result ~= nil then
			table.insert(
				violations,
				`AC-2: accepted call {i + 1} on the limited remote at t + {i * 2} -> `
					.. `{if ok then Deep.show(result) else `RAISED: {tostring(result)}`}`
			)
		end
	end
	world.clock:set(START + 30)
	for i = 1, 5 do
		local ok, result = call(guardedUnlimited, "p1", VALID)
		if not ok or result ~= nil then
			table.insert(
				violations,
				`AC-2: accepted call {i} on the unlimited remote -> `
					.. `{if ok then Deep.show(result) else `RAISED: {tostring(result)}`}`
			)
		end
	end
	if #runs ~= 10 then
		table.insert(violations, `AC-2: the handler ran {#runs} time(s) over 10 accepted calls`)
	end
	if #calls ~= 0 then
		table.insert(
			violations,
			`AC-2: reporter:record was called {#calls} time(s) over 10 accepted calls; the first: `
				.. `{Deep.show(calls[1])}. An accepted call touches neither the reporter nor emit`
		)
	end
	if #batches ~= 0 then
		table.insert(
			violations,
			`AC-2: emit was called {#batches} time(s) over 10 accepted calls: `
				.. `{describeEvents(eventsOf(batches))}. Emitting on accepts buries the signal under `
				.. `the traffic it is meant to stand out from`
		)
	end

	-- The positive control: a rejection still records and emits, so a wrapper
	-- that touches neither for ANY call cannot pass by doing nothing.
	local recordsBefore, batchesBefore = #calls, #batches
	local ok, result = call(guardedLimited, "p1", {})
	local violation =
		expectRejection("AC-2", "malformed {} (the positive control)", ok, result, "shape")
	if violation ~= nil then
		table.insert(violations, violation :: string)
	elseif #calls - recordsBefore ~= 1 or #batches - batchesBefore ~= 1 then
		table.insert(
			violations,
			`AC-2: the positive control (one shape rejection) called record `
				.. `{#calls - recordsBefore} time(s) and emit {#batches - batchesBefore} time(s); `
				.. `expected 1 and 1`
		)
	end

	if #violations ~= 0 then
		Contract.fail(
			`AC-2: {#violations} violation(s) - a wrapper that records or emits on an accepted call `
				.. `fails here:\n{indent(Contract.firstFew(violations, #violations))}`
		)
	end
end

--[[
	Contract: `telemetry = nil` means nothing is recorded and nothing is
	emitted, exactly as today. The five rejections and the acceptance return
	the same results through a context without the field as through one with
	it, and nothing raises. GREEN ON ARRIVAL - the wrapper ignores the field
	today - and earned by the `assumesTelemetry` control in
	`rejection_controls_test.luau`, a wrapper that indexes the field without a
	nil check and raises on every context NET-001..003 ever built.
]]
function RejectionContract.contextWithoutTelemetryIsUnchanged(bundle: Bundle)
	local definition = remote(bundle, "no_telemetry", RateContract.MIN_INTERVAL_SECONDS)
	local violations: { string } = {}

	local function drive(context: any, world: RateContract.World, who: string): { any }
		local handler = NetContract.recorder()
		local guarded = bundle.Wrapper.guard(definition, context, handler)
		local outcomes: { any } = {}
		for _, case in fiveReasons() do
			world.phase = case.phase
			world.clock:set(START + case.at)
			local ok, result = call(guarded, case.playerId, case.args)
			if not ok then
				table.insert(
					violations,
					`Contract: {who}: {case.label} -> RAISED: {tostring(result)}`
				)
				table.insert(outcomes, "<raised>")
			else
				table.insert(outcomes, if result == nil then "accepted" else result.reason)
			end
		end
		return outcomes
	end

	local bare, bareWorld = RateContract.world({ "p1" }, "Round", START)
	if bare.telemetry ~= nil then
		Contract.fail("fixture: RateContract.world must not set telemetry")
	end
	local without = drive(bare, bareWorld, "without telemetry")

	local spy = spyReporter()
	local withContext, withWorld = telemetryWorld({ "p1" }, spy)
	local with = drive(withContext, withWorld, "with telemetry")

	local expected = { "identity", "shape", "range", "phase", "accepted", "rate" }
	if not Deep.equal(expected, without) then
		table.insert(
			violations,
			`Contract: without telemetry the six calls returned {Deep.show(without)}; expected `
				.. `{Deep.show(expected)}`
		)
	end
	if not Deep.equal(without, with) then
		table.insert(
			violations,
			`Contract: the six calls returned {Deep.show(without)} without telemetry and `
				.. `{Deep.show(with)} with it; the field changes what is emitted, never what is returned`
		)
	end

	if #violations ~= 0 then
		Contract.fail(
			`Contract: {#violations} violation(s) - a wrapper that indexes context.telemetry without `
				.. `a nil check, or whose verdicts depend on it, fails here:\n{indent(
					Contract.firstFew(violations, #violations)
				)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     Wrapper + reporter, end to end
     ------------------------------------------------------------------------ ]]

--[[
	AC-1 and AC-3, end to end. The real wrapper with the real reporter: each
	of the five reasons in turn produces exactly one batch of exactly one
	event carrying the remote name, the caller's id in the envelope, and
	`fields.reason` equal - byte for byte - to the `reason` of the Rejection
	the wrapper returned, with `count = 1`, `at` = the clock's value, bucket
	D1 and the reporter's session id. Each reconstructs through `Event.new`.
]]
function RejectionContract.everyReasonProducesExactlyOneEventNamingRemoteReasonAndPlayer(
	bundle: Bundle
)
	local reporter = newReporter(bundle, "AC-1")
	local definition = remote(bundle, "ac1", RateContract.MIN_INTERVAL_SECONDS)
	local handler = NetContract.recorder()
	local context, world, batches = telemetryWorld({ "p1" }, reporter)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	local violations: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, case in fiveReasons() do
		world.phase = case.phase
		world.clock:set(START + case.at)
		local before = #batches
		local ok, result = call(guarded, case.playerId, case.args)
		if case.expected == nil then
			continue -- the acceptance the rate case needs; what it emits is AC-2's
		end
		local expected = case.expected :: string
		local violation = expectRejection("AC-1", case.label, ok, result, expected)
		if violation ~= nil then
			table.insert(violations, violation :: string)
			continue
		end
		seen[result.reason] = true
		local produced = #batches - before
		if produced ~= 1 then
			table.insert(
				violations,
				`AC-1: {case.label} -> {produced} batch(es) emitted for one rejected call; exactly one`
			)
			continue
		end
		local batch = batches[#batches]
		if typeof(batch) ~= "table" or #batch ~= 1 then
			table.insert(violations, `AC-1: {case.label} -> emit was handed {Deep.show(batch)}`)
			continue
		end
		local event = batch[1]
		local label = `AC-1/AC-3: {case.label}`
		diffEvent(
			label,
			event,
			expectedEvent(world.clock.now(), case.playerId, definition.name, result.reason, 1),
			violations
		)
		if
			typeof(event) == "table"
			and typeof(event.fields) == "table"
			and event.fields.reason ~= result.reason
		then
			table.insert(
				violations,
				`AC-3: {case.label} -> fields.reason is {Deep.show(event.fields.reason)} and the `
					.. `Rejection's reason is "{result.reason}"; the five strings are NET-001's contract `
					.. `and are not collapsed or reworded`
			)
		end
		fieldKeysAreExactly(label, event, violations)
		reconstructs(label, bundle, event, violations)
	end

	for _, reason in RejectionContract.REASONS do
		if not seen[reason] then
			table.insert(violations, `fixture: no call was rejected for "{reason}"`)
		end
	end

	if #violations ~= 0 then
		Contract.fail(
			`AC-1/AC-3: {#violations} violation(s) across the five reasons through Wrapper.guard `
				.. `with the real reporter:\n{indent(Contract.firstFew(violations, #violations))}`
		)
	end
end

--[[
	AC-4. The rejected arguments are hostile input and must not enter the
	log. Four payloads carry the needle where the schema rejects them for
	`shape` or `range`, and the real schema quotes it VERBATIM into
	`Rejection.detail` - asserted first, so the leak is provably possible - and
	the event's fields must carry neither the needle nor any key beyond
	`remote`, `reason`, `count`. An implementation copying `rawArgs` and one
	copying `detail` (PO decision 2) both fail here.
]]
function RejectionContract.noArgumentValueEntersTheEvent(bundle: Bundle)
	local reporter = newReporter(bundle, "AC-4")
	local definition = remote(bundle, "ac4", RateContract.MIN_INTERVAL_SECONDS)
	local handler = NetContract.recorder()
	local context, world, batches = telemetryWorld({ "p1" }, reporter)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	local violations: { string } = {}

	type Hostile = { label: string, args: any, needle: string, expected: string }
	local cases: { Hostile } = {
		{
			label = `a string where the integer belongs: \{ token = "{NEEDLE}", flag = true }`,
			args = { token = NEEDLE, flag = true },
			needle = NEEDLE,
			expected = "shape",
		},
		{
			label = `an out-of-range integer: \{ token = {NEEDLE_NUMBER}, flag = true }`,
			args = { token = NEEDLE_NUMBER, flag = true },
			needle = tostring(NEEDLE_NUMBER),
			expected = "range",
		},
		{
			label = `a bare string payload: "{NEEDLE}"`,
			args = NEEDLE,
			needle = NEEDLE,
			expected = "shape",
		},
		{
			label = `an unexpected key: \{ token = 4, flag = true, {NEEDLE} = true }`,
			args = { token = 4, flag = true, [NEEDLE] = true },
			needle = NEEDLE,
			expected = "shape",
		},
	}

	world.clock:set(START)
	for _, case in cases do
		local before = #batches
		local ok, result = call(guarded, "p1", case.args)
		local violation = expectRejection("AC-4", case.label, ok, result, case.expected)
		if violation ~= nil then
			table.insert(violations, violation :: string)
			continue
		end
		if string.find(tostring(result.detail), case.needle, 1, true) == nil then
			table.insert(
				violations,
				`fixture: {case.label} -> the detail does not quote the needle, so this case could `
					.. `not detect a detail leak: {Deep.show(result.detail)}`
			)
		end
		local events = eventsOf({ table.unpack(batches, before + 1) })
		if #events ~= 1 then
			table.insert(
				violations,
				`AC-4: {case.label} -> {#events} event(s) emitted; exactly one`
			)
			continue
		end
		local event = events[1]
		if fieldsMention(event, case.needle) then
			table.insert(
				violations,
				`AC-4: {case.label} -> the needle "{case.needle}" is in the event's fields: `
					.. `{Deep.show(event.fields)}. The payload was rejected BECAUSE it is untrusted; `
					.. `copying it into telemetry hands an attacker a write primitive into the log`
			)
		end
		fieldKeysAreExactly(`AC-4: {case.label}`, event, violations)
		reconstructs(`AC-4: {case.label}`, bundle, event, violations)
	end

	if #violations ~= 0 then
		Contract.fail(
			`AC-4: {#violations} violation(s) across {#cases} hostile payloads - an implementation `
				.. `that copies rawArgs or detail into fields fails here:\n{indent(
					Contract.firstFew(violations, #violations)
				)}`
		)
	end
end

--[[
	AC-4, the second half the criterion's control names: with a TABLE payload
	the guarded call must not raise, and the event's fields must be TEL-001's
	flat scalars - every value a string, number or boolean, and `Event.new`
	accepting them. An implementation that puts `rawArgs` in `fields` fails
	this whether or not it fails the needle check, and vice versa.
]]
function RejectionContract.tablePayloadYieldsScalarFieldsAndNoRaise(bundle: Bundle)
	local reporter = newReporter(bundle, "AC-4")
	local definition = remote(bundle, "ac4_table", RateContract.MIN_INTERVAL_SECONDS)
	local handler = NetContract.recorder()
	local context, world, batches = telemetryWorld({ "p1" }, reporter)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	local violations: { string } = {}

	local payloads: { { label: string, args: any } } = {
		{
			label = "a table where the integer belongs",
			args = { token = { [NEEDLE] = true }, flag = true },
		},
		{ label = "a table where the boolean belongs", args = { token = 4, flag = { NEEDLE } } },
		{
			label = "a nested table with no declared key",
			args = { [NEEDLE] = { deep = { NEEDLE } } },
		},
		{
			label = "a 40-deep table",
			args = (function(): any
				local root: any = {}
				local node = root
				for _ = 1, 40 do
					node.child = {}
					node = node.child
				end
				node[NEEDLE] = NEEDLE
				return root
			end)(),
		},
	}

	world.clock:set(START + 1)
	for _, payload in payloads do
		local before = #batches
		local ok, result = call(guarded, "p1", payload.args)
		if not ok then
			table.insert(
				violations,
				`AC-4: {payload.label} -> the guarded call RAISED: {tostring(result)}. The wrapper never `
					.. `raises, and a table in fields is what makes Event.new raise`
			)
			continue
		end
		if typeof(result) ~= "table" or result.reason ~= "shape" then
			table.insert(
				violations,
				`AC-4: {payload.label} -> returned {Deep.show(result)}, expected shape`
			)
			continue
		end
		local events = eventsOf({ table.unpack(batches, before + 1) })
		if #events ~= 1 then
			table.insert(
				violations,
				`AC-4: {payload.label} -> {#events} event(s) emitted; exactly one`
			)
			continue
		end
		local event = events[1]
		if typeof(event) == "table" and typeof(event.fields) == "table" then
			for key, value in pairs(event.fields :: { [any]: any }) do
				if not SCALAR[typeof(value)] then
					table.insert(
						violations,
						`AC-4: {payload.label} -> fields.{tostring(key)} is a {typeof(value)}; TEL-001 AC-6: `
							.. `an event's fields are a flat map of string, number or boolean values`
					)
				end
			end
		end
		if fieldsMention(event, NEEDLE) then
			table.insert(
				violations,
				`AC-4: {payload.label} -> the needle is in fields: {Deep.show(event.fields)}`
			)
		end
		fieldKeysAreExactly(`AC-4: {payload.label}`, event, violations)
		reconstructs(`AC-4: {payload.label}`, bundle, event, violations)
	end

	if #violations ~= 0 then
		Contract.fail(
			`AC-4 (scalar fields): {#violations} violation(s) across {#payloads} table payloads:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[
	AC-5 through the wrapper (PO decision 1). One seated player, one remote
	limited at 1.5 s, 1,000 calls at `t + i / 100`: some are accepted, the
	rest are `rate` Rejections. The events are BOUNDED - at most 10 from the
	calls and at most 11 with `flush(t + 10)`, at least one either way - and
	`sum(count)` equals the number of `rate` Rejections the wrapper actually
	returned. Every batch carries exactly one event and every event is a
	`rate` event for this player and remote.
]]
function RejectionContract.floodThroughTheWrapperIsBoundedAndCounted(bundle: Bundle)
	local reporter = newReporter(bundle, "AC-5")
	local definition = remote(bundle, "ac5", RateContract.MIN_INTERVAL_SECONDS)
	local handler, runs = NetContract.recorder()
	local context, world, batches = telemetryWorld({ "p1" }, reporter)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	local violations: { string } = {}

	local rateRejections = 0
	local raised: string? = nil
	for i = 0, FLOOD_CALLS - 1 do
		world.clock:set(START + i / FLOOD_HZ)
		local ok, result = call(guarded, "p1", VALID)
		if not ok then
			raised = raised or `AC-5: call {i + 1} RAISED: {tostring(result)}`
		elseif result ~= nil then
			if result.reason == "rate" then
				rateRejections += 1
			else
				raised = raised
					or `AC-5: call {i + 1} -> rejected for {Deep.show(result.reason)}, expected rate`
			end
		end
	end
	if raised ~= nil then
		table.insert(violations, raised :: string)
	end
	if rateRejections < 900 then
		table.insert(
			violations,
			`fixture: only {rateRejections} of {FLOOD_CALLS} calls were rate-rejected (the handler `
				.. `ran {#runs} time(s)); the flood did not flood`
		)
	end

	local fromCalls = #batches
	local ok, flushed = flush(reporter, START + FLOOD_CALLS / FLOOD_HZ)
	if not ok then
		table.insert(violations, `AC-5: flush RAISED: {tostring(flushed)}`)
		flushed = {}
	end
	local all = eventsOf(batches)
	for _, event in flushed do
		table.insert(all, event)
	end

	if fromCalls > 10 or #all > 11 or #all < 1 then
		table.insert(
			violations,
			`AC-5: {rateRejections} rate rejections produced {fromCalls} emit call(s) and `
				.. `{#flushed} flushed event(s), {#all} in all; bounded means at most 10 from the calls `
				.. `and 11 with the flush, and at least 1`
		)
	end
	for i, batch in batches do
		if typeof(batch) ~= "table" or #batch ~= 1 then
			table.insert(
				violations,
				`AC-5: emit call {i} was handed {Deep.show(batch)}; one event per batch`
			)
			break
		end
	end
	local total, missing = sumOfCounts(all)
	if total ~= rateRejections then
		table.insert(
			violations,
			`AC-5: sum(fields.count) over {#all} event(s) is {total} ({missing} carry no numeric `
				.. `count); the wrapper returned {rateRejections} rate Rejections and every one must be `
				.. `accounted for`
		)
	end
	for i, event in all do
		if typeof(event) ~= "table" or typeof(event.fields) ~= "table" then
			table.insert(violations, `AC-5: event {i} is {Deep.show(event)}`)
		elseif
			event.fields.reason ~= "rate"
			or event.fields.remote ~= definition.name
			or event.playerId ~= "p1"
		then
			table.insert(
				violations,
				`AC-5: event {i} is {describeEvent(event)}; every event is a rate event for p1 on {definition.name}`
			)
		end
	end

	if #violations ~= 0 then
		Contract.fail(
			`AC-5: {#violations} violation(s) over a {FLOOD_CALLS}-call flood through Wrapper.guard - an `
				.. `unbounded reporter, or one that loses the count, fails here:\n{indent(
					Contract.firstFew(violations, #violations)
				)}`
		)
	end
end

--[[
	Contract: a non-string caller id through the wrapper. A table sent as the
	player id is rejected for `identity` (it is not seated); the event carries
	`playerId = nil`, exactly three fields, and nothing about the caller - not
	its rendering, not the needle inside it.
]]
function RejectionContract.tableCallerIdIsNotPutInTheEvent(bundle: Bundle)
	local reporter = newReporter(bundle, "Contract")
	local definition = remote(bundle, "table_caller", RateContract.MIN_INTERVAL_SECONDS)
	local handler = NetContract.recorder()
	local context, world, batches = telemetryWorld({ "p1" }, reporter)
	local guarded = bundle.Wrapper.guard(definition, context, handler)
	local violations: { string } = {}

	world.clock:set(START + 2)
	local callers: { { label: string, id: any } } = {
		{ label = "a table", id = { HOSTILE = NEEDLE } },
		{ label = "a number", id = NEEDLE_NUMBER },
		{ label = "nil", id = nil },
	}
	for _, caller in callers do
		local before = #batches
		local ok, result = call(guarded, caller.id, VALID)
		local violation =
			expectRejection("Contract", `{caller.label} as the caller id`, ok, result, "identity")
		if violation ~= nil then
			table.insert(violations, violation :: string)
			continue
		end
		local events = eventsOf({ table.unpack(batches, before + 1) })
		if #events ~= 1 then
			table.insert(
				violations,
				`Contract: {caller.label} as the caller id -> {#events} event(s); exactly one`
			)
			continue
		end
		local event = events[1]
		if event.playerId ~= nil then
			table.insert(
				violations,
				`Contract: {caller.label} as the caller id -> playerId is {Deep.show(event.playerId)}; `
					.. `the envelope's playerId is string? and an attacker-chosen value is not put in it`
			)
		end
		fieldKeysAreExactly(`Contract: {caller.label} as the caller id`, event, violations)
		-- The caller's exact rendering (`table: 0x...`, `424242`, `nil`) and the
		-- needle inside the table; not the bare word "table", which a remote's
		-- own name may contain.
		if fieldsMention(event, NEEDLE) or fieldsMention(event, tostring(caller.id)) then
			table.insert(
				violations,
				`Contract: {caller.label} as the caller id -> fields mention the caller: {Deep.show(
					event.fields
				)}`
			)
		end
		diffEvent(
			`Contract: {caller.label} as the caller id`,
			event,
			expectedEvent(world.clock.now(), nil, definition.name, "identity", 1),
			violations
		)
		reconstructs(`Contract: {caller.label} as the caller id`, bundle, event, violations)
	end

	if #violations ~= 0 then
		Contract.fail(
			`Contract: {#violations} violation(s) across {#callers} non-string caller ids:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

return RejectionContract
