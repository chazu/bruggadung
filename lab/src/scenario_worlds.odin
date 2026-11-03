package lab

/*
 * The laboratory's worlds, as the system groups that set them up. The
 * scenarios and interactive sessions build them the same way, so the same
 * world seed gives the same entities and IDs.
 *
 * (ported from the Objective-C lab's scenario/BGWorlds.m)
 */


/* The workshop of COMPONENTS.md Scenario 1. Handles: 0 bin, 1 the smith's
 * nails, 2 lock, 3 worker, 4 smith, 5 the smith's claim; with mixed goods
 * also 6 the worker's nails (in the worker's hand) and 7 the worker's claim. */
// the handles as ^[8]Entity_ID (the C array parameter).
workshop_setup :: proc(mixedGoods: bool, h: ^[8]Entity_ID) -> ^Proposal_Group {
	g: ^Proposal_Group

	g    = proposal_group_group_with_phase(.System, "setup: the workshop")
	h[0] = proposal_group_create(g, "bin", "bin", on_tile(3, 4, 0))
	h[1] = proposal_group_create(g, "nails_30", "the smith's nails", in_(h[0]))
	h[2] = proposal_group_create(g, "lock", "lock", on_tile(5, 4, 0))
	h[3] = proposal_group_create(g, "worker", "worker", on_tile(4, 4, 0))
	h[4] = proposal_group_create(g, "smith", "smith", on_tile(2, 4, 0))
	h[5] = proposal_group_create(g, "ownership", "the smith's claim", location_make_none())
	proposal_group_set_of_to(g, "Claim.quantity", whole(h[5]), 30)
	proposal_group_relate(g, .Claimant, whole(h[5]), whole(h[4]))
	proposal_group_relate(g, .Claim_Subject, whole(h[5]), whole(h[1]))
	h[6] = NO_ENTITY
	h[7] = NO_ENTITY
	if mixedGoods {
		h[6] = proposal_group_create(g, "nails_10", "the worker's nails", held_by(h[3], 0))
		h[7] = proposal_group_create(g, "ownership", "the worker's claim", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(h[7]), 10)
		proposal_group_relate(g, .Claimant, whole(h[7]), whole(h[3]))
		proposal_group_relate(g, .Claim_Subject, whole(h[7]), whole(h[6]))
	}
	return g
}


/* The cistern room of DOMAIN_SIMULATION.md Scenario 3. Handles: 0 cistern,
 * 1 tap A, 2 tap B, 3 crack, 4 bucket A, 5 bucket B, 6 agent A, 7 agent B. */
// the handles as ^[8]Entity_ID.
cistern_setup :: proc(h: ^[8]Entity_ID) -> ^Proposal_Group {
	g: ^Proposal_Group

	g    = proposal_group_group_with_phase(.System, "setup: the cistern room")
	h[0] = proposal_group_create(g, "cistern", "cistern", on_tile(5, 5, 0))
	h[1] = proposal_group_create(g, "tap", "tap A", part_of(h[0], "tap", 0))
	h[2] = proposal_group_create(g, "tap", "tap B", part_of(h[0], "tap", 1))
	h[3] = proposal_group_create(g, "crack", "crack", part_of(h[0], "crack", 0))
	h[4] = proposal_group_create(g, "bucket", "bucket A", in_(h[1]))
	h[5] = proposal_group_create(g, "bucket", "bucket B", in_(h[2]))
	h[6] = proposal_group_create(g, "agent_a", "agent A", on_tile(4, 5, 0))
	h[7] = proposal_group_create(g, "agent_b", "agent B", on_tile(6, 5, 0))
	return g
}
