--!strict
--[[
	The negative controls for NET-001, and the proof that each check in
	`tests/helpers/NetContract.luau` refuses the module it exists to catch.

	TWO CRITERIA NAME THEIR CONTROL. AC-5: a wrapper that rejects everything
	"passes AC-2, AC-3 and AC-4 and must fail this". AC-6: an implementation
	returning a single boolean false "must fail this". Both are asserted below
	in exactly those terms - the passes as well as the failure - because the
	story's success condition is that the two controls are DEMONSTRATED.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half
	is the one that is easy to leave out and worth the most: a stub that fails
	EVERY check proves only that the checks reject something, and a control
	that fails everything is indistinguishable from a broken stub.

	WHERE A CONTROL FAILS MORE THAN ONE CHECK, IT IS SAID SO, with the number
	MEASURED here rather than predicted - the measurement was taken outside
	the runner first (`## Handoff`), then pinned. The reject-everything wrapper
	fails AC-1 as well as AC-5, because AC-1 counts handler runs and a
	rejected call runs none; the boolean-false wrapper fails AC-2, AC-3 and
	AC-4 as well as AC-6, because each of those asserts the REASON and `false`
	has none. Those are properties of the defects, not of the checks.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED `src/net/` does not
	exist and every test in `schema_test`, `remotes_test` and `wrapper_test`
	fails before reaching its check. These controls need only `Clock.manual`
	from ROUND-001 and `Deep` from ROUND-003, both merged, so the numbers
	below are measurements taken in RED rather than claims left for GREEN.
]]

local Contract = require("../helpers/NetContract")
local Stubs = require("../helpers/NetStubs")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local function accepts(check: Check, subject: any, what: string)
	local ok, err = pcall(check, subject)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function refuses(check: Check, subject: any, what: string): string
	local ok, err = pcall(check, subject)
	assert(ok == false, `{what}\n  but the check passed, so the check is vacuous`)
	return tostring(err)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

local function lacks(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) == nil,
		`{what}, but the failure message mentions "{fragment}":\n{message}`
	)
end

local SCHEMA_CHECKS: { Named } = {
	{
		label = "Schema.integer",
		check = Contract.integerSchemaAcceptsTheInclusiveDomainAndRejectsByKind,
	},
	{
		label = "Schema.number",
		check = Contract.numberSchemaAcceptsTheInclusiveDomainAndRejectsByKind,
	},
	{ label = "Schema.boolean", check = Contract.booleanSchemaAcceptsOnlyBooleans },
	{ label = "Schema.literal", check = Contract.literalSchemaAcceptsOnlyTheGivenStrings },
	{ label = "Schema.shape", check = Contract.shapeSchemaIsExact },
	{ label = "Schema.optional", check = Contract.optionalSchemaAcceptsNilAndDefersToTheInner },
	{ label = "Schema never raises", check = Contract.validateNeverRaisesOnHostileInput },
}

local REMOTES_CHECKS: { Named } = {
	{ label = "Remotes.define/all", check = Contract.defineReturnsTheDeclarationAndAllListsIt },
	{ label = "AC-8", check = Contract.redeclaringANameFails },
}

local WRAPPER_CHECKS: { Named } = {
	{ label = "AC-1", check = Contract.handlerRunsExactlyOnceWithTheValidatedArguments },
	{ label = "AC-2", check = Contract.malformedPayloadIsRejectedForShape },
	{ label = "AC-3", check = Contract.outOfRangeNumberIsRejectedForRange },
	{ label = "AC-4", check = Contract.unseatedPlayerIsRejectedForIdentity },
	{ label = "AC-5", check = Contract.validCallIsAccepted },
	{ label = "AC-6 names", check = Contract.rejectionNamesTheCheckThatFired },
	{ label = "AC-6 order", check = Contract.checksRunIdentityThenShapeThenRange },
	{ label = "never raises", check = Contract.guardedCallNeverRaises },
	{ label = "short-circuit", check = Contract.identityFailureShortCircuitsBeforeTheSchema },
	{ label = "kind mapping", check = Contract.wrapperReadsTheKindFromTheSchemasFailureString },
}

