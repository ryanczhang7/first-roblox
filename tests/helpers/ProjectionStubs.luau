--!strict
--[[
	The wrong projections SEAT-002's controls are aimed at, and the one baseline
	each of them is a single defect away from.

	TWO CRITERIA NAME THEIR CONTROL IN THE CRITERION. AC-2: "a projection
	implemented as copy the assignment, remove sigma passes a test that checks
	for a sigma key and must fail this". AC-3: "adding a new private field to
	Assignment and not to the allowlist must leave the projection unchanged" -
	which the same copy fails, because a copy carries whatever is added. The
	rest are the mutations the story's `## Notes` asks the orchestrator to run
	at acceptance (a lens read from the supplier, `{}` for a stranger) and the
	one-defect projections the remaining criteria would otherwise have no
	control for.

	It is a FACTORY over a table of defects, as `RingStubs.luau` is, so that
	`defects` is empty for the baseline and has exactly ONE field set for every
	control: a control that fires is then attributable to that one field.

	WHAT THIS IS NOT, and it matters because the next agent to read it is the
	one who has to write the real thing: it is NOT `src/server/seats/Projection.luau`
	and not a sketch of one. The baseline is the Contract's allowlist only as
	far as the checks can see - it has no types beyond `any`, it does no
	membership check of its own beyond what the defects need, and its error
	message for a stranger is whatever fell out. GREEN writes the module from
	the story's Contract (PO-1 to PO-6), against the failing tests in
	`tests/server/projection_test.luau`; nothing here is to be copied. In
	particular AC-4's source guard never runs over this file, so nothing here
	says anything about how the real module may be written.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE - `src/server/seats/Ring.luau`
	is SEAT-001's, merged and frozen - so these controls are EXECUTED in RED,
	and `tests/server/projection_controls_test.luau` records what each one
	actually did.
]]

local Ring = require("../../src/server/seats/Ring")

local ProjectionStubs = {}

--[[
	One field per control, each a single edit to the projection below.

	  * `copyAndRemoveSigma`  - `table.clone(assignment)` then `sigma = nil`
	                            (AC-2's control, AC-3's control; mutation 1 of
	                            `## Notes`)
	  * `lensFromSupplier`    - lensClass read from the supplier's key class
	                            instead of the dependent's (mutation 2)
	  * `emptyForUnknown`     - `{}` for a player not in the assignment
	                            instead of raising (mutation 3)
	  * `refuseViaRing`       - no membership check of its own; a stranger
	                            reaches `Ring.supplierOf` and gets Ring's error
	                            (PO-3)
	  * `aliasSeatOrder`      - `seatOrder = assignment.players`, the same
	                            table (PO-2)
	  * `seatOrderFromRing`   - seatOrder walked along σ from `p` rather than
	                            copied from the seats (AC-6, "σ in any form")
	  * `leakSupplierClass`   - one extra field, `supplierClass`, holding
	                            `keyClass[σ⁻¹(p)]` (AC-2 and AC-6, one integer)
	  * `swapNeighbours`      - supplierId and dependentId exchanged (AC-1)
]]
export type Defects = {
	copyAndRemoveSigma: boolean?,
	lensFromSupplier: boolean?,
	emptyForUnknown: boolean?,
	refuseViaRing: boolean?,
	aliasSeatOrder: boolean?,
	seatOrderFromRing: boolean?,
	leakSupplierClass: boolean?,
	swapNeighbours: boolean?,
}

local function isSeated(assignment: any, playerId: any): boolean
	for _, id in assignment.players do
		if id == playerId then
			return true
		end
	end
	return false
end

function ProjectionStubs.make(defects: Defects): any
	local projection = {}

	projection.forPlayer = function(assignment: any, playerId: any): any
		if defects.copyAndRemoveSigma then
			-- The denylist, verbatim: the whole record minus the one field
			-- everyone already knows is private.
			local view = table.clone(assignment)
			view.sigma = nil
			return view
		end

		if not defects.refuseViaRing and not isSeated(assignment, playerId) then
			if defects.emptyForUnknown then
				return {}
			end
			error(
				`ProjectionStubs.forPlayer: {tostring(playerId)} is not seated in this assignment`,
				2
			)
		end

		local supplierId = Ring.supplierOf(assignment, playerId)
		local dependentId = Ring.dependentOf(assignment, playerId)
		if defects.swapNeighbours then
			supplierId, dependentId = dependentId, supplierId
		end

		local seatOrder: { string }
		if defects.aliasSeatOrder then
			seatOrder = assignment.players
		elseif defects.seatOrderFromRing then
			seatOrder = { playerId }
			local at = playerId
			for _ = 2, #assignment.players do
				at = assignment.sigma[at]
				table.insert(seatOrder, at)
			end
		else
			seatOrder = {}
			for i, id in assignment.players do
				seatOrder[i] = id
			end
		end

		local view: { [string]: any } = {
			playerId = playerId,
			keyClass = assignment.keyClass[playerId],
			lensClass = if defects.lensFromSupplier
				then assignment.keyClass[Ring.supplierOf(assignment, playerId)]
				else Ring.lensOf(assignment, playerId),
			supplierId = supplierId,
			dependentId = dependentId,
			seatOrder = seatOrder,
		}
		if defects.leakSupplierClass then
			view.supplierClass = assignment.keyClass[Ring.supplierOf(assignment, playerId)]
		end
		return view
	end

	return projection
end

ProjectionStubs.correct = ProjectionStubs.make({})
ProjectionStubs.copyAndRemoveSigma = ProjectionStubs.make({ copyAndRemoveSigma = true })
ProjectionStubs.lensFromSupplier = ProjectionStubs.make({ lensFromSupplier = true })
ProjectionStubs.emptyForUnknown = ProjectionStubs.make({ emptyForUnknown = true })
ProjectionStubs.refuseViaRing = ProjectionStubs.make({ refuseViaRing = true })
ProjectionStubs.aliasSeatOrder = ProjectionStubs.make({ aliasSeatOrder = true })
ProjectionStubs.seatOrderFromRing = ProjectionStubs.make({ seatOrderFromRing = true })
ProjectionStubs.leakSupplierClass = ProjectionStubs.make({ leakSupplierClass = true })
ProjectionStubs.swapNeighbours = ProjectionStubs.make({ swapNeighbours = true })

return ProjectionStubs
