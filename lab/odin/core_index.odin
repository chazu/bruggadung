package lab

/*
 * BGIndex — a map from a key to the entities filed under it, each list in
 * entity order, so a lookup costs what it finds, and reads the same however
 * it was built. The world files what stands on the ground by chunk, and
 * what is in, on, held by or part of a thing by that thing (TERRAIN.md,
 * the spatial index). Plain C.
 */

/*
 * BGIndex: an open-addressed table of keys, linear probing, removed by
 * shifting back (no tombstones); a key goes when its list empties.
 */

import "core:mem"

@(private = "file")
Index_Slot :: struct {
	key: u64,
	ids: [^]Entity_ID,         /* NULL: an empty slot */
	n:   uint,
	cap_: uint,
}

Index :: struct {
	slots: [^]Index_Slot,
	cap_:  uint,               /* a power of two, or 0 */
	count: uint,
}

index_new :: proc() -> ^Index {
	return new(Index)
}

index_clear :: proc(index: ^Index) {
	i: uint

	for i = 0; i < index.cap_; i += 1 do free(index.slots[i].ids)
	free(index.slots)
	index.slots = nil
	index.cap_ = 0
	index.count = 0
}

index_free :: proc(index: ^Index) {
	if index == nil do return
	index_clear(index)
	free(index)
}

@(private = "file")
home :: proc(key: u64, cap_: uint) -> uint {
	return uint(mix(key)) & (cap_ - 1)
}

@(private = "file")
find :: proc(index: ^Index, key: u64) -> ^Index_Slot {
	i: uint

	if index.count == 0 do return nil
	for i = home(key, index.cap_); index.slots[i].ids != nil; i = (i + 1) & (index.cap_ - 1) {
		if index.slots[i].key == key do return &index.slots[i]
	}
	return nil
}

@(private = "file")
grow :: proc(index: ^Index) {
	old: [^]Index_Slot
	oldcap: uint
	i: uint
	j: uint

	old = index.slots
	oldcap = index.cap_
	index.cap_ = oldcap * 2 if oldcap != 0 else 16
	index.slots = make([^]Index_Slot, index.cap_)
	for i = 0; i < oldcap; i += 1 {
		if old[i].ids != nil {
			for j = home(old[i].key, index.cap_); index.slots[j].ids != nil; j = (j + 1) & (index.cap_ - 1) {
			}
			index.slots[j] = old[i]
		}
	}
	free(old)
}

/* Where an entity is, or would go, in a sorted list. */
@(private = "file")
position :: proc(s: ^Index_Slot, e: Entity_ID, found: ^bool) -> uint {
	lo: uint
	hi: uint
	mid: uint

	lo = 0
	hi = s.n
	for lo < hi {
		mid = (lo + hi) / 2
		if s.ids[mid] < e {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	found^ = lo < s.n && s.ids[lo] == e
	return lo
}

/* Files an entity under a key (once); unfiles it. */
index_add :: proc(index: ^Index, key: u64, entity: Entity_ID) {
	s: ^Index_Slot
	i: uint
	found: bool

	s = find(index, key)
	if s == nil {
		if (index.count + 1) * 2 > index.cap_ do grow(index)
		for i = home(key, index.cap_); index.slots[i].ids != nil; i = (i + 1) & (index.cap_ - 1) {
		}
		s = &index.slots[i]
		s.key = key
		s.cap_ = 4
		s.n = 0
		s.ids = make([^]Entity_ID, s.cap_)
		index.count += 1
	}
	i = position(s, entity, &found)
	if found do return
	if s.n == s.cap_ {
		old := s.cap_
		s.cap_ *= 2
		p, _ := mem.resize(s.ids, int(old * size_of(Entity_ID)), int(s.cap_ * size_of(Entity_ID)))
		s.ids = ([^]Entity_ID)(p)
	}
	mem.copy(&s.ids[i + 1], &s.ids[i], int((s.n - i) * size_of(Entity_ID)))
	s.ids[i] = entity
	s.n += 1
}

index_remove :: proc(index: ^Index, key: u64, entity: Entity_ID) {
	s: ^Index_Slot
	i: uint
	j: uint
	k: uint
	found: bool

	s = find(index, key)
	if s == nil do return
	i = position(s, entity, &found)
	if !found do return
	mem.copy(&s.ids[i], &s.ids[i + 1], int((s.n - i - 1) * size_of(Entity_ID)))
	s.n -= 1
	if s.n != 0 do return
	/* the key goes: shift back what probed past it */
	free(s.ids)
	s^ = {}
	index.count -= 1
	i = uint(mem.ptr_sub(s, &index.slots[0]))
	for j = (i + 1) & (index.cap_ - 1); index.slots[j].ids != nil; j = (j + 1) & (index.cap_ - 1) {
		k = home(index.slots[j].key, index.cap_)
		/* move j to i if its home is not in (i, j] cyclically */
		if (j > i && (k <= i || k > j)) || (j < i && k <= i && k > j) {
			index.slots[i] = index.slots[j]
			index.slots[j] = {}
			i = j
		}
	}
}

/* What is filed under a key, in entity order: *n of them, or NULL. */
index_get :: proc(index: ^Index, key: u64, n: ^uint) -> [^]Entity_ID {
	s: ^Index_Slot

	s = find(index, key)
	n^ = s.n if s != nil else 0
	return s.ids if s != nil else nil
}

/* Keys with anything filed. */
index_keys :: proc(index: ^Index) -> uint {
	return index.count
}
