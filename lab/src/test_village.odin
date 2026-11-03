package lab

/*
 * The village (VILLAGE.md slice 3, scenario_village.odin): three days and
 * nights of the day's commitments, every check passing; and each person's
 * bed known to it by its blanket, not taken for another like it.
 */

test_village :: proc() {
	w := test_world(101)
	village := autorelease(village_init_with_world(w, test_committer(w)))
	bg_check(village_error(village) == "")
	village_run(village)
	bg_check(len(village_results(village)) == 9 && village_failure_count(village) == 0)
	/* asleep at 02:00 on the third night: everyone's sleep is of its own bed */
	for v in village.people {
		bed := world_location_of(w, v.bed)
		me  := world_location_of(w, v.id)
		bg_check(abs(bed.x - me.x) <= 1 && abs(bed.y - me.y) <= 1)
	}
	/* twelve people in four households */
	bg_check(len(village.people) == 12)
}
