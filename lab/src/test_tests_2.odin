package lab

// The lab's tests, part 2 of 3 (test/BGTests.m, lines 3847-7966: from
// test_pump_wear to traces_agree). The file is split by line range; its
// static helpers are package-level, named with a test_ prefix, so the other
// parts call them (and this part theirs) by the same names.
//
// Four helpers whose prefixed names would be their tests' names take a
// trailing underscore, as part 1's do (test_missing_nails_, test_rumour_):
// test_component_pump_, test_false_alarm_, test_tempting_purse_,
// test_coat_at_dusk_.

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


test_pump_wear :: proc() {
	wet:    Pump_Work
	dry:    Pump_Work
	half:   Pump_Work
	seized: Pump_Work
	failed: Pump_Work
	again:  Pump_Work
	saved:  Pump_Work
	worn:   Pump_Run
	harsh:  Pump_Run
	cheap:  Pump_Run
	run:    Pump_Run
	seal:   i64
	key:    cstring
	fresh:  i32
	beaten: i32

	/* an hour's work lifts what its flow does (20 L a minute) from the well
	 * into the tank, until the tank is full: water moved, none made */
	wet = test_pump_work("crank_pump", "pump 2", nil, 10000000, 0, 1, 0)
	bg_check(wet.used == 3600000 && wet.abused == 0)
	bg_check(wet.tank == 100000 && wet.well == 10000000 - 100000)
	/* the well dry, the hour is abuse; half an hour's lift in it, half */
	dry = test_pump_work("crank_pump", "pump 2", nil, 0, 0, 1, 0)
	bg_check(dry.used == 3600000 && dry.abused == 3600000 && dry.tank == 0)
	half = test_pump_work("crank_pump", "pump 2", nil, 600000, 0, 1, 0)
	bg_check(half.abused == 1800000 && half.tank == 100000 && half.well == 500000)
	/* seized, it can't be worked */
	seized = test_pump_work("crank_pump", "pump 2", "seized", 10000000, 0, 1, 0)
	bg_check(seized.used == 0 && seized.tank == 0)

	/* decision 4: 400 hours' use, shared out: the leather cup wears fastest,
	 * then the valves, the iron slowly, the cover not at all */
	worn = test_pump_opened("crank_pump", "pump 2", "", 300 * 3600000, 0, 400 * 3600000, 0)
	seal = test_wear_in(worn, "piston_seal")
	bg_check(seal > test_wear_in(worn, "inlet_valve") && seal > test_wear_in(worn, "outlet_valve"))
	bg_check(test_wear_in(worn, "inlet_valve") > test_wear_in(worn, "piston") && test_wear_in(worn, "piston") > 0)
	bg_check(test_wear_in(worn, "handle") > 0 && test_wear_in(worn, "cover") == 0)
	/* worked dry all that time, the cup wears three times as fast; the rest
	 * as before */
	harsh = test_pump_opened("crank_pump", "pump 2", "", 300 * 3600000, 0, 400 * 3600000, 400 * 3600000)
	bg_check(test_wear_in(harsh, "piston_seal") >= 3 * seal - 2 && test_wear_in(harsh, "piston_seal") <= 3 * seal + 2)
	bg_check(test_wear_in(harsh, "inlet_valve") == test_wear_in(worn, "inlet_valve"))
	/* decision 6: the cheap make's leather is poorer: the same unit's cup
	 * wears faster, its valves no differently */
	cheap = test_pump_opened("cheap_pump", "pump 2", "", 300 * 3600000, 0, 400 * 3600000, 0)
	bg_check(test_wear_in(cheap, "piston_seal") > seal)
	bg_check(test_wear_in(cheap, "outlet_valve") == test_wear_in(worn, "outlet_valve"))

	/* decision 5: the culprit is drawn weighted by wear: among 24 pumps worked
	 * dry a thousand hours, the cup is to blame more often than among new
	 * ones, but not always */
	fresh = 0
	beaten = 0
	for k in 0 ..< i32(24) {
		key = fmt.ctprintf("pump %d", k)
		fresh  += i32(test_pump_open(key, "flow_loss", 300 * 3600000, 0).culprit == "piston_seal")
		run     = test_pump_opened("crank_pump", key, "flow_loss", 300 * 3600000, 0, 1000 * 3600000, 1000 * 3600000)
		beaten += i32(run.culprit == "piston_seal")
		/* the blamed part is worn at least as a failure leaves it */
		bg_check(len(run.culprit) == 0 || test_wear_in(run, run.culprit) >= 60)
	}
	bg_check(beaten > fresh && beaten < 24)

	/* decision 5: use risks failure, more the more worn: the rickety pump,
	 * 2000 hours behind it, fails within a hundred hours' work. Its culprit is
	 * decided then; a flow loss costs it 80 points of flow if the culprit is
	 * a part; opened, the culprit is worn as a failure leaves it */
	failed = test_pump_work("rickety_pump", "pump 2", nil, 10000000, 2000, 100, 0)
	bg_check(failed.failedIn > 0 && failed.failure == "flow_loss")
	bg_check(i64(failed.failedAt) > i64(failed.failedIn - 1) * (3600000 + 1000) &&
	         i64(failed.failedAt) <= i64(failed.failedIn) * (3600000 + 1000) + 1)
	bg_check(len(failed.blamed) > 0)
	bg_check((failed.flow == 100 && failed.blamedWear == -1) if failed.blamed == "housing" else (failed.flow == 20 && failed.blamedWear >= 60))
	/* worked on after, its use still counts, and it fails no further */
	bg_check(failed.used == (2000 + 100) * 3600000)
	/* the same unit, the same work: the same hour, the same culprit; saved
	 * and restored before it failed, too */
	again = test_pump_work("rickety_pump", "pump 2", nil, 10000000, 2000, 100, 0)
	bg_check(again.failedIn == failed.failedIn && again.blamed == failed.blamed)
	saved = test_pump_work("rickety_pump", "pump 2", nil, 10000000, 2000, 100, failed.failedIn - 1 if failed.failedIn > 1 else 1)
	bg_check(saved.failedIn == failed.failedIn && saved.blamed == failed.blamed)
	/* worn, more fail: of 12 units worked 20 hours, more with 2000 hours
	 * behind them fail than new ones (4% an hour against 1%) */
	fresh = 0
	beaten = 0
	for k in 0 ..< i32(12) {
		key = fmt.ctprintf("pump %d", k)
		fresh  += i32(test_pump_work("rickety_pump", key, nil, 10000000, 0, 20, 0).failedIn > 0)
		beaten += i32(test_pump_work("rickety_pump", key, nil, 10000000, 2000, 20, 0).failedIn > 0)
	}
	bg_check(beaten > fresh)
}


/* LATENT_ASSEMBLY.md decision 7: a part's wear is its own. The pump
 * `blueprint` `key`, `hours` worked dry behind it, opened two levels; its
 * seal replaced, if `spare` is 0 or more, with a new cup worn that much;
 * then worked `work` hours from a full well, saved and restored after hour
 * `saveAfter` if not 0. */
Part_Run :: struct {
	oldSeal:      i64,          /* the seal opened, its attrition then */
	oldSealAfter: i64,          /* and after the work, wherever it is */
	seal:         i64,          /* the seal in place, its attrition before the work */
	sealAfter:    i64,          /* and after */
	valve:        i64,          /* the inlet valve's, before and after */
	valveAfter:   i64,
	blamed:       string,
	failedIn:     i32,
}


test_part_in :: proc(st: Stage, pump: Entity_ID, role: cstring) -> Entity_ID {
	in_: [16]Entity_ID
	n:   uint

	n = world_entities_at(st.w, pump, .Part_Of, raw_data(in_[:]), 16)
	for i in 0 ..< n {
		loc := world_location_of(st.w, in_[i])
		if location_role(&loc) == string(role) do return in_[i]
	}
	return NO_ENTITY
}


test_part_work :: proc(blueprint: cstring, key: cstring, hours: i64, spare: i64, work: i32, saveAfter: i32) -> Part_Run {
	st:     Stage
	g:      ^Proposal_Group
	pump:   Entity_ID
	well:   Entity_ID
	worker: Entity_ID
	wrench: Entity_ID
	cup:    Entity_ID
	old:    Entity_ID
	run:    Part_Run
	error:  string
	text:   cstring
	t:      i64

	st.w   = test_world(157)
	st.c   = test_committer(st.w)
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g      = proposal_group_group_with_phase(.System, "setup: the pump on its well, worn")
	pump   = proposal_group_create(g, blueprint, key, on_tile(5, 5, 0))
	well   = proposal_group_create(g, "well", "the well", on_tile(5, 6, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	cup    = proposal_group_create(g, "leather_cup", "a new cup", held_by(worker, 1)) if spare >= 0 else NO_ENTITY
	proposal_group_set_of_to(g, "Pump.draws", whole(pump), i64(well))
	proposal_group_set_of_to(g, "Latent.used", whole(pump), hours * 3600000)
	proposal_group_set_of_to(g, "Latent.abused", whole(pump), hours * 3600000)
	if cup != NO_ENTITY {
		proposal_group_set_of_to_text(g, "Part.fits", whole(cup), "piston_seal")
		proposal_group_set_of_to(g, "Part.wear", whole(cup), spare)
	}
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump   = proposal_group_id_for(g, pump)
	well   = proposal_group_id_for(g, well)
	worker = proposal_group_id_for(g, worker)
	wrench = proposal_group_id_for(g, wrench)
	cup    = proposal_group_id_for(g, cup) if cup != NO_ENTITY else NO_ENTITY

	error = ""
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2000))
	old = test_part_in(st, pump, "piston_seal")
	world_get_field(st.w, "Part.attrition", old, &run.oldSeal)
	if cup != NO_ENTITY {
		bg_check(perform(st.w, st.c, action_make("replace_part", worker, cup, old), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(10000))
		bg_check(test_part_in(st, pump, "piston_seal") == cup)
	}
	world_get_field(st.w, "Part.attrition", test_part_in(st, pump, "piston_seal"), &run.seal)
	world_get_field(st.w, "Part.wear", test_part_in(st, pump, "piston_seal"), &t)
	run.seal = run.seal if run.seal > t * 10000 else t * 10000
	world_get_field(st.w, "Part.attrition", test_part_in(st, pump, "inlet_valve"), &run.valve)

	for h: i32 = 1; h <= work; h += 1 {
		t = world_time(st.w).ms
		g = proposal_group_group_with_phase(.System, "setup: the worker rested and fed")
		proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), 0)
		proposal_group_set_of_to(g, "Agent.injury", whole(worker), 0)
		proposal_group_set_of_to(g, "Hungry.satiety", whole(worker), 80)
		proposal_group_set_of_to(g, "Hungry.fedAt", whole(worker), t)
		committer_submit(st.c, g)
		perform(st.w, st.c, action_make("work_pump", worker, pump, NO_ENTITY), 0, &error)
		scheduler_run_until(st.s, time_make(t + 3600000 + 1000))
		text = world_text_field(st.w, "Latent.failure", pump)
		if run.failedIn == 0 && text != nil && string(text) != "" do run.failedIn = h
		if h == saveAfter {
			st.w = test_restore(save(st.w, st.c, nil), world_content_build(st.w), &st.c, &error)
			st.s = autorelease(scheduler_init_with_world(st.w, st.c))
			scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
		}
	}
	world_get_field(st.w, "Part.attrition", old, &run.oldSealAfter)
	world_get_field(st.w, "Part.attrition", test_part_in(st, pump, "piston_seal"), &run.sealAfter)
	world_get_field(st.w, "Part.attrition", test_part_in(st, pump, "inlet_valve"), &run.valveAfter)
	text       = world_text_field(st.w, "Latent.blamed", pump)
	run.blamed = ns_string(text if text != nil else "")
	return run
}


test_part_condition :: proc() {
	kept:        Part_Run
	fresh:       Part_Run
	used:        Part_Run
	saved:       Part_Run
	cheap:       Part_Run
	plain:       Part_Run
	key:         cstring
	worn:        i64
	failedKept:  i32
	failedFresh: i32
	sealKept:    i32
	sealFresh:   i32

	/* opened, a seal 1000 hours worked dry is worn through; worked on, the
	 * parts opened wear on, each as its role does */
	kept = test_part_work("crank_pump", "pump 2", 1000, -1, 50, 0)
	bg_check(kept.oldSeal == 1000000 && kept.seal == 1000000 && kept.sealAfter == 1000000)
	bg_check(kept.valveAfter > kept.valve && kept.valve > 0)

	/* a new cup in its place brings its own wear in, none, and wears on from
	 * there; the old one, out on the floor, wears no further */
	fresh = test_part_work("crank_pump", "pump 2", 1000, 0, 50, 0)
	bg_check(fresh.oldSeal == 1000000 && fresh.oldSealAfter == 1000000)
	bg_check(fresh.seal == 0 && fresh.sealAfter > 0 && fresh.sealAfter < 100000)
	bg_check(fresh.valveAfter - fresh.valve == kept.valveAfter - kept.valve)
	/* a cup already worn 30 brings that in: it wears on the same */
	used = test_part_work("crank_pump", "pump 2", 1000, 30, 50, 0)
	bg_check(used.seal == 300000 && used.sealAfter - used.seal == fresh.sealAfter)
	/* saved and restored halfway, the same */
	saved = test_part_work("crank_pump", "pump 2", 1000, 30, 50, 25)
	bg_check(saved.sealAfter == used.sealAfter && saved.valveAfter == used.valveAfter)

	/* its quality is its own: the cheap make's own cup wears faster than the
	 * plain make's, but the same new cup fitted in either wears the same */
	cheap = test_part_work("cheap_pump", "pump 2", 0, -1, 50, 0)
	plain = test_part_work("crank_pump", "pump 2", 0, -1, 50, 0)
	bg_check(plain.sealAfter > 0 && cheap.sealAfter > plain.sealAfter)
	worn  = test_part_work("cheap_pump", "pump 2", 1000, 0, 50, 0).sealAfter
	bg_check(worn == fresh.sealAfter)

	/* the risk and the blame follow what is fitted: of 12 rickety pumps 1000
	 * hours worked dry, worked 20 hours more, fewer fail with a new cup in
	 * them, and fewer of those blame the cup */
	failedKept = 0
	failedFresh = 0
	sealKept = 0
	sealFresh = 0
	for k in 0 ..< i32(12) {
		key          = fmt.ctprintf("pump %d", k)
		kept         = test_part_work("rickety_pump", key, 1000, -1, 20, 0)
		fresh        = test_part_work("rickety_pump", key, 1000, 0, 20, 0)
		failedKept  += i32(kept.failedIn > 0)
		failedFresh += i32(fresh.failedIn > 0)
		sealKept    += i32(kept.blamed == "piston_seal")
		sealFresh   += i32(fresh.blamed == "piston_seal")
	}
	bg_check(failedFresh < failedKept)
	bg_check(sealFresh < sealKept)
}


/* LATENT_ASSEMBLY.md decision 8: servicing a part. The pump `blueprint`
 * `key` on its well, `hours` used behind it, `dry` of them abused, opened two
 * levels, a worker by it with a wrench. */
test_serviced_pump :: proc(st: ^Stage, blueprint: cstring, key: cstring, hours: i64, dry: i64, worker: ^Entity_ID) -> Entity_ID {
	g:      ^Proposal_Group
	pump:   Entity_ID
	well:   Entity_ID
	wrench: Entity_ID
	error:  string

	st.w    = test_world(157)
	st.c    = test_committer(st.w)
	st.s    = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g       = proposal_group_group_with_phase(.System, "setup: the pump on its well, used")
	pump    = proposal_group_create(g, blueprint, key, on_tile(5, 5, 0))
	well    = proposal_group_create(g, "well", "the well", on_tile(5, 6, 0))
	worker^ = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench  = proposal_group_create(g, "wrench_250", "wrench", held_by(worker^, 0))
	proposal_group_set_of_to(g, "Pump.draws", whole(pump), i64(well))
	proposal_group_set_of_to(g, "Latent.used", whole(pump), hours * 3600000)
	proposal_group_set_of_to(g, "Latent.abused", whole(pump), dry * 3600000)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump    = proposal_group_id_for(g, pump)
	worker^ = proposal_group_id_for(g, worker^)
	wrench  = proposal_group_id_for(g, wrench)
	error   = ""
	bg_check(perform(st.w, st.c, action_make("open_up", worker^, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))
	bg_check(perform(st.w, st.c, action_make("open_up", worker^, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2000))
	return pump
}


/* The pump worked `hours`, the worker rested and fed each hour; the hour of
 * its first failure in them, or 0. */
test_serviced_work :: proc(st: Stage, worker: Entity_ID, pump: Entity_ID, hours: i32) -> i32 {
	g:        ^Proposal_Group
	error:    string
	text:     cstring
	t:        i64
	failedIn: i32

	failedIn = 0
	error    = ""
	for h: i32 = 1; h <= hours; h += 1 {
		t = world_time(st.w).ms
		g = proposal_group_group_with_phase(.System, "setup: the worker rested and fed")
		proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), 0)
		proposal_group_set_of_to(g, "Agent.injury", whole(worker), 0)
		proposal_group_set_of_to(g, "Hungry.satiety", whole(worker), 80)
		proposal_group_set_of_to(g, "Hungry.fedAt", whole(worker), t)
		committer_submit(st.c, g)
		perform(st.w, st.c, action_make("work_pump", worker, pump, NO_ENTITY), 0, &error)
		scheduler_run_until(st.s, time_make(t + 3600000 + 1000))
		text = world_text_field(st.w, "Latent.failure", pump)
		if failedIn == 0 && text != nil && string(text) != "" do failedIn = h
	}
	return failedIn
}


/* The worker services the part in `role`, ten minutes; whether it could
 * begin. */
test_service_role :: proc(st: Stage, worker: Entity_ID, pump: Entity_ID, role: cstring) -> bool {
	error: string
	begun: bool
	t:     i64

	error = ""
	t     = world_time(st.w).ms
	begun = perform(st.w, st.c, action_make("service_part", worker, test_part_in(st, pump, role), NO_ENTITY), 0,
	                &error) != nil
	scheduler_run_until(st.s, time_make(t + 600000 + 1000))
	return begun
}


test_attrition_of :: proc(st: Stage, pump: Entity_ID, role: cstring) -> i64 {
	v: i64

	v = -1
	world_get_field(st.w, "Part.attrition", test_part_in(st, pump, role), &v)
	return v
}


test_servicing :: proc() {
	@(static) roles := [4]cstring{"handle", "piston_seal", "inlet_valve", "outlet_valve"}
	st:         Stage
	twin:       Stage
	worker:     Entity_ID
	twinWorker: Entity_ID
	pump:       Entity_ID
	twinPump:   Entity_ID
	error:      string
	key:        cstring
	seal:       i64
	valve:      i64
	piston:     i64
	after:      i64
	grown:      i64
	v:          i64
	kept:       i32
	serviced:   i32
	later:      i32

	/* 400 hours used: dressing the cup undoes 60 per cent of its wear, a
	 * valve cleaned half; the piston's iron, nothing */
	pump   = test_serviced_pump(&st, "crank_pump", "pump 2", 400, 0, &worker)
	seal   = test_attrition_of(st, pump, "piston_seal")
	valve  = test_attrition_of(st, pump, "inlet_valve")
	piston = test_attrition_of(st, pump, "piston")
	bg_check(seal > 100000 && seal < 600000 && valve > 0 && piston > 0)
	bg_check(test_service_role(st, worker, pump, "piston_seal"))
	bg_check(test_attrition_of(st, pump, "piston_seal") == seal - seal * 60 / 100)
	bg_check(world_get_field(st.w, "Part.wear", test_part_in(st, pump, "piston_seal"), &v) &&
	         v == (seal - seal * 60 / 100) / 10000)
	bg_check(test_service_role(st, worker, pump, "inlet_valve"))
	bg_check(test_attrition_of(st, pump, "inlet_valve") == valve - valve * 50 / 100)
	test_service_role(st, worker, pump, "piston")
	bg_check(test_attrition_of(st, pump, "piston") == piston)

	/* serviced again at once, nothing more: what was undone was the wear since */
	seal = test_attrition_of(st, pump, "piston_seal")
	bg_check(test_service_role(st, worker, pump, "piston_seal"))
	bg_check(test_attrition_of(st, pump, "piston_seal") == seal)

	/* worked 100 hours, it wears as fast as its twin left alone (its quality
	 * is its own); serviced, 60 per cent of that is undone, no more */
	twinPump = test_serviced_pump(&twin, "crank_pump", "pump 2", 400, 0, &twinWorker)
	grown    = test_attrition_of(twin, twinPump, "piston_seal")
	test_serviced_work(twin, twinWorker, twinPump, 100)
	grown    = test_attrition_of(twin, twinPump, "piston_seal") - grown
	test_serviced_work(st, worker, pump, 100)
	bg_check(grown > 0 && test_attrition_of(st, pump, "piston_seal") == seal + grown)
	bg_check(test_service_role(st, worker, pump, "piston_seal"))
	after = seal + grown - grown * 60 / 100
	bg_check(test_attrition_of(st, pump, "piston_seal") == after)
	bg_check(after < test_attrition_of(twin, twinPump, "piston_seal"))

	/* saved and restored, it remembers being serviced */
	error = ""
	st.w  = test_restore(save(st.w, st.c, nil), world_content_build(st.w), &st.c, &error)
	st.s  = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	bg_check(st.w != nil && world_get_field(st.w, "Part.tended", test_part_in(st, pump, "piston_seal"), &v) && v == after)
	bg_check(test_service_role(st, worker, pump, "piston_seal"))
	bg_check(test_attrition_of(st, pump, "piston_seal") == after)

	/* worked dry 1000 hours, the cup is worn through: past servicing */
	pump = test_serviced_pump(&st, "crank_pump", "pump 2", 1000, 1000, &worker)
	bg_check(test_attrition_of(st, pump, "piston_seal") == 1000000)
	bg_check(!test_service_role(st, worker, pump, "piston_seal"))
	bg_check(test_attrition_of(st, pump, "piston_seal") == 1000000)

	/* serviced, a pump is less likely to fail: of 12 rickety pumps 900 hours
	 * used, worked 40 hours, none fails sooner with its parts serviced, and
	 * some later or not at all */
	kept = 0
	serviced = 0
	later = 0
	for k in 0 ..< i32(12) {
		key  = fmt.ctprintf("pump %d", k)
		pump = test_serviced_pump(&st, "rickety_pump", key, 900, 0, &worker)
		kept = test_serviced_work(st, worker, pump, 40)
		pump = test_serviced_pump(&st, "rickety_pump", key, 900, 0, &worker)
		for r in 0 ..< 4 do test_service_role(st, worker, pump, roles[r])
		serviced = test_serviced_work(st, worker, pump, 40)
		bg_check(kept == 0 || serviced == 0 || serviced >= kept)
		bg_check(kept != 0 || serviced == 0)
		later += (i32(kept != 0) if serviced == 0 else i32(serviced > kept))
	}
	bg_check(later > 0)
}


/* Agents keeping machines in order of their own accord, as inclined
 * (AGENCY.md §9's dispositions; LATENT_ASSEMBLY.md decision 8): each by an
 * opened crank pump 600 hours used, far apart, left to themselves for an
 * hour. The agent's diligence `diligent`; if `rewear`, its seal worn again
 * to 30 after the hour, and another hour. */
Diligence :: struct {
	agency:    ^Agency,
	agent:     Entity_ID,
	seal:      i64,             /* the seal's attrition, opened */
	sealAfter: i64,             /* after the first hour */
	sealLast:  i64,             /* after the second, if rewear */
	serviced:  i32,             /* parts it serviced */
}


