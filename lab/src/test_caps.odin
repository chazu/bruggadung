package lab

/*
 * Fixed caps (core_faults.odin, REVIEW.md §4.4): past one, the lab used to
 * skip work silently. Now a mind's lists, the claims on a thing and what a
 * place holds grow as they need; a cap that stays is a fault when met.
 * Each test meets the caps it names and takes the faults it expects, so
 * the runner doesn't fail it.
 */

import "core:fmt"
import "core:strings"
import tri "../../triangle/odin/triangle"


/* Whether the faults taken hold each of `wanted`. */
@(private = "file")
faults_hold :: proc(taken: string, wanted: ..string) -> bool {
	for w in wanted do if !strings.contains(taken, w) do return false
	return true
}


/* The fault list itself: a fault met twice is kept once; taken, the list
 * is empty; `fitting` passes what fits and faults past it. */
test_caps_faults :: proc() {
	bg_check(len(cap_faults) == 0)
	cap_fault("a cap: %d", 1)
	cap_fault("a cap: %d", 1)
	cap_fault("another cap")
	bg_check(len(cap_faults) == 2)
	taken := take_cap_faults()
	bg_check(taken == "a cap: 1\nanother cap")
	bg_check(len(cap_faults) == 0)

	bg_check(fitting(3, 4, "things") == 3 && len(cap_faults) == 0)
	bg_check(fitting(4, 4, "things") == 4 && len(cap_faults) == 0)
	bg_check(fitting(5, 4, "things") == 4)
	bg_check(take_cap_faults() == "things: 5, more than the 4 it holds; the rest passed over")
}


/* A mind's lists grow past what were their caps (16 commitments, 8
 * questions, 16 settled and weighed, 8 talks, 16 debts), restored and
 * saved again whole; the caps that stay (16 goals deep, 8 slots, 16 habits,
 * 16 acts) are faults when a save holds more. */
test_caps_mind :: proc() {
	w := test_world(1)
	c := test_committer(w)
	knowledge := autorelease(knowledge_init_with_world(w))
	agency    := autorelease(agency_init_with_world(w, c, knowledge))

	lines := make([dynamic]string, context.temp_allocator)
	for k in 0 ..< 20 do append(&lines, fmt.tprintf("commitment 4 goal%d %d %d self 0 0", k, k, 1000 + k))
	for k in 0 ..< 12 do append(&lines, fmt.tprintf("question 4 %d %d 0 %s", 5 + k, k, encode_word("#WhereIs")))
	for k in 0 ..< 20 do append(&lines, fmt.tprintf("settled 4 goal%d %d", k, 7 + k))
	for k in 0 ..< 20 do append(&lines, fmt.tprintf("weighed 4 goal%d %d 1", k, 7 + k))
	for k in 0 ..< 12 do append(&lines, fmt.tprintf("talk 4 %d 1 %d %% 1 0 1 0 %d 0 0 0 0 0 %s", 5 + k, int(Talk_State.Open), k,
	                                                  encode_word("#Stack")))
	for k in 0 ..< 20 do append(&lines, fmt.tprintf("owed 4 %d %d 1 0 %d %d %s", int(Owed_Kind.Debt), 5 + k, 100 + k, k,
	                                                  encode_word("#Stack")))
	agency_restore_saved_state(agency, lines[:])
	m := agency_mind_of(agency, 4)
	bg_check(m.ncommitments == 20 && m.nquestions == 12 && m.nsettled == 20 && m.nweighed == 20)
	bg_check(m.ntalks == 12 && m.nowed == 20)
	bg_check(m.commitments[19].goal == "goal19" && m.owed[19].other == 24 && m.talks[11].with == 16)
	bg_check(len(cap_faults) == 0)
	/* saved again, as many */
	copy_ := autorelease(agency_init_with_world(w, c, knowledge))
	agency_restore_saved_state(copy_, agency_saved_state(agency))
	bg_check(strings.join(agency_saved_state(copy_), "\n", context.temp_allocator) ==
	         strings.join(agency_saved_state(agency), "\n", context.temp_allocator))

	/* the caps that stay: a save past them is a fault */
	clear(&lines)
	mind := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&mind, "mind 4 0 0 0 0 0 0 %d", BG_MAX_INTENTIONS + 1)
	for k in 0 ..< BG_MAX_INTENTIONS + 1 do fmt.sbprintf(&mind, " goal%d 0 0 -1 -1 0 0 0 0 0", k)
	append(&lines, strings.to_string(mind))
	for k in 0 ..< BG_MAX_HABITS + 1 do append(&lines, fmt.tprintf("habit 4 context%d 0 50 0", k))
	for k in 0 ..< BG_MAX_ACTED + 1 do append(&lines, fmt.tprintf("acted 4 op%d 0", k))
	slots := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&slots, "commitment 4 wide 0 1000 self 0 %d", BG_MAX_SLOTS + 1)
	for k in 0 ..< BG_MAX_SLOTS + 1 do fmt.sbprintf(&slots, " slot%d %d", k, k + 1)
	append(&lines, strings.to_string(slots))
	agency_restore_saved_state(agency, lines[:])
	m = agency_mind_of(agency, 4)
	bg_check(m.nintentions == BG_MAX_INTENTIONS && m.nhabits == BG_MAX_HABITS && m.nacted == BG_MAX_ACTED)
	bg_check(m.ncommitments == 1 && m.commitments[0].nparams == BG_MAX_SLOTS)
	bg_check(faults_hold(take_cap_faults(), "more than BG_MAX_INTENTIONS (16)", "more than BG_MAX_HABITS (16)",
	                     "more than BG_MAX_ACTED (16)", "more than BG_MAX_SLOTS (8) slots"))
}


