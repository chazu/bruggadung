#include "internal.h"

#include <time.h>

/* Loading: building feature structures from the syntax tree, type expansions,
 * instance patterns and specs (defaults, variation), construction from seeds,
 * runtime values, matching, generalisation, and the public loading API. */

static Loc noloc;

static const char *prelude =
    "#List: {}\n"
    "#Cons: #List & { first: _, rest: #List }\n"
    "#Null: #List\n";

/* --- building ------------------------------------------------------------------------- */

typedef struct { Sym name; TriNode *node; } TagEnt;

typedef struct {
    Content *c;
    VEC(TagEnt) tags;
    U32Vec path;
    DefVec defs;
    uint32_t contributor;
    bool record;
    bool ok;
    bool direct;     /* the next type name may use its expansion without copying */
    Loc errloc;
} Build;

static void build_free(Build *b)
{
    VEC_FREE(b->tags);
    VEC_FREE(b->path);
    VEC_FREE(b->defs);
}

static void reset_failure(Content *c)
{
    c->failed = false;
    c->depth = 0;
}

static void build_error(Build *b, Loc loc, const char *fmt, const char *arg)
{
    if (b->ok) {
        char msg[256];
        snprintf(msg, sizeof msg, fmt, arg);
        diag(b->c, true, loc, "%s", msg);
    }
    b->ok = false;
}

static bool unify_at(Build *b, TriNode *x, TriNode *y, Loc loc, const char *what)
{
    Content *c = b->c;
    memcpy(c->pathstack, b->path.v, b->path.n * sizeof(uint32_t));
    c->depth = (int) b->path.n;
    c->failed = false;
    if (unify1(c, x, y)) return true;
    if (b->ok)
        diag(c, true, loc, "%s: conflict at %s: %s vs %s", what, c->fail.path, c->fail.left,
             c->fail.right[0] ? c->fail.right : "(missing)");
    b->ok = false;
    return false;
}

static void record_default(Build *b, X *value)
{
    if (!b->record) return;
    DefaultRec d = { { 0 }, value, b->contributor };
    for (size_t i = 0; i < b->path.n; i++) VEC_PUSH(d.path, b->path.v[i]);
    VEC_PUSH(b->defs, d);
}

static TriNode *build_raw(Build *b, X *x);

static TriNode *build_struct_into(Build *b, TriNode *r, X *x)
{
    Content *c = b->c;
    for (int i = 0; i < x->u.st.n && b->ok; i++) {
        XField *f = &x->u.st.fields[i];
        uint32_t fid = feat_lookup(c, f->label);
        if (fid == TRI_BOTTOM) { build_error(b, f->loc, "unknown feature '%s'", f->label); break; }
        VEC_PUSH(b->path, fid);
        TriNode *child = build_raw(b, f->value);
        b->path.n--;
        if (!child) break;
        TriNode *rd = deref(c, r);
        TriNode *existing = carc_find(c, rd, fid);
        if (existing) {
            VEC_PUSH(b->path, fid);
            unify_at(b, existing, child, f->loc, "field");
            b->path.n--;
        } else {
            /* attach as a temporary arc; copy_out sorts and checks closedness */
            carc_add(c, rd, fid, child);
        }
    }
    return r;
}

static void flatten_or(X *x, XPtrVec *out)
{
    if (x->k == X_OR) { flatten_or(x->u.bin.a, out); flatten_or(x->u.bin.b, out); }
    else VEC_PUSH(*out, x);
}

static bool numeric_interval(Build *b, X *x, int *dim, int64_t *lo, int64_t *hi)
{
    if (x->k == X_NUM) { *dim = x->u.num.dim; *lo = *hi = x->u.num.q; return true; }
    if (x->k == X_BOUND) {
        *dim = x->u.bound.dim;
        int64_t q = x->u.bound.q;
        *lo = TRI_NINF; *hi = TRI_INF;
        switch (x->u.bound.op) {
        case B_GE: *lo = q; break;
        case B_GT: *lo = q + 1; break;
        case B_LE: *hi = q; break;
        case B_LT: *hi = q - 1; break;
        }
        return true;
    }
    if (x->k == X_AND) {
        int d1, d2;
        int64_t l1, h1, l2, h2;
        if (!numeric_interval(b, x->u.bin.a, &d1, &l1, &h1) ||
            !numeric_interval(b, x->u.bin.b, &d2, &l2, &h2) || d1 != d2) return false;
        *dim = d1;
        *lo = l1 > l2 ? l1 : l2;
        *hi = h1 < h2 ? h1 : h2;
        return true;
    }
    return false;
}

