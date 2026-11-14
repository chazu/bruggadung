/*
 * watcher — a lab world in a window (TESSERA.md, slice 4): the watcher and its
 * viewer in one process. The world runs on the viewer's clock, boundary by
 * boundary, and each frame draws a scene of what is in view: the truth, or
 * the world as one agent knows it (VILLAGE.md slice 11).
 *
 *   watcher [-C contentdir] <what> [agents] [--from hours] [--knows] [--pane log|content]
 *           [--open declaration] [--shot file.png]
 *
 * <what> is one of lab.WATCHABLE (for `hills`, the number is its seed). In the window:
 *
 *   space        pause, or go on          .  one boundary
 *   [  ]         slower, faster           f  follow the one selected, or stop
 *   tab          select the next agent    q  quit
 *   k            as the agent selected knows it, or the truth again
 *   click        select what is on a tile (again: the one under it)
 *   arrows/WASD, right-drag: pan; wheel: zoom; PgUp/PgDn or < >: level;
 *   L: light; Esc: select nothing
 *   1 2 3        the panel's pane: inspect, the log, the content (panes.odin)
 *   backspace    back, in the log and the content
 *   \            the panel wide, or narrow again
 *
 * In an agent's knowledge, what is selected is one of its referents, and
 * tab goes on to the next agent's knowledge. --from runs the world that many
 * hours before the window opens (as it would run watched: no boundary put
 * in). --knows opens it as the first agent knows it, following it. --shot draws three
 * seconds of frames, saves the last as a PNG, and quits: a look at the
 * window without anyone at it. --pane opens the panel on that pane, and
 * --open the content pane on a declaration (`forage`, `#Patch`).
 *
 * The lab itself never links raylib: this is its own executable, built by
 * `make watcher`.
 */
package watcher

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

import lab "../src"
import view "../../tessera/raylib"

// World seconds a wall second.
SPEEDS :: [?]f64{0.25, 0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600, 1800, 3600}

// Wall time a frame may spend running boundaries.
BUDGET_NS :: 12_000_000

HELP :: [?]string {
	"space: pause   .: one boundary   [ ]: slower, faster",
	"click: select (again: the one under it)   tab: next agent   f: follow",
	"arrows, WASD, right-drag: pan   wheel: zoom   PgUp PgDn, < >: level",
	"k: as the agent selected knows it, or the truth",
	"L: light   Esc: select nothing   q: quit",
	"1 2 3: inspect, the log, the content   backspace: back   \\: wide panel",
	"over the panel, the wheel scrolls; a blue line leads somewhere",
}

