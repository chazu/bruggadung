#include "internal.h"

/* Feature structure nodes, Tomabechi quasi-destructive unification, copying
 * with structure sharing, subsumption, paths, and printing. */

/* --- generations ------------------------------------------------------------------ */

/* Each operation gets a fresh generation; scratch from other operations becomes
 * invalid without being cleared. Nested operations (lazy expansion during a
 * unification) save and restore the outer generation. */
uint32_t op_begin(Content *c)
{
    uint32_t saved = c->gen;
    c->gen = ++c->genctr;
    c->opdepth++;
    return saved;
}

void op_end(Content *c, uint32_t saved)
{
    c->gen = saved;
    c->opdepth--;
}

/* --- nodes ------------------------------------------------------------------------ */

TriNode *node_new(Content *c, TriArena *a, uint32_t type)
{
    TriNode *n = arena_alloc_raw(a, sizeof(TriNode));
    n->type = type;
    n->narcs = 0;
    n->flags = a == c->scratch ? NF_SCRATCH : 0;
    n->sx = NULL;
    n->sxgen = 0;
    n->cpygen = 0;
    n->cpy = NULL;
    if (is_dim(c, type)) {
        n->flags |= NF_DIM;
        n->lo = TRI_NINF;
        n->hi = TRI_INF;
    } else {
        n->arcs = NULL;
        n->hi = 0;
    }
    return n;
}

TriNode *leaf_new(Content *c, TriArena *a, uint32_t type, int64_t lo, int64_t hi)
{
    TriNode *n = node_new(c, a, type);
    n->lo = lo;
    n->hi = hi;
    return n;
}

Scratch *sx_get(Content *c, TriNode *n)
{
    return n->sxgen == c->gen ? n->sx : NULL;
}

Scratch *sx_make(Content *c, TriNode *n)
{
    if (n->sxgen != c->gen) {
        Scratch *s = arena_alloc_raw(c->scratch, sizeof(Scratch));
        s->fwd = s->bwd = NULL;
        s->carcs = NULL;
        s->ncarcs = s->ccap = 0;
        s->hasiv = false;
        s->forced = false;
        n->sx = s;
        n->sxgen = c->gen;
    }
    return n->sx;
}

TriNode *deref(Content *c, TriNode *n)
{
    for (;;) {
        Scratch *s = sx_get(c, n);
        if (!s || !s->fwd) return n;
        n = s->fwd;
    }
}

void node_iv(Content *c, TriNode *n, int64_t *lo, int64_t *hi)
{
    Scratch *s = sx_get(c, n);
    if (s && s->hasiv) { *lo = s->slo; *hi = s->shi; }
    else if (n->flags & NF_DIM) { *lo = n->lo; *hi = n->hi; }
    else { *lo = TRI_NINF; *hi = TRI_INF; }
}

TriNode *node_arc(TriNode *n, uint32_t f)
{
    size_t lo = 0, hi = n->narcs;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (n->arcs[mid].feat == f) return n->arcs[mid].val;
        if (n->arcs[mid].feat < f) lo = mid + 1; else hi = mid;
    }
    return NULL;
}

TriNode *carc_find(Content *c, TriNode *n, uint32_t f)
{
    TriNode *v = n->narcs ? node_arc(n, f) : NULL;
    if (v) return v;
    Scratch *s = sx_get(c, n);
    if (s)
        for (uint32_t i = 0; i < s->ncarcs; i++)
            if (s->carcs[i].feat == f) return s->carcs[i].val;
    return NULL;
}

void carc_add(Content *c, TriNode *n, uint32_t f, TriNode *v)
{
    Scratch *s = sx_make(c, n);
    if (s->ncarcs == s->ccap) {
        uint32_t ncap = s->ccap ? s->ccap * 2 : 4;
        Arc *na = arena_alloc_raw(c->scratch, ncap * sizeof(Arc));
        if (s->ncarcs) memcpy(na, s->carcs, s->ncarcs * sizeof(Arc));
        s->carcs = na;
        s->ccap = ncap;
    }
    s->carcs[s->ncarcs].feat = f;
    s->carcs[s->ncarcs].val = v;
    s->ncarcs++;
}

static uint32_t arc_count(Content *c, TriNode *n)
{
    Scratch *s = sx_get(c, n);
    return n->narcs + (s ? s->ncarcs : 0);
}

/* --- failure recording ---------------------------------------------------------------- */

static void describe_value(Content *c, Buf *b, uint32_t type, int64_t lo, int64_t hi)
{
    if (is_dim(c, type)) {
        int dim = c->types.v[type].dim;
        if (lo == hi) units_format(b, dim, lo);
        else if (dim == DIM_TEXT && text_rx(lo, hi)) rx_print(b, text_rx(lo, hi));
        else if ((lo == TRI_NINF && hi == TRI_INF) || dim == DIM_TEXT) buf_puts(b, dim_names[dim]);
        else {
            if (lo != TRI_NINF) { buf_puts(b, ">="); units_format(b, dim, lo); }
            if (lo != TRI_NINF && hi != TRI_INF) buf_puts(b, " & ");
            if (hi != TRI_INF) { buf_puts(b, "<="); units_format(b, dim, hi); }
        }
    } else {
        buf_puts(b, c->types.v[type].name);
    }
}

static void describe(Content *c, Buf *b, TriNode *n)
{
    int64_t lo, hi;
    node_iv(c, n, &lo, &hi);
    describe_value(c, b, n->type, lo, hi);
}

