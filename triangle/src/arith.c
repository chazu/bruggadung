#include "internal.h"
#include <math.h>

/* Arithmetic over quantities: interval arithmetic in exact quanta, with units.
 *
 * A value is a dimension and a closed interval. Sums need one dimension;
 * products and quotients scale by a dimensionless int or fixed value, or
 * combine two dimensions through the product table. Bounds round outward, so
 * the result always contains every exact answer. An infinite bound stays
 * infinite, which is how a constraint waits for its arguments (LIFE-style
 * suspension): the result narrows as they do. */

/* d1 × d2 = r, with r_quanta = d1_quanta × d2_quanta × num / den */
static const struct { int d1, d2, r; int64_t num, den; } products[] = {
    /* force (mN) × length (0.1 mm) = torque (mN·m) */
    { DIM_FORCE, DIM_LENGTH, DIM_TORQUE, 1, 10000 },
};

static bool scalar(int dim) { return dim == DIM_INT || dim == DIM_FIXED; }

static int64_t clamp128(__int128 v)
{
    if (v >= (__int128) TRI_INF) return TRI_INF - 1;
    if (v <= (__int128) TRI_NINF) return TRI_NINF + 1;
    return (int64_t) v;
}

static bool infinite(int64_t v) { return v == TRI_INF || v == TRI_NINF; }

/* a × b for bounds, with infinities */
static __int128 mul_bound(int64_t a, int64_t b, bool *inf, int *sign)
{
    *inf = false;
    if (a == 0 || b == 0) return 0;
    if (infinite(a) || infinite(b)) {
        *inf = true;
        *sign = ((a < 0) != (b < 0)) ? -1 : 1;
        return 0;
    }
    return (__int128) a * b;
}

/* floor or ceiling of v × num / den */
static int64_t scale(__int128 v, int64_t num, int64_t den, bool up)
{
    __int128 t = v * num;
    __int128 q = t / den, r = t % den;
    if (r != 0 && ((t < 0) != (den < 0))) q -= 1;       /* towards -inf */
    if (up && r != 0) q += 1;
    return clamp128(q);
}

static void interval_mul(Quantity a, Quantity b, int64_t num, int64_t den, Quantity *out)
{
    int64_t xs[2] = { a.lo, a.hi }, ys[2] = { b.lo, b.hi };
    bool any_lo_inf = false, any_hi_inf = false;
    __int128 lo = 0, hi = 0;
    bool first = true;
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++) {
            bool inf;
            int sign;
            __int128 p = mul_bound(xs[i], ys[j], &inf, &sign);
            if (inf) { if (sign < 0) any_lo_inf = true; else any_hi_inf = true; continue; }
            if (first || p < lo) lo = p;
            if (first || p > hi) hi = p;
            first = false;
        }
    out->lo = any_lo_inf || first ? TRI_NINF : scale(lo, num, den, false);
    out->hi = any_hi_inf || first ? TRI_INF : scale(hi, num, den, true);
}

/* floor (or ceiling) of n / d, exactly */
static __int128 div_round(__int128 n, __int128 d, bool up)
{
    __int128 q = n / d, r = n % d;
    if (r != 0 && ((r < 0) != (d < 0))) q -= 1;
    if (up && r != 0) q += 1;
    return q;
}

/* a / b: (a × num) / (b × den), rounding outward. An interval b containing
 * zero gives no bound. */
static void interval_div(Quantity a, Quantity b, int64_t num, int64_t den, Quantity *out)
{
    if (b.lo <= 0 && b.hi >= 0) { out->lo = TRI_NINF; out->hi = TRI_INF; return; }
    int64_t xs[2] = { a.lo, a.hi }, ys[2] = { b.lo, b.hi };
    __int128 lo = 0, hi = 0;
    bool lo_inf = false, hi_inf = false, first = true;
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++) {
            __int128 vlo, vhi;
            if (infinite(ys[j])) {
                vlo = vhi = 0;                    /* x / ±inf → 0 */
            } else if (infinite(xs[i])) {
                if ((xs[i] < 0) != (ys[j] < 0)) lo_inf = true; else hi_inf = true;
                continue;
            } else {
                __int128 n = (__int128) xs[i] * num, d = (__int128) ys[j] * den;
                vlo = div_round(n, d, false);
                vhi = div_round(n, d, true);
            }
            if (first || vlo < lo) lo = vlo;
            if (first || vhi > hi) hi = vhi;
            first = false;
        }
    out->lo = lo_inf || first ? TRI_NINF : clamp128(lo);
    out->hi = hi_inf || first ? TRI_INF : clamp128(hi);
}

static int64_t add_bound(int64_t a, int64_t b, bool up)
{
    if (a == TRI_NINF || b == TRI_NINF) return up && (a == TRI_INF || b == TRI_INF) ? TRI_INF : TRI_NINF;
    if (a == TRI_INF || b == TRI_INF) return TRI_INF;
    return clamp128((__int128) a + b);
}

