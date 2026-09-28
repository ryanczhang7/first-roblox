--!strict
--[[
	The one way a contract helper raises. HARNESS-011.

	`Contract.fail(message)` is `error(message, 0)`, and every failure in the
	helpers AC-4 names goes through it. Two reasons, both measured under Lune
	0.10.5 (`docs/wiki/stack.md`):

	  1. `assert(false, message)` keeps the first 511 characters of `message`
	     and drops the rest. `error` does not truncate at any level: a
	     900-character message arrives as 900 characters at level 0 and as 1075
	     (with a position prefix) at levels 1 and 2. A check that reports its
	     first eight violations goes past 511, and what it said after that was
	     gone before anyone read it.
	  2. Luau evaluates `assert`'s message argument EAGERLY, so a check written
	     `assert(ok, <message>)` builds its message on every PASSING run. So
	     does a private `check(ok, <message>)` wrapper - it escapes the
	     truncation and keeps the eager build. The call shape is therefore

	         if #violations > 0 then
	             Contract.fail(`AC-N: ...{Contract.firstFew(violations, 8)}`)
	         end

	     and a message is built only on the path that raises it.

	WHY LEVEL 0. From inside a contract check, level 2 names the controls
	test's `pcall(check, ring)` line, which says less than the message's own
	`AC-N:` header; level 0 also drops the ~109-character path prefix, which is
	dead weight in a message that exists to be grepped.

	CAVEAT for anyone writing an ANCHORED match over these messages: level 0
	means there is no position prefix. Every needle offset is 109 characters
	earlier than it was under `assert` or `error(_, 2)`, and a pattern anchored
	with `^` now anchors on the message's first character. A plain
	`string.find(message, needle, 1, true)` is unaffected.
]]

local Contract = {}

local builds = 0

-- Raise `message`, whole, with no position prefix. Never returns.
function Contract.fail(message: string): never
	error(message, 0)
end

--[[
	The first `count` entries of `list`, one per line, with the remainder
	counted. The message-builder the accumulating helpers share, and AC-2's
	instrument: every call is counted, so a test can show that a passing check
	built nothing and a failing one built its message.
]]
function Contract.firstFew(list: { string }, count: number): string
	builds += 1
	local shown: { string } = {}
	for i = 1, math.min(count, #list) do
		shown[i] = list[i]
	end
	local more = #list - #shown
	return table.concat(shown, "\n") .. (if more > 0 then `\n  ... and {more} more` else "")
end

-- How many messages `firstFew` has built since the last `resetBuilds`.
function Contract.builds(): number
	return builds
end

function Contract.resetBuilds()
	builds = 0
end

return Contract
