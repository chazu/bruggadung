# 9. What Triangle borrows

Triangle has few new ideas. Almost all its parts come from an older grammar
formalism or language. This chapter names the sources and says what
Triangle takes from each. It also says what Triangle does not take, and
what it adds or changes.

The design followed a study of the family of typed feature structure
systems. [CONTENT_LANGUAGE.md](../../../CONTENT_LANGUAGE.md) gives the
findings of that study. The engine is written from the papers. It contains
no code from the other systems.

**How sure the findings are.** The study verified most of its findings
against the primary sources. It only extracted some findings from a source
and did not verify them a second time. This chapter marks those findings
with "(not verified)". All measurements from the papers are from parsers of
about the year 2000. Use them as ratios, not as absolute numbers.

## The family

Typed feature structures come from computational linguistics. In the 1980s
and 1990s, linguists wrote grammars as sets of constraints. The best known
theory of this kind is Head-driven Phrase Structure Grammar (HPSG). A word,
a phrase and a grammar rule are all feature structures. A parser combines
them by unification.

Carpenter gave the mathematics in *The Logic of Typed Feature Structures*
(1992). The terms **appropriateness** and **totally well-typed** in this
book are his.

The table lists the systems that the study covered, and what Triangle
takes from each.

| System | What it is | What Triangle takes |
| --- | --- | --- |
| TDL | The type description language of Krieger and Schäfer. A variant of it is the language of the DELPH-IN grammars | The meaning of the language |
| LKB | The Linguistic Knowledge Builder of Copestake: a grammar development system that reads TDL | With TDL: the type discipline. The LKB has defeasible constraints, which PET removed |
| PET, ACE | Fast parsers for DELPH-IN grammars, in C++ and C | The engine techniques. ACE is also the reference for tests |
| LOGIN, LIFE | Logic programming languages of Aït-Kaci and others, with typed terms in place of Prolog terms | The encoding of meets. Matching by entailment |
| Troll, ConTroll | Systems from Tübingen with strict typing and constraints on types | Closed types, and constraints attached to types. No syntax for implication |
| ALE, TRALE | The Attribute Logic Engine of Carpenter and Penn, and its successor | Nothing directly. ALE is evidence against an abstract machine (not verified) |
| ProFIT | Erbach's Prolog with features, inheritance and templates | The idea of features at fixed positions |
| LiLFeS | A logic programming language with feature structures, from Tokyo. The Enju parser uses it | With CUF: definite clauses over feature structures, and delayed goals |
| CUF | A constraint formalism from Stuttgart | With LiLFeS: the clause layer |
| The TFS system of Emele and Zajac | An early typed feature structure system | Nothing directly. The study covered it |
| CUE | A configuration language. It is not a grammar system, but its implementation notes ground it in typed feature structures and the LKB (not verified) | The syntax |

## TDL and the LKB: the meaning

Triangle takes the type discipline of TDL completely.

| From TDL and the LKB | In Triangle |
| --- | --- |
| Named types in a hierarchy with multiple inheritance | `#Tool: #Physical & #Sized & { … }` |
| Closed, totally well-typed feature structures | A wrong field is an error. A field that is not written is open |
| One type introduces each feature | The language rule of [chapter 2](02-types.md) |
| Meet types that the system generates | `glb[#A,#B]` |
| Types and instances are different | A type is in the hierarchy. An instance is not |
| The constraint of a type applies to each feature structure of the type | The body of a type |

There are two differences in the hierarchy.

- In TDL, two types can unify only if the grammar declares a common
  subtype. Content conjoins mixins freely, so Triangle generates a
  **conjunction type** for each conjunction of types that are not related.
- In TDL, an addendum can add a parent to a type. In Triangle, an addition
  cannot. Thus the primary parent never depends on the order of files.

## CUE: the syntax

TDL is hard to read for people who do not know it. CUE has a clear syntax
for almost the same ideas. Triangle takes its surface from CUE.

| From CUE | In Triangle |
| --- | --- |
| `#Name` for a definition | A type |
| `&` and `\|` | Unification and disjunction |
| Bounds: `>=10 & <=24` | Intervals |
| `*value` for a default | A default |
| `@attribute(...)` | Attributes |
| The order of declarations does not matter | The same guarantee |
| Packages | Packages that own names and features |
| `let`, hidden fields, comprehensions | The same, at load |
| Built-in functions, `strings`, `list`, `math` | A part of them, at load |
| String escapes, raw strings, interpolation | The same |
| `=~` and `!~` with the syntax of RE2 | Constraints on text |
| `@embed` | The text of a file in a field |
| `cue export`, `cue fmt` | `triangle export`, `triangle fmt` |

