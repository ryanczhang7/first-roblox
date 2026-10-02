--!strict
--[[
	PROC-005: the pure handler between a guarded `Turn` call and the Procedure.
	`Wrapper.guard` has already checked identity, shape, range, phase and rate
	by the time `handle` runs; what is left is to judge the claim and to say
	privately to the turner what came of it. Session wiring and the transport
	are SLICE-005's.

	`handle` IS A PASS-THROUGH. It returns exactly what `Procedure.turn`
	returns for the caller's id, the requested machine and setting, and the
	session's ACCEPTED positions (`architecture.md` §9.8). It reads only
	`args.machine` and `args.setting`: a position, a player or anything else a
	payload carries is never read, so a client cannot argue its way into reach
	or into another seat's key.

	`reply` IS BUILT FIELD BY FIELD (D8), never by copying a record. A
	`TurnResult` is copied today from nothing but `kind`, `machineId` and
	`reason`, but a copy would carry whatever a future result grows - a
	machine record's `requiredSetting` is the leak this rule exists to stop.
	`committed` and `armed` reply `{ machineId, kind }`; `rejected` and
	`refused` reply `{ machineId, kind, reason }`, the reason unchanged.
	`machineId` is optional because the `refused` arm's is; it is copied as it
	is and never invented.
]]

local Procedure = require("./Procedure")
local Ring = require("../seats/Ring")

local TurnRequests = {}

export type TurnReply = {
	machineId: number?,
	kind: "committed" | "armed" | "rejected" | "refused",
	reason: string?,
}

function TurnRequests.handle(
	procedure: Procedure.ProcedureState,
	assignment: Ring.Assignment,
	playerId: string,
	args: { machine: number, setting: number },
	now: number,
	positions: { [string]: Procedure.Vec }
): (Procedure.ProcedureState, Procedure.TurnResult)
	return Procedure.turn(
		procedure,
		assignment,
		playerId,
		args.machine,
		args.setting,
		now,
		positions
	)
end

function TurnRequests.reply(result: Procedure.TurnResult): TurnReply
	if result.kind == "committed" or result.kind == "armed" then
		return { machineId = result.machineId, kind = result.kind }
	end
	return { machineId = result.machineId, kind = result.kind, reason = result.reason }
end

return TurnRequests
