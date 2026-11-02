#include "internal.h"

#include <ctype.h>
#include <time.h>

/* Loading: building feature structures from the syntax tree, type expansions,
 * instance patterns and specs (defaults, variation), construction from seeds,
 * runtime values, matching, generalisation, and the public loading API. */

static Loc noloc;

static const char *prelude =
    "#List: {}\n"
    "#Cons: #List & { first: _, rest: #List }\n"
    "#Null: #List\n";

/* Definite clauses (§10), built in when content uses them: they introduce
 * `head` and `body`, which content may otherwise want for itself. */
static const char *clause_prelude =
    "#Clause: { head: _, body: #List }\n"
    "#Fact: #Clause & { body: #Null }\n";

/* --- building ------------------------------------------------------------------------- */

typedef struct { Sym name; TriNode *node; } TagEnt;

typedef struct {
    Content *c;
    VEC(TagEnt) tags;
    U32Vec path;
    DefVec defs;
    DefVec varies;
    uint32_t contributor;
    bool record;
    bool ok;
    bool direct;     /* the next type name may use its expansion without copying */
    Loc errloc;
    uint32_t owner;  /* type whose body is being built, or TRI_BOTTOM */
    size_t decl;     /* which of its declarations */
    bool runtime;    /* a runtime value: no defaults */
    ArithVec ariths; /* arithmetic met while building; tags resolved afterwards */
} Build;

static const char *interp_eval(Content *c, const X *x, void *lookup, Buf *out);
static TriNode *string_node(Content *c, TriArena *a, const char *bytes, size_t n);

static void free_ariths(ArithVec *v)
{
    for (size_t i = 0; i < v->n; i++) {
        VEC_FREE(v->v[i].path);
        for (size_t k = 0; k < v->v[i].tags.n; k++) VEC_FREE(v->v[i].tags.v[k].path);
        VEC_FREE(v->v[i].tags);
    }
    VEC_FREE(*v);
}

