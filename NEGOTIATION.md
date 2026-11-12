# Negotiation

## Status and scope

Decisions; built in the lab (lab/PLAN.md, `test_deals`). This document extends
[AGENCY.md](AGENCY.md) §5 (methods), §7 (commitments: a debt), decision 15
(employment is a deal), decision 16 (what a thing is worth) and decision 18
(a loan's terms). It covers how an agent gets from another what one of its
goals wants: **asking**, a general method any goal can fall back on, and
**negotiation**, the open-ended haggling over a **deal** that every asking
is. It covers what a deal leaves behind (a **debt**, gratitude, a credit),
and the **dispositions** that make some agents give freely, some lend only
on terms, and some never ask at all.

What it doesn't cover yet: deals among more than two, deals written down
or posted (AGENCY.md decision 15 has the posted kind for employment),
bluffing, and an institution enforcing a deal (INSTITUTIONS.md); each is an
open question below.

The lab had pieces of this before: Scenario 3's borrowing (`#Request`, a
plea to lend the very thing the lender holds, answered `#Granted` or
`#HaveNone`), asking for work (`#AskWork`), and the market's sale at a
posted price (`#Buy`, VILLAGE.md decision 9). Each was written into one
goal's methods. They stay as they are; what this document adds is general.

## Decisions so far

1. **Asking is one general method, for any goal.** When no method of a
   goal holds, and a method's precondition wants something in the agent's
   hand that it doesn't hold, the agent may ask someone else for a thing
   like it. Content doesn't write "ask for food" or "ask for a nail": the
   engine reads what is wanted from the methods themselves (the slot's
   pattern, its `place` loosened to anywhere), in their order of rank. Told
   there is nothing like the first, it asks for what the next method
   wants. A starving agent asks for a meal; told there is none, for raw
   food, which its other methods can use. (A meet of types the content
   never named prints as `glb[A,B]`; it is said as its first part, `A`, the
   meet as written.)
2. **Asking is weighed, and is for needs.** It costs the asker something
   to ask: a fixed cost (`BG_ASK_COST`, 30) and half its **pride**. It asks
   only when the goal is worth more than that (AGENCY.md decision 14:
   worth in dB), and only for a goal a need presses, or one serving it
   with no duty between. At the default dispositions that means a need
   near its worst (hunger past 90); a humble agent asks sooner, a proud
   one hardly ever. A duty asks nothing of others yet: a seller short of
   goods asked its neighbours for some to sell, and a buyer for coins
   (open question 8).
3. **It asks those it knows, kin first.** Whom it asks: agents it believes
   present or knows where to find, by loyalty to them (AGENCY.md decision
   12), then those it believes have something like it (in hand, or at
   their house), then by nearness; no more than three for each time the
   goal is adopted, and none it has asked since. Not those it believes
   live where it does (seen keeping things in what is its own, or whose
   bed is by its own: its household): they have what it has. Seen just
   now, it walks to them, wherever it meets them; else to their house
   (where it has seen them keep things, or their bed: in the village,
   common knowledge, KNOWLEDGE.md decision 27), and waits there for them
   to come home, an hour at most: then it counts them asked. Two hungry
   neighbours each waiting at the other's house waited for good.
4. **Every asking is a negotiation over a deal.** The ask (`#Ask`) says
   what is wanted, how many, the deal the asker proposes, and the need it
   is for. A deal is one of:
   - a **gift**: nothing owed;
   - **in kind**: as much again, some time: a debt both understand without
     a date, a kindness to be returned;
   - a **loan**: an explicit agreement, back by a date (its `term`):
     either the very thing, or as much again and `extra` more (interest
     in kind);
   - a **sale**: so many coins for it, paid on the spot.

   `#Request` stays as Scenario 3 has it: a plea to lend the very thing in
   the lender's hand, answered yes or no, with no haggling.
