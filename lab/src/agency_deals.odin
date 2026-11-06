package lab

/*
 * Asking and negotiation (NEGOTIATION.md; content/deals/).
 *
 * Asking is a general method: when no method of the agent's goal holds,
 * and a method's precondition wants something in its hand, the agent asks
 * someone it knows for a thing like it, if the goal is worth more than
 * asking costs it (BG_ASK_COST and its pride). What it asks for is the
 * slot's pattern with its place loosened, method by method in rank order;
 * told there is nothing like one, it asks the same one for the next.
 *
 * Every asking is a negotiation over a deal: a gift, in kind, a loan, a
 * sale. Each side values a deal in the units of value (AGENCY.md decision
 * 16): the one asked, what the deal brings back (kindness, as much again as
 * far as it trusts the asker, coins) less what parting costs it (its value,
 * raised by its need, and by how little it has of it at home); the asker,
 * what the thing is worth to it (raised by its need) less what the deal
 * costs (its pride, as much again as it means to return, coins). Each
 * round, each side's target falls from the best a deal could be worth to
 * it toward nothing, slower the shrewder it is, reaching it once its
 * patience is spent: it agrees to what meets its target, or offers what
 * meets it and is worth least to itself, or, its patience spent, walks
 * away.
 *
 * Agreed, the one asked hands it over (`handed_over`, a commitment of an
 * hour); the asker owes as much again (`repaid_in_kind`), for a loan by its
 * term, in kind within a fortnight if its reciprocity has it, and for a
 * sale at once, in coins. Each side remembers what is owed (`Owed`):
 * repaid, the creditor trusts the debtor more; unrepaid by the date, less.
 */

import "core:fmt"
import "core:strings"
import tri "../../triangle/odin/triangle"

BG_MAX_TALKS   :: 8
BG_MAX_OWED    :: 16
BG_ASK_COST    :: 30                      /* what asking costs anyone, before its pride (dB) */
BG_ASK_PEOPLE  :: 3                       /* whom it asks, each time it takes the goal up */
BG_DEAL_WAIT   :: i64(5000)               /* ms it waits for the other's answer */
BG_HANDOVER    :: i64(3600000)            /* ms: an hour to hand over what was agreed */
BG_IN_KIND     :: i64(14 * 86400000)      /* a debt in kind is repaid within a fortnight */
BG_SPARE       :: 5                       /* it repays in kind only with five times as much at home */
BG_REPAID      :: 3                       /* trust gained in one who repays */
BG_COIN_TENTHS :: 25                      /* what a coin is worth, in tenths of a point: a portion of grain is four */

Deal_Kind :: enum u8 {
	None,
	Gift,
	In_Kind,
	Loan,
	For_Coins,
}

/* A deal over a thing (content/deals/'s #Deal). */
Deal :: struct {
	kind:  Deal_Kind,
	same:  bool,             /* a loan of the very thing */
	extra: i32,              /* a loan's interest, in things like it */
	term:  i64,              /* a loan's term, ms */
	sum:   i32,              /* a sale's coins, in all */
}

Talk_State :: enum u8 {
	Open,
	Agreed,
	Ended,
	None_Like,               /* asked, the other had nothing like it */
}

/* A negotiation the agent is in, as the asker or the one asked. */
Talk :: struct {
	with:    u32,            /* referent */
	asking:  bool,
	state:   Talk_State,
	goal:    cstring,        /* interned: the asker's goal it is for */
	what:    cstring,        /* interned: what is asked for, a pattern */
	units:   i32,
	wanting: i32,            /* the need it is for, as the asker said it */
	rounds:  i32,            /* the deals this side has proposed */
	want:    i32,            /* the asker's: which of its goal's wants */
	last:    Deal,           /* the last deal proposed, by either */
	since:   i64,            /* ms */
}

Owed_Kind :: enum u8 {
	Hand_Over,               /* the agent hands it to `other`, as agreed */
	Debt,                    /* the agent owes it `other` */
	Credit,                  /* `other` owes it the agent */
}

/* What is owed, by the agent or to it (NEGOTIATION.md decision 8). */
Owed :: struct {
	kind:     Owed_Kind,
	other:    u32,           /* referent */
	what:     cstring,       /* interned: a pattern */
	units:    i32,           /* how many, still; 0, given, to be said */
	explicit: bool,          /* a loan or a sale, not in kind */
	due:      i64,           /* ms */
	since:    i64,           /* ms */
}

/* One side's view of a negotiation: what it values the thing at, and its
 * dispositions. */
@(private = "file")
Deal_Side :: struct {
	giving:      bool,
	base:        i32,        /* a thing's value to it, at ease */
	full:        i32,        /* and raised by its needs */
	units:       i32,
	pct:         i32,        /* giving: what parting costs, by its stock, percent */
	price:       i32,        /* coins a unit, by the thing's pricing; 0, none */
	kindness:    i32,
	trust:       i32,        /* in the other */
	pride:       i32,
	reciprocity: i32,
	honesty:     i32,
	shrewd:      i32,
	patience:    i32,
	coins:       i64,        /* asking: the coins it holds */
	consumed:    bool,       /* used up: lent only by quantity */
}


/* --- C buffers (as agency_agency.odin's) ------------------------------------------------ */

@(private = "file")
dput :: proc(buf: []u8, s: string) {
	n := min(len(s), len(buf) - 1)
	copy(buf[:n], s[:n])
	buf[n] = 0
}

@(private = "file")
dstr :: proc(buf: []u8) -> string {
	return string(cstring(raw_data(buf)))
}

@(private = "file")
dtext :: proc(tc: ^tri.Content, node: ^tri.Node, path: cstring, buf: []u8) -> bool {
	tmp: [256]u8

	v := tri.at(tc, node, path) if node != nil && path != nil else node
	if v == nil do return false
	tri.print(tc, v, raw_data(tmp[:]), size_of(tmp))
	n := len(dstr(tmp[:]))
	if n < 2 || tmp[0] != '"' || tmp[n - 1] != '"' do return false
	dput(buf, string(tmp[1:n - 1]))
	return true
}

