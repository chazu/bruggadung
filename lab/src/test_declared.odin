package lab

/*
 * Declared effects (EFFECTS.md, act_declared.odin): an operation that says
 * what it does in content is resolved against the truth, and what it says
 * becomes proposals. A field `after` states is set; a `moves` into a hand
 * is into a free one; an `emits` is an event. What an operation requires
 * and the truth doesn't bear out fails, with the path as the reason.
 */

import "core:slice"
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


/* Lending (a move that `lends`, act_declared.odin's declared_lend): what
 * its owner lends stays its own, in the keeping of the other and its
 * household, who may hold and use it but not give it away, till the
 * loan's term is over; back with its owner, by whatever move, it is in
 * nobody's keeping. What isn't the actor's it can't lend; what is nobody's
 * is its own by lending it. */
test_lending :: proc() {
	error: string

	w := test_world(7)
	c := test_committer(w)
	ada   := test_commit_create(c, "worker", on_tile(1, 1, 0))
	bo    := test_commit_create(c, "worker", on_tile(2, 1, 0))
	cy    := test_commit_create(c, "worker", on_tile(1, 2, 0))
	dee   := test_commit_create(c, "worker", on_tile(2, 2, 0))
	nail  := test_commit_create(c, "iron_nail", held_by(ada, 0))
	purse := test_commit_create(c, "coins_400", held_by(ada, 1))
	other := test_commit_create(c, "iron_nail", held_by(cy, 0))
	spare := test_commit_create(c, "iron_nail", held_by(cy, 1))
	test_owning(c, ada, nail)
	test_owning(c, ada, purse)
	test_owning(c, ada, other)
	{
		kin := proposal_group_group_with_phase(.System, "setup: Bo and Dee, kin")
		for pair in ([2][2]Entity_ID{{bo, dee}, {dee, bo}}) {
			bond := proposal_group_create(kin, "kin_bond", "kin", location_make_none())
			proposal_group_set_of_to(kin, "Bond.bondOf", whole(bond), i64(pair[0]))
			proposal_group_set_of_to(kin, "Bond.toward", whole(bond), i64(pair[1]))
		}
		committer_submit(c, kin)
		committer_commit_boundary(c)
	}
	hour := i64(3600000)

	/* lent to Bo for an hour, the nail is Ada's still, and Bo's to hold,
	 * and his household's: Dee's too */
	bg_check(perform(w, c, action_make("lend", ada, nail, bo), hour, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, nail).place == bo)
	bg_check(slice.equal(owners_of(w, nail), []Entity_ID{ada}) && in_keeping_of(w, nail, bo) && in_keeping_of(w, nail, dee))
	bg_check(!claimed_by_another(w, nail, ada) && !claimed_by_another(w, nail, bo) && !claimed_by_another(w, nail, dee) &&
	         claimed_by_another(w, nail, cy))
	kept := claims_on(w, nail, "\"keeping\"")
	bg_check(len(kept) == 2)

	/* put down and taken up again by Bo, it is in Bo's keeping still, and
	 * not Bo's own */
	bg_check(perform(w, c, action_make("put_down", bo, nail, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(perform(w, c, action_make("take", bo, nail, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, nail).place == bo && in_keeping_of(w, nail, bo))
	bg_check(slice.equal(owners_of(w, nail), []Entity_ID{ada}))

	/* given back, it is in nobody's keeping, and Ada's as it was */
	bg_check(perform(w, c, action_make("give", bo, nail, ada), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, nail).place == ada && !in_keeping_of(w, nail, bo) && !in_keeping_of(w, nail, dee))
	for claim in kept do bg_check(!world_is_live(w, claim))
	bg_check(slice.equal(owners_of(w, nail), []Entity_ID{ada}) && claimed_by_another(w, nail, bo))

	/* lent, the purse isn't Bo's to give: given to Cy, it is Ada's still,
	 * and not Cy's to hold */
	bg_check(perform(w, c, action_make("lend", ada, purse, bo), hour, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, purse).place == bo && in_keeping_of(w, purse, bo))
	bg_check(perform(w, c, action_make("put_down", cy, other, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(perform(w, c, action_make("give", bo, purse, cy), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, purse).place == cy)
	bg_check(slice.equal(owners_of(w, purse), []Entity_ID{ada}) && claimed_by_another(w, purse, cy))

	/* Ada's other nail, in Cy's hand, isn't Cy's to lend */
	bg_check(perform(w, c, action_make("put_down", cy, purse, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(perform(w, c, action_make("take", cy, other, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(perform(w, c, action_make("lend", cy, other, bo), hour, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, other).place == bo && !in_keeping_of(w, other, bo) && claimed_by_another(w, other, bo))

	/* the spare nail is nobody's: lent by Cy, it is Cy's own by that, and
	 * in Bo's keeping */
	bg_check(len(owners_of(w, spare)) == 0)
	bg_check(perform(w, c, action_make("lend", cy, spare, bo), hour, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, spare).place == bo && slice.equal(owners_of(w, spare), []Entity_ID{cy}))
	bg_check(in_keeping_of(w, spare, bo) && !claimed_by_another(w, spare, bo) && claimed_by_another(w, spare, ada))

	/* the hour over, the keeping has lapsed: Bo holds Cy's nail as he
	 * would any other's; given back even so, the claim is gone */
	world_set_time(w, time_make(world_time(w).ms + hour))
	bg_check(!in_keeping_of(w, spare, bo) && !in_keeping_of(w, spare, dee) && claimed_by_another(w, spare, bo))
	bg_check(len(laws_broken(w, action_make("take", bo, spare, NO_ENTITY))) == 0)      /* no law in this world */
	late := claims_on(w, spare, "\"keeping\"")
	bg_check(len(late) == 2)
	bg_check(perform(w, c, action_make("give", bo, spare, cy), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, spare).place == cy)
	for claim in late do bg_check(!world_is_live(w, claim))
}


/* What is nobody's is whoever's gets it into its own hand
 * (kinds_body_kind.odin): taken up, it is the taker's own; another's taken
 * stays whose it was. */
test_taking_up :: proc() {
	error: string

	w := test_world(7)
	c := test_committer(w)
	ada   := test_commit_create(c, "worker", on_tile(1, 1, 0))
	bo    := test_commit_create(c, "worker", on_tile(2, 1, 0))
	found := test_commit_create(c, "iron_nail", on_tile(1, 1, 0))
	hers  := test_commit_create(c, "iron_nail", on_tile(2, 1, 0))
	sack  := test_commit_create(c, "grain_sack", on_tile(1, 1, 0))
	test_owning(c, ada, hers)
	bg_check(len(owners_of(w, found)) == 0)

	bg_check(perform(w, c, action_make("take", ada, found, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(slice.equal(owners_of(w, found), []Entity_ID{ada}) && claimed_by_another(w, found, bo))

	/* Ada's, taken by Bo, is Ada's still */
	bg_check(perform(w, c, action_make("take", bo, hers, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, hers).place == bo && slice.equal(owners_of(w, hers), []Entity_ID{ada}))

	/* some of a stack nobody's, taken: those are the taker's, the rest
	 * nobody's */
	bg_check(perform(w, c, action_make("take_some", ada, sack, NO_ENTITY), 10, &error) != nil)
	committer_commit_boundary(c)
	inhand: [4]Entity_ID
	some := NO_ENTITY
	for e in inhand[:min(world_entities_at(w, ada, .Held_By, raw_data(inhand[:]), 4), 4)] do if e != found do some = e
	bg_check(some != NO_ENTITY && some != sack && slice.equal(owners_of(w, some), []Entity_ID{ada}))
	bg_check(len(owners_of(w, sack)) == 0)

	/* put by, and more of it taken up and put with it: the stack they merge
	 * into is claimed by her once, not once for each armful */
	chest := test_commit_create(c, "larder", on_tile(1, 1, 0))
	test_owning(c, ada, chest)
	bg_check(perform(w, c, action_make("put_in", ada, some, chest), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(perform(w, c, action_make("take_some", ada, sack, NO_ENTITY), 10, &error) != nil)
	committer_commit_boundary(c)
	more := NO_ENTITY
	for e in inhand[:min(world_entities_at(w, ada, .Held_By, raw_data(inhand[:]), 4), 4)] do if e != found do more = e
	bg_check(more != NO_ENTITY && more != some && slice.equal(owners_of(w, more), []Entity_ID{ada}))
	bg_check(perform(w, c, action_make("put_in", ada, more, chest), 0, &error) != nil)
	committer_commit_boundary(c)
	committer_commit_boundary(c)
	bg_check(!world_is_live(w, more) && world_units_of(w, some) == 20 && len(claims_on(w, some, "\"ownership\"")) == 1)

	/* one unit of it, hers alone by taking it up, goes with hers in the
	 * chest all the same; put with what is nobody's it would stay apart */
	bg_check(perform(w, c, action_make("take_some", ada, sack, NO_ENTITY), 1, &error) != nil)
	committer_commit_boundary(c)
	one := NO_ENTITY
	for e in inhand[:min(world_entities_at(w, ada, .Held_By, raw_data(inhand[:]), 4), 4)] do if e != found do one = e
	bg_check(one != NO_ENTITY && !world_is_stack(w, one) && len(claims_on(w, one, "\"ownership\"")) == 1)
	bg_check(perform(w, c, action_make("put_in", ada, one, chest), 0, &error) != nil)
	committer_commit_boundary(c)
	committer_commit_boundary(c)
	bg_check(!world_is_live(w, one) && world_units_of(w, some) == 21 && len(claims_on(w, some, "\"ownership\"")) == 1)

	/* what one of a household takes up is the household's: Bo's kin Cy
	 * owns it too, and takes it up after him with no wrong */
	cy   := test_commit_create(c, "worker", on_tile(2, 2, 0))
	hook := test_commit_create(c, "iron_nail", on_tile(2, 1, 0))
	{
		kin := proposal_group_group_with_phase(.System, "setup: Bo and Cy, kin")
		for pair in ([2][2]Entity_ID{{bo, cy}, {cy, bo}}) {
			bond := proposal_group_create(kin, "kin_bond", "kin", location_make_none())
			proposal_group_set_of_to(kin, "Bond.bondOf", whole(bond), i64(pair[0]))
			proposal_group_set_of_to(kin, "Bond.toward", whole(bond), i64(pair[1]))
		}
		committer_submit(c, kin)
		committer_commit_boundary(c)
	}
	bg_check(perform(w, c, action_make("put_down", bo, hers, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(perform(w, c, action_make("take", bo, hook, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(len(owners_of(w, hook)) == 2 && !claimed_by_another(w, hook, bo) && !claimed_by_another(w, hook, cy) &&
	         claimed_by_another(w, hook, ada))

	/* a claim on what is gone, and on nothing else, is over */
	mine := claims_on(w, found, "\"ownership\"")
	bg_check(len(mine) == 1)
	g := proposal_group_group_with_phase(.System, "test: the nail lost")
	proposal_group_destroy(g, whole(found), "lost")
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!world_is_live(w, found) && len(mine) == 1 && !world_is_live(w, mine[0]))
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
