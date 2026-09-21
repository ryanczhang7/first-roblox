--!strict
--[[
	NET-002 AC-7: `src/net/Remotes.luau` and `src/server/round/PhaseMachine.luau`
	both export a `Phase` union, and the two must name exactly the same phases.

	WHY A GUARD AND NOT THE TYPECHECKER: the two unions never meet in any
	expression - nothing constructs a `GuardContext`, nothing in `src/net/`
	requires `PhaseMachine`, nothing in `src/server/` requires `Wrapper` - so
	`luau-lsp` has nothing to reject and exits 0 whether or not they agree.
	The Contract measured that; RED re-measured it. A `legalPhases` entry
	naming a phase the round machine never produces is a remote that is
	silently dead in that phase, which is AC-5's defect by another route.

	THE FILE LIST COMES FROM `scripts/classify.sh`, through
	`tests/helpers/SourceScan.luau`, never from a path of my own: both target
	paths are asserted to be IN the classifier's source set before they are
	read, so a module renamed or moved fails here rather than being a guard
	over nothing. THE EXTRACTION is `tests/helpers/PhaseUnion.luau`: the
	declaration is located in `SourceScan.codeOnly` output, so a union quoted
	in a doc comment is not a second declaration, and the names are read from
	the raw line because `codeOnly` blanks string contents.

	THIS TEST IS GREEN ON ARRIVAL - the two unions agree today - so it is
	earned two ways rather than watched to fail: the in-memory controls below
	drive the same `violations` function with a sixth phase, a missing phase,
	a reordering and a doc-comment decoy, and `## Regressions` in the story
	shows `scripts/mutate.sh` adding a sixth phase to each real file in turn
	and this test going red naming it.

	THE THREE VACUITY ASSERTIONS ARE THE CRITERION. Each extracted set must
	be non-empty, must contain all five known phases, and the failure must
	name the differing phase. A pattern that matches nothing compares `{}` to
	`{}` and passes; the "lacks the known phase" lines are what turn that
	into a failure with five names in it.

	WHAT THIS CANNOT SEE is in `PhaseUnion.luau`'s header: a union built by
	concatenation, from other aliases, single-quoted, or under another name.
	It catches the way the type is written today.
]]

local fs = require("@lune/fs")
local PhaseUnion = require("../helpers/PhaseUnion")
local SourceScan = require("../helpers/SourceScan")

local NET = "src/net/Remotes.luau"
local ROUND = "src/server/round/PhaseMachine.luau"

local function readSide(path: string): PhaseUnion.Side
	local sources = SourceScan.sourceFiles()
	assert(
		SourceScan.contains(sources, path),
		`{path} is not in the classifier's source set, so this guard would be reading a path of its `
			.. `own: classify.sh --list source src said: {table.concat(sources, ", ")}`
	)
	return PhaseUnion.read(path, fs.readFile(path))
end

-- The real text with a sixth phase appended to its union, the way a developer
-- adding an intermission would write it.
local function withSixthPhase(text: string, phase: string): string
	local edited, count =
		string.gsub(text, '(export type Phase = [^\n]-"Post")', `%1 | "{phase}"`, 1)
	assert(count == 1, `the fixture could not find the union to extend ({count} edits)`)
	return edited
end

-- The real text with one phase removed from its union.
local function withoutPhase(text: string, phase: string): string
	local edited, count = string.gsub(text, ` | "{phase}"`, "", 1)
	assert(count == 1, `the fixture could not find "{phase}" to remove ({count} edits)`)
	return edited
end

