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
   A law forbids a kind of operation, by its type (a **taking**,
   `#Taking`): an operation of that type, or of one under it, is what it
   forbids, whatever its effect (EFFECTS.md decision 10).
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
6. **Wrongs reach an institution through people.** A grievance is a
   claim told to an office holder ("B took the seal reserved for me");
   members also act on what they witness themselves. Either way it is
   ordinary knowledge (KNOWLEDGE.md): the holder weighs who said it and
   decides whether to act.
7. **Sanctions are ordinary operations** an office gives its holders, as
   issuing a permit is: arrest (into custody, a location), fine (a debt,
   as a loan is), confiscate (a take, with a custody claim), revoke (a
   permit marked void). Each is an activity the holder chooses; its target
   complies, resists, or flees, as its own agency decides.
8. **Knowing the rules**: an agent kind starts knowing its society's
   common rules and what breaking them brings (authored in content:
   theft brings arrest); particular rules (an office's permits, a new
   ordinance) are learned like anything else, by reading a posted notice,
   being told, or seeing someone sanctioned.
9. **Ownership passes with the thing when its owner gives it**: handed
   over, paid, given, or put into a container, a thing is the
   receiver's, or the container's owners' (**passing**; EFFECTS.md
   decision 11). So a buyer taking bought grain out of its pack, and a
   seller taking its takings home, break no law; a thief's handing on
   what it took passes nothing. What is lent stays its owner's, in the
   borrower's **keeping** (EFFECTS.md decision 12): the borrower's
   holding and using it breaks no law, and anyone else's taking it
   does. What is nobody's is whoever's takes it up, and their
   household's (decision 13), so what one has gathered, made or caught
   is one's household's before it is home.
