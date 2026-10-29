#include "internal.h"

#include <time.h>

static double trace_t0;
static void trace(const char *what, size_t a, size_t b)
{
    static int on = -1;
    if (on < 0) on = getenv("TRI_TRACE") != NULL;
    if (!on) return;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double t = ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
    if (!trace_t0) trace_t0 = t;
    fprintf(stderr, "[%8.0f ms] %s %zu %zu\n", t - trace_t0, what, a, b);
}

/* Builds the type hierarchy: types from declarations and atoms, anonymous
 * enums, completion to a bounded complete partial order (generated meet types),
 * deterministic IDs, codes for meets, and feature appropriateness. */

static Loc noloc;

uint32_t type_lookup(const Content *c, Sym name)
{
    uint64_t v;
    if (u64map_get(&c->typeidx, (uint64_t) (uintptr_t) name, &v)) return (uint32_t) v - 1;
    return TRI_BOTTOM;
}

uint32_t feat_lookup(const Content *c, Sym name)
{
    uint64_t v;
    if (u64map_get(&c->featidx, (uint64_t) (uintptr_t) name, &v)) return (uint32_t) v - 1;
    return TRI_BOTTOM;
}

static uint32_t type_add(Content *c, Sym name, TypeKind kind)
{
    TypeInfo t = { 0 };
    t.name = name;
    t.kind = kind;
    t.dim = -1;
    t.bit = -1;          /* no code until compute_codes runs */
    VEC_PUSH(c->types, t);
    uint32_t id = (uint32_t) c->types.n - 1;
    u64map_put(&c->typeidx, (uint64_t) (uintptr_t) name, id + 1);
    return id;
}

static uint32_t type_get(Content *c, Sym name, TypeKind kind)
{
    uint32_t t = type_lookup(c, name);
    return t != TRI_BOTTOM ? t : type_add(c, name, kind);
}

static void add_parent(Content *c, uint32_t child, uint32_t parent)
{
    TypeInfo *t = &c->types.v[child];
    for (size_t i = 0; i < t->parents.n; i++)
        if (t->parents.v[i] == parent) return;
    VEC_PUSH(t->parents, parent);
}

static int cmp_sym(const void *a, const void *b)
{
    return strcmp(*(Sym const *) a, *(Sym const *) b);
}

/* --- codes ----------------------------------------------------------------------- */

/* Codes are descendant sets over "bits". Leaf types (no subtypes, one parent)
 * get no bit, as in PET: the many string types would otherwise make every
 * code enormous. Their subsumption follows the parent chain instead. */

static inline bool code_has_bit(const uint64_t *code, int32_t bit)
{
    return bit >= 0 && ((code[bit >> 6] >> (bit & 63)) & 1);
}

static void compute_codes(Content *c)
{
    size_t n = c->types.n;
    for (size_t i = 0; i < n; i++) {
        TypeInfo *t = &c->types.v[i];
        free(t->code);
        t->code = NULL;
        t->children.n = 0;
    }
    for (size_t i = 0; i < n; i++)
        for (size_t j = 0; j < c->types.v[i].parents.n; j++)
            VEC_PUSH(c->types.v[c->types.v[i].parents.v[j]].children, (uint32_t) i);
    c->nbits = 0;
    for (size_t i = 0; i < n; i++) {
        TypeInfo *t = &c->types.v[i];
        t->bit = (t->children.n == 0 && t->parents.n == 1) ? -1 : (int32_t) c->nbits++;
    }
    c->bittype = realloc(c->bittype, (c->nbits ? c->nbits : 1) * sizeof(uint32_t));
    c->codewords = (c->nbits + 63) / 64;
    if (!c->codewords) c->codewords = 1;
    for (size_t i = 0; i < n; i++) {
        TypeInfo *t = &c->types.v[i];
        if (t->bit < 0) continue;
        c->bittype[t->bit] = (uint32_t) i;
        t->code = calloc(c->codewords, 8);
    }
    /* propagate upward from the lowest non-leaf types */
    uint32_t *order = malloc(n * sizeof(uint32_t));
    uint32_t *indeg = calloc(n, sizeof(uint32_t));
    size_t head = 0, tail = 0;
    for (size_t i = 0; i < n; i++) {
        if (c->types.v[i].bit < 0) continue;
        for (size_t k = 0; k < c->types.v[i].children.n; k++)
            if (c->types.v[c->types.v[i].children.v[k]].bit >= 0) indeg[i]++;
        if (!indeg[i]) order[tail++] = (uint32_t) i;
    }
    while (head < tail) {
        uint32_t t = order[head++];
        TypeInfo *ti = &c->types.v[t];
        ti->code[ti->bit >> 6] |= 1ULL << (ti->bit & 63);
        for (size_t k = 0; k < ti->children.n; k++) {
            TypeInfo *ch = &c->types.v[ti->children.v[k]];
            if (ch->bit < 0) continue;
            for (size_t w = 0; w < c->codewords; w++) ti->code[w] |= ch->code[w];
        }
        for (size_t k = 0; k < ti->parents.n; k++) {
            uint32_t p = ti->parents.v[k];
            if (--indeg[p] == 0) order[tail++] = p;
        }
    }
    free(order);
    free(indeg);
}

static uint64_t code_hash(const Content *c, const uint64_t *code)
{
    uint64_t h = 0x9e3779b97f4a7c15ULL;
    for (size_t w = 0; w < c->codewords; w++) h = hash64(h ^ code[w]) + w;
    return h;
}