static TriNode *build_raw(Build *b, X *x)
{
    Content *c = b->c;
    if (!b->ok) return NULL;
    switch (x->k) {
    case X_TOP:
        return node_new(c, c->scratch, c->top);
    case X_NAME: {
        uint32_t t = type_lookup(c, x->u.name);
        if (t != TRI_BOTTOM && c->types.v[t].kind != TK_ATOM) {
            TriNode *e = type_expansion(c, t);
            if (!e) { build_error(b, x->loc, "cannot expand %s", x->u.name); return NULL; }
            /* The first type name of a top-level definition may be used as is:
             * it occurs once in the operation, so unification only touches its
             * scratch, and copy_out can share its unchanged parts. Only in a
             * top-level operation: a nested one (a lazy expansion inside a
             * unification) could overwrite the scratch of shared nodes that
             * the outer operation is using. */
            if (b->direct && c->opdepth == 1) { b->direct = false; return e; }
            return copy_raw(c, c->scratch, e);
        }
        uint64_t v;
        if (u64map_get(&c->instidx, (uint64_t) (uintptr_t) x->u.name, &v)) {
            if (!inst_pattern(c, (uint32_t) v - 1)) {
                build_error(b, x->loc, "instance %s could not be resolved", x->u.name);
                return NULL;
            }
            return copy_raw(c, c->scratch, c->insts.v[v - 1].pattern);
        }
        build_error(b, x->loc, "unknown name %s", x->u.name);
        return NULL;
    }
    case X_ATOM: {
        uint32_t t = type_lookup(c, x->u.name);
        if (t == TRI_BOTTOM) { build_error(b, x->loc, "unknown atom %s", x->u.name); return NULL; }
        return node_new(c, c->scratch, t);
    }
    case X_NUM:
        return leaf_new(c, c->scratch, c->dimtype[x->u.num.dim], x->u.num.q, x->u.num.q);
    case X_BOUND: {
        int dim;
        int64_t lo, hi;
        numeric_interval(b, x, &dim, &lo, &hi);
        return leaf_new(c, c->scratch, c->dimtype[dim], lo, hi);
    }
    case X_TAG: {
        for (size_t i = 0; i < b->tags.n; i++)
            if (b->tags.v[i].name == x->u.name) return b->tags.v[i].node;
        TagEnt te = { x->u.name, node_new(c, c->scratch, c->top) };
        VEC_PUSH(b->tags, te);
        return te.node;
    }
    case X_STRUCT: {
        uint32_t t = c->top;
        for (int i = 0; i < x->u.st.n; i++) {
            uint32_t f = feat_lookup(c, x->u.st.fields[i].label);
            if (f == TRI_BOTTOM) { build_error(b, x->u.st.fields[i].loc, "unknown feature '%s'", x->u.st.fields[i].label); return NULL; }
            uint32_t m = meet(c, t, c->feats.v[f].intro);
            if (m == TRI_BOTTOM) {
                build_error(b, x->u.st.fields[i].loc, "no type has all of these features (at '%s')", x->u.st.fields[i].label);
                return NULL;
            }
            t = m;
        }
        TriNode *r = node_new(c, c->scratch, t);
        build_struct_into(b, r, x);
        if (!b->ok) return NULL;
        if (t != c->top) {
            TriNode *e = type_expansion(c, t);
            if (!e) { build_error(b, x->loc, "cannot expand %s", c->types.v[t].name); return NULL; }
            unify_at(b, r, copy_raw(c, c->scratch, e), x->loc, "struct");
        }
        return b->ok ? r : NULL;
    }
    case X_AND: {
        TriNode *l = build_raw(b, x->u.bin.a);
        TriNode *r = l ? build_raw(b, x->u.bin.b) : NULL;
        if (!r) return NULL;
        unify_at(b, l, r, x->loc, "conjunction");
        return b->ok ? l : NULL;
    }
    case X_DEFAULT:
        record_default(b, x->u.sub);
        return node_new(c, c->scratch, c->top);
    case X_OR: {
        XPtrVec ds = { 0 };
        flatten_or(x, &ds);
        X *def = NULL;
        bool all_atoms = true, all_num = true;
        int dim = -1;
        int64_t lo = TRI_INF, hi = TRI_NINF;
        for (size_t i = 0; i < ds.n; i++) {
            X *d = ds.v[i];
            if (d->k == X_DEFAULT) {
                if (def) { build_error(b, d->loc, "%s", "more than one default in a disjunction"); VEC_FREE(ds); return NULL; }
                def = d->u.sub;
                d = d->u.sub;
            }
            if (d->k != X_ATOM) all_atoms = false;
            int dd;
            int64_t l, h;
            if (numeric_interval(b, d, &dd, &l, &h) && (dim < 0 || dim == dd)) {
                dim = dd;
                if (l < lo) lo = l;
                if (h > hi) hi = h;
            } else {
                all_num = false;
            }
        }
        VEC_FREE(ds);
        if (def) record_default(b, def);
        if (all_atoms) {
            Sym an = anon_name(c, x);
            if (!an) {                           /* every disjunct is the same atom */
                X *d = x;
                while (d->k == X_OR) d = d->u.bin.a;
                if (d->k == X_DEFAULT) d = d->u.sub;
                return build_raw(b, d);
            }
            uint32_t t = type_lookup(c, an);
            if (t == TRI_BOTTOM) { build_error(b, x->loc, "unknown enum %s", an); return NULL; }
            return node_new(c, c->scratch, t);
        }
        if (all_num) return leaf_new(c, c->scratch, c->dimtype[dim], lo, hi);
        build_error(b, x->loc, "%s", "disjunction of structures is not supported yet");
        return NULL;
    }
    case X_LIST: {
        if (c->tcons == TRI_BOTTOM) { build_error(b, x->loc, "%s", "list types are missing"); return NULL; }
        size_t base = b->path.n;
        TriNode *tail;
        if (x->u.list.tail) {                    /* TDL: < a . #rest > */
            for (int k = 0; k < x->u.list.n; k++) VEC_PUSH(b->path, c->frest);
            tail = build_raw(b, x->u.list.tail);
            b->path.n = base;
            if (!tail) return NULL;
        } else {
            tail = copy_raw(c, c->scratch, type_expansion(c, x->u.list.open ? c->tlist : c->tnull));
        }
        /* Build from the end, tracking paths for defaults inside items. */
        TriNode **cells = malloc(sizeof(TriNode *) * (size_t) (x->u.list.n ? x->u.list.n : 1));
        for (int i = 0; i < x->u.list.n && b->ok; i++) {
            for (int k = 0; k < i; k++) VEC_PUSH(b->path, c->frest);
            VEC_PUSH(b->path, c->ffirst);
            TriNode *item = build_raw(b, x->u.list.items[i]);
            b->path.n = base;
            TriNode *cell = copy_raw(c, c->scratch, type_expansion(c, c->tcons));
            cells[i] = cell;
            if (item) {
                for (int k = 0; k < i; k++) VEC_PUSH(b->path, c->frest);
                VEC_PUSH(b->path, c->ffirst);
                unify_at(b, node_arc(cell, c->ffirst), item, x->loc, "list item");
                b->path.n = base;
            }
        }
        TriNode *next = tail;
        for (int i = x->u.list.n - 1; i >= 0 && b->ok; i--) {
            unify_at(b, node_arc(cells[i], c->frest), next, x->loc, "list");
            next = cells[i];
        }
        free(cells);
        return b->ok ? next : NULL;
    }
    }
    return NULL;
}

/* --- type expansions ------------------------------------------------------------------------ */

static void conjuncts(X *x, XPtrVec *out)
{
    if (x->k == X_AND) { conjuncts(x->u.bin.a, out); conjuncts(x->u.bin.b, out); }
    else VEC_PUSH(*out, x);
}

static bool path_eq(const U32Vec *a, const U32Vec *b)
{
    return a->n == b->n && (a->n == 0 || memcmp(a->v, b->v, a->n * sizeof(uint32_t)) == 0);
}

static void add_default(DefVec *defs, const DefaultRec *d, const uint32_t *prefix, size_t plen)
{
    DefaultRec n = { { 0 }, d->value, d->contributor };
    for (size_t i = 0; i < plen; i++) VEC_PUSH(n.path, prefix[i]);
    for (size_t i = 0; i < d->path.n; i++) VEC_PUSH(n.path, d->path.v[i]);
    for (size_t i = 0; i < defs->n; i++)
        if (defs->v[i].value == n.value && defs->v[i].contributor == n.contributor && path_eq(&defs->v[i].path, &n.path)) {
            VEC_FREE(n.path);
            return;
        }
    VEC_PUSH(*defs, n);
}

