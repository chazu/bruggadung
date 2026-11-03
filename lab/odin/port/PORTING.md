# Porting the lab to Odin

The Objective-C lab (`lab/src`) is being ported to Odin, here in `lab/odin`.
This is how. Everyone porting a module follows it, so that modules ported
apart compile together and behave as the Objective-C did.

**The goal is the same program**, not a better one. Every scenario must end
in the same state and print the same text (`lab/ci/scenario-hashes.txt`
compares the hashes), and every test must check what it checked. Port
literally: the same algorithms, the same order of operations, the same loops,
the same integer arithmetic, the same comments (they are the design
record). Odin syntax, Objective-C semantics. Cleaning up comes after the
port passes, not during it.

## Layout

- One package, `lab`, in `lab/odin/`: Odin forbids import cycles between
  packages, and the lab's modules import each other in a cycle. Every name
  is visible across files, as it was in Objective-C.
- One `.odin` file for each `.m`, named for its directory and class:
  `core/BGWorld.m` → `core_world.odin`, `act/BGActions.m` →
  `act_actions.odin`, `test/BGTests.m` → `test_tests_<part>.odin`. A
  header's declarations (its typedefs, constants, inline functions) go at
  the top of the file for its `.m`.
- Already here, shared by all: `types.odin` (BGTypes.h), `object.odin`
  (reference counts and autorelease pools), `foundation.odin` (Foundation's
  behaviour where Odin's differs), `protocols.odin` (every protocol), and
  `components.odin` (generated from content by `make gen`: the component
  records and the field registry, BGComponents.h's). Don't change them
  without saying so in your report; ask for what they lack.
- Triangle is imported as `import tri "../../triangle/odin/triangle"`:
  `triangle.odin` there is the C API without the `tri_` prefix
  (`tri.content_hash(c)`, `tri.unify(...)`), `content.odin` the helpers
  BGContent.m had.

## Names

**`port/NAMES.md` is authoritative** for everything declared in a header:
classes, methods, protocols, functions, types, enum members and constants.
Look names up there; don't derive them. It is generated (`port/names.py`).

- A class's methods are procedures taking the object first:
  `[world kindNamed:"Body"]` → `world_kind_named(world, "Body")`.
- A class method: `[BGWorld worldWithContent:c seed:s error:&e]` →
  `world_with_content(c, s, &e)`.
- Its parameter types in NAMES.md are a first guess. The module that
  implements a method settles its exact signature (a `^T` out array becomes
  `[^]T`, an NSArray `[]Some_Type`), and says so in a comment if it differs
  from NAMES.md's. Callers follow the header's meaning.
- What a `.m` declares for itself only (static functions, private methods,
  file-level variables) is `@(private = "file")`, named by the same rules.
- Struct fields keep their C names (`loc.place`, `rec.burnRate`,
  `info.blueprint`). An instance variable drops its underscore:
  `_world` → `world`.
- Component records are the generated types, BG dropped, in Ada_Case:
  `BGFuelContainer` → `Fuel_Container`, `BGGasStore` → `Gas_Store`; their
  enum constants drop BG_: `BG_COLOUR_BEIGE` → `COLOUR_BEIGE`;
  `BG_CONTENT_HASH` → `CONTENT_HASH`; `BG_VALUE_TEXT` → `VALUE_TEXT`;
  `BGComponents` → `COMPONENTS`; `BGFieldInfo` → `Field_Info`.
- A name that is an Odin keyword or builtin takes a trailing underscore
  (`BGIn` → `in_`, a parameter `max` → `max_`).

## Types

| Objective-C / C | Odin |
| --- | --- |
| `BGEntityID`, `uint64_t`, `int64_t`, `uint32_t`, ... | `Entity_ID`, `u64`, `i64`, `u32`, ... |
| `NSUInteger`, `size_t` / `NSInteger` / `int` | `uint` / `int` / `i32` |
| `BOOL`, `YES`, `NO` | `bool`, `true`, `false` |
| `NSNotFound` | `NOT_FOUND` |
| `const char *` (C strings: interned names, content, records' text) | `cstring` |
| `NSString *` | `string` |
| `NSMutableString *` | `strings.Builder` (see Strings) |
| `NSArray *` of strings / of numbers / of objects | `[]string` / `[]u64` (the type the numbers had) / `[]^Class` |
| `NSMutableArray *` | `[dynamic]T` |
| `NSMutableDictionary *` keyed by strings or numbers | `map[string]T`, `map[u64]T` |
| `NSNumber` | the number it boxed |
| `id <BGProtocol>` | the protocol's struct (`Domain`, `Reactor`, ...) |
| `BGWorld *` | `^World` |
| `TriNode *`, `TriContent *`, `TriArena *`, `TriType` | `^tri.Node`, `^tri.Content`, `^tri.Arena`, `tri.Type` |
| `BGContent *` | `^tri.Content` (see Triangle) |
| `void *`, `const void *` | `rawptr` |
| `T *out` filled up to `max` | `[^]T` |
| `malloc`'d array returned with a count | `[^]T`, freed with `free(p)` by the caller, as before |
| C arrays in structs `char role[16]` | `[16]u8` |
| `enum { BGLocationNone, BGLocationOnTile }` | `Location_Form{.None, .On_Tile}` (NAMES.md) |
| `typedef struct {...} BGHorizon` | `Horizon :: struct {...}`, fields as named |

C's `malloc`, `calloc`, `realloc`, `free`, `memcpy`, `memset`, `memmove`,
`memcmp`, `qsort` and `bsearch` are fine to keep as Odin's `mem.alloc`,
`mem.resize`, `free`, `mem.copy`, `mem.set`, `mem.zero`, `mem.compare`,
`slice.sort_by`. A qsort comparator that orders ties fully keeps doing so
(determinism). Pointer arithmetic: `[^]T` indexing, or `mem.ptr_offset`.

Integer arithmetic must stay exactly C's: the same widths, the same
truncating division (Odin's `/` and `%` on integers truncate, as C's do),
the same wrapping of unsigned values. Mind implicit conversions C did that
Odin won't: cast where C converted, to the type C converted to. Floating
point, where the lab has it, the same operations in the same order.

## Classes

An `@interface` becomes a struct whose first field is `using object:
Object`, then the instance variables (underscore dropped):

```odin
Committer :: struct {
	using object: Object,
	untraced:  bool,
	world:     ^World,
	submitted: [dynamic]^Proposal_Group,
	...
}
```

- `[[BGCommitter alloc] initWithWorld:w]` → `committer_init_with_world(w)`,
  which makes it with `object_new(Committer, committer_dealloc)` and returns
  it with a count of 1. `[BGFoo new]` → `foo_new()`.
- `-dealloc` → `foo_dealloc :: proc(self: ^Foo)`: releases and frees what
  the object holds, not the object itself (release frees that after).
- `retain`, `release`, `autorelease` → `retain(x)`, `release(x)`,
  `autorelease(x)`, exactly where the Objective-C sent them. Convenience
  constructors that returned autoreleased objects do the same
  (`return autorelease(x)`).
- A class conforming to a protocol has `foo_as_<protocol>(self) ->
  Protocol` filling the protocol struct (`atmosphere_as_domain`). A method
  that takes `id <Proto>` and retains it does `object_retain(p.data)`; one
  that doesn't retain (a comment says "not retained") doesn't.
- Inheritance: the lab's classes subclass only NSObject. `super` calls are
  NSObject's: drop them.
- `[self foo]` → `foo_bar(self)`. `self` is a parameter named as you like.
- `nil` messages: sending to nil did nothing and returned 0. Where the
  Objective-C relied on that, test for nil.

## Protocols

`protocols.odin` has every protocol as a struct of procedures, `data:
rawptr` first. Call through them: `d.horizon_at(d.data, t)`. A missing
optional method, or a non-coupled domain, is a nil procedure:
`conformsToProtocol:@protocol(BGCoupledDomain)` → `d.publish_into != nil`,
`respondsToSelector:@selector(nextForgetting)` → `p.next_forgetting != nil`.
A conformer's procedures cast `data` back: `(^Atmosphere)(data)`.

## Memory

- Objects: reference counts, as before (object.odin). Translate every
  retain, release and autorelease. Don't decide ownership afresh.
- An instance variable that held a retained object releases it in dealloc;
  an NSArray of objects in an instance variable retained each it held:
  `append(&self.groups, retain(g))`, and release each when removed and in
  dealloc.
- Autoreleased values that aren't objects (strings, arrays) are allocated in
  `context.temp_allocator`: they live until the pool around them drains (a
  test, or main), as they did. Anything kept beyond that (an instance
  variable, a global) is cloned into `context.allocator` and freed in
  dealloc: `self.name = strings.clone(name)`.
- Never store a temp-allocated string or slice in an object: clone it.
- C memory (`malloc`'d buffers, `free`) stays as it was.

## Strings

- `[NSString stringWithFormat:@"...", ...]` → `fmt.tprintf("...", ...)`.
  `appendFormat:` → `fmt.sbprintf(&b, ...)`; `appendString:` →
  `strings.write_string(&b, s)`; an NSMutableString made with `[NSMutableString
  string]` is `strings.builder_make(context.temp_allocator)`, and its value
  `strings.to_string(b)`.
- `printf(...)` → `fmt.printf(...)`; `fprintf(stderr, ...)` →
  `fmt.eprintf(...)`; `puts`/`fputs` likewise. Output must be byte for byte
  what it was.
- **Formats.** Odin's fmt is not printf. Change each format so it prints
  what printf printed:
  - `%d %i %u %ld %lu %lld %llu %zu %hd` → `%d`; `%x %llx` → `%x`;
    `%c` → `%c` with a `rune(x)`; `%s` of a C string or an Odin string →
    `%s`; `%@` of an NSString → `%s`; `%%` → `%%`; `%f %.1f %+d` stay.
  - **A width on a number pads with zeros in Odin unless the format has the
    space flag**: printf's `%10d` is Odin's `% 10d`, `%5.1f` is `% 5.1f`,
    `%2x` is `% 2x`. A `0` flag (`%016llx` → `%016x`, `%02x`) means zeros
    in both. `%-10d` agrees. Strings pad with spaces either way (`%-14s`,
    `%15s` stay).
  - printf's own space flag (`% d`) has no Odin form; the lab doesn't use
    it.
  - `%.*s` (a length and a pointer) → `%s` of the string sliced to it;
    `%*s` stays (`%*s` with the width, then the string).
  - The spike checks the rule against libc (`make -C lab odin-spike`).
- NSString methods: `length` → `len(s)`; `isEqualToString:` → `==`;
  `hasPrefix:`/`hasSuffix:` → `ns_has_prefix`/`ns_has_suffix` (they say NO
  for an empty affix); `rangeOfString:` → `ns_range_of` or `ns_contains`;
  `componentsSeparatedByString:` → `ns_components_separated`;
  `componentsJoinedByString:` → `strings.join(parts, sep,
  context.temp_allocator)`; `substringFromIndex:` → `s[i:]`;
  `substringToIndex:` → `s[:i]`; `substringWithRange:` → `s[loc:][:len]`;
  `stringByAppendingString:` → `strings.concatenate({a, b},
  context.temp_allocator)`; `stringByReplacingOccurrencesOfString:` →
  `ns_replace`; `longLongValue`/`intValue`/`unsignedLongLongValue` →
  `ns_long_long_value`/`ns_int_value`/`ns_unsigned_long_long_value`;
  `compare:` → `ns_compare`; trimming whitespace → `ns_trim_whitespace`;
  `UTF8String` → `ns_utf8(s)` (or the cstring itself, if it was one);
  `stringWithUTF8String:` → `ns_string(cs)` (or `string(cs)`), cloned if
  kept.
- A C string from Odin: a literal converts as it is; anything else
  `ns_utf8(s)` or `strings.clone_to_cstring`. A C string to Odin:
  `string(cs)`.

## Arrays and dictionaries

- `[NSMutableArray array]` → `make([dynamic]T, context.temp_allocator)` if
  it is autoreleased and dropped, `make([dynamic]T)` (freed in dealloc) if
  kept. `count` → `len`; `objectAtIndex:` → `a[i]`; `addObject:` →
  `append`; `insertObject:atIndex:` → `inject_at`; `removeObjectAtIndex:` →
  `ordered_remove`; `removeAllObjects` → `clear`; `lastObject` → `a[len(a)
  - 1]` if any, else nil; `containsObject:`/`indexOfObject:` by `==` for
  strings and numbers, by pointer for objects (`isEqual:` on them was
  NSObject's: identity); `subarrayWithRange:` → `a[loc:][:len]`;
  `sortedArrayUsingSelector:@selector(compare:)` → sort a copy with
  `ns_compare`.
- Dictionaries: Odin's map iterates in no fixed order. Where the
  Objective-C iterated a dictionary (`allKeys`, `objectEnumerator`) and the
  order could reach output or state, sort the keys; where it couldn't,
  say so in a comment.

## Triangle

`BGContent` and `BGSpec` are gone: use Triangle's Odin package.

- `[content content]` (the TriContent) → the `^tri.Content` itself.
- `[BGContent contentFromFiles:paths error:&e]` →
  `tri.load_files(paths)` (returns the content and the diagnostics joined).
- `contentHash` → `tri.content_hash(c)`; `typeNamed:` →
  `tri.type_named(c, name)`; `nameOfType:` → `tri.name_of(c, t)`;
  `documentationFor:` → `tri.documentation(c, name)`; `patternNamed:` →
  `tri.pattern(c, name)`; `indexForFamily:` → `tri.family_index(c, name)`;
  `match:against:residuals:` → `tri.match_with_residuals(c, name, d)`;
  `describe:` → `tri.describe(c, node, context.temp_allocator)`;
  `diagnostics` → `tri.diagnostics(c, context.temp_allocator)`.
- `specNamed:` (nil if none) → `tri.spec(c, name) != nil`, and the BGSpec's
  methods → `tri.spec(c, name)` (its node), `tri.variation_paths`,
  `tri.notes`, `tri.inspection`, `tri.construct(c, name, seed, arena)`.
- The C API's `const char *` parameters take a cstring: a literal as it is,
  `ns_utf8(s)` otherwise.
- A content build is not an object: no counts. Whoever loads one frees it
  with `tri.content_free` when everything using it is done (main, the test
  runner's shared content at the end of the run). A world doesn't own its
  content; where the Objective-C retained or released a BGContent, do
  nothing.

## Tests

The lab's tests keep their own runner (`lab test [name]`, test/BGTest.m),
ported as it is: a test is a procedure in the `TESTS` table, and
`BG_CHECK(cond)` → `bg_check(cond)`, which counts and reports as
BGTestCheck did, with the expression's text (`#caller_expression`) and the
caller's file and line.

## Checking your module

The package compiles only when every module is there, so while you port:

```sh
cd lab/odin && odin check . -no-entry-point -vet -strict-style 2>&1 | grep '<your_file>.odin'
```

Errors in your files that name another module's procedures or types (not
yet ported) are expected; fix every other error in your files: syntax,
types, your own names. Don't edit other modules' files. If you need
something from a shared file (types.odin, protocols.odin, foundation.odin,
object.odin), or find NAMES.md wrong, say so in your report rather than
working around it.

## Reporting

End with: the files you wrote; each signature you settled that differs
from NAMES.md's guess (so callers can follow); anything left unported or
uncertain, marked in the code with `// PORT:` and a reason; and what you
need from the shared files.