static void index_codes(Content *c)
{
    u64map_free(&c->codeidx);
    for (size_t i = 0; i < c->types.n; i++)
        if (c->types.v[i].bit >= 0) u64map_put(&c->codeidx, code_hash(c, c->types.v[i].code), i + 1);
}

static uint32_t type_with_code(Content *c, const uint64_t *code)
{
    uint64_t v;
    if (u64map_get(&c->codeidx, code_hash(c, code), &v) &&
        memcmp(c->types.v[v - 1].code, code, c->codewords * 8) == 0)
        return (uint32_t) v - 1;
    return TRI_BOTTOM;   /* a 64-bit hash collision would make a meet look missing */
}

bool is_subtype(const Content *c, uint32_t a, uint32_t b)
{
    if (a == b) return true;
    const TypeInfo *tb = &c->types.v[b];
    if (tb->bit < 0) return false;
    while (c->types.v[a].bit < 0) {
        a = c->types.v[a].parents.v[0];
        if (a == b) return true;
    }
    return code_has_bit(tb->code, c->types.v[a].bit);
}

uint32_t meet(Content *c, uint32_t a, uint32_t b)
{
    if (a == b) return a;
    if (a == TRI_BOTTOM || b == TRI_BOTTOM) return TRI_BOTTOM;
    if (is_subtype(c, a, b)) return a;
    if (is_subtype(c, b, a)) return b;
    if (c->types.v[a].bit < 0 || c->types.v[b].bit < 0) return TRI_BOTTOM;
    uint64_t key = a < b ? ((uint64_t) a << 32 | b) : ((uint64_t) b << 32 | a);
    uint64_t v;
    if (u64map_get(&c->meetmemo, key, &v)) return (uint32_t) v;
    uint64_t *ca = c->types.v[a].code, *cb = c->types.v[b].code;
    uint64_t *tmp = malloc(c->codewords * 8);
    bool any = false;
    for (size_t w = 0; w < c->codewords; w++) {
        tmp[w] = ca[w] & cb[w];
        any |= tmp[w] != 0;
    }
    uint32_t r = any ? type_with_code(c, tmp) : TRI_BOTTOM;
    free(tmp);
    u64map_put(&c->meetmemo, key, r);
    return r;
}

bool approp(const Content *c, uint32_t t, uint32_t f)
{
    const U32Vec *fs = &c->types.v[t].feats;
    size_t lo = 0, hi = fs->n;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (fs->v[mid] == f) return true;
        if (fs->v[mid] < f) lo = mid + 1; else hi = mid;
    }
    return false;
}

bool is_dim(const Content *c, uint32_t t)
{
    return t < c->types.n && c->types.v[t].kind == TK_DIM;
}

bool is_leaf(const Content *c, uint32_t t)
{
    return c->types.v[t].children.n == 0 && c->types.v[t].feats.n == 0;
}

/* --- anonymous enums ----------------------------------------------------------------- */

static void or_atoms(X *x, SymVec *out, bool *ok)
{
    if (x->k == X_OR) {
        or_atoms(x->u.bin.a, out, ok);
        or_atoms(x->u.bin.b, out, ok);
    } else if (x->k == X_DEFAULT) {
        or_atoms(x->u.sub, out, ok);
    } else if (x->k == X_ATOM) {
        VEC_PUSH(*out, x->u.name);
    } else {
        *ok = false;
    }
}

Sym anon_name(Content *c, X *orx)
{
    SymVec atoms = { 0 };
    bool ok = true;
    or_atoms(orx, &atoms, &ok);
    Sym r = NULL;
    if (ok && atoms.n) {
        qsort(atoms.v, atoms.n, sizeof(Sym), cmp_sym);
        size_t k = 0;
        for (size_t i = 0; i < atoms.n; i++)
            if (!k || atoms.v[k - 1] != atoms.v[i]) atoms.v[k++] = atoms.v[i];
        atoms.n = k;
        if (k >= 2) {
            Buf b = { 0 };
            for (size_t i = 0; i < k; i++) {
                if (i) buf_puts(&b, " | ");
                buf_puts(&b, atoms.v[i]);
            }
            r = intern(c, b.s);
            buf_free(&b);
        }
    }
    VEC_FREE(atoms);
    return r;
}

static void disjuncts(X *x, XPtrVec *out)
{
    if (x->k == X_OR) { disjuncts(x->u.bin.a, out); disjuncts(x->u.bin.b, out); }
    else VEC_PUSH(*out, x);
}

/* Registers atom literals and anonymous enums found anywhere in an expression. */
static void scan_expr(Content *c, X *x)
{
    if (!x) return;
    switch (x->k) {
    case X_ATOM:
        if (type_lookup(c, x->u.name) == TRI_BOTTOM) {
            uint32_t t = type_add(c, x->u.name, TK_ATOM);
            (void) t;
        }
        break;
    case X_OR: {
        Sym an = anon_name(c, x);
        if (an && type_lookup(c, an) == TRI_BOTTOM) {
            uint32_t t = type_add(c, an, TK_ANON);
            SymVec atoms = { 0 };
            bool ok = true;
            or_atoms(x, &atoms, &ok);
            for (size_t i = 0; i < atoms.n; i++) {
                bool dup = false;
                for (size_t j = 0; j < c->types.v[t].members.n; j++)
                    if (c->types.v[t].members.v[j] == atoms.v[i]) dup = true;
                if (!dup) VEC_PUSH(c->types.v[t].members, atoms.v[i]);
            }
            VEC_FREE(atoms);
        }
        /* only the whole chain is an enum; its disjuncts are scanned individually */
        XPtrVec ds = { 0 };
        disjuncts(x, &ds);
        for (size_t i = 0; i < ds.n; i++) scan_expr(c, ds.v[i]);
        VEC_FREE(ds);
        break;
    }
    case X_AND:
        scan_expr(c, x->u.bin.a);
        scan_expr(c, x->u.bin.b);
        break;
    case X_DEFAULT:
        scan_expr(c, x->u.sub);
        break;
    case X_STRUCT:
        for (int i = 0; i < x->u.st.n; i++) scan_expr(c, x->u.st.fields[i].value);
        break;
    case X_LIST:
        for (int i = 0; i < x->u.list.n; i++) scan_expr(c, x->u.list.items[i]);
        break;
    default:
        break;
    }
}

