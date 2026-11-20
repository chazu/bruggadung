# 6. Clauses, packages and tools

This chapter explains three parts that complete the language: definite
clauses for recursion, packages for names, and the tools for authors.

## Definite clauses

A pattern that is applied one time cannot answer a recursive question, such
as "which rooms can I get to?". For these questions Triangle has **definite
clauses**, as Prolog has. A clause has a `head` and a `body`. The head is
true if each goal in the body is true. A **fact** is a clause with no body.

Clauses are ordinary instances of two built-in types, `#Clause` and
`#Fact`. There is no new syntax.

```cue
#Room: "kitchen" | "hall" | "cellar" | "yard"
#Link: { from: #Room, to: #Room }
#Door: #Link & { width: length }
#Way:  #Link & { length: length }

d1: #Fact & { head: #Door & { from: "kitchen", to: "hall", width: 90cm } }
d2: #Fact & { head: #Door & { from: "hall", to: "cellar", width: 70cm } }
d3: #Fact & { head: #Door & { from: "cellar", to: "yard", width: 1m } }

way_one:  #Clause & {
    head: #Way & { from: $x, to: $y, length: 1m }
    body: [#Door & { from: $x, to: $y }]
}
way_more: #Clause & {
    head: #Way & { from: $x, to: $z, length: $n + 1m }
    body: [#Door & { from: $x, to: $y }, #Way & { from: $y, to: $z, length: $n }]
}
```

Here `length` counts the doors on the way, one metre for each.

A **query** is a feature structure. The query `#Way & { from: "kitchen" }`
has three solutions:

```text
#Way & { from: "kitchen", length: 3000mm, to: "yard" }
#Way & { from: "kitchen", length: 2000mm, to: "cellar" }
#Way & { from: "kitchen", length: 1000mm, to: "hall" }
```

### How the engine solves a query

- The engine proves the goals from left to right.
- It tries the clauses in the order of their names.
- Each use of a clause is a new copy, so the tags of the clause are its
  variables.
- Arithmetic in a clause waits. `$n + 1m` is computed when the recursive
  goal gives `$n`.
- A bound in the query filters the solutions. With `length: <=2m`, there
  are two solutions.
- The engine gives each different solution one time.

### Limits

A depth limit stops each proof. The caller learns if the limit stopped a
proof. A limit of one million steps stops the complete search.

The clause layer has no negation and no cut. Use clauses for short
inferences about relations. Do not use them for search on the map. A search
for a path is the work of code.

## Packages

A large body of content has many topics. Two topics can use the same name.
**Packages** prevent conflicts.

A file that starts with `package name` puts its declarations in that
package. A file with no such line is in the **root**. Many files can
declare the same package.

```cue
package cooking

#Larder: #Container & { larder: bool }
```

This `#Larder` is an illustration. It is not the `#Larder` of the lab.

### What a package owns

Types, instances, component kinds and features belong to their package. Two
packages can each declare a `#Larder`, or each introduce a field `larder`.
In one package, a feature still has exactly one type that introduces it.

Atoms are values, not names. They are global.

### How a plain name resolves

You write most names with no package. The engine finds the declaration in
this order:

1. the package of the file
2. the root
3. the one other package that declares the name

If two other packages declare the name, write it with its package:
`tools.#Wrench`.

A label of a field resolves in a similar way. First the engine uses the
type that the label is written against. In `#Larder & { larder: true }`,
the label is the `larder` of `#Larder`, and it needs no package.

### Additions between packages

A file in a package can add to a type of the root. It declares the type
again with the new fields. The new fields belong to the package of the
file.

A file can add to a type of a different package too. It uses the qualified
name:

```cue
package brewing

hunger.#Food: {
    mashesInto: *"" | text @field(content, saved, inspect, perceive(sight))
}
```

Now each `#Food` has the field `mashesInto`, and the field belongs to
`brewing`. The package `hunger` did not change.

### Order and identity

Packages do not change the order of types and features. If you move a
declaration into a package, no number changes. A name prints with no
package where that is not ambiguous.

## The `triangle` command

The command loads content from files or from directories. A directory
stands for the `.tri` files in it and below it.