/* Undertaken live, commitments past 16 are kept; one with more slots bound
 * than a goal may have is a fault, and not undertaken. */
test_caps_undertake :: proc() {
	w := test_world(2)
	c := test_committer(w)
	knowledge := autorelease(knowledge_init_with_world(w))
	agency    := autorelease(agency_init_with_world(w, c, knowledge))
	g := proposal_group_group_with_phase(.System, "setup: a farmer")
	me := proposal_group_create(g, "farmer", "me", on_tile(10, 10, 0))
	committer_submit(c, g)
	committer_commit_boundary(c)
	me = proposal_group_id_for(g, me)
	bg_check(world_is_live(w, me))

	for k in 0 ..< 20 {
		bg_check(agency_undertake_goal_from_until_source(agency, me, "brew_on", i64(k), i64(1000 + k), "self"))
	}
	bg_check(agency_mind_of(agency, me).ncommitments == 20)

	wide := make([]Slot_Binding, BG_MAX_SLOTS + 1, context.temp_allocator)
	for &b, k in wide do b = {world_intern(w, ns_utf8(fmt.tprintf("slot%d", k))), u32(k + 1)}
	bg_check(!agency_undertake_every_with(agency, me, "brew_on", 0, 1000, "self", 86400000, wide))
	bg_check(agency_mind_of(agency, me).ncommitments == 20)
	bg_check(faults_hold(take_cap_faults(), "undertaking brew_on: 9 slots bound, more than BG_MAX_SLOTS (8)"))
}


/* What content says, read into fixed room: a list of finds, a goal's ways,
 * an instance's variants, more than the room is a fault. (Content holds
 * fewer than the caps themselves: the readers are asked for less.) */