static void conjuncts(X *x, XPtrVec *out)
{
    if (x->k == X_AND) {
        conjuncts(x->u.bin.a, out);
        conjuncts(x->u.bin.b, out);
    } else {
        VEC_PUSH(*out, x);
    }
}

typedef VEC(SymVec) SymSets;

/* Collects the sets of named types conjoined in each AND chain. The top-level
 * chain of an instance is handled across all its declarations instead. */
static void conj_sets(Content *c, X *x, bool skip_root, SymSets *out)
{
    if (!x) return;
    if (x->k == X_AND) {
        XPtrVec cj = { 0 };
        conjuncts(x, &cj);
        SymVec names = { 0 };
        for (size_t j = 0; j < cj.n; j++) {
            X *y = cj.v[j];
            if (y->k == X_NAME) {
                uint32_t t = type_lookup(c, y->u.name);
                if (t != TRI_BOTTOM && c->types.v[t].kind == TK_DEF) VEC_PUSH(names, y->u.name);
            } else {
                conj_sets(c, y, false, out);
            }
        }
        if (names.n >= 2 && !skip_root) VEC_PUSH(*out, names);
        else VEC_FREE(names);
        VEC_FREE(cj);
        return;
    }
    switch (x->k) {
    case X_OR: conj_sets(c, x->u.bin.a, false, out); conj_sets(c, x->u.bin.b, false, out); break;
    case X_DEFAULT: conj_sets(c, x->u.sub, false, out); break;
    case X_STRUCT:
        for (int i = 0; i < x->u.st.n; i++) conj_sets(c, x->u.st.fields[i].value, false, out);
        break;
    case X_LIST:
        for (int i = 0; i < x->u.list.n; i++) conj_sets(c, x->u.list.items[i], false, out);
        break;
    default: break;
    }
}

/* --- topological renumbering ---------------------------------------------------------- */

static void renumber(Content *c)
{
    size_t n = c->types.n;
    uint32_t *indeg = calloc(n, sizeof(uint32_t));
    for (size_t i = 0; i < n; i++) indeg[i] = (uint32_t) c->types.v[i].parents.n;
    /* Kahn's algorithm with a ready set ordered by name. */
    uint32_t *heap = malloc(n * sizeof(uint32_t));
    size_t hn = 0;
#define LESS(a, b) (strcmp(c->types.v[a].name, c->types.v[b].name) < 0)
#define PUSH(x) do { size_t i_ = hn++; heap[i_] = (x); \
        while (i_ && LESS(heap[i_], heap[(i_ - 1) / 2])) { \
            uint32_t t_ = heap[i_]; heap[i_] = heap[(i_ - 1) / 2]; heap[(i_ - 1) / 2] = t_; i_ = (i_ - 1) / 2; } } while (0)
    for (size_t i = 0; i < n; i++) if (!indeg[i]) PUSH((uint32_t) i);
    uint32_t *order = malloc(n * sizeof(uint32_t));
    uint32_t *newid = malloc(n * sizeof(uint32_t));
    size_t k = 0;
    while (hn) {
        uint32_t t = heap[0];
        heap[0] = heap[--hn];
        size_t i = 0;
        for (;;) {
            size_t l = 2 * i + 1, r = l + 1, m = i;
            if (l < hn && LESS(heap[l], heap[m])) m = l;
            if (r < hn && LESS(heap[r], heap[m])) m = r;
            if (m == i) break;
            uint32_t tmp = heap[i]; heap[i] = heap[m]; heap[m] = tmp;
            i = m;
        }
        order[k] = t;
        newid[t] = (uint32_t) k++;
        for (size_t j = 0; j < c->types.v[t].children.n; j++) {
            uint32_t ch = c->types.v[t].children.v[j];
            if (--indeg[ch] == 0) PUSH(ch);
        }
    }
#undef LESS
#undef PUSH
    TypeInfo *nt = malloc(n * sizeof(TypeInfo));
    for (size_t i = 0; i < n; i++) {
        nt[i] = c->types.v[order[i]];
        for (size_t j = 0; j < nt[i].parents.n; j++) nt[i].parents.v[j] = newid[nt[i].parents.v[j]];
    }
    free(c->types.v);
    c->types.v = nt;
    c->types.cap = n;
    u64map_free(&c->typeidx);
    for (size_t i = 0; i < n; i++)
        u64map_put(&c->typeidx, (uint64_t) (uintptr_t) c->types.v[i].name, i + 1);
    free(indeg);
    free(heap);
    free(order);
    free(newid);
}