@(private = "file")
dint :: proc(tc: ^tri.Content, node: ^tri.Node, path: cstring, fallback: i64) -> i64 {
	lo, hi: i64
	v := tri.at(tc, node, path) if node != nil else nil
	if v == nil || tri.node_interval(v, &lo, &hi) == 0 || lo != hi do return fallback
	return lo
}

@(private = "file")
dbound :: proc(b: [^]Slot_Binding, n: i32, slot: string) -> u32 {
	for i: i32 = 0; i < n; i += 1 do if string(b[i].slot) == slot do return b[i].referent
	return 0
}

@(private = "file")
is_type :: proc(tc: ^tri.Content, node: ^tri.Node, name: cstring) -> bool {
	t := tri.type_named(tc, name)
	return node != nil && t != 0 && tri.subtype(tc, tri.node_type(node), t) != 0
}


/* --- deals ---------------------------------------------------------------------------- */

deal_text :: proc(d: Deal) -> string {
	switch d.kind {
	case .Gift:      return "#Gift"
	case .In_Kind:   return "#InKind"
	case .Loan:      return fmt.tprintf("#Loan & {{ back: \"%s\", extra: %d, term: %dms }}", "same" if d.same else "like", d.extra, d.term)
	case .For_Coins: return fmt.tprintf("#ForCoins & {{ sum: %d }}", d.sum)
	case .None:
	}
	return "#Deal"
}

/* How a deal reads in a log. */
deal_name :: proc(d: Deal) -> string {
	switch d.kind {
	case .Gift:      return "a gift"
	case .In_Kind:   return "in kind"
	case .Loan:
		return fmt.tprintf("a loan%s%s, back in %dd", " of the very thing" if d.same else "",
		                   fmt.tprintf(", %d more", d.extra) if d.extra > 0 else "", d.term / 86400000)
	case .For_Coins: return fmt.tprintf("for %d coins", d.sum)
	case .None:
	}
	return "no deal"
}

@(private = "file")
deal_of :: proc(tc: ^tri.Content, node: ^tri.Node) -> Deal {
	back: [16]u8
	if is_type(tc, node, "#Gift") do return {kind = .Gift}
	if is_type(tc, node, "#InKind") do return {kind = .In_Kind}
	if is_type(tc, node, "#Loan") {
		return {kind = .Loan, same = dtext(tc, node, "back", back[:]) && dstr(back[:]) == "same",
		        extra = i32(dint(tc, node, "extra", 0)), term = dint(tc, node, "term", BG_LOAN_TERM)}
	}
	if is_type(tc, node, "#ForCoins") do return {kind = .For_Coins, sum = i32(dint(tc, node, "sum", 0))}
	return {}
}


/* What a deal is worth to this side (NEGOTIATION.md decision 5); false if
 * it can't be (a loan of the very thing used up, coins it hasn't). */
@(private = "file")
deal_value :: proc(s: ^Deal_Side, d: Deal) -> (i32, bool) {
	tf := s.trust + BG_TRUST_LIMIT      /* 0 to twice the limit: how far it trusts the other */
	if d.kind == .Loan && d.same && s.consumed do return 0, false
	if s.giving {
		cost := s.full * s.units * s.pct / 100
		back: i32
		switch d.kind {
		case .Gift:      back = s.kindness
		case .In_Kind:   back = s.base * s.units * tf / (2 * BG_TRUST_LIMIT) + s.kindness / 2
		/* interest is unkind: so much less, for each more, as it is kind */
		case .Loan:      back = s.base * (s.units + d.extra) * tf / (2 * BG_TRUST_LIMIT) - s.kindness * d.extra / 2
		case .For_Coins:
			if s.coins < i64(d.sum) do return 0, false
			back = d.sum * BG_COIN_TENTHS / 10
		case .None:      return 0, false
		}
		return back - cost, true
	}
	gain := s.full * s.units
	cost: i32
	switch d.kind {
	case .Gift:    cost = s.pride / 5
	case .In_Kind: cost = s.base * s.units * s.reciprocity / 100
	case .Loan:
		cost = s.base * (s.units + d.extra) * s.honesty / 100
		if d.same do cost /= 2
		if d.term < BG_LOAN_TERM do cost += 1 + s.base / 5
	case .For_Coins:
		if s.coins < i64(d.sum) do return 0, false
		cost = d.sum * BG_COIN_TENTHS / 10
	case .None:
		return 0, false
	}
	return gain - cost, true
}


/* The deals either side may propose: a gift, in kind, loans of a day or a
 * week with up to three more, of the very thing if it isn't used up, and
 * sales about its price. */
@(private = "file")
deal_candidates :: proc(s: ^Deal_Side) -> [dynamic]Deal {
	out := make([dynamic]Deal, context.temp_allocator)
	append(&out, Deal{kind = .Gift}, Deal{kind = .In_Kind})
	for term in ([2]i64{BG_LOAN_SHORT, BG_LOAN_TERM}) {
		for extra: i32 = 0; extra <= 3; extra += 1 do append(&out, Deal{kind = .Loan, extra = extra, term = term})
		if !s.consumed do append(&out, Deal{kind = .Loan, same = true, term = term})
	}
	price := s.price if s.price > 0 else max(1, s.base * 10 / BG_COIN_TENTHS)
	for pct in ([7]i32{50, 75, 100, 125, 150, 200, 300}) {
		append(&out, Deal{kind = .For_Coins, sum = max(1, price * s.units * pct / 100)})
	}
	return out
}


/* The most any deal is worth to this side; false if none can be. */
@(private = "file")
deal_best :: proc(s: ^Deal_Side, cands: []Deal) -> (best: i32, ok: bool) {
	for d in cands {
		if v, can := deal_value(s, d); can && (!ok || v > best) do best, ok = v, true
	}
	return
}


