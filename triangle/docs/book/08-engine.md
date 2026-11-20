# 8. The engine

This chapter explains how the engine does its work. You do not need it to
write content. It helps you to understand the cost of each operation and
the reasons for some language rules.

## The main fact: most unifications fail

In a parser for a large grammar, more than 90% of the unifications fail.
The design expects the same in a simulation: most operations are not
possible for most entities. This is not measured yet for Bruggadung. The
design has one main aim. **A failure must be cheap.**

Each technique in this chapter serves that aim.

## The steps of a load

The loader does these steps one time for each content build:

1. Parse each file.
2. Build the hierarchy. Complete it. Give each type a number. Find the type
   that introduces each feature.
3. Expand the constraint of each type, and each enum.
4. Resolve each instance: unify its declarations, expand its variants, make
   the spec of each blueprint.
5. Check the fields: content sets only fields with the flag `content`, and
   each field of a blueprint is concrete or is variation.
6. Copy the specs into their own arena.
7. Make the index of each family.
8. Compute the content hash.

## The hierarchy

### Meets by bit vectors

The engine gives each type a code: a vector of bits. The meet of two types
is the bitwise AND of their codes, and then one lookup. This method is from
Aït-Kaci and others (1989).

In front of that computation is a table that keeps each meet after the
engine computes it the first time. The engine only looks up this table. It
never goes through it in order, so the table cannot change a result.

Leaf types are not part of the codes. A large body of content has many
leaves, most of them atoms.

### Completion

Where two types have more than one most general common subtype, the loader
makes a meet type (`glb[...]`). After completion, each pair of compatible
types has exactly one meet. This is why unification of two types is one
lookup and never a search.

### Type IDs

Type IDs are small and dense. The loader gives them in topological
order, and by name where the order does not decide. They do not depend on
the order of files.

## Nodes

A node is a C struct of 56 bytes. It has a type ID, its arcs, and the
scratch fields that unification uses. A quantity or an atom is a leaf node,
with its value in the node.

The arcs of a node are sorted by feature. Each feature structure is totally
well-typed, so two nodes of one type have the same features in the same
order. Unification goes through the two lists of arcs together. A lookup of
one feature is a binary search.

## Unification

The engine uses the **quasi-destructive unification** of Tomabechi.

- During unification, the engine writes only into the scratch fields of the
  nodes. Each scratch field has a generation number.
- If unification fails, the engine adds one to the global generation
  number. All scratch fields are then invalid. The cost is constant, and
  the engine allocated nothing.
- If unification succeeds, the engine copies the result out.

The copy **shares** the parts that did not change. This is why the result
of `tri_unify` can point into its inputs. Sharing made the expanded types
of a large grammar 2.4 times smaller: 62 MB in place of 146 MB.

The engine makes the text of a failure only if the caller asks for it.

## Subsumption and matching

The subsumption check is from Oepen and Carroll. It goes through the two
feature structures one time. It tests both directions together. It
allocates nothing.

Matching uses that check:

1. If the pattern subsumes the description, with consistent bindings of the
   tags, the result is *entailed*.
2. If the two cannot unify, the result is *incompatible*.
3. In all other cases the result is *unknown*, and the engine collects the
   residual paths.

## Lazy nodes

A recursive type has no finite expansion. The engine makes a lazy node for
it: a node that has only its type. The constraint of the type applies when
unification adds information to the node. Paths, subsumption, matching and
generalisation read through a lazy node to the expansion of its type.

A lazy node prints as its type.

## Memory

All nodes are in arenas. An arena allocates by a move of a pointer, and it
frees all its nodes together.

The design doc lists four sorts of arena:

| Arena | Lifetime |
| --- | --- |
| Load | One content build |
| Specs | The life of the content. The specs do not change |
| Scratch | One match or one unification. Released with a mark |
| Knowledge | One for each agent. Made smaller by a copy of the live descriptions |

A program measures an arena with `tri_arena_bytes` and a feature structure
with `tri_node_count`. To make a knowledge store smaller, it copies the
live descriptions into a new arena with `tri_copy`, and frees the old one.

## The quick check and the index

The index of a family holds the patterns by the type at the root of each
role. For a description, it returns the patterns whose types are
compatible.

The **quick check** makes the index reject more patterns. For each family,
the engine keeps the types at a small set of paths: those where matches
fail most often. For a description, it compares the types at those paths by a meet
lookup. That rejects most patterns that would fail, before the full match.

On the English Resource Grammar, 13 paths reject 97.6% of the failures, and
the work is 2.2 times faster. The quick check never rejects a pair that
would succeed. A test with random feature structures checks this.

## Determinism

- Each call runs on one thread.
- The engine never goes through a hash table in order.
- Type IDs, the order of arcs, and the order of choices at construction
  are all fixed at load.
- If you change the order of the content files, the specs are identical
  byte for byte, and the content hash is the same. A test checks this.

## The TDL front end

The engine can read a second language: TDL, the language of the DELPH-IN
grammars. `tri_content_load_tdl` reads a grammar into the same syntax tree.

This front end is not for content. It has two purposes:

- **A large test.** The English Resource Grammar (ERG) is a large grammar
  of English. If the engine loads it and gives the same results as a
  second system, that is good evidence that the hierarchy and unification
  are correct.
- **A reference.** ACE is a fast parser for those grammars, written in C.
  The benchmark compares Triangle with ACE on the same work.

The comparison found a real defect. The loader made conjunction types for
TDL too, which changed the hierarchy. Now it makes them only for Triangle
sources. After that correction, the two systems agree:

- Both make the same 4,730 meet types for the ERG.
- Of 597,000 unifications, the same 38,191 succeed in both.

## Measured speed

These results are from an Apple M3, with the ERG of 22 May 2026. They are
measurements of one machine. Use the ratios, not the absolute numbers.

| Measure | Result |
| --- | --- |
| Load of the complete ERG | 0.57 s |
| Unifications of rule daughters with lexical entries | About 1.5 million per second |
| The same work in ACE 0.9.34 | About 1.1 million per second |
| Subsumption tests | About 17 million per second |
| Memory for all expanded types | 62 MB (ACE: 131 MB) |

For content of the shape of Bruggadung, with 20,000 blueprints and 200
operations:

| Measure | Result |
| --- | --- |
| Load, with the spec of each blueprint | 0.18 s |
| Construction from a seed | About 790,000 entities per second |
| Matches after the family index | About 200,000 per second |

## Tests

The engine has tests of each feature of the language. It also has tests
with random input:

- Unification is commutative, associative and idempotent.
- Subsumption, matching and generalisation agree with unification.
- A save and a restore give the same feature structure.
- The order of declarations never changes the content.
- Random source text never makes the loader crash.

A separate test (`tests/leakcheck`) counts allocations. It checks that the
engine frees each allocation, also on the paths for errors.

The random tests found five defects, which are corrected. The
[README](../../README.md) of the engine lists them.

## Known limits

- The generation counters have 64 bits and never reset. They do not wrap
  in practice: 2^64 operations take about 365,000 years.
- A failure's path as text has at most 255 characters. A longer path keeps
  its first and last features, and gives the number of features between
  them.
- The two inputs of a unification must not share a node at two different
  positions.
- The units are a table in `src/units.c`. Content cannot add a unit.
- The engine has no saved image. It loads from source each time. The load
  is fast, so this is acceptable.

Previous: [7. The C API](07-c-api.md).
Next: [9. What Triangle borrows](09-heritage.md)
