--!strict
--[[
	THE NEGATIVE CONTROL FOR NET-001 AC-7. NOT A MODULE ANYTHING MAY USE.

	It exists to break the raw-remote guard on purpose. The three member
	accesses below - `OnServerEvent`, `OnServerInvoke`, `.OnClientEvent` - are
	real code, at the real path: `src/server/`, deliberately, because
	`.claude/harness/rules.md` says a probe scanned from a temp directory is
	scanned under the wrong path rules, and then the guard silently stops
	testing anything while still passing. B4's rule is "no raw
	`OnServerEvent:Connect` in `src/server/`", so this is the directory the
	rule is about.

	`.claude/harness/paths.conf` classifies `**/__probe_*.*` as `test`, which
	does two jobs with one rule: RED may write this file, and every
	tree-scanning guard skips it - because `scripts/classify.sh --list source
	src` does not return it, not because any guard checks its name.

	Owned by `tests/net/raw_remote_guard_test.luau`, which is the only thing
	that may read it. That test scans `source + test` files together and
	asserts this file is reported BY NAME against `OnServerEvent`; delete this
	probe and that test fails, which is the point. See `rules.md`: "no
	probe-named file sits under `src/` without a guard that owns it".

	Nothing here runs. The functions take the remote as a parameter and are
	never called, so the module needs no `Instance.new`, no `game` and no
	Roblox runtime - ROUND-003's Roblox-runtime guard must stay clean over it.
]]

local RawRemoteProbe = {}

-- The offence B4 names: a raw connection in src/server/.
function RawRemoteProbe.connect(remote: RemoteEvent)
	remote.OnServerEvent:Connect(function(_player: Player) end)
end

-- The second needle: a raw invoke handler, assigned rather than connected.
function RawRemoteProbe.bind(fn: RemoteFunction)
	fn.OnServerInvoke = function(_player: Player)
		return nil
	end
end

-- The third needle: the client-side signal read from server code.
function RawRemoteProbe.clientSignal(remote: RemoteEvent): RBXScriptSignal
	return remote.OnClientEvent
end

return RawRemoteProbe