TriNode *type_expansion(Content *c, uint32_t t)
{
    TypeInfo *ti = &c->types.v[t];
    if (ti->xstate == 2) return ti->expansion;
    if (ti->xstate == 1) {
        diag(c, true, ti->decls.n ? ti->decls.v[0]->loc : noloc,
             "recursive type constraint involving %s", ti->name);
        return NULL;
    }
    if (ti->kind == TK_TOP || ti->kind == TK_DIM || ti->kind == TK_ATOMROOT ||
        ti->kind == TK_ATOM || ti->kind == TK_ANON) {
        ti->expansion = node_new(c, c->spec, t);
        ti->xstate = 2;
        return ti->expansion;
    }
    ti->xstate = 1;

    /* Save the failure state of any operation in progress. */
    uint32_t savedpath[128];
    int saveddepth = c->depth;
    bool savedfailed = c->failed;
    TriFailure savedfail = c->fail;
    memcpy(savedpath, c->pathstack, sizeof savedpath);
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);

    Build b = { 0 };
    b.c = c;
    b.contributor = t;
    b.record = true;
    b.ok = true;
    TriNode *r = node_new(c, c->scratch, t);
    for (size_t k = 0; k < ti->decls.n && b.ok; k++) {
        XPtrVec cj = { 0 };
        conjuncts(ti->decls.v[k]->value, &cj);
        for (size_t j = 0; j < cj.n && b.ok; j++)
            if (cj.v[j]->k == X_STRUCT) build_struct_into(&b, r, cj.v[j]);
        VEC_FREE(cj);
    }
    Loc loc = ti->decls.n ? ti->decls.v[0]->loc : noloc;
    for (size_t k = 0; k < ti->parents.n && b.ok; k++) {
        uint32_t p = ti->parents.v[k];
        TriNode *e = type_expansion(c, p);
        if (!e) { b.ok = false; break; }
        Buf what = { 0 };
        buf_printf(&what, "%s inheriting from %s", ti->name, c->types.v[p].name);
        /* the first parent's expansion is used as is, so the result shares it */
        unify_at(&b, r, k == 0 && c->opdepth == 1 ? e : copy_raw(c, c->scratch, e), loc, what.s);
        buf_free(&what);
    }
    TriNode *out = NULL;
    if (b.ok) {
        bool closed;
        out = copy_out(c, c->spec, r, &closed);
        if (!closed) {
            diag(c, true, loc, "%s: a field is not appropriate for its type", ti->name);
            out = NULL;
        }
    }
    if (out) {
        for (size_t i = 0; i < b.defs.n; i++) add_default(&ti->defaults, &b.defs.v[i], NULL, 0);
        for (size_t k = 0; k < ti->parents.n; k++) {
            TypeInfo *pi = &c->types.v[ti->parents.v[k]];
            for (size_t i = 0; i < pi->defaults.n; i++) add_default(&ti->defaults, &pi->defaults.v[i], NULL, 0);
        }
    }
    for (size_t i = 0; i < b.defs.n; i++) VEC_FREE(b.defs.v[i].path);
    build_free(&b);

    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    memcpy(c->pathstack, savedpath, sizeof savedpath);
    c->depth = saveddepth;
    c->failed = savedfailed;
    c->fail = savedfail;

    ti = &c->types.v[t];
    ti->expansion = out;
    ti->xstate = out ? 2 : 0;
    if (!out) ti->xstate = 2;    /* do not retry; errors are already reported */
    return out;
}

/* --- instances ------------------------------------------------------------------------------- */

static void find_tag_paths(Content *c, TriNode *root, TriNode *target, U32Vec *cur, U32Vec *out, U64Map *seen)
{
    if (out->n || !root) return;
    if (root == target) {
        for (size_t i = 0; i < cur->n; i++) VEC_PUSH(*out, cur->v[i]);
        if (!out->n) VEC_PUSH(*out, TRI_BOTTOM);  /* root itself; marked */
        return;
    }
    uint64_t k = (uint64_t) (uintptr_t) root;
    if (u64map_get(seen, k, NULL)) return;
    u64map_put(seen, k, 1);
    for (uint32_t i = 0; i < root->narcs && !out->n; i++) {
        VEC_PUSH(*cur, root->arcs[i].feat);
        find_tag_paths(c, root->arcs[i].val, target, cur, out, seen);
        cur->n--;
    }
}

/* Builds one declaration of an instance by itself, for locating conflicts. */
static bool decl_pair_conflicts(Content *c, Decl *d1, Decl *d2)
{
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    Build b = { 0 };
    b.c = c; b.ok = true; b.contributor = CONTRIB_INSTANCE;
    int nerr = c->nerrors;
    size_t ndiag = c->diags.n;
    TriNode *x = build_raw(&b, d1->value);
    TriNode *y = x ? build_raw(&b, d2->value) : NULL;
    bool conflict = false;
    if (x && y) {
        reset_failure(c);
        conflict = !unify1(c, x, y);
    }
    while (c->diags.n > ndiag) free(c->diags.v[--c->diags.n].msg);
    c->nerrors = nerr;
    build_free(&b);
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    return conflict;
}

