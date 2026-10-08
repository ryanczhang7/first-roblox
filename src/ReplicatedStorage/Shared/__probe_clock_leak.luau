--!strict
--[[
	THE NEGATIVE CONTROL FOR ROUND-001 AC-5. NOT A MODULE ANYTHING MAY USE.

	It exists to break the source guard on purpose. `os.clock()` below is a real
	call, in real code, at the real path - `src/shared/`, deliberately, because
	`.claude/harness/rules.md` says a probe scanned from a temp directory is
	scanned under the wrong path rules, and then the guard silently stops testing
	anything while still passing.

	`.claude/harness/paths.conf` classifies `**/__probe_*.*` as `test`, which does
	two jobs with one rule: RED may write this file, and every tree-scanning guard
	skips it - because `scripts/classify.sh --list source src` does not return it,
	not because any guard checks its name.

	Owned by `tests/shared/source_guard_test.luau`, which is the only thing that
	may read it. That test scans `source + test` files together and asserts this
	file is reported by name; delete this probe and that test fails, which is the
	point. See `rules.md`: "no probe-named file sits under `src/` without a guard
	that owns it".
]]

local ClockLeakProbe = {}

-- The offence. A module that is handed a Clock has no reason to ask the process
-- what time it is; this one asks, so that the guard has something to find.
function ClockLeakProbe.leak(): number
	return os.clock()
end

return ClockLeakProbe
