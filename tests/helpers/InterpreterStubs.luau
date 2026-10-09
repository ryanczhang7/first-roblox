--!strict
--[[
	The wrong interpreters SLICE-004's controls are aimed at, and the one
	baseline each of them is a single defect away from.

	AC-1 NAMES ITS CONTROL: "an interpreter that turns a `SendTo` into a
	broadcast must fail, because `Transport` raises for a private kind" -
	`sendToBroadcasts`, which is also D-1's mutation. The rest are the
	one-defect interpreters the remaining checks in `InterpreterContract.luau`
	would otherwise have no control for.

	IT IS A FACTORY OVER A TABLE OF DEFECTS, as `TransportStubs.luau` and
	`NetStubs.luau` are: `defects` is empty for the baseline and has exactly
	ONE field set for every control, so a control that fires is attributable
	to that one field.

	WHAT THIS IS NOT: `src/server/session/Interpreter.luau` or a sketch of
	it. GREEN writes the real module from the story's `## Contract`, against
	the failing tests in `tests/server/interpreter_test.luau`; the types here
	are all `any` and the failure strings are whatever fell out. Nothing here
	is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/server/interpreter_controls_test.luau` records
	what each one actually did.
]]

local InterpreterStubs = {}

--[[
	One field per control, each a single edit to the baseline below.

	  * `sendToBroadcasts`        - SendTo goes through `broadcast` (AC-1's
	                                control; D-1)
	  * `sendToDotCall`           - `ports.transport.sendTo(...)` with a dot,
	                                so every argument shifts one place
	  * `sendsTwice`              - two `sendTo` calls per SendTo
	  * `dropsEmit`               - Emit makes no call
	  * `emitsTheEventNotAList`   - `ports.emit(e.event)`
	  * `emitsAllAtOnce`          - events are collected and emitted in one
	                                call at the end
	  * `emitSharesOneList`       - one list table is reused for every emit
	  * `copiesPayload`           - the payload is `table.clone`d before the
	                                port sees it
	  * `prevalidates`            - a pass over the whole list raises before
	                                anything is performed
	  * `swallowsUnknown`         - an unknown kind is silently skipped
	  * `raiseOmitsKind`          - the raise says "unknown effect" only
	  * `continuesAfterRaise`     - the rest of the list is performed, then
	                                the raise
	  * `acceptsAssignSeats`      - AssignSeats is a no-op
	  * `reversesOrder`           - the list is walked from the end
	  * `placeDropsPosition`      - `ports.place(e.playerId)` only
	  * `computeTraceDropsRoundId`- `ports.computeTrace()` with no id
]]
InterpreterStubs.DEFECTS = {
	"sendToBroadcasts",
	"sendToDotCall",
	"sendsTwice",
	"dropsEmit",
	"emitsTheEventNotAList",
	"emitsAllAtOnce",
	"emitSharesOneList",
	"copiesPayload",
	"prevalidates",
	"swallowsUnknown",
	"raiseOmitsKind",
	"continuesAfterRaise",
	"acceptsAssignSeats",
	"reversesOrder",
	"placeDropsPosition",
	"computeTraceDropsRoundId",
}

local KNOWN = {
	SendTo = true,
	Broadcast = true,
	Emit = true,
	PromptRematch = true,
	ComputeTrace = true,
	Placed = true,
}

function InterpreterStubs.build(
	defects: { [string]: boolean }
): (effects: { any }, ports: any) -> ()
	local sharedList: { any } = {}

	local function raiseUnknown(kind: any)
		if defects.raiseOmitsKind then
			error("Interpreter.perform: unknown effect", 0)
		end
		error(`Interpreter.perform: unknown effect kind "{tostring(kind)}"`, 0)
	end

	local function one(e: any, ports: any, pending: { any })
		local kind = e.kind
		if kind == "AssignSeats" and defects.acceptsAssignSeats then
			return
		end
		if kind == "SendTo" then
			local payload = if defects.copiesPayload then table.clone(e.payload) else e.payload
			if defects.sendToBroadcasts then
				ports.transport:broadcast(e.payloadKind, payload)
			elseif defects.sendToDotCall then
				ports.transport.sendTo(e.playerId, e.payloadKind, payload)
			else
				ports.transport:sendTo(e.playerId, e.payloadKind, payload)
				if defects.sendsTwice then
					ports.transport:sendTo(e.playerId, e.payloadKind, payload)
				end
			end
		elseif kind == "Broadcast" then
			local payload = if defects.copiesPayload then table.clone(e.payload) else e.payload
			ports.transport:broadcast(e.payloadKind, payload)
		elseif kind == "Emit" then
			if defects.dropsEmit then
				return
			elseif defects.emitsTheEventNotAList then
				ports.emit(e.event)
			elseif defects.emitsAllAtOnce then
				table.insert(pending, e.event)
			elseif defects.emitSharesOneList then
				sharedList[1] = e.event
				ports.emit(sharedList)
			else
				ports.emit({ e.event })
			end
		elseif kind == "PromptRematch" then
			ports.promptRematch()
		elseif kind == "ComputeTrace" then
			if defects.computeTraceDropsRoundId then
				ports.computeTrace()
			else
				ports.computeTrace(e.roundId)
			end
		elseif kind == "Placed" then
			if defects.placeDropsPosition then
				ports.place(e.playerId)
			else
				ports.place(e.playerId, e.position)
			end
		elseif defects.swallowsUnknown then
			return
		else
			raiseUnknown(kind)
		end
	end

	return function(effects: { any }, ports: any)
		if defects.prevalidates then
			for _, e in effects do
				if not KNOWN[e.kind] then
					raiseUnknown(e.kind)
				end
			end
		end
		local pending: { any } = {}
		local deferred: any = nil
		local order: { any } = {}
		for i, e in effects do
			if defects.reversesOrder then
				table.insert(order, 1, e)
			else
				order[i] = e
			end
		end
		for _, e in order do
			if defects.continuesAfterRaise then
				local ok, err = pcall(one, e, ports, pending)
				if not ok and deferred == nil then
					deferred = err
				end
			else
				one(e, ports, pending)
			end
		end
		if defects.emitsAllAtOnce and #pending > 0 then
			ports.emit(pending)
		end
		if deferred ~= nil then
			error(deferred, 0)
		end
	end
end

return InterpreterStubs