bool inst_pattern(Content *c, uint32_t i)
{
    InstInfo *in = &c->insts.v[i];
    if (in->pstate == 2) return true;
    if (in->pstate == 3) return false;
    if (in->pstate == 1) {
        diag(c, true, in->decls.v[0]->loc, "instance %s refers to itself", in->name);
        return false;
    }
    in->pstate = 1;
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    Build b = { 0 };
    b.c = c; b.ok = true; b.contributor = CONTRIB_INSTANCE; b.record = true;
    b.direct = true;
    TriNode *r = NULL;
    for (size_t k = 0; k < in->decls.n && b.ok; k++) {
        Decl *d = c->insts.v[i].decls.v[k];
        TriNode *x = build_raw(&b, d->value);
        if (!x) break;
        if (!r) { r = x; continue; }
        reset_failure(c);
        if (!unify1(c, r, x)) {
            Decl *partner = NULL;
            for (size_t j = 0; j < k && !partner; j++)
                if (decl_pair_conflicts(c, c->insts.v[i].decls.v[j], d)) partner = c->insts.v[i].decls.v[j];
            if (partner)
                diag(c, true, d->loc, "%s: conflict at %s: %s vs %s, with the declaration at %s:%d",
                     c->insts.v[i].name, c->fail.path, c->fail.left, c->fail.right,
                     partner->loc.file, partner->loc.line);
            else
                diag(c, true, d->loc, "%s: conflict at %s: %s vs %s, with earlier declarations",
                     c->insts.v[i].name, c->fail.path, c->fail.left, c->fail.right);
            b.ok = false;
        }
    }
    in = &c->insts.v[i];
    if (b.ok && r) {
        bool closed;
        TriNode *out = copy_out(c, c->spec, r, &closed);
        if (!closed) {
            diag(c, true, in->decls.v[0]->loc, "%s: a field is not appropriate for its type", in->name);
            b.ok = false;
        } else {
            in->pattern = out;
            for (size_t t = 0; t < b.tags.n; t++) {
                TriNode *tn = deref(c, b.tags.v[t].node);
                TriNode *mapped = tn->cpy;   /* valid: copy_out just ran */
                TagPath tp = { b.tags.v[t].name, { 0 } };
                U32Vec cur = { 0 };
                U64Map seen = { 0 };
                find_tag_paths(c, out, mapped, &cur, &tp.path, &seen);
                if (tp.path.n == 1 && tp.path.v[0] == TRI_BOTTOM) tp.path.n = 0;
                VEC_FREE(cur);
                u64map_free(&seen);
                VEC_PUSH(in->tags, tp);
            }
            for (size_t d = 0; d < b.defs.n; d++) add_default(&in->defaults, &b.defs.v[d], NULL, 0);
        }
    }
    for (size_t d = 0; d < b.defs.n; d++) VEC_FREE(b.defs.v[d].path);
    build_free(&b);
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    in->pstate = b.ok && in->pattern ? 2 : 3;
    return in->pstate == 2;
}

/* --- specs: defaults and variation ---------------------------------------------------------- */

static int cmp_path(const U32Vec *a, const U32Vec *b)
{
    size_t n = a->n < b->n ? a->n : b->n;
    for (size_t i = 0; i < n; i++)
        if (a->v[i] != b->v[i]) return a->v[i] < b->v[i] ? -1 : 1;
    return a->n < b->n ? -1 : a->n > b->n;
}

static void collect_defaults(Content *c, TriNode *n, U32Vec *path, DefVec *out, U64Map *seen)
{
    uint64_t k = (uint64_t) (uintptr_t) n;
    if (u64map_get(seen, k, NULL)) return;
    u64map_put(seen, k, 1);
    TypeInfo *ti = &c->types.v[n->type];
    for (size_t i = 0; i < ti->defaults.n; i++) add_default(out, &ti->defaults.v[i], path->v, path->n);
    for (uint32_t i = 0; i < n->narcs; i++) {
        VEC_PUSH(*path, n->arcs[i].feat);
        collect_defaults(c, n->arcs[i].val, path, out, seen);
        path->n--;
    }
}

/* A chain of top-typed wrapper nodes leading to `value` along `path`. */
static TriNode *wrap_path(Content *c, const U32Vec *path, TriNode *value)
{
    TriNode *n = value;
    for (size_t i = path->n; i-- > 0;) {
        TriNode *w = node_new(c, c->scratch, c->top);
        w->arcs = arena_alloc(c->scratch, sizeof(Arc));
        w->arcs[0].feat = path->v[i];
        w->arcs[0].val = n;
        w->narcs = 1;
        n = w;
    }
    return n;
}

/* Unifies `root` with each default value at its path; returns the new root in
 * the load arena, or NULL if they do not all fit. */
static TriNode *try_defaults(Content *c, TriNode *root, DefaultRec **ds, size_t n)
{
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    Build b = { 0 };
    b.c = c; b.ok = true;
    int nerr = c->nerrors;
    size_t ndiag = c->diags.n;
    TriNode *r = NULL;
    bool ok = true;
    for (size_t i = 0; i < n && ok; i++) {
        TriNode *v = build_raw(&b, ds[i]->value);
        if (!v) { ok = false; break; }
        reset_failure(c);
        ok = unify1(c, root, wrap_path(c, &ds[i]->path, v));
    }
    if (ok) {
        bool closed;
        r = copy_out(c, c->load, root, &closed);
        if (!closed) r = NULL;
    }
    while (c->diags.n > ndiag) free(c->diags.v[--c->diags.n].msg);
    c->nerrors = nerr;
    build_free(&b);
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    return r;
}

static const char *contributor_name(Content *c, uint32_t contrib)
{
    return contrib == CONTRIB_INSTANCE ? "the instance" : c->types.v[contrib].name;
}

/* d1 strictly more specific than d2 */
static bool more_specific(Content *c, uint32_t a, uint32_t b)
{
    if (a == b) return false;
    if (a == CONTRIB_INSTANCE) return true;
    if (b == CONTRIB_INSTANCE) return false;
    return is_subtype(c, a, b);
}

static void note(InstInfo *in, Buf *b)
{
    VEC_PUSH(in->notes, b->s);
    b->s = NULL;
    b->len = b->cap = 0;
}

static void collect_variation(Content *c, TriNode *n, U32Vec *path, InstInfo *in, U64Map *seen, bool *ok)
{
    uint64_t k = (uint64_t) (uintptr_t) n;
    if (u64map_get(seen, k, NULL)) return;
    u64map_put(seen, k, 1);
    TypeInfo *ti = &c->types.v[n->type];
    bool vary = false;
    if (ti->kind == TK_DIM) {
        if (n->lo != n->hi) {
            if (n->lo == TRI_NINF || n->hi == TRI_INF) {
                Buf p = { 0 };
                path_format(c, &p, path->v, path->n);
                diag(c, true, in->decls.v[0]->loc, "%s: %s is not concrete and has no bounds to vary within",
                     in->name, p.s);
                buf_free(&p);
                *ok = false;
            } else {
                vary = true;
            }
        }
    } else if (is_subtype(c, n->type, c->atomroot) && ti->children.n > 0) {
        vary = true;
    }
    if (vary) {
        U32Vec copy = { 0 };
        for (size_t i = 0; i < path->n; i++) VEC_PUSH(copy, path->v[i]);
        VEC_PUSH(in->varpaths, copy);
        Buf p = { 0 };
        path_format(c, &p, path->v, path->n);
        VEC_PUSH(in->variation, p.s);
    }
    for (uint32_t i = 0; i < n->narcs; i++) {
        VEC_PUSH(*path, n->arcs[i].feat);
        collect_variation(c, n->arcs[i].val, path, in, seen, ok);
        path->n--;
    }
}