local function has(list: { string }, needle: string): boolean
	for _, line in list do
		if string.find(line, needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

return {
	--[[
		The vacuity guard on the FILE LIST, before anything is read: both
		modules are in the harness's source set. A module that moved would
		otherwise make the guard below a guard over a missing file.
	]]
	["AC-7: both Phase declarations are in the classifier's source set, and each file holds exactly one standing as code"] = function()
		local net = readSide(NET)
		local round = readSide(ROUND)
		assert(
			net.declarations == 1,
			`{NET} holds {net.declarations} 'export type Phase =' declaration(s) standing as code`
		)
		assert(
			round.declarations == 1,
			`{ROUND} holds {round.declarations} 'export type Phase =' declaration(s) standing as code`
		)
	end,

	["AC-7: src/net/Remotes.luau and src/server/round/PhaseMachine.luau export Phase unions naming exactly the same phases - each non-empty, each holding all five known phases, compared as sets"] = function()
		local net = readSide(NET)
		local round = readSide(ROUND)
		-- Repeated here rather than trusted from the test above: this is the
		-- assertion that could pass while proving nothing.
		assert(
			#net.phases > 0,
			`{NET}: the extraction found no phases; a guard over nothing passes`
		)
		assert(
			#round.phases > 0,
			`{ROUND}: the extraction found no phases; a guard over nothing passes`
		)
		for _, known in PhaseUnion.KNOWN do
			assert(
				table.find(net.phases, known) ~= nil,
				`{NET}: the extracted union lacks "{known}": {table.concat(net.phases, ", ")}`
			)
			assert(
				table.find(round.phases, known) ~= nil,
				`{ROUND}: the extracted union lacks "{known}": {table.concat(round.phases, ", ")}`
			)
		end

		local violations = PhaseUnion.violations(net, round)
		assert(
			#violations == 0,
			`the two Phase unions differ in {#violations} way(s); src/net/ re-declares the union `
				.. `because it may not require src/server/, and a phase one names and the other does `
				.. `not is a remote silently dead in that phase:\n`
				.. PhaseUnion.describe(violations)
		)
	end,

	--[[ The controls the criterion names: "a sixth phase added to EITHER
	     module alone must make this fail and must name the phase that
	     differs". Both directions, over the real text edited in memory. ]]

	["AC-7 control: a sixth phase in Remotes.luau's union alone is reported, naming Intermission and the file that has it"] = function()
		local net = PhaseUnion.read(NET, withSixthPhase(fs.readFile(NET), "Intermission"))
		local round = readSide(ROUND)
		assert(#net.phases == 6, `the fixture has {#net.phases} phases, expected 6`)
		local violations = PhaseUnion.violations(net, round)
		assert(
			#violations == 1,
			`expected exactly 1 violation, got {#violations}:\n` .. PhaseUnion.describe(violations)
		)
		assert(
			violations[1] == `{NET} names the phase "Intermission", which {ROUND} does not`,
			`the violation does not name the phase and the side that has it: {violations[1]}`
		)
	end,

	["AC-7 control: a sixth phase in PhaseMachine.luau's union alone is reported, naming Intermission and the file that has it"] = function()
		local net = readSide(NET)
		local round = PhaseUnion.read(ROUND, withSixthPhase(fs.readFile(ROUND), "Intermission"))
		assert(#round.phases == 6, `the fixture has {#round.phases} phases, expected 6`)
		local violations = PhaseUnion.violations(net, round)
		assert(
			#violations == 1,
			`expected exactly 1 violation, got {#violations}:\n` .. PhaseUnion.describe(violations)
		)
		assert(
			violations[1] == `{ROUND} names the phase "Intermission", which {NET} does not`,
			`the violation does not name the phase and the side that has it: {violations[1]}`
		)
	end,

	["AC-7 control: a phase missing from one side is reported twice - as a known phase the side lacks, and as a phase the other side names"] = function()
		local net = PhaseUnion.read(NET, withoutPhase(fs.readFile(NET), "Resolution"))
		local round = readSide(ROUND)
		assert(#net.phases == 4, `the fixture has {#net.phases} phases, expected 4`)
		local violations = PhaseUnion.violations(net, round)
		assert(
			#violations == 2,
			`expected exactly 2 violations, got {#violations}:\n` .. PhaseUnion.describe(violations)
		)
		assert(
			has(violations, `{NET}: the Phase union lacks the known phase "Resolution"`),
			"the missing known phase is not reported:\n" .. PhaseUnion.describe(violations)
		)
		assert(
			has(violations, `{ROUND} names the phase "Resolution", which {NET} does not`),
			"the side that still names it is not reported:\n" .. PhaseUnion.describe(violations)
		)
	end,

	["AC-7 control: the same five phases in a different order are not a difference"] = function()
		local shuffled = PhaseUnion.read(
			"src/net/Shuffled.luau",
			'export type Phase = "Post" | "Round" | "Lobby" | "Resolution" | "Assignment"\n'
		)
		local round = readSide(ROUND)
		local violations = PhaseUnion.violations(shuffled, round)
		assert(
			#violations == 0,
			"reordering was reported as a difference:\n" .. PhaseUnion.describe(violations)
		)
	end,

	--[[ The extraction's own discrimination, in memory. ]]

	["AC-7 control: a union in a doc comment, a line comment or a string literal is not a declaration - the extraction matches nothing and every vacuity assertion fires"] = function()
		local decoy = table.concat({
			"--!strict",
			'--[[ The union is export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post" ]]',
			'-- export type Phase = "Lobby" | "Round"',
			'local doc = \'export type Phase = "Lobby" | "Post"\'',
			"return doc",
		}, "\n")
		local side = PhaseUnion.read("src/net/Decoy.luau", decoy)
		assert(side.declarations == 0, `the decoy yielded {side.declarations} declaration(s)`)
		assert(#side.phases == 0, `the decoy yielded phases: {table.concat(side.phases, ", ")}`)

		local violations = PhaseUnion.violations(side, readSide(ROUND))
		-- 1 (declaration count) + 1 (empty) + 5 (each known phase lacking) + 5
		-- (each phase the other side names) = 12 lines, all against the decoy.
		assert(
			#violations == 12,
			`expected 12 violations against an empty side, got {#violations}:\n`
				.. PhaseUnion.describe(violations)
		)
		assert(
			has(
				violations,
				"src/net/Decoy.luau: the Phase union names no phases - the extraction matched nothing"
			),
			"the empty extraction is not called out:\n" .. PhaseUnion.describe(violations)
		)
		for _, known in PhaseUnion.KNOWN do
			assert(
				has(
					violations,
					`src/net/Decoy.luau: the Phase union lacks the known phase "{known}"`
				),
				`"{known}" is not reported as lacking:\n` .. PhaseUnion.describe(violations)
			)
		end
	end,

	["AC-7 control: a union wrapped across lines is read whole, a trailing comment on the declaration line contributes nothing, and a phase named twice is reported"] = function()
		local wrapped = table.concat({
			"--!strict",
			"export type Phase =",
			'\t| "Lobby"',
			'\t| "Assignment" -- was "Setup"',
			'\t| "Round"',
			'\t| "Resolution"',
			'\t| "Post"',
			"",
			'local x = "Lobby"',
			"return x",
		}, "\n")
		local side = PhaseUnion.read("src/net/Wrapped.luau", wrapped)
		assert(
			side.declarations == 1,
			`the wrapped union yielded {side.declarations} declaration(s)`
		)
		assert(
			table.concat(side.phases, ",") == "Lobby,Assignment,Round,Resolution,Post",
			`the wrapped union read as: {table.concat(side.phases, ", ")}`
		)
		assert(
			#PhaseUnion.violations(side, readSide(ROUND)) == 0,
			"a wrapped union was reported as differing"
		)

		local trailing = 'export type Phase = "Lobby" | "Round" -- | "Post" | "Setup"\n'
		local trailingSide = PhaseUnion.read("src/net/Trailing.luau", trailing)
		assert(
			table.concat(trailingSide.phases, ",") == "Lobby,Round",
			`the trailing comment contributed a phase: {table.concat(trailingSide.phases, ", ")}`
		)

		local twice =
			'export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post" | "Round"\n'
		local twiceSide = PhaseUnion.read("src/net/Twice.luau", twice)
		local violations = PhaseUnion.violations(twiceSide, readSide(ROUND))
		assert(
			#violations == 1,
			`expected 1 violation for a duplicated phase, got {#violations}:\n`
				.. PhaseUnion.describe(violations)
		)
		assert(
			violations[1] == 'src/net/Twice.luau: the Phase union names "Round" 2 times',
			`the duplicate is not named: {violations[1]}`
		)
	end,

	["AC-7 control: two declarations in one file are reported by count, and a second file's union in a comment does not count as one"] = function()
		local doubled = table.concat({
			'export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post"',
			'export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post"',
		}, "\n")
		local side = PhaseUnion.read("src/net/Doubled.luau", doubled)
		assert(
			side.declarations == 2,
			`the doubled file yielded {side.declarations} declaration(s)`
		)
		local violations = PhaseUnion.violations(side, readSide(ROUND))
		assert(
			has(
				violations,
				"src/net/Doubled.luau: found 2 'export type Phase =' declaration(s) standing as code; expected exactly one"
			),
			"the declaration count is not reported:\n" .. PhaseUnion.describe(violations)
		)
		-- The real file's own doc comment is the second file of the title:
		-- Remotes.luau's header talks about `Phase` and is not a declaration.
		assert(
			readSide(NET).declarations == 1,
			"Remotes.luau's header comment counted as a declaration"
		)
	end,
}
