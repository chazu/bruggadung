# 3. Blueprints

A type describes a kind of entity. A **blueprint** describes how to make
entities of that kind. This chapter explains blueprints, quantities,
defaults, and variation.

## Instances

A declaration with a name that has no `#` is an **instance**. An instance
is not a type, and it is not in the hierarchy.

Instances are in two groups.

- A **blueprint** describes a thing that the program can make. The engine
  knows a blueprint by its types: one or more of them, or of the types
  above them, has the attribute `@component`
  ([chapter 2](02-types.md)). Thus an entity made from the instance has
  data to keep.
- All other instances are **patterns**: an operation, a method, an
  interpretation rule. None of the types of a pattern has `@component`, so
  the program cannot make an entity from it. The program matches a pattern
  against descriptions. [Chapter 4](04-patterns-and-matching.md) is about
  patterns.

You do not mark an instance as a blueprint or as a pattern. Its types
decide.

```cue
wrench_19: #Wrench & {
    material: "steel"
    size:     19mm
    mass:     0.85kg
}
```

`wrench_19` is a blueprint. Its type is `#Wrench`. `#Wrench` is below
`#Physical`, and `#Physical` has `@component(Physical)`. An entity made
from `wrench_19` thus has a `Physical` component, with a mass of 0.85 kg
and steel as its material.

## The spec

When content loads, the engine resolves each blueprint into a **spec**. The
spec is all that the types say, unified with what the instance says, with
the defaults applied. The spec of `wrench_19` prints as follows:

```text
#Wrench & { mass: 850g, material: "steel", size: 19mm, wear: 0 }
```

Two values changed. `0.85kg` is now `850g`. The field `wear` has its
default value, 0.

A spec does not change after the load. The program reads it each time it
constructs an entity.

## Quantities

A quantity is a number with a unit. Triangle stores each quantity as a
whole number of **quanta**. A quantum is the smallest step of that kind of
quantity.

| Kind | Quantum | Units |
| --- | --- | --- |
| `mass` | 1 g | `g`, `kg`, `t` |
| `length` | 0.1 mm | `mm`, `cm`, `m`, `km` |
| `time` | 1 ms | `ms`, `s`, `min`, `h`, `d` |
| `force` | 1 mN | `mN`, `N`, `kN` |
| `torque` | 1 mN·m | `mNm`, `Nm` |
| `heat` | 100 J | `J`, `kJ`, `MJ` |
| `temperature` | 0.01 K | `K`, `C`, `degC` |
| `volume` | 1 mL | `mL`, `L`, `m3` |
| `amount` | 1 mmol | `mmol`, `mol` |

The language rules are:

- A literal converts exactly. `0.85kg` is 850 quanta of mass.
- A literal that is not a whole number of quanta is an error. `0.05mm` is
  half of a quantum, and the engine refuses it. The engine never rounds a
  literal.
- Different kinds never unify. A length is not a mass.

A program reads a quantity as a 64-bit whole number. There are no
floating-point numbers in content. Thus two computers always get the same
result.

## Intervals

A number in a feature structure is an **interval**: a lowest value and a
highest value. An exact number is an interval of width zero.

| Syntax | Meaning |
| --- | --- |
| `19mm` | Exactly 19 mm |
| `>=10mm & <=24mm` | From 10 mm to 24 mm |
| `>10mm` | More than 10 mm: from 10.1 mm, one quantum above |
| `length` | A length. Nothing more is known |

Unification of two numbers gives the part that both intervals contain. If
they have no common part, unification fails. `>=10mm & <=24mm` unified with
`>=20mm` is `>=20mm & <=24mm`.

## Defaults

A value marked with `*` is a **default**. The engine uses a default only if
nothing more specific decides the field.

```cue
#Tool: #Physical & #Sized & {
    @component(Tool)
    wear: *0 | >=0 & <=1000 @field(saved)
}
```

The value of `wear` is in the range 0 to 1000, and it is 0 if no
declaration says more. The operator `&` binds more tightly than `|`, so
the expression is `*0 | (>=0 & <=1000)`.

### Which default wins

Types can give different defaults for one field. The language rule is
**specificity**:

1. A default of a more specific type wins over a default of a more general
   type.
2. A default of the instance wins over each default of a type.
3. If two types that are not related give different defaults, the engine
   drops both. It gives a warning. The field stays open.
4. A default never wins over a value. If they conflict, the default loses
   and there is no message.

```cue
#Metal:   #Physical & { material: *"steel" }
#Wooden:  #Physical & { material: *"oak" }
#Handled: #Wooden & { mass: <=2kg }

hammer: #Tool & #Metal & #Handled & { size: 30cm, mass: 1.2kg }
mallet: #Tool & #Handled & #Metal & { material: *"ash", size: 25cm, mass: 0.9kg }
```

`hammer` gets a default from `#Metal` and a different one from `#Wooden`.
The two types are not related. The engine drops both defaults and gives
this warning:

```text
warning: hammer: conflicting defaults for material from #Wooden, #Metal; both dropped
```

`mallet` gives its own default, so its material is `"ash"`.

The order of the types in the conjunction does not change the result. This
is important. In a language where the last declaration wins, a small edit
changes the meaning. In Triangle, only specificity decides.

### Defaults exist only at load

The engine applies defaults when it makes a spec. A spec has no defaults in
it. A pattern never uses defaults. Matching ignores them.

Thus defaults cost nothing at runtime, and they cannot make a match
uncertain.

### Where a value came from

The `triangle inspect` command shows the origin of each value of a spec:

```text
mallet: #Handled & #Metal & #Tool
  mass: 900g  <- the instance
  material: "ash"  <- default from the instance
  size: 250mm  <- the instance
  wear: 0  <- default from #Tool
```

## Variation

A spec can leave a field open. That is **variation**. When the program
constructs an entity, the engine chooses a value for each open field. It
makes the choice from the **seed** of the entity: a 64-bit number that the
program gives.

```cue
nut: #Nut & {
    material: "brass" | "steel" @vary(3, 1)
    size:     >=10mm & <=24mm @vary(mode: 13mm)
    mass:     >=5g & <=40g
    state:    *"loose" | "tight"
}
```

| Field | How construction chooses |
| --- | --- |
| `material` | One of two atoms. Brass is three times as probable as steel. |
| `size` | A value in the range, most often near 13 mm (a triangular distribution) |
| `mass` | A value in the range. Each value is equally probable. |
| `state` | No choice. The default decides: `"loose"`. |

Four seeds give four nuts:

```text
#Nut & { mass: 39g, material: "brass", size: 12.4mm, state: "loose" }
#Nut & { mass: 9g, material: "brass", size: 12mm, state: "loose" }
#Nut & { mass: 10g, material: "brass", size: 13.1mm, state: "loose" }
#Nut & { mass: 5g, material: "steel", size: 16mm, state: "loose" }
```

### The language rules of construction

- The same seed always gives the same entity.
- Each open field is a **variation point**. Each variation point has its
  own seed: a hash of the seed of the entity and the path of the field.
  Thus one field does not depend on another. If you add a field to a
  blueprint later, the other fields of existing entities do not change.
- An atom that is an enum is open too. `wrench_19` says `"steel"`, so each
  wrench is mild steel or forged steel.
- A field that has arithmetic is computed, not chosen.

### Each field must be concrete, or have alternatives to choose from

Each field of a blueprint must be concrete, or must be something that
construction can choose from. A field `mass: mass`, with no range, is an
error:

```text
nut: mass is not concrete and has no bounds to vary within
```

Fields of the types `text` and `ref` are the exception. They can stay open.
The program gives them a value at runtime.

This language rule finds a common mistake at load: an author forgets a
field. Without it, the mistake shows much later, when an entity has no
mass.

## Variants

A disjunction can contain complete feature structures. In an instance, each
alternative is a **variant**.

```cue
spanner: #Wrench & { material: "steel" } &
    ({ size: 13mm, mass: 0.2kg } | { size: 17mm, mass: 0.3kg } | { size: 19mm, mass: 0.35kg }) @vary(1, 2, 1)
```

`spanner` has three variants. Construction chooses one. The weights after
the declaration make the 17 mm spanner as probable as the other two
together.

Variants keep related values together. A 13 mm spanner always has a mass of
0.2 kg. Two separate ranges cannot say that.

The engine expands variants at load. An instance can have 64 variants at
most. The attribute `@variants(n)` changes the limit.

## What a disjunction means

The meaning of `|` depends on its position. This table is a summary.

| Position | Alternatives | Meaning |
| --- | --- | --- |
| A type | Atoms | An enum |
| A type | Feature structures | A disjunction type, with a subtype for each alternative |
| An instance | Atoms, or ranges that overlap | Variation: construction chooses |
| An instance | Feature structures, or separate numbers | Variants |
| A runtime value | Feature structures, or separate numbers | An error |

The engine resolves each disjunction at load or at construction. At load,
a disjunction becomes types or variants. At construction, the engine
chooses one alternative. No disjunction of feature structures stays in a
feature structure at runtime.

## A copy of an instance

An instance can name another instance. That makes a copy:

```cue
ada_wrench: wrench_19 & { maker: "Ada" }
```

The copy has all that `wrench_19` says, and what it adds. (`maker` is the
field that an addition gave to `#Tool` in [chapter 2](02-types.md).) A name
always copies. If you change the copy, the original does not change.

**Caution.** A copy of an instance that has variants does not get the
variants. It gets their generalisation: what all the variants say. A copy
of `spanner` has a size from 13 mm to 19 mm and a mass from 200 g to
350 g. Construction chooses the two values separately.

Previous: [2. Types and feature structures](02-types.md).
Next: [4. Patterns and matching](04-patterns-and-matching.md)