/* Its patience, in rounds: one, and one more for every 25. */
@(private = "file")
deal_rounds :: proc(s: ^Deal_Side) -> i32 {
	return 1 + s.patience / 25
}


/* What a deal must be worth to it this round (NEGOTIATION.md decision 6):
 * from the best, toward nothing as the rounds go, slower the shrewder. */
@(private = "file")
deal_target :: proc(s: ^Deal_Side, best: i32, rounds: i32) -> i32 {
	p := deal_rounds(s)
	t := min(rounds, p)
	return max(best - best * t * (150 - s.shrewd) / (100 * p), 0)
}


/* Its offer this round: of the deals that meet its target, the one worth
 * least to it; false if none does. */
@(private = "file")
deal_propose :: proc(s: ^Deal_Side, cands: []Deal, rounds: i32) -> (Deal, bool) {
	best, ok := deal_best(s, cands)
	if !ok || best < 0 do return {}, false
	target := deal_target(s, best, rounds)
	chosen: Deal
	least:  i32
	found := false
	for d in cands {
		v, can := deal_value(s, d)
		if can && v >= target && (!found || v < least) do chosen, least, found = d, v, true
	}
	return chosen, found
}


/* One side's view: what it values the thing at (`thing`, the one it would
 * give, if it is the one asked; else what is wanted), its dispositions, and
 * its trust in the other. */
@(private = "file")
deal_side :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, giving: bool, what: ^tri.Node, thing: u32,
                  units: i32, other: u32, wanting: i32) -> Deal_Side {
	s: Deal_Side
	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	agent := (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), m.agent))
	desc  := what
	if giving && thing != 0 && knowledge_store_referent(store, thing) != nil {
		desc = tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, thing)), arena, nil, 0)
	}
	s.giving   = giving
	s.units    = max(units, 1)
	s.base     = agency_worth_desc(self, desc, store, false)
	s.full     = agency_worth_desc(self, desc, store, true)
	s.price    = max(agency_pricing(self, desc, store, false), 0)
	s.trust    = knowledge_store_trust_in(store, other)
	s.consumed = is_type(tc, what, "#Food") || is_type(tc, what, "#Stack")
	s.pct      = 100
	s.coins    = -1
	if agent != nil {
		s.pride, s.reciprocity, s.honesty = i32(agent.pride), i32(agent.reciprocity), i32(agent.honesty)
		s.shrewd, s.patience = i32(agent.shrewdness), i32(agent.patience)
	}
	if giving {
		/* it spares little of what it is short of: its price's curve over
		 * what it has of it at home, against the kind's plenty */
		if stock := agency_at_home(self, what, nil, store); stock >= 0 do s.pct = deal_spare_pct(self, desc, stock)
		/* kindness: its generosity, more for the need it believes the asker
		 * has, and its loyalty to the asker */
		need := wanting * (s.trust + BG_TRUST_LIMIT) / (2 * BG_TRUST_LIMIT)
		s.kindness = (i32(agent.generosity) if agent != nil else 0) * (20 + need) / 200 +
		             knowledge_store_loyalty_to(store, other) / 5
		/* it asks coins only of one it sees holding some, as many as that */
		s.coins = agency_coins_held_by(self, other, store)
	} else {
		s.coins = agency_coins_held_by(self, knowledge_store_self_referent(store), store)
	}
	return s
}


/* The coins the agent believes someone (itself, or another it sees) holds. */
@(private = "file")
agency_coins_held_by :: proc(self: ^Agency, who: u32, store: ^Knowledge_Store) -> i64 {
	result: tri.Match_Result
	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	coin  := tri.value(tc, "#Stack & { unit: \"coin\" }", arena, nil, 0)
	total: i64
	for i: uint = 0; coin != nil && i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present || r.form != .Held_By || r.container != who do continue
		d := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
		/* so many as its mass makes, a count unseen */
		if d != nil && tri.match(tc, coin, d, &result) == .Entailed do total += agency_units_of(self, r.id, store)
	}
	return total
}


/* What parting with some costs, as a percent of its value, by what it has
 * at home: the curve a seller's price follows (money/coins.tri's `asks`,
 * against `plenty`); 100 for what has no pricing. */
@(private = "file")
deal_spare_pct :: proc(self: ^Agency, description: ^tri.Node, stock: i64) -> i32 {
	result: tri.Match_Result
	pct: i32 = 100
	tc     := world_tri(self.world)
	family := tri.family_index(tc, "prices")
	for i: uint = 0; description != nil && family != nil && i < uint(tri.index_count(family)); i += 1 {
		pattern := tri.pattern(tc, cstring(tri.index_tag(family, i)))
		of      := tri.at(tc, pattern, "valued") if pattern != nil else nil
		if of == nil || tri.match(tc, of, description, &result) != .Entailed do continue
		plenty := dint(tc, pattern, "plenty", 0)
		if plenty > 0 && curve_at(tc, tri.at(tc, pattern, "asks"), stock * 100 / plenty, &pct) do return pct
	}
	return pct
}


/* --- what to ask for, and whom --------------------------------------------------------- */

/* What the goal's methods want in hand, in rank order: each slot whose
 * pattern holds it in the agent's hand, its place loosened to anywhere. */
