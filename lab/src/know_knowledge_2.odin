package lab

// know/BGKnowledge.m, part 3 of 3 (its lines 3877 to the end): the rest of
// the BGKnowledge class: perceiving a boundary, the developer's true
// ancestry of claims, the wakes of perception and forgetting, the
// developer's view, and saves; with BGSplitTopLevel, BGWritingEntries,
// BGEncodeWord and BGDecodeWord, and the conformances to Perception_Phase
// and Saved_System. The types, the statics before line 1720 and the store
// are in part 1; lines 1720 to 3876 in part 2. The .m's statics are
// package-level `know_...` (the split's rule), wherever they are defined.

import "core:c/libc"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


// realloc: the block resized, in the context allocator.
@(private = "file")
realloc :: proc(p: rawptr, old_size, new_size: uint) -> rawptr {
	q, _ := mem.resize(p, int(old_size), int(new_size))
	return q
}

// strncpy into a buffer: up to n bytes of src, the rest of the n zeroed.
@(private = "file")
strncpy :: proc(dst: [^]u8, src: [^]u8, n: int) {
	i := 0
	for ; i < n && src != nil && src[i] != 0; i += 1 do dst[i] = src[i]
	for ; i < n; i += 1 do dst[i] = 0
}

// printf's "%s" of a C string that may be NULL.
@(private = "file")
nul_s :: proc(s: cstring) -> cstring {
	return s if s != nil else "(null)"
}


knowledge_perceptions :: proc(self: ^Knowledge) -> u64 {
	return self.perceptions
}


