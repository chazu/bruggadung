package lab

/*
 * BGPath — finding a way over tiles (TERRAIN.md, pathfinding): a search
 * from a tile, by steps north, south, east and west, each to the level the
 * caller says it comes to (the same, or a step up or down: OROGEN.md
 * decision 6), for a tile it is looking for. Bounded: it expands at
 * most a budget of tiles, so its cost is the same in any size of world.
 * With a target, it is A*, the steps still to go reckoned to the target's
 * reach (a tile beside it, corners too); without, it is breadth-first,
 * nearest first. Plain C; its buffers are kept between searches, so it is
 * not for more than one thread.
 */

/*
 * BGPath: a bounded best-first search. Nodes are kept in arrays indexed by
 * the order they were reached, found by an open-addressed table of their
 * tiles, and opened from a binary heap by steps so far plus steps to go,
 * then steps to go, then the order reached: every tie is broken the same
 * way every time.
 */

import "base:runtime"
import "core:mem"
import "core:slice"

BG_PATH_BUDGET :: 4096        /* tiles a search expands, at most */

Step :: enum i32 {
	None  = -1,
	North = 0,
	South,
	East,
	West,
}

Path_Query :: struct {
	x:        i32,                      /* where it starts */
	y:        i32,
	z:        i32,
	targeted: bool,                     /* toward (tx, ty, tz): done within a step of it, and a level */
	tx:       i32,
	ty:       i32,
	tz:       i32,
	budget:   uint,                     /* 0: BG_PATH_BUDGET */
	context_: rawptr,                   // `context` is Odin's keyword
	/* a walk from (x, y, z) to the tile (u, v) beside it: the level it comes to, or false */
	step:     proc(context_: rawptr, x: i32, y: i32, z: i32, u: i32, v: i32) -> (level: i32, ok: bool),
	goal:     proc(context_: rawptr, x: i32, y: i32, z: i32) -> bool,    /* untargeted: what it looks for */
	way:      ^[dynamic]Step,           /* if set, filled with every step of the way, first to last */
}

Path_Result :: struct {
	step:     Step,                     /* the first step; none if it is there, or nothing was found */
	found:    bool,                     /* a way all the way */
	x:        i32,                      /* where the way it took ends */
	y:        i32,
	z:        i32,
	steps:    i64,                      /* how many to there */
	expanded: uint,
}

@(private = "file")
Path_Node :: struct {
	x:      i32,
	y:      i32,
	z:      i32,
	g:      i64,            /* steps from the start */
	h:      i64,            /* steps to go, at least */
	parent: i32,            /* -1 for the start */
	closed: bool,
}

@(private = "file")
nodes: [^]Path_Node
@(private = "file")
nodecap: uint
@(private = "file")
table: [^]i32           /* node + 1, or 0 */
@(private = "file")
stamps: [^]u32          /* the search a slot was filled in; else it is empty */
@(private = "file")
search: u32             /* this search's stamp */
@(private = "file")
tablecap: uint          /* a power of two */

@(private = "file")
Path_Entry :: struct {
	f:    i64,          /* as it was when pushed: a node pushed again is newer */
	h:    i64,
	seq:  u32,
	node: i32,
}

@(private = "file")
heap: [^]Path_Entry
@(private = "file")
heapcap: uint
@(private = "file")
seq: u32

@(private = "file")
dx := [4]i32{0, 0, 1, -1}
@(private = "file")
dy := [4]i32{-1, 1, 0, 0}

@(private = "file")
to_go :: proc(q: ^Path_Query, x: i32, y: i32) -> i64 {
	ax: i64
	ay: i64

	if !q.targeted do return 0
	ax = abs(i64(x) - i64(q.tx)) - 1
	ay = abs(i64(y) - i64(q.ty)) - 1
	return (ax if ax > 0 else 0) + (ay if ay > 0 else 0)
}