void path_format(Content *c, Buf *b, const uint32_t *path, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        if (i) buf_putc(b, '.');
        buf_puts(b, c->feats.v[path[i]].name);
    }
    if (!n) buf_puts(b, "(root)");
}

/* Records a failure cheaply; most failures are never looked at, so the text
 * is made only when failure() is asked for it. */
static void fail_at(Content *c, TriNode *a, TriNode *b, const char *why)
{
    if (c->failed) return;
    c->failed = true;
    c->failfmt = false;
    c->faildepth = c->depth;
    memcpy(c->failpath, c->pathstack, sizeof(uint32_t) * (size_t) c->depth);
    c->failraw.why = why;
    c->failraw.ltype = a->type;
    node_iv(c, a, &c->failraw.llo, &c->failraw.lhi);
    c->failraw.hasr = b != NULL;
    if (b) {
        c->failraw.rtype = b->type;
        node_iv(c, b, &c->failraw.rlo, &c->failraw.rhi);
    }
}

TriFailure *fail_info(Content *c)
{
    if (c->failfmt) return &c->fail_;
    c->failfmt = true;
    memset(&c->fail_, 0, sizeof c->fail_);
    if (!c->failed) return &c->fail_;
    Buf p = { 0 }, l = { 0 }, r = { 0 };
    path_format(c, &p, c->failpath, (size_t) c->faildepth);
    if (c->failraw.why) buf_puts(&l, c->failraw.why);
    else describe_value(c, &l, c->failraw.ltype, c->failraw.llo, c->failraw.lhi);
    if (c->failraw.hasr) describe_value(c, &r, c->failraw.rtype, c->failraw.rlo, c->failraw.rhi);
    snprintf(c->fail_.path, sizeof c->fail_.path, "%s", p.s ? p.s : "");
    snprintf(c->fail_.left, sizeof c->fail_.left, "%s", l.s ? l.s : "");
    snprintf(c->fail_.right, sizeof c->fail_.right, "%s", r.s ? r.s : "");
    buf_free(&p);
    buf_free(&l);
    buf_free(&r);
    return &c->fail_;
}

/* --- unification ------------------------------------------------------------------------ */

/* An enum atom meeting free text becomes text: its name, as a string. */
static TriNode *atom_as_text(Content *c, TriNode *atom)
{
    int64_t q = (int64_t) (intptr_t) c->types.v[atom->type].name;
    TriNode *t = leaf_new(c, c->scratch, c->dimtype[DIM_TEXT], q, q);
    sx_make(c, atom)->fwd = t;
    return t;
}

static bool is_text(Content *c, TriNode *n)
{
    return (n->flags & NF_DIM) && c->types.v[n->type].dim == DIM_TEXT;
}

/* --- text and its regex constraints ------------------------------------------------------- */

static uint32_t join_type(Content *c, uint32_t a, uint32_t b, uint32_t bound);

static const RxSet *node_rx(Content *c, TriNode *n)
{
    int64_t lo, hi;
    node_iv(c, n, &lo, &hi);
    return text_rx(lo, hi);
}

/* Meets two text values: concrete, constrained (a set), or open. */
static bool text_meet(Content *c, int64_t lo1, int64_t hi1, int64_t lo2, int64_t hi2, int64_t *lo, int64_t *hi)
{
    bool c1 = lo1 == hi1, c2 = lo2 == hi2;
    if (c1 && c2) { *lo = *hi = lo1; return lo1 == lo2; }
    if (c1 || c2) {
        int64_t v = c1 ? lo1 : lo2;
        *lo = *hi = v;
        return rx_accepts(c1 ? text_rx(lo2, hi2) : text_rx(lo1, hi1), (Sym) (intptr_t) v);
    }
    const RxSet *u = rx_union(c, text_rx(lo1, hi1), text_rx(lo2, hi2));
    *lo = TRI_NINF;
    *hi = u ? (int64_t) (intptr_t) u : TRI_INF;
    return true;
}

/* An atom, or an enum of atoms, with no structure of its own. */
static bool is_enum_value(Content *c, TriNode *n)
{
    if ((n->flags & NF_DIM) || arc_count(c, n) || c->types.v[n->type].feats.n) return false;
    if (c->types.v[n->type].kind == TK_ATOM) return true;
    if (n->type == c->top || n->type == c->atomroot) return false;
    const U32Vec *leaves = enum_leaves(c, n->type);
    for (size_t i = 0; i < leaves->n; i++)
        if (c->types.v[leaves->v[i]].kind != TK_ATOM) return false;
    return leaves->n > 0;
}

static bool same_leaves(const U32Vec *a, const U32Vec *b)
{
    if (a->n != b->n) return false;
    for (size_t i = 0; i < a->n; i++) if (a->v[i] != b->v[i]) return false;
    return true;
}

/* Constrained text meeting an atom or an enum: the regexes test the atoms'
 * names. The result is the atom, the enum, or the enum (or atom) whose atoms
 * are exactly those that match. When no type is exactly those, load reports
 * it (a widened pattern would match too much), and at runtime the value keeps
 * the most specific type covering them: less precise, never wrong. */
