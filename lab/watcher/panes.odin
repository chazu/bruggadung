/*
 * The watcher's panes: what the panel on the right shows, one at a time.
 *
 *   1  Inspect   what is selected: its records (or, in an agent's knowledge,
 *                what it recalls), what content declares of it, and what
 *                lately happened to it
 *   2  Log       the proposal groups committed, the latest first, a line to
 *                each with its events by kind: all of them, or those
 *                about what is selected; one opened shows its event, its
 *                proposal group, the declaration it came from with what
 *                filled its roles and its text, and the chain of its causes
 *   3  Content   the content's files; a file; a declaration, wherever it is
 *                declared
 *
 * A line that leads somewhere is drawn as a link: an event opens in the
 * log, an entity is selected, a declaration or a file opens in the content.
 * In content as written, a click on a name that is declared opens it.
 * Backspace goes back; the wheel scrolls (sideways, or with shift, content
 * as written); `\` widens the panel, or narrows it again.
 *
 * It reads through lab's watcher_inspect.odin, and changes nothing but
 * what is selected.
 */
package watcher

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

import lab "../src"
import view "../../tessera/raylib"

Pane :: enum {
	Inspect,
	Log,
	Content,
}

PANE_NAMES :: [Pane]string {
	.Inspect = "1 Inspect",
	.Log     = "2 Log",
	.Content = "3 Content",
}

// What the content pane shows: a declaration, a file (at a line), or, with
// neither, the files. Its strings are its own.
Shown :: struct {
	declared: string,
	file:     string,
	at:       int,
	scroll:   f32,
}

Panes :: struct {
	pane:   Pane,
	scroll: [Pane]f32,
	all:    bool,              // the log: every event, not only those about what is selected
	event:  u64,               // the log: the event opened, or 0
	shown:  Shown,
	back:   [dynamic]Shown,    // what the content pane showed before
	jump:   int,               // a line of a file to scroll to once it is laid out, or 0
	across: f32,               // px content as written is drawn to the left: the wheel sideways
	wide:   bool,              // the panel takes two thirds of the window
}

@(private = "file")
Act :: enum {
	None,
	All,        // the log: all, or about the selection
	Back,
	Files,
}

@(private = "file")
Line :: struct {
	using line: lab.Watcher_Line,
	act:        Act,
	head:       bool,
}

PX     :: 14
ROW    :: PX + 4
TAB_H  :: 28

@(private = "file") INK      :: rl.Color{210, 210, 200, 255}
@(private = "file") DIM      :: rl.Color{130, 130, 135, 255}
@(private = "file") LINK     :: rl.Color{130, 190, 255, 255}
@(private = "file") HEAD     :: rl.Color{240, 215, 120, 255}
@(private = "file") COMMENT  :: rl.Color{120, 150, 120, 255}
@(private = "file") CODE     :: rl.Color{200, 205, 215, 255}

panes_free :: proc(p: ^Panes) {
	shown_free(&p.shown)
	for &s in p.back do shown_free(&s)
	delete(p.back)
}

@(private = "file")
shown_free :: proc(s: ^Shown) {
	delete(s.declared)
	delete(s.file)
	s^ = {}
}

// Opens a declaration, or a file at a line, in the content pane; what it
// showed is kept to go back to.
panes_open :: proc(p: ^Panes, declared, file: string, at: int) {
	p.shown.scroll = p.scroll[.Content]
	append(&p.back, p.shown)
	p.shown = Shown{declared = strings.clone(declared), file = strings.clone(file), at = at}
	p.pane = .Content
	p.scroll[.Content] = 0
	p.jump = at if file != "" else 0
}

@(private = "file")
panes_back :: proc(p: ^Panes) {
	switch p.pane {
	case .Inspect:
	case .Log:
		p.event = 0
		p.scroll[.Log] = 0
	case .Content:
		if len(p.back) == 0 do return
		shown_free(&p.shown)
		p.shown = pop(&p.back)
		p.scroll[.Content] = p.shown.scroll
	}
}

// A path as the content names it: below the content directory.
@(private = "file")
short :: proc(path: string) -> string {
	if strings.has_prefix(path, lab.content_dir) do return strings.trim_left(path[len(lab.content_dir):], "/")
	return path
}

@(private = "file")
add :: proc(lines: ^[dynamic]Line, text: string, act := Act.None, head := false, dim := false) {
	append(lines, Line{line = {text = text, dim = dim}, act = act, head = head})
}

// A declaration as written, wherever it is declared: for each place, where,
// and its lines.
@(private = "file")
add_declared :: proc(lines: ^[dynamic]Line, w: ^lab.Watcher, name: string) {
	decls := lab.watcher_declared(w, name)
	if len(decls) == 0 do add(lines, fmt.tprintf("%s isn't declared by that name.", name), dim = true)
	for d in decls {
		first, text := lab.watcher_source(d.file, d.line)
		append(lines, Line{line = {text = fmt.tprintf("%s   %s:%d", d.name, short(d.file), d.line), file = d.file, at = d.line}})
		for l, i in text do append(lines, Line{line = {text = l, code = true, file = d.file, at = first + i}})
		add(lines, "")
	}
}

