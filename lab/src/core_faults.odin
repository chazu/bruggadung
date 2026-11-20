package lab

/*
 * Cap faults: a fixed cap the lab's code met (GLOSSARY.md; REVIEW.md
 * §4.4). Past a cap, work the lab would have done is not done: a subgoal
 * not adopted, a slot not bound, a tap not drawn from. That is never
 * silent. Each such place calls `cap_fault`, which keeps the line here:
 *
 * - `lab test` prints the cap faults a test met and fails it, as it does
 *   interpretation_missed's lines. A test that means to meet a cap takes
 *   its faults with `take_cap_faults` before it ends.
 * - The lab's other commands print them to stderr at the end and exit 1,
 *   so a scenario that meets a cap fails `make check`.
 *
 * A cap whose overflow is the model (a habit forgotten, the weakest first;
 * ground past BG_ROOM_MAX is open) is no cap fault. Neither is a cap
 * where the code stays on the safe side (a full list of residuals leaves
 * the operation unknown).
 *
 * Like interpretation_missed, the list is the package's: one more mutable
 * global for the threading REALITY.md decision 8 plans (REVIEW.md §4.4).
 */

import "core:fmt"
import "core:strings"


cap_faults: [dynamic]string     /* each in context.allocator */


/* A cap met: what it is, its size, and the work not done. A cap fault
 * met again (a cap met at each boundary) is kept once. */
cap_fault :: proc(format: string, args: ..any) {
	line := fmt.aprintf(format, ..args)
	for kept in cap_faults {
		if kept == line {
			delete(line)
			return
		}
	}
	append(&cap_faults, line)
}


/* The cap faults met since the last take, as one text, a line each; the list
 * is emptied. In the temporary allocator. */
take_cap_faults :: proc() -> string {
	text := strings.join(cap_faults[:], "\n", context.temp_allocator)
	for line in cap_faults do delete(line)
	clear(&cap_faults)
	return text
}


/* The cap faults met, printed to stderr, and the list emptied: true if there
 * were any. */
report_cap_faults :: proc() -> bool {
	if len(cap_faults) == 0 do return false
	for line in cap_faults do fmt.eprintf("lab: cap fault: %s\n", line)
	take_cap_faults()
	return true
}


/* `n` of a list, read into a buffer that holds `room`: as many as fit. More
 * than fit is a cap fault, named by `what`. */
fitting :: proc(n: uint, room: int, what: string) -> uint {
	if n <= uint(room) do return n
	cap_fault("%s: %d, more than the %d it holds; the rest passed over", what, n, room)
	return uint(room)
}


/* The element at `n` of a list counted apart (a mind's `ncommitments` of
 * its `commitments`), the list grown to hold it. Past the count, the list
 * may hold stale elements: whoever writes one sets all of it. */
grown_to :: proc(list: ^[dynamic]$T, n: i32) -> ^T {
	if int(n) >= len(list) do resize(list, int(n) + 1)
	return &list[n]
}