static int cmp_defptr(const void *a, const void *b)
{
    const DefaultRec *x = *(DefaultRec *const *) a, *y = *(DefaultRec *const *) b;
    return cmp_path(&x->path, &y->path);
}

static bool inst_spec(Content *c, uint32_t i)
{
    InstInfo *in = &c->insts.v[i];
    if (in->sstate) return in->sstate == 2;
    in->sstate = 3;
    if (!inst_pattern(c, i)) return false;
    in = &c->insts.v[i];
    TriNode *root = in->pattern;

    DefVec all = { 0 };
    U32Vec path = { 0 };
    U64Map seen = { 0 };
    collect_defaults(c, root, &path, &all, &seen);
    u64map_free(&seen);
    for (size_t k = 0; k < in->defaults.n; k++) add_default(&all, &in->defaults.v[k], NULL, 0);

    DefaultRec **order = malloc(sizeof(DefaultRec *) * (all.n ? all.n : 1));
    for (size_t k = 0; k < all.n; k++) order[k] = &all.v[k];
    qsort(order, all.n, sizeof(DefaultRec *), cmp_defptr);   /* stable enough: groups by path */

    Buf nb = { 0 };
    size_t g0 = 0;
    while (g0 < all.n) {
        size_t g1 = g0;
        while (g1 < all.n && path_eq(&order[g1]->path, &order[g0]->path)) g1++;
        size_t gn = g1 - g0;
        bool *done = calloc(gn, 1);
        DefaultRec **ready = malloc(sizeof(DefaultRec *) * gn);
        size_t left = gn;
        Buf pth = { 0 };
        path_format(c, &pth, order[g0]->path.v, order[g0]->path.n);
        while (left) {
            size_t nr = 0;
            for (size_t a = 0; a < gn; a++) {
                if (done[a]) continue;
                bool isready = true;
                for (size_t bb = 0; bb < gn && isready; bb++)
                    if (!done[bb] && more_specific(c, order[g0 + bb]->contributor, order[g0 + a]->contributor))
                        isready = false;
                if (isready) ready[nr++] = order[g0 + a];
            }
            for (size_t a = 0; a < gn; a++)
                for (size_t q = 0; q < nr; q++)
                    if (order[g0 + a] == ready[q]) { done[a] = true; left--; }
            TriNode *res = try_defaults(c, root, ready, nr);
            if (res) {
                root = res;
                for (size_t q = 0; q < nr; q++) {
                    buf_printf(&nb, "%s <- %s (default)", pth.s, contributor_name(c, ready[q]->contributor));
                    note(in, &nb);
                }
                continue;
            }
            DefaultRec **compat = malloc(sizeof(DefaultRec *) * nr);
            size_t nc = 0;
            for (size_t q = 0; q < nr; q++) {
                if (try_defaults(c, root, &ready[q], 1)) compat[nc++] = ready[q];
                else {
                    buf_printf(&nb, "%s: default from %s loses to a more specific value",
                               pth.s, contributor_name(c, ready[q]->contributor));
                    note(in, &nb);
                }
            }
            if (nc == 1) {
                root = try_defaults(c, root, compat, 1);
                buf_printf(&nb, "%s <- %s (default)", pth.s, contributor_name(c, compat[0]->contributor));
                note(in, &nb);
            } else if (nc > 1) {
                Buf names = { 0 };
                for (size_t q = 0; q < nc; q++) {
                    if (q) buf_puts(&names, ", ");
                    buf_puts(&names, contributor_name(c, compat[q]->contributor));
                }
                diag(c, false, in->decls.v[0]->loc, "%s: conflicting defaults for %s from %s; both dropped",
                     in->name, pth.s, names.s);
                buf_printf(&nb, "%s: conflicting defaults from %s dropped", pth.s, names.s);
                note(in, &nb);
                buf_free(&names);
            }
            free(compat);
        }
        buf_free(&pth);
        free(done);
        free(ready);
        g0 = g1;
    }
    free(order);
    for (size_t k = 0; k < all.n; k++) VEC_FREE(all.v[k].path);
    VEC_FREE(all);

    bool ok = true;
    path.n = 0;
    U64Map vseen = { 0 };
    collect_variation(c, root, &path, in, &vseen, &ok);
    u64map_free(&vseen);
    VEC_FREE(path);
    for (size_t k = 0; k < in->variation.n; k++) {
        buf_printf(&nb, "%s <- seed", in->variation.v[k]);
        note(in, &nb);
    }
    buf_free(&nb);
    if (!ok) return false;

    /* freeze into the spec arena */
    TriMark fm = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    in->spec = copy_out(c, c->spec, root, NULL);
    op_end(c, saved);
    tri_arena_release(c->scratch, fm);
    in->sstate = 2;
    return true;
}

/* --- construction --------------------------------------------------------------------------- */

static uint64_t splitmix(uint64_t *s)
{
    uint64_t z = (*s += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

static uint64_t draw(uint64_t *s, uint64_t n)
{
    /* unbiased: reject the top partial range */
    uint64_t limit = UINT64_MAX - UINT64_MAX % n;
    uint64_t r;
    do r = splitmix(s); while (r >= limit);
    return r % n;
}

static uint32_t inst_index(Content *c, const char *name)
{
    uint64_t v;
    if (u64map_get(&c->instidx, (uint64_t) (uintptr_t) intern(c, name), &v)) return (uint32_t) v - 1;
    return TRI_BOTTOM;
}

const TriNode *tri_construct(TriContent *c, const char *instance, uint64_t seed, TriArena *out)
{
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_spec(c, i)) return NULL;
    InstInfo *in = &c->insts.v[i];
    uint64_t state = seed;
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    reset_failure(c);
    bool ok = true;
    for (size_t k = 0; k < in->varpaths.n && ok; k++) {
        U32Vec *p = &in->varpaths.v[k];
        TriNode *n = node_at(in->spec, p->v, p->n);
        TriNode *v;
        if (is_dim(c, n->type)) {
            uint64_t span = (uint64_t) (n->hi - n->lo) + 1;
            int64_t q = n->lo + (int64_t) draw(&state, span);
            v = leaf_new(c, c->scratch, n->type, q, q);
        } else {
            U32Vec leaves = { 0 };
            for (uint32_t t = 0; t < c->types.n; t++)
                if (is_subtype(c, t, n->type) && c->types.v[t].children.n == 0) VEC_PUSH(leaves, t);
            v = node_new(c, c->scratch, leaves.v[draw(&state, leaves.n)]);
            VEC_FREE(leaves);
        }
        ok = unify1(c, in->spec, wrap_path(c, p, v));
    }
    TriNode *r = ok ? copy_out(c, out, in->spec, NULL) : NULL;
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    return r;
}

/* --- public instance API ---------------------------------------------------------------------- */

const TriNode *tri_pattern(TriContent *c, const char *instance)
{
    uint32_t i = inst_index(c, instance);
    return i != TRI_BOTTOM && inst_pattern(c, i) ? c->insts.v[i].pattern : NULL;
}

const TriNode *tri_spec(TriContent *c, const char *instance)
{
    uint32_t i = inst_index(c, instance);
    return i != TRI_BOTTOM && inst_spec(c, i) ? c->insts.v[i].spec : NULL;
}

size_t tri_spec_variation_count(TriContent *c, const char *instance)
{
    uint32_t i = inst_index(c, instance);
    return i != TRI_BOTTOM && inst_spec(c, i) ? c->insts.v[i].variation.n : 0;
}

const char *tri_spec_variation_path(TriContent *c, const char *instance, size_t k)
{
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_spec(c, i) || k >= c->insts.v[i].variation.n) return NULL;
    return c->insts.v[i].variation.v[k];
}