| Command | Purpose |
| --- | --- |
| `triangle check DIR` | Load the content. Print the diagnostics, or a summary and the content hash |
| `triangle inspect NAME DIR` | Print the spec of an instance, with the origin of each value. For a type: its docstring, its parents, its components |
| `triangle export DIR` | Write each instance as JSON (`--yaml` for YAML) |
| `triangle export --seed N -e NAME DIR` | Write one entity that construction makes from the seed N |
| `triangle fmt DIR` | Give the sources one layout |
| `triangle components PREFIX DIR` | Write the C structs of the component kinds |
| `triangle lsp` | Run the language server |

```text
$ triangle check examples/workshop
examples/workshop/blueprints.tri:21:1: warning: hammer: conflicting defaults for material from #Wooden, #Metal; both dropped
ok: 73 types, 20 instances, 6 components, 1 warning; hash …
```

### Diagnostics

A diagnostic has the form `file:line:col: error: message`. Editors read
this form. A conflict gives the path, the two values, and the location of
the other declaration.

A program must not use a content build that has errors. A content build
that has only warnings is correct to use.

### The formatter

`triangle fmt` changes only the white space in a line. It never joins or
divides a line. It aligns fields that are on consecutive lines. It writes
nothing if the result would change the meaning of the content. The lab
keeps all content in this layout: `make check` in the lab fails if `fmt`
would change a file.

### The language server

The language server gives an editor these functions: diagnostics, the
documentation of a name, go to definition, references, symbols, completion
and formatting. It loads the content root again after each change. For the
content of Bruggadung, a load takes a few milliseconds.

There is a mode for Emacs in `triangle/emacs`.

### Export

`triangle export` writes instances as JSON or YAML, as `cue export` does.
The command writes a blueprint as its spec, and a pattern as the content
writes it. It writes a value that the spec leaves open as its constraint,
such as `">=10mm & <=24mm"`. Open values are the purpose of a blueprint,
so they are not an error. The option `--concrete` makes them an error.

## The content hash

Each content build has a **content hash**. It is a hash of the meaning of
the content. It does not change with the order of files or declarations. It
does not change with layout or comments.

The hash covers the names of features and the text of every attribute,
such as `@field(content, saved)` or `@vary(mode: 2mm)`. If you change a flag
or a mode, the hash changes. The order of the attributes after one field
does not change it.

Programs use the hash to make sure that data agrees with the content. A
save contains it. A generated file of component structs contains it.

## Other parts of the language

This book does not explain each part of the language. The table lists the
parts that have no other place in the book. The reference gives the rules.

| Part | Example | Meaning |
| --- | --- | --- |
| A derived field | `torque: torque @fn(lever_torque)` | A function of the program computes the value ([chapter 7](07-c-api.md)) |
| An embedded file | `rows: _ @embed(file="cellar.map", type=text)` | The value is the text of a file, read at load |
| A step of memory decay | `height: length @widen(5cm)` | Each step of generalisation widens the interval by 5 cm on each side |
| A bound by a name | `wear: <worn_through` | The bound is a `let` or a field, read at load |
| A path as a label | `a: b: c` | The same as `a: { b: c }` |
| An item of a list in a reference | `.steps[0]` | The first item: the path `steps.first` |
| A regular expression on an atom | `#Material & =~"^(iron\|brass\|steel)$"` | The type whose atoms are exactly those that match: in the lab, `"metal"`. Such a type must exist |
| A fixed-point number | `2.5` | The type `fixed`: three decimal places |
| Celsius | `20C` | A temperature with an offset: `293.15K` |

The attributes are:

| Attribute | Position | Purpose |
| --- | --- | --- |
| `@component(Name)` | In the body of a type | The type is a component kind |
| `@field(flags)` | After a field | The flags of the field. `content` permits content to set it |
| `@vary(w1, w2, …)` | After a field or an instance | Weights for the alternatives |
| `@vary(mode: v)` | After a field with a range | A triangular distribution with its peak at `v` |
| `@variants(n)` | After an instance | The limit on its variants |
| `@family(name)` | After an instance | The instance is a member of the family |
| `@quickcheck(p, …)` | After an instance | Quick-check paths for its family |
| `@widen(step)` | After a field | The step of memory decay for a number |
| `@embed(file=…, type=text)` | After a field | The text of a file |
| `@fn(name)` | After a field | A derived field |

The engine ignores an attribute that it does not know. A tool can add its
own.

Previous: [5. Computed values](05-computed-values.md).
Next: [7. The C API](07-c-api.md)