static bool text_meets_enum(Content *c, TriNode *tx, TriNode *e)
{
    const RxSet *set = node_rx(c, tx);
    if (is_leaf(c, e->type)) {
        if (!rx_accepts(set, c->types.v[e->type].name)) { fail_at(c, tx, e, NULL); return false; }
        sx_make(c, tx)->fwd = e;
        return true;
    }
    const U32Vec *leaves = enum_leaves(c, e->type);
    U32Vec match = { 0 };
    for (size_t i = 0; i < leaves->n; i++)
        if (rx_accepts(set, c->types.v[leaves->v[i]].name)) VEC_PUSH(match, leaves->v[i]);
    if (!match.n) { VEC_FREE(match); fail_at(c, tx, e, NULL); return false; }
    if (match.n == leaves->n) { VEC_FREE(match); sx_make(c, tx)->fwd = e; return true; }
    uint32_t t = match.v[0];
    for (size_t i = 1; i < match.n; i++) t = join_type(c, t, match.v[i], e->type);
    if (!is_subtype(c, t, e->type)) t = e->type;
    bool exact = same_leaves(enum_leaves(c, t), &match);
    if (exact || c->loaded) VEC_FREE(match);
    if (!exact && !c->loaded) {
        if (!c->failed) {
            Buf w = { 0 };
            rx_print(&w, set);
            buf_puts(&w, " (allows only ");
            for (size_t i = 0; i < match.n; i++) {
                if (i) buf_puts(&w, i + 1 == match.n ? " and " : ", ");
                buf_puts(&w, c->types.v[match.v[i]].name);
            }
            buf_puts(&w, ", and no enum is exactly those: declare one)");
            snprintf(c->failwhy, sizeof c->failwhy, "%s", w.s);
            buf_free(&w);
        }
        VEC_FREE(match);
        fail_at(c, tx, e, c->failwhy);
        return false;
    }
    TriNode *n = node_new(c, c->scratch, t);
    sx_make(c, tx)->fwd = n;
    sx_make(c, e)->fwd = n;
    return true;
}

/* Whether text value g subsumes s (both as lo, hi). */
static bool text_subsumes(int64_t glo, int64_t ghi, int64_t slo, int64_t shi)
{
    if (glo == TRI_NINF && ghi == TRI_INF) return true;
    if (glo == ghi) return slo == shi && slo == glo;
    const RxSet *g = text_rx(glo, ghi);
    if (slo == shi) return rx_accepts(g, (Sym) (intptr_t) slo);
    const RxSet *sr = text_rx(slo, shi);
    return sr && rx_subset(g, sr);
}

/* The most specific text value subsuming both. */
static void text_join(Content *c, int64_t lo1, int64_t hi1, int64_t lo2, int64_t hi2, int64_t *lo, int64_t *hi)
{
    bool c1 = lo1 == hi1, c2 = lo2 == hi2;
    const RxSet *r = NULL;
    if (c1 && c2) {
        if (lo1 == lo2) { *lo = *hi = lo1; return; }
    } else if (c1 || c2) {
        r = rx_satisfied(c, c1 ? text_rx(lo2, hi2) : text_rx(lo1, hi1), (Sym) (intptr_t) (c1 ? lo1 : lo2));
    } else {
        r = rx_common(c, text_rx(lo1, hi1), text_rx(lo2, hi2));
    }
    *lo = TRI_NINF;
    *hi = r ? (int64_t) (intptr_t) r : TRI_INF;
}

static int dim_of(Content *c, TriNode *n)
{
    return (n->flags & NF_DIM) ? c->types.v[n->type].dim : -1;
}

/* A whole number meeting a fixed-point value is taken as fixed (×1000). */
static TriNode *int_as_fixed(Content *c, TriNode *n)
{
    int64_t lo, hi;
    node_iv(c, n, &lo, &hi);
    int64_t s = 1000;
    lo = lo == TRI_NINF ? lo : lo < TRI_NINF / s ? TRI_NINF + 1 : lo * s;
    hi = hi == TRI_INF ? hi : hi > TRI_INF / s ? TRI_INF - 1 : hi * s;
    TriNode *f = leaf_new(c, c->scratch, c->dimtype[DIM_FIXED], lo, hi);
    sx_make(c, n)->fwd = f;
    return f;
}