test_diligence_run :: proc(diligent: i64, rewear: bool) -> Diligence {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	g:          ^Proposal_Group
	run:        Diligence
	pump:       Entity_ID
	wrench:     Entity_ID
	seal:       Entity_ID
	error:      string

	st.w       = test_world(157)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	run.agency = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(run.agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(run.agency))

	g         = proposal_group_group_with_phase(.System, "setup: a pump, used, and someone by it")
	pump      = proposal_group_create(g, "crank_pump", "pump 2", on_tile(5, 5, 0))
	run.agent = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench    = proposal_group_create(g, "wrench_250", "wrench", held_by(run.agent, 0))
	proposal_group_set_of_to(g, "Latent.used", whole(pump), 600 * 3600000)
	proposal_group_set_of_to(g, "Agent.diligent", whole(run.agent), diligent)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump      = proposal_group_id_for(g, pump)
	run.agent = proposal_group_id_for(g, run.agent)
	wrench    = proposal_group_id_for(g, wrench)
	error     = ""
	bg_check(perform(st.w, st.c, action_make("open_up", run.agent, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))
	bg_check(perform(st.w, st.c, action_make("open_up", run.agent, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2000))
	seal = test_part_in(st, pump, "piston_seal")
	world_get_field(st.w, "Part.attrition", seal, &run.seal)

	agency_control(run.agency, run.agent)
	scheduler_run_until(st.s, time_make(3600000))
	world_get_field(st.w, "Part.attrition", seal, &run.sealAfter)
	if rewear {
		g = proposal_group_group_with_phase(.System, "setup: the seal worn again")
		proposal_group_set_of_to(g, "Part.attrition", whole(seal), 300000)
		proposal_group_set_of_to(g, "Part.wear", whole(seal), 30)
		committer_submit(st.c, g)
		scheduler_run_until(st.s, time_make(2 * 3600000))
		world_get_field(st.w, "Part.attrition", seal, &run.sealLast)
	}
	for i: uint = 0; i < world_event_count(st.w); i += 1 {
		run.serviced += i32(string(world_event_at(st.w, i).kind) == "serviced" && world_event_at(st.w, i).other == run.agent)
	}
	return run
}


test_diligence :: proc() {
	lazy:  Diligence
	usual: Diligence
	keen:  Diligence

	/* seen worn a fifth of the way, the seal wants servicing; at the usual
	 * diligence that is worth doing with nothing better to do, and it is
	 * done: 60 per cent of its wear undone */
	usual = test_diligence_run(50, false)
	bg_check(usual.seal >= 200000 && usual.seal < 600000)
	bg_check(test_logged_by(usual.agency, usual.agent, "weighing service the worn part (R"))
	bg_check(test_logged_by(usual.agency, usual.agent, "+10 (-10, diligent +20) against nothing: switching"))
	bg_check(test_logged_by(usual.agency, usual.agent, "[service the worn part] service it: service_part R"))
	bg_check(usual.serviced >= 1 && usual.sealAfter == usual.seal - usual.seal * 60 / 100)

	/* a lazy one sees the same, and lets it be */
	lazy = test_diligence_run(10, false)
	bg_check(test_logged_by(lazy.agency, lazy.agent, "-6 (-10, diligent +4) against nothing: staying"))
	bg_check(lazy.serviced == 0 && lazy.sealAfter == lazy.seal)

	/* a diligent one keeps at it: the seal, then the valves, which look worn
	 * too; serviced, the seal stops looking worn; seen worn again, it is
	 * serviced again, once: 60 per cent of its wear since */
	keen = test_diligence_run(90, true)
	bg_check(keen.sealAfter < keen.seal)
	bg_check(keen.sealLast == 300000 - (300000 - keen.sealAfter) * 60 / 100 && keen.serviced == 4)
	lazy = test_diligence_run(10, true)
	bg_check(lazy.serviced == 0 && lazy.sealLast == 300000)
}


/* TERRAIN.md step 1: what each tile is. */
test_terrain_kind :: proc(w: ^World, x: i32, y: i32, z: i32) -> string {
	info: ^Terrain_Info

	info = terrain_kind_info(world_terrain(w), terrain_at(world_terrain(w), x, y, z))
	return ns_string(info.name) if info != nil else "-"
}


test_walk_once :: proc(st: Stage, who: Entity_ID, op: cstring) -> Location {
	error: string

	error = ""
	perform(st.w, st.c, action_make(op, who, NO_ENTITY, NO_ENTITY), 0, &error)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 2000))
	return world_location_of(st.w, who)
}


test_terrain :: proc() {
	st:     Stage
	g:      ^Proposal_Group
	worker: Entity_ID
	at:     Location
	error:  string
	text:   string
	t:      ^Terrain
	hash:   u64

	/* a world with no map: open floor, 32 x 32, one level; nothing past it */
	st.w = test_world(7)
	t    = world_terrain(st.w)
	bg_check(t != nil && terrain_kind_count(t) == 9 && test_terrain_kind(st.w, 0, 0, 0) == "open_floor")
	bg_check(world_tiles_wide(st.w) == 32 && world_tiles_high(st.w) == 32 && world_levels(st.w) == 1)
	bg_check(terrain_at(t, 32, 0, 0) == 0 && terrain_solid(t, -1, 0, 0) && !terrain_solid(t, 5, 5, 0))
	bg_check(terrain_changed(t, nil, 0) == 0)
	bg_check(!world_set_terrain_map(st.w, "no_such_map", &error) && ns_contains(error, "no map named"))

	/* the shed, drawn: its extent the drawing's; the legend's kinds; past
	 * a short row, the fill */
	st.w = test_world(7)
	error = ""
	bg_check(world_set_terrain_map(st.w, "shed_map", &error))
	t = world_terrain(st.w)
	bg_check(world_tiles_wide(st.w) == 16 && world_tiles_high(st.w) == 7 && world_levels(st.w) == 1)
	bg_check(test_terrain_kind(st.w, 0, 0, 0) == "stone_wall" &&
	         test_terrain_kind(st.w, 1, 1, 0) == "plank_floor" &&
	         test_terrain_kind(st.w, 11, 3, 0) == "doorway" &&
	         test_terrain_kind(st.w, 13, 3, 0) == "open_floor" &&
	         test_terrain_kind(st.w, 14, 0, 0) == "open_floor")
	bg_check(terrain_solid(t, 0, 0, 0) && terrain_opaque(t, 0, 0, 0) && terrain_floored(t, 1, 1, 0))
	bg_check(string(terrain_kind_info(t, terrain_at(t, 0, 0, 0)).look) == "wall.stone")

	/* walls stop a walker; the doorway lets it out */
	st.c = test_committer(st.w)
	st.s = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g      = proposal_group_group_with_phase(.System, "setup: a worker in the shed")
	worker = proposal_group_create(g, "worker", "worker", on_tile(1, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	at = test_walk_once(st, worker, "walk_west")
	bg_check(at.x == 1 && at.y == 3)
	for _ in 0 ..< 12 do at = test_walk_once(st, worker, "walk_east")
	bg_check(at.x == 13 && at.y == 3)
	/* nothing is put into a wall, either */
	g = proposal_group_group_with_phase(.System, "setup: a bucket in the wall")
	proposal_group_create(g, "bucket", "bucket", on_tile(0, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1))
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "is stone_wall, solid"))

	/* terrain changes by commitment: the doorway walled up, an event; a
	 * group rejected leaves terrain as it was */
	g = proposal_group_group_with_phase(.System, "setup: the doorway walled up")
	proposal_group_set_terrain(g, "stone_wall", on_tile(11, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1))
	bg_check(proposal_group_applied(g) && test_terrain_kind(st.w, 11, 3, 0) == "stone_wall")
	bg_check(string(world_event_at(st.w, world_event_count(st.w) - 1).kind) == "terrain" &&
	         string(world_event_at(st.w, world_event_count(st.w) - 1).detail) == "stone_wall")
	g = proposal_group_group_with_phase(.System, "setup: opened, and a kind that isn't")
	proposal_group_set_terrain(g, "doorway", on_tile(11, 3, 0))
	proposal_group_set_terrain(g, "marble", on_tile(10, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1))
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "no terrain kind named marble"))
	bg_check(test_terrain_kind(st.w, 11, 3, 0) == "stone_wall")
	at = test_walk_once(st, worker, "walk_west")
	at = test_walk_once(st, worker, "walk_west")
	bg_check(at.x == 12)

	/* saved: the map, and only the chunk that changed; restored, the same */
	hash = world_state_hash(st.w)
	text = save(st.w, st.c, nil)
	bg_check(ns_contains(text, "terrain shed_map\n"))
	bg_check(len(ns_components_separated(text, "terrain-chunk ")) == 2 &&
	         ns_contains(text, "terrain-chunk 0 0 0 "))
	error = ""
	st.w = test_restore(text, world_content_build(st.w), &st.c, &error)
	bg_check(st.w != nil && world_state_hash(st.w) == hash && test_terrain_kind(st.w, 11, 3, 0) == "stone_wall" &&
	         world_tiles_wide(st.w) == 16)
	/* set back as the map has it, the chunk is no longer a change */
	st.s = autorelease(scheduler_init_with_world(st.w, st.c))
	g = proposal_group_group_with_phase(.System, "setup: the doorway again")
	proposal_group_set_terrain(g, "doorway", on_tile(11, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1))
	bg_check(proposal_group_applied(g) && terrain_changed(world_terrain(st.w), nil, 0) == 0)

	/* a map is drawn only before a tile holds a stock */
	st.w = test_world(7)
	world_set_water(st.w, 100, 2, 2, 0)
	bg_check(!world_set_terrain_map(st.w, "shed_map", &error) &&
	         ns_contains(error, "before any tile holds a stock"))
}


/* TERRAIN.md step 2: sight stops at what is opaque, and what an agent has
 * seen of the terrain is a bit per tile, with what it recalls of changes it
 * missed. In the shed (shed_map), a worker inside by the east wall. */
test_believed_kind :: proc(w: ^World, store: ^Knowledge_Store, x: i32, y: i32) -> string {
	info: ^Terrain_Info

	info = terrain_kind_info(world_terrain(w), knowledge_store_believed_terrain_at_x(store, x, y, 0))
	return ns_string(info.name) if info != nil else "-"
}


test_sight_and_memory :: proc() {
	st:        Stage
	knowledge: ^Knowledge
	store:     ^Knowledge_Store
	g:         ^Proposal_Group
	worker:    Entity_ID
	past:      Entity_ID
	behind:    Entity_ID
	chunks:    [^]Seen_Chunk
	error:     string
	text:      string

	st.w      = test_world(7)
	error     = ""
	bg_check(world_set_terrain_map(st.w, "shed_map", &error))
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: a worker by the wall, buckets outside")
	worker = proposal_group_create(g, "worker", "worker", on_tile(9, 2, 0))
	past   = proposal_group_create(g, "bucket", "past the doorway", on_tile(12, 3, 0))
	behind = proposal_group_create(g, "bucket", "behind the wall", on_tile(12, 1, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1000))
	worker = proposal_group_id_for(g, worker)
	past   = proposal_group_id_for(g, past)
	behind = proposal_group_id_for(g, behind)
	store  = knowledge_store_of(knowledge, worker)

	/* through the doorway it sees the bucket past it; the one behind the
	 * wall, three tiles off, it doesn't */
	bg_check(test_referent_of(store, past) != 0)
	bg_check(test_referent_of(store, behind) == 0)
	bg_check(knowledge_in_sight(knowledge, on_tile(12, 3, 0), on_tile(9, 2, 0)) &&
	         !knowledge_in_sight(knowledge, on_tile(12, 1, 0), on_tile(9, 2, 0)) &&
	         !knowledge_in_sight(knowledge, on_tile(9, 2, 0), on_tile(12, 1, 0)))
	/* the wall it sees, and believes a wall; what is behind, it hasn't seen */
	bg_check(knowledge_store_has_seen_x(store, 11, 2, 0) && test_believed_kind(st.w, store, 11, 2) == "stone_wall")
	bg_check(!knowledge_store_has_seen_x(store, 12, 1, 0) && test_believed_kind(st.w, store, 12, 1) == "-")
	/* last seen when it last looked, which is not at every boundary: when
	 * something happened, or it learnt something (REALITY.md decision 7) */
	bg_check(knowledge_store_chunk_seen_at_x(store, 11, 2, 0) == store.perceivedAt && store.perceivedAt > 0)
	/* the whole shed is one chunk: 128 bytes of bits, not a copy of the map */
	bg_check(knowledge_store_seen_chunks(store, &chunks) == 1)
	free(chunks)

	/* away from the doorway, the doorway is walled up: it believes what it
	 * saw, a doorway, and says so after a save */
	for _ in 0 ..< 7 do test_walk_once(st, worker, "walk_west")
	bg_check(world_location_of(st.w, worker).x == 2)
	g = proposal_group_group_with_phase(.System, "setup: the doorway walled up")
	proposal_group_set_terrain(g, "stone_wall", on_tile(11, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	bg_check(test_believed_kind(st.w, store, 11, 3) == "doorway" && knowledge_store_recall_count(store) == 1)
	text = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge)})
	{
		recall: string

		recall = fmt.tprintf("recall %d 11 3 0 doorway", u64(worker))
		bg_check(ns_contains(text, recall))
	}
	{
		again: ^Knowledge
		c2:    ^Committer
		w2:    ^World
		s2:    ^Knowledge_Store

		w2    = test_restore(text, world_content_build(st.w), &c2, &error)
		again = autorelease(knowledge_init_with_world(w2))
		saved := knowledge_as_saved_system(again)
		saved.restore_saved_state(saved.data, saved_domain_state(text, "knowledge"))
		s2 = knowledge_store_of(again, worker)
		bg_check(test_believed_kind(w2, s2, 11, 3) == "doorway" && knowledge_store_has_seen_x(s2, 11, 2, 0) &&
		         !knowledge_store_has_seen_x(s2, 12, 1, 0) &&
		         knowledge_store_chunk_seen_at_x(s2, 5, 5, 0) == knowledge_store_chunk_seen_at_x(store, 5, 5, 0))
	}

	/* back where it can see it: a wall, and nothing recalled */
	for _ in 0 ..< 7 do test_walk_once(st, worker, "walk_east")
	bg_check(test_believed_kind(st.w, store, 11, 3) == "stone_wall" && knowledge_store_recall_count(store) == 0)

	/* played, the map shows the walls it sees, the bucket through the
	 * doorway, and nothing behind the wall */
	{
		h: u64

		text = test_session("shed", []string{"look"}, &h)
		bg_check(ns_contains(text, "      #######     \n" +
		                           "      ......#     \n" +
		                           "      ....@.#     \n" +
		                           "      .......w.   \n" +
		                           "      ......#..   \n" +
		                           "      ......# .   \n"))
	}
}


/* TERRAIN.md step 3: rooms from terrain. In rooms_map, the room, the back
 * room and the corridor are rooms; walls and doorways are in none, and so
 * is the ground outdoors, open to the world's edge. */
test_rooms :: proc() {
	st:       Stage
	g:        ^Proposal_Group
	room:     Entity_ID
	back:     Entity_ID
	corridor: Entity_ID
	door:     Entity_ID
	o:        [8]Air_Opening
	t:        ^Terrain
	cells:    [4][3]i32
	x:        i32
	y:        i32
	z:        i32
	r:        u32

	st.w = test_world(7)
	bg_check(world_set_terrain_map(st.w, "rooms_map", nil))
	bg_check(world_tiles_wide(st.w) == 32 && world_tiles_high(st.w) == 32)
	t = world_terrain(st.w)
	bg_check(terrain_room_at(t, 1, 1, 0) != 0 && terrain_room_at(t, 1, 1, 0) == terrain_room_at(t, 4, 5, 0))
	bg_check(terrain_room_at(t, 6, 1, 0) != 0 && terrain_room_at(t, 6, 1, 0) != terrain_room_at(t, 1, 1, 0))
	bg_check(terrain_room_at(t, 1, 7, 0) != 0 && terrain_room_at(t, 1, 7, 0) == terrain_room_at(t, 20, 8, 0) &&
	         terrain_room_at(t, 1, 7, 0) != terrain_room_at(t, 1, 1, 0))
	bg_check(terrain_room_at(t, 4, 6, 0) == 0 && terrain_room_at(t, 0, 7, 0) == 0 && terrain_room_at(t, 32, 0, 0) == 0)
	bg_check(terrain_room_at(t, 15, 15, 0) == 0 && terrain_room_at(t, 11, 0, 0) == 0)

	/* a room's size, its first cell, and the doorways at its side */
	r = terrain_room_at(t, 3, 4, 0)
	bg_check(terrain_room_size(t, r) == 20 && terrain_room_corner(t, r, &x, &y, &z) && x == 1 && y == 1 && z == 0)
	bg_check(terrain_room_doorways(t, r, raw_data(cells[:]), 4) == 1 && cells[0][0] == 4 && cells[0][1] == 6)
	r = terrain_room_at(t, 12, 8, 0)
	bg_check(terrain_room_doorways(t, r, raw_data(cells[:]), 4) == 2 && cells[0][0] == 4 && cells[1][0] == 8)

	/* the air over a tile is the region whose tile is in its room */
	st.c = test_committer(st.w)
	st.s = autorelease(scheduler_init_with_world(st.w, st.c))
	g        = proposal_group_group_with_phase(.System, "setup: the air")
	room     = proposal_group_create(g, "room_air", "the room's air", location_make_none())
	back     = proposal_group_create(g, "back_room", "the back room's air", location_make_none())
	corridor = proposal_group_create(g, "corridor", "the corridor", location_make_none())
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	room     = proposal_group_id_for(g, room)
	back     = proposal_group_id_for(g, back)
	corridor = proposal_group_id_for(g, corridor)
	bg_check(world_air_region_at(st.w, on_tile(3, 4, 0)) == room && world_air_region_at(st.w, on_tile(9, 5, 0)) == back &&
	         world_air_region_at(st.w, on_tile(12, 8, 0)) == corridor)
	bg_check(world_air_region_at(st.w, on_tile(4, 6, 0)) == NO_ENTITY && world_air_region_at(st.w, on_tile(15, 15, 0)) == NO_ENTITY)

	/* the ways air opens, from the doorways: the room's to the corridor,
	 * passing the doorway's draught; the corridor's to both rooms */
	bg_check(world_air_openings_of(st.w, room, raw_data(o[:]), 8) == 1 && o[0].at.x == 4 && o[0].at.y == 6 &&
	         o[0].beyond == corridor && o[0].door == NO_ENTITY && o[0].flow == 200 && o[0].open)
	bg_check(world_air_openings_of(st.w, corridor, raw_data(o[:]), 8) == 2 && o[0].beyond == room && o[1].beyond == back)
	/* a door in the doorway: shut, it passes nothing; ajar, its width */
	g    = proposal_group_group_with_phase(.System, "setup: the room's door")
	door = proposal_group_create(g, "room_door", "the room's door", on_tile(4, 6, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2))
	door = proposal_group_id_for(g, door)
	bg_check(world_air_openings_of(st.w, room, raw_data(o[:]), 8) == 1 && o[0].door == door && o[0].flow == 0 && !o[0].open)
	bg_check(world_set_field_of_value(st.w, "Door.ajar", door, 1))
	bg_check(world_air_openings_of(st.w, room, raw_data(o[:]), 8) == 1 && o[0].flow == 5000 && o[0].open)
	/* the back room's doorway, to the corridor */
	bg_check(world_air_openings_of(st.w, back, raw_data(o[:]), 8) == 1 && o[0].beyond == corridor && o[0].at.x == 8)
}


/* The stocks of a region of air: oxygen, carbon dioxide, heat, total. */
test_air_stocks :: proc(w: ^World, air: Entity_ID, v: [^]i64) {
	if !world_get_field(w, "GasStore.oxygen", air, &v[0]) || !world_get_field(w, "GasStore.dioxide", air, &v[1]) ||
	   !world_get_field(w, "GasStore.gasHeat", air, &v[2]) || !world_get_field(w, "GasStore.total", air, &v[3]) {
		mem.zero(v, 4 * size_of(i64))
	}
}


/* TERRAIN.md step 3: air follows terrain. A wall knocked through joins two
 * rooms' air into the first's, every stock kept; one built back parts it
 * by tiles; a group refused undoes both; a hole to the outdoors leaves the
 * air in no room, and it airs out. The atmosphere balances throughout. */
test_air_follows_terrain :: proc() {
	st:       Stage
	air:      ^Atmosphere
	copy_:    ^Atmosphere
	g:        ^Proposal_Group
	room:     Entity_ID
	back:     Entity_ID
	parted:   Entity_ID
	doors:    [2]Entity_ID
	a:        [4]i64
	b:        [4]i64
	sum:      [4]i64
	balanced: bool

	st.w = test_world(11)
	bg_check(world_set_terrain_map(st.w, "rooms_map", nil))
	st.c = test_committer(st.w)
	air  = autorelease(atmosphere_init_with_world(st.w))
	st.s = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_add_domain(st.s, atmosphere_as_domain(air))
	g    = proposal_group_group_with_phase(.System, "setup: two rooms")
	room = proposal_group_create(g, "room_air", "the room's air", location_make_none())
	back = proposal_group_create(g, "back_room", "the back room's air", location_make_none())
	doors[0] = proposal_group_create(g, "room_door", "the room's door", on_tile(4, 6, 0))
	doors[1] = proposal_group_create(g, "room_door", "the back room's door", on_tile(8, 6, 0))
	proposal_group_set_of_to(g, "GasStore.dioxide", whole(room), 4800)        /* stale */
	proposal_group_set_of_to(g, "Door.ajar", whole(doors[0]), 1)
	proposal_group_set_of_to(g, "Door.ajar", whole(doors[1]), 1)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	room     = proposal_group_id_for(g, room)
	back     = proposal_group_id_for(g, back)
	doors[0] = proposal_group_id_for(g, doors[0])
	doors[1] = proposal_group_id_for(g, doors[1])
	balanced = true
	for scheduler_step_until(st.s, time_make(590000)) do balanced = balanced && atmosphere_balanced(air)
	bg_check(atmosphere_steps(air) > 0)
	/* the doors shut, the air is still: what it holds is what joins */
	g = proposal_group_group_with_phase(.System, "the doors shut")
	proposal_group_set_of_to(g, "Door.ajar", whole(doors[0]), 0)
	proposal_group_set_of_to(g, "Door.ajar", whole(doors[1]), 0)
	committer_submit(st.c, g)
	for scheduler_step_until(st.s, time_make(600000)) do balanced = balanced && atmosphere_balanced(air)
	test_air_stocks(st.w, room, raw_data(a[:]))
	test_air_stocks(st.w, back, raw_data(b[:]))
	for q in 0 ..< 4 do sum[q] = a[q] + b[q]

	/* the wall between knocked through: one air, the room's, all of both */
	g = proposal_group_group_with_phase(.System, "the wall between knocked through")
	proposal_group_set_terrain(g, "plank_floor", on_tile(5, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(600001))
	test_air_stocks(st.w, room, raw_data(a[:]))
	bg_check(proposal_group_applied(g) && !world_is_live(st.w, back) && world_resolve(st.w, back) == room)
	bg_check(world_air_region_at(st.w, on_tile(9, 5, 0)) == room && world_air_region_at(st.w, on_tile(5, 3, 0)) == room)
	bg_check(a[0] == sum[0] && a[1] == sum[1] && a[2] == sum[2] && a[3] == 4000000)
	for scheduler_step_until(st.s, time_make(1200000)) do balanced = balanced && atmosphere_balanced(air)

	/* built back: the side cut off gets its share, by tiles, half */
	test_air_stocks(st.w, room, raw_data(sum[:]))
	g = proposal_group_group_with_phase(.System, "the wall built back")
	proposal_group_set_terrain(g, "stone_wall", on_tile(5, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1200001))
	parted = world_air_region_at(st.w, on_tile(9, 5, 0))
	bg_check(proposal_group_applied(g) && parted != NO_ENTITY && parted != room && world_air_region_at(st.w, on_tile(2, 2, 0)) == room)
	test_air_stocks(st.w, room, raw_data(a[:]))
	test_air_stocks(st.w, parted, raw_data(b[:]))
	bg_check(b[3] == 2000000 && a[3] == 2000000 && b[0] == sum[0] / 2)
	for q in 0 ..< 4 do bg_check(a[q] + b[q] == sum[q])
	/* the doors opened: the two airs move again, each its own way */
	g = proposal_group_group_with_phase(.System, "the doors opened")
	proposal_group_set_of_to(g, "Door.ajar", whole(doors[0]), 1)
	proposal_group_set_of_to(g, "Door.ajar", whole(doors[1]), 1)
	committer_submit(st.c, g)
	for scheduler_step_until(st.s, time_make(1800000)) do balanced = balanced && atmosphere_balanced(air)
	airs := atmosphere_as_domain(air)
	bg_check(airs.is_active(airs.data))
	/* saved mid-flow, its links' carries with it */
	copy_ = autorelease(atmosphere_init_with_world(st.w))
	copies := atmosphere_as_domain(copy_)
	copies.restore_saved_state(copies.data, airs.saved_state(airs.data))
	bg_check(slice.equal(copies.saved_state(copies.data), airs.saved_state(airs.data)) &&
	         ns_contains(strings.join(airs.saved_state(airs.data), "\n", context.temp_allocator), "link "))

	/* a group refused undoes the join with it */
	g = proposal_group_group_with_phase(.System, "a knock refused")
	proposal_group_set_terrain(g, "plank_floor", on_tile(5, 3, 0))
	proposal_group_set_of_to(g, "Door.ajar", whole(room), 1)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1800001))
	bg_check(!proposal_group_applied(g) && world_is_live(st.w, parted) && world_air_region_at(st.w, on_tile(9, 5, 0)) == parted &&
	         !terrain_roomy(world_terrain(st.w), 5, 3, 0))

	/* a hole to the outdoors: the parted air is in no room, and airs out */
	g = proposal_group_group_with_phase(.System, "a hole in the back wall")
	proposal_group_set_terrain(g, "plank_floor", on_tile(7, 0, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1800002))
	bg_check(proposal_group_applied(g) && world_room_of_air(st.w, parted) == 0 && world_air_region_at(st.w, on_tile(9, 5, 0)) == NO_ENTITY)
	for scheduler_step_until(st.s, time_make(3600000)) do balanced = balanced && atmosphere_balanced(air)
	test_air_stocks(st.w, parted, raw_data(b[:]))
	bg_check(b[1] >= 800 && b[1] <= 900)       /* the outdoors' 0.04%, within the 100 mmol it rests at */
	bg_check(balanced)
}


