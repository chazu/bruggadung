# Triangle: the content language

## Status and scope

Proposal. This document specifies bruggadung's **content language**, named
**Triangle**: the typed feature structure (TFS) system in which blueprints, operations,
recipes, propositions, interpretation rules, methods, and consideration
curves are written. It also specifies the engine that loads that content and
matches against it at runtime. It is item 3 of "What comes next" in
[ARCHITECTURE.md](ARCHITECTURE.md), and it answers the open format questions
left by the other documents:

- blueprints and the field registry ([COMPONENTS.md](COMPONENTS.md) §2, §10)
- operation schemas, capability compatibility, and recipes
  ([ACTIONS.md](ACTIONS.md) §1, §2, §6)
- propositions, recognition, interpretation rules, and memory decay
  ([KNOWLEDGE.md](KNOWLEDGE.md) §6, §8, §9, §12)
- methods, consideration curves, and norms ([AGENCY.md](AGENCY.md) §3, §5,
  §9)

The design follows a research pass over the TFS family: LOGIN, LIFE, Emele
and Zajac's TFS, CUF, ALE and TRALE, ConTroll, ProFIT, LiLFeS, LKB/TDL with
PET and ACE, and CUE. The findings that shaped it are summarised in
[Findings from the research](#findings-from-the-research).

In one sentence: **the semantics of TDL (the DELPH-IN type description
language), the syntax of CUE, the engine techniques of PET and ACE, and the
matching discipline of LIFE**, extended with integer units, load-time
defaults, and seed-driven variation.

For writing content, start with the user documentation in
[triangle/docs/](triangle/docs/): a [guide](triangle/docs/GUIDE.md) that
builds one content file step by step, a [language
reference](triangle/docs/REFERENCE.md) with the grammar, attributes, units,
and diagnostics, and [the embedding API](triangle/docs/API.md). This document
keeps the design and the reasons for it.

Out of scope here:

- what the systems do with the content once it is loaded (their own docs)
- institutions' content: offices, permits, claims recognition (§6)
- latent assembly descriptors, beyond being referenceable from blueprints

## Decisions so far

1. **The language is called Triangle**, with files ending in `.tri`. It is not
   a clone of TDL: the syntax, units, defaults, variation, and matching are
   its own.
2. **TDL semantics with CUE-style syntax.** The type discipline is TDL's:
   named types in a hierarchy, closed and totally well-typed structures, one
   introducing type per feature. The surface is CUE's: `#Defs`, `&`, `|`,
   bounds, `*` defaults, attributes. Where the two disagree, TDL's meaning
   wins and the syntax is adjusted (the "false friends" in §2).
3. **One core, two modes.**
   - **Load mode** is full: disjunction, defaults, and type constraints are
     resolved, and blueprints become flat immutable specs.
   - **Runtime mode** is restricted: conjunctive only, no defaults, closed
     and totally well-typed. It merges descriptions and matches patterns.
4. **Types are nominal and closed.** The hierarchy is completed to a bounded
   complete partial order at load, with greatest-lower-bound (meet) types
   generated where missing. Every feature is introduced by exactly one type.
   Types marked `@component` group the features they introduce into a
   component kind, so the field registry is generated from content.
5. **Names copy; references and tags share.** A reference to a top-level
   name (a type or an instance), or to a path into one (`wrench_19.size`),
   unifies a copy of its constraints, as in CUE. Within a top-level
   definition, sharing a node between paths, so that information flows both
   ways, is written as a reference to the other field (`.instrument.size`,
   its path from the definition's root) or as a tag (`$s`). A reference is a
   tag named by its path. A `let` names an expression; each use copies it.
   *Revised:* field references and `let` were first left out (§2).
6. **No general disjunction at runtime.**
   - In types, a disjunction of atoms is an enum and becomes subtypes.
   - In blueprints, whatever a spec leaves open (alternatives or ranges) is
     **variation**: construction makes it concrete from the entity's seed.
   - Disjunction of structures is expanded at load. Nothing disjunctive
     survives into runtime structures.
7. **Defaults follow YADU and exist only at load time.** A default on a more
   specific type overrides one on a more general type, independently of
   order. Specs contain no defaults, and **patterns never use defaults**.
8. **Numbers are integers in quanta with units.** Decimal literals with unit
   suffixes convert exactly at load; a literal that is not a whole number of
   quanta is a load error. Numeric constraints are intervals, and unification
   intersects them. Arithmetic over quantities (`+ - * /` on numbers and
   tags) is a constraint on intervals, propagated forward (§5).
9. **Rules are feature structures applied by fixed engines.** Operations,
   recipes, interpretation rules, and methods are tagged structures. The
   action, knowledge, and agency systems apply them, as DELPH-IN parsers
   apply grammar rules. For recursion, such as reachability, there is a
   definite-clause layer: relations over feature structures, solved by
   resolution with a depth limit (§10).
10. **Runtime matching is three-valued.** Matching a pattern against a
   description returns **entailed**, **incompatible**, or **unknown**, with
   the tag bindings and the **residual paths** that would have to be learned.
   Against a referent with competing hypotheses, it returns the credence mass
   of each outcome.
11. **The engine is DELPH-IN's technique stack in plain C.** Feature
    structure nodes are C structs in arenas, never Objective-C objects. An
    optional TDL front end shares the internal tree, so the English Resource
    Grammar can serve as a large benchmark.
12. **Packages scope names, not features.** A package (a file, or a
    directory of them) scopes type, component, and blueprint names, and
    prefixes the C and Objective-C identifiers generated from them, so a
    component can't clash with an engine class. Feature names stay global:
    every feature is still introduced by exactly one type, so where two
    meanings truly coincide they share a supertype. This revises "Not
    adopted from CUE: ... packages" (§2).

## Terms

| Term | Meaning |
| --- | --- |
| Feature structure (FS) | A rooted graph of typed nodes. Each node has a type and one arc per feature appropriate to that type. |
| Type | A named point in the hierarchy. `#Wrench`, `"steel"`, and the built-in `length` are all types. |
| Hierarchy | The partial order of types, completed so that any two compatible types have a unique meet |
| Meet (GLB) | The most general type that is a subtype of both. Undefined (bottom) means the types are incompatible. |
| Appropriateness | Which features a type has, and the most general type allowed for each feature's value |
| Introducing type | The unique most general type that declares a feature |
| Totally well-typed | Every node has every feature its type makes appropriate. A missing value is present as the most general allowed type, which means "nothing known". |
| Unification | Combining two FSs into the most general FS more specific than both, or failing |
| Subsumption | A ⊒ B: A is more general than B, so everything A says, B says too |
| Tag | `$name`: marks paths that share one node |
| Instance | A top-level name without `#`. Blueprints are instances. Instances do not enter the hierarchy. |
| Spec | A resolved, immutable instance, ready for constructing components |
| Variation | Whatever a spec leaves open, made concrete from the seed at construction |
| Default | A value marked `*`, used only if nothing more specific decides the field |
| Pattern | An FS used for matching: an operation role, a method precondition, a rule premise |
| Description | An FS describing something: a hypothesis about a referent, or a projection of a true entity |
| Residual | The paths where a description is too general to decide a pattern |
| Primary parent | The first-listed supertype of a type. Memory decay generalises along it. |

## The content language contract

### 1. Syntax

Triangle files have the extension `.tri`. The syntax is CUE's, minus
the parts listed in §2.

| Construct | Example | Meaning |
| --- | --- | --- |
| Type definition | `#Tool: #Physical & { size: length }` | Declares type `tool` under `physical`, introducing `size` |
| Multiple parents | `#Wrench: #Tool & #Lever` | Several supertypes. The first is the primary parent. |
| Enum | `#Material: "steel" \| "brass" \| "oak"` | Three atom types under `material` |
| Instance | `wrench_19: #Wrench & { ... }` | A blueprint; not a type |
| Field | `size: 19mm` | A feature and its value constraint |
| Path shorthand | `grip: surface: "knurled"` | Same as `grip: { surface: "knurled" }` |
| Conjunction | `#Nut & { state: "loose" }` | Unification |
| Disjunction | `"steel" \| "brass"` | Enum in a type; variation in an instance |
| Tag | `size: $s` | Shared node, within one top-level definition |
| Reference | `size: .instrument.size` | Shared node with the field at that path from the definition's root |
| Path | `size: wrench_19.size`, `#Wrench.size` | A copy of another declaration's field |
| Let | `let socket = 30mm`, then `socket` | A named expression, in a file or a struct; each use copies it |
| Comprehension | `[for s in sizes if s > 12mm { s }]`, `{ for m in #Material { (m): 0 } }` | Items or fields made from data known at load, expanded before anything else sees them |
| Bounds | `>=0 & <=1000`, `>=40Nm` | Interval constraints |
| Quantity literal | `0.85kg`, `19mm`, `2.5s` | Exact conversion to quanta |
| Default | `wear: *0 \| >=0 & <=1000` | Default 0 within the range |
| List | `[a, b]`, `[a, ...]`, `[...#Item]`, `[a, ...#Item]` | Closed list, open list, list of any length of `#Item` (items before the `...` are not constrained by it) |
| Booleans | `true`, `false` | The two atoms of `bool` |
| Referent | `ref(12)` | A runtime referent handle, in descriptions and tests |
| Field attribute | `mass: mass @field(content, saved)` | Field registry flags |
| Declaration attribute | `@component(Physical)` inside a type | Marks a component kind |
| Variation attribute | `material: "steel" \| "brass" @vary(3, 1)` | Weights for seed variation, one per alternative (or per member of a named enum) |
| Decay attribute | `height: length @widen(5cm)` | How far a number widens per step of memory decay |
| Derived field | `torque: torque @fn(lever_torque)` | A value computed by registered code |
| Instance attributes | `@family(operations)`, `@quickcheck(target.size)`, `@variants(128)` | Pattern family, its quick-check paths, and the variant cap |
| Range distribution | `size: >=10mm & <=20mm @vary(mode: 11mm)` | A triangular draw peaked at the mode |
| Arithmetic | `torque: $f * $a`, `girth: ($w + $h) * 2` | A constraint between tagged fields (§5) |
| Addition | the same name declared again, anywhere | Unified with the other declarations; order never matters |
| Comment | `// ...` | A comment directly above a declaration is its docstring |

`&` binds tighter than `|`, as in CUE.

**Built-in types:**

- `int`, `fixed` (a fixed-point coefficient), `bool`, `text` (free text,
  compared by equality), `ref` (a runtime referent or entity handle)
- `text` and `ref` are values, not types: a string or referent first seen at
  runtime is as good as one in content. Left open in a spec, they stay open
  (they are bound at runtime), rather than becoming variation
- one type per quantity kind, named after it: `mass` (1 g), `length`
  (0.1 mm), `time` (1 ms), `force` (1 mN), `torque` (1 mN·m), `heat`
  (100 J), `temperature` (0.01 K), `volume` (1 mL), `amount` (1 mmol). Each
  kind's descriptor gives its exponents over the base units, its quantum,
  and its display unit, following DOMAIN_SIMULATION.md §12. The descriptor
  table (`triangle/src/units.c`) is the one source; the engine's unit
  structs will be generated from it.

### 2. False friends with CUE

Three constructs look like CUE but mean something else:

1. **References.** CUE's `x: y` passes constraints one way only. Here,
   naming a *top-level* definition, or a path into one, copies it the same
   way. A field reference inside a definition (`.instrument.size`) shares,
   as a tag does: anything learned at one path is known at the other, and
   `x: .y & >5` constrains `y` too, where CUE would leave `y` alone. It is
   written with a leading dot, as a path from the definition's root, rather
   than as CUE's bare name resolved by scope.
2. **Types.** In CUE, `#Wrench: #Tool & {...}` merges two structs. Here it
   declares a named type `wrench` with supertype `tool`. Two types with the
   same features are still different types.
3. **Defaults.** CUE drops conflicting defaults. Here a default on a more
   specific type wins. Only defaults from incomparable types that conflict
   are dropped, with a warning.

**Not adopted from CUE:** comprehensions that make declarations.
Arithmetic is adopted, between tags and references (§5).
Packages are adopted for names only (decision 12): a `package` scopes
types, instances, and components, and features stay global; files are
otherwise simply included.

**Adopted later from CUE, for usability:** string escapes and raw strings
(`#"..."#`), regex constraints (`=~`, `!~`, RE2 syntax), and string
interpolation (`"\($g) \($f)"`). They change nothing for content without
them. Interpolation is arithmetic's mechanism with a string for a result: a
constraint between tagged values, made concrete when they are, so it never
needs references between fields; its result is an atom when an enum lists
it, as any string is. A string means its contents, so every
spelling of the same contents is one atom or text, interned in one canonical
spelling that reads back as itself; that also lets runtime text with quotes
or newlines survive printing and parsing. A regex is a constraint carried by
text until it is concrete, never a type: the hierarchy is fixed at load, and
two unrelated regex types would meet at bottom, failing `=~"a" & =~"b"`. On
atoms a regex tests names and must narrow an enum to a type that exists,
since widening a pattern would make it match too much; at runtime a
description may be widened instead, as that only loses information. Matching
doesn't prove that one regex implies another, so it answers unknown there.

Field references and `let` came later still. A one-way reference has no
meaning in a feature structure: it would have to be resolved and dropped at
load, so it couldn't appear in patterns, which are where references are most
wanted, and matching needs information to flow both ways (learn the nut's
size and the pattern constrains the wrench). So a reference is a tag named by
its path, and every part of the engine that handles tags handles it
unchanged. It is written `.a.b`, from the definition's root, instead of CUE's
bare `a.b` resolved by lexical scope: a bare name would silently change the
meaning of the few names that are both a field and an instance, and of any
field moved into a nested struct, and tools could not tell a reference from a
name without resolving scope. A `let` copies, as names do; if it shared, it
would be a tag spelled differently. Its name may not be an instance's or a
built-in type's, so it never hides one. Both are resolved by the parser,
before anything else sees the content.

Comprehensions in lists and structs (`for`, `if`, computed labels) came with
them. They are expanded when content loads, after packages resolve and
before the hierarchy is built, so they cost nothing at runtime and nothing
downstream knows them. That fixes what they may read: data written in the
content (literals, lets, fields of this or another declaration as written,
an enum's atoms), never a computed value, since nothing is computed yet.
Data read from another declaration must be plain values, not its references
or tags, which mean nothing elsewhere. What they make is checked like
anything written: a computed field must still belong to its struct's type,
so closedness still catches mistakes, and a type's comprehension introduces
its features as written fields would.

Built-in functions (`len`, `div`, `mod`, and parts of `strings`, `list` and
`math`), comparisons and logic (`==`, `<`, `&&`, `!`) follow the same rule:
evaluated with comprehensions, over data known at load, and replaced by
what they give. A comparison between fields still open is not a constraint
here, as it would be in CUE; arithmetic and tags already relate fields, and
a third mechanism would reach the matcher. CUE's hidden fields (`_x: v`)
are lets: Triangle's structures are closed by their types, so a field
outside the type has nowhere to be, and a let is what a hidden field is for.
A bound may name its value (`wear: <worn_through`, `>=.lead`), as in CUE,
by the same rule: the name is read when content loads, so it must give a
number written in the content. Writing the bound with a literal everywhere
the threshold appears was the first gap writing new content in the new
syntax found (lab/content/machines/latent.tri, servicing).
`@embed(file=…, type=text)` brings a file's text into a field, as CUE's
`@embed` does: for data better kept in its own form than spelled in
Triangle, such as a map drawn in characters, its legend left in Triangle.
`triangle export` writes instances as JSON or YAML, as `cue export` does;
a value a spec leaves open is written as its constraint, since open values
are the point of a blueprint.

### 3. The type hierarchy

- **Declaration order never matters.** All files are read before anything is
  resolved.
- **Completion.** At load, the hierarchy is completed into a bounded complete
  partial order. Where two types have several maximal common subtypes, the
  loader generates a meet type for them (named `glb[...]` after those
  subtypes).
- **Conjunction types.** TDL only lets two types meet if a common subtype is
  declared. Content here conjoins mixins freely (`#Wrench & #ForgedSteel`),
  so for every conjunction of unrelated named types in content, and for each
  instance's root across all its additions, the loader generates a common
  subtype named after the conjuncts (`#ForgedSteel & #Wrench`). Completion
  then gives every pair of conjuncts a meet. TDL sources get no conjunction
  types: there a conjunction means the meet that completion already
  provides, and adding a type changes the hierarchy.
- **Supertypes are declared in one place.** Additions to a type may add body
  constraints but not supertypes, so the primary parent can't depend on file
  order.
- **Type IDs are dense integers assigned deterministically**: in topological
  order, ties broken by name. They don't depend on file order.
- **Appropriateness is inferred**:
  - A feature belongs to the type that introduces it.
  - Subtypes inherit it and may narrow its value type.
  - A feature introduced by two unrelated types is a load error, by
    decision: generating a hidden common supertype would change what the
    types mean without anyone seeing it. The message gives both locations,
    and names a common supertype to declare it on, or suggests a new one.
- **Type constraints.** A type's definition body is a constraint every
  instance of the type satisfies. This is how universal constraints, like
  Troll's "every bird can fly", are written: there is no separate implication
  syntax.
- **Enums** are atom types. A string some enum lists (named or anonymous) is
  that enum's atom; any other string is free text. An atom meeting `text` is
  taken as its string. An atom can itself be an enum, by a declaration with
  the atom as its label: `"dark": "grey" | "black" | "navy"`.
- **Recursive constraints** are allowed: `#Person: { mother: #Person }`. A
  node made while its type is still being expanded is lazy: its type's
  constraint is applied when unification first adds structure to it, so a
  structure is only as deep as what is known about it.
- **Components.** A type with `@component(Name)` defines component kind
  `Name`. The features it introduces are that component's fields, with the
  flags from their `@field` attributes. An entity type conjoins component
  types, so an entity's components are the component types among its
  supertypes. This is Qud's parts written as multiple inheritance.
- **Content is the source of truth for components.** A build step
  (`tri-components`) generates one C struct per component from the
  `@component` types, with numbers as quanta, enums as type IDs, and units
  and flags in comments. The component stores use those structs; the field
  registry is never written twice.

### 4. Unification and tags

- Unification takes the meet of the two root types, then unifies each shared
  feature, recursively.
- A tag makes several paths point at one node. Unifying anything into that
  node updates every path at once.
- Tags are scoped to one top-level definition. Two different operations both
  using `$s` share nothing.
- A reference `.a.b` is a tag whose name is its path. The parser adds the
  conjunct `{ a: { b: .a.b } }` to its definition, which puts the tag there.
- **Failure is reported with its path and both sources.** At load it is an
  error. At runtime it is a result the caller handles (§9, §11).

### 5. Numbers and units

- A quantity node holds a dimension and a closed interval `[lo, hi]` of
  `int64` quanta. An exact value is an interval of width zero.
- **Literals convert exactly.** `0.85kg` with a 1 g quantum is 850. `0.8505kg`
  is a load error, not a rounding.
- **Unification intersects intervals.** An empty intersection fails, and so
  do mismatched dimensions.
- `int` and `fixed` values work the same way, without a dimension. A whole
  number where a fixed-point value is expected is that number in fixed point.
- **Precision is an interval.** A perceived temperature of 30 °C ± 2 is the
  interval [28, 32] °C in quanta, so imprecise perception produces "unknown"
  matches naturally (§9).
- **Arithmetic** relates fields through tags: `torque: $f * $a` with
  `force: $f, arm: $a`, or through references: `reach: .arm + 30mm`.
  - Operators are `+ - * /` over numbers, tags, and parenthesised
    expressions, binding tighter than `&`.
  - Values carry their exponents over the base units (m, kg, s, K, mol)
    and their quantum, so products and quotients follow from the units:
    force × length is torque (torque and heat share exponents; a product is
    torque), length × length × length is volume, and an intermediate needs
    no kind of its own (the area on the way). Only the final result must be
    a kind, converted to its field's quanta. Sums need equal exponents.
  - A dimensionless result is `int` or `fixed` as its field says; an
    untyped field gets `fixed`.
  - Constraints also narrow backwards, through sums, differences, and
    scaling by a constant: a known total and one part give the other.
    Products and quotients of two variables are not inverted.
  - It is a constraint on intervals, computed forward and rounded outward:
    while an argument is open, so is the result, and it narrows as the
    arguments do (LIFE's suspension, for free). A result that is not a whole
    number of quanta is the one-quantum interval holding it.
  - It applies wherever structures are made: type expansions, patterns,
    specs, construction (a computed field is not a variation point), runtime
    values, and unification. A result that contradicts its field fails.
  - Constants fold at load: `size: 2 * 9.5mm` is `19mm`.
- Values code computes, such as a transformer's output torque from a table,
  come from functions named by attribute (`@fn(lever_torque)`), as in
  ACTIONS.md §2.

### 6. Defaults

- A default is written `*v` among a field's alternatives.
- **Defaults resolve when a blueprint becomes a spec**, after all
  indefeasible constraints are unified.
- **Specificity decides, YADU-style.** Each default is tagged with the type
  that contributed it.
  - A default from a more specific type overrides a conflicting one from a
    more general type.
  - Conflicting defaults from incomparable types are both dropped, by
    decision (YADU proper would keep their generalisation, a value nobody
    wrote), with a
    warning. The field stays open, which makes it variation (§7).
  - A default never overrides an indefeasible value. If they conflict, the
    default silently loses.
  - Instance-level defaults are the most specific of all.
- The result doesn't depend on the order of files, parents, or declarations.
- **Patterns ignore defaults.** Matching against `#Tool` uses `wear: >=0 &
  <=1000`, not `wear: 0`.
- The worst-case cost of YADU resolution is factorial in the number of
  conflicting defaults on one structure, but it runs once per blueprint at
  load, and real blueprints have a handful.

### 7. Disjunction and variation

- **In type definitions**, a disjunction of atoms is an enum (§3). A
  disjunction of structures is moved into the hierarchy:
  - the disjunction becomes a type (anonymous, or the named type it defines),
    below the common named ancestors of its alternatives
  - each alternative becomes a subtype of it, named after its text
  - a field that several alternatives declare, and no named type does, is
    introduced by the disjunction
  - unification picks an alternative when the types decide it (a feature only
    one alternative has, or a value only one allows)
  - if one alternative is a supertype of all the others (`*"oak" | #Material`),
    the disjunction is just that type
- A disjunction of separate numbers (`1 | 3`) is not a type, and is an error
  in a type. Overlapping or adjacent ranges are their hull.
- **In instances**, what remains open after defaults is variation:
  - an atom alternative: one is chosen
  - a range: a value is drawn
  - a structural alternative: the blueprint was already expanded at load into
    one variant per alternative, and one variant is chosen
  - an open disjunction type: one of its alternatives that fits is chosen,
    and its own defaults and variation follow
- **Variants.** An instance's disjunctions of structures (and of separate
  numbers) are expanded into one variant per combination:
  - variants that cannot hold are dropped; none holding is an error
  - a pattern instance matches if some variant matches (`tri_match_instance`);
    its single pattern is the generalisation of the variants
  - a `*` alternative is a default: the spec keeps the variants that took it
  - a spec resolves an open disjunction that only one alternative fits
  - `@vary` weights after a field or declaration weight its alternatives
- **Construction makes every authoritative field concrete** from the
  entity's seed (COMPONENTS.md §1, §10), using `@vary` weights where given
  and a uniform choice otherwise.
- **Each point draws from its own seed:** a hash of the entity's seed and
  the point's path, by feature name. A draw doesn't depend on the order of
  points or on which others are drawn. Adding a field to a blueprint leaves
  existing entities' other values alone, and a latent part can be drawn
  when it is revealed, from its parent's seed and its own path.
- **Distributions.** Enums and alternatives take `@vary` weights. A range
  takes `@vary(mode: 19mm)`: a triangular distribution peaked at the mode,
  drawn in integers so that it is deterministic everywhere.
- A spec records its variation points, so the developer inspector can show
  which properties came from the seed.
- **Expansion is capped.** A blueprint that expands to more than a declared
  number of variants (`@variants(n)`, 64 by default) is a load error, to
  catch accidental blowup.

### 8. Loading

The loader runs these steps, in this order, once per content build:

1. Parse every file into one shared syntax tree. The TDL front end, if used,
   produces the same tree.
2. Build the hierarchy: complete it, assign type IDs, infer appropriateness,
   check introductions.
3. Expand type constraints and enums. Encode meets (§12).
4. Resolve each instance: unify its parts and additions, resolve defaults,
   expand structural alternatives, record variation points. Blueprints
   (instances whose type includes a component) become specs here; other
   instances, such as operations, become patterns, and specs only on request.
5. Check against the field registry: only `content` fields set by content,
   units valid, every authoritative field either concrete or variation.
6. Freeze the specs into an immutable arena, laid out by position (§12).
7. Compile the pattern indexes and quick-check vectors (§12), one per
   family of instances marked `@family(name)`, from their `@quickcheck` paths.
8. Record the content hash. Saves store it (§15).

Every error carries the source locations of both conflicting sides.

### 9. Runtime matching

Matching is LIFE's "call by entailment": a pattern is checked against a
description without changing the description.

| Result | Condition | Meaning |
| --- | --- | --- |
| **Entailed** | The description is subsumed by the pattern, tags bound consistently | The description says everything the pattern needs |
| **Incompatible** | Unifying them would fail | The description rules the pattern out |
| **Unknown** | Neither | The description is too general to decide |

- **Bindings.** Tags in the pattern bind to nodes in the description. A tag
  occurring twice requires both paths to agree. With `size: $s` on both
  instrument and target, two known sizes entail if equal and are
  incompatible if not, and one unknown size makes the match unknown.
- **Residual paths.** An unknown result lists the paths that are too general,
  for example `target.size`. For a tag, it is the positions whose value is
  less specific than at another of the tag's positions, whatever the order of
  features; below a too-general type, the open fields show too. Equal values
  in separate structures under one tag are residual at every position: tags
  share nodes, and whether two described things are one is open until a
  `ref` says so. Agency uses this to create information goals
  (AGENCY.md §5): a residual says exactly what to find out.
- **Intervals.** An interval inside the pattern's interval entails, one
  disjoint from it is incompatible, and one overlapping it is unknown.
- **Hypotheses.** A referent with competing hypotheses is matched per
  hypothesis. The result is the credence mass of entailed, incompatible, and
  unknown, in fixed point, plus the residuals of the unknown hypotheses.
- **One matcher, two sources of descriptions:**
  - the **knowledge view** projects a referent's hypotheses into
    descriptions, using only the agent's beliefs
  - the **truth projection** builds a description from an entity's real
    components. It is used by `resolve` and by the omniscient stubs in the
    scenarios. Agent reasoning never sees it.
- **How the systems read the result:**
  - the action menu (ACTIONS.md §3) excludes only incompatible: unknown never
    excludes
  - a method (AGENCY.md §5) declares its credence threshold for entailed, and
    what to do with unknown: skip, or adopt the residual as a subgoal
  - an interpretation rule fires only on entailed premises

### 10. Rules as feature structures

The systems each apply their own kind of rule, written as an FS:

| Rule | Shape | Applied by |
| --- | --- | --- |
| Operation | roles, parameters, requirements, stages, effects | Actions: menu, chain search, resolve |
| Capability compatibility | a pattern over the target, such as "fits a 19 mm fastener" | Chain search |
| Recipe | inputs, tools, steps, output | Actions; expanded through knowledge |
| Proposition type | a predicate's arguments, time index, persistence | Knowledge |
| Interpretation rule | premises, conclusion, expertise, strength | Knowledge |
| Method | goal, preconditions, steps, alternatives, failure handling | Agency |
| Consideration curve | fixed-point points over a knowledge-view value | Agency |
| Norm | a pattern over actions, and a weight | Agency |

Tags carry bindings between the parts of a rule, so a rule's conclusion or
result is built by unification once its premises match. **No rule engine
searches.** Each system applies its rules in its own fixed way, within the
depth limits its doc sets.

**Definite clauses** over feature structures (LiLFeS-style) give recursion,
such as reachability, which rules applied once can't express:

```cue
e1: #Fact   & { head: #Edge & { from: "kitchen", to: "hall", d: 4m } }
r1: #Clause & { head: #Dist & { from: $x, to: $y, d: $d },
                body: [#Edge & { from: $x, to: $y, d: $d }] }
r2: #Clause & { head: #Dist & { from: $x, to: $z, d: $a + $b },
                body: [#Edge & { from: $x, to: $y, d: $a },
                       #Dist & { from: $y, to: $z, d: $b }] }
```

- Clauses are ordinary instances of the built-in `#Clause` (a `head` and a
  `body` list of goals) and `#Fact` (no body), so they need no new syntax.
  The two types exist when content uses them, leaving `head` and `body`
  free otherwise.
- A query is a structure; each solution is the query made specific by one
  proof (`tri_solve`). Resolution is depth-first, goals left to right,
  clauses in name order, each clause copied fresh so its tags are its
  variables.
- A depth limit bounds each proof, and the caller learns whether it cut any
  short. A bound on the whole search guards against explosion. A solution
  equal to one already found (the same answer by another route around a
  cycle) is reported once.
- Clauses are for short relational inferences ("reachable through doors this
  agent can open"). Search over the map, such as pathfinding, is engine code.
- Arithmetic in a clause waits through the search: `$a + $b` narrows as the
  recursive goal fixes `$b`, and a query's bound (`d: <=8m`) filters.

### 11. Descriptions in knowledge

- A referent's features (KNOWLEDGE.md §6) are one description per
  hypothesis. Because structures are totally well-typed, "not known" is just
  a feature at its most general allowed type.
- **Recognition is unification.** A percept description is unified with a
  referent's hypotheses:
  - success on all distinguishing paths: a strong match, and the result is
    the merged, more specific description
  - failure: the failing paths are reported, every one of them
    (`tri_conflicts`), not only the first that unification meets. Recognition weighs them against
    the agreeing paths, using each feature's persistence (a coat changes
    daily, height doesn't). It then binds, splits into a new referent, or
    creates competing identity hypotheses with credences.
- **Unification failure is never an error in knowledge.** Conflicts become
  competing hypotheses (KNOWLEDGE.md §11).
- **Memory decay is generalisation.** Losing detail (KNOWLEDGE.md §12)
  replaces a node's type with its primary parent: "grey" becomes "dark",
  `#WoolCoat` becomes `#Coat`. Intervals widen by declared steps
  (`@widen(5cm)` per step on each side); a number without a declared step,
  and any text or referent, is forgotten in one step. A decayed
  description can then unify with percepts it used to conflict with. That is
  a source of honest misidentification.
- Propositions are FSs whose arguments are `ref` atoms and values (§5).
  Their time index and persistence are features of `#Proposition`.
- **Uncertain identity lives in hypotheses only.** A `ref` unifies only with
  itself, and "R12 may be R7" is a pair of competing hypotheses with
  credences, never a disjunction inside a description: descriptions stay
  conjunctive.

### 12. The engine

The engine is a plain C library, with an Objective-C wrapper for the
systems.

**Type hierarchy**

- Meets come from Aït-Kaci bit-vector codes: the meet of two types is the
  bitwise AND of their codes, followed by a lookup.
- In front of that, a memo table caches meets as they are first needed, as
  in PET. It is only ever looked up, never iterated, so it can't affect
  determinism.
- Leaf types are excluded from the code computation.

**Nodes and layout**

- A node is a C struct: type ID, arcs, and the scratch fields unification
  needs (a forwarding pointer, a copy pointer, a generation number).
- **Arcs are sorted by feature** (the prototype's choice; the plan was
  positional slots, as in ProFIT and Wintner and Francez). Since structures
  are totally well-typed, a type's nodes carry the same features in the same
  order, and unification walks two arc lists in step. Lookup by feature is a
  binary search.
- Quantities and atoms are leaf nodes with an inline payload.

**Unification and subsumption**

- **Tomabechi's quasi-destructive unification.** It writes only scratch
  fields, which a bump of the global generation number invalidates in
  constant time. On failure it allocates nothing. On success it copies the
  result out.
- **Oepen and Carroll's subsumption check** runs in one linear pass, tests
  both directions at once, and allocates nothing. Matching (§9) is built on
  it, plus a compatibility check for the incompatible case.

**Memory**

| Arena | Lifetime |
| --- | --- |
| Load | One content build; dropped after specs are frozen |
| Specs | The session; immutable |
| Scratch | One match or unification, released by mark and release |
| Knowledge | One per agent; compacted by copying live descriptions (`tri_copy`) into a fresh arena during housekeeping (boundary step 4) when live data is under about half the arena (`tri_arena_bytes`). A store's memory bound counts bytes, estimated from node counts (`tri_node_count`). |

**Filtering and indexing**

- Patterns are indexed by the root type of each role or premise. Lookup
  returns candidates whose types are compatible.
- **The quick check.** Each pattern family stores the types at a small set of
  paths that most often cause failure. Comparing those by meet lookup
  rejects most failing matches before full matching. The paths are chosen
  offline from recorded scenario runs and written in content
  (`@quickcheck(...)` on a family's instances), so they are fixed at load.
  In DELPH-IN, 13–30 paths with a rule filter rejected 95–98% of failing
  unifications.
- **Choosing the paths is measured, not guessed.** Scenario runs record the
  failure paths of each family's matches (`tri_record_failures`), and
  `tri_family_suggest_quickcheck` writes the `@quickcheck` attribute to
  paste in. It should pay off for method and operation matching, with many
  patterns per description; blueprint loading needs none.

**Determinism**

- Single-threaded per call. No iteration over hash tables. Type IDs, slot
  order, and variation draw order are fixed at load.
- Permuting the order of content files produces byte-identical specs. A test
  checks this.

### 13. Uses across the systems

| System | Content | Language feature |
| --- | --- | --- |
| Components §2, §10 | Component kinds, field flags, blueprints | `@component`, `@field`, instances, defaults, variation |
| Actions §1–2 | Operations, capability records, transformers' compatibility | Rule FSs, tags, intervals, `@fn` |
| Actions §3 | The menu | Three-valued matching: unknown never excludes |
| Actions §6 | Recipes | Rule FSs; steps as lists |
| Knowledge §6 | Referents and recognition | Descriptions per hypothesis; unification with failure paths |
| Knowledge §8 | Propositions | `#Proposition` subtypes, `ref` atoms, intervals for precision |
| Knowledge §9 | Interpretation rules | Rule FSs; fire on entailed premises |
| Knowledge §12 | Memory decay | Generalisation along primary parents |
| Agency §3, §5, §9 | Consideration curves, methods, norms | Rule FSs; residuals become subgoals |

### 14. Tooling and observation

- **Load errors** show both conflicting sources, the path, and the two
  values.
- **The developer inspector** shows any FS as an indented structure with
  tags. For a spec, it also shows each value's origin: which parent, mixin,
  default, or seed draw (`tri_inspect`).
- **A match explainer** shows, for any pattern and description, the result,
  the bindings, the residuals, and the first failing path (`tri_explain`,
  and `tri_explain_instance` with tag names).
- **Docstrings.** A comment directly above a declaration is its docstring
  (`tri_doc`).
- **The TDL front end** stays, as a test oracle: checking against ACE found
  a real bug and drove the performance work. The game links a build without
  it (`make game`). It reads a subset of TDL into the same tree. Its first
  use is benchmarking against the English Resource Grammar, with ACE (MIT,
  C) as the reference for results.

### 15. Saves

- Specs are never saved. Saves record the content hash.
- **Reloading and mods are a full rebuild.** A rebuild is fast (the ERG, far
  larger than the game's content, takes 0.6 s), and declaration order never
  matters, so a mod is more files in the same load. What crosses a rebuild
  is live descriptions, moved by name (`tri_migrate`), as saves are.
- Knowledge descriptions are saved as FSs. With the same content hash, they
  use type IDs. Otherwise they are written by type name, so a save can be
  migrated to new content, failing loudly on types that no longer exist.
- The format is text: a header with the content hash and encoding, then the
  structure, with shared nodes written once and referred to as `@n`.
  Restoring into changed content makes every node satisfy its type again,
  so new features appear at their most general value, and a structure that
  no longer fits is refused with the reason (`tri_save`, `tri_restore`).

### 16. Interface sketch

Illustrative only. The built interfaces are `triangle/include/triangle.h`
and the Objective-C wrapper `triangle/objc/BGContent.h`.

```c
typedef uint32_t TriType;            // dense, assigned at load
typedef struct TriNode    TriNode;
typedef struct TriArena   TriArena;
typedef struct TriPattern TriPattern;

typedef enum { BGTEntailed, BGTUnknown, BGTIncompatible } TriMatch;

TriType  tri_meet(const TriSignature *sig, TriType a, TriType b);  // TRI_BOTTOM if none
TriNode *tri_unify(TriArena *out, TriNode *a, TriNode *b,
                   BGTFailure *failure);                           // NULL on failure
void     tri_subsumes(const TriNode *a, const TriNode *b,
                      bool *forward, bool *backward);
TriMatch tri_match(const TriPattern *p, const TriNode *d,
                   BGTBindings *bindings, BGTPathList *residual);
TriNode *tri_generalize(TriArena *out, const TriNode *d,
                        BGTPath path, int steps);                  // memory decay
```

```objc
@interface BGContent : NSObject
+ (instancetype) contentFromFiles:(NSArray *) paths error:(NSError **) error;
- (BGSpec *) specNamed:(NSString *) name;
- (TriType) typeNamed:(NSString *) name;
- (BGTPatternIndex *) indexForFamily:(NSString *) family;   // operations, methods, rules
@end

@protocol BGDescriptionSource          // the knowledge view, or the truth projection
- (NSUInteger) hypothesesFor:(BGRef) ref;
- (const TriNode *) description:(NSUInteger) i of:(BGRef) ref credence:(BGLogOdds *) c;
@end
```

### 17. An example file

```cue
// --- components ---------------------------------------------------------

#Physical: {
    @component(Physical)
    mass:     mass      @field(content, saved, perceive(touch))
    material: #Material @field(content, saved, perceive(sight))
}

#Material: "steel" | "brass" | "oak"

#Sized: {
    @component(Sized)
    size: length @field(content, saved, perceive(sight, touch))
}

#Tool: #Physical & #Sized & {
    @component(Tool)
    wear: *0 | >=0 & <=1000 @field(saved, proposable, inspect)
}

#Fastener: #Physical & #Sized & {
    @component(Fastener)
    state: "loose" | "tight" @field(saved, proposable, perceive(touch))
}

#Wrench: #Tool
#Nut:    #Fastener

// --- a blueprint ----------------------------------------------------------

wrench_19: #Wrench & {
    material: "steel"
    size:     19mm
    mass:     0.85kg
}

// --- an operation -----------------------------------------------------------

tighten_nut: #Operation & {
    roles: {
        instrument: #Wrench & { size: $s }
        target:     #Nut    & { size: $s, state: "loose" }
    }
    requires: torque: >=40Nm
    effects:  target: state: "tight"
}

// --- a proposition and an interpretation rule ---------------------------------

#Cleaned: #Proposition & {
    place:       ref
    persistence: 6h
}

recently_cleaned: #InterpretationRule & {
    expertise: #Domestic
    premises: [
        #Observed & { what: #Floor & { wetness: "damp" }, place: $room },
        #Observed & { what: #Smell & { kind: "soap" },    place: $room },
        #Believed & { what: #Climate & { humidity: "dry" }, place: $room },
    ]
    conclusion: #Cleaned & { place: $room }
    strength:   2.5     // log-likelihood ratio, fixed point
}

// --- a method -------------------------------------------------------------------

fetch_tool: #Method & {
    goal:  #Holding & { item: $tool }
    pre:   [ #LocatedAt & { item: $tool, place: $p } ]
    steps: [ #Go & { to: $p }, #Take & { item: $tool } ]
    onUnknown: "subgoal"
}
```

### 18. Prototype status

The prototype of the engine is in [triangle/](triangle/README.md): plain C11,
about 7,800 lines, with 2,000 lines of tests. Every feature in this document
is built, including the definite-clause layer (§10) and arithmetic (§5),
which the first version had deferred, and the decisions on the former open
questions (the last section):

- the parser, the hierarchy with completion, conjunction types, and
  bit-vector meets
- disjunction of structures, in types (as subtypes) and in instances (as
  variants, with a cap)
- typed open lists and recursive type constraints
- quasi-destructive unification with structure sharing, subsumption, and
  generalisation of two structures
- instance patterns and specs, YADU defaults, variation with `@vary` weights,
  construction from seeds, and derived fields (`@fn`)
- the field registry check, with blueprints resolved at load
- three-valued matching with residuals, matching against variants, and
  hypothesis masses with residuals
- memory decay, including numbers (`@widen`)
- the quick check, pattern indexes, and families compiled at load
- the inspector, the match explainer, docstrings, and both locations of every
  conflict
- saves by ID or by name, with migration to changed content
- arithmetic over quantities, with units from exponents, propagated as
  interval constraints forwards and (through sums and scaling) backwards
- definite clauses, solved by resolution with a depth limit (`tri_solve`)
- path-keyed variation seeds and triangular ranges (`@vary(mode:)`)
- generated component structs (`tri-components`), failure recording for
  choosing quick-check paths, store sizes, and migration between builds
- the content hash, and the Objective-C wrapper (`BGContent`), run under
  Apple's runtime and mulle-objc

Tests cover each feature, the three scenarios below, and the example file of
§17, read from this document. Randomised property tests check the algebra of
unification, subsumption, matching, and generalisation, the quick check,
saves, construction, and order independence; mutated sources are fuzzed. A
leak check runs the library against a counting allocator. All of it passes
under AddressSanitizer and UndefinedBehaviorSanitizer.

**The TDL front end** reads the whole English Resource Grammar from
`english.tdl` with no diagnostics. It handles `:begin`/`:end`/`:include`,
`:+` addenda, lists with tails, difference lists, strings, regular
expressions as opaque atoms, and `%suffix` and letter sets, which it skips.

**Checked against ACE 0.9.34** on the ERG, built natively on the same machine
(details in [triangle/README.md](triangle/README.md)):

- The generated meet types are the same 4,730, compared by each one's set of
  declared supertypes. The check found that conjunction types were also
  being made for TDL; they are now made only for Triangle sources.
- On 597,000 rule-daughter × lexical-entry unifications, the same 38,191
  succeed in both engines, pair by pair.
- Unification with copying runs at about 1.6 M per second here and 1.07 M in
  ACE (1.3 M without copying).
- Type expansions take 62 MB here and 131 MB in ACE.
- The ERG loads in 0.57 s, with hierarchy completion in 0.2 s (ACE: 0.3 s).

**Engine features the ERG called for:**

- Leaf types get no bit in the codes, as in PET: their subsumption follows
  the parent chain.
- Completion examines each pair of types once: after the first round, only
  new meet types against the ancestors of their descendants. Codes carry
  their range of non-zero words.
- In TDL mode, `:+` addenda may add supertypes after the declared ones.
- Nodes are 48 bytes, with unification scratch allocated on first touch, and
  copy-out shares unchanged structure (Malouf, Carroll & Copestake). Type
  expansions went from 324 MB to 62 MB, and a lexical entry from 74 KB to
  5 KB.

**A content build of the game's shape** (`bench/content.c`: 20,000
blueprints over 40 component kinds) loads in 0.18 s, constructs about
790,000 entities per second, and matches about 200,000 operation patterns per
second after the family index.

## Scenarios

Each scenario lists its purpose, setup, sequence, choices and uncertainty,
observable information, and acceptance checks. Names are illustrative.

### Scenario 1: The miller's wrench, from content

**Purpose:** order-independent loading, mixins, YADU defaults, conflicts as
errors, exact unit conversion, generated meet types, and seed variation.

**Setup**

Three files, loaded in every possible order:

- `base.tri` defines `#Tool` (with `wear: *0`), `#Wrench`, and a material
  mixin `#Steel: { hardness: *50 }`, plus `#ForgedSteel: #Steel & {
  hardness: *62 }`.
- `mill.tri` defines `miller_wrench: #Wrench & #ForgedSteel & { size: 19mm,
  mass: 0.85kg }`.
- `finish.tri` defines two finish mixins, `#Painted: { finish: *"black" }`
  and `#Oiled: { finish: *"bright" }`, and adds `miller_wrench: #Painted &
  #Oiled`.

**Sequence**

1. The loader completes the hierarchy. The instance's root conjoins
   `#Wrench`, `#ForgedSteel`, `#Painted`, and `#Oiled`, which have no common
   subtype, so it generates the conjunction type `#ForgedSteel & #Oiled &
   #Painted & #Wrench` (§3).
2. Indefeasible constraints unify: size 19 mm, mass 850 g.
3. Defaults resolve:
   - `hardness`: 62 from `#ForgedSteel` overrides 50 from `#Steel`, because
     `#ForgedSteel` is more specific.
   - `wear`: 0.
   - `finish`: "black" and "bright" come from incomparable types and
     conflict. Both are dropped with a warning, so `finish` stays open.
4. The spec freezes with one variation point, `finish`.
5. Two wrenches are constructed with different seeds. Each gets a concrete
   finish. Constructing again with the same seeds gives the same finishes.

**Variants**

- **A, conflict:** a fourth file sets `miller_wrench: size: 22mm`. Loading
  fails, naming both files, the path `size`, and the values 19 mm and 22 mm.
- **B, inexact literal:** `mass: 0.8505kg` fails, because 850.5 g is not a
  whole number of 1 g quanta.
- **C, feature clash:** `#Nut` declares its own `size` instead of inheriting
  from `#Sized`. Loading fails and suggests a common supertype.

**Choices and uncertainty**

- The finish is undetermined until construction, by design.

**Observable information**

- **Developer:** the build log (generated meet types, dropped defaults), and
  the spec inspector showing each value's origin: `hardness ← #ForgedSteel
  (default)`, `finish ← seed`.
- **Player:** nothing until the wrench exists; then whatever perception
  allows.

**Acceptance checks**

1. **Order independence:** all six file orders give byte-identical specs and
   the same content hash.
2. **Specificity:** `hardness` is 62.
3. **Incomparable defaults** drop with a warning and become variation.
4. **Conflicts** are load errors with both sources.
5. **Exactness:** mass is 850 quanta; 0.8505 kg is rejected.
6. **Construction** is deterministic given spec and seed.

### Scenario 2: The nut of unknown size

**Purpose:** three-valued matching, residual paths becoming goals, interval
precision, tags shared across roles, and the omniscient stub. It follows on
from AGENCY.md Scenario 1.

**Setup**

- Oskar holds the miller's wrench and knows it is 19 mm (he has used it for
  years).
- The pump's gland nut is in shadow. Oskar's description of it: `#Nut & {
  size: >=17mm & <=24mm, state: "loose" }`. The interval comes from seeing it
  at a distance in poor light.
- In truth the nut is 19 mm.
- Oskar's current method needs `tighten_nut` to apply.

**Sequence**

1. Matching `tighten_nut` against Oskar's view: the instrument binds `$s` to
   19 mm. The target's size [17, 24] mm overlaps 19 mm without being inside
   it, so the result is **unknown**, with residual `target.size`.
2. The menu still offers *tighten nut*: unknown never excludes.
3. The method declares `onUnknown: "subgoal"`. Agency adopts *find out
   target.size*. The method for that goal is *inspect*, which brings Oskar
   close with a lamp.
4. The inspect observation narrows the size to 19 mm. Matching again gives
   **entailed**.
5. Oskar tightens the nut.

**Variants**

- **A, wrong size:** the nut is truly 22 mm. Step 4 gives **incompatible**.
  The failed precondition produces *seek 22 mm wrench*, as in AGENCY.md §5.
- **B, omniscient stub:** with the truth projection as the description
  source, step 1 is already entailed, and Oskar never inspects. Behaviour
  differs observably.
- **C, two hypotheses:** Oskar half-remembers the nut was replaced last
  month with a 22 mm one (credence 0.3). The match returns entailed mass 0.7
  and incompatible mass 0.3, and the method's threshold decides whether to
  inspect first.

**Choices and uncertainty**

- The nut's size is uncertain to Oskar; his memory may be wrong (variant C).

**Observable information**

- **Player:** Oskar peering at the nut with a lamp, then working.
- **Developer:** the match explainer: result, `$s` binding, residual
  `target.size`, and the hypothesis masses.

**Acceptance checks**

1. **Unknown** is returned exactly when the interval overlaps without
   containment, with the residual `target.size` and nothing else.
2. **The residual becomes a goal** deterministically.
3. **No truth is consulted** outside variant B.
4. **Tags:** changing the instrument to 22 mm turns step 4's result from
   entailed into incompatible.
5. **Determinism:** replay is bit-identical.

### Scenario 3: The coat at dusk

**Purpose:** recognition by unification, failure paths weighted by
persistence, competing identity hypotheses, and memory decay as
generalisation leading to misidentification. It extends KNOWLEDGE.md
Scenario 1.

**Setup**

- The colour hierarchy has `"dark"` with subtypes `"grey"`, `"black"`,
  `"navy"`, and `"brown"`.
- Ulla holds referent R7, "the visitor", with one hypothesis: `#Person & {
  coat: #WoolCoat & { colour: "grey" }, height: >=1.75m & <=1.85m }`.
- Coat colour has a persistence of one day; height has a persistence of
  decades.

**Sequence**

1. At dusk Ulla sees a figure in the yard: `#Person & { coat: #Coat & {
   colour: "dark" }, height: >=1.70m & <=1.90m }`. Unifying with R7
   succeeds everywhere: "grey" is a subtype of "dark", and the intervals
   intersect. It is a strong match, and R7's description keeps the more
   specific values.
2. Next morning she sees a figure at the pump in a brown coat, 1.80 m.
   Unification with R7 fails at exactly one path, `coat.colour`: "grey" and
   "brown" have no meet. Height agrees.
3. Recognition weighs the one failing path (low persistence: coats change)
   against the agreeing paths. It creates a new referent R12 and two
   identity hypotheses, "R12 is R7" and "R12 is someone else", with
   credences from that weighing.
4. A week passes. R7's coat decays along primary parents: `#WoolCoat` becomes
   `#Coat`, and "grey" becomes "dark".
5. Ulla sees the brown-coated figure again. "Brown" now unifies with "dark",
   so recognition finds no conflict with R7, and the credence of "R12 is R7"
   rises.

**Variants**

- **A:** R12 truly is the visitor. The decayed memory led Ulla to the right
  answer for a weak reason.
- **B:** R12 is truly someone else. The decayed memory produces a false
  merge, which the developer inspector flags against the truth links.

**Choices and uncertainty**

- Ulla doesn't know whether the two figures are one person.

**Observable information**

- **Player** (if Ulla's account is asked for): "a man about my height in a
  dark coat, maybe the visitor".
- **Developer:** the failing path in step 2, the hypothesis credences, the
  decay steps, and the truth links.

**Acceptance checks**

1. **Failure paths** are reported exactly: only `coat.colour` in step 2.
2. **Unification failure in knowledge** creates hypotheses, never an error.
3. **Decay** follows primary parents and is computed analytically when read.
4. **The merge in step 5** follows from the decay alone, with no special
   case.
5. **No truth links** are read by recognition.
6. **Compaction:** compacting Ulla's knowledge arena between steps changes
   nothing observable; replay is bit-identical.

## Findings from the research

The research pass fetched 26 primary sources and adversarially verified 25
claims (24 confirmed, 1 refuted). Findings marked *(src)* were extracted from
primary sources but not adversarially verified.

| Finding | Evidence | Used in |
| --- | --- | --- |
| Most attempted unifications fail (over 90% in HPSG parsing), so failure must be cheap | Malouf, Carroll and Copestake 2000 | Tomabechi unification, quick check |
| Quasi-destructive unification beats non-destructive by about 17% with the quick check, 34% without | Callmeier 2001 | §12 |
| The quick check with 13–30 paths plus a rule filter rejects 95–98% of failing unifications; parse time fell about 75% | Kiefer et al. 1999; Malouf et al. 2000 | §12 |
| Arena allocation: node allocation was almost 40% of run time in early PET; mark and release gave nearly 1.6× | Callmeier 2001 | §12 memory |
| Meets by bit-vector AND, encoded at compile time | Aït-Kaci, Boyer, Lincoln and Nasr 1989 | §12 |
| Lazily cached meets are as fast as a full table with far less memory; hit rates 98.5–99.6% *(src)* | Callmeier 2001; a CUF-lineage paper crediting Dorna 1992 | §12 |
| Dropping disjunction from the unifier: grammars grew 1.4–3×, parsing 2–5× faster | Kiefer et al. 1999 | §7, decision 6 |
| Consistency with disjunction is NP-complete *(src)* | Kasper's analysis | §7 |
| Bidirectional subsumption in one linear pass, no allocation; about 34,000 tests per second in 2000 | Oepen and Carroll 2000 | §9, §12 |
| Typed terms compile to fixed-arity terms, so plain structural unification does typed unification | Erbach 1995 (ProFIT) | §12 positional arcs |
| Encoding beats custom abstract machines: ALE with flat terms ran 2.5–10× faster than the LiLFeS machine *(src)* | Penn 2000, cited in a later thesis | No abstract machine |
| PET dropped the LKB's defeasible constraints | Callmeier et al. 2000 | Defaults at load only |
| YADU: order-independent default unification where specific beats general; cheap to combine, costly only to resolve, once per object *(src)* | Lascarides and Copestake 1999 | §6 |
| CUE grounds itself in TFS and the LKB, refuses order-dependent defaults, and cites Tomabechi *(src)* | CUE implementation notes | Syntax, §2 |
| LIFE matches function arguments by entailment and suspends when undecided *(src)* | Aït-Kaci and Podelski | §9 |
| Closed-world typing catches more errors and infers more; complex implication antecedents explode the hierarchy *(src)* | Meurers 1994 (ALE vs Troll) | §3, no implication syntax |
| ACE is pure C under the MIT License; the English Resource Grammar released ERG 2025 | sweaglesw.org; Zenodo | §14 |
| Refuted: "ACE is about 15× faster than the LKB" | 1–2 vote | — |

**Prior claims checked:** ProFIT compiles typed terms to Prolog terms
(confirmed); LiLFeS powers Enju, which vendors it (confirmed); DELPH-IN
grammars are maintained (confirmed). LOGIN's BABEL demo and CUF as a general
constraint solver were not checked.

**Licences:** ACE is MIT; Enju is Apache 2.0 with LiLFeS parts under the
Artistic License; Wild LIFE carries a non-commercial DEC copyright *(src)*.
We reimplement from papers and borrow nothing.

**Caveats:** almost every measurement is from HPSG chart parsing on
1999–2001 hardware, often including Lisp garbage collection. Ratios transfer
better than absolute numbers, and our failure ratios must be measured on our
own workloads (open question 9).

## What we take from other approaches

| Source | Idea | Here |
| --- | --- | --- |
| TDL / LKB | Named types, closed structures, feature introduction, generated meet types, types vs instances | The semantics, wholesale |
| CUE | Pleasant syntax, order independence, no override, bounds | The surface syntax and its order-independence guarantee |
| PET / ACE | Quasi-destructive unification, quick check, arenas, cached meets | The engine |
| Aït-Kaci (LOGIN, LIFE) | Bit-vector meets; matching by entailment with suspension | Meet encoding; three-valued matching and residuals |
| ProFIT; Wintner and Francez | Features as fixed positions | Positional arcs and spec layout |
| Oepen and Carroll | Linear bidirectional subsumption | The basis of matching |
| YADU | Specific-beats-general defaults, order-independent | Load-time defaults |
| Kiefer et al. | Disjunction out of the unifier | Enums as types; variation; load-time expansion |
| Troll / ConTroll | Closed-world typing; type-triggered constraints | Closed types; constraints in type bodies |
| LiLFeS, CUF | Definite clauses over TFS; delayed goals | Deferred clause layer |
| Qud | Parts as composition | Component types conjoined by multiple inheritance |

## Decisions on the former open questions

Each question this section used to hold is decided; what stays open is
listed under it.

1. **The clause layer.** Built (§10): no negation, no cut; identical
   solutions are merged; pathfinding stays engine code. *Open:* tabling, if
   content comes to lean on recursion over cyclic data.
2. **Code generation.** Content is the source of truth; `tri-components`
   generates C structs for the component stores (§3), not Objective-C
   classes. This also answers COMPONENTS.md open question 6.
3. **Feature introduction friction.** Kept as an error, with both locations
   and a suggested supertype (§3).
4. **Default ties.** Both are dropped, with a warning; the field becomes
   variation (§6).
5. **Variation distributions.** Path-keyed seeds, weights for alternatives,
   and `@vary(mode: v)` for ranges (§7). Latent parts draw from their
   parent's seed and their own path.
6. **Arithmetic.** Units from exponents; backward narrowing through sums,
   differences, and constant scaling (§5). *Open:* narrowing through
   products of two variables, if content needs it.
7. **Quanta.** As in §1's built-in types, from one descriptor table, which
   DOMAIN_SIMULATION.md §12's quanta also come from.
8. **Referent identity.** Hypotheses only (§11).
9. **Our workloads.** Measured by recording failure paths in scenario runs
   (§12). *Open:* the numbers, once the systems exist.
10. **Knowledge arenas.** Compact under half live; bound by bytes (§12).
11. **Reloading and mods.** A full rebuild, with live descriptions migrated
    by name (§15).
12. **The TDL front end.** Kept as a test oracle, left out of the game build
    (§14).
