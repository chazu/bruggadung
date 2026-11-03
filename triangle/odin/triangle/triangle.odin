/*
Package triangle is the Odin face of Triangle, the content language: the C
library's declarations (include/triangle.h, without the tri_ prefix) and, in
content.odin, the procedures the systems call with Odin strings.

The library is the game's build (no TDL front end), compiled by
`make -C triangle odin-lib` into build/<platform>/: an ar archive on the Mac
and Linux, a COFF library built for the MSVC ABI on Windows, which is the
only one Odin links with there.
*/
package triangle

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "../../build/windows/triangle.lib"
} else when ODIN_OS == .Darwin {
	foreign import lib "../../build/darwin/libtriangle.a"
} else {
	foreign import lib "../../build/linux/libtriangle.a"
}

Content :: struct {}
Node :: struct {}
Arena :: struct {}
Quick_Check :: struct {}
Index :: struct {}
Type :: u32

BOTTOM :: Type(0xFFFFFFFF)

Mark :: struct {
	chunk: rawptr,
	used:  c.size_t,
}

Stats :: struct {
	parse_ms, hierarchy_ms, expansion_ms, instances_ms:   f64,
	types, glb_types, leaf_types, features, instances:    c.size_t,
	spec_bytes, load_bytes:                               c.size_t,
}

Decl_Kind :: enum c.int {
	Type,
	Atom,
	Instance,
}

Decl :: struct {
	name:      cstring,
	kind:      Decl_Kind,
	package_:  cstring, // nil in the root
	file:      cstring,
	line, col: c.int,
	doc:       cstring,
}

Failure :: struct {
	path:  [256]u8,
	left:  [128]u8,
	right: [128]u8,
}

Match :: enum c.int {
	Entailed,
	Unknown,
	Incompatible,
}

MAX_RESIDUAL :: 16

Match_Result :: struct {
	result:    Match,
	nresidual: c.size_t,
	residual:  [MAX_RESIDUAL][128]u8,
	failure:   Failure, // set when incompatible
}

Masses :: struct {
	entailed, unknown, incompatible: u32,
	nresidual:                       c.size_t,
	residual:                        [MAX_RESIDUAL][128]u8,
}

Fn :: #type proc "c" (ctx: rawptr, content: ^Content, owner: ^Node, lo, hi: ^i64) -> c.int