@(private = "file")
agency_wants :: proc(self: ^Agency, m: ^Motivation, goal: cstring) -> [dynamic]string {
	methods: [32]cstring
	slot:    [64]u8
	printed: [4096]u8

	wants := make([dynamic]string, context.temp_allocator)
	tc    := world_tri(self.world)
	held  := tri.type_named(tc, "#Held")
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	n := agency_methods_for_mind(self, goal, m, raw_data(methods[:]), len(methods))
	for i: uint = 0; i < n; i += 1 {
		pre   := tri.at(tc, tri.pattern(tc, methods[i]), "pre")
		match := tri.at(tc, pre, "match")
		for list := tri.at(tc, pre, "find"); list != nil; list = tri.at(tc, list, "rest") {
			if !dtext(tc, tri.at(tc, list, "first"), nil, slot[:]) do break
			p     := tri.at(tc, match, cstring(raw_data(slot[:])))
			place := tri.at(tc, p, "place") if p != nil else nil
			if place == nil || held == 0 || tri.subtype(tc, tri.node_type(place), held) == 0 do continue
			loose := tri.generalize(tc, p, "place", 64, arena)
			if loose == nil do continue
			tri.print(tc, loose, raw_data(printed[:]), size_of(printed))
			want := deal_sayable(dstr(printed[:]))
			seen := false
			for w in wants do if w == want do seen = true
			if !seen do append(&wants, want)
		}
	}
	return wants
}


/* A printed pattern as it can be said: a meet the content never named
 * prints as `glb[A,B]`, which reads back as nothing; its first part, `A`,
 * is the meet as written. */
@(private = "file")
deal_sayable :: proc(printed: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(printed); {
		if strings.has_prefix(printed[i:], "glb[") {
			depth, j, first := 1, i + 4, -1
			for ; j < len(printed) && depth > 0; j += 1 {
				switch printed[j] {
				case '[', '(', '{': depth += 1
				case ']', ')', '}': depth -= 1
				case ',': if depth == 1 && first < 0 do first = j
				}
			}
			strings.write_string(&b, printed[i + 4:first if first >= 0 else j - 1])
			i = j
			continue
		}
		strings.write_byte(&b, printed[i])
		i += 1
	}
	return strings.to_string(b)
}


/* Whom to ask next: someone it believes here, a person, not asked for this
 * goal since it took the goal up; by its loyalty to them, then nearness. */
@(private = "file")
agency_whom_to_ask :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, me: ^Referent, top: ^Intention) -> u32 {
	best: ^Referent = nil
	bestLoyal, bestAt: i32
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present || r.id == me.id || r.form != .On_Tile || !agency_is_a(self, r, "#Agent") || agency_is_a(self, r, "#Animal") {
			continue
		}
		asked := false
		for t in m.talks[:m.ntalks] do if t.asking && t.with == r.id && t.goal == top.goal && t.since >= top.adopted do asked = true
		if asked do continue
		loyal := knowledge_store_loyalty_to(store, r.id)
		at    := max(abs(r.x - me.x), abs(r.y - me.y)) + (0 if r.level == me.level else 1000)
		if best == nil || loyal > bestLoyal || (loyal == bestLoyal && at < bestAt) {
			best, bestLoyal, bestAt = r, loyal, at
		}
	}
	return best.id if best != nil else 0
}


/* What the goal the agent is doing is worth: the topmost intention with a
 * worth, or that keeps a commitment (as weighing has it). */
@(private = "file")
agency_doing_worth :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store) -> i32 {
	tc := world_tri(self.world)
	for k := m.nintentions - 1; k >= 0; k -= 1 {
		it := &m.intentions[k]
		if tri.at(tc, tri.pattern(tc, it.goal), "worth.first") == nil && it.commitment == 0 do continue
		parts := make([dynamic]string, context.temp_allocator)
		worth := agency_worth_of_goal(self, it.goal, raw_data(it.params[:]), it.nparams, store, &parts)
		if it.commitment > 0 && it.commitment <= m.ncommitments {
			worth += BG_DUTY + agency_urgency_of(self, &m.commitments[it.commitment - 1])
		}
		return worth
	}
	return 0
}


@(private = "file")
agency_add_talk :: proc(m: ^Motivation, t: Talk) {
	if m.ntalks == BG_MAX_TALKS {
		/* the oldest that is over makes room, else the oldest */
		k: i32 = 0
		for i: i32 = 0; i < m.ntalks; i += 1 do if m.talks[i].state != .Open && m.talks[i].state != .Agreed { k = i; break }
		copy(m.talks[k:m.ntalks - 1], m.talks[k + 1:m.ntalks])
		m.ntalks -= 1
	}
	m.talks[m.ntalks] = t
	m.ntalks += 1
}


@(private = "file")
agency_add_owed :: proc(m: ^Motivation, o: Owed) {
	if m.nowed == BG_MAX_OWED {
		copy(m.owed[0:m.nowed - 1], m.owed[1:m.nowed])
		m.nowed -= 1
	}
	m.owed[m.nowed] = o
	m.nowed += 1
}


@(private = "file")
agency_drop_owed :: proc(m: ^Motivation, k: i32) {
	copy(m.owed[k:m.nowed - 1], m.owed[k + 1:m.nowed])
	m.nowed -= 1
}


/* --- the asker -------------------------------------------------------------------------- */

/* Asking (NEGOTIATION.md decisions 1 to 3), when none of the goal's
 * methods holds: (true, true) when it acts or waits; (false, false) when
 * asking won't serve, and the goal is impossible for now. */