static int64_t neg_bound(int64_t v)
{
    return v == TRI_INF ? TRI_NINF : v == TRI_NINF ? TRI_INF : -v;
}

/* an int value read as fixed */
static Quantity as_fixed(Quantity q)
{
    if (q.dim != DIM_INT) return q;
    q.dim = DIM_FIXED;
    q.lo = infinite(q.lo) ? q.lo : clamp128((__int128) q.lo * 1000);
    q.hi = infinite(q.hi) ? q.hi : clamp128((__int128) q.hi * 1000);
    return q;
}

const char *quantity_op(int op, Quantity a, Quantity b, Quantity *out)
{
    if ((a.dim == DIM_INT && b.dim == DIM_FIXED) || (a.dim == DIM_FIXED && b.dim == DIM_INT)) {
        if (op == '+' || op == '-') { a = as_fixed(a); b = as_fixed(b); }
    }
    switch (op) {
    case '+': case '-':
        if (a.dim != b.dim) return "adding or subtracting needs the same dimension";
        out->dim = a.dim;
        if (op == '+') { out->lo = add_bound(a.lo, b.lo, false); out->hi = add_bound(a.hi, b.hi, true); }
        else { out->lo = add_bound(a.lo, neg_bound(b.hi), false); out->hi = add_bound(a.hi, neg_bound(b.lo), true); }
        return NULL;
    case '*': {
        if (scalar(b.dim) && !scalar(a.dim)) { Quantity t = a; a = b; b = t; }
        if (scalar(a.dim)) {                    /* a scales b */
            int64_t den = a.dim == DIM_FIXED ? 1000 : 1;
            out->dim = b.dim == DIM_INT && a.dim == DIM_FIXED ? DIM_FIXED : b.dim;
            if (b.dim == DIM_INT && a.dim == DIM_FIXED) den = 1;     /* int × fixed is fixed */
            interval_mul(a, b, 1, den, out);
            return NULL;
        }
        for (size_t i = 0; i < sizeof products / sizeof products[0]; i++)
            if ((products[i].d1 == a.dim && products[i].d2 == b.dim) ||
                (products[i].d2 == a.dim && products[i].d1 == b.dim)) {
                out->dim = products[i].r;
                interval_mul(a, b, products[i].num, products[i].den, out);
                return NULL;
            }
        return "no product of these dimensions is defined";
    }
    case '/':
        if (scalar(b.dim)) {
            out->dim = a.dim == DIM_INT && b.dim == DIM_FIXED ? DIM_FIXED : a.dim;
            int64_t num = b.dim == DIM_FIXED ? 1000 : 1;
            if (a.dim == DIM_INT && b.dim == DIM_FIXED) num = 1000000;  /* int / fixed is fixed */
            interval_div(a, b, num, 1, out);
            return NULL;
        }
        if (a.dim == b.dim) {                   /* a ratio: fixed */
            out->dim = DIM_FIXED;
            interval_div(a, b, 1000, 1, out);
            return NULL;
        }
        for (size_t i = 0; i < sizeof products / sizeof products[0]; i++)
            if (products[i].r == a.dim && (products[i].d1 == b.dim || products[i].d2 == b.dim)) {
                out->dim = products[i].d1 == b.dim ? products[i].d2 : products[i].d1;
                interval_div(a, b, products[i].den, products[i].num, out);
                return NULL;
            }
        return "no quotient of these dimensions is defined";
    }
    return "unknown operator";
}

/* Evaluates an arithmetic expression. Returns NULL with the result, an error
 * message, or ARITH_UNKNOWN when some argument is not yet a number. */
const char *const ARITH_UNKNOWN = "unknown";

const char *arith_eval(const X *x, bool (*lookup)(void *ctx, Sym tag, Quantity *q), void *ctx, Quantity *out)
{
    switch (x->k) {
    case X_NUM:
        out->dim = x->u.num.dim;
        out->lo = out->hi = x->u.num.q;
        return NULL;
    case X_TAG:
        return lookup(ctx, x->u.name, out) ? NULL : ARITH_UNKNOWN;
    case X_ARITH: {
        Quantity a, b;
        const char *e = arith_eval(x->u.ar.a, lookup, ctx, &a);
        if (e) return e;
        e = arith_eval(x->u.ar.b, lookup, ctx, &b);
        if (e) return e;
        return quantity_op(x->u.ar.op, a, b, out);
    }
    default:
        return "only numbers, tags, and + - * / may appear in arithmetic";
    }
}

/* Collects the tags an expression uses. */
void arith_tags(const X *x, SymVec *out)
{
    if (x->k == X_TAG) {
        for (size_t i = 0; i < out->n; i++) if (out->v[i] == x->u.name) return;
        VEC_PUSH(*out, x->u.name);
    } else if (x->k == X_ARITH) {
        arith_tags(x->u.ar.a, out);
        arith_tags(x->u.ar.b, out);
    }
}
