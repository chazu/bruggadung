package lab

/*
 * What the watcher's panes read (watcher/panes.odin): the events lately
 * committed, each with the proposal group it was of and that group's source;
 * an event's causes back to where they start; the declaration a group came
 * from, where content declares it (an operation, a progression), with what
 * filled its roles; and the content itself: its files, and a declaration's
 * text as it is written. It reads the world, the committer and the content's
 * files, and changes none of them.
 *
 * Cut points: a group whose source is code (a domain other than
 * progressions, a reaction, a scenario's setup) names no declaration; the
 * goal and method an action was a step of are in the actor's log, not on
 * the event; the variables a declared effect bound aren't kept.
 */

import "core:fmt"
import "core:os"
import "core:strings"

import tri "../../triangle/odin/triangle"


/* A line a pane shows, and what it leads to: an event (its index), an
 * entity, a declaration by name, a content file; or nothing. `code` is a
 * line of content as written. Temporary strings. */
Watcher_Line :: struct {
	text:     string,
	event:    u64,
	entity:   Entity_ID,
	declared: string,
	file:     string,
	at:       int,           // with `file`: the line to show, from 1; or 0
	code:     bool,
	dim:      bool,
}

/* Where a name is declared: every declaration of it, a topic's additions to
 * a root type among them. */
Watcher_Decl :: struct {
	name: string,
	file: string,
	line: int,
}


@(private = "file")
watcher_clock :: proc(ms: i64) -> string {
	return fmt.tprintf("d%d %02d:%02d:%02d", ms / 86_400_000 + 1, ms / 3_600_000 % 24, ms / 60_000 % 60, ms / 1000 % 60)
}


/* An event in a line: when, what, of what, and its group's source. */
@(private = "file")
watcher_event_line :: proc(w: ^Watcher, ev: ^Event) -> Watcher_Line {
	b := strings.builder_make(context.temp_allocator)
	c, kept := committer_committed_at(w.scheduler.committer, ev.group)
	if kept do fmt.sbprintf(&b, "%s  ", watcher_clock(c.time))
	fmt.sbprintf(&b, "%s %s", ev.kind, watcher_name(w, ev.subject))
	if ev.detail != nil do fmt.sbprintf(&b, " %s", ev.detail)
	if ev.other != NO_ENTITY do fmt.sbprintf(&b, ", %s", watcher_name(w, ev.other))
	if source, ok := committer_source_of_position(w.scheduler.committer, ev.group); ok {
		fmt.sbprintf(&b, "   (%s)", source)
	}
	return {text = strings.to_string(b), event = ev.index, dim = ev.diagnostic}
}


/* The proposal groups lately committed that left events, the latest first,
 * `limit` at most: all of them, or those with an event `about` an entity
 * (it is its subject, its other, or who did it). A line to a group: when,
 * its source, and its events by kind; it leads to the first of its events
 * (of those about the entity). */
watcher_log :: proc(w: ^Watcher, about: Entity_ID, limit: int) -> []Watcher_Line {
	lines := make([dynamic]Watcher_Line, context.temp_allocator)
	history := world_history(w.world)
	for end := len(history); end > 0 && len(lines) < limit; {
		start := end - 1                 /* a group's events stand together */
		for start > 0 && history[start - 1].group == history[end - 1].group do start -= 1
		run := history[start:end]
		end = start
		first: ^Event
		kinds: [8]cstring
		counts: [8]int
		nkinds, diagnostic := 0, true
		for &ev in run {
			if first == nil && (about == NO_ENTITY || ev.subject == about || ev.other == about || ev.actor == about) {
				first = &ev
			}
			diagnostic &&= ev.diagnostic
			k := 0
			for k < nkinds && kinds[k] != ev.kind do k += 1
			if k == len(kinds) do continue
			if k == nkinds {
				kinds[k] = ev.kind
				nkinds += 1
			}
			counts[k] += 1
		}
		if first == nil do continue
		b := strings.builder_make(context.temp_allocator)
		c, kept := committer_committed_at(w.scheduler.committer, first.group)
		if kept do fmt.sbprintf(&b, "%s  ", watcher_clock(c.time))
		source, ok := committer_source_of_position(w.scheduler.committer, first.group)
		strings.write_string(&b, source if ok else "before the save")
		strings.write_string(&b, ":")
		for k in 0 ..< nkinds {
			fmt.sbprintf(&b, " %s", kinds[k])
			if counts[k] > 1 do fmt.sbprintf(&b, " x%d", counts[k])
		}
		append(&lines, Watcher_Line{text = strings.to_string(b), event = first.index, dim = diagnostic})
	}
	return lines[:]
}


