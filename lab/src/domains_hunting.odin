package lab

// BGGame — the herds kept up (VILLAGE.md decision 7; content/hunting/): a
// scenario's input, for each kind of game, how many the woods hold at most,
// how often one may come in, and where: at its entry tiles on the woods'
// edge, each in turn. While fewer than that many live, one comes in at
// each due time; a count is read, never kept, so the dead and the
// butchered are simply fewer. An animal that comes in takes on its
// instinct (agency) as it first perceives.

import "core:fmt"
import "core:strconv"
import "core:strings"


Herd :: struct {
	blueprint: cstring,
	most:      int,
	every:     i64,        /* ms */
	entries:   [][2]i32,   /* tiles on level 0, each in turn */
	next:      i64,        /* when one may next come in */
	came:      int,        /* how many have: which entry is next */
}


Game :: struct {
	using object: Object,
	world:        ^World,
	herds:        [dynamic]Herd,
}


game_init_with_world :: proc(world: ^World) -> ^Game {
	self := object_new(Game, game_dealloc)
	self.world = retain(world)
	self.herds = make([dynamic]Herd)
	return self
}


game_dealloc :: proc(self: ^Game) {
	for h in self.herds do delete(h.entries)
	delete(self.herds)
	release(self.world)
}


// A herd of the blueprint: at most `most` of it, one coming in every
// `every` from `first`, at the entries in turn.
game_add_herd :: proc(self: ^Game, blueprint: cstring, most: int, first: i64, every: i64, entries: [][2]i32) {
	append(&self.herds, Herd{blueprint, most, every, sliceclone(entries), first, 0})
}


@(private = "file")
sliceclone :: proc(s: [][2]i32) -> [][2]i32 {
	c := make([][2]i32, len(s))
	copy(c, s)
	return c
}


// How many of the blueprint live now.
game_count :: proc(world: ^World, blueprint: cstring) -> int {
	n := 0
	agents := world_store_for_kind(world, world_kind_named(world, "Agent"))
	for i: uint = 0; i < store_count(agents); i += 1 {
		info := world_info(world, store_entity_at_index(agents, i))
		if info != nil && string(info.blueprint) == string(blueprint) do n += 1
	}
	return n
}


game_horizon_at :: proc(self: ^Game, t: Time) -> Horizon {
	h: Horizon
	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	for herd in self.herds {
		if herd.next > t.ms && herd.next < h.nextEvent.ms do h.nextEvent = time_make(herd.next)
	}
	return h
}


// Each herd due by t1: one comes in if there are fewer than its most.
game_advance_from :: proc(self: ^Game, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	group: ^Proposal_Group
	for &herd in self.herds {
		if herd.next > t1.ms || herd.every <= 0 do continue
		for herd.next <= t1.ms do herd.next += herd.every
		if len(herd.entries) == 0 || game_count(world, herd.blueprint) >= herd.most do continue
		at := herd.entries[herd.came % len(herd.entries)]
		herd.came += 1
		if group == nil do group = proposal_group_group_with_phase(.Process, "game: comes in from the woods' edge")
		proposal_group_create(group, herd.blueprint, herd.blueprint, on_tile(at.x, at.y, 0))
	}
	if group != nil do committer_submit(committer, group)
}


// "herd <blueprint> <next> <came>", each.
game_saved_state :: proc(self: ^Game) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	for h in self.herds do append(&lines, fmt.tprintf("herd %s %d %d", h.blueprint, h.next, h.came))
	return lines[:]
}


game_restore_saved_state :: proc(self: ^Game, lines: []string) {
	for line in lines {
		words := strings.fields(line, context.temp_allocator)
		if len(words) != 4 || words[0] != "herd" do continue
		for &h in self.herds {
			if string(h.blueprint) != words[1] do continue
			h.next, _ = strconv.parse_i64(words[2])
			came, _ := strconv.parse_int(words[3])
			h.came = came
		}
	}
}


game_as_domain :: proc(self: ^Game) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return "game"},
		check_in_all        = proc(data: rawptr) {},
		saved_state         = proc(data: rawptr) -> []string {return game_saved_state((^Game)(data))},
		restore_saved_state = proc(data: rawptr, lines: []string) {game_restore_saved_state((^Game)(data), lines)},
		is_active           = proc(data: rawptr) -> bool {return len((^Game)(data).herds) > 0},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return game_horizon_at((^Game)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			game_advance_from((^Game)(data), t0, t1, world, committer)
		},
	}
}
