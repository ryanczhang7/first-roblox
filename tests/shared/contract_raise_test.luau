--!strict
--[[
	HARNESS-011: a contract helper's failure message survives past 511
	characters.

	`assert(false, message)` under Lune keeps the first 511 characters of
	`message` and drops the rest (`docs/wiki/stack.md`). A contract check that
	reports its first eight violations goes past that, and whatever it said after
	character 511 was gone before anyone read it. The shared raiser in
	`tests/helpers/Contract.luau` is `error(message, 0)`, which does not truncate.

	The raiser is required through a `pcall` and re-checked inside each test, as
	`ring_test.luau` does with its module: in SCAFFOLD's first run it does not
	exist, and a bare top-level `require` would make this file one LOAD FAIL
	that hides the `assert` control below - the one case here that can run, and
	pass, before the raiser is written.
]]

local NetContract = require("../helpers/NetContract")
local NetStubs = require("../helpers/NetStubs")
local PhaseContract = require("../helpers/PhaseContract")
local PhaseStubs = require("../helpers/PhaseStubs")
local ProjectionContract = require("../helpers/ProjectionContract")
local ProjectionStubs = require("../helpers/ProjectionStubs")
local RateContract = require("../helpers/RateContract")
local RateStubs = require("../helpers/RateStubs")
local RejectionContract = require("../helpers/RejectionContract")
local RejectionStubs = require("../helpers/RejectionStubs")
local RingContract = require("../helpers/RingContract")
local RingStubs = require("../helpers/RingStubs")
local SourceScan = require("../helpers/SourceScan")
local TelemetryContract = require("../helpers/TelemetryContract")
local TelemetryStubs = require("../helpers/TelemetryStubs")
local fs = require("@lune/fs")

local loaded, loadResult = pcall(require, "../helpers/Contract")