bool unify1(Content *c, TriNode *a, TriNode *b)
{
    a = deref(c, a);
    b = deref(c, b);
    if (a == b) return true;
    if ((a->flags ^ b->flags) & NF_DIM) {
        if (is_text(c, a) && node_rx(c, a) && is_enum_value(c, b)) return text_meets_enum(c, a, b);
        if (is_text(c, b) && node_rx(c, b) && is_enum_value(c, a)) return text_meets_enum(c, b, a);
        if (is_text(c, a) && c->types.v[b->type].kind == TK_ATOM) b = atom_as_text(c, b);
        else if (is_text(c, b) && c->types.v[a->type].kind == TK_ATOM) a = atom_as_text(c, a);
    } else if ((a->flags & NF_DIM) && a->type != b->type) {
        if (dim_of(c, a) == DIM_INT && dim_of(c, b) == DIM_FIXED) a = int_as_fixed(c, a);
        else if (dim_of(c, b) == DIM_INT && dim_of(c, a) == DIM_FIXED) b = int_as_fixed(c, b);
    }
    uint32_t t = meet(c, a->type, b->type);
    if (t == TRI_BOTTOM) { fail_at(c, a, b, NULL); return false; }

    if (t != a->type && t != b->type) {
        /* A new, more specific type: its constraint must hold too. */
        TriNode *n = type_instance(c, t, c->scratch);
        if (!n) { fail_at(c, a, b, "the type's constraint cannot be expanded"); return false; }
        return unify1(c, n, a) && unify1(c, n, b);
    }

    TriNode *target, *src;
    if (t == a->type && t == b->type) {
        bool a_more = arc_count(c, a) >= arc_count(c, b);
        target = a_more ? a : b;
        src = a_more ? b : a;
    } else if (t == a->type) {
        target = a; src = b;
    } else {
        target = b; src = a;
    }

    if ((target->flags & NF_LAZY) && is_lazy(c, target) && arc_count(c, src) && c->types.v[target->type].xstate == 2) {
        /* structure is being added to a lazy node: apply its constraint first */
        TriNode *e = type_expansion(c, target->type);
        sx_make(c, target)->forced = true;
        if (e) {
            TriNode *m = copy_raw(c, c->scratch, e);
            if (!unify1(c, m, target)) return false;
            target = deref(c, target);
        }
    }

    if (target->flags & NF_DIM) {
        int64_t lo1, hi1, lo2, hi2, lo, hi;
        node_iv(c, target, &lo1, &hi1);
        node_iv(c, src, &lo2, &hi2);
        if (is_text(c, target)) {
            if (!text_meet(c, lo1, hi1, lo2, hi2, &lo, &hi)) { fail_at(c, a, b, NULL); return false; }
        } else {
            lo = lo1 > lo2 ? lo1 : lo2;
            hi = hi1 < hi2 ? hi1 : hi2;
            if (lo > hi) { fail_at(c, a, b, NULL); return false; }
        }
        if (lo != lo1 || hi != hi1) {
            Scratch *s = sx_make(c, target);
            s->slo = lo;
            s->shi = hi;
            s->hasiv = true;
        }
    }

    sx_make(c, src)->fwd = target;

    /* src's own arcs never change during unification; its comp-arcs might (if
     * it is reached again as a target), so those are taken as a snapshot. */
    Scratch *ss = sx_get(c, src);
    uint32_t nown = (src->flags & NF_DIM) ? 0 : src->narcs, ncomp = ss ? ss->ncarcs : 0;
    if (!nown && !ncomp) return true;
    Arc *comp = NULL;
    if (ncomp) {
        comp = arena_alloc_raw(c->scratch, ncomp * sizeof(Arc));
        memcpy(comp, ss->carcs, ncomp * sizeof(Arc));
    }
    /* Both own arc lists are sorted by feature: walk them in step, and look in
     * the target's comp-arcs only for features its own arcs lack. */
    uint32_t tn = (target->flags & NF_DIM) ? 0 : target->narcs, j = 0;
    for (uint32_t i = 0; i < nown + ncomp; i++) {
        const Arc *arc = i < nown ? &src->arcs[i] : &comp[i - nown];
        uint32_t f = arc->feat;
        TriNode *tv = NULL;
        if (i < nown) {
            while (j < tn && target->arcs[j].feat < f) j++;
            if (j < tn && target->arcs[j].feat == f) tv = target->arcs[j].val;
        } else {
            tv = tn ? node_arc(target, f) : NULL;
        }
        if (!tv) {
            Scratch *ts = sx_get(c, target);
            if (ts)
                for (uint32_t k = 0; k < ts->ncarcs; k++)
                    if (ts->carcs[k].feat == f) { tv = ts->carcs[k].val; break; }
        }
        c->pathstack[c->depth++] = f;
        if (tv) {
            if (!unify1(c, tv, arc->val)) return false;
        } else if (!approp(c, t, f)) {
            fail_at(c, target, NULL, "feature not appropriate for this type");
            return false;
        } else {
            carc_add(c, target, f, arc->val);
        }
        c->depth--;
    }
    return true;
}

/* --- copying ------------------------------------------------------------------------------ */

static int cmp_arc(const void *a, const void *b)
{
    uint32_t x = ((const Arc *) a)->feat, y = ((const Arc *) b)->feat;
    return x < y ? -1 : x > y;
}

bool is_lazy(Content *c, TriNode *n)
{
    if (!(n->flags & NF_LAZY)) return false;
    Scratch *s = sx_get(c, n);
    return !(s && s->forced);
}

/* A lazy node as a full structure, in scratch: its type's expansion unified
 * with what it carries. Used by read-only passes that need its arcs. */
TriNode *materialize(Content *c, TriNode *n)
{
    if (!is_lazy(c, n) || c->types.v[n->type].xstate != 2) return n;
    TriNode *e = type_expansion(c, n->type);
    if (!e) return n;
    uint32_t saved = op_begin(c);
    bool savedfailed = c->failed;
    int saveddepth = c->depth;
    TriNode *m = copy_raw(c, c->scratch, e);
    TriNode *r = n;
    if (unify1(c, m, n)) r = copy_out(c, c->scratch, m, NULL);
    c->failed = savedfailed;
    c->depth = saveddepth;
    op_end(c, saved);
    return r;
}

static TriNode *copy_raw_rec(Content *c, TriArena *a, TriNode *n, uint32_t cg)
{
    if (n->cpygen == cg) return n->cpy;
    TriNode *m = node_new(c, a, n->type);
    m->flags |= n->flags & NF_LAZY;
    if (n->flags & NF_DIM) { m->lo = n->lo; m->hi = n->hi; }
    n->cpy = m;
    n->cpygen = cg;
    m->narcs = n->narcs;
    if (n->narcs) {
        m->arcs = arena_alloc(a, n->narcs * sizeof(Arc));
        for (uint32_t i = 0; i < n->narcs; i++) {
            m->arcs[i].feat = n->arcs[i].feat;
            m->arcs[i].val = copy_raw_rec(c, a, n->arcs[i].val, cg);
        }
    }
    return m;
}

/* A pristine copy, ignoring scratch state: used to instantiate type constraints. */
TriNode *copy_raw(Content *c, TriArena *a, TriNode *n)
{
    return copy_raw_rec(c, a, n, ++c->cgenctr);
}

#define INPROGRESS ((TriNode *) (uintptr_t) 1)