knowledge_perceive :: proc(self: ^Knowledge, store: ^Knowledge_Store, first: uint, last: uint) {
	ev:          ^Event
	body:        ^Thermal_Body
	gas:         ^Gas_Store
	r:           ^Referent
	near:        [^]Entity_ID
	nnear:       uint
	kbody:       uint
	view:        ^View
	seen:        [^]Seen
	lookedIn:    [64]Entity_ID
	glimpsed:    [64]Entity_ID
	witnessed:   [64]uint
	o:           Observation
	agent:       Entity_ID
	here:        Location
	at:          Location
	tile:        Location
	news:        ^[dynamic]string
	kind:        string
	features:    string
	specific:    string
	assigned:    [^]u32      /* per visible entity: its referent */
	taken:       [^]u8       /* per referent index: matched this phase */
	container:   u32
	closely:     bool
	degraded:    bool
	impaired:    bool
	distracted:  bool
	doubted:     bool
	blurred:     bool
	maybe:       uint
	maybeN:      i32
	maybeD:      i32
	maybeA:      i32
	maybePaths:  [64]u8
	hider:       ^Agent
	memory:      ^Agent
	concerns:    []string
	notice:      i32
	nlooked:     uint
	nglimpsed:   uint
	nwitnessed:  uint
	nseen:       uint
	i:           uint
	j:           uint
	best:        uint
	now:         i64
	x:           i32
	y:           i32
	pass:        i32
	d:           i32
	bestd:       i32
	exact:       bool
	glance:      [64]uint
	nglance:     uint
	candidates:  [64]Candidate
	ncandidates: uint
	budget:      int
	left:        int

	self.perceptions += 1

	agent       = knowledge_store_agent(store)
	news        = knowledge_store_mutable_news(store)
	nglance     = 0
	ncandidates = 0
	// the news lines are the store's own (cloned): those let go are deleted
	for line in news^ do delete(line)
	clear(news)
	if !world_is_live(self.world, agent) || !know_ground_tile(self.world, agent, &here) do return
	now = world_time(self.world).ms
	/* where it was when it last perceived: a label it has just come close
	 * enough to read is read, sighted or not */
	was := knowledge_store_referent(store, knowledge_store_self_referent(store))
	wasAt := Location{form = .On_Tile, x = was.x, y = was.y, level = was.level} if was != nil && was.seen > 0 else here
	klabel := world_kind_named(self.world, "Label")

	/* what the agent looked into this boundary: where it put something, or reached */
	nlooked = 0
	for i = first; i < last && nlooked < 64; i += 1 {
		ev = world_event_at(self.world, i)
		if ev.actor != agent do continue
		if ev.location.form == .In && ev.location.place != 0 {
			lookedIn[nlooked] = ev.location.place
			nlooked += 1
		} else if (string(ev.kind) == "attempted" || string(ev.kind) == "looked") && ev.other != 0 {
			lookedIn[nlooked] = ev.other
			nlooked += 1
		}
		/* reaching for something in a container: taking from a stack in the bin */
		if nlooked < 64 && ev.other != 0 && world_location_of(self.world, ev.other).form == .In {
			lookedIn[nlooked] = world_location_of(self.world, ev.other).place
			nlooked += 1
		}
		if nlooked < 64 && ev.subject != 0 && world_location_of(self.world, ev.subject).form == .In {
			lookedIn[nlooked] = world_location_of(self.world, ev.subject).place
			nlooked += 1
		}
	}

	/* what happens in sight, by an actor it can see (event perception); a
	 * thing seen put somewhere is seen there, though nothing else inside is */
	nwitnessed = 0
	nglimpsed  = 0
	for i = first; i < last && nwitnessed < 64; i += 1 {
		ev = world_event_at(self.world, i)
		if ev.actor == 0 || (string(ev.kind) != "moved" && string(ev.kind) != "said") do continue
		if string(ev.kind) == "moved" && ev.subject == ev.actor do continue      /* a step: where the walker is, it is seen */
		if !self.omniscient && (!know_ground_tile(self.world, ev.actor, &tile) || !knowledge_in_sight(self, tile, here)) do continue
		witnessed[nwitnessed] = i
		nwitnessed += 1
		if string(ev.kind) == "moved" && nglimpsed < 64 {
			glimpsed[nglimpsed] = ev.subject
			nglimpsed += 1
		}
	}

	/* what is in sight, holders before what they hold */
	kbody = world_kind_named(self.world, "Body")
	nnear = knowledge_candidates_from(self, here, &near)
	seen  = make([^]Seen, nnear + 1)
	nseen = 0
	for i = 0; i < nnear; i += 1 {
		e: Entity_ID

		e = near[i]
		if world_record(self.world, kbody, e) == nil || !know_ground_tile(self.world, e, &tile) do continue
		/* an area, by the nearest of its tiles (content/things.tri) */
		sight := tile
		if world_location_of(self.world, e).form == .On_Tile {
			east, south := world_area_extent(self.world, e)
			sight = area_nearest(tile, east, south, here)
		}
		if !knowledge_sees(self, sight, here) do continue
		at = world_location_of(self.world, e)
		if at.form == .In && !self.omniscient && !know_contains(raw_data(lookedIn[:]), nlooked, at.place) &&
		   !know_contains(raw_data(glimpsed[:]), nglimpsed, e) {
			continue          /* inside, unseen */
		}
		hider = (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), e))
		if hider != nil && hider.hiding && e != agent && !self.omniscient &&
		   (abs(tile.x - here.x) > 1 || abs(tile.y - here.y) > 1) {
			continue          /* half hidden: seen only from close by */
		}
		seen[nseen].entity = e
		seen[nseen].depth  = know_depth_of(self.world, e)
		nseen += 1
	}
	slice.sort_by(seen[:nseen], know_cmp_seen)
	free(near)
	/* terrain changed where it can't see: it recalls what it saw there
	 * (TERRAIN.md decision 7); then the tiles it sees now */
	for i = first; i < last; i += 1 {
		ev = world_event_at(self.world, i)
		if string(ev.kind) == "terrain" && ev.location.form == .On_Tile && !knowledge_sees(self, ev.location, here) {
			knowledge_store_miss_change_from(store, Terrain_Kind(ev.amount), ev.location.x, ev.location.y, ev.location.level)
		}
	}
	for y = here.y - BG_SIGHT; y <= here.y + BG_SIGHT; y += 1 {
		for x = here.x - BG_SIGHT; x <= here.x + BG_SIGHT; x += 1 {
			tile   = here
			tile.x = x
			tile.y = y
			if world_is_tile_x(self.world, x, y, here.level) && knowledge_sees(self, tile, here) {
				knowledge_store_see(store, now, x, y, here.level)
			}
		}
	}

	/* recognition: the same kind, at that very place first, then the nearest */
	view     = view_of(agent, self.world)
	assigned = make([^]u32, nseen + 1)
	taken    = make([^]u8, knowledge_store_count(store) + nseen + 1)
	/* the perceiver's state, and its attention (KNOWLEDGE.md decision 12) */
	memory     = (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), agent))
	impaired   = memory != nil && (memory.fatigue + memory.injury >= BG_IMPAIRED || memory.adrenaline >= BG_IMPAIRED / 2 ||
	                               weakness(self.world, agent, .Perception, now) >= 50)
	distracted = knowledge_attention_of(self, agent) >= BG_ATTENTION / 2
	for pass = 0; pass < 2; pass += 1 {
		for i = 0; i < nseen; i += 1 {
			if assigned[i] != 0 do continue
			kind     = view_kind_of(view, seen[i].entity)
			features = knowledge_features_of(self, seen[i].entity, view)
			at       = world_location_of(self.world, seen[i].entity)
			know_ground_tile(self.world, seen[i].entity, &tile)
			/* by the light: at dusk, beyond arm's reach, a step less precisely;
			 * at night, within it, unless just handled; and so too impaired
			 * (worn out, hurt, or full of adrenaline), or distracted (half its
			 * attention or more on what it is doing): KNOWLEDGE.md decision 12 */
			degraded = !self.omniscient && seen[i].entity != agent &&
			           ((knowledge_light_at(self, tile) == 1 && (abs(tile.x - here.x) > 1 || abs(tile.y - here.y) > 1)) ||
			            (knowledge_light_at(self, tile) == 0 && !know_contains(raw_data(lookedIn[:]), nlooked, seen[i].entity)) ||
			            impaired || distracted)
			specific = features
			doubted  = degraded
			if degraded do features = knowledge_store_generalize(store, features, ns_utf8(kind), 1)
			/* from afar, sizes only roughly: what it half took in too */
			if !self.omniscient && seen[i].entity != agent {
				features = knowledge_blur(self, features, ns_utf8(kind),
				                          i32(know_max64(i64(abs(tile.x - here.x)), i64(abs(tile.y - here.y)))), &degraded)
				specific = knowledge_blur(self, specific, ns_utf8(kind),
				                          i32(know_max64(i64(abs(tile.x - here.x)), i64(abs(tile.y - here.y)))), &blurred)
			}
			container = 0
			for j = 0; j < i; j += 1 {
				if seen[j].entity == at.place do container = assigned[j]
			}
			if seen[i].entity == agent {
				/* an agent knows itself */
				if knowledge_store_self_referent(store) == 0 {
					knowledge_store_set_self(store, knowledge_store_add_referent(store, 0).id)
				}
				r = knowledge_store_mutable_referent(store, knowledge_store_self_referent(store))
			} else {
				best      = NOT_FOUND
				bestd     = 1 << 30
				maybe     = NOT_FOUND
				maybeN    = 1 << 30
				maybeD    = 1 << 30
				maybePaths[0] = 0
				for j = 0; j < knowledge_store_count(store); j += 1 {
					r = knowledge_store_referent_at(store, j)
					if taken[j] != 0 || r.ended || r.id == knowledge_store_self_referent(store) || r.kind == nil || string(r.kind) != kind do continue
					exact = r.present && r.form == at.form && r.container == container &&
					        (container != 0 || (r.x == tile.x && r.y == tile.y))
					d = 0 if exact else ((1 if r.present else 2) + i32(know_max64(i64(abs(r.x - tile.x)), i64(abs(r.y - tile.y)))))
					if pass == 0 && !exact do continue
					/* elsewhere, a thing can't be where it is still believed to be
					 * (KNOWLEDGE.md decision 18): one like it is another, unless
					 * the agent believes it gone from there, it goes about by
					 * itself, the agent sees where it was, or saw it moved */
					if !exact && r.present && !knowledge_moves_itself(r) &&
					   !knowledge_sees(self, Location{form = .On_Tile, x = r.x, y = r.y, level = r.level}, here) &&
					   !know_contains(raw_data(glimpsed[:]), nglimpsed, seen[i].entity) {
						continue
					}
					/* elsewhere, a referent known by nothing matches anyone: weakly */
					if !exact && !knowledge_knows_anything_of(self, r, store) do continue
					/* elsewhere than believed, it must look the same: the crate isn't the chest;
					 * unless only what changes daily differs, when it may be the same, changed */
					if !exact && !knowledge_looks_alike(self, r, store, kind, features) {
						nc:    i32
						agree: i32
						paths: [64]u8

						nc = knowledge_conflicts_of(self, r, store, kind, features, raw_data(paths[:]), size_of(paths), &agree)
						if pass == 1 && nc != 0 && knowledge_short_lived(self, cstring(raw_data(paths[:]))) &&
						   (nc < maybeN || (nc == maybeN && d < maybeD)) {
							maybe  = j
							maybeN = nc
							maybeD = d
							maybeA = agree
							strncpy(raw_data(maybePaths[:]), raw_data(paths[:]), size_of(maybePaths) - 1)
						}
						continue
					}
					if d < bestd {
						bestd = d
						best  = j
					}
				}
				if best == NOT_FOUND && pass == 0 do continue
				if best == NOT_FOUND {
					other: u32

					other = knowledge_store_referent_at(store, maybe).id if maybe != NOT_FOUND else 0
					r     = knowledge_store_add_referent(store, 0)
					append(news, fmt.aprintf("R%d: %s, at (%d, %d)", r.id, kind, tile.x, tile.y))
					if other != 0 {
						h: Identity

						/* it may be the other, changed: the agreeing paths for it, the conflicts against */
						h = {}
						h.a        = r.id
						h.b        = other
						h.credence = BG_PRIOR + 3 * maybeA - 5 * maybeN
						h.time     = now
						strncpy(raw_data(h.paths[:]), raw_data(maybePaths[:]), size_of(h.paths) - 1)
						knowledge_store_add_identity(store, h)
						append(news, fmt.aprintf("R%d may be R%d (%+d dB): only %s differs", r.id, other,
						                         h.credence, cstring(raw_data(h.paths[:]))))
					}
				} else {
					r = knowledge_store_referent_at(store, best)
					if !(r.present && r.form == at.form && r.container == container &&
					     (container != 0 || (r.x == tile.x && r.y == tile.y))) {
						append(news, fmt.aprintf("R%d is at (%d, %d) now", r.id, tile.x, tile.y))
					}
				}
			}
			/* it fits the other of a hypothesis about it as well: evidence they
			 * are one, once a sighting (not seen for a minute before) */
			for j = 0; r.id != knowledge_store_self_referent(store) && now - r.seen > 60000 && j < knowledge_store_identity_count(store); j += 1 {
				h:    ^Identity
				oref: ^Referent

				h = knowledge_store_mutable_identity_at(store, j)
				if (h.a != r.id && h.b != r.id) || h.time >= now do continue
				oref = knowledge_store_referent(store, h.b if h.a == r.id else h.a)
				if oref == nil || !knowledge_looks_alike(self, oref, store, kind, features) do continue
				h.credence += 10
				h.time      = now
				append(news, fmt.aprintf("R%d may be R%d (%+d dB): it fits both", h.a, h.b, h.credence))
			}

			/* the referent takes what was perceived: kept more specific where
			 * memory was, when it was seen less well */
			if r.features != nil && r.id != knowledge_store_self_referent(store) && degraded {
				features = knowledge_unified(self, r, store, kind, features)
			}
			knowledge_notice_wear_lost(self, r, features, store, now, news)
			/* seen plainly, a competing hypothesis is settled */
			if !degraded && r.supposed[0] != nil {
				append(news, fmt.aprintf("R%d is plainly as it seems: no doubt about it now", r.id))
				knowledge_store_drop_supposed(store, r.id)
			}
			/* seen less well than usual, what it half took in lingers: a doubt
			 * (KNOWLEDGE.md decision 12), "it was this, or maybe that" */
			if doubted && r.id != knowledge_store_self_referent(store) && specific != features &&
			   knowledge_store_hypotheses_of(store, r.id) == 0 {
				knowledge_store_suppose(store, specific, r.id, BG_DOUBT)
				append(news, fmt.aprintf("R%d: seen poorly, maybe %s", r.id, specific))
			}
			// the copies are made before the old are let go: what was perceived
			// may be the referent's own text
			nkind     := strings.clone_to_cstring(kind)
			nfeatures := strings.clone_to_cstring(features)
			delete(r.kind)
			delete(r.features)
			r.kind     = nkind
			r.features = nfeatures
			r.form      = at.form
			r.container = container
			r.x         = tile.x
			r.y         = tile.y
			r.level     = tile.level
			r.slot      = at.slot
			r.role      = at.role
			/* a sighting (not seen for a minute before): remembered longer for
			 * each; a label, on sighting it, or on coming close enough to read
			 * it from further, is read below */
			sighted := r.seen == 0 || now - r.seen > 60000
			if sighted do r.sightings += 1
			if label := (^Label)(world_record(self.world, klabel, seen[i].entity)) if klabel != 0 else nil; label != nil && nglance < 64 {
				if sighted || wasAt.level != tile.level || i64(max(abs(wasAt.x - tile.x), abs(wasAt.y - tile.y))) > label.legible {
					glance[nglance] = i
					nglance += 1
				}
			}
			r.seen    = now
			if r.first < 0 do r.first = now
			r.present = true
			r.truth   = seen[i].entity                /* developer-only */
			r.toldBy  = 0
			/* whom it is bound to, it knows when it recognizes them */
			r.loyalty = know_loyalty(self.world, agent, seen[i].entity)
			/* and what it owns, as its own (KNOWLEDGE.md decision 18) */
			know_own(self, store, agent, seen[i].entity, r.id, now)
			if self.omniscient || know_contains(raw_data(lookedIn[:]), nlooked, seen[i].entity) do r.insideSeen = now
			if r.form == .In || r.form == .Held_By do know_settle(store, r.id, r.container, true, now, news)
			assigned[i] = r.id
			for j = 0; j < knowledge_store_count(store); j += 1 {
				if knowledge_store_referent_at(store, j).id == r.id do taken[j] = 1
			}
		}
	}

	/* a close look: what its investigation ends in */
	closely = false
	for i = first; i < last; i += 1 {
		if world_event_at(self.world, i).actor == agent && string(world_event_at(self.world, i).kind) == "investigated" do closely = true
	}

	/* what it read: each entry, from the author, in the record */
	for i = first; i < last; i += 1 {
		who:     ^tri.Node
		arena:   ^tri.Arena
		entries: []string
		by:      string
		k:       uint
		author:  u32
		record:  u32

		ev = world_event_at(self.world, i)
		if ev.actor != agent || string(ev.kind) != "read" || ev.detail == nil do continue
		by      = ""
		entries = writing_entries(ev.detail, &by)
		arena   = tri.arena_new()
		who     = tri.value(world_tri(self.world), ns_utf8(by), arena, nil, 0) if by != "" else nil
		author  = knowledge_person(self, who, store, news) if who != nil else 0
		tri.arena_free(arena)
		record  = know_bound_to(ev.other, agent, knowledge_store_self_referent(store), seen, assigned, nseen)
		for k = 0; author != 0 && k < uint(len(entries)); k += 1 {
			knowledge_believe(self, ns_utf8(entries[k]), author, record, ev.index, now, store, news)
		}
	}

	/* what a label it sighted says, read at a glance from close enough
	 * (ACTIONS.md §7's tag): each entry, from the author, in the label */
	for j = 0; j < nglance; j += 1 {
		who:     ^tri.Node
		label:   ^Label
		arena:   ^tri.Arena
		entries: []string
		by:      string
		written: cstring
		k:       uint
		author:  u32

		i     = glance[j]
		label = (^Label)(world_record(self.world, world_kind_named(self.world, "Label"), seen[i].entity))
		if !know_ground_tile(self.world, seen[i].entity, &tile) || tile.level != here.level ||
		   i64(abs(tile.x - here.x)) > label.legible || i64(abs(tile.y - here.y)) > label.legible {
			continue
		}
		written = world_text_field(self.world, "Record.writing", seen[i].entity)
		if written == nil || len(written) == 0 do continue
		by      = ""
		entries = writing_entries(written, &by)
		arena   = tri.arena_new()
		who     = tri.value(world_tri(self.world), ns_utf8(by), arena, nil, 0) if by != "" else nil
		author  = knowledge_person(self, who, store, news) if who != nil else 0
		tri.arena_free(arena)
		for k = 0; author != 0 && k < uint(len(entries)); k += 1 {
			knowledge_believe(self, ns_utf8(entries[k]), author, assigned[i], 0, now, store, news)
		}
	}

	/* arrested (INSTITUTIONS.md decision 7): it knows it, and by whom */
	for i = first; i < last; i += 1 {
		f: Finding

		ev = world_event_at(self.world, i)
		if string(ev.kind) != "arrested" || ev.subject != agent do continue
		f = {}
		f.kind     = world_intern(self.world, "#Arrested")
		f.about    = knowledge_store_self_referent(store)
		f.choice   = know_bound_to(ev.other, agent, knowledge_store_self_referent(store), seen, assigned, nseen)
		f.credence = BG_SEEN
		f.rule     = world_intern(self.world, "seen")
		f.time     = now
		knowledge_store_retract_finding(store, "#Arrested", f.about)
		knowledge_store_add_finding(store, f)
		append(news, fmt.aprintf("you are under arrest, by R%d", f.choice))
	}

	/* struck (AGENCY.md §13): a threat, which it knows, and from whom; the
	 * finding is about the one who struck, so a goal can turn on it */
	for i = first; i < last; i += 1 {
		f: Finding

		ev = world_event_at(self.world, i)
		if string(ev.kind) != "struck" || ev.subject != agent do continue
		f = {}
		f.kind     = world_intern(self.world, "#Struck")
		f.about    = know_bound_to(ev.other, agent, knowledge_store_self_referent(store), seen, assigned, nseen)
		f.choice   = knowledge_store_self_referent(store)
		f.credence = BG_SEEN
		f.rule     = world_intern(self.world, "felt")
		f.time     = now
		if f.about == 0 do continue
		knowledge_store_retract_finding(store, "#Struck", f.about)
		knowledge_store_add_finding(store, f)
		knowledge_store_adjust_trust_in(store, f.about, -BG_WRONGED)
		append(news, fmt.aprintf("R%d struck you", f.about))
	}

	/* what its own analyses found beneath the looks of what they analysed */
	for i = first; i < last; i += 1 {
		ev = world_event_at(self.world, i)
		if ev.actor != agent || string(ev.kind) != "analysed" || ev.detail == nil do continue
		r = knowledge_store_mutable_referent(store, know_bound_to(ev.other, agent, knowledge_store_self_referent(store), seen, assigned, nseen))
		if r == nil do continue
		delete(r.deeper)
		r.deeper = strings.clone_to_cstring(string(ev.detail))
		append(news, fmt.aprintf("R%d, beneath its looks: %s", r.id, ev.detail))
	}

	/* absence: believed at a place in sight, and not seen there; what it
	 * saw end there ended (KNOWLEDGE.md decision 19), the rest is lost */
	ends := know_ends_witnessed(self, store, agent, here, first, last, seen, assigned, nseen)
	gone := make([dynamic]u32, context.temp_allocator)
	for j = 0; j < knowledge_store_count(store); j += 1 {
		holder: ^Referent

		r = knowledge_store_referent_at(store, j)
		if taken[j] != 0 || !r.present do continue
		{
			believed: Location

			believed       = here
			believed.x     = r.x
			believed.y     = r.y
			believed.level = r.level
			if !knowledge_sees(self, believed, here) do continue       /* out of sight, or dark there */
		}
		if r.form == .In && !self.omniscient {
			holder = knowledge_store_referent(store, r.container)
			if holder == nil || !know_contains(raw_data(lookedIn[:]), nlooked, holder.truth) do continue       /* inside, and not looked into: nothing to contradict it */
		}
		r.present = false
		append(news, fmt.aprintf("R%d is not where it was", r.id))
		append(&gone, r.id)
	}
	know_ended(store, ends[:], gone[:], news)
	for id in gone {
		r = knowledge_store_mutable_referent(store, id)
		if r != nil && !r.ended do know_lost(self, store, r, news)
	}

	/* what has faded too far, forgotten */
	for j = 0; j < knowledge_store_count(store); j += 1 {
		habit: u32

		r = knowledge_store_referent_at(store, j)
		if !r.present || r.id == knowledge_store_self_referent(store) || knowledge_store_strength_of_referent(store, r) >= BG_BELIEVE do continue
		/* what it always puts in the same place, it believes is there (AGENCY.md
		 * Scenario 1: Oskar always hangs the wrench on the hook) */
		habit = know_own_usual_place(store, r.id, 3)
		if habit != 0 {
			if r.form != .In || r.container != habit {
				r.form      = .In
				r.container = habit
				append(news, fmt.aprintf("R%d: where it always goes, in R%d", r.id, habit))
			}
			continue
		}
		r.present = false
		append(news, fmt.aprintf("R%d: forgotten where it was", r.id))
	}
	know_forget(self, store, now, news)

	/* promised into someone's hand, and due: the holder, in sight now,
	 * hasn't it, so the promise is broken (in its hand, it was kept when
	 * seen there) */
	for j = 0; j < knowledge_store_testimony_count(store); j += 1 {
		t:      ^Testimony
		holder: ^Referent

		t      = knowledge_store_testimony_at(store, j)
		holder = knowledge_store_referent(store, t.container)
		if t.settled != 0 || t.attribution != .Pledged || now < t.when_ || holder == nil || holder.kind == nil ||
		   string(holder.kind) != "#Agent" || holder.seen != now {
			continue
		}
		r = knowledge_store_mutable_referent(store, t.thing)
		if r != nil && r.present && r.form == .Held_By && r.container == t.container do continue
		know_settle(store, t.thing, t.container, false, now, news)
	}

	/* what it was told is inside something it looked into: so it is, or it isn't */
	for j = 0; j < knowledge_store_testimony_count(store); j += 1 {
		t:      ^Testimony
		holder: ^Referent

		t      = knowledge_store_testimony_at(store, j)
		holder = knowledge_store_referent(store, t.container)
		if t.settled != 0 || holder == nil || holder.truth == 0 || !know_contains(raw_data(lookedIn[:]), nlooked, holder.truth) do continue
		r = knowledge_store_mutable_referent(store, t.thing)
		know_settle(store, t.thing, t.container, r != nil && r.present && r.form == .In && r.container == t.container,
		            now, news)
	}

	/* what it saw happen, in its referents, kept if salient; what it heard
	 * said, if it noticed, believed */
	memory = (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), agent))
	notice = BG_NOTICE + knowledge_attention_of(self, agent) - (i32(memory.curious) / 10 if memory != nil else 0)

	/* interoception: hunger, to the band, dulled by attention, blurred by
	 * exhaustion */
	if memory != nil {
		hunger: i64
		band:   i64

		/* exhaustion blurs it (AGENCY.md §6): felt half as precisely */
		band   = 2 * BG_HUNGER_BAND if memory.fatigue >= 80 else BG_HUNGER_BAND
		hunger = 100 - satiety(hungry_of(self.world, agent), now) - 2 * i64(knowledge_attention_of(self, agent))
		hunger = 0 if hunger < 0 else (hunger / band) * band
		if knowledge_store_feel_hunger(store, i32(hunger), now) {
			append(news, fmt.aprintf("you feel hunger (%d)", i32(hunger)))
		}
	}

	/* and cold, from its body's heat (the thermal domain's): ten points a
	 * kelvin below 310 K, to the band */
	body = (^Thermal_Body)(world_record(self.world, world_kind_named(self.world, "ThermalBody"), agent))
	if body != nil && body.heatCapacity != 0 {
		cold: i64

		cold = (310000 - body.heat * 1000 / body.heatCapacity) / 100
		/* numbness hides it */
		if memory != nil do cold -= memory.numbness
		cold = 0 if cold < 0 else (100 if cold > 100 else (cold / BG_HUNGER_BAND) * BG_HUNGER_BAND)
		if knowledge_store_feel_cold(store, i32(cold)) {
			append(news, fmt.aprintf("you feel cold (%d)", i32(cold)))
		}
	}

	/* and pain, from its injury (a component field), dulled by adrenaline */
	if memory != nil {
		pain: i64

		pain = i64(memory.injury) - memory.adrenaline
		pain = 0 if pain < 0 else (pain / BG_HUNGER_BAND) * BG_HUNGER_BAND
		if knowledge_store_feel_pain(store, i32(pain)) {
			append(news, fmt.aprintf("you feel pain (%d)", i32(pain)))
		}
	}

	/* and tired, from its fatigue (a component field), to the band */
	if memory != nil {
		tired: i64

		tired = (memory.fatigue / BG_HUNGER_BAND) * BG_HUNGER_BAND
		if knowledge_store_feel_tired(store, i32(tired)) {
			append(news, fmt.aprintf("you feel tired (%d)", i32(tired)))
		}
	}

	/* and short of breath, for something that breathes: from the carbon
	 * dioxide in the air over it (the atmosphere's; the blood's gases stand
	 * in for by the air's), ten points for every 0.1% above 0.1%, to the band */
	if world_record(self.world, world_kind_named(self.world, "Respirator"), agent) != nil {
		gas = (^Gas_Store)(world_record(self.world, world_kind_named(self.world, "GasStore"), air_over(self.world, agent)))
	} else {
		gas = nil
	}
	if gas != nil && gas.total != 0 {
		stuffy: i64

		stuffy = (gas.dioxide * 1000000 / gas.total - 1000) / 100
		stuffy = 0 if stuffy < 0 else (100 if stuffy > 100 else (stuffy / BG_HUNGER_BAND) * BG_HUNGER_BAND)
		if knowledge_store_feel_stuffy(store, i32(stuffy)) {
			append(news, fmt.aprintf("you feel short of breath (%d)", i32(stuffy)))
		}
	}
	concerns = self.concerns.concerns_of(self.concerns.data, agent) if self.concerns.data != nil else nil
	for i = 0; i < nwitnessed; i += 1 {
		lines: uint

		lines = uint(len(news^))
		ev    = world_event_at(self.world, witnessed[i])
		o = {}
		o.time  = now
		o.kind  = ev.kind
		o.actor = know_bound_to(ev.actor, agent, knowledge_store_self_referent(store), seen, assigned, nseen)
		if string(ev.kind) == "moved" {
			o.subject = know_bound_to(ev.subject, agent, knowledge_store_self_referent(store), seen, assigned, nseen)
			if ev.location.form == .In || ev.location.form == .Held_By {
				o.other = know_bound_to(ev.location.place, agent, knowledge_store_self_referent(store), seen, assigned, nseen)
			}
			if o.actor != knowledge_store_self_referent(store) {
				append(news, fmt.aprintf("R%d %s R%d%s", o.actor,
				                         "put" if ev.location.form == .In else
				                         "took" if ev.location.form == .Held_By else "moved",
				                         o.subject,
				                         fmt.tprintf(" into R%d", o.other) if ev.location.form == .In else ""))
			}
		} else {
			ancestry: ^Ancestry

			o.other   = know_bound_to(ev.other, agent, knowledge_store_self_referent(store), seen, assigned, nseen)
			o.content = ev.detail
			ancestry  = knowledge_ancestry_of(self, ev.index)
			if ev.actor == agent && ancestry != nil && ancestry.fabricated && !ancestry.relayed do o.unbelieved = true      /* it knows it didn't see that */
			if o.actor != knowledge_store_self_referent(store) {
				append(news, fmt.aprintf("R%d says to R%d: %s", o.actor, o.other,
				                         ev.detail if ev.detail != nil else ""))
			}
		}
		o.salience = 0
		if o.actor == knowledge_store_self_referent(store) do o.salience = BG_OWN_DEED
		if string(ev.kind) == "said" && o.other == knowledge_store_self_referent(store) do o.salience = BG_ADDRESSED
		if o.salience < BG_CONCERN &&
		   knowledge_concerns_description(self, concerns,
		                                  knowledge_topic_of(self, ev.detail) if string(ev.kind) == "said" else knowledge_store_describe_referent(store, o.subject)) {
			o.salience = BG_CONCERN
		}
		/* harm to those it is loyal to, or to what it believes theirs, is
		 * salient (AGENCY.md §12): what happens to them, it notices */
		if o.salience < BG_CONCERN && o.subject != 0 {
			owned: ^Finding

			owned = knowledge_store_finding(store, "#Owned", o.subject)
			if knowledge_store_loyalty_to(store, o.subject) > 0 || (owned != nil && knowledge_store_loyalty_to(store, owned.choice) > 0) {
				o.salience = BG_CONCERN
			}
		}
		/* someone not doing as they usually do */
		if string(ev.kind) == "moved" && o.other != 0 && ev.location.form == .In {
			k: uint

			for k = 0; k < knowledge_store_finding_count(store); k += 1 {
				habit: ^Finding

				habit = knowledge_store_finding_at(store, k)
				if string(habit.kind) == "#Habit" && habit.about == o.actor && habit.choice != 0 && habit.choice != o.other {
					o.salience = BG_ANOMALY if BG_ANOMALY > o.salience else o.salience
					append(news, fmt.aprintf("R%d broke a habit: R%d, not R%d, this time", o.actor, o.other,
					                         habit.choice))
				}
			}
		}
		if o.salience < notice {
			for line in news^[lines:] do delete(line)
			resize(news, int(lines))
			continue      /* unnoticed */
		}
		/* a candidate for attention: its news held back until it gets it */
		// (the lines move to the candidate: they are deleted if it gets none)
		candidates[ncandidates].o     = o
		candidates[ncandidates].event = witnessed[i]
		candidates[ncandidates].news  = slice.clone(news^[lines:], context.temp_allocator)
		resize(news, int(lines))
		ncandidates += 1
	}

	/* the attention budget (KNOWLEDGE.md §5, AGENCY.md §10): what is left of
	 * BG_ATTENTION after the running activity's demand, BG_PERCEPT_COST a
	 * percept; the most salient first, in event order among equals */
	budget = int((BG_ATTENTION * (100 - weakness(self.world, agent, .Attention, now)) / 100 -
	              i64(knowledge_attention_of(self, agent))) / BG_PERCEPT_COST)
	slice.sort_by(candidates[:ncandidates], know_cmp_candidates)
	for i = 0; i < ncandidates; i += 1 {
		if int(i) >= budget {
			append(news, fmt.aprintf("no attention left for event %d",
			                         world_event_at(self.world, candidates[i].event).index))
			self.short = true
			for line in candidates[i].news do delete(line)
			continue
		}
		o  = candidates[i].o
		ev = world_event_at(self.world, candidates[i].event)
		append(news, ..candidates[i].news)
		knowledge_store_add_observation(store, o, false)
		/* what took part in it is remembered as long as its most salient part */
		{
			parts: [3]u32
			p:     ^Referent
			q:     i32

			parts[0] = o.actor
			parts[1] = o.subject
			parts[2] = o.other
			for q = 0; q < 3; q += 1 {
				if parts[q] == 0 do continue
				p = knowledge_store_mutable_referent(store, parts[q])
				if p != nil && p.salience < o.salience do p.salience = o.salience
			}
		}
		if string(ev.kind) == "said" && ev.detail != nil && o.actor != 0 && o.actor != knowledge_store_self_referent(store) {
			knowledge_believe(self, ev.detail, o.actor, 0, ev.index, now, store, news)
		}
		/* seen taken into someone's hand who isn't its owner, as the agent
		 * believes it: taken (INSTITUTIONS.md decision 6, a wrong witnessed) */
		if string(ev.kind) == "moved" && o.actor != 0 && o.subject != 0 && o.actor != knowledge_store_self_referent(store) &&
		   ev.location.form == .Held_By && ev.location.place == ev.actor {
			owned: ^Finding
			f:     Finding

			owned = knowledge_store_finding(store, "#Owned", o.subject)
			if owned != nil && owned.choice != o.actor && knowledge_store_finding(store, "#Taken", o.subject) == nil {
				f = {}
				f.kind     = world_intern(self.world, "#Taken")
				f.about    = o.subject
				f.choice   = o.actor
				f.credence = BG_SEEN
				f.rule     = world_intern(self.world, "seen")
				f.time     = now
				knowledge_store_add_finding(store, f)
				knowledge_store_adjust_trust_in(store, o.actor, -BG_WRONGED)
				append(news, fmt.aprintf("R%d took R%d, R%d's", o.actor, o.subject, owned.choice))
			}
		}
	}
	/* believed the same past the threshold content declares (KNOWLEDGE.md
	 * decision 13): one referent, the older */
	knowledge_merge_identities(self, store, news)
	memory = (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), agent))
	knowledge_store_keep_at_most(store, uint(memory.memory) if memory != nil && memory.memory > 0 else 64)
	/* what the events attended to left of the budget, for traces new to it,
	 * then for thinking it over */
	left = budget - int(ncandidates)
	if left < 0 do left = 0
	knowledge_perceive_traces(self, store, here, now, seen, assigned, nseen, closely, &left, news)
	mark := now_ns()
	knowledge_interpret(self, store, closely, left, news)
	self.interpretationNs += now_ns() - mark
	free(seen)
	free(assigned)
	free(taken)
}