/* Rooms in a large world (TERRAIN.md step 3): a 1024 by 1024 plain of open
 * floor is in no room, found by a flood stopped at BG_ROOM_MAX; a hut walled
 * on it is a room, found when its last wall closes it; one too large to be
 * a room is open ground. */
test_rooms_at_scale :: proc() {
	w:     ^World
	t:     ^Terrain
	why:   string
	wall:  Terrain_Kind
	floor: Terrain_Kind

	w = test_world(13)
	t = terrain_new(world_tri(w), 1024, 1024, 1, "open_floor", &why)
	bg_check(t != nil)
	if t == nil do return
	wall  = terrain_kind_named(t, "stone_wall")
	floor = terrain_kind_named(t, "open_floor")
	bg_check(terrain_room_at(t, 500, 500, 0) == 0 && terrain_room_at(t, 10, 1000, 0) == 0)

	/* a hut, 3 by 3 inside, walled one wall at a time */
	for i: i32 = 0; i < 5; i += 1 {
		terrain_set(t, 499 + i, 499, 0, wall)
		terrain_set(t, 499 + i, 503, 0, wall)
	}
	terrain_set(t, 499, 500, 0, wall)
	terrain_set(t, 499, 501, 0, wall)
	terrain_set(t, 499, 502, 0, wall)
	terrain_set(t, 503, 500, 0, wall)
	terrain_set(t, 503, 501, 0, wall)
	bg_check(terrain_room_at(t, 501, 501, 0) == 0)           /* one wall short: open */
	terrain_set(t, 503, 502, 0, wall)
	bg_check(terrain_room_at(t, 501, 501, 0) != 0 && terrain_room_size(t, terrain_room_at(t, 501, 501, 0)) == 9)
	bg_check(terrain_room_at(t, 500, 500, 0) == terrain_room_at(t, 502, 502, 0) && terrain_room_at(t, 498, 498, 0) == 0)
	/* a wall knocked out: open again */
	terrain_set(t, 503, 501, 0, floor)
	bg_check(terrain_room_at(t, 501, 501, 0) == 0)

	/* a hall 70 by 70 inside is more than a room can be: open */
	for i: i32 = 0; i < 72; i += 1 {
		terrain_set(t, 100 + i, 100, 0, wall)
		terrain_set(t, 100 + i, 171, 0, wall)
		terrain_set(t, 100, 100 + i, 0, wall)
		terrain_set(t, 171, 100 + i, 0, wall)
	}
	bg_check(terrain_room_at(t, 130, 130, 0) == 0)
	/* parted in two by a wall down it, each side is a room */
	for i: i32 = 101; i < 171; i += 1 do terrain_set(t, 135, i, 0, wall)
	bg_check(terrain_room_at(t, 130, 130, 0) != 0 && terrain_room_at(t, 140, 130, 0) != 0 &&
	         terrain_room_at(t, 130, 130, 0) != terrain_room_at(t, 140, 130, 0) &&
	         terrain_room_size(t, terrain_room_at(t, 130, 130, 0)) == 34 * 70)
	terrain_free(t)
}


/* DOMAIN_SIMULATION.md Scenario 2's drain: the pump `key` under its header
 * tank (100 L), opened, and its piston taken out: through a leaky outlet
 * valve the tank drains onto the floor; an hour on, how much left the tank,
 * and whether the water is the same in all, every boundary. */
test_pump_drain :: proc(key: cstring, conserved: ^bool, leaking: ^bool) -> i64 {
	st:     Stage
	fluid:  ^Fluid_Domain
	g:      ^Proposal_Group
	pump:   Entity_ID
	tank:   Entity_ID
	worker: Entity_ID
	wrench: Entity_ID
	piston: Entity_ID
	parts:  ^Store
	error:  string
	v:      i64
	total:  i64
	sum:    i64

	st.w   = test_world(157)       /* as pump_open: the same units, the same culprits */
	st.c   = test_committer(st.w)
	fluid  = autorelease(fluid_domain_init_with_world(st.w))
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_add_domain(st.s, fluid_domain_as_domain(fluid))
	g      = proposal_group_group_with_phase(.System, "setup: the pump house")
	pump   = proposal_group_create(g, "crank_pump", key, on_tile(5, 5, 0))
	tank   = proposal_group_create(g, "header_tank", "the header tank", on_tile(5, 5, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	proposal_group_set_of_to(g, "Latent.riser", whole(pump), i64(tank))
	proposal_group_set_of_to_text(g, "Latent.failure", whole(pump), "flow_loss")
	proposal_group_set_of_to(g, "Latent.failedAt", whole(pump), 0)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump   = proposal_group_id_for(g, pump)
	tank   = proposal_group_id_for(g, tank)
	worker = proposal_group_id_for(g, worker)
	wrench = proposal_group_id_for(g, wrench)
	error  = ""
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2000))
	piston = NO_ENTITY
	parts  = world_store_for_kind(st.w, world_kind_named(st.w, "Part"))
	for i: uint = 0; i < store_count(parts); i += 1 {
		if string(world_info(st.w, store_entity_at_index(parts, i)).blueprint) == "piston" do piston = store_entity_at_index(parts, i)
	}
	bg_check(perform(st.w, st.c, action_make("take", worker, piston, NO_ENTITY), 0, &error) != nil)
	conserved^ = true
	total      = 100000
	for world_time(st.w).ms < 3600000 {
		if !scheduler_step_until(st.s, time_make(3600000)) do scheduler_run_until(st.s, time_make(3600000))
		sum = world_total_tile_water(st.w) + fluid_domain_checked_out_water(fluid)
		if !world_is_checked_out(st.w, tank) && world_get_field(st.w, "WaterStore.water", tank, &v) do sum += v
		conserved^ = conserved^ && sum == total
	}
	leaking^ = world_get_field(st.w, "Latent.leaking", pump, &v) && v != 0
	bg_check(world_location_of(st.w, piston).form == .Held_By)
	/* what left the tank is on the floor (checked out by the domain, or in) */
	world_get_field(st.w, "WaterStore.water", tank, &v)
	return total - v
}


/* Check 3's heat: the warm pump (305 K, 18 kJ/K) opened and its piston
 * (1.8 kJ/K) taken out: the piston leaves with its share of the heat, by
 * heat capacity; the total is the same, and both are at 305 K. */
/* The same, with the thermal domain running (the heat slice's "Not yet"):
 * the pump in the yard, cooling, the domain stepping. The piston's share,
 * moved by the reaction between steps, reaches the domain, which loads its
 * bodies from their records: once out it takes part, at the pump's
 * temperature, and every joule is accounted for, then and an hour on. */
