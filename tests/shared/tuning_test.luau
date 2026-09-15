--!strict
--[[
	ROUND-002 AC-1, AC-2, AC-3 and AC-5, against `src/shared/Tuning.luau`.

	AC-1 and AC-2 are SETTLED criteria (`## Oracle partition`): the values are read
	out of the specification, never re-derived here. They are compared against
	`TuningSpec.ACCEPTANCE`, which is ROUND-002's own frozen AC-1 and AC-2 lists -
	and `tuning_spec_test.luau` separately checks that `docs/wiki/game/tuning.md`
	still agrees with those lists, so a value edited in the specification under a
	frozen story is reported rather than absorbed.

	Nothing here pins HOW the module is written: not the order of the keys, not
	whether `Tuning` exposes anything besides `session` and `round`, not which of
	`table.freeze` or a `__newindex` metatable provides AC-3. Only that the
	attempt fails.

	Loaded through a `pcall` for the reason `rng_test.luau` gives: in RED this
	module does not exist, and one LOAD FAIL covering four criteria is worse
	evidence than eleven failures naming them.
]]

local TuningSpec = require("../helpers/TuningSpec")

local loaded, loadResult = pcall(require, "../../src/shared/Tuning")

local function Tuning(): any
	assert(loaded, `src/shared/Tuning.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- Every constant in one table, compared to the frozen criteria, accumulated and
-- asserted once. A per-key assertion reports the first offender and hides the
-- rest.
local function assertTableMatchesAcceptance(criterion: string, tableName: string, section: number)
	local expected = TuningSpec.ACCEPTANCE[tableName]
	local subject = Tuning()[tableName]
	assert(
		typeof(subject) == "table",
		`{criterion}: Tuning.{tableName} is {typeof(subject)}, expected a table`
	)

	local wrong: { string } = {}
	for _, name in TuningSpec.sortedKeys(expected) do
		local actual = subject[name]
		if actual == nil then
			table.insert(wrong, `{name}: expected {expected[name]}, absent from the module`)
		elseif typeof(actual) ~= "number" then
			table.insert(wrong, `{name}: expected {expected[name]}, module has a {typeof(actual)}`)
		elseif actual ~= expected[name] then
			table.insert(wrong, `{name}: expected {expected[name]}, module has {actual}`)
		end
	end

	assert(
		#wrong == 0,
		`{criterion}: Tuning.{tableName} disagrees with tuning.md §{section}:\n  `
			.. table.concat(wrong, "\n  ")
	)
end

local function assertNoExtraKeys(criterion: string, tableName: string, section: number)
	local expected = TuningSpec.ACCEPTANCE[tableName]
	local subject = Tuning()[tableName]
	assert(
		typeof(subject) == "table",
		`{criterion}: Tuning.{tableName} is {typeof(subject)}, expected a table`
	)

	local extra: { string } = {}
	for _, key in TuningSpec.sortedKeys(subject) do
		if expected[key] == nil then
			table.insert(extra, key)
		end
	end

	assert(
		#extra == 0,
		`{criterion}: Tuning.{tableName} exposes constants tuning.md §{section} does not name: `
			.. table.concat(extra, ", ")
	)
end

--[[
	AC-3, one attempt. Both halves matter: the write must RAISE, and the table
	must be unchanged afterwards. A `__newindex` that swallows the write silently
	satisfies "does not change" while failing "the attempt fails", and a
	`rawset`-able table satisfies neither.

	The value is put back on the way out if the write got through, so that a
	single AC-3 failure does not cascade into every later test in the run.
]]
local function refusesWrite(target: any, key: string, value: any, what: string)
	local before = target[key]
	local ok = pcall(function()
		target[key] = value
	end)
	local after = target[key]
	if after ~= before then
		pcall(function()
			target[key] = before
		end)
	end

	-- Deliberately NOT asserted: what the error says. AC-3 asks that the attempt
	-- fail, and `table.freeze` and a `__newindex` metatable word it differently.
	assert(ok == false, `AC-3: {what} succeeded; the write must raise`)
	assert(
		after == before,
		`AC-3: {what} raised but the value changed from {tostring(before)} to {tostring(after)}`
	)
end

return {
	--[[ AC-1 ]]

	["AC-1: every session constant tuning.md §1 names holds its specified value"] = function()
		assertTableMatchesAcceptance("AC-1", "session", 1)
	end,

	["AC-1: Tuning.session exposes no constant tuning.md §1 does not name"] = function()
		assertNoExtraKeys("AC-1", "session", 1)
	end,

	--[[ AC-2 ]]

	["AC-2: every round constant tuning.md §5 names holds its specified value"] = function()
		assertTableMatchesAcceptance("AC-2", "round", 5)
	end,

	["AC-2: Tuning.round exposes no constant tuning.md §5 does not name"] = function()
		assertNoExtraKeys("AC-2", "round", 5)
	end,

	--[[
		The conflict amendment 12 records, pinned so that nobody closes it here.

		`lobby_seconds` 60 + `round_seconds` 480 exceeds `first_round_within_seconds`
		480, so A5's day-1 promise is violated BY THE SPECIFICATION. That is an
		open operator decision (`## Out of scope`), and the failure mode this test
		guards against is a well-meaning implementer "fixing" it - setting
		`first_round_within_seconds` to 540, or shaving the lobby - which would
		make the module disagree with the spec and make the decision look taken.
	]]
	["AC-2: the day-1 conflict amendment 12 records is carried, not resolved"] = function()
		local round = Tuning().round
		local session = Tuning().session
		assert(
			round.first_round_within_seconds == 480,
			`AC-2: first_round_within_seconds is {tostring(round.first_round_within_seconds)}, `
				.. `the specification says 480. Amendment 12 is the operator's to close.`
		)
		assert(
			session.lobby_seconds + round.round_seconds > round.first_round_within_seconds,
			"AC-2: lobby_seconds + round_seconds no longer exceeds first_round_within_seconds, "
				.. "so amendment 12's conflict has been resolved in the module. It is an open "
				.. "operator decision; the module transcribes the specification."
		)
	end,

	--[[ AC-3 ]]

	["AC-3: assigning to an existing session constant fails"] = function()
		refusesWrite(Tuning().session, "lobby_seconds", 999, "Tuning.session.lobby_seconds = 999")
	end,

	["AC-3: assigning to an existing round constant fails"] = function()
		refusesWrite(Tuning().round, "round_seconds", 999, "Tuning.round.round_seconds = 999")
	end,

	["AC-3: adding a new key to Tuning.session fails"] = function()
		refusesWrite(Tuning().session, "warmup_seconds", 15, "Tuning.session.warmup_seconds = 15")
	end,

	["AC-3: adding a new key to Tuning.round fails"] = function()
		refusesWrite(Tuning().round, "overtime_seconds", 15, "Tuning.round.overtime_seconds = 15")
	end,

	["AC-3: the module table itself rejects assignment and new keys"] = function()
		refusesWrite(Tuning(), "session", {}, "Tuning.session = {}")
		refusesWrite(Tuning(), "instance", {}, "Tuning.instance = {}")
	end,

	--[[ AC-5 ]]

	["AC-5: no exported key names a constant tuning.md §7 records as deliberately absent"] = function()
		TuningSpec.assertNoAbsentConstants(Tuning())
	end,
}