agency_ask :: proc(self: ^Agency, m: ^Motivation, top: ^Intention, store: ^Knowledge_Store, me: ^Referent) -> (bool, bool) {
	need: [32]u8

	tc  := world_tri(self.world)
	now := world_time(self.world).ms
	if tri.type_named(tc, "#Ask") == 0 || me == nil do return false, false
	/* agreed: it waits for it to be handed over, an hour at most */
	for &t in m.talks[:m.ntalks] {
		if !t.asking || t.goal != top.goal || t.state != .Agreed do continue
		/* handed over: it holds something like it, and goes on without asking */
		{
			arena := tri.arena_new()
			held := agency_held_like(self, tri.value(tc, t.what, arena, nil, 0), store)
			tri.arena_free(arena)
			if held != 0 {
				agency_note(self, m, fmt.tprintf("R%d handed it over: R%d", t.with, held))
				t.state = .Ended
				return false, false
			}
		}
		if now - t.since < BG_HANDOVER {
			if m.wake == 0 || m.wake > now + 60000 do m.wake = now + 60000
			m.waiting = true
			return true, true
		}
		t.state = .Ended
		agency_note(self, m, fmt.tprintf("R%d never handed it over", t.with))
	}
	/* only for a need (NEGOTIATION.md decision 2): the goal's, or one it
	 * serves; a duty asks nothing of others yet */
	pressing := false
	for k := m.nintentions - 1; k >= 0 && !pressing; k -= 1 {
		pressing = dtext(tc, tri.pattern(tc, m.intentions[k].goal), "pressed.need", need[:])
		if m.intentions[k].commitment != 0 do break      /* a duty, between it and any need below */
	}
	if !pressing do return false, false
	agent := (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), m.agent))
	worth := agency_doing_worth(self, m, store)
	cost  := BG_ASK_COST + (i32(agent.pride) if agent != nil else 0) / 2
	if worth <= cost do return false, false
	wants := agency_wants(self, m, top.goal)
	if len(wants) == 0 do return false, false
	/* the one that had nothing like the last, for the next; else someone new */
	pick: u32 = 0
	want: i32 = 0
	asked := 0
	for &t in m.talks[:m.ntalks] {
		if !t.asking || t.goal != top.goal || t.since < top.adopted do continue
		asked += 1
		if pick == 0 && t.state == .None_Like && int(t.want) + 1 < len(wants) {
			pick, want = t.with, t.want + 1
			t.state = .Ended
		}
	}
	if pick == 0 {
		if asked >= BG_ASK_PEOPLE do return false, false
		pick = agency_whom_to_ask(self, m, store, me, top)
		if pick == 0 do return false, false
	}
	r := knowledge_store_referent(store, pick)
	if r == nil do return false, false
	title: [64]u8
	goal_title(tc, top.goal, title[:])
	why := fmt.tprintf("asking R%d for %s", pick, dstr(title[:]))
	if !in_reach(me, r) {
		agency_walk(self, m, why, me, r, store, 1)
		return true, true
	}
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	what := tri.value(tc, ns_utf8(wants[want]), arena, nil, 0)
	s    := deal_side(self, m, store, false, what, 0, 1, pick, 0)
	cands := deal_candidates(&s)
	opening, ok := deal_propose(&s, cands[:], 0)
	if !ok do return false, false
	/* the need it is for: the goal's, or what it serves's below */
	wanting: i32 = 0
	for k := m.nintentions - 1; k >= 0 && wanting == 0 && (k == m.nintentions - 1 || m.intentions[k + 1].commitment == 0); k -= 1 {
		if dtext(tc, tri.pattern(tc, m.intentions[k].goal), "pressed.need", need[:]) {
			wanting = knowledge_store_feels(store, cstring(raw_data(need[:])))
		}
	}
	agency_note(self, m, fmt.tprintf("asking is worth %+d, against %+d: asking R%d, %s", worth, cost, pick, deal_name(opening)))
	content := fmt.tprintf("#Ask & {{ what: %s, howMany: 1, deal: %s, wanting: %d }}", wants[want], deal_text(opening), wanting)
	if !agency_act(self, m, why, store, "say", pick, 0, 0, ns_utf8(content)) do return false, false
	agency_add_talk(m, Talk{with = pick, asking = true, state = .Open, goal = top.goal, what = world_intern(self.world, ns_utf8(wants[want])),
	                        units = 1, wanting = wanting, rounds = 1, want = want, last = opening, since = now})
	m.awaiting   = pick
	m.awaitSince = now
	m.awaitUntil = now + BG_DEAL_WAIT
	return true, true
}


/* An answer to an ask or an offer of the agent's (true if it was one): on
 * an offer, it agrees, offers again, or walks away. */
agency_deal_answer :: proc(self: ^Agency, m: ^Motivation, content: cstring, from: u32, store: ^Knowledge_Store) -> bool {
	tc := world_tri(self.world)
	if tri.type_named(tc, "#Ask") == 0 || content == nil do return false
	t: ^Talk = nil
	for &u in m.talks[:m.ntalks] do if u.asking && u.with == from && u.state == .Open do t = &u
	if t == nil do return false
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	said := tri.value(tc, content, arena, nil, 0)
	switch {
	case is_type(tc, said, "#HaveNone"):
		t.state = .None_Like
		return true
	case is_type(tc, said, "#Agree"):
		t.state = .Agreed
		t.last  = deal_of(tc, tri.at(tc, said, "deal"))
		agency_agreed(self, m, store, t)
		return true
	case is_type(tc, said, "#Offer"):
		offer := deal_of(tc, tri.at(tc, said, "deal"))
		what  := tri.value(tc, t.what, arena, nil, 0)
		s     := deal_side(self, m, store, false, what, 0, t.units, from, 0)
		agency_haggle(self, m, store, t, &s, offer)
		return true
	case is_type(tc, said, "#Refuse"), is_type(tc, said, "#WontSay"), is_type(tc, said, "#DontKnow"), is_type(tc, said, "#Ask"):
		/* refused; or, asked for something itself, no answer to its own */
		t.state = .Ended
		return true
	}
	return false
}


/* The other answered nothing in time. */
agency_deal_unanswered :: proc(self: ^Agency, m: ^Motivation, from: u32) {
	for &t in m.talks[:m.ntalks] do if t.asking && t.with == from && t.state == .Open do t.state = .Ended
}


/* A round (NEGOTIATION.md decision 6), for either side: the other's deal
 * agreed to if it meets this side's target; else, patience spent, walked
 * away from; else another offered. */