test_pump_heat_running :: proc() {
	st:      Stage
	thermal: ^Thermal
	g:       ^Proposal_Group
	pump:    Entity_ID
	worker:  Entity_ID
	wrench:  Entity_ID
	piston:  Entity_ID
	parts:   ^Store
	error:   string

	st.w    = test_world(167)
	st.c    = test_committer(st.w)
	st.s    = autorelease(scheduler_init_with_world(st.w, st.c))
	thermal = autorelease(thermal_init_with_world(st.w))
	scheduler_add_domain(st.s, thermal_as_domain(thermal))
	g      = proposal_group_group_with_phase(.System, "setup: a warm pump")
	/* out in the yard: it cools toward the outdoors, the domain stepping */
	pump   = proposal_group_create(g, "yard_pump", "pump 1", on_tile(5, 5, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump   = proposal_group_id_for(g, pump)
	worker = proposal_group_id_for(g, worker)
	wrench = proposal_group_id_for(g, wrench)
	error  = ""
	scheduler_run_until(st.s, time_make(600000))
	bg_check(thermal_steps(thermal) > 0 && thermal_temperature_of(thermal, pump) < 305000)
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	piston = NO_ENTITY
	parts  = world_store_for_kind(st.w, world_kind_named(st.w, "Part"))
	for i: uint = 0; i < store_count(parts); i += 1 {
		if string(world_info(st.w, store_entity_at_index(parts, i)).blueprint) == "piston" do piston = store_entity_at_index(parts, i)
	}
	bg_check(piston != NO_ENTITY && !thermal_participates(thermal, piston))
	bg_check(perform(st.w, st.c, action_make("take", worker, piston, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	bg_check(thermal_participates(thermal, piston) && thermal_participates(thermal, pump))
	/* taken out at the pump's temperature; the pump has cooled on for the
	 * second since (some 250 W to the outdoors, 15 mK), the piston not */
	bg_check(thermal_temperature_of(thermal, piston) >= thermal_temperature_of(thermal, pump) &&
	         thermal_temperature_of(thermal, piston) - thermal_temperature_of(thermal, pump) <= 20)
	bg_check(thermal_balanced(thermal))
	/* and on, the domain stepping with both: the pump cools on, the piston
	 * (no outdoors of its own) keeps what it took */
	scheduler_run_until(st.s, time_make(3600000))
	bg_check(thermal_balanced(thermal))
	bg_check(thermal_temperature_of(thermal, pump) < thermal_temperature_of(thermal, piston))
}


test_pump_heat :: proc() {
	st:         Stage
	g:          ^Proposal_Group
	pump:       Entity_ID
	worker:     Entity_ID
	wrench:     Entity_ID
	piston:     Entity_ID
	parts:      ^Store
	error:      string
	pumpHeat:   i64
	pumpCap:    i64
	pistonHeat: i64
	pistonCap:  i64
	v:          i64

	st.w   = test_world(167)
	st.c   = test_committer(st.w)
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	g      = proposal_group_group_with_phase(.System, "setup: a warm pump")
	pump   = proposal_group_create(g, "warm_pump", "pump 1", on_tile(5, 5, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump   = proposal_group_id_for(g, pump)
	worker = proposal_group_id_for(g, worker)
	wrench = proposal_group_id_for(g, wrench)
	error  = ""
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2000))
	piston = NO_ENTITY
	parts  = world_store_for_kind(st.w, world_kind_named(st.w, "Part"))
	for i: uint = 0; i < store_count(parts); i += 1 {
		if string(world_info(st.w, store_entity_at_index(parts, i)).blueprint) == "piston" do piston = store_entity_at_index(parts, i)
	}
	/* inside, it has none of its own: its heat is the pump's */
	bg_check(piston != NO_ENTITY && world_get_field(st.w, "ThermalBody.heat", piston, &v) && v == 0)
	bg_check(perform(st.w, st.c, action_make("take", worker, piston, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(3000))
	world_get_field(st.w, "ThermalBody.heat", pump, &pumpHeat)
	world_get_field(st.w, "ThermalBody.heatCapacity", pump, &pumpCap)
	world_get_field(st.w, "ThermalBody.heat", piston, &pistonHeat)
	world_get_field(st.w, "ThermalBody.heatCapacity", piston, &pistonCap)
	bg_check(pumpHeat + pistonHeat == 5490000)
	bg_check(pumpCap == 16200 && pistonCap == 1800)
	bg_check(pumpHeat * 1000 / pumpCap == 305000 && pistonHeat * 1000 / pistonCap == 305000)
	bg_check(world_get_field(st.w, "Part.detached", piston, &v) && v == 1)
}


/* ACTIONS.md Scenario 3's steps 3 and 4, and check 2: the worker, with a
 * wrench and a spare leather cup, is to mend the pump `key`. Nothing is bound
 * to the worn part until opening shows one: it opens the pump, a level at a
 * time, sees the worn part, and replaces it. The agency, for its log. */
test_mend_run :: proc(key: cstring, world: ^^World, spare: ^Entity_ID) -> ^Agency {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	pump:       Entity_ID
	worker:     Entity_ID

	st.w       = test_world(157)       /* as pump_open: the same units, the same culprits */
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g      = proposal_group_group_with_phase(.System, "setup: the pump house")
	pump   = proposal_group_create(g, "crank_pump", key, on_tile(5, 5, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	spare^ = proposal_group_create(g, "leather_cup", "a spare leather cup", held_by(worker, 1))
	proposal_group_set_of_to_text(g, "Part.fits", whole(spare^), "piston_seal")
	proposal_group_set_of_to_text(g, "Latent.failure", whole(pump), "flow_loss")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	spare^ = proposal_group_id_for(g, spare^)
	bg_check(agency_commit(agency, worker, "mend_pump"))
	scheduler_run_until(st.s, time_make(60000))
	world^ = st.w
	return agency
}


/* COMPONENTS.md Scenario 3, the pump from the component side. The miller
 * owns the hand pump; a flow loss has left it at 20%. The player opens it,
 * takes the piston out (itself an assembly, with the seal inside), opens it,
 * cuts a strip from its own hide, shapes it into a seal, replaces the worn
 * one, and puts the piston back. `inPlace`: the piston opened before it is
 * taken out. The new seal's wear, for reveal-order independence. */
test_component_pump_ :: proc(inPlace: bool, check: bool) -> i64 {
	st:       Stage
	thermal:  ^Thermal
	g:        ^Proposal_Group
	pump:     Entity_ID
	worker:   Entity_ID
	miller:   Entity_ID
	wrench:   Entity_ID
	hide:     Entity_ID
	claim:    Entity_ID
	mine:     Entity_ID
	piston:   Entity_ID
	seal:     Entity_ID
	strip:    Entity_ID
	source:   Entity_ID
	parts:    ^Store
	error:    string
	v:        i64
	sealWear: i64
	masses:   i64

	st.w    = test_world(179)
	st.c    = test_committer(st.w)
	thermal = autorelease(thermal_init_with_world(st.w))
	st.s    = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	scheduler_add_domain(st.s, thermal_as_domain(thermal))
	g      = proposal_group_group_with_phase(.System, "setup: the miller's pump")
	pump   = proposal_group_create(g, "hand_pump", "the miller's pump", on_tile(5, 5, 0))
	miller = proposal_group_create(g, "smith", "the miller", on_tile(20, 20, 0))
	worker = proposal_group_create(g, "worker", "the player", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	hide   = proposal_group_create(g, "hide", "the player's hide", on_tile(4, 5, 0))
	claim  = proposal_group_create(g, "ownership", "the miller's claim", location_make_none())
	proposal_group_relate(g, .Claimant, whole(claim), whole(miller))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(pump))
	mine   = proposal_group_create(g, "ownership", "the player's claim", location_make_none())
	proposal_group_relate(g, .Claimant, whole(mine), whole(worker))
	proposal_group_relate(g, .Claim_Subject, whole(mine), whole(hide))
	proposal_group_set_of_to_text(g, "Latent.failure", whole(pump), "flow_loss")
	proposal_group_set_of_to(g, "Pump.flow", whole(pump), 20)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump   = proposal_group_id_for(g, pump)
	miller = proposal_group_id_for(g, miller)
	worker = proposal_group_id_for(g, worker)
	wrench = proposal_group_id_for(g, wrench)
	hide   = proposal_group_id_for(g, hide)
	claim  = proposal_group_id_for(g, claim)
	mine   = proposal_group_id_for(g, mine)
	error  = ""

	/* 1: opening the cover reveals level 1, carved from the pump */
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))
	piston = NO_ENTITY
	parts  = world_store_for_kind(st.w, world_kind_named(st.w, "Part"))
	for i: uint = 0; i < store_count(parts); i += 1 {
		if string(world_info(st.w, store_entity_at_index(parts, i)).blueprint) == "nested_piston" do piston = store_entity_at_index(parts, i)
	}
	masses = 0
	world_get_field(st.w, "Body.mass", pump, &masses)
	for i: uint = 0; i < store_count(parts); i += 1 {
		if world_get_field(st.w, "Body.mass", store_entity_at_index(parts, i), &v) do masses += v
	}
	if check {
		bg_check(piston != NO_ENTITY && world_location_of(st.w, piston).form == .Part_Of && store_count(parts) == 5)
		bg_check(masses == 40000)
		/* the piston, the culprit, takes the failure on; it isn't worn itself */
		bg_check(string(world_text_field(st.w, "Latent.failure", piston)) == "flow_loss")
		bg_check(world_get_field(st.w, "Part.wear", piston, &v) && v < 60)
		/* 4: inspection alone changes nothing aggregate */
		bg_check(world_get_field(st.w, "Pump.flow", pump, &v) && v == 20)
		/* 6: inside, the piston joins no domain */
		bg_check(!thermal_participates(thermal, piston))
	}

	/* 2: the piston out; its nested level opened, in place or out */
	if inPlace {
		bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, piston), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(2000))
	}
	bg_check(perform(st.w, st.c, action_make("take", worker, piston, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2500))
	if !inPlace {
		bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, piston), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(3000))
	}
	if check do bg_check(world_location_of(st.w, piston).form == .Held_By && thermal_participates(thermal, piston))
	seal = NO_ENTITY
	for i: uint = 0; i < store_count(parts); i += 1 {
		if world_location_of(st.w, store_entity_at_index(parts, i)).form == .Part_Of &&
		   world_location_of(st.w, store_entity_at_index(parts, i)).place == piston {
			seal = store_entity_at_index(parts, i)
		}
	}
	sealWear = -1
	world_get_field(st.w, "Part.wear", seal, &sealWear)

	/* 3: a strip cut from the hide; shaped into a seal (the wrench and the
	 * piston set down, for hands) */
	g = proposal_group_group_with_phase(.System, "setup: hands free for the hide")
	proposal_group_move_to(g, whole(wrench), on_tile(4, 5, 0))
	proposal_group_move_to(g, whole(hide), held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(4000))
	bg_check(perform(st.w, st.c, action_make("cut_strip", worker, hide, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(5000))
	strip = NO_ENTITY
	for i: uint = 0; i < store_count(parts); i += 1 {
		if string(world_info(st.w, store_entity_at_index(parts, i)).blueprint) == "leather_strip" do strip = store_entity_at_index(parts, i)
	}
	if check {
		/* 2: the strip carved exactly from the hide */
		bg_check(strip != NO_ENTITY && world_get_field(st.w, "Body.mass", hide, &v) && v == 900)
		bg_check(world_get_field(st.w, "Body.mass", strip, &v) && v == 100)
		bg_check(world_edges_from(st.w, .Split_From, strip, ([^]Entity_ID)(&source), 1) == 1 && source == hide)
	}
	g = proposal_group_group_with_phase(.System, "setup: the strip in hand")
	proposal_group_move_to(g, whole(hide), on_tile(4, 5, 0))
	proposal_group_move_to(g, whole(strip), held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(6000))
	bg_check(perform(st.w, st.c, action_make("shape_seal", worker, strip, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(7000))

	/* 4: the new seal installed in the piston, the old one out: the pump's
	 * flow changes by the old seal's loss */
	bg_check(perform(st.w, st.c, action_make("replace_part", worker, strip, seal), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(13000))
	if check {
		bg_check(world_location_of(st.w, strip).form == .Part_Of && world_location_of(st.w, strip).place == piston)
		bg_check(world_location_of(st.w, seal).form == .On_Tile)
		bg_check(world_get_field(st.w, "Pump.flow", pump, &v) && v == 100)
	}

	/* 5: the piston back in its place */
	bg_check(perform(st.w, st.c, action_make("install_part", worker, piston, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(14000))
	if check {
		bg_check(world_location_of(st.w, piston).form == .Part_Of && world_location_of(st.w, piston).place == pump)
		/* 6: in again, out of the domain */
		bg_check(!thermal_participates(thermal, piston))
		/* 5: the miller's claim covers the pump's parts, and the old seal by
		 * its provenance; the new seal keeps the player's, and the miller's
		 * doesn't reach it (COMPONENTS.md decision 11: installing transfers
		 * nothing; whether it was a gift is for people to settle) */
		bg_check(slice.contains(claims_covering(st.w, piston), claim))
		bg_check(slice.contains(claims_covering(st.w, seal), claim) &&
		         !ownership_open(st.w, seal))
		bg_check(!slice.contains(claims_covering(st.w, strip), claim) &&
		         slice.contains(claims_covering(st.w, strip), mine))
		bg_check(!ownership_open(st.w, strip))
		/* 1: every part is part of exactly one assembly, or elsewhere */
		for i: uint = 0; i < store_count(parts); i += 1 {
			bg_check(world_location_of(st.w, store_entity_at_index(parts, i)).form != .None)
		}
	}
	return sealWear
}


test_component_pump :: proc() {
	out: i64
	in_: i64

	out = test_component_pump_(false, true)
	/* 3: the nested level opened in place, before the piston comes out,
	 * gives the same seal */
	in_ = test_component_pump_(true, false)
	bg_check(out >= 60 && out == in_)
}


/* ACTIONS.md Scenario 3's step 6 and check 7: the piston out of the pump
 * `key`, the worker sets to clean out its cylinder, watching the floor. With
 * the outlet valve leaking, the water rises at its feet: the watch fires
 * within the domain's tolerance (a spreading step, 10 s) of the crossing, and
 * the activity is interrupted, its watch removed. Returns the status. */
test_flood_run :: proc(key: cstring, crossed: ^i64, interrupted: ^i64, watch: ^i64) -> cstring {
	st:     Stage
	fluid:  ^Fluid_Domain
	g:      ^Proposal_Group
	pump:   Entity_ID
	tank:   Entity_ID
	worker: Entity_ID
	wrench: Entity_ID
	piston: Entity_ID
	a:      Entity_ID
	parts:  ^Store
	error:  string

	st.w   = test_world(157)       /* as pump_open: the same units, the same culprits */
	st.c   = test_committer(st.w)
	fluid  = autorelease(fluid_domain_init_with_world(st.w))
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	scheduler_add_domain(st.s, fluid_domain_as_domain(fluid))
	g      = proposal_group_group_with_phase(.System, "setup: the pump house")
	pump   = proposal_group_create(g, "crank_pump", key, on_tile(5, 5, 0))
	tank   = proposal_group_create(g, "header_tank", "the header tank", on_tile(5, 5, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	proposal_group_set_of_to(g, "Latent.riser", whole(pump), i64(tank))
	proposal_group_set_of_to_text(g, "Latent.failure", whole(pump), "flow_loss")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump   = proposal_group_id_for(g, pump)
	worker = proposal_group_id_for(g, worker)
	wrench = proposal_group_id_for(g, wrench)
	error  = ""
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2000))
	piston = NO_ENTITY
	parts  = world_store_for_kind(st.w, world_kind_named(st.w, "Part"))
	for i: uint = 0; i < store_count(parts); i += 1 {
		if string(world_info(st.w, store_entity_at_index(parts, i)).blueprint) == "piston" do piston = store_entity_at_index(parts, i)
	}
	bg_check(perform(st.w, st.c, action_make("take", worker, piston, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(3000))
	g = perform(st.w, st.c, action_make("clean_out", worker, wrench, pump), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(4000))
	a      = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	watch^ = -1
	world_get_field(st.w, "Activity.watchFloor", a, watch)
	crossed^     = 0
	interrupted^ = 0
	for world_time(st.w).ms < 20 * 60000 {
		if !scheduler_step_until(st.s, time_make(20 * 60000)) do scheduler_run_until(st.s, time_make(20 * 60000))
		if crossed^ == 0 && world_water_at_x(st.w, 4, 5, 0) >= 500 do crossed^ = world_time(st.w).ms
		if interrupted^ == 0 && string(test_status_of(st.w, a)) != "\"running\"" do interrupted^ = world_time(st.w).ms
	}
	world_get_field(st.w, "Activity.watchFloor", a, watch)

	/* DOMAIN_SIMULATION.md Scenario 2's check 5: saved now, the piston
	 * out, the puddle as it is, the work suspended; restored with its fluid
	 * domain, the next step is the same, to the byte */
	{
		st2:    Stage
		fluid2: ^Fluid_Domain
		text:   string
		next:   i64

		text    = save(st.w, st.c, []Saved_System{domain_as_saved_system(fluid_domain_as_domain(fluid))})
		st2.w   = test_restore(text, world_content_build(st.w), &st2.c, &error)
		fluid2  = autorelease(fluid_domain_init_with_world(st2.w))
		restored := fluid_domain_as_domain(fluid2)
		restored.restore_saved_state(restored.data, saved_domain_state(text, "fluid"))
		st2.s   = autorelease(scheduler_init_with_world(st2.w, st2.c))
		scheduler_set_activities(st2.s, activities_as_activity_clock(activities_with_world(st2.w, st2.c)))
		scheduler_add_domain(st2.s, fluid_domain_as_domain(fluid2))
		bg_check(st2.w != nil && world_state_hash(st2.w) == world_state_hash(st.w))
		next = world_time(st.w).ms + 60000
		scheduler_run_until(st.s, time_make(next))
		scheduler_run_until(st2.s, time_make(next))
		bg_check(save(st2.w, st2.c, []Saved_System{domain_as_saved_system(fluid_domain_as_domain(fluid2))}) ==
		         save(st.w, st.c, []Saved_System{domain_as_saved_system(fluid_domain_as_domain(fluid))}))
	}
	return test_status_of(st.w, a)
}


/* ACTIONS.md Scenario 3's step 5: dismantling suspended, the wrench taken;
 * resuming is refused, for nothing turns the gland nut; the worker
 * improvises with a spanner, and the dismantling goes on to the end. */
test_improvise :: proc() {
	st:         Stage
	activities: ^Activities
	g:          ^Proposal_Group
	worker:     Entity_ID
	smith:      Entity_ID
	wrench:     Entity_ID
	spanner:    Entity_ID
	pump:       Entity_ID
	a:          Entity_ID
	error:      string
	v:          i64

	st.w       = test_world(181)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	g       = proposal_group_group_with_phase(.System, "setup: the mill")
	pump    = proposal_group_create(g, "pump", "pump", on_tile(5, 5, 0))
	worker  = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	smith   = proposal_group_create(g, "smith", "smith", on_tile(4, 6, 0))
	wrench  = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	spanner = proposal_group_create(g, "spanner_19", "spanner", on_tile(4, 5, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump    = proposal_group_id_for(g, pump)
	worker  = proposal_group_id_for(g, worker)
	smith   = proposal_group_id_for(g, smith)
	wrench  = proposal_group_id_for(g, wrench)
	spanner = proposal_group_id_for(g, spanner)
	error   = ""
	g = perform(st.w, st.c, action_make("dismantle", worker, wrench, pump), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(4000))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	bg_check(activities_suspend(activities, a, "called away", &error) != nil)
	g = proposal_group_group_with_phase(.System, "setup: the smith takes the wrench")
	proposal_group_move_to(g, whole(wrench), held_by(smith, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(5000))
	/* resuming finds nothing to turn the gland nut */
	bg_check(activities_resume(activities, a, &error) == nil && ns_contains(error, "no longer holds"))
	/* the wrench won't do from the smith's hand; a spanner, taken up, will */
	bg_check(activities_improvise(activities, a, wrench, &error) == nil)
	g = proposal_group_group_with_phase(.System, "setup: the worker picks up the spanner")
	proposal_group_move_to(g, whole(spanner), held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(6000))
	bg_check(activities_improvise(activities, a, spanner, &error) != nil)
	scheduler_run_until(st.s, time_make(7000))
	bg_check(world_get_field(st.w, "Activity.itemRef", a, &v) && v == i64(spanner))
	bg_check(activities_resume(activities, a, &error) != nil)
	scheduler_run_until(st.s, time_make(20000))
	bg_check(string(test_status_of(st.w, a)) == "\"completed\"")
	bg_check(world_get_field(st.w, "Pump.opened", pump, &v) && v != 0)
}


test_latent_pump :: proc() {
	early:  Pump_Run
	late:   Pump_Run
	saved:  Pump_Run
	seized: Pump_Run
	other:  Pump_Run
	seal:   bool
	outlet: bool
	none:   bool
	key:    cstring

	/* opened two levels: six parts, part of it; 3: its mass carved, not duplicated */
	early = test_pump_open("pump 2", "flow_loss", 300 * 3600000, 0)
	bg_check(early.inside && len(ns_components_separated(early.parts, "; ")) == 6)
	bg_check(early.total == 40000 && early.pumpMass < 40000)

	/* 2: deterministic reveal: at hour 400, the same parts and culprit. Never
	 * worked, nothing is worn but the culprit, worn as a failure leaves it,
	 * and it wears no further unused (LATENT_ASSEMBLY.md decision 5) */
	late = test_pump_open("pump 2", "flow_loss", 400 * 3600000, 0)
	bg_check(early.parts == "handle pump_handle 0; cover pump_cover 0; piston piston 0; " +
	                        "piston_seal leather_cup 60; inlet_valve inlet_valve 0; outlet_valve outlet_valve 0")
	bg_check(late.culprit == early.culprit && early.culprit == "piston_seal")
	bg_check(late.parts == early.parts)
	/* reloading a save made before opening gives the same */
	saved = test_pump_open("pump 2", "flow_loss", 300 * 3600000, 200 * 3600000)
	bg_check(saved.parts == early.parts)

	/* the culprit varies with the unit's seed, among the candidates; the
	 * housing is no part at these levels: cause unresolved, none invented */
	seal = false
	outlet = false
	none = false
	for k in 0 ..< i32(24) {
		key    = fmt.ctprintf("pump %d", k)
		other  = test_pump_open(key, "flow_loss", 300 * 3600000, 0)
		seal   = seal || other.culprit == "piston_seal"
		outlet = outlet || other.culprit == "outlet_valve"
		none   = none || other.culprit == ""
		/* 6: the menu before opening says nothing of it */
		bg_check(other.menu == early.menu)
	}
	bg_check(seal && outlet && none)
	/* check 1: the piston out, the open cylinder is a path: through the
	 * outlet valve, the culprit, the header tank drains onto the floor, the
	 * water conserved exactly at every boundary; with the seal the culprit,
	 * the valve holds and nothing drains */
	for k in 0 ..< i32(24) {
		key = fmt.ctprintf("pump %d", k)
		if test_pump_open(key, "flow_loss", 300 * 3600000, 0).culprit == "outlet_valve" do break
	}
	{
		conserved: bool
		leaking:   bool
		floor:     i64

		floor = test_pump_drain(key, &conserved, &leaking)
		bg_check(leaking && conserved && floor > 10000)
		floor = test_pump_drain("pump 2", &conserved, &leaking)
		bg_check(leaking && conserved && floor == 0)
	}

	/* steps 3 and 4: inspection binds the faulty part */
	{
		agency: ^Agency
		w:      ^World
		spare:  Entity_ID
		at:     Location

		/* "pump 2": the seal. It opens the pump, a level at a time, with
		 * nothing bound to the worn part; seen worn, the seal is replaced
		 * with the spare, and the failure is mended */
		agency = test_mend_run("pump 2", &w, &spare)
		bg_check(test_log_index(agency, 2, "open it further: open_up") < test_log_index(agency, 2, "replace the worn part: replace_part"))
		bg_check(test_logged_by(agency, 2, "[mend the pump] replace the worn part: replace_part R4 into R8"))
		bg_check(test_logged_by(agency, 2, "[mend the pump] done"))
		at = world_location_of(w, spare)
		bg_check(at.form == .Part_Of && location_role(&at) == "piston_seal")
		bg_check(string(world_text_field(w, "Latent.failure", 1)) == "")
		bg_check(string(world_text_field(w, "Latent.blamed", 1)) == "")
		/* the housing the culprit: no part is worn, nothing to bind; opened
		 * through, it finds none, and none is invented */
		for k in 0 ..< i32(24) {
			key = fmt.ctprintf("pump %d", k)
			if test_pump_open(key, "flow_loss", 300 * 3600000, 0).culprit == "" do break
		}
		agency = test_mend_run(key, &w, &spare)
		bg_check(!test_logged_by(agency, 2, "replace_part"))
		bg_check(test_logged_by(agency, 2, "there is nothing further to open"))
		bg_check(world_location_of(w, spare).form == .Held_By)
	}

	/* check 7: the watch on rising water */
	{
		status:      cstring
		crossed:     i64
		interrupted: i64
		watch:       i64

		for k in 0 ..< i32(24) {
			key = fmt.ctprintf("pump %d", k)
			if test_pump_open(key, "flow_loss", 300 * 3600000, 0).culprit == "outlet_valve" do break
		}
		/* the outlet valve leaking: the water at its feet reaches 500 mL, and
		 * the work is interrupted at that boundary (the tolerance, a spreading
		 * step of 10 s), its watch removed */
		status = test_flood_run(key, &crossed, &interrupted, &watch)
		bg_check(string(status) == "\"suspended\"" && watch == 0)
		bg_check(crossed > 0 && interrupted >= crossed && interrupted <= crossed + 10000)
		/* the seal at fault: no water; the work runs its ten minutes, its watch removed as it ends */
		status = test_flood_run("pump 2", &crossed, &interrupted, &watch)
		bg_check(string(status) == "\"completed\"" && crossed == 0 && watch == 0)
	}

	/* a failure with no candidates: nothing marked */
	seized = test_pump_open("pump 2", "seized", 300 * 3600000, 0)
	bg_check(seized.culprit == "")
}


/* ACTIONS.md §2: an office holder's capability, issuing a permit. The
 * harbour office's clerk, its seal in hand, issues Alun a permit for the
 * warehouse, across the town: the permit's content claims the office, the
 * office's authorization is linked to it, and a sealed copy is in Alun's
 * hand. A worker who holds no office can't; and the clerk, who can issue,
 * isn't itself permitted. */
test_issue_permit :: proc() {
	st:        Stage
	g:         ^Proposal_Group
	office:    Entity_ID
	clerk:     Entity_ID
	worker:    Entity_ID
	alun:      Entity_ID
	seal:      Entity_ID
	warehouse: Entity_ID
	copy_:     Entity_ID
	content:   Entity_ID
	held:      [2]Entity_ID
	error:     string
	issue:     Action
	v:         i64

	st.w      = test_world(191)
	st.c      = test_committer(st.w)
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	g         = proposal_group_group_with_phase(.System, "setup: the harbour office")
	office    = proposal_group_create(g, "harbour_office", "the harbour office", location_make_none())
	proposal_group_set_of_to_text(g, "Organization.orgName", whole(office), "the harbour office")
	warehouse = proposal_group_create(g, "storeroom", "the warehouse", on_tile(20, 4, 0))
	clerk     = proposal_group_create(g, "office_clerk", "the clerk", on_tile(10, 10, 0))
	proposal_group_set_of_to(g, "OfficeHolder.office", whole(clerk), i64(office))
	proposal_group_set_of_to_text(g, "Scribe.handwriting", whole(clerk), "a clerk's round hand")
	seal      = proposal_group_create(g, "stamp", "the office seal", held_by(clerk, 0))
	proposal_group_set_of_to_text(g, "Stamp.presses", whole(seal), "the harbour anchor")
	proposal_group_set_of_to_text(g, "Stamp.sealOf", whole(seal), "the harbour office")
	alun      = proposal_group_create(g, "alun", "Alun", on_tile(11, 10, 0))
	worker    = proposal_group_create(g, "worker", "a worker", on_tile(10, 11, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	office    = proposal_group_id_for(g, office)
	warehouse = proposal_group_id_for(g, warehouse)
	clerk     = proposal_group_id_for(g, clerk)
	alun      = proposal_group_id_for(g, alun)
	worker    = proposal_group_id_for(g, worker)

	/* a worker holds no office: it can't issue one */
	error         = ""
	issue         = action_make("issue_permit", worker, alun, NO_ENTITY)
	issue.content = world_intern(st.w, "#Container & { place: #OnTile & { x: 20, y: 4, level: 0 } }")
	bg_check(perform(st.w, st.c, issue, 0, &error) == nil)

	issue.roles[.Actor] = clerk
	bg_check(perform(st.w, st.c, issue, 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2))

	/* the authorization: the office's, over the warehouse, to Alun */
	auth := authorize(st.w, action_make("look_in", alun, warehouse, NO_ENTITY))
	bg_check(len(auth) == 1)
	/* the clerk can issue; that is no permission of its own */
	bg_check(len(authorize(st.w, action_make("look_in", clerk, warehouse, NO_ENTITY))) == 0)
	/* a sealed copy in Alun's hand, its content claiming the office, and stating the authorization */
	bg_check(world_entities_at(st.w, alun, .Held_By, raw_data(held[:]), 2) == 1)
	copy_ = held[0]
	bg_check(world_get_field(st.w, "Inscription.inscribed", copy_, &v))
	content = Entity_ID(v)
	bg_check(string(world_text_field(st.w, "Inscription.impression", copy_)) == "the harbour anchor")
	bg_check(string(world_text_field(st.w, "Information.issuer", content)) == "the harbour office")
	bg_check(content_authorizes(st.w, content))
	bg_check(world_location_of(st.w, content).form == .None)
}


/* --- the false alarm -------------------------------------------------------- */

Alarm :: enum i32 {
	No_Rumour = 0,          /* A */
	Rumour,                 /* B */
	Deflated,               /* C: the rumour has one named source */
	Repeated,               /* D: B, with noise after noise */
	Asked,                  /* C, the long way: B's rumours, both from the neighbour, and Bela asks */
	Autopilot,              /* E: B, the watchman the player's, on autopilot */
	Autopilot_Quiet,        /* E under A: the noise alone */
}


Alarm_Run :: struct {
	world:     ^World,
	knowledge: ^Knowledge,
	agency:    ^Agency,
	watchman:  Entity_ID,
	carter:    Entity_ID,
	porter:    Entity_ID,
	storeroom: Entity_ID,
	cat:       Entity_ID,
	notices:   []string,
	text:      string,
}


/* AGENCY.md Scenario 2, "the false alarm", in the workshop: the watchman
 * walks past the storeroom, then sits down by the gate to eat supper, eight
 * tiles off, out of sight and in earshot. The carter and the porter tell it
 * someone has been getting into the storeroom (B, D: neither names a source;
 * C: both heard it from the neighbour). Then a cat by the storeroom knocks
 * something over (D: again and again). `tolerance`: the watchman's risk
 * tolerance. */
test_false_alarm_ :: proc(variant: Alarm, saveAt: i64, tolerance: i32) -> Alarm_Run {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	h:          [8]Entity_ID
	error:      string
	source:     string
	rumour:     string
	run:        Alarm_Run
	text:       string

	st.w       = test_world(41)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	scheduler_add_domain(st.s, traces_as_domain(autorelease(traces_init_with_world(st.w))))

	g    = proposal_group_group_with_phase(.System, "setup: the storeroom at night")
	h[0] = proposal_group_create(g, "storeroom", "storeroom", on_tile(12, 4, 0))
	h[1] = proposal_group_create(g, "cat", "cat", on_tile(12, 5, 0))
	h[2] = proposal_group_create(g, "watchman", "watchman", on_tile(9, 4, 0))
	h[3] = proposal_group_create(g, "supper", "supper", held_by(h[2], 0))
	proposal_group_set_of_to(g, "Agent.riskTolerance", whole(h[2]), i64(tolerance))
	h[4] = proposal_group_create(g, "carter", "carter", on_tile(3, 5, 0))
	h[5] = proposal_group_create(g, "porter", "porter", on_tile(5, 5, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	run.world     = st.w
	run.knowledge = knowledge
	run.agency    = agency
	run.storeroom = proposal_group_id_for(g, h[0])
	run.cat       = proposal_group_id_for(g, h[1])
	run.watchman  = proposal_group_id_for(g, h[2])
	run.carter    = proposal_group_id_for(g, h[4])
	run.porter    = proposal_group_id_for(g, h[5])
	if variant < .Autopilot do agency_control(agency, run.watchman)

	/* past the storeroom (it sees it, under the cat's eye), to the gate */
	test_stage_move(&st, run.watchman, 4, 4)

	/* C, the long way: far off, out of earshot, the neighbour tells the
	 * carter and the porter; they come back; they will answer through agency */
	if variant == .Asked {
		n:         ^Proposal_Group
		neighbour: Entity_ID

		n         = proposal_group_group_with_phase(.System, "setup: the neighbour")
		neighbour = proposal_group_create(n, "neighbour", "neighbour", on_tile(20, 25, 0))
		committer_submit(st.c, n)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
		neighbour = proposal_group_id_for(n, neighbour)
		test_stage_move(&st, run.carter, 20, 24)
		test_stage_move(&st, run.porter, 21, 25)
		rumour = "#IsIn & { what: #Agent, within: #Container & { place: #OnTile & { x: 12, y: 4, level: 0 } }, " +
		         "attribution: #Saw & { sure: 30 } }"
		test_stage_say(&st, neighbour, run.carter, rumour)
		test_stage_say(&st, neighbour, run.porter, rumour)
		test_stage_move(&st, run.carter, 3, 5)
		test_stage_move(&st, run.porter, 5, 5)
		agency_control(agency, run.carter)
		agency_control(agency, run.porter)
	}

	/* the rumour */
	if variant != .No_Rumour && variant != .Autopilot_Quiet {
		source = ("#Heard & { from: #Agent & { material: \"flesh\", hands: 2, coat: \"grey\", mass: 60kg } }"
		          if variant == .Deflated else "#Heard")
		rumour = fmt.tprintf("#IsIn & {{ what: #Agent, within: #Container & {{ place: #OnTile & " +
		                     "{{ x: 12, y: 4, level: 0 }} }}, attribution: %s }}", source)
		test_stage_say(&st, run.carter, run.watchman, rumour)
		test_stage_say(&st, run.porter, run.watchman, rumour)
	}
	if variant == .Asked {
		/* where did you hear it? both answer: from the neighbour */
		rumour = "#WhoToldYou & { what: #Agent, within: #Container & { place: #OnTile & { x: 12, y: 4, level: 0 } } }"
		test_stage_say(&st, run.watchman, run.carter, rumour)
		test_stage_say(&st, run.watchman, run.porter, rumour)
	}
	test_stage_move(&st, run.carter, 3, 20)
	test_stage_move(&st, run.porter, 5, 20)

	/* supper; E: the player puts the watchman on autopilot, to come back for
	 * anything worth more than 25 */
	if variant >= .Autopilot {
		bg_check(agency_autopilot_to_goal(agency, run.watchman, "eat_supper", 25))
	} else {
		bg_check(agency_commit(agency, run.watchman, "eat_supper"))
	}
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 2000))

	/* the cat */
	for _ in 0 ..< (5 if variant == .Repeated else 1) {
		error = ""
		bg_check(perform(st.w, st.c, action_make("knock_over", proposal_group_id_for(g, h[1]), NO_ENTITY, NO_ENTITY), 0,
		                 &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1500))
	}
	if saveAt != 0 {
		/* saved, restored into a fresh world, and carried on there */
		scheduler_run_until(st.s, time_make(saveAt))
		text  = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
		error = ""
		st.w  = test_restore(text, world_content_build(st.w), &st.c, &error)
		bg_check(st.w != nil)
		activities = activities_with_world(st.w, st.c)
		knowledge  = autorelease(knowledge_init_with_world(st.w))
		agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
		st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
		known := knowledge_as_saved_system(knowledge)
		known.restore_saved_state(known.data, saved_domain_state(text, "knowledge"))
		minds := agency_as_saved_system(agency)
		minds.restore_saved_state(minds.data, saved_domain_state(text, "agency"))
		agency_set_activities(agency, activities)
		scheduler_set_activities(st.s, activities_as_activity_clock(activities))
		scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
		scheduler_set_decision(st.s, agency_as_decision_phase(agency))
		scheduler_add_domain(st.s, traces_as_domain(autorelease(traces_init_with_world(st.w))))
		bg_check(save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)}) == text)
		run.world     = st.w
		run.knowledge = knowledge
		run.agency    = agency
	}
	scheduler_run_until(st.s, time_make(120000))
	run.notices = agency_take_notices(agency)
	run.text    = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


test_log_count :: proc(agency: ^Agency, agent: Entity_ID, text: string) -> uint {
	log: []string
	n:   uint

	log = agency_log_of(agency, agent)
	n   = 0
	for i in 0 ..< len(log) {
		if ns_contains(log[i], text) do n += 1
	}
	return n
}


test_false_alarm :: proc() {
	a:       Alarm_Run
	b:       Alarm_Run
	c:       Alarm_Run
	d:       Alarm_Run
	again:   Alarm_Run
	resumed: Alarm_Run
	e:       Alarm_Run
	quiet:   Alarm_Run
	bold:    Alarm_Run
	asked:   Alarm_Run
	timid:   Alarm_Run
	store:   ^Knowledge_Store

	a = test_false_alarm_(.No_Rumour, 0, 50)
	b = test_false_alarm_(.Rumour, 0, 50)
	c = test_false_alarm_(.Deflated, 0, 50)

	/* everyone hears the cat, and makes of it that something stirred by the storeroom */
	bg_check(test_logged_by(a.agency, a.watchman, "weighing investigate the disturbance"))
	bg_check(test_logged_by(c.agency, c.watchman, "weighing investigate the disturbance"))

	/* 1, 2: credence changes the decision; the margin and the interruption
	 * decide the comparison with supper. A: the noise alone, credence 0: 15
	 * against supper's 20 + 5 + 5, it stays. B: two rumours whose sources it
	 * doesn't know, two groups, credence 20: 35, it switches. C: one named
	 * source, one group, credence 15: 30, not more than 30, it stays. */
	bg_check(test_logged_by(a.agency, a.watchman, "+15 (credence +0, +20, risk -5) against eat supper +20 (+20) + margin 5 + " +
	                                              "interruption 5: staying"))
	bg_check(test_logged_by(b.agency, b.watchman, "+35 (credence +20, +20, risk -5) against eat supper +20 (+20) + margin 5 + " +
	                                              "interruption 5: switching"))
	bg_check(test_logged_by(c.agency, c.watchman, "+30 (credence +15, +20, risk -5) against eat supper +20 (+20) + margin 5 + " +
	                                              "interruption 5: staying"))
	bg_check(!test_logged_by(a.agency, a.watchman, "switching") && !test_logged_by(c.agency, c.watchman, "switching"))

	/* C, the long way: B's two rumours, naming no one, but Bela asks each
	 * where it came from; both heard it from the neighbour, the groups merge,
	 * and credence falls to C's: it stays at supper */
	asked = test_false_alarm_(.Asked, 0, 50)
	bg_check(test_logged_by(asked.agency, asked.watchman, "+30 (credence +15, +20, risk -5) against eat supper +20 (+20) + " +
	                                                      "margin 5 + interruption 5: staying"))
	bg_check(!test_happened(asked.world, "looked", asked.watchman, asked.storeroom))

	/* the risk, as risk tolerance weighs it: a bold watchman, in C's
	 * conditions, makes nothing of it, 35, and gets up; a timid one, in B's,
	 * makes double of it, 30, and stays */
	bold  = test_false_alarm_(.Deflated, 0, 100)
	timid = test_false_alarm_(.Rumour, 0, 0)
	bg_check(test_logged_by(bold.agency, bold.watchman, "+35 (credence +15, +20, risk +0) against eat supper +20 (+20) + " +
	                                                    "margin 5 + interruption 5: switching"))
	bg_check(test_happened(bold.world, "looked", bold.watchman, bold.storeroom))
	bg_check(test_logged_by(timid.agency, timid.watchman, "+30 (credence +20, +20, risk -10) against eat supper +20 (+20) + " +
	                                                      "margin 5 + interruption 5: staying"))
	bg_check(!test_happened(timid.world, "looked", timid.watchman, timid.storeroom))
	bg_check(!test_happened(a.world, "looked", a.watchman, a.storeroom) && !test_happened(c.world, "looked", c.watchman, c.storeroom))

	/* B: it puts supper down, looks, and goes back to it, resuming where it left off */
	bg_check(test_logged_by(b.agency, b.watchman, "suspending eat"))
	bg_check(test_happened(b.world, "looked", b.watchman, b.storeroom))
	bg_check(test_logged_by(b.agency, b.watchman, "[investigate the disturbance] done"))
	bg_check(test_logged_by(b.agency, b.watchman, "back to it: investigate the disturbance is done"))
	bg_check(test_logged_by(b.agency, b.watchman, "[eat supper] eat: resuming eat"))
	bg_check(test_logged_by(b.agency, b.watchman, "[eat supper] done"))
	bg_check(test_log_index(b.agency, b.watchman, "switching") < test_log_index(b.agency, b.watchman, "resuming eat"))

	/* 4: no one was there: the claim is found false, and it trusts the carter
	 * and the porter less */
	store = knowledge_store_of(b.knowledge, b.watchman)
	bg_check(knowledge_store_testimony_count(store) == 2 && knowledge_store_testimony_at(store, 0).settled == -1 &&
	         knowledge_store_testimony_at(store, 1).settled == -1)
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, b.carter)) == BG_TRUST - BG_REFUTED)
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, b.porter)) == BG_TRUST - BG_REFUTED)
	/* untested, in A and C */
	store = knowledge_store_of(c.knowledge, c.watchman)
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, c.carter)) == BG_TRUST)

	/* 3: no dithering: noise after noise, the intention changes once */
	d = test_false_alarm_(.Repeated, 0, 50)
	bg_check(test_log_count(d.agency, d.watchman, "switching") == 1)
	bg_check(test_log_count(d.agency, d.watchman, "staying") == 0)
	bg_check(test_log_count(d.agency, d.watchman, "suspending eat") == 1)
	bg_check(test_happened(d.world, "looked", d.watchman, d.storeroom))

	/* 6: determinism */
	again = test_false_alarm_(.Rumour, 0, 50)
	bg_check(world_state_hash(again.world) == world_state_hash(b.world))
	bg_check(again.text == b.text)
	bg_check(slice.equal(agency_log_of(again.agency, again.watchman), agency_log_of(b.agency, b.watchman)))

	/* saved mid-investigation, supper suspended beneath it, restored: the same
	 * end (a boundary the run has: a step toward the storeroom) */
	resumed = test_false_alarm_(.Rumour, 10003, 50)
	bg_check(world_state_hash(resumed.world) == world_state_hash(b.world))
	bg_check(resumed.text == b.text)
	bg_check(test_logged_by(resumed.agency, resumed.watchman, "[eat supper] eat: resuming eat"))

	/* 5: E, autopilot: in B's conditions, the noise is worth more than the
	 * player's 25: control returns at that weighing, supper still under way,
	 * nothing looked into; autopilot used nothing the watchman didn't know */
	e = test_false_alarm_(.Autopilot, 0, 50)
	bg_check(len(e.notices) == 1 &&
	         e.notices[0] == "Control returns to you: investigate the disturbance (R2) is " +
	                         "worth +35, more than your +25.")
	bg_check(!agency_controls(e.agency, e.watchman))
	bg_check(!test_logged_by(e.agency, e.watchman, "switching") && !test_logged_by(e.agency, e.watchman, "suspending"))
	bg_check(!test_happened(e.world, "looked", e.watchman, e.storeroom))
	/* 5: autopilot uses nothing Bela lacks: what it weighed is Bela's
	 * belief, from the rumours and the clatter it heard, that someone is in
	 * the storeroom (R2), a someone with no truth behind it at all */
	store = knowledge_store_of(e.knowledge, e.watchman)
	bg_check(test_referent_of(store, e.storeroom) == 2)
	bg_check(knowledge_store_finding(store, "#Disturbance", 2) != nil)
	{
		r:        ^Referent
		intruder: bool

		intruder = false
		for i: uint = 0; i < knowledge_store_count(store); i += 1 {
			r = knowledge_store_referent_at(store, i)
			intruder = intruder || (r.form == .In && r.container == 2 && r.truth == 0 &&
			                        string(r.kind) == "#Agent")
		}
		bg_check(intruder)
	}
	/* in A's, it eats on, and hands back when supper is done */
	quiet = test_false_alarm_(.Autopilot_Quiet, 0, 50)
	bg_check(len(quiet.notices) == 1 &&
	         quiet.notices[0] == "Control returns to you: there is nothing left to do.")
	bg_check(test_logged_by(quiet.agency, quiet.watchman, "[eat supper] done"))
}


/* Autopilot in a session: the worker looks into the bin, then hands itself
 * to agency to wedge the lock; it fetches nails, drives one, and control
 * returns. */
test_play_autopilot :: proc() {
	commands: []string
	out:      string
	again:    string
	h1:       u64
	h2:       u64

	commands = []string{"do 1", "autopilot wedge_lock 100", "autopilot nonesuch", "menu"}
	out   = test_session("workshop", commands, &h1)
	again = test_session("workshop", commands, &h2)
	bg_check(h1 == h2 && out == again)
	bg_check(ns_contains(out, "Autopilot: wedge_lock, until something is worth more than 100."))
	bg_check(ns_contains(out, "action 4: take_some item 2"))
	bg_check(ns_contains(out, "drive completes"))
	bg_check(ns_contains(out, "Control returns to you: there is nothing left to do."))
	bg_check(ns_contains(out, "There is no goal nonesuch."))
}


/* --- the tempting purse ----------------------------------------------------- */

Purse :: enum i32 {
	Base = 0,
	Noticed,                /* A: Mira isn't hiding, and Kasimir sees her */
	Honest,                 /* B: an honest Kasimir, the same debt */
	No_Witness,             /* C: Mira isn't there */
	Untold,                 /* A, but no one told Kasimir whose the purse is */
	Asked,                  /* the base case, but the merchant asks Kasimir where the purse is */
	Asked_Untold,           /* that, and no one told Kasimir whose it is */
	Watch,                  /* the base case, and an officer of the town's watch by Mira */
	Flight,                 /* that, and Kasimir doesn't abide by the rules */
	Resist,                 /* that, and he has a temper */
	Gentle,                 /* that, and he holds never to strike anyone */
	Kin,                    /* the watch case, and Mira is the merchant's daughter */
	Wary,                   /* B, and the carter trusts no one */
	Strangers,              /* B, and the carter and Kasimir aren't friends */
	Hired,                  /* wary, strangers, and a foreman by Kasimir who hires */
	Stiffed,                /* that, and the foreman is dishonest */
	Advert,                 /* hired, but the foreman is out of sight, and its flyer by Kasimir */
	Unadvertised,           /* that, with no flyer */
	Repaid,                 /* B, and on until the loan's term is out */
	Lost,                   /* that, but the wages are lost on the third day */
}


Purse_Run :: struct {
	world:     ^World,
	knowledge: ^Knowledge,
	agency:    ^Agency,
	purse:     Entity_ID,
	kasimir:   Entity_ID,
	mira:      Entity_ID,
	merchant:  Entity_ID,
	carter:    Entity_ID,
	wages:     Entity_ID,
	officer:   Entity_ID,
	foreman:   Entity_ID,
	pay:       Entity_ID,
	fitting:   Entity_ID,
	crate:     Entity_ID,
	owedLate:  bool,            /* the wages still Kasimir's on the sixth day */
	text:      string,
}


/* AGENCY.md Scenario 3, "the tempting purse": a purse on the counter, the
 * merchant's; Kasimir, who owes, beside it; the carter across the room, a
 * friend to borrow from; and Mira, half hidden in a doorway, who sees
 * Kasimir, unseen. The merchant turns away to serve someone out of sight,
 * and Kasimir's debt falls due. Later the merchant comes back and asks Mira
 * where the purse is. */
test_tempting_purse_ :: proc(variant: Purse) -> Purse_Run {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	h:          [8]Entity_ID
	run:        Purse_Run

	st.w       = test_world(43)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))

	g    = proposal_group_group_with_phase(.System, "setup: the market stall")
	h[0] = proposal_group_create(g, "purse", "purse", on_tile(10, 10, 0))
	h[1] = proposal_group_create(g, "merchant", "merchant", on_tile(10, 11, 0))
	/* the town, and its law against theft, which everyone knows */
	h[6] = proposal_group_create(g, "town", "the town", location_make_none())
	h[7] = proposal_group_create(g, "theft_law", "the law against theft", location_make_none())
	proposal_group_set_of_to(g, "Law.lawOf", whole(h[7]), i64(h[6]))
	/* the purse is truly the merchant's */
	{
		claim: Entity_ID

		claim = proposal_group_create(g, "ownership", "the merchant's purse", location_make_none())
		proposal_group_relate(g, .Claimant, whole(claim), whole(h[1]))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(h[0]))
	}
	h[2] = proposal_group_create(g, "kasimir", "kasimir", on_tile(9, 10, 0))
	h[3] = proposal_group_create(g, "carter", "carter", on_tile(5, 10, 0))
	h[5] = proposal_group_create(g, "purse", "the carter's wages", held_by(h[3], 0))
	{
		claim := proposal_group_create(g, "ownership", "the carter's wages", location_make_none())
		proposal_group_relate(g, .Claimant, whole(claim), whole(h[3]))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(h[5]))
	}
	h[4] = NO_ENTITY
	if variant != .No_Witness {
		h[4] = proposal_group_create(g, "mira", "mira", on_tile(12, 12, 0))
		if variant == .Noticed || variant == .Untold || variant == .Asked_Untold {
			proposal_group_set_of_to(g, "Agent.hiding", whole(h[4]), 0)
		}
	}
	if variant == .Watch || variant == .Flight || variant == .Resist || variant == .Kin ||
	   variant == .Gentle {
		run.officer = proposal_group_create(g, "watch_officer", "an officer of the watch", on_tile(13, 12, 0))
	}
	if variant == .Flight || variant == .Resist || variant == .Gentle {
		proposal_group_set_of_to(g, "Agent.abiding", whole(h[2]), 0)
	}
	if variant == .Resist || variant == .Gentle {
		proposal_group_set_of_to(g, "Agent.temper", whole(h[2]), 100)
	}
	if variant == .Gentle {
		proposal_group_set_of_to(g, "Agent.gentle", whole(h[2]), 100)
	}
	if variant == .Kin {
		bond: Entity_ID

		bond = proposal_group_create(g, "kin_bond", "Mira's to her father", location_make_none())
		proposal_group_set_of_to(g, "Bond.bondOf", whole(bond), i64(h[4]))
		proposal_group_set_of_to(g, "Bond.toward", whole(bond), i64(h[1]))
		proposal_group_set_of_to(g, "Agent.trusting", whole(h[4]), 3)
	}
	if variant == .Honest || variant == .Repaid || variant == .Lost || variant == .Wary ||
	   variant == .Strangers || variant == .Hired || variant == .Stiffed || variant == .Advert ||
	   variant == .Unadvertised {
		proposal_group_set_of_to(g, "Agent.honesty", whole(h[2]), 90)
	}
	/* a foreman who hires (AGENCY.md decision 15): the job, a stone into the
	 * crate; the pay, a purse in hand. Neither it nor the carter
	 * will lend to a stranger */
	if variant == .Hired || variant == .Stiffed || variant == .Advert || variant == .Unadvertised {
		far: i32

		far = 4 if variant == .Advert || variant == .Unadvertised else 0
		proposal_group_set_of_to(g, "Agent.trusting", whole(h[3]), -20)
		run.foreman = proposal_group_create(g, "foreman", "the foreman", on_tile(13 + far, 10, 0))
		proposal_group_set_of_to_text(g, "Agent.hires", whole(run.foreman), "crate_job")
		proposal_group_set_of_to(g, "Agent.trusting", whole(run.foreman), -20)
		if variant == .Stiffed do proposal_group_set_of_to(g, "Agent.honesty", whole(run.foreman), 0)
		run.pay     = proposal_group_create(g, "purse", "the foreman's purse", held_by(run.foreman, 0))
		run.fitting = proposal_group_create(g, "stone", "the stone", on_tile(10 + far, 8, 0))
		run.crate   = proposal_group_create(g, "crate", "the crate", on_tile(12 + far, 11, 0))
		/* the foreman's flyer, by Kasimir (decision 15: a deal posted) */
		if variant == .Advert {
			flyer: Entity_ID

			flyer = proposal_group_create(g, "flyer", "the flyer", on_tile(9, 9, 0))
			proposal_group_set_of_to_text(g, "Record.writing", whole(flyer),
			                              world_intern(st.w, "#Writing & { author: #Agent & { coat: \"black\" }, entries: [#Hiring & { " +
			                                                 "what: #Body & { material: \"cloth\" }, holder: #Agent & { coat: \"black\" }, " +
			                                                 "site: #OnTile & { x: 17, y: 10, level: 0 }, when: 0ms, attribution: #Saw & { sure: 30 } }] }"))
		}
	}
	/* the carter and Kasimir are friends (AGENCY.md decision 12) */
	if variant != .Strangers && variant != .Hired && variant != .Stiffed && variant != .Advert &&
	   variant != .Unadvertised {
		bond: Entity_ID

		bond = proposal_group_create(g, "friend_bond", "the carter's to Kasimir", location_make_none())
		proposal_group_set_of_to(g, "Bond.bondOf", whole(bond), i64(h[3]))
		proposal_group_set_of_to(g, "Bond.toward", whole(bond), i64(h[2]))
		bond = proposal_group_create(g, "friend_bond", "Kasimir's to the carter", location_make_none())
		proposal_group_set_of_to(g, "Bond.bondOf", whole(bond), i64(h[2]))
		proposal_group_set_of_to(g, "Bond.toward", whole(bond), i64(h[3]))
	}
	if variant == .Wary do proposal_group_set_of_to(g, "Agent.trusting", whole(h[3]), -20)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	run.world     = st.w
	run.knowledge = knowledge
	run.agency    = agency
	run.purse     = proposal_group_id_for(g, h[0])
	run.merchant  = proposal_group_id_for(g, h[1])
	run.kasimir   = proposal_group_id_for(g, h[2])
	run.carter    = proposal_group_id_for(g, h[3])
	run.wages     = proposal_group_id_for(g, h[5])
	run.officer   = proposal_group_id_for(g, run.officer) if run.officer != NO_ENTITY else NO_ENTITY
	if run.foreman != NO_ENTITY {
		run.foreman = proposal_group_id_for(g, run.foreman)
		run.pay     = proposal_group_id_for(g, run.pay)
		run.fitting = proposal_group_id_for(g, run.fitting)
		run.crate   = proposal_group_id_for(g, run.crate)
		agency_control(agency, run.foreman)
	}
	if run.officer != NO_ENTITY do agency_control(agency, run.officer)
	agency_control(agency, run.carter)
	run.mira      = proposal_group_id_for(g, h[4]) if h[4] != NO_ENTITY else NO_ENTITY
	if run.mira != NO_ENTITY do agency_control(agency, run.mira)

	/* the merchant, beside Kasimir, says the purse is its own; then turns
	 * away, out of sight */
	if variant != .Untold && variant != .Asked_Untold {
		own: ^Knowledge_Store

		own = knowledge_store_of(knowledge, run.merchant)
		test_stage_say(&st, run.merchant, run.kasimir,
		               knowledge_store_ownership_of(own, test_referent_of(own, run.purse), knowledge_store_self_referent(own)))
	}
	test_stage_move(&st, run.merchant, 25, 10)

	/* the debt falls due */
	bg_check(agency_commit(agency, run.kasimir, "get_money"))
	scheduler_run_until(st.s, time_make(30000))

	/* the merchant comes back, by Mira, and asks her where the purse is; or
	 * by Kasimir, and asks him */
	if variant == .Asked || variant == .Asked_Untold {
		test_stage_move(&st, run.merchant, 9, 11)
		test_stage_say(&st, run.merchant, run.kasimir, "#WhereIs & { what: #Body & { material: \"cloth\" } }")
	} else if run.mira != NO_ENTITY {
		test_stage_move(&st, run.merchant, 12, 13)
		test_stage_say(&st, run.merchant, run.mira, "#WhereIs & { what: #Body & { material: \"cloth\" } }")
	}
	scheduler_run_until(st.s, time_make(90000))
	if run.foreman != NO_ENTITY do scheduler_run_until(st.s, time_make(3700000))
	if variant == .Repaid || variant == .Lost {
		if variant == .Lost {
			scheduler_run_until(st.s, time_make(3 * 86400000))
			g = proposal_group_group_with_phase(.System, "setup: the wages lost")
			proposal_group_destroy(g, whole(run.wages), "lost")
			committer_submit(st.c, g)
		}
		/* still owed on the sixth day; handed back on the seventh */
		scheduler_run_until(st.s, time_make(6 * 86400000 - 60000))
		run.owedLate = world_location_of(st.w, run.wages).place == run.kasimir
		scheduler_run_until(st.s, time_make(7 * 86400000 + 60000))
	}
	run.text = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


/* What the speaker last said that holds `text`, or nil (false). */
test_said_with :: proc(w: ^World, speaker: Entity_ID, text: string) -> (string, bool) #optional_ok {
	said: string

	for i := world_event_count(w); i > 0; i -= 1 {
		if string(world_event_at(w, i - 1).kind) == "said" && world_event_at(w, i - 1).actor == speaker &&
		   world_event_at(w, i - 1).detail != nil {
			said = ns_string(world_event_at(w, i - 1).detail)
			if ns_contains(said, text) do return said, true
		}
	}
	return "", false
}


/* When the agent last noted it owes something back by, or 0. */
test_owed_by :: proc(agency: ^Agency, agent: Entity_ID) -> i64 {
	log:  []string
	line: string
	at:   uint

	log = agency_log_of(agency, agent)
	for i := len(log); i > 0; i -= 1 {
		line = log[i - 1]
		at   = ns_range_of(line, " back by ")
		if ns_contains(line, "owes R") && at != NOT_FOUND {
			return ns_long_long_value(line[int(at) + len(" back by "):])
		}
	}
	return 0
}


/* The promise the source made the agent, or nil. */
test_pledge_from :: proc(store: ^Knowledge_Store, source: u32) -> ^Testimony {
	for i: uint = 0; i < knowledge_store_testimony_count(store); i += 1 {
		if knowledge_store_testimony_at(store, i).attribution == .Pledged && knowledge_store_testimony_at(store, i).source == source {
			return knowledge_store_testimony_at(store, i)
		}
	}
	return nil
}


test_tempting_purse :: proc() {
	base:         Purse_Run
	noticed:      Purse_Run
	honest:       Purse_Run
	alone:        Purse_Run
	again:        Purse_Run
	repaid:       Purse_Run
	lost:         Purse_Run
	untold:       Purse_Run
	watch:        Purse_Run
	flight:       Purse_Run
	resist:       Purse_Run
	asked:        Purse_Run
	askedUntold:  Purse_Run
	gentle:       Purse_Run
	kin:          Purse_Run
	wary:         Purse_Run
	strangers:    Purse_Run
	hired:        Purse_Run
	stiffed:      Purse_Run
	advert:       Purse_Run
	unadvertised: Purse_Run
	store:        ^Knowledge_Store
	purse:        ^Referent
	t:            ^Testimony
	saw:          bool

	base = test_tempting_purse_(.Base)

	/* 1, 4: the debt drives the goal; Kasimir believes no one is watching
	 * (the merchant is gone, Mira unseen), so taking the purse scores best,
	 * though a witness is truly there */
	bg_check(test_logged_by(base.agency, base.kasimir, "take the purse +20 (+30, honesty -5, scruples -5, unlawful, unwatched +0)"))
	bg_check(test_logged_by(base.agency, base.kasimir, "borrow from a friend +10 (loyal +10)"))
	bg_check(test_logged_by(base.agency, base.kasimir, "[get money] take the purse: take R"))
	bg_check(world_location_of(base.world, base.purse).form == .Held_By &&
	         world_location_of(base.world, base.purse).place == base.kasimir)
	bg_check(test_referent_of(knowledge_store_of(base.knowledge, base.kasimir), base.mira) == 0)

	/* 5: Mira saw it, and keeps it: curious, she notices what is routine to others */
	store = knowledge_store_of(base.knowledge, base.mira)
	saw   = false
	for i: uint = 0; i < knowledge_store_observation_count(store); i += 1 {
		if string(knowledge_store_observation_at(store, i).kind) == "moved" &&
		   knowledge_store_observation_at(store, i).actor == test_referent_of(store, base.kasimir) &&
		   knowledge_store_observation_at(store, i).subject == test_referent_of(store, base.purse) {
			saw = true
		}
	}
	bg_check(saw)
	/* asked, she tells the merchant that Kasimir has it, and the merchant believes her */
	bg_check(test_logged_by(base.agency, base.mira, "answering: say R"))
	store = knowledge_store_of(base.knowledge, base.merchant)
	purse = knowledge_store_referent(store, test_referent_of(store, base.purse))
	bg_check(purse != nil && purse.present && purse.form == .Held_By &&
	         purse.container == test_referent_of(store, base.kasimir))
	t = knowledge_store_testimony_at(store, 0) if knowledge_store_testimony_count(store) != 0 else nil
	bg_check(t != nil && t.source == test_referent_of(store, base.mira) && t.attribution == .Saw &&
	         t.thing == purse.id && t.container == test_referent_of(store, base.kasimir))
	/* and when it sees Kasimir with it, so it is: it trusts Mira more */
	bg_check(t != nil && t.settled == 1 && knowledge_store_trust_in(store, t.source) == BG_TRUST + BG_CONFIRMED)

	/* 2: A: Kasimir sees Mira, believes himself watched, and taking scores
	 * below nothing: unthinkable. He borrows instead, from his friend first
	 * (AGENCY.md decision 12): the carter lends him his wages, and he never
	 * asks Mira */
	noticed = test_tempting_purse_(.Noticed)
	bg_check(test_referent_of(knowledge_store_of(noticed.knowledge, noticed.kasimir), noticed.mira) != 0)
	bg_check(test_logged_by(noticed.agency, noticed.kasimir, "take the purse -20 (+30, honesty -5, scruples -5, unlawful, watched -40)"))
	bg_check(test_logged_by(noticed.agency, noticed.kasimir, "borrow from a friend: say R"))
	bg_check(test_logged_by(noticed.agency, noticed.kasimir, "answered: #Granted"))
	bg_check(test_logged_by(noticed.agency, noticed.kasimir, "[get money] done"))
	bg_check(world_location_of(noticed.world, noticed.purse).form == .On_Tile)
	bg_check(world_location_of(noticed.world, noticed.wages).form == .Held_By &&
	         world_location_of(noticed.world, noticed.wages).place == noticed.kasimir)

	/* 3: B: an honest Kasimir, unwatched, never takes it; asked, the carter
	 * weighs lending at its trust in him less what lending costs it
	 * (AGENCY.md decision 16): the wages' worth to it, 30, less by its trust
	 * in him, 22 (untested, and a friend: AGENCY.md decision 12) */
	honest = test_tempting_purse_(.Honest)
	bg_check(test_logged_by(honest.agency, honest.kasimir, "take the purse -20 (+30, honesty -45, scruples -5, unlawful, unwatched +0)"))
	bg_check(!test_logged_by(honest.agency, honest.kasimir, "take R"))
	bg_check(world_location_of(honest.world, honest.purse).form == .On_Tile)
	bg_check(test_logged_by(honest.agency, honest.carter, "worth 30 to it: lending it costs 4"))
	bg_check(test_logged_by(honest.agency, honest.carter, "worth +18, granting"))
	bg_check(test_logged_by(honest.agency, honest.carter, "granting: lend R"))
	bg_check(world_location_of(honest.world, honest.wages).place == honest.kasimir)
	/* lent, the wages are the carter's still, in Kasimir's keeping */
	bg_check(in_keeping_of(honest.world, honest.wages, honest.kasimir) &&
	         !claimed_by_another(honest.world, honest.wages, honest.carter))
	bg_check(!test_logged_by(noticed.agency, noticed.mira, "for something it hasn't"))
	/* a wary carter, disposed to trust no one (-20), trusts him at 2: lending
	 * costs nearly half the wages' worth, and it refuses */
	wary = test_tempting_purse_(.Wary)
	bg_check(test_logged_by(wary.agency, wary.carter, "worth 30 to it: lending it costs 14"))
	bg_check(test_logged_by(wary.agency, wary.carter, "worth -12, refusing"))
	bg_check(world_location_of(wary.world, wary.wages).place == wary.carter)
	/* a loan is a debt (AGENCY.md §7): Kasimir owes the carter its wages
	 * back within the week, a commitment, saved like any other */
	bg_check(test_logged_by(honest.agency, honest.kasimir, "owes R"))
	bg_check(ns_contains(honest.text, " repay ") &&
	         ns_contains(honest.text, " debt "))
	/* AGENCY.md decision 18: the terms are part of the deal. Between
	 * friends, none are said, and the default holds: a week. Not friends,
	 * the carter lends for a day, and says so; Kasimir owes it back then */
	strangers = test_tempting_purse_(.Strangers)
	bg_check(test_logged_by(strangers.agency, strangers.carter, "worth +15, granting"))
	{
		granted, said := test_said_with(strangers.world, strangers.carter, "#Granted")
		bg_check(said && ns_range_of(granted, "owedIn: 86400000ms") != NOT_FOUND)
	}
	{
		granted, said := test_said_with(honest.world, honest.carter, "#Granted")
		bg_check(said && ns_range_of(granted, "owedIn") == NOT_FOUND)
	}
	bg_check(test_owed_by(strangers.agency, strangers.kasimir) > 0 &&
	         test_owed_by(honest.agency, honest.kasimir) - test_owed_by(strangers.agency, strangers.kasimir) == 6 * 86400000)

	/* AGENCY.md decision 15: employment is a deal. Neither stranger will
	 * lend to Kasimir; asked for work, the foreman weighs it like any
	 * request (its trust in him, nothing, plus what having the job done is
	 * worth to it, 40, less the pay's worth, 30), hires him, and says the
	 * job: a stone into the crate within the hour. Asked for a loan, the
	 * foreman can still be asked for work: a search passes over only those
	 * asked the same */
	hired = test_tempting_purse_(.Hired)
	bg_check(test_logged_by(hired.agency, hired.foreman, "asked by R4: worth -15, refusing"))
	bg_check(test_logged_by(hired.agency, hired.foreman, "for work: worth +10, hiring"))
	bg_check(test_logged_by(hired.agency, hired.foreman, "hiring: hire R"))
	bg_check(test_logged_by(hired.agency, hired.kasimir, "answered: #Job"))
	bg_check(test_logged_by(hired.agency, hired.kasimir, "hired by R5: deliver, by "))
	/* the job is a commitment of his, an employment, and he does it */
	bg_check(test_logged_by(hired.agency, hired.kasimir, "weighing deliver it: +20 (employment, duty +20"))
	bg_check(world_location_of(hired.world, hired.fitting).form == .In &&
	         world_location_of(hired.world, hired.fitting).place == hired.crate)
	/* loyalty to his employer forms with it (decision 12) */
	store = knowledge_store_of(hired.knowledge, hired.kasimir)
	bg_check(knowledge_store_loyalty_to(store, test_referent_of(store, hired.foreman)) == 30)
	/* as the shift ends, the foreman, believing the job done, keeps its
	 * promise: the purse is in Kasimir's hand, and he finds it kept */
	bg_check(test_logged_by(hired.agency, hired.foreman, "scoring pay up +5 (-20, honesty +25)"))
	bg_check(world_location_of(hired.world, hired.pay).form == .Held_By &&
	         world_location_of(hired.world, hired.pay).place == hired.kasimir)
	t = test_pledge_from(store, test_referent_of(store, hired.foreman))
	bg_check(t != nil && t.settled == 1)
	/* a dishonest foreman can't bring itself to pay: the promise is broken,
	 * and Kasimir, the shift over and nothing in his hand, finds it so */
	stiffed = test_tempting_purse_(.Stiffed)
	bg_check(world_location_of(stiffed.world, stiffed.fitting).place == stiffed.crate)
	bg_check(test_logged_by(stiffed.agency, stiffed.foreman, "scoring pay up -20 (-20, honesty +0): unthinkable"))
	bg_check(world_location_of(stiffed.world, stiffed.pay).place == stiffed.foreman)
	store = knowledge_store_of(stiffed.knowledge, stiffed.kasimir)
	t     = test_pledge_from(store, test_referent_of(store, stiffed.foreman))
	bg_check(t != nil && t.settled == -1)
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, stiffed.foreman)) <
	         knowledge_store_trust_in(knowledge_store_of(hired.knowledge, hired.kasimir),
	                                  test_referent_of(knowledge_store_of(hired.knowledge, hired.kasimir), hired.foreman)))

	/* decision 15: deals can be posted. The foreman is out of Kasimir's
	 * sight, but its flyer by him says it hires, and where: he reads it at a
	 * glance, believes it there, goes to it, and is hired. Without the
	 * flyer, he asks the nearest, the carter, who has no work, and gives up */
	advert = test_tempting_purse_(.Advert)
	store  = knowledge_store_of(advert.knowledge, advert.kasimir)
	bg_check(knowledge_store_finding(store, "#Hires", test_referent_of(store, advert.foreman)) != nil &&
	         string(knowledge_store_finding(store, "#Hires", test_referent_of(store, advert.foreman)).rule) == "told")
	bg_check(test_logged_by(advert.agency, advert.kasimir, "toward R7 at (17, 10)"))
	bg_check(test_logged_by(advert.agency, advert.kasimir, "ask for work: say R7: #AskWork"))
	bg_check(test_logged_by(advert.agency, advert.kasimir, "hired by R7: deliver"))
	bg_check(world_location_of(advert.world, advert.fitting).place == advert.crate)
	bg_check(world_location_of(advert.world, advert.pay).place == advert.kasimir)
	unadvertised = test_tempting_purse_(.Unadvertised)
	bg_check(test_logged_by(unadvertised.agency, unadvertised.kasimir, "ask for work: say R4: #AskWork"))
	bg_check(test_logged_by(unadvertised.agency, unadvertised.kasimir, "R4 answered: #HaveNone"))
	bg_check(test_logged_by(unadvertised.agency, unadvertised.carter, "for work it hasn't"))
	bg_check(!test_logged_by(unadvertised.agency, unadvertised.kasimir, "hired by"))

	/* kept on the loan's last day, not before: the wages back in the carter's hand */
	repaid = test_tempting_purse_(.Repaid)
	bg_check(repaid.owedLate)
	bg_check(test_logged_by(repaid.agency, repaid.kasimir, "hand it back: give R"))
	bg_check(world_location_of(repaid.world, repaid.wages).form == .Held_By &&
	         world_location_of(repaid.world, repaid.wages).place == repaid.carter)
	bg_check(!in_keeping_of(repaid.world, repaid.wages, repaid.kasimir) &&
	         claimed_by_another(repaid.world, repaid.wages, repaid.kasimir))
	/* and promised so (§7): the carter holds it as a claim about the
	 * seventh day, kept when the wages are back in its hand, and trusts
	 * Kasimir more */
	bg_check(test_logged_by(repaid.agency, repaid.kasimir, "promising: say R"))
	store = knowledge_store_of(repaid.knowledge, repaid.carter)
	t     = test_pledge_from(store, test_referent_of(store, repaid.kasimir))
	bg_check(t != nil && t.settled == 1 && t.container == knowledge_store_self_referent(store))
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, repaid.kasimir)) == BG_TRUST + BG_CONFIRMED + 2)
	/* lost on the third day, it can't be: due, the carter, with Kasimir in
	 * sight and nothing back in its hand, finds the promise broken */
	lost  = test_tempting_purse_(.Lost)
	store = knowledge_store_of(lost.knowledge, lost.carter)
	t     = test_pledge_from(store, test_referent_of(store, lost.kasimir))
	bg_check(t != nil && t.settled == -1)
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, lost.kasimir)) == BG_TRUST - BG_REFUTED + 2)

	/* INSTITUTIONS.md decisions 5 and 8: everyone knows the town's law
	 * against theft from the start; Kasimir weighs it because he believes
	 * the purse is the merchant's, told so. Untold, seeing Mira watch, he
	 * knows the law but not that it applies, and takes it: belief, not
	 * truth (the law is truly broken all the same) */
	store = knowledge_store_of(base.knowledge, base.kasimir)
	bg_check(knowledge_store_law_count(store) == 1 && string(knowledge_store_law_at(store, 0).forbids) == "#Taking" &&
	         knowledge_store_law_at(store, 0).weighs == 40)
	bg_check(knowledge_store_finding(store, "#Owned", test_referent_of(store, base.purse)) != nil)
	untold = test_tempting_purse_(.Untold)
	bg_check(test_logged_by(untold.agency, untold.kasimir, "take the purse +20 (+30, honesty -5, scruples -5, lawful +0)"))
	bg_check(world_location_of(untold.world, untold.purse).place == untold.kasimir)

	/* INSTITUTIONS.md decision 6: a wrong reaches an institution through
	 * people. Mira overheard the merchant say the purse is its own, and saw
	 * Kasimir take it: taken. She tells the officer of the watch beside her
	 * what was taken, whose, and by whom; the officer, who saw nothing of
	 * it, believes it on her word */
	watch = test_tempting_purse_(.Watch)
	store = knowledge_store_of(watch.knowledge, watch.mira)
	bg_check(knowledge_store_finding(store, "#Taken", test_referent_of(store, watch.purse)) != nil &&
	         knowledge_store_finding(store, "#Taken", test_referent_of(store, watch.purse)).choice == test_referent_of(store, watch.kasimir))
	bg_check(test_logged_by(watch.agency, watch.mira, "[report the theft] tell the watch: say R"))
	/* KNOWLEDGE.md decision 15: seeing him wrong another, she trusts him less */
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, watch.kasimir)) == BG_TRUST - BG_WRONGED)
	store = knowledge_store_of(watch.knowledge, watch.officer)
	{
		taken: ^Finding
		owned: ^Finding

		taken = nil
		owned = nil
		for i: uint = 0; i < knowledge_store_finding_count(store); i += 1 {
			if string(knowledge_store_finding_at(store, i).kind) == "#Taken" do taken = knowledge_store_finding_at(store, i)
			if string(knowledge_store_finding_at(store, i).kind) == "#Owned" do owned = knowledge_store_finding_at(store, i)
		}
		bg_check(taken != nil && taken.choice == test_referent_of(store, watch.kasimir) && string(taken.rule) == "told")
		bg_check(owned != nil && owned.about == taken.about && owned.choice == test_referent_of(store, watch.merchant))
	}
	/* decision 7: the officer acts on it, its office's duty weighed like any
	 * goal: it arrests Kasimir, as the law against theft brings, and takes
	 * the purse back; both in the watch's custody. The law was truly broken */
	bg_check(test_log_index(watch.agency, watch.officer, "take it back: arrest R") <
	         test_log_index(watch.agency, watch.officer, "take it back: confiscate R"))
	bg_check(test_log_index(watch.agency, watch.officer, "take it back: confiscate R") != NOT_FOUND)
	bg_check(world_location_of(watch.world, watch.purse).form == .Held_By &&
	         world_location_of(watch.world, watch.purse).place == watch.officer)
	{
		claims:      []Entity_ID
		purseHeld:   bool
		kasimirHeld: bool
		who:         Entity_ID

		purseHeld   = false
		kasimirHeld = false
		claims      = claims_covering(watch.world, watch.purse)
		for i in 0 ..< len(claims) {
			if world_edges_from(watch.world, .Claimant, Entity_ID(claims[i]), ([^]Entity_ID)(&who), 1) != 0 &&
			   who == watch.officer {
				purseHeld = true
			}
		}
		claims = claims_covering(watch.world, watch.kasimir)
		for i in 0 ..< len(claims) {
			if world_edges_from(watch.world, .Claimant, Entity_ID(claims[i]), ([^]Entity_ID)(&who), 1) != 0 &&
			   who == watch.officer {
				kasimirHeld = true
			}
		}
		bg_check(purseHeld && kasimirHeld)
		/* the purse is still the merchant's: custody isn't ownership */
		bg_check(claimed_by_another(watch.world, watch.purse, watch.officer))
	}
	{
		arrested: bool

		arrested = false
		for i: uint = 0; i < world_event_count(watch.world); i += 1 {
			if string(world_event_at(watch.world, i).kind) == "arrested" && world_event_at(watch.world, i).subject == watch.kasimir &&
			   world_event_at(watch.world, i).other == watch.officer {
				arrested = true
			}
		}
		bg_check(arrested)
	}

	/* decision 7: arrested, Kasimir decides for himself. Disposed to abide
	 * (as by default), getting away is worth nothing to him: he complies,
	 * and stays. Not, he runs off, four tiles straight from the officer */
	store = knowledge_store_of(watch.knowledge, watch.kasimir)
	bg_check(knowledge_store_finding(store, "#Arrested", knowledge_store_self_referent(store)) != nil &&
	         knowledge_store_finding(store, "#Arrested", knowledge_store_self_referent(store)).choice == test_referent_of(store, watch.officer))
	bg_check(test_logged_by(watch.agency, watch.kasimir, "get away: +0 (+40, abiding -40)") ||
	         !test_logged_by(watch.agency, watch.kasimir, "[get away] run off"))
	bg_check(world_location_of(watch.world, watch.kasimir).x == 9 && world_location_of(watch.world, watch.kasimir).y == 10)
	flight = test_tempting_purse_(.Flight)
	bg_check(test_logged_by(flight.agency, flight.kasimir, "[get away] run off: flee R"))
	{
		k: Location
		o: Location

		k = world_location_of(flight.world, flight.kasimir)
		o = world_location_of(flight.world, flight.officer)
		bg_check(k.form == .On_Tile && (abs(k.x - o.x) >= 4 || abs(k.y - o.y) >= 4))
	}

	/* AGENCY.md §13: with a temper, he resists instead: he hits the officer,
	 * who is hurt and knows by whom, a threat it weighs against its duty */
	resist = test_tempting_purse_(.Resist)
	bg_check(test_logged_by(resist.agency, resist.kasimir,
	                        "weighing get away (R1): +40 (+40, abiding +0) against resist +60 (+20, abiding +0, temper +40, gentle +0)"))
	bg_check(test_logged_by(resist.agency, resist.kasimir, "[resist] fight them off: hit R"))
	{
		injury: i64

		injury = 0
		bg_check(world_get_field(resist.world, "Agent.injury", resist.officer, &injury) && injury == 15)
	}
	store = knowledge_store_of(resist.knowledge, resist.officer)
	bg_check(knowledge_store_finding(store, "#Struck", test_referent_of(store, resist.kasimir)) != nil &&
	         string(knowledge_store_finding(store, "#Struck", test_referent_of(store, resist.kasimir)).rule) == "felt")
	/* KNOWLEDGE.md decision 15: harmed by him, it trusts him less */
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, resist.kasimir)) <= BG_TRUST - BG_WRONGED)
	/* the threat is weighed: getting clear, worth the hurt, not the officer's
	 * temper; hitting back, nothing to it. It finishes its duty first, and
	 * by then Kasimir has run, so there is nothing to get clear of */
	bg_check(test_logged_by(resist.agency, resist.officer, "get clear (R"))
	bg_check(test_logged_by(resist.agency, resist.officer, ": +7 (injury +7, temper +0)"))
	bg_check(test_logged_by(resist.agency, resist.officer, "is gone from where it was"))
	bg_check(test_log_index(resist.agency, resist.officer, "[recover it and arrest the taker] done") <
	         test_log_index(resist.agency, resist.officer, "[get clear]"))
	/* AGENCY.md decision 14: some considerations veto. Holding never to
	 * strike anyone, he doesn't resist, whatever his temper adds: he runs */
	gentle = test_tempting_purse_(.Gentle)
	bg_check(test_logged_by(gentle.agency, gentle.kasimir, "(+20, abiding +0, temper +40, gentle -10, a veto)"))
	bg_check(!test_logged_by(gentle.agency, gentle.kasimir, "fight them off"))
	bg_check(test_logged_by(gentle.agency, gentle.kasimir, "[get away] run off: flee R"))
	/* of the watch, the officer doesn't report the theft to itself */
	bg_check(!test_logged_by(resist.agency, resist.officer, "report the theft"))

	/* AGENCY.md decision 12: loyalty is a weighted relation. The merchant's
	 * daughter knows it of him when she sees him; she trusts him more
	 * (KNOWLEDGE.md decision 15: a tenth of a point a point, and her
	 * disposition to trust adds its own), and reporting
	 * the theft of what she believes his is worth more to her. Kasimir owes
	 * him nothing, and the bond is saved and restored with her knowledge */
	kin   = test_tempting_purse_(.Kin)
	store = knowledge_store_of(kin.knowledge, kin.mira)
	bg_check(knowledge_store_loyalty_to(store, test_referent_of(store, kin.merchant)) == 60)
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, kin.merchant)) ==
	         knowledge_store_referent(store, test_referent_of(store, kin.merchant)).trust + 6 + 3)
	bg_check(test_logged_by(kin.agency, kin.mira, "report the theft (R2): +33 (+15, loyal +18)"))
	bg_check(test_logged_by(watch.agency, watch.mira, "report the theft (R2): +15 (+15, loyal +0)"))
	store = knowledge_store_of(kin.knowledge, kin.kasimir)
	bg_check(knowledge_store_loyalty_to(store, test_referent_of(store, kin.merchant)) == 0)
	bg_check(ns_contains(kin.text, " 60 1 "))

	/* AGENCY.md decision 11: the gain from a lie. Asked by the merchant
	 * where the purse is, Kasimir, holding it and told it is the merchant's,
	 * weighs denying it: the theft the truth would expose (the law weighs
	 * 40), against his honesty and the merchant seeing it in his hand. He
	 * says he doesn't know. Never told whose it was, he has nothing to hide,
	 * and says he has it */
	asked = test_tempting_purse_(.Asked)
	bg_check(test_logged_by(asked.agency, asked.kasimir, "deny it +15 (exposing +40, honesty -5, watched -20): lying"))
	{
		_, said := test_said_with(asked.world, asked.kasimir, "#DontKnow")
		bg_check(said)
	}
	askedUntold = test_tempting_purse_(.Asked_Untold)
	bg_check(test_logged_by(askedUntold.agency, askedUntold.kasimir,
	                        "deny it -25 (nothing to hide +0, honesty -5, watched -20): telling the truth"))
	{
		_, held := test_said_with(askedUntold.world, askedUntold.kasimir, "#IsHeld")
		bg_check(held)
		_, denied := test_said_with(askedUntold.world, askedUntold.kasimir, "#DontKnow")
		bg_check(!denied)
	}

	/* 1: C: no one is there, and Kasimir decides just the same */
	alone = test_tempting_purse_(.No_Witness)
	bg_check(slice.equal(agency_log_of(alone.agency, alone.kasimir), agency_log_of(base.agency, base.kasimir)))

	/* 6: determinism */
	again = test_tempting_purse_(.Base)
	bg_check(world_state_hash(again.world) == world_state_hash(base.world))
	bg_check(again.text == base.text)

	/* the wages lent for a week: Kasimir's taking them up breaks no law
	 * within it, and does once it is over (the keeping has lapsed) */
	lent := action_make("take", honest.kasimir, honest.wages, NO_ENTITY)
	bg_check(in_keeping_of(honest.world, honest.wages, honest.kasimir) && len(laws_broken(honest.world, lent)) == 0)
	world_set_time(honest.world, time_make(world_time(honest.world).ms + 8 * 86400000))
	bg_check(!in_keeping_of(honest.world, honest.wages, honest.kasimir) && len(laws_broken(honest.world, lent)) == 1)
}


