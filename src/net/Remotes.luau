--!strict
--[[
	NET-001: the declaration registry. Every remote of this game is declared
	here with the schema its arguments must satisfy, per B4: "Every remote gets
	a server-side validation wrapper in `src/net/`."

	A DUPLICATE NAME FAILS rather than replacing the first declaration (AC-8).
	A silently replaced declaration is a validated remote quietly becoming an
	unvalidated one - the second declaration wins, nothing says so, and the
	schema the first caller relies on is gone.

	`all()` RETURNS A COPY for the same reason read from the other side: a live
	registry handed out is a registry any caller can edit.

	`legalPhases` IS ENFORCED FROM NET-002: it may not be empty (AC-5, below),
	and `Wrapper.guard` rejects a call made in a phase it does not name.
	`rateLimit` is still declared and unread; NET-003 is the story that
	consumes it. Both were declared in NET-001 so that those stories change
	one file each and no call site.

	`Phase` IS RE-DECLARED, not imported. `docs/wiki/architecture.md` section 1
	forbids `net` -> `server`, and `.luaurc` declares exactly one alias
	(`shared`), so the require to `PhaseMachine` cannot even be spelled. Luau
	string-literal unions are structural, so a `Phase` from the phase machine
	is accepted where this one is wanted and the reverse holds too. The cost is
	two copies that can drift, and the two never meet in an expression, so the
	analyser has nothing to reject: NET-002 needs them to agree SEMANTICALLY
	while giving the compiler nothing to check, which is why
	`tests/net/phase_union_guard_test.luau` compares them textually (AC-7).
]]

local Schema = require("./Schema")

local Remotes = {}

export type Phase = "Lobby" | "Assignment" | "Round" | "Resolution" | "Post"

export type RateLimit = { minIntervalSeconds: number }

export type RemoteDefinition = {
	name: string,
	args: Schema.Schema,
	legalPhases: { Phase },
	rateLimit: RateLimit?,
}

export type RemoteSpec = {
	args: Schema.Schema,
	legalPhases: { Phase },
	rateLimit: RateLimit?,
}

-- Module-level, so a remote is declared once per server and every guard reads
-- the same declaration. Declaration order is kept, because `all()` is a list.
local registry: { RemoteDefinition } = {}
local byName: { [string]: RemoteDefinition } = {}

--[[
	Declares a remote. Raises on a duplicate name, naming the name: the caller
	of a duplicate has two schemas in mind for one wire, and picking either
	silently is how the weaker one ships.
]]
function Remotes.define(name: string, spec: RemoteSpec): RemoteDefinition
	if byName[name] ~= nil then
		error(
			`Remotes.define: the remote "{name}" is already declared; a second declaration would `
				.. `replace a validated remote with an unvalidated one`,
			2
		)
	end

	-- NET-002 AC-5. An empty `legalPhases` means "legal in no phase", which is
	-- a remote every call to which is rejected - a silently dead wire that
	-- nobody meant to declare. Refused HERE, BEFORE the name is registered, so
	-- a refused declaration leaves the name free rather than poisoned.
	if #spec.legalPhases == 0 then
		error(
			`Remotes.define: the remote "{name}" declares an empty legalPhases; a remote legal in no `
				.. `phase is silently dead - name at least one phase it may be called in`,
			2
		)
	end

	local definition: RemoteDefinition = {
		name = name,
		args = spec.args,
		legalPhases = spec.legalPhases,
		rateLimit = spec.rateLimit,
	}
	byName[name] = definition
	table.insert(registry, definition)
	return definition
end

-- Every declaration, in declaration order, as a COPY: what a caller does to
-- the list it is given cannot reach the registry.
function Remotes.all(): { RemoteDefinition }
	return table.clone(registry)
end

return Remotes
