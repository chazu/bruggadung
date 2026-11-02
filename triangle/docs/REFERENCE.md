# Triangle language reference

This reference gives the rules of Triangle as the prototype in this directory
implements them. [GUIDE.md](GUIDE.md) teaches the language by example, and
[CONTENT_LANGUAGE.md](../../CONTENT_LANGUAGE.md) explains why it is the way it
is. When this reference and the code disagree, the code is right and this
reference is a bug.

- [Lexical structure](#lexical-structure)
- [Grammar](#grammar)
- [Declarations](#declarations)
- [Expressions](#expressions)
- [Built-in types](#built-in-types)
- [Quantities and units](#quantities-and-units)
- [Regular expressions](#regular-expressions)
- [Attributes](#attributes)
- [Defaults](#defaults)
- [Disjunction and variation](#disjunction-and-variation)
- [Tags](#tags)
- [References](#references)
- [Let](#let)
- [Comprehensions](#comprehensions)
- [Built-in functions](#built-in-functions)
- [Arithmetic](#arithmetic)
- [Interpolation](#interpolation)
- [Definite clauses](#definite-clauses)
- [Runtime values](#runtime-values)
- [Loading](#loading)
- [Generated types](#generated-types)
- [Diagnostics](#diagnostics)
- [The TDL front end](#the-tdl-front-end)

## Lexical structure

Source files have the extension `.tri` and are read as bytes.

| Token | Form | Notes |
| --- | --- | --- |
| Identifier | `[A-Za-z_][A-Za-z0-9_]*` | Instance names, feature labels. `_` alone is the top type. |
| Type name | `#` then an identifier | `#Wrench` |
| Qualified name | an identifier, `.`, then an identifier or a type name | `tools.wrench_250`, `tools.#Wrench`: a name in another package (see [Packages](#packages)) |
| Path | a name (plain, qualified, or a type's), then `.name` and `[n]` segments | `wrench_19.size`, `#Wrench.size`, `tools.wrench_250.head.size`, `recipe.steps[0]`: a field of another declaration (see [References](#references)) |
| Reference | `.` then a name, then `.name` and `[n]` segments | `.instrument.size`, `.steps[0].tool`: a field of the declaration it is in |
| String | `"` … `"` | One line. Escapes as in CUE (below). |
| Raw string | `#"` … `"#` | A backslash is an ordinary character, so `#"\d+"#` is `\d+`. An escape needs the opening's `#`s after its backslash: `\#n`. With more `#`s, a quote followed by fewer doesn't close: `##"say "#hi"#"##`. |
| Number | digits with an optional `.` and fraction, then an optional unit | `19`, `0.85kg`, `2m3`. No exponent form; no leading `.`. The unit follows with no space. |
| Negative number | `-` directly before a digit | Only where an operand is expected. After an operand, `-` subtracts. |
| Tag | `$` then letters, digits, `_` | `$s`, `$room` |
| Attribute | `@` name, then optionally `(` raw text `)` | Parentheses inside must balance. The text is passed to the attribute unparsed. |
| Punctuation | `: , { } [ ] ( ) & \| * + / - ... >= <= > < =` | `=` only in `let name = …` |
| Comparison and logic | `== != && \|\| !` | Evaluated when content loads (see [Built-in functions](#built-in-functions)) |
| Comment | `//` to the end of the line | |

**Escapes.** In a string, `\(…)` interpolates ([below](#interpolation)),
`\a` `\b` `\f` `\n` `\r` `\t` `\v` are the control
characters, `\\` `\/` `\"` are themselves, `\u` takes four hex digits, and `\U`
eight; both name a Unicode scalar value, written to the string as UTF-8. Any
other escape is an error, and so is U+0000.

A string means its contents, not its spelling: `"a\"b"`, `"a\u0022b"` and
`#"a"b"#` are the same atom or text. Strings print in one canonical spelling,
which reads back as the same value: quotes, backslashes and control
characters escaped (`\n`, `\t`, `\r`, else `\u00XX`), everything else as it
is. `tri_text` gives a string's contents, decoded.

`let` is a keyword only where it starts `let name =`; `for` only where it
starts `for x in` or `for k, v in`; `in` only there; `if` only where a
condition follows it. Elsewhere they are ordinary names, so a field may still
be called `let`, `for` or `if`.

Whitespace and newlines separate tokens and are otherwise insignificant.
Commas between fields and between top-level declarations are optional. Inside
a list they are required.

**Docstrings.** Comment lines that stand alone on their lines, directly above
a top-level declaration, with no blank line in between, are that
declaration's docstring (`tri_doc`). Lines are joined with newlines, and one
leading space is removed from each.

## Grammar

```text
file        = [ "package" IDENT ] { ( decl | let ) [ "," ] }
decl        = label ":" fieldvalue
let         = "let" IDENT "=" expr
label       = TYPENAME | STRING | IDENT          (type, atom enum, instance)
fieldvalue  = IDENT ":" fieldvalue               (path shorthand: a: b: c)
            | expr { ATTR }
expr        = conj { "|" conj }
conj        = or { "&" or }
or          = and { "||" and }
and         = cmp { "&&" cmp }
cmp         = sum [ ("==" | "!=" | "<" | "<=" | ">" | ">=") sum ]
sum         = product { ("+" | "-") product }
product     = unary { ("*" | "/") unary }
unary       = "*" unary                          (default)
            | "!" unary                          (not)
            | (">=" | "<=" | ">" | "<") NUMBER   (bound)
            | ("=~" | "!~") STRING               (regex)
            | primary
primary     = "_" | "true" | "false"
            | "ref" "(" NUMBER ")"
            | IDENT | TYPENAME | QUALIFIED | PATH | REF | STRING | NUMBER | TAG
            | FUNCTION "(" [ expr { "," expr } ] ")"   (built-in, no space before "(")
            | struct | list
            | "(" expr ")"
struct      = "{" { field | let | comprehension | ATTR | "," } "}"
field       = ( IDENT | "(" expr ")" | INTERPOLATED ) ":" fieldvalue
list        = "[" [ item { "," item } [ "," ] ] [ "..." [ expr ] ] "]"
item        = expr | comprehension
comprehension = clause { clause } "{" body "}"
clause      = "for" IDENT [ "," IDENT ] "in" expr
            | "if" expr
```

A `*` at the start of a term marks a default. After an operand it multiplies.
So `*0 | >=0` is a default, and `$a * $b` is a product.

The parser stops at the first syntax error in a file. Each file reports its
own first error.

## Declarations

| Label | Declares | Example |
| --- | --- | --- |
| `#Name` | A type | `#Wrench: #Tool & { size: length }` |
| `"atom"` | An atom as an enum of other atoms | `"steel": "mild" \| "forged"` |
| `name` | An instance | `wrench_19: #Wrench & { size: 19mm }` |

**A type's definition** is a conjunction of names and structures, or a
disjunction:

- Each named type in the conjunction is a supertype. The first is the
  **primary parent**, which memory decay follows.
- The structures are the type's body: a constraint every instance satisfies.
- A disjunction of atoms makes the type an enum. A disjunction of structures
  makes it a disjunction type (see [Disjunction](#disjunction-and-variation)).

**Additions.** A name may be declared any number of times, in any files. All
its declarations are unified, and order never matters. Only one declaration
of a type may list supertypes: an addition may add body constraints, not
parents.

**Instances** are blueprints or patterns:

- A **blueprint** is an instance whose type has a component (`@component`)
  among its supertypes. It is resolved at load into a spec, with defaults
  applied and its variation recorded.
- Any other instance is a **pattern**: an operation, a rule, a clause. Its
  spec is made only on request.
- An instance may name another instance in its definition, which copies it:
  `long_spanner: spanner & { … }`. An instance may not refer to itself.
- An instance's name may not be a built-in type's name.

**Features.** A feature belongs to the type that introduces it: the most
general type whose body declares it. Its subtypes inherit it and may narrow its
value. A feature that two unrelated types introduce is an error. Structures
are closed: a structure may only carry features its type has, and a struct
literal's features must all belong to one type.

### Packages

A file that begins `package name` puts its declarations in that package; a
file without one is in the root. Many files may declare the same package.

- **Types, instances (blueprints and patterns), and components are the
  package's.** `#Wrench` declared in `package tools` is `tools.#Wrench`;
  `wrench_250` is `tools.wrench_250`; `@component(Record)` is the component
  `tools.Record`. Two packages may each declare the same name.
- **Inside a package, a plain name is the package's own** if it declares
  one, else the root's. Another package's names are always qualified:
  `spare: tools.#Wrench & { … }`. The root sees only the root's names
  plainly.
- **Features and atoms stay global.** A feature is still introduced by
  exactly one type, whatever its package; a qualified field label is an
  error. Atoms (`"steel"`) are values, not names.
- A declaration's own label is never qualified: a name is declared in its
  package's files.
- Qualified names print as written, and parse back: `tri_type_name` gives
  `tools.#Wrench`, and `tri_spec(c, "tools.wrench_250")` finds the blueprint.
- **Generated C names carry the package**: the component `tools.Record`
  under the prefix `BG` is the struct `BGtools_Record`, and its registry
  entry is named `"tools.Record"`. A root component's names are unchanged.

## Expressions

| Precedence (loosest first) | Operators |
| --- | --- |
| 1 | `\|` disjunction |
| 2 | `&` conjunction (unification) |
| 3 | `\|\|` or |
| 4 | `&&` and |
| 5 | `==` `!=` `<` `<=` `>` `>=` comparison (between operands) |
| 6 | `+` `-` |
| 7 | `*` `/` (between operands) |
| 8 | `*` default, `>=` `<=` `>` `<` bounds, `=~` `!~` regexes, `!` not (prefix) |

A bound and a comparison share their symbols: at the start of a term `>=10mm`
is a bound; between two operands `a >= b` compares them.

| Construct | Meaning |
| --- | --- |
| `_` | Top: no constraint. |
| `#Name`, `name` | The named type, or a copy of the named instance. |
| `"text"` | The atom, if an enum lists it; otherwise a `text` value. |
| `19mm`, `7`, `2.5` | A number: an exact interval of width zero. |
| `>=10mm`, `<20mm` | A bound. `>` and `<` are strict: one quantum inside. `>10mm & <20mm` is 10.1 mm to 19.9 mm. |
| `a & b` | Unification. Fails if `a` and `b` are incompatible. |
| `a \| b` | Disjunction: an enum, a disjunction type, variation, or variants, depending on where it appears. |
| `*a` | A default among alternatives. |
| `{ f: v, … }` | A structure. Its type is the most general type that has all its features. |
| `a: b: c` | Path shorthand for `a: { b: c }`. |
| `$t` | A tag: every occurrence in one top-level declaration is one node. |
| `.a.b` | A reference: the field at `a.b` of this declaration, one node with it. |
| `inst.a.b`, `#T.a.b` | A copy of another declaration's field. |
| `n` (a let's name) | A copy of the expression `let n = …` binds. |
| `[a, b]` | A closed list. |
| `[a, ...]` | An open list: `a`, then anything. |
| `[...#I]` | A list of any length whose items are all `#I`. |
| `[a, ...#I]` | `a`, then any number of `#I` (the `...` constrains only what follows). |
| `ref(12)` | A referent handle. It unifies only with itself. |
| `true`, `false` | The two atoms of `bool`. |
| `$a + $b`, `$f * $a` | Arithmetic: a constraint between tagged values. |
| `"\($given) \($family)"` | Interpolation: a string made from tagged values once they are concrete. |
| `=~"^ab"`, `!~#"\d"#` | A string that matches, or doesn't match, a regular expression ([below](#regular-expressions)). |

## Built-in types

| Type | Values |
| --- | --- |
| `_` | Everything. The top of the hierarchy. |
| `atom` | The supertype of every enum and atom. |
| `bool` | The enum of `true` and `false`. |
| `int` | Whole numbers. |
| `fixed` | Fixed-point numbers with three decimal places. A whole number given where `fixed` is expected is that number. |
| `text` | Free text, compared by equality. A string no enum lists is `text`. |
| `ref` | A runtime referent or entity handle, `ref(n)`. |
| `mass`, `length`, `time`, `force`, `torque`, `heat`, `temperature`, `volume`, `amount` | Quantities (below). |
| `#List`, `#Cons`, `#Null` | Lists. `#Cons` has `first` and `rest`; `#Null` is the empty list. List syntax builds these: a path such as `items.rest.first` reaches the second item. |
| `#Clause`, `#Fact` | Definite clauses (below). They exist only when some source mentions them. |

`text` and `ref` fields left open in a blueprint stay open. They are bound at
runtime, so they are never variation.

## Quantities and units

A quantity is a closed interval of whole **quanta**, each kind with its own
quantum. Literals convert exactly: a literal that is not a whole number of
quanta is an error, never rounded. Unifying quantities intersects their
intervals, and different kinds never unify.

| Kind | Quantum | Units accepted | Prints as | Exponents (m, kg, s, K, mol) |
| --- | --- | --- | --- | --- |
| `mass` | 1 g | `g`, `kg`, `t` | `g` | 0, 1, 0, 0, 0 |
| `length` | 0.1 mm | `mm`, `cm`, `m`, `km` | `mm` | 1, 0, 0, 0, 0 |
| `time` | 1 ms | `ms`, `s`, `min`, `h`, `d` | `ms` | 0, 0, 1, 0, 0 |
| `force` | 1 mN | `mN`, `N`, `kN` | `N` | 1, 1, −2, 0, 0 |
| `torque` | 1 mN·m | `mNm`, `Nm` | `Nm` | 2, 1, −2, 0, 0 |
| `heat` | 100 J | `J`, `kJ`, `MJ` | `J` | 2, 1, −2, 0, 0 |
| `temperature` | 0.01 K | `K`, `C`, `degC` | `K` | 0, 0, 0, 1, 0 |
| `volume` | 1 mL | `mL`, `L`, `m3` | `mL` | 3, 0, 0, 0, 0 |
| `amount` | 1 mmol | `mmol`, `mol` | `mmol` | 0, 0, 0, 0, 1 |
| `int` | 1 | none | | dimensionless |
| `fixed` | 0.001 | none; a number with a `.` and no unit is `fixed` | | dimensionless |

- Celsius (`C`, `degC`) is offset to kelvin: `20C` is `293.15K`.
- Heat is counted in units of 100 J, so `150J` is an error.
- Torque and heat have the same exponents. A product that could be either is
  torque.
- The table lives in `src/units.c`. It is the one source of the kinds; the
  generated component structs and the engine's unit types come from it.

## Regular expressions

`=~"re"` is a string that matches `re` somewhere in it, and `!~"re"` one that
doesn't, as in CUE. Write the expression as a raw string when it has
backslashes: `=~#"^\d+$"#`, not `=~"^\\d+$"`.

```cue
#Coded: #Thing & { label: =~#"^[a-z]+-\d+$"# }
tagged: #Coded & { label: "ab-12" }            // ok
```

**On text**, a regex is a constraint the value carries until it is concrete.
Constraints conjoin: `=~"^ab" & !~"9"` is a value that must meet both, and
unifying it with `"abc"` gives `"abc"`, with `"ab9"` fails. Constraints
print sorted and read back as the same value, and saves, migration and the
content hash keep them. Generalisation keeps the constraints both sides meet;
memory decay forgets a field's constraints down to those its type declares.

**On atoms**, a regex tests the atom's name: `"steel" & =~"^s"` is the atom
`"steel"`. Against an enum such as `#Material`, the result is the type whose
atoms are exactly those that match: none is a conflict, all is the enum, and
`=~"^(steel|brass|iron)$"` is `"metal"` when that enum lists just those. When
no type is exactly the atoms that match (`=~"^s"` allows `"steel"` and
`"stone"`), content is an error that asks for such an enum: a pattern widened
to all of `#Material` would match what it shouldn't. At runtime, a description
keeps the most specific type covering them instead: less precise, never wrong.

**Matching.** A pattern's regex entails a concrete string or atom that meets
it, and is incompatible with one that doesn't. Against a description that is
itself only constrained, it is entailed when the description carries all of
the pattern's constraints, and otherwise **unknown**: Triangle doesn't prove
that one regex implies another. An agent may then go and look at what it
could have deduced, but it never concludes something false.

**The syntax is RE2's**, as CUE and Go use it, matched over UTF-8 code points
in time linear in the text, with no backtracking:

| Supported | |
| --- | --- |
| Literals, `.` (no newline unless `(?s)`), `\|`, groups `(…)`, `(?:…)`, `(?P<name>…)` | |
| `*` `+` `?` `{n}` `{n,}` `{n,m}` (counts up to 1000), and their lazy forms | Lazy forms match the same strings. |
| Classes `[a-z]`, `[^…]`, `\d` `\w` `\s` `\D` `\W` `\S`, `[[:alpha:]]` and the other POSIX classes | ASCII, as in RE2. |
| `^` `$` (lines with `(?m)`), `\A` `\z`, `\b` `\B` | Without `(?m)`, `$` is the end of the text. |
| Flags `(?i)` `(?s)` `(?m)`, scoped `(?i:…)` | `(?i)` folds ASCII letters only. |
| Escapes `\n` `\t` `\x41` `\x{263a}`, `\Q…\E`, punctuation `\.` | |

Not supported: backreferences and lookaround (RE2 has neither), Unicode
classes such as `\pL`, and case folding beyond ASCII.

## Attributes

An attribute is written after a field's value, after a top-level declaration,
or on its own inside a structure. The parser keeps the text between the
parentheses as it is, and the attribute that reads it parses it. Unknown
attribute names are ignored, so tools can add their own.

| Attribute | Where | Arguments | Meaning |
| --- | --- | --- | --- |
| `@component(Name)` | Inside a type's structure | A name | The type is component kind `Name`. The features it introduces are the component's fields. A type is at most one component. |
| `@field(flags)` | After a field | Comma-separated flags | Field registry flags. `content` lets content set the field; setting any other field from content is an error. Other flags (`saved`, `inspect`, `proposable`, `perceive(sight)`, …) are kept for the engine (`tri_component_field`, generated headers) and not checked. A field with no `@field` is unrestricted. |
| `@vary(w1, w2, …)` | After a field, or after an instance declaration | Whole-number weights | Weights for choosing among alternatives in construction, one per alternative. After a field, they count the field's top-level alternatives, or, when its value is a named enum, the enum's declared members in order. After a declaration, they weight its top-level structural alternatives (its variants). A weight of 0 means never. |
| `@vary(mode: v)` | After a field holding a range | A quantity of the field's kind | Draw from a triangular distribution over the range, peaked at `v`. The range needs both bounds. If `v` doesn't parse as that kind, the draw is uniform. |
| `@variants(n)` | After an instance declaration | A positive whole number | The cap on the instance's variants. Default 64. |
| `@family(name)` | After an instance declaration | A name | Put the instance in a pattern family, whose index is compiled at load (`tri_family_index`). |
| `@quickcheck(p, …)` | After an instance declaration | Dotted feature paths | Quick-check paths for the instance's family. The family pools the paths of all its instances. |
| `@widen(step)` | After a field | A quantity of the field's kind | In memory decay, the field's interval widens by `step` on each side per step, within what its type allows. Without it, a number is forgotten in one step. |
| `@fn(name)` | After a field | A function name | The field's value is computed by C code registered with `tri_register_fn`. Construction and `tri_derive` call it. The field is never a variation point. |

## Defaults

- A default is an alternative marked `*`: `wear: *0 | >=0 & <=1000`. One
  disjunction may have only one.
- Defaults are applied when a blueprint becomes a spec, after every value has
  been unified. Patterns and matching ignore them.
- Each default belongs to the type (or instance) that wrote it:
  - A default from a more specific type overrides one from a more general type.
  - An instance's own default overrides every type's.
  - Conflicting defaults from unrelated types are both dropped, with a
    warning. The field stays open, so it becomes variation.
  - A default never overrides a value. If they conflict, the default loses
    silently.
- The result is the same whatever the order of files, parents, or
  declarations.

## Disjunction and variation

What a disjunction means depends on where it is.

| Where | Alternatives | Meaning |
| --- | --- | --- |
| Type | Atoms | An enum: each atom becomes a subtype of it. An unnamed one gets a generated name (`"loose" \| "tight"`). |
| Type | Structures (and type names) | A disjunction type, with one subtype per alternative. Unification chooses an alternative when the types decide it. If one alternative is a supertype of all the others, the disjunction is just that type. |
| Type | Numbers that touch or overlap | Their hull: `1 \| 2` is `>=1 & <=2`. |
| Type | Separate numbers | An error. Use a range, or an enum of atoms. |
| Instance | Atoms, overlapping ranges | Variation, chosen at construction. |
| Instance | Structures, separate numbers | **Variants**: one version of the instance per combination of alternatives. Combinations that can't hold are dropped; if none holds, that is an error. More than the cap (`@variants`, default 64) is an error. |
| Runtime value | Structures, separate numbers | An error: a runtime value must be one description. |

**Variants.** An instance with variants has one pattern per variant
(`tri_pattern_variant`). Its single pattern (`tri_pattern`) is their
generalisation. `tri_match_instance` matches against all of them: entailed if
any variant is entailed, incompatible if all are incompatible, otherwise
unknown. A `*` alternative is a default: the spec keeps only the variants
that took it.

**Construction** (`tri_construct`) makes every open field of a spec concrete:

- an enum or atom alternative: one member, by `@vary` weights or uniformly
- a range: a whole number of quanta, uniformly or by `@vary(mode:)`
- a disjunction type left open: one alternative that fits, then its own
  defaults and variation
- variants: one variant, by the declaration's `@vary` weights or uniformly
- `@fn` fields and arithmetic results are computed, not drawn

Each variation point draws from its own seed: a hash of the entity's seed and
the point's path, by feature name. A draw doesn't depend on any other point.

A field of a blueprint that is neither concrete nor drawable is an error at
load. A range needs both bounds to be drawn. `text` and `ref` fields are
exempt.

## Tags

- A tag (`$name`) makes every path where it occurs one node.
- Its scope is one top-level declaration, including all of that
  declaration's additions.
- In matching, a pattern's tags bind to nodes of the description. A tag
  whose positions disagree makes the match incompatible. One that is open at
  some positions makes it unknown, with those positions as residuals.
- A [reference](#references) is a tag whose name is its path: `.a.b` shares
  the node at `a.b`.

## References

A reference names a field of the declaration it's written in, by its path
from the declaration's root:

```cue
loosen: #Roles & {
    instrument: #Wrench
    target:     #Nut & { size: .instrument.size, state: "tight" }
}
```

- **A reference shares.** `.instrument.size` and the field it names are one
  node, exactly as if both carried one tag. A constraint at either end holds
  at both: `size: .instrument.size & >=15mm` narrows the wrench too. (CUE's
  references pass constraints one way only; see CONTENT_LANGUAGE.md §2.)
- **The path is from the declaration's root,** wherever the reference
  stands, so moving a field into a nested struct doesn't change what a
  reference means. `[n]` is a list's item: `.steps[0]` is `steps.first`,
  `.steps[1]` is `steps.rest.first`.
- **The field needn't be written.** `.instrument.size` may name a field that
  only the type declares. Each feature along the path must belong to the type
  at that point.
- A reference may not name a field that contains it (`a: { b: .a }`): the
  structure would be cyclic.
- **In types,** a reference holds in every subtype: with
  `#Matched: #Op & { target: { bore: .instrument.size } }`, any `#Matched`
  has one size for both.
- **References work wherever tags do:** in arithmetic and interpolation, in
  patterns and matching (a binding is asked for by the reference as written:
  `tri_binding(c, "loosen", ".instrument.size", d)`), and in runtime values.
  A spec prints the shared node as a numbered tag, as it does any tag.
- **A path into another declaration copies:** `wrench_19.size` is a copy of
  that instance's `size`; `#Wrench.size` is the constraint the type gives it.
  The longest prefix that names a type or an instance is the declaration, so
  `tools.wrench_250.size` is a field of the package's blueprint. Inside a
  package, a path starts from the package's own name if it declares one.

## Let

`let name = expr` names an expression, in a file or in a struct:

```cue
let socket = 30mm

#Ratchet: #Lever & {
    let reach_of_arm = .arm
    reach: reach_of_arm + socket
}
```

- **A use is a copy:** each use of the name is the expression afresh, as
  naming an instance is. Two uses of `let r = >=10 & <=30` are two values. A
  reference or tag in the expression still shares, wherever it's used: tags
  and references belong to the declaration the use is in.
- **Scope:** a file's lets are visible in all of that file; a struct's lets
  in all of that struct, including inside nested structs. A use may come
  before its let.
- **A let's name may not hide anything:** not an instance's, a built-in
  type's, or an enclosing let's. `_`, `true`, `false`, `ref`, `let` and
  `package` can't be bound.
- A let that refers to itself, directly or through other lets, is an error.
- A let is not a declaration. It makes no instance, and the game can't look
  it up.

## Comprehensions

`for` and `if` make a list's items and a struct's fields from data, as in
CUE. They are expanded when content loads, so the rest of the engine (and
the game) only ever sees what they make.

```cue
let table = [[30, 10], [60, 40], [100, 60]]
warm: #Curve & { points: [for p in table { input: p[0], output: p[1] }] }

let sizes = [13mm, 17mm, 19mm, 24mm]
let counted = true
shelf: #Shelf & {
    sizes:  [for s in sizes if s >= 17mm { s }]          // [17mm, 19mm, 24mm]
    labels: [for i, s in sizes { "\(i): \(s)" }]        // ["0: 13mm", ...]
    stock:  { for m in #Material { (m): 0 }, if counted { note: "counted" } }
}

#Stock: { for m in #Material { (m): int & >=0 } }      // a field per material
```

- **In a list**, a comprehension stands for items: the body `{ … }` is one
  item, a struct, or a single value in braces (`{ s }`, `{ x * 2 }`). **In a
  struct**, it stands for fields: the body's fields join the struct's.
- **`for v in src`** goes through a source's values; `for k, v in src` also
  binds the key: a list's index (from 0), or a struct's label as a string.
  Clauses chain, left to right: `for i in xs for j in ys if i != j { … }`.
- **A source is data written in the content, known when content loads:** a
  list or struct literal, a `let`'s value, a reference to a field of this
  declaration (`.points`), a path into another declaration
  (`table.rows`), or an enum, which gives the atoms it lists, in order. A
  closed list only: an open one's items aren't all written. Data from
  another declaration must be plain values, without its own references or
  tags; a declaration whose comprehensions it reads is expanded first.
- **`if cond`** keeps what follows when the condition holds: an expression
  that is `true` or `false` when content loads, such as a comparison (see
  [Built-in functions](#built-in-functions)).
- **Computed labels:** `(expr): value` or `"\(k)_x": value`, a string that is
  a field's name. A computed field is like any written one: its feature must
  belong to the struct's type, and in a type's body it introduces the
  feature, as `#Stock`'s do.
- **A variable is a copy of its value,** as a `let` is; its name follows the
  `let` rule (it may not hide an instance, a built-in type, a `let`, or an
  enclosing comprehension's variable). A variable's path reads into its
  value: `p[0]`, `row.size`. References in the body (`.lead`) are this
  declaration's, and share as usual.
- Comprehensions make at most 100,000 items or fields per declaration.
  Comprehensions that make declarations are not supported.

## Built-in functions

CUE's `len`, `div`, `mod`, `quo` and `rem`, a part of its `strings`, `list`
and `math` packages, and its comparisons and logic. Like comprehensions,
they are evaluated when content loads, over data written in the content
(literals, lets, fields of this or another declaration, comprehensions'
variables), and become the value they give. Nothing at runtime calls them,
and an argument not known by then is an error. No `import` is needed.

```cue
let names = ["oak", "Ash ", "elm"]
r: #R & {
    n:  len(names) * 10                                    // 30
    s:  strings.Join([for x in names { strings.ToUpper(strings.TrimSpace(x)) }], "-")   // "OAK-ASH-ELM"
    ok: strings.HasPrefix("wrench", "wr") && len(names) > 2  // true
    l:  list.Range(0, 10, 3)                               // [0, 3, 6, 9]
}
```

| Function | Gives |
| --- | --- |
| `len(x)` | Items of a closed list, fields of a struct, bytes of a string. |
| `div(a, b)`, `mod(a, b)` | Euclidean quotient and remainder: `0 <= mod < \|b\|`. |
| `quo(a, b)`, `rem(a, b)` | Quotient and remainder truncated toward zero. |
| `math.Abs(x)` | Any number, in its kind. |
| `math.Floor`, `math.Ceil`, `math.Round`, `math.Trunc` | A whole number, from `int` or `fixed`. `Round` is half away from zero. |
| `strings.ToUpper`, `strings.ToLower` | ASCII letters only. |
| `strings.TrimSpace(s)` | Without leading and trailing white space. |
| `strings.Contains`, `strings.HasPrefix`, `strings.HasSuffix` | `true` or `false`. |
| `strings.Index(s, sub)` | The first byte offset of `sub`, or -1. |
| `strings.Join(list, sep)`, `strings.Split(s, sep)` | `Split` with `""` splits into characters. |
| `strings.Replace(s, old, new, n)` | At most `n` replacements; -1 for all. |
| `strings.Repeat(s, n)` | |
| `list.Sum`, `list.Max`, `list.Min` | Numbers of one kind, in that kind. `Sum` of `[]` is 0. |
| `list.Product` | Whole numbers. |
| `list.Contains(list, v)` | Equal numbers of a kind, or equal strings and atoms. |
| `list.Concat(lists)`, `list.Range(start, limit, step)` | `Range` counts from `start` toward `limit`, excluding it. |
| `list.Slice(l, i, j)`, `list.Take(l, n)`, `list.Drop(l, n)`, `list.Repeat(l, n)` | |
| `list.SortStrings(l)` | Strings, in byte order. |

**Comparisons and logic** are expressions too, also evaluated at load:
`==` `!=` `<` `<=` `>` `>=` compare numbers of one kind; `==` and `!=`
compare strings and atoms; `&&`, `||` and `!` combine `true` and `false`.
`ok: .count > 2` is `true` or `false` once content loads, never a
constraint between fields, since that is what arithmetic and tags are for.

**Hidden fields.** CUE's `_name: value` is a [let](#let): in a struct or a
file, `_base: 10` names a value for the struct's fields to use, and is not a
feature, so closedness, specs and exports never see it. Declared twice, it
is an error rather than unified.

## Arithmetic

- Operands are numbers, tags, references, and parenthesised arithmetic.
  Operators are `+ - * /`.
- Every tag in an arithmetic expression must also be bound to a field of the
  same declaration. A reference always is.
- Values carry exponents over m, kg, s, K and mol. Sums and differences need
  equal exponents. Products and quotients combine them. An intermediate
  result needs no kind of its own. The final result must convert to its
  field's kind. A dimensionless result is `int` or `fixed` as its field says,
  and `fixed` in an untyped field.
- Arithmetic is a constraint on intervals, computed forward and rounded
  outward. While an argument is open, the result is as open as the argument
  allows, and it narrows as the arguments narrow. A result between two quanta
  is the one-quantum interval holding it.
- Sums, differences and scaling by a constant also narrow backwards: a known
  total and one known part narrow the other part. Products and quotients of
  two variables are not inverted.
- Arithmetic of constants folds at load: `size: 2 * 9.5mm` is `19mm`.
- It applies everywhere structures are made: type expansions, patterns,
  specs, construction, runtime values, unification, and clause resolution.

## Interpolation

`\(expr)` in a string puts a value's text there, as in CUE. It works like
arithmetic: a constraint on its field, made concrete once its tags are.

```cue
#Person: { given: text & $g, family: text & $f, full: "\($g) \($f)" }
#Bolt:   { size: length & $s, count: int & $n, label: "M\($s) x\($n * 2)" }
#Paint:  { tone: #Tone & $t, shade: #Shade & "\($t)_red" }

ada:  #Person & { given: "Ada", family: "Lovelace" }   // full: "Ada Lovelace"
bolt: #Bolt & { size: 19mm, count: 3 }                // label: "M19mm x6"
```

- An interpolated expression is a tag, a reference, a string, a number, or
  arithmetic (`\($n * 2)`, `\(.size)`). Every tag must also be bound to a
  field of the same declaration.
- A value's text is a string's contents, an atom's name, or a number as
  content writes it (`19mm`, `3`, `ref(12)`). A structure is an error.
- The result is a string like any other: an atom if some enum lists it, so
  `"\($t)_red"` is the atom `"dark_red"` of `#Shade`, and otherwise `text`.
- While a part isn't concrete, the field stays as it is: open `text`, or the
  enum it is declared as. A field computed by interpolation is never a
  variation point. Construction draws the parts, then the string follows.
- With no tags, it is made at load: `"a\(1 + 2)b"` is `"a3b"`.
- It applies where arithmetic does: type expansions, patterns, specs,
  construction, runtime values, and unification. A value that contradicts
  what an interpolation gives is a conflict.
- In a raw string, `\#(…)` interpolates (as many `#`s as opened it), and
  `\(` is ordinary text. In an ordinary string, `\\(` is a backslash and a
  parenthesis.
- A regex and a declaration's label can't be interpolated.

## Definite clauses

When a source mentions `#Clause` or `#Fact`, the loader adds:

```text
#Clause: { head: _, body: #List }
#Fact:   #Clause & { body: #Null }
```

- A clause is an instance of `#Clause` with a `head` and a `body` list of goals.
  A fact is an instance of `#Fact`, with no body.
- `tri_solve` proves a query structure by resolution, depth-first. Goals are
  proved left to right, and clauses are tried in order of instance name. Each
  use of a clause is a fresh copy, so its tags act as variables.
- A solution is the query made as specific as one proof makes it. A solution
  equal to an earlier one is dropped.
- A depth limit bounds each proof, and the caller learns whether it cut any
  short. A bound of one million steps on the whole search guards against
  explosion.
- Arithmetic in a clause waits until resolution narrows its arguments.

## Runtime values

`tri_value` builds a description from an expression at runtime. It follows
the same rules as content, with three differences:

- A default (`*`) is an error.
- A disjunction of structures or of separate numbers is an error.
- It is not checked against the field registry. Runtime code may describe any
  field.

## Loading

The loader runs these steps once per content build:

1. Parse every file. A TDL source is read by the TDL front end into the same
   syntax tree.
2. Build the hierarchy: complete it, give every type an ID, and work out
   which type introduces each feature.
3. Expand type constraints and enums.
4. Resolve instances: unify each instance's declarations, expand its
   variants, and resolve blueprints into specs with defaults and variation.
5. Check the field registry: content sets only `content` fields, and every
   blueprint field is concrete or variation.
6. Freeze the specs into their own arena.
7. Compile each family's index from its `@quickcheck` paths.
8. Record the content hash.

The result never depends on the order of files or declarations: permuting
them gives byte-identical specs and the same content hash. Type IDs are
assigned in topological order, with ties broken by name.

## Generated types

The loader generates types for constructs that need one. Each is listed in
the build log (`tri_log_message`), with its supertypes.

| Construct | Generated name |
| --- | --- |
| The meet of two types with several maximal common subtypes | `glb[#A,#B]` |
| A conjunction of unrelated named types in content | `#A & #B` (conjuncts sorted by name) |
| A disjunction of structures in a type | its text in parentheses: `({ kind: "bare" } \| { kind: "wrapped" })` |
| An alternative of such a disjunction | disjunction `/` alternative: `({ … } \| { … })/{ kind: "bare" }` |
| An unnamed enum | its text: `"loose" \| "tight"` |
| A typed list `[...#I]` | `[...#I]`, with the non-empty case `[#I, ...#I]` |

## Diagnostics

Each diagnostic has the form `file:line:col: error: message`, or `warning:`.
`tri_content_ok` is false when there is at least one error. Warnings don't
stop a build. A conflict reports the path and both values, and gives the
location of the other declaration where there is one.

**Syntax**

| Message | Cause |
| --- | --- |
| `unexpected character 'c'` | A character outside the language. |
| `unterminated string`, `unterminated struct`, `unterminated attribute` | A missing closing `"`, `}`, or `)`. |
| `unknown escape in a string; …`, `\u takes four hex digits`, `\U takes eight hex digits` | An escape not in the table, or a short code. |
| `not a Unicode scalar value`, `a string may not contain U+0000` | A `\u`/`\U` code that is a surrogate, past U+10FFFF, or zero. |
| `unterminated interpolation: \( without its )`, `an empty interpolation: \()`, `unexpected input in an interpolation` | A malformed `\(…)`. Errors inside one point into it. |
| `a regex can't be interpolated`, `a declaration's label can't be interpolated` | |
| `… (in a regex, write a raw string such as #"\d+"#, or double the backslash)` | A regex escape such as `\d` in an ordinary string. |
| `bad regular expression: …` | The expression doesn't parse: `missing )`, `lookaround is not supported (RE2 syntax)`, and so on. |
| `expected a string after =~ or !~` | |
| `unexpected '='; did you mean ':' or '=~'?`, `unexpected '!'; did you mean '!~'?` | A lone `=` where a value belongs, or a lone `!`. |
| `expected ':' after field label ('=' only binds a let)` | `size = 3` instead of `size: 3`. |
| `expected a declaration`, `expected a field label`, `expected a value`, `expected ':' after …` | A malformed declaration or structure. |
| `expected a number after a bound` | A bound needs a number: `>=10mm`, not `>= $x`. |
| `expected a referent number in ref(...)`, `a referent number has no unit` | `ref` takes a plain whole number. |
| `expected a tag name after '$'`, `expected an attribute name after '@'` | A bare `$` or `@`. |
| `unknown unit: 3furlong` | A unit not in the table. |
| `literal is not a whole number of quanta: 0.05mm` | The value can't be represented exactly. |
| `malformed number`, `number out of range`, `quantity out of range` | |

**Built-in functions**

| Message | Cause |
| --- | --- |
| `unknown function f: the built-ins are …` | A name followed directly by `(` that isn't a built-in. |
| `f takes n arguments: signature` | |
| `f: takes …`, `f: division by zero`, `f: of an empty list`, … | An argument of the wrong kind, or not known when content loads. |

**References and let**

| Message | Cause |
| --- | --- |
| `unknown feature 'f'` | A reference through a feature no type introduces. |
| `the reference .a.b: a is #T, which has no field b` | A path through a field whose type lacks the next feature. |
| `the reference .a.b: conflict at a.b: x vs y` | The value where the reference stands contradicts the field it names. |
| `.a refers to a field that contains it (.a.b), which would make the structure cyclic` | |
| `a field's label is a plain name; a reference (.a.b) is a value` | `.a: 3`. |
| `X has no field f (in X.f)`, `X has no item n (in X[n])` | A path into another declaration that it doesn't have. |
| `let x: an instance has this name, and a let may not hide it`, `let x: a built-in type has this name, …` | |
| `let x: the name is already bound, by the let at line:col` | Two lets of one name in a scope, or in nested scopes. |
| `let x refers to itself` | A cycle among lets. |
| `'true' can't be a let's name` | A reserved name. |

**Comprehensions**

| Message | Cause |
| --- | --- |
| `a comprehension goes through a list, a struct, or an enum, written in the content: not X` | A source that isn't data known at load, such as a type or an open range. |
| `.x is not written in this declaration, so a comprehension can't read it` | A reference to a field only a type gives. |
| `a comprehension can't go through an open list: its items aren't all written` | |
| `x.f holds .r, which belongs to x: a comprehension reads values as written, …` | Data from another declaration that has its own references or tags. |
| `x: its comprehensions read y, whose comprehensions read it back` | A cycle between declarations' comprehensions. |
| `a condition is true or false, known when content loads: not X` | |
| `a comparison is of values known when content loads: …`, `a comparison of numbers of different kinds` | |
| `a computed label is a string: not X`, `a computed label must be a field's name: not "…"` | |
| `x.f: its value has no such field or item` | A variable's path its value doesn't have. |
| `for x: an instance has this name, and a for's variable may not hide it`, `x: the name is already bound, by the for at line:col` | |
| `expected 'in' after for's variables`, `expected '{' after a comprehension's clauses` | |

**Interpolation**

| Message | Cause |
| --- | --- |
| `the tag $t in an interpolation is not bound to a field` | A tag only the string uses. |
| `a structure can't be interpolated into a string`, `only tags, strings, numbers and arithmetic can be interpolated` | |

**Regular expressions**

| Message | Cause |
| --- | --- |
| `conflict at f: =~"re" vs "value"` | A string or atom that doesn't match. |
| `conflict at f: =~"^s" (allows only "steel" and "stone", and no enum is exactly those: declare one) vs #Material` | A regex that narrows an enum to atoms no type is exactly. |

**Names and the hierarchy**

| Message | Cause |
| --- | --- |
| `unknown name X`, `unknown feature 'f'`, `unknown atom X`, `unknown enum X` | A name no declaration defines. Features must be introduced by a type before content can use them. |
| `feature 'f' is introduced by both #A (…) and #B (…); declare it once on …, and inherit it` | Two unrelated types introduce one feature. The message suggests an existing common supertype, or a new one. |
| `X is not a type that #T can inherit from` | A supertype that is unknown, or not a type. |
| `supertypes of #T are already declared at file:line; additions may not add supertypes` | Parents listed in a second declaration. |
| `type hierarchy has a cycle through #T` | A type is its own ancestor. |
| `#T inherits from #P, whose constraint depends on #T` | A cycle through type constraints rather than parents. |
| `only atoms may be listed in the enum #T` | An enum with a non-atom member. |
| `a disjunction of separate numbers is not a type; use a range, or an enum of atoms` | `1 \| 3` in a type. |
| `an alternative may conjoin only names and structures` | An alternative of a type-level disjunction holds something else, such as numbers. |
| `more than one default in a disjunction` | Two `*` alternatives. |
| `#T is already component C` | Two `@component` attributes. |
| `instance name X is a built-in type` | An instance named `int`, `bool`, and so on. |
| `no type has all of these features (at 'f')` | A structure whose features belong to no single type. |
| `unsupported construct in the definition of #T` | A type defined by something other than names, structures, and disjunctions. |

**Instances and blueprints**

| Message | Cause |
| --- | --- |
| `X: conflict at path: a vs b, with the declaration at file:line` | Two declarations of `X` disagree at `path`. |
| `what: conflict at path: a vs b` | A unification in a definition failed. `what` names the construct (`conjunction`, `struct`, `field`). |
| `X: a field is not appropriate for its type` | A feature used under a type that doesn't have it. |
| `instance X refers to itself`, `instance X could not be resolved` | A cycle among instances. |
| `X: f is not a content field (@field(flags)), so content may not set it` | Content set a field whose flags lack `content`. |
| `X: [variant n: ]path is not concrete and has no bounds to vary within` | A blueprint field construction can't draw. |
| `X: [variant n: ]no alternative of T fits at path` | No alternative of a disjunction type is compatible with the rest of the blueprint. |
| `X expands to more than n variants; raise the limit with @variants(n)` | Too many combinations of alternatives. |
| `X: @variants needs a positive count` | |
| `warning: X: conflicting defaults for path from #A, #B; both dropped` | Defaults from unrelated types disagree. The field becomes variation. |

**Attributes**

| Message | Cause |
| --- | --- |
| `@vary(…) needs one whole-number weight per alternative (n)` | The weights don't match the alternatives. |
| `@vary(…) needs a field with alternatives` | Weights on a field with fewer than two alternatives. |
| `@vary(mode) needs a value: @vary(mode: 19mm)` | |
| `X: @vary(…) after a declaration weights its top-level alternatives, and this declaration has none (put it after the field)` | Weights after a declaration whose value is a single structure. |
| `X: @quickcheck path 'p' has an unknown feature` | |

**Arithmetic**

| Message | Cause |
| --- | --- |
| `X: the tag $t in arithmetic is not bound to a field` | Every tag in arithmetic must also be a field's value. |
| `adding or subtracting needs the same dimension` | `$length + $mass`. |
| `only numbers, tags, and + - * / may appear in arithmetic` | |
| `X: arithmetic at path: … gives …` | The result contradicts the field. |

**Runtime values** (the `err` buffer of `tri_value`)

| Message | Cause |
| --- | --- |
| `a default (*) has no meaning in a runtime value` | |
| `a disjunction of structures is resolved only in a type or an instance`, `a disjunction of separate numbers is resolved only in an instance` | |
| Any of the conflict, unknown name, or unit messages above | |

**Files**

| Message | Cause |
| --- | --- |
| `cannot open file` | |
| `includes nested too deeply at file` | TDL `:include` deeper than 32. |
| `this library was built without the TDL front end (TRI_NO_TDL); cannot read file` | `tri_content_load_tdl` in the game build. |

## The TDL front end

`tri_content_load_tdl` reads DELPH-IN TDL from a top file, into the same
syntax tree. It is a test oracle and a benchmark (against ACE on the English
Resource Grammar), not a content format for the game. It handles
`:begin`/`:end` blocks, `:include`, `:+` addenda (which, unlike Triangle
additions, may add supertypes), lists with tails, difference lists, strings,
and regular expressions as opaque atoms. It skips `%suffix` rules and letter
sets. TDL sources get no conjunction types, and their list types are TDL's
`*list*`, `*cons*` and `*null*`.