static bool has_cycle(Content *c)
{
    size_t n = c->types.n;
    uint8_t *state = calloc(n, 1);
    uint32_t *stack = malloc(n * 2 * sizeof(uint32_t));
    bool cyc = false;
    for (size_t s = 0; s < n && !cyc; s++) {
        if (state[s]) continue;
        size_t sp = 0;
        stack[sp++] = (uint32_t) s;
        stack[sp++] = 0;
        state[s] = 1;
        while (sp && !cyc) {
            uint32_t t = stack[sp - 2], i = stack[sp - 1];
            if (i < c->types.v[t].parents.n) {
                stack[sp - 1]++;
                uint32_t p = c->types.v[t].parents.v[i];
                if (state[p] == 1) {
                    diag(c, true, noloc, "type hierarchy has a cycle through %s", c->types.v[p].name);
                    cyc = true;
                } else if (!state[p]) {
                    state[p] = 1;
                    stack[sp++] = p;
                    stack[sp++] = 0;
                }
            } else {
                state[t] = 2;
                sp -= 2;
            }
        }
    }
    free(state);
    free(stack);
    return cyc;
}

/* --- completion --------------------------------------------------------------------------- */

static void ancestors(Content *c, uint32_t m, uint32_t *mark, uint32_t stamp, U32Vec *out)
{
    out->n = 0;
    VEC_PUSH(*out, m);
    mark[m] = stamp;
    for (size_t i = 0; i < out->n; i++) {
        TypeInfo *t = &c->types.v[out->v[i]];
        for (size_t k = 0; k < t->parents.n; k++) {
            uint32_t p = t->parents.v[k];
            if (mark[p] != stamp) { mark[p] = stamp; VEC_PUSH(*out, p); }
        }
    }
}

