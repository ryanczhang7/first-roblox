--!strict
--[[
	CHAN-004 AC-1, AC-2, AC-3, AC-4's guarded half and AC-7, written once as
	checks over a `Net` bundle - `{ Schema, Remotes, Wrapper }` - and a
	`SendPreset` REMOTE DEFINITION handed in as a parameter, rather than over
	`src/net/GameRemotes.luau` by name. The same arrangement as
	`PingRemoteContract.luau`, for the same reason:
	`tests/net/preset_remote_test.luau` applies these to the real
	`GameRemotes.SendPreset`, and `tests/net/preset_remote_controls_test.luau`
	applies them to declarations with EXACTLY ONE defect each - the rate at
	9.5, no attempt floor, an extra legal phase, a missing one, a bound one
	too high, `number()` for `integer()`, an optional `to`, ten per-preset
	limiters - so that in RED, where `GameRemotes.SendPreset` does not exist
	and not one assertion in the real file has executed, every check here has
	still been EXECUTED and observed to reject the declaration it exists to
	catch.

	THE ORACLE PARTITION (story `## Contract`) IS HONOURED HERE. AC-1 is
	SETTLED and is READ, never re-derived: the rate is what `RateLimitSpec`
	reads for `preset_rate_limit_seconds` out of `docs/wiki/game/tuning.md`,
	compared against `MechanicsTuning.channel.preset_rate_limit_seconds` and
	the published floor `RateLimitSpec.FLOOR_SECONDS`; the attempt floor is
	`MechanicsTuning.channel.channel_attempt_min_interval_seconds`; the schema
	bound is `channel.preset_count`. The legal phases are DERIVED (C-2): the
	union of `Presets.ALL[*].phases`, ordered by `PhaseUnion.KNOWN` (the phase
	machine's order) with absent phases dropped. Nothing below writes 10, 1 or
	a phase name where a constant is meant. The DECLARATION is compared - the
	table `Remotes.all()` lists - never a copy of the number.

	AC-2, AC-3 AND AC-7 ARE MECHANICAL: B4's triple - malformed, out-of-phase,
	flooded - through the REAL `Wrapper.guard` over the definition under test.
	The malformed and phase halves use a recording handler whose call count is
	the assertion "the handler never ran". AC-4's guarded half and AC-7 run
	the handler `SLICE-006` will ship: `PresetSends.send` over the validated
	args, with the wrapper's `CallControl` passed on (C-7). Those two take the
	`PresetSends` module as a parameter: the real one in `preset_remote_test`,
	`PresetSendsStubs.reference` in the controls. The two rate refusals are
	told apart by their WHOLE detail string (`DeclineContract.attemptDetail`
	/ `sendDetail`): a substring of either is satisfied by the other.

	THE SUBJECT OF A GUARDED CHECK MAY BE A GUARD FACTORY. AC-7's required
	control is not one declaration with one defect: it is ten declarations,
	one per preset id, behind a dispatcher (C-7). So the checks that build a
	guard do it through `guardFor`, which accepts either a `RemoteDefinition`
	(the usual case) or a table with a `guard(context, handler)` function. A
	real definition has no `guard` field.

	NO ROBLOX, NO `Players`, NO ROUND, NO REAL TIME. The `GuardContext` is
	`RateContract.world`'s: `isSeated` answers for the listed players, `phase`
	is a mutable field, and the clock is `Clock.manual`, SET to each instant.
	Every check builds its OWN guard, so no rate state leaks between checks.
	Nothing here declares `"SendPreset"`: the registry is process-wide and
	refuses a duplicate; `declare` names its declarations uniquely.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local DeclineContract = require("./DeclineContract")
local Deep = require("./Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local NetContract = require("./NetContract")
local PhaseUnion = require("./PhaseUnion")
local Presets = require("../../src/shared/channel/Presets")
local PresetSendsContract = require("./PresetSendsContract")
local RateContract = require("./RateContract")
local RateLimitSpec = require("./RateLimitSpec")

local PresetRemoteContract = {}

export type Net = { Schema: any, Remotes: any, Wrapper: any }

-- The seated callers. Every single-caller check uses CALLER; AC-7 seats both.
PresetRemoteContract.CALLER = "kim"
PresetRemoteContract.SECOND = "lee"

-- A start instant that is not 0, so `now - lastAccepted` and `now` differ.
PresetRemoteContract.START = 10

-- How far past the attempt floor (and how far short of a limit) a call lands.
PresetRemoteContract.EPSILON = 0.1

local function presetCount(): number
	return MechanicsTuning.channel.preset_count
end

PresetRemoteContract.presetCount = presetCount

-- AC-1's settled numbers, read where the Contract says they live.
function PresetRemoteContract.rateLimitSeconds(): number
	return MechanicsTuning.channel.preset_rate_limit_seconds
end

function PresetRemoteContract.attemptSeconds(): number
	return MechanicsTuning.channel.channel_attempt_min_interval_seconds
end

--[[
	The value `RateLimitSpec` reads for `preset_rate_limit_seconds` out of
	`tuning.md`: exactly one row, a bare number. Raises (naming the document)
	when the document does not fix it, so a comparison against nothing never
	passes.
]]
function PresetRemoteContract.documentRateLimitSeconds(): number
	local name = RateLimitSpec.NAMES[1]
	assert(name == "preset_rate_limit_seconds", `RateLimitSpec.NAMES[1] is {name}`)
	local rows = RateLimitSpec.rowsNaming(RateLimitSpec.read(), name)
	local violations = RateLimitSpec.violations(rows, name, RateLimitSpec.FLOOR_SECONDS)
	if #violations > 0 then
		Contract.fail(
			`AC-1: {RateLimitSpec.SPEC_PATH} does not fix {name}:\n{RateLimitSpec.describe(
				violations
			)}`
		)
	end
	return tonumber(rows[1].valueCell) :: number
end

--[[
	C-2: the union of `Presets.ALL[*].phases`, in `PhaseUnion.KNOWN` order,
	absent phases dropped. A phase name in the table that the phase machine
	does not know is a fixture failure, not a silent drop.
]]
function PresetRemoteContract.legalPhases(): { string }
	local union: { [string]: boolean } = {}
	for _, preset in Presets.ALL do
		for _, phase in preset.phases do
			union[phase] = true
		end
	end
	local out: { string } = {}
	for _, phase in PhaseUnion.KNOWN do
		if union[phase] then
			table.insert(out, phase)
			union[phase] = nil
		end
	end
	for stray in union do
		Contract.fail(
			`fixture: Presets.ALL names the phase "{stray}", which PhaseUnion.KNOWN does not list`
		)
	end
	return out
end

-- `PhaseUnion.KNOWN` minus the legal phases, in the same order.
function PresetRemoteContract.illegalPhases(): { string }
	local legal = PresetRemoteContract.legalPhases()
	local out: { string } = {}
	for _, phase in PhaseUnion.KNOWN do
		if table.find(legal, phase) == nil then
			table.insert(out, phase)
		end
	end
	return out
end

-- A preset id legal in `phase` (the first such row), raising when none is.
function PresetRemoteContract.aPresetIdLegalIn(phase: string): number
	local preset = PresetSendsContract.aPresetLegalIn(phase)
	if preset == nil then
		Contract.fail(`fixture: no preset is legal in {phase}`)
	end
	return (preset :: Presets.Preset).id
end

-- Two DIFFERENT preset ids both legal in `phase`, raising when there are not two.
function PresetRemoteContract.twoPresetIdsLegalIn(phase: string): (number, number)
	local found: { number } = {}
	for _, preset in Presets.ALL do
		if table.find(preset.phases, phase) ~= nil then
			table.insert(found, preset.id)
		end
		if #found == 2 then
			break
		end
	end
	if #found < 2 then
		Contract.fail(`fixture: fewer than two presets are legal in {phase}`)
	end
	return found[1], found[2]
end

-- A preset id whose row EXCLUDES `phase` (the first such row), raising when none does.
function PresetRemoteContract.aPresetIdIllegalIn(phase: string): number
	local preset = PresetSendsContract.aPresetIllegalIn(phase)
	if preset == nil then
		Contract.fail(`fixture: every preset is legal in {phase}`)
	end
	return (preset :: Presets.Preset).id
end

function PresetRemoteContract.wellFormed(): any
	return { preset = 1 }
end

function PresetRemoteContract.wellFormedAtTheMaximum(): any
	return { preset = presetCount() }
end

local function indent(text: string): string
	return "  " .. (string.gsub(text, "\n", "\n  "))
end

local function describeResult(result: any): string
	if typeof(result) == "table" then
		return `reason = {Deep.show(result.reason)}, detail = {Deep.show(result.detail)}`
	end
	return Deep.show(result)
end

local function call(guarded: any, playerId: any, args: any): (boolean, any)
	return pcall(guarded, playerId, args)
end

local function expectRejection(
	criterion: string,
	label: string,
	ok: boolean,
	result: any,
	expected: string,
	detail: string?
): string?
	if not ok then
		return `{criterion}: {label} -> the guarded call RAISED instead of rejecting: {tostring(
			result
		)}`
	end
	if result == nil then
		return `{criterion}: {label} -> ACCEPTED (returned nil); expected a "{expected}" rejection`
	end
	if typeof(result) ~= "table" then
		return `{criterion}: {label} -> rejected with {Deep.show(result)}, which names no check`
	end
	if result.reason ~= expected then
		return `{criterion}: {label} -> rejected for {Deep.show(result.reason)}, expected "{expected}"`
	end
	if detail ~= nil and result.detail ~= detail then
		return `{criterion}: {label} -> rejected for "{expected}" with detail {Deep.show(
			result.detail
		)}, expected exactly {Deep.show(detail)}`
	end
	return nil
end

local function expectAcceptance(criterion: string, label: string, ok: boolean, result: any): string?
	if not ok then
		return `{criterion}: {label} -> the guarded call RAISED: {tostring(result)}`
	end
	if result ~= nil then
		return `{criterion}: {label} -> REJECTED: {describeResult(result)}`
	end
	return nil
end

local function requireDefinition(criterion: string, definition: any)
	if typeof(definition) ~= "table" then
		Contract.fail(
			`{criterion}: the SendPreset definition is {Deep.show(definition)}, not a table`
		)
	end
	if typeof(definition.args) ~= "table" or typeof(definition.args.validate) ~= "function" then
		Contract.fail(
			`{criterion}: the SendPreset definition's args is {Deep.show(definition.args)}; it must be a Schema with a validate function`
		)
	end
end

-- A subject of a guarded check: a definition, or a guard factory (see the header).
local function requireSubject(criterion: string, subject: any)
	if typeof(subject) == "table" and typeof(subject.guard) == "function" then
		if typeof(subject.name) ~= "string" then
			Contract.fail(`{criterion}: the guard factory has no name`)
		end
		return
	end
	requireDefinition(criterion, subject)
end

-- The guard over `subject` for `context` and `handler`; see the header.
function PresetRemoteContract.guardFor(net: Net, subject: any, context: any, handler: any): any
	if typeof(subject) == "table" and typeof(subject.guard) == "function" then
		return subject.guard(context, handler)
	end
	return net.Wrapper.guard(subject, context, handler)
end

type HandlerCall = { playerId: any, args: any, call: any }

-- A handler recording every invocation, with its third argument.
local function recorder(): (any, { HandlerCall })
	local calls: { HandlerCall } = {}
	local handler = function(playerId: any, args: any, control: any)
		table.insert(calls, { playerId = playerId, args = args, call = control })
	end
	return handler, calls
end

-- A guard over `definition` with a recording handler and an injected context
-- in which exactly CALLER is seated, the phase is `phase`, the clock reads START.
function PresetRemoteContract.guardWithSpy(
	net: Net,
	definition: any,
	phase: string
): (any, { HandlerCall }, RateContract.World)
	local handler, calls = recorder()
	local context, world =
		RateContract.world({ PresetRemoteContract.CALLER }, phase, PresetRemoteContract.START)
	local guarded = PresetRemoteContract.guardFor(net, definition, context, handler)
	return guarded, calls, world
end

--[[ ------------------------------------------------------------------------
     The reference declaration, with one edit at a time. Shared by both
     controls files; declared under a unique name through the REAL
     `Remotes.define`.
     --------------------------------------------------------------------- ]]

export type Edits = {
	presetMax: number?,
	presetIsNumber: boolean?,
	acceptsTo: boolean?,
	legalPhases: { string }?,
	rateLimitSeconds: number?,
	noRateLimit: boolean?,
	attemptSeconds: number?,
	noAttemptLimit: boolean?,
}

function PresetRemoteContract.declare(net: Net, label: string, edits: Edits): any
	local Schema = net.Schema
	local max = edits.presetMax or presetCount()
	local fields: { [string]: any } = {
		preset = if edits.presetIsNumber then Schema.number(1, max) else Schema.integer(1, max),
	}
	if edits.acceptsTo then
		fields.to = Schema.optional(Schema.literal(PresetRemoteContract.SECOND))
	end
	local spec: { [string]: any } = {
		args = Schema.shape(fields),
		legalPhases = edits.legalPhases or PresetRemoteContract.legalPhases(),
	}
	if not edits.noRateLimit then
		spec.rateLimit = {
			minIntervalSeconds = edits.rateLimitSeconds or PresetRemoteContract.rateLimitSeconds(),
		}
	end
	if not edits.noAttemptLimit then
		spec.attemptLimit = {
			minIntervalSeconds = edits.attemptSeconds or PresetRemoteContract.attemptSeconds(),
		}
	end
	return net.Remotes.define(NetContract.uniqueName(label), spec)
end

--[[
	AC-7's required control (C-7): ten reference declarations, one per preset
	id, each guarded on its own, behind a dispatcher that routes `{ preset =
	n }` to guard `n`. Every other field matches the reference, so only a
	check that sends two DIFFERENT presets by one player can tell it apart.
	The dispatcher sends an unroutable payload to guard 1, so shape and range
	rejections still come from a real guard.
]]
function PresetRemoteContract.declarePerPreset(net: Net, label: string): any
	local definitions: { any } = {}
	for id = 1, presetCount() do
		definitions[id] = PresetRemoteContract.declare(net, `{label}_preset{id}`, {})
	end
	return {
		name = definitions[1].name,
		definitions = definitions,
		guard = function(context: any, handler: any): any
			local guards: { any } = {}
			for id, definition in definitions do
				guards[id] = net.Wrapper.guard(definition, context, handler)
			end
			return function(playerId: any, rawArgs: any): any
				local id = if typeof(rawArgs) == "table" then rawArgs.preset else nil
				local guarded = if typeof(id) == "number" then guards[id] else nil
				return (guarded or guards[1])(playerId, rawArgs)
			end
		end,
	}
end

--[[ ------------------------------------------------------------------------
     AC-1, settled: the rate, the attempt floor, the registry.
     --------------------------------------------------------------------- ]]

--[[
	`rateLimit.minIntervalSeconds` IS the value `RateLimitSpec` reads for
	`preset_rate_limit_seconds` from `tuning.md`, IS
	`MechanicsTuning.channel.preset_rate_limit_seconds`, and is at least
	`RateLimitSpec.FLOOR_SECONDS`. The message carries the declared value and
	the document's, so a declaration at 9.5 fails naming 9.5 and 10.
]]
function PresetRemoteContract.rateLimitIsThePresetRateLimitTheDocumentFixes(
	_net: Net,
	definition: any
)
	requireDefinition("AC-1", definition)
	local document = PresetRemoteContract.documentRateLimitSeconds()
	local module = PresetRemoteContract.rateLimitSeconds()
	local floor = RateLimitSpec.FLOOR_SECONDS
	local rateLimit = definition.rateLimit
	local declared: any = if typeof(rateLimit) == "table" then rateLimit.minIntervalSeconds else nil
	local problems: { string } = {}
	if module ~= document then
		table.insert(
			problems,
			`MechanicsTuning.channel.preset_rate_limit_seconds is {module} but {RateLimitSpec.SPEC_PATH} fixes {document}; the module and the document disagree`
		)
	end
	if typeof(rateLimit) ~= "table" or declared ~= document then
		table.insert(
			problems,
			`SendPreset.rateLimit is {Deep.show(rateLimit)}, expected \{ minIntervalSeconds = {document} } - the value RateLimitSpec reads for preset_rate_limit_seconds from {RateLimitSpec.SPEC_PATH} ({document}), which MechanicsTuning.channel.preset_rate_limit_seconds carries ({module})`
		)
	end
	if typeof(declared) ~= "number" or not (declared >= floor) then
		table.insert(
			problems,
			`SendPreset.rateLimit.minIntervalSeconds is {Deep.show(declared)}, below RateLimitSpec.FLOOR_SECONDS = {floor} (the preset guideline, brief §0d #19)`
		)
	end
	if #problems > 0 then
		Contract.fail(
			`AC-1 (rate): {#problems} problem(s):\n{indent(table.concat(problems, "\n"))}`
		)
	end
end

-- `attemptLimit.minIntervalSeconds` IS `channel_attempt_min_interval_seconds`.
function PresetRemoteContract.attemptLimitIsTheChannelAttemptFloorFromTuning(
	_net: Net,
	definition: any
)
	requireDefinition("AC-1", definition)
	local want = PresetRemoteContract.attemptSeconds()
	local attemptLimit = definition.attemptLimit
	if typeof(attemptLimit) ~= "table" or attemptLimit.minIntervalSeconds ~= want then
		Contract.fail(
			`AC-1: SendPreset.attemptLimit is {Deep.show(attemptLimit)}, expected \{ minIntervalSeconds = {want} } (MechanicsTuning.channel.channel_attempt_min_interval_seconds)`
		)
	end
end

-- `Remotes.all()` lists this very table under its name - by identity, once.
function PresetRemoteContract.isTheDefinitionRemotesAllLists(net: Net, definition: any)
	requireDefinition("AC-1", definition)
	local byName: { any } = {}
	for _, entry in net.Remotes.all() do
		if typeof(entry) == "table" and entry.name == definition.name then
			table.insert(byName, entry)
		end
	end
	if #byName ~= 1 then
		Contract.fail(
			`AC-1: Remotes.all() lists {#byName} definition(s) named {Deep.show(definition.name)}, expected exactly one`
		)
	end
	if not rawequal(byName[1], definition) then
		Contract.fail(
			`AC-1: the definition Remotes.all() lists as {Deep.show(definition.name)} is not the same table as the SendPreset definition under test; a copy or a second declaration is not the registered remote`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-2, mechanical: the schema, directly and through the guard.
     --------------------------------------------------------------------- ]]

type Expectation = { label: string, value: any, expect: string }

--[[
	The schema accepts exactly `{ preset = n }` for integer n in
	1..preset_count: 1, preset_count and a middle value accepted; 0,
	preset_count + 1 and 1.5 are `range`; a string, a missing field, an empty
	table, a non-table, and ANY other key - `to`, `target`, `player`, a
	position - are `shape`. The wire cannot carry a recipient (C9).
]]
function PresetRemoteContract.schemaIsExactlyPresetIntegerOneToPresetCount(
	_net: Net,
	definition: any
)
	requireDefinition("AC-2", definition)
	local n = presetCount()
	local cases: { Expectation } = {
		{ label = "{ preset = 1 }", value = { preset = 1 }, expect = "ok" },
		{ label = `\{ preset = {n} } (preset_count)`, value = { preset = n }, expect = "ok" },
		{
			label = `\{ preset = {math.min(3, n)} }`,
			value = { preset = math.min(3, n) },
			expect = "ok",
		},
		{ label = "{ preset = 0 }", value = { preset = 0 }, expect = "range" },
		{
			label = `\{ preset = {n + 1} } (preset_count + 1)`,
			value = { preset = n + 1 },
			expect = "range",
		},
		{ label = "{ preset = 1.5 }", value = { preset = 1.5 }, expect = "range" },
		{ label = '{ preset = "1" }', value = { preset = "1" }, expect = "shape" },
		{ label = "{ preset = true }", value = { preset = true }, expect = "shape" },
		{ label = "{} (missing preset)", value = {}, expect = "shape" },
		{ label = "nil", value = nil, expect = "shape" },
		{ label = '"preset" (a string payload)', value = "preset", expect = "shape" },
		{ label = "1 (a number payload)", value = 1, expect = "shape" },
		{
			label = `\{ preset = 1, to = "{PresetRemoteContract.SECOND}" } (a recipient)`,
			value = { preset = 1, to = PresetRemoteContract.SECOND },
			expect = "shape",
		},
		{
			label = `\{ preset = 1, target = "{PresetRemoteContract.SECOND}" } (a recipient)`,
			value = { preset = 1, target = PresetRemoteContract.SECOND },
			expect = "shape",
		},
		{
			label = `\{ preset = 1, player = "{PresetRemoteContract.SECOND}" } (a recipient)`,
			value = { preset = 1, player = PresetRemoteContract.SECOND },
			expect = "shape",
		},
		{
			label = "{ preset = 1, position = { x = 0, y = 0, z = 0 } } (a position)",
			value = { preset = 1, position = { x = 0, y = 0, z = 0 } },
			expect = "shape",
		},
		{
			label = "{ preset = 1, [1] = 2 } (an array key)",
			value = { preset = 1, [1] = 2 },
			expect = "shape",
		},
		{
			label = `\{ preset = {n + 1}, to = "{PresetRemoteContract.SECOND}" } (range in preset, shape in to -> shape)`,
			value = { preset = n + 1, to = PresetRemoteContract.SECOND },
			expect = "shape",
		},
	}
	local violations: { string } = {}
	for _, case in cases do
		local ok, valid, failure = pcall(definition.args.validate, case.value)
		if not ok then
			table.insert(violations, `{case.label} -> validate RAISED: {tostring(valid)}`)
		elseif case.expect == "ok" then
			if valid ~= true then
				table.insert(
					violations,
					`{case.label} -> rejected ({Deep.show(failure)}), expected acceptance`
				)
			end
		elseif valid ~= false then
			table.insert(violations, `{case.label} -> accepted, expected a {case.expect} failure`)
		else
			local kind = NetContract.kindOf(failure)
			if kind ~= case.expect then
				table.insert(violations, `{case.label} -> failed as {kind}, expected {case.expect}`)
			end
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2: the SendPreset schema is not \{ preset = integer(1, {n}) } (preset_count = {n}) - {#violations} of {#cases} cases:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

export type MalformedCase = { label: string, args: any, expect: string }

function PresetRemoteContract.malformedCases(): { MalformedCase }
	local n = presetCount()
	local who = PresetRemoteContract.SECOND
	return {
		{ label = "a missing preset: {}", args = {}, expect = "shape" },
		{ label = 'preset = "1"', args = { preset = "1" }, expect = "shape" },
		{ label = "preset = 0", args = { preset = 0 }, expect = "range" },
		{
			label = `preset = {n + 1} (preset_count + 1)`,
			args = { preset = n + 1 },
			expect = "range",
		},
		{ label = "preset = 1.5", args = { preset = 1.5 }, expect = "range" },
		{
			label = `a recipient: \{ preset = 1, to = "{who}" }`,
			args = { preset = 1, to = who },
			expect = "shape",
		},
		{
			label = `a recipient: \{ preset = 1, target = "{who}" }`,
			args = { preset = 1, target = who },
			expect = "shape",
		},
		{
			label = `a recipient: \{ preset = 1, player = "{who}" }`,
			args = { preset = 1, player = who },
			expect = "shape",
		},
		{
			label = "a position: { preset = 1, position = { x = 0, y = 0, z = 0 } }",
			args = { preset = 1, position = { x = 0, y = 0, z = 0 } },
			expect = "shape",
		},
		{ label = 'the payload is the string "preset"', args = "preset", expect = "shape" },
		{ label = "the payload is nil", args = nil, expect = "shape" },
	}
end

-- Through the guard, in Round: each malformed payload is rejected for its
-- kind and the handler never runs.
function PresetRemoteContract.malformedCallsAreRejectedBeforeTheHandler(net: Net, definition: any)
	requireSubject("AC-2", definition)
	local guarded, calls = PresetRemoteContract.guardWithSpy(net, definition, "Round")
	local cases = PresetRemoteContract.malformedCases()
	local violations: { string } = {}
	for _, case in cases do
		local ok, result = call(guarded, PresetRemoteContract.CALLER, case.args)
		local violation = expectRejection("AC-2", case.label, ok, result, case.expect)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-2: the handler ran {#calls} time(s) across {#cases} malformed payloads; it must never run for one`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-2 (malformed) failed in {#violations} case(s) of {#cases}:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-3, mechanical: the legal phases, declared and enforced.
     --------------------------------------------------------------------- ]]

-- Exactly the derived union, in the phase machine's order.
function PresetRemoteContract.legalPhasesAreTheUnionOfThePresetTablesPhases(
	_net: Net,
	definition: any
)
	requireDefinition("AC-3", definition)
	local want = PresetRemoteContract.legalPhases()
	if not Deep.equal(definition.legalPhases, want) then
		Contract.fail(
			`AC-3: SendPreset.legalPhases is {Deep.show(definition.legalPhases)}, expected exactly {Deep.show(
				want
			)} - the union of Presets.ALL[*].phases in phase-machine order`
		)
	end
end

-- A well-formed call in each phase outside the union (Assignment,
-- Resolution today) is `phase`; the handler never runs.
function PresetRemoteContract.wellFormedCallOutsideTheUnionIsRejectedForPhase(
	net: Net,
	definition: any
)
	requireSubject("AC-3", definition)
	local illegal = PresetRemoteContract.illegalPhases()
	if #illegal == 0 then
		Contract.fail("AC-3: fixture: every known phase is in the union; nothing to refuse")
	end
	local guarded, calls, world = PresetRemoteContract.guardWithSpy(net, definition, "Round")
	local violations: { string } = {}
	for _, phase in illegal do
		world.phase = phase
		local ok, result =
			call(guarded, PresetRemoteContract.CALLER, PresetRemoteContract.wellFormed())
		local violation = expectRejection(
			"AC-3",
			`a well-formed call while the phase is {phase}`,
			ok,
			result,
			"phase"
		)
		if violation ~= nil then
			table.insert(violations, violation :: string)
		end
	end
	if #calls > 0 then
		table.insert(
			violations,
			`AC-3: the handler ran {#calls} time(s) across {#illegal} out-of-union calls`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-3 (phase) failed in {#violations} case(s):\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[
	The positive control for AC-3: a well-formed call in EACH phase of the
	union reaches the handler exactly once with the caller's id, exactly the
	payload and a `CallControl` (CHAN-003) - on a fresh guard per phase, so
	the limiter does not refuse the second. A declaration missing `Post`
	fails here, and only here.
]]
function PresetRemoteContract.wellFormedCallInEachLegalPhaseReachesTheHandler(
	net: Net,
	definition: any
)
	requireSubject("AC-3 positive control", definition)
	local violations: { string } = {}
	for _, phase in PresetRemoteContract.legalPhases() do
		for _, payload in
			{ PresetRemoteContract.wellFormed(), PresetRemoteContract.wellFormedAtTheMaximum() }
		do
			local guarded, calls = PresetRemoteContract.guardWithSpy(net, definition, phase)
			local ok, result = call(guarded, PresetRemoteContract.CALLER, payload)
			local label = `{Deep.show(payload)} in {phase}`
			local violation = expectAcceptance("AC-3 positive control", label, ok, result)
			if violation ~= nil then
				table.insert(violations, violation :: string)
			elseif #calls ~= 1 then
				table.insert(
					violations,
					`{label} -> the handler ran {#calls} time(s), expected exactly once`
				)
			else
				local c = calls[1]
				if c.playerId ~= PresetRemoteContract.CALLER then
					table.insert(
						violations,
						`{label} -> the handler received playerId {Deep.show(c.playerId)}, expected "{PresetRemoteContract.CALLER}"`
					)
				end
				if not Deep.equal(c.args, payload) then
					table.insert(
						violations,
						`{label} -> the handler received args {Deep.show(c.args)}, expected exactly the payload`
					)
				end
				if typeof(c.call) ~= "table" or typeof(c.call.decline) ~= "function" then
					table.insert(
						violations,
						`{label} -> the handler received call = {Deep.show(c.call)}; expected a CallControl with a decline function`
					)
				end
			end
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-3 positive control: a well-formed call in each legal phase must reach the handler once with exactly the payload:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     AC-1's attempt floor, enforced (so a missing floor is seen, not just read).
     --------------------------------------------------------------------- ]]

--[[
	Two well-formed in-Round calls at `t` and `t + attempt - EPSILON` - the
	second is `rate` with the ATTEMPT detail (not the send detail), and the
	handler count stays 1. A third at exactly `t + attempt` is past the floor
	and is refused by the SEND limit instead: the floor is inclusive, and the
	two refusals are distinguishable.
]]
function PresetRemoteContract.secondCallInsideTheAttemptFloorIsRejectedForRate(
	net: Net,
	definition: any
)
	requireSubject("AC-1", definition)
	local attempt = PresetRemoteContract.attemptSeconds()
	local rate = PresetRemoteContract.rateLimitSeconds()
	local eps = PresetRemoteContract.EPSILON
	assert(
		eps < attempt and attempt < rate,
		`fixture: need EPSILON {eps} < attempt {attempt} < rate {rate}`
	)
	local guarded, calls, world = PresetRemoteContract.guardWithSpy(net, definition, "Round")
	local caller = PresetRemoteContract.CALLER
	local start = PresetRemoteContract.START
	local payload = PresetRemoteContract.wellFormed()
	local violations: { string } = {}
	local function push(v: string?)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
	end

	world.clock:set(start)
	local ok1, r1 = call(guarded, caller, payload)
	push(expectAcceptance("AC-1", "the first well-formed in-Round call, at t", ok1, r1))
	if #calls ~= 1 then
		push(`AC-1: after the first call the handler ran {#calls} time(s), expected 1`)
	end

	world.clock:set(start + attempt - eps)
	local ok2, r2 = call(guarded, caller, payload)
	push(
		expectRejection(
			"AC-1",
			`the second call at t + {attempt} - {eps} (inside channel_attempt_min_interval_seconds = {attempt})`,
			ok2,
			r2,
			"rate",
			DeclineContract.attemptDetail(definition.name, attempt)
		)
	)

	world.clock:set(start + attempt)
	local ok3, r3 = call(guarded, caller, payload)
	push(
		expectRejection(
			"AC-1",
			`the third call at exactly t + {attempt} (past the floor, inside the send limit)`,
			ok3,
			r3,
			"rate",
			DeclineContract.sendDetail(definition.name, rate)
		)
	)
	if #calls ~= 1 then
		push(
			`AC-1: after two rate-limited calls the handler ran {#calls} time(s) in total; expected 1`
		)
	end

	if #violations > 0 then
		Contract.fail(
			`AC-1 (attempt floor = {attempt}) failed in {#violations} step(s):\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     The handler SLICE-006 will ship, over a PresetSends module (C-7).
     --------------------------------------------------------------------- ]]

type Outcome = { playerId: any, result: any }

--[[
	A handler threading one `PresetState` through `P.send`, reading the phase
	and the clock the guard reads, and handing on the wrapper's `call`. Every
	`send` result is kept in order, with the filter's call count beside it.
]]
local function sendingHandler(
	P: any,
	world: RateContract.World,
	positions: { [string]: PresetSendsContract.Position },
	filter: any
): (any, { Outcome }, { state: any })
	local outcomes: { Outcome } = {}
	local held = { state = P.new() }
	local handler = function(playerId: any, args: any, control: any)
		local newState, result = P.send(
			held.state,
			playerId,
			args.preset,
			world.phase,
			positions[playerId],
			world.clock.now(),
			filter,
			control
		)
		held.state = newState
		table.insert(outcomes, { playerId = playerId, result = result })
	end
	return handler, outcomes, held
end

local function needSends(criterion: string, P: any)
	if typeof(P) ~= "table" or typeof(P.send) ~= "function" or typeof(P.new) ~= "function" then
		Contract.fail(
			`{criterion}: PresetSends is {Deep.show(P)}; expected a module with new and send`
		)
	end
end

--[[
	AC-4 through the REAL guard (C-7). In `Round`, with the `hashed` filter:

	  t           : a preset whose row excludes Round (Well played today) ->
	                the guard answers `declined`; `send` returned exactly
	                `failed` / `phase_for_preset`; the filter was not called;
	                the log is empty.
	  t + attempt : a preset legal in Round, exactly at the attempt floor and
	                well inside the send limit -> the guard answers nil, the
	                handler ran, `send` returned `shown` with the filter's
	                text, and the log holds that one entry.

	A handler whose phase refusal does NOT decline leaves the first call's
	acceptance in the send limiter, and the second call is `rate`.
]]
function PresetRemoteContract.outOfPhasePresetIsDeclinedAndTheNextLegalPresetAtTheAttemptFloorIsShown(
	net: Net,
	subject: any,
	P: any
)
	requireSubject("AC-4", subject)
	needSends("AC-4", P)
	local sender = PresetRemoteContract.CALLER
	local attempt = PresetRemoteContract.attemptSeconds()
	local rate = PresetRemoteContract.rateLimitSeconds()
	local start = PresetRemoteContract.START
	assert(attempt < rate, `fixture: need attempt {attempt} < rate {rate}`)
	local refusedId = PresetRemoteContract.aPresetIdIllegalIn("Round")
	local legalId = PresetRemoteContract.aPresetIdLegalIn("Round")
	local position = PresetSendsContract.position()
	local filter, record = PresetSendsContract.hashed()
	local context, world = RateContract.world({ sender }, "Round", start)
	local handler, outcomes, held = sendingHandler(P, world, { [sender] = position }, filter)
	local guarded = PresetRemoteContract.guardFor(net, subject, context, handler)
	local violations: { string } = {}

	world.clock:set(start)
	local ok1, r1 = call(guarded, sender, { preset = refusedId })
	if not ok1 then
		table.insert(violations, `AC-4: the out-of-phase preset at t RAISED: {tostring(r1)}`)
	else
		local want = { reason = "declined", detail = DeclineContract.declinedDetail(subject.name) }
		if not Deep.equal(r1, want) then
			table.insert(
				violations,
				`AC-4: the out-of-phase preset at t -> the guard answered {Deep.show(r1)}, expected {Deep.show(
					want
				)}`
			)
		end
		if #outcomes ~= 1 then
			table.insert(
				violations,
				`AC-4: after the out-of-phase preset the handler ran {#outcomes} time(s), expected 1`
			)
		else
			local wantResult = {
				kind = "failed",
				failed = { presetId = refusedId, reason = "phase_for_preset" },
			}
			if not Deep.equal(outcomes[1].result, wantResult) then
				table.insert(
					violations,
					`AC-4: the out-of-phase preset -> send returned {Deep.show(outcomes[1].result)}, expected exactly {Deep.show(
						wantResult
					)}`
				)
			end
		end
		if #record.calls ~= 0 then
			table.insert(
				violations,
				`AC-4: the filter was called {#record.calls} time(s) for the out-of-phase preset; expected never`
			)
		end
		if typeof(held.state) ~= "table" or not Deep.equal(held.state, { log = {} }) then
			table.insert(
				violations,
				`AC-4: after the out-of-phase preset the state is {Deep.show(held.state)}, expected an empty log`
			)
		end
	end

	world.clock:set(start + attempt)
	local ok2, r2 = call(guarded, sender, { preset = legalId })
	if not ok2 then
		table.insert(violations, `AC-4: the legal preset at t + {attempt} RAISED: {tostring(r2)}`)
	else
		if r2 ~= nil then
			table.insert(
				violations,
				`AC-4: the legal preset at t + {attempt} (the attempt floor, inside the send limit {rate}) -> the guard answered {Deep.show(
					r2
				)}, expected nil (accepted); the phase refusal must have declined and refunded the send limit`
			)
		end
		if #outcomes ~= 2 then
			table.insert(
				violations,
				`AC-4: after the legal preset the handler ran {#outcomes} time(s) in total, expected 2`
			)
		else
			local wantShown = {
				kind = "shown",
				shown = {
					senderId = sender,
					presetId = legalId,
					position = PresetSendsContract.position(),
					text = PresetSendsContract.HASHED,
				},
			}
			if not Deep.equal(outcomes[2].result, wantShown) then
				table.insert(
					violations,
					`AC-4: the legal preset -> send returned {Deep.show(outcomes[2].result)}, expected exactly {Deep.show(
						wantShown
					)}`
				)
			end
		end
		local wantState = {
			log = {
				{
					senderId = sender,
					presetId = legalId,
					position = PresetSendsContract.position(),
					at = start + attempt,
				},
			},
		}
		if not Deep.equal(held.state, wantState) then
			table.insert(
				violations,
				`AC-4: after the legal preset the state is not exactly one log entry:\n{indent(
					Deep.diff(wantState, held.state)
				)}`
			)
		end
		if #record.calls ~= 1 then
			table.insert(
				violations,
				`AC-4: across both calls the filter was called {#record.calls} time(s), expected exactly once (for the legal preset)`
			)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-4 (guarded): {#violations} violation(s) for an out-of-phase preset followed by a legal one at the attempt floor:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[
	AC-7 through the REAL guard (C-7). In `Round`, with the `hashed` filter,
	two seated players A and B:

	  t          : A sends preset p1 -> accepted, shown by A.
	  t          : B sends preset p1 -> accepted, shown by B (B's own limiter).
	  t + rate/2 : A sends a DIFFERENT preset p2, legal and filterable ->
	               `rate` with the SEND detail; the handler count stays 2 and
	               the log holds exactly A's and B's first sends.

	One send limit per player across the wheel: ten per-preset limiters
	behind a dispatcher let A's p2 through, and so does a send limit set to
	the attempt floor (D-5's shape).
]]
function PresetRemoteContract.twoPlayersAreBothShownAndOnePlayersSecondPresetInsideTheLimitIsRate(
	net: Net,
	subject: any,
	P: any
)
	requireSubject("AC-7", subject)
	needSends("AC-7", P)
	local a, b = PresetRemoteContract.CALLER, PresetRemoteContract.SECOND
	local attempt = PresetRemoteContract.attemptSeconds()
	local rate = PresetRemoteContract.rateLimitSeconds()
	local start = PresetRemoteContract.START
	local gap = rate / 2
	assert(attempt < gap and gap < rate, `fixture: need attempt {attempt} < {gap} < rate {rate}`)
	local p1, p2 = PresetRemoteContract.twoPresetIdsLegalIn("Round")
	local positions = {
		[a] = PresetSendsContract.position(),
		[b] = { x = 30, y = 1, z = 40 },
	}
	local filter = PresetSendsContract.hashed()
	local context, world = RateContract.world({ a, b }, "Round", start)
	local handler, outcomes, held = sendingHandler(P, world, positions, filter)
	local guarded = PresetRemoteContract.guardFor(net, subject, context, handler)
	local violations: { string } = {}
	local function push(v: string?)
		if v ~= nil then
			table.insert(violations, v :: string)
		end
	end
	local function expectShown(index: number, who: string, presetId: number)
		local outcome = outcomes[index]
		local want = {
			kind = "shown",
			shown = {
				senderId = who,
				presetId = presetId,
				position = Deep.copy(positions[who]),
				text = PresetSendsContract.HASHED,
			},
		}
		if outcome == nil then
			push(`AC-7: no handler outcome {index} for {who}'s preset {presetId}`)
		elseif outcome.playerId ~= who or not Deep.equal(outcome.result, want) then
			push(
				`AC-7: outcome {index} is {Deep.show(outcome.playerId)} -> {Deep.show(
					outcome.result
				)}, expected {who} -> {Deep.show(want)}`
			)
		end
	end

	world.clock:set(start)
	local okA, rA = call(guarded, a, { preset = p1 })
	push(expectAcceptance("AC-7", `{a} sends preset {p1} at t`, okA, rA))
	local okB, rB = call(guarded, b, { preset = p1 })
	push(expectAcceptance("AC-7", `{b} sends preset {p1} at t, the same instant`, okB, rB))
	if #outcomes ~= 2 then
		push(`AC-7: after two players' sends the handler ran {#outcomes} time(s), expected 2`)
	else
		expectShown(1, a, p1)
		expectShown(2, b, p1)
	end

	world.clock:set(start + gap)
	local okA2, rA2 = call(guarded, a, { preset = p2 })
	push(
		expectRejection(
			"AC-7",
			`{a} sends a DIFFERENT preset {p2} at t + {gap} (inside preset_rate_limit_seconds = {rate})`,
			okA2,
			rA2,
			"rate",
			DeclineContract.sendDetail(subject.name, rate)
		)
	)
	if #outcomes ~= 2 then
		push(
			`AC-7: after {a}'s second preset the handler ran {#outcomes} time(s) in total; expected 2 - one send limit per player spans the whole wheel`
		)
	end
	local wantState = {
		log = {
			{ senderId = a, presetId = p1, position = Deep.copy(positions[a]), at = start },
			{ senderId = b, presetId = p1, position = Deep.copy(positions[b]), at = start },
		},
	}
	if not Deep.equal(held.state, wantState) then
		push(
			`AC-7: the log is not exactly the two first sends:\n{indent(
				Deep.diff(wantState, held.state)
			)}`
		)
	end

	if #violations > 0 then
		Contract.fail(
			`AC-7: {#violations} violation(s) for two players in one window and one player's two presets {gap} s apart:\n{indent(
				Contract.firstFew(violations, #violations)
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     The battery over a DEFINITION, named, so the controls can run every
     check against one and report exactly which fire. The two PresetSends
     checks above are run on their own, with a module.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Net, any) -> ...any }

PresetRemoteContract.CHECKS = {
	{
		name = "rateLimitIsThePresetRateLimitTheDocumentFixes",
		ac = "AC-1",
		run = PresetRemoteContract.rateLimitIsThePresetRateLimitTheDocumentFixes,
	},
	{
		name = "attemptLimitIsTheChannelAttemptFloorFromTuning",
		ac = "AC-1",
		run = PresetRemoteContract.attemptLimitIsTheChannelAttemptFloorFromTuning,
	},
	{
		name = "isTheDefinitionRemotesAllLists",
		ac = "AC-1",
		run = PresetRemoteContract.isTheDefinitionRemotesAllLists,
	},
	{
		name = "secondCallInsideTheAttemptFloorIsRejectedForRate",
		ac = "AC-1",
		run = PresetRemoteContract.secondCallInsideTheAttemptFloorIsRejectedForRate,
	},
	{
		name = "schemaIsExactlyPresetIntegerOneToPresetCount",
		ac = "AC-2",
		run = PresetRemoteContract.schemaIsExactlyPresetIntegerOneToPresetCount,
	},
	{
		name = "malformedCallsAreRejectedBeforeTheHandler",
		ac = "AC-2",
		run = PresetRemoteContract.malformedCallsAreRejectedBeforeTheHandler,
	},
	{
		name = "legalPhasesAreTheUnionOfThePresetTablesPhases",
		ac = "AC-3",
		run = PresetRemoteContract.legalPhasesAreTheUnionOfThePresetTablesPhases,
	},
	{
		name = "wellFormedCallOutsideTheUnionIsRejectedForPhase",
		ac = "AC-3",
		run = PresetRemoteContract.wellFormedCallOutsideTheUnionIsRejectedForPhase,
	},
	{
		name = "wellFormedCallInEachLegalPhaseReachesTheHandler",
		ac = "AC-3 positive control",
		run = PresetRemoteContract.wellFormedCallInEachLegalPhaseReachesTheHandler,
	},
} :: { Check }

-- Every check against `definition`; the names of those that raised, with
-- their messages, in CHECKS order.
function PresetRemoteContract.failures(
	net: Net,
	definition: any
): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in PresetRemoteContract.CHECKS do
		local ok, err = pcall(check.run, net, definition)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return PresetRemoteContract