/* AGENCY.md §7: in the workshop, the smith, having looked into the bin,
 * promises the worker beside it that the nails will be in the crate by the
 * deadline. The worker looks into the crate once early, and once after. */
Promise_Run :: struct {
	world:        ^World,
	knowledge:    ^Knowledge,
	agency:       ^Agency,
	crate:        Entity_ID,
	earlySettled: i32,          /* the worker's promise testimony, after looking early */
	text:         string,
}


test_look_into :: proc(st: ^Stage, agent: Entity_ID, container: Entity_ID, x: i32, y: i32) {
	error: string

	test_stage_move(st, agent, x, y)
	error = ""
	bg_check(perform(st.w, st.c, action_make("look_in", agent, container, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 500))
}


test_promise_run :: proc(deadline: i64, told: bool) -> Promise_Run {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	smith:      ^Knowledge_Store
	g:          ^Proposal_Group
	h:          [8]Entity_ID
	error:      string
	run:        Promise_Run
	carter:     Entity_ID

	st.w       = test_world(59)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	committer_submit(st.c, workshop_setup(false, &h))
	scheduler_run_until(st.s, time_make(1))
	g         = proposal_group_group_with_phase(.System, "setup: the crate")
	run.crate = proposal_group_create(g, "crate", "crate", on_tile(6, 4, 0))
	carter    = proposal_group_create(g, "carter", "carter", on_tile(12, 12, 0)) if told else NO_ENTITY
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2))
	run.crate = proposal_group_id_for(g, run.crate)
	carter    = proposal_group_id_for(g, carter) if carter != NO_ENTITY else NO_ENTITY

	/* the smith looks into the bin; the worker stands beside it */
	error = ""
	bg_check(perform(st.w, st.c, action_make("look_in", 5, 1, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(3))
	test_stage_move(&st, 4, 3, 5)

	/* the promise */
	smith = knowledge_store_of(knowledge, 5)
	bg_check(agency_promise(agency, 5, test_referent_of(smith, 4), test_referent_of(smith, 2), test_referent_of(smith, run.crate),
	                        world_time(st.w).ms + deadline))
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))

	/* the worker looks into the crate early: not due, nothing settled */
	test_look_into(&st, 4, run.crate, 7, 5)
	run.earlySettled = (i32(knowledge_store_testimony_at(knowledge_store_of(knowledge, 4), 0).settled)
	                    if knowledge_store_testimony_count(knowledge_store_of(knowledge, 4)) != 0 else 9)
	test_stage_move(&st, 4, 3, 7)

	/* after the deadline, it looks again; or, told, a carter who looked
	 * tells it where the nails are, and it doesn't look itself */
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + deadline + 5000))
	if carter != NO_ENTITY {
		seen:  ^Knowledge_Store
		claim: string
		found: bool

		test_look_into(&st, carter, run.crate, 7, 4)
		test_stage_move(&st, carter, 3, 6)
		seen  = knowledge_store_of(knowledge, carter)
		claim, found = knowledge_store_claim_about(seen, test_referent_of(seen, 2))
		bg_check(found)
		test_stage_say(&st, carter, 4, claim)
	} else {
		test_look_into(&st, 4, run.crate, 7, 5)
	}
	run.world     = st.w
	run.knowledge = knowledge
	run.agency    = agency
	run.text      = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