/* --- true ancestry (developer-only) ------------------------------------------------ */

knowledge_ancestry_of :: proc(self: ^Knowledge, utterance: u64) -> ^Ancestry {
	i: uint

	for i = 0; i < self.nancestry; i += 1 {
		if self.ancestry[i].utterance == utterance do return &self.ancestry[i]
	}
	return nil
}


knowledge_root_of :: proc(self: ^Knowledge, utterance: u64) -> ^Ancestry {
	a:     ^Ancestry
	guard: uint

	a = knowledge_ancestry_of(self, utterance)
	for guard = 0; a != nil && a.relayed && guard < 64; guard += 1 {
		if knowledge_ancestry_of(self, a.parent) == nil do break
		a = knowledge_ancestry_of(self, a.parent)
	}
	return a
}


knowledge_add_ancestry :: proc(self: ^Knowledge, a: Ancestry) {
	if self.nancestry == self.acapacity {
		old := self.acapacity
		self.acapacity = self.acapacity * 2 if self.acapacity != 0 else 16
		self.ancestry  = ([^]Ancestry)(realloc(self.ancestry, old * size_of(Ancestry), self.acapacity * size_of(Ancestry)))
	}
	self.ancestry[self.nancestry] = a
	self.nancestry += 1
}


/* Where a claim said came from, by what its speaker knew when it spoke:
 * something like `what` it believed inside a container of the kind on that
 * tile. Seen, the speaker is the root; told, it relays the testimony that
 * weighs most; believed nowhere, it made the claim up. */