@(private = "file")
build :: proc(p: ^Panes, w: ^lab.Watcher, selected: u64, knower: lab.Entity_ID, inspect: []string) -> []Line {
	lines := make([dynamic]Line, context.temp_allocator)
	e := lab.Entity_ID(selected) if knower == 0 else 0     // in an agent's knowledge, a referent: no entity
	switch p.pane {
	case .Inspect:
		for l in inspect do add(&lines, l)
		if e != 0 {
			add(&lines, "")
			add(&lines, "Declared", head = true)
			for name in lab.watcher_declarations_of(w, e) {
				append(&lines, Line{line = {text = fmt.tprintf("  %s", name), declared = name}})
			}
			add(&lines, "")
			add(&lines, "Lately", head = true)
			log := lab.watcher_log(w, e, 16)
			if len(log) == 0 do add(&lines, "  nothing has happened to it", dim = true)
			for l in log do append(&lines, Line{line = l})
		}
	case .Log:
		if p.event != 0 {
			add(&lines, "< the log", act = .Back)
			add(&lines, "")
			for l in lab.watcher_event(w, p.event) do append(&lines, Line{line = l})
			if name := lab.watcher_declared_by(w, p.event); name != "" {
				add(&lines, "")
				add(&lines, "As declared", head = true)
				add_declared(&lines, w, name)
			}
		} else {
			about := e if !p.all else 0
			if e != 0 {
				add(&lines, fmt.tprintf("about %s   (click: every event)", lab.watcher_name(w, e)) if !p.all else
				            fmt.tprintf("every event   (click: about %s)", lab.watcher_name(w, e)), act = .All)
			} else {
				add(&lines, "every event", head = true)
			}
			add(&lines, "")
			for l in lab.watcher_log(w, about, 400) do append(&lines, Line{line = l})
		}
	case .Content:
		switch {
		case p.shown.declared != "":
			add(&lines, "< back" if len(p.back) > 0 else "", act = .Back)
			add(&lines, "the files", act = .Files)
			add(&lines, "")
			add_declared(&lines, w, p.shown.declared)
		case p.shown.file != "":
			add(&lines, "< back" if len(p.back) > 0 else "", act = .Back)
			add(&lines, "the files", act = .Files)
			add(&lines, short(p.shown.file), head = true)
			add(&lines, "")
			for l, i in lab.watcher_file(p.shown.file) {
				append(&lines, Line{line = {text = l, code = true, file = p.shown.file, at = i + 1}})
			}
		case:
			add(&lines, "The content's files", head = true)
			topic := "?"
			for f in lab.watcher_files(w) {
				name := short(f)
				slash := strings.last_index_byte(name, '/')
				dir := name[:slash] if slash >= 0 else ""
				if dir != topic {
					topic = dir
					add(&lines, "")
					add(&lines, fmt.tprintf("%s/", dir) if dir != "" else "the vocabulary", dim = true)
				}
				append(&lines, Line{line = {text = fmt.tprintf("  %s", name[slash + 1:]), file = f}})
			}
		}
	}
	return lines[:]
}

// The name written under a column of a line of content: letters, digits,
// `_`, a leading `#`, and a package before a dot.
@(private = "file")
name_at :: proc(text: string, col: int) -> string {
	part :: proc(c: u8) -> bool {
		return c == '_' || c == '#' || c == '.' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
	}
	if col < 0 || col >= len(text) || !part(text[col]) do return ""
	lo, hi := col, col + 1
	for lo > 0 && part(text[lo - 1]) do lo -= 1
	for hi < len(text) && part(text[hi]) do hi += 1
	return strings.trim(text[lo:hi], ".")
}

