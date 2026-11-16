# 1. What Triangle is

Triangle is the content language of Bruggadung. Bruggadung is a project to
make a roguelike with many simulated systems. Its simulation has agents and
other entities in a small world. The *content* of the simulation is all
that an author writes to describe that world:

- the kinds of entity: a wrench, a stove, a villager
- the specific entities: a 19 mm wrench of forged steel
- the operations: to take, to eat, to tighten a nut
- the goals of an agent, and the methods that achieve them
- the rules by which an agent interprets what it sees

Triangle is one language for all of these. A file of Triangle has the
extension `.tri`.

## The problem

A simulation must describe many entities, and it does so for three purposes.

1. **To make entities.** The simulation makes a wrench from a description of
   wrenches. Two wrenches must not be identical in all details.
2. **To decide what is possible.** An operation says what it needs: a
   wrench that fits the nut. The simulation compares that with what is
   there.
3. **To hold what an agent knows.** An agent knows less than the truth. It
   knows that the nut is "about 19 mm". Later it learns more, or forgets.

Most systems use a different mechanism for each purpose. Triangle uses one:
the **typed feature structure**. A description of a kind of entity, a
requirement of an operation, and the knowledge of an agent are all feature
structures. One engine operates on all of them.

## A feature structure

A feature structure is a graph of nodes. Each node has a **type**. Each
node has one arc for each **feature** that its type has. The arc goes to
the value of the feature, which is a node too.

```cue
#Nut & { size: 19mm, state: "tight", material: "steel" }
```

This feature structure has the type `#Nut`. It has three features. The
value of `size` is a length. The values of `state` and `material` are
atoms.

A feature structure can say less:

```cue
#Nut & { size: >=17mm & <=21mm }
```

This one says that the size is between 17 mm and 21 mm. It says nothing
about the state. It is *more general* than the first one. Each entity that
the first one describes, the second one describes too.

This order, from general to specific, is the most important idea of
Triangle. Less
information is not an error. It is a more general description.

## Three operations

The engine has three main operations on feature structures.

| Operation | Input | Result |
| --- | --- | --- |
| **Unification** | Two feature structures | The most general feature structure that says all that both say, or a failure |
| **Matching** | A pattern and a description | *Entailed*, *incompatible* or *unknown* |
| **Generalisation** | A feature structure | A feature structure that says less |

Each purpose of the simulation uses these operations:

- To make an entity, the engine unifies the types of a blueprint with what
  the blueprint says. Then it chooses a value for each field that is open.
- To decide what is possible, the engine matches the pattern of an
  operation against a description.
- When an agent sees something, the simulation makes a **percept**: a
  description of what the agent perceives. It unifies the percept with
  what the agent knows. When the agent forgets, the simulation generalises
  that knowledge.

## The third result

A match has three results, not two.

| Result | Meaning |
| --- | --- |
| Entailed | The description says all that the pattern needs. |
| Incompatible | The description contradicts the pattern. |
| Unknown | The description is too general. It does not decide. |

With *unknown*, the engine gives the **residual paths**: the places in the
description where more information would decide the match. Suppose that a
pattern needs a nut of exactly 19 mm. Against the second nut above, the
result is unknown, and the residual path is `size`.

This result is the reason that agents in Bruggadung can act with partial
knowledge. An agent that does not know the size of a nut can still try the
wrench. An agent can also take the residual path as a goal: to find out the
size. Unknown never forbids an action. Only incompatible does.

## Where the ideas come from

Triangle is not new in its parts. In one sentence, it has:

- the meaning of **TDL**, the type description language of the DELPH-IN
  grammars
- the syntax of **CUE**, a configuration language
- the engine techniques of **PET** and **ACE**, two parsers for those
  grammars
- the method of matching of **LIFE**, a logic programming language

Triangle adds what a simulation needs: quantities with units as whole
numbers, defaults that are resolved when content loads, and variation that
comes from a seed. [Chapter 9](09-heritage.md) gives the sources in full.

## Two modes

The language has two modes.

- **Load mode** is the full language. The engine reads all content files
  once. It resolves disjunctions and defaults. This is one **content
  build**.
- **Runtime mode** is a part of the language. A program makes feature
  structures while it runs. They have no defaults and no disjunction of
  feature structures. Each is one description.

The reason is speed and simplicity. Disjunction and defaults are costly and
hard to reason about. Triangle resolves them one time, at load. At runtime,
the engine only unifies, matches and generalises simple feature structures.

## Properties that the language guarantees

- **Order does not matter.** The order of files and of declarations never
  changes the result. The engine reads all files before it resolves
  anything.
- **Types are closed.** A feature structure can only have the features that
  its type has. A wrong field name is an error at load.
- **Numbers are exact.** A quantity is a whole number of small units. The
  engine never rounds a literal. Arithmetic gives an interval that contains
  the exact result.
- **Results are repeatable.** The same content and the same seed give the
  same entity. The engine does not use the order of a hash table.

## The parts of the project

| Directory | Contents |
| --- | --- |
| `triangle/src`, `triangle/include` | The engine, in C11, with no dependencies |
| `triangle/tools` | The `triangle` command, the language server, the generator of component structs |
| `triangle/odin` | The Odin package that calls the engine |
| `triangle/docs` | The guide, the reference, the API document, and this book |
| `triangle/examples/workshop` | The example content of the guide |
| `lab/content` | The content of Bruggadung |
| `lab/src` | The simulation, in Odin, which uses the engine |

Next: [2. Types and feature structures](02-types.md)