knowledge_trace :: proc(self: ^Knowledge, ev: ^Event) {
	claim:  ^tri.Node
	r:      ^Referent
	c:      ^Referent
	t:      ^Testimony
	parent: ^Ancestry
	store:  ^Knowledge_Store
	a:      Ancestry
	content: ^tri.Content
	arena:  ^tri.Arena
	kind:   cstring
	ckind:  cstring
	x:      i64
	y:      i64
	level:  i64
	i:      uint

	content = world_tri(self.world)
	arena   = tri.arena_new()
	claim   = tri.value(content, ev.detail, arena, nil, 0)
	if claim == nil || tri.subtype(content, tri.node_type(claim), tri.type_named(content, "#IsIn")) == 0 ||
	   !know_node_int(content, claim, "within.place.x", &x) || !know_node_int(content, claim, "within.place.y", &y) ||
	   !know_node_int(content, claim, "within.place.level", &level) {
		tri.arena_free(arena)
		return
	}
	kind  = tri.type_name(content, tri.node_type(tri.at(content, claim, "what")))
	ckind = tri.type_name(content, tri.node_type(tri.at(content, claim, "within")))
	if tri.at(content, claim, "attribution") != nil &&
	   tri.subtype(content, tri.node_type(tri.at(content, claim, "attribution")), tri.type_named(content, "#Pledged")) != 0 {
		tri.arena_free(arena)
		return      /* a promise, not a claim of what is */
	}
	tri.arena_free(arena)

	a = {}
	a.utterance  = ev.index
	a.speaker    = ev.actor
	a.origin     = ev.actor
	a.fabricated = true
	store        = knowledge_store_of(self, ev.actor)
	for i = 0; i < knowledge_store_count(store); i += 1 {
		r = knowledge_store_referent_at(store, i)
		c = knowledge_store_referent(store, r.container) if r.form == .In else nil
		if !r.present || r.kind == nil || string(r.kind) != string(kind) || c == nil || c.kind == nil || string(c.kind) != string(ckind) ||
		   c.form != .On_Tile || i64(c.x) != x || i64(c.y) != y || i64(c.level) != level {
			continue
		}
		a.fabricated = false
		if r.toldBy != 0 {
			t = knowledge_store_strongest_that(store, r.id, c.id)
			if t != nil {
				a.relayed = true
				a.parent  = t.utterance
				parent = knowledge_ancestry_of(self, t.utterance)
				if parent != nil {
					a.origin     = parent.origin
					a.fabricated = parent.fabricated
				}
			}
		}
		break
	}
	knowledge_add_ancestry(self, a)
}


/* A store's next forgetting, worked out again once it has passed. */
knowledge_forget_by_of :: proc(self: ^Knowledge, store: ^Knowledge_Store) -> i64 {
	j:    uint
	now:  i64
	when_: i64

	now = world_time(self.world).ms
	if store.forgetBy == -2 || (store.forgetBy != max(i64) && store.forgetBy <= now) {
		store.forgetBy = max(i64)
		for j = 0; j < knowledge_store_count(store); j += 1 {
			when_ = knowledge_store_forgetting_of(store, knowledge_store_referent_at(store, j).id)
			if when_ > now && when_ < store.forgetBy do store.forgetBy = when_
		}
		/* below full detail, on the cadence's beat */
		store.forgetBy = reality_beat(world_reality(self.world), Detail(world_detail_of(self.world, store.agent)), store.forgetBy)
	}
	return store.forgetBy
}


/* The store of an agent, if it has one; none is made. */
knowledge_existing_store_of :: proc(self: ^Knowledge, agent: Entity_ID) -> ^Knowledge_Store {
	store: ^Knowledge_Store
	lo:    uint
	hi:    uint
	i:     uint

	lo = 0
	hi = uint(len(self.stores))
	for lo < hi {
		i = (lo + hi) / 2
		if self.stores[i].agent < agent {
			lo = i + 1
		} else {
			hi = i
		}
	}
	if lo < uint(len(self.stores)) {
		store = self.stores[lo]
		if store.agent == agent do return store
	}
	return nil
}


@(private)
know_forget_by_now :: proc(context_: rawptr, agent: Entity_ID) -> i64 {
	self:  ^Knowledge
	store: ^Knowledge_Store

	self  = (^Knowledge)(context_)
	store = knowledge_existing_store_of(self, agent)
	if store == nil || world_detail_of(self.world, agent) == i32(Detail.Frozen) {
		return max(i64)                  /* frozen: it forgets when it rises */
	}
	return knowledge_forget_by_of(self, store)
}


@(private)
know_perceive_by_now :: proc(context_: rawptr, agent: Entity_ID) -> i64 {
	self:  ^Knowledge
	store: ^Knowledge_Store

	self  = (^Knowledge)(context_)
	store = knowledge_existing_store_of(self, agent)
	if store == nil || world_record(self.world, world_kind_named(self.world, "Agent"), agent) == nil ||
	   world_detail_of(self.world, agent) == i32(Detail.Frozen) {
		return max(i64)                  /* frozen: it looks when it rises */
	}
	return store.perceiveBy
}


/* The wakes, from the stores, when first wanted (a knowledge new, or
 * restored): an agent that hasn't perceived, or perceived in another
 * light, is due now. */
knowledge_wake :: proc(self: ^Knowledge) {
	store:     ^Knowledge_Store
	agents:    ^Store
	i:         uint
	daylight_: i32

	if self.woken do return
	self.woken         = true
	self.perceiveWakes = wakes_new()
	self.forgetWakes   = wakes_new()
	daylight_          = daylight(self.world, world_time(self.world).ms)
	self.boundaryDaylight = daylight_
	agents             = world_store_for_kind(self.world, world_kind_named(self.world, "Agent"))
	for i = 0; i < store_count(agents); i += 1 {
		store = knowledge_store_of(self, store_entity_at_index(agents, i))
		if store.perceivedAt < 0 || store.daylightSeen != daylight_ do store.perceiveBy = world_time(self.world).ms
		wakes_push(self.perceiveWakes, store.agent, store.perceiveBy)
		wakes_push(self.forgetWakes, store.agent, knowledge_forget_by_of(self, store))
	}
}


knowledge_next_forgetting :: proc(self: ^Knowledge) -> Time {
	next_: i64

	knowledge_wake(self)
	next_ = wakes_next(self.forgetWakes, know_forget_by_now, self)
	return TIME_NEVER if next_ == max(i64) else time_make(next_)
}


/* Marks the agents within `radius` of a tile (on the ground, or in what
 * stands there), as concerned. */
@(private)
know_mark_near :: proc(world: ^World, tile: Location, radius: i32, kagent: uint,
                       marked: ^[^]Entity_ID, n: ^uint, cap_: ^uint) {
	near:  [^]Entity_ID
	count: uint
	i:     uint

	count = world_things_near(world, tile, radius, &near)
	for i = 0; i < count; i += 1 {
		if world_record(world, kagent, near[i]) != nil {
			if n^ == cap_^ {
				old := cap_^
				cap_^ = cap_^ * 2 if cap_^ != 0 else 64
				marked^ = ([^]Entity_ID)(realloc(marked^, old * size_of(Entity_ID), cap_^ * size_of(Entity_ID)))
			}
			marked^[n^] = near[i]
			n^ += 1
		}
	}
	free(near)
}


@(private)
know_mark :: proc(e: Entity_ID, marked: ^[^]Entity_ID, n: ^uint, cap_: ^uint) {
	if e == 0 do return
	if n^ == cap_^ {
		old := cap_^
		cap_^ = cap_^ * 2 if cap_^ != 0 else 64
		marked^ = ([^]Entity_ID)(realloc(marked^, old * size_of(Entity_ID), cap_^ * size_of(Entity_ID)))
	}
	marked^[n^] = e
	n^ += 1
}


// The qsort comparator, as slice.sort_by's "less".
@(private)
know_cmp_entity_id :: proc(x, y: Entity_ID) -> bool {
	return x < y
}


/* The agents this boundary concerns (REALITY.md decision 7): those that
 * changed, or took part in an event; those within their senses of what
 * changed, or of where an event was; those whose air changed. Sorted, maybe
 * twice. */
knowledge_concerned_from :: proc(self: ^Knowledge, first: uint, last: uint, count: ^uint) -> [^]Entity_ID {
	nearby:   [^]Entity_ID
	nnear:    uint
	nearcap:  uint

	ev:       ^Event
	activity: ^Activity
	trace:    ^Trace
	marked:   [^]Entity_ID
	gas:      [^]Entity_ID
	agents:   ^Store
	tile:     Location
	kagent:   uint
	kgas:     uint
	ngas:     uint
	n:        uint
	cap_:     uint
	i:        uint
	k:        uint
	radius:   i32

	kagent  = world_kind_named(self.world, "Agent")
	kgas    = world_kind_named(self.world, "GasStore")
	marked  = nil
	n       = 0
	cap_    = 0
	nearby  = nil
	nnear   = 0
	nearcap = 0
	gas     = make([^]Entity_ID, self.ntouched + 1)
	ngas    = 0
	for i = 0; i < self.ntouched; i += 1 {
		e: Entity_ID

		e = self.touched[i]
		if world_record(self.world, kagent, e) != nil do know_mark(e, &marked, &n, &cap_)
		activity = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), e))
		if activity != nil do know_mark(Entity_ID(activity.actorRef), &marked, &n, &cap_)
		if world_record(self.world, kgas, e) != nil {
			gas[ngas] = e
			ngas += 1
		}
		radius = BG_SIGHT + 1
		trace = (^Trace)(world_record(self.world, world_kind_named(self.world, "Trace"), e))
		if trace != nil {
			radius = BG_SOUND_REACH
			unplaced := !know_ground_tile(self.world, Entity_ID(trace.bearer), &tile) if trace.bearer != 0 else false
			if unplaced do continue
			if trace.bearer == 0 do tile = on_tile(i32(trace.tileX), i32(trace.tileY), i32(trace.tileLevel))
		} else if !know_ground_tile(self.world, e, &tile) {
			continue
		}
		if world_record(self.world, world_kind_named(self.world, "Lamp"), e) != nil {
			radius = BG_SIGHT + 11          /* a lamp lights its reach, ten at most */
		} else if world_record(self.world, world_kind_named(self.world, "Door"), e) != nil {
			radius = BG_SIGHT + 16          /* a door shades the room behind it */
		}
		know_mark_near(self.world, tile, radius, kagent, &nearby, &nnear, &nearcap)
	}
	for i = first; i < last; i += 1 {
		ev = world_event_at(self.world, i)
		know_mark(ev.subject if world_record(self.world, kagent, ev.subject) != nil else NO_ENTITY, &marked, &n, &cap_)
		know_mark(ev.other if world_record(self.world, kagent, ev.other) != nil else NO_ENTITY, &marked, &n, &cap_)
		know_mark(ev.actor if world_record(self.world, kagent, ev.actor) != nil else NO_ENTITY, &marked, &n, &cap_)
		if ev.location.form == .On_Tile do know_mark_near(self.world, ev.location, BG_SIGHT + 1, kagent, &nearby, &nnear, &nearcap)
		if ev.subject != 0 && know_ground_tile(self.world, ev.subject, &tile) {
			know_mark_near(self.world, tile, BG_SIGHT + 1, kagent, &nearby, &nnear, &nearcap)
		}
		if ev.actor != 0 && ev.actor != ev.subject && know_ground_tile(self.world, ev.actor, &tile) {
			know_mark_near(self.world, tile, BG_SIGHT + 1, kagent, &nearby, &nnear, &nearcap)
		}
		/* terrain changed: whoever saw the tile, however far, recalls what was
		 * there (TERRAIN.md decision 7) */
		if string(ev.kind) == "terrain" && ev.location.form == .On_Tile {
			for k = 0; k < uint(len(self.stores)); k += 1 {
				if knowledge_store_has_seen_x(self.stores[k], ev.location.x, ev.location.y, ev.location.level) {
					know_mark(knowledge_store_agent(self.stores[k]), &marked, &n, &cap_)
				}
			}
		}
	}
	/* where things were: who saw them there sees them gone */
	{
		vacated:  [^]Location
		nvacated: uint

		vacated = world_take_vacated(self.world, &nvacated)
		for i = 0; i < nvacated; i += 1 {
			know_mark_near(self.world, vacated[i], BG_SIGHT + 1, kagent, &nearby, &nnear, &nearcap)
		}
		free(vacated)
	}
	/* the air they breathe */
	if ngas != 0 {
		agents = world_store_for_kind(self.world, kagent)
		for i = 0; i < store_count(agents); i += 1 {
			// bsearch: the touched are in entity order, and so are these
			if _, found := slice.binary_search(gas[:ngas], air_over(self.world, store_entity_at_index(agents, i))); found {
				know_mark(store_entity_at_index(agents, i), &marked, &n, &cap_)
			}
		}
	}
	free(gas)
	/* nearby, not party to it: those whose senses reach only what they take
	 * part in (below full detail, REALITY.md step 3) don't attend */
	for i = 0; i < nnear; i += 1 {
		if !reality_own_senses_at(world_reality(self.world), Detail(world_detail_of(self.world, nearby[i]))) {
			know_mark(nearby[i], &marked, &n, &cap_)
		}
	}
	free(nearby)
	if n != 0 do slice.sort_by(marked[:n], know_cmp_entity_id)
	count^ = n
	return marked
}


