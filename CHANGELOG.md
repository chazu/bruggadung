# Changelog

> **Status: built.** Checked on 2026-11-19 against `5750de8`. Made from
> `git log --since=2026-11-01`: 129 commits and 6 merges, from 2026-11-02
> to 2026-11-19.

What changed in bruggadung since 2026-11-01, by topic. In each topic the
oldest change is first. Each line names its commit. For the reasons and
the details, read the commit or lab/PLAN.md, the lab's log of each step.
For where each design doc stands, read the status line under its title.

## Triangle, the content language

- 2026-11-02: a bound name can name its value, as CUE's do (`4ee82da`).
- 2026-11-02: `triangle fmt`, a formatter, and formatting in the language
  server (`9c1ec47`).
- 2026-11-02: a file's text can be embedded, as CUE's `@embed` does
  (`33b38a1`).
- 2026-11-03: the language server takes Windows paths and file URIs
  (`ec56eee`).
- 2026-11-03: Triangle linked into Odin: the package
  `triangle/odin/triangle` and the lab's content hash (`18407ff`).
- 2026-11-04: a default among text values is text, so it constructs as
  the string (`cb8b4b9`).
- 2026-11-05: topics are packages and own their fields (CONTENT_LANGUAGE.md
  decision 12; `e22f407`).
- 2026-11-05: a runtime value lets go of its syntax (PERFORMANCE.md
  decision 8; `fe0af2e`).
- 2026-11-11: arithmetic goes with a pattern; `math.Min`, `math.Max` and
  `math.Clamp` (EFFECTS.md step 2; `f8e4dd7`).
- 2026-11-12: no `strndup`, for Windows (`316e51b`).
- 2026-11-15: the docs catch up with pattern arithmetic, and the Triangle
  book; a second review corrects it (`afe075d`, `e85e417`, `5e073e9`).
- 2026-11-15: the command-line test counts the workshop's 20 instances,
  which had kept CI red since `afe075d` (`3bb0b51`).
- 2026-11-19: the unifier's path stack grows, and the generation counters
  are 64-bit (REVIEW.md §4.2 defects 1 and 2; `d232152`, merge
  `dc1590a`).
- 2026-11-19: a comment can't bring in the clause prelude, and an unknown
  attribute is an error (defects 9 and 10; `d1be273`, merge `f7987ff`).
- 2026-11-19: the content hash covers attributes and feature names
  (defect 6; `2123232`, merge `4f15898`).

## The lab: the port to Odin, the build and CI

- 2026-11-03: the Objective-C lab builds and passes on Linux and Windows
  with GNUstep, then with clang and make; mulle-sde is dropped (`3f3f96e`,
  `3b55349`).
- 2026-11-03: the lab is ported to Odin, with every test's checks and every
  scenario's hashes kept. The Objective-C lab, GNUstep and the wrapper are
  retired (`3c5090c`, `7ea1136`, `fdf6e50`, `b90232e`). STACK.md says why.
- 2026-11-04: checks build optimised, and the village says what it cost
  (PERFORMANCE.md decisions 5 and 6; `79adce5`).
- 2026-11-05: the scenario hashes name content by name, not by number, so
  content that only adds types leaves them as they were (`4077be6`).
- 2026-11-11: determinism is not a goal: the scenario hashes only show that
  a change moved an outcome (`85e48ed`).
- 2026-11-12: `make check` checks that the content is as `triangle fmt`
  writes it (`316e51b`, `432b8a8`).
- 2026-11-13: a Makefile at the root sends its targets to each part's
  (`93eeaa4`).
- 2026-11-19: a fixed cap that skipped silently is a cap fault, or a list
  that grows (REVIEW.md §4.4, §5 item 5; `f405c3a`, merge `5750de8`).

## Terrain and Orogen

- 2026-11-02: terrain: kinds in content, maps embedded, walls that stop a
  walk (TERRAIN.md step 1; `da0bee5`).
- 2026-11-02: terrain stops sight, and an agent remembers terrain as a bit
  per tile (step 2; `4edc1a8`).
- 2026-11-02: rooms found from terrain, links from doorways, air that
  follows terrain (step 3; `780c340`, `0369f1d`).