/* Copies the result of the current operation out of scratch, following forwards,
 * narrowed intervals, and comp-arcs. With `share`, a node from a long-lived
 * arena that is unchanged, with unchanged descendants, is reused rather than
 * copied (structure sharing). */
static TriNode *copy_out_rec(Content *c, TriArena *a, TriNode *n, uint32_t cg, bool *ok, bool share)
{
    n = deref(c, n);
    if (n->cpygen == cg) {
        if (n->cpy == INPROGRESS) { c->cyclic = true; return n; }
        return n->cpy;
    }
    n->cpygen = cg;
    Scratch *s = sx_get(c, n);
    bool same = share && !(n->flags & NF_SCRATCH) && !(s && (s->ncarcs || s->hasiv));
    uint32_t na = n->narcs + (s ? s->ncarcs : 0);
    Arc *arcs = NULL;
    Arc local[32];
    if (na) {
        n->cpy = INPROGRESS;
        arcs = na <= 32 ? local : arena_alloc_raw(c->scratch, na * sizeof(Arc));
        if (n->narcs) memcpy(arcs, n->arcs, n->narcs * sizeof(Arc));
        if (s && s->ncarcs) {
            memcpy(arcs + n->narcs, s->carcs, s->ncarcs * sizeof(Arc));
            qsort(arcs, na, sizeof(Arc), cmp_arc);
        }
        for (uint32_t i = 0; i < na; i++) {
            TriNode *v = copy_out_rec(c, a, arcs[i].val, cg, ok, share);
            if (v != arcs[i].val) same = false;
            arcs[i].val = v;
        }
    }
    if (same) {
        n->cpy = n;
        return n;
    }
    TriNode *m = node_new(c, a, n->type);
    if (is_lazy(c, n)) m->flags |= NF_LAZY;
    if (n->flags & NF_DIM) node_iv(c, n, &m->lo, &m->hi);
    if (na) {
        m->arcs = arena_alloc_raw(a, na * sizeof(Arc));
        memcpy(m->arcs, arcs, na * sizeof(Arc));
        m->narcs = (uint16_t) na;
        for (uint32_t i = 0; i < na; i++)
            if (!approp(c, m->type, arcs[i].feat)) *ok = false;
    }
    n->cpy = m;
    return m;
}

/* Copies several roots out of one operation together, so nodes they share
 * stay shared. */
void copy_out_many(Content *c, TriArena *a, TriNode **roots, size_t n)
{
    static int noshare = -1;
    if (noshare < 0) noshare = getenv("TRI_NOSHARE") != NULL;
    bool ok = true;
    c->cyclic = false;
    uint32_t cg = ++c->cgenctr;
    TriNode **in = malloc(sizeof(TriNode *) * (n ? n : 1));
    memcpy(in, roots, sizeof(TriNode *) * n);
    for (size_t i = 0; i < n; i++) roots[i] = copy_out_rec(c, a, in[i], cg, &ok, !noshare);
    if (c->cyclic) {
        c->cyclic = false;
        cg = ++c->cgenctr;
        for (size_t i = 0; i < n; i++) roots[i] = copy_out_rec(c, a, in[i], cg, &ok, false);
    }
    free(in);
}

TriNode *copy_out(Content *c, TriArena *a, TriNode *n, bool *closed_ok)
{
    bool ok = true;
    c->cyclic = false;
    static int noshare = -1;                  /* TRI_NOSHARE=1 disables sharing, for checking */
    if (noshare < 0) noshare = getenv("TRI_NOSHARE") != NULL;
    TriNode *r = copy_out_rec(c, a, n, ++c->cgenctr, &ok, !noshare);
    if (c->cyclic) {
        /* sharing can't decide on a cycle; copy everything instead */
        ok = true;
        c->cyclic = false;
        r = copy_out_rec(c, a, n, ++c->cgenctr, &ok, false);
    }
    if (closed_ok) *closed_ok = ok;
    return r;
}

/* --- extensional equality and subsumption --------------------------------------------------- */

/* Leaves are extensional: two nodes with the same maximal featureless type, or
 * the same exact quantity, count as the same value. */
bool ext_equal(Content *c, TriNode *a, TriNode *b)
{
    if (a == b) return true;
    if (a->type != b->type) return false;
    if (a->flags & NF_DIM) return a->lo == a->hi && b->lo == b->hi && a->lo == b->lo;
    return is_leaf(c, a->type);
}

typedef struct { bool fwd, bwd; } SubState;

