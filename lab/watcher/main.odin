/*
 * watcher — a lab world in a window (TESSERA.md, slice 4): the watcher and its
 * viewer in one process. The world runs on the viewer's clock, boundary by
 * boundary, and each frame draws a truth scene of what is in view.
 *
 *   watcher [-C contentdir] <what> [agents] [--shot file.png]
 *
 * <what> is one of lab.WATCHABLE. In the window:
 *
 *   space        pause, or go on          .  one boundary
 *   [  ]         slower, faster           f  follow the one selected, or stop
 *   tab          select the next agent    q  quit
 *   click        select what is on a tile (again: the one under it)
 *   arrows/WASD, right-drag: pan; wheel: zoom; PgUp/PgDn or < >: level;
 *   L: light; Esc: select nothing
 *
 * --shot draws three seconds of frames, saves the last as a PNG, and quits:
 * a look at the window without anyone at it.
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
	"L: light   Esc: select nothing   q: quit",
}

main :: proc() {
	args := os.args[1:]
	shot: string
	if len(args) >= 2 && args[len(args) - 2] == "--shot" {
		shot = args[len(args) - 1]
		args = args[:len(args) - 2]
	}
	if len(args) >= 2 && args[0] == "-C" {
		lab.content_dir = args[1]
		args = args[2:]
	}
	if len(args) < 1 {
		fmt.eprintf("usage: watcher [-C contentdir] <what> [agents]\n  <what>: %s\n", lab.WATCHABLE)
		os.exit(2)
	}
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
	rl.InitWindow(1400, 860, strings.clone_to_cstring(fmt.tprintf("watcher: %s", w.title)))
	rl.SetExitKey(.KEY_NULL)           // Escape lets go of the selection; q quits
	rl.SetTargetFPS(60)

	theme := view.theme_make()
	for agent in ([?]string{"worker", "smith", "agent_a", "agent_b"}) {
		view.theme_set(&theme, agent, {'@', {240, 220, 120, 255}, theme.background})
	}
	world := w.world
	levels := lab.world_levels(world)
	v := view.viewer_make({f32(lab.world_tiles_wide(world)) / 2, f32(lab.world_tiles_high(world)) / 2}, 0,
	                      {0, levels - 1})
	v.selected = u64(w.follow)
	follow := false                    // f follows the one selected

	speeds := SPEEDS
	speed := 2                         // 1 world second a second
	paused := false
	clock := f64(lab.world_time(world).ms)   // the viewer's clock: world ms
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
		if rl.IsKeyPressed(.TAB) && len(w.ids) > 0 {
			next := 0
			for id, i in w.ids do if u64(id) == v.selected do next = (i + 1) % len(w.ids)
			v.selected = u64(w.ids[next])
		}
		if rl.IsKeyPressed(.PERIOD) && !shift {
			paused = true
			lab.watcher_step(&w)
			clock = f64(lab.world_time(world).ms)
		}
		if !paused {
			clock += dt * 1000 * speeds[speed]
			behind = !lab.watcher_step_until(&w, i64(clock), BUDGET_NS)
			// a world slower than the clock falls behind by a quarter second at most
			clock = min(clock, f64(lab.world_time(world).ms) + 250 * speeds[speed])
		}

		if follow && v.selected != 0 {
			if x, y, z, ok := lab.watcher_tile_of(&w, lab.Entity_ID(v.selected)); ok {
				v.centre, v.focus = {f32(x), f32(y)}, z
			}
		}
		scene := lab.scene_truth(world, view.viewer_extent(&v), seq, context.temp_allocator)
		seq += 1
		if view.viewer_input(&v, scene) do follow = false

		/* nothing happens between boundaries: caught up, the world stands as
		 * it will until the next, at the clock's time */
		now := lab.world_time(world).ms
		if !behind do now = max(now, i64(clock))
		header := [?]string {
			fmt.tprintf("%s   day %d  %02d:%02d:%02d   boundary %d", w.title, now / 86_400_000 + 1,
			            now / 3_600_000 % 24, now / 60_000 % 60, now / 1000 % 60, lab.world_boundary(world)),
			fmt.tprintf("x%v%s%s   level %d", speeds[speed], "   paused" if paused else "",
			            "   (behind)" if behind && !paused else "", v.focus),
		}
		panel := make([dynamic]string, context.temp_allocator)
		if v.selected != 0 {
			if follow do append(&panel, "following")
			for line in lab.watcher_describe(&w, lab.Entity_ID(v.selected)) do append(&panel, line)
		} else {
			append(&panel, "Nothing selected.")
			for line in HELP do append(&panel, line)
		}

		rl.BeginDrawing()
		view.viewer_draw(&v, scene, &theme, header[:], panel[:])
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

	rl.CloseWindow()
	view.theme_free(&theme)
	delete(w.ids)
	delete(w.title)
	lab.pool_drain()
	lab.free_released_content()
}