// Takes the panes' input and draws the one shown, over the viewer's panel.
// `inspect` is what the inspector says of what is selected. Returns the
// entity a click selected, or 0.
panes_frame :: proc(p: ^Panes, v: ^view.Viewer, w: ^lab.Watcher, knower: lab.Entity_ID, inspect: []string) -> (select: u64) {
	if rl.IsKeyPressed(.ONE) do p.pane = .Inspect
	if rl.IsKeyPressed(.TWO) do p.pane = .Log
	if rl.IsKeyPressed(.THREE) do p.pane = .Content
	if rl.IsKeyPressed(.BACKSPACE) do panes_back(p)
	if rl.IsKeyPressed(.BACKSLASH) do p.wide = !p.wide
	v.panel = 1400 if p.wide else 620
	v.share = 0.66 if p.wide else 0.4

	width := f32(view.panel_width(v))
	left  := f32(rl.GetScreenWidth()) - width
	high  := f32(rl.GetScreenHeight())
	mouse := rl.GetMousePosition()
	over  := mouse.x >= left
	click := over && rl.IsMouseButtonPressed(.LEFT)

	// the tabs
	names := PANE_NAMES
	x := left + 10
	for pane in Pane {
		tw := view.text_width(&v.fonts, names[pane], PX)
		hit := mouse.x >= x - 4 && mouse.x < x + tw + 8 && mouse.y < TAB_H
		if hit && click {
			p.pane = pane
			click = false
		}
		view.draw_text(&v.fonts, names[pane], {x, 7}, PX, HEAD if pane == p.pane else (INK if hit else DIM))
		if pane == p.pane do rl.DrawRectangleV({x, TAB_H - 5}, {tw, 2}, HEAD)
		x += tw + 22
	}
	rl.DrawLine(i32(left), TAB_H, rl.GetScreenWidth(), TAB_H, {70, 70, 80, 255})

	lines := build(p, w, v.selected, knower, inspect)
	if over {
		wheel := rl.GetMouseWheelMoveV()
		sideways := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
		p.scroll[p.pane] -= (0 if sideways else wheel.y) * ROW * 3
		p.across = max(p.across - (wheel.y if sideways else wheel.x) * 40, 0)
	}

	char := view.text_width(&v.fonts, "M", PX)
	inner := width - 20
	rl.BeginScissorMode(i32(left) + 1, TAB_H + 1, i32(width) - 1, i32(high) - TAB_H - 1)
	y := f32(TAB_H + 8) - p.scroll[p.pane]
	top := y
	act := Act.None
	opened: Line
	name: string
	for l in lines {
		if l.code && p.jump != 0 && l.at == p.jump && l.file == p.shown.file {
			p.scroll[p.pane] = max(y - top - ROW * 3, 0)
			p.jump = 0
		}
		parts: []string
		if l.code {
			text, _ := strings.replace_all(l.text, "\t", "    ", context.temp_allocator)
			parts = {text}
		} else if l.text == "" {
			y += ROW / 2
			continue
		} else {
			parts = view.wrap(&v.fonts, l.text, inner, PX)
		}
		leads := l.event != 0 || l.entity != 0 || l.declared != "" || (l.file != "" && !l.code) || l.act != .None
		rows := f32(len(parts)) * ROW
		hit := over && mouse.y >= max(y, TAB_H) && mouse.y < y + rows
		if y + rows >= TAB_H && y < high {
			colour := INK
			switch {
			case l.head:  colour = HEAD
			case l.code:  colour = COMMENT if strings.has_prefix(strings.trim_left_space(l.text), "//") else CODE
			case leads:   colour = LINK
			case l.dim:   colour = DIM
			}
			if leads && l.dim do colour = rl.Color{100, 140, 185, 255}
			if hit && leads do rl.DrawRectangleV({left + 4, y - 1}, {width - 8, rows}, {40, 50, 70, 255})
			if l.code && p.pane == .Content && p.shown.file != "" && l.at == p.shown.at {
				rl.DrawRectangleV({left + 4, y - 1}, {width - 8, rows}, {50, 46, 24, 255})
			}
			shift := p.across if l.code else 0
			for part, i in parts do view.draw_text(&v.fonts, part, {left + 10 - shift, y + f32(i) * ROW}, PX, colour)
			if l.code && hit {       // a name under the mouse that is declared: underlined
				col := int((mouse.x - left - 10 + shift) / char)
				if n := name_at(parts[0], col); n != "" && len(lab.watcher_declared(w, n)) > 0 {
					at := strings.index(parts[0], n)
					for at >= 0 && at + len(n) <= col {
						next := strings.index(parts[0][at + 1:], n)
						if next < 0 do break
						at += 1 + next
					}
					rl.DrawRectangleV({left + 10 - shift + f32(at) * char, y + PX + 1}, {f32(len(n)) * char, 1}, LINK)
					if click do name = n
				}
			}
		}
		if hit && click && leads do opened, act = l, l.act
		y += rows
	}
	rl.EndScissorMode()
	total := y - top
	p.scroll[p.pane] = clamp(p.scroll[p.pane], 0, max(total - (high - TAB_H - 40), 0))

	switch {
	case name != "":
		panes_open(p, name, "", 0)
	case act == .All:
		p.all = !p.all
		p.scroll[.Log] = 0
	case act == .Back:
		panes_back(p)
	case act == .Files:
		panes_open(p, "", "", 0)
	case opened.event != 0:
		p.pane, p.event = .Log, opened.event
		p.scroll[.Log] = 0
	case opened.entity != 0:
		if knower == 0 do select = u64(opened.entity)
	case opened.declared != "":
		panes_open(p, opened.declared, "", 0)
	case opened.file != "":
		panes_open(p, "", opened.file, opened.at)
	}
	return select
}