Where the two disagree, the meaning of TDL wins. Three constructs look like
CUE and mean something different. The design doc calls them **false
friends**.

| Construct | In CUE | In Triangle |
| --- | --- | --- |
| A reference to a field | Constraints go one way | `.a.b` shares a node. Constraints go both ways |
| `#A: #B & {...}` | Two structs are merged. Types are structural | A new named type below `#B`. Types are nominal |
| Defaults that conflict | Both are dropped | The more specific one wins. Only two defaults from unrelated types are both dropped |

The first difference has a strong reason. A pattern must let information go
in both directions. If the simulation learns the size of the nut, the
pattern must constrain the wrench. A one-way reference cannot do that.

Triangle writes a reference with a dot at the start: `.instrument.size`.
The path starts at the root of the declaration. In CUE a reference is a
plain name, found by scope. With the dot, a tool can tell a reference from
a name. A reference also keeps its meaning when an author moves its field
into a nested feature structure.

## PET and ACE: the engine

The DELPH-IN parsers were made fast over many years. Triangle uses their
methods.

| Method | Source | Purpose |
| --- | --- | --- |
| Quasi-destructive unification | Tomabechi; used in PET | A failure allocates nothing |
| The quick check | Kiefer and others (1999); Malouf, Carroll and Copestake (2000) | The engine rejects most failures before unification starts |
| Arenas with mark and release | Callmeier (PET) | Allocation was almost 40% of run time in early PET |
| A table of meets, filled when needed | Callmeier (PET) | As fast as a full table, with much less memory (not verified) |
| Linear subsumption in both directions | Oepen and Carroll (2000) | The base of matching |

PET also removed the defeasible constraints of the LKB from its engine.
Triangle does the same: defaults exist only at load.

The engine keeps a front end for TDL so that it can run the English
Resource Grammar. Then its results can be compared with those of ACE. See
[chapter 8](08-engine.md).

## LOGIN and LIFE: bit vectors and matching by entailment

Two ideas come from the work of Aït-Kaci and his colleagues.

**Meets by bit vectors.** Aït-Kaci, Boyer, Lincoln and Nasr (1989) showed
how to give each type a code. The meet of two types is then the bitwise
AND of their codes. Triangle uses this encoding.

**Matching by entailment.** The study reports this of LIFE (not verified).
LIFE matches the arguments of a function by entailment: it checks if the
call *entails* the pattern of the function. If the call is too general to
decide, the function suspends: it waits for more information.

Triangle takes this idea and changes one part. A match in a simulation
cannot wait for more information. So a match does not suspend. It returns
the third result, *unknown*, with the **residual paths**. The program
decides what to do: permit the action, or find out. Arithmetic keeps the
suspension: a result stays open until its operands are known.

## YADU: defaults

Defaults are difficult in a unification system. The result can depend on
the order in which the defaults apply.

The study reports this of YADU, by Lascarides and Copestake (1999) (not
verified). YADU is a default unification that does not depend on order. A
more specific default wins over a more general one. Defaults are cheap to
combine and costly only to resolve, one time for each object.

Triangle takes the language rule of specificity from YADU. It resolves
defaults one time, when it makes a spec.

Triangle departs from YADU in one case. Where two defaults from unrelated
types conflict, YADU keeps their generalisation: a value that no author
wrote. Triangle drops both, gives a warning, and leaves the field open. An
author then sees the conflict.

## Kiefer and others: no disjunction in the unifier

General disjunction in feature structures is costly. To decide if a feature
structure with disjunctions is consistent is NP-complete (Kasper's
analysis; not verified). Kiefer and others removed disjunction from the
unifier of their system. The grammars became 1.4 to 3 times larger, and
parsing became 2 to 5 times faster.

Triangle does the same. It gives each use of disjunction a different, cheap
meaning:

- A disjunction of atoms is an enum: types in the hierarchy.
- A disjunction in a blueprint is variation or variants, resolved at load
  or at construction.
- At runtime, a feature structure has no disjunction. Uncertainty is a set
  of hypotheses with credences.

## Troll and ConTroll: constraints on types

Meurers (1994) compared ALE with Troll. The comparison reports that the
closed-world reading of the type hierarchy in Troll finds more errors and
permits more inference. It also reports a danger: general implications with
complex conditions make the hierarchy grow very large (not verified).

Triangle takes from Troll and ConTroll the idea that a constraint is
attached to a type. It does not take a general syntax for implication. To
state "each X is Y", an author declares the type X and writes Y in its
body.

The design doc names two sources for closed types: TDL, and the
closed-world typing of Troll.

## ProFIT, and Wintner and Francez: features at fixed positions