test_promises :: proc() {
	kept:   Promise_Run
	broken: Promise_Run
	again:  Promise_Run
	heard:  Promise_Run
	store:  ^Knowledge_Store
	t:      ^Testimony

	/* kept: the promise is the smith's commitment, and it delivers */
	kept = test_promise_run(60000, false)
	bg_check(test_logged_by(kept.agency, 5, "promising: say R"))
	bg_check(test_logged_by(kept.agency, 5, "weighing deliver it: +20 (promise, duty +20, urgency +0) against nothing: switching"))
	bg_check(test_logged_by(kept.agency, 5, "[hold it] pick it up: take R"))
	bg_check(test_logged_by(kept.agency, 5, "[deliver it] bring it: put_in R"))
	bg_check(test_logged_by(kept.agency, 5, "[deliver it] done"))
	bg_check(world_location_of(kept.world, 2).form == .In && world_location_of(kept.world, 2).place == kept.crate)
	/* the worker held it as a promise, about then: looking early settled nothing; after, kept, and it trusts the smith more */
	store = knowledge_store_of(kept.knowledge, 4)
	t     = knowledge_store_testimony_at(store, 0) if knowledge_store_testimony_count(store) != 0 else nil
	bg_check(t != nil && t.attribution == .Pledged && t.source == test_referent_of(store, 5))
	bg_check(kept.earlySettled == 0)
	bg_check(t != nil && t.settled == 1 && knowledge_store_trust_in(store, t.source) == BG_TRUST + BG_CONFIRMED)
	bg_check(ns_contains(knowledge_dump(kept.knowledge, 4), "promised, root R"))

	/* broken: three seconds isn't enough; the window closes, the promise is
	 * broken, and the worker, finding the crate empty after the deadline,
	 * trusts the smith less */
	broken = test_promise_run(3000, false)
	bg_check(test_logged_by(broken.agency, 5, "deliver it is over: its window has closed; the promise is broken"))
	bg_check(world_location_of(broken.world, 2).form != .In || world_location_of(broken.world, 2).place != broken.crate)
	store = knowledge_store_of(broken.knowledge, 4)
	t     = knowledge_store_testimony_at(store, 0) if knowledge_store_testimony_count(store) != 0 else nil
	bg_check(broken.earlySettled == 0)
	bg_check(t != nil && t.settled == -1 && knowledge_store_trust_in(store, t.source) == BG_TRUST - BG_REFUTED)

	/* the same on replay */
	again = test_promise_run(60000, false)
	bg_check(again.text == kept.text)

	/* learned without looking (§7: hearers perceive it "when they learn
	 * the outcome"): the worker doesn't look; a carter who did tells it the
	 * nails are in the crate, after the deadline, and it finds the promise
	 * kept on the carter's word, trusting the smith more */
	heard = test_promise_run(60000, true)
	store = knowledge_store_of(heard.knowledge, 4)
	t     = nil
	for i: uint = 0; i < knowledge_store_testimony_count(store); i += 1 {
		if knowledge_store_testimony_at(store, i).attribution == .Pledged do t = knowledge_store_testimony_at(store, i)
	}
	bg_check(t != nil && t.source == test_referent_of(store, 5) && t.settled == 1)
	bg_check(knowledge_store_trust_in(store, test_referent_of(store, 5)) == BG_TRUST + BG_CONFIRMED)
	/* it looked only the once, early */
	{
		looks: uint

		looks = 0
		for i: uint = 0; i < world_event_count(heard.world); i += 1 {
			if string(world_event_at(heard.world, i).kind) == "looked" && world_event_at(heard.world, i).actor == 4 &&
			   world_event_at(heard.world, i).other == heard.crate {
				looks += 1
			}
		}
		bg_check(looks == 1)
	}
}