/* The hunger an agent feels at t, to its band (as perception has it). */
knowledge_hunger_of :: proc(self: ^Knowledge, agent: Entity_ID, memory: ^Agent, t: i64) -> i64 {
	band:   i64
	hunger: i64

	band   = 2 * BG_HUNGER_BAND if memory.fatigue >= 80 else BG_HUNGER_BAND
	hunger = 100 - satiety(hungry_of(self.world, agent), t) - 2 * i64(knowledge_attention_of(self, agent))
	return 0 if hunger < 0 else (hunger / band) * band
}


/* When a store perceives again with nothing happening (REALITY.md decision
 * 7): what it believes fading past belief; a promise falling due; its
 * hunger reaching its next band; a trace it knows of fading past what it
 * notices. */
knowledge_perceive_by_of :: proc(self: ^Knowledge, store: ^Knowledge_Store) -> i64 {
	t:      ^Trace_Seen
	trace:  ^Trace
	pledge: ^Testimony
	r:      ^Referent
	memory: ^Agent
	i:      uint
	by:     i64
	gone:   i64
	now:    i64
	lo:     i64
	hi:     i64
	mid:    i64
	felt:   i64

	now = world_time(self.world).ms
	by  = max(i64)
	for i = 0; i < knowledge_store_count(store); i += 1 {
		r = knowledge_store_referent_at(store, i)
		if !r.present || r.id == knowledge_store_self_referent(store) do continue
		gone = knowledge_store_forgetting_of(store, r.id)
		if gone > now && gone < by do by = gone
	}
	for i = 0; i < knowledge_store_testimony_count(store); i += 1 {
		pledge = knowledge_store_testimony_at(store, i)
		if pledge.settled == 0 && pledge.attribution == .Pledged && pledge.when_ > now && pledge.when_ < by do by = pledge.when_
	}
	/* hunger rises with time alone: the first moment, within a day, its band
	 * changes, found by halving (it only rises) */
	memory = (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), knowledge_store_agent(store)))
	if memory != nil {
		felt = knowledge_hunger_of(self, knowledge_store_agent(store), memory, now)
		lo   = now
		hi   = now + 86400000          /* a day */
		if knowledge_hunger_of(self, knowledge_store_agent(store), memory, hi) == felt {
			mid = hi
		} else {
			for hi - lo > 1 {
				mid = lo + (hi - lo) / 2
				if knowledge_hunger_of(self, knowledge_store_agent(store), memory, mid) == felt {
					lo = mid
				} else {
					hi = mid
				}
			}
			mid = hi
		}
		if mid < by do by = mid
	}
	for i = 0; i < knowledge_store_trace_count(store); i += 1 {
		t = knowledge_store_trace_at(store, i)
		if !t.present || t.truth == 0 do continue
		trace = (^Trace)(world_record(self.world, world_kind_named(self.world, "Trace"), t.truth))
		if trace == nil do continue
		gone = trace_gone(self.world, trace)
		if gone > world_time(self.world).ms && gone < by do by = gone
	}
	return by
}


knowledge_perceive_boundary :: proc(self: ^Knowledge, boundary: u64) {
	ev:         ^Event
	store:      ^Knowledge_Store
	agents:     ^Store
	concerned:  [^]Entity_ID
	woken:      [^]Entity_ID
	risen:      [^]Entity_ID
	nrisen:     uint
	due:        [^]Entity_ID
	agent:      Entity_ID
	nconcerned: uint
	nwoken:     uint
	ndue:       uint
	i:          uint
	last:       uint
	now:        i64
	daylight_:  i32

	last = world_event_count(self.world)
	/* claims said, traced first, by what their speakers knew when they spoke */
	for i = self.eventsSeen; i < last; i += 1 {
		ev = world_event_at(self.world, i)
		if string(ev.kind) == "said" && ev.actor != 0 && ev.detail != nil do knowledge_trace(self, ev)
	}
	free(self.touched)
	self.touched = world_take_touched(self.world, &self.ntouched)
	/* what changed looks as it may not have */
	for i = 0; self.features != nil && i < self.ntouched; i += 1 {
		_, was := delete_key(&self.features, self.touched[i] * 2)
		delete(was)
		_, was1 := delete_key(&self.features, self.touched[i] * 2 + 1)
		delete(was1)
	}
	concerned = knowledge_concerned_from(self, self.eventsSeen, last, &nconcerned)
	now       = world_time(self.world).ms
	daylight_ = daylight(self.world, now)
	agents    = world_store_for_kind(self.world, world_kind_named(self.world, "Agent"))

	/* who perceives (REALITY.md decision 7): those concerned; those whose
	 * wake falls due; those new to it; and everyone, as the daylight turns,
	 * or to an omniscient eye. Else they rest, and no one reads them */
	knowledge_wake(self)
	woken = wakes_take(self.perceiveWakes, now, know_perceive_by_now, self, &nwoken)
	/* risen from frozen: they look at once (REALITY.md step 4) */
	risen = world_take_risen(self.world, &nrisen)
	{
		// realloc: woken's own size isn't known here, so a new block
		grown := make([^]Entity_ID, nwoken + nrisen + 1)
		mem.copy(grown, woken, int(nwoken * size_of(Entity_ID)))
		free(woken)
		woken = grown
	}
	mem.copy(woken[nwoken:], risen, int(nrisen * size_of(Entity_ID)))
	nwoken += nrisen
	free(risen)
	if self.omniscient || daylight_ != self.boundaryDaylight {
		ndue = store_count(agents)
		due  = make([^]Entity_ID, ndue + 1)
		for i = 0; i < ndue; i += 1 do due[i] = store_entity_at_index(agents, i)
	} else {
		due = make([^]Entity_ID, nconcerned + nwoken + 1)
		if nconcerned != 0 do mem.copy(due, concerned, int(nconcerned * size_of(Entity_ID)))
		if nwoken != 0 do mem.copy(due[nconcerned:], woken, int(nwoken * size_of(Entity_ID)))
		ndue = nconcerned + nwoken
		slice.sort_by(due[:ndue], know_cmp_entity_id)
	}
	self.boundaryDaylight = daylight_
	free(woken)
	free(concerned)

	/* in stable ID order; each depends only on the world and its own store */
	free(self.perceived)
	self.perceived  = make([^]Entity_ID, ndue + 1)
	self.nperceived = 0
	for i = 0; i < ndue; i += 1 {
		agent = due[i]
		if (i != 0 && agent == due[i - 1]) || world_record(self.world, world_kind_named(self.world, "Agent"), agent) == nil ||
		   world_detail_of(self.world, agent) == i32(Detail.Frozen) {
			continue                         /* frozen: nothing runs */
		}
		store      = knowledge_store_of(self, agent)
		self.short = false
		knowledge_perceive(self, store, self.eventsSeen, last)
		store.perceivedAt  = now
		store.daylightSeen = daylight_
		/* short of attention, or it learnt something: it looks again next
		 * boundary, what it learnt checked against what it sees (told that
		 * Kasimir has the purse, it sees whether he does) */
		store.perceiveBy   = reality_beat(world_reality(self.world), Detail(world_detail_of(self.world, agent)),
		                                  now + 1 if self.short || len(knowledge_store_news(store)) != 0 else knowledge_perceive_by_of(self, store))
		store.forgetBy     = -2
		wakes_push(self.perceiveWakes, agent, store.perceiveBy)
		wakes_push(self.forgetWakes, agent, knowledge_forget_by_of(self, store))
		self.perceived[self.nperceived] = agent
		self.nperceived += 1
		/* housekeeping: the knowledge arena, compacted when half garbage */
		knowledge_store_compact(store, self.compactAlways)
	}
	free(due)
	/* a test's: compaction changes nothing, at every boundary */
	for i = 0; self.compactAlways && i < uint(len(self.stores)); i += 1 do knowledge_store_compact(self.stores[i], true)
	self.eventsSeen = last
}


// The agents that perceived at this boundary: n^ of them.
knowledge_agents_perceived_now :: proc(self: ^Knowledge, n: ^uint) -> [^]Entity_ID {
	n^ = self.nperceived
	return self.perceived
}


/* What an entity looks like, by its records: kept until it changes (what
 * changed is let go of at each boundary), so a crowd looked at again and
 * again is read once. */
// The features kept are cloned into the context allocator, and let go of
// (deleted) when the entity changes; dealloc deletes those left.
knowledge_features_of :: proc(self: ^Knowledge, entity: Entity_ID, view: ^View) -> string {
	key:      u64
	features: string

	key = entity * 2 + (1 if self.omniscient else 0)
	if kept, ok := self.features[key]; ok do return kept
	features = strings.clone(view_features_of_all(view, entity, self.omniscient))
	self.features[key] = features
	return features
}


knowledge_perceived_now :: proc(self: ^Knowledge, agent: Entity_ID) -> bool {
	store: ^Knowledge_Store

	store = knowledge_store_of(self, agent)
	return store != nil && store.perceivedAt == world_time(self.world).ms
}


knowledge_touched_now :: proc(self: ^Knowledge, entity: Entity_ID) -> bool {
	if self.touched == nil do return false
	_, found := slice.binary_search(self.touched[:self.ntouched], entity)
	return found
}


/* --- the developer's view ---------------------------------------------------------- */

@(private)
know_attribution_text :: proc(t: ^Testimony) -> string {
	#partial switch t.attribution {
	case .Heard_From: return fmt.tprintf("heard from R%d", t.root)
	case .Heard:      return "heard"
	case .Pledged:    return "promised"
	case:             return "saw"
	}
}


/* What it was told, claim by claim: credence, each item's group and weight,
 * and, for the developer, where each truly came from; groups the agent
 * counts apart that share a true root are false corroboration. */
knowledge_dump_testimony :: proc(self: ^Knowledge, store: ^Knowledge_Store) -> string {
	t: ^Testimony
	u: ^Testimony
	a: ^Ancestry
	b: ^Ancestry
	s: strings.Builder
	i: uint
	j: uint
	k: uint

	s = strings.builder_make(context.temp_allocator)
	for i = 0; i < knowledge_store_testimony_count(store); i += 1 {
		t = knowledge_store_testimony_at(store, i)
		for j = 0; j < i; j += 1 {
			if knowledge_store_testimony_at(store, j).thing == t.thing && knowledge_store_testimony_at(store, j).container == t.container do break
		}
		if j < i do continue      /* the claim is shown already */
		fmt.sbprintf(&s, "  claim R%d in R%d: credence %+d dB\n", t.thing, t.container,
		             knowledge_store_credence_that(store, t.thing, t.container))
		for j = i; j < knowledge_store_testimony_count(store); j += 1 {
			u = knowledge_store_testimony_at(store, j)
			if u.thing != t.thing || u.container != t.container do continue
			a = knowledge_root_of(self, u.utterance)
			truly := "untraced" if a == nil else fmt.tprintf("%s by %d", "made up" if a.fabricated else "seen", a.origin)
			fmt.sbprintf(&s, "    R%d %s at %dms, as of %dms: %s, %s, weight %+d dB%s; truly %s\n", u.source,
			             fmt.tprintf("wrote so in R%d, read", u.via) if u.via != 0 else "said so",
			             u.heard, u.when_, know_attribution_text(u),
			             fmt.tprintf("root R%d", u.root) if u.root != 0 else "root unknown",
			             knowledge_store_weight_of(store, u), ", seen true" if u.settled > 0 else (", found false" if u.settled < 0 else ""),
			             truly)
			/* false corroboration: a later item counted apart, from the same true root */
			for k = j + 1; k < knowledge_store_testimony_count(store); k += 1 {
				v: ^Testimony

				v = knowledge_store_testimony_at(store, k)
				if v.thing != t.thing || v.container != t.container || u.settled < 0 || v.settled < 0 ||
				   (u.root != 0 && u.root == v.root) {
					continue
				}
				b = knowledge_root_of(self, v.utterance)
				if a != nil && b != nil && a.origin == b.origin && a.fabricated == b.fabricated {
					fmt.sbprintf(&s, "    false corroboration: R%d and R%d are counted apart, and both come from %d\n",
					             u.source, v.source, a.origin)
				}
			}
		}
	}
	return strings.to_string(s)
}