@(private = "file")
slot :: proc(x: i32, y: i32, z: i32) -> uint {
	return uint(mix(mix((u64(u32(x)) << 32) | u64(u32(y))) ~ u64(u32(z)))) & (tablecap - 1)
}

/* The node at a tile, or -1. */
@(private = "file")
node_at :: proc(x: i32, y: i32, z: i32) -> i32 {
	i: uint

	for i = slot(x, y, z); stamps[i] == search; i = (i + 1) & (tablecap - 1) {
		if nodes[table[i] - 1].x == x && nodes[table[i] - 1].y == y && nodes[table[i] - 1].z == z do return table[i] - 1
	}
	return -1
}

@(private = "file")
table_put :: proc(n: i32) {
	i: uint

	for i = slot(nodes[n].x, nodes[n].y, nodes[n].z); stamps[i] == search; i = (i + 1) & (tablecap - 1) {
	}
	table[i] = n + 1
	stamps[i] = search
}

@(private = "file")
before :: proc(a: ^Path_Entry, b: ^Path_Entry) -> bool {
	if a.f != b.f do return a.f < b.f
	if a.h != b.h do return a.h < b.h
	return a.seq < b.seq
}

@(private = "file")
heap_push :: proc(n: ^uint, node: i32) {
	t: Path_Entry
	i: uint

	heap[n^].f = nodes[node].g + nodes[node].h
	heap[n^].h = nodes[node].h
	heap[n^].seq = seq
	seq += 1
	heap[n^].node = node
	n^ += 1
	for i = n^ - 1; i != 0 && before(&heap[i], &heap[(i - 1) / 2]); i = (i - 1) / 2 {
		t = heap[i]
		heap[i] = heap[(i - 1) / 2]
		heap[(i - 1) / 2] = t
	}
}

@(private = "file")
heap_pop :: proc(n: ^uint) -> i32 {
	t: Path_Entry
	i: uint
	c: uint
	top: i32

	top = heap[0].node
	n^ -= 1
	heap[0] = heap[n^]
	for i = 0;; i = c {
		c = 2 * i + 1
		if c >= n^ do break
		if c + 1 < n^ && before(&heap[c + 1], &heap[c]) do c += 1
		if !before(&heap[c], &heap[i]) do break
		t = heap[i]
		heap[i] = heap[c]
		heap[c] = t
	}
	return top
}

@(private = "file")
done :: proc(q: ^Path_Query, x: i32, y: i32, z: i32) -> bool {
	if q.targeted do return abs(i64(x) - i64(q.tx)) <= 1 && abs(i64(y) - i64(q.ty)) <= 1 && abs(z - q.tz) <= 1
	return q.goal != nil && q.goal(q.context_, x, y, z)
}

/* The first step on the way from the start to node n. */
@(private = "file")
first_step :: proc(n: i32) -> Step {
	n := n
	p: i32
	d: i32

	if nodes[n].parent < 0 do return .None
	for {
		p = nodes[n].parent
		if !(p >= 0 && nodes[p].parent >= 0) do break
		n = p
	}
	for d = 0; d < 4; d += 1 {
		if nodes[n].x == nodes[p].x + dx[d] && nodes[n].y == nodes[p].y + dy[d] do return Step(d)
	}
	return .None
}

/* Searches. Targeted and not found within the budget, the first step is
 * toward the tile it reached nearest the target; untargeted, none. The
 * start need not be anywhere one could walk to. Ties go to the order north, south, east,
 * west, after the steps nearer the target. */
