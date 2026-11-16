# 4. Patterns and matching

A **pattern** is a feature structure that the program matches against
descriptions. Operations, methods and interpretation rules are patterns.
This chapter explains how to write a pattern and what a match gives.

## A pattern

An instance whose type has no component kind is a pattern.

```cue
#Roles: { instrument: #Tool, target: #Fastener }

// Turn a tight nut loose with a wrench that fits it.
loosen: #Roles & {
    instrument: #Wrench
    target:     #Nut & { size: .instrument.size, state: "tight" }
} @family(operations) @quickcheck(target.state)

tighten: #Roles & {
    instrument: #Wrench & { size: $s }
    target:     #Nut & { size: $s, state: "loose" }
} @family(operations)
```

`loosen` has two **roles**: an instrument and a target. It says what each
role needs. The instrument is a wrench. The target is a tight nut. The nut
and the wrench have the same size.

## Shared nodes: references and tags

A pattern must often say that two values are the same. Triangle has two
ways to write this. Both make the two paths go to **one node**.

- A **reference** is a dot, then a path from the root of the declaration:
  `.instrument.size`.
- A **tag** is a name with a `$`: `$s`. Each `$s` in one top-level
  declaration is the same node.

A reference is a tag whose name is its path. Use a reference when one field
is clearly the source of the value. Use a tag when no one field is the
source, or for arithmetic between many fields.

Because the two paths are one node, information goes in both directions. If
the program learns the size of the nut, it knows the size of the wrench. If
it learns the size of the wrench, it knows the size of the nut.

The scope of a tag is one top-level declaration. The `$s` of `tighten` and
a `$s` in a different declaration have no relation.

### A name copies, a reference shares

This difference is important. In CUE, a reference passes constraints in
one direction only.

| Syntax | Meaning |
| --- | --- |
| `wrench_19.size` | A **copy** of a field of a different declaration |
| `.instrument.size` | The **same node** as a field of this declaration |
| `$s` | The same node at each place where `$s` is |

With a copy, a constraint on the copy does not go back to the original.
With a shared node, a constraint at one end applies at the other end. Thus
`size: .instrument.size & >=15mm` makes the wrench 15 mm or more too.

## The three results

A match compares a pattern with a **description**. A description is a
feature structure that describes a situation: what an agent knows, or what
is true. The match does not change the pattern or the description.

| Result | Condition |
| --- | --- |
| **Entailed** | The description says all that the pattern needs. |
| **Incompatible** | The description and the pattern cannot unify. |
| **Unknown** | The two can unify, but the description is too general to decide. |

Here is `loosen` against four descriptions. In each, the wrench is 19 mm.

| What is known about the nut | Result | Residual paths |
| --- | --- | --- |
| 19 mm, tight | Entailed | |
| Between 17 mm and 21 mm, tight | Unknown | `target.size` |
| 13 mm | Incompatible: `target.size: 19mm vs 13mm` | |
| Nothing | Unknown | `target.size`, `target.state` |

For numbers, the result depends on the intervals:

- If the interval of the description is inside the interval of the pattern,
  the pattern is entailed there.
- If the two intervals have no common part, the match is incompatible.
- If they overlap in part, the match is unknown.

## Residual paths

With the result *unknown*, the engine gives the **residual paths**. A
residual path is a place in the description that is too general.

Residual paths make partial knowledge useful:

- The list of possible actions excludes an operation only if the match is
  incompatible. An operation with an unknown match stays possible.
- An agent can take a residual path as a goal. If the residual path is
  `target.size`, the agent goes to measure the nut.
- An **interpretation rule** is content that says what an agent concludes
  from what it perceives. The agent concludes only if the premises of the
  interpretation rule are entailed. An agent never concludes from what it
  does not know.

## Bindings

After a match, each tag of the pattern is bound to a node of the
description. The program asks for a **binding** by the name of the tag, or
by the reference as written.

The tool that explains a match shows the bindings:

```text
result: unknown
bindings:
  .instrument.size = 19mm
residuals: target.size
```

## Patterns with variants

A pattern can have a disjunction of feature structures, as a blueprint can.
The engine expands it into variants at load.

A match against a pattern with variants has this result:

- entailed, if one variant or more is entailed
- incompatible, if all variants are incompatible
- unknown in all other cases

This is how a pattern says "an entity on the ground, or in a container". An
example from the lab:

```cue
take: #Taking & {
    contest: "quickness"
    roles: {
        actor: #Agent & { id: $a, freeHands: >=1 }
        item:  #Body & { id: $i, place: #Inside | #OnTile | #Installed }
    }
    moves: [{ moved: $i, into: #Held & { by: $a } }]
} @family(operations) @quickcheck(actor.freeHands)
```

`take` has three variants: one for an item in a container, one for an item
on the ground, and one for an item that is installed in an assembly.
Suppose that a description says that the item is in a container, and that
the actor has a free hand. The description entails the first variant, so
it entails `take`.

## Competing hypotheses

An agent can have more than one hypothesis about an entity, each with a
**credence**: how much the agent believes it. The engine matches the
pattern against each hypothesis. The result is three sums of credence: the
part that is entailed, the part that is incompatible, and the part that is
unknown.

A description stays simple in this design. The uncertainty is in the set of
hypotheses, not in a disjunction in one description.

## Families and the quick check

A program often has many patterns and one description. Most patterns do not
match. The engine has two tools to find the candidates quickly.

`@family(operations)` puts a pattern in a **family**. When content loads,
the engine makes an index for each family. For a description, the index
gives the patterns that can match. It never omits a pattern that matches.
It can include some that do not.

`@quickcheck(target.state)` names a path where matches often fail. The
index compares the types at those paths first. Each comparison is one
lookup in a table. The comparisons reject most patterns before the full
match starts.

Do not guess the paths. The engine can record the paths where matches
fail while tests run. Then it writes the `@quickcheck` attribute for you.
[Chapter 7](07-c-api.md) shows the calls.

A family is also a list that a program can read. The lab uses families
only in this way. See [chapter 10](10-substrate.md).

## Unification with a pattern

Matching answers a question. **Unification** makes a result. When the
program unifies a pattern with a description, the result has all that both
say. The tags of the pattern carry values from one part of the result to a
different part.

This is how a Triangle rule makes its conclusion. The premises and the
conclusion are parts of one pattern. Tags connect them. When the premises
unify with a description, the conclusion is complete.
[Chapter 5](05-computed-values.md) gives an example with arithmetic.

## Memory and recognition

The same operations hold the knowledge of an agent.

- **Recognition** is unification. The simulation unifies a new percept with
  what the agent knows about an entity. If they unify, the result is a more
  specific description. If they do not, the engine gives each path where
  they conflict.
- **Memory decay** is generalisation. The type of a node goes up to its
  primary parent: `"forged"` becomes `"steel"`. A number becomes wider by a
  step that the field declares with the attribute `@widen`:
  `height: length @widen(5cm)`. The agent forgets a number with no declared
  step in one step.

A conflict in knowledge is never an error. It is information. The
simulation can decide that the entity changed, or that it is a different
entity.

Previous: [3. Blueprints](03-blueprints.md).
Next: [5. Computed values](05-computed-values.md)