local ALL_CHECKS: { Named } = {}
for _, group in { SCHEMA_CHECKS, REMOTES_CHECKS, WRAPPER_CHECKS } do
	for _, entry in group do
		table.insert(ALL_CHECKS, entry)
	end
end

local function checkNamed(label: string): Check
	for _, entry in ALL_CHECKS do
		if entry.label == label then
			return entry.check
		end
	end
	error(`no check labelled {label}`)
end

-- Every check, so a control is held to all of them except the ones it is
-- built to fail - and every one of those is asserted to fail, by name.
local function holdsExactly(subject: any, who: string, failing: { string })
	local except: { [string]: boolean } = {}
	for _, label in failing do
		except[label] = true
	end
	for _, entry in ALL_CHECKS do
		if except[entry.label] then
			refuses(entry.check, subject, `{entry.label} on {who} must fail`)
		else
			accepts(entry.check, subject, `{entry.label} on {who} must pass`)
		end
	end
end

return {
	--[[ The baseline. Every control below is this with exactly one defect set,
	     so a control that fires is attributable to that one thing. This is
	     also the proof that the checks are satisfiable at all. ]]

	["baseline: a correct Schema, Remotes and Wrapper pass all 19 checks"] = function()
		assert(#ALL_CHECKS == 19, `expected 19 checks, found {#ALL_CHECKS}`)
		holdsExactly(Stubs.correct(), "the baseline", {})
	end,

	--[[
		AC-5's control, named in the criterion. The story's claim is asserted
		word for word: it PASSES AC-2, AC-3 and AC-4 - and AC-6, whose every
		rejection is well-formed - and FAILS AC-5. It also fails AC-1 (the
		handler never runs), the short-circuit check (the seated call is not
		accepted) and the kind-mapping check (an accepting schema does not lead
		to acceptance). Measured: 4 failures of 19.
	]]
	["AC-5 control: a wrapper that rejects everything passes AC-2, AC-3, AC-4 and both halves of AC-6, and fails AC-5 on all 4 valid calls (plus AC-1, short-circuit and kind mapping: 4 of 19)"] = function()
		local net = Stubs.with("rejectEverything")
		holdsExactly(
			net,
			"the reject-everything wrapper",
			{ "AC-1", "AC-5", "short-circuit", "kind mapping" }
		)

		local message =
			refuses(checkNamed("AC-5"), net, "a wrapper that rejects everything must fail AC-5")
		names(message, "AC-5 failed in 4 case(s) of 4", "AC-5 fires on every valid call")
		names(
			message,
			"a wrapper that rejects everything fails here",
			"the AC-5 failure says what it caught"
		)
		names(
			message,
			'{ token = 1, flag = true } (the minimum) by a seated player was REJECTED: reason = "shape", detail = "rejected"',
			"the AC-5 failure shows the rejection the valid call got"
		)
	end,

	--[[
		AC-6's control, named in the criterion. FAILS both halves of AC-6 - and
		AC-2, AC-3 and AC-4, because each asserts WHICH check fired and `false`
		names none, which is the whole point of D7. PASSES AC-1 and AC-5: a
		boolean-false wrapper still accepts valid calls, so the two positive
		checks cannot tell it from a correct one; only the reason can. Measured:
		8 failures of 19.
	]]
	["AC-6 control: a wrapper returning a single boolean false passes AC-1 and AC-5 and fails both halves of AC-6 on every case (plus AC-2, AC-3, AC-4, never-raises, short-circuit and kind mapping: 8 of 19)"] = function()
		local net = Stubs.with("booleanFalse")
		holdsExactly(net, "the boolean-false wrapper", {
			"AC-2",
			"AC-3",
			"AC-4",
			"AC-6 names",
			"AC-6 order",
			"never raises",
			"short-circuit",
			"kind mapping",
		})

		local message =
			refuses(checkNamed("AC-6 names"), net, "a boolean-false wrapper must fail AC-6")
		names(message, "AC-6 failed in 21 case(s) of 21", "AC-6 fires on every rejection")
		names(
			message,
			"identity: unseated player, valid payload -> the rejection is false, not a table naming the check that fired",
			"the AC-6 failure names the boolean and the case"
		)
		local order = refuses(
			checkNamed("AC-6 order"),
			net,
			"a boolean-false wrapper must fail AC-6's order half too"
		)
		names(order, "AC-6 order failed in 8 case(s) of 8", "the order half fires on every case")
	end,

	--[[ The mutations `## Notes` asks the orchestrator to run at acceptance. ]]

	["mutation 1 control: a permissive shape fails AC-2 on exactly the two extra-key cases (plus the handler having run), Schema.shape on 4 of 21 and Schema.optional on 1 of 6, and passes everything else"] = function()
		local net = Stubs.with("permissiveShape")
		holdsExactly(
			net,
			"the permissive shape",
			{ "Schema.shape", "Schema.optional", "AC-2", "AC-6 names" }
		)

		local message = refuses(checkNamed("AC-2"), net, "a permissive shape must fail AC-2")
		names(
			message,
			"AC-2 failed in 3 case(s) of 14",
			"AC-2 reports the two extra-key cases and the handler count"
		)
		names(
			message,
			"wrong number of arguments (one key too many): { token = 4, flag = true, extra = 1 } -> ACCEPTED",
			"the arity-as-key-count case is the first"
		)
		names(
			message,
			"extra unexpected field: { token = 4, flag = true, admin = true } -> ACCEPTED",
			"the smuggled admin field is the second"
		)
		names(
			message,
			"the handler ran 2 time(s) across 14 malformed payloads",
			"the handler was reachable"
		)
		lacks(message, "missing required field", "a permissive shape still catches a missing field")

		local schema =
			refuses(checkNamed("Schema.shape"), net, "a permissive shape must fail the unit check")
		names(
			schema,
			"Schema.shape failed in 4 case(s) of 21",
			"the unit check reports the extra-key cases"
		)
	end,

	["mutation 2 control: collapsing every reason to shape fails AC-3 on 6 of 6, AC-4, and AC-6 order on 6 of 8 - and passes AC-2, whose reason really is shape"] = function()
		local net = Stubs.with("collapseToShape")
		holdsExactly(
			net,
			"the collapse-to-shape wrapper",
			{ "AC-3", "AC-4", "AC-6 order", "short-circuit", "kind mapping" }
		)

		local message = refuses(checkNamed("AC-3"), net, "collapsing to shape must fail AC-3")
		names(message, "AC-3 failed in 6 case(s) of 6", "every range case is reported")
		names(message, 'NaN: token = 0/0 -> rejected for "shape", expected "range"', "NaN is named")
		local identity = refuses(checkNamed("AC-4"), net, "collapsing to shape must fail AC-4")
		names(identity, 'rejected for "shape", expected "identity"', "the identity case is named")
		local order = refuses(
			checkNamed("AC-6 order"),
			net,
			"collapsing to shape must fail AC-6's order half"
		)
		names(
			order,
			"AC-6 order failed in 6 case(s) of 8",
			"only the two genuinely-shape cases survive"
		)
	end,

	["mutation 3 control: identity checked after shape fails AC-6 order on 5 of 8 and the short-circuit check, and passes AC-4 - whose payload is valid, so the order is invisible to it"] = function()
		local net = Stubs.with("identityAfterShape")
		holdsExactly(net, "the identity-after-shape wrapper", { "AC-6 order", "short-circuit" })

		local message = refuses(
			checkNamed("AC-6 order"),
			net,
			"identity after shape must fail AC-6's order half"
		)
		names(message, "AC-6 order failed in 5 case(s) of 8", "every unseated case is reported")
		names(
			message,
			'unseated + {} (arity) -> identity -> rejected for "shape", expected "identity"',
			"the criterion's own example is named"
		)
		local short = refuses(
			checkNamed("short-circuit"),
			net,
			"identity after shape consults the schema first"
		)
		names(
			short,
			"the schema was consulted 1 time(s) for an unseated caller",
			"the spy schema saw the call"
		)
	end,

	--[[ The one-defect modules the remaining checks would otherwise have no
	     control for. Each is a plausible wrong implementation. ]]

	["control: a wrapper that runs the handler twice fails AC-1 alone among the criteria, saying 2"] = function()
		local net = Stubs.with("runsHandlerTwice")
		holdsExactly(net, "the twice-running wrapper", { "AC-1", "short-circuit", "kind mapping" })
		local message = refuses(checkNamed("AC-1"), net, "running the handler twice must fail AC-1")
		names(
			message,
			"the handler ran 2 time(s) for one valid call; it must run exactly once",
			"AC-1 counts"
		)
	end,

	["control: a wrapper that drops the arguments fails AC-1 alone, by structural diff"] = function()
		local net = Stubs.with("dropsArgs")
		holdsExactly(net, "the argument-dropping wrapper", { "AC-1" })
		local message = refuses(checkNamed("AC-1"), net, "dropping the arguments must fail AC-1")
		names(
			message,
			"the handler did not receive the validated arguments",
			"AC-1 compares the arguments"
		)
	end,

	["control: a wrapper that never checks the seat fails AC-4, both halves of AC-6 and short-circuit"] = function()
		local net = Stubs.with("skipsIdentity")
		holdsExactly(
			net,
			"the seat-less wrapper",
			{ "AC-4", "AC-6 names", "AC-6 order", "short-circuit" }
		)
		local message = refuses(checkNamed("AC-4"), net, "skipping identity must fail AC-4")
		names(
			message,
			"ACCEPTED (returned nil); the handler was reachable",
			"the unseated call got through"
		)
	end,

	["control: a wrapper that runs the handler before the verdict fails AC-2, AC-3, AC-4 and AC-6 order on the handler count"] = function()
		local net = Stubs.with("runsHandlerOnReject")
		holdsExactly(
			net,
			"the handler-first wrapper",
			{ "AC-2", "AC-3", "AC-4", "AC-6 order", "short-circuit", "kind mapping" }
		)
		local message =
			refuses(checkNamed("AC-2"), net, "running the handler on a rejection must fail AC-2")
		names(
			message,
			"the handler ran 14 time(s) across 14 malformed payloads",
			"AC-2 counts the handler"
		)
	end,

	["control: a wrapper whose schema step indexes a non-table raises, and fails never-raises on 2 of 14, AC-2 on 4 of 14 (a string payload indexes through the string metatable and does not raise) and AC-6 names"] = function()
		local net = Stubs.with("raisesOnNonTable")
		holdsExactly(
			net,
			"the raising wrapper",
			{ "AC-2", "AC-6 names", "never raises", "kind mapping" }
		)
		local message =
			refuses(checkNamed("never raises"), net, "an unguarded index must fail never-raises")
		names(
			message,
			"raised or returned a non-Rejection in 2 case(s) of 14",
			"the function and the thread payloads raise"
		)
		names(message, "a thread as rawArgs -> RAISED", "the thread payload is named")
		local shape = refuses(checkNamed("AC-2"), net, "an unguarded index must fail AC-2")
		names(
			shape,
			"AC-2 failed in 4 case(s) of 14",
			"nil, a number, a boolean and a function raise; the string does not"
		)
		names(
			shape,
			"rawArgs is nil -> the guarded call RAISED instead of rejecting",
			"nil is named"
		)
	end,

	["control: a wrapper that consults the schema before the seat check - with identity still winning - fails only the short-circuit check"] = function()
		local net = Stubs.with("consultsSchemaFirst")
		holdsExactly(net, "the eager wrapper", { "short-circuit" })
	end,

	["control: an integer schema that files 3.5 as shape fails AC-3 (3.5 and, through floor ~= value, NaN), Schema.integer on 4 of 18 and Schema.shape on 1 of 21"] = function()
		local net = Stubs.with("nonIntegerIsShape")
		holdsExactly(
			net,
			"the non-integer-is-shape schema",
			{ "Schema.integer", "Schema.shape", "AC-3" }
		)
		local message = refuses(checkNamed("AC-3"), net, "3.5 as shape must fail AC-3")
		names(message, "AC-3 failed in 2 case(s) of 6", "3.5 and NaN are reported")
		names(
			message,
			'a non-integer where an integer is declared: token = 3.5 -> rejected for "shape", expected "range"',
			"3.5 is named with the wrong kind"
		)
		local unit =
			refuses(checkNamed("Schema.integer"), net, "3.5 as shape must fail the unit check")
		names(
			unit,
			"3.5 (non-integer) -> failed as shape, expected range",
			"the unit check names the case"
		)
	end,

	["control: a schema that files NaN and the infinities as shape fails AC-3 on 3 of 6, Schema.integer on 3 of 18 and Schema.number on 3 of 13"] = function()
		local net = Stubs.with("nanIsShape")
		holdsExactly(net, "the NaN-is-shape schema", { "Schema.integer", "Schema.number", "AC-3" })
		local message = refuses(checkNamed("AC-3"), net, "NaN as shape must fail AC-3")
		names(
			message,
			"AC-3 failed in 3 case(s) of 6",
			"NaN, math.huge and -math.huge are reported"
		)
		names(
			message,
			'math.huge: token = math.huge -> rejected for "shape", expected "range"',
			"math.huge is named"
		)
	end,

	["control: a schema that runs the domain pass before the structural one fails AC-6 order on the 2 mixed payloads and Schema.shape on 3 of 21, and nothing else"] = function()
		local net = Stubs.with("rangeBeforeShape")
		holdsExactly(net, "the range-first schema", { "Schema.shape", "AC-6 order" })
		local message =
			refuses(checkNamed("AC-6 order"), net, "range before shape must fail AC-6's order half")
		names(message, "AC-6 order failed in 2 case(s) of 8", "exactly the two mixed payloads")
		names(
			message,
			'seated + { token = 99, flag = "no" } (range in one field, shape in the other) -> shape -> rejected for "range", expected "shape"',
			"the mixed payload is named"
		)
	end,

	["control: a schema with an exclusive maximum fails AC-1 and AC-5 at the maximum, and the three numeric unit checks"] = function()
		local net = Stubs.with("exclusiveMaximum")
		holdsExactly(
			net,
			"the exclusive-maximum schema",
			{ "Schema.integer", "Schema.number", "Schema.shape", "AC-1", "AC-5" }
		)
		local message = refuses(checkNamed("AC-5"), net, "an exclusive maximum must fail AC-5")
		names(message, "AC-5 failed in 1 case(s) of 4", "only the maximum is refused")
		names(
			message,
			"{ token = 16, flag = false } (the maximum) by a seated player was REJECTED",
			"the maximum is named"
		)
	end,

	["AC-8 control: a registry that silently replaces a duplicate fails AC-8 alone"] = function()
		local net = Stubs.with("silentRedeclare")
		holdsExactly(net, "the silently-replacing registry", { "AC-8" })
		local message = refuses(checkNamed("AC-8"), net, "silent replacement must fail AC-8")
		names(
			message,
			"a second time did not fail; it returned",
			"AC-8 reports the accepted duplicate"
		)
	end,

	["control: a registry whose all() is the live table fails the define/all check alone"] = function()
		local net = Stubs.with("leaksRegistry")
		holdsExactly(net, "the leaking registry", { "Remotes.define/all" })
		local message =
			refuses(checkNamed("Remotes.define/all"), net, "a leaked registry must fail")
		names(
			message,
			"hands out the live registry; a caller inserted a definition into it",
			"the leak is named"
		)
	end,
}
