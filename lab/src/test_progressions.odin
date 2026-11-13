package lab

/*
 * Progressions (content/reality.tri's #Rate and #Turn; DETAIL_REGIMES.md
 * decisions 4 and 5): a rate, by a bramble's regrowth (content/foraging/).
 * Full, it rests, its time 0. Stripped, by whatever strips it, its time is
 * then, and it holds one more each day after, to its most, where it rests
 * again; nothing is stepped between. A turn is farming's test: a sown plot
 * ripe a fortnight on.
 */
test_progressions :: proc() {
	DAY :: i64(86400000)

	w := test_world(105)
	bg_check(progressions_check(world_tri(w)) == "")
	c := test_committer(w)
	progressions := autorelease(progressions_init_with_world(w))
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_add_domain(s, progressions_as_domain(progressions))

	g := proposal_group_group_with_phase(.System, "setup: a bramble")
	bramble := proposal_group_create(g, "bramble", "a bramble", on_tile(5, 5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(3600000))
	bramble = proposal_group_id_for(g, bramble)
	patch :: proc(w: ^World, e: Entity_ID) -> ^Patch {
		return (^Patch)(world_record(w, world_kind_named(w, "Patch"), e))
	}
	bg_check(patch(w, bramble).handfuls == 3 && patch(w, bramble).grewAt == 0)

	/* stripped, and nothing said of its time */
	g = proposal_group_group_with_phase(.System, "the bramble is stripped")
	proposal_group_set_of_to(g, "Patch.handfuls", whole(bramble), 0)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2 * 3600000))
	left := patch(w, bramble).grewAt
	bg_check(patch(w, bramble).handfuls == 0 && left >= 3600000 && left <= 2 * 3600000)

	before := world_boundary(w)
	scheduler_run_until(s, time_make(left + DAY - 1000))
	bg_check(patch(w, bramble).handfuls == 0)
	scheduler_run_until(s, time_make(left + DAY + 1000))
	bg_check(patch(w, bramble).handfuls == 1 && patch(w, bramble).grewAt == left + DAY)
	scheduler_run_until(s, time_make(left + 2 * DAY + 1000))
	bg_check(patch(w, bramble).handfuls == 2 && patch(w, bramble).grewAt == left + 2 * DAY)
	scheduler_run_until(s, time_make(left + 3 * DAY + 1000))
	bg_check(patch(w, bramble).handfuls == 3 && patch(w, bramble).grewAt == 0)
	scheduler_run_until(s, time_make(left + 9 * DAY))
	bg_check(patch(w, bramble).handfuls == 3 && patch(w, bramble).grewAt == 0)
	bg_check(world_boundary(w) - before <= 12)

	/* several periods at once: as many as the time makes it */
	g = proposal_group_group_with_phase(.System, "stripped again, a day and a half ago")
	now := world_time(w).ms
	proposal_group_set_of_to(g, "Patch.handfuls", whole(bramble), 0)
	proposal_group_set_of_to(g, "Patch.grewAt", whole(bramble), now - DAY - DAY / 2)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(now + 1000))
	bg_check(patch(w, bramble).handfuls == 1 && patch(w, bramble).grewAt == now - DAY / 2)
}
