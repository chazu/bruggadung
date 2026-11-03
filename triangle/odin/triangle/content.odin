package triangle

// What objc/BGContent.m gives the Objective-C systems, for Odin's: loading a
// content build from Odin strings, and Triangle's text results as Odin
// strings. Everything else the systems call directly: a constant string
// converts to a cstring as it is, and any other is cloned to one in the
// temporary allocator (to_c).

import "core:c"
import "core:c/libc"
import "core:slice"
import "core:strings"

// A content build from files, in the order given. On failure, nil and every
// diagnostic, a line each; the caller frees either.
load_files :: proc(paths: []string, allocator := context.allocator) -> (content: ^Content, err: string) {
	cpaths := make([]cstring, len(paths), context.temp_allocator)
	for p, i in paths do cpaths[i] = to_c(p)
	return finish(content_load(raw_data(cpaths), c.size_t(len(cpaths))), allocator)
}

// A content build from sources by name (the names are for diagnostics),
// loaded in the names' order.
load_sources :: proc(sources: map[string]string, allocator := context.allocator) -> (content: ^Content, err: string) {
	names := make([dynamic]string, 0, len(sources), context.temp_allocator)
	for name in sources do append(&names, name)
	slice.sort(names[:])
	cn := make([]cstring, len(names), context.temp_allocator)
	cs := make([]cstring, len(names), context.temp_allocator)
	for name, i in names {
		cn[i] = to_c(name)
		cs[i] = to_c(sources[name])
	}
	return finish(content_load_strings(raw_data(cn), raw_data(cs), c.size_t(len(names))), allocator)
}

@(private)
finish :: proc(content: ^Content, allocator := context.allocator) -> (^Content, string) {
	if content_ok(content) != 0 do return content, ""
	d := diagnostics(content, context.temp_allocator)
	msg := strings.join(d, "\n", allocator)
	content_free(content)
	return nil, msg
}

diagnostics :: proc(content: ^Content, allocator := context.allocator) -> []string {
	out := make([]string, diag_count(content), allocator)
	for &s, i in out do s = strings.clone_from_cstring(diag_message(content, c.size_t(i)), allocator)
	return out
}

// A type's name, or "" for a type the build doesn't have. The string is the
// build's: it lives as long as the build.
name_of :: proc(content: ^Content, t: Type) -> string {
	return string(type_name(content, t))
}

// The comment above a declaration, or "" (the build's string).
documentation :: proc(content: ^Content, name: string) -> string {
	return string(doc(content, to_c(name)))
}

// A structure as content would write it.
describe :: proc(content: ^Content, node: ^Node, allocator := context.allocator) -> string {
	n := print(content, node, nil, 0)
	buf := make([]u8, n + 1, allocator)
	print(content, node, raw_data(buf), n + 1)
	return string(buf[:n])
}

// An instance's spec, each value annotated with where it comes from.
inspection :: proc(content: ^Content, instance: string, allocator := context.allocator) -> string {
	ci := to_c(instance)
	n := inspect(content, ci, nil, 0)
	buf := make([]u8, n + 1, allocator)
	inspect(content, ci, raw_data(buf), n + 1)
	return string(buf[:n])
}

// The paths of an instance's variation points (the build's strings).
variation_paths :: proc(content: ^Content, instance: string, allocator := context.allocator) -> []string {
	ci := to_c(instance)
	out := make([]string, spec_variation_count(content, ci), allocator)
	for &s, i in out do s = string(spec_variation_path(content, ci, c.size_t(i)))
	return out
}

// The notes on an instance's spec (the build's strings).
notes :: proc(content: ^Content, instance: string, allocator := context.allocator) -> []string {
	ci := to_c(instance)
	out := make([]string, spec_note_count(content, ci), allocator)
	for &s, i in out do s = string(spec_note(content, ci, c.size_t(i)))
	return out
}

// Matches a description against every variant of an instance, with the
// residuals: the paths that leave it unknown.
match_with_residuals :: proc(content: ^Content, instance: string, description: ^Node,
                             allocator := context.allocator) -> (m: Match, residuals: []string) {
	r: Match_Result
	m = match_instance(content, to_c(instance), description, &r)
	residuals = make([]string, r.nresidual, allocator)
	for &s, i in residuals do s = strings.clone_from_cstring(cstring(&r.residual[i][0]), allocator)
	return
}

// An Odin string as a C string, in the temporary allocator.
to_c :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

// A saved description (save), as an Odin string in the allocator.
saved :: proc(content: ^Content, node: ^Node, by_id: bool, allocator := context.allocator) -> string {
	p := save(content, node, c.int(by_id))
	defer libc.free(p)
	return strings.clone_from_cstring(cstring(p), allocator)
}
