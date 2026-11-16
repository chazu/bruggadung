# 2. Types and feature structures

This chapter explains types. A type says which features a feature structure
has, and which values each feature can have. The examples are the content
of a workshop, from the guide.

## Declarations

A Triangle file is a list of declarations. The label of a declaration says
what it declares.

| Label | Declares | Example |
| --- | --- | --- |
| `#Name` | A type | `#Wrench: #Tool` |
| `"atom"` | An atom that is an enum of other atoms | `"steel": "mild" \| "forged"` |
| `name` | An instance | `wrench_19: #Wrench & { size: 19mm }` |

This chapter is about the first two. [Chapter 3](03-blueprints.md) is about
instances.

## A type introduces features

```cue
// Anything with mass and a material.
#Physical: {
    @component(Physical)
    mass:     mass      @field(content, saved)
    material: #Material @field(content, saved)
}

#Sized: {
    @component(Sized)
    size: length @field(content, saved)
}
```

`#Physical` **introduces** two features, `mass` and `material`. Each field
names the type of its value. `mass` is a built-in quantity type. `#Material`
is a type that the content declares.

The comment directly above `#Physical` is its **docstring**. Tools show it.

The words that start with `@` are **attributes**. They give information to
the program that uses the content.

- `@component(Physical)` makes the type a **component kind**. The features
  that the type introduces are the fields of the component.
- `@field(content, saved)` sets the flags of a field. The flag `content`
  permits content to set the field. The engine keeps the other flags for
  the program.

## One feature, one type

A feature belongs to the one type that introduces it. Each type below that
type has the feature too.

If two types that are not related both declare a field `from`, that is an
error. The message names both types. It tells you to declare the field one
time, on a type above both:

```cue
#Link: { from: #Room, to: #Room }
#Door: #Link & { width: length }
#Way:  #Link & { length: length }
```

This language rule is strict. Because of it, the engine knows the type of
a feature structure from its features: `{ from: "hall" }` is a `#Link`.
The language rule also prevents a mistake: two authors cannot use one
field name for two different meanings.

Packages relax this language rule between topics. Two packages can each
have a feature of the same name. See
[chapter 6](06-clauses-packages-tools.md).

## Types are closed

A feature structure can only have the features of its type. If no type has
a feature `colour`, then `colour: "red"` in a wrench is this error:

```text
unknown feature 'colour'
```

In addition, each feature structure is **totally well-typed**. Each node
has each feature of its type, also when the content does not write it. A
feature that the content does not write has the most general value that its
type permits. That value means "nothing is known".

This is why a description never has a missing field. A field is
**concrete** (one exact value) or it is **open** (a range or a type).

## Enums and atoms

A disjunction of strings in a type is an **enum**. Each string is an
**atom**. Each atom is a type below the enum.

```cue
#Material: "steel" | "brass" | "oak" | "ash"
"steel":   "mild" | "forged"
```

The second line makes the atom `"steel"` an enum too. `"mild"` and
`"forged"` are kinds of steel. Thus `material: "steel"` does not decide
between mild steel and forged steel.

This small hierarchy is useful in two ways:

- A blueprint can say `"steel"`, and each wrench gets one of the two kinds.
- When an agent forgets, a value goes up the hierarchy. `"forged"` becomes
  `"steel"`, and then `#Material`.

A string that some enum lists is the atom of that enum, in all content. A
string that no enum lists is free text, of the built-in type `text`.

## The hierarchy

Types inherit by conjunction. The operator is `&`.

```cue
#Tool: #Physical & #Sized & {
    @component(Tool)
    wear: *0 | >=0 & <=1000 @field(saved)
}

#Fastener: #Physical & #Sized & {
    @component(Fastener)
    state: "loose" | "tight" @field(content, saved)
}

#Wrench: #Tool
#Nut:    #Fastener
```

`#Tool` is below `#Physical` and below `#Sized`. It has their features, and
it introduces `wear`. The first type in the conjunction is the **primary
parent**. Generalisation follows the primary parent.