local function Contract(): any
	assert(loaded, `tests/helpers/Contract.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

-- 2000 characters, every six of them a distinct numbered block, so that any
-- run of 511 characters occurs in it exactly once and a cut at 511 cannot be
-- mistaken for a cut anywhere else.
local function longMessage(): string
	local blocks: { string } = {}
	for i = 1, 334 do
		table.insert(blocks, string.format("[%04d]", i))
	end
	local message = string.sub(table.concat(blocks), 1, 2000)
	assert(#message == 2000, `the fixture message is {#message} characters, not 2000`)
	return message
end

-- AC-1's predicate, shared by the criterion and its control so that the
-- control fails THIS assertion rather than one written to fail.
local function arrivesIntact(raise: (string) -> (), message: string): (boolean, string)
	local ok, err = pcall(raise, message)
	if ok then
		return false, "the raiser returned instead of raising"
	end
	local received = tostring(err)
	return received == message, received
end

--[[
	AC-2's instrument. `Contract.firstFew` is the one message-builder the two
	accumulating helpers share, and it counts every call. A passing check that
	builds its message eagerly - `assert(ok, <message>)`, or `check(ok,
	<message>)`, where Luau evaluates the argument before the call - counts one
	per check; a check that builds only on its failing path counts zero.
]]
local function buildsDuring(run: () -> ()): number
	local contract = Contract()
	contract.resetBuilds()
	run()
	return contract.builds()
end

local PASSING: { { what: string, run: () -> () } } = {
	{
		what = "RingContract, SEAT-001 AC-1, on the correct ring stub",
		run = function()
			RingContract.sigmaIsAFixedPointFreePermutation(RingStubs.correct)
		end,
	},
	-- Not SEAT-001 AC-5: it joins its lines with `table.concat`, not
	-- `firstFew`, so this counter reads 0 on it whether or not it builds eagerly.
	-- Observed: 0 in the run where the other four read 1. A case that cannot
	-- fail is left out rather than kept for show.
	{
		what = "RingContract, SEAT-003 AC-1, on the correct ring stub",
		run = function()
			RingContract.withdrawTransfersTheKeyClassToTheSupplier(RingStubs.correct)
		end,
	},
	{
		what = "ProjectionContract, SEAT-002 AC-1, on the correct projection stub",
		run = function()
			ProjectionContract.viewIsExactlyTheAllowlist(ProjectionStubs.correct)
		end,
	},
	{
		what = "ProjectionContract, SEAT-002 AC-2, on the correct projection stub",
		run = function()
			ProjectionContract.noForeignKeyClassAppears(ProjectionStubs.correct)
		end,
	},
	-- HARNESS-016 AC-2: one accumulating check per newly reached helper, each
	-- paired below with a control stub its own controls test asserts it fails.
	{
		what = "NetContract, NET-001 AC-2, on the correct wrapper",
		run = function()
			NetContract.malformedPayloadIsRejectedForShape(NetStubs.correct())
		end,
	},
	{
		what = "PhaseContract, NET-002 AC-4, on the correct wrapper",
		run = function()
			PhaseContract.multiPhaseRemoteRunsInEachLegalPhaseAndNowhereElse(PhaseStubs.correct())
		end,
	},
	{
		what = "RateContract, NET-003 AC-2, on the correct wrapper",
		run = function()
			RateContract.playersAreLimitedIndependently(RateStubs.correct())
		end,
	},
	{
		what = "RejectionContract, TEL-003 AC-6, on the correct bundle",
		run = function()
			RejectionContract.coalescingIsPerPlayerAndPerRemote(RejectionStubs.correct())
		end,
	},
	{
		what = "TelemetryContract, TEL-001 AC-6, on the correct Event",
		run = function()
			TelemetryContract.nonScalarFieldIsRefusedNamingTheKey(TelemetryStubs.correctEvent)
		end,
	},
}

local FAILING: { { what: string, run: () -> () } } = {
	{
		what = "RingContract, SEAT-001 AC-1, on a generator that allows fixed points",
		run = function()
			RingContract.sigmaIsAFixedPointFreePermutation(RingStubs.anyPermutation)
		end,
	},
	{
		what = "ProjectionContract, SEAT-002 AC-2, on copy-and-remove-sigma",
		run = function()
			ProjectionContract.noForeignKeyClassAppears(ProjectionStubs.copyAndRemoveSigma)
		end,
	},
	{
		what = "NetContract, NET-001 AC-2, on the boolean-false wrapper",
		run = function()
			NetContract.malformedPayloadIsRejectedForShape(NetStubs.with("booleanFalse"))
		end,
	},
	{
		what = "PhaseContract, NET-002 AC-4, on the first-entry-only wrapper",
		run = function()
			PhaseContract.multiPhaseRemoteRunsInEachLegalPhaseAndNowhereElse(
				PhaseStubs.with("firstEntryOnly")
			)
		end,
	},
	{
		what = "RateContract, NET-003 AC-2, on the shared-timestamp wrapper",
		run = function()
			RateContract.playersAreLimitedIndependently(RateStubs.with("sharedTimestamp"))
		end,
	},
	{
		what = "RejectionContract, TEL-003 AC-6, on the per-player reporter",
		run = function()
			RejectionContract.coalescingIsPerPlayerAndPerRemote(
				RejectionStubs.with("perPlayerOnly")
			)
		end,
	},
	{
		what = "TelemetryContract, TEL-001 AC-6, on the accept-nested-table Event",
		run = function()
			TelemetryContract.nonScalarFieldIsRefusedNamingTheKey(TelemetryStubs.acceptNestedTable)
		end,
	},
}

--[[
	The guarded set, BY NAME: HARNESS-011's AC-4 named the first four, and
	HARNESS-016's AC-1 the other ten. Stubs, `Fakes` and `SourceScan` raise on
	purpose and are not contracts. The file list those names are looked up in is
	the harness's - `classify.sh --list test` through
	`SourceScan.classifierList` - so a helper that is renamed, or stops
	classifying as a test, is reported missing rather than silently unscanned.
]]
local IN_SCOPE = {
	"tests/helpers/LobbyGateContract.luau",
	"tests/helpers/ProjectionContract.luau",
	"tests/helpers/RingContract.luau",
	"tests/helpers/RoundEndingContract.luau",
	-- HARNESS-016
	"tests/helpers/ClockContract.luau",
	"tests/helpers/NetContract.luau",
	"tests/helpers/PhaseContract.luau",
	"tests/helpers/PhaseMachineContract.luau",
	"tests/helpers/RateContract.luau",
	"tests/helpers/RejectionContract.luau",
	"tests/helpers/RngContract.luau",
	"tests/helpers/TelemetryContract.luau",
	"tests/helpers/TelemetryEmitContract.luau",
	"tests/helpers/TuningSpec.luau",
}

-- A raise that does not go through `Contract.fail`: bare `assert`, or `error`
-- called directly, which is what every private `check` wrapper is built from.
-- `SourceScan.hitsIn` reads code only - comments and strings are blanked - and
-- a symbol only counts standing alone, so `Contract.fail` and a comment that
-- says "assert" are not hits.
local RAISES = { "assert", "error" }

local function bareRaises(path: string, text: string): { string }
	local found: { string } = {}
	for _, hit in SourceScan.hitsIn(path, text, RAISES) do
		table.insert(found, `  {hit.path}:{hit.line}: {hit.symbol}`)
	end
	return found
end

--[[
	HARNESS-016 AC-3's needle, matched in COMMENT text only
	(`SourceScan.commentsOnly`): code and string literals are blanked, so this
	file's own strings - AC-1's control message, this constant - are not hits.
	It covers the plural too. The five private `check` wrappers each carried the
	phrase, in a doc comment quoting the cap one too high.
]]
local CAP_NEEDLE = "512 character"

local function capComments(path: string, text: string): { string }
	local found: { string } = {}
	for lineNumber, line in string.split(SourceScan.commentsOnly(text), "\n") do
		if string.find(line, CAP_NEEDLE, 1, true) then
			table.insert(found, `  {path}:{lineNumber}`)
		end
	end
	return found
end

-- `text` with `line` as a new last line, and the line number it landed on.
local function withLastLine(text: string, line: string): (string, number)
	local lines = string.split(text, "\n")
	table.insert(lines, line)
	return table.concat(lines, "\n"), #lines
end

return {
	["AC-1: Contract.fail delivers a 2000-character message intact, every character in order"] = function()
		local message = longMessage()
		local intact, received = arrivesIntact(Contract().fail, message)
		assert(
			intact,
			`Contract.fail delivered {#received} characters of a {#message}-character message; `
				.. `it begins {string.sub(received, 1, 60)}`
		)
	end,

	["AC-1 control: the same message through bare assert is not intact, cut at exactly 511"] = function()
		local message = longMessage()
		local intact, received = arrivesIntact(function(m: string)
			assert(false, m)
		end, message)

		assert(
			not intact,
			"bare assert delivered the 2000-character message intact; the control means nothing"
		)
		-- Exactly 511: the first 511 characters are the tail of what arrived
		-- (after the position prefix), and the first 512 appear nowhere in it.
		assert(
			string.sub(received, -511) == string.sub(message, 1, 511),
			`the last 511 characters received are not the message's first 511: `
				.. `...{string.sub(received, -40)}`
		)
		assert(
			string.find(received, string.sub(message, 1, 512), 1, true) == nil,
			"the message's first 512 characters survived bare assert; the cap is not 511"
		)
	end,

	["AC-2: a passing contract check never builds its failure message"] = function()
		local eager: { string } = {}
		for _, case in PASSING do
			local count = buildsDuring(case.run)
			if count ~= 0 then
				table.insert(eager, `  {case.what}: {count} build(s)`)
			end
		end
		-- Through the raiser, not `assert`: this report grows a line per helper,
		-- and HARNESS-016's red run 3a watched its sibling below cut at 511.
		if #eager > 0 then
			Contract().fail(
				`a passing check built its failure message:\n{table.concat(eager, "\n")}`
			)
		end
	end,

	-- The non-zero half. Without it, a counter that is never incremented at all
	-- satisfies the zero half for the wrong reason.
	["AC-2 control: a failing contract check does build its message, and the counter sees it"] = function()
		local silent: { string } = {}
		for _, case in FAILING do
			local raised = false
			local count = buildsDuring(function()
				raised = not pcall(case.run)
			end)
			if not raised then
				table.insert(
					silent,
					`  {case.what}: the check PASSED, so this is not a failing run`
				)
			elseif count == 0 then
				table.insert(silent, `  {case.what}: raised, but the counter saw 0 builds`)
			end
		end
		if #silent > 0 then
			Contract().fail(
				`the counter did not see a failing check build:\n{table.concat(silent, "\n")}`
			)
		end
	end,

	["AC-4: no in-scope contract helper raises except through Contract.fail"] = function()
		local classified: { [string]: boolean } = {}
		for _, path in SourceScan.classifierList("test", "tests/helpers") do
			classified[path] = true
		end

		local missing: { string } = {}
		local found: { string } = {}
		for _, path in IN_SCOPE do
			if not classified[path] then
				table.insert(missing, `  {path}`)
			else
				for _, entry in bareRaises(path, fs.readFile(path)) do
					table.insert(found, entry)
				end
			end
		end

		assert(
			#missing == 0,
			`classify.sh --list test tests/helpers does not return:\n{table.concat(missing, "\n")}`
		)
		if #found > 0 then
			-- `error(_, 0)`, the raiser's own mechanism, rather than `Contract.fail`:
			-- this guard has to report its sites whole (129 of them overflow 511)
			-- in the run where `Contract.luau` does not exist yet.
			error(
				`AC-4: {#found} raise(s) in the in-scope helpers do not go through Contract.fail:\n`
					.. table.concat(found, "\n"),
				0
			)
		end
	end,

	--[[
		The control: ONE site reintroduced, reported by NAME and LINE. The real
		text of each in-scope helper is read and a bare `assert` - then, a direct
		`error` - is appended as a new last line, so the site the guard must name
		is `<path>:<that line>`. A count-only guard would see "1" and point at
		nothing. The end of the file, not some fixed line, because every helper
		opens with a long doc comment and a site inserted inside one is, correctly,
		not code.

		The scan runs over the edited text in memory: no file is written, so no
		test can see a helper with the site in it, and nothing needs restoring.
	]]
	["AC-4 control: one reintroduced bare assert or direct error is reported by file and line"] = function()
		local unreported: { string } = {}
		for _, path in IN_SCOPE do
			local original = fs.readFile(path)
			local baseline = #bareRaises(path, original)
			for _, symbol in RAISES do
				local edited, line = withLastLine(original, `{symbol}("probe")`)
				local report = bareRaises(path, edited)
				local expected = `  {path}:{line}: {symbol}`
				if not table.find(report, expected) then
					table.insert(
						unreported,
						`  {expected} was not reported; the report was:\n{table.concat(report, "\n")}`
					)
				elseif #report ~= baseline + 1 then
					table.insert(
						unreported,
						`  {path}: one inserted {symbol} changed the count by {#report - baseline}, not 1`
					)
				end
			end
		end
		if #unreported > 0 then
			Contract().fail(
				`the AC-4 guard missed a reintroduced site:\n{table.concat(unreported, "\n")}`
			)
		end
	end,

	--[[
		AC-3. Three sentences of `docs/wiki/stack.md`, each matched as a WHOLE
		LINE (after trimming) so that a line saying the opposite - "512
		characters of message, exactly" - cannot satisfy a needle that floats.
	]]
	["AC-3: stack.md records the cap as 511, keeps the prefix sentence, and records the off-by-one"] = function()
		local lines: { [string]: boolean } = {}
		for _, line in string.split(fs.readFile("docs/wiki/stack.md"), "\n") do
			lines[string.match(line, "^%s*(.-)%s*$") :: string] = true
		end
		local wanted = {
			"### An `assert` message is truncated at 511 characters, and the evidence goes with it",
			"**511 characters of message, exactly** — a fixed buffer, not a soft limit — plus",
			"*not* counted against the 511.",
			"**This section said 512 until `HARNESS-011`, and 512 was an off-by-one.** The",
		}
		local absent: { string } = {}
		for _, line in wanted do
			if not lines[line] then
				table.insert(absent, `  {line}`)
			end
		end
		assert(
			#absent == 0,
			`docs/wiki/stack.md has no line reading:\n{table.concat(absent, "\n")}`
		)
	end,

	["HARNESS-016 AC-3: no comment in tests/ quotes the assert cap as 512"] = function()
		local found: { string } = {}
		for _, path in SourceScan.classifierList("test", "tests") do
			for _, entry in capComments(path, fs.readFile(path)) do
				table.insert(found, entry)
			end
		end
		if #found > 0 then
			Contract().fail(
				`{#found} comment line(s) quote the cap as "{CAP_NEEDLE}"; it is 511:\n`
					.. table.concat(found, "\n")
			)
		end
	end,

	--[[
		Both halves, on a real helper's text in memory: the phrase appended as a
		COMMENT is reported at exactly that line, and the same phrase appended as
		a STRING LITERAL is not. The second half is what keeps the scan off code;
		a scan of whole lines would pass the first and fail it.
	]]
	["HARNESS-016 AC-3 control: a comment quoting 512 is reported by line, a string saying it is not"] = function()
		local path = "tests/helpers/RingContract.luau"
		local original = fs.readFile(path)
		local baseline = #capComments(path, original)

		local asComment, line = withLastLine(original, `-- assert keeps {CAP_NEEDLE}s`)
		local report = capComments(path, asComment)
		assert(
			table.find(report, `  {path}:{line}`) ~= nil and #report == baseline + 1,
			`a comment on line {line} was not reported alone; the report was:\n{table.concat(
				report,
				"\n"
			)}`
		)

		local asString = withLastLine(original, `local _ = "assert keeps {CAP_NEEDLE}s"`)
		local stringReport = capComments(path, asString)
		assert(
			#stringReport == baseline,
			`a string literal was reported as a comment:\n{table.concat(stringReport, "\n")}`
		)
	end,
}