static bool complete(Content *c)
{
    /* After the first round, a pair of older types keeps its meet: new meet
     * types only add codes below meets that already exist. So later rounds
     * only look at pairs involving a type made in the previous round. */
    size_t newfrom = 0;
    for (int round = 0; round < 64; round++) {
        compute_codes(c);
        index_codes(c);
        size_t n = c->types.n;
        trace("completion round: types, bits", n, c->nbits);
        VEC(uint64_t *) needed = { 0 };
        U64Map seen = { 0 };              /* hash of an intersection already handled */
        uint32_t *mark = calloc(n, sizeof(uint32_t));
        uint32_t stamp = 0;
        U32Vec anc = { 0 };
        uint64_t *inter = malloc(c->codewords * 8);
        uint32_t *news = malloc(n * sizeof(uint32_t));
        size_t npairs = 0, nincomp = 0;
        U64Map pairs = { 0 };               /* pairs already examined this round */
        for (size_t m = 0; m < n; m++) {
            if (c->types.v[m].parents.n < 2) continue;
            ancestors(c, (uint32_t) m, mark, ++stamp, &anc);
            /* first round: all pairs of ancestors; later: pairs with a new type */
            size_t ni = 0;
            for (size_t i = 1; i < anc.n; i++)
                if (!round || anc.v[i] >= newfrom) news[ni++] = anc.v[i];
            for (size_t i = 0; i < ni; i++)
                for (size_t j = 1; j < anc.n; j++) {
                    uint32_t a = news[i], b = anc.v[j];
                    if (a == b || (b >= newfrom || !round ? b < a : false)) continue;
                    npairs++;
                    uint64_t pk = a < b ? ((uint64_t) a << 32 | b) : ((uint64_t) b << 32 | a);
                    if (u64map_get(&pairs, pk, NULL)) continue;
                    u64map_put(&pairs, pk, 1);
                    if (is_subtype(c, a, b) || is_subtype(c, b, a)) continue;
                    nincomp++;
                    const uint64_t *ca = c->types.v[a].code, *cb = c->types.v[b].code;
                    for (size_t w = 0; w < c->codewords; w++) inter[w] = ca[w] & cb[w];
                    uint64_t h = code_hash(c, inter);
                    if (u64map_get(&seen, h, NULL)) continue;
                    u64map_put(&seen, h, 1);
                    if (type_with_code(c, inter) != TRI_BOTTOM) continue;
                    uint64_t *copy = malloc(c->codewords * 8);
                    memcpy(copy, inter, c->codewords * 8);
                    VEC_PUSH(needed, copy);
                }
        }
        free(inter);
        free(news);
        trace("  pairs examined, incomparable", npairs, nincomp);
        trace("  distinct pairs", pairs.count, 0);
        u64map_free(&pairs);
        trace("  pairs done: needed, seen", needed.n, seen.count);
        u64map_free(&seen);
        if (!needed.n) { free(mark); VEC_FREE(anc); return true; }
        c->nglb += needed.n;
        newfrom = n;                        /* types from here on are this round's */
        /* new glb types are added below and may be reached as ancestors */
        free(mark);
        mark = calloc(n + needed.n, sizeof(uint32_t));
        stamp = 0;
        U32Vec created = { 0 };
        for (size_t k = 0; k < needed.n; k++) {
            uint64_t *in = needed.v[k];
            SymVec maxes = { 0 };
            U32Vec maxids = { 0 };
            for (uint32_t bit = 0; bit < c->nbits; bit++) {
                if (!code_has_bit(in, (int32_t) bit)) continue;
                uint32_t x = c->bittype[bit];
                bool maximal = true;
                for (size_t q = 0; q < c->types.v[x].parents.n && maximal; q++)
                    if (code_has_bit(in, c->types.v[c->types.v[x].parents.v[q]].bit)) maximal = false;
                if (maximal) { VEC_PUSH(maxes, c->types.v[x].name); VEC_PUSH(maxids, x); }
            }
            qsort(maxes.v, maxes.n, sizeof(Sym), cmp_sym);
            Buf b = { 0 };
            for (int suffix = 1;; suffix++) {
                b.len = 0;
                buf_puts(&b, "glb[");
                for (size_t i = 0; i < maxes.n; i++) {
                    if (i) buf_putc(&b, ',');
                    buf_puts(&b, maxes.v[i]);
                }
                buf_putc(&b, ']');
                if (suffix > 1) buf_printf(&b, "#%d", suffix);
                if (type_lookup(c, intern(c, b.s)) == TRI_BOTTOM) break;
            }
            uint32_t g = type_add(c, intern(c, b.s), TK_GLB);
            VEC_PUSH(created, g);
            buf_free(&b);
            for (size_t i = 0; i < maxes.n; i++) VEC_PUSH(c->types.v[g].members, maxes.v[i]);
            /* parents: the minimal common ancestors of the maximal members, outside the set */
            U32Vec cands = { 0 };
            ancestors(c, maxids.v[0], mark, ++stamp, &anc);
            for (size_t i = 0; i < anc.n; i++) {
                uint32_t u = anc.v[i];
                if (u == g || code_has_bit(in, c->types.v[u].bit)) continue;
                bool all = true;
                for (size_t q = 1; q < maxids.n && all; q++) all = is_subtype(c, maxids.v[q], u);
                if (all) VEC_PUSH(cands, u);
            }
            SymVec pnames = { 0 };
            for (size_t i = 0; i < cands.n; i++) {
                bool minimal = true;
                for (size_t j = 0; j < cands.n && minimal; j++)
                    if (i != j && is_subtype(c, cands.v[j], cands.v[i])) minimal = false;
                if (minimal) VEC_PUSH(pnames, c->types.v[cands.v[i]].name);
            }
            qsort(pnames.v, pnames.n, sizeof(Sym), cmp_sym);
            for (size_t i = 0; i < pnames.n; i++) add_parent(c, g, type_lookup(c, pnames.v[i]));
            for (size_t i = 0; i < maxids.n; i++) add_parent(c, maxids.v[i], g);
            VEC_FREE(cands);
            VEC_FREE(pnames);
            VEC_FREE(maxes);
            VEC_FREE(maxids);
        }
        /* Meet types made in the same round don't see each other's codes yet:
         * place each under the minimal other new ones whose sets contain its set. */
        size_t W = c->codewords;
        for (size_t i = 0; i < needed.n; i++) {
            U32Vec sup = { 0 };
            for (size_t j = 0; j < needed.n; j++) {
                if (i == j) continue;
                bool subset = true, proper = false;
                for (size_t w = 0; w < W && subset; w++) {
                    uint64_t a = needed.v[i][w], bb = needed.v[j][w];
                    if (a & ~bb) subset = false;
                    if (bb & ~a) proper = true;
                }
                if (subset && proper) VEC_PUSH(sup, (uint32_t) j);
            }
            for (size_t x = 0; x < sup.n; x++) {
                bool minimal = true;
                for (size_t y = 0; y < sup.n && minimal; y++) {
                    if (x == y) continue;
                    bool sub = true;          /* needed[sup[y]] ⊊ needed[sup[x]] ? */
                    for (size_t w = 0; w < W && sub; w++)
                        if (needed.v[sup.v[y]][w] & ~needed.v[sup.v[x]][w]) sub = false;
                    if (sub) minimal = false;
                }
                if (minimal) add_parent(c, created.v[i], created.v[sup.v[x]]);
            }
            VEC_FREE(sup);
        }
        for (size_t k = 0; k < needed.n; k++) free(needed.v[k]);
        VEC_FREE(created);
        VEC_FREE(needed);
        free(mark);
        VEC_FREE(anc);
    }
    diag(c, true, noloc, "type hierarchy completion did not converge");
    return false;
}

/* --- building ------------------------------------------------------------------------------- */

static uint32_t inst_get(Content *c, Sym name)
{
    uint64_t v;
    if (u64map_get(&c->instidx, (uint64_t) (uintptr_t) name, &v)) return (uint32_t) v - 1;
    InstInfo in = { 0 };
    in.name = name;
    VEC_PUSH(c->insts, in);
    u64map_put(&c->instidx, (uint64_t) (uintptr_t) name, c->insts.n);
    return (uint32_t) c->insts.n - 1;
}

static char *trim_dup(const char *s)
{
    while (*s == ' ' || *s == '\t') s++;
    size_t n = strlen(s);
    while (n && (s[n - 1] == ' ' || s[n - 1] == '\t')) n--;
    char *r = malloc(n + 1);
    memcpy(r, s, n);
    r[n] = 0;
    return r;
}

