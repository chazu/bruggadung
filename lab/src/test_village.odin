package lab

/*
 * The village (VILLAGE.md slices 3 to 10, scenario_village.odin): a week
 * of days and nights, every check passing (79 of them):
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
	bg_check(len(village_results(village)) == 80 && village_failure_count(village) == 0)
	/* at 02:00 on the last night: everyone's sleep is of its own bed (one up
	 * at its hearth for a meal, woken hungry, aside) */
	for v in village.people {
		if agency_intends(village.agency, v.id, "eat_when_hungry") do continue
		bed := world_location_of(w, v.bed)
		me  := world_location_of(w, v.id)
		bg_check(abs(bed.x - me.x) <= 1 && abs(bed.y - me.y) <= 1)
	}
	/* twelve people in four households */
	bg_check(len(village.people) == 12)
}