- 2026-11-02: terrain that scales: pathfinding, a spatial index, sparse
  water (`b0d57cc`).
- 2026-11-13: OROGEN.md proposes a terrain generator (`1e92aeb`).
- 2026-11-13: Orogen slice 1, the library and a tool that prints a map
  (`9bcd8b1`); slice 2, a generated terrain source in the lab (`1dfc879`);
  slice 3, walking and seeing over relief (`c829b86`).

## The reality bubble and levels of detail

- 2026-11-02: REALITY.md drafted and settled: anchors, levels of detail,
  contact leases, coarse progression and reach, and which systems run at
  each level for each kind (`a73cbc9`, `72e14cc`, `d0d55a6`).
- 2026-11-02: perception and decision only when something happens, from
  queues of wakes (REALITY.md step 1; `4cbd197`, `2ebdfaf`).
- 2026-11-02: anchors, levels and leases (step 2; `b4ac9b2`); reduced
  detail (step 3; `4a5be74`); frozen detail and catching up, for agents
  (step 4; `741294e`).
- 2026-11-02: DETAIL_REGIMES.md: what each system does at each level of
  detail, and what Triangle can model (`5d8518b`).
- 2026-11-12: progressions: a patch's regrowth and a plot's ripening are
  declared, and one domain applies them at every level of detail
  (`a95de4f`).

## Tessera and the watcher

- 2026-11-02: TESSERA.md proposed, and the scene core built: scenes,
  frames and diffs (`9c728ee`, `995e99d`).
- 2026-11-03: Tessera ported to Odin, frame format 1 kept byte for byte
  (`a477437`).
- 2026-11-03: the watcher: a lab world in a window, through Tessera's
  raylib backend, in DejaVu Sans Mono (`88e9b17`, `7ac7f5b`).
- 2026-11-03: looks in content: a `#Look` family, and text and tiles
  themes (TESSERA.md slice 3, VILLAGE.md slice 2; `741bb35`).
- 2026-11-05: the knowledge view in the watcher (VILLAGE.md slice 11;
  `c8cc897`).
- 2026-11-13: the watcher's panes: inspect, the log, the content
  (`343dae7`).

## Knowledge

- 2026-11-03: seen kinds, and identity from context (KNOWLEDGE.md
  decisions 17 and 18; `d07fdee`, `e0d0f0a`, `01d72b2`).
- 2026-11-03: lost and found, and knowing one's own (`8d49aa3`).
- 2026-11-04: a referent nothing holds is forgotten (decision 19;
  `a9858de`).
- 2026-11-04: interpretation weighs only what changed (decision 20,
  PERFORMANCE.md decision 2; `7037b89`).

## Agency, methods and negotiation

- 2026-11-02: agents service machines of their own accord, as diligent
  as they are (`14e9092`).
- 2026-11-04: walking to a place is one activity (AGENCY.md decision 20,
  PERFORMANCE.md decision 1; `39e36f3`).
- 2026-11-06: rationing, and a need's goal weighed again (`5d9d4a5`).
- 2026-11-06: NEGOTIATION.md, built: asking for what a need wants, and
  haggling over a deal (`b7d29fe`).
- 2026-11-06: METHODS.md, built in part: a tool in hand as a subgoal,
  methods as whole ways, goals done beneath, fall-through counted, buying
  rewritten (`f367830`, `cfc42ac`).
- 2026-11-06: what keeps least is cooked first; what lies in one's own is
  one's own (`cdc0c06`).
- 2026-11-06 to 2026-11-07: firewood and the hunt as whole ways; a
  commitment's search window is the errand's; a refused resume checks the
  way; free after an impossible goal (`27bef94`, `c04e6b1`, `d0d7ba5`,
  `c1b98ab`, `f7d5aec`).
- 2026-11-09: handling written once in carrying/; neighbours asked at
  home, by common knowledge (`fa2e056`).
- 2026-11-11: waiting at a neighbour's house ends after an hour
  (`033dc77`).
- 2026-11-12: routines: what a villager keeps to, and when, is content
  (`dd226d4`).
- 2026-11-13: a farmer that believes its plot bare takes seed along
  (`e697518`).

## Effects as data

- 2026-11-11: EFFECTS.md decided, and declared effects built: looking,
  giving, putting, a door, a pump opened (`c30d85c`).
