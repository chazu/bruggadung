package lab

// Loading the content build: every .tri file under the content root, its
// topic directories' too, skipping names that start with a dot, in byte
// order of their paths (src/test/BGTest.m's BGLoadContent, which this
// replaces). The content hash depends on that order, so every platform must
// give the same paths.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"

content_dir := "content"

load_content :: proc() -> ^tri.Content {
	paths: [dynamic]string
	defer {
		for p in paths do delete(p)
		delete(paths)
	}
	if !collect_tri(content_dir, &paths) do return nil
	slice.sort(paths[:])
	content, err := tri.load_files(paths[:])
	if content == nil {
		fmt.eprintf("lab: the content does not load:\n%s\n", err)
		delete(err)
	}
	return content
}

// Paths are joined with '/' on every platform, Windows too, so that they
// sort, and name diagnostics, the same everywhere.
@(private = "file")
collect_tri :: proc(dir: string, paths: ^[dynamic]string) -> bool {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		fmt.eprintf("lab: cannot open the content directory %s\n", dir)
		return false
	}
	ok := true
	for e in entries {
		if strings.has_prefix(e.name, ".") do continue
		path := strings.concatenate({dir, "/", e.name})
		if e.type == .Directory {
			ok &= collect_tri(path, paths)
			delete(path)
		} else if len(e.name) >= 5 && strings.has_suffix(e.name, ".tri") {
			append(paths, path)
		} else {
			delete(path)
		}
	}
	return ok
}