knowledge_dump :: proc(self: ^Knowledge, agent: Entity_ID) -> string {
	store: ^Knowledge_Store
	r:     ^Referent
	o:     ^Observation
	s:     strings.Builder
	i:     uint
	j:     uint

	store = knowledge_store_of(self, agent)
	s     = strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&s, "what %d knows (self R%d):\n", agent, knowledge_store_self_referent(store))
	for i = 0; i < knowledge_store_count(store); i += 1 {
		r = knowledge_store_referent_at(store, i)
		inside := fmt.tprintf(", inside seen at %dms", r.insideSeen) if r.insideSeen >= 0 else ""
		trust := ""
		if r.kind != nil && string(r.kind) == "#Agent" && r.id != knowledge_store_self_referent(store) {
			trust = fmt.tprintf(", trust %+d dB%s", knowledge_store_trust_in(store, r.id),
			                    fmt.tprintf(", loyalty %d", r.loyalty) if r.loyalty != 0 else "")
		}
		fmt.sbprintf(&s, "  R%d %s, seen at %dms%s, truth %d%s%s%s: %s\n", r.id, nul_s(r.kind), r.seen,
		             "" if r.present else ", not there any more", r.truth,
		             inside,
		             fmt.tprintf(", told by R%d", r.toldBy) if r.toldBy != 0 else "",
		             trust,
		             knowledge_store_describe_referent(store, r.id))
		for j = 0; j < BG_HYPOTHESES && r.supposed[j] != nil; j += 1 {
			fmt.sbprintf(&s, "    or, %d in 1000: %s\n", r.supposedMass[j], r.supposed[j])
		}
	}
	for i = 0; i < knowledge_store_trace_count(store); i += 1 {
		t: ^Trace_Seen

		t = knowledge_store_trace_at(store, i)
		fmt.sbprintf(&s, "  trace %s %s, strength %d, at %dms%s, truth %d\n", t.kind,
		             fmt.tprintf("on R%d", t.bearer) if t.bearer != 0 else fmt.tprintf("at (%d, %d)", t.x, t.y),
		             t.strength, t.seen, "" if t.present else ", gone", t.truth)
	}
	if knowledge_store_felt_at(store) >= 0 {
		fmt.sbprintf(&s, "  feels hunger %d, cold %d, short of breath %d, tired %d, pain %d, at %dms\n",
		             knowledge_store_feels(store, "hunger"), knowledge_store_feels(store, "cold"), knowledge_store_feels(store, "stuffy"),
		             knowledge_store_feels(store, "tired"), knowledge_store_feels(store, "pain"), knowledge_store_felt_at(store))
	}
	for i = 0; i < knowledge_store_finding_count(store); i += 1 {
		f: ^Finding

		f = knowledge_store_finding_at(store, i)
		fmt.sbprintf(&s, "  finding %s about R%d%s, %+d dB, by %s at %dms\n", f.kind, f.about,
		             fmt.tprintf(", choosing R%d", f.choice) if f.choice != 0 else "", f.credence, f.rule,
		             f.time)
	}
	for i = 0; i < knowledge_store_identity_count(store); i += 1 {
		h:  ^Identity
		ta: Entity_ID
		tb: Entity_ID

		h  = knowledge_store_identity_at(store, i)
		ta = knowledge_store_referent(store, h.a).truth if knowledge_store_referent(store, h.a) != nil else 0
		tb = knowledge_store_referent(store, h.b).truth if knowledge_store_referent(store, h.b) != nil else 0
		fmt.sbprintf(&s, "  identity R%d may be R%d: %+d dB, differing in %s; truly %s%s\n", h.a, h.b, h.credence,
		             cstring(&h.paths[0]), "unknown" if ta == 0 || tb == 0 else "the same" if ta == tb else "not",
		             ": false merge" if ta != 0 && tb != 0 && ta != tb && h.credence >= 0 else "")
	}
	strings.write_string(&s, knowledge_dump_testimony(self, store))
	for i = 0; i < knowledge_store_observation_count(store); i += 1 {
		o = knowledge_store_observation_at(store, i)
		fmt.sbprintf(&s, "  at %dms, salience %d: R%d %s R%d%s%s%s\n", o.time, o.salience, o.actor, o.kind,
		             o.other if string(o.kind) == "said" else o.subject,
		             fmt.tprintf(" to R%d", o.other) if string(o.kind) == "moved" && o.other != 0 else "",
		             fmt.tprintf(": %s", o.content) if o.content != nil else "",
		             " (not believed)" if o.unbelieved else "")
	}
	return strings.to_string(s)
}


/* --- saves --------------------------------------------------------------------------- */

// BGSplitTopLevel: the parts, in the temporary allocator.
split_top_level :: proc(text: string) -> []string {
	parts:  [dynamic]string
	p:      int
	start:  int
	depth:  i32
	quoted: bool

	// a C string's bytes: up to its NUL, or the end
	at :: proc(s: string, i: int) -> u8 {
		return s[i] if i < len(s) else 0
	}

	parts  = make([dynamic]string, context.temp_allocator)
	depth  = 0
	quoted = false
	start = 0
	for p = 0; ; p += 1 {
		if at(text, p) == '"' && (p == 0 || at(text, p - 1) != '\\') do quoted = !quoted
		if quoted && at(text, p) != 0 do continue
		if at(text, p) == '{' || at(text, p) == '[' || at(text, p) == '(' {
			depth += 1
		} else if (at(text, p) == '}' || at(text, p) == ']' || at(text, p) == ')') && depth > 0 {
			depth -= 1
		} else if (at(text, p) == ',' && depth == 0) || at(text, p) == 0 {
			end: int

			for start < p && at(text, start) == ' ' do start += 1
			for end = p; end > start && at(text, end - 1) == ' '; end -= 1 {}
			append(&parts, strings.clone(text[start:end], context.temp_allocator))
			start = p + 1
		}
		if at(text, p) == 0 do break
	}
	return parts[:]
}


// BGWritingEntries: the entries, in the temporary allocator, and true; nil
// and false if it isn't writing. author^ is set to the author, when it says.
writing_entries :: proc(writing: cstring, author: ^string) -> ([]string, bool) #optional_ok {
	text:  string
	pair:  string
	list:  string
	pairs: []string
	open:  uint
	i:     uint

	text = string(writing) if writing != nil else ""
	if !ns_has_prefix(text, "#Writing & {") || !ns_has_suffix(text, "}") do return nil, false
	open  = ns_range_of(text, "{")
	pairs = split_top_level(text[open + 1:][:uint(len(text)) - open - 2])
	list  = ""
	for i = 0; i < uint(len(pairs)); i += 1 {
		pair = pairs[i]
		if ns_has_prefix(pair, "author: ") && author != nil do author^ = pair[8:]
		if ns_has_prefix(pair, "entries: [") && ns_has_suffix(pair, "]") do list = pair[10:][:len(pair) - 11]
	}
	if len(list) == 0 do return make([]string, 0, context.temp_allocator), true
	return split_top_level(list), true
}


// BGEncodeWord: in the temporary allocator.
encode_word :: proc(s: cstring) -> string {
	out: strings.Builder
	p:   [^]u8

	out = strings.builder_make(context.temp_allocator)
	for p = ([^]u8)(s); p != nil && p[0] != 0; p = p[1:] {
		if p[0] == ' ' || p[0] == '%' || p[0] == '\n' {
			fmt.sbprintf(&out, "%%%02x", p[0])
		} else {
			strings.write_byte(&out, p[0])
		}
	}
	if strings.builder_len(out) == 0 do strings.write_string(&out, "%")
	return strings.to_string(out)
}


// BGDecodeWord: malloc'd (the context allocator); the caller frees it with
// delete.
decode_word :: proc(s: cstring) -> cstring {
	out: [^]u8
	w:   int
	c:   u32
	p:   [^]u8

	out = make([^]u8, len(s) + 1)
	w   = 0
	p   = ([^]u8)(s)
	empty: cstring = ""
	if s == "%" do p = ([^]u8)(empty)
	for p[0] != 0 {
		if p[0] == '%' && p[1] != 0 && p[2] != 0 && libc.sscanf(cstring(&p[1]), "%2x", &c) == 1 {
			out[w] = u8(c)
			w += 1
			p = p[3:]
			continue
		}
		out[w] = p[0]
		w += 1
		p = p[1:]
	}
	out[w] = 0
	return cstring(out)
}


knowledge_check_in_all :: proc(self: ^Knowledge) {
}