/* One event in full: what it is, the group it was of with the others of
 * that group, the declaration the group came from with what filled its
 * roles, and the chain of its causes. Nothing for an event no longer kept. */
watcher_event :: proc(w: ^Watcher, index: u64) -> []Watcher_Line {
	lines := make([dynamic]Watcher_Line, context.temp_allocator)
	ev := world_event_at(w.world, uint(index) - 1) if index != 0 else nil
	if ev == nil {
		append(&lines, Watcher_Line{text = fmt.tprintf("Event %d is no longer kept.", index)})
		return lines[:]
	}
	append(&lines, Watcher_Line{text = fmt.tprintf("event %d: %s%s%s", ev.index, ev.kind, " " if ev.detail != nil else "",
	                                               ev.detail if ev.detail != nil else "")})
	append(&lines, Watcher_Line{text = fmt.tprintf("  of %s", watcher_name(w, ev.subject)), entity = ev.subject})
	if ev.other != NO_ENTITY {
		append(&lines, Watcher_Line{text = fmt.tprintf("  and %s", watcher_name(w, ev.other)), entity = ev.other})
	}
	if ev.actor != NO_ENTITY {
		append(&lines, Watcher_Line{text = fmt.tprintf("  by %s", watcher_name(w, ev.actor)), entity = ev.actor})
	}
	if ev.location.form != .None do append(&lines, Watcher_Line{text = fmt.tprintf("  to %s", location_format(ev.location))})
	if name := world_event_type_name(w.world, ev); name != nil {
		append(&lines, Watcher_Line{text = fmt.tprintf("  %s", name)})
	} else if ev.amount != 0 {
		append(&lines, Watcher_Line{text = fmt.tprintf("  amount %d", ev.amount)})
	}
	c, kept := committer_committed_at(w.scheduler.committer, ev.group)
	append(&lines, Watcher_Line{text = fmt.tprintf("  boundary %d, round %d%s%s", ev.boundary, ev.round,
	                                               ", at " if kept else "", watcher_clock(c.time) if kept else ""),
	                            dim = true})
	if ev.diagnostic do append(&lines, Watcher_Line{text = "  a step along the way: kept a while, not history", dim = true})

	append(&lines, Watcher_Line{})
	source, ok := committer_source_of_position(w.scheduler.committer, ev.group)
	append(&lines, Watcher_Line{text = fmt.tprintf("proposal group %d: %s", ev.group, source if ok else "before the save")})
	history := world_history(w.world)
	for &other in history {
		if other.group != ev.group || other.index == ev.index do continue
		line := watcher_event_line(w, &other)
		line.text = fmt.tprintf("  with: %s %s%s%s", other.kind, watcher_name(w, other.subject),
		                        " " if other.detail != nil else "", other.detail if other.detail != nil else "")
		append(&lines, line)
	}
	if kept && c.declared != nil {
		append(&lines, Watcher_Line{})
		append(&lines, Watcher_Line{text = fmt.tprintf("declared: %s", c.declared), declared = string(c.declared)})
		for r in Role.Actor ..< Role.Count {
			if c.acts.roles[r] == NO_ENTITY || ROLE_NAMES[r] == nil do continue
			append(&lines, Watcher_Line{text = fmt.tprintf("  %s: %s", ROLE_NAMES[r], watcher_name(w, c.acts.roles[r])),
			                            entity = c.acts.roles[r]})
		}
		if c.acts.content != nil do append(&lines, Watcher_Line{text = fmt.tprintf("  content: %s", c.acts.content)})
		if c.acts.way != nil do append(&lines, Watcher_Line{text = fmt.tprintf("  way: %s", c.acts.way)})
	} else {
		append(&lines, Watcher_Line{text = "its source is code: no declaration", dim = true})
	}

	if ev.cause != 0 {
		append(&lines, Watcher_Line{})
		append(&lines, Watcher_Line{text = "because:"})
		depth := 1
		for cause := world_event_at(w.world, uint(ev.cause) - 1); cause != nil && depth <= 12; depth += 1 {
			line := watcher_event_line(w, cause)
			line.text = fmt.tprintf("%*s%s", depth * 2, "", line.text)
			append(&lines, line)
			cause = world_event_at(w.world, uint(cause.cause) - 1) if cause.cause != 0 else nil
		}
	}
	return lines[:]
}


