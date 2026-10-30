# Institutions

## Status and scope

This document is ARCHITECTURE.md §6. It holds decisions as they are made;
the contract follows once enough is decided.

## Decisions so far

1. **Institutions are real organizations made of people**: a licensing
   office, the police, a bank, a court, parts of government. An
   organization is an entity in the world (`Organization`), and its
   members hold offices in it (`OfficeHolder`, as the lab has it for the
   issuing office).
2. **Their rules are real content they issue**: a law, a licensing rule, a
   permit. Whether an act breaks a rule is objectively true, and the
   developer inspector can show it. `authorize(action)` reports that truth.
3. **The world never blocks anything.** An act against the rules commits
   like any other (ACTIONS.md §3: authorization "never blocks an attempt").
4. **An organization acts only through its members, by fiat.** It does
   something only when a member acts in office: a clerk issues a licence,
   an officer arrests, a judge tries. Members decide whether to act with
   the same agency as anyone else (AGENCY.md), on what they know.
5. **Compliance is each agent's choice.** People keep the rules because
   they believe breaking them brings consequences (AGENCY.md §9's beliefs
   about sanctions, weighed against whether they believe they are
   observed), because the legitimate way is easier (a licence from the
   office rather than a forgery), and by a disposition to abide.
