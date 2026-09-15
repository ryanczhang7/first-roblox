--!strict
--[[
	The negative controls for ROUND-001 AC-2, AC-3 and AC-4.

	`## Model guidance` makes this file the story's success condition for RED:
	"the AC-2, AC-3 and AC-5 controls each fail against a plausible wrong
	implementation, demonstrated in the handoff - not merely described".

	It requires NO production code, deliberately. In RED `src/shared/Rng.luau` does
	not exist, `rng_test.luau` cannot load, and not one assertion in that file
	runs - which is exactly the condition `.claude/harness/rules.md` warns leaves
	every threshold in a suite unverified for a whole phase. The checks in
	`RngContract.luau` are the same objects `rng_test.luau` uses, so running them
	here against known-wrong implementations is a real measurement of whether they
	discriminate, taken now rather than promised for later.

	Each control asserts BOTH directions: the wrong implementation passes the
	check the story says it passes, and fails the one the story says catches it.
	Only the second half is the control; the first half is what proves the fake is
	plausible rather than merely broken.
]]

local Fakes = require("../helpers/Fakes")
local RngContract = require("../helpers/RngContract")

local function accepts(check: (any) -> (), factory: any, what: string)
	local ok, err = pcall(check, factory)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: (any) -> (), factory: any, what: string): string
	local ok, err = pcall(check, factory)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

return {
	--[[
		The baseline. Every control below is this implementation with exactly one
		thing broken, so a control that fires is attributable to that one thing.
	]]
	["baseline: a correct Rng passes every AC-2, AC-3 and AC-4 check"] = function()
		accepts(RngContract.sameSeedReproduces, Fakes.correct, "AC-2 reproducibility")
		accepts(RngContract.differentSeedsDiverge, Fakes.correct, "AC-2 divergence")
		accepts(RngContract.sameLabelSameSubStream, Fakes.correct, "AC-3 same label")
		accepts(RngContract.deriveIsIndependent, Fakes.correct, "AC-3 independence")
		accepts(RngContract.differentLabelsDiffer, Fakes.correct, "Contract label determinism")
		accepts(RngContract.shuffleIsAPermutation, Fakes.correct, "AC-4 permutation")
		accepts(RngContract.shuffleDoesNotMutateItsInput, Fakes.correct, "AC-4 no mutation")
		accepts(RngContract.shuffleHandlesEmptyAndSingleton, Fakes.correct, "AC-4 empty and one")
		accepts(RngContract.shuffleActuallyPermutes, Fakes.correct, "AC-4 shuffle permutes")
	end,

	["AC-2 control: an Rng that ignores its seed is reproducible and is still rejected"] = function()
		accepts(
			RngContract.sameSeedReproduces,
			Fakes.seedIgnoring,
			"a seed-ignoring Rng must pass the reproducibility half - that is the trap"
		)

		local message = refuses(
			RngContract.differentSeedsDiverge,
			Fakes.seedIgnoring,
			"a seed-ignoring Rng must fail AC-2's different-seeds half"
		)
		assert(
			string.find(message, "AC-2", 1, true) ~= nil,
			`the AC-2 failure does not name the criterion: {message}`
		)
		assert(
			string.find(message, "the seed is not being used", 1, true) ~= nil,
			`the AC-2 failure does not say what is wrong: {message}`
		)
	end,

	["AC-3 control: a derive that returns the parent passes the same-label check and is still rejected"] = function()
		accepts(
			RngContract.sameLabelSameSubStream,
			Fakes.selfDeriving,
			"a self-returning derive must pass AC-3's same-label half - that is the trap"
		)

		local message = refuses(
			RngContract.deriveIsIndependent,
			Fakes.selfDeriving,
			"a self-returning derive must fail AC-3's independence half"
		)
		assert(
			string.find(message, "AC-3", 1, true) ~= nil,
			`the AC-3 failure does not name the criterion: {message}`
		)
		assert(
			string.find(message, 'derive("a")', 1, true) ~= nil,
			`the AC-3 failure does not name the sub-stream that was drained: {message}`
		)
	end,

	--[[
		The second AC-3 control, and the one AC-3's own two halves do not catch: a
		`derive` that is deterministic in the parent seed and ignores the label.
		It passes same-label AND independence, and hands "seats" and "instance"
		the same numbers. The Contract's "deterministic in (parent seed, label)"
		is what rejects it.
	]]
	["Contract control: a derive that ignores its label passes both AC-3 halves and is still rejected"] = function()
		accepts(
			RngContract.sameLabelSameSubStream,
			Fakes.labelIgnoringDerive,
			"a label-ignoring derive must pass AC-3's same-label half"
		)
		accepts(
			RngContract.deriveIsIndependent,
			Fakes.labelIgnoringDerive,
			"a label-ignoring derive must pass AC-3's independence half - its streams are fresh"
		)

		local message = refuses(
			RngContract.differentLabelsDiffer,
			Fakes.labelIgnoringDerive,
			"a label-ignoring derive must fail the label-determinism check"
		)
		assert(
			string.find(message, "the label is not being used", 1, true) ~= nil,
			`the label failure does not say what is wrong: {message}`
		)
	end,

	["AC-4 control: a shuffle that permutes in place is a permutation and is still rejected"] = function()
		accepts(
			RngContract.shuffleIsAPermutation,
			Fakes.mutatingShuffle,
			"an in-place shuffle must pass AC-4's permutation half - that is the trap"
		)

		local message = refuses(
			RngContract.shuffleDoesNotMutateItsInput,
			Fakes.mutatingShuffle,
			"an in-place shuffle must fail AC-4's no-mutation half"
		)
		assert(
			string.find(message, "AC-4", 1, true) ~= nil,
			`the AC-4 failure does not name the criterion: {message}`
		)
		assert(
			string.find(message, "mutated its argument", 1, true) ~= nil,
			`the AC-4 failure does not say what is wrong: {message}`
		)
	end,
}
