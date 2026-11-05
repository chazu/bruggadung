package lab

/*
 * The village (VILLAGE.md slices 3 and 4, scenario_village.odin): three
 * days and nights of the day's commitments and meals, every check passing:
 * a meal taken to work and eaten there, each household eating from its own
 * larder, nobody going without; and each person's bed and larder, just
 * like its neighbours', known to it by where it is (KNOWLEDGE.md decision
 * 18), not taken for another like it.
 */

test_village :: proc() {
	w := test_world(101)
	village := autorelease(village_init_with_world(w, test_committer(w)))
	bg_check(village_error(village) == "")
	village_run(village)
	bg_check(len(village_results(village)) == 30 && village_failure_count(village) == 0)
	/* asleep at 02:00 on the third night: everyone's sleep is of its own bed */
	for v in village.people {
		bed := world_location_of(w, v.bed)
		me  := world_location_of(w, v.id)
		bg_check(abs(bed.x - me.x) <= 1 && abs(bed.y - me.y) <= 1)
	}
	/* twelve people in four households */
	bg_check(len(village.people) == 12)
}
