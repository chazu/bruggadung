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
- [Attributes](#attributes)
- [Defaults](#defaults)
- [Disjunction and variation](#disjunction-and-variation)
- [Tags](#tags)
- [Arithmetic](#arithmetic)
- [Definite clauses](#definite-clauses)
- [Runtime values](#runtime-values)
- [Loading](#loading)
- [Generated types](#generated-types)
- [Diagnostics](#diagnostics)
- [The TDL front end](#the-tdl-front-end)

## Lexical structure

Source files have the extension `.tri` and are read as bytes. Strings may
hold any bytes except a newline and `"`.

| Token | Form | Notes |
| --- | --- | --- |
| Identifier | `[A-Za-z_][A-Za-z0-9_]*` | Instance names, feature labels. `_` alone is the top type. |
| Type name | `#` then an identifier | `#Wrench` |
| String | `"` … `"` | No escapes, no newlines. |
| Number | digits with an optional `.` and fraction, then an optional unit | `19`, `0.85kg`, `2m3`. No exponent form; no leading `.`. The unit follows with no space. |
| Negative number | `-` directly before a digit | Only where an operand is expected. After an operand, `-` subtracts. |
| Tag | `$` then letters, digits, `_` | `$s`, `$room` |
| Attribute | `@` name, then optionally `(` raw text `)` | Parentheses inside must balance. The text is passed to the attribute unparsed. |
| Punctuation | `: , { } [ ] ( ) & \| * + / - ... >= <= > <` | |
| Comment | `//` to the end of the line | |

Whitespace and newlines separate tokens and are otherwise insignificant.
Commas between fields and between top-level declarations are optional. Inside
a list they are required.

**Docstrings.** Comment lines that stand alone on their lines, directly above
a top-level declaration, with no blank line in between, are that
declaration's docstring (`tri_doc`). Lines are joined with newlines, and one
leading space is removed from each.

## Grammar

```text
file        = { decl [ "," ] }
decl        = label ":" fieldvalue
label       = TYPENAME | STRING | IDENT          (type, atom enum, instance)
fieldvalue  = IDENT ":" fieldvalue               (path shorthand: a: b: c)
            | expr { ATTR }
expr        = conj { "|" conj }
conj        = sum { "&" sum }
sum         = product { ("+" | "-") product }
product     = unary { ("*" | "/") unary }
unary       = "*" unary                          (default)
            | (">=" | "<=" | ">" | "<") NUMBER   (bound)
            | primary
primary     = "_" | "true" | "false"
            | "ref" "(" NUMBER ")"
            | IDENT | TYPENAME | STRING | NUMBER | TAG
            | struct | list
            | "(" expr ")"
struct      = "{" { field | ATTR | "," } "}"
field       = IDENT ":" fieldvalue
list        = "[" [ expr { "," expr } [ "," ] ] [ "..." [ expr ] ] "]"
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

## Expressions

| Precedence (loosest first) | Operators |
| --- | --- |
| 1 | `\|` disjunction |
| 2 | `&` conjunction (unification) |
| 3 | `+` `-` |
| 4 | `*` `/` (between operands) |
| 5 | `*` default, `>=` `<=` `>` `<` bounds (prefix) |

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
| `[a, b]` | A closed list. |
| `[a, ...]` | An open list: `a`, then anything. |
| `[...#I]` | A list of any length whose items are all `#I`. |
| `[a, ...#I]` | `a`, then any number of `#I` (the `...` constrains only what follows). |
| `ref(12)` | A referent handle. It unifies only with itself. |
| `true`, `false` | The two atoms of `bool`. |
| `$a + $b`, `$f * $a` | Arithmetic: a constraint between tagged values. |

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
- There are no field references. Sharing is always written with tags.

## Arithmetic

- Operands are numbers, tags, and parenthesised arithmetic. Operators are
  `+ - * /`.
- Every tag in an arithmetic expression must also be bound to a field of the
  same declaration.
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
| `expected a declaration`, `expected a field label`, `expected a value`, `expected ':' after …` | A malformed declaration or structure. |
| `expected a number after a bound` | A bound needs a number: `>=10mm`, not `>= $x`. |
| `expected a referent number in ref(...)`, `a referent number has no unit` | `ref` takes a plain whole number. |
| `expected a tag name after '$'`, `expected an attribute name after '@'` | A bare `$` or `@`. |
| `unknown unit: 3furlong` | A unit not in the table. |
| `literal is not a whole number of quanta: 0.05mm` | The value can't be represented exactly. |
| `malformed number`, `number out of range`, `quantity out of range` | |

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