size_t tri_spec_note_count(TriContent *c, const char *instance)
{
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM) return 0;
    inst_spec(c, i);
    return c->insts.v[i].notes.n;
}

const char *tri_spec_note(TriContent *c, const char *instance, size_t k)
{
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || k >= c->insts.v[i].notes.n) return NULL;
    return c->insts.v[i].notes.v[k];
}

const TriNode *tri_binding(TriContent *c, const char *instance, const char *tag, const TriNode *d)
{
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_pattern(c, i)) return NULL;
    Sym t = intern(c, tag[0] == '$' ? tag : "");
    if (tag[0] != '$') {
        Buf b = { 0 };
        buf_printf(&b, "$%s", tag);
        t = intern(c, b.s);
        buf_free(&b);
    }
    InstInfo *in = &c->insts.v[i];
    for (size_t k = 0; k < in->tags.n; k++)
        if (in->tags.v[k].name == t) return node_at((TriNode *) d, in->tags.v[k].path.v, in->tags.v[k].path.n);
    return NULL;
}

/* --- runtime values ------------------------------------------------------------------------------ */

const TriNode *tri_value(TriContent *c, const char *expr, TriArena *out, char *err, size_t errlen)
{
    size_t ndiag = c->diags.n;
    int nerr = c->nerrors;
    X *x = parse_expr_string(c, intern(c, "<value>"), expr);
    const TriNode *r = NULL;
    if (x) {
        TriMark m = tri_arena_mark(c->scratch);
        uint32_t saved = op_begin(c);
        Build b = { 0 };
        b.c = c; b.ok = true;
        TriNode *n = build_raw(&b, x);
        if (n && b.ok) {
            bool closed;
            r = copy_out(c, out, n, &closed);
            if (!closed) {
                diag(c, true, noloc, "a field is not appropriate for its type");
                r = NULL;
            }
        }
        build_free(&b);
        op_end(c, saved);
        tri_arena_release(c->scratch, m);
    }
    if (err && errlen) err[0] = 0;
    if (c->diags.n > ndiag && err && errlen) snprintf(err, errlen, "%s", c->diags.v[ndiag].msg);
    /* runtime values do not leave diagnostics on the content */
    while (c->diags.n > ndiag) free(c->diags.v[--c->diags.n].msg);
    c->nerrors = nerr;
    return r;
}

/* --- matching ------------------------------------------------------------------------------------ */

static void residuals(Content *c, TriNode *p, TriNode *d, U32Vec *path, TriMatchResult *r)
{
    if (r->nresidual >= TRI_MAX_RESIDUAL) return;
    Scratch *sp = sx_make(c, p);
    if (sp->fwd) {
        if (sp->fwd != d && !ext_equal(c, sp->fwd, d)) goto record;
        if (sp->fwd == d) return;
    } else {
        sp->fwd = d;
    }
    if (p->flags & NF_DIM) {
        if ((d->flags & NF_DIM) && d->lo >= p->lo && d->hi <= p->hi) return;
        goto record;
    }
    if (!is_subtype(c, d->type, p->type)) goto record;
    for (uint32_t i = 0; i < p->narcs; i++) {
        TriNode *dv = node_arc(d, p->arcs[i].feat);
        if (!dv) continue;
        VEC_PUSH(*path, p->arcs[i].feat);
        residuals(c, p->arcs[i].val, dv, path, r);
        path->n--;
    }
    return;
record: {
        Buf b = { 0 };
        path_format(c, &b, path->v, path->n);
        snprintf(r->residual[r->nresidual++], sizeof r->residual[0], "%s", b.s);
        buf_free(&b);
    }
}

TriMatch tri_match(TriContent *c, const TriNode *pattern, const TriNode *description,
                   TriMatchResult *result)
{
    TriMatchResult local;
    TriMatchResult *r = result ? result : &local;
    memset(r, 0, sizeof *r);
    int fwd, bwd;
    tri_subsumes(c, pattern, description, &fwd, &bwd);
    if (fwd) { r->result = TRI_ENTAILED; return r->result; }

    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    reset_failure(c);
    bool compatible = unify1(c, (TriNode *) pattern, (TriNode *) description);
    if (!compatible) r->failure = c->fail;
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    if (!compatible) { r->result = TRI_INCOMPATIBLE; return r->result; }

    m = tri_arena_mark(c->scratch);
    saved = op_begin(c);
    U32Vec path = { 0 };
    residuals(c, (TriNode *) pattern, (TriNode *) description, &path, r);
    VEC_FREE(path);
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    r->result = TRI_UNKNOWN;
    return r->result;
}

TriMasses tri_match_hypotheses(TriContent *c, const TriNode *pattern,
                               const TriNode *const *ds, const uint32_t *cred, size_t n)
{
    TriMasses m = { 0, 0, 0 };
    for (size_t i = 0; i < n; i++) {
        switch (tri_match(c, pattern, ds[i], NULL)) {
        case TRI_ENTAILED: m.entailed += cred[i]; break;
        case TRI_UNKNOWN: m.unknown += cred[i]; break;
        case TRI_INCOMPATIBLE: m.incompatible += cred[i]; break;
        }
    }
    return m;
}

/* --- generalisation ----------------------------------------------------------------------------- */

