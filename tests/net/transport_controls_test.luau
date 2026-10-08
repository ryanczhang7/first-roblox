--!strict
--[[
	The negative controls for SLICE-002, and the proof that each check in
	`tests/helpers/TransportContract.luau` refuses the transport it exists to
	catch.

	THE CRITERIA NAME THEIR CONTROLS. AC-1: "a `bind` that connects the
	handler directly (no guard) must fail this AC" - `bindBypassesGuard`,
	which is also the second of D-1's two mutations. AC-3: "a `sendTo`
	implemented with `FireAllClients` must fail this AC" - `sendToFiresAll`,
	D-1's first. The rest are one-defect transports for the Contract blocks
	C-1 through C-7 the remaining checks would otherwise have no control for.

	EVERY CONTROL IS ASSERTED TO FAIL EXACTLY THE CHECKS IT SHOULD, and the
	baseline is asserted to pass every check: a control failing a check is
	then a control with ONE defect rather than a broken stub, and a control
	that starts failing a check it did not fail before is a change in what
	the suite discriminates, worth a red line. The sets below were MEASURED
	outside the runner first (`build/measure_transport.luau`, recorded in the
	story's `## Handoff`) and pinned exactly here. Two of them are properties
	of the fixture rather than of the defect: `bindConnectsTwice` fails
	twelve checks because `bindWorld` asserts exactly one connection per
	remote before handing a world out (the vacuity guard), and
	`privateKindsMissingOne` fails five because every send of `PingRefused`
	then raises.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. The transports are
	`TransportStubs.luau` over the merged `Wrapper` and `Schema`, so these
	controls EXECUTE in RED while `transport_test.luau`'s assertions against
	the real `src/ReplicatedStorage/Net/Transport.luau` and
	`ClientTransport.luau` are red at require.
]]

local Contract = require("../helpers/TransportContract")
local Stubs = require("../helpers/TransportStubs")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local CHECKS: { Named } = {
	{ label = "AC-1 once", check = Contract.bindConnectsEachDeclaredRemoteExactlyOnce },
	{
		label = "AC-1 shape",
		check = Contract.malformedCallIsRejectedForShapeAndNeverReachesTheHandler,
	},
	{
		label = "AC-1 handler",
		check = Contract.wellFormedCallReachesTheHandlerWithTheMappedIdAndACallControl,
	},
	{
		label = "C-1 decline",
		check = Contract.aHandlerThatDeclinesMakesTheConnectedFunctionReturnDeclined,
	},
	{
		label = "AC-2 unhandled",
		check = Contract.bindRaisesNamingADeclaredRemoteWithNoHandlerBeforeTouchingPorts,
	},
	{
		label = "AC-2 undeclared",
		check = Contract.bindRaisesNamingAHandlerForAnUndeclaredRemoteBeforeTouchingPorts,
	},
	{ label = "C-4", check = Contract.bindReadsEveryPortExactlyOnceAndSendsReadNone },
	{ label = "AC-3", check = Contract.sendToFiresEachPrivateKindOnItsOwnEventToThatPlayerOnly },
	{ label = "AC-3 no-op", check = Contract.sendToForAPlayerWithNoObjectIsANoOp },
	{
		label = "AC-4 private",
		check = Contract.broadcastWithAPrivateKindRaisesNamingItAndFiresNothing,
	},
	{ label = "AC-4 public", check = Contract.broadcastFiresEachPublicKindOnceOnItsOwnEvent },
	{ label = "AC-4 sets", check = Contract.kindSetsAreExactlyTheSixAndTheFour },
	{
		label = "C-6 sendTo",
		check = Contract.sendToWithAPublicOrUnknownKindRaisesNamingItAndFiresNothing,
	},
	{
		label = "C-6 broadcast",
		check = Contract.broadcastWithAnUnknownKindRaisesNamingItAndFiresNothing,
	},
	{
		label = "AC-5",
		check = Contract.unmappedPlayerIsRejectedForIdentityAndTheRawObjectReachesNothing,
	},
	{ label = "C-3", check = Contract.mappedPlayerIsIdentifiedOncePerCallAndNeverSeenRaw },
	{ label = "C-7 init", check = Contract.clientOnAndSendBeforeInitRaiseNamingTheCall },
	{ label = "AC-6 on", check = Contract.clientOnDeliversEachKindsPayloadToItsOwnListener },
	{ label = "AC-6 send", check = Contract.clientSendCallsFireServerWithArgsAsTheSinglePayload },
	{ label = "C-7 unknown", check = Contract.clientOnWithAKindInNeitherSetRaisesNamingIt },
	{ label = "C-7 replace", check = Contract.clientInitAgainReplacesThePorts },
}

local ALL_SERVER_CHECKS_AFTER_BIND: { string } = {
	"AC-1 once",
	"AC-1 shape",
	"AC-1 handler",
	"C-4",
	"AC-3",
	"AC-3 no-op",
	"AC-4 private",
	"AC-4 public",
	"C-6 sendTo",
	"C-6 broadcast",
	"AC-5",
	"C-3",
}

local function accepts(check: Check, subject: any, what: string)
	local ok, err = pcall(check, subject)
	assert(ok, `{what}\n  but it failed with: {tostring(err)}`)
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

--[[
	Runs every check over a FRESH control per check (the client side is
	module state, so a check that inits must not see another's init) and
	asserts the set of failing labels is EXACTLY `expected`, and that the
	first expected failure's message carries `fragment`.
]]
local function failsExactly(defect: string, expected: { string }, fragment: string)
	local expectedSet: { [string]: boolean } = {}
	for _, label in expected do
		expectedSet[label] = true
	end
	local failed: { string } = {}
	local messages: { [string]: string } = {}
	for _, entry in CHECKS do
		local ok, err = pcall(entry.check, Stubs.with(defect))
		if not ok then
			table.insert(failed, entry.label)
			messages[entry.label] = tostring(err)
		end
	end
	local unexpected: { string } = {}
	for _, label in failed do
		if not expectedSet[label] then
			table.insert(unexpected, `{label} (failed, should pass): {messages[label]}`)
		end
	end
	for _, label in expected do
		if table.find(failed, label) == nil then
			table.insert(
				unexpected,
				`{label} (passed, should fail - the check is vacuous against it)`
			)
		end
	end
	assert(
		#unexpected == 0,
		`the "{defect}" control must fail exactly \{ {table.concat(expected, ", ")} \}; measured `
			.. `\{ {table.concat(failed, ", ")} \}:\n  {table.concat(unexpected, "\n  ")}`
	)
	names(
		messages[expected[1]],
		fragment,
		`the "{defect}" control's {expected[1]} failure must name what it did`
	)
end

return {
	--[[ The baseline ]]

	["the correct transport passes every SLICE-002 check, server and client"] = function()
		for _, entry in CHECKS do
			accepts(entry.check, Stubs.correct(), `the correct transport must pass {entry.label}`)
		end
	end,

	["every control is a single defect: each fails at least one check, and none fails the kind-set check except the two that edit a set"] = function()
		for _, defect in Stubs.DEFECTS do
			local failed = 0
			for _, entry in CHECKS do
				if not pcall(entry.check, Stubs.with(defect)) then
					failed += 1
				end
			end
			assert(failed > 0, `the "{defect}" control fails no check; it is not a control`)
			if defect ~= "privateKindsMissingOne" and defect ~= "publicKindsHaveExtra" then
				accepts(
					Contract.kindSetsAreExactlyTheSixAndTheFour,
					Stubs.with(defect),
					`the "{defect}" control must still export the exact kind sets`
				)
			end
		end
	end,

	--[[ AC-1 - the control the criterion names, and D-1's second mutation ]]

	["AC-1 control (D-1): a bind that connects the handler directly, with no guard, fails AC-1 shape - the malformed call returns nil and reaches the handler - and with it C-1, AC-5 and C-3, which all read the guard's result; the connection count and the routing checks pass"] = function()
		failsExactly(
			"bindBypassesGuard",
			{ "AC-1 shape", "C-1 decline", "AC-5", "C-3" },
			'expected a Rejection with reason "shape", got nil'
		)
		-- The half the criterion spells out: the malformed call REACHED the
		-- handler. Shown directly, because the first assertion in the check
		-- fires on the return value before it counts handler calls.
		local Stubs2 = Stubs.with("bindBypassesGuard")
		local harness = Stubs.ports({ p1 = { Name = "one" } })
		local reached = 0
		Stubs2.Transport.bind({
			{
				name = "Ping",
				args = {
					validate = function()
						return false, "shape: not even consulted"
					end,
				},
				legalPhases = { "Round" },
			},
		}, {
			isSeated = function()
				return true
			end,
			phase = function()
				return "Round"
			end,
			clock = {
				now = function()
					return 0
				end,
			},
		}, {
			Ping = function()
				reached += 1
			end,
		}, harness.ports)
		harness.events.Ping.serverConnections[1](harness.players.p1, { token = "four" })
		assert(
			reached == 1,
			`the unguarded bind let the malformed call reach the handler {reached} time(s)`
		)
	end,

	["AC-1 control: a bind that connects each remote twice fails every check that builds a world, on the connection count - the fixture's vacuity guard"] = function()
		failsExactly(
			"bindConnectsTwice",
			ALL_SERVER_CHECKS_AFTER_BIND,
			'"Ping" has 2 OnServerEvent connection(s); expected exactly 1'
		)
	end,

	["C-1 control: a bind that hands the handler two arguments fails AC-1 handler (call = nil) and C-1 decline alone"] = function()
		failsExactly(
			"dropsCallControl",
			{ "AC-1 handler", "C-1 decline" },
			"the handler received 2 argument(s) and call = nil"
		)
	end,

	["C-2 control: a connected function that discards the guard's result fails AC-1 shape, C-1 decline, AC-5 and C-3 - every rejection reads as nil"] = function()
		failsExactly(
			"connectedReturnsNil",
			{ "AC-1 shape", "C-1 decline", "AC-5", "C-3" },
			'expected a Rejection with reason "shape", got nil'
		)
	end,

	--[[ AC-2 / C-5 ]]

	["AC-2 control: a bind that skips a declared remote with no handler fails AC-2 unhandled alone, naming Orphaned_Declared"] = function()
		failsExactly(
			"bindAcceptsUnhandled",
			{ "AC-2 unhandled" },
			'expected a raise naming "Orphaned_Declared"'
		)
	end,

	["AC-2 control: a bind that ignores a handler for an undeclared remote fails AC-2 undeclared alone, naming Stray_Handler"] = function()
		failsExactly(
			"bindAcceptsUndeclared",
			{ "AC-2 undeclared" },
			'expected a raise naming "Stray_Handler"'
		)
	end,

	["C-5 control: a bind that fetches and connects the events before validating fails both AC-2 checks on the port count - 3 and 2 remoteEvent calls before the raise"] = function()
		failsExactly(
			"bindReadsPortsFirst",
			{ "AC-2 unhandled", "AC-2 undeclared" },
			"bind called ports.remoteEvent 3 time(s) before raising (C-5)"
		)
	end,

	["AC-2 needle: a bind that raises without naming the remote fails both AC-2 checks - any raise is not enough"] = function()
		failsExactly(
			"bindRaiseOmitsName",
			{ "AC-2 unhandled", "AC-2 undeclared" },
			'the raise does not name "Orphaned_Declared"'
		)
	end,

	--[[ C-3 / AC-5 ]]

	["C-3 control: a bind that passes the raw player object to the guard fails AC-5 (idOf called 0 times), C-3, and the three checks whose seated calls now read identity"] = function()
		failsExactly(
			"passesRawPlayer",
			{ "AC-1 shape", "AC-1 handler", "C-1 decline", "AC-5", "C-3" },
			"a caller sending table as a player id"
		)
	end,

	["C-3 control: a bind that consults idOf twice per call fails AC-5 and C-3 alone, on the count"] = function()
		failsExactly(
			"idOfCalledTwice",
			{ "AC-5", "C-3" },
			"ports.idOf was called 2 time(s) for one call; expected once"
		)
	end,

	--[[ C-4 ]]

	["C-4 control: a bind that fetches the kind events on first send fails AC-1 once and C-4 - no remoteEvent call for SeatView at bind"] = function()
		failsExactly(
			"kindEventsReadLazily",
			{ "AC-1 once", "C-4" },
			'bind never asked ports.remoteEvent for the kind "SeatView"'
		)
	end,

	--[[ AC-3 - the control the criterion names, and D-1's first mutation ]]

	["AC-3 control (D-1): a sendTo implemented with FireAllClients fails AC-3 alone, naming the broadcast"] = function()
		failsExactly(
			"sendToFiresAll",
			{ "AC-3" },
			"called FireAllClients (1 call(s) across every event) for a per-player payload (AC-3)"
		)
	end,

	["AC-3 control: a sendTo that puts every private kind on one event fails AC-3 alone - LensView's own event sees 0 FireClient calls"] = function()
		failsExactly(
			"sendToOnSharedEvent",
			{ "AC-3" },
			'sendTo("p2", "LensView") called FireClient on "LensView" 0 time(s)'
		)
	end,

	["AC-3 control: a sendTo that fires twice fails AC-3 alone, on the count"] = function()
		failsExactly(
			"sendToFiresTwice",
			{ "AC-3" },
			'sendTo("p1", "SeatView") called FireClient on "SeatView" 2 time(s)'
		)
	end,

	["Contract control: a sendTo that raises when playerFor answers nil fails the no-op check and C-4, which sends to a player who has left"] = function()
		failsExactly("sendToRaisesWithoutPlayer", { "C-4", "AC-3 no-op" }, 'no player for "nobody"')
	end,

	--[[ AC-4 / C-6 ]]

	["AC-4 control: a broadcast that accepts a private kind fails AC-4 private alone, naming SeatView"] = function()
		failsExactly(
			"broadcastAcceptsPrivate",
			{ "AC-4 private" },
			'broadcast("SeatView"): expected a raise naming "SeatView"'
		)
	end,

	["AC-4 control: a broadcast that fires twice fails AC-4 public alone, on the count"] = function()
		failsExactly(
			"broadcastFiresTwice",
			{ "AC-4 public" },
			'broadcast("RoundView") called FireAllClients on "RoundView" 2 time(s)'
		)
	end,

	["AC-4 control: a broadcast that puts every public kind on one event fails AC-4 public alone"] = function()
		failsExactly(
			"broadcastOnSharedEvent",
			{ "AC-4 public" },
			'broadcast("FacilityView") called FireAllClients on "FacilityView" 0 time(s)'
		)
	end,

	["AC-4 sets control: a PRIVATE_KINDS missing PingRefused fails AC-4 sets, and every check that sends PingRefused - C-4, AC-3, AC-3 no-op, AC-6 on"] = function()
		failsExactly(
			"privateKindsMissingOne",
			{ "C-4", "AC-3", "AC-3 no-op", "AC-4 sets", "AC-6 on" },
			'"PingRefused" is not a per-player payload kind'
		)
	end,

	["AC-4 sets control: a PUBLIC_KINDS that also holds LensView fails AC-4 sets and AC-4 private - broadcast(LensView) no longer raises"] = function()
		failsExactly(
			"publicKindsHaveExtra",
			{ "AC-4 private", "AC-4 sets" },
			'broadcast("LensView"): expected a raise naming "LensView"'
		)
	end,

	["C-6 control: a sendTo that accepts a public kind fails C-6 sendTo alone, naming RoundView"] = function()
		failsExactly(
			"sendToAcceptsPublicKind",
			{ "C-6 sendTo" },
			'sendTo("p1", "RoundView") with a public kind: expected a raise naming "RoundView"'
		)
	end,

	["C-6 control: a transport that accepts a kind in neither set fails both C-6 checks, naming Nonsense"] = function()
		failsExactly(
			"unknownKindAccepted",
			{ "C-6 sendTo", "C-6 broadcast" },
			'expected a raise naming "Nonsense"'
		)
	end,

	--[[ AC-6 / C-7 ]]

	["C-7 control: a ClientTransport that indexes nil ports instead of raising by name fails C-7 init alone - any raise is not enough"] = function()
		failsExactly("clientNoInitCheck", { "C-7 init" }, 'the raise does not name "init"')
	end,

	["C-7 control: an on that connects any name fails C-7 unknown alone"] = function()
		failsExactly(
			"clientOnAcceptsUnknownKind",
			{ "C-7 unknown" },
			'ClientTransport.on("Nonsense"): expected a raise naming "Nonsense"'
		)
	end,

	["AC-6 control: a send that wraps args in a table fails AC-6 send alone - FireServer's one argument is not the args table"] = function()
		failsExactly(
			"clientSendWrapsArgs",
			{ "AC-6 send" },
			"expected exactly one, the args table itself"
		)
	end,

	["C-7 control: an init that keeps the first ports fails C-7 replace alone"] = function()
		failsExactly(
			"clientInitKeepsFirstPorts",
			{ "C-7 replace" },
			"the first ports were still used after init was called again"
		)
	end,

	["AC-6 control: an on that connects every kind to one event fails AC-6 on and C-7 replace"] = function()
		failsExactly(
			"clientOnSharedEvent",
			{ "AC-6 on", "C-7 replace" },
			'on("SeatView") never asked ports.remoteEvent for "SeatView"'
		)
	end,
}
