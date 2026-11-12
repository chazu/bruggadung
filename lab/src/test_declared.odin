package lab

/*
 * Declared effects (EFFECTS.md, act_declared.odin): an operation that says
 * what it does in content is resolved against the truth, and what it says
 * becomes proposals. A field `after` states is set; a `moves` into a hand
 * is into a free one; an `emits` is an event. What an operation requires
 * and the truth doesn't bear out fails, with the path as the reason.
 */

import "core:strings"

test_declared :: proc() {
	v: i64
	error: string

	w := test_world(7)
	c := test_committer(w)
	giver  := test_commit_create(c, "worker", on_tile(1, 1, 0))
	taker  := test_commit_create(c, "worker", on_tile(2, 1, 0))
	door   := test_commit_create(c, "room_door", on_tile(1, 2, 0))
	larder := test_commit_create(c, "larder", on_tile(2, 2, 0))
	nail   := test_commit_create(c, "iron_nail", held_by(giver, 0))

	/* after: the door, shut, is left ajar */
	bg_check(world_get_field(w, "Door.ajar", door, &v) && v == 0)
	bg_check(perform(w, c, action_make("open_door", giver, door, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_get_field(w, "Door.ajar", door, &v) && v == 1)
	/* ajar already, the truth doesn't bear out what opening requires */
	g := proposal_group_group_with_phase(.Action, "test: a door opened twice")
	reason := apply_declared_effect(w, action_make("open_door", giver, door, NO_ENTITY), 0, 0, g)
	bg_check(strings.contains(reason, "open_door fails at roles.item.ajar"))
	bg_check(proposal_group_count(g) == 0)

	/* moves: what is given is in a free hand of the other's */
	bg_check(perform(w, c, action_make("give", giver, nail, taker), 0, &error) != nil)
	committer_commit_boundary(c)
	at := world_location_of(w, nail)
	bg_check(at.form == .Held_By && at.place == taker)
	/* not the giver's to give now: the item is no longer in its hand */
	g = proposal_group_group_with_phase(.Action, "test: given twice")
	reason = apply_declared_effect(w, action_make("give", giver, nail, taker), 0, 0, g)
	bg_check(strings.contains(reason, "give fails at roles.item.place"))

	/* moves, into a container and onto a tile: the taker puts the nail in
	 * the larder; the giver, handed another, puts it down at its feet */
	bg_check(perform(w, c, action_make("put_in", taker, nail, larder), 0, &error) != nil)
	committer_commit_boundary(c)
	at = world_location_of(w, nail)
	bg_check(at.form == .In && at.place == larder)
	other := test_commit_create(c, "iron_nail", held_by(giver, 0))
	bg_check(perform(w, c, action_make("put_down", giver, other, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	at = world_location_of(w, other)
	bg_check(at.form == .On_Tile && at.x == 1 && at.y == 1 && at.level == 0)

	/* every operation in the content says what it does */
	bg_check(declared_check(world_tri(w)) == "")

	/* emits: looking in is an event, the looker's, of what it looked in */
	g = perform(w, c, action_make("look_in", giver, larder, NO_ENTITY), 0, &error)
	bg_check(g != nil && proposal_group_count(g) == 1)
	if g != nil && proposal_group_count(g) == 1 {
		p := proposal_group_proposals(g)[0]
		bg_check(p.kind == .Event && p.name == "looked" && p.target.entity == giver && p.other.entity == larder)
	}
	committer_commit_boundary(c)

	/* an instant operation's declared effect is resolved again if it is
	 * stale when it commits: two open the door shut again in one boundary.
	 * The second's group, built when the door was shut, is rejected; built
	 * afresh, opening no longer holds of a door ajar, and nothing replaces
	 * it */
	shut := proposal_group_group_with_phase(.System, "test: the door shut again")
	proposal_group_set_of_to(shut, "Door.ajar", whole(door), 0)
	committer_submit(c, shut)
	committer_commit_boundary(c)
	first  := perform(w, c, action_make("open_door", giver, door, NO_ENTITY), 0, &error)
	second := perform(w, c, action_make("open_door", taker, door, NO_ENTITY), 0, &error)
	bg_check(first != nil && second != nil && second.again != nil)
	settled := committer_commit_boundary(c)
	bg_check(len(settled) == 2 && world_get_field(w, "Door.ajar", door, &v) && v == 1)

	/* a portion: paying puts so many coins in; `exact`, more than there
	 * are is refused, where taking more than there are takes them all */
	purse := test_commit_create(c, "coins_400", held_by(giver, 0))
	bg_check(perform(w, c, action_make("pay", giver, purse, larder), 500, &error) == nil && strings.contains(error, "it hasn't so many"))
	bg_check(perform(w, c, action_make("pay", giver, purse, larder), 100, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_units_of(w, purse) == 300 && world_location_of(w, purse).place == giver)
	bg_check(perform(w, c, action_make("put_down", giver, purse, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(perform(w, c, action_make("take_some", giver, purse, NO_ENTITY), 500, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_units_of(w, purse) == 300 && world_location_of(w, purse).place == giver)

	/* and where it still holds, the fresh group stands in the same
	 * boundary: two mark the nail, each one more than it read */
	one := test_marking(w, nail, 0)
	two := test_marking(w, nail, 0)
	committer_submit(c, one)
	committer_submit(c, two)
	settled = committer_commit_boundary(c)
	bg_check(len(settled) == 3 && world_get_field(w, "Body.toolMarks", nail, &v) && v == 2)
}


/* An ownership claim of `who`'s on `thing`, committed. */
@(private = "file")
test_owning :: proc(c: ^Committer, who: Entity_ID, thing: Entity_ID) -> Entity_ID {
	g := proposal_group_group_with_phase(.System, "setup: whose it is")
	claim := proposal_group_create(g, "ownership", "its own", location_make_none())
	proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
	proposal_group_relate(g, .Claimant, whole(claim), whole(who))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
	committer_submit(c, g)
	committer_commit_boundary(c)
	return proposal_group_id_for(g, claim)
}


/* Passing (a move that `passes`, act_declared.odin's declared_pass): what
 * its owner pays, gives or puts away is the receiver's from then on; what
 * isn't the actor's to give stays whose it was; what is nobody's, put into
 * a container, is its owners'. */
test_passing :: proc() {
	error: string
	inside: [4]Entity_ID

	w := test_world(7)
	c := test_committer(w)
	ada   := test_commit_create(c, "worker", on_tile(1, 1, 0))
	bo    := test_commit_create(c, "worker", on_tile(2, 1, 0))
	cy    := test_commit_create(c, "worker", on_tile(1, 2, 0))
	dee   := test_commit_create(c, "worker", on_tile(2, 2, 0))
	stall := test_commit_create(c, "larder", on_tile(2, 2, 0))
	purse := test_commit_create(c, "coins_400", held_by(ada, 0))
	nail  := test_commit_create(c, "iron_nail", held_by(cy, 0))
	sack  := test_commit_create(c, "grain_sack", held_by(cy, 1))
	ours  := test_commit_create(c, "iron_nail", held_by(ada, 1))
	test_owning(c, bo, stall)
	hers := test_owning(c, ada, purse)
	test_owning(c, ada, nail)
	test_owning(c, ada, ours)
	test_owning(c, bo, ours)
	bg_check(!claimed_by_another(w, purse, ada) && claimed_by_another(w, purse, bo))

	/* paid into Bo's stall, the coins are Bo's; the purse is still Ada's */
	bg_check(perform(w, c, action_make("pay", ada, purse, stall), 100, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_entities_at(w, stall, .In, raw_data(inside[:]), 4) == 1)
	paid := inside[0]
	bg_check(world_units_of(w, paid) == 100 && world_units_of(w, purse) == 300)
	bg_check(claimed_by_another(w, paid, ada) && !claimed_by_another(w, paid, bo))
	bg_check(!claimed_by_another(w, purse, ada) && claimed_by_another(w, purse, bo))

	/* what several own, given by one of them to another of them, is still
	 * theirs */
	bg_check(perform(w, c, action_make("give", ada, ours, bo), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, ours).place == bo)
	bg_check(!claimed_by_another(w, ours, ada) && !claimed_by_another(w, ours, bo) && claimed_by_another(w, ours, cy))

	/* given whole, the purse is Bo's alone, and Ada's claim on it is over */
	bg_check(perform(w, c, action_make("give", ada, purse, bo), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, purse).place == bo)
	bg_check(claimed_by_another(w, purse, ada) && !claimed_by_another(w, purse, bo))
	bg_check(!world_is_live(w, hers))

	/* Ada's nail in Cy's hand isn't Cy's to give: given to Dee, it is
	 * still Ada's */
	bg_check(perform(w, c, action_make("give", cy, nail, dee), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, nail).place == dee)
	bg_check(!claimed_by_another(w, nail, ada) && claimed_by_another(w, nail, dee) && claimed_by_another(w, nail, cy))

	/* nobody's, put into Bo's larder, the sack is Bo's */
	bg_check(!claimed_by_another(w, sack, ada))
	bg_check(perform(w, c, action_make("put_in", cy, sack, stall), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(claimed_by_another(w, sack, cy) && !claimed_by_another(w, sack, bo))
}


/* A group that marks a thing once more than it read, expecting what it
 * read, and is built afresh if that is stale. */
@(private = "file")
test_marking :: proc(w: ^World, thing: Entity_ID, tries: int) -> ^Proposal_Group {
	marks: i64

	world_get_field(w, "Body.toolMarks", thing, &marks)
	g := proposal_group_group_with_phase(.Action, "test: a mark more")
	proposal_group_set_of_to_expecting(g, "Body.toolMarks", whole(thing), marks + 1, marks)
	g.action = action_make("mark", NO_ENTITY, thing, NO_ENTITY)
	g.tries  = tries
	g.again  = proc(world: ^World, was: ^Proposal_Group) -> ^Proposal_Group {
		return test_marking(world, was.action.roles[.Item], was.tries + 1)
	}
	return g
}