/* --- two hands, one seal ---------------------------------------------------- */

/* ACTIONS.md Scenario 2's conflict, on the committer: the spare seal on the
 * bench, reserved for A (the worker); A and B (the smith) take it at the same
 * boundary. 1 if A gets it, 2 if B does. `swap` creates B first, so their
 * IDs swap. */
test_seal_race :: proc(seed: u64, quickA: i64, quickB: i64, swap: bool, operation: cstring) -> i32 {
	w:     ^World
	c:     ^Committer
	g:     ^Proposal_Group
	ga:    ^Proposal_Group
	gb:    ^Proposal_Group
	seal:  Entity_ID
	a:     Entity_ID
	b:     Entity_ID
	claim: Entity_ID

	w    = test_world(seed)
	c    = test_committer(w)
	g    = proposal_group_group_with_phase(.System, "setup: the bench")
	seal = proposal_group_create(g, "seal", "seal", on_tile(6, 6, 0))
	b    = proposal_group_create(g, "smith", "B", on_tile(7, 6, 0)) if swap else NO_ENTITY
	a    = proposal_group_create(g, "worker", "A", on_tile(5, 6, 0))
	if !swap do b = proposal_group_create(g, "smith", "B", on_tile(7, 6, 0))
	claim = proposal_group_create(g, "reservation", "A's reservation", location_make_none())
	proposal_group_relate(g, .Claimant, whole(claim), whole(a))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(seal))
	proposal_group_set_of_to(g, "Agent.quickness", whole(a), quickA)
	proposal_group_set_of_to(g, "Agent.quickness", whole(b), quickB)
	committer_submit(c, g)
	committer_commit_boundary(c)
	seal = proposal_group_id_for(g, seal)
	a    = proposal_group_id_for(g, a)
	b    = proposal_group_id_for(g, b)
	world_set_boundary(w, 7)
	ga = proposal_group_group_with_phase(.Action, "A takes the seal")
	proposal_group_set_actor(ga, a)
	proposal_group_set_weight(ga, contest_weight(w, a, operation))
	proposal_group_move_to_expecting(ga, whole(seal), held_by(a, 0), on_tile(6, 6, 0))
	gb = proposal_group_group_with_phase(.Action, "B takes the seal")
	proposal_group_set_actor(gb, b)
	proposal_group_set_weight(gb, contest_weight(w, b, operation))
	proposal_group_move_to_expecting(gb, whole(seal), held_by(b, 0), on_tile(6, 6, 0))
	committer_submit(c, ga)
	committer_submit(c, gb)
	committer_commit_boundary(c)
	if proposal_group_applied(ga) == proposal_group_applied(gb) do return 0
	return 1 if proposal_group_applied(ga) else 2
}


/* The scenario with activities: A and B start taking the seal up at the
 * same boundary; B, if `agency`, decides for itself, `respectful` of
 * reservations it knows of, and A tells it first that the seal is A's: by
 * saying so (1), or by a tag beside the seal B sights, legible from a step
 * away (2) or only from on it (3). */
Seal_Run :: struct {
	world:     ^World,
	committer: ^Committer,
	knowledge: ^Knowledge,
	agency:    ^Agency,
	seal:      Entity_ID,
	a:         Entity_ID,
	b:         Entity_ID,
}


test_seal_scene :: proc(seed: u64, agency: i32, respectful: i64) -> Seal_Run {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	minds:      ^Agency
	g:          ^Proposal_Group
	h:          [3]Entity_ID
	error:      string
	reserved:   string
	action:     Action
	run:        Seal_Run

	st.w       = test_world(seed)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	minds      = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(minds, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(minds))
	g    = proposal_group_group_with_phase(.System, "setup: the bench")
	h[0] = proposal_group_create(g, "seal", "seal", on_tile(6, 6, 0))
	h[1] = proposal_group_create(g, "worker", "A", on_tile(5, 6, 0))
	h[2] = proposal_group_create(g, "smith", "B", on_tile(6, 7, 0))
	proposal_group_set_of_to(g, "Agent.respectful", whole(h[2]), respectful)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	run.seal = proposal_group_id_for(g, h[0])
	run.a    = proposal_group_id_for(g, h[1])
	run.b    = proposal_group_id_for(g, h[2])
	if agency != 0 {
		/* A tells B the seal is A's; B wants it */
		reserved = knowledge_store_reservation_of(knowledge_store_of(knowledge, run.a),
		                                          test_referent_of(knowledge_store_of(knowledge, run.a), run.seal),
		                                          knowledge_store_self_referent(knowledge_store_of(knowledge, run.a)))
		error = ""
		if agency == 1 {
			action         = action_make("say", run.a, run.b, NO_ENTITY)
			action.content = world_intern(st.w, ns_utf8(reserved))
			bg_check(perform(st.w, st.c, action, 0, &error) != nil)
		} else {
			/* a tag beside it, in A's hand: B sights it */
			g    = proposal_group_group_with_phase(.System, "setup: A's tag")
			h[0] = proposal_group_create(g, "seal_tag", "tag", on_tile(6, 6, 0))
			proposal_group_set_of_to_text(g, "Record.writing", whole(h[0]),
			                              world_intern(st.w, ns_utf8(fmt.tprintf("#Writing & {{ author: %s, entries: [%s] }}",
			                                                                     knowledge_store_describe_looks(knowledge_store_of(knowledge, run.a),
			                                                                                                    knowledge_store_self_referent(knowledge_store_of(knowledge, run.a))),
			                                                                     reserved))))
			if agency == 3 do proposal_group_set_of_to(g, "Label.legible", whole(h[0]), 0)
			committer_submit(st.c, g)
		}
		scheduler_run_until(st.s, time_make(1000))
		bg_check(agency_commit(minds, run.b, "get_the_seal"))
		/* A starts as B's decision does: both takes complete at one boundary */
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1))
		bg_check(perform(st.w, st.c, action_make("take_up", run.a, run.seal, NO_ENTITY), 0, &error) != nil)
	} else {
		error = ""
		bg_check(perform(st.w, st.c, action_make("take_up", run.a, run.seal, NO_ENTITY), 0, &error) != nil)
		bg_check(perform(st.w, st.c, action_make("take_up", run.b, run.seal, NO_ENTITY), 0, &error) != nil)
	}
	scheduler_run_until(st.s, time_make(6000))
	run.world     = st.w
	run.committer = st.c
	run.knowledge = knowledge
	run.agency    = minds
	return run
}


test_two_hands :: proc() {
	race:     Seal_Run
	respect:  Seal_Run
	ignore:   Seal_Run
	store:    ^Knowledge_Store
	seal:     ^Referent
	trace:    string
	winner:   Entity_ID
	loser:    Entity_ID
	a:        i32
	swapped:  i32
	weighted: i32
	even:     i32
	w:        i32

	/* 1, 2: exactly one take applies; the other is rejected whole, and its
	 * activity fails with the reason; the loser sees the seal in the winner's
	 * hand */
	race = test_seal_scene(61, 0, 50)
	bg_check(world_location_of(race.world, race.seal).form == .Held_By)
	winner = world_location_of(race.world, race.seal).place
	loser  = race.b if winner == race.a else race.a
	bg_check(winner == race.a || winner == race.b)
	trace = strings.join(committer_trace(race.committer), "\n", context.temp_allocator)
	bg_check(ns_contains(trace, ": failed ("))
	store = knowledge_store_of(race.knowledge, loser)
	seal  = knowledge_store_referent(store, test_referent_of(store, race.seal))
	bg_check(seal != nil && seal.form == .Held_By && seal.container == test_referent_of(store, winner))

	/* 3, 5, 6: fair: with equal weights, over 1,000 seeds, each wins about
	 * half; swapping their IDs leaves that so; the reservation blocks
	 * nothing; the same seed, the same winner */
	a        = 0
	swapped  = 0
	weighted = 0
	even     = 0
	for seed: u64 = 1; seed <= 1000; seed += 1 {
		w = test_seal_race(seed, 10, 10, false, "take_up")
		bg_check(w != 0)
		if w == 1 do a += 1
		if test_seal_race(seed, 10, 10, true, "take_up") == 1 do swapped += 1
		/* 4: weighted 1 to 3, B wins about three times in four */
		if test_seal_race(seed, 10, 30, false, "take_up") == 2 do weighted += 1
		/* ACTIONS.md decision 13: an operation that declares nothing to weigh
		 * its contests draws evenly, however quick */
		if test_seal_race(seed, 10, 30, false, "look_in") == 2 do even += 1
	}
	bg_check(a > 430 && a < 570)
	bg_check(swapped > 430 && swapped < 570)
	bg_check(weighted > 700 && weighted < 800)
	bg_check(even > 430 && even < 570)
	bg_check(test_seal_race(77, 10, 10, false, "take_up") == test_seal_race(77, 10, 10, false, "take_up"))

	/* A: B, told the seal is A's and disposed to respect that, never starts:
	 * taking it scores below nothing; A takes it */
	respect = test_seal_scene(61, 1, 50)
	bg_check(test_logged_by(respect.agency, respect.b, "take the seal -30 (+10, reserved -40)"))
	bg_check(!test_logged_by(respect.agency, respect.b, "take_up R"))
	bg_check(world_location_of(respect.world, respect.seal).place == respect.a)
	/* or B sights a tag beside the seal saying so, a step away, and reads
	 * it at a glance (ACTIONS.md §7's physical marker): the same */
	respect = test_seal_scene(61, 2, 50)
	bg_check(test_logged_by(respect.agency, respect.b, "take the seal -30 (+10, reserved -40)"))
	bg_check(world_location_of(respect.world, respect.seal).place == respect.a)
	store = knowledge_store_of(respect.knowledge, respect.b)
	bg_check(knowledge_store_finding(store, "#Reserved", test_referent_of(store, respect.seal)) != nil)
	/* a tag legible only from on it, a step away, says nothing */
	ignore = test_seal_scene(61, 3, 50)
	bg_check(test_logged_by(ignore.agency, ignore.b, "take the seal +10 (+10, unreserved +0)"))
	store = knowledge_store_of(ignore.knowledge, ignore.b)
	bg_check(knowledge_store_finding(store, "#Reserved", test_referent_of(store, ignore.seal)) == nil)
	/* B: B, who doesn't mind, races A for it, and wins the draw: the
	 * reservation doesn't block the commit. A's take fails with the reason;
	 * A, who knew the seal was reserved for it, sees it in B's hand */
	for w = 61; w < 81; w += 1 {
		ignore = test_seal_scene(u64(w), 1, 0)
		if world_location_of(ignore.world, ignore.seal).place == ignore.b do break
	}
	bg_check(test_logged_by(ignore.agency, ignore.b, "take the seal +10 (+10, reserved +0)"))
	bg_check(test_logged_by(ignore.agency, ignore.b, "take_up R"))
	bg_check(world_location_of(ignore.world, ignore.seal).form == .Held_By &&
	         world_location_of(ignore.world, ignore.seal).place == ignore.b)
	trace = strings.join(committer_trace(ignore.committer), "\n", context.temp_allocator)
	bg_check(ns_contains(trace, "rejected: 1 is no longer where it was taken from"))
	store = knowledge_store_of(ignore.knowledge, ignore.a)
	seal  = knowledge_store_referent(store, test_referent_of(store, ignore.seal))
	bg_check(seal != nil && seal.form == .Held_By && seal.container == test_referent_of(store, ignore.b))
}


/* --- the coat at dusk ------------------------------------------------------- */

Coat_Run :: struct {
	world:       ^World,
	knowledge:   ^Knowledge,
	porter:      Entity_ID,
	visitor:     Entity_ID,
	smith:       Entity_ID,
	atDusk:      string,        /* the visitor's referent, after the dusk sighting */
	compactions: uint,          /* of the porter's knowledge arena */
	before:      i32,           /* the hypothesis' credence, made */
	merged:      bool,          /* no hypothesis left after the third sighting */
	text:        string,
}


/* CONTENT_LANGUAGE.md Scenario 3, "the coat at dusk": the porter (Ulla) sees
 * a visitor in a grey coat by day; at dusk, a figure three tiles off whose
 * coat looks only dark; next morning, a figure in a brown coat (B: a
 * stranger of the visitor's build; A: the visitor, in a brown coat now); a
 * week later, the brown-coated figure again. */
test_coat_at_dusk_ :: proc(sameOne: bool, compactAlways: bool, thrice: bool, together: bool) -> Coat_Run {
	st:        Stage
	knowledge: ^Knowledge
	g:         ^Proposal_Group
	figure:    Entity_ID
	run:       Coat_Run
	day:       i64

	day        = 86400000
	st.w       = test_world(67)
	st.c       = test_committer(st.w)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	knowledge_set_compact_always(knowledge, compactAlways)
	g           = proposal_group_group_with_phase(.System, "setup: the yard")
	run.porter  = proposal_group_create(g, "porter", "Ulla", on_tile(10, 10, 0))
	run.visitor = proposal_group_create(g, "agent_a", "the visitor", on_tile(12, 10, 0))
	run.smith   = proposal_group_create(g, "stranger", "the stranger", on_tile(30, 30, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	run.porter  = proposal_group_id_for(g, run.porter)
	run.visitor = proposal_group_id_for(g, run.visitor)
	run.smith   = proposal_group_id_for(g, run.smith)
	test_stage_move(&st, run.visitor, 25, 25)

	/* dusk: a figure three tiles off, its coat only dark */
	knowledge_set_dusk(knowledge, true)
	scheduler_run_until(st.s, time_make(3600000))
	test_stage_move(&st, run.visitor, 13, 10)
	run.atDusk = knowledge_store_describe_referent(knowledge_store_of(knowledge, run.porter),
	                                               test_referent_of(knowledge_store_of(knowledge, run.porter), run.visitor))
	test_stage_move(&st, run.visitor, 25, 25)
	knowledge_set_dusk(knowledge, false)

	/* the morning: a figure in a brown coat at the pump */
	figure = run.visitor if sameOne else run.smith
	scheduler_run_until(st.s, time_make(12 * 3600000))
	g = proposal_group_group_with_phase(.System, "setup: a figure in a brown coat")
	if sameOne do proposal_group_set_of_to(g, "Agent.coat", whole(figure), i64(tri.type_named(world_tri(st.w), "\"brown\"")))
	proposal_group_move_to(g, whole(figure), on_tile(13, 11, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(12 * 3600000 + 1000))
	run.before = (i32(knowledge_store_identity_at(knowledge_store_of(knowledge, run.porter), 0).credence)
	              if knowledge_store_identity_count(knowledge_store_of(knowledge, run.porter)) != 0 else 99)
	test_stage_move(&st, figure, 30, 30)

	/* a week passes; the brown-coated figure again */
	scheduler_run_until(st.s, time_make(12 * 3600000 + 7 * day))
	test_stage_move(&st, figure, 13, 11)

	/* and again, a week later (KNOWLEDGE.md decision 13); then the visitor
	 * and the stranger together */
	if thrice {
		test_stage_move(&st, figure, 30, 30)
		scheduler_run_until(st.s, time_make(12 * 3600000 + 14 * day))
		test_stage_move(&st, figure, 13, 11)
		run.merged = knowledge_store_identity_count(knowledge_store_of(knowledge, run.porter)) == 0
	}
	if together {
		test_stage_move(&st, run.visitor, 12, 10)
		test_stage_move(&st, run.smith, 13, 11)
	}

	run.world     = st.w
	run.knowledge = knowledge
	run.text      = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge)})
	run.compactions = knowledge_store_compactions(knowledge_store_of(knowledge, run.porter))
	return run
}