// The lines, in the temporary allocator.
knowledge_saved_state :: proc(self: ^Knowledge) -> []string {
	store: ^Knowledge_Store
	o:     ^Observation
	r:     ^Referent
	t:     ^Testimony
	lines: [dynamic]string
	i:     uint
	j:     uint
	k:     uint

	lines = make([dynamic]string, context.temp_allocator)
	for i = 0; i < uint(len(self.stores)); i += 1 {
		store = self.stores[i]
		append(&lines, fmt.tprintf("store %d %d %d %d", knowledge_store_agent(store),
		                           knowledge_store_next_id(store), knowledge_store_self_referent(store),
		                           knowledge_store_next_serial(store)))
		/* when it perceives: last, and next with nothing happening */
		append(&lines, fmt.tprintf("perceives %d %d %d %d", knowledge_store_agent(store),
		                           store.perceivedAt, store.perceiveBy,
		                           store.daylightSeen))
		/* the terrain seen: a chunk a line, its bits in hex; then what it recalls */
		{
			chunks:  [^]Seen_Chunk
			bits:    strings.Builder
			nchunks: uint
			c:       uint
			w:       uint

			nchunks = knowledge_store_seen_chunks(store, &chunks)
			for c = 0; c < nchunks; c += 1 {
				bits = strings.builder_make(context.temp_allocator)
				for w = 0; w < BG_CHUNK * BG_CHUNK / 32; w += 1 do fmt.sbprintf(&bits, "%08x", chunks[c].bits[w])
				append(&lines, fmt.tprintf("seenchunk %d %d %d %d %d %s", knowledge_store_agent(store),
				                           chunks[c].cx, chunks[c].cy, chunks[c].z, chunks[c].seen,
				                           strings.to_string(bits)))
			}
			free(chunks)
			for c = 0; c < knowledge_store_recall_count(store); c += 1 {
				append(&lines, fmt.tprintf("recall %d %d %d %d %s", knowledge_store_agent(store),
				                           knowledge_store_recall_at(store, c).x, knowledge_store_recall_at(store, c).y, knowledge_store_recall_at(store, c).z,
				                           terrain_kind_info(world_terrain(self.world), knowledge_store_recall_at(store, c).kind).name))
			}
		}
		for j = 0; j < knowledge_store_count(store); j += 1 {
			r = knowledge_store_referent_at(store, j)
			append(&lines, fmt.tprintf("ref %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %s %s %s %s",
			                           knowledge_store_agent(store), r.id, i32(r.form),
			                           r.container, r.x, r.y, r.level, r.slot, r.seen, r.first,
			                           r.insideSeen, r.toldBy, r.trust, r.loyalty, 1 if r.present else (2 if r.ended else 0),
			                           r.truth,
			                           encode_word(cstring(&r.role[0])), encode_word(r.kind), encode_word(r.features),
			                           encode_word(r.deeper)))
		}
		for j = 0; j < knowledge_store_observation_count(store); j += 1 {
			o = knowledge_store_observation_at(store, j)
			append(&lines, fmt.tprintf("obs %d %d %s %d %d %d %d %d %d %s",
			                           knowledge_store_agent(store),
			                           o.time, o.kind, o.actor, o.subject, o.other,
			                           1 if o.unbelieved else 0, o.salience, o.serial,
			                           encode_word(o.content)))
		}
		for j = 0; j < knowledge_store_trace_count(store); j += 1 {
			tr: ^Trace_Seen

			tr = knowledge_store_trace_at(store, j)
			append(&lines, fmt.tprintf("tracing %d %d %d %d %d %d %d %d %d %s",
			                           knowledge_store_agent(store), tr.bearer, tr.x, tr.y,
			                           tr.level, tr.strength, tr.seen, 1 if tr.present else 0,
			                           tr.truth, tr.kind))
		}
		if knowledge_store_felt_at(store) >= 0 {
			append(&lines, fmt.tprintf("feels %d %d %d %d %d %d %d", knowledge_store_agent(store),
			                           knowledge_store_feels(store, "hunger"), knowledge_store_felt_at(store),
			                           knowledge_store_feels(store, "cold"), knowledge_store_feels(store, "stuffy"), knowledge_store_feels(store, "tired"),
			                           knowledge_store_feels(store, "pain")))
		}
		for j = 0; j < knowledge_store_recipe_count(store); j += 1 {
			append(&lines, fmt.tprintf("recipe %d %s", knowledge_store_agent(store),
			                           knowledge_store_recipe_at(store, j)))
		}
		for j = 0; j < knowledge_store_law_count(store); j += 1 {
			append(&lines, fmt.tprintf("law %d %d %s %s %s", knowledge_store_agent(store),
			                           knowledge_store_law_at(store, j).weighs,
			                           encode_word(knowledge_store_law_at(store, j).forbids),
			                           encode_word(knowledge_store_law_at(store, j).wrong),
			                           encode_word(knowledge_store_law_at(store, j).brings)))
		}
		for j = 0; j < knowledge_store_count(store); j += 1 {
			if knowledge_store_referent_at(store, j).sightings != 0 || knowledge_store_referent_at(store, j).salience != 0 {
				append(&lines, fmt.tprintf("remembers %d %d %d %d", knowledge_store_agent(store),
				                           knowledge_store_referent_at(store, j).id, knowledge_store_referent_at(store, j).sightings,
				                           knowledge_store_referent_at(store, j).salience))
			}
		}
		for j = 0; j < knowledge_store_count(store); j += 1 {
			for k = 0; k < BG_HYPOTHESES && knowledge_store_referent_at(store, j).supposed[k] != nil; k += 1 {
				append(&lines, fmt.tprintf("supposes %d %d %d %s", knowledge_store_agent(store),
				                           knowledge_store_referent_at(store, j).id, knowledge_store_referent_at(store, j).supposedMass[k],
				                           encode_word(knowledge_store_referent_at(store, j).supposed[k])))
			}
		}
		for j = 0; j < knowledge_store_identity_count(store); j += 1 {
			h: ^Identity

			h = knowledge_store_identity_at(store, j)
			append(&lines, fmt.tprintf("identity %d %d %d %d %d %s", knowledge_store_agent(store),
			                           h.a, h.b, h.credence, h.time, encode_word(cstring(&h.paths[0]))))
		}
		for j = 0; j < knowledge_store_finding_count(store); j += 1 {
			f: ^Finding

			f = knowledge_store_finding_at(store, j)
			append(&lines, fmt.tprintf("finding %d %d %d %d %s %s %d", knowledge_store_agent(store),
			                           f.about, f.credence, f.time, f.kind, f.rule, f.choice))
		}
		for p in store.prices {
			append(&lines, fmt.tprintf("price %d %d %d %d %d %s", knowledge_store_agent(store),
			                           p.seller, p.board, p.coins, p.time, encode_word(p.unit)))
		}
		for j = 0; j < knowledge_store_testimony_count(store); j += 1 {
			t = knowledge_store_testimony_at(store, j)
			append(&lines, fmt.tprintf("told %d %d %d %d %d %d %d %d %d %d %d %d",
			                           knowledge_store_agent(store), t.thing, t.container,
			                           t.when_, t.heard, t.source, t.root,
			                           i32(t.attribution), t.settled, t.sure,
			                           t.utterance, t.via))
		}
	}
	for j = 0; j < self.nancestry; j += 1 {
		append(&lines, fmt.tprintf("ancestry %d %d %d %d %d %d",
		                           self.ancestry[j].utterance,
		                           self.ancestry[j].speaker,
		                           self.ancestry[j].origin,
		                           self.ancestry[j].parent,
		                           1 if self.ancestry[j].relayed else 0, 1 if self.ancestry[j].fabricated else 0))
	}
	return lines[:]
}


// The lines are read as the Objective-C read them, with C's sscanf.
knowledge_restore_saved_state :: proc(self: ^Knowledge, lines: []string) {
	store:       ^Knowledge_Store
	restoring:   ^Knowledge_Store
	perceivedAt: i64
	perceiveBy:  i64
	daylight_:   i32
	r:           ^Referent
	agent:       u64
	truth:       u64
	seen:        i64
	inside:      i64
	first:       i64
	told:        u32
	origin:      u64
	parent:      u64
	cold:        i32
	stuffy:      i32
	tired:       i32
	pain:        i32
	trust:       i32
	t:           Testimony
	a:           Ancestry
	o:           Observation
	id:          u32
	next_:       u32
	me:          u32
	container:   u32
	form:        i32
	x:           i32
	y:           i32
	level:       i32
	slot:        i32
	present:     i32
	loyal:       i32
	role:        [64]u8
	kind:        [512]u8
	features:    [4096]u8
	deeper:      [512]u8
	text:        cstring
	i:           uint

	for s in self.stores do release(s)
	clear(&self.stores)
	self.nancestry = 0
	for i = 0; i < uint(len(lines)); i += 1 {
		text = ns_utf8(lines[i])
		if libc.sscanf(text, "store %llu %u %u %llu", &agent, &next_, &me, &parent) == 4 {
			knowledge_store_set_next_id(knowledge_store_of(self, Entity_ID(agent)), next_, me)
			knowledge_store_set_next_serial(knowledge_store_of(self, Entity_ID(agent)), parent)
		} else if libc.sscanf(text, "perceives %llu %lld %lld %d", &agent, &perceivedAt, &perceiveBy, &daylight_) == 4 {
			restoring = knowledge_store_of(self, Entity_ID(agent))
			restoring.perceivedAt  = perceivedAt
			restoring.perceiveBy   = perceiveBy
			restoring.daylightSeen = daylight_
		} else if strings.has_prefix(lines[i], "seenchunk ") {
			chunk: Seen_Chunk
			hex:   [300]u8
			word:  [9]u8
			w:     uint
			cz:    i32

			chunk = {}
			if libc.sscanf(text, "seenchunk %llu %d %d %d %lld %299s", &agent, &chunk.cx, &chunk.cy, &cz, &seen, &hex[0]) == 6 &&
			   len(cstring(&hex[0])) == BG_CHUNK * BG_CHUNK / 4 {
				chunk.z    = cz
				chunk.seen = seen
				for w = 0; w < BG_CHUNK * BG_CHUNK / 32; w += 1 {
					mem.copy(&word[0], &hex[8 * w], 8)
					word[8]       = 0
					chunk.bits[w] = u32(libc.strtoul(cstring(&word[0]), nil, 16))
				}
				knowledge_store_restore_seen_chunk(knowledge_store_of(self, Entity_ID(agent)), &chunk)
			}
		} else if libc.sscanf(text, "recall %llu %d %d %d %511s", &agent, &x, &y, &level, &kind[0]) == 5 {
			s: ^Knowledge_Store
			k: Terrain_Kind

			s = knowledge_store_of(self, Entity_ID(agent))
			k = terrain_kind_named(world_terrain(self.world), cstring(&kind[0])) if world_terrain(self.world) != nil else 0
			if k != 0 do knowledge_store_miss_change_from(s, k, x, y, level)
		} else if libc.sscanf(text, "obs %llu %lld %15s %u %u %u %d %d %llu %4095s", &agent, &seen, &role[0], &id, &container,
		                      &told, &present, &trust, &origin, &features[0]) == 10 {
			o = {}
			o.time       = seen
			o.kind       = world_intern(self.world, cstring(&role[0]))
			o.actor      = id
			o.subject    = container
			o.other      = told
			o.unbelieved = present != 0
			o.salience   = trust
			o.serial     = origin
			o.content    = decode_word(cstring(&features[0]))
			if len(o.content) == 0 {
				delete(o.content)
				o.content = nil
			}
			knowledge_store_add_observation(knowledge_store_of(self, Entity_ID(agent)), o, true)
			delete(o.content)
		} else if libc.sscanf(text, "told %llu %u %u %lld %lld %u %u %d %d %d %llu %u", &agent, &id, &container, &seen, &inside,
		                      &told, &me, &form, &present, &trust, &truth, &next_) == 12 {
			t = {}
			t.thing       = id
			t.container   = container
			t.when_       = seen
			t.heard       = inside
			t.source      = told
			t.root        = me
			t.attribution = Attribution(form)
			t.settled     = present
			t.sure        = trust
			t.utterance   = truth
			t.via         = next_
			knowledge_store_append_testimony(knowledge_store_of(self, Entity_ID(agent)), t)
		} else if libc.sscanf(text, "tracing %llu %u %d %d %d %d %lld %d %llu %63s", &agent, &id, &x, &y, &level, &trust,
		                      &seen, &present, &truth, &role[0]) == 10 {
			tr: Trace_Seen

			tr = {}
			tr.bearer   = id
			tr.x        = x
			tr.y        = y
			tr.level    = level
			tr.strength = trust
			tr.seen     = seen
			tr.present  = present != 0
			tr.truth    = Entity_ID(truth)
			tr.kind     = world_intern(self.world, cstring(&role[0]))
			knowledge_store_note_trace(knowledge_store_of(self, Entity_ID(agent)), tr)
		} else if libc.sscanf(text, "recipe %llu %63s", &agent, &role[0]) == 2 {
			knowledge_store_learn_recipe(knowledge_store_of(self, Entity_ID(agent)), cstring(&role[0]))
		} else if libc.sscanf(text, "law %llu %d %511s %511s %4095s", &agent, &trust, &deeper[0], &kind[0], &features[0]) == 5 {
			k:       Known_Law
			forbids: cstring
			wrong:   cstring
			brings:  cstring

			forbids   = decode_word(cstring(&deeper[0]))
			wrong     = decode_word(cstring(&kind[0]))
			brings    = decode_word(cstring(&features[0]))
			k.forbids = world_intern(self.world, forbids)
			k.wrong   = world_intern(self.world, wrong)
			k.brings  = world_intern(self.world, brings)
			k.weighs  = trust
			knowledge_store_learn_law(knowledge_store_of(self, Entity_ID(agent)), k)
			delete(forbids)
			delete(wrong)
			delete(brings)
		} else if libc.sscanf(text, "remembers %llu %u %d %d", &agent, &id, &trust, &x) == 4 {
			m: ^Referent

			m = knowledge_store_mutable_referent(knowledge_store_of(self, Entity_ID(agent)), id)
			if m != nil {
				m.sightings = trust
				m.salience  = x
			}
		} else if libc.sscanf(text, "supposes %llu %u %d %511s", &agent, &id, &trust, &deeper[0]) == 4 {
			overrides: cstring

			overrides = decode_word(cstring(&deeper[0]))
			knowledge_store_suppose(knowledge_store_of(self, Entity_ID(agent)), string(overrides), id, trust)
			delete(overrides)
		} else if libc.sscanf(text, "identity %llu %u %u %d %lld %511s", &agent, &id, &container, &trust, &seen, &deeper[0]) == 6 {
			h:     Identity
			paths: cstring

			h = {}
			h.a        = id
			h.b        = container
			h.credence = trust
			h.time     = seen
			paths      = decode_word(cstring(&deeper[0]))
			strncpy(raw_data(h.paths[:]), ([^]u8)(paths), size_of(h.paths) - 1)
			delete(paths)
			knowledge_store_add_identity(knowledge_store_of(self, Entity_ID(agent)), h)
		} else if libc.sscanf(text, "feels %llu %d %lld %d %d %d %d", &agent, &trust, &seen, &cold, &stuffy, &tired, &pain) == 7 {
			knowledge_store_feel_pain(knowledge_store_of(self, Entity_ID(agent)), pain)
			knowledge_store_feel_tired(knowledge_store_of(self, Entity_ID(agent)), tired)
			knowledge_store_feel_hunger(knowledge_store_of(self, Entity_ID(agent)), trust, seen)
			knowledge_store_feel_cold(knowledge_store_of(self, Entity_ID(agent)), cold)
			knowledge_store_feel_stuffy(knowledge_store_of(self, Entity_ID(agent)), stuffy)
		} else if libc.sscanf(text, "price %llu %u %u %d %lld %63s", &agent, &id, &next_, &trust, &seen, &role[0]) == 6 {
			unit := decode_word(cstring(&role[0]))
			knowledge_store_learn_price(knowledge_store_of(self, Entity_ID(agent)),
			                            Known_Price{id, next_, world_intern(self.world, unit), trust, seen})
			delete(unit)
		} else if libc.sscanf(text, "finding %llu %u %d %lld %63s %511s %u", &agent, &id, &trust, &seen, &role[0], &kind[0], &next_) == 7 {
			f: Finding

			f = {}
			f.about    = id
			f.credence = trust
			f.time     = seen
			f.kind     = world_intern(self.world, cstring(&role[0]))
			f.rule     = world_intern(self.world, cstring(&kind[0]))
			f.choice   = next_
			knowledge_store_add_finding(knowledge_store_of(self, Entity_ID(agent)), f)
		} else if libc.sscanf(text, "ancestry %llu %llu %llu %llu %d %d", &truth, &agent, &origin, &parent, &form,
		                      &present) == 6 {
			a = {}
			a.utterance  = truth
			a.speaker    = Entity_ID(agent)
			a.origin     = Entity_ID(origin)
			a.parent     = parent
			a.relayed    = form != 0
			a.fabricated = present != 0
			knowledge_add_ancestry(self, a)
		} else if libc.sscanf(text, "ref %llu %u %d %u %d %d %d %d %lld %lld %lld %u %d %d %d %llu %63s %511s %4095s %511s", &agent,
		                      &id, &form, &container, &x, &y, &level, &slot, &seen, &first, &inside, &told, &trust, &loyal, &present,
		                      &truth, &role[0], &kind[0], &features[0], &deeper[0]) == 20 {
			decoded: cstring

			store        = knowledge_store_of(self, Entity_ID(agent))
			next_        = knowledge_store_next_id(store)
			r            = knowledge_store_add_referent(store, id)
			r.form       = Location_Form(form)
			r.container  = container
			r.x          = x
			r.y          = y
			r.level      = level
			r.slot       = slot
			r.seen       = seen
			r.first      = first
			r.insideSeen = inside
			r.toldBy     = told
			r.trust      = trust
			r.loyalty    = loyal
			r.present    = present == 1
			r.ended      = present == 2      /* 2: it ended (KNOWLEDGE.md decision 19) */
			r.truth      = Entity_ID(truth)
			decoded      = decode_word(cstring(&role[0]))
			strncpy(raw_data(r.role[:]), ([^]u8)(decoded), size_of(r.role) - 1)
			delete(decoded)
			r.kind       = decode_word(cstring(&kind[0]))
			r.features   = decode_word(cstring(&features[0]))
			r.deeper     = decode_word(cstring(&deeper[0]))
			if len(r.deeper) == 0 {
				delete(r.deeper)
				r.deeper = nil
			}
			knowledge_store_set_next_id(store, u32(know_max64(i64(next_), i64(knowledge_store_next_id(store)))), knowledge_store_self_referent(store))
		}
	}
	self.eventsSeen = world_event_count(self.world)
}