path_find :: proc(q: ^Path_Query) -> Path_Result {
	r: Path_Result
	budget: uint
	nnodes: uint
	nheap: uint
	need: uint
	best: i32
	n: i32
	m: i32
	u: i32
	v: i32
	d: i32

	r = {}
	r.step = .None
	budget = q.budget if q.budget != 0 else BG_PATH_BUDGET
	need = budget * 4 + 1                  /* each expanded tile reaches four at most */
	if nodecap < need {
		oldcap := nodecap
		nodecap = need
		nodes = ([^]Path_Node)(realloc(nodes, oldcap * size_of(Path_Node), nodecap * size_of(Path_Node)))
		heap = ([^]Path_Entry)(realloc(heap, heapcap * size_of(Path_Entry), nodecap * size_of(Path_Entry)))
		heapcap = nodecap
	}
	if tablecap < need * 2 {
		oldcap := tablecap
		for tablecap = tablecap if tablecap != 0 else 64; tablecap < need * 2; tablecap *= 2 {
		}
		table = ([^]i32)(realloc(table, oldcap * size_of(i32), tablecap * size_of(i32)))
		stamps = ([^]u32)(realloc(stamps, oldcap * size_of(u32), tablecap * size_of(u32)))
		mem.set(stamps, 0, int(tablecap * size_of(u32)))
		search = 0
	}
	/* a new stamp, not a cleared table: each search reads only what it fills */
	search += 1
	if search == 0 {
		mem.set(stamps, 0, int(tablecap * size_of(u32)))
		search = 1
	}

	nnodes = 0
	nheap = 0
	seq = 0
	nodes[0].x = q.x
	nodes[0].y = q.y
	nodes[0].z = q.z
	nodes[0].g = 0
	nodes[0].h = to_go(q, q.x, q.y)
	nodes[0].parent = -1
	nodes[0].closed = false
	nnodes = 1
	table_put(0)
	heap_push(&nheap, 0)
	best = 0
	for nheap != 0 && r.expanded < budget {
		n = heap_pop(&nheap)
		if nodes[n].closed do continue
		nodes[n].closed = true
		r.expanded += 1
		if done(q, nodes[n].x, nodes[n].y, nodes[n].z) {
			r.found = true
			best = n
			break
		}
		if nodes[n].h < nodes[best].h || (nodes[n].h == nodes[best].h && nodes[n].g < nodes[best].g) do best = n
		for d = 0; d < 4; d += 1 {
			u = nodes[n].x + dx[d]
			v = nodes[n].y + dy[d]
			w, ok := q.step(q.context_, nodes[n].x, nodes[n].y, nodes[n].z, u, v)
			if !ok do continue
			m = node_at(u, v, w)
			if m >= 0 {
				if nodes[m].closed || nodes[m].g <= nodes[n].g + 1 do continue
				nodes[m].g = nodes[n].g + 1
				nodes[m].parent = n
			} else {
				if nnodes == nodecap do continue
				m = i32(nnodes)
				nnodes += 1
				nodes[m].x = u
				nodes[m].y = v
				nodes[m].z = w
				nodes[m].g = nodes[n].g + 1
				nodes[m].h = to_go(q, u, v)
				nodes[m].parent = n
				nodes[m].closed = false
				table_put(m)
			}
			if nheap < heapcap do heap_push(&nheap, m)
		}
	}
	if !r.found && !q.targeted do return r
	r.x = nodes[best].x
	r.y = nodes[best].y
	r.z = nodes[best].z
	r.steps = nodes[best].g
	r.step = first_step(best)
	if q.way != nil do way_to(best, q.way)
	return r
}


/* Every step from the start to node n, first to last. */
@(private = "file")
way_to :: proc(n: i32, way: ^[dynamic]Step) {
	p: i32
	d: i32

	clear(way)
	for n := n; nodes[n].parent >= 0; n = p {
		p = nodes[n].parent
		for d = 0; d < 4; d += 1 {
			if nodes[n].x == nodes[p].x + dx[d] && nodes[n].y == nodes[p].y + dy[d] do break
		}
		append(way, Step(d))
	}
	slice.reverse(way[:])
}

// realloc: the block resized. The search's buffers live as long as the
// program, as they did: on the heap, whatever the caller's allocator.
@(private = "file")
realloc :: proc(p: rawptr, old_size, new_size: uint) -> rawptr {
	q, _ := mem.resize(p, int(old_size), int(new_size), allocator = runtime.heap_allocator())
	return q
}