static void subsume_rec(Content *c, TriNode *a, TriNode *b, SubState *s)
{
    /* A lazy node stands for its type's expansion with what it carries. Compare
     * against that, unless both are lazy (then their carried arcs decide). */
    if (is_lazy(c, a) != is_lazy(c, b)) {
        if (is_lazy(c, b) && a->narcs) b = materialize(c, b);
        else if (is_lazy(c, a) && b->narcs) a = materialize(c, a);
    }
    Scratch *sa = sx_make(c, a), *sb = sx_make(c, b);
    bool amapped = sa->fwd != NULL, bmapped = sb->bwd != NULL;
    if (amapped && bmapped && sa->fwd == b && sb->bwd == a) return;
    if (amapped && sa->fwd != b && !ext_equal(c, sa->fwd, b)) s->fwd = false;
    if (bmapped && sb->bwd != a && !ext_equal(c, sb->bwd, a)) s->bwd = false;
    if (!amapped) sa->fwd = b;
    if (!bmapped) sb->bwd = a;
    /* constrained text subsumes the atoms whose names it accepts */
    const RxSet *arx = is_text(c, a) ? text_rx(a->lo, a->hi) : NULL, *brx = is_text(c, b) ? text_rx(b->lo, b->hi) : NULL;
    bool fwd_atom = arx && !(b->flags & NF_DIM) && is_leaf(c, b->type) && c->types.v[b->type].kind == TK_ATOM;
    bool bwd_atom = brx && !(a->flags & NF_DIM) && is_leaf(c, a->type) && c->types.v[a->type].kind == TK_ATOM;
    if (fwd_atom) { if (!rx_accepts(arx, c->types.v[b->type].name)) s->fwd = false; }
    else if (!is_subtype(c, b->type, a->type)) s->fwd = false;
    if (bwd_atom) { if (!rx_accepts(brx, c->types.v[a->type].name)) s->bwd = false; }
    else if (!is_subtype(c, a->type, b->type)) s->bwd = false;
    if ((a->flags & NF_DIM) && (b->flags & NF_DIM)) {
        if (is_text(c, a) && is_text(c, b)) {
            if (!text_subsumes(a->lo, a->hi, b->lo, b->hi)) s->fwd = false;
            if (!text_subsumes(b->lo, b->hi, a->lo, a->hi)) s->bwd = false;
        } else {
            if (!(b->lo >= a->lo && b->hi <= a->hi)) s->fwd = false;
            if (!(a->lo >= b->lo && a->hi <= b->hi)) s->bwd = false;
        }
    }
    if (!s->fwd && !s->bwd) return;
    uint32_t i = 0, j = 0;
    while (i < a->narcs && j < b->narcs && (s->fwd || s->bwd)) {
        if (a->arcs[i].feat == b->arcs[j].feat) {
            subsume_rec(c, a->arcs[i].val, b->arcs[j].val, s);
            i++; j++;
        } else if (a->arcs[i].feat < b->arcs[j].feat) {
            i++;
        } else {
            j++;
        }
    }
}

void tri_subsumes(TriContent *c, const TriNode *a, const TriNode *b, int *forward, int *backward)
{
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    SubState s = { true, true };
    subsume_rec(c, (TriNode *) a, (TriNode *) b, &s);
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    if (forward) *forward = s.fwd;
    if (backward) *backward = s.bwd;
}

/* --- paths ------------------------------------------------------------------------------------ */

bool path_parse(Content *c, const char *s, U32Vec *out)
{
    out->n = 0;
    while (*s) {
        const char *e = strchr(s, '.');
        size_t len = e ? (size_t) (e - s) : strlen(s);
        Sym name = sym_intern(&c->syms, s, len);
        uint32_t f = feat_lookup(c, name);
        if (f == TRI_BOTTOM) return false;
        VEC_PUSH(*out, f);
        if (!e) break;
        s = e + 1;
    }
    return true;
}

TriNode *node_at(TriNode *n, const uint32_t *path, size_t len)
{
    for (size_t i = 0; i < len && n; i++) n = node_arc(n, path[i]);
    return n;
}

/* Like node_at, but a lazy node with no arc for the next feature stands for
 * its type's expansion (which lives as long as the content): continue there. */
static TriNode *node_at_lazy(Content *c, TriNode *n, const uint32_t *path, size_t len)
{
    for (size_t i = 0; i < len && n; i++) {
        TriNode *next = node_arc(n, path[i]);
        if (!next && (n->flags & NF_LAZY)) {
            TriNode *e = type_expansion(c, n->type);
            next = e ? node_arc(e, path[i]) : NULL;
        }
        n = next;
    }
    return n;
}

/* Each of the path's fields is the one the node it is read from has: where
 * two packages have a field of one name, the node's type says which. */
const TriNode *tri_at(const TriContent *cc, const TriNode *node, const char *path)
{
    Content *c = (Content *) cc;
    TriNode *n = (TriNode *) node;
    for (const char *s = path; n && *s;) {
        const char *e = strchr(s, '.');
        size_t len = e ? (size_t) (e - s) : strlen(s);
        uint32_t f = feat_resolve(c, sym_intern(&c->syms, s, len), n->type, NULL, NULL);
        if (f == TRI_BOTTOM) return NULL;
        n = node_at_lazy(c, n, &f, 1);
        if (!e) break;
        s = e + 1;
    }
    return n;
}

TriType tri_node_type(const TriNode *node) { return node->type; }

int tri_node_interval(const TriNode *node, int64_t *lo, int64_t *hi)
{
    if (!(node->flags & NF_DIM)) { *lo = TRI_NINF; *hi = TRI_INF; return 0; }
    *lo = node->lo;
    *hi = node->hi;
    return node->lo != TRI_NINF || node->hi != TRI_INF;
}

/* --- printing ------------------------------------------------------------------------------------ */

typedef struct { U64Map refs; U64Map tags; int ntags; } PrintState;

static void count_refs(TriNode *n, U64Map *refs)
{
    uint64_t k = (uint64_t) (uintptr_t) n, v = 0;
    if (u64map_get(refs, k, &v)) { u64map_put(refs, k, v + 1); return; }
    u64map_put(refs, k, 1);
    for (uint32_t i = 0; i < n->narcs; i++) count_refs(n->arcs[i].val, refs);
}

