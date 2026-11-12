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
	reason := apply_declared_effect(w, action_make("open_door", giver, door, NO_ENTITY), 0, g)
	bg_check(strings.contains(reason, "open_door fails at roles.item.ajar"))
	bg_check(proposal_group_count(g) == 0)

	/* moves: what is given is in a free hand of the other's */
	bg_check(perform(w, c, action_make("give", giver, nail, taker), 0, &error) != nil)
	committer_commit_boundary(c)
	at := world_location_of(w, nail)
	bg_check(at.form == .Held_By && at.place == taker)
	/* not the giver's to give now: the item is no longer in its hand */
	g = proposal_group_group_with_phase(.Action, "test: given twice")
	reason = apply_declared_effect(w, action_make("give", giver, nail, taker), 0, g)
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

	/* and where it still holds, the fresh group stands in the same
	 * boundary: two mark the nail, each one more than it read */
	one := test_marking(w, nail, 0)
	two := test_marking(w, nail, 0)
	committer_submit(c, one)
	committer_submit(c, two)
	settled = committer_commit_boundary(c)
	bg_check(len(settled) == 3 && world_get_field(w, "Body.toolMarks", nail, &v) && v == 2)
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