main :: proc() {
	args := make([dynamic]string)
	knows := false                     // --knows: open as the first agent knows it
	for a in os.args[1:] {
		if a == "--knows" do knows = true
		else do append(&args, a)
	}
	shot: string
	from: f64                          // hours of world time run before the window opens
	pane: Pane                         // --pane: the pane the panel opens on
	open: string                       // --open: a declaration the content pane opens on
	for len(args) >= 2 && (args[len(args) - 2] == "--shot" || args[len(args) - 2] == "--from" ||
	                       args[len(args) - 2] == "--pane" || args[len(args) - 2] == "--open") {
		if args[len(args) - 2] == "--shot" {
			shot = args[len(args) - 1]
		} else if args[len(args) - 2] == "--pane" {
			switch args[len(args) - 1] {
			case "log":     pane = .Log
			case "content": pane = .Content
			}
		} else if args[len(args) - 2] == "--open" {
			open = args[len(args) - 1]
		} else if h, ok := strconv.parse_f64(args[len(args) - 1]); ok && h >= 0 {
			from = h
		}
		resize(&args, len(args) - 2)
	}
	if len(args) >= 2 && args[0] == "-C" {
		lab.content_dir = args[1]
		remove_range(&args, 0, 2)
	}
	if len(args) < 1 {
		fmt.eprintf("usage: watcher [-C contentdir] <what> [agents]\n  <what>: %s\n", lab.WATCHABLE)
		os.exit(2)
	}
	defer delete(args)
	agents: i32 = 40
	if len(args) >= 2 {
		n, ok := strconv.parse_int(args[1])
		if !ok || n < 1 {
			fmt.eprintf("watcher: not a number of agents: %s\n", args[1])
			os.exit(2)
		}
		agents = i32(n)
	}

	lab.pool_push()                    // the world's objects: they last the session
	w, why := lab.watcher_open(args[0], agents)
	if why != "" {
		fmt.eprintf("watcher: %s: %s\n  <what>: %s\n", args[0], why, lab.WATCHABLE)
		os.exit(2)
	}
	lab.release_shared_content_after_use()

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1600, 940, strings.clone_to_cstring(fmt.tprintf("watcher: %s", w.title)))
	rl.SetExitKey(.KEY_NULL)           // Escape lets go of the selection; q quits
	rl.SetTargetFPS(60)

	/* the tiles theme, from content (content/looks/tiles.tri) */
	theme := view.theme_make()
	for g in lab.watcher_glyphs(&w) {
		ground := view.rgb(g.ground) if g.has_ground else theme.background
		view.theme_set(&theme, g.look, {g.char, view.rgb(g.ink), ground})
	}
	world := w.world
	levels := lab.world_levels(world)
	centre := [2]i32{lab.world_tiles_wide(world), lab.world_tiles_high(world)} / 2
	v := view.viewer_make({f32(centre.x), f32(centre.y)}, lab.world_ground_level(world, centre.x, centre.y),
	                      {0, levels - 1})
	if x, y, z, ok := lab.watcher_tile_of(&w, w.follow); ok do v.centre, v.focus = {f32(x), f32(y)}, z
	v.selected = u64(w.follow)
	panes := Panes{pane = pane}
	if open != "" do panes_open(&panes, open, "", 0)
	follow := false                    // f follows the one selected
	knower: lab.Entity_ID              // whose knowledge is shown; none: the truth

	speeds := SPEEDS
	speed := 2                         // 1 world second a second
	paused := false
	lab.watcher_step_until(&w, i64(from * 3_600_000), max(u64))
	clock := max(f64(lab.world_time(world).ms), from * 3_600_000)   // the viewer's clock: world ms
	if knows && lab.watcher_knows(&w, w.follow) {
		knower, v.selected = w.follow, u64(lab.watcher_self_of(&w, w.follow))
		follow = true
	}
	behind := false
	seq: u64

	frames := 0
	for !rl.WindowShouldClose() && !rl.IsKeyPressed(.Q) {
		lab.pool_push()                // a frame's: its scene, its strings
		dt := f64(rl.GetFrameTime())
		shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
		if rl.IsKeyPressed(.SPACE) do paused = !paused
		if rl.IsKeyPressed(.RIGHT_BRACKET) do speed = min(speed + 1, len(speeds) - 1)
		if rl.IsKeyPressed(.LEFT_BRACKET) do speed = max(speed - 1, 0)
		if rl.IsKeyPressed(.L) do v.shade = !v.shade
		if rl.IsKeyPressed(.F) do follow = !follow && v.selected != 0
		if rl.IsKeyPressed(.K) {
			if knower != 0 {                    // back to the truth, the knower selected
				v.selected, knower = u64(knower), 0
			} else if lab.watcher_knows(&w, lab.Entity_ID(v.selected)) {
				knower = lab.Entity_ID(v.selected)
				v.selected = u64(lab.watcher_self_of(&w, knower))
			}
		}
		if rl.IsKeyPressed(.TAB) && len(w.ids) > 0 {
			if knower == 0 {
				next := 0
				for id, i in w.ids do if u64(id) == v.selected do next = (i + 1) % len(w.ids)
				v.selected = u64(w.ids[next])
			} else {                            // the next agent's knowledge
				at := 0
				for id, i in w.ids do if id == knower do at = i
				for step in 1 ..= len(w.ids) {
					next := w.ids[(at + step) % len(w.ids)]
					if !lab.watcher_knows(&w, next) do continue
					knower, v.selected = next, u64(lab.watcher_self_of(&w, next))
					break
				}
			}
		}
		if rl.IsKeyPressed(.PERIOD) && !shift {
			paused = true
			lab.watcher_step(&w)
			clock = f64(lab.world_time(world).ms)
		}
		if !paused {
			clock += dt * 1000 * speeds[speed]
			behind = !lab.watcher_step_until(&w, i64(clock), BUDGET_NS)
			// a world slower than the clock falls behind by a quarter second at
			// most; one with nothing to do (no boundary due) isn't behind
			if behind do clock = min(clock, f64(lab.world_time(world).ms) + 250 * speeds[speed])
		}

		if follow && v.selected != 0 {
			x, y, z: i32
			ok: bool
			if knower == 0 {
				x, y, z, ok = lab.watcher_tile_of(&w, lab.Entity_ID(v.selected))
			} else {
				x, y, z, ok = lab.watcher_believed_tile(&w, knower, u32(v.selected))
			}
			if ok do v.centre, v.focus = {f32(x), f32(y)}, z
		}
		scene := lab.watcher_scene(&w, knower, view.viewer_extent(&v), seq)
		seq += 1
		if view.viewer_input(&v, scene) do follow = false

		/* nothing happens between boundaries: caught up, the world stands as
		 * it will until the next, at the clock's time */
		now := lab.world_time(world).ms
		if !behind do now = max(now, i64(clock))
		header := [?]string {
			fmt.tprintf("%s   day %d  %02d:%02d:%02d   boundary %d", w.title, now / 86_400_000 + 1,
			            now / 3_600_000 % 24, now / 60_000 % 60, now / 1000 % 60, lab.world_boundary(world)),
			fmt.tprintf("x%v%s%s   level %d%s", speeds[speed], "   paused" if paused else "",
			            "   (behind)" if behind && !paused else "", v.focus,
			            fmt.tprintf("   as %s knows it", lab.watcher_name(&w, knower)) if knower != 0 else ""),
		}
		panel := make([dynamic]string, context.temp_allocator)
		if v.selected != 0 {
			if follow do append(&panel, "following")
			lines := lab.watcher_describe(&w, lab.Entity_ID(v.selected)) if knower == 0 else
			         lab.watcher_recall(&w, knower, u32(v.selected))
			for line in lines do append(&panel, line)
		} else {
			append(&panel, "Nothing selected.")
			for line in HELP do append(&panel, line)
		}

		rl.BeginDrawing()
		view.viewer_draw(&v, scene, &theme, header[:], nil)
		if picked := panes_frame(&panes, &v, &w, knower, panel[:]); picked != 0 do v.selected = picked
		rl.EndDrawing()
		frames += 1
		if shot != "" && frames == 180 {
			image := rl.LoadImageFromScreen()
			rl.ExportImage(image, strings.clone_to_cstring(shot, context.temp_allocator))
			rl.UnloadImage(image)
			lab.pool_drain()
			break
		}
		lab.pool_drain()
	}

	panes_free(&panes)
	view.viewer_free(&v)
	rl.CloseWindow()
	view.theme_free(&theme)
	delete(w.ids)
	delete(w.title)
	lab.pool_drain()
	lab.free_released_content()
}
