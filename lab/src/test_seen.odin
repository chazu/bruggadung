package lab

/*
 * Seen kinds (KNOWLEDGE.md decision 17, content/knowledge.tri's #Seen):
 * what a thing is, as far as it shows, whatever its blueprint's type is
 * written as. An inner state doesn't show; a kind with no field of its own
 * does, if it is listed; one not listed shows as the listed kinds above it.
 */

import tri "../../triangle/odin/triangle"

test_seen_kinds :: proc() {
	w := test_world(1)
	c := test_committer(w)
	tc := world_tri(w)

	/* every entry names a type, and none twice */
	family := tri.family_index(tc, "seen")
	bg_check(family != nil && uint(len(w.seen)) == uint(tri.index_count(family)))
	twice := false
	for a, i in w.seen do for b in w.seen[i + 1:] do twice |= a.type == b.type
	bg_check(!twice)

	/* a person is seen as an agent: its stomach doesn't show */
	farmer := test_commit_create(c, "farmer", on_tile(1, 1, 0))
	bg_check(world_record(w, world_kind_named(w, "Hungry"), farmer) != nil)
	bg_check(kind_of_entity(w, farmer) == "#Agent")
	/* a worksite has no field of its own to show, and shows */
	bg_check(kind_of_entity(w, test_commit_create(c, "scarecrow", on_tile(2, 1, 0))) == "#Worksite")
	/* a stove is a stove, not its heat */
	bg_check(kind_of_entity(w, test_commit_create(c, "stove", on_tile(3, 1, 0))) == "#Stove")
	/* several at once: their conjunction */
	bg_check(kind_of_entity(w, test_commit_create(c, "grain", on_tile(4, 1, 0))) == "#Thing & #Food & #Body")

	/* what has no body is what it is */
	g := proposal_group_group_with_phase(.System, "a claim")
	claim := proposal_group_create(g, "ownership", "a claim", location_make_none())
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(kind_of_entity(w, proposal_group_id_for(g, claim)) == "#Claim")

	/* a kind not listed shows as the listed kinds above it: a stove, the
	 * stove struck from the list, is a firebox and a body */
	stove := test_commit_create(c, "stove", on_tile(5, 1, 0))
	for s, i in w.seen {
		if string(s.name) == "#Stove" {
			ordered_remove(&w.seen, i)
			break
		}
	}
	bg_check(kind_of_entity(w, stove) == "#Thing & #Combustor & #Body")
}
