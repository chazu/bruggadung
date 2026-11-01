#include "internal.h"

/* Syntax tree helpers: canonical printing (for generated type names) and
 * constructors for trees the loader synthesises. */

static void print_field(Buf *b, const XField *f)
{
    buf_printf(b, "%s: ", f->label);
    x_print(b, f->value);
}

void x_print(Buf *b, const X *x)
{
    switch (x->k) {
    case X_TOP: buf_putc(b, '_'); break;
    case X_NAME: case X_ATOM: case X_TAG: buf_puts(b, x->u.name); break;
    case X_NUM: units_format(b, x->u.num.dim, x->u.num.q); break;
    case X_BOUND:
        buf_puts(b, x->u.bound.op == B_GE ? ">=" : x->u.bound.op == B_LE ? "<=" :
                    x->u.bound.op == B_GT ? ">" : "<");
        units_format(b, x->u.bound.dim, x->u.bound.q);
        break;
    case X_INTERP:
        buf_putc(b, '"');
        for (int i = 0; i <= x->u.in.n; i++) {
            string_escape_into(b, x->u.in.lits[i], strlen(x->u.in.lits[i]));
            if (i == x->u.in.n) break;
            buf_puts(b, "\\(");
            x_print(b, x->u.in.parts[i]);
            buf_putc(b, ')');
        }
        buf_putc(b, '"');
        break;
    case X_REGEX:
        buf_puts(b, x->u.rx.neg ? "!~" : "=~");
        buf_puts(b, x->u.rx.pat);
        break;
    case X_STRUCT:
        buf_puts(b, "{ ");
        for (int i = 0; i < x->u.st.n; i++) {
            if (i) buf_puts(b, ", ");
            print_field(b, &x->u.st.fields[i]);
        }
        buf_puts(b, x->u.st.n ? " }" : "}");
        break;
    case X_LIST:
        buf_putc(b, '[');
        for (int i = 0; i < x->u.list.n; i++) {
            if (i) buf_puts(b, ", ");
            x_print(b, x->u.list.items[i]);
        }
        if (x->u.list.open || x->u.list.elem) {
            buf_puts(b, x->u.list.n ? ", ..." : "...");
            if (x->u.list.elem) x_print(b, x->u.list.elem);
        }
        buf_putc(b, ']');
        break;
    case X_AND: case X_OR: {
        const X *sides[2] = { x->u.bin.a, x->u.bin.b };
        for (int i = 0; i < 2; i++) {
            if (i) buf_puts(b, x->k == X_AND ? " & " : " | ");
            bool paren = x->k == X_AND && sides[i]->k == X_OR;
            if (paren) buf_putc(b, '(');
            x_print(b, sides[i]);
            if (paren) buf_putc(b, ')');
        }
        break;
    }
    case X_DEFAULT:
        buf_putc(b, '*');
        x_print(b, x->u.sub);
        break;
    case X_ARITH:
        buf_putc(b, '(');
        x_print(b, x->u.ar.a);
        buf_printf(b, " %c ", x->u.ar.op);
        x_print(b, x->u.ar.b);
        buf_putc(b, ')');
        break;
    }
}

char *x_text(const X *x)
{
    Buf b = { 0 };
    x_print(&b, x);
    return b.s ? b.s : calloc(1, 1);
}

X *x_new(Content *c, XKind k, Loc loc)
{
    X *x = arena_alloc(c->load, sizeof(X));
    x->k = k;
    x->loc = loc;
    return x;
}

X *x_name(Content *c, Sym name, Loc loc)
{
    X *x = x_new(c, X_NAME, loc);
    x->u.name = name;
    return x;
}

X *x_and(Content *c, X *a, X *b)
{
    if (!a) return b;
    if (!b) return a;
    X *x = x_new(c, X_AND, a->loc);
    x->u.bin.a = a;
    x->u.bin.b = b;
    return x;
}

void x_flatten(X *x, XKind k, XPtrVec *out)
{
    if (x->k == k) { x_flatten(x->u.bin.a, k, out); x_flatten(x->u.bin.b, k, out); }
    else VEC_PUSH(*out, x);
}

/* The interval a numeric expression denotes, if it is one: a number, a bound,
 * a conjunction of those, or the name of a dimension (its whole range). */
bool x_interval(const X *x, int *dim, int64_t *lo, int64_t *hi)
{
    if (x->k == X_DEFAULT) return x_interval(x->u.sub, dim, lo, hi);
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
    if (x->k == X_NAME) {
        for (int d = 0; d < NDIMS; d++)
            if (strcmp(x->u.name, dim_names[d]) == 0) { *dim = d; *lo = TRI_NINF; *hi = TRI_INF; return true; }
        return false;
    }
    if (x->k == X_ARITH) {                       /* constant arithmetic folds, into the kind it has */
        int da, db;
        int64_t la, ha, lb, hb;
        if (!x_interval(x->u.ar.a, &da, &la, &ha) || !x_interval(x->u.ar.b, &db, &lb, &hb)) return false;
        Quantity r, k;
        if (quantity_op(x->u.ar.op, quantity_of(da, la, ha), quantity_of(db, lb, hb), &r)) return false;
        int kd = quantity_kind_for(&r);
        if (kd < 0 || quantity_to(&r, kd, &k)) return false;
        *dim = kd; *lo = k.lo; *hi = k.hi;
        return true;
    }
    if (x->k == X_AND) {
        int d1, d2;
        int64_t l1, h1, l2, h2;
        if (!x_interval(x->u.bin.a, &d1, &l1, &h1) || !x_interval(x->u.bin.b, &d2, &l2, &h2) || d1 != d2)
            return false;
        *dim = d1;
        *lo = l1 > l2 ? l1 : l2;
        *hi = h1 < h2 ? h1 : h2;
        return true;
    }
    return false;
}

static int cmp_iv(const void *a, const void *b)
{
    const int64_t *x = a, *y = b;
    return x[0] < y[0] ? -1 : x[0] > y[0];
}

/* A disjunction of numeric expressions: its hull, and whether the hull adds
 * nothing (the alternatives cover it without gaps). */
bool x_numeric_or(X *x, int *dim, int64_t *lo, int64_t *hi, bool *contiguous)
{
    XPtrVec ds = { 0 };
    x_flatten(x, X_OR, &ds);
    int64_t (*iv)[2] = malloc(sizeof *iv * ds.n);
    bool ok = true;
    *dim = -1;
    for (size_t i = 0; i < ds.n && ok; i++) {
        int d;
        if (!x_interval(ds.v[i], &d, &iv[i][0], &iv[i][1]) || (*dim >= 0 && d != *dim)) ok = false;
        else *dim = d;
    }
    if (ok) {
        qsort(iv, ds.n, sizeof *iv, cmp_iv);
        *lo = iv[0][0];
        *hi = iv[0][1];
        *contiguous = true;
        for (size_t i = 1; i < ds.n; i++) {
            if (*hi != TRI_INF && iv[i][0] > *hi + 1) *contiguous = false;
            if (iv[i][1] > *hi) *hi = iv[i][1];
        }
    }
    free(iv);
    VEC_FREE(ds);
    return ok;
}