test_caps_content :: proc() {
	w := test_world(3)
	c := test_committer(w)
	knowledge := autorelease(knowledge_init_with_world(w))
	agency    := autorelease(agency_init_with_world(w, c, knowledge))
	tc := world_tri(w)

	/* brew_on's done finds the vat and the work */
	finds: [2][32]u8
	bg_check(texts_at(tc, tri.pattern(tc, "brew_on"), "done.find", raw_data(finds[:]), 2, "BG_MAX_SLOTS") == 2)
	bg_check(len(cap_faults) == 0)
	bg_check(texts_at(tc, tri.pattern(tc, "brew_on"), "done.find", raw_data(finds[:]), 1, "BG_MAX_SLOTS") == 1)
	bg_check(faults_hold(take_cap_faults(), "more than BG_MAX_SLOTS (1) in its done.find"))
	/* asked for the first only, it is no fault */
	bg_check(texts_at(tc, tri.pattern(tc, "brew_on"), "done.find", raw_data(finds[:]), 1) == 1 && len(cap_faults) == 0)

	/* a goal of several ways */
	methods: [32]cstring
	goal:    cstring
	goals := tri.family_index(tc, "goals")
	for i: uint = 0; goals != nil && i < uint(tri.index_count(goals)) && goal == nil; i += 1 {
		name := cstring(tri.index_tag(goals, i))
		if agency_methods_for(agency, name, raw_data(methods[:]), len(methods)) >= 2 do goal = name
	}
	bg_check(goal != nil && len(cap_faults) == 0)
	if goal != nil {
		bg_check(agency_methods_for(agency, goal, raw_data(methods[:]), 1) == 1)
		bg_check(faults_hold(take_cap_faults(), fmt.tprintf("goal %s: more than 1 methods (BG_MAX_METHODS)", goal)))
	}

	/* an instance of several variants */
	variants: [16]^tri.Node
	several: cstring
	for family in ([]cstring{"things", "methods", "goals", "terrain"}) {
		index := tri.family_index(tc, family)
		for i: uint = 0; index != nil && i < uint(tri.index_count(index)) && several == nil; i += 1 {
			name := cstring(tri.index_tag(index, i))
			if tri.pattern_variant_count(tc, name) >= 2 do several = name
		}
	}
	bg_check(several != nil)
	if several != nil {
		bg_check(variants_of(tc, several, raw_data(variants[:]), len(variants)) >= 2 && len(cap_faults) == 0)
		bg_check(variants_of(tc, several, raw_data(variants[:]), 1) == 1)
		bg_check(faults_hold(take_cap_faults(), "variants, more than BG_MAX_VARIANTS (1)"))
	}
}


/* What a place holds and the claims on a thing grow as they need: a
 * stack with seventy claims on it, each counted, and each over when the
 * stack is gone. Read into fixed room, more than fits is a fault. */
test_caps_world :: proc() {
	w := test_world(4)
	c := test_committer(w)
	g := proposal_group_group_with_phase(.System, "setup: a larder, three sacks, a stack with seventy claims")
	larder := proposal_group_create(g, "larder", "the larder", on_tile(10, 10, 0))
	for _ in 0 ..< 3 do proposal_group_create(g, "grain_sack", "a sack", in_(larder))
	grain := proposal_group_create(g, "grain", "the grain", on_tile(11, 10, 0))
	claims: [70]Entity_ID
	for &claim in claims {
		claim = proposal_group_create(g, "ownership", "a claim", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(grain))
	}
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(proposal_group_applied(g))
	larder, grain = proposal_group_id_for(g, larder), proposal_group_id_for(g, grain)
	for &claim in claims do claim = proposal_group_id_for(g, claim)

	room: [2]Entity_ID
	bg_check(len(world_entities_at_in(w, larder, .In, room[:], "sacks in a larder")) == 2)
	bg_check(faults_hold(take_cap_faults(), "sacks in a larder: 3, more than the 2 it holds"))
	all := world_entities_at_all(w, larder, .In, context.temp_allocator)
	bg_check(len(all) == 3 && len(cap_faults) == 0)

	bg_check(world_claimed_units_of(w, grain) == 70)
	bg_check(len(claims_on(w, grain, "\"ownership\"")) == 70)
	g = proposal_group_group_with_phase(.System, "the grain gone")
	proposal_group_destroy(g, whole(grain), "gone")
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(proposal_group_applied(g))
	live := 0
	for claim in claims do if world_is_live(w, claim) do live += 1
	bg_check(live == 0)
	bg_check(len(cap_faults) == 0)
}


/* The fluid domain's cap on open taps: a save with more taps' carries
 * than it holds is a fault. */
test_caps_fluid :: proc() {
	w := test_world(5)
	fluid := autorelease(fluid_domain_init_with_world(w))
	lines := make([dynamic]string, context.temp_allocator)
	for k in 0 ..< BG_FLUID_MAX + 1 do append(&lines, fmt.tprintf("carry %d %d", 100 + k, k))
	fluid_domain_restore_saved_state(fluid, lines[:])
	bg_check(fluid.ncarries == BG_FLUID_MAX)
	bg_check(faults_hold(take_cap_faults(), "more than BG_FLUID_MAX (64) taps' carries"))
}
