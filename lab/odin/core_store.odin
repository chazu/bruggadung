package lab

/*
 * BGStore — every component of one kind, keyed by entity ID and iterated in
 * ID order. Records are the C structs generated from content; the store
 * knows only their size.
 */

import "core:mem"

Store :: struct {
	using object: Object,
	size:         uint,
	count:        uint,
	capacity:     uint,
	ids:          [^]Entity_ID,
	records:      [^]u8,
	changes:      u64,
	members:      u64,
}

// -initWithRecordSize: (NAMES.md's guess took self: alloc and init are one
// call here, returning the store with a count of 1).
store_init_with_record_size :: proc(size: uint) -> ^Store {
	self := object_new(Store, store_dealloc)
	self.size = size
	return self
}

store_dealloc :: proc(self: ^Store) {
	free(self.ids)
	free(self.records)
}

store_record_size :: proc(self: ^Store) -> uint {
	return self.size
}

store_count :: proc(self: ^Store) -> uint {
	return self.count
}

store_entity_at_index :: proc(self: ^Store, i: uint) -> Entity_ID {
	return self.ids[i]
}

store_record_at_index :: proc(self: ^Store, i: uint) -> rawptr {
	return &self.records[i * self.size]
}

/* The position of the entity, or where it would be inserted. */
@(private = "file")
position :: proc(self: ^Store, entity: Entity_ID, found: ^bool) -> uint {
	hi: uint
	lo: uint
	mid: uint

	lo = 0
	hi = self.count
	for lo < hi {
		mid = (lo + hi) / 2
		if self.ids[mid] < entity {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	found^ = lo < self.count && self.ids[lo] == entity
	return lo
}

/* NULL if the entity has no record here */
store_record_for :: proc(self: ^Store, entity: Entity_ID) -> rawptr {
	found: bool
	i: uint

	i = position(self, entity, &found)
	return &self.records[i * self.size] if found else nil
}

/* Inserts or replaces the entity's record with a copy of `record`. */
store_set_record :: proc(self: ^Store, record: rawptr, entity: Entity_ID) {
	found: bool
	i: uint

	i = position(self, entity, &found)
	if !found {
		if self.count == self.capacity {
			old := self.capacity
			self.capacity = self.capacity * 2 if self.capacity != 0 else 16
			self.ids = ([^]Entity_ID)(realloc(self.ids, size_of(Entity_ID) * old, size_of(Entity_ID) * self.capacity))
			self.records = ([^]u8)(realloc(self.records, self.size * old, self.size * self.capacity))
		}
		mem.copy(&self.ids[i + 1], &self.ids[i], int(size_of(Entity_ID) * (self.count - i)))
		mem.copy(&self.records[(i + 1) * self.size], &self.records[i * self.size], int(self.size * (self.count - i)))
		self.ids[i] = entity
		self.count += 1
		self.members += 1
	}
	mem.copy(&self.records[i * self.size], record, int(self.size))
	self.changes += 1
}

store_remove_record_for :: proc(self: ^Store, entity: Entity_ID) {
	found: bool
	i: uint

	i = position(self, entity, &found)
	if !found do return
	mem.copy(&self.ids[i], &self.ids[i + 1], int(size_of(Entity_ID) * (self.count - i - 1)))
	mem.copy(&self.records[i * self.size], &self.records[(i + 1) * self.size], int(self.size * (self.count - i - 1)))
	self.count -= 1
	self.changes += 1
	self.members += 1
}

/* How many times a record was set or removed: a cache over the store is good
 * while this is as it was. */
store_changes :: proc(self: ^Store) -> u64 {
	return self.changes
}

/* How many times an entity was added or removed: a cache of which entities
 * are here is good while this is as it was. */
store_members :: proc(self: ^Store) -> u64 {
	return self.members
}

// realloc: the block resized, in the context allocator.
@(private = "file")
realloc :: proc(p: rawptr, old_size, new_size: uint) -> rawptr {
	q, _ := mem.resize(p, int(old_size), int(new_size))
	return q
}