/* The declaration the event's group came from, or "". */
watcher_declared_by :: proc(w: ^Watcher, index: u64) -> string {
	ev := world_event_at(w.world, uint(index) - 1) if index != 0 else nil
	if ev == nil do return ""
	c, kept := committer_committed_at(w.scheduler.committer, ev.group)
	return string(c.declared) if kept && c.declared != nil else ""
}


/* What content declares of an entity: its blueprint, and the type of each
 * component it has. */
watcher_declarations_of :: proc(w: ^Watcher, e: Entity_ID) -> []string {
	names := make([dynamic]string, context.temp_allocator)
	info := world_info(w.world, e)
	if info == nil do return names[:]
	append(&names, string(info.blueprint))
	for k: uint = 0; k < w.world.nkinds; k += 1 {
		if store_record_for(w.world.kinds[k], e) != nil do append(&names, string(COMPONENTS[k].type))
	}
	return names[:]
}


/* Every declaration of a name, in load order. A name is found as written
 * (`#Food`, `forage`), whichever package declares it, or qualified
 * (`hunger.#Food`). */
watcher_declared :: proc(w: ^Watcher, name: string) -> []Watcher_Decl {
	found := make([dynamic]Watcher_Decl, context.temp_allocator)
	if name == "" do return found[:]
	tc := world_tri(w.world)
	d: tri.Decl
	for i in 0 ..< tri.decl_count(tc) {
		if tri.decl(tc, i, &d) == 0 || d.file == nil do continue
		full := string(d.name)
		bare := full
		if dot := strings.last_index_byte(full, '.'); dot >= 0 do bare = full[dot + 1:]
		if full != name && bare != name do continue
		append(&found, Watcher_Decl{name = full, file = string(d.file), line = int(d.line)})
	}
	return found[:]
}


/* The content's files, in load order. */
watcher_files :: proc(w: ^Watcher) -> []string {
	files := make([dynamic]string, context.temp_allocator)
	tc := world_tri(w.world)
	d: tri.Decl
	last := ""
	for i in 0 ..< tri.decl_count(tc) {
		if tri.decl(tc, i, &d) == 0 || d.file == nil || string(d.file) == last do continue
		last = string(d.file)
		seen := false
		for f in files do if f == last do seen = true
		if !seen do append(&files, last)
	}
	return files[:]
}


/* A content file's lines, read once and kept for the session. */
@(private = "file")
watcher_texts: map[string][]string

watcher_file :: proc(path: string) -> []string {
	if lines, ok := watcher_texts[path]; ok do return lines
	lines: []string
	if data, err := os.read_entire_file(path, context.allocator); err == nil {
		lines = strings.split_lines(string(data), context.allocator)
	}
	watcher_texts[strings.clone(path)] = lines
	return lines
}


/* The lines a declaration is written on: `first`, from 1, is the first of
 * the comment above it, and it runs to where its brackets close. */
watcher_source :: proc(file: string, line: int) -> (first: int, text: []string) {
	lines := watcher_file(file)
	if line < 1 || line > len(lines) do return 0, nil
	first = line
	for first > 1 && strings.has_prefix(strings.trim_left_space(lines[first - 2]), "//") do first -= 1
	depth, last := 0, line
	for last <= len(lines) {
		quoted := false
		l := lines[last - 1]
		for i := 0; i < len(l); i += 1 {
			switch {
			case l[i] == '\\' && quoted:  i += 1
			case l[i] == '"':             quoted = !quoted
			case quoted:
			case l[i] == '/' && i + 1 < len(l) && l[i + 1] == '/': i = len(l)
			case l[i] == '{' || l[i] == '[' || l[i] == '(': depth += 1
			case l[i] == '}' || l[i] == ']' || l[i] == ')': depth -= 1
			}
		}
		if depth <= 0 do break
		last += 1
	}
	return first, lines[first - 1:min(last, len(lines))]
}