`#Wrench: #Tool` declares a new type. Types are **nominal**: the name makes
the type, not the features. A `#Wrench` and a `#Nut` could have the same
features. They are still different types, and they never unify.

A type can have many parents. A type that an author conjoins with others to
add features and defaults is a **mixin**:

```cue
#Metal:   #Physical & { material: *"steel" }
#Wooden:  #Physical & { material: *"oak" }
```

## The meet of two types

When the engine unifies two feature structures, it first finds the **meet**
of their types. The meet is the most general type that is below both. If
there is none, the types are incompatible, and unification fails.

The loader completes the hierarchy, so that two compatible types always
have exactly one meet. It makes two kinds of type for this purpose:

| Generated type | When | Name |
| --- | --- | --- |
| Meet type | Two types have more than one most general common subtype | `glb[#A,#B]` |
| Conjunction type | Content conjoins two named types that are not related | `#A & #B` |

Authors do not write these types. The build log lists them.

## A type is a constraint

The body of a type is a constraint. Each feature structure of the type
satisfies it. This is how content states a constraint that is always true:

```cue
#Stack: #Body & {
    ...
    count:    $n & int & >=1 & <=100000 ...
    unitMass: $u & mass                 ...
    ...
    mass:     $u * $n
}
```

This is a type from the lab, shortened: `...` shows what is omitted. It
says that the mass of each stack is the mass of one unit times the count.
No code of the lab computes the mass. The engine computes it from the
type. ([Chapter 4](04-patterns-and-matching.md) explains the tags `$n`
and `$u`. [Chapter 5](05-computed-values.md) explains the arithmetic.)

Triangle has no separate syntax for "if an entity is X, then Y". To state
such a constraint, declare the type X and put Y in its body.

## Disjunction in a type

A disjunction of feature structures in a type makes a small hierarchy too:

```cue
#Gripped: { grip: { kind: "bare" } | { kind: "wrapped", wraps: int & >=1 & <=6 } }
```

The loader makes one type for the disjunction and one subtype for each
alternative. Unification chooses an alternative when something decides it.
A description that has `wraps` is the wrapped alternative.

A disjunction of numbers that touch or overlap is their range: `1 | 2` is
`>=1 & <=2`. A disjunction of separate numbers, such as `1 | 3`, is an
error in a type. Use a range or an enum of atoms.

## Lists

A list is a feature structure too. The built-in types are `#Cons`, with the
features `first` and `rest`, and `#Null`, the empty list.

| Syntax | Meaning |
| --- | --- |
| `[a, b]` | A closed list of two items |
| `[a, ...]` | `a`, then anything |
| `[...#Stage]` | A list of any length. Each item is a `#Stage` |

Because a list is a feature structure, a path can go into it. The second
item of `items` is at the path `items.rest.first`.

## Recursive types

A type can refer to itself:

```cue
#Person: { mother: #Person }
```

The engine does not expand such a type without end. It makes a **lazy**
node. The constraint of the type applies when unification first adds
information to the node. Thus a feature structure is only as deep as what
is known about it.

## Additions

A name can be declared more than one time, in any file. The engine unifies
all the declarations. This is an **addition**:

```cue
#Tool: { maker: text }
```

In another file, this adds the feature `maker` to `#Tool`. Only one
declaration of a type can list its parents. An addition can add fields and
constraints, not parents.

Additions let one topic add its fields to a type of a different topic.
[Chapter 11](11-modelling-practices.md) shows how the lab uses them.

## Built-in types

| Type | Values |
| --- | --- |
| `_` | All values. The top of the hierarchy |
| `atom` | The type above each enum and atom |
| `bool` | `true` and `false` |
| `int` | Whole numbers |
| `fixed` | Numbers with three decimal places |
| `text` | Free text |
| `ref` | A handle to a referent or an entity at runtime: `ref(12)` |
| `mass`, `length`, `time`, `force`, `torque`, `heat`, `temperature`, `volume`, `amount` | Quantities, with units |

Previous: [1. What Triangle is](01-introduction.md).
Next: [3. Blueprints](03-blueprints.md)