@(default_calling_convention = "c", link_prefix = "tri_")
foreign lib {
	// arenas
	arena_new     :: proc() -> ^Arena ---
	arena_free    :: proc(arena: ^Arena) ---
	arena_mark    :: proc(arena: ^Arena) -> Mark ---
	arena_release :: proc(arena: ^Arena, mark: Mark) ---
	arena_bytes   :: proc(arena: ^Arena) -> c.size_t ---

	// loading
	content_load         :: proc(paths: [^]cstring, n: c.size_t) -> ^Content ---
	content_load_strings :: proc(names, sources: [^]cstring, n: c.size_t) -> ^Content ---
	content_free         :: proc(content: ^Content) ---
	content_stats        :: proc(content: ^Content, stats: ^Stats) ---
	instance_count       :: proc(content: ^Content) -> c.size_t ---
	instance_name        :: proc(content: ^Content, i: c.size_t) -> cstring ---
	instance_status      :: proc(content: ^Content, i: c.size_t) -> cstring ---
	content_ok           :: proc(content: ^Content) -> c.int ---
	content_hash         :: proc(content: ^Content) -> u64 ---
	log_count            :: proc(content: ^Content) -> c.size_t ---
	log_message          :: proc(content: ^Content, i: c.size_t) -> cstring ---
	diag_count           :: proc(content: ^Content) -> c.size_t ---
	diag_message         :: proc(content: ^Content, i: c.size_t) -> cstring ---
	diag_is_error        :: proc(content: ^Content, i: c.size_t) -> c.int ---
	diag_location        :: proc(content: ^Content, i: c.size_t, file: ^cstring, line, col: ^c.int) -> c.int ---
	diag_text            :: proc(content: ^Content, i: c.size_t) -> cstring ---
	decl_count           :: proc(content: ^Content) -> c.size_t ---
	decl                 :: proc(content: ^Content, i: c.size_t, out: ^Decl) -> c.int ---
	doc                  :: proc(content: ^Content, name: cstring) -> cstring ---

	// types
	type_count            :: proc(content: ^Content) -> c.size_t ---
	type_named            :: proc(content: ^Content, name: cstring) -> Type ---
	type_name             :: proc(content: ^Content, t: Type) -> cstring ---
	meet                  :: proc(content: ^Content, a, b: Type) -> Type ---
	subtype               :: proc(content: ^Content, a, b: Type) -> c.int ---
	primary_parent        :: proc(content: ^Content, t: Type) -> Type ---
	type_feature_count    :: proc(content: ^Content, t: Type) -> c.size_t ---
	type_feature          :: proc(content: ^Content, t: Type, i: c.size_t) -> cstring ---
	function_count        :: proc() -> c.size_t ---
	function              :: proc(i: c.size_t, signature: ^cstring) -> cstring ---
	component_count       :: proc(content: ^Content) -> c.size_t ---
	component_name        :: proc(content: ^Content, i: c.size_t) -> cstring ---
	component_type        :: proc(content: ^Content, i: c.size_t) -> Type ---
	type_components       :: proc(content: ^Content, t: Type, out: [^]c.size_t, max: c.size_t) -> c.size_t ---
	component_field_count :: proc(content: ^Content, i: c.size_t) -> c.size_t ---
	component_field       :: proc(content: ^Content, i, j: c.size_t, flags: ^cstring) -> cstring ---

	// feature structures
	node_type     :: proc(node: ^Node) -> Type ---
	node_interval :: proc(node: ^Node, lo, hi: ^i64) -> c.int ---
	at            :: proc(content: ^Content, node: ^Node, path: cstring) -> ^Node ---
	print         :: proc(content: ^Content, node: ^Node, buf: [^]u8, buflen: c.size_t) -> c.size_t ---
	text          :: proc(content: ^Content, node: ^Node, buf: [^]u8, buflen: c.size_t) -> c.size_t ---
	value         :: proc(content: ^Content, expr: cstring, out: ^Arena, err: [^]u8, errlen: c.size_t) -> ^Node ---
	unify         :: proc(content: ^Content, a, b: ^Node, out: ^Arena, failure: ^Failure) -> ^Node ---
	subsumes      :: proc(content: ^Content, a, b: ^Node, forward, backward: ^c.int) ---
	@(link_name = "tri_copy")
	copy_node     :: proc(content: ^Content, node: ^Node, out: ^Arena) -> ^Node ---
	conflicts     :: proc(content: ^Content, a, b: ^Node, paths: [^][256]u8, max: c.size_t) -> c.size_t ---
	lgg           :: proc(content: ^Content, a, b: ^Node, out: ^Arena) -> ^Node ---
	generalize    :: proc(content: ^Content, node: ^Node, path: cstring, steps: c.int, out: ^Arena) -> ^Node ---
	node_count    :: proc(node: ^Node) -> c.size_t ---

	// instances
	pattern                 :: proc(content: ^Content, instance: cstring) -> ^Node ---
	pattern_variant_count   :: proc(content: ^Content, instance: cstring) -> c.size_t ---
	pattern_variant         :: proc(content: ^Content, instance: cstring, i: c.size_t) -> ^Node ---
	spec                    :: proc(content: ^Content, instance: cstring) -> ^Node ---
	spec_variation_count    :: proc(content: ^Content, instance: cstring) -> c.size_t ---
	spec_variation_path     :: proc(content: ^Content, instance: cstring, i: c.size_t) -> cstring ---
	spec_note_count         :: proc(content: ^Content, instance: cstring) -> c.size_t ---
	spec_note               :: proc(content: ^Content, instance: cstring, i: c.size_t) -> cstring ---
	inspect                 :: proc(content: ^Content, instance: cstring, buf: [^]u8, buflen: c.size_t) -> c.size_t ---
	register_fn             :: proc(content: ^Content, name: cstring, fn: Fn, ctx: rawptr) ---
	derive                  :: proc(content: ^Content, node: ^Node, out: ^Arena, failure: ^Failure) -> ^Node ---
	construct               :: proc(content: ^Content, instance: cstring, seed: u64, out: ^Arena) -> ^Node ---

	// matching
	match            :: proc(content: ^Content, pattern, description: ^Node, result: ^Match_Result) -> Match ---
	match_instance   :: proc(content: ^Content, instance: cstring, description: ^Node, result: ^Match_Result) -> Match ---
	binding          :: proc(content: ^Content, instance, tag: cstring, description: ^Node) -> ^Node ---
	match_hypotheses :: proc(content: ^Content, pattern: ^Node, descriptions: [^]^Node, credences: [^]u32, n: c.size_t) -> Masses ---
	explain          :: proc(content: ^Content, pattern, description: ^Node, buf: [^]u8, buflen: c.size_t) -> c.size_t ---
	explain_instance :: proc(content: ^Content, instance: cstring, description: ^Node, buf: [^]u8, buflen: c.size_t) -> c.size_t ---

	// quick check and pattern indexes
	qc_new            :: proc(content: ^Content, paths: [^]cstring, n: c.size_t) -> ^Quick_Check ---
	qc_from_failures  :: proc(content: ^Content, failures: [^]cstring, n, k: c.size_t) -> ^Quick_Check ---
	qc_free           :: proc(qc: ^Quick_Check) ---
	qc_size           :: proc(qc: ^Quick_Check) -> c.size_t ---
	qc_path           :: proc(qc: ^Quick_Check, i: c.size_t) -> cstring ---
	qc_vector         :: proc(qc: ^Quick_Check, node: ^Node, out: [^]Type) ---
	qc_compatible     :: proc(qc: ^Quick_Check, a, b: [^]Type) -> c.int ---
	index_new         :: proc(qc: ^Quick_Check) -> ^Index ---
	index_add         :: proc(index: ^Index, pattern: ^Node, tag: rawptr) ---
	index_count       :: proc(index: ^Index) -> c.size_t ---
	index_candidates  :: proc(index: ^Index, description: ^Node, out: [^]c.size_t, max: c.size_t) -> c.size_t ---
	index_pattern     :: proc(index: ^Index, i: c.size_t) -> ^Node ---
	index_tag         :: proc(index: ^Index, i: c.size_t) -> rawptr ---
	index_free        :: proc(index: ^Index) ---

	// definite clauses
	solve :: proc(content: ^Content, query: ^Node, depth_limit: c.size_t, solutions: [^]^Node, max: c.size_t, out: ^Arena, truncated: ^c.int) -> c.size_t ---

	// families
	family_count             :: proc(content: ^Content) -> c.size_t ---
	family_name              :: proc(content: ^Content, i: c.size_t) -> cstring ---
	family_index             :: proc(content: ^Content, family: cstring) -> ^Index ---
	record_failures          :: proc(content: ^Content, on: c.int) ---
	family_suggest_quickcheck :: proc(content: ^Content, family: cstring, k: c.size_t, buf: [^]u8, buflen: c.size_t) -> c.size_t ---

	// code generation
	component_header :: proc(content: ^Content, prefix: cstring, buf: [^]u8, buflen: c.size_t) -> c.size_t ---
	format_quantity  :: proc(kind: cstring, quanta: i64, buf: [^]u8, buflen: c.size_t) -> c.size_t ---

	// moving descriptions between content builds, and saves
	migrate :: proc(from, to: ^Content, node: ^Node, out: ^Arena, err: [^]u8, errlen: c.size_t) -> ^Node ---
	save    :: proc(content: ^Content, node: ^Node, by_id: c.int) -> [^]u8 --- // malloc'd: free with libc.free
	restore :: proc(content: ^Content, text: cstring, out: ^Arena, err: [^]u8, errlen: c.size_t) -> ^Node ---
}