static TriNode *gen_copy(Content *c, TriArena *a, TriNode *n, TriNode *target, uint32_t newtype, uint32_t cg)
{
    if (n->cpygen == cg) return n->cpy;
    uint32_t t = n == target ? newtype : n->type;
    TriNode *m = node_new(c, a, t);
    if (n->flags & NF_DIM) { m->lo = n->lo; m->hi = n->hi; }
    n->cpy = m;
    n->cpygen = cg;
    uint32_t k = 0;
    if (!(n->flags & NF_DIM)) m->arcs = n->narcs ? arena_alloc(a, n->narcs * sizeof(Arc)) : NULL;
    for (uint32_t i = 0; i < n->narcs; i++) {
        if (!approp(c, t, n->arcs[i].feat)) continue;
        m->arcs[k].feat = n->arcs[i].feat;
        m->arcs[k].val = gen_copy(c, a, n->arcs[i].val, target, newtype, cg);
        k++;
    }
    m->narcs = k;
    return m;
}

const TriNode *tri_generalize(TriContent *c, const TriNode *node, const char *path, int steps,
                              TriArena *out)
{
    U32Vec p = { 0 };
    if (!path_parse(c, path, &p) || !p.n) { VEC_FREE(p); return NULL; }
    TriNode *parent = node_at((TriNode *) node, p.v, p.n - 1);
    TriNode *target = parent ? node_arc(parent, p.v[p.n - 1]) : NULL;
    if (!target) { VEC_FREE(p); return NULL; }
    /* The bound: the value type the parent's type allows at this feature. */
    TriNode *pe = type_expansion(c, parent->type);
    TriNode *bound = pe ? node_arc(pe, p.v[p.n - 1]) : NULL;
    uint32_t limit = bound ? bound->type : c->top;
    uint32_t t = target->type;
    for (int s = 0; s < steps && t != limit && t != c->top; s++) {
        uint32_t pt = c->types.v[t].parents.v[0];
        if (!is_subtype(c, pt, limit)) { t = limit; break; }
        t = pt;
    }
    VEC_FREE(p);
    return gen_copy(c, out, (TriNode *) node, target, t, ++c->cgenctr);
}

/* --- loading API ----------------------------------------------------------------------------------- */

static void compute_hash(Content *c)
{
    uint64_t h = 0xcbf29ce484222325ULL;
    Buf b = { 0 };
    for (uint32_t t = 0; t < c->types.n; t++) {
        TypeInfo *ti = &c->types.v[t];
        buf_printf(&b, "%s<", ti->name);
        for (size_t k = 0; k < ti->parents.n; k++) buf_printf(&b, "%s,", c->types.v[ti->parents.v[k]].name);
        buf_puts(&b, ">");
        if (ti->expansion) fs_print(c, &b, ti->expansion);
        buf_putc(&b, '\n');
    }
    /* instances in name order */
    Sym *names = malloc(sizeof(Sym) * (c->insts.n ? c->insts.n : 1));
    for (size_t i = 0; i < c->insts.n; i++) names[i] = c->insts.v[i].name;
    for (size_t i = 1; i < c->insts.n; i++)
        for (size_t j = i; j > 0 && strcmp(names[j - 1], names[j]) > 0; j--) {
            Sym tmp = names[j]; names[j] = names[j - 1]; names[j - 1] = tmp;
        }
    for (size_t i = 0; i < c->insts.n; i++) {
        uint32_t k = inst_index(c, names[i]);
        buf_printf(&b, "%s=", names[i]);
        if (c->insts.v[k].pattern) fs_print(c, &b, c->insts.v[k].pattern);
        buf_putc(&b, '\n');
    }
    free(names);
    h = fnv1a(h, b.s ? b.s : "", b.len);
    const char *dump = getenv("TRI_DUMP");     /* write the hashed text, for diffing */
    if (dump) {
        FILE *f = fopen(dump, "w");
        if (f) { fwrite(b.s ? b.s : "", 1, b.len, f); fclose(f); }
    }
    buf_free(&b);
    c->hash = h;
}

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

static void finish_load(Content *c, bool ok, double t0)
{
    double t1 = now_ms();
    c->stats.parse_ms = t1 - t0;
    if (ok && types_build(c)) {
        double t2 = now_ms();
        c->stats.hierarchy_ms = t2 - t1;
        for (uint32_t t = 0; t < c->types.n; t++) type_expansion(c, t);
        double t3 = now_ms();
        c->stats.expansion_ms = t3 - t2;
        if (!c->tdl)                             /* TDL instances (lexicons) resolve on demand */
            for (uint32_t i = 0; i < c->insts.n; i++) inst_pattern(c, i);
        c->stats.instances_ms = now_ms() - t3;
        compute_hash(c);
    }
}

TriContent *tri_content_load_tdl(const char *topfile)
{
    Content *c = calloc(1, sizeof(Content));
    c->load = tri_arena_new();
    c->spec = tri_arena_new();
    c->scratch = tri_arena_new();
    c->genctr = 1;
    c->gen = 1;
    c->tdl = true;
    double t0 = now_ms();
    bool ok = tdl_parse_top(c, topfile, L_DEF);
    finish_load(c, ok, t0);
    return c;
}

static TriContent *load_common(const char *const *names, const char *const *sources, size_t n,
                               bool from_files)
{
    double t0 = now_ms();
    Content *c = calloc(1, sizeof(Content));
    c->load = tri_arena_new();
    c->spec = tri_arena_new();
    c->scratch = tri_arena_new();
    /* Nodes start with zeroed scratch generations; no operation may use 0, and
     * the generation outside any operation (1) is never handed out either. */
    c->genctr = 1;
    c->gen = 1;
    bool ok = parse_source(c, intern(c, "<prelude>"), prelude, &c->decls);
    for (size_t i = 0; i < n; i++) {
        const char *src = sources ? sources[i] : NULL;
        char *owned = NULL;
        if (from_files) {
            FILE *f = fopen(names[i], "rb");
            if (!f) { diag(c, true, noloc, "cannot open %s", names[i]); ok = false; continue; }
            fseek(f, 0, SEEK_END);
            long len = ftell(f);
            fseek(f, 0, SEEK_SET);
            owned = malloc((size_t) len + 1);
            size_t got = fread(owned, 1, (size_t) len, f);
            owned[got] = 0;
            fclose(f);
            src = owned;
        }
        ok &= parse_source(c, intern(c, names[i]), src, &c->decls);
        free(owned);
    }
    finish_load(c, ok, t0);
    return c;
}

TriContent *tri_content_load(const char *const *paths, size_t n)
{
    return load_common(paths, NULL, n, true);
}

