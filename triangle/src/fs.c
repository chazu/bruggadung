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
    TriNode *n = arena_alloc(a, sizeof(TriNode));
    n->type = type;
    if (a == c->scratch) n->flags |= NF_SCRATCH;
    if (is_dim(c, type)) {
        n->flags |= NF_DIM;
        n->lo = TRI_NINF;
        n->hi = TRI_INF;
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
        n->sx = arena_alloc(c->scratch, sizeof(Scratch));
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
        Arc *na = arena_alloc(c->scratch, ncap * sizeof(Arc));
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

static void describe(Content *c, Buf *b, TriNode *n)
{
    if (is_dim(c, n->type)) {
        int64_t lo, hi;
        node_iv(c, n, &lo, &hi);
        int dim = c->types.v[n->type].dim;
        if (lo == hi) units_format(b, dim, lo);
        else if (lo == TRI_NINF && hi == TRI_INF) buf_puts(b, dim_names[dim]);
        else {
            if (lo != TRI_NINF) { buf_puts(b, ">="); units_format(b, dim, lo); }
            if (lo != TRI_NINF && hi != TRI_INF) buf_puts(b, " & ");
            if (hi != TRI_INF) { buf_puts(b, "<="); units_format(b, dim, hi); }
        }
    } else {
        buf_puts(b, c->types.v[n->type].name);
    }
}

void path_format(Content *c, Buf *b, const uint32_t *path, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        if (i) buf_putc(b, '.');
        buf_puts(b, c->feats.v[path[i]].name);
    }
    if (!n) buf_puts(b, "(root)");
}

static void fail_at(Content *c, TriNode *a, TriNode *b, const char *why)
{
    if (c->failed) return;
    c->failed = true;
    Buf p = { 0 }, l = { 0 }, r = { 0 };
    path_format(c, &p, c->pathstack, (size_t) c->depth);
    if (why) buf_puts(&l, why);
    else describe(c, &l, a);
    if (b) describe(c, &r, b);
    snprintf(c->fail.path, sizeof c->fail.path, "%s", p.s ? p.s : "");
    snprintf(c->fail.left, sizeof c->fail.left, "%s", l.s ? l.s : "");
    snprintf(c->fail.right, sizeof c->fail.right, "%s", r.s ? r.s : "");
    buf_free(&p);
    buf_free(&l);
    buf_free(&r);
}

/* --- unification ------------------------------------------------------------------------ */

bool unify1(Content *c, TriNode *a, TriNode *b)
{
    a = deref(c, a);
    b = deref(c, b);
    if (a == b) return true;
    uint32_t t = meet(c, a->type, b->type);
    if (t == TRI_BOTTOM) { fail_at(c, a, b, NULL); return false; }

    if (t != a->type && t != b->type) {
        /* A new, more specific type: its constraint must hold too. */
        TriNode *e = type_expansion(c, t);
        if (!e) { fail_at(c, a, b, "recursive type constraint"); return false; }
        TriNode *n = copy_raw(c, c->scratch, e);
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

    if (target->flags & NF_DIM) {
        int64_t lo1, hi1, lo2, hi2;
        node_iv(c, target, &lo1, &hi1);
        node_iv(c, src, &lo2, &hi2);
        int64_t lo = lo1 > lo2 ? lo1 : lo2, hi = hi1 < hi2 ? hi1 : hi2;
        if (lo > hi) { fail_at(c, a, b, NULL); return false; }
        if (lo != lo1 || hi != hi1) {
            Scratch *s = sx_make(c, target);
            s->slo = lo;
            s->shi = hi;
            s->hasiv = true;
        }
    }

    sx_make(c, src)->fwd = target;

    /* Take src's arc list first: adding comp-arcs to target can't affect it. */
    uint32_t nsrc = arc_count(c, src);
    if (!nsrc) return true;
    Scratch *ss = sx_get(c, src);
    Arc *arcs = arena_alloc(c->scratch, nsrc * sizeof(Arc));
    if (src->narcs) memcpy(arcs, src->arcs, src->narcs * sizeof(Arc));
    if (ss && ss->ncarcs) memcpy(arcs + src->narcs, ss->carcs, ss->ncarcs * sizeof(Arc));
    for (uint32_t i = 0; i < nsrc; i++) {
        uint32_t f = arcs[i].feat;
        TriNode *tv = carc_find(c, target, f);
        c->pathstack[c->depth++] = f;
        if (tv) {
            if (!unify1(c, tv, arcs[i].val)) return false;
        } else if (!approp(c, t, f)) {
            fail_at(c, target, NULL, "feature not appropriate for this type");
            return false;
        } else {
            carc_add(c, target, f, arcs[i].val);
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

static TriNode *copy_raw_rec(Content *c, TriArena *a, TriNode *n, uint32_t cg)
{
    if (n->cpygen == cg) return n->cpy;
    TriNode *m = node_new(c, a, n->type);
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
    if (na) {
        n->cpy = INPROGRESS;
        arcs = arena_alloc(c->scratch, na * sizeof(Arc));
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
    if (n->flags & NF_DIM) node_iv(c, n, &m->lo, &m->hi);
    if (na) {
        m->arcs = arena_alloc(a, na * sizeof(Arc));
        memcpy(m->arcs, arcs, na * sizeof(Arc));
        m->narcs = (uint16_t) na;
        for (uint32_t i = 0; i < na; i++)
            if (!approp(c, m->type, arcs[i].feat)) *ok = false;
    }
    n->cpy = m;
    return m;
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
    Scratch *sa = sx_make(c, a), *sb = sx_make(c, b);
    bool amapped = sa->fwd != NULL, bmapped = sb->bwd != NULL;
    if (amapped && bmapped && sa->fwd == b && sb->bwd == a) return;
    if (amapped && sa->fwd != b && !ext_equal(c, sa->fwd, b)) s->fwd = false;
    if (bmapped && sb->bwd != a && !ext_equal(c, sb->bwd, a)) s->bwd = false;
    if (!amapped) sa->fwd = b;
    if (!bmapped) sb->bwd = a;
    if (!is_subtype(c, b->type, a->type)) s->fwd = false;
    if (!is_subtype(c, a->type, b->type)) s->bwd = false;
    if ((a->flags & NF_DIM) && (b->flags & NF_DIM)) {
        if (!(b->lo >= a->lo && b->hi <= a->hi)) s->fwd = false;
        if (!(a->lo >= b->lo && a->hi <= b->hi)) s->bwd = false;
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

const TriNode *tri_at(const TriContent *cc, const TriNode *node, const char *path)
{
    Content *c = (Content *) cc;
    U32Vec p = { 0 };
    TriNode *r = path_parse(c, path, &p) ? node_at((TriNode *) node, p.v, p.n) : NULL;
    VEC_FREE(p);
    return r;
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
        *failure = c->fail;
    }
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    return r;
}
