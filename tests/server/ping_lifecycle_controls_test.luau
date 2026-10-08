--!strict
--[[
	The negative controls for CHAN-006 AC-1 .. AC-6, C-2 and C-3, and the proof
	that each check in `tests/helpers/PingLifecycleContract.luau` means what it
	says.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/channel/Pings.luau` has none of `new`, `accept`, `tick`,
	`onCommitted` or `shown`, every test in
	`tests/server/ping_lifecycle_test.luau` stops at the contract's `need()`,
	and so not one of that file's checks has been observed to accept or
	refuse anything. `PingLifecycleStubs.luau` needs only `MechanicsTuning`
	and CHAN-005's merged `Pings`, so what is asserted here is MEASURED in
	RED rather than claimed for GREEN. The story's handoff carries the table.

	THE REFERENCE is the Contract written out. Every check must ACCEPT it, or
	the check is wrong and the fix belongs HERE, in RED. Each control is the
	reference with EXACTLY ONE thing changed, so the set of checks that fire is
	attributable to that one change, and each control pins that set EXACTLY -
	a check that fires on a control it should not is as much a finding as one
	that stays quiet.

	THE DEFERRED VERIFICATIONS' SHAPES ARE HERE AS IMPLEMENTATIONS. D-1 is
	`appendsUnderDistinctKey`, D-2 is `strictExpiry`, D-3 is
	`commitIgnoresKind`, D-4 is `shownLeaksAt`. What is measured here is that
	the checks WOULD see them; D-1..D-4 THEMSELVES stay with GATES.

	THE SETTLED NUMBER is asserted first: `ping_display_seconds` is 15 in
	`MechanicsTuning`, the substituted tuning says 4, and the boundary sums
	are exact in binary. A check built on a duration that moved would say
	nothing about the module.

	WHAT THIS IS NOT: `src/server/channel/Pings.luau`, or a sketch of one.
]]

local Contract = require("../helpers/PingLifecycleContract")
local Deep = require("../helpers/Deep")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Stubs = require("../helpers/PingLifecycleStubs")

local function failingNames(P: any): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Contract.failures(P) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(defect: Stubs.Defect, expected: { string })
	local names, messages = failingNames(Stubs.with(defect))
	local want = table.clone(expected)
	table.sort(want)
	print(`        [measured] {defect} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`{defect} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{table.concat(
				shown,
				"\n"
			)}`,
			0
		)
	end
	local byName: { [string]: Contract.Check } = {}
	for _, check in Contract.CHECKS do
		byName[check.name] = check
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac, 1, true) ~= nil,
			`{defect}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end
	return messages
end

local NEW = "newReturnsAnEmptyStateFreshEachCall"
local REPLACES = "aSecondPingBySameSenderReplacesTheFirstAtOnce"
local EXPIRES = "aPingIsActiveUntilExactlyPingDisplaySecondsAfterItWasMade"
local COMMIT = "aCommitClearsSettingAndMachinePingsOnThatMachineOnly"
local TWO_SENDERS = "twoSendersPingingOneTargetBothStayActiveWithTheirOwnSender"
local LOG = "theLogHoldsOneEntryPerAcceptedPingInOrderAndNothingIsEverRemoved"
local DOORWAY_LIT = "aDoorwayPingAlwaysLogsRoomLitTrue"
local REFUSED = "aRefusedRequestIsNeverLoggedAndOnlyAcceptedPingsReachTheLog"
local SHOWN = "shownIsExactlySenderKindTargetAndSettingSortedBySender"
local PURE = "acceptTickAndOnCommittedReturnANewStateAndNeverMutateTheirInput"

local function contains(haystack: string, needle: string, what: string)
	assert(
		string.find(haystack, needle, 1, true) ~= nil,
		`{what}: expected the message to contain "{needle}", got:\n{haystack}`
	)
end

return {
	--[[ ================================================================
	     The settled number, read out.
	     ================================================================ ]]

	["settled: ping_display_seconds is 15 in MechanicsTuning, the substituted tuning reads 4, and the boundaries 10 + 15 = 25 and 10 + 4 = 14 are exact with 1e-6 strictly inside them"] = function()
		local d = MechanicsTuning.channel.ping_display_seconds
		assert(d == 15, `ping_display_seconds is {d}; the story's boundary is 25 = 10 + 15`)
		local sub = Contract.substitutedTuning()
		assert(
			sub.channel.ping_display_seconds == Contract.SUBSTITUTED_DISPLAY_SECONDS
				and sub.channel.ping_display_seconds == 4,
			`the substituted tuning reads {sub.channel.ping_display_seconds}, expected 4`
		)
		assert(
			sub.channel.ping_range_studs == MechanicsTuning.channel.ping_range_studs,
			"substitution touched range"
		)
		assert(Contract.AT + d == 25 and Contract.AT + 4 == 14, "the boundary sums are not exact")
		assert(Contract.EPSILON == 1e-6, "epsilon is not 1e-6")
		assert(
			Contract.AT + d - Contract.EPSILON < 25 and Contract.AT + 4 - Contract.EPSILON < 14,
			"epsilon vanished"
		)
		print(
			`        [measured] ping_display_seconds = {d}, substituted = {sub.channel.ping_display_seconds}`
		)
	end,

	--[[ ================================================================
	     The reference. Everything below is this implementation with one edit.
	     ================================================================ ]]

	["baseline: the reference implementation - the Contract written out - passes every check in PingLifecycleContract"] = function()
		local names, messages = failingNames(Stubs.reference)
		if #names > 0 then
			local shown: { string } = {}
			for _, name in names do
				table.insert(shown, `{name}: {messages[name]}`)
			end
			error(
				`the reference fails {#names} check(s), so the check or the fixture is wrong:\n{table.concat(
					shown,
					"\n"
				)}`,
				0
			)
		end
		print(`        [measured] reference fails 0 of {#Contract.CHECKS} checks`)
	end,

	["baseline: a module with none of the five functions fails every check at need(), naming the missing export - the shape of RED against the real module"] = function()
		local names, messages = failingNames({ request = Stubs.reference.request })
		assert(
			#names == #Contract.CHECKS,
			`{#names} of {#Contract.CHECKS} checks fired on an empty module`
		)
		for _, name in names do
			contains(messages[name], "is nil, expected a function", name)
		end
	end,

	--[[ ================================================================
	     AC-1's named control (D-1's shape), and the key.
	     ================================================================ ]]

	["control (AC-1, required; D-1's shape): an implementation that appends a second ping by the same sender beside the first fails the replacement check holding 2 - and every other check that reads the active set by senderId (expiry, commit, two senders); it is pure, so purity passes"] = function()
		local messages =
			expectFires("appendsUnderDistinctKey", { REPLACES, EXPIRES, COMMIT, TWO_SENDERS })
		contains(
			messages[REPLACES],
			"the active set holds 2 ping(s), expected exactly 1",
			"holding 2"
		)
	end,

	["control: an active set keyed by target rather than sender holds kim's two pings on different targets and merges kim's and lee's on one target - the replacement, expiry, commit and two-senders checks fire, nothing else"] = function()
		local messages = expectFires("keyedByTarget", { REPLACES, EXPIRES, COMMIT, TWO_SENDERS })
		contains(messages[TWO_SENDERS], "expected exactly 2", "two senders merged")
	end,

	--[[ ================================================================
	     AC-2 (D-2's shape) and the tuning.
	     ================================================================ ]]

	["control (D-2's shape): an expiry that keeps a ping at exactly at + ping_display_seconds fails exactly the expiry check, on the boundary case"] = function()
		local messages = expectFires("strictExpiry", { EXPIRES })
		contains(messages[EXPIRES], "gone at exactly 10 + 15 = 25", "the module's boundary")
		contains(messages[EXPIRES], "gone at exactly 10 + 4 = 14", "the substituted boundary")
	end,

	["control: a duration hard-coded from MechanicsTuning instead of the tuning handed to tick fails exactly the expiry check, on the substituted tuning only"] = function()
		local messages = expectFires("hardCodedDuration", { EXPIRES })
		contains(
			messages[EXPIRES],
			"a substituted tuning (d = 4), gone at exactly 10 + 4 = 14",
			"the substituted case"
		)
		assert(
			string.find(messages[EXPIRES], "the module's tuning (d = 15)", 1, true) == nil,
			`the module's own tuning should not fire on a hard-coded 15:\n{messages[EXPIRES]}`
		)
	end,

	["control: a tick that drops expired pings from the log fails the expiry check (tick changed the log) and the log check"] = function()
		local messages = expectFires("tickTrimsTheLog", { EXPIRES, LOG })
		contains(messages[EXPIRES], "changed the log", "tick touched the log")
		contains(messages[LOG], "after a tick at 40 expired everything", "trimmed at the tick")
	end,

	--[[ ================================================================
	     AC-3 (D-3's shape).
	     ================================================================ ]]

	["control (D-3's shape): a commit without the kind check clears the doorway numbered like the machine - exactly the commit check fires, on the doorway case"] = function()
		local messages = expectFires("commitIgnoresKind", { COMMIT })
		contains(
			messages[COMMIT],
			"ann's doorway 1 (the same number, a doorway)",
			"the doorway case"
		)
		contains(messages[COMMIT], "value.ann: expected", "ann missing")
	end,

	["control: a commit that clears only setting pings leaves the machine ping on the committed machine - exactly the commit check fires"] = function()
		local messages = expectFires("commitClearsOnlySettings", { COMMIT })
		contains(messages[COMMIT], "value.lee: unexpected", "lee survived")
	end,

	["control: a commit that drops the cleared pings' log entries fails the commit check (log changed) and the log check"] = function()
		local messages = expectFires("commitTrimsTheLog", { COMMIT, LOG })
		contains(messages[LOG], "after machine 2 commits", "trimmed at the commit")
	end,

	--[[ ================================================================
	     AC-5: the log.
	     ================================================================ ]]

	["control: a replacement that drops the sender's earlier log entry fails the log check at the replacement step and the refused-request check (kim is accepted twice in that sequence)"] = function()
		local messages = expectFires("replacementTrimsTheLog", { LOG, REFUSED })
		contains(
			messages[LOG],
			"after kim REPLACES with a doorway ping",
			"trimmed at the replacement"
		)
		contains(
			messages[REFUSED],
			"the log holds 2 entries, expected exactly 3",
			"kim's first entry gone"
		)
	end,

	["control: two log entries per accept fail the log check and the refused-request check, on the count"] = function()
		local messages = expectFires("logsEveryAcceptTwice", { LOG, REFUSED })
		contains(messages[LOG], "the log holds 2 entries, expected exactly 1", "the count")
		contains(
			messages[REFUSED],
			"the log holds 6 entries, expected exactly 3",
			"the mixed sequence"
		)
	end,

	["control: a log entry without roomLit fails the log check, the doorway-roomLit check and the refused-request check"] = function()
		local messages = expectFires("logOmitsRoomLit", { LOG, DOORWAY_LIT, REFUSED })
		contains(messages[DOORWAY_LIT], "logged roomLit = nil", "missing roomLit")
	end,

	["control: a doorway ping that logs the roomLit it was given fails the doorway-roomLit check and the log check (the sequence has a doorway ping with roomLit = false)"] = function()
		local messages = expectFires("doorwayLogsRoomLitAsGiven", { LOG, DOORWAY_LIT })
		contains(
			messages[DOORWAY_LIT],
			"a doorway ping accepted with roomLit = false logged roomLit = false, expected true",
			"the doorway case"
		)
	end,

	--[[ ================================================================
	     AC-6 (D-4's shape).
	     ================================================================ ]]

	["control (D-4's shape): a public payload carrying `at` fails exactly the shown check, naming the leak"] = function()
		local messages = expectFires("shownLeaksAt", { SHOWN })
		contains(messages[SHOWN], "value.1.at: unexpected 11", "the leaked at")
	end,

	["control: a public payload that IS the active entries fails exactly the shown check"] = function()
		local messages = expectFires("shownReturnsActiveEntries", { SHOWN })
		contains(messages[SHOWN], ".at: unexpected", "the leaked at")
	end,

	["control: a public payload sorted descending fails exactly the shown check"] = function()
		local messages = expectFires("shownUnsorted", { SHOWN })
		contains(messages[SHOWN], 'value.1.senderId: expected "ann", got "zoe"', "the order")
	end,

	["control: a public payload without `setting` fails exactly the shown check"] = function()
		local messages = expectFires("shownDropsSetting", { SHOWN })
		contains(messages[SHOWN], "value.3.setting: expected 1, got nil", "the dropped setting")
	end,

	--[[ ================================================================
	     C-2: purity.
	     ================================================================ ]]

	["control: an accept that writes into the state it was given and returns it fails exactly the purity check - every other check reads only the state it was last handed back"] = function()
		local messages = expectFires("acceptMutatesInPlace", { PURE })
		contains(
			messages[PURE],
			"accept (a new sender) returned the state it was given",
			"same table"
		)
		contains(messages[PURE], "accept (a new sender) mutated the state it was given", "mutated")
	end,

	["control: a tick that removes from the state it was given fails exactly the purity check - the expiry check's later ticks see a state already emptied at the boundary and expect emptiness anyway"] = function()
		local messages = expectFires("tickMutatesInput", { PURE })
		contains(
			messages[PURE],
			"tick (expiring everything) mutated the state it was given",
			"mutated"
		)
	end,

	["control: an onCommitted that removes from the state it was given fails the purity check and the commit check (the state committed at 1 was reused at 2)"] = function()
		local messages = expectFires("commitMutatesInput", { PURE, COMMIT })
		contains(
			messages[PURE],
			"onCommitted (clearing two) mutated the state it was given",
			"mutated"
		)
	end,

	--[[ ================================================================
	     C-3: new().
	     ================================================================ ]]

	["control: a new() that returns one shared state fails exactly the new check, on freshness"] = function()
		local messages = expectFires("newIsASingleton", { NEW })
		contains(messages[NEW], "returned the same table twice", "the singleton")
	end,

	["control: a new() with a third key fails exactly the new check, on the extra key"] = function()
		local messages = expectFires("newCarriesACounter", { NEW })
		contains(messages[NEW], "value.count: unexpected 0", "the extra key")
	end,
}
