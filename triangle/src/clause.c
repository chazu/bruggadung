#include "internal.h"

/* Definite clauses over feature structures (CONTENT_LANGUAGE.md §10), in the
 * manner of LiLFeS: relations whose arguments are typed feature structures,
 * for what rules can't say without recursion, such as reachability.
 *
 *   edge_ab:   #Fact & { head: #Edge & { from: "a", to: "b" } }
 *   reach_one: #Clause & { head: #Reach & { from: $x, to: $y },
 *                          body: [#Edge & { from: $x, to: $y }] }
 *   reach_far: #Clause & { head: #Reach & { from: $x, to: $z },
 *                          body: [#Edge & { from: $x, to: $y }, #Reach & { from: $y, to: $z }] }
 *
 * A query is a structure (#Reach & { from: "a" }); each solution is the query
 * made specific by one proof. Resolution is depth-first over the goals left to
 * right and the clauses in name order, so solutions come in a fixed order; a
 * depth limit bounds each proof, and the caller learns if it cut any short.
 * Each clause is copied fresh for each use, so its tags are its variables. */

typedef struct {
    Content *c;
    uint32_t fhead, fbody;
    U32Vec clauses;             /* instance × variant, in name order: (inst << 8) | variant */
    TriArena *work;
    TriArena *out;
    const TriNode **solutions;
    size_t max, n;
    size_t limit;
    bool truncated;
    size_t steps, step_limit;
} Solver;

static int cmp_inst_name(const void *a, const void *b, void *ctx)
{
    Content *c = ctx;
    uint32_t x = *(const uint32_t *) a >> 8, y = *(const uint32_t *) b >> 8;
    int r = strcmp(c->insts.v[x].name, c->insts.v[y].name);
    if (r) return r;
    return (int) (*(const uint32_t *) a & 255) - (int) (*(const uint32_t *) b & 255);
}

static void sort_clauses(Content *c, U32Vec *v)
{
    for (size_t i = 1; i < v->n; i++)
        for (size_t j = i; j > 0 && cmp_inst_name(&v->v[j - 1], &v->v[j], c) > 0; j--) {
            uint32_t t = v->v[j]; v->v[j] = v->v[j - 1]; v->v[j - 1] = t;
        }
}

typedef VEC(TriNode *) NodeVec;

/* The goals of a clause body, a list, in order. */
static void list_items(Content *c, TriNode *list, NodeVec *out)
{
    for (int guard = 0; list && guard < 10000; guard++) {
        list = deref(c, list);
        TriNode *first = carc_find(c, list, c->ffirst), *rest = carc_find(c, list, c->frest);
        if (!first || !rest) break;
        VEC_PUSH(*out, first);
        list = rest;
    }
}

/* A clause's arithmetic, waiting for its arguments during the search. Its
 * nodes live in the state's roots, so they are copied with the resolvent. */
#define PEND_TAGS 8
typedef struct {
    const X *expr;
    uint32_t target;                /* index in roots */
    uint32_t ntags;
    Sym names[PEND_TAGS];
    uint32_t tags[PEND_TAGS];       /* indices in roots */
} Pend;

/* roots: the query, then the goals, then the nodes pending constraints use */
typedef struct {
    TriNode **roots;
    size_t ngoals, nroots;
    Pend *pend;
    size_t npend;
} State;

typedef struct { const State *st; const Pend *p; Content *c; } PLookup;

static bool pend_lookup(void *ctx, Sym tag, Quantity *q)
{
    PLookup *l = ctx;
    for (uint32_t i = 0; i < l->p->ntags; i++) {
        if (l->p->names[i] != tag) continue;
        TriNode *n = l->st->roots[l->p->tags[i]];
        if (!(n->flags & NF_DIM)) return false;
        q->dim = l->c->types.v[n->type].dim;
        q->lo = n->lo;
        q->hi = n->hi;
        return true;
    }
    return false;
}

/* Narrows every pending constraint's target as far as its arguments allow,
 * copying the state again when anything changed. False if one can't hold. */
static bool propagate_pending(Solver *s, State *st)
{
    Content *c = s->c;
    for (int round = 0; round < 16; round++) {
        TriMark sm = tri_arena_mark(c->scratch);
        uint32_t saved = op_begin(c);
        c->failed = false;
        c->depth = 0;
        bool ok = true, changed = false;
        for (size_t k = 0; k < st->npend && ok; k++) {
            Pend *p = &st->pend[k];
            PLookup l = { st, p, c };
            Quantity q;
            const char *err = arith_eval(p->expr, pend_lookup, &l, &q);
            if (err == ARITH_UNKNOWN) continue;
            if (err) { ok = false; break; }
            TriNode *t = st->roots[p->target];
            if (t->flags & NF_DIM) {
                int64_t lo, hi;
                node_iv(c, t, &lo, &hi);
                if (q.lo <= lo && q.hi >= hi) continue;
            } else if (t->type != c->top) {
                ok = false;
                break;
            }
            ok = unify1(c, t, leaf_new(c, c->scratch, c->dimtype[q.dim], q.lo, q.hi));
            changed = true;
        }
        if (ok && changed) copy_out_many(c, s->work, st->roots, st->nroots);
        op_end(c, saved);
        tri_arena_release(c->scratch, sm);
        if (!ok) return false;
        if (!changed) return true;
    }
    return true;
}

