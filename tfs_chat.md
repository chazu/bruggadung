What other typed feature structure based systems have been implemented other than cue and what are their functions

Yes. CUE is actually a fairly late and unusual application of an older family of ideas. Most earlier typed-feature-structure systems were built for logic programming, knowledge representation, and computational linguistics, rather than configuration.

The ones I think are most interesting for what you’ve been thinking about are LOGIN, LIFE, TFS, CUF, ALE/TRALE, and LiLFeS.
System	Rough era	What the TFS machinery is used for	What the system does
LOGIN	1986	Typed records/graphs with inheritance (ψ-terms)	Logic programming + knowledge representation
LIFE	early 1990s	Order-sorted feature structures as universal values	Logic + functional + object-oriented constraint programming
TFS	~1990–98	Recursive typed feature structures + constraints	Knowledge representation, relational programming, NLP
CUF	early 1990s	Feature structures + types + relations	General-purpose constraint solving
ALE	1990s	TFS as the terms of a Prolog-like language	Logic programming + grammar parsing
TRALE	2000s	More powerful ALE-style TFS constraints	Parsing, generation, constraint resolution
ConTroll	1990s	Strongly typed FS + implicational constraints	HPSG/constraint grammar development
ProFIT	1990s	Typed feature terms compiled into Prolog terms	Add types/features/inheritance to Prolog
LiLFeS	late 1990s+	High-performance TFS runtime	Logic programming, databases, NLP
LKB / TDL	1990s+	Declarative type hierarchies and feature constraints	Large grammar/lexicon engineering
PET / ACE	2000s+	Efficient execution of TDL/TFS grammars	Production parsers and generators
1. LOGIN — probably the most important ancestor for your purposes

Hassan Aït-Kaci and Roger Nasr's LOGIN is basically:

    Prolog where ordinary first-order terms have been replaced by typed, feature-addressable structures.

Instead of a positional Prolog term like:
person(chaz, engineer, charleston)

you can conceptually have something like:
person(
    name => chaz,
    occupation => engineer,
    location => charleston
)

but person, engineer, etc. live in an inheritance/subsumption hierarchy.

Its ψ-terms are essentially order-sorted feature structures. Unification therefore simultaneously performs ordinary variable unification and type reasoning/inheritance. LOGIN retains Horn-clause logic programming on top of this.

This wasn't purely theoretical. One demonstration, BABEL, implemented a library knowledge system where classes of library objects formed an inheritance hierarchy while Horn clauses represented dynamic facts and queries such as loans and overdue items.

So conceptually:

CUE + Horn clauses ≈ surprisingly close to LOGIN.

That is a major historical precedent for the CUE-complementary-language idea we've been discussing.
2. LIFE — LOGIN taken considerably further

LIFE ("Logic, Inheritance, Functions, Equations") came from Aït-Kaci and collaborators after LOGIN.

It attempted to combine:

logic programming + functional programming + object-oriented programming + constraint solving

around order-sorted feature structures.

Functions could dispatch/match against partially known feature structures; relations performed logic programming; types provided inheritance; unification accumulated information. The formal foundation was a constraint logic programming interpretation of order-sorted feature structures.

This makes LIFE particularly interesting because it starts looking like a genuine general-purpose language based on the same conceptual substrate as CUE rather than merely a grammar notation.

Something like:
truck <: vehicle
truck(weight => W, payload => P)

isn't merely a schema. It can participate in computation, matching and inference.

Of all these systems, LIFE is probably the closest historical example to "what if we built a programming language around this idea?"
3. TFS — typed feature structures as an OO/relational programming substrate

Martin Emele's system was literally called TFS — Typed Feature Structure Representation Formalism.

Its design is fascinating in the context of your Logtalk/CUE thinking because its authors explicitly described it as combining:

    unification-based feature structures
    inheritance-based knowledge representation
    logical variables
    declarative relations
    multiple inheritance
    nondeterminism/backtracking
    existential queries

Its typed feature structures could be recursive and nested and could carry equality and inequality constraints. Types acted rather like OO classes, while a relational programming layer supplied logic-programming behavior.

It was principally used for linguistic knowledge representation, including HPSG grammars and bilingual machine translation.

In other words, somebody really did explore:

    feature-structure constraint language + objects + relations

in the early 1990s.

That's strikingly close to the territory you're circling.
4. CUF — perhaps the closest thing to "CUE plus relations"

CUF, the Constraint Unification Formalism, is another especially relevant one.

CUF combines a feature-structure description language with definite clauses over typed feature terms. It was intentionally designed as a relatively general constraint system rather than merely a parser implementation. Contemporary descriptions explicitly note that it had no specialized parser or generator; it could instead be regarded as a general constraint solver.

That distinction matters.

ALE says roughly:

    Here's a TFS logic system particularly suited to writing grammars.

CUF says something much more like:

    Here is a constraint language whose values are feature structures, plus relations.

So if you're investigating precedents for:
CUE
+
Horn relations
+
unification

I would put CUF near the very top of your reading list.
5. ALE — TFS Prolog

ALE, the Attribute Logic Engine, is one of the canonical implementations of Carpenter-style typed feature structures.

The simplest description is:

    Prolog whose fundamental terms are typed feature structures.

Feature structures support type inheritance, feature appropriateness, variables, equations, inequalities, constraints and disjunction. On top of them ALE provides definite-clause logic programming.