test_coat_at_dusk :: proc() {
	b:         Coat_Run
	a:         Coat_Run
	again:     Coat_Run
	compacted: Coat_Run
	store:     ^Knowledge_Store
	h:         ^Identity
	w2:        ^World
	restored:  ^Knowledge
	deferred:  []^Proposal_Group
	error:     string
	position:  u64

	b     = test_coat_at_dusk_(false, false, false, false)
	store = knowledge_store_of(b.knowledge, b.porter)

	/* at dusk the coat looks only dark; it unifies with the visitor's grey,
	 * and memory keeps the more specific */
	bg_check(ns_contains(b.atDusk, "coat: \"grey\""))

	/* 1, 2: the brown coat fails to unify at exactly one path, the coat; a
	 * coat changes daily, so it is a new referent that may be the visitor,
	 * not an error */
	bg_check(knowledge_store_identity_count(store) == 1)
	h = knowledge_store_identity_at(store, 0) if knowledge_store_identity_count(store) != 0 else nil
	bg_check(h != nil && string(cstring(&h.paths[0])) == "coat")
	bg_check(h != nil && h.b == test_referent_of(store, b.visitor) && h.a == test_referent_of(store, b.smith))
	bg_check(b.before == BG_PRIOR + 3 * 5 - 5)          /* five features agree, the coat doesn't */

	/* 3, 4: a week on, both coats have decayed past telling; the brown-coated
	 * figure fits both, and that alone raises the credence that they are one */
	bg_check(h != nil && h.credence == b.before + 10)
	/* B: they are not: the inspector flags the false merge */
	bg_check(ns_contains(knowledge_dump(b.knowledge, b.porter), "truly not: false merge"))

	/* A: the visitor itself, in a brown coat: the decayed memory leads to the
	 * right answer, for a weak reason */
	a     = test_coat_at_dusk_(true, false, false, false)
	store = knowledge_store_of(a.knowledge, a.porter)

	bg_check(knowledge_store_identity_count(store) == 1 && knowledge_store_identity_at(store, 0).credence == b.before + 10)
	bg_check(ns_contains(knowledge_dump(a.knowledge, a.porter), "truly the same"))

	/* the same on replay, and saved */
	again = test_coat_at_dusk_(false, false, false, false)
	bg_check(again.text == b.text)

	/* 6: compaction: the porter's knowledge arena compacted at every
	 * boundary changes nothing observable; the save is the same to the byte */
	compacted = test_coat_at_dusk_(false, true, false, false)
	bg_check(compacted.compactions >= 5 && compacted.compactions > b.compactions)
	bg_check(compacted.text == b.text)
	bg_check(knowledge_dump(compacted.knowledge, compacted.porter) == knowledge_dump(b.knowledge, b.porter))
	w2 = restore(b.text, world_content_build(b.world), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	known := knowledge_as_saved_system(restored)
	known.restore_saved_state(known.data, saved_domain_state(b.text, "knowledge"))
	bg_check(knowledge_dump(restored, b.porter) == knowledge_dump(b.knowledge, b.porter))

	/* KNOWLEDGE.md decision 13: believed the same past the threshold (20 dB),
	 * two referents merge. A third sighting that fits both: the porter now
	 * holds one referent for the visitor and the brown-coated figure, the
	 * older of the two, with no hypothesis left. In B it is wrong, two
	 * people taken for one; it stands until they are seen together, when
	 * they are two again */
	{
		merged: Coat_Run
		apart:  Coat_Run
		ms:     ^Knowledge_Store
		older:  u32

		store  = knowledge_store_of(b.knowledge, b.porter)
		older  = test_referent_of(store, b.visitor)
		merged = test_coat_at_dusk_(false, false, true, false)
		ms     = knowledge_store_of(merged.knowledge, merged.porter)
		bg_check(merged.merged && knowledge_store_identity_count(ms) == 0)
		bg_check(test_referent_of(ms, merged.smith) == older && test_referent_of(ms, merged.visitor) == 0)
		apart = test_coat_at_dusk_(false, false, true, true)
		ms    = knowledge_store_of(apart.knowledge, apart.porter)
		bg_check(test_referent_of(ms, apart.smith) != 0 && test_referent_of(ms, apart.visitor) != 0 &&
		         test_referent_of(ms, apart.smith) != test_referent_of(ms, apart.visitor))
	}
}


/* --- the nut of unknown size ------------------------------------------------- */

Nut_Run :: struct {
	world:     ^World,
	knowledge: ^Knowledge,
	agency:    ^Agency,
	nut:       Entity_ID,
	fromAfar:  string,          /* the worker's referent of the nut, before it looks closer */
	text:      string,
}


/* CONTENT_LANGUAGE.md Scenario 2, "the nut of unknown size": the worker,
 * holding a spanner, is to tighten the pump's gland nut, four tiles off,
 * whose size it sees only roughly from there. `spare`, if not NULL: another
 * spanner lying on the bench by the nut. */
test_nut_run :: proc(nut: cstring, spanner: cstring, omniscient: bool, spare: cstring) -> Nut_Run {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	worker:     Entity_ID
	run:        Nut_Run

	st.w       = test_world(71)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	knowledge_set_omniscient(knowledge, omniscient)
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g       = proposal_group_group_with_phase(.System, "setup: the pump")
	worker  = proposal_group_create(g, "worker", "Oskar", on_tile(2, 2, 0))
	proposal_group_create(g, spanner, "spanner", held_by(worker, 0))
	run.nut = proposal_group_create(g, nut, "gland nut", on_tile(6, 2, 0))
	if spare != nil do proposal_group_create(g, spare, "spare spanner", on_tile(5, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker   = proposal_group_id_for(g, worker)
	run.nut  = proposal_group_id_for(g, run.nut)
	run.fromAfar = knowledge_store_describe_referent(knowledge_store_of(knowledge, worker),
	                                                 test_referent_of(knowledge_store_of(knowledge, worker), run.nut))
	bg_check(agency_commit(agency, worker, "tighten_nut"))
	scheduler_run_until(st.s, time_make(30000))
	run.world     = st.w
	run.knowledge = knowledge
	run.agency    = agency
	run.text      = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


/* CONTENT_LANGUAGE.md Scenario 2's variant C: the worker has seen the nut
 * plainly (19 mm) from beside it, then stands four tiles off; it half
 * remembers the nut was replaced with a 22 mm one, at `doubt` in 1000. */
test_doubtful_nut_run :: proc(doubt: i32, doubt24: i32, massSeen: ^i64) -> Nut_Run {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	store:      ^Knowledge_Store
	worker:     Entity_ID
	run:        Nut_Run

	st.w       = test_world(71)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g       = proposal_group_group_with_phase(.System, "setup: the pump")
	worker  = proposal_group_create(g, "worker", "Oskar", on_tile(5, 2, 0))
	proposal_group_create(g, "spanner_19", "spanner", held_by(worker, 0))
	run.nut = proposal_group_create(g, "gland_nut", "gland nut", on_tile(6, 2, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker  = proposal_group_id_for(g, worker)
	run.nut = proposal_group_id_for(g, run.nut)
	test_stage_move(&st, worker, 2, 2)
	store = knowledge_store_of(knowledge, worker)
	knowledge_store_suppose(store, "size: 22mm", test_referent_of(store, run.nut), doubt)
	if doubt24 != 0 do knowledge_store_suppose(store, "size: 24mm", test_referent_of(store, run.nut), doubt24)
	massSeen^    = i64(knowledge_store_supposed_mass_of(store, test_referent_of(store, run.nut)))
	run.fromAfar = knowledge_dump(knowledge, worker)
	{
		restored: ^Knowledge
		text:     string

		/* the doubt is saved */
		text     = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge)})
		restored = autorelease(knowledge_init_with_world(st.w))
		known := knowledge_as_saved_system(restored)
		known.restore_saved_state(known.data, saved_domain_state(text, "knowledge"))
		bg_check(knowledge_dump(restored, worker) == run.fromAfar)
	}
	bg_check(agency_commit(agency, worker, "tighten_nut"))
	scheduler_run_until(st.s, time_make(30000))
	run.world     = st.w
	run.knowledge = knowledge
	run.agency    = agency
	run.text      = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


/* The menu, beside the nut, while it half remembers a 22 mm one at `doubt`
 * in 1000: the tighten entry, described. */
test_doubtful_menu :: proc(doubt: i32) -> string {
	st:        Stage
	knowledge: ^Knowledge
	g:         ^Proposal_Group
	store:     ^Knowledge_Store
	menu:      ^Menu
	worker:    Entity_ID
	nut:       Entity_ID

	st.w      = test_world(71)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: the pump")
	worker = proposal_group_create(g, "worker", "Oskar", on_tile(5, 2, 0))
	proposal_group_create(g, "spanner_19", "spanner", held_by(worker, 0))
	nut    = proposal_group_create(g, "gland_nut", "gland nut", on_tile(6, 2, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	nut    = proposal_group_id_for(g, nut)
	store  = knowledge_store_of(knowledge, worker)
	if doubt != 0 do knowledge_store_suppose(store, "size: 22mm", test_referent_of(store, nut), doubt)
	menu = menu_for_world_believed(store, st.w, true)
	for i: uint = 0; i < menu_count(menu); i += 1 {
		if string(menu_action_at(menu, i).operation) == "tighten" do return menu_describe_at(menu, i)
	}
	return ""
}


/* AGENCY.md §7's urgency curve: the worker, beside the nut, is committed
 * to tightening it within [0, 100 s], and takes it up at 90 s: by the goal's
 * curve, barely urgent yet. */
test_urgent_nut :: proc() -> ^Agency {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	worker:     Entity_ID

	st.w       = test_world(71)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g      = proposal_group_group_with_phase(.System, "setup: the pump")
	worker = proposal_group_create(g, "worker", "Oskar", on_tile(5, 2, 0))
	proposal_group_create(g, "spanner_19", "spanner", held_by(worker, 0))
	proposal_group_create(g, "gland_nut", "gland nut", on_tile(6, 2, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(90000))
	worker = proposal_group_id_for(g, worker)
	bg_check(agency_undertake_goal_from_until_source(agency, worker, "tighten_nut", 0, 100000, "employment"))
	agency_control(agency, worker)
	scheduler_run_until(st.s, time_make(95000))
	return agency
}


/* ACTIONS.md decision 12: knowing a recipe is knowledge. At the mill, the
 * smith, a wrench in hand, the diagram read, and no fitter, undertakes to
 * repair the pump, having read `manual` (a recipe's name), if anything.
 * Whether the line was shut, and the pump opened; its log. */
test_recipe_run :: proc(manual: cstring, shut: ^bool, opened: ^bool, saved: ^string) -> []string {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	smith:      Entity_ID
	pump:       Entity_ID
	trough:     Entity_ID
	diagram:    Entity_ID
	book:       Entity_ID
	error:      string
	v:          i64

	st.w       = test_world(83)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g       = proposal_group_group_with_phase(.System, "setup: the mill")
	pump    = proposal_group_create(g, "pump", "pump", on_tile(10, 10, 0))
	trough  = proposal_group_create(g, "cock_trough", "the trough line's cock", on_tile(9, 9, 0))
	proposal_group_create(g, "cock_pump", "the riser's cock", on_tile(11, 9, 0))
	smith   = proposal_group_create(g, "smith", "smith", on_tile(10, 9, 0))
	proposal_group_create(g, "wrench_250", "wrench", held_by(smith, 0))
	diagram = proposal_group_create(g, "diagram", "diagram", held_by(smith, 1))
	proposal_group_set_of_to_text(g, "Record.writing", whole(diagram),
	                              world_intern(st.w, "#Writing & { author: #Agent & { coat: \"white\" }, entries: [#Serves & { what: #Cock & " +
	                                                 "{ place: #OnTile & { x: 9, y: 9, level: 0 } }, line: \"pump\", attribution: #Saw & { sure: 30 } }] }"))
	book = NO_ENTITY
	if manual != nil {
		book = proposal_group_create(g, "notebook", "the manual", on_tile(10, 8, 0))
		proposal_group_set_of_to_text(g, "Record.writing", whole(book),
		                              world_intern(st.w, ns_utf8(fmt.tprintf("#Writing & {{ author: #Agent & {{ coat: \"white\" }}, entries: " +
		                                                                     "[#RecipeSays & {{ recipe: \"%s\", attribution: #Saw & {{ sure: 30 }} }}] }}",
		                                                                     manual))))
	}
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump    = proposal_group_id_for(g, pump)
	trough  = proposal_group_id_for(g, trough)
	smith   = proposal_group_id_for(g, smith)
	diagram = proposal_group_id_for(g, diagram)
	error   = ""
	bg_check(perform(st.w, st.c, action_make("read", smith, diagram, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1100))
	if manual != nil {
		bg_check(perform(st.w, st.c, action_make("read", smith, proposal_group_id_for(g, book), NO_ENTITY), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(2200))
	}
	bg_check(agency_commit(agency, smith, "repair_pump"))
	scheduler_run_until(st.s, time_make(60000))
	shut^   = world_get_field(st.w, "Cock.shut", trough, &v) && v != 0
	opened^ = world_get_field(st.w, "Pump.opened", pump, &v) && v != 0
	saved^  = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return agency_log_of(agency, smith)
}


test_logged_in :: proc(log: []string, text: string) -> bool {
	for i in 0 ..< len(log) {
		if ns_contains(log[i], text) do return true
	}
	return false
}


test_recipes :: proc() {
	log:    []string
	saved:  string
	shut:   bool
	opened: bool

	/* no fitter, and no recipe: it can't choose one, and gives up */
	log = test_recipe_run(nil, &shut, &opened, &saved)
	bg_check(test_logged_in(log, "[repair the pump] nothing I know of will do"))
	bg_check(!shut && !opened)
	/* having read a manual with the recipe in it, it follows it: the line
	 * shut first, then the pump opened; and the recipe is in the save */
	log = test_recipe_run("the_recipe", &shut, &opened, &saved)
	bg_check(test_logged_in(log, "[repair the pump] follow the recipe: shut_off R"))
	bg_check(shut && opened)
	bg_check(ns_contains(saved, " the_recipe") &&
	         ns_contains(saved, "recipe "))
	/* a bad manual: it follows the wrong recipe, wrongly, the line open */
	log = test_recipe_run("rash_recipe", &shut, &opened, &saved)
	bg_check(test_logged_in(log, "[repair the pump] take it apart: dismantle R"))
	bg_check(!shut && opened)
}


/* AGENCY.md §14, autopilot "carry out this recipe": at the mill, the
 * worker, holding the wrench, reads the diagram; the player hands it to
 * agency to follow the recipe. It shuts the line the diagram says, opens
 * the pump, and control returns. Saved midway, the recipe is kept. A
 * method that isn't a recipe can't be handed over so. */
test_recipe_autopilot :: proc() {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	worker:     Entity_ID
	pump:       Entity_ID
	trough:     Entity_ID
	diagram:    Entity_ID
	notices:    []string
	text:       string
	error:      string
	v:          i64

	st.w       = test_world(83)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g       = proposal_group_group_with_phase(.System, "setup: the mill")
	pump    = proposal_group_create(g, "pump", "pump", on_tile(10, 10, 0))
	trough  = proposal_group_create(g, "cock_trough", "the trough line's cock", on_tile(9, 9, 0))
	proposal_group_create(g, "cock_pump", "the riser's cock", on_tile(11, 9, 0))
	worker  = proposal_group_create(g, "worker", "worker", on_tile(10, 9, 0))
	proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	diagram = proposal_group_create(g, "diagram", "diagram", held_by(worker, 1))
	proposal_group_set_of_to_text(g, "Record.writing", whole(diagram),
	                              world_intern(st.w, "#Writing & { author: #Agent & { coat: \"white\" }, entries: [#Serves & { what: #Cock & " +
	                                                 "{ place: #OnTile & { x: 9, y: 9, level: 0 } }, line: \"pump\", attribution: #Saw & { sure: 30 } }] }"))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump    = proposal_group_id_for(g, pump)
	trough  = proposal_group_id_for(g, trough)
	worker  = proposal_group_id_for(g, worker)
	diagram = proposal_group_id_for(g, diagram)
	error   = ""
	bg_check(perform(st.w, st.c, action_make("read", worker, diagram, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))

	bg_check(!agency_autopilot_recipe(agency, worker, "borrow_money", 50))
	bg_check(agency_autopilot_recipe(agency, worker, "the_recipe", 50))
	scheduler_run_until(st.s, time_make(3000))
	text = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	bg_check(ns_contains(text, " the_recipe"))
	scheduler_run_until(st.s, time_make(60000))
	bg_check(test_logged_by(agency, worker, "[repair the pump] follow the recipe: shut_off R"))
	bg_check(world_get_field(st.w, "Cock.shut", trough, &v) && v != 0)
	bg_check(world_get_field(st.w, "Pump.opened", pump, &v) && v != 0)
	notices = agency_take_notices(agency)
	bg_check(len(notices) == 1 &&
	         notices[0] == "Control returns to you: there is nothing left to do.")
}


/* Reading takes time, as talking does: a second, and what the record holds
 * is taken in when it ends. */
test_reading_takes_time :: proc() {
	st:      Stage
	g:       ^Proposal_Group
	worker:  Entity_ID
	diagram: Entity_ID
	error:   string
	read:    uint
	when_:   i64

	st.w    = test_world(191)
	st.c    = test_committer(st.w)
	st.s    = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g       = proposal_group_group_with_phase(.System, "setup: a diagram")
	worker  = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	diagram = proposal_group_create(g, "diagram", "diagram", held_by(worker, 0))
	proposal_group_set_of_to_text(g, "Record.writing", whole(diagram),
	                              world_intern(st.w, "#Writing & { author: #Agent & { coat: \"white\" }, entries: [#Serves & { what: #Cock & " +
	                                                 "{ place: #OnTile & { x: 9, y: 9, level: 0 } }, line: \"pump\", attribution: #Saw & { sure: 30 } }] }"))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker  = proposal_group_id_for(g, worker)
	diagram = proposal_group_id_for(g, diagram)

	error = ""
	bg_check(perform(st.w, st.c, action_make("read", worker, diagram, NO_ENTITY), 0, &error) != nil)
	when_ = world_time(st.w).ms
	scheduler_run_until(st.s, time_make(when_ + 500))
	read = 0
	for i: uint = 0; i < world_event_count(st.w); i += 1 {
		if string(world_event_at(st.w, i).kind) == "read" do read += 1
	}
	bg_check(read == 0)
	scheduler_run_until(st.s, time_make(when_ + 1001))
	read = 0
	for i: uint = 0; i < world_event_count(st.w); i += 1 {
		if string(world_event_at(st.w, i).kind) == "read" && world_event_at(st.w, i).actor == worker do read += 1
	}
	bg_check(read == 1)
}


/* AGENCY.md §14, autopilot "auto-explore": the player hands a worker,
 * alone in the middle of the map, to agency to explore. It walks toward the
 * nearest tile it has never seen, a step at a time, until it has seen every
 * one; then control returns. Saved midway, the mode is kept. */
test_explore_autopilot :: proc() {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	restored:   ^Agency
	store:      ^Knowledge_Store
	g:          ^Proposal_Group
	worker:     Entity_ID
	notices:    []string
	text:       string
	mode:       string
	unseen:     i32

	st.w       = test_world(179)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g      = proposal_group_group_with_phase(.System, "setup: an empty map")
	worker = proposal_group_create(g, "worker", "worker", on_tile(16, 16, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	bg_check(agency_autopilot_explore(agency, worker, 50))

	/* midway: under way, and the mode saved */
	scheduler_run_until(st.s, time_make(10000))
	bg_check(len(agency_take_notices(agency)) == 0 && test_logged_by(agency, worker, "exploring: a walk of "))
	text     = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	mode     = fmt.tprintf("explore %d", u64(worker))
	bg_check(ns_contains(text, mode))
	restored = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	minds := agency_as_saved_system(restored)
	minds.restore_saved_state(minds.data, saved_domain_state(text, "agency"))
	bg_check(agency_mind_of(restored, worker).explore && agency_mind_of(restored, worker).autopilot)

	/* on until it has seen it all */
	scheduler_run_until(st.s, time_make(600000))
	store  = knowledge_store_of(knowledge, worker)
	unseen = 0
	for y: i32 = 0; y < 32; y += 1 {
		for x: i32 = 0; x < 32; x += 1 {
			if !knowledge_store_has_seen_x(store, x, y, 0) do unseen += 1
		}
	}
	bg_check(unseen == 0)
	notices = agency_take_notices(agency)
	bg_check(len(notices) == 1 &&
	         notices[0] == "Control returns to you: there is nothing left to explore.")
	bg_check(!agency_controls(agency, worker))
}


/* TERRAIN.md, pathfinding: exploring the rooms from inside the room, the
 * worker finds its way out by the doorway, along the corridor and into
 * the back room by its doorway, until it has seen every floor of the
 * building; walled in, it never sees the outdoors, and stops. Walking
 * straight at the nearest unseen tile, it would stand at a wall. */
test_explore_rooms :: proc() {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	store:      ^Knowledge_Store
	g:          ^Proposal_Group
	worker:     Entity_ID
	notices:    []string
	unseen:     i32

	st.w       = test_world(181)
	bg_check(world_set_terrain_map(st.w, "rooms_map", nil))
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g      = proposal_group_group_with_phase(.System, "setup: shut in the room")
	worker = proposal_group_create(g, "worker", "worker", on_tile(2, 2, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	bg_check(agency_autopilot_explore(agency, worker, 50))
	scheduler_run_until(st.s, time_make(3600000))
	store  = knowledge_store_of(knowledge, worker)
	bg_check(knowledge_store_has_seen_x(store, 7, 3, 0) && knowledge_store_has_seen_x(store, 20, 8, 0) &&
	         !knowledge_store_has_seen_x(store, 30, 30, 0))
	unseen = 0
	for y: i32 = 0; y < 10; y += 1 {
		for x: i32 = 0; x < 22; x += 1 {
			if terrain_room_at(world_terrain(st.w), x, y, 0) != 0 && !knowledge_store_has_seen_x(store, x, y, 0) do unseen += 1
		}
	}
	bg_check(unseen == 0)                                     /* every floor tile of the building */
	bg_check(!test_logged_by(agency, worker, "could not set out"))
	notices = agency_take_notices(agency)
	bg_check(len(notices) == 1)
	/* a walk is an activity: of the dozens it set out on, what stays is what
	 * is still asked of, the last completed and its latest (BGActivities
	 * letGo) */
	bg_check(world_activities_of(st.w, worker, nil, 0) <= 5 &&
	         store_count(world_store_for_kind(st.w, world_kind_named(st.w, "Activity"))) <= 5)
	{
		indexed: [8]Entity_ID
		kept:    ^Store            /* the C's inner `store`, renamed: it would shadow the outer */
		n:       uint

		kept = world_store_for_kind(st.w, world_kind_named(st.w, "Activity"))
		n    = world_activities_of(st.w, worker, raw_data(indexed[:]), 8)
		bg_check(n == store_count(kept))
		for i: uint = 0; i < n && i < store_count(kept); i += 1 {
			bg_check(indexed[i] == store_entity_at_index(kept, i) &&
			         (^Activity)(store_record_at_index(kept, i)).actorRef == worker)
		}
	}
	bg_check(len(agency_log_of(agency, worker)) > 20)
}


/* Whether the world's index of what is where agrees with its locations,
 * read the slow way: on the ground near each of a few tiles, and in each
 * thing. */
test_index_agrees :: proc(w: ^World) -> bool {
	fast:      [256]Entity_ID
	slow:      [256]Entity_ID
	loc:       ^Location
	locations: ^Store
	nf:        uint
	ns:        uint

	locations = world_locations(w)
	for y: i32 = 0; y < 64; y += 9 {
		for x: i32 = 0; x < 64; x += 7 {
			nf = world_entities_near(w, on_tile(x, y, 0), 5, raw_data(fast[:]), 256)
			ns = 0
			for i: uint = 0; i < store_count(locations); i += 1 {
				loc = (^Location)(store_record_at_index(locations, i))
				if loc.form == .On_Tile && loc.level == 0 && abs(loc.x - x) <= 5 && abs(loc.y - y) <= 5 {
					slow[ns] = store_entity_at_index(locations, i)
					ns += 1
				}
			}
			if nf != ns || mem.compare_ptrs(&fast[0], &slow[0], int(ns) * size_of(Entity_ID)) != 0 do return false
		}
	}
	for i: uint = 0; i < store_count(locations); i += 1 {
		loc = (^Location)(store_record_at_index(locations, i))
		if loc.form == .On_Tile do continue
		nf = world_entities_at(w, loc.place, loc.form, raw_data(fast[:]), 256)
		for ns = 0; ns < nf && fast[ns] != store_entity_at_index(locations, i); ns += 1 {
		}
		if ns == nf do return false
	}
	return true
}


/* Whether the traces near a few tiles, by the index, are those a scan finds:
 * on the floor within the square, or borne by what is in it. */
test_traces_agree :: proc(w: ^World) -> bool {
	trace:  ^Trace
	fast:   [^]Entity_ID
	slow:   [256]Entity_ID
	tile:   Location
	at:     Location
	traces: ^Store
	nf:     uint
	ns:     uint
	same:   bool

	traces = world_store_for_kind(w, world_kind_named(w, "Trace"))
	for y: i32 = 0; y < 64; y += 9 {
		for x: i32 = 0; x < 64; x += 7 {
			nf = world_traces_near(w, on_tile(x, y, 0), 6, &fast)
			ns = 0
			for i: uint = 0; i < store_count(traces); i += 1 {
				trace = (^Trace)(store_record_at_index(traces, i))
				if trace.bearer != 0 {
					for at = world_location_of(w, Entity_ID(trace.bearer)); at.form != .On_Tile && at.place != NO_ENTITY;
					    at = world_location_of(w, at.place) {
					}
					tile = at
				} else {
					tile = on_tile(i32(trace.tileX), i32(trace.tileY), i32(trace.tileLevel))
				}
				if tile.form == .On_Tile && tile.level == 0 && abs(tile.x - x) <= 6 && abs(tile.y - y) <= 6 {
					slow[ns] = store_entity_at_index(traces, i)
					ns += 1
				}
			}
			same = nf == ns && mem.compare_ptrs(fast, &slow[0], int(ns) * size_of(Entity_ID)) == 0
			free(fast)
			if !same do return false
		}
	}
	return true
}