TriContent *tri_content_load_strings(const char *const *names, const char *const *sources, size_t n)
{
    return load_common(names, sources, n, false);
}

void tri_content_free(TriContent *c)
{
    if (!c) return;
    for (size_t i = 0; i < c->diags.n; i++) free(c->diags.v[i].msg);
    VEC_FREE(c->diags);
    for (size_t i = 0; i < c->types.n; i++) {
        TypeInfo *t = &c->types.v[i];
        VEC_FREE(t->parents);
        VEC_FREE(t->children);
        free(t->code);
        VEC_FREE(t->feats);
        VEC_FREE(t->decls);
        VEC_FREE(t->members);
        for (size_t k = 0; k < t->defaults.n; k++) VEC_FREE(t->defaults.v[k].path);
        VEC_FREE(t->defaults);
        VEC_FREE(t->field_attrs);
        VEC_FREE(t->field_feats);
    }
    VEC_FREE(c->types);
    for (size_t i = 0; i < c->insts.n; i++) {
        InstInfo *in = &c->insts.v[i];
        VEC_FREE(in->decls);
        for (size_t k = 0; k < in->defaults.n; k++) VEC_FREE(in->defaults.v[k].path);
        VEC_FREE(in->defaults);
        for (size_t k = 0; k < in->tags.n; k++) VEC_FREE(in->tags.v[k].path);
        VEC_FREE(in->tags);
        for (size_t k = 0; k < in->variation.n; k++) free(in->variation.v[k]);
        VEC_FREE(in->variation);
        for (size_t k = 0; k < in->varpaths.n; k++) VEC_FREE(in->varpaths.v[k]);
        VEC_FREE(in->varpaths);
        for (size_t k = 0; k < in->notes.n; k++) free(in->notes.v[k]);
        VEC_FREE(in->notes);
    }
    VEC_FREE(c->insts);
    VEC_FREE(c->feats);
    VEC_FREE(c->decls);
    u64map_free(&c->typeidx);
    u64map_free(&c->codeidx);
    u64map_free(&c->meetmemo);
    u64map_free(&c->featidx);
    u64map_free(&c->instidx);
    free(c->bittype);
    tri_arena_free(c->load);
    tri_arena_free(c->spec);
    tri_arena_free(c->scratch);
    sym_free(&c->syms);
    free(c);
}

int tri_content_ok(const TriContent *c) { return c->nerrors == 0; }
uint64_t tri_content_hash(const TriContent *c) { return c->hash; }
size_t tri_diag_count(const TriContent *c) { return c->diags.n; }
const char *tri_diag_message(const TriContent *c, size_t i) { return i < c->diags.n ? c->diags.v[i].msg : NULL; }
int tri_diag_is_error(const TriContent *c, size_t i) { return i < c->diags.n && c->diags.v[i].error; }

/* --- types API ------------------------------------------------------------------------------------- */

size_t tri_type_count(const TriContent *c) { return c->types.n; }

TriType tri_type_named(const TriContent *cc, const char *name)
{
    Content *c = (Content *) cc;
    return type_lookup(c, intern(c, name));
}

const char *tri_type_name(const TriContent *c, TriType t)
{
    return t < c->types.n ? c->types.v[t].name : NULL;
}

TriType tri_meet(TriContent *c, TriType a, TriType b) { return meet(c, a, b); }
int tri_subtype(const TriContent *c, TriType a, TriType b) { return is_subtype(c, a, b); }

TriType tri_primary_parent(const TriContent *c, TriType t)
{
    return t < c->types.n && c->types.v[t].parents.n ? c->types.v[t].parents.v[0] : TRI_BOTTOM;
}

static uint32_t component_type_at(const TriContent *c, size_t i)
{
    size_t k = 0;
    for (uint32_t t = 0; t < c->types.n; t++)
        if (c->types.v[t].component) { if (k == i) return t; k++; }
    return TRI_BOTTOM;
}

size_t tri_component_count(const TriContent *c)
{
    size_t k = 0;
    for (uint32_t t = 0; t < c->types.n; t++) if (c->types.v[t].component) k++;
    return k;
}

const char *tri_component_name(const TriContent *c, size_t i)
{
    uint32_t t = component_type_at(c, i);
    return t == TRI_BOTTOM ? NULL : c->types.v[t].component;
}

TriType tri_component_type(const TriContent *c, size_t i) { return component_type_at(c, i); }

/* A component's fields are the features its type introduces. */
size_t tri_component_field_count(const TriContent *c, size_t i)
{
    uint32_t t = component_type_at(c, i);
    if (t == TRI_BOTTOM) return 0;
    size_t k = 0;
    for (uint32_t f = 0; f < c->feats.n; f++) if (c->feats.v[f].intro == t) k++;
    return k;
}

const char *tri_component_field(const TriContent *c, size_t i, size_t j, const char **flags)
{
    uint32_t t = component_type_at(c, i);
    if (t == TRI_BOTTOM) return NULL;
    size_t k = 0;
    for (uint32_t f = 0; f < c->feats.n; f++) {
        if (c->feats.v[f].intro != t) continue;
        if (k++ != j) continue;
        if (flags) {
            *flags = "";
            const TypeInfo *ti = &c->types.v[t];
            for (size_t a = 0; a < ti->field_feats.n; a++)
                if (ti->field_feats.v[a] == f) *flags = ti->field_attrs.v[a]->args;
        }
        return c->feats.v[f].name;
    }
    return NULL;
}

/* --- statistics and instance enumeration --------------------------------------------------------- */

static size_t arena_bytes(const TriArena *a)
{
    size_t n = 0;
    for (const Chunk *ch = a->top; ch; ch = ch->prev) n += ch->used;
    return n;
}

void tri_content_stats(const TriContent *c, TriStats *s)
{
    *s = c->stats;
    s->types = c->types.n;
    s->glb_types = c->nglb;
    s->leaf_types = c->types.n - c->nbits;
    s->features = c->feats.n;
    s->instances = c->insts.n;
    s->spec_bytes = arena_bytes(c->spec);
    s->load_bytes = arena_bytes(c->load);
}

size_t tri_instance_count(const TriContent *c) { return c->insts.n; }

const char *tri_instance_name(const TriContent *c, size_t i)
{
    return i < c->insts.n ? c->insts.v[i].name : NULL;
}

const char *tri_instance_status(const TriContent *c, size_t i)
{
    if (i >= c->insts.n || !c->insts.v[i].decls.n) return NULL;
    Sym s = c->insts.v[i].decls.v[0]->status;
    return s ? s : "";
}