static void print_rec(Content *c, Buf *b, TriNode *n, PrintState *ps)
{
    uint64_t k = (uint64_t) (uintptr_t) n, v;
    u64map_get(&ps->refs, k, &v);
    if (v > 1) {
        uint64_t tag;
        if (u64map_get(&ps->tags, k, &tag)) { buf_printf(b, "$%llu", (unsigned long long) tag); return; }
        u64map_put(&ps->tags, k, (uint64_t) ++ps->ntags);
        buf_printf(b, "$%d & ", ps->ntags);
    }
    TypeInfo *ti = &c->types.v[n->type];
    if (ti->kind == TK_DIM) {
        describe(c, b, n);
        return;
    }
    if (ti->kind == TK_ANON) buf_putc(b, '(');
    if (n->type != c->top || !n->narcs) buf_puts(b, ti->name);
    if (ti->kind == TK_ANON) buf_putc(b, ')');
    if (!n->narcs) return;
    buf_puts(b, n->type != c->top ? " & { " : "{ ");
    for (uint32_t i = 0; i < n->narcs; i++) {
        if (i) buf_puts(b, ", ");
        buf_printf(b, "%s: ", c->feats.v[n->arcs[i].feat].name);
        print_rec(c, b, n->arcs[i].val, ps);
    }
    buf_puts(b, " }");
}

void fs_print(Content *c, Buf *b, TriNode *n)
{
    PrintState ps = { 0 };
    count_refs(n, &ps.refs);
    print_rec(c, b, n, &ps);
    u64map_free(&ps.refs);
    u64map_free(&ps.tags);
}

size_t tri_text(TriContent *c, const TriNode *n, char *buf, size_t len)
{
    const char *q;
    if (!n) return (size_t) -1;
    if (n->flags & NF_DIM) {
        if (c->types.v[n->type].dim != DIM_TEXT || n->lo != n->hi) return (size_t) -1;
        q = (const char *) (intptr_t) n->lo;
    } else if (c->types.v[n->type].kind == TK_ATOM) {
        q = c->types.v[n->type].name;
    } else return (size_t) -1;
    Buf b = { 0 };
    string_decode(q, &b);
    if (len) {
        size_t k = b.len < len - 1 ? b.len : len - 1;
        memcpy(buf, b.s, k);
        buf[k] = 0;
    }
    size_t r = b.len;
    buf_free(&b);
    return r;
}

size_t tri_print(TriContent *c, const TriNode *node, char *buf, size_t len)
{
    Buf b = { 0 };
    fs_print(c, &b, (TriNode *) node);
    size_t n = b.len;
    if (len) snprintf(buf, len, "%s", b.s ? b.s : "");
    buf_free(&b);
    return n;
}

/* --- public unification ----------------------------------------------------------------------------- */

const TriNode *tri_unify(TriContent *c, const TriNode *a, const TriNode *b, TriArena *out,
                         TriFailure *failure)
{
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    c->failed = false;
    c->depth = 0;
    TriNode *r = NULL;
    if (unify1(c, (TriNode *) a, (TriNode *) b)) {
        bool ok;
        r = copy_out(c, out, (TriNode *) a, &ok);
    } else if (failure) {
        *failure = *fail_info(c);
    }
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    if (r && (c->disjs.n || c->narith)) r = settle(c, r, NULL, out, failure);   /* alternatives, arithmetic */
    return r;
}

/* --- generalisation of two structures ----------------------------------------------------------- */

/* A least upper bound of two types: a minimal common ancestor, preferring one
 * within `bound` (the type the context allows), then the highest ID, so the
 * choice is deterministic. */
static uint32_t join_type(Content *c, uint32_t a, uint32_t b, uint32_t bound)
{
    if (is_subtype(c, a, b)) return b;
    if (is_subtype(c, b, a)) return a;
    U32Vec queue = { 0 }, common = { 0 };
    U64Map seen = { 0 };
    VEC_PUSH(queue, a);
    u64map_put(&seen, a, 1);
    for (size_t i = 0; i < queue.n; i++) {
        uint32_t t = queue.v[i];
        if (is_subtype(c, b, t)) { VEC_PUSH(common, t); continue; }   /* its ancestors are not minimal */
        for (size_t k = 0; k < c->types.v[t].parents.n; k++) {
            uint32_t p = c->types.v[t].parents.v[k];
            if (!u64map_get(&seen, p, NULL)) { u64map_put(&seen, p, 1); VEC_PUSH(queue, p); }
        }
    }
    uint32_t best = c->top;
    bool best_in = false;
    for (size_t i = 0; i < common.n; i++) {
        uint32_t t = common.v[i];
        bool minimal = true;
        for (size_t j = 0; j < common.n && minimal; j++)
            if (common.v[j] != t && is_subtype(c, common.v[j], t)) minimal = false;
        if (!minimal) continue;
        bool in = bound == TRI_BOTTOM || is_subtype(c, t, bound);
        if ((in && !best_in) || (in == best_in && (best == c->top || t > best))) { best = t; best_in = in; }
    }
    VEC_FREE(queue);
    VEC_FREE(common);
    u64map_free(&seen);
    return best;
}

typedef struct { TriNode *a, *b, *r; } GenPair;
typedef struct { VEC(GenPair) pairs; U64Map idx; } GenState;