@(private = "file")
agency_haggle :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, t: ^Talk, s: ^Deal_Side, offer: Deal) {
	now   := world_time(self.world).ms
	cands := deal_candidates(s)
	best, ok := deal_best(s, cands[:])
	v, can := deal_value(s, offer)
	target := deal_target(s, best, t.rounds)
	why := "haggling" if t.asking else "answering"
	what := string(t.what)
	t.last = offer
	if !ok || best < 0 {
		agency_note(self, m, fmt.tprintf("R%d offers %s: no deal is worth it", t.with, deal_name(offer)))
		agency_act(self, m, why, store, "say", t.with, 0, 0, ns_utf8(fmt.tprintf("#Refuse & {{ what: %s }}", what)))
		t.state = .Ended
		return
	}
	if can && v >= target && v >= 0 {
		agency_note(self, m, fmt.tprintf("R%d offers %s, worth %+d to it, against %+d: agreed", t.with, deal_name(offer), v, target))
		content := fmt.tprintf("#Agree & {{ what: %s, howMany: %d, deal: %s }}", what, t.units, deal_text(offer))
		if agency_act(self, m, why, store, "say", t.with, 0, 0, ns_utf8(content)) {
			t.state = .Agreed
			t.since = now
			agency_agreed(self, m, store, t)
		} else {
			t.state = .Ended
		}
		return
	}
	if t.rounds > deal_rounds(s) {
		agency_note(self, m, fmt.tprintf("R%d offers %s, worth %+d to it, against %+d: its patience spent, it walks away", t.with,
		                                 deal_name(offer), v, target))
		agency_act(self, m, why, store, "say", t.with, 0, 0, ns_utf8(fmt.tprintf("#Refuse & {{ what: %s }}", what)))
		t.state = .Ended
		return
	}
	counter, found := deal_propose(s, cands[:], t.rounds)
	if !found {
		agency_act(self, m, why, store, "say", t.with, 0, 0, ns_utf8(fmt.tprintf("#Refuse & {{ what: %s }}", what)))
		t.state = .Ended
		return
	}
	cv, _ := deal_value(s, counter)
	agency_note(self, m, fmt.tprintf("R%d offers %s, worth %+d to it, against %+d: it offers %s (%+d)", t.with, deal_name(offer), v,
	                                 target, deal_name(counter), cv))
	content := fmt.tprintf("#Offer & {{ what: %s, howMany: %d, deal: %s }}", what, t.units, deal_text(counter))
	if !agency_act(self, m, why, store, "say", t.with, 0, 0, ns_utf8(content)) {
		t.state = .Ended
		return
	}
	t.rounds += 1
	t.last    = counter
	if t.asking {
		m.awaiting   = t.with
		m.awaitSince = now
		m.awaitUntil = now + BG_DEAL_WAIT
	}
}


/* A deal agreed (NEGOTIATION.md decisions 7 and 8): the one asked will hand
 * it over, and holds what it is owed; the asker owes it, and takes up
 * repaying it, or is grateful for a gift. */
@(private = "file")
agency_agreed :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, t: ^Talk) {
	now   := world_time(self.world).ms
	d     := t.last
	agent := (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), m.agent))
	owed  := Owed{other = t.with, what = t.what, units = t.units + (d.extra if d.kind == .Loan else 0), since = now,
	              explicit = d.kind == .Loan || d.kind == .For_Coins}
	switch d.kind {
	case .Gift, .None:
	case .In_Kind:   owed.due = now + BG_IN_KIND
	case .Loan:      owed.due = now + d.term
	case .For_Coins:
		owed.due   = now + BG_HANDOVER
		owed.what  = world_intern(self.world, "#Stack & { unit: \"coin\" }")
		owed.units = d.sum
	}
	if !t.asking {
		agency_add_owed(m, Owed{kind = .Hand_Over, other = t.with, what = t.what, units = t.units, since = now, due = now + BG_HANDOVER})
		agency_commit_to(self, m, "handed_over", now, now + BG_HANDOVER, t.with)
		if d.kind != .Gift && d.kind != .None {
			owed.kind = .Credit
			agency_add_owed(m, owed)
		}
		return
	}
	if d.kind == .Gift {
		/* gratitude, as its reciprocity has it */
		knowledge_store_adjust_trust_in(store, t.with, (i32(agent.reciprocity) if agent != nil else 0) / 10)
		return
	}
	owed.kind = .Debt
	agency_add_owed(m, owed)
	/* it takes up repaying: a loan or a sale as agreed, if honest enough to;
	 * in kind, within a fortnight, if disposed to return kindness */
	switch d.kind {
	case .In_Kind:
		if agent != nil && agent.reciprocity >= 50 do agency_commit_to(self, m, "repaid_in_kind", now + 86400000, owed.due, t.with)
	case .Loan:
		if agent != nil && agent.honesty >= 30 do agency_commit_to(self, m, "repaid_in_kind", owed.due - d.term / BG_LOAN_DUE, owed.due, t.with)
	case .For_Coins:
		agency_commit_to(self, m, "repaid_in_kind", now, owed.due, t.with)
	case .Gift, .None:
	}
}


@(private = "file")
agency_commit_to :: proc(self: ^Agency, m: ^Motivation, goal: cstring, from: i64, until: i64, to: u32) {
	if !agency_undertake_goal_from_until_source(self, m.agent, goal, from, until, "deal") do return
	c := &m.commitments[m.ncommitments - 1]
	c.params[0].slot     = world_intern(self.world, "to")
	c.params[0].referent = to
	c.nparams            = 1
}


/* --- the one asked ---------------------------------------------------------------------- */

Deal_Heard :: enum {
	Not_Mine,
	Done,
	Later,
}

/* Something said to the agent in a negotiation (NEGOTIATION.md decisions
 * 4 to 8): an ask or an offer it answers, as agency's social generator has
 * it worth answering at all (`worth`, its trust in the asker and its
 * helpfulness, less what it is busy with); an agreement; a refusal; a debt
 * repaid. */
