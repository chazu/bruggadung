# 5. Computed values

Some values follow from other values. This chapter explains arithmetic, the
tools for data, and text.

There are two groups, and the difference is important:

- **Constraints** hold wherever the feature structure goes: at load, at
  construction, at runtime. Arithmetic and string interpolation are
  constraints.
- **Load-time tools** run one time when content loads. The engine replaces
  each of them with its result. `let`, comprehensions, most built-in
  functions, and comparisons are load-time tools.

## Arithmetic

Arithmetic relates fields. The operands are numbers, tags and references.
The operators are `+`, `-`, `*` and `/`.

```cue
#Lever: #Tool & {
    force:  $f & force & >=1N & <=500N
    arm:    $a & length
    torque: $f * $a
}

breaker: #Lever & { material: "steel", size: 60cm, mass: 2kg, arm: 0.5m, force: 80N }
```

The torque of `breaker` is `40Nm`.

### Units follow from the arithmetic

Each quantity has exponents of the base units. A force times a length has
the exponents of a torque. The engine checks them:

- A sum or a difference needs two operands of the same dimension.
- A product or a quotient combines the exponents.
- The final result must convert to the kind of its field.

### Arithmetic is a constraint

`torque: $f * $a` is not an assignment. It is a relation between three
nodes, and it works on intervals.

- While the operands are open ranges, the result is a range too. The result
  becomes narrower as the operands become narrower.
- A sum, a difference, and a product with a constant also work backwards.
  If the total and one part are known, the engine knows the other part.
- A result that contradicts its field is a failure, as all other conflicts
  are.
- Arithmetic of constants is computed at load: `size: 2 * 9.5mm` is `19mm`.
- Construction does not choose a field that has arithmetic. It computes it.

### Minimum, maximum and clamp

`math.Min(a, b)`, `math.Max(a, b)` and `math.Clamp(x, lowest, highest)` are
arithmetic too. They take tags and wait for them, as the four operators do.
They do not work backwards.

### Arithmetic goes with its pattern

A pattern can say what a field is *after* something occurs:

```cue
// Using a tool wears it: by 10, and never past worn out.
#Use: { tool: #Tool, after: #Tool }

use: #Use & {
    tool:  { wear: $w }
    after: { wear: math.Clamp($w + 10, 0, 1000) }
}

worn_use: use & { tool: { wear: 995 } }
```

The arithmetic of `use` is a part of the pattern. It goes to two places:

- **To a copy by name.** `worn_use` copies `use` and adds a wear of 995. Its
  `after.wear` is `1000`: the sum is 1005, and the clamp stops it at 1000.
- **To a unification at runtime.** The program unifies the pattern of `use`
  with a description of a real tool. If the wear of the tool is 400, then
  `after.wear` in the result is `410`. If the wear is only known to be
  between 100 and 200, the result is between 110 and 210.

This is how the content of Bruggadung states the effect of an operation.
One pattern names the roles before the operation and computes the roles
after it. [Chapter 10](10-substrate.md) gives the details.

There are two limits. The arithmetic does not go from the *result* of such
a unification into a second unification. A copy by name of an instance that
has variants does not get the arithmetic.

## Let

`let` gives a name to an expression. The name is for the file, or for the
feature structure that contains the `let`.

```cue
let socket = 30mm

#Ratchet: #Lever & { reach: .arm + socket }
```

Each use of the name is a copy of the expression. A `let` is not a
declaration. The program cannot find it. Its name cannot be the name of an
instance or of a built-in type, so it never hides one.

A field whose name starts with `_` is a **hidden field**. It is a `let`
with the syntax of CUE: `_spare: 2`. It is not a feature.

## Comprehensions

`for` and `if` make the items of a list, or the fields of a feature
structure, from data in the content.

```cue
let ratios = [1, 2, 4]

#Gearbox: #Tool & { teeth: [...int] }

gearbox: #Gearbox & { material: "steel", size: 20cm, mass: 3kg, teeth: [for r in ratios if r > 1 { r * 12 }] }
```