- 2026-11-11 to 2026-11-12: more operations declared: stoking, cooking,
  felling, splitting, lighting a stove, tightening, a cock, a tap,
  putting back, handing over, paying, taking, posting a price, sawing,
  butchering and farming (`53c5d81`, `957871a`, `81c4d26`, `0ff4ddb`,
  `c03b895`, `f4c4e41`, `3ea6110`).
- 2026-11-12: `changes` is built; eating, resting and four more are
  declared (`f8881c3`).
- 2026-11-12: `madeAs`: a declared effect says fields of what it makes;
  hiring is declared (`99afae6`).
- 2026-11-15: a declared effect is resolved against its operation's
  variants (`0a8658b`).

## Institutions, ownership and lending

- 2026-11-11: a law forbids a kind of operation; the village has a law
  against theft and a watch officer (`c03b895`, `e196c46`).
- 2026-11-11: what several own is each one's own; the town keeps its
  watch (`fb37146`).
- 2026-11-12: ownership passes with what is sold, paid, given or brought
  home (`776d11a`).
- 2026-11-12: lending; what is nobody's is whoever takes it up; the
  watch's wage; the household's keeping till the loan's term is over
  (`5a02aa1`, `45facda`).

## The village and its topics

- 2026-11-03: VILLAGE.md, and its slices as GitHub issues #1 to #11
  (`2cb001e`).
- 2026-11-03: hunger over weeks (slice 1; `18bbcdc`, `f3100ec`); the
  village and its homes (slice 3; `db9c219`); cooking and the larder
  (slice 4; `2cb8066`); firewood (slice 5; `dd872c7`).
- 2026-11-04 to 2026-11-05: farming, a plot sown and harvested a row at a
  time (slice 6; `e644ee8`, `0610eec`).
- 2026-11-05: hunting, and animals that sleep at night (slice 7;
  `544260e`, `5272e6a`); perishing (slice 8; `4c09ed7`); the market
  (slice 9; `73968cb`); carrying (slice 12; `742e662`); a week in the
  village, checked in CI (slice 10; `937b28e`).
- 2026-11-05: the village's small open questions (`3469ebe`).
- 2026-11-06: the village's economy: prices by stock, work when short of
  coins (`1fa473d`).
- 2026-11-06: foraging (slice 13; `58f78ea`); preserving food, smoking
  meat first (`e1d99b4`).
- 2026-11-07: cooking takes one portion of a stack (`845329a`).
- 2026-11-12: the shortage before the harvest (`cd04cf2`).
- 2026-11-12: tanning, and leatherwork sold and sewn (`ea87470`,
  `af21e39`).
- 2026-11-12: becoming: where a thing lies may give it another course
  (`c863199`).
- 2026-11-12: a buyer carries its purse in its household's pouch
  (`53dbc96`).
- 2026-11-12: brewing, a topic with no code of its own (`6cbe6dd`).

## Machines and latent assembly

- 2026-11-02: a part can be serviced: some of its wear since it was last
  serviced is undone (LATENT_ASSEMBLY.md decision 8; `fb10787`).

## Performance

- 2026-11-02: no silent caps in the domains; activities indexed and let go
  (`cf285ea`).
- 2026-11-04: PERFORMANCE.md: where the village's time goes, and what to
  change (`6cdc70b`).
- 2026-11-05: what is a function of the content alone is worked out once
  (decision 7; `64195c0`).
- Decisions 1, 2, 5, 6 and 8 are under Agency, Knowledge, the lab and
  Triangle above.

## Docs and process

- 2026-11-02: GLOSSARY.md, the ubiquitous language, and the rule to use it
  (`42fdf38`, `a3f308d`, `86ef7e0`).
- 2026-11-03: content by topic: a directory per topic, each file headed by
  its cut points (lab/content/README.md; `f457593`).
- 2026-11-19: REVIEW.md, an outside review of technical debt and of how
  Triangle is used (`8e10170`).
- 2026-11-19: CLAUDE.md: agents run only the narrowest tests, and the merge
  check runs `make test` (`9c120b8`, merge `58d6010`).
- 2026-11-19: a status line on every root doc, and this changelog
  (REVIEW.md §4.8, §5 item 18).