/* --- the protocols ------------------------------------------------------------------- */

knowledge_as_perception_phase :: proc(self: ^Knowledge) -> Perception_Phase {
	return Perception_Phase{
		data              = self,
		perceive_boundary = proc(data: rawptr, boundary: u64) {
			knowledge_perceive_boundary((^Knowledge)(data), boundary)
		},
		next_forgetting   = proc(data: rawptr) -> Time {
			return knowledge_next_forgetting((^Knowledge)(data))
		},
	}
}


knowledge_as_saved_system :: proc(self: ^Knowledge) -> Saved_System {
	return Saved_System{
		data                = self,
		name                = proc(data: rawptr) -> string {
			return knowledge_name((^Knowledge)(data))
		},
		check_in_all        = proc(data: rawptr) {
			knowledge_check_in_all((^Knowledge)(data))
		},
		saved_state         = proc(data: rawptr) -> []string {
			return knowledge_saved_state((^Knowledge)(data))
		},
		restore_saved_state = proc(data: rawptr, lines: []string) {
			knowledge_restore_saved_state((^Knowledge)(data), lines)
		},
	}
}


/* Whether a referent is believed to go about by itself (KNOWLEDGE.md
 * decision 18): an agent, which walks; a thing stays where it was put. */
knowledge_moves_itself :: proc(r: ^Referent) -> bool {
	return r.kind != nil && strings.contains(string(r.kind), "#Agent")
}


/* A thing found gone from where it was (KNOWLEDGE.md decision 18) may be
 * one like it the agent has seen elsewhere since it last saw it there, first
 * seen then: an identity hypothesis each (decision 13), believed as much as
 * BG_FOUND if there is only one, less for each other. A thing that goes
 * about by itself isn't lost; one known alongside it is another. */
@(private)
know_lost :: proc(self: ^Knowledge, store: ^Knowledge_Store, r: ^Referent, news: ^[dynamic]string) {
	if r.kind == nil || knowledge_moves_itself(r) do return
	found := make([dynamic]u32, context.temp_allocator)
	for j: uint = 0; j < knowledge_store_count(store); j += 1 {
		c := knowledge_store_referent_at(store, j)
		if c.id == r.id || c.id == knowledge_store_self_referent(store) || !c.present || c.kind == nil ||
		   string(c.kind) != string(r.kind) || c.first < 0 || c.first <= r.seen {
			continue
		}
		if !knowledge_looks_alike(self, r, store, string(c.kind), string(c.features) if c.features != nil else "") do continue
		append(&found, c.id)
	}
	for c in found {
		h: Identity
		h.a        = c
		h.b        = r.id
		h.credence = BG_FOUND - 10 * i32(len(found) - 1)
		h.time     = world_time(self.world).ms
		knowledge_store_add_identity(store, h)
		append(news, fmt.aprintf("R%d may be R%d (%+d dB): gone from where it was, and one like it seen since", c, r.id,
		                         h.credence))
	}
}


/* What the agent owns, it knows as its own when it sees it (KNOWLEDGE.md
 * decision 18), as it knows whom it is bound to: an #Owned finding, its own
 * the choice. */
@(private)
know_own :: proc(self: ^Knowledge, store: ^Knowledge_Store, agent: Entity_ID, e: Entity_ID, referent: u32, now: i64) {
	claims: [64]Entity_ID
	claimant: [1]Entity_ID
	me := knowledge_store_self_referent(store)
	if me == 0 do return
	held := knowledge_store_finding(store, "#Owned", referent)
	if held != nil && held.choice == me do return
	ownership := u32(tri.type_named(world_tri(self.world), "\"ownership\""))
	kclaim := world_kind_named(self.world, "Claim")
	n := world_edges_to(self.world, .Claim_Subject, e, &claims[0], 64)
	for i: uint = 0; i < n && i < 64; i += 1 {
		claim := (^Claim)(world_record(self.world, kclaim, claims[i]))
		if claim == nil || u32(claim.kind) != ownership do continue
		if world_edges_from(self.world, .Claimant, claims[i], &claimant[0], 1) == 0 || claimant[0] != agent do continue
		/* told it was another's: it knows better */
		if held != nil do knowledge_store_retract_finding(store, "#Owned", referent)
		f: Finding
		f.kind     = world_intern(self.world, "#Owned")
		f.about    = referent
		f.choice   = me
		f.credence = BG_SEEN
		f.rule     = world_intern(self.world, "own")
		f.time     = now
		knowledge_store_add_finding(store, f)
		return
	}
}



/* --- forgetting a referent (KNOWLEDGE.md decision 19) ------------------------------------ */

/* Where things it perceived end ended: at a place (on a tile, in or held by
 * a referent), by an actor (whose hands it may have been in a moment ago:
 * a stack put in a bin merges there). */
@(private = "file")
Ended_Place :: struct {
	form:  Location_Form,
	place: u32,              /* the referent it was in or held by */
	x:     i32,
	y:     i32,
	level: i32,
	hands: u32,              /* the actor, as a referent, or 0 */
	ends:  int,              /* things that ended there */
}


/* The things the agent perceived end this boundary: by an actor in sight,
 * or itself, where they were. */
@(private = "file")
know_ends_witnessed :: proc(self: ^Knowledge, store: ^Knowledge_Store, agent: Entity_ID, here: Location, first: uint, last: uint,
                            seen: [^]Seen, assigned: [^]u32, nseen: uint) -> [dynamic]Ended_Place {
	ends := make([dynamic]Ended_Place, context.temp_allocator)
	me := knowledge_store_self_referent(store)
	for i := first; i < last; i += 1 {
		tile: Location

		ev := world_event_at(self.world, i)
		if (string(ev.kind) != "destroyed" && string(ev.kind) != "merged") || ev.location.form == .None do continue
		/* a reaction's (a stack merging in the bin it was put in): whoever did what it follows from */
		actor := ev.actor
		for c, hops := ev.cause, 0; actor == 0 && c != 0 && hops < 8; hops += 1 {
			cause := world_event_at(self.world, uint(c - 1))      /* indices count from 1 */
			if cause == nil do break
			actor, c = cause.actor, cause.cause
		}
		if actor != agent && !self.omniscient &&
		   (actor == 0 || !know_ground_tile(self.world, actor, &tile) || !knowledge_in_sight(self, tile, here)) {
			continue
		}
		p := Ended_Place{form = ev.location.form, ends = 1}
		p.hands = know_bound_to(actor, agent, me, seen, assigned, nseen) if actor != 0 else 0
		if p.form == .On_Tile {
			if !self.omniscient && !knowledge_sees(self, ev.location, here) do continue
			p.x, p.y, p.level = ev.location.x, ev.location.y, ev.location.level
		} else {
			p.place = know_bound_to(ev.location.place, agent, me, seen, assigned, nseen)
			if p.place == 0 && p.hands == 0 do continue
		}
		merged := false
		for &q in ends {
			if q.form == p.form && q.place == p.place && q.x == p.x && q.y == p.y && q.level == p.level && q.hands == p.hands {
				q.ends += 1
				merged = true
			}
		}
		if !merged do append(&ends, p)
	}
	return ends
}


/* Of what it found gone just now, what it saw end where it believed it: as
 * many as ended at each place, or none if more are gone from there than
 * ended (it can't tell which). */
@(private = "file")
know_ended :: proc(store: ^Knowledge_Store, ends: []Ended_Place, gone: []u32, news: ^[dynamic]string) {
	if len(ends) == 0 do return
	claimed := make([]bool, len(gone), context.temp_allocator)
	for p in ends {
		matched := make([dynamic]int, context.temp_allocator)
		for id, k in gone {
			r := knowledge_store_referent(store, id)
			if claimed[k] || r == nil do continue
			at_place := r.form == p.form &&
			            (r.container == p.place if p.form != .On_Tile else (r.x == p.x && r.y == p.y && r.level == p.level))
			in_hands := p.hands != 0 && r.form == .Held_By && r.container == p.hands
			if at_place || in_hands do append(&matched, k)
		}
		if len(matched) == 0 || len(matched) > p.ends do continue
		for k in matched {
			claimed[k] = true
			r := knowledge_store_mutable_referent(store, gone[k])
			r.ended = true
			append(news, fmt.aprintf("R%d is no more", r.id))
		}
	}
}


/* A referent not believed anywhere, ended or faded below belief, is
 * forgotten if nothing holds it: what it observed, was told, or supposes
 * of it, what it believes in or on it, what its agency holds, or its being
 * someone. Its findings go with it. */
@(private = "file")
know_forget :: proc(self: ^Knowledge, store: ^Knowledge_Store, now: i64, news: ^[dynamic]string) {
	me := knowledge_store_self_referent(store)
	going := make([dynamic]u32, context.temp_allocator)
	for j: uint = 0; j < store.count; j += 1 {
		r := &store.referents[j]
		if r.present || r.id == me || knowledge_moves_itself(r) do continue
		if !r.ended && knowledge_store_strength_of_referent(store, r) >= BG_BELIEVE do continue
		append(&going, r.id)
	}
	if len(going) == 0 do return
	held := make(map[u32]struct{}, context.temp_allocator)
	for j: uint = 0; j < store.count; j += 1 do if store.referents[j].container != 0 do held[store.referents[j].container] = {}
	for j: uint = 0; j < store.nobservations; j += 1 {
		o := &store.observations[j]
		held[o.actor] = {}; held[o.subject] = {}; held[o.other] = {}
	}
	for j: uint = 0; j < store.ntestimony; j += 1 {
		t := &store.testimony[j]
		held[t.thing] = {}; held[t.container] = {}; held[t.source] = {}; held[t.root] = {}; held[t.via] = {}
	}
	for j: uint = 0; j < store.nidentities; j += 1 {
		held[store.identities[j].a] = {}; held[store.identities[j].b] = {}
	}
	for j: uint = 0; j < store.ntraces; j += 1 do held[store.traces[j].bearer] = {}
	for id in going {
		if id in held do continue
		if self.concerns.holds != nil && self.concerns.holds(self.concerns.data, store.agent, id) do continue
		knowledge_store_forget_referent(store, id)
		append(news, fmt.aprintf("R%d: forgotten", id))
	}
}