agency_deal_heard :: proc(self: ^Agency, m: ^Motivation, q: ^Question, said: ^tri.Node, store: ^Knowledge_Store, worth: i32,
                          busy: i32) -> Deal_Heard {
	tc := world_tri(self.world)
	if tri.type_named(tc, "#Ask") == 0 || said == nil do return .Not_Mine
	t: ^Talk = nil
	for &u in m.talks[:m.ntalks] {
		/* an answer to its own asking: its waiting takes it (agency_deal_answer) */
		if u.asking && u.with == q.asker && (u.state == .Open || u.state == .Agreed) do return .Done
		if !u.asking && u.with == q.asker && u.state == .Open do t = &u
	}
	printed: [4096]u8
	tri.print(tc, tri.at(tc, said, "what"), raw_data(printed[:]), size_of(printed))
	what := deal_sayable(dstr(printed[:]))
	switch {
	case is_type(tc, said, "#Repaid"):
		for k: i32 = 0; k < m.nowed; k += 1 {
			if m.owed[k].kind != .Credit || m.owed[k].other != q.asker do continue
			agency_note(self, m, fmt.tprintf("R%d repaid it", q.asker))
			knowledge_store_adjust_trust_in(store, q.asker, BG_REPAID)
			agency_drop_owed(m, k)
			break
		}
		return .Done
	case is_type(tc, said, "#Refuse"):
		if t != nil do t.state = .Ended
		return .Done
	case is_type(tc, said, "#Agree"):
		if t == nil do return .Done
		t.last  = deal_of(tc, tri.at(tc, said, "deal"))
		t.state = .Agreed
		t.since = world_time(self.world).ms
		agency_note(self, m, fmt.tprintf("R%d agrees: %s", q.asker, deal_name(t.last)))
		agency_agreed(self, m, store, t)
		return .Done
	case is_type(tc, said, "#Ask"), is_type(tc, said, "#Offer"):
		if worth <= 0 && worth + busy > 0 do return .Later
		if worth <= 0 {
			agency_note(self, m, fmt.tprintf("asked by R%d: worth %+d, it won't", q.asker, worth))
			agency_act(self, m, "answering", store, "say", q.asker, 0, 0, ns_utf8(fmt.tprintf("#Refuse & {{ what: %s }}", what)))
			if t != nil do t.state = .Ended
			return .Done
		}
		arena := tri.arena_new()
		defer tri.arena_free(arena)
		like  := tri.value(tc, ns_utf8(what), arena, nil, 0)
		thing := agency_held_like(self, like, store)
		if thing == 0 do thing = agency_kept_like(self, like, store)
		if thing == 0 {
			agency_note(self, m, fmt.tprintf("asked by R%d for something it hasn't", q.asker))
			agency_act(self, m, "answering", store, "say", q.asker, 0, 0, ns_utf8(fmt.tprintf("#HaveNone & {{ what: %s }}", what)))
			if t != nil do t.state = .Ended
			return .Done
		}
		units := i32(dint(tc, said, "howMany", 1))
		if t == nil {
			if !is_type(tc, said, "#Ask") do return .Done
			agency_add_talk(m, Talk{with = q.asker, state = .Open, what = world_intern(self.world, ns_utf8(what)), units = units,
			                        wanting = i32(dint(tc, said, "wanting", 0)), since = world_time(self.world).ms})
			t = &m.talks[m.ntalks - 1]
		}
		s := deal_side(self, m, store, true, like, thing, units, q.asker, t.wanting)
		agency_haggle(self, m, store, t, &s, deal_of(tc, tri.at(tc, said, "deal")))
		return .Done
	}
	return .Not_Mine
}


/* Something like the description in a container the agent knows is its
 * own (its larder, its coffer), or 0. */
@(private = "file")
agency_kept_like :: proc(self: ^Agency, what: ^tri.Node, store: ^Knowledge_Store) -> u32 {
	result: tri.Match_Result
	tc    := world_tri(self.world)
	me    := knowledge_store_self_referent(store)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	for i: uint = 0; what != nil && i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present || r.form != .In do continue
		owned := knowledge_store_finding(store, "#Owned", r.container)
		if owned == nil || owned.choice != me do continue
		d := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
		if d != nil && tri.match(tc, what, d, &result) == .Entailed do return r.id
	}
	return 0
}


/* --- handing over, and repaying --------------------------------------------------------- */

/* The `#HandOver` step: to whom the commitment binds (`to`), what is owed
 * them (handed over as agreed, or repaid): from its hands, so many split
 * off; else fetched from its own containers first. "" once it acts; else
 * why it can't. */
