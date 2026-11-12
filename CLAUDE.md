# Bruggadung: instructions for agents

## Terminology

GLOSSARY.md is the project's ubiquitous language. Always use its terms, in
its senses, consistently: in design docs, Triangle content, identifiers,
comments, commit messages, and conversation with the user.

- Don't use a word the glossary lists under *Avoid* for that concept.
- A word with more than one sense is written as the glossary's table
  "Words with more than one sense" says (a storey is a **level**; how
  exactly something is simulated is its **detail**).
- A new concept gets a glossary entry in the same change that introduces
  it. A term whose meaning changes is changed in the glossary first.
- If a request or a doc uses a term inconsistently with the glossary, say
  so rather than silently following either.

## Content layout

lab/content/README.md is the rule for arranging Triangle content. In short:

- Each topic (hunger, air, law) is a directory holding everything about
  it, at every level of detail. The root's own `.tri` files hold only the
  vocabulary every topic is written in.
- Every content file starts with a header listing its cut points: what
  changes at each level of detail, what crosses to other topics, and what
  the code does that the content doesn't say. A change that moves a cut
  point updates the header in the same change.

See also lab/AGENTS.md for the lab's build rules.

## Scenario hashes

A deterministic simulation is not a goal, and probability will come into
the simulation. The lab's scenario hashes only show that a change moved an
outcome. That a change would move them is never a cost to weigh against
it and never a reason to shape a design: make the better change,
regenerate the hashes, and say so in the commit.