Its other major function is grammar processing: phrase-structure rules operate over typed feature structures, making ALE a popular implementation platform for HPSG and other unification grammars.

So you can think of ALE as having two personalities:
TFS constraint engine
        +
Prolog-ish relational language
        +
grammar/parser machinery

The grammar part received most of the attention, but the underlying programming language is considerably more general.
6. TRALE — ALE evolved

TRALE grew directly out of ALE.

It combines:

    typed feature structures
    constraint logic programming
    phrase-structure parsing
    semantic-head-driven generation
    constraint resolution

The interesting advance is that TRALE became a much more serious environment for expressing the implicational constraints found in sophisticated linguistic theories.

So where CUE tends toward:
A & B

TRALE-world formalisms are also interested in things akin to:
A => B

and relations between structures.

That makes the ALE → TRALE lineage useful if you're wondering what happens when you give a CUE-like lattice rules.
7. ConTroll — TFS + implication

ConTroll is particularly notable because it was designed around strongly typed feature structures plus implicational constraints.

It supported things including:

    typed FSs
    universal constraints
    definite relations
    lexical rules
    complex implication antecedents

and provided a debugger and graphical grammar-development environment.

Conceptually:
X : bird
    ⇒ X.can_fly = true

is moving beyond merely saying:
bird: {
    can_fly: bool
}

You now have rules about structures.

Again, very relevant to your complementary language.
8. ProFIT — compile typed structures down to ordinary Prolog

ProFIT took a pragmatic implementation approach.

It extended Prolog with:

    feature structures
    sort/type inheritance
    feature appropriateness
    templates
    finite domains

but instead of implementing an entirely new runtime, it compiled typed feature terms to ordinary Prolog terms, allowing normal Prolog unification to do most of the work.

Its purpose was largely to let grammar authors write rich declarative structures while still producing practical Prolog programs.

Architecturally this one is interesting for an MVP because it says:

    You don't necessarily need to implement a new VM just because you've added a TFS layer.

That's potentially very relevant if your CUE companion language compiled to an existing relational engine.
9. LiLFeS — a high-performance TFS programming language

LiLFeS is a genuine logic programming language built around typed feature structures.

It provides:

    TFS values
    predicates
    fast feature-structure unification
    a feature-structure database
    C++ APIs/libraries

It was specifically engineered to make expensive TFS operations fast and became infrastructure for the Enju HPSG parser.

LiLFeS is interesting if you're thinking about TFSs not merely as configuration descriptions but as an in-memory computational data model.
10. LKB / TDL / DELPH-IN — probably the most mature TFS ecosystem

The Linguistic Knowledge Builder (LKB) and the DELPH-IN ecosystem use TDL — Type Description Language.

TDL definitions look remarkably CUE-ish:
typename :=
    supertype &
    [ FEATURE value,
      OTHER-FEATURE other-value ].

Types form an inheritance hierarchy, and type constraints themselves are typed feature structures.

LKB is the interactive grammar-development environment: inspect structures, debug grammars, parse and generate.

The same representation then feeds optimized execution engines:

    PET — high-efficiency batch parser
    ACE — high-performance parser and generator

That ecosystem is still alive; DELPH-IN continues to maintain substantial grammars in multiple languages.
The historical family tree is roughly this

You can simplify quite a lot of history into:
semantic networks / frames
           │
           │
           ▼
      feature structures
           │
     + type lattice
           │
           ▼
 order-sorted / typed
   feature structures
           │
     ┌─────┼──────────┐
     │     │          │
     ▼     ▼          ▼
  LOGIN   TFS     Carpenter TFS
     │                │
     ▼                ├── ALE ── TRALE
   LIFE               │
                      ├── LKB / TDL
                      │      ├── PET
                      │      └── ACE
                      │
                     CUE

That genealogy is slightly simplified, but the conceptual relationship is real: CUE explicitly defines subsumption and unification over typed attribute/feature structures, with unification as the greatest lower bound in the information ordering.
And this changes how I'd frame our CUE + Logtalk idea

The thing we were imagining has actually been explored in pieces much more thoroughly than it first appears.

CUE has essentially retained:

types + features + subsumption + unification + constraints

and discarded most of:

logical variables + Horn clauses + relations + search + implication + procedural computation

Earlier systems explored almost every combination:
                  Typed feature structures
                           │
          ┌────────────────┼────────────────┐
          │                │                │
     constraints       relations         functions
          │                │                │
         CUE          LOGIN / ALE         LIFE
                           │
                       CUF / TFS
                           │
                  implication / rules
                           │
                    ConTroll / TRALE

And that is why I increasingly think the clean version of your proposed companion language should not try to recreate Logtalk wholesale.

A particularly compelling foundation is almost exactly the old CUF/LOGIN proposition:

    CUE values + logical variables + Horn relations + queries.

Keep CUE responsible for the information lattice and structural constraints. Add only a relational layer that can say things CUE can't naturally express:
reachable(A, B) :-
    edge(A, B).

reachable(A, C) :-
    edge(A, B),
    reachable(B, C).

while its terms remain CUE-like feature structures rather than Prolog's positional functors.

That would have a surprisingly distinguished lineage. CUF, LOGIN, LIFE and TFS are the four systems I'd investigate next, because each represents a different answer to almost exactly the design question you've been asking.
