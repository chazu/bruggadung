package lab

/*
 * BGWakes — a queue of wakes (REALITY.md decision 7): when each of many
 * things is next due, earliest first, so a boundary reads only what falls
 * due at it, not all there are. An entry may go stale (the thing is due at
 * another time now, or never); it is checked when it comes up, against
 * what the caller says is so now, and let go. Push again whenever a
 * thing's time changes. Plain C.
 */

/*
 * BGWakes: a binary heap of (time, thing), ties by thing.
 */

import "core:mem"
import "core:slice"

/* What is so now: when the thing is next due, or INT64_MAX for never. */
Wake_Time :: proc(context_: rawptr, thing: Entity_ID) -> i64

@(private = "file")
Wake :: struct {
	at:    i64,
	thing: Entity_ID,
}

Wakes :: struct {
	heap: [^]Wake,
	n:    uint,
	cap_: uint,
}

wakes_new :: proc() -> ^Wakes {
	return new(Wakes)
}

wakes_clear :: proc(q: ^Wakes) {
	q.n = 0
}

wakes_free :: proc(q: ^Wakes) {
	if q == nil do return
	free(q.heap)
	free(q)
}

wakes_count :: proc(q: ^Wakes) -> uint {
	return q.n
}

@(private = "file")
before :: proc(x: ^Wake, y: ^Wake) -> bool {
	return x.at < y.at || (x.at == y.at && x.thing < y.thing)
}

/* A thing due at `at`; INT64_MAX is ignored. */
wakes_push :: proc(q: ^Wakes, thing: Entity_ID, at: i64) {
	t: Wake
	i: uint

	if at == max(i64) do return
	if q.n == q.cap_ {
		old := q.cap_
		q.cap_ = q.cap_ * 2 if q.cap_ != 0 else 64
		p, _ := mem.resize(q.heap, int(old * size_of(Wake)), int(q.cap_ * size_of(Wake)))
		q.heap = ([^]Wake)(p)
	}
	q.heap[q.n].at = at
	q.heap[q.n].thing = thing
	i = q.n
	q.n += 1
	for ; i != 0 && before(&q.heap[i], &q.heap[(i - 1) / 2]); i = (i - 1) / 2 {
		t = q.heap[i]
		q.heap[i] = q.heap[(i - 1) / 2]
		q.heap[(i - 1) / 2] = t
	}
}

@(private = "file")
pop :: proc(q: ^Wakes) -> Wake {
	top: Wake
	t: Wake
	i: uint
	c: uint

	top = q.heap[0]
	q.n -= 1
	q.heap[0] = q.heap[q.n]
	for i = 0;; i = c {
		c = 2 * i + 1
		if c >= q.n do break
		if c + 1 < q.n && before(&q.heap[c + 1], &q.heap[c]) do c += 1
		if !before(&q.heap[c], &q.heap[i]) do break
		t = q.heap[i]
		q.heap[i] = q.heap[c]
		q.heap[c] = t
	}
	return top
}

/* The earliest time still so, stale entries let go; INT64_MAX if none. */
wakes_next :: proc(q: ^Wakes, now: Wake_Time, context_: rawptr) -> i64 {
	top: Wake
	at: i64

	for q.n != 0 {
		top = q.heap[0]
		at = now(context_, top.thing)
		if at == top.at do return at
		pop(q)
		wakes_push(q, top.thing, at)       /* its time now, if it has one */
	}
	return max(i64)
}

/* The things due by `t` (whose time, still so, is at or before it), taken
 * from the queue: malloc'd, in entity order, each once; *n of them. The
 * caller frees them with free(). */
wakes_take :: proc(q: ^Wakes, t: i64, now: Wake_Time, context_: rawptr, n: ^uint) -> [^]Entity_ID {
	due: [^]Entity_ID
	top: Wake
	k: uint
	i: uint
	at: i64

	due = make([^]Entity_ID, q.n + 1)
	k = 0
	for q.n != 0 && q.heap[0].at <= t {
		top = pop(q)
		at = now(context_, top.thing)
		if at == top.at {
			due[k] = top.thing
			k += 1
		} else {
			wakes_push(q, top.thing, at)    /* stale: its time now */
		}
	}
	slice.sort(due[:k])      // qsort by thing: equal ones are the same thing
	n^ = 0
	for i = 0; i < k; i += 1 {
		if n^ == 0 || due[n^ - 1] != due[i] {
			due[n^] = due[i]
			n^ += 1
		}
	}
	return due
}