The teeth of `gearbox` are `[24, 48]`.

A comprehension can make the fields of a type, one for each atom of an
enum:

```cue
// How many of each material a rack holds.
#Stock: { for m in #Material { (m): int & >=0 & <=50 } }
```

`(m)` is a **computed label**. `#Stock` gets the fields `steel`, `brass`,
`oak` and `ash`. When an author adds a material to the enum, `#Stock` gets
a field for it.

The engine expands comprehensions when content loads. They can read only
data that the content writes: a list, a `let`, a field as written, the
atoms of an enum. They cannot read a value that unification computes later.
That is one difference from comprehensions in CUE. The other is that a
comprehension cannot make declarations.

## Built-in functions

Triangle has a part of the built-in functions of CUE: `len`, `div`, `mod`,
`quo`, `rem`, and parts of the packages `strings`, `list` and `math`. No
`import` is necessary.

```cue
let sizes = [10mm, 13mm, 17mm, 19mm, 24mm]

#Rack: #Physical & {
    @component(Rack)
    slots: [...length] @field(content)
    stock: #Stock      @field(content)
}

rack: #Rack & {
    _spare:   2
    material: "oak"
    mass:     12kg
    slots:    [for s in sizes if s > 12mm { s }]
    stock:    { steel: len(.slots) + _spare, brass: 0, oak: 0, ash: list.Sum([1, 2]) }
}
```

The slots of `rack` are `[13mm, 17mm, 19mm, 24mm]`. Its stock of steel is
6: four slots and two spare.

These functions run at load, on data that is known then. The engine
replaces each call with its result. Comparisons (`==`, `<`) and logic
(`&&`, `||`, `!`) follow the same language rule.

A comparison between two open fields is not a constraint in Triangle.
Arithmetic and tags relate fields. A third mechanism would make matching
more complex.

## Text

A string that no enum lists has the type `text`. Strings have the escapes
of CUE. In a **raw string**, `#"…"#`, a backslash is an ordinary
character. Use a raw string for regular expressions.

```cue
#Labelled: {
    label: text & =~#"^[A-Z][a-z]+-\d+$"#
    note:  text
}

#Tin: #Physical & #Labelled & {
    @component(Tin)
    count: int & >=1 & <=500 @field(content)
}

tin_of_nails: #Tin & {
    material: "steel"
    mass:     400g
    count:    120
    label:    "Nails-\(.count)"
    note:     "for \"soft\" wood\tonly"
}
```

### Regular expressions

`=~` constrains text with a regular expression. `!~` constrains it with the
negation. The syntax is that of RE2, as in CUE and Go. The engine matches
in a time that is linear in the length of the text.

The constraint stays with the text until the text is concrete. Then the
engine tests it.

### Interpolation

`"Nails-\(.count)"` is an **interpolation**. It becomes `"Nails-120"` when
`count` is known. Interpolation is a constraint, as arithmetic is. It works
in types and at runtime, and it waits while a part is open.

The result of an interpolation is an ordinary string. If an enum lists it,
it is the atom of that enum.

## A summary of when each construct runs

| Construct | When it runs | Can it read an open field? |
| --- | --- | --- |
| Arithmetic, `math.Min`, `math.Max`, `math.Clamp` | Always, as a constraint | Yes. It waits. |
| Interpolation | Always, as a constraint | Yes. It waits. |
| A regular expression on text | When the text is concrete | Yes. It waits. |
| `let`, hidden fields | At load | No |
| Comprehensions | At load | No |
| Other built-in functions, comparisons, logic | At load | No |
| Defaults | At load, when a spec is made | — |
| Variation | At construction | — |

Previous: [4. Patterns and matching](04-patterns-and-matching.md).
Next: [6. Clauses, packages and tools](06-clauses-packages-tools.md)
