--!strict
--[[
	Deep structural comparison, snapshotting and rendering.

	ROUND-003 AC-6 is the reason this exists. Its non-mutation half must NOT be
	an identity check: `stateBefore ~= stateAfter` is satisfied by an
	implementation that mutates the input and returns a fresh copy of it, which
	is the exact bug AC-6 is about. The honest form is a DEEP SNAPSHOT of the
	input taken before the call and a DEEP COMPARISON against it afterwards, and
	that needs a comparator that is itself trustworthy.

	So this module is an instrument, and an instrument that always returns
	`true` would make the most important assertion in the story vacuous while
	turning the whole suite green. `tests/server/phase_machine_controls_test.luau`
	exercises it directly against pairs that differ in every way a RoundState
	can differ - a changed leaf, a missing key, an extra key, a longer array, a
	different type, a difference nested two levels down. Those checks need no
	production code, so they run in RED, which is the only phase in which the
	rest of the suite cannot run at all.

	`Deep.diff` returns EVERY difference rather than the first: a failure that
	names one field of six is a bug report that costs a second run.
]]

local Deep = {}

local function show(value: any, seen: { [any]: boolean }): string
	if typeof(value) == "string" then
		return '"' .. value .. '"'
	end
	if typeof(value) ~= "table" then
		return tostring(value)
	end
	if seen[value] then
		return "<cycle>"
	end
	seen[value] = true

	local keys: { any } = {}
	for key in pairs(value :: { [any]: any }) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: any, b: any): boolean
		return tostring(a) < tostring(b)
	end)

	local parts: { string } = {}
	for _, key in keys do
		table.insert(parts, tostring(key) .. " = " .. show((value :: any)[key], seen))
	end

	seen[value] = nil
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- A stable rendering with sorted keys, so a failure message reads the same way
-- twice and two renderings can be compared by eye.
function Deep.show(value: any): string
	return show(value, {})
end

--[[
	A full copy: every nested table is a new table, so nothing in the result
	aliases anything in the original. This is the snapshot half of AC-6 - a
	shallow copy would share the `players` array and the `outcome` table with
	the state under test, and an implementation that mutated either of those in
	place would compare equal to its own snapshot.
]]
function Deep.copy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local out: { [any]: any } = {}
	for key, item in pairs(value :: { [any]: any }) do
		out[key] = Deep.copy(item)
	end
	return out
end

local function compare(expected: any, actual: any, path: string, problems: { string })
	local here = if path == "" then "value" else path

	if typeof(expected) ~= typeof(actual) then
		table.insert(
			problems,
			`{here}: expected {typeof(expected)} {Deep.show(expected)}, `
				.. `got {typeof(actual)} {Deep.show(actual)}`
		)
		return
	end

	if typeof(expected) ~= "table" then
		if expected ~= actual then
			table.insert(
				problems,
				`{here}: expected {Deep.show(expected)}, got {Deep.show(actual)}`
			)
		end
		return
	end

	for key, item in pairs(expected :: { [any]: any }) do
		local other = (actual :: any)[key]
		if other == nil then
			table.insert(problems, `{here}.{tostring(key)}: expected {Deep.show(item)}, got nil`)
		else
			compare(item, other, `{here}.{tostring(key)}`, problems)
		end
	end

	for key, item in pairs(actual :: { [any]: any }) do
		if (expected :: any)[key] == nil then
			table.insert(problems, `{here}.{tostring(key)}: unexpected {Deep.show(item)}`)
		end
	end
end

-- Every structural difference between two values, one per line; "" when they
-- are deeply equal.
function Deep.diff(expected: any, actual: any): string
	local problems: { string } = {}
	compare(expected, actual, "", problems)
	return table.concat(problems, "\n")
end

function Deep.equal(a: any, b: any): boolean
	return Deep.diff(a, b) == ""
end

-- The kinds of a list of effects, in order. AC-8 asserts effect SEQUENCES as
-- whole lists, and a list of kinds is what makes the failure readable.
function Deep.kinds(effects: { any }): { string }
	local out: { string } = {}
	for _, effect in effects do
		table.insert(
			out,
			if typeof(effect) == "table" then tostring(effect.kind) else "<not a table>"
		)
	end
	return out
end

--[[
	The CONTROL effects of a step: every effect whose kind is not `Emit`, in
	order.

	TEL-002 adds telemetry to the phase machine as `{ kind = "Emit", event }`
	effects returned from `step` (architecture.md §Effects, D3). ROUND-003 AC-8,
	ROUND-005 AC-6 and AC-7 pin the machine's control effects - `AssignSeats`,
	`ComputeTrace`, `PromptRematch` - and that meaning is KEPT: each of those
	assertions filters through this one function before comparing, so a join,
	a departure or the step that enters Resolution may carry telemetry without
	the ROUND suites re-deciding what the control sequence is. Telemetry on
	those steps is pinned by `tests/helpers/TelemetryEmitContract.luau`.

	ONE shared filter rather than a private one per file (TEL-002 Contract §5):
	four private copies of "which files are source" once drifted apart in this
	repository, and a private "which effects are control" would drift the same
	way.
]]
function Deep.controlEffects(effects: { any }): { any }
	local out: { any } = {}
	for _, effect in effects do
		if not (typeof(effect) == "table" and effect.kind == "Emit") then
			table.insert(out, effect)
		end
	end
	return out
end

-- `Deep.kinds` over the control effects only. Read the comment above.
function Deep.controlKinds(effects: { any }): { string }
	return Deep.kinds(Deep.controlEffects(effects))
end

return Deep
