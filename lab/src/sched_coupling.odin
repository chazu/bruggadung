package lab

// BGCoupling — what passes between domains (DOMAIN_SIMULATION.md §7–8). A
// domain reads the others' values from a snapshot taken at step start, so it
// never sees another's mid-step state, and the order domains run in can't
// change the result. What it gives another is a contribution: a typed,
// additive amount, tagged with its source, which the scheduler holds in
// transit and hands to the domain that takes it, to apply over its next step.
//
// (ported from the Objective-C lab's sched/BGCoupling.m)

Quantity :: enum i32 {
	Temperature = 1,      // mK, a value
	Heat        = 2,      // J, an amount
}


Contribution :: struct {
	target:   Entity_ID,
	source:   Entity_ID,
	quantity: Quantity,
	amount:   i64,
}


// Values of the domains' participants, as of step start.
Snapshot :: struct {
	using object: Object,
	entities:   [dynamic]Entity_ID,      // _entities, _count and _size
	quantities: [dynamic]Quantity,
	values:     [dynamic]i64,
}

// [BGSnapshot new]
snapshot_new :: proc() -> ^Snapshot {
	return object_new(Snapshot, snapshot_dealloc)
}


snapshot_dealloc :: proc(self: ^Snapshot) {
	delete(self.entities)
	delete(self.quantities)
	delete(self.values)
}


snapshot_set_quantity :: proc(self: ^Snapshot, quantity: Quantity, entity: Entity_ID, value: i64) {
	for i := 0; i < len(self.entities); i += 1 {
		if self.entities[i] == entity && self.quantities[i] == quantity {
			self.values[i] = value
			return
		}
	}
	append(&self.entities, entity)
	append(&self.quantities, quantity)
	append(&self.values, value)
}


// false when no domain published it
snapshot_quantity :: proc(self: ^Snapshot, quantity: Quantity, entity: Entity_ID, value: ^i64) -> bool {
	for i := 0; i < len(self.entities); i += 1 {
		if self.entities[i] == entity && self.quantities[i] == quantity {
			value^ = self.values[i]
			return true
		}
	}
	return false
}


// A step's contributions, in the order they were made.
Contributions :: struct {
	using object: Object,
	items: [dynamic]Contribution,        // _items, _count and _size
}

// [BGContributions new]
contributions_new :: proc() -> ^Contributions {
	return object_new(Contributions, contributions_dealloc)
}


contributions_dealloc :: proc(self: ^Contributions) {
	delete(self.items)
}


contributions_add_contribution :: proc(self: ^Contributions, contribution: Contribution) {
	append(&self.items, contribution)
}


contributions_count :: proc(self: ^Contributions) -> uint {
	return uint(len(self.items))
}


contributions_contribution_at_index :: proc(self: ^Contributions, i: uint) -> Contribution {
	return self.items[i]
}
