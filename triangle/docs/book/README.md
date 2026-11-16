# The Triangle book

This book explains Triangle, the content language of the Bruggadung
project. It has three parts:

- the language: how to write content in it
- the C API: how a program loads content and uses it
- the use of Triangle in Bruggadung: how a simulation is built on it

The book is written in simplified technical English. The sentences are
short. A technical term has one meaning. The terms are those of
[GLOSSARY.md](../../../GLOSSARY.md), the glossary of the project.

## Chapters

| Chapter | Contents |
| --- | --- |
| [1. What Triangle is](01-introduction.md) | The problem that Triangle solves, and its main ideas |
| [2. Types and feature structures](02-types.md) | Types, features, enums, the hierarchy |
| [3. Blueprints](03-blueprints.md) | Instances, quantities, defaults, variation, construction |
| [4. Patterns and matching](04-patterns-and-matching.md) | Tags, references, the three results of a match, families |
| [5. Computed values](05-computed-values.md) | Arithmetic, data, text |
| [6. Clauses, packages and tools](06-clauses-packages-tools.md) | Definite clauses, packages, the `triangle` command |
| [7. The C API](07-c-api.md) | How to load content, construct, match and unify from C and Odin |
| [8. The engine](08-engine.md) | How the engine does its work, and how fast |
| [9. What Triangle borrows](09-heritage.md) | The grammar formalisms and languages that Triangle comes from |
| [10. Triangle as a substrate for simulation](10-substrate.md) | How the lab of Bruggadung uses content |
| [11. Practices for reusable models](11-modelling-practices.md) | Ways to model phenomena that the authors of the content found useful |
| [12. A worked example: brewing](12-worked-example.md) | One topic, read from start to end |

## How to read this book

- To write content, read chapters 1 to 6, then 11 and 12.
- To embed the engine in a program, read chapters 1, 4, 7 and 8.
- To learn why Triangle is as it is, read chapters 1 and 9.
- To work on the simulation, read chapters 10 to 12.

## The other documents

The book does not replace the other documents. It gives the ideas and the
reasons. The other documents give each language rule and each function in
full.

| Document | Contents |
| --- | --- |
| [GUIDE.md](../GUIDE.md) | A tutorial that builds one content file |
| [REFERENCE.md](../REFERENCE.md) | The grammar, each attribute, the units, each diagnostic |
| [API.md](../API.md) | Each function of the C API and the Odin package |
| [CONTENT_LANGUAGE.md](../../../CONTENT_LANGUAGE.md) | The design doc of the language, with the reason for each decision |
| [EFFECTS.md](../../../EFFECTS.md) | How content states the effect of an operation |
| [lab/content/README.md](../../../lab/content/README.md) | The rule for the layout of content |

If the book and the reference disagree, the reference is correct. If the
reference and the code disagree, the code is correct.

## The examples

- Most examples of chapters 2 to 6 are the workshop content of the guide.
  The files are in [examples/workshop](../../examples/workshop). A test
  (`test_docs_guide`) loads the guide and checks its results. The test
  does not read this book.
- Some examples of chapters 2 to 6 are not in the workshop: `maker`,
  `ada_wrench`, `#Person` and `#Larder`. They are small illustrations.
  Some are from the content of the lab, and the text says so.
- The examples of chapters 10 to 12 are from the content of the lab, in
  [lab/content](../../../lab/content). They were correct in November 2026.
  The content changes, so read the files for the current text.
- Where an example is shortened, `...` shows what is omitted.
- A block marked `cue` is Triangle source. A block marked `text` is output.
  A block marked `c` is C.

## Words used in this book

| Word | Meaning |
| --- | --- |
| Content | The Triangle source that authors write: types, blueprints, operations, goals |
| Topic | One part of the content that crosses systems, such as hunger. Each topic has its own directory |
| Engine | The C library that loads content and operates on it |
| Bruggadung | The project: a roguelike with many simulated systems. The framework comes first, then the game |
| Lab | The simulation laboratory of the project, in Odin, in `lab/`. It implements the systems and proves them by scenarios |
| Program | The code that uses the engine. In this project, the lab |
| Entity | Anything with identity in the simulation: a person, a tool, a claim |
| Blueprint | Content that says how to make entities of one kind ([chapter 3](03-blueprints.md)) |
| Operation | Content that says what an agent can do: to take, to eat ([chapter 10](10-substrate.md)) |
| Feature, field | A feature is a named attribute of a type. In content, an author writes it as a field |
| Open, concrete | A value is concrete when it is one exact value. It is open when it is not concrete: a range, or a type |
| Percept | What an agent perceives of an entity at one time, as a description |
| Referent | What an agent takes to be one entity, from what it perceived ([chapter 10](10-substrate.md)) |
| Seed | A 64-bit number from which construction makes its choices. The program gives one to each entity |
| Load | To read all content files and resolve them. The result is one **content build** |
| Feature structure | A graph of typed nodes. All content is made of feature structures |
| Atom | A value that is a name, written as a string: `"steel"` ([chapter 2](02-types.md)) |
| Pattern | A feature structure that a program matches against descriptions ([chapter 4](04-patterns-and-matching.md)) |
| Description | A feature structure that describes something: what an agent knows, or what is true |
| Level of detail | How exactly the simulation simulates something: full, reduced, abstract or frozen |