Erbach's ProFIT compiles typed terms to Prolog terms with a fixed number of
arguments. Then plain unification of terms does typed unification. Wintner
and Francez also put features at fixed positions.

The plan of Triangle was to give each feature a fixed position in its node.
The engine as built sorts the arcs by feature. The effect is similar: two
nodes of one type have the same features in the same order.

One report shaped a related decision. A thesis that cites Penn (2000) says
that ALE, which encodes feature structures as flat terms, ran faster than
the special abstract machine of LiLFeS. The study did not verify this
report. Triangle has no abstract machine. It has C structs.

## LiLFeS and CUF: definite clauses

LiLFeS and CUF are logic programming languages over feature structures.
Triangle takes two ideas for its clause layer from them:

- definite clauses whose terms are feature structures, solved by
  resolution, as in LiLFeS
- delayed goals: arithmetic in a clause waits until its arguments are known

The design doc names the two systems together as the source of both ideas.

The layer is small. It has no negation and no cut. Clauses are for short
inferences about relations, not for search.

## Sources outside this family

| Source | Idea | In Triangle |
| --- | --- | --- |
| Caves of Qud | An object is a set of parts | A component kind is a type. An entity type conjoins component types |
| Prolog | Definite clauses, resolution, depth-first search | The clause layer |
| Go | `gofmt`: one layout for all source | `triangle fmt` |
| RE2 | Regular expressions in linear time, with no backtracking | The syntax and the guarantee of `=~` |

## What Triangle does not take

| Not taken | Reason |
| --- | --- |
| Disjunction in runtime feature structures | The cost, and the complexity of reasoning |
| Defaults at runtime | A match must not depend on a default |
| A syntax for implication | The hierarchy can grow very large. A constraint in a type body is sufficient |
| An abstract machine | One report (not verified) says that an encoding as terms ran faster than a special machine |
| Structural types | A wrench and a nut with the same fields must stay different |
| Negation and cut in clauses | Clauses are for short inferences only |
| Comprehensions that make declarations | The design doc lists them as not adopted. It gives no reason |
| Comparisons as constraints between open fields | Arithmetic and tags already relate fields |

## What Triangle adds or changes

The sources are about grammars and configuration. A simulation needs more.
Some of these parts are new: they do not come from one of the sources
above. Some change an idea from a source.

| Part | New, or changed from | Purpose |
| --- | --- | --- |
| Quantities with units, as whole numbers of quanta | New | Exact physics with no floating point in content |
| Intervals as partial knowledge, and arithmetic as a constraint on intervals | Changed from the bounds of CUE | "About 19 mm" is a value that the engine can match |
| Variation from a seed, with a seed for each path | New | Different entities from one blueprint. The same seed gives the same entity |
| The spec: a blueprint resolved at load | New | Construction is fast and has no defaults |
| A third result of a match, with residual paths | Changed from the suspension of LIFE | Agents act and plan with partial knowledge |
| Matching against hypotheses with credences | New | Uncertain identity with no disjunction |
| Generalisation along the primary parent, and `@widen` | New | Memory decay |
| `@component` and `@field` | New | The records of the program are generated from content |
| The content hash | New | Saved data names the content that made it |
| Arithmetic that goes with a pattern | New | A pattern computes the effect of an operation |

## Sources

The design doc gives each source by author and year. This list adds the
titles as the author of this book knows them. Check a title before you cite
it.

- Aït-Kaci, Boyer, Lincoln and Nasr (1989). *Efficient implementation of
  lattice operations.*
- Aït-Kaci and Podelski (1993). *Towards a meaning of LIFE.*
- Callmeier (2000). *PET: a platform for experimentation with efficient
  HPSG processing techniques.*
- Carpenter (1992). *The Logic of Typed Feature Structures.*
- Copestake (2002). *Implementing Typed Feature Structure Grammars.*
- Erbach (1995). *ProFIT: Prolog with features, inheritance and templates.*
- Kiefer, Krieger, Carroll and Malouf (1999). *A bag of useful techniques
  for efficient and robust parsing.*
- Krieger and Schäfer (1994). *TDL: a type description language for
  constraint-based grammars.*
- Lascarides and Copestake (1999). *Default representation in
  constraint-based frameworks.*
- Malouf, Carroll and Copestake (2000). *Efficient feature structure
  operations without compilation.*
- Meurers (1994). *On implementing an HPSG theory.*
- Oepen and Carroll (2000). *Ambiguity packing in constraint-based parsing:
  practical results.*
- Tomabechi (1991). *Quasi-destructive graph unification.*

Previous: [8. The engine](08-engine.md).
Next: [10. Triangle as a substrate for simulation](10-substrate.md)