agency_hand_over :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, me: ^Referent, title: string, b: [^]Slot_Binding,
                         n: i32) -> string {
	tc   := world_tri(self.world)
	to   := dbound(b, n, "to")
	goal := m.intentions[m.nintentions - 1].goal
	kind := Owed_Kind.Debt if string(goal) == "repaid_in_kind" else Owed_Kind.Hand_Over
	k: i32 = -1
	for i: i32 = 0; i < m.nowed && k < 0; i += 1 do if m.owed[i].kind == kind && m.owed[i].other == to do k = i
	if to == 0 || k < 0 {
		/* handed over just now: done once the giving has completed */
		adopted := m.intentions[m.nintentions - 1].adopted
		if agency_activity(self, "give_some", m.agent, "running", adopted) != NO_ENTITY ||
		   agency_activity(self, "give_some", m.agent, "starting", adopted) != NO_ENTITY {
			return ""
		}
		return fmt.tprintf("nothing is owed R%d", to)
	}
	o := &m.owed[k]
	r := knowledge_store_referent(store, to)
	if r == nil || !r.present do return fmt.tprintf("it doesn't know where R%d is", to)
	/* given: said so, and it is settled */
	if o.units <= 0 {
		agency_act(self, m, title, store, "say", to, 0, 0, ns_utf8(fmt.tprintf("#Repaid & {{ what: %s }}", o.what)))
		agency_drop_owed(m, k)
		top := &m.intentions[0]
		if top.commitment > 0 && top.commitment <= m.ncommitments do m.commitments[top.commitment - 1].settled = true
		return ""
	}
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	what := tri.value(tc, o.what, arena, nil, 0)
	held := agency_held_like(self, what, store)
	if held != 0 {
		if !in_reach(me, r) {
			agency_walk(self, m, title, me, r, store, 1)
			return ""
		}
		have := i32(agency_units_of(self, held, store))
		if have <= 0 do have = 1
		give := min(have, o.units)
		if !agency_act(self, m, title, store, "give_some", held, to, i64(give), nil) do return "it couldn't hand it over"
		o.units -= give
		if o.units <= 0 && kind == .Hand_Over do agency_drop_owed(m, k)
		return ""
	}
	kept := agency_kept_like(self, what, store)
	if kept == 0 do return "it has nothing like it"
	/* in kind, only what it can spare */
	if kind == .Debt && !o.explicit {
		each := agency_units_of(self, kept, store)
		stock := agency_at_home(self, what, nil, store)
		mass := i64(0)
		if kr := knowledge_store_referent(store, kept); kr != nil {
			d := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, kept)), arena, nil, 0)
			mass = dint(tc, d, "mass", 0) / max(each, 1)
		}
		if mass > 0 && stock < mass * i64(o.units) * BG_SPARE do return "it can't spare it yet"
	}
	c := knowledge_store_referent(store, knowledge_store_referent(store, kept).container)
	if c != nil && !in_reach(me, c) {
		agency_walk(self, m, title, me, c, store, 1)
		return ""
	}
	if !agency_act(self, m, title, store, "take_some", kept, 0, i64(o.units), nil) do return "it couldn't take it"
	return ""
}


/* Each decision: what is owed past its date (NEGOTIATION.md decision 8),
 * and negotiations long over. */
agency_deals_tick :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store) {
	now := world_time(self.world).ms
	for k: i32 = 0; k < m.nowed; {
		o := &m.owed[k]
		if o.due == 0 || now <= o.due {
			k += 1
			continue
		}
		switch o.kind {
		case .Credit:
			wronged := i32(BG_WRONGED) if o.explicit else i32(BG_WRONGED) / 2
			agency_note(self, m, fmt.tprintf("R%d owes it still: it trusts R%d less", o.other, o.other))
			knowledge_store_adjust_trust_in(store, o.other, -wronged)
		case .Debt:
			agency_note(self, m, fmt.tprintf("it never repaid R%d", o.other))
		case .Hand_Over:
		}
		agency_drop_owed(m, k)
	}
	for k: i32 = 0; k < m.ntalks; {
		t := &m.talks[k]
		if (t.state == .Open && now - t.since > BG_HANDOVER) || (t.state == .Agreed && !t.asking && now - t.since > BG_HANDOVER) {
			t.state = .Ended
		}
		if t.state != .Open && t.state != .Agreed && now - t.since > 86400000 {
			copy(m.talks[k:m.ntalks - 1], m.talks[k + 1:m.ntalks])
			m.ntalks -= 1
			continue
		}
		k += 1
	}
}


/* --- saved -------------------------------------------------------------------------------- */

agency_deals_saved :: proc(m: ^Motivation, lines: ^[dynamic]string) {
	for t in m.talks[:m.ntalks] {
		append(lines, fmt.tprintf("talk %d %d %d %d %s %d %d %d %d %d %d %d %d %d %d %s", m.agent, t.with, 1 if t.asking else 0,
		                          int(t.state), encode_word(t.goal if t.goal != nil else ""), t.units, t.wanting, t.rounds, t.want,
		                          t.since, int(t.last.kind), 1 if t.last.same else 0, t.last.extra, t.last.term, t.last.sum,
		                          encode_word(t.what)))
	}
	for o in m.owed[:m.nowed] {
		append(lines, fmt.tprintf("owed %d %d %d %d %d %d %d %s", m.agent, int(o.kind), o.other, o.units, 1 if o.explicit else 0,
		                          o.due, o.since, encode_word(o.what)))
	}
}


agency_deals_restore :: proc(self: ^Agency, words: []string) -> bool {
	if len(words) == 17 && words[0] == "talk" {
		m := agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
		if m.ntalks == BG_MAX_TALKS do return true
		goal := decode_word(ns_utf8(words[5]))
		what := decode_word(ns_utf8(words[16]))
		m.talks[m.ntalks] = Talk{with = u32(ns_long_long_value(words[2])), asking = ns_int_value(words[3]) != 0,
		                         state = Talk_State(ns_int_value(words[4])),
		                         goal = world_intern(self.world, goal) if len(string(goal)) > 0 else nil,
		                         units = ns_int_value(words[6]), wanting = ns_int_value(words[7]), rounds = ns_int_value(words[8]),
		                         want = ns_int_value(words[9]), since = ns_long_long_value(words[10]),
		                         last = Deal{kind = Deal_Kind(ns_int_value(words[11])), same = ns_int_value(words[12]) != 0,
		                                     extra = ns_int_value(words[13]), term = ns_long_long_value(words[14]),
		                                     sum = ns_int_value(words[15])},
		                         what = world_intern(self.world, what)}
		m.ntalks += 1
		free(rawptr(goal))
		free(rawptr(what))
		return true
	}
	if len(words) == 9 && words[0] == "owed" {
		m := agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
		if m.nowed == BG_MAX_OWED do return true
		what := decode_word(ns_utf8(words[8]))
		m.owed[m.nowed] = Owed{kind = Owed_Kind(ns_int_value(words[2])), other = u32(ns_long_long_value(words[3])),
		                       units = ns_int_value(words[4]), explicit = ns_int_value(words[5]) != 0,
		                       due = ns_long_long_value(words[6]), since = ns_long_long_value(words[7]),
		                       what = world_intern(self.world, what)}
		m.nowed += 1
		free(rawptr(what))
		return true
	}
	return false
}