static void solve(Solver *s, State *st, size_t depth)
{
    Content *c = s->c;
    if (s->n >= s->max) return;
    if (!propagate_pending(s, st)) return;
    if (!st->ngoals) {
        /* a proof: the query, made as specific as it allows, independent of the work arena */
        TriFailure f;
        TriNode *q = copy_raw(c, s->out, st->roots[0]);
        q = settle(c, q, NULL, s->out, &f);
        if (q) s->solutions[s->n++] = q;
        return;
    }
    if (depth >= s->limit || ++s->steps > s->step_limit) { s->truncated = true; return; }
    TriNode *goal = st->roots[1];
    for (size_t k = 0; k < s->clauses.n && s->n < s->max; k++) {
        InstVariant *cv = &c->insts.v[s->clauses.v[k] >> 8].vars.v[s->clauses.v[k] & 255];
        TriNode *pattern = cv->pattern;
        TriNode *head = node_arc(pattern, s->fhead);
        if (!head || meet(c, head->type, goal->type) == TRI_BOTTOM) continue;
        TriMark wm = tri_arena_mark(s->work);
        TriMark sm = tri_arena_mark(c->scratch);
        uint32_t saved = op_begin(c);
        c->failed = false;
        c->depth = 0;
        TriNode *fresh = copy_raw(c, c->scratch, pattern);          /* fresh variables */
        bool ok = unify1(c, goal, node_arc(fresh, s->fhead));
        State next = { 0 };
        if (ok) {
            NodeVec body = { 0 };
            list_items(c, node_arc(fresh, s->fbody), &body);
            /* the clause's arithmetic: its target and tags become roots */
            size_t newnodes = 0;
            for (size_t i = 0; i < cv->ariths.n; i++) newnodes += 1 + cv->ariths.v[i].tags.n;
            size_t oldpend = st->nroots - 1 - st->ngoals;
            next.ngoals = body.n + st->ngoals - 1;
            next.nroots = 1 + next.ngoals + oldpend + newnodes;
            next.roots = malloc(sizeof(TriNode *) * next.nroots);
            next.npend = st->npend;
            next.pend = malloc(sizeof(Pend) * (st->npend + cv->ariths.n + 1));
            size_t r = 0;
            next.roots[r++] = st->roots[0];
            for (size_t i = 0; i < body.n; i++) next.roots[r++] = body.v[i];
            for (size_t i = 2; i < 1 + st->ngoals; i++) next.roots[r++] = st->roots[i];
            /* old pending nodes keep their order, shifted */
            size_t shift = r - (1 + st->ngoals);
            for (size_t i = 1 + st->ngoals; i < st->nroots; i++) next.roots[r++] = st->roots[i];
            for (size_t i = 0; i < st->npend; i++) {
                next.pend[i] = st->pend[i];
                next.pend[i].target = (uint32_t) (st->pend[i].target + shift);
                for (uint32_t t = 0; t < next.pend[i].ntags; t++) next.pend[i].tags[t] = (uint32_t) (st->pend[i].tags[t] + shift);
            }
            for (size_t i = 0; i < cv->ariths.n && ok; i++) {
                const ArithRec *ar = &cv->ariths.v[i];
                Pend p = { ar->expr, (uint32_t) r, 0, { 0 }, { 0 } };
                TriNode *tn = node_at(fresh, ar->path.v, ar->path.n);
                if (!tn || ar->tags.n > PEND_TAGS) { ok = false; break; }
                next.roots[r++] = tn;
                for (size_t t = 0; t < ar->tags.n; t++) {
                    TriNode *vn = node_at(fresh, ar->tags.v[t].path.v, ar->tags.v[t].path.n);
                    if (!vn) { ok = false; break; }
                    p.names[p.ntags] = ar->tags.v[t].name;
                    p.tags[p.ntags++] = (uint32_t) r;
                    next.roots[r++] = vn;
                }
                next.pend[next.npend++] = p;
            }
            next.nroots = r;
            if (ok) copy_out_many(c, s->work, next.roots, next.nroots);
            VEC_FREE(body);
        }
        op_end(c, saved);
        tri_arena_release(c->scratch, sm);
        if (ok) solve(s, &next, depth + 1);
        free(next.roots);
        free(next.pend);
        tri_arena_release(s->work, wm);
    }
}

size_t tri_solve(TriContent *c, const TriNode *query, size_t depth_limit, const TriNode **solutions, size_t max,
                 TriArena *out, int *truncated)
{
    Solver s = { 0 };
    s.c = c;
    s.fhead = feat_lookup(c, intern(c, "head"));
    s.fbody = feat_lookup(c, intern(c, "body"));
    uint32_t tclause = type_lookup(c, intern(c, "#Clause"));
    if (truncated) *truncated = 0;
    if (s.fhead == TRI_BOTTOM || s.fbody == TRI_BOTTOM || tclause == TRI_BOTTOM || !query || !max) return 0;
    for (uint32_t i = 0; i < c->insts.n; i++) {
        if (!inst_pattern(c, i)) continue;
        InstInfo *in = &c->insts.v[i];
        for (size_t v = 0; v < in->vars.n && v < 256; v++)
            if (is_subtype(c, in->vars.v[v].pattern->type, tclause)) VEC_PUSH(s.clauses, (i << 8) | (uint32_t) v);
    }
    sort_clauses(c, &s.clauses);
    s.work = tri_arena_new();
    s.out = out;
    s.solutions = solutions;
    s.max = max;
    s.limit = depth_limit;
    s.step_limit = 1000000;                   /* a bound on the whole search, as well as each proof */
    /* the query and its goal are one structure: solve it as the single goal */
    TriNode *q = copy_raw(c, s.work, (TriNode *) query);
    TriNode *roots[2] = { q, q };
    State st = { roots, 1, 2, NULL, 0 };
    solve(&s, &st, 0);
    tri_arena_free(s.work);
    VEC_FREE(s.clauses);
    if (truncated) *truncated = s.truncated;
    return s.n;
}