5. **Each side values each deal, in the units of value** (AGENCY.md
   decision 16), and prefers the deal worth most to it.
   - **The one asked** gives up the thing: its value to it, raised by its
     own need (a hungry farmer values grain more), and by how little it has
     of it at home, on the same curve a seller's price follows (money/'s
     `asks`, against the kind's `plenty`): it spares little of what it is
     short of. What the deal brings back: for a gift, **kindness** (its
     **generosity**, more for the asker's need as it believes it, plus its
     loyalty to the asker); in kind, as much again, as far as it trusts the
     asker to return it, and half the kindness; a loan, as much again and
     the extra, as far as it trusts the asker, less half its kindness for
     each extra (charging a neighbour in need is unkind: the generous give
     or ask it back in kind, the mean lend at interest); a sale, the coins,
     at a coin's worth (`BG_COIN_TENTHS`: a portion of grain, worth 10, is
     4 coins). It asks coins only of one it sees holding them, no more than
     their mass makes (a count isn't seen).
   - **The asker** gains the thing: its value to it, raised by its need. A
     deal costs it: a gift, its pride; in kind, as much again as its
     **reciprocity** disposes it to return; a loan, as much again and the
     extra, as its **honesty** disposes it to repay, a little more for a
     short term; a sale, the coins, valued the same way, and only as many
     as it holds.

   No deal is worth nothing to either. A deal worth less than nothing to
   one side, that side won't make.
6. **Haggling is open-ended.** The asker opens with the deal worth most
   to it. Each answer is one of: agree (`#Agree`), a counter-offer
   (`#Offer`, which expects an answer as the ask did), walk away
   (`#Refuse`), or nothing like it to give (`#HaveNone`). Each side
   concedes as the rounds go: its **target** falls from the most a deal
   could be worth to it toward nothing, slower the more **shrewd** it is,
   reaching nothing once its **patience** is spent. Each round it agrees
   to the other's offer if that meets its target; otherwise it offers, of
   the deals that meet its target, the one worth least to itself (the most
   it can concede); with patience spent and nothing offered worth more
   than nothing to it, it walks away. So it ends, however long it goes:
   in a deal both prefer to none, or in none. The deals offered: a gift,
   in kind, a loan of a day or a week with up to three more (of the very
   thing, if it isn't used up), and sales at half to three times its
   price. Its patience is one round and one more for every 25; its target
   in round t of P is the best less `best * t * (150 - shrewdness) /
   (100 * P)`, never below nothing.
7. **Agreed, the one asked hands it over.** From its hands if it holds
   something like it (`give_some`: so many of a stack split off into the
   other's free hand, two seconds); otherwise it fetches it from its own
   containers (its larder) and brings it. Asked, it gives from its own
   containers only at home, eight tiles from them at most: help comes
   when it is home. Either is a commitment with a
   window of an hour (AGENCY.md §7). The asker waits, an hour at most; once
   it holds something like it, it goes on.
8. **What a deal leaves.**
   - **A gift**: gratitude. The asker trusts the giver more, by its
     reciprocity.
   - **In kind**: a debt both hold, with no date. An asker disposed to
     return kindness (reciprocity at least half) takes up repaying it, a
     kept commitment from a day on to a fortnight: as much again, from
     what it holds, or from home if it has five times as much there
     (`BG_SPARE`), given into the creditor's hand, and said (`#Repaid`);
     tried again every six hours while it can't (a goal's `retry`), and
     not while it doesn't know where the creditor is. The creditor holds
     it as a **credit**. Unrepaid at a fortnight, the
     creditor trusts the debtor less (half a wrong).
   - **A loan**: a debt with its term (AGENCY.md decision 18), a
     commitment repaid in the last seventh of it: the very thing, or as
     much again and the extra. Unrepaid by the date, the lender trusts the
     borrower less by a wrong (`BG_WRONGED`). A grievance to an office
     (INSTITUTIONS.md) is open.
   - **A sale**: the coins, paid within the hour, from the purse in hand.

   Repaid, the creditor's credit is cleared and it trusts the debtor more.
9. **The dispositions** (AGENCY.md §9's per-agent weights, 0 to 100):
   **generosity** (how much kindness a gift is worth to it; default 30),
   **reciprocity** (how much it means to return what it is given, and how
   grateful it is; 50), **pride** (what asking, and a gift, cost it; 30),
   **shrewdness** (how slowly it concedes; 50), **patience** (how many
   rounds it haggles before walking away; 50: three). They are deals/'s
   fields on `#Agent`. With the existing
   `helpful` (whether it answers at all, AGENCY.md's social generator),
   `honesty` (whether it means to repay), `trusting`, and its trust in and
   loyalty to the other, they decide how common each deal is between whom:
   kin give, strangers lend on terms or sell, the proud owe rather than
   take, the shrewd haggle long.
10. **Loans in general.** A loan is of the very thing (an axe, back the
    same) or of a quantity of a kind (three portions of grain, back as
    much again). Things used up (food, fuel, coins) are lent only by
    quantity: repaying gives any thing like it, as many. A loan of the
    very thing is **lent** (GLOSSARY.md; EFFECTS.md decision 12): it
    stays the lender's own, in the borrower's keeping, till it is given
    back. A loan by quantity is given, and is the borrower's.
11. **A need's goal dropped as impossible is weighed again when what the
    agent holds changes**, not only two hours on (AGENCY.md decision 27):
    a portion handed to a starving agent is eaten at once. Likewise when
    someone it could ask comes by, seen just now and not asked lately:
    wherever it meets them. (Whoever it had seen in the last minute, as a
    reason, changed as it walked, and a hunter weighed eating, found it
    impossible and set off home, again and again, in one minute.)
12. **Eating from a stack held eats one of it.** An agent handed a sack of
    grain ate all sixty portions in a minute; `eat` now takes one, and the
    rest stays in hand.
13. **What is put into what is its own, it notices** (KNOWLEDGE.md §10's
    salience): who keeps things in its larder, so who eats from it with it.
    Another's comings and goings it didn't keep at all, so it never knew
    its household from its neighbours, and asked its kin, as hungry as
    itself.

## The negotiation, step by step

Ada, hunger 100, her larder empty; Bo, a farmer with grain at home.

1. Ada's hunger goal: no method holds. Asking is worth her hunger (+50)
   against her pride and the cost of asking (+45): she asks. The first
   method wants a meal in hand: she walks to Bo (the nearest she knows)
   and says `#Ask & { what: <a meal>, units: 1, deal: #InKind, need: 100 }`
   (in kind: owing it is worth more to her than her pride would let a gift
   be).
2. Bo has no meal: `#HaveNone`. Ada asks again, for what her next method
   wants: raw food.
3. Bo has grain. Parting with a portion costs him its value (10). In kind
   brings back a portion as far as he trusts her (8 of 10) and half his
   kindness (15, at generosity 30 and her need as he believes it): +5, as
   much as a gift would be to him, his best. Ada's ask meets his target:
   `#Agree`.
4. Bo fetches a portion from his larder and gives it to her. What Ada
   holds has changed: her hunger goal is weighed again, and she eats it
   raw, or cooks it.
5. Ada owes Bo a portion, and holds it as a debt; reciprocity 50, she
   takes up repaying it. Bo holds a credit. When Ada next has grain to
   spare, she gives him a portion, and Bo trusts her more.

Had Bo been mean (generosity 0) and shrewd, he would have answered
`#Offer & { deal: #Loan & { extra: 3, term: 1d } }`, and Ada, that worth
+37 to her against a target of +37, `#Agree`. Had he trusted her little
and seen coins in her hand, he would have asked 12 coins; Ada would have
offered the loan; Bo, the 12 coins again; and Ada, her target fallen,
agreed and paid.

## Content and code

- **content/deals/deals.tri**: the five dispositions on `#Agent`, the
  deals (`#Gift`, `#InKind`, `#Loan`, `#ForCoins`), the utterances (`#Ask`,
  `#Offer`, `#Agree`, `#Refuse`, `#Repaid`), `give_some`, the goal of
  handing over (`handed_over`) and of repaying in kind (`repaid_in_kind`),
  each done by a step the code carries out (`#HandOver`), as the market's
  `#Purchase` is. The header lists the cut points.
- **src/agency_deals.odin**: asking, valuing, haggling, handing over,
  debts and credits; a mind's negotiations and what it owes and is owed
  are saved with it.

## Scenarios

1. **A neighbour asked.** Hungry past asking, Ada asks Bo for food. Bo,
   generous, gives a portion (a gift) and Ada eats it at once; Bo mean and
   shrewd, they haggle to a loan, and Ada owes it; Bo short of food
   himself, he walks away; with nothing like it, he says so, and she asks
   for what her next method wants.
2. **A sale.** Bo would rather sell; Ada has coins: they settle on a price
   between Bo's opening and Ada's, and she pays.
3. **Debts.** Ada repays in kind once she has grain to spare, and Bo
   trusts her more; a loan unpaid past its term, Bo trusts her less.
4. **The village.** Before the harvest, the hungriest ask their neighbours,
   and the farmers' surplus reaches the hunters (VILLAGE.md).

## Open questions

1. **Bluffing.** An asker could overstate its need, a giver its own
   shortage; the hearer would weigh what it is told by its trust, as any
   claim (KNOWLEDGE.md). Lying is AGENCY.md decision 11's.
2. **Enforcement.** A loan unpaid is only lost trust. Whether it is a wrong
   an office takes up (a grievance, a fine) is INSTITUTIONS.md's.
3. **More than two.** A household asked as one; a go-between; a deal that
   others witness and so hold the parties to.
4. **Deals written down or posted**, as employment's can be: an IOU.
5. **Reputation.** What others hear of how an agent keeps its debts.
6. **What can be asked for** that isn't held: help with a task, a place to
   sleep, knowledge (asking where something is, `#WhereIs`, is the one kind
   so far).
7. **Asking a household's kin for what is the household's**: today kin
   share a larder by each owning it.
8. **A duty that asks.** A seller short of goods, a buyer short of coins:
   what a duty may ask of others, and of whom (its employer, its
   household).
9. **Valuing coins.** A coin's worth is one constant; it should follow
   the agent's own prices and how many it has.
10. **Where neighbours live.** Settled (2026-11-09): common knowledge,
    said by kind (KNOWLEDGE.md decision 27). In the village everyone knows
    whose each bed is, and everyone by sight.

## Terms

| Term | Meaning |
| --- | --- |
| Asking | The general method: getting from someone else a thing like what a method wants in hand |
| Negotiation | The exchange over a deal that every asking is: ask, offers, agree or walk away |
| Deal | A gift, in kind, a loan or a sale, with its terms |
| Debt in kind | What an agent owes for something given in kind: as much again, no date |
| Credit | What another owes the agent: the creditor's side of a debt |
| Target | What a deal must be worth to a side this round for it to agree |
| Kindness | What giving is worth to a giver: its generosity, the asker's need, its loyalty |