static void build_free(Build *b)
{
    VEC_FREE(b->tags);
    VEC_FREE(b->path);
    VEC_FREE(b->defs);
    VEC_FREE(b->varies);
    free_ariths(&b->ariths);
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

/* The location of the field at `path` in an expression, through
 * conjunctions and nested structures. */
static bool find_field_loc(Content *c, X *x, const uint32_t *path, size_t n, Loc *out)
{
    if (!n) return false;
    if (x->k == X_AND) return find_field_loc(c, x->u.bin.a, path, n, out) || find_field_loc(c, x->u.bin.b, path, n, out);
    if (x->k == X_DEFAULT) return find_field_loc(c, x->u.sub, path, n, out);
    if (x->k != X_STRUCT) return false;
    for (int i = 0; i < x->u.st.n; i++) {
        XField *f = &x->u.st.fields[i];
        if (f->label != c->feats.v[path[0]].name) continue;
        if (n == 1 || find_field_loc(c, f->value, path + 1, n - 1, out)) {
            if (n == 1) *out = f->loc;
            return true;
        }
    }
    return false;
}

/* Where a type, or its nearest ancestor that does, declares `path`. */
static bool type_field_loc(Content *c, uint32_t t, const uint32_t *path, size_t n, Loc *out, Sym *who)
{
    U32Vec queue = { 0 };
    U64Map seen = { 0 };
    VEC_PUSH(queue, t);
    bool found = false;
    for (size_t i = 0; i < queue.n && !found; i++) {
        TypeInfo *ti = &c->types.v[queue.v[i]];
        for (size_t k = 0; k < ti->decls.n && !found; k++) found = find_field_loc(c, ti->decls.v[k]->value, path, n, out);
        if (found) { *who = ti->name; break; }
        for (size_t k = 0; k < ti->parents.n; k++)
            if (!u64map_get(&seen, ti->parents.v[k], NULL)) {
                u64map_put(&seen, ti->parents.v[k], 1);
                VEC_PUSH(queue, ti->parents.v[k]);
            }
    }
    VEC_FREE(queue);
    u64map_free(&seen);
    return found;
}

/* Reports a conflict at `loc`, naming where the other side was declared:
 * an earlier declaration of the type being built, or `other` (a type whose
 * constraint is being added) and its ancestors. */
static bool unify_at_other(Build *b, TriNode *x, TriNode *y, Loc loc, const char *what, uint32_t other)
{
    Content *c = b->c;
    memcpy(c->pathstack, b->path.v, b->path.n * sizeof(uint32_t));
    c->depth = (int) b->path.n;
    c->failed = false;
    if (unify1(c, x, y)) return true;
    if (b->ok) {
        Buf where = { 0 };
        Loc ol;
        Sym who = NULL;
        if (other != TRI_BOTTOM && type_field_loc(c, other, c->failpath, (size_t) c->faildepth, &ol, &who))
            buf_printf(&where, ", with %s at %s:%d", who, ol.file, ol.line);
        else if (b->owner != TRI_BOTTOM)
            for (size_t k = 0; k < b->decl && !where.len; k++)
                if (find_field_loc(c, c->types.v[b->owner].decls.v[k]->value, c->failpath, (size_t) c->faildepth, &ol))
                    buf_printf(&where, ", with the declaration at %s:%d", ol.file, ol.line);
        TriFailure *fl = fail_info(c);
        size_t pl = strlen(fl->path);
        if (what[0] == '.' && !strncmp(what + 1, fl->path, pl) && what[1 + pl] == '.') {
            /* a reference whose path goes through a field without its next name */
            const char *nx = what + 2 + pl;
            diag(c, true, loc, "the reference %s: %s is %s, which has no field %.*s", what, fl->path, fl->left,
                 (int) strcspn(nx, ".["), nx);
        } else
        diag(c, true, loc, "%s%s: conflict at %s: %s vs %s%s", what[0] == '.' ? "the reference " : "", what, fl->path,
             fl->left, fl->right[0] ? fl->right : "(missing)", where.s ? where.s : "");
        buf_free(&where);
    }
    b->ok = false;
    return false;
}

static bool unify_at(Build *b, TriNode *x, TriNode *y, Loc loc, const char *what)
{
    return unify_at_other(b, x, y, loc, what, TRI_BOTTOM);
}

static void record_default(Build *b, X *value)
{
    if (!b->record) return;
    DefaultRec d = { { 0 }, value, b->contributor, NULL };
    for (size_t i = 0; i < b->path.n; i++) VEC_PUSH(d.path, b->path.v[i]);
    VEC_PUSH(b->defs, d);
}

static bool parse_weights(const char *args, uint64_t *w, size_t n);

/* A field's @vary weights, kept for construction. The path includes the field. */
static void record_vary(Build *b, X *value, const char *weights, Loc loc)
{
    if (!b->record) return;
    if (!strncmp(weights, "mode", 4)) {
        /* @vary(mode: v): a peak for a range, checked when drawn */
        const char *v = strchr(weights, ':');
        if (!v) { build_error(b, loc, "@vary(%s) needs a value: @vary(mode: 19mm)", weights); return; }
        DefaultRec d = { { 0 }, value, b->contributor, weights };
        for (size_t i = 0; i < b->path.n; i++) VEC_PUSH(d.path, b->path.v[i]);
        VEC_PUSH(b->varies, d);
        return;
    }
    if (value->k == X_NAME) {
        /* a named enum: the weights follow its declared members */
        uint32_t t = type_lookup(b->c, value->u.name);
        if (t != TRI_BOTTOM && b->c->types.v[t].decls.n && b->c->types.v[t].decls.v[0]->value->k == X_OR)
            value = b->c->types.v[t].decls.v[0]->value;
    }
    XPtrVec ds = { 0 };
    x_flatten(value, X_OR, &ds);
    size_t n = ds.n;
    VEC_FREE(ds);
    uint64_t *w = malloc(sizeof(uint64_t) * (n ? n : 1));
    bool good = parse_weights(weights, w, n);
    free(w);
    if (n < 2) {
        build_error(b, loc, "@vary(%s) needs a field with alternatives", weights);
        return;
    }
    if (!good) {
        char msg[160];
        snprintf(msg, sizeof msg, "@vary(%s) needs one whole-number weight per alternative (%zu)", weights, n);
        build_error(b, loc, "%s", msg);
        return;
    }
    DefaultRec d = { { 0 }, value, b->contributor, weights };
    for (size_t i = 0; i < b->path.n; i++) VEC_PUSH(d.path, b->path.v[i]);
    VEC_PUSH(b->varies, d);
}

static TriNode *build_raw(Build *b, X *x);

/* A path into another declaration, as in wrench_19.size or #Wrench.size: a
 * copy of the declaration, at the path. The longest prefix that names a type
 * or an instance is the declaration, so a package's names come first. */
static TriNode *name_path(Build *b, X *x)
{
    Content *c = b->c;
    const char *s = x->u.name;
    size_t n = strlen(s);
    for (size_t end = n; end-- > 1;) {
        if (s[end] != '.' && s[end] != '[') continue;
        if (s[end] == '.' && s[end + 1] == '#') continue;           /* pkg.#Type is one name */
        char *pre = malloc(end + 1);
        memcpy(pre, s, end);
        pre[end] = 0;
        Sym name = intern(c, pre);
        free(pre);
        TriNode *node = NULL;
        uint32_t t = type_lookup(c, name);
        uint64_t v;
        if (t != TRI_BOTTOM && c->types.v[t].kind != TK_ATOM) {
            TriNode *e = type_expansion(c, t);
            if (!e) { build_error(b, x->loc, "cannot expand %s", name); return NULL; }
            node = copy_raw(c, c->scratch, e);
        } else if (u64map_get(&c->instidx, (uint64_t) (uintptr_t) name, &v)) {
            if (!inst_pattern(c, (uint32_t) v - 1)) {
                build_error(b, x->loc, "instance %s could not be resolved", name);
                return NULL;
            }
            node = copy_raw(c, c->scratch, c->insts.v[v - 1].pattern);
        } else continue;
        /* the rest: .name and [k] */
        for (const char *p = s + end; *p && node;) {
            char seg[256];
            if (*p == '.') {
                const char *e = ++p;
                while (*e && *e != '.' && *e != '[') e++;
                snprintf(seg, sizeof seg, "%.*s", (int) (e - p), p);
                p = e;
                uint32_t f = feat_lookup(c, intern(c, seg));
                TriNode *next = f == TRI_BOTTOM ? NULL : node_arc(deref(c, node), f);
                if (!next) {
                    char msg[600];
                    snprintf(msg, sizeof msg, "%s has no field %s (in %s)", name, seg, s);
                    build_error(b, x->loc, "%s", msg);
                    return NULL;
                }
                node = next;
            } else {
                long k = strtol(p + 1, NULL, 10);
                while (*p && *p != ']') p++;
                if (*p) p++;
                for (long i = 0; i <= k; i++) {
                    TriNode *next = node_arc(deref(c, node), i == k ? c->ffirst : c->frest);
                    if (!next) {
                        char msg[600];
                        snprintf(msg, sizeof msg, "%s has no item %ld (in %s)", name, k, s);
                        build_error(b, x->loc, "%s", msg);
                        return NULL;
                    }
                    node = next;
                }
            }
        }
        return node;
    }
    return NULL;
}

static TriNode *build_struct_into(Build *b, TriNode *r, X *x)
{
    Content *c = b->c;
    for (int i = 0; i < x->u.st.n && b->ok; i++) {
        XField *f = &x->u.st.fields[i];
        uint32_t fid = feat_lookup(c, f->label);
        if (fid == TRI_BOTTOM) { build_error(b, f->loc, "unknown feature '%s'", f->label); break; }
        VEC_PUSH(b->path, fid);
        const char *vary = attr_args(f->attrs, f->nattrs, "vary");
        if (vary) record_vary(b, f->value, vary, f->loc);
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
    return x_interval(x, dim, lo, hi);
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
            if (c->types.v[t].xstate == 1) return type_instance(c, t, c->scratch);
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
        if (strchr(x->u.name, '.') || strchr(x->u.name, '[')) {
            TriNode *n = name_path(b, x);
            if (n || !b->ok) return n;
        }
        build_error(b, x->loc, "unknown name %s", x->u.name);
        return NULL;
    }
    case X_ATOM: {
        uint32_t t = type_lookup(c, x->u.name);
        if (!c->tdl && (t == TRI_BOTTOM || (c->types.v[t].kind == TK_ATOM && c->types.v[t].parents.n == 1 &&
                                            c->types.v[t].parents.v[0] == c->atomroot))) {
            /* a string no enum lists is free text */
            int64_t q = (int64_t) (intptr_t) x->u.name;
            return leaf_new(c, c->scratch, c->dimtype[DIM_TEXT], q, q);
        }
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
    case X_INTERP: {
        SymVec names = { 0 };
        arith_tags(x, &names);
        bool tagged = names.n > 0;
        VEC_FREE(names);
        if (!tagged) {                       /* nothing to wait for: the string now */
            Buf sb = { 0 };
            const char *err = interp_eval(c, x, NULL, &sb);
            if (err) {
                build_error(b, x->loc, "%s", err == ARITH_UNKNOWN ? "an interpolation that is not concrete" : err);
                buf_free(&sb);
                return NULL;
            }
            TriNode *n = string_node(c, c->scratch, sb.s ? sb.s : "", sb.len);
            buf_free(&sb);
            return n;
        }
        /* like arithmetic: a constraint on this field, once its tags are concrete */
        ArithRec r = { { 0 }, x, { 0 } };
        for (size_t i = 0; i < b->path.n; i++) VEC_PUSH(r.path, b->path.v[i]);
        VEC_PUSH(b->ariths, r);
        return node_new(c, c->scratch, c->top);
    }
    case X_REGEX: {
        const RxSet *set = rx_single(c, x->u.rx.pat, x->u.rx.neg, NULL, 0);
        if (!set) { build_error(b, x->loc, "bad regular expression %s", x->u.rx.pat); return NULL; }
        return leaf_new(c, c->scratch, c->dimtype[DIM_TEXT], TRI_NINF, (int64_t) (intptr_t) set);
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
        const char *what = "struct";
        if (x->u.st.refs) {                  /* a reference's place: name the reference */
            X *tag = x;
            while (tag->k == X_STRUCT) tag = tag->u.st.fields[0].value;
            what = tag->u.name;
        }
        if (t != c->top && c->types.v[t].xstate == 1) {
            r->flags |= NF_LAZY;             /* inside t's own constraint */
        } else if (t != c->top) {
            TriNode *e = type_expansion(c, t);
            if (!e) { build_error(b, x->loc, "cannot expand %s", c->types.v[t].name); return NULL; }
            unify_at(b, r, copy_raw(c, c->scratch, e), x->loc, what);
        }
        return b->ok ? r : NULL;
    }
    case X_AND: {
        TriNode *l = build_raw(b, x->u.bin.a);
        TriNode *r = l ? build_raw(b, x->u.bin.b) : NULL;
        if (!r) return NULL;
        X *rb = x->u.bin.b;
        if (rb->k == X_STRUCT && rb->u.st.refs) {      /* a reference's place: name the reference */
            X *tag = rb;
            while (tag->k == X_STRUCT) tag = tag->u.st.fields[0].value;
            unify_at(b, l, r, tag->loc, tag->u.name);
        } else
        unify_at(b, l, r, x->loc, "conjunction");
        return b->ok ? l : NULL;
    }
    case X_ARITH: {
        int dim;
        int64_t lo, hi;
        if (x_interval(x, &dim, &lo, &hi)) return leaf_new(c, c->scratch, c->dimtype[dim], lo, hi);
        /* a constraint on this field, resolved once the tags have their places */
        ArithRec r = { { 0 }, x, { 0 } };
        for (size_t i = 0; i < b->path.n; i++) VEC_PUSH(r.path, b->path.v[i]);
        VEC_PUSH(b->ariths, r);
        return node_new(c, c->scratch, c->top);
    }
    case X_COMP: case X_VAR: case X_CALL:    /* expanded when content loads */
        build_error(b, x->loc, "%s", "a comprehension or its variable outside one, not expanded");
        return NULL;
    case X_CMP: case X_LOGIC: case X_NOT:
        build_error(b, x->loc, "%s", "a comparison not expanded");
        return NULL;
    case X_LET:                              /* the parser replaces every use */
        build_error(b, x->loc, "%s", "a let's use was not resolved");
        return NULL;
    case X_DEFAULT:
        if (b->runtime) { build_error(b, x->loc, "%s", "a default (*) has no meaning in a runtime value"); return NULL; }
        record_default(b, x->u.sub);
        return node_new(c, c->scratch, c->top);
    case X_OR: {
        uint64_t di;
        if (u64map_get(&c->disjidx, (uint64_t) (uintptr_t) x, &di)) {
            /* a disjunction of structures in a type body: its type, whose
             * alternatives are subtypes */
            DisjInfo *d = &c->disjs.v[di - 1];
            if (d->def >= 0)
                record_default(b, d->collapse ? d->altx.v[d->def] : x_name(c, d->alts.v[d->def], x->loc));
            X *named = x_name(c, d->collapse ? d->collapse : d->dname, x->loc);
            if (d->collapse && c->types.v[type_lookup(c, d->collapse)].kind == TK_ATOM) named->k = X_ATOM;
            return build_raw(b, named);
        }
        XPtrVec ds = { 0 };
        flatten_or(x, &ds);
        X *def = NULL;
        bool all_atoms = true, all_num = true;
        int dim = -1;
        int64_t lo = TRI_INF, hi = TRI_NINF;
        for (size_t i = 0; i < ds.n; i++) {
            X *d = ds.v[i];
            if (d->k == X_DEFAULT) {
                if (b->runtime) {
                    build_error(b, d->loc, "%s", "a default (*) has no meaning in a runtime value");
                    VEC_FREE(ds);
                    return NULL;
                }
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
        if (all_num) {
            int d2;
            int64_t l2, h2;
            bool contiguous;
            if (x_numeric_or(x, &d2, &l2, &h2, &contiguous) && !contiguous) {
                build_error(b, x->loc, "%s", "a disjunction of separate numbers is resolved only in an instance");
                return NULL;
            }
            return leaf_new(c, c->scratch, c->dimtype[dim], lo, hi);
        }
        build_error(b, x->loc, "%s", "a disjunction of structures is resolved only in a type or an instance");
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
        } else if (x->u.list.elem) {
            uint32_t lt = type_lookup(c, list_type_name(c, x->u.list.elem, false));
            TriNode *e = lt == TRI_BOTTOM ? NULL : type_expansion(c, lt);
            if (!e) { build_error(b, x->loc, "%s", "this typed list does not occur in the content"); return NULL; }
            tail = copy_raw(c, c->scratch, e);
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

static bool resolve_ariths(Content *c, Build *b, TriNode *out, ArithVec *dst, Loc loc, const char *who);
static void copy_arith(ArithVec *dst, const ArithRec *src);
static TriNode *settle_arith(Content *c, TriNode *root, const ArithVec *extra, TriArena *arena, TriFailure *fail);

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
    DefaultRec n = { { 0 }, d->value, d->contributor, d->vary };
    for (size_t i = 0; i < plen; i++) VEC_PUSH(n.path, prefix[i]);
    for (size_t i = 0; i < d->path.n; i++) VEC_PUSH(n.path, d->path.v[i]);
    for (size_t i = 0; i < defs->n; i++)
        if (defs->v[i].value == n.value && defs->v[i].contributor == n.contributor && path_eq(&defs->v[i].path, &n.path)) {
            VEC_FREE(n.path);
            return;
        }
    VEC_PUSH(*defs, n);
}

TriNode *type_instance(Content *c, uint32_t t, TriArena *a)
{
    if (c->types.v[t].xstate == 1) {
        /* t's constraint mentions t: a lazy node, completed when used */
        TriNode *n = node_new(c, a, t);
        n->flags |= NF_LAZY;
        return n;
    }
    TriNode *e = type_expansion(c, t);
    return e ? copy_raw(c, a, e) : NULL;
}

TriNode *type_expansion(Content *c, uint32_t t)
{
    TypeInfo *ti = &c->types.v[t];
    if (ti->xstate == 2) return ti->expansion;
    if (ti->xstate == 1) return NULL;
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
    TriFailure savedfail = *fail_info(c);
    uint32_t savedfailpath[128];
    int savedfaildepth = c->faildepth;
    memcpy(savedfailpath, c->failpath, sizeof savedfailpath);
    memcpy(savedpath, c->pathstack, sizeof savedpath);
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);

    Build b = { 0 };
    b.c = c;
    b.contributor = t;
    b.record = true;
    b.ok = true;
    b.owner = t;
    TriNode *r = node_new(c, c->scratch, t);
    for (size_t k = 0; k < ti->decls.n && b.ok; k++) {
        b.decl = k;
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
        if (!e) {
            if (c->types.v[p].xstate == 1)
                diag(c, true, loc, "%s inherits from %s, whose constraint depends on %s", ti->name,
                     c->types.v[p].name, ti->name);
            b.ok = false;
            break;
        }
        Buf what = { 0 };
        buf_printf(&what, "%s inheriting from %s", ti->name, c->types.v[p].name);
        /* the conflict is reported at this type's own declaration of the path */
        Loc here = loc;
        b.owner = TRI_BOTTOM;
        /* the first parent's expansion is used as is, so the result shares it */
        if (!unify_at_other(&b, r, k == 0 && c->opdepth == 1 ? e : copy_raw(c, c->scratch, e), here, what.s, p)) {
            /* re-point the diagnostic at this type's declaration of the path, if any */
            for (size_t q = 0; q < ti->decls.n; q++)
                if (find_field_loc(c, ti->decls.v[q]->value, c->failpath, (size_t) c->faildepth, &here)) {
                    Diag *dg = &c->diags.v[c->diags.n - 1];
                    char *old = dg->msg;
                    const char *rest = strstr(old, ": error: ");
                    Buf nb = { 0 };
                    if (rest) buf_printf(&nb, "%s:%d:%d%s", here.file, here.line, here.col, rest);
                    else buf_printf(&nb, "%s:%d:%d: %s", here.file, here.line, here.col, old);
                    dg->msg = nb.s;
                    dg->loc = here;
                    free(old);
                    break;
                }
        }
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
        /* arithmetic: the type's own, with tags placed in its expansion, and its parents' */
        if (!resolve_ariths(c, &b, out, &ti->ariths, loc, ti->name)) out = NULL;
        ti = &c->types.v[t];
        for (size_t k = 0; k < ti->parents.n; k++) {
            const ArithVec *pa = &c->types.v[ti->parents.v[k]].ariths;
            for (size_t i = 0; i < pa->n; i++) copy_arith(&ti->ariths, &pa->v[i]);
        }
    }
    if (out) {
        for (size_t i = 0; i < b.defs.n; i++) add_default(&ti->defaults, &b.defs.v[i], NULL, 0);
        for (size_t i = 0; i < b.varies.n; i++) add_default(&ti->varies, &b.varies.v[i], NULL, 0);
        for (size_t k = 0; k < ti->parents.n; k++) {
            TypeInfo *pi = &c->types.v[ti->parents.v[k]];
            for (size_t i = 0; i < pi->defaults.n; i++) add_default(&ti->defaults, &pi->defaults.v[i], NULL, 0);
            for (size_t i = 0; i < pi->varies.n; i++) add_default(&ti->varies, &pi->varies.v[i], NULL, 0);
        }
    }
    for (size_t i = 0; i < b.defs.n; i++) VEC_FREE(b.defs.v[i].path);
    for (size_t i = 0; i < b.varies.n; i++) VEC_FREE(b.varies.v[i].path);
    build_free(&b);

    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    memcpy(c->pathstack, savedpath, sizeof savedpath);
    c->depth = saveddepth;
    c->failed = savedfailed;
    c->fail_ = savedfail;
    c->failfmt = true;
    memcpy(c->failpath, savedfailpath, sizeof savedfailpath);
    c->faildepth = savedfaildepth;

    ti = &c->types.v[t];
    if (out && c->types.v[t].ariths.n) {
        /* what the constraints give with the type's own values; open stays open */
        ti->expansion = out;
        ti->xstate = 2;
        TriFailure f;
        TriNode *settled = settle_arith(c, out, NULL, c->spec, &f);
        if (!settled) diag(c, true, loc, "%s: arithmetic at %s: %s gives %s", c->types.v[t].name, f.path, f.left, f.right);
        out = settled;
        ti = &c->types.v[t];
    }
    ti->expansion = out;
    ti->xstate = out ? 2 : 0;
    if (!out) ti->xstate = 2;    /* do not retry; errors are already reported */
    return out;
}

/* --- variants ---------------------------------------------------------------------------------- */

/* An instance's disjunctions of structures are expanded at load: the instance
 * becomes one variant per combination of alternatives. Enums of atoms and
 * ranges stay as they are; they are resolved by types and intervals. */

typedef struct { X *x; uint64_t weight, hasdef, tookdef; } XVar;
typedef VEC(XVar) XVarVec;

typedef struct {
    Content *c;
    size_t cap;
    int ndisj;               /* disjunctions with a default, numbered for the masks */
    bool overflow, bad;
    bool vary_used;          /* some disjunction took the weights it was given */
} Expand;

static bool structural_or(Content *c, X *x)
{
    if (x->k != X_OR || anon_name(c, x)) return false;
    XPtrVec ds = { 0 };
    x_flatten(x, X_OR, &ds);
    bool atoms = true;
    for (size_t i = 0; i < ds.n; i++) {
        X *d = ds.v[i]->k == X_DEFAULT ? ds.v[i]->u.sub : ds.v[i];
        if (d->k != X_ATOM) atoms = false;
    }
    VEC_FREE(ds);
    if (atoms) return false;                 /* the same atom, repeated */
    int dim;
    int64_t lo, hi;
    bool contiguous;
    if (x_numeric_or(x, &dim, &lo, &hi, &contiguous)) return !contiguous;
    return true;
}

static bool has_structural(Content *c, X *x)
{
    switch (x->k) {
    case X_OR: return structural_or(c, x) || has_structural(c, x->u.bin.a) || has_structural(c, x->u.bin.b);
    case X_AND: return has_structural(c, x->u.bin.a) || has_structural(c, x->u.bin.b);
    case X_DEFAULT: return has_structural(c, x->u.sub);
    case X_STRUCT:
        for (int i = 0; i < x->u.st.n; i++) if (has_structural(c, x->u.st.fields[i].value)) return true;
        return false;
    case X_LIST:
        for (int i = 0; i < x->u.list.n; i++) if (has_structural(c, x->u.list.items[i])) return true;
        return (x->u.list.tail && has_structural(c, x->u.list.tail)) ||
               (x->u.list.elem && has_structural(c, x->u.list.elem));
    default: return false;
    }
}

/* Parses @vary weights; false unless there is exactly one per alternative. */
static bool parse_weights(const char *args, uint64_t *w, size_t n)
{
    const char *s = args;
    size_t k = 0;
    while (*s) {
        while (*s == ' ' || *s == ',' || *s == '\t') s++;
        if (!*s) break;
        if (*s < '0' || *s > '9' || k == n) return false;
        uint64_t v = 0;
        while (*s >= '0' && *s <= '9') { v = v * 10 + (uint64_t) (*s - '0'); if (v > 1000000) return false; s++; }
        w[k++] = v;
        while (*s == ' ' || *s == '\t') s++;
        if (*s && *s != ',') return false;
    }
    return k == n;
}

const char *attr_args(const Attr *attrs, int n, const char *name)
{
    for (int i = 0; i < n; i++) if (strcmp(attrs[i].name, name) == 0) return attrs[i].args;
    return NULL;
}

static uint64_t mul_sat(uint64_t a, uint64_t b)
{
    return a && b > UINT64_MAX / a ? UINT64_MAX : a * b;
}

static void expand_x(Expand *e, X *x, const char *vary, Loc vloc, XVarVec *out);

/* The cartesian product of the children's variants; `make` builds the parent. */
static void product(Expand *e, XVarVec *parts, size_t n, X *orig,
                    X *(*make)(Content *, X *, X **), XVarVec *out)
{
    size_t *ix = calloc(n ? n : 1, sizeof(size_t));
    X **chosen = malloc(sizeof(X *) * (n ? n : 1));
    for (;;) {
        XVar v = { NULL, 1, 0, 0 };
        for (size_t i = 0; i < n; i++) {
            XVar *p = &parts[i].v[ix[i]];
            chosen[i] = p->x;
            v.weight = mul_sat(v.weight, p->weight);
            v.hasdef |= p->hasdef;
            v.tookdef |= p->tookdef;
        }
        v.x = make(e->c, orig, chosen);
        VEC_PUSH(*out, v);
        if (out->n > e->cap) { e->overflow = true; break; }
        size_t i = 0;
        while (i < n && ++ix[i] == parts[i].n) ix[i++] = 0;
        if (i == n) break;
    }
    free(ix);
    free(chosen);
}

static X *make_and(Content *c, X *orig, X **ch)
{
    X *x = x_new(c, X_AND, orig->loc);
    x->u.bin.a = ch[0];
    x->u.bin.b = ch[1];
    return x;
}

static X *make_default(Content *c, X *orig, X **ch)
{
    X *x = x_new(c, X_DEFAULT, orig->loc);
    x->u.sub = ch[0];
    return x;
}

static X *make_struct(Content *c, X *orig, X **ch)
{
    X *x = x_new(c, X_STRUCT, orig->loc);
    x->u.st = orig->u.st;
    x->u.st.fields = arena_alloc(c->load, sizeof(XField) * (size_t) (orig->u.st.n ? orig->u.st.n : 1));
    for (int i = 0; i < orig->u.st.n; i++) {
        x->u.st.fields[i] = orig->u.st.fields[i];
        x->u.st.fields[i].value = ch[i];
    }
    return x;
}

static X *make_list(Content *c, X *orig, X **ch)
{
    X *x = x_new(c, X_LIST, orig->loc);
    x->u.list = orig->u.list;
    x->u.list.items = arena_alloc(c->load, sizeof(X *) * (size_t) (orig->u.list.n ? orig->u.list.n : 1));
    int k = 0;
    for (int i = 0; i < orig->u.list.n; i++) x->u.list.items[i] = ch[k++];
    if (orig->u.list.tail) x->u.list.tail = ch[k++];
    if (orig->u.list.elem) x->u.list.elem = ch[k++];
    return x;
}

static void free_parts(XVarVec *parts, size_t n)
{
    for (size_t i = 0; i < n; i++) VEC_FREE(parts[i]);
    free(parts);
}

static void expand_x(Expand *e, X *x, const char *vary, Loc vloc, XVarVec *out)
{
    Content *c = e->c;
    if (e->overflow || e->bad) return;
    if (!has_structural(c, x)) {
        XVar v = { x, 1, 0, 0 };
        VEC_PUSH(*out, v);
        return;
    }
    switch (x->k) {
    case X_OR: {
        if (!structural_or(c, x)) {           /* an enum or range whose parts nest structure */
            XVar v = { x, 1, 0, 0 };
            VEC_PUSH(*out, v);
            return;
        }
        XPtrVec ds = { 0 };
        x_flatten(x, X_OR, &ds);
        uint64_t *w = malloc(sizeof(uint64_t) * ds.n);
        for (size_t i = 0; i < ds.n; i++) w[i] = 1;
        if (vary) e->vary_used = true;
        if (vary && !parse_weights(vary, w, ds.n)) {
            diag(c, true, vloc, "@vary(%s) needs one whole-number weight per alternative (%zu)", vary, ds.n);
            e->bad = true;
        }
        int def = -1;
        for (size_t i = 0; i < ds.n; i++) if (ds.v[i]->k == X_DEFAULT) def = (int) i;
        uint64_t bit = 0;
        if (def >= 0) {
            if (e->ndisj == 64) { diag(c, true, x->loc, "too many defaults among alternatives"); e->bad = true; }
            else bit = 1ull << e->ndisj++;
        }
        for (size_t i = 0; i < ds.n && !e->overflow && !e->bad; i++) {
            X *a = ds.v[i]->k == X_DEFAULT ? ds.v[i]->u.sub : ds.v[i];
            size_t from = out->n;
            expand_x(e, a, NULL, a->loc, out);
            for (size_t k = from; k < out->n; k++) {
                out->v[k].weight = mul_sat(out->v[k].weight, w[i]);
                out->v[k].hasdef |= bit;
                if ((int) i == def) out->v[k].tookdef |= bit;
            }
            if (out->n > e->cap) e->overflow = true;
        }
        free(w);
        VEC_FREE(ds);
        return;
    }
    case X_AND: {
        /* weights written after a conjunction belong to its disjunction */
        bool sa = structural_or(c, x->u.bin.a) || x->u.bin.a->k == X_AND;
        bool sb = structural_or(c, x->u.bin.b) || x->u.bin.b->k == X_AND;
        XVarVec *parts = calloc(2, sizeof(XVarVec));
        expand_x(e, x->u.bin.a, sa && !sb ? vary : NULL, vloc, &parts[0]);
        expand_x(e, x->u.bin.b, sb ? vary : NULL, vloc, &parts[1]);
        if (!e->overflow && !e->bad) product(e, parts, 2, x, make_and, out);
        free_parts(parts, 2);
        return;
    }
    case X_DEFAULT: {
        XVarVec *parts = calloc(1, sizeof(XVarVec));
        expand_x(e, x->u.sub, vary, vloc, &parts[0]);
        if (!e->overflow && !e->bad) product(e, parts, 1, x, make_default, out);
        free_parts(parts, 1);
        return;
    }
    case X_STRUCT: {
        size_t n = (size_t) x->u.st.n;
        XVarVec *parts = calloc(n ? n : 1, sizeof(XVarVec));
        for (size_t i = 0; i < n; i++) {
            XField *f = &x->u.st.fields[i];
            expand_x(e, f->value, attr_args(f->attrs, f->nattrs, "vary"), f->loc, &parts[i]);
        }
        if (!e->overflow && !e->bad) product(e, parts, n, x, make_struct, out);
        free_parts(parts, n);
        return;
    }
    case X_LIST: {
        size_t n = (size_t) x->u.list.n + (x->u.list.tail != NULL) + (x->u.list.elem != NULL);
        XVarVec *parts = calloc(n ? n : 1, sizeof(XVarVec));
        size_t k = 0;
        for (int i = 0; i < x->u.list.n; i++) expand_x(e, x->u.list.items[i], NULL, vloc, &parts[k++]);
        if (x->u.list.tail) expand_x(e, x->u.list.tail, NULL, vloc, &parts[k++]);
        if (x->u.list.elem) expand_x(e, x->u.list.elem, NULL, vloc, &parts[k++]);
        if (!e->overflow && !e->bad) product(e, parts, n, x, make_list, out);
        free_parts(parts, n);
        return;
    }
    default: {
        XVar v = { x, 1, 0, 0 };
        VEC_PUSH(*out, v);
        return;
    }
    }
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

/* --- arithmetic ------------------------------------------------------------------------------- */

static TriNode *wrap_path(Content *c, const U32Vec *path, TriNode *value);

/* Turns a build's arithmetic into constraints on `out`, the structure it
 * built: each tag the expression uses gets its path there. False (with a
 * diagnostic) if a tag is bound nowhere else. */
static bool resolve_ariths(Content *c, Build *b, TriNode *out, ArithVec *dst, Loc loc, const char *who)
{
    bool ok = true;
    for (size_t i = 0; i < b->ariths.n; i++) {
        ArithRec r = { { 0 }, b->ariths.v[i].expr, { 0 } };
        for (size_t k = 0; k < b->ariths.v[i].path.n; k++) VEC_PUSH(r.path, b->ariths.v[i].path.v[k]);
        SymVec names = { 0 };
        arith_tags(r.expr, &names);
        for (size_t t = 0; t < names.n; t++) {
            TagPath tp = { names.v[t], { 0 } };
            bool found = false;
            for (size_t q = 0; q < b->tags.n && !found; q++) {
                if (b->tags.v[q].name != names.v[t]) continue;
                TriNode *mapped = deref(c, b->tags.v[q].node)->cpy;      /* valid: copy_out just ran */
                U32Vec cur = { 0 };
                U64Map seen = { 0 };
                find_tag_paths(c, out, mapped, &cur, &tp.path, &seen);
                VEC_FREE(cur);
                u64map_free(&seen);
                found = tp.path.n > 0 && !(tp.path.n == 1 && tp.path.v[0] == TRI_BOTTOM);
            }
            if (!found) {
                diag(c, true, loc, "%s: the tag %s in %s is not bound to a field", who, names.v[t],
                     r.expr->k == X_INTERP ? "an interpolation" : "arithmetic");
                ok = false;
            }
            VEC_PUSH(r.tags, tp);
        }
        VEC_FREE(names);
        VEC_PUSH(*dst, r);
        c->narith++;
    }
    return ok;
}

static void copy_arith(ArithVec *dst, const ArithRec *src)
{
    ArithRec r = { { 0 }, src->expr, { 0 } };
    for (size_t k = 0; k < src->path.n; k++) VEC_PUSH(r.path, src->path.v[k]);
    for (size_t t = 0; t < src->tags.n; t++) {
        TagPath tp = { src->tags.v[t].name, { 0 } };
        for (size_t k = 0; k < src->tags.v[t].path.n; k++) VEC_PUSH(tp.path, src->tags.v[t].path.v[k]);
        VEC_PUSH(r.tags, tp);
    }
    VEC_PUSH(*dst, r);
}

/* A constraint as found in a structure: the record and where it applies. */
typedef struct { const ArithRec *rec; U32Vec prefix; } ArithUse;
typedef VEC(ArithUse) ArithUses;

static void collect_ariths(Content *c, TriNode *n, U32Vec *path, ArithUses *out, uint32_t cg)
{
    if (n->cpygen == cg) return;
    n->cpygen = cg;
    TypeInfo *ti = &c->types.v[n->type];
    for (size_t i = 0; i < ti->ariths.n; i++) {
        ArithUse u = { &ti->ariths.v[i], { 0 } };
        for (size_t k = 0; k < path->n; k++) VEC_PUSH(u.prefix, path->v[k]);
        VEC_PUSH(*out, u);
    }
    if (n->flags & NF_DIM) return;
    for (uint32_t i = 0; i < n->narcs; i++) {
        VEC_PUSH(*path, n->arcs[i].feat);
        collect_ariths(c, n->arcs[i].val, path, out, cg);
        path->n--;
    }
}

static TriNode *node_at_prefixed(TriNode *root, const U32Vec *prefix, const U32Vec *path)
{
    TriNode *n = node_at(root, prefix->v, prefix->n);
    return n ? node_at(n, path->v, path->n) : NULL;
}

typedef struct { TriNode *root; const ArithUse *use; Content *c; } ALookup;

static bool arith_lookup(void *ctx, Sym tag, Quantity *q)
{
    ALookup *l = ctx;
    for (size_t i = 0; i < l->use->rec->tags.n; i++) {
        if (l->use->rec->tags.v[i].name != tag) continue;
        TriNode *n = node_at_prefixed(l->root, &l->use->prefix, &l->use->rec->tags.v[i].path);
        if (!n || !(n->flags & NF_DIM)) return false;
        *q = quantity_of(l->c->types.v[n->type].dim, n->lo, n->hi);
        return true;
    }
    return false;
}

/* --- interpolation --------------------------------------------------------------------------- */

/* A string's value as content would write it: an atom if some enum lists it,
 * else text. */
static TriNode *string_node(Content *c, TriArena *a, const char *bytes, size_t n)
{
    Sym v = string_canonical(c, bytes, n);
    uint32_t t = type_lookup(c, v);
    if (!c->tdl && (t == TRI_BOTTOM || (c->types.v[t].kind == TK_ATOM && c->types.v[t].parents.n == 1 &&
                                        c->types.v[t].parents.v[0] == c->atomroot)))
        return leaf_new(c, a, c->dimtype[DIM_TEXT], (int64_t) (intptr_t) v, (int64_t) (intptr_t) v);
    return node_new(c, a, t);
}

static TriNode *tag_node(ALookup *l, Sym tag)
{
    for (size_t i = 0; i < l->use->rec->tags.n; i++)
        if (l->use->rec->tags.v[i].name == tag)
            return node_at_prefixed(l->root, &l->use->prefix, &l->use->rec->tags.v[i].path);
    return NULL;
}

/* Writes a value's text: a string's contents, an atom's name, a number as
 * content writes it. ARITH_UNKNOWN while it isn't concrete. */
static const char *node_text(Content *c, TriNode *n, Buf *out)
{
    if (n->flags & NF_DIM) {
        if (n->lo != n->hi) return ARITH_UNKNOWN;
        int dim = c->types.v[n->type].dim;
        if (dim == DIM_TEXT) string_decode((const char *) (intptr_t) n->lo, out);
        else units_format(out, dim, n->lo);
        return NULL;
    }
    TypeInfo *ti = &c->types.v[n->type];
    if (n->narcs || ti->feats.n) return "a structure can't be interpolated into a string";
    if (ti->kind == TK_ATOM && is_leaf(c, n->type)) { string_decode(ti->name, out); return NULL; }
    if (n->type == c->top) return ARITH_UNKNOWN;
    const U32Vec *leaves = enum_leaves(c, n->type);
    for (size_t i = 0; i < leaves->n; i++)
        if (c->types.v[leaves->v[i]].kind != TK_ATOM) return "only strings, atoms and numbers can be interpolated";
    return ARITH_UNKNOWN;                    /* an enum: an atom of it, once known */
}

static bool arith_lookup(void *ctx, Sym tag, Quantity *q);

/* Writes an interpolated string. lookup is an ALookup, or NULL when it has
 * no tags. Returns NULL, ARITH_UNKNOWN until every part is concrete, or what
 * is wrong. */
static const char *interp_eval(Content *c, const X *x, void *lookup, Buf *out)
{
    ALookup *l = lookup;
    buf_puts(out, "");
    for (int i = 0; i <= x->u.in.n; i++) {
        buf_puts(out, x->u.in.lits[i]);
        if (i == x->u.in.n) break;
        const X *e = x->u.in.parts[i];
        const char *err = NULL;
        if (e->k == X_ATOM) string_decode(e->u.name, out);
        else if (e->k == X_INTERP) err = interp_eval(c, e, lookup, out);
        else if (e->k == X_TAG) {
            TriNode *n = l ? tag_node(l, e->u.name) : NULL;
            err = n ? node_text(c, n, out) : ARITH_UNKNOWN;
        } else if (e->k == X_NUM || e->k == X_ARITH) {
            Quantity q;
            err = arith_eval(e, arith_lookup, l, &q);
            if (!err && q.lo != q.hi) err = ARITH_UNKNOWN;
            if (!err) {
                int dim = q.dim >= 0 ? q.dim : quantity_kind_for(&q);
                Quantity conv;
                if (dim < 0 || quantity_to(&q, dim, &conv)) err = "no quantity has this dimension";
                else units_format(out, dim, conv.lo);
            }
        } else err = "only tags, strings, numbers and arithmetic can be interpolated";
        if (err) return err;
    }
    return NULL;
}

/* Backward narrowings found while settling: each tag's new interval. The
 * lookup comes first, so one context serves both callbacks. */
typedef struct { ALookup l; NodeVec *vals; PathVec *where; } ANarrow;

static void arith_narrowed(void *ctx, Sym tag, const Quantity *q)
{
    ANarrow *an = ctx;
    const ArithUse *u = an->l.use;
    for (size_t i = 0; i < u->rec->tags.n; i++) {
        if (u->rec->tags.v[i].name != tag) continue;
        TriNode *n = node_at_prefixed(an->l.root, &u->prefix, &u->rec->tags.v[i].path);
        if (!n || !(n->flags & NF_DIM)) return;
        int64_t lo = q->lo > n->lo ? q->lo : n->lo, hi = q->hi < n->hi ? q->hi : n->hi;
        if (lo == n->lo && hi == n->hi) return;       /* nothing new (an empty result is left to unification) */
        U32Vec full = { 0 };
        for (size_t k = 0; k < u->prefix.n; k++) VEC_PUSH(full, u->prefix.v[k]);
        for (size_t k = 0; k < u->rec->tags.v[i].path.n; k++) VEC_PUSH(full, u->rec->tags.v[i].path.v[k]);
        VEC_PUSH(*an->where, full);
        VEC_PUSH(*an->vals, leaf_new(an->l.c, an->l.c->scratch, n->type, q->lo, q->hi));
        return;
    }
}

static void set_arith_failure(Content *c, TriFailure *fail, const U32Vec *prefix, const U32Vec *path, const ArithRec *rec,
                              const char *why)
{
    if (!fail) return;
    memset(fail, 0, sizeof *fail);
    U32Vec full = { 0 };
    for (size_t k = 0; k < prefix->n; k++) VEC_PUSH(full, prefix->v[k]);
    for (size_t k = 0; k < path->n; k++) VEC_PUSH(full, path->v[k]);
    Buf p = { 0 }, e = { 0 };
    path_format(c, &p, full.v, full.n);
    x_print(&e, rec->expr);
    snprintf(fail->path, sizeof fail->path, "%s", p.s);
    snprintf(fail->left, sizeof fail->left, "%s", e.s);
    snprintf(fail->right, sizeof fail->right, "%s", why);
    buf_free(&p);
    buf_free(&e);
    VEC_FREE(full);
}

/* Propagates arithmetic: every constraint in `root` (those of its nodes'
 * types, and `extra`, given at the root) narrows its field to the value its
 * expression gives, until nothing changes. Returns the new root in `arena`,
 * root itself if nothing changed, or NULL with *fail if a constraint can't
 * hold. */
static TriNode *settle_arith(Content *c, TriNode *root, const ArithVec *extra, TriArena *arena, TriFailure *fail)
{
    if (!c->narith || !root) return root;
    for (int round = 0; round < 16; round++) {
        ArithUses uses = { 0 };
        U32Vec path = { 0 };
        collect_ariths(c, root, &path, &uses, ++c->cgenctr);
        VEC_FREE(path);
        for (size_t i = 0; extra && i < extra->n; i++) {
            ArithUse u = { &extra->v[i], { 0 } };
            VEC_PUSH(uses, u);
        }
        TriMark m = tri_arena_mark(c->scratch);
        NodeVec vals = { 0 };
        PathVec where = { 0 };
        bool ok = true;
        for (size_t i = 0; i < uses.n && ok; i++) {
            ArithUse *u = &uses.v[i];
            ALookup l = { root, u, c };
            if (u->rec->expr->k == X_INTERP) {
                Buf sb = { 0 };
                const char *ierr = interp_eval(c, u->rec->expr, &l, &sb);
                if (ierr == ARITH_UNKNOWN) { buf_free(&sb); continue; }
                if (ierr) { set_arith_failure(c, fail, &u->prefix, &u->rec->path, u->rec, ierr); buf_free(&sb); ok = false; break; }
                TriNode *val = string_node(c, c->scratch, sb.s ? sb.s : "", sb.len);
                buf_free(&sb);
                TriNode *t = node_at_prefixed(root, &u->prefix, &u->rec->path);
                if (!t) continue;
                bool same = (val->flags & NF_DIM) ? ((t->flags & NF_DIM) && t->lo == t->hi && t->lo == val->lo)
                                                  : (!(t->flags & NF_DIM) && t->type == val->type);
                if (same) continue;
                U32Vec full = { 0 };
                for (size_t k = 0; k < u->prefix.n; k++) VEC_PUSH(full, u->prefix.v[k]);
                for (size_t k = 0; k < u->rec->path.n; k++) VEC_PUSH(full, u->rec->path.v[k]);
                VEC_PUSH(where, full);
                VEC_PUSH(vals, val);
                continue;
            }
            Quantity q;
            const char *err = arith_eval(u->rec->expr, arith_lookup, &l, &q);
            if (err == ARITH_UNKNOWN) continue;
            if (err) { set_arith_failure(c, fail, &u->prefix, &u->rec->path, u->rec, err); ok = false; break; }
            TriNode *t = node_at_prefixed(root, &u->prefix, &u->rec->path);
            if (!t) continue;
            /* the result, in the field's kind (or the kind its dimension has) */
            int tdim = (t->flags & NF_DIM) ? c->types.v[t->type].dim : quantity_kind_for(&q);
            Quantity conv;
            if (tdim < 0 || quantity_to(&q, tdim, &conv)) {
                set_arith_failure(c, fail, &u->prefix, &u->rec->path, u->rec,
                                  tdim < 0 ? "no quantity has this dimension" : "a value of another dimension");
                ok = false;
                break;
            }
            q = conv;
            if (t->flags & NF_DIM) {
                /* backwards: the field's interval narrows the arguments */
                ANarrow an = { l, &vals, &where };
                arith_narrow(u->rec->expr, quantity_of(tdim, t->lo, t->hi), arith_lookup, &an, arith_narrowed);
                int64_t lo = q.lo > t->lo ? q.lo : t->lo, hi = q.hi < t->hi ? q.hi : t->hi;
                if (lo > hi) {
                    Buf d = { 0 };
                    units_format(&d, q.dim, q.lo);
                    if (q.lo != q.hi) { buf_puts(&d, ".."); units_format(&d, q.dim, q.hi); }
                    set_arith_failure(c, fail, &u->prefix, &u->rec->path, u->rec, d.s);
                    buf_free(&d);
                    ok = false;
                    break;
                }
                if (lo == t->lo && hi == t->hi) continue;
                q.lo = lo;
                q.hi = hi;
            } else if (t->type != c->top) {
                set_arith_failure(c, fail, &u->prefix, &u->rec->path, u->rec, "a number where a structure is");
                ok = false;
                break;
            }
            U32Vec full = { 0 };
            for (size_t k = 0; k < u->prefix.n; k++) VEC_PUSH(full, u->prefix.v[k]);
            for (size_t k = 0; k < u->rec->path.n; k++) VEC_PUSH(full, u->rec->path.v[k]);
            VEC_PUSH(where, full);
            VEC_PUSH(vals, leaf_new(c, c->scratch, c->dimtype[q.dim], q.lo, q.hi));
        }
        bool changed = false;
        if (ok && where.n) {
            uint32_t saved = op_begin(c);
            reset_failure(c);
            for (size_t k = 0; k < where.n && ok; k++) ok = unify1(c, root, wrap_path(c, &where.v[k], vals.v[k]));
            if (ok) { root = copy_out(c, arena, root, NULL); changed = true; }
            else if (fail) *fail = *fail_info(c);
            op_end(c, saved);
        }
        for (size_t k = 0; k < where.n; k++) VEC_FREE(where.v[k]);
        VEC_FREE(where);
        VEC_FREE(vals);
        for (size_t k = 0; k < uses.n; k++) VEC_FREE(uses.v[k].prefix);
        VEC_FREE(uses);
        if (arena != c->scratch) tri_arena_release(c->scratch, m);
        if (!ok) return NULL;
        if (!changed) break;
    }
    return root;
}

/* Whether field f of a node of type t is computed by arithmetic. */
static bool arith_target(Content *c, uint32_t t, uint32_t f)
{
    const ArithVec *av = &c->types.v[t].ariths;
    for (size_t i = 0; i < av->n; i++)
        if (av->v[i].path.n == 1 && av->v[i].path.v[0] == f) return true;
    return false;
}

/* Builds two parts of an instance by themselves, for locating conflicts. */
static bool pair_conflicts(Content *c, X *x1, X *x2)
{
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    Build b = { 0 };
    b.c = c; b.ok = true; b.contributor = CONTRIB_INSTANCE; b.owner = TRI_BOTTOM;
    int nerr = c->nerrors;
    size_t ndiag = c->diags.n;
    TriNode *x = build_raw(&b, x1);
    TriNode *y = x ? build_raw(&b, x2) : NULL;
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

static void free_recs(DefVec *v)
{
    for (size_t k = 0; k < v->n; k++) VEC_FREE(v->v[k].path);
    VEC_FREE(*v);
}

/* Builds one variant of an instance from one expression per declaration.
 * With `report`, a failure is diagnosed; otherwise it leaves no trace. */
static bool build_variant(Content *c, uint32_t i, X **xs, InstVariant *out, bool report)
{
    InstInfo *in = &c->insts.v[i];
    int nerr = c->nerrors;
    size_t ndiag = c->diags.n;
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    Build b = { 0 };
    b.c = c; b.ok = true; b.contributor = CONTRIB_INSTANCE; b.owner = TRI_BOTTOM; b.record = true;
    b.direct = true;
    TriNode *r = NULL;
    for (size_t k = 0; k < in->decls.n && b.ok; k++) {
        Decl *d = in->decls.v[k];
        TriNode *x = build_raw(&b, xs[k]);
        if (!x) break;
        if (!r) { r = x; continue; }
        reset_failure(c);
        if (!unify1(c, r, x)) {
            Decl *partner = NULL;
            if (report)
                for (size_t j = 0; j < k && !partner; j++)
                    if (pair_conflicts(c, xs[j], xs[k])) partner = in->decls.v[j];
            if (partner)
                diag(c, true, d->loc, "%s: conflict at %s: %s vs %s, with the declaration at %s:%d",
                     in->name, fail_info(c)->path, fail_info(c)->left, fail_info(c)->right,
                     partner->loc.file, partner->loc.line);
            else
                diag(c, true, d->loc, "%s: conflict at %s: %s vs %s, with earlier declarations",
                     in->name, fail_info(c)->path, fail_info(c)->left, fail_info(c)->right);
            b.ok = false;
        }
        in = &c->insts.v[i];
    }
    in = &c->insts.v[i];
    if (b.ok && r) {
        bool closed;
        TriNode *pat = copy_out(c, c->spec, r, &closed);
        if (!closed) {
            diag(c, true, in->decls.v[0]->loc, "%s: a field is not appropriate for its type", in->name);
            b.ok = false;
        } else {
            out->pattern = pat;
            for (size_t t = 0; t < b.tags.n; t++) {
                TriNode *tn = deref(c, b.tags.v[t].node);
                TriNode *mapped = tn->cpy;   /* valid: copy_out just ran */
                TagPath tp = { b.tags.v[t].name, { 0 } };
                U32Vec cur = { 0 };
                U64Map seen = { 0 };
                find_tag_paths(c, pat, mapped, &cur, &tp.path, &seen);
                if (tp.path.n == 1 && tp.path.v[0] == TRI_BOTTOM) tp.path.n = 0;
                VEC_FREE(cur);
                u64map_free(&seen);
                VEC_PUSH(out->tags, tp);
            }
            for (size_t d = 0; d < b.defs.n; d++) add_default(&out->defaults, &b.defs.v[d], NULL, 0);
            for (size_t d = 0; d < b.varies.n; d++) add_default(&out->varies, &b.varies.v[d], NULL, 0);
            if (!resolve_ariths(c, &b, pat, &out->ariths, in->decls.v[0]->loc, in->name)) b.ok = false;
        }
    } else if (b.ok) {
        b.ok = false;
    }
    free_recs(&b.defs);
    free_recs(&b.varies);
    build_free(&b);
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    if (b.ok && c->narith) {
        TriFailure f;
        TriNode *settled = settle_arith(c, out->pattern, &out->ariths, c->spec, &f);
        if (!settled) {
            diag(c, true, c->insts.v[i].decls.v[0]->loc, "%s: arithmetic at %s: %s gives %s", c->insts.v[i].name,
                 f.path, f.left, f.right);
            b.ok = false;
        } else {
            out->pattern = settled;
        }
    }
    if (!report) {
        while (c->diags.n > ndiag) free(c->diags.v[--c->diags.n].msg);
        c->nerrors = nerr;
    }
    return b.ok;
}

static void variant_free(InstVariant *v)
{
    free_recs(&v->specvaries);
    free_ariths(&v->ariths);
    for (size_t k = 0; k < v->tags.n; k++) VEC_FREE(v->tags.v[k].path);
    VEC_FREE(v->tags);
    free_recs(&v->defaults);
    free_recs(&v->varies);
    for (size_t k = 0; k < v->varpaths.n; k++) VEC_FREE(v->varpaths.v[k]);
    VEC_FREE(v->varpaths);
}

#define DEFAULT_MAX_VARIANTS 64

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
    size_t nd = in->decls.n;
    Expand e = { c, DEFAULT_MAX_VARIANTS, 0, false, false, false };
    for (size_t k = 0; k < nd; k++) {
        const char *lim = attr_args(in->decls.v[k]->attrs, in->decls.v[k]->nattrs, "variants");
        if (lim) {
            long n = strtol(lim, NULL, 10);
            if (n < 1) diag(c, true, in->decls.v[k]->loc, "%s: @variants needs a positive count", in->name);
            else e.cap = (size_t) n;
        }
    }
    /* each declaration's variants, then their product */
    XVarVec *parts = calloc(nd ? nd : 1, sizeof(XVarVec));
    for (size_t k = 0; k < nd && !e.overflow && !e.bad; k++) {
        Decl *d = c->insts.v[i].decls.v[k];
        const char *vary = attr_args(d->attrs, d->nattrs, "vary");
        e.vary_used = false;
        expand_x(&e, d->value, vary, d->loc, &parts[k]);
        if (vary && !e.vary_used && !e.bad) {
            diag(c, true, d->loc, "%s: @vary(%s) after a declaration weights its top-level alternatives, "
                 "and this declaration has none (put it after the field)", c->insts.v[i].name, vary);
            e.bad = true;
        }
    }
    XVarVec all = { 0 };
    if (!e.overflow && !e.bad) {
        X **xs = malloc(sizeof(X *) * (nd ? nd : 1));
        size_t *ix = calloc(nd ? nd : 1, sizeof(size_t));
        for (;;) {
            /* one combination: a pseudo-variant whose x is unused; xs are kept per combination */
            XVar v = { NULL, 1, 0, 0 };
            for (size_t k = 0; k < nd; k++) {
                XVar *p = &parts[k].v[ix[k]];
                v.weight = mul_sat(v.weight, p->weight);
                v.hasdef |= p->hasdef;
                v.tookdef |= p->tookdef;
            }
            /* the combination's expressions, as a list X holding one item per declaration */
            X *combo = x_new(c, X_LIST, noloc);
            combo->u.list.n = (int) nd;
            combo->u.list.items = arena_alloc(c->load, sizeof(X *) * (nd ? nd : 1));
            for (size_t k = 0; k < nd; k++) combo->u.list.items[k] = parts[k].v[ix[k]].x;
            v.x = combo;
            VEC_PUSH(all, v);
            if (all.n > e.cap) { e.overflow = true; break; }
            size_t k = 0;
            while (k < nd && ++ix[k] == parts[k].n) ix[k++] = 0;
            if (k == nd) break;
        }
        free(xs);
        free(ix);
    }
    free_parts(parts, nd);
    in = &c->insts.v[i];
    if (e.overflow)
        diag(c, true, in->decls.v[0]->loc, "%s expands to more than %zu variants; raise the limit with @variants(n)",
             in->name, e.cap);
    if (e.overflow || e.bad) {
        VEC_FREE(all);
        in->pstate = 3;
        return false;
    }
    for (size_t k = 0; k < all.n; k++) {
        InstVariant v = { 0 };
        v.weight = all.v[k].weight;
        v.hasdef = all.v[k].hasdef;
        v.tookdef = all.v[k].tookdef;
        if (build_variant(c, i, all.v[k].x->u.list.items, &v, false)) VEC_PUSH(c->insts.v[i].vars, v);
        else variant_free(&v);
    }
    in = &c->insts.v[i];
    if (!in->vars.n && all.n) {
        InstVariant v = { 0 };
        build_variant(c, i, all.v[0].x->u.list.items, &v, true);    /* diagnoses the first variant */
        variant_free(&v);
    }
    VEC_FREE(all);
    in = &c->insts.v[i];
    if (!in->vars.n) { in->pstate = 3; return false; }
    in->pattern = in->vars.v[0].pattern;
    for (size_t k = 1; k < in->vars.n; k++) in->pattern = fs_generalise(c, c->spec, in->pattern, in->vars.v[k].pattern);
    in->pstate = 2;
    return true;
}

/* --- specs: defaults and variation ---------------------------------------------------------- */

static int cmp_path(const U32Vec *a, const U32Vec *b)
{
    size_t n = a->n < b->n ? a->n : b->n;
    for (size_t i = 0; i < n; i++)
        if (a->v[i] != b->v[i]) return a->v[i] < b->v[i] ? -1 : 1;
    return a->n < b->n ? -1 : a->n > b->n;
}

/* Gathers the default (or @vary) records of the types of every node, with
 * their paths made absolute. */
static void collect_recs(Content *c, TriNode *n, U32Vec *path, DefVec *out, uint32_t cg, bool vary)
{
    if (n->cpygen == cg) return;          /* visited (a shared node) */
    n->cpygen = cg;
    TypeInfo *ti = &c->types.v[n->type];
    DefVec *own = vary ? &ti->varies : &ti->defaults;
    for (size_t i = 0; i < own->n; i++) add_default(out, &own->v[i], path->v, path->n);
    if (n->flags & NF_DIM) return;
    for (uint32_t i = 0; i < n->narcs; i++) {
        VEC_PUSH(*path, n->arcs[i].feat);
        collect_recs(c, n->arcs[i].val, path, out, cg, vary);
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
 * `arena`, or NULL if they do not all fit. In the scratch arena, the result
 * lives until the caller releases its own mark. */
static TriNode *try_defaults(Content *c, TriNode *root, DefaultRec **ds, size_t n, TriArena *arena)
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
        r = copy_out(c, arena, root, &closed);
        if (!closed) r = NULL;
    }
    while (c->diags.n > ndiag) free(c->diags.v[--c->diags.n].msg);
    c->nerrors = nerr;
    free_recs(&b.defs);
    free_recs(&b.varies);
    build_free(&b);
    op_end(c, saved);
    if (arena != c->scratch) tri_arena_release(c->scratch, m);
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

typedef struct {
    InstInfo *in;            /* notes and warnings go here; NULL to stay quiet */
    const char *prefix;      /* for notes, e.g. "variant 2: " */
    TriFailure *fail;        /* if set, where no alternative fits */
} Notes;

static void note(Notes *ns, Buf *b)
{
    if (ns->in) {
        Buf full = { 0 };
        buf_printf(&full, "%s%s", ns->prefix ? ns->prefix : "", b->s);
        bool dup = false;
        for (size_t k = 0; k < ns->in->notes.n && !dup; k++) dup = strcmp(ns->in->notes.v[k], full.s) == 0;
        if (dup) buf_free(&full);
        else VEC_PUSH(ns->in->notes, full.s);
    }
    b->len = 0;
}

static int cmp_defptr(const void *a, const void *b)
{
    const DefaultRec *x = *(DefaultRec *const *) a, *y = *(DefaultRec *const *) b;
    return cmp_path(&x->path, &y->path);
}

/* YADU-style default resolution: per path, the most specific defaults first;
 * one overridden by a more specific default stays overridden; conflicting
 * defaults from incomparable types are both dropped. */
static TriNode *resolve_defaults(Content *c, TriNode *root, const DefVec *instdefs, Notes *ns, TriArena *arena)
{
    DefVec all = { 0 };
    U32Vec path = { 0 };
    collect_recs(c, root, &path, &all, ++c->cgenctr, false);
    VEC_FREE(path);
    for (size_t k = 0; k < instdefs->n; k++) add_default(&all, &instdefs->v[k], NULL, 0);

    DefaultRec **order = malloc(sizeof(DefaultRec *) * (all.n ? all.n : 1));
    for (size_t k = 0; k < all.n; k++) order[k] = &all.v[k];
    qsort(order, all.n, sizeof(DefaultRec *), cmp_defptr);   /* stable enough: groups by path */

    Buf nb = { 0 };
    size_t g0 = 0;
    while (g0 < all.n) {
        size_t g1 = g0;
        while (g1 < all.n && cmp_path(&order[g1]->path, &order[g0]->path) == 0) g1++;
        size_t gn = g1 - g0;
        bool *done = calloc(gn, 1);
        VEC(DefaultRec *) dropped = { 0 };
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
            /* A default overridden by a more specific one stays overridden even
             * when that one was dropped in a tie. */
            size_t kept = 0;
            for (size_t q = 0; q < nr; q++) {
                bool overridden = false;
                for (size_t k = 0; k < dropped.n && !overridden; k++) {
                    DefaultRec *pair[2] = { ready[q], dropped.v[k] };
                    overridden = more_specific(c, dropped.v[k]->contributor, ready[q]->contributor) &&
                                 !try_defaults(c, root, pair, 2, arena);
                }
                if (overridden) {
                    buf_printf(&nb, "%s: default from %s is overridden by a more specific default",
                               pth.s, contributor_name(c, ready[q]->contributor));
                    note(ns, &nb);
                } else {
                    ready[kept++] = ready[q];
                }
            }
            nr = kept;
            if (!nr) continue;
            TriNode *res = try_defaults(c, root, ready, nr, arena);
            if (res) {
                root = res;
                for (size_t q = 0; q < nr; q++) {
                    buf_printf(&nb, "%s <- %s (default)", pth.s, contributor_name(c, ready[q]->contributor));
                    note(ns, &nb);
                }
                continue;
            }
            DefaultRec **compat = malloc(sizeof(DefaultRec *) * nr);
            size_t nc = 0;
            for (size_t q = 0; q < nr; q++) {
                if (try_defaults(c, root, &ready[q], 1, arena)) compat[nc++] = ready[q];
                else {
                    buf_printf(&nb, "%s: default from %s loses to a more specific value",
                               pth.s, contributor_name(c, ready[q]->contributor));
                    note(ns, &nb);
                }
            }
            if (nc == 1) {
                root = try_defaults(c, root, compat, 1, arena);
                buf_printf(&nb, "%s <- %s (default)", pth.s, contributor_name(c, compat[0]->contributor));
                note(ns, &nb);
            } else if (nc > 1) {
                Buf names = { 0 };
                for (size_t q = 0; q < nc; q++) {
                    if (q) buf_puts(&names, ", ");
                    buf_puts(&names, contributor_name(c, compat[q]->contributor));
                }
                if (ns->in) {
                    diag(c, false, ns->in->decls.v[0]->loc, "%s: %sconflicting defaults for %s from %s; both dropped",
                         ns->in->name, ns->prefix ? ns->prefix : "", pth.s, names.s);
                    Buf lb = { 0 };
                    buf_printf(&lb, "dropped defaults: %s: %s%s from %s", ns->in->name, ns->prefix ? ns->prefix : "",
                               pth.s, names.s);
                    VEC_PUSH(c->buildlog, lb.s);
                }
                for (size_t q = 0; q < nc; q++) VEC_PUSH(dropped, compat[q]);
                buf_printf(&nb, "%s: conflicting defaults from %s dropped", pth.s, names.s);
                note(ns, &nb);
                buf_free(&names);
            }
            free(compat);
        }
        buf_free(&pth);
        VEC_FREE(dropped);
        free(done);
        free(ready);
        g0 = g1;
    }
    buf_free(&nb);
    free(order);
    free_recs(&all);
    return root;
}

/* Whether a node is a variation point: an enum or a disjunction left open, or
 * a bounded range. Free text and referents stay open: they are bound at runtime. */
static int variation_kind(Content *c, TriNode *n)
{
    TypeInfo *ti = &c->types.v[n->type];
    if (ti->kind == TK_DIM) {
        if (n->lo == n->hi || ti->dim == DIM_REF || ti->dim == DIM_TEXT) return 0;
        return n->lo == TRI_NINF || n->hi == TRI_INF ? -1 : 1;
    }
    if (ti->isdisj) return 1;
    if (!is_subtype(c, n->type, c->atomroot)) return 0;
    for (size_t k = 0; k < ti->children.n; k++)
        if (c->types.v[ti->children.v[k]].kind != TK_ALT) return 1;
    return 0;
}

/* Records variation points in path order. Returns false (with a diagnostic
 * when `in` is given) if a number is open without bounds. */
static bool collect_variation(Content *c, TriNode *n, U32Vec *path, PathVec *out, InstInfo *in,
                              const char *prefix, uint32_t cg)
{
    if (n->cpygen == cg) return true;     /* visited (a shared node) */
    n->cpygen = cg;
    bool ok = true;
    int v = variation_kind(c, n);
    if (v < 0) {
        if (in) {
            Buf p = { 0 };
            path_format(c, &p, path->v, path->n);
            diag(c, true, in->decls.v[0]->loc, "%s: %s%s is not concrete and has no bounds to vary within",
                 in->name, prefix ? prefix : "", p.s);
            buf_free(&p);
        }
        ok = false;
    } else if (v > 0) {
        U32Vec copy = { 0 };
        for (size_t i = 0; i < path->n; i++) VEC_PUSH(copy, path->v[i]);
        VEC_PUSH(*out, copy);
    }
    if (n->flags & NF_DIM) return ok;
    for (uint32_t i = 0; i < n->narcs; i++) {
        TriNode *v = n->arcs[i].val;
        /* a derived value (@fn, arithmetic, or an interpolation, which may be an
         * enum's atom) is computed, not drawn */
        bool open = !(v->flags & NF_DIM) || v->lo != v->hi;
        if (open && (((v->flags & NF_DIM) && field_attr(c, n->type, n->arcs[i].feat, "fn")) ||
                     arith_target(c, n->type, n->arcs[i].feat)))
            continue;
        if (open && c->varskip) {
            bool skip = false;
            for (size_t q = 0; q < c->varskip->n && !skip; q++) {
                const U32Vec *tp = &c->varskip->v[q].path;
                skip = tp->n == path->n + 1 && tp->v[path->n] == n->arcs[i].feat &&
                       (path->n == 0 || memcmp(tp->v, path->v, path->n * sizeof(uint32_t)) == 0);
            }
            if (skip) continue;
        }
        VEC_PUSH(*path, n->arcs[i].feat);
        ok &= collect_variation(c, v, path, out, in, prefix, cg);
        path->n--;
    }
    return ok;
}

static void alternatives_fitting(Content *c, TriNode *root, const U32Vec *path, uint32_t d, void *outv);

/* Resolves open disjunctions that only one alternative fits. Returns the new
 * root (in the load arena), or NULL if some disjunction has no fitting
 * alternative. Sets *changed when it resolved any. */
static TriNode *force_alternatives(Content *c, TriNode *root, Notes *ns, bool *changed, TriArena *arena)
{
    *changed = false;
    TriMark m = tri_arena_mark(c->scratch);
    PathVec points = { 0 };
    U32Vec path = { 0 };
    collect_variation(c, root, &path, &points, NULL, NULL, ++c->cgenctr);
    VEC_FREE(path);
    VEC(TriNode *) vals = { 0 };
    PathVec forced = { 0 };
    bool ok = true;
    Buf nb = { 0 };
    for (size_t k = 0; k < points.n && ok; k++) {
        TriNode *n = node_at(root, points.v[k].v, points.v[k].n);
        if (!c->types.v[n->type].isdisj) continue;
        VEC(TriNode *) fit = { 0 };
        alternatives_fitting(c, root, &points.v[k], n->type, &fit);
        path_format(c, &nb, points.v[k].v, points.v[k].n);
        if (fit.n == 1) {
            VEC_PUSH(vals, fit.v[0]);
            VEC_PUSH(forced, points.v[k]);
            buf_printf(&nb, " <- %s (the only alternative that fits)", c->types.v[fit.v[0]->type].name);
            note(ns, &nb);
        } else if (!fit.n) {
            if (ns->in)
                diag(c, true, ns->in->decls.v[0]->loc, "%s: %sno alternative of %s fits at %s", ns->in->name,
                     ns->prefix ? ns->prefix : "", c->types.v[n->type].name, nb.s);
            if (ns->fail) {
                memset(ns->fail, 0, sizeof *ns->fail);
                snprintf(ns->fail->path, sizeof ns->fail->path, "%s", nb.s);
                snprintf(ns->fail->left, sizeof ns->fail->left, "no alternative of %s fits", c->types.v[n->type].name);
            }
            ok = false;
        }
        nb.len = 0;
        VEC_FREE(fit);
    }
    buf_free(&nb);
    if (ok && forced.n) {
        uint32_t saved = op_begin(c);
        reset_failure(c);
        for (size_t k = 0; k < forced.n && ok; k++) ok = unify1(c, root, wrap_path(c, &forced.v[k], vals.v[k]));
        if (ok) root = copy_out(c, arena, root, NULL);
        op_end(c, saved);
        *changed = ok;
    }
    for (size_t k = 0; k < points.n; k++) VEC_FREE(points.v[k]);
    VEC_FREE(points);
    VEC_FREE(forced);
    VEC_FREE(vals);
    tri_arena_release(c->scratch, m);
    return ok ? root : NULL;
}

/* Resolves, in a runtime structure, every open disjunction that only one
 * alternative fits; NULL (with the failure) if one has none. Content without
 * disjunctions of structures costs nothing. */
TriNode *settle_alternatives(Content *c, TriNode *root, TriArena *arena, TriFailure *fail)
{
    if (!c->disjs.n || !root) return root;
    TriFailure local;
    Notes ns = { NULL, NULL, fail ? fail : &local };
    for (int round = 0; round < 64 && root; round++) {
        bool changed;
        root = force_alternatives(c, root, &ns, &changed, arena);
        if (!changed) break;
    }
    return root;
}

TriNode *settle(Content *c, TriNode *root, const ArithVec *extra, TriArena *arena, TriFailure *fail)
{
    if (!root || (!c->disjs.n && !c->narith)) return root;
    for (int round = 0; round < 8 && root; round++) {
        TriNode *before = root;
        root = settle_alternatives(c, root, arena, fail);
        if (root) root = settle_arith(c, root, extra, arena, fail);
        if (root == before) break;
    }
    return root;
}

bool inst_spec(Content *c, uint32_t i)
{
    InstInfo *in = &c->insts.v[i];
    if (in->sstate) return in->sstate == 2;
    in->sstate = 3;
    if (!inst_pattern(c, i)) return false;
    in = &c->insts.v[i];
    size_t nv = in->vars.n;
    bool multi = nv > 1;
    TriNode **roots = calloc(nv, sizeof(TriNode *));
    for (size_t k = 0; k < nv; k++) {
        char prefix[32];
        snprintf(prefix, sizeof prefix, "variant %zu: ", k + 1);
        Notes ns = { &c->insts.v[i], multi ? prefix : NULL, NULL };
        InstVariant *v = &c->insts.v[i].vars.v[k];
        TriNode *r = resolve_defaults(c, v->pattern, &v->defaults, &ns, c->load);
        for (int round = 0; r && round < 64; round++) {
            TriFailure af;
            TriNode *before = r;
            r = settle_arith(c, r, &c->insts.v[i].vars.v[k].ariths, c->load, &af);
            if (!r) {
                diag(c, true, c->insts.v[i].decls.v[0]->loc, "%s: %sarithmetic at %s: %s gives %s", c->insts.v[i].name,
                     multi ? prefix : "", af.path, af.left, af.right);
                break;
            }
            bool changed;
            r = force_alternatives(c, r, &ns, &changed, c->load);
            if (!r || (!changed && r == before)) break;
            r = resolve_defaults(c, r, &c->insts.v[i].vars.v[k].defaults, &ns, c->load);
        }
        roots[k] = r;
    }
    in = &c->insts.v[i];
    /* defaults among structural alternatives choose variants */
    bool *alive = malloc(nv);
    for (size_t k = 0; k < nv; k++) alive[k] = true;
    for (int d = 0; d < 64; d++) {
        uint64_t bit = 1ull << d;
        bool took = false;
        for (size_t k = 0; k < nv; k++)
            if (alive[k] && (in->vars.v[k].hasdef & bit) && (in->vars.v[k].tookdef & bit)) took = true;
        if (!took) continue;
        for (size_t k = 0; k < nv; k++)
            if ((in->vars.v[k].hasdef & bit) && !(in->vars.v[k].tookdef & bit)) alive[k] = false;
    }
    bool ok = true;
    for (size_t k = 0; k < nv; k++) if (!roots[k]) ok = false;
    size_t nalive = 0;
    for (size_t k = 0; k < nv; k++) nalive += alive[k];
    if (nalive < nv) {
        Buf nb = { 0 };
        buf_puts(&nb, "(variant): defaults among alternatives keep variant");
        for (size_t k = 0, first = 1; k < nv; k++)
            if (alive[k]) { buf_printf(&nb, "%s %zu", first ? "" : ",", k + 1); first = 0; }
        VEC_PUSH(c->insts.v[i].notes, nb.s);
    }
    TriNode *gen = NULL;
    for (size_t k = 0; k < nv && ok; k++) {
        if (!alive[k]) continue;
        InstVariant *v = &c->insts.v[i].vars.v[k];
        char prefix[32];
        snprintf(prefix, sizeof prefix, "variant %zu: ", k + 1);
        U32Vec path = { 0 };
        c->varskip = &v->ariths;
        ok &= collect_variation(c, roots[k], &path, &v->varpaths, &c->insts.v[i], multi ? prefix : NULL, ++c->cgenctr);
        c->varskip = NULL;
        VEC_FREE(path);
        /* freeze into the spec arena */
        TriMark fm = tri_arena_mark(c->scratch);
        uint32_t saved = op_begin(c);
        v->spec = copy_out(c, c->spec, roots[k], NULL);
        op_end(c, saved);
        tri_arena_release(c->scratch, fm);
        VEC_PUSH(c->insts.v[i].specvars, (uint32_t) k);
        gen = gen ? fs_generalise(c, c->spec, gen, v->spec) : v->spec;
    }
    free(alive);
    free(roots);
    in = &c->insts.v[i];
    /* variation: which variant, then each point, in order of first appearance */
    Buf nb = { 0 };
    if (in->specvars.n > 1) VEC_PUSH(in->variation, strdup("(variant)"));
    for (size_t s = 0; s < in->specvars.n; s++) {
        InstVariant *v = &in->vars.v[in->specvars.v[s]];
        for (size_t k = 0; k < v->varpaths.n; k++) {
            path_format(c, &nb, v->varpaths.v[k].v, v->varpaths.v[k].n);
            bool dup = false;
            for (size_t q = 0; q < in->variation.n && !dup; q++) dup = strcmp(in->variation.v[q], nb.s) == 0;
            if (!dup) VEC_PUSH(in->variation, strdup(nb.s));
            nb.len = 0;
        }
    }
    for (size_t k = 0; k < in->variation.n; k++) {
        buf_printf(&nb, "%s <- seed", in->variation.v[k]);
        VEC_PUSH(in->notes, strdup(nb.s));
        nb.len = 0;
    }
    buf_free(&nb);
    if (!ok) return false;
    in->spec = gen;
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

/* An index drawn with probability proportional to its weight; uniform if all
 * weights are zero. */
static size_t draw_weighted(uint64_t *s, const uint64_t *w, size_t n)
{
    uint64_t total = 0;
    for (size_t i = 0; i < n; i++) total = total + w[i] < total ? UINT64_MAX : total + w[i];
    if (!total) return (size_t) draw(s, n);
    uint64_t r = draw(s, total);
    for (size_t i = 0; i < n; i++) {
        if (r < w[i]) return i;
        r -= w[i];
    }
    return n - 1;
}

static uint32_t inst_index(Content *c, const char *name)
{
    uint64_t v;
    if (u64map_get(&c->instidx, (uint64_t) (uintptr_t) intern(c, name), &v)) return (uint32_t) v - 1;
    return TRI_BOTTOM;
}

/* The maximal subtypes of t that are not alternatives: an enum's leaves. */
const U32Vec *enum_leaves(Content *c, uint32_t t)
{
    if (!c->leafcache) c->leafcache = calloc(c->types.n, sizeof(U32Vec *));
    if (c->leafcache[t]) return c->leafcache[t];
    U32Vec *v = calloc(1, sizeof *v);
    U32Vec stack = { 0 };
    U64Map seen = { 0 };
    VEC_PUSH(stack, t);
    while (stack.n) {
        uint32_t u = stack.v[--stack.n];
        TypeInfo *ui = &c->types.v[u];
        size_t kids = 0;
        for (size_t k = 0; k < ui->children.n; k++) {
            uint32_t ch = ui->children.v[k];
            if (c->types.v[ch].kind == TK_ALT) continue;
            kids++;
            if (!u64map_get(&seen, ch, NULL)) { u64map_put(&seen, ch, 1); VEC_PUSH(stack, ch); }
        }
        if (!kids) VEC_PUSH(*v, u);
    }
    /* ascending IDs, so the draw does not depend on traversal order */
    for (size_t a = 1; a < v->n; a++)
        for (size_t b = a; b > 0 && v->v[b - 1] > v->v[b]; b--) { uint32_t x = v->v[b]; v->v[b] = v->v[b - 1]; v->v[b - 1] = x; }
    VEC_FREE(stack);
    u64map_free(&seen);
    c->leafcache[t] = v;
    return v;
}

/* Whether unifying `value` into `root` at `path` would succeed. */
static bool fits(Content *c, TriNode *root, const U32Vec *path, TriNode *value)
{
    uint32_t saved = op_begin(c);
    reset_failure(c);
    bool ok = unify1(c, root, wrap_path(c, path, value));
    op_end(c, saved);
    return ok;
}

/* The alternatives of disjunction type d that fit at `path`, each as a fresh
 * copy of its expansion in scratch. */
static void alternatives_fitting(Content *c, TriNode *root, const U32Vec *path, uint32_t d, void *outv)
{
    VEC(TriNode *) *out = outv;
    TypeInfo *ti = &c->types.v[d];
    for (size_t k = 0; k < ti->children.n; k++) {
        uint32_t ch = ti->children.v[k];
        if (c->types.v[ch].kind != TK_ALT || c->types.v[ch].parents.v[0] != d) continue;
        TriNode *e = type_expansion(c, ch);
        if (!e) continue;
        TriNode *alt = copy_raw(c, c->scratch, e);
        if (fits(c, root, path, alt)) VEC_PUSH(*out, alt);
    }
}

/* A value for one variation point: from the most specific @vary record at
 * the path if there is one, otherwise uniform. Allocated in scratch. */
/* The seed for one variation point: the entity's seed mixed with the point's
 * path, by feature name (not ID, which content changes may renumber). Each
 * point's draw is then independent of every other point's, of the order they
 * are drawn in, and of whether they are drawn at all: adding a field to a
 * blueprint leaves existing entities' other values alone, and a latent part
 * can be drawn when it is revealed. */
static uint64_t point_seed(Content *c, uint64_t seed, const U32Vec *path)
{
    uint64_t h = hash64(seed ^ 0x7072696e74ULL);
    for (size_t i = 0; i < path->n; i++) h = fnv1a(hash64(h), c->feats.v[path->v[i]].name, strlen(c->feats.v[path->v[i]].name));
    return hash64(h);
}

/* A draw from the triangular distribution on [lo, hi] with its peak at mode,
 * in integers: each side's density is linear, from the larger of two
 * uniform draws. */
static int64_t draw_triangular(uint64_t *state, int64_t lo, int64_t hi, int64_t mode)
{
    if (mode < lo) mode = lo;
    if (mode > hi) mode = hi;
    uint64_t span = (uint64_t) (hi - lo);
    if (!span) return lo;
    uint64_t u1 = splitmix(state) >> 32, u2 = splitmix(state) >> 32, u = u1 > u2 ? u1 : u2;   /* in [0, 2^32) */
    bool left = draw(state, span) < (uint64_t) (mode - lo);
    if (left) return lo + (int64_t) (((__int128) (mode - lo) * u) >> 32);
    return hi - (int64_t) (((__int128) (hi - mode) * u) >> 32);
}

static TriNode *draw_point(Content *c, TriNode *root, const U32Vec *path, const DefVec *varies, uint64_t seed,
                           bool *structural)
{
    uint64_t pstate = point_seed(c, seed, path), *state = &pstate;
    TriNode *n = node_at(root, path->v, path->n);
    const DefaultRec *rec = NULL;
    for (size_t k = 0; k < varies->n; k++)
        if (cmp_path(&varies->v[k].path, path) == 0 &&
            (!rec || more_specific(c, varies->v[k].contributor, rec->contributor)))
            rec = &varies->v[k];
    if (rec && !strncmp(rec->vary, "mode", 4) && (n->flags & NF_DIM)) {
        /* @vary(mode: v): a range peaked at v */
        const char *v = strchr(rec->vary, ':');
        int dim;
        int64_t m;
        if (v) {
            while (*++v == ' ') {}
            size_t len = strlen(v);
            while (len && v[len - 1] == ' ') len--;
            bool neg = *v == '-';
            if (!units_parse(v + neg, len - neg, neg, &dim, &m) && dim == c->types.v[n->type].dim &&
                n->lo != TRI_NINF && n->hi != TRI_INF) {
                int64_t q = draw_triangular(state, n->lo, n->hi, m);
                return leaf_new(c, c->scratch, n->type, q, q);
            }
        }
    }
    if (rec && strncmp(rec->vary, "mode", 4)) {
        XPtrVec ds = { 0 };
        x_flatten(rec->value, X_OR, &ds);
        uint64_t *w = malloc(sizeof(uint64_t) * ds.n);
        TriNode **cand = calloc(ds.n, sizeof(TriNode *));
        uint64_t di = 0;
        DisjInfo *d = u64map_get(&c->disjidx, (uint64_t) (uintptr_t) rec->value, &di) ? &c->disjs.v[di - 1] : NULL;
        if (!parse_weights(rec->vary, w, ds.n)) for (size_t k = 0; k < ds.n; k++) w[k] = 1;
        Build b = { 0 };
        b.c = c; b.ok = true;
        for (size_t k = 0; k < ds.n; k++) {
            if (!w[k]) continue;
            X *a = ds.v[k]->k == X_DEFAULT ? ds.v[k]->u.sub : ds.v[k];
            if (d && !d->collapse) a = x_name(c, d->alts.v[k], a->loc);
            b.ok = true;
            cand[k] = build_raw(&b, a);
            if (!cand[k] || !fits(c, root, path, cand[k])) { cand[k] = NULL; w[k] = 0; }
        }
        build_free(&b);
        bool any = false;
        for (size_t k = 0; k < ds.n; k++) any |= cand[k] != NULL;
        TriNode *r = NULL;
        if (any) {
            size_t k = draw_weighted(state, w, ds.n);
            while (!cand[k]) k = (k + 1) % ds.n;      /* all weights zero: uniform over the fitting */
            r = cand[k];
            *structural |= d != NULL && !d->collapse;
        }
        free(w);
        free(cand);
        VEC_FREE(ds);
        if (r) return r;
    }
    TypeInfo *ti = &c->types.v[n->type];
    if (ti->kind == TK_DIM) {
        uint64_t span = (uint64_t) (n->hi - n->lo) + 1;
        int64_t q = n->lo + (int64_t) (span ? draw(state, span) : splitmix(state));
        return leaf_new(c, c->scratch, n->type, q, q);
    }
    if (ti->isdisj) {
        VEC(TriNode *) fit = { 0 };
        alternatives_fitting(c, root, path, n->type, &fit);
        TriNode *r = fit.n ? fit.v[draw(state, fit.n)] : NULL;
        VEC_FREE(fit);
        *structural = true;
        return r;
    }
    const U32Vec *leaves = enum_leaves(c, n->type);
    return node_new(c, c->scratch, leaves->v[draw(state, leaves->n)]);
}

/* --- derived fields --------------------------------------------------------------------------- */

void tri_register_fn(TriContent *c, const char *name, TriFn fn, void *ctx)
{
    Sym s = intern(c, name);
    for (size_t i = 0; i < c->fns.n; i++)
        if (c->fns.v[i].name == s) { c->fns.v[i].fn = fn; c->fns.v[i].ctx = ctx; return; }
    FnReg r = { s, fn, ctx };
    VEC_PUSH(c->fns, r);
}

typedef struct { U32Vec path; int64_t lo, hi; uint32_t dimtype; } Derived;

static void derive_walk(Content *c, TriNode *n, U32Vec *path, U64Map *seen, void *outv)
{
    VEC(Derived) *out = outv;
    uint64_t k = (uint64_t) (uintptr_t) n;
    if (u64map_get(seen, k, NULL) || (n->flags & NF_DIM)) return;
    u64map_put(seen, k, 1);
    for (uint32_t i = 0; i < n->narcs; i++) {
        uint32_t f = n->arcs[i].feat;
        TriNode *v = n->arcs[i].val;
        const char *fn = (v->flags & NF_DIM) ? field_attr(c, n->type, f, "fn") : NULL;
        if (fn) {
            char *name = strdup(fn);
            char *s = name;
            while (*s == ' ') s++;
            size_t len = strlen(s);
            while (len && s[len - 1] == ' ') s[--len] = 0;
            Sym sym = intern(c, s);
            free(name);
            for (size_t q = 0; q < c->fns.n; q++) {
                if (c->fns.v[q].name != sym) continue;
                Derived d = { { 0 }, TRI_NINF, TRI_INF, v->type };
                if (c->fns.v[q].fn(c->fns.v[q].ctx, c, n, &d.lo, &d.hi)) {
                    for (size_t z = 0; z < path->n; z++) VEC_PUSH(d.path, path->v[z]);
                    VEC_PUSH(d.path, f);
                    VEC_PUSH(*out, d);
                }
                break;
            }
        }
        VEC_PUSH(*path, f);
        derive_walk(c, v, path, seen, out);
        path->n--;
    }
}

/* Unifies the values of registered @fn fields into `root`; the result goes to
 * `out` (or is root itself when there is nothing to derive). */
static TriNode *derive(Content *c, TriNode *root, TriArena *out, bool *ok)
{
    *ok = true;
    if (!c->fns.n) return root;
    VEC(Derived) ds = { 0 };
    U32Vec path = { 0 };
    U64Map seen = { 0 };
    derive_walk(c, root, &path, &seen, &ds);
    u64map_free(&seen);
    VEC_FREE(path);
    if (!ds.n) { VEC_FREE(ds); return root; }
    TriMark m = tri_arena_mark(c->scratch);
    uint32_t saved = op_begin(c);
    reset_failure(c);
    for (size_t k = 0; k < ds.n && *ok; k++) {
        TriNode *v = leaf_new(c, c->scratch, ds.v[k].dimtype, ds.v[k].lo, ds.v[k].hi);
        *ok = unify1(c, root, wrap_path(c, &ds.v[k].path, v));
    }
    TriNode *r = *ok ? copy_out(c, out, root, NULL) : NULL;
    op_end(c, saved);
    if (out != c->scratch) tri_arena_release(c->scratch, m);
    for (size_t k = 0; k < ds.n; k++) VEC_FREE(ds.v[k].path);
    VEC_FREE(ds);
    return r;
}

const TriNode *tri_derive(TriContent *c, const TriNode *node, TriArena *out, TriFailure *failure)
{
    bool ok;
    TriNode *r = derive(c, (TriNode *) node, out, &ok);
    if (!ok && failure) *failure = *fail_info(c);
    return r;
}

const TriNode *tri_construct(TriContent *c, const char *instance, uint64_t seed, TriArena *out)
{
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_spec(c, i)) return NULL;
    InstInfo *in = &c->insts.v[i];
    uint64_t state = hash64(seed ^ 0x76617269616e74ULL);        /* the variant's own stream */
    InstVariant *v = &in->vars.v[in->specvars.v[0]];
    if (in->specvars.n > 1) {
        uint64_t *w = malloc(sizeof(uint64_t) * in->specvars.n);
        for (size_t k = 0; k < in->specvars.n; k++) w[k] = in->vars.v[in->specvars.v[k]].weight;
        v = &in->vars.v[in->specvars.v[draw_weighted(&state, w, in->specvars.n)]];
        free(w);
    }
    TriMark m = tri_arena_mark(c->scratch);
    TriNode *root = v->spec;
    bool ok = true;
    /* Each round makes the open points concrete. Choosing an alternative can
     * expose new points and new defaults, so rounds repeat until none are left. */
    /* The first round works on the spec itself: its points and @vary records
     * are the same every time, so they are kept with the variant. */
    if (!v->vcached) {
        U32Vec path = { 0 };
        collect_recs(c, v->spec, &path, &v->specvaries, ++c->cgenctr, true);
        VEC_FREE(path);
        for (size_t k = 0; k < v->varies.n; k++) add_default(&v->specvaries, &v->varies.v[k], NULL, 0);
        v->vcached = true;
    }
    for (int round = 0; round < 64 && ok; round++) {
        PathVec fresh = { 0 };
        const PathVec *pts = &v->varpaths;
        if (round) {
            U32Vec path = { 0 };
            c->varskip = &v->ariths;
            collect_variation(c, root, &path, &fresh, NULL, NULL, ++c->cgenctr);
            c->varskip = NULL;
            VEC_FREE(path);
            pts = &fresh;
        }
        if (!pts->n) { VEC_FREE(fresh); break; }
        PathVec points = *pts;
        DefVec varies = { 0 };
        const DefVec *vp = &v->specvaries;
        if (round) {
            U32Vec path = { 0 };
            collect_recs(c, root, &path, &varies, ++c->cgenctr, true);
            VEC_FREE(path);
            for (size_t k = 0; k < v->varies.n; k++) add_default(&varies, &v->varies.v[k], NULL, 0);
            vp = &varies;
        }
        bool structural = false;
        TriNode *small[16];
        TriNode **vals = points.n <= 16 ? small : malloc(sizeof(TriNode *) * points.n);
        for (size_t k = 0; k < points.n && ok; k++) {
            vals[k] = draw_point(c, root, &points.v[k], vp, seed, &structural);
            ok = vals[k] != NULL;
        }
        uint32_t saved = op_begin(c);
        reset_failure(c);
        for (size_t k = 0; k < points.n && ok; k++) ok = unify1(c, root, wrap_path(c, &points.v[k], vals[k]));
        if (ok) root = copy_out(c, c->scratch, root, NULL);
        op_end(c, saved);
        if (ok && c->narith) {
            TriFailure af;
            root = settle_arith(c, root, &v->ariths, c->scratch, &af);
            ok = root != NULL;
        }
        if (vals != small) free(vals);
        free_recs(&varies);
        for (size_t k = 0; k < fresh.n; k++) VEC_FREE(fresh.v[k]);
        VEC_FREE(fresh);
        if (ok && structural) {
            Notes quiet = { NULL, NULL, NULL };
            root = resolve_defaults(c, root, &v->defaults, &quiet, c->scratch);
        }
    }
    if (ok) root = derive(c, root, c->scratch, &ok);
    TriNode *r = NULL;
    if (ok) {
        uint32_t saved = op_begin(c);
        r = copy_out(c, out, root, NULL);
        op_end(c, saved);
    }
    tri_arena_release(c->scratch, m);
    return r;
}

/* --- public instance API ---------------------------------------------------------------------- */

const TriNode *tri_pattern(TriContent *c, const char *instance)
{
    uint32_t i = inst_index(c, instance);
    return i != TRI_BOTTOM && inst_pattern(c, i) ? c->insts.v[i].pattern : NULL;
}

size_t tri_pattern_variant_count(TriContent *c, const char *instance)
{
    uint32_t i = inst_index(c, instance);
    return i != TRI_BOTTOM && inst_pattern(c, i) ? c->insts.v[i].vars.n : 0;
}

const TriNode *tri_pattern_variant(TriContent *c, const char *instance, size_t k)
{
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_pattern(c, i) || k >= c->insts.v[i].vars.n) return NULL;
    return c->insts.v[i].vars.v[k].pattern;
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

static void count_nodes(TriNode *n, U64Map *count);
static size_t buf_out(Buf *b, char *buf, size_t len);

/* --- the inspector ------------------------------------------------------------------------------ */

static bool same_value(Content *c, TriNode *a, TriNode *b)
{
    if (a->type != b->type) return false;
    if (a->flags & NF_DIM) return a->lo == b->lo && a->hi == b->hi;
    return true;
}

static bool x_sets_path(Content *c, X *x, const uint32_t *path, size_t n)
{
    Loc loc;
    if (x->k == X_OR) return x_sets_path(c, x->u.bin.a, path, n) || x_sets_path(c, x->u.bin.b, path, n);
    if (x->k == X_AND) return x_sets_path(c, x->u.bin.a, path, n) || x_sets_path(c, x->u.bin.b, path, n);
    if (x->k == X_STRUCT && n) {
        for (int i = 0; i < x->u.st.n; i++) {
            XField *f = &x->u.st.fields[i];
            if (f->label != c->feats.v[path[0]].name) continue;
            if (n == 1 || x_sets_path(c, f->value, path + 1, n - 1)) return true;
        }
        return false;
    }
    return find_field_loc(c, x, path, n, &loc);
}

/* Where a value in a spec came from. */
static void origin(Content *c, InstInfo *in, TriNode *root, const U32Vec *path, TriNode *v, Buf *b)
{
    Buf p = { 0 };
    path_format(c, &p, path->v, path->n);
    size_t plen = p.len;
    for (size_t k = 0; k < in->variation.n; k++)
        if (strcmp(in->variation.v[k], p.s) == 0) { buf_puts(b, "seed"); buf_free(&p); return; }
    for (size_t k = 0; k < in->notes.n; k++) {
        const char *n = in->notes.v[k];
        if (!strncmp(n, "variant ", 8)) { const char *q = strstr(n, ": "); if (q) n = q + 2; }
        if (strncmp(n, p.s, plen) || strncmp(n + plen, " <- ", 4)) continue;
        const char *what = n + plen + 4;
        const char *dflt = strstr(what, " (default)");
        if (dflt) buf_printf(b, "default from %.*s", (int) (dflt - what), what);
        else if (strstr(what, "(the only alternative that fits)")) buf_puts(b, "the only alternative that fits");
        else continue;
        buf_free(&p);
        return;
    }
    buf_free(&p);
    for (size_t k = 0; k < in->decls.n; k++)
        if (x_sets_path(c, in->decls.v[k]->value, path->v, path->n)) { buf_puts(b, "the instance"); return; }
    /* the most general type in the root's ancestry whose constraint gives this value */
    U32Vec queue = { 0 }, found = { 0 };
    U64Map seen = { 0 };
    VEC_PUSH(queue, root->type);
    u64map_put(&seen, root->type, 1);
    for (size_t i = 0; i < queue.n; i++) {
        uint32_t t = queue.v[i];
        TriNode *e = type_expansion(c, t);
        TriNode *ev = e ? node_at(e, path->v, path->n) : NULL;
        if (ev && same_value(c, ev, v)) VEC_PUSH(found, t);
        for (size_t k = 0; k < c->types.v[t].parents.n; k++) {
            uint32_t pt = c->types.v[t].parents.v[k];
            if (!u64map_get(&seen, pt, NULL)) { u64map_put(&seen, pt, 1); VEC_PUSH(queue, pt); }
        }
    }
    uint32_t best = TRI_BOTTOM;
    for (size_t i = 0; i < found.n && best == TRI_BOTTOM; i++) {
        bool general = true;
        for (size_t j = 0; j < found.n && general; j++)
            if (found.v[j] != found.v[i] && is_subtype(c, found.v[i], found.v[j])) general = false;
        if (general) best = found.v[i];
    }
    if (best != TRI_BOTTOM) buf_printf(b, "%s", c->types.v[best].name);
    else buf_puts(b, "combined");
    VEC_FREE(queue);
    VEC_FREE(found);
    u64map_free(&seen);
}

static void inspect_rec(Content *c, InstInfo *in, TriNode *root, TriNode *n, U32Vec *path, int depth,
                        U64Map *count, U64Map *tags, int *ntags, Buf *b)
{
    uint64_t k = (uint64_t) (uintptr_t) n, v = 0, tag;
    u64map_get(count, k, &v);
    if (v > 1 && u64map_get(tags, k, &tag)) { buf_printf(b, "$%llu\n", (unsigned long long) tag); return; }
    if (v > 1) {
        u64map_put(tags, k, (uint64_t) ++*ntags);
        buf_printf(b, "$%d & ", *ntags);
    }
    if ((n->flags & NF_DIM) || !n->narcs) {
        Buf val = { 0 };
        fs_print(c, &val, n);
        buf_puts(b, val.s);
        buf_free(&val);
        if (depth) {
            buf_puts(b, "  <- ");
            origin(c, in, root, path, n, b);
        }
        buf_putc(b, '\n');
        return;
    }
    buf_printf(b, "%s\n", c->types.v[n->type].name);
    for (uint32_t i = 0; i < n->narcs; i++) {
        for (int d = 0; d <= depth; d++) buf_puts(b, "  ");
        buf_printf(b, "%s: ", c->feats.v[n->arcs[i].feat].name);
        VEC_PUSH(*path, n->arcs[i].feat);
        inspect_rec(c, in, root, n->arcs[i].val, path, depth + 1, count, tags, ntags, b);
        path->n--;
    }
}

size_t tri_inspect(TriContent *c, const char *instance, char *buf, size_t len)
{
    Buf b = { 0 };
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_spec(c, i)) {
        buf_printf(&b, "%s has no spec\n", instance);
    } else {
        InstInfo *in = &c->insts.v[i];
        U64Map count = { 0 }, tags = { 0 };
        int ntags = 0;
        U32Vec path = { 0 };
        count_nodes(in->spec, &count);
        buf_printf(&b, "%s: ", in->name);
        if (in->specvars.n > 1) buf_printf(&b, "(%zu variants, generalised) ", in->specvars.n);
        inspect_rec(c, in, in->spec, in->spec, &path, 0, &count, &tags, &ntags, &b);
        VEC_FREE(path);
        u64map_free(&count);
        u64map_free(&tags);
    }
    return buf_out(&b, buf, len);
}

/* Matching against an instance with variants: entailed if some variant is,
 * incompatible if every variant is, otherwise unknown. Returns the variant
 * that decided (or the first unknown one) in *which. */
static TriMatch match_variants(Content *c, InstInfo *in, const TriNode *d, TriMatchResult *r, size_t *which)
{
    TriMatchResult tmp, first_incompatible;
    bool have_unknown = false;
    *which = 0;
    memset(r, 0, sizeof *r);
    for (size_t k = 0; k < in->vars.n; k++) {
        TriMatch m = tri_match(c, in->vars.v[k].pattern, d, &tmp);
        if (m == TRI_ENTAILED) { *r = tmp; *which = k; return m; }
        if (m == TRI_UNKNOWN) {
            if (!have_unknown) { *r = tmp; *which = k; have_unknown = true; }
            else
                for (size_t q = 0; q < tmp.nresidual && r->nresidual < TRI_MAX_RESIDUAL; q++) {
                    bool dup = false;
                    for (size_t s = 0; s < r->nresidual && !dup; s++) dup = strcmp(r->residual[s], tmp.residual[q]) == 0;
                    if (!dup) memcpy(r->residual[r->nresidual++], tmp.residual[q], sizeof tmp.residual[q]);
                }
        } else if (k == 0 || !have_unknown) {
            if (k == 0) first_incompatible = tmp;
        }
    }
    if (have_unknown) return TRI_UNKNOWN;
    *r = first_incompatible;
    return TRI_INCOMPATIBLE;
}

TriMatch tri_match_instance(TriContent *c, const char *instance, const TriNode *description,
                            TriMatchResult *result)
{
    TriMatchResult local;
    TriMatchResult *r = result ? result : &local;
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_pattern(c, i)) {
        memset(r, 0, sizeof *r);
        r->result = TRI_INCOMPATIBLE;
        snprintf(r->failure.left, sizeof r->failure.left, "no instance %s", instance);
        return r->result;
    }
    size_t which;
    r->result = match_variants(c, &c->insts.v[i], description, r, &which);
    if (c->recording && r->result == TRI_INCOMPATIBLE) family_record_failure(c, i, r->failure.path);
    return r->result;
}

static TriNode *arc_lazy(Content *c, TriNode *n, uint32_t f);
static bool below(Content *c, TriNode *x, TriNode *y);

static void tag_positions(TriNode *n, TriNode *target, U32Vec *path, PathVec *out, int depth)
{
    if (depth > 64) return;
    if (n == target) {
        U32Vec copy = { 0 };
        for (size_t i = 0; i < path->n; i++) VEC_PUSH(copy, path->v[i]);
        VEC_PUSH(*out, copy);
        return;
    }
    if (n->flags & NF_DIM) return;
    for (uint32_t i = 0; i < n->narcs; i++) {
        VEC_PUSH(*path, n->arcs[i].feat);
        tag_positions(n->arcs[i].val, target, path, out, depth + 1);
        path->n--;
    }
}

static TriNode *desc_at(Content *c, TriNode *d, const U32Vec *p)
{
    for (size_t i = 0; i < p->n && d; i++) d = arc_lazy(c, d, p->v[i]);
    return d;
}

/* The value a tag of `pattern` (first found at `first`) takes in a description:
 * the most specific of the description's values at all the tag's positions. */
static TriNode *tag_value(Content *c, TriNode *pattern, const U32Vec *first, TriNode *d, U32Vec *where)
{
    TriNode *pn = node_at(pattern, first->v, first->n);
    PathVec pos = { 0 };
    U32Vec path = { 0 };
    if (pn) tag_positions(pattern, pn, &path, &pos, 0);
    VEC_FREE(path);
    TriNode *best = desc_at(c, d, first);
    size_t bi = SIZE_MAX;
    for (size_t k = 0; k < pos.n; k++) {
        TriNode *v = desc_at(c, d, &pos.v[k]);
        if (!v) continue;
        if (!best || (bi != k && below(c, v, best) && !below(c, best, v))) { best = v; bi = k; }
    }
    if (where) {
        where->n = 0;
        const U32Vec *src = bi != SIZE_MAX ? &pos.v[bi] : first;
        for (size_t i = 0; i < src->n; i++) VEC_PUSH(*where, src->v[i]);
    }
    for (size_t k = 0; k < pos.n; k++) VEC_FREE(pos.v[k]);
    VEC_FREE(pos);
    return best;
}

const TriNode *tri_binding(TriContent *c, const char *instance, const char *tag, const TriNode *d)
{
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_pattern(c, i)) return NULL;
    Buf b = { 0 };
    buf_printf(&b, "%s%s", tag[0] == '$' || tag[0] == '.' ? "" : "$", tag);   /* a tag, or a reference */
    Sym t = intern(c, b.s);
    buf_free(&b);
    InstInfo *in = &c->insts.v[i];
    size_t which = 0;
    if (in->vars.n > 1) {
        TriMatchResult r;
        match_variants(c, in, d, &r, &which);
    }
    InstVariant *v = &in->vars.v[which];
    for (size_t k = 0; k < v->tags.n; k++)
        if (v->tags.v[k].name == t) return tag_value(c, v->pattern, &v->tags.v[k].path, (TriNode *) d, NULL);
    return NULL;
}

/* --- runtime values ------------------------------------------------------------------------------ */

const TriNode *tri_value(TriContent *c, const char *expr, TriArena *out, char *err, size_t errlen)
{
    size_t ndiag = c->diags.n;
    int nerr = c->nerrors;
    X *x = parse_expr_string(c, intern(c, "<value>"), expr);
    if (x && c->parsed_comp) {
        bool ok;
        x = expand_value(c, x, &ok);
        if (!ok) x = NULL;
    }
    const TriNode *r = NULL;
    if (x) {
        TriMark m = tri_arena_mark(c->scratch);
        uint32_t saved = op_begin(c);
        Build b = { 0 };
        b.c = c; b.ok = true; b.runtime = true;
        TriNode *n = build_raw(&b, x);
        ArithVec ariths = { 0 };
        if (n && b.ok) {
            bool closed;
            r = copy_out(c, out, n, &closed);
            if (!closed) {
                diag(c, true, noloc, "a field is not appropriate for its type");
                r = NULL;
            } else if (!resolve_ariths(c, &b, (TriNode *) r, &ariths, noloc, "value")) {
                r = NULL;
            }
        }
        build_free(&b);
        op_end(c, saved);
        tri_arena_release(c->scratch, m);
        if (r) {
            TriFailure f;
            r = settle(c, (TriNode *) r, &ariths, out, &f);
            if (!r && f.right[0]) diag(c, true, noloc, "arithmetic at %s: %s gives %s", f.path, f.left, f.right);
            else if (!r) diag(c, true, noloc, "%s at %s", f.left, f.path);
        }
        free_ariths(&ariths);
    }
    if (err && errlen) err[0] = 0;
    if (c->diags.n > ndiag && err && errlen) snprintf(err, errlen, "%s", c->diags.v[ndiag].msg);
    /* runtime values do not leave diagnostics on the content */
    while (c->diags.n > ndiag) free(c->diags.v[--c->diags.n].msg);
    c->nerrors = nerr;
    return r;
}

/* --- matching ------------------------------------------------------------------------------------ */

/* Residuals. The description is walked under the pattern, recording each
 * position of each pattern node with the description node there. A position
 * is residual if the description is too general there: a type not below the
 * pattern's, or an interval not inside it. A pattern node at several positions
 * (a tag) is residual where its description is less specific than at another
 * of its positions: that is where the value is still to be learned. If its
 * descriptions are all equivalent but separate structures, every position is
 * residual: whether they are one thing is what remains unknown. The walk goes
 * on below a too-general type, so the fields that are open there show too. */

typedef struct { TriNode *p, *d; U32Vec path; } Occ;
typedef VEC(Occ) OccVec;

static TriNode *arc_lazy(Content *c, TriNode *n, uint32_t f)
{
    TriNode *v = (n->flags & NF_DIM) ? NULL : node_arc(n, f);
    if (!v && (n->flags & NF_LAZY)) {
        TriNode *e = type_expansion(c, n->type);
        v = e ? node_arc(e, f) : NULL;
    }
    return v;
}

static void occ_walk(Content *c, TriNode *p, TriNode *d, U32Vec *path, OccVec *out, int depth)
{
    if (depth > 64) return;
    Occ o = { p, d, { 0 } };
    for (size_t i = 0; i < path->n; i++) VEC_PUSH(o.path, path->v[i]);
    VEC_PUSH(*out, o);
    if (p->flags & NF_DIM) return;
    for (uint32_t i = 0; i < p->narcs; i++) {
        TriNode *dv = arc_lazy(c, d, p->arcs[i].feat);
        if (!dv) continue;
        VEC_PUSH(*path, p->arcs[i].feat);
        occ_walk(c, p->arcs[i].val, dv, path, out, depth + 1);
        path->n--;
    }
}

static bool below(Content *c, TriNode *x, TriNode *y)         /* x ⊑ y */
{
    if (x == y || ext_equal(c, x, y)) return true;
    int f, b;
    tri_subsumes(c, y, x, &f, &b);
    return f;
}

static void add_residual(Content *c, TriMatchResult *r, const U32Vec *path)
{
    if (r->nresidual >= TRI_MAX_RESIDUAL) return;
    Buf b = { 0 };
    path_format(c, &b, path->v, path->n);
    for (size_t k = 0; k < r->nresidual; k++)
        if (strcmp(r->residual[k], b.s) == 0) { buf_free(&b); return; }
    snprintf(r->residual[r->nresidual++], sizeof r->residual[0], "%s", b.s);
    buf_free(&b);
}

static void residuals(Content *c, TriNode *pattern, TriNode *desc, TriMatchResult *r)
{
    OccVec occ = { 0 };
    U32Vec path = { 0 };
    occ_walk(c, pattern, desc, &path, &occ, 0);
    VEC_FREE(path);
    for (size_t i = 0; i < occ.n; i++) {
        Occ *o = &occ.v[i];
        bool open;
        if ((o->p->flags & NF_DIM) && c->types.v[o->p->type].dim == DIM_TEXT)
            open = !below(c, o->d, o->p);      /* text compares by its constraints, never by address */
        else if (o->p->flags & NF_DIM)
            open = !((o->d->flags & NF_DIM) && o->d->lo >= o->p->lo && o->d->hi <= o->p->hi);
        else
            open = !is_subtype(c, o->d->type, o->p->type);
        /* the other positions of the same pattern node */
        bool shared = false, unresolved_identity = false;
        for (size_t j = 0; j < occ.n && !open; j++) {
            if (j == i || occ.v[j].p != o->p) continue;
            shared = true;
            TriNode *e = occ.v[j].d;
            if (e == o->d) continue;
            if (!below(c, o->d, e)) open = true;
            else if (!ext_equal(c, o->d, e) && below(c, e, o->d)) unresolved_identity = true;
        }
        if (open || (shared && unresolved_identity)) add_residual(c, r, &o->path);
    }
    for (size_t i = 0; i < occ.n; i++) VEC_FREE(occ.v[i].path);
    VEC_FREE(occ);
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
    if (!compatible) r->failure = *fail_info(c);
    op_end(c, saved);
    tri_arena_release(c->scratch, m);
    if (!compatible) { r->result = TRI_INCOMPATIBLE; return r->result; }

    m = tri_arena_mark(c->scratch);
    residuals(c, (TriNode *) pattern, (TriNode *) description, r);
    tri_arena_release(c->scratch, m);
    r->result = TRI_UNKNOWN;
    return r->result;
}

TriMasses tri_match_hypotheses(TriContent *c, const TriNode *pattern,
                               const TriNode *const *ds, const uint32_t *cred, size_t n)
{
    TriMasses m;
    memset(&m, 0, sizeof m);
    TriMatchResult r;
    for (size_t i = 0; i < n; i++) {
        switch (tri_match(c, pattern, ds[i], &r)) {
        case TRI_ENTAILED: m.entailed += cred[i]; break;
        case TRI_INCOMPATIBLE: m.incompatible += cred[i]; break;
        case TRI_UNKNOWN:
            m.unknown += cred[i];
            for (size_t k = 0; k < r.nresidual && m.nresidual < TRI_MAX_RESIDUAL; k++) {
                bool dup = false;
                for (size_t q = 0; q < m.nresidual && !dup; q++) dup = strcmp(m.residual[q], r.residual[k]) == 0;
                if (!dup) memcpy(m.residual[m.nresidual++], r.residual[k], sizeof r.residual[k]);
            }
            break;
        }
    }
    return m;
}

/* --- explaining matches ------------------------------------------------------------------------- */

static const char *match_name(TriMatch m)
{
    return m == TRI_ENTAILED ? "entailed" : m == TRI_UNKNOWN ? "unknown" : "incompatible";
}

static void explain_tail(Content *c, Buf *b, const TriMatchResult *r)
{
    if (r->nresidual) {
        buf_puts(b, "residuals:");
        for (size_t k = 0; k < r->nresidual; k++) buf_printf(b, " %s", r->residual[k]);
        buf_putc(b, '\n');
    }
    if (r->result == TRI_INCOMPATIBLE)
        buf_printf(b, "first failing path: %s: %s vs %s\n", r->failure.path[0] ? r->failure.path : "(root)",
                   r->failure.left, r->failure.right[0] ? r->failure.right : "(missing)");
}

static void binding_line(Content *c, Buf *b, const char *name, const U32Vec *path, const TriNode *d)
{
    Buf p = { 0 };
    path_format(c, &p, path->v, path->n);
    if (name[0] == '.') buf_printf(b, "  %s = ", name);      /* a reference names its own path */
    else buf_printf(b, "  %s at %s = ", name, p.s);
    TriNode *v = node_at((TriNode *) d, path->v, path->n);
    if (v) fs_print(c, b, v);
    else buf_puts(b, "(not in the description)");
    buf_putc(b, '\n');
    buf_free(&p);
}

/* Shared nodes of a pattern, by first path: its tags. */
static void shared_paths(Content *c, TriNode *n, U32Vec *path, U64Map *count, U64Map *done, PathVec *out)
{
    uint64_t k = (uint64_t) (uintptr_t) n, v = 0;
    u64map_get(count, k, &v);
    if (v > 1 && !u64map_get(done, k, NULL)) {
        u64map_put(done, k, 1);
        U32Vec copy = { 0 };
        for (size_t i = 0; i < path->n; i++) VEC_PUSH(copy, path->v[i]);
        VEC_PUSH(*out, copy);
        return;
    }
    if (u64map_get(done, k, NULL) || (n->flags & NF_DIM)) return;
    u64map_put(done, k, 1);
    for (uint32_t i = 0; i < n->narcs; i++) {
        VEC_PUSH(*path, n->arcs[i].feat);
        shared_paths(c, n->arcs[i].val, path, count, done, out);
        path->n--;
    }
}

static void count_nodes(TriNode *n, U64Map *count)
{
    uint64_t k = (uint64_t) (uintptr_t) n, v = 0;
    if (u64map_get(count, k, &v)) { u64map_put(count, k, v + 1); return; }
    u64map_put(count, k, 1);
    if (n->flags & NF_DIM) return;
    for (uint32_t i = 0; i < n->narcs; i++) count_nodes(n->arcs[i].val, count);
}

static size_t buf_out(Buf *b, char *buf, size_t len)
{
    size_t n = b->len;
    if (len) snprintf(buf, len, "%s", b->s ? b->s : "");
    buf_free(b);
    return n;
}

size_t tri_explain(TriContent *c, const TriNode *pattern, const TriNode *d, char *buf, size_t len)
{
    TriMatchResult r;
    tri_match(c, pattern, d, &r);
    Buf b = { 0 };
    buf_printf(&b, "result: %s\n", match_name(r.result));
    U64Map count = { 0 }, done = { 0 };
    PathVec shared = { 0 };
    U32Vec path = { 0 };
    count_nodes((TriNode *) pattern, &count);
    shared_paths(c, (TriNode *) pattern, &path, &count, &done, &shared);
    if (shared.n) buf_puts(&b, "bindings:\n");
    for (size_t k = 0; k < shared.n; k++) {
        char name[16];
        snprintf(name, sizeof name, "$%zu", k + 1);
        binding_line(c, &b, name, &shared.v[k], d);
        VEC_FREE(shared.v[k]);
    }
    VEC_FREE(shared);
    VEC_FREE(path);
    u64map_free(&count);
    u64map_free(&done);
    explain_tail(c, &b, &r);
    return buf_out(&b, buf, len);
}

size_t tri_explain_instance(TriContent *c, const char *instance, const TriNode *d, char *buf, size_t len)
{
    Buf b = { 0 };
    uint32_t i = inst_index(c, instance);
    if (i == TRI_BOTTOM || !inst_pattern(c, i)) {
        buf_printf(&b, "no pattern instance %s\n", instance);
        return buf_out(&b, buf, len);
    }
    InstInfo *in = &c->insts.v[i];
    TriMatchResult r;
    size_t which;
    r.result = match_variants(c, in, d, &r, &which);
    buf_printf(&b, "result: %s\n", match_name(r.result));
    if (in->vars.n > 1) buf_printf(&b, "variant: %zu of %zu\n", which + 1, in->vars.n);
    InstVariant *v = &in->vars.v[which];
    if (v->tags.n) buf_puts(&b, "bindings:\n");
    for (size_t k = 0; k < v->tags.n; k++) {
        U32Vec where = { 0 };
        tag_value(c, v->pattern, &v->tags.v[k].path, (TriNode *) d, &where);
        binding_line(c, &b, v->tags.v[k].name, &where, d);
        VEC_FREE(where);
    }
    explain_tail(c, &b, &r);
    return buf_out(&b, buf, len);
}

/* --- generalisation ----------------------------------------------------------------------------- */

typedef struct { TriNode *target; uint32_t type; int64_t lo, hi; } GenTarget;

static TriNode *gen_copy(Content *c, TriArena *a, TriNode *n, const GenTarget *g, uint32_t cg)
{
    if (n->cpygen == cg) return n->cpy;
    uint32_t t = n == g->target ? g->type : n->type;
    TriNode *m = node_new(c, a, t);
    m->flags |= n->flags & NF_LAZY;
    if (n->flags & NF_DIM) {
        m->lo = n == g->target ? g->lo : n->lo;
        m->hi = n == g->target ? g->hi : n->hi;
    }
    n->cpy = m;
    n->cpygen = cg;
    uint32_t k = 0;
    if (!(n->flags & NF_DIM)) m->arcs = n->narcs ? arena_alloc(a, n->narcs * sizeof(Arc)) : NULL;
    for (uint32_t i = 0; i < n->narcs; i++) {
        if (!approp(c, t, n->arcs[i].feat)) continue;
        m->arcs[k].feat = n->arcs[i].feat;
        m->arcs[k].val = gen_copy(c, a, n->arcs[i].val, g, cg);
        k++;
    }
    m->narcs = k;
    return m;
}

/* An attribute on the declaration of feature f, looked up from type t along
 * primary parents: the nearest declaration that has it. */
const char *field_attr(Content *c, uint32_t t, uint32_t f, const char *name)
{
    Sym label = c->feats.v[f].name;
    for (uint32_t u = t; u != TRI_BOTTOM; u = c->types.v[u].parents.n ? c->types.v[u].parents.v[0] : TRI_BOTTOM) {
        TypeInfo *ui = &c->types.v[u];
        for (size_t k = 0; k < ui->decls.n; k++) {
            XPtrVec cj = { 0 };
            conjuncts(ui->decls.v[k]->value, &cj);
            const char *r = NULL;
            for (size_t j = 0; j < cj.n && !r; j++) {
                if (cj.v[j]->k != X_STRUCT) continue;
                for (int q = 0; q < cj.v[j]->u.st.n && !r; q++)
                    if (cj.v[j]->u.st.fields[q].label == label)
                        r = attr_args(cj.v[j]->u.st.fields[q].attrs, cj.v[j]->u.st.fields[q].nattrs, name);
            }
            VEC_FREE(cj);
            if (r) return r;
        }
        if (u == c->top) break;
    }
    return NULL;
}

static int64_t sat_add(int64_t a, int64_t b)
{
    if (a == TRI_NINF || a == TRI_INF) return a;
    if (b > 0 && a > TRI_INF - b) return TRI_INF;
    if (b < 0 && a < TRI_NINF - b) return TRI_NINF;
    return a + b;
}

const TriNode *tri_generalize(TriContent *c, const TriNode *node, const char *path, int steps,
                              TriArena *out)
{
    U32Vec p = { 0 };
    if (!path_parse(c, path, &p)) { VEC_FREE(p); return NULL; }
    if (!p.n) {
        /* the root: its type along primary parents, as far as the top */
        VEC_FREE(p);
        GenTarget g = { (TriNode *) node, node->type, node->lo, node->hi };
        for (int s = 0; s < steps && g.type != c->top && c->types.v[g.type].parents.n; s++)
            g.type = c->types.v[g.type].parents.v[0];
        if (node->flags & NF_DIM) return node;
        return gen_copy(c, out, (TriNode *) node, &g, ++c->cgenctr);
    }
    TriNode *parent = node_at((TriNode *) node, p.v, p.n - 1);
    uint32_t f = p.v[p.n - 1];
    TriNode *target = parent ? node_arc(parent, f) : NULL;
    VEC_FREE(p);
    if (!target) return NULL;
    /* The bound: the value the parent's type allows at this feature. */
    TriNode *pe = type_expansion(c, parent->type);
    TriNode *bound = pe ? node_arc(pe, f) : NULL;
    GenTarget g = { target, target->type, target->lo, target->hi };
    if (target->flags & NF_DIM) {
        /* numbers widen by the declared @widen step on each side, within the bound */
        int64_t blo = bound && (bound->flags & NF_DIM) ? bound->lo : TRI_NINF;
        int64_t bhi = bound && (bound->flags & NF_DIM) ? bound->hi : TRI_INF;
        const char *w = field_attr(c, parent->type, f, "widen");
        int dim = c->types.v[target->type].dim;
        int wdim;
        int64_t step = 0;
        if (w && dim != DIM_TEXT && dim != DIM_REF) {
            char *t = strdup(w);
            char *s = t;
            while (*s == ' ') s++;
            size_t len = strlen(s);
            while (len && s[len - 1] == ' ') s[--len] = 0;
            if (units_parse(s, len, false, &wdim, &step) || wdim != dim) step = 0;
            free(t);
        }
        if (steps > 0 && step > 0) {
            for (int k = 0; k < steps; k++) { g.lo = sat_add(g.lo, -step); g.hi = sat_add(g.hi, step); }
        } else if (steps > 0) {
            g.lo = blo;
            g.hi = bhi;
        }
        if (g.lo < blo) g.lo = blo;
        if (g.hi > bhi) g.hi = bhi;
    } else {
        uint32_t limit = bound ? bound->type : c->top;
        uint32_t t = target->type;
        for (int s = 0; s < steps && t != limit && t != c->top; s++) {
            uint32_t pt = c->types.v[t].parents.v[0];
            if (!is_subtype(c, pt, limit)) { t = limit; break; }
            t = pt;
        }
        g.type = t;
    }
    return gen_copy(c, out, (TriNode *) node, &g, ++c->cgenctr);
}

/* --- loading API ----------------------------------------------------------------------------------- */

/* --- the content hash ---------------------------------------------------------------------------- */

/* The hash covers the hierarchy, every type's expansion, and every instance's
 * patterns and spec. Structures are hashed by walking them: a node seen before
 * in the same structure is hashed as a reference to its first position (the
 * copy-generation fields mark the visit), so sharing counts but addresses don't.
 * TRI_DUMP=file also writes the same content as text, for diffing. */

static void hmix(uint64_t *h, uint64_t x)
{
    *h = hash64(*h ^ x) * 0x100000001b3ULL + 0x9e3779b97f4a7c15ULL;
}

static void hstr(uint64_t *h, const char *s)
{
    *h = fnv1a(*h, s, strlen(s) + 1);
}

static void hash_node(Content *c, uint64_t *h, TriNode *n, uint32_t cg, uint64_t *next)
{
    if (n->cpygen == cg) { hmix(h, 0xA11CE ^ ((uint64_t) (uintptr_t) n->cpy << 8)); return; }
    n->cpygen = cg;
    n->cpy = (TriNode *) (uintptr_t) (*next)++;
    hmix(h, ((uint64_t) n->type << 8) | (n->flags & NF_LAZY));
    if (n->flags & NF_DIM) {
        const RxSet *rx = c->types.v[n->type].dim == DIM_TEXT ? text_rx(n->lo, n->hi) : NULL;
        if (c->types.v[n->type].dim == DIM_TEXT && n->lo == n->hi) hstr(h, (const char *) (intptr_t) n->lo);
        else if (rx) hmix(h, rx->hash);         /* by contents, never by address */
        else { hmix(h, (uint64_t) n->lo); hmix(h, (uint64_t) n->hi); }
        return;
    }
    hmix(h, n->narcs);
    for (uint32_t i = 0; i < n->narcs; i++) {
        hmix(h, n->arcs[i].feat);
        hash_node(c, h, n->arcs[i].val, cg, next);
    }
}

static void hash_root(Content *c, uint64_t *h, TriNode *n)
{
    uint64_t next = 1;
    hash_node(c, h, n, ++c->cgenctr, &next);
}

static int cmp_symp(const void *a, const void *b)
{
    return strcmp(*(Sym const *) a, *(Sym const *) b);
}

static void compute_hash(Content *c)
{
    uint64_t h = 0xcbf29ce484222325ULL;
    const char *dump = getenv("TRI_DUMP");
    Buf b = { 0 };
    for (uint32_t t = 0; t < c->types.n; t++) {
        TypeInfo *ti = &c->types.v[t];
        hstr(&h, ti->name);
        for (size_t k = 0; k < ti->parents.n; k++) hmix(&h, ti->parents.v[k]);
        if (ti->expansion) hash_root(c, &h, ti->expansion);
        if (dump) {
            buf_printf(&b, "%s<", ti->name);
            for (size_t k = 0; k < ti->parents.n; k++) buf_printf(&b, "%s,", c->types.v[ti->parents.v[k]].name);
            buf_puts(&b, ">");
            if (ti->expansion) fs_print(c, &b, ti->expansion);
            buf_putc(&b, '\n');
        }
    }
    /* instances in name order */
    Sym *names = malloc(sizeof(Sym) * (c->insts.n ? c->insts.n : 1));
    for (size_t i = 0; i < c->insts.n; i++) names[i] = c->insts.v[i].name;
    qsort(names, c->insts.n, sizeof(Sym), cmp_symp);
    for (size_t i = 0; i < c->insts.n; i++) {
        InstInfo *in = &c->insts.v[inst_index(c, names[i])];
        hstr(&h, names[i]);
        for (size_t v = 0; v < in->vars.n; v++) hash_root(c, &h, in->vars.v[v].pattern);
        if (in->sstate == 2) hash_root(c, &h, in->spec);
        if (dump) {
            buf_printf(&b, "%s=", names[i]);
            for (size_t v = 0; v < in->vars.n; v++) {
                if (v) buf_puts(&b, " || ");
                fs_print(c, &b, in->vars.v[v].pattern);
            }
            if (in->sstate == 2) {
                buf_puts(&b, " spec ");
                fs_print(c, &b, in->spec);
            }
            buf_putc(&b, '\n');
        }
    }
    free(names);
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

/* --- the field registry ---------------------------------------------------------------------- */

/* The @field flags of a feature, from the type that introduces it, or NULL. */
const char *field_flags(const Content *c, uint32_t f)
{
    const TypeInfo *ti = &c->types.v[c->feats.v[f].intro];
    for (size_t a = 0; a < ti->field_feats.n; a++)
        if (ti->field_feats.v[a] == f) return ti->field_attrs.v[a]->args;
    return NULL;
}

/* Whether a comma-separated flag list has `flag` at the top level. */
bool has_flag(const char *flags, const char *flag)
{
    size_t n = strlen(flag);
    int depth = 0;
    const char *s = flags;
    while (*s) {
        while (*s == ' ' || *s == '\t' || (*s == ',' && !depth)) s++;
        const char *start = s;
        while (*s && !(*s == ',' && !depth)) {
            if (*s == '(') depth++;
            if (*s == ')') depth--;
            s++;
        }
        const char *end = s;
        while (end > start && (end[-1] == ' ' || end[-1] == '\t')) end--;
        if ((size_t) (end - start) == n && memcmp(start, flag, n) == 0) return true;
    }
    return false;
}

/* A blueprint is an instance whose type includes a component. */
static bool is_blueprint(Content *c, uint32_t i, const U32Vec *components)
{
    InstInfo *in = &c->insts.v[i];
    if (!in->pattern) return false;
    for (size_t k = 0; k < components->n; k++)
        if (is_subtype(c, in->pattern->type, components->v[k])) return true;
    return false;
}

/* Content may set only fields the registry marks `content`. */
static void check_fields_set(Content *c, InstInfo *in, X *x)
{
    if (!x) return;
    switch (x->k) {
    case X_STRUCT:
        for (int k = 0; k < x->u.st.n; k++) {
            XField *fl = &x->u.st.fields[k];
            uint32_t f = feat_lookup(c, fl->label);
            const char *flags = f == TRI_BOTTOM ? NULL : field_flags(c, f);
            if (flags && !has_flag(flags, "content"))
                diag(c, true, fl->loc, "%s: %s is not a content field (@field(%s)), so content may not set it",
                     in->name, fl->label, flags);
            check_fields_set(c, in, fl->value);
        }
        break;
    case X_AND: case X_OR:
        check_fields_set(c, in, x->u.bin.a);
        check_fields_set(c, in, x->u.bin.b);
        break;
    case X_DEFAULT:
        check_fields_set(c, in, x->u.sub);
        break;
    case X_LIST:
        for (int k = 0; k < x->u.list.n; k++) check_fields_set(c, in, x->u.list.items[k]);
        break;
    default:
        break;
    }
}

static void check_blueprint(Content *c, uint32_t i)
{
    InstInfo *in = &c->insts.v[i];
    for (size_t k = 0; k < in->decls.n; k++) check_fields_set(c, in, in->decls.v[k]->value);
    inst_spec(c, i);
}

/* --- packages (CONTENT_LANGUAGE.md decision 12) ---------------------------------- */

/* The name as its package qualifies it: #Wrench in tools is tools.#Wrench,
 * wrench_250 is tools.wrench_250. */
static Sym qualify(Content *c, Sym pkg, Sym name)
{
    Buf b = { 0 };
    buf_printf(&b, "%s.%s", pkg, name);
    Sym q = intern(c, b.s);
    buf_free(&b);
    return q;
}

/* Within a package, a plain name is the package's own if it declares one,
 * else the root's. Qualified names are taken as written. */
static void resolve_names(Content *c, X *x, Sym pkg, const U64Map *declared)
{
    if (!x) return;
    switch (x->k) {
    case X_NAME: {
        if (!pkg) break;
        const char *s = x->u.name;
        size_t first = strcspn(s, ".[");
        if (!s[first]) {
            Sym q = qualify(c, pkg, s);
            if (u64map_get(declared, (uint64_t) (uintptr_t) q, NULL)) x->u.name = q;
            break;
        }
        /* a path, wrench_19.size: the package's own wrench_19 if it has one,
         * unless the name already starts with another package's name */
        if (s[first] == '.' && s[first + 1] == '#') break;
        for (size_t end = strlen(s); end > first; end--) {
            if (s[end] && s[end] != '.' && s[end] != '[') continue;
            char *pre = malloc(end + 1);
            memcpy(pre, s, end);
            pre[end] = 0;
            bool other = u64map_get(declared, (uint64_t) (uintptr_t) intern(c, pre), NULL);
            free(pre);
            if (other) return;
        }
        char *head = malloc(first + 1);
        memcpy(head, s, first);
        head[first] = 0;
        Sym q = qualify(c, pkg, intern(c, head));
        free(head);
        if (u64map_get(declared, (uint64_t) (uintptr_t) q, NULL)) x->u.name = qualify(c, pkg, s);
        break;
    }
    case X_STRUCT:
        for (int i = 0; i < x->u.st.n; i++) {
            resolve_names(c, x->u.st.fields[i].value, pkg, declared);
            resolve_names(c, x->u.st.fields[i].dlabel, pkg, declared);
        }
        break;
    case X_COMP:
        for (int i = 0; i < x->u.comp.n; i++) resolve_names(c, x->u.comp.clauses[i].expr, pkg, declared);
        resolve_names(c, x->u.comp.body, pkg, declared);
        break;
    case X_CMP: case X_LOGIC:
        resolve_names(c, x->u.ar.a, pkg, declared);
        resolve_names(c, x->u.ar.b, pkg, declared);
        break;
    case X_NOT:
        resolve_names(c, x->u.sub, pkg, declared);
        break;
    case X_CALL:
        for (int i = 0; i < x->u.call.n; i++) resolve_names(c, x->u.call.args[i], pkg, declared);
        break;
    case X_LIST:
        for (int i = 0; i < x->u.list.n; i++) resolve_names(c, x->u.list.items[i], pkg, declared);
        resolve_names(c, x->u.list.tail, pkg, declared);
        resolve_names(c, x->u.list.elem, pkg, declared);
        break;
    case X_AND:
    case X_OR:
        resolve_names(c, x->u.bin.a, pkg, declared);
        resolve_names(c, x->u.bin.b, pkg, declared);
        break;
    case X_DEFAULT:
        resolve_names(c, x->u.sub, pkg, declared);
        break;
    case X_ARITH:
        resolve_names(c, x->u.ar.a, pkg, declared);
        resolve_names(c, x->u.ar.b, pkg, declared);
        break;
    case X_INTERP:
        for (int i = 0; i < x->u.in.n; i++) resolve_names(c, x->u.in.parts[i], pkg, declared);
        break;
    default:
        break;
    }
}

/* A let's name may not be a type's or an instance's: inside its scope, it
 * would hide that one without a word. */
static bool check_lets(Content *c)
{
    bool ok = true;
    for (size_t i = 0; i < c->lets.n; i++) {
        LetName *l = &c->lets.v[i];
        Sym q = l->pkg ? qualify(c, l->pkg, l->name) : NULL;
        const char *what = NULL;
        uint32_t t = type_lookup(c, l->name);
        if (t != TRI_BOTTOM && c->types.v[t].kind != TK_ATOM) what = "a built-in type";
        else if (u64map_get(&c->instidx, (uint64_t) (uintptr_t) l->name, NULL) ||
                 (q && u64map_get(&c->instidx, (uint64_t) (uintptr_t) q, NULL)))
            what = "an instance";
        if (what) {
            diag(c, true, l->loc, "%s %s: %s has this name, and %s may not hide it", l->var ? "for" : "let", l->name, what,
                 l->var ? "a for's variable" : "a let");
            ok = false;
        }
    }
    return ok;
}

/* Types and blueprints declared in a package take its name; references to
 * them inside it are resolved. Atoms and features stay global. */
static void resolve_packages(Content *c)
{
    U64Map declared = { 0 };
    bool any = false;
    for (size_t i = 0; i < c->decls.n; i++) {
        Decl *d = &c->decls.v[i];
        if (!d->pkg || d->kind == L_ATOM) continue;
        d->label = qualify(c, d->pkg, d->label);
        u64map_put(&declared, (uint64_t) (uintptr_t) d->label, 1);
        any = true;
    }
    for (size_t i = 0; any && i < c->decls.n; i++)
        if (c->decls.v[i].pkg) resolve_names(c, c->decls.v[i].value, c->decls.v[i].pkg, &declared);
    u64map_free(&declared);
}


/* --- comprehensions (REFERENCE.md, Comprehensions) ------------------------------- */

/* A comprehension is expanded when content loads, into what it stands for:
 * a list's items, or a struct's fields. Its sources and conditions must be
 * known by then: data written in the content (a list, a struct, a let's
 * value, a field of this or another declaration), or an enum's atoms. The
 * rest of the engine never sees one. */

typedef struct Env { const CompVar *var; X *value; const struct Env *up; } Env;
typedef struct { Content *c; X *root; bool ok; size_t made; int refdepth; } Exp;
typedef VEC(XField) FieldVec;

enum { EXPAND_MAX = 100000 };      /* items and fields a declaration's comprehensions may make */

static void exp_error(Exp *e, Loc loc, const char *msg)
{
    if (e->ok) diag(e->c, true, loc, "%s", msg);
    e->ok = false;
}

static void build_declidx(Content *c)
{
    if (c->declidx_built) return;
    for (size_t i = 0; i < c->decls.n; i++)
        if (!u64map_get(&c->declidx, (uint64_t) (uintptr_t) c->decls.v[i].label, NULL))
            u64map_put(&c->declidx, (uint64_t) (uintptr_t) c->decls.v[i].label, i + 1);
    c->declidx_built = true;
}

/* A field written in a literal: through conjunctions, not the structs that
 * place references. */
static X *data_field(X *x, Sym label)
{
    if (!x) return NULL;
    if (x->k == X_AND) {
        X *a = data_field(x->u.bin.a, label);
        return a ? a : data_field(x->u.bin.b, label);
    }
    if (x->k != X_STRUCT || x->u.st.refs) return NULL;
    for (int i = 0; i < x->u.st.n; i++)
        if (x->u.st.fields[i].label == label) return x->u.st.fields[i].value;
    return NULL;
}

static X *data_item(X *x, long k)
{
    if (!x) return NULL;
    if (x->k == X_AND) {
        X *a = data_item(x->u.bin.a, k);
        return a ? a : data_item(x->u.bin.b, k);
    }
    return x->k == X_LIST && k >= 0 && k < x->u.list.n ? x->u.list.items[k] : NULL;
}

static X *data_of(Exp *e, X *x, int depth);

/* The literal at a path, ".a[0].b" (or "a[0].b"), in x. */
static X *data_at(Exp *e, X *x, const char *path, int depth)
{
    const char *s = path;
    while (x && *s) {
        x = data_of(e, x, depth + 1);
        if (*s == '.') s++;
        if (*s == '[') {
            long k = strtol(s + 1, NULL, 10);
            while (*s && *s != ']') s++;
            if (*s) s++;
            x = data_item(x, k);
        } else {
            size_t n = strcspn(s, ".[");
            char *seg = malloc(n + 1);
            memcpy(seg, s, n);
            seg[n] = 0;
            x = data_field(x, intern(e->c, seg));
            free(seg);
            s += n;
        }
    }
    return x;
}

/* The atoms an enum lists, as written, as a list; NULL if t isn't an enum. */
static X *enum_list(Exp *e, const Decl *d, Loc loc)
{
    if (d->kind != L_DEF && d->kind != L_ATOM) return NULL;
    XPtrVec ds = { 0 };
    x_flatten(d->value, X_OR, &ds);
    bool atoms = ds.n > 1;
    for (size_t i = 0; i < ds.n && atoms; i++) {
        X *a = ds.v[i]->k == X_DEFAULT ? ds.v[i]->u.sub : ds.v[i];
        if (a->k != X_ATOM) atoms = false;
        ds.v[i] = a;
    }
    X *l = NULL;
    if (atoms) {
        l = x_new(e->c, X_LIST, loc);
        l->u.list.n = (int) ds.n;
        l->u.list.items = arena_alloc(e->c->load, ds.n * sizeof(X *));
        memcpy(l->u.list.items, ds.v, ds.n * sizeof(X *));
    }
    VEC_FREE(ds);
    return l;
}

static bool expand_decl(Content *c, Decl *d, Loc from);
static X *expand(Exp *e, X *x, const Env *env);

/* A tag or reference anywhere in x, or NULL. */
static const char *x_tag_in(const X *x)
{
    if (!x) return NULL;
    const char *t = NULL;
    switch (x->k) {
    case X_TAG: return x->u.name;
    case X_STRUCT:
        for (int i = 0; i < x->u.st.n && !t; i++) t = x_tag_in(x->u.st.fields[i].value);
        return t;
    case X_LIST:
        for (int i = 0; i < x->u.list.n && !t; i++) t = x_tag_in(x->u.list.items[i]);
        return t ? t : x->u.list.elem ? x_tag_in(x->u.list.elem) : x_tag_in(x->u.list.tail);
    case X_AND: case X_OR: return (t = x_tag_in(x->u.bin.a)) ? t : x_tag_in(x->u.bin.b);
    case X_ARITH: return (t = x_tag_in(x->u.ar.a)) ? t : x_tag_in(x->u.ar.b);
    case X_DEFAULT: return x_tag_in(x->u.sub);
    case X_INTERP:
        for (int i = 0; i < x->u.in.n && !t; i++) t = x_tag_in(x->u.in.parts[i]);
        return t;
    default: return NULL;
    }
}

/* What x stands for as data: a reference's or a name's literal, an enum's
 * atoms; else x itself. */
static X *data_of(Exp *e, X *x, int depth)
{
    if (!x || depth > 64) return x;
    if (x->k == X_TAG && x->u.name[0] == '.') {
        X *v = data_at(e, e->root, x->u.name, depth + 1);
        if (!v) {
            char msg[300];
            snprintf(msg, sizeof msg, "%s is not written in this declaration, so a comprehension can't read it", x->u.name);
            exp_error(e, x->loc, msg);
            return x;
        }
        /* the field as it will be: its own comprehensions expanded */
        if (++e->refdepth > 32) {
            exp_error(e, x->loc, "references that comprehensions read go around in a circle");
            return x;
        }
        v = expand(e, v, NULL);
        e->refdepth--;
        return data_of(e, v, depth + 1);
    }
    if (x->k == X_NAME) {
        build_declidx(e->c);
        const char *s = x->u.name;
        size_t n = strlen(s);
        for (size_t end = n; end > 0; end--) {
            if (end < n && s[end] != '.' && s[end] != '[') continue;
            if (end < n && s[end] == '.' && s[end + 1] == '#') continue;
            char *pre = malloc(end + 1);
            memcpy(pre, s, end);
            pre[end] = 0;
            uint64_t di;
            bool found = u64map_get(&e->c->declidx, (uint64_t) (uintptr_t) intern(e->c, pre), &di);
            free(pre);
            if (!found) continue;
            Decl *d = &e->c->decls.v[di - 1];
            if (d->comp && d->expstate != 2 && !expand_decl(e->c, d, x->loc)) { e->ok = false; return x; }
            if (end == n) {
                X *l = enum_list(e, d, x->loc);
                if (l || d->kind != L_INST) return l ? l : x;
            }
            X *root = e->root;                       /* its references are its own */
            e->root = d->value;
            X *v = end == n ? data_of(e, d->value, depth + 1) : data_at(e, d->value, s + end, depth + 1);
            if (v && end < n) v = data_of(e, v, depth + 1);
            e->root = root;
            const char *tag = v ? x_tag_in(v) : NULL;
            if (tag) {
                char msg[400];
                snprintf(msg, sizeof msg, "%s holds %s, which belongs to %s: a comprehension reads values as written, "
                         "so another declaration's must be plain values", x->u.name, tag, d->label);
                exp_error(e, x->loc, msg);
                return x;
            }
            return v ? v : x;
        }
    }
    return x;
}

static X *atom_of(Exp *e, const char *s, size_t n, Loc loc)
{
    X *a = x_new(e->c, X_ATOM, loc);
    a->u.name = string_canonical(e->c, s, n);
    return a;
}

/* The keys and values a source gives: a list's indexes and items, a struct's
 * labels and values. */
static bool comp_items(Exp *e, X *src, Loc loc, XPtrVec *keys, XPtrVec *vals)
{
    /* expanded: another declaration's data may have comprehensions of its own */
    X *x = expand(e, data_of(e, src, 0), NULL);
    if (!e->ok) return false;
    XPtrVec cj = { 0 };
    x_flatten(x, X_AND, &cj);
    X *list = NULL;
    bool structs = false;
    for (size_t i = 0; i < cj.n; i++) {
        X *k = data_of(e, cj.v[i], 0);
        if (k->k == X_LIST) list = k;
        else if (k->k == X_STRUCT && !k->u.st.refs) structs = true;
    }
    if (list) {
        if (list->u.list.open || list->u.list.tail || list->u.list.elem) {
            exp_error(e, loc, "a comprehension can't go through an open list: its items aren't all written");
            VEC_FREE(cj);
            return false;
        }
        for (int i = 0; i < list->u.list.n; i++) {
            X *k = x_new(e->c, X_NUM, loc);
            k->u.num.dim = DIM_INT;
            k->u.num.q = i;
            VEC_PUSH(*keys, k);
            VEC_PUSH(*vals, list->u.list.items[i]);
        }
    } else if (structs) {
        for (size_t i = 0; i < cj.n; i++) {
            X *k = data_of(e, cj.v[i], 0);
            if (k->k != X_STRUCT || k->u.st.refs) continue;
            for (int f = 0; f < k->u.st.n; f++) {
                XField *fl = &k->u.st.fields[f];
                if (!fl->label) continue;
                VEC_PUSH(*keys, atom_of(e, fl->label, strlen(fl->label), loc));
                VEC_PUSH(*vals, fl->value);
            }
        }
    } else {
        char *t = x_text(src);
        char msg[300];
        snprintf(msg, sizeof msg, "a comprehension goes through a list, a struct, or an enum, written in the content: not %s", t);
        free(t);
        exp_error(e, loc, msg);
    }
    VEC_FREE(cj);
    return e->ok;
}

static bool concrete_number(X *x, int *dim, int64_t *q)
{
    int64_t lo, hi;
    if (!x_interval(x, dim, &lo, &hi) || lo != hi) return false;
    *q = lo;
    return true;
}

/* An if's condition: 1 or 0; -1 after an error. */
static int cond_eval(Exp *e, X *x)
{
    if (!e->ok) return -1;
    switch (x->k) {
    case X_LOGIC: {
        int a = cond_eval(e, x->u.ar.a);
        if (a < 0) return -1;
        if (x->u.ar.op == '&' ? !a : a) return a;
        return cond_eval(e, x->u.ar.b);
    }
    case X_NOT: {
        int a = cond_eval(e, x->u.sub);
        return a < 0 ? -1 : !a;
    }
    case X_CMP: {
        X *a = data_of(e, x->u.ar.a, 0), *b = data_of(e, x->u.ar.b, 0);
        int op = x->u.ar.op;
        int da, db;
        int64_t qa, qb;
        if (concrete_number(a, &da, &qa) && concrete_number(b, &db, &qb)) {
            if (da != db) {
                exp_error(e, x->loc, "a comparison of numbers of different kinds");
                return -1;
            }
            switch (op) {
            case 'e': return qa == qb;
            case 'n': return qa != qb;
            case '<': return qa < qb;
            case 'l': return qa <= qb;
            case '>': return qa > qb;
            default:  return qa >= qb;
            }
        }
        if (a->k == X_ATOM && b->k == X_ATOM && (op == 'e' || op == 'n')) return (a->u.name == b->u.name) == (op == 'e');
        char *ta = x_text(a), *tb = x_text(b);
        char msg[400];
        snprintf(msg, sizeof msg, "a comparison is of values known when content loads: numbers, or strings with == and != (not %s and %s)",
                 ta, tb);
        free(ta);
        free(tb);
        exp_error(e, x->loc, msg);
        return -1;
    }
    default: {
        X *v = data_of(e, x, 0);
        if (v->k == X_ATOM && !strcmp(v->u.name, "true")) return 1;
        if (v->k == X_ATOM && !strcmp(v->u.name, "false")) return 0;
        char *t = x_text(v);
        char msg[300];
        snprintf(msg, sizeof msg, "a condition is true or false, known when content loads: not %s", t);
        free(t);
        exp_error(e, x->loc, msg);
        return -1;
    }
    }
}

/* A computed label: a name, from a string or a string's interpolation. */
static Sym label_of(Exp *e, X *x, Loc loc)
{
    Buf b = { 0 };
    X *v = x->k == X_INTERP ? x : data_of(e, x, 0);
    const char *err = NULL;
    if (v->k == X_INTERP) err = interp_eval(e->c, v, NULL, &b);
    else if (v->k == X_ATOM && v->u.name[0] == '"') string_decode(v->u.name, &b);
    else {
        char *t = x_text(v);
        snprintf(e->c->failwhy, sizeof e->c->failwhy, "a computed label is a string: not %s", t);
        free(t);
        err = e->c->failwhy;
    }
    if (err == ARITH_UNKNOWN) err = "a computed label must be known when content loads";
    bool name = !err && b.len && (isalpha((unsigned char) b.s[0]) || b.s[0] == '_');
    for (size_t i = 0; name && i < b.len; i++) name = isalnum((unsigned char) b.s[i]) || b.s[i] == '_';
    Sym r = NULL;
    if (err) exp_error(e, loc, err);
    else if (!name) {
        char msg[300];
        snprintf(msg, sizeof msg, "a computed label must be a field's name: not \"%.*s\"", (int) b.len, b.s ? b.s : "");
        exp_error(e, loc, msg);
    } else r = intern(e->c, b.s);
    buf_free(&b);
    return r;
}

/* For builtin_call: an argument as data. */
static X *call_data(void *ctx, X *x)
{
    Exp *e = ctx;
    return data_of(e, x, 0);
}

static void comp_run(Exp *e, X *comp, int i, const Env *env, XPtrVec *items, FieldVec *fields)
{
    if (!e->ok) return;
    if (i == comp->u.comp.n) {
        if (++e->made > EXPAND_MAX) {
            char msg[128];
            snprintf(msg, sizeof msg, "comprehensions here make more than %d items or fields", EXPAND_MAX);
            exp_error(e, comp->loc, msg);
            return;
        }
        X *b = expand(e, comp->u.comp.body, env);
        if (!e->ok) return;
        if (comp->u.comp.list) { VEC_PUSH(*items, b); return; }
        if (b->u.st.nattrs) { exp_error(e, b->loc, "a comprehension's fields can't carry a struct's attributes"); return; }
        for (int f = 0; f < b->u.st.n; f++) VEC_PUSH(*fields, b->u.st.fields[f]);
        return;
    }
    CompClause *cl = &comp->u.comp.clauses[i];
    if (cl->kind == C_IF) {
        int v = cond_eval(e, expand(e, cl->expr, env));
        if (v > 0) comp_run(e, comp, i + 1, env, items, fields);
        return;
    }
    XPtrVec keys = { 0 }, vals = { 0 };
    if (comp_items(e, expand(e, cl->expr, env), cl->loc, &keys, &vals))
        for (size_t k = 0; k < vals.n && e->ok; k++) {
            Env ke = { cl->key, keys.v[k], env };
            Env ve = { cl->val, vals.v[k], cl->key ? &ke : env };
            comp_run(e, comp, i + 1, &ve, items, fields);
        }
    VEC_FREE(keys);
    VEC_FREE(vals);
}

static X *x_copy(Exp *e, X *x)
{
    X *n = x_new(e->c, x->k, x->loc);
    *n = *x;
    return n;
}

/* x with its comprehensions expanded, its computed labels made names, and
 * the variables in env replaced by their values. x itself is left alone:
 * its parts may be shared (a let's value, one comprehension's body). */
static X *expand(Exp *e, X *x, const Env *env)
{
    if (!x || !e->ok) return x;
    switch (x->k) {
    case X_VAR: {
        const Env *b = env;
        while (b && b->var != x->u.var.var) b = b->up;
        if (!b) { exp_error(e, x->loc, "a comprehension's variable outside its comprehension"); return x; }
        if (!x->u.var.path) return b->value;
        X *v = data_at(e, b->value, x->u.var.path, 0);
        if (!v) {
            char msg[300];
            snprintf(msg, sizeof msg, "%s%s: its value has no such field or item", x->u.var.var->name, x->u.var.path);
            exp_error(e, x->loc, msg);
            return x;
        }
        return v;
    }
    case X_STRUCT: {
        FieldVec out = { 0 };
        for (int i = 0; i < x->u.st.n && e->ok; i++) {
            XField *f = &x->u.st.fields[i];
            X *fc = field_comp(f);
            if (fc) { comp_run(e, fc, 0, env, NULL, &out); continue; }
            XField g = *f;
            if (f->dlabel) {
                g.label = label_of(e, expand(e, f->dlabel, env), f->loc);
                g.dlabel = NULL;
            }
            g.value = expand(e, f->value, env);
            VEC_PUSH(out, g);
        }
        X *n = x_copy(e, x);
        n->u.st.n = (int) out.n;
        n->u.st.fields = arena_alloc(e->c->load, (out.n ? out.n : 1) * sizeof(XField));
        if (out.n) memcpy(n->u.st.fields, out.v, out.n * sizeof(XField));
        VEC_FREE(out);
        return n;
    }
    case X_LIST: {
        XPtrVec out = { 0 };
        for (int i = 0; i < x->u.list.n && e->ok; i++) {
            X *it = x->u.list.items[i];
            if (it->k == X_COMP) comp_run(e, it, 0, env, &out, NULL);
            else VEC_PUSH(out, expand(e, it, env));
        }
        X *n = x_copy(e, x);
        n->u.list.n = (int) out.n;
        n->u.list.items = arena_alloc(e->c->load, (out.n ? out.n : 1) * sizeof(X *));
        if (out.n) memcpy(n->u.list.items, out.v, out.n * sizeof(X *));
        n->u.list.tail = expand(e, x->u.list.tail, env);
        n->u.list.elem = expand(e, x->u.list.elem, env);
        VEC_FREE(out);
        return n;
    }
    case X_AND: case X_OR: {
        X *n = x_copy(e, x);
        n->u.bin.a = expand(e, x->u.bin.a, env);
        n->u.bin.b = expand(e, x->u.bin.b, env);
        return n;
    }
    case X_ARITH: {
        X *n = x_copy(e, x);
        n->u.ar.a = expand(e, x->u.ar.a, env);
        n->u.ar.b = expand(e, x->u.ar.b, env);
        return n;
    }
    case X_CMP: case X_LOGIC: case X_NOT: {        /* true or false, now */
        X *n = x_copy(e, x);
        if (x->k == X_NOT) n->u.sub = expand(e, x->u.sub, env);
        else {
            n->u.ar.a = expand(e, x->u.ar.a, env);
            n->u.ar.b = expand(e, x->u.ar.b, env);
        }
        int v = cond_eval(e, n);
        if (v < 0) return x;
        X *r = x_new(e->c, X_ATOM, x->loc);
        r->u.name = intern(e->c, v ? "true" : "false");
        return r;
    }
    case X_DEFAULT: {
        X *n = x_copy(e, x);
        n->u.sub = expand(e, x->u.sub, env);
        return n;
    }
    case X_INTERP: {
        X *n = x_copy(e, x);
        n->u.in.parts = arena_alloc(e->c->load, (size_t) (x->u.in.n ? x->u.in.n : 1) * sizeof(X *));
        for (int i = 0; i < x->u.in.n; i++) n->u.in.parts[i] = expand(e, x->u.in.parts[i], env);
        return n;
    }
    case X_COMP:
        exp_error(e, x->loc, "a comprehension stands in a list, or among a struct's fields");
        return x;
    case X_CALL: {
        X *args[8];
        for (int i = 0; i < x->u.call.n && i < 8; i++) args[i] = expand(e, x->u.call.args[i], env);
        if (!e->ok) return x;
        char err[400];
        X *r = builtin_call(e->c, x, args, call_data, e, err, sizeof err);
        if (!r) exp_error(e, x->loc, err);
        return r ? r : x;
    }
    default:
        return x;
    }
}

/* Expands a declaration, once; one a comprehension reads is expanded first. */
static bool expand_decl(Content *c, Decl *d, Loc from)
{
    if (d->expstate == 2) return true;
    if (d->expstate == 1) {
        diag(c, true, from, "%s: its comprehensions read %s, whose comprehensions read it back", d->label, d->label);
        return false;
    }
    d->expstate = 1;
    Exp e = { c, d->value, true, 0, 0 };
    X *v = expand(&e, d->value, NULL);
    d->value = v;                            /* the decls vector doesn't move here */
    d->expstate = 2;
    return e.ok;
}

/* Expands the declarations that have comprehensions or computed labels. */
static bool expand_all(Content *c)
{
    bool ok = true;
    for (size_t i = 0; i < c->decls.n; i++)
        if (c->decls.v[i].comp) ok &= expand_decl(c, &c->decls.v[i], c->decls.v[i].loc);
    return ok;
}

X *expand_value(Content *c, X *x, bool *ok)
{
    Exp e = { c, x, true, 0, 0 };
    X *r = expand(&e, x, NULL);
    *ok = e.ok;
    return r;
}


static void finish_load(Content *c, bool ok, double t0)
{
    double t1 = now_ms();
    c->stats.parse_ms = t1 - t0;
    if (ok && !c->tdl)
        resolve_packages(c);
    if (ok && !c->tdl) ok = expand_all(c);
    if (ok && types_build(c) && check_lets(c)) {
        double t2 = now_ms();
        c->stats.hierarchy_ms = t2 - t1;
        for (uint32_t t = 0; t < c->types.n; t++) type_expansion(c, t);
        double t3 = now_ms();
        c->stats.expansion_ms = t3 - t2;
        if (!c->tdl) {                           /* TDL instances (lexicons) resolve on demand */
            for (uint32_t i = 0; i < c->insts.n; i++) inst_pattern(c, i);
            /* blueprints become specs at load; other instances only on request */
            U32Vec components = { 0 };
            for (uint32_t t = 0; t < c->types.n; t++) if (c->types.v[t].component) VEC_PUSH(components, t);
            for (uint32_t i = 0; i < c->insts.n; i++)
                if (is_blueprint(c, i, &components)) check_blueprint(c, i);
            VEC_FREE(components);
            families_build(c);
        }
        c->stats.instances_ms = now_ms() - t3;
        compute_hash(c);
    }
    c->loaded = true;
}

TriContent *tri_content_load_tdl(const char *topfile)
{
#ifdef TRI_NO_TDL
    Content *nc = calloc(1, sizeof(Content));
    nc->load = tri_arena_new();
    nc->spec = tri_arena_new();
    nc->scratch = tri_arena_new();
    diag(nc, true, noloc, "this library was built without the TDL front end (TRI_NO_TDL); cannot read %s", topfile);
    return nc;
#endif
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
    bool uses_clauses = false;
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
        if (src && (strstr(src, "#Clause") || strstr(src, "#Fact"))) uses_clauses = true;
        free(owned);
    }
    if (uses_clauses) ok &= parse_source(c, intern(c, "<clauses>"), clause_prelude, &c->decls);
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
        free_recs(&t->defaults);
        free_recs(&t->varies);
        free_ariths(&t->ariths);
        if (c->leafcache && c->leafcache[i]) { VEC_FREE(*c->leafcache[i]); free(c->leafcache[i]); }
        VEC_FREE(t->field_attrs);
        VEC_FREE(t->field_feats);
    }
    VEC_FREE(c->types);
    for (size_t i = 0; i < c->insts.n; i++) {
        InstInfo *in = &c->insts.v[i];
        VEC_FREE(in->decls);
        for (size_t k = 0; k < in->vars.n; k++) variant_free(&in->vars.v[k]);
        VEC_FREE(in->vars);
        VEC_FREE(in->specvars);
        for (size_t k = 0; k < in->variation.n; k++) free(in->variation.v[k]);
        VEC_FREE(in->variation);
        for (size_t k = 0; k < in->notes.n; k++) free(in->notes.v[k]);
        VEC_FREE(in->notes);
    }
    VEC_FREE(c->insts);
    free(c->leafcache);
    VEC_FREE(c->listelems);
    for (size_t i = 0; i < c->buildlog.n; i++) free(c->buildlog.v[i]);
    VEC_FREE(c->buildlog);
    families_free(c);
    VEC_FREE(c->fns);
    for (size_t i = 0; i < c->disjs.n; i++) { VEC_FREE(c->disjs.v[i].altx); VEC_FREE(c->disjs.v[i].alts); }
    VEC_FREE(c->disjs);
    u64map_free(&c->disjidx);
    rx_free_all(c);
    VEC_FREE(c->feats);
    VEC_FREE(c->decls);
    VEC_FREE(c->lets);
    u64map_free(&c->declidx);
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
size_t tri_log_count(const TriContent *c) { return c->buildlog.n; }
const char *tri_log_message(const TriContent *c, size_t i) { return i < c->buildlog.n ? c->buildlog.v[i] : NULL; }
uint64_t tri_content_hash(const TriContent *c) { return c->hash; }
size_t tri_diag_count(const TriContent *c) { return c->diags.n; }
const char *tri_diag_message(const TriContent *c, size_t i) { return i < c->diags.n ? c->diags.v[i].msg : NULL; }
int tri_diag_is_error(const TriContent *c, size_t i) { return i < c->diags.n && c->diags.v[i].error; }

int tri_diag_location(const TriContent *c, size_t i, const char **file, int *line, int *col)
{
    if (i >= c->diags.n || !c->diags.v[i].loc.file) return 0;
    const Loc *l = &c->diags.v[i].loc;
    if (file) *file = l->file;
    if (line) *line = l->line;
    if (col) *col = l->col;
    return 1;
}

const char *tri_diag_text(const TriContent *c, size_t i)
{
    if (i >= c->diags.n) return NULL;
    const char *m = c->diags.v[i].msg;
    const char *tag = c->diags.v[i].error ? "error: " : "warning: ";
    const char *r = strstr(m, tag);
    return r ? r + strlen(tag) : m;
}

/* Declarations as written: the prelude's are left out. */
static bool decl_visible(const Decl *d)
{
    return d->loc.file && d->loc.file[0] != '<';
}

size_t tri_decl_count(const TriContent *c)
{
    size_t n = 0;
    for (size_t i = 0; i < c->decls.n; i++) n += decl_visible(&c->decls.v[i]);
    return n;
}

int tri_decl(const TriContent *c, size_t i, TriDecl *out)
{
    for (size_t k = 0; k < c->decls.n; k++) {
        const Decl *d = &c->decls.v[k];
        if (!decl_visible(d)) continue;
        if (i--) continue;
        out->name = d->label;
        out->kind = d->kind == L_DEF ? TRI_DECL_TYPE : d->kind == L_ATOM ? TRI_DECL_ATOM : TRI_DECL_INSTANCE;
        out->package = d->pkg;
        out->file = d->loc.file;
        out->line = d->loc.line;
        out->col = d->loc.col;
        out->doc = d->doc;
        return 1;
    }
    return 0;
}

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

size_t tri_type_feature_count(const TriContent *c, TriType t)
{
    return t < c->types.n ? c->types.v[t].feats.n : 0;
}

const char *tri_type_feature(const TriContent *c, TriType t, size_t i)
{
    if (t >= c->types.n || i >= c->types.v[t].feats.n) return NULL;
    return c->feats.v[c->types.v[t].feats.v[i]].name;
}

size_t tri_type_components(const TriContent *c, TriType t, size_t *out, size_t max)
{
    size_t n = 0, k = 0;
    for (uint32_t u = 0; u < c->types.n; u++) {
        if (!c->types.v[u].component) continue;
        if (is_subtype(c, t, u)) { if (n < max) out[n] = k; n++; }
        k++;
    }
    return n;
}

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