bool types_build(Content *c)
{
    int errors0 = c->nerrors;

    /* builtins */
    c->top = type_add(c, intern(c, "_"), TK_TOP);
    c->atomroot = type_add(c, intern(c, "atom"), TK_ATOMROOT);
    add_parent(c, c->atomroot, c->top);
    for (int d = 0; d < NDIMS; d++) {
        uint32_t t = type_add(c, intern(c, dim_names[d]), TK_DIM);
        c->types.v[t].dim = d;
        add_parent(c, t, c->top);
    }

    /* declarations */
    for (size_t i = 0; i < c->decls.n; i++) {
        Decl *d = &c->decls.v[i];
        if (d->kind == L_DEF || d->kind == L_ATOM) {
            uint32_t t = type_get(c, d->label, d->kind == L_DEF ? TK_DEF : TK_ATOM);
            VEC_PUSH(c->types.v[t].decls, d);
        } else {
            if (type_lookup(c, d->label) != TRI_BOTTOM) {
                diag(c, true, d->loc, "instance name %s is a built-in type", d->label);
                continue;
            }
            uint32_t in = inst_get(c, d->label);
            VEC_PUSH(c->insts.v[in].decls, d);
        }
    }
    for (size_t i = 0; i < c->decls.n; i++) {
        X *v = c->decls.v[i].value;
        if (c->decls.v[i].kind != L_INST && v->k == X_OR) {
            /* an enum declaration lists its atoms; it is not an anonymous enum */
            XPtrVec ds = { 0 };
            disjuncts(v, &ds);
            for (size_t k = 0; k < ds.n; k++) scan_expr(c, ds.v[k]);
            VEC_FREE(ds);
        } else {
            scan_expr(c, v);
        }
    }

    /* TDL strings are subtypes of the grammar's `string` type */
    c->stringroot = c->tdl ? type_lookup(c, intern(c, "#string")) : TRI_BOTTOM;

    /* parents from declarations */
    size_t nnamed = c->types.n;
    SymVec *listers = calloc(nnamed, sizeof *listers);   /* named enums listing each atom */
    VEC(uint64_t) addparents = { 0 };                     /* (type << 32 | parent) from addenda */
    bool *enumtype = calloc(nnamed, 1);
    for (uint32_t t = 0; t < nnamed; t++) {
        TypeInfo *ti = &c->types.v[t];
        if (ti->kind != TK_DEF && ti->kind != TK_ATOM) continue;
        Loc ploc = noloc;
        bool have_parents = false;
        for (size_t k = 0; k < ti->decls.n; k++) {
            Decl *d = ti->decls.v[k];
            XPtrVec cj = { 0 };
            conjuncts(d->value, &cj);
            U32Vec parents = { 0 };
            for (size_t j = 0; j < cj.n; j++) {
                X *x = cj.v[j];
                if (x->k == X_NAME && ti->kind == TK_DEF) {
                    uint32_t p = type_lookup(c, x->u.name);
                    if (p == TRI_BOTTOM || c->types.v[p].kind != TK_DEF) {
                        diag(c, true, x->loc, "%s is not a type that %s can inherit from",
                             x->u.name, ti->name);
                        continue;
                    }
                    VEC_PUSH(parents, p);
                } else if (x->k == X_STRUCT && ti->kind == TK_DEF) {
                    /* body: handled when features are inferred */
                } else if (x->k == X_TOP && ti->kind == TK_DEF) {
                    /* *top* in TDL: the default parent */
                } else if (x->k == X_OR || x->k == X_ATOM) {
                    SymVec atoms = { 0 };
                    bool ok = true;
                    or_atoms(x, &atoms, &ok);
                    if (!ok) {
                        diag(c, true, x->loc, "only atoms may be listed in the enum %s", ti->name);
                    } else {
                        enumtype[t] = true;
                        for (size_t a = 0; a < atoms.n; a++) {
                            uint32_t at = type_lookup(c, atoms.v[a]);
                            bool dup = false;
                            for (size_t q = 0; q < listers[at].n; q++)
                                if (listers[at].v[q] == ti->name) dup = true;
                            if (!dup) VEC_PUSH(listers[at], ti->name);
                        }
                    }
                    VEC_FREE(atoms);
                } else {
                    diag(c, true, x->loc, "unsupported construct in the definition of %s", ti->name);
                }
            }
            if (parents.n && d->addendum) {
                /* TDL addenda may add supertypes; they follow the declared ones */
                for (size_t j = 0; j < parents.n; j++) VEC_PUSH(addparents, ((uint64_t) t << 32) | parents.v[j]);
            } else if (parents.n) {
                if (have_parents) {
                    diag(c, true, d->loc, "supertypes of %s are already declared at %s:%d; "
                         "additions may not add supertypes", ti->name, ploc.file, ploc.line);
                } else {
                    have_parents = true;
                    ploc = d->loc;
                    for (size_t j = 0; j < parents.n; j++) add_parent(c, t, parents.v[j]);
                }
            }
            VEC_FREE(parents);
            VEC_FREE(cj);
        }
    }
    for (uint32_t t = 0; t < nnamed; t++) {
        TypeInfo *ti = &c->types.v[t];
        if (ti->kind == TK_ATOM) {
            if (listers[t].n) {
                qsort(listers[t].v, listers[t].n, sizeof(Sym), cmp_sym);
                for (size_t k = 0; k < listers[t].n; k++) add_parent(c, t, type_lookup(c, listers[t].v[k]));
            } else {
                add_parent(c, t, c->stringroot != TRI_BOTTOM ? c->stringroot : c->atomroot);
            }
        } else if (ti->kind == TK_DEF && !ti->parents.n) {
            add_parent(c, t, enumtype[t] ? c->atomroot : c->top);
        }
        VEC_FREE(listers[t]);
    }
    /* addendum supertypes, in name order so file order can't matter */
    for (size_t i = 1; i < addparents.n; i++)
        for (size_t j = i; j > 0; j--) {
            uint64_t x = addparents.v[j - 1], y = addparents.v[j];
            int cmp = (x >> 32) != (y >> 32) ? ((x >> 32) > (y >> 32) ? 1 : -1)
                    : strcmp(c->types.v[(uint32_t) x].name, c->types.v[(uint32_t) y].name);
            if (cmp <= 0) break;
            addparents.v[j - 1] = y;
            addparents.v[j] = x;
        }
    for (size_t i = 0; i < addparents.n; i++)
        add_parent(c, (uint32_t) (addparents.v[i] >> 32), (uint32_t) addparents.v[i]);
    VEC_FREE(addparents);
    free(listers);
    free(enumtype);
    if (c->nerrors > errors0 || has_cycle(c)) return false;

    /* conjunction types: content may conjoin unrelated types (mixins), so each
     * such conjunction gets a generated common subtype. TDL has no such types:
     * a conjunction there is the meet that completion already provides. */
    compute_codes(c);
    if (!c->tdl) {
        SymSets sets = { 0 };
        for (size_t i = 0; i < c->decls.n; i++)
            conj_sets(c, c->decls.v[i].value, true, &sets);   /* a type's own chain is the type */
        for (size_t i = 0; i < c->insts.n; i++) {     /* an instance's root, across additions */
            SymVec root = { 0 };
            for (size_t k = 0; k < c->insts.v[i].decls.n; k++) {
                XPtrVec cj = { 0 };
                conjuncts(c->insts.v[i].decls.v[k]->value, &cj);
                for (size_t j = 0; j < cj.n; j++)
                    if (cj.v[j]->k == X_NAME) {
                        uint32_t t = type_lookup(c, cj.v[j]->u.name);
                        if (t != TRI_BOTTOM && c->types.v[t].kind == TK_DEF) VEC_PUSH(root, cj.v[j]->u.name);
                    }
                VEC_FREE(cj);
            }
            VEC_PUSH(sets, root);
        }
        for (size_t i = 0; i < sets.n; i++) {
            SymVec *s = &sets.v[i];
            qsort(s->v, s->n, sizeof(Sym), cmp_sym);
            size_t k = 0;
            for (size_t j = 0; j < s->n; j++) if (!k || s->v[k - 1] != s->v[j]) s->v[k++] = s->v[j];
            s->n = k;
            bool incomparable = false;
            for (size_t a = 0; a < s->n; a++)
                for (size_t b = a + 1; b < s->n; b++) {
                    uint32_t ta = type_lookup(c, s->v[a]), tb = type_lookup(c, s->v[b]);
                    if (!is_subtype(c, ta, tb) && !is_subtype(c, tb, ta)) incomparable = true;
                }
            if (incomparable) {
                Buf nb = { 0 };
                for (size_t j = 0; j < s->n; j++) {
                    if (j) buf_puts(&nb, " & ");
                    buf_puts(&nb, s->v[j]);
                }
                Sym name = intern(c, nb.s);
                buf_free(&nb);
                if (type_lookup(c, name) == TRI_BOTTOM) {
                    uint32_t g = type_add(c, name, TK_GLB);
                    for (size_t j = 0; j < s->n; j++) add_parent(c, g, type_lookup(c, s->v[j]));
                }
            }
            VEC_FREE(*s);
        }
        VEC_FREE(sets);
    }

    /* anonymous enums: parents are the minimal common named ancestors of members */
    compute_codes(c);
    for (uint32_t t = 0; t < c->types.n; t++) {
        if (c->types.v[t].kind != TK_ANON) continue;
        TypeInfo *ti = &c->types.v[t];
        U32Vec cands = { 0 };
        for (uint32_t u = 0; u < nnamed; u++) {
            bool all = true;
            for (size_t k = 0; k < ti->members.n && all; k++)
                if (!is_subtype(c, type_lookup(c, ti->members.v[k]), u)) all = false;
            if (all) VEC_PUSH(cands, u);
        }
        SymVec pn = { 0 };
        for (size_t i = 0; i < cands.n; i++) {
            bool minimal = true;
            for (size_t j = 0; j < cands.n && minimal; j++)
                if (i != j && is_subtype(c, cands.v[j], cands.v[i])) minimal = false;
            if (minimal) VEC_PUSH(pn, c->types.v[cands.v[i]].name);
        }
        qsort(pn.v, pn.n, sizeof(Sym), cmp_sym);
        for (size_t i = 0; i < pn.n; i++) add_parent(c, t, type_lookup(c, pn.v[i]));
        for (size_t k = 0; k < ti->members.n; k++) add_parent(c, type_lookup(c, ti->members.v[k]), t);
        VEC_FREE(cands);
        VEC_FREE(pn);
    }

    trace("parents built: types", c->types.n, 0);
    if (!complete(c)) return false;
    trace("completed: types", c->types.n, 0);
    renumber(c);
    compute_codes(c);
    index_codes(c);
    u64map_free(&c->meetmemo);
    c->top = type_lookup(c, intern(c, "_"));
    c->atomroot = type_lookup(c, intern(c, "atom"));
    for (int d = 0; d < NDIMS; d++) c->dimtype[d] = type_lookup(c, intern(c, dim_names[d]));

    trace("renumbered", c->types.n, 0);
    /* features: introduced by the top-level fields of each type's own body */
    SymVec fnames = { 0 };
    VEC(uint64_t) declpairs = { 0 };      /* (type << 32 | label index) */
    U64Map labidx = { 0 };                /* label Sym → index into fnames + 1 */
    for (uint32_t t = 0; t < c->types.n; t++) {
        TypeInfo *ti = &c->types.v[t];
        if (ti->kind != TK_DEF) continue;
        for (size_t k = 0; k < ti->decls.n; k++) {
            XPtrVec cj = { 0 };
            conjuncts(ti->decls.v[k]->value, &cj);
            for (size_t j = 0; j < cj.n; j++) {
                X *x = cj.v[j];
                if (x->k != X_STRUCT) continue;
                for (int a = 0; a < x->u.st.nattrs; a++) {
                    if (strcmp(x->u.st.attrs[a].name, "component") == 0) {
                        char *nm = trim_dup(x->u.st.attrs[a].args);
                        Sym s = intern(c, nm);
                        free(nm);
                        if (ti->component && ti->component != s)
                            diag(c, true, x->loc, "%s is already component %s", ti->name, ti->component);
                        ti->component = s;
                    }
                }
                for (int f = 0; f < x->u.st.n; f++) {
                    Sym lab = x->u.st.fields[f].label;
                    uint64_t li;
                    if (!u64map_get(&labidx, (uint64_t) (uintptr_t) lab, &li)) {
                        VEC_PUSH(fnames, lab);
                        li = fnames.n;
                        u64map_put(&labidx, (uint64_t) (uintptr_t) lab, li);
                    }
                    VEC_PUSH(declpairs, ((uint64_t) t << 32) | (li - 1));
                }
            }
            VEC_FREE(cj);
        }
    }
    SymVec unsorted = { 0 };
    for (size_t i = 0; i < fnames.n; i++) VEC_PUSH(unsorted, fnames.v[i]);
    qsort(fnames.v, fnames.n, sizeof(Sym), cmp_sym);
    for (size_t i = 0; i < fnames.n; i++) {
        FeatInfo fi = { fnames.v[i], TRI_BOTTOM };
        VEC_PUSH(c->feats, fi);
        u64map_put(&c->featidx, (uint64_t) (uintptr_t) fnames.v[i], i + 1);
    }
    U32Vec *declarers = calloc(c->feats.n ? c->feats.n : 1, sizeof(U32Vec));
    for (size_t i = 0; i < declpairs.n; i++) {
        uint32_t t = (uint32_t) (declpairs.v[i] >> 32);
        uint32_t f = feat_lookup(c, unsorted.v[(uint32_t) declpairs.v[i]]);
        U32Vec *dv = &declarers[f];
        bool dup = false;
        for (size_t q = 0; q < dv->n && !dup; q++) dup = dv->v[q] == t;
        if (!dup) VEC_PUSH(*dv, t);
    }
    VEC_FREE(declpairs);
    VEC_FREE(unsorted);
    u64map_free(&labidx);
    for (uint32_t f = 0; f < c->feats.n; f++) {
        U32Vec decl = declarers[f];
        U32Vec minimal = { 0 };
        for (size_t i = 0; i < decl.n; i++) {
            bool m = true;
            for (size_t j = 0; j < decl.n && m; j++)
                if (i != j && is_subtype(c, decl.v[i], decl.v[j])) m = false;
            if (m) VEC_PUSH(minimal, decl.v[i]);
        }
        if (minimal.n == 1) {
            c->feats.v[f].intro = minimal.v[0];
        } else {
            Buf b = { 0 };
            for (size_t i = 0; i < minimal.n; i++) {
                if (i) buf_puts(&b, " and ");
                buf_puts(&b, c->types.v[minimal.v[i]].name);
            }
            diag(c, true, c->types.v[minimal.v[0]].decls.v[0]->loc,
                 "feature '%s' is introduced by both %s; declare it once on a common supertype "
                 "and inherit it", c->feats.v[f].name, b.s);
            buf_free(&b);
        }
        VEC_FREE(decl);
        VEC_FREE(minimal);
    }
    free(declarers);
    VEC_FREE(fnames);
    if (c->nerrors > errors0) return false;

    for (uint32_t t = 0; t < c->types.n; t++)
        for (uint32_t f = 0; f < c->feats.n; f++)
            if (is_subtype(c, t, c->feats.v[f].intro)) VEC_PUSH(c->types.v[t].feats, f);

    /* field attributes on each type's own fields */
    for (uint32_t t = 0; t < c->types.n; t++) {
        TypeInfo *ti = &c->types.v[t];
        if (ti->kind != TK_DEF) continue;
        for (size_t k = 0; k < ti->decls.n; k++) {
            XPtrVec cj = { 0 };
            conjuncts(ti->decls.v[k]->value, &cj);
            for (size_t j = 0; j < cj.n; j++) {
                X *x = cj.v[j];
                if (x->k != X_STRUCT) continue;
                for (int f = 0; f < x->u.st.n; f++) {
                    XField *fl = &x->u.st.fields[f];
                    for (int a = 0; a < fl->nattrs; a++) {
                        if (strcmp(fl->attrs[a].name, "field") != 0) continue;
                        VEC_PUSH(ti->field_feats, feat_lookup(c, fl->label));
                        VEC_PUSH(ti->field_attrs, &fl->attrs[a]);
                    }
                }
            }
            VEC_FREE(cj);
        }
    }

    c->tlist = type_lookup(c, intern(c, c->tdl ? "#*list*" : "#List"));
    c->tcons = type_lookup(c, intern(c, c->tdl ? "#*cons*" : "#Cons"));
    c->tnull = type_lookup(c, intern(c, c->tdl ? "#*null*" : "#Null"));
    c->ffirst = feat_lookup(c, intern(c, "first"));
    c->frest = feat_lookup(c, intern(c, "rest"));
    return c->nerrors == errors0;
}
