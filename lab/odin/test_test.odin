package lab

/*
 * The laboratory's test runner: `lab test` runs every registered test and
 * exits non-zero if any check fails.
 *
 * (src/test/BGTest.h and BGTest.m.)
 */

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


Test_Function :: proc()

Test_Case :: struct {
	name:     cstring,
	function: Test_Function,
}


content_dir := "content"

@(private = "file") checks: i32
@(private = "file") failures: i32
@(private = "file") shared_content: ^tri.Content      /* loaded once per run, released at the end */
// Content let go of by release_shared_content_after_use, which the worlds
// on it still use: freed by free_released_content, once they are gone (a
// content build is not counted: PORTING.md, Triangle).
@(private = "file") released_content: [dynamic]^tri.Content


// Settled: ok is a bool (BGTestCheck's int), what and file Odin strings.
test_check :: proc(ok: bool, what: string, file: string, line: i32) {
	base: string

	checks += 1
	if ok do return
	failures += 1
	slash := strings.last_index_byte(file, '/')
	base = file[slash + 1:] if slash >= 0 else file
	fmt.eprintf("    %s:%d: failed: %s\n", base, line, what)
}

// BG_CHECK( cond): the expression's text, and the caller's file and line.
bg_check :: proc(cond: bool, expr := #caller_expression(cond), loc := #caller_location) {
	test_check(cond, expr, loc.file_path, loc.line)
}


/* Every *.tri under `dir`, its topic directories' too (content/README.md),
 * added to `names` as paths from the content directory. A name starting
 * with a dot is passed over, as the triangle tool does. */
//
// Paths are joined with '/' on every platform, Windows too, so that they
// sort, and name diagnostics, the same everywhere (the spike's approach,
// spike/content.odin).
@(private = "file")
collect_tri :: proc(dir: string, names: ^[dynamic]string) -> bool {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		fmt.eprintf("lab: cannot open the content directory %s\n", dir)
		return false
	}
	ok := true
	for ent in entries {
		if strings.has_prefix(ent.name, ".") do continue
		path := strings.concatenate({dir, "/", ent.name})
		if ent.type == .Directory {
			ok &= collect_tri(path, names)
			delete(path)
			continue
		}
		if len(ent.name) < 5 || !strings.has_suffix(ent.name, ".tri") {
			delete(path)
			continue
		}
		append(names, path)
	}
	return ok
}


/* The content in content_dir (every *.tri, its topic directories' too, in
 * path order), or nil with the diagnostics printed. */
load_content :: proc() -> ^tri.Content {
	content: ^tri.Content
	names:   [dynamic]string
	error:   string

	defer {
		for name in names do delete(name)
		delete(names)
	}
	if !collect_tri(content_dir, &names) do return nil
	slice.sort(names[:])            // strcmp's order: bytes
	content, error = tri.load_files(names[:])
	if content == nil {
		fmt.eprintf("lab: the content does not load:\n%s\n", error)
		delete(error)
	}
	return content
}


/* A fresh world on that content, with a committer that has the kinds'
 * reactors. */
test_world :: proc(seed: u64) -> ^World {
	world: ^World
	error: string

	if shared_content == nil do shared_content = load_content()
	if shared_content == nil do return nil
	error = ""
	world = world_with_content(shared_content, seed, &error)
	if world == nil do fmt.eprintf("lab: %s\n", error)
	return world
}


/* The shared content stays alive while the worlds holding it do; this drops
 * the runner's own reference, so leak checks come out clean. */
//
// Worlds don't own their content in the port, so it is kept aside, and
// freed by free_released_content when the worlds on it are gone.
release_shared_content_after_use :: proc() {
	if shared_content != nil do append(&released_content, shared_content)
	shared_content = nil
}

// Frees the content release_shared_content_after_use let go of: call it
// once the worlds on it are gone (main, after its pool drains). Not in
// NAMES.md: what [sharedContent release] did once the last world released
// its content.
free_released_content :: proc() {
	for c in released_content do tri.content_free(c)
	delete(released_content)
	released_content = nil
}


test_committer :: proc(world: ^World) -> ^Committer {
	committer: ^Committer

	committer = autorelease(committer_init_with_world(world))
	committer_add_reactor(committer, body_kind_as_reactor(autorelease(body_kind_new())), "Body")
	committer_add_reactor(committer, valve_kind_as_reactor(autorelease(valve_kind_new())), "Valve")
	committer_add_reactor(committer, latent_kind_as_reactor(autorelease(latent_kind_new())), "Part")
	return committer
}


/* Runs the tests whose names contain `only` (all, if ""). Returns the
 * number of failed checks. */
// Settled: the tests as a slice (BGRunTests' pointer and count), `only` an
// Odin string, "" for NULL (strstr finds "" in every name anyway).
run_tests :: proc(tests: []Test_Case, only: string) -> i32 {
	run:    uint
	before: i32

	run = 0
	for i := 0; i < len(tests); i += 1 {
		if only != "" && !strings.contains(string(tests[i].name), only) do continue
		before = failures
		pool_push()
		tests[i].function()
		pool_drain()
		fmt.printf("%s %s\n", "ok  " if failures == before else "FAIL", tests[i].name)
		run += 1
	}
	fmt.printf("%d tests, %d checks, %d failed\n", run, checks, failures)
	if shared_content != nil do tri.content_free(shared_content)
	shared_content = nil
	free_released_content()
	return failures
}