static TriNode *gen_rec(Content *c, TriArena *out, TriNode *a, TriNode *b, uint32_t bound, GenState *st)
{
    uint64_t key = hash64((uint64_t) (uintptr_t) a * 31 + (uint64_t) (uintptr_t) b), v;
    for (uint64_t k = key; u64map_get(&st->idx, k, &v); k = hash64(k)) {
        GenPair *gp = &st->pairs.v[v - 1];
        if (gp->a == a && gp->b == b) return gp->r;
    }
    if (a == b && !(a->flags & NF_SCRATCH)) return a;
    uint32_t t = join_type(c, a->type, b->type, bound);
    if (is_lazy(c, a) && is_lazy(c, b)) {
        /* both stand for their type's expansion: so does the result (what they
         * carry beyond it is dropped, which only generalises further) */
        TriNode *r = node_new(c, out, t);
        r->flags |= c->types.v[t].feats.n ? NF_LAZY : 0;
        return r;
    }
    if (is_lazy(c, a)) a = materialize(c, a);
    if (is_lazy(c, b)) b = materialize(c, b);
    TriNode *r = node_new(c, out, t);
    GenPair gp = { a, b, r };
    VEC_PUSH(st->pairs, gp);
    uint64_t k = key;
    while (u64map_get(&st->idx, k, NULL)) k = hash64(k);
    u64map_put(&st->idx, k, st->pairs.n);
    if (r->flags & NF_DIM) {
        bool both = (a->flags & NF_DIM) && (b->flags & NF_DIM);
        int dim = c->types.v[t].dim;
        if (dim == DIM_TEXT && both && is_text(c, a) && is_text(c, b)) {
            text_join(c, a->lo, a->hi, b->lo, b->hi, &r->lo, &r->hi);
            return r;
        }
        r->lo = both ? (a->lo < b->lo ? a->lo : b->lo) : TRI_NINF;
        r->hi = both ? (a->hi > b->hi ? a->hi : b->hi) : TRI_INF;
        if ((dim == DIM_TEXT || dim == DIM_REF) && r->lo != r->hi) { r->lo = TRI_NINF; r->hi = TRI_INF; }
        return r;
    }
    TypeInfo *ti = &c->types.v[t];
    if (!ti->feats.n) return r;
    TriNode *e = type_expansion(c, t);
    r->arcs = arena_alloc(out, ti->feats.n * sizeof(Arc));
    for (size_t i = 0; i < ti->feats.n; i++) {
        uint32_t f = ti->feats.v[i];
        TriNode *ev = e ? node_arc(e, f) : NULL;
        TriNode *va = node_arc(a, f), *vb = node_arc(b, f);
        TriNode *val = va && vb ? gen_rec(c, out, va, vb, ev ? ev->type : TRI_BOTTOM, st)
                     : ev ? copy_raw(c, out, ev) : NULL;
        if (!val) continue;
        r->arcs[r->narcs].feat = f;
        r->arcs[r->narcs].val = val;
        r->narcs++;
    }
    return r;
}

/* The most specific structure that subsumes both (anti-unification). */
TriNode *fs_generalise(Content *c, TriArena *out, TriNode *a, TriNode *b)
{
    GenState st = { 0 };
    TriMark m = tri_arena_mark(c->scratch);
    TriNode *r = gen_rec(c, out, a, b, TRI_BOTTOM, &st);
    if (out != c->scratch) tri_arena_release(c->scratch, m);
    VEC_FREE(st.pairs);
    u64map_free(&st.idx);
    return r;
}

const TriNode *tri_lgg(TriContent *c, const TriNode *a, const TriNode *b, TriArena *out)
{
    return fs_generalise(c, out, (TriNode *) a, (TriNode *) b);
}

/* --- every conflict ------------------------------------------------------------------------------ */

/* The paths where two structures conflict, all of them, not just the first
 * unification meets: recognition weighs each against the paths that agree.
 * Each conflict is reported at its smallest path: a type clash or disjoint
 * interval where it occurs, or, if the parts below agree one by one, where
 * the combination fails (for example through a tag). */
static void conflicts_rec(Content *c, TriNode *a, TriNode *b, U32Vec *path, char (*out)[256], size_t *n, size_t max,
                          int depth)
{
    if (*n >= max || depth > 64) return;
    TriFailure f;
    TriArena *tmp = c->scratch;
    TriMark m = tri_arena_mark(tmp);
    bool ok = tri_unify(c, a, b, tmp, &f) != NULL;
    tri_arena_release(tmp, m);
    if (ok) return;
    size_t before = *n;
    uint32_t t = meet(c, a->type, b->type);
    bool local = t == TRI_BOTTOM;
    if (!local && (a->flags & NF_DIM) && (b->flags & NF_DIM)) local = a->lo > b->hi || b->lo > a->hi;
    if (!local && !(a->flags & NF_DIM) && !(b->flags & NF_DIM)) {
        uint32_t i = 0, j = 0;
        while (i < a->narcs && j < b->narcs && *n < max) {
            if (a->arcs[i].feat == b->arcs[j].feat) {
                VEC_PUSH(*path, a->arcs[i].feat);
                conflicts_rec(c, a->arcs[i].val, b->arcs[j].val, path, out, n, max, depth + 1);
                path->n--;
                i++; j++;
            } else if (a->arcs[i].feat < b->arcs[j].feat) i++;
            else j++;
        }
    }
    if (*n == before && *n < max) {
        Buf p = { 0 };
        path_format(c, &p, path->v, path->n);
        snprintf(out[(*n)++], 256, "%s", p.s);
        buf_free(&p);
    }
}

size_t tri_conflicts(TriContent *c, const TriNode *a, const TriNode *b, char (*paths)[256], size_t max)
{
    size_t n = 0;
    U32Vec path = { 0 };
    conflicts_rec(c, (TriNode *) a, (TriNode *) b, &path, paths, &n, max, 0);
    VEC_FREE(path);
    return n;
}

/* A copy that shares nothing with its source (apart from type expansions a
 * lazy node stands for), keeping its own shared nodes shared: what a store
 * compacts by, copying its live descriptions into a fresh arena. */
const TriNode *tri_copy(TriContent *c, const TriNode *node, TriArena *out)
{
    return copy_raw(c, out, (TriNode *) node);
}
