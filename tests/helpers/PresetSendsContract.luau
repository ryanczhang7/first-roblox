--!strict
--[[
	CHAN-004 AC-4 (the pure half), AC-5 and AC-6, plus the Contract's C-4
	(order) and C-5 (immutability, fresh positions, exact keys), written once
	as checks over a `PresetSends` MODULE handed in as a parameter - `{ new,
	send }` - rather than over `src/server/channel/PresetSends.luau` by name.
	`tests/server/preset_sends_test.luau` applies these to the real module;
	`tests/server/preset_sends_controls_test.luau` applies them to
	`PresetSendsStubs.luau`'s reference and to implementations with EXACTLY
	ONE defect each, so that in RED - where the module does not exist and
	every check against it stops at `need()` - every check here has still been
	EXECUTED and observed to refuse the implementation it exists to catch.

	EVERY CRITERION HERE IS MECHANICAL (story `## Contract`, "Oracle
	partition"): exact result tables compared with `Deep.equal`, so an extra
	key, a missing key or a wrong value is reported by name; exact decline
	counts; exact filter call counts and arguments. Nothing is designed; it is
	read out of C-4's four steps and C-5.

	THE INPUT DOMAIN IS THE PRESET TABLE. Which presets are legal in which
	phase is READ out of `Presets.ALL` (CHAN-002, merged) and the phase names
	out of `PhaseUnion.KNOWN`, never restated: every preset is driven in every
	phase its row excludes (AC-4) and in every phase it lists (AC-5, AC-6), so
	a preset table change re-reds this suite by itself.

	THE FILTER IS A STAND-IN (C-8): plain functions that echo, that return a
	DIFFERENT string (`HASHED`, which proves `text` is the returned string and
	not the word), that return `(false, nil)`, `(true, nil)`, `(false, word)`,
	`(true, 42)`, and that raise. Each records every call. No `TextService`.

	"ADDRESSED TO THE SENDER ONLY" IS THE RETURN VALUE (C-6): a `failed`
	result is pinned as the value `send` returns, with the log unchanged and
	nothing shown. There is no transport here.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local PhaseUnion = require("./PhaseUnion")
local Presets = require("../../src/shared/channel/Presets")

local PresetSendsContract = {}

export type Position = { x: number, y: number, z: number }
export type PresetSends = any
export type FilterRecord = { calls: { { senderId: any, text: any } } }
export type Check = { name: string, ac: string, run: (PresetSends) -> ...any }

PresetSendsContract.SENDER = "kim"
PresetSendsContract.OTHER = "lee"
PresetSendsContract.NOW = 100
PresetSendsContract.HASHED = "####"

-- Not on an axis and not at the origin, so a copy that drops or swaps a
-- component is visible.
function PresetSendsContract.position(): Position
	return { x = 3, y = 1, z = -4 }
end

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
end

--[[ ------------------------------------------------------------------------
     The input domain, read out of the preset table.
     --------------------------------------------------------------------- ]]

-- Every preset, as `Presets.ALL` lists it.
function PresetSendsContract.presets(): { Presets.Preset }
	return Presets.ALL
end

-- The phases a preset's row excludes, in `PhaseUnion.KNOWN` order.
function PresetSendsContract.illegalPhasesOf(preset: Presets.Preset): { string }
	local out: { string } = {}
	for _, phase in PhaseUnion.KNOWN do
		if table.find(preset.phases, phase) == nil then
			table.insert(out, phase)
		end
	end
	return out
end

-- The first preset whose row lists `phase`, or nil.
function PresetSendsContract.aPresetLegalIn(phase: string): Presets.Preset?
	for _, preset in Presets.ALL do
		if table.find(preset.phases, phase) ~= nil then
			return preset
		end
	end
	return nil
end

-- The first preset whose row does NOT list `phase`, or nil.
function PresetSendsContract.aPresetIllegalIn(phase: string): Presets.Preset?
	for _, preset in Presets.ALL do
		if table.find(preset.phases, phase) == nil then
			return preset
		end
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     The filter stand-ins (C-8).
     --------------------------------------------------------------------- ]]

local function recording(answer: (string) -> (boolean, any)): (any, FilterRecord)
	local record: FilterRecord = { calls = {} }
	local function filter(senderId: any, text: any): (boolean, any)
		table.insert(record.calls, { senderId = senderId, text = text })
		return answer(text)
	end
	return filter, record
end

-- A filter that returns its input unchanged.
function PresetSendsContract.echo(): (any, FilterRecord)
	return recording(function(text: string): (boolean, any)
		return true, text
	end)
end

-- A filter that returns `HASHED`, whatever it is given.
function PresetSendsContract.hashed(): (any, FilterRecord)
	return recording(function(_text: string): (boolean, any)
		return true, PresetSendsContract.HASHED
	end)
end

export type FailingFilter = { label: string, make: () -> (any, FilterRecord) }

-- Every way the port can fail (C-4 step 3): a raise, `ok` false, and a
-- non-string text with `ok` true.
function PresetSendsContract.failingFilters(): { FailingFilter }
	return {
		{
			label = "a filter returning (false, nil)",
			make = function(): (any, FilterRecord)
				return recording(function(_text: string): (boolean, any)
					return false, nil
				end)
			end,
		},
		{
			label = "a filter returning (true, nil)",
			make = function(): (any, FilterRecord)
				return recording(function(_text: string): (boolean, any)
					return true, nil
				end)
			end,
		},
		{
			label = "a filter that raises",
			make = function(): (any, FilterRecord)
				return recording(function(_text: string): (boolean, any)
					error("TextService: service error")
				end)
			end,
		},
		{
			label = "a filter returning (false, the word)",
			make = function(): (any, FilterRecord)
				return recording(function(text: string): (boolean, any)
					return false, text
				end)
			end,
		},
		{
			label = "a filter returning (true, 42)",
			make = function(): (any, FilterRecord)
				return recording(function(_text: string): (boolean, any)
					return true, 42
				end)
			end,
		},
	}
end

-- A `CallControl` counting its declines.
function PresetSendsContract.control(): (any, { declines: number })
	local count = { declines = 0 }
	local control = {
		decline = function()
			count.declines += 1
		end,
	}
	return control, count
end

-- A state with one prior entry, so "the log is unchanged" is not "the log
-- is still empty".
function PresetSendsContract.seededState(): any
	return {
		log = {
			{
				senderId = PresetSendsContract.OTHER,
				presetId = 1,
				position = { x = 0, y = 0, z = 0 },
				at = PresetSendsContract.NOW - 50,
			},
		},
	}
end

local function need(criterion: string, P: PresetSends, name: string)
	if typeof(P) ~= "table" then
		Contract.fail(`{criterion}: PresetSends is {Deep.show(P)}, expected the module table`)
	end
	if typeof(P[name]) ~= "function" then
		Contract.fail(`{criterion}: PresetSends.{name} is {typeof(P[name])}, expected a function`)
	end
end

local function finish(criterion: string, violations: { string }, summary: string)
	if #violations > 0 then
		Contract.fail(
			`{criterion}: {#violations} violation(s) for {summary}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

-- `send` under pcall: a raise is a violation, not the end of the check.
local function send(
	P: PresetSends,
	state: any,
	senderId: string,
	presetId: number,
	phase: string,
	position: Position,
	now: number,
	filter: any,
	control: any
): (boolean, any, any)
	return pcall(P.send, state, senderId, presetId, phase, position, now, filter, control)
end

--[[ ------------------------------------------------------------------------
     C-5: `new`.
     --------------------------------------------------------------------- ]]

-- `new()` is exactly `{ log = {} }`, and two calls are two tables.
function PresetSendsContract.newIsAnEmptyLog(P: PresetSends)
	need("Contract (new)", P, "new")
	local ok, state = pcall(P.new)
	if not ok then
		Contract.fail(`Contract (new): PresetSends.new() RAISED: {tostring(state)}`)
	end
	local diff = Deep.diff({ log = {} }, state)
	if diff ~= "" then
		Contract.fail(
			`Contract (new): PresetSends.new() is {Deep.show(state)}, expected exactly \{ log = \{} }:\n{indent(
				diff
			)}`
		)
	end
	local second = P.new()
	if rawequal(second, state) or rawequal(second.log, state.log) then
		Contract.fail(
			"Contract (new): two calls to PresetSends.new() share a table; each is a fresh state"
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-4, pure half: the per-preset phase check.
     --------------------------------------------------------------------- ]]

--[[
	Every preset in every phase its row excludes (`Well played` in `Round`
	among them): the result is exactly `{ kind = "failed", failed = { presetId,
	reason = "phase_for_preset" } }`, the call is declined exactly once, the
	filter is NOT called, the returned state's log equals the given one by
	value, and the given state is untouched. Driven with the `hashed` filter,
	which would show something if it were reached.
]]
function PresetSendsContract.outOfPhasePresetIsFailedForPhaseDeclinedOnceAndNeverFiltered(
	P: PresetSends
)
	need("AC-4", P, "send")
	local sender = PresetSendsContract.SENDER
	local now = PresetSendsContract.NOW
	local violations: { string } = {}
	local cases = 0
	for _, preset in PresetSendsContract.presets() do
		for _, phase in PresetSendsContract.illegalPhasesOf(preset) do
			cases += 1
			local label =
				`{preset.word} (id {preset.id}, phases {Deep.show(preset.phases)}) in {phase}`
			local state = PresetSendsContract.seededState()
			local before = Deep.copy(state)
			local filter, record = PresetSendsContract.hashed()
			local control, count = PresetSendsContract.control()
			local ok, newState, result = send(
				P,
				state,
				sender,
				preset.id,
				phase,
				PresetSendsContract.position(),
				now,
				filter,
				control
			)
			if not ok then
				table.insert(violations, `AC-4: {label} -> send RAISED: {tostring(newState)}`)
				continue
			end
			local want = {
				kind = "failed",
				failed = { presetId = preset.id, reason = "phase_for_preset" },
			}
			local diff = Deep.diff(want, result)
			if diff ~= "" then
				table.insert(
					violations,
					`AC-4: {label} -> the result is not exactly {Deep.show(want)}:\n{indent(diff)}`
				)
			end
			if count.declines ~= 1 then
				table.insert(
					violations,
					`AC-4: {label} -> call.decline() was called {count.declines} time(s), expected exactly once`
				)
			end
			if #record.calls ~= 0 then
				table.insert(
					violations,
					`AC-4: {label} -> the filter was called {#record.calls} time(s) for a preset refused by its own phase list; expected never`
				)
			end
			if typeof(newState) ~= "table" or not Deep.equal(newState.log, before.log) then
				table.insert(
					violations,
					`AC-4: {label} -> the returned state's log changed: {Deep.diff(
						before.log,
						if typeof(newState) == "table" then newState.log else newState
					)}`
				)
			end
			if not Deep.equal(state, before) then
				table.insert(
					violations,
					`AC-4: {label} -> send wrote into the state it was given: {Deep.diff(
						before,
						state
					)}`
				)
			end
		end
	end
	if cases == 0 then
		table.insert(violations, "fixture: no preset excludes any phase - the preset table changed")
	end
	finish(
		"AC-4",
		violations,
		`{cases} out-of-phase sends (phase_for_preset, declined, unfiltered)`
	)
end

--[[ ------------------------------------------------------------------------
     AC-5: a legal preset through a succeeding filter.
     --------------------------------------------------------------------- ]]

--[[
	Every preset in every phase its row lists, with a filter returning
	`HASHED` rather than the word: the result is exactly `{ kind = "shown",
	shown = { senderId, presetId, position, text = HASHED } }`, the returned
	state is exactly the old log plus `{ senderId, presetId, position, at =
	now }`, the filter was called exactly once with `(senderId, preset.word)`,
	the call was never declined, and the given state is untouched. One send
	through the `echo` filter shows the word, so `text` is what the filter
	returned in both directions.
]]
function PresetSendsContract.legalPresetIsShownWithTheFiltersTextAndLogged(P: PresetSends)
	need("AC-5", P, "send")
	local sender = PresetSendsContract.SENDER
	local now = PresetSendsContract.NOW
	local hashed = PresetSendsContract.HASHED
	local violations: { string } = {}
	local cases = 0
	for _, preset in PresetSendsContract.presets() do
		for _, phase in preset.phases do
			cases += 1
			local label = `{preset.word} (id {preset.id}) in {phase}`
			local state = PresetSendsContract.seededState()
			local before = Deep.copy(state)
			local position = PresetSendsContract.position()
			local filter, record = PresetSendsContract.hashed()
			local control, count = PresetSendsContract.control()
			local ok, newState, result =
				send(P, state, sender, preset.id, phase, position, now, filter, control)
			if not ok then
				table.insert(violations, `AC-5: {label} -> send RAISED: {tostring(newState)}`)
				continue
			end
			local wantShown = {
				kind = "shown",
				shown = {
					senderId = sender,
					presetId = preset.id,
					position = PresetSendsContract.position(),
					text = hashed,
				},
			}
			local diff = Deep.diff(wantShown, result)
			if diff ~= "" then
				table.insert(
					violations,
					`AC-5: {label} -> the result is not exactly {Deep.show(wantShown)}:\n{indent(
						diff
					)}`
				)
			end
			local wantLog = Deep.copy(before.log)
			table.insert(wantLog, {
				senderId = sender,
				presetId = preset.id,
				position = PresetSendsContract.position(),
				at = now,
			})
			local logDiff = Deep.diff({ log = wantLog }, newState)
			if logDiff ~= "" then
				table.insert(
					violations,
					`AC-5: {label} -> the returned state is not exactly the old log plus \{ senderId, presetId, position, at = now }:\n{indent(
						logDiff
					)}`
				)
			end
			if #record.calls ~= 1 then
				table.insert(
					violations,
					`AC-5: {label} -> the filter was called {#record.calls} time(s), expected exactly once (architecture.md §9.5.1)`
				)
			elseif record.calls[1].senderId ~= sender or record.calls[1].text ~= preset.word then
				table.insert(
					violations,
					`AC-5: {label} -> the filter was called with ({Deep.show(
						record.calls[1].senderId
					)}, {Deep.show(record.calls[1].text)}), expected ("{sender}", "{preset.word}")`
				)
			end
			if count.declines ~= 0 then
				table.insert(
					violations,
					`AC-5: {label} -> call.decline() was called {count.declines} time(s) on a SHOWN preset; expected never`
				)
			end
			if not Deep.equal(state, before) then
				table.insert(
					violations,
					`AC-5: {label} -> send wrote into the state it was given (C-5): {Deep.diff(
						before,
						state
					)}`
				)
			end
		end
	end

	-- The echo direction: the word comes back as the word.
	local preset = PresetSendsContract.aPresetLegalIn("Round")
	if preset == nil then
		table.insert(violations, "fixture: no preset is legal in Round")
	else
		local filter = PresetSendsContract.echo()
		local control = PresetSendsContract.control()
		local ok, _, result = send(
			P,
			P.new(),
			sender,
			preset.id,
			"Round",
			PresetSendsContract.position(),
			now,
			filter,
			control
		)
		if not ok then
			table.insert(violations, `AC-5: {preset.word} through echo -> send RAISED`)
		elseif
			typeof(result) ~= "table"
			or typeof(result.shown) ~= "table"
			or result.shown.text ~= preset.word
		then
			table.insert(
				violations,
				`AC-5: {preset.word} through an echo filter -> shown.text is {Deep.show(
					if typeof(result) == "table" and typeof(result.shown) == "table"
						then result.shown.text
						else result
				)}, expected the echoed word "{preset.word}"`
			)
		end
	end
	if cases == 0 then
		table.insert(violations, "fixture: no preset lists any phase - the preset table changed")
	end
	finish("AC-5", violations, `{cases} legal sends through a succeeding filter`)
end

--[[
	C-5: `position` in `PresetShown` and in the log entry is a FRESH copy. Not
	the caller's table, and unmoved when the caller's table is written to
	afterwards.
]]
function PresetSendsContract.positionsInTheResultAndTheLogAreFreshCopies(P: PresetSends)
	need("Contract (C-5)", P, "send")
	local preset = PresetSendsContract.aPresetLegalIn("Round")
	if preset == nil then
		Contract.fail("Contract (C-5): fixture: no preset is legal in Round")
	end
	local given = PresetSendsContract.position()
	local original = PresetSendsContract.position()
	local filter = PresetSendsContract.hashed()
	local control = PresetSendsContract.control()
	local ok, newState, result = send(
		P,
		P.new(),
		PresetSendsContract.SENDER,
		(preset :: Presets.Preset).id,
		"Round",
		given,
		PresetSendsContract.NOW,
		filter,
		control
	)
	if not ok then
		Contract.fail(`Contract (C-5): send RAISED: {tostring(newState)}`)
	end
	local violations: { string } = {}
	local shownPosition = if typeof(result) == "table" and typeof(result.shown) == "table"
		then result.shown.position
		else nil
	local entry = if typeof(newState) == "table" and typeof(newState.log) == "table"
		then newState.log[1]
		else nil
	local entryPosition = if typeof(entry) == "table" then entry.position else nil
	if shownPosition == nil then
		table.insert(
			violations,
			`Contract (C-5): no shown.position in the result {Deep.show(result)}`
		)
	elseif rawequal(shownPosition, given) then
		table.insert(
			violations,
			"Contract (C-5): shown.position IS the caller's table; expected a fresh { x, y, z } copy"
		)
	end
	if entryPosition == nil then
		table.insert(
			violations,
			`Contract (C-5): no log entry with a position in the returned state {Deep.show(newState)}`
		)
	elseif rawequal(entryPosition, given) then
		table.insert(
			violations,
			"Contract (C-5): the log entry's position IS the caller's table; expected a fresh copy"
		)
	end
	-- Write to the caller's table afterwards: neither copy may move.
	given.x += 1000
	given.y += 1000
	given.z += 1000
	if shownPosition ~= nil and not Deep.equal(shownPosition, original) then
		table.insert(
			violations,
			`Contract (C-5): writing to the caller's position afterwards moved shown.position to {Deep.show(
				shownPosition
			)}; expected {Deep.show(original)}`
		)
	end
	if entryPosition ~= nil and not Deep.equal(entryPosition, original) then
		table.insert(
			violations,
			`Contract (C-5): writing to the caller's position afterwards moved the log entry's position to {Deep.show(
				entryPosition
			)}; expected {Deep.show(original)}`
		)
	end
	finish("Contract (C-5)", violations, "fresh position copies in the result and the log")
end

--[[ ------------------------------------------------------------------------
     AC-6: a failing filter, fail closed.
     --------------------------------------------------------------------- ]]

--[[
	Every preset in its first legal phase, through each failing filter: `send`
	does not raise (a raise is contained by `pcall`), the result is exactly
	`{ kind = "failed", failed = { presetId, reason = "filter" } }`, the call is
	declined exactly once, the filter was called exactly once, the returned
	state's log equals the given one by value, and the given state is
	untouched. Nothing shown, nothing logged.
]]
function PresetSendsContract.filterFailureIsFailedForFilterDeclinedOnceAndNothingIsShownOrLogged(
	P: PresetSends
)
	need("AC-6", P, "send")
	local sender = PresetSendsContract.SENDER
	local now = PresetSendsContract.NOW
	local violations: { string } = {}
	local cases = 0
	for _, preset in PresetSendsContract.presets() do
		local phase = preset.phases[1]
		for _, failing in PresetSendsContract.failingFilters() do
			cases += 1
			local label = `{preset.word} (id {preset.id}) in {phase} through {failing.label}`
			local state = PresetSendsContract.seededState()
			local before = Deep.copy(state)
			local filter, record = failing.make()
			local control, count = PresetSendsContract.control()
			local ok, newState, result = send(
				P,
				state,
				sender,
				preset.id,
				phase,
				PresetSendsContract.position(),
				now,
				filter,
				control
			)
			if not ok then
				table.insert(
					violations,
					`AC-6: {label} -> send RAISED: {tostring(newState)}; a filter failure never escapes send`
				)
				continue
			end
			local want = { kind = "failed", failed = { presetId = preset.id, reason = "filter" } }
			local diff = Deep.diff(want, result)
			if diff ~= "" then
				table.insert(
					violations,
					`AC-6: {label} -> the result is not exactly {Deep.show(want)}:\n{indent(diff)}`
				)
			end
			if count.declines ~= 1 then
				table.insert(
					violations,
					`AC-6: {label} -> call.decline() was called {count.declines} time(s), expected exactly once`
				)
			end
			if #record.calls ~= 1 then
				table.insert(
					violations,
					`AC-6: {label} -> the filter was called {#record.calls} time(s), expected exactly once`
				)
			end
			if typeof(newState) ~= "table" or not Deep.equal(newState.log, before.log) then
				table.insert(
					violations,
					`AC-6: {label} -> the returned state's log changed (something was logged): {Deep.diff(
						before.log,
						if typeof(newState) == "table" then newState.log else newState
					)}`
				)
			end
			if not Deep.equal(state, before) then
				table.insert(
					violations,
					`AC-6: {label} -> send wrote into the state it was given: {Deep.diff(
						before,
						state
					)}`
				)
			end
		end
	end
	finish("AC-6", violations, `{cases} sends through a failing filter (fail closed)`)
end

--[[ ------------------------------------------------------------------------
     AC-5, many: the log accumulates.
     --------------------------------------------------------------------- ]]

--[[
	From `new()`: three shown sends by two senders at rising instants, with a
	phase-refused and a filter-refused send between them, leave a log of
	exactly those three entries in send order, and every intermediate state
	is left as it was (an implementation that appends in place fails the
	snapshot of the first state).
]]
function PresetSendsContract.theLogAccumulatesEveryShownSendInOrder(P: PresetSends)
	need("AC-5", P, "send")
	need("AC-5", P, "new")
	local a, b = PresetSendsContract.SENDER, PresetSendsContract.OTHER
	local first = PresetSendsContract.aPresetLegalIn("Round")
	local refused = PresetSendsContract.aPresetIllegalIn("Round")
	if first == nil or refused == nil then
		Contract.fail("AC-5: fixture: the preset table has no Round preset or no non-Round preset")
	end
	local legal = (first :: Presets.Preset).id
	local illegal = (refused :: Presets.Preset).id
	local position = PresetSendsContract.position()
	local hashed = PresetSendsContract.hashed()
	local failing = PresetSendsContract.failingFilters()[1].make()
	local violations: { string } = {}

	local s0 = P.new()
	local snapshot0 = Deep.copy(s0)
	local function step(
		state: any,
		label: string,
		senderId: string,
		presetId: number,
		now: number,
		filter: any,
		expectKind: string
	): any
		local control = PresetSendsContract.control()
		local ok, newState, result =
			send(P, state, senderId, presetId, "Round", position, now, filter, control)
		if not ok then
			table.insert(violations, `AC-5: {label} -> send RAISED: {tostring(newState)}`)
			return state
		end
		if typeof(result) ~= "table" or result.kind ~= expectKind then
			table.insert(
				violations,
				`AC-5: {label} -> result {Deep.show(result)}, expected kind "{expectKind}"`
			)
		end
		return newState
	end
	local s1 = step(s0, "a sends at 100", a, legal, 100, hashed, "shown")
	local s2 = step(s1, "a sends an out-of-phase preset at 101", a, illegal, 101, hashed, "failed")
	local s3 = step(s2, "b sends at 102", b, legal, 102, hashed, "shown")
	local s4 = step(s3, "b's filter fails at 103", b, legal, 103, failing, "failed")
	local s5 = step(s4, "a sends again at 110", a, legal, 110, hashed, "shown")

	local want = {
		log = {
			{ senderId = a, presetId = legal, position = PresetSendsContract.position(), at = 100 },
			{ senderId = b, presetId = legal, position = PresetSendsContract.position(), at = 102 },
			{ senderId = a, presetId = legal, position = PresetSendsContract.position(), at = 110 },
		},
	}
	local diff = Deep.diff(want, s5)
	if diff ~= "" then
		table.insert(
			violations,
			`AC-5: after three shown and two refused sends the state is not exactly the three entries in order:\n{indent(
				diff
			)}`
		)
	end
	if not Deep.equal(s0, snapshot0) then
		table.insert(
			violations,
			`AC-5: the state new() returned was written to by later sends (C-5): {Deep.diff(
				snapshot0,
				s0
			)}`
		)
	end
	if typeof(s1) == "table" and typeof(s1.log) == "table" and #s1.log ~= 1 then
		table.insert(
			violations,
			`AC-5: the state after the first send holds {#s1.log} entries after later sends; expected 1 (C-5)`
		)
	end
	finish("AC-5", violations, "the log over a sequence of shown and refused sends")
end

--[[ ------------------------------------------------------------------------
     The battery, named.
     --------------------------------------------------------------------- ]]

PresetSendsContract.CHECKS = {
	{ name = "newIsAnEmptyLog", ac = "Contract (new)", run = PresetSendsContract.newIsAnEmptyLog },
	{
		name = "outOfPhasePresetIsFailedForPhaseDeclinedOnceAndNeverFiltered",
		ac = "AC-4",
		run = PresetSendsContract.outOfPhasePresetIsFailedForPhaseDeclinedOnceAndNeverFiltered,
	},
	{
		name = "legalPresetIsShownWithTheFiltersTextAndLogged",
		ac = "AC-5",
		run = PresetSendsContract.legalPresetIsShownWithTheFiltersTextAndLogged,
	},
	{
		name = "positionsInTheResultAndTheLogAreFreshCopies",
		ac = "Contract (C-5)",
		run = PresetSendsContract.positionsInTheResultAndTheLogAreFreshCopies,
	},
	{
		name = "filterFailureIsFailedForFilterDeclinedOnceAndNothingIsShownOrLogged",
		ac = "AC-6",
		run = PresetSendsContract.filterFailureIsFailedForFilterDeclinedOnceAndNothingIsShownOrLogged,
	},
	{
		name = "theLogAccumulatesEveryShownSendInOrder",
		ac = "AC-5",
		run = PresetSendsContract.theLogAccumulatesEveryShownSendInOrder,
	},
} :: { Check }

-- Every check against `P`; the names of those that raised, with messages.
function PresetSendsContract.failures(P: PresetSends): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in PresetSendsContract.CHECKS do
		local ok, err = pcall(check.run, P)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return PresetSendsContract
