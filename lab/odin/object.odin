package lab

// Objects with reference counts, as the Objective-C lab had them (manual
// retain/release), so the port keeps every object's lifetime as it was: a
// class's struct starts with `using object: Object`; `object_new` makes one
// with a count of 1 and its dealloc; `retain`, `release` and `autorelease`
// are the messages. Autorelease pools drain where the lab drained them: once
// a test (run_tests) and at the end of main. A pool's drain releases what it
// holds, then takes the temporary allocator back to where it stood when the
// pool began: autoreleased strings and arrays live there, and die with the
// pool, as they did.
//
// PORTING.md, "Memory", says how a class's dealloc is written.

import "base:runtime"

Object :: struct {
	rc:      int,
	dealloc: proc(obj: ^Object),     // releases what the object holds; not the object itself
}

// A new object of type T, its count 1. dealloc (the class's `<type>_dealloc`)
// releases its fields: release frees the struct after it.
object_new :: proc($T: typeid, dealloc: proc(obj: ^T)) -> ^T {
	o := new(T)
	o.object = Object{1, transmute(proc(^Object))dealloc}
	return o
}

retain :: proc(o: ^$T) -> ^T {
	if o != nil do o.object.rc += 1
	return o
}

release :: proc(o: ^$T) {
	if o != nil do object_release(&o.object)
}

autorelease :: proc(o: ^$T) -> ^T {
	if o != nil do object_autorelease(&o.object)
	return o
}

// The same, for an object known only as a pointer (a protocol's data): it
// must be one of the lab's objects.
object_retain :: proc(p: rawptr) -> rawptr {
	if p != nil do (^Object)(p).rc += 1
	return p
}

object_release :: proc(p: rawptr) {
	if p == nil do return
	o := (^Object)(p)
	assert(o.rc > 0, "an object released once too often")
	o.rc -= 1
	if o.rc == 0 {
		if o.dealloc != nil do o.dealloc(o)
		free(o)
	}
}

object_autorelease :: proc(p: rawptr) -> rawptr {
	if p == nil do return nil
	assert(len(pools) > 0, "an object autoreleased with no pool")
	append(&pools[len(pools) - 1].objects, p)
	return p
}

@(private = "file")
Pool :: struct {
	objects: [dynamic]rawptr,
	temp:    runtime.Arena_Temp,
}

@(private = "file")
pools: [dynamic]Pool

// NSAutoreleasePool new.
pool_push :: proc() {
	append(&pools, Pool{make([dynamic]rawptr), runtime.default_temp_allocator_temp_begin()})
}

// [pool release]: what it holds is released, in the order it was put in;
// then the temporary allocator goes back to where it stood.
pool_drain :: proc() {
	p := &pools[len(pools) - 1]
	for i := 0; i < len(p.objects); i += 1 do object_release(p.objects[i])   // a dealloc may autorelease more
	delete(p.objects)
	runtime.default_temp_allocator_temp_end(p.temp)
	pop(&pools)
}

// The count, for tests of lifetimes.
retain_count :: proc(o: ^$T) -> int {
	return o.object.rc
}
