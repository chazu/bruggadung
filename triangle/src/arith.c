#include "internal.h"

/* Arithmetic over quantities: interval arithmetic in exact quanta, with units.
 *
 * A value carries its exponents over the base units (m, kg, s, K, mol) and its
 * quantum in those units, so intermediate results need not be a named kind:
 * length × length is an area on the way to a volume. Only a final result is
 * converted to its field's kind. Sums need equal exponents and work in the
 * largest quantum dividing both; products and quotients add or subtract
 * exponents. Bounds round outward, so a result always contains every exact
 * answer. An infinite bound stays infinite, which is how a constraint waits
 * for its arguments (LIFE-style suspension): the result narrows as they do.
 *
 * Constraints also narrow backwards where that is exact enough to be useful:
 * through sums and differences, and through scaling by a constant. */

static __int128 gcd128(__int128 a, __int128 b)
{
    if (a < 0) a = -a;
    if (b < 0) b = -b;
    while (b) { __int128 t = a % b; a = b; b = t; }
    return a ? a : 1;
}

static int64_t clamp128(__int128 v)
{
    if (v >= (__int128) TRI_INF) return TRI_INF - 1;
    if (v <= (__int128) TRI_NINF) return TRI_NINF + 1;
    return (int64_t) v;
}

static bool infinite(int64_t v) { return v == TRI_INF || v == TRI_NINF; }

/* floor (or ceiling) of n / d, exactly */
static __int128 div_round(__int128 n, __int128 d, bool up)
{
    __int128 q = n / d, r = n % d;
    if (r != 0 && ((r < 0) != (d < 0))) q -= 1;
    if (up && r != 0) q += 1;
    return q;
}

/* a bound times num / den, rounded down (or up); infinities stay */
static int64_t rescale(int64_t v, __int128 num, __int128 den, bool up)
{
    if (infinite(v)) return v;
    return clamp128(div_round((__int128) v * num, den, up));
}

Quantity quantity_of(int dim, int64_t lo, int64_t hi)
{
    Quantity q;
    q.dim = dim;
    q.lo = lo;
    q.hi = hi;
    memcpy(q.exp, quantity_kinds[dim].exp, sizeof q.exp);
    q.qnum = quantity_kinds[dim].qnum;
    q.qden = quantity_kinds[dim].qden;
    return q;
}

static void set_quantum(Quantity *q, __int128 num, __int128 den)
{
    __int128 g = gcd128(num, den);
    num /= g;
    den /= g;
    q->qnum = clamp128(num);
    q->qden = clamp128(den);
}

/* The kind with q's exponents, preferring one with q's quantum. Dimensionless
 * values are int in quantum 1, fixed otherwise. -1 if no kind has them. */
int quantity_kind_for(const Quantity *q)
{
    bool zero = true;
    for (int i = 0; i < 5; i++) zero &= q->exp[i] == 0;
    if (zero) return q->qden == 1 && q->qnum == 1 ? DIM_INT : DIM_FIXED;
    int best = -1;
    for (int d = 0; d < NDIMS; d++) {
        if (!quantity_kinds[d].quantity || d == DIM_INT || d == DIM_FIXED) continue;
        if (memcmp(quantity_kinds[d].exp, q->exp, sizeof q->exp)) continue;
        if (quantity_kinds[d].qnum == q->qnum && quantity_kinds[d].qden == q->qden) return d;
        if (best < 0) best = d;
    }
    return best;
}

const char *quantity_to(const Quantity *q, int dim, Quantity *out)
{
    const QuantityKind *k = &quantity_kinds[dim];
    if (!k->quantity || memcmp(k->exp, q->exp, sizeof q->exp)) return "a value of another dimension";
    /* value × (q's quantum / the kind's quantum) */
    __int128 num = (__int128) q->qnum * k->qden, den = (__int128) q->qden * k->qnum;
    __int128 g = gcd128(num, den);
    num /= g;
    den /= g;
    *out = quantity_of(dim, rescale(q->lo, num, den, false), rescale(q->hi, num, den, true));
    return NULL;
}

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

static void interval_mul(const Quantity *a, const Quantity *b, Quantity *out)
{
    int64_t xs[2] = { a->lo, a->hi }, ys[2] = { b->lo, b->hi };
    bool lo_inf = false, hi_inf = false, first = true;
    __int128 lo = 0, hi = 0;
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++) {
            bool inf;
            int sign;
            __int128 p = mul_bound(xs[i], ys[j], &inf, &sign);
            if (inf) { if (sign < 0) lo_inf = true; else hi_inf = true; continue; }
            if (first || p < lo) lo = p;
            if (first || p > hi) hi = p;
            first = false;
        }
    out->lo = lo_inf || first ? TRI_NINF : clamp128(lo);
    out->hi = hi_inf || first ? TRI_INF : clamp128(hi);
}

/* (a × scale) / b, rounding outward; b containing zero gives no bound */
static void interval_div(const Quantity *a, const Quantity *b, int64_t scale, Quantity *out)
{
    if (b->lo <= 0 && b->hi >= 0) { out->lo = TRI_NINF; out->hi = TRI_INF; return; }
    int64_t xs[2] = { a->lo, a->hi }, ys[2] = { b->lo, b->hi };
    __int128 lo = 0, hi = 0;
    bool lo_inf = false, hi_inf = false, first = true;
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++) {
            __int128 vlo, vhi;
            if (infinite(ys[j])) {
                vlo = vhi = 0;
            } else if (infinite(xs[i])) {
                if ((xs[i] < 0) != (ys[j] < 0)) lo_inf = true; else hi_inf = true;
                continue;
            } else {
                __int128 n = (__int128) xs[i] * scale;
                vlo = div_round(n, ys[j], false);
                vhi = div_round(n, ys[j], true);
            }
            if (first || vlo < lo) lo = vlo;
            if (first || vhi > hi) hi = vhi;
            first = false;
        }
    out->lo = lo_inf || first ? TRI_NINF : clamp128(lo);
    out->hi = hi_inf || first ? TRI_INF : clamp128(hi);
}

static int64_t add_bound(int64_t a, int64_t b)
{
    if (a == TRI_NINF || b == TRI_NINF) return (a == TRI_INF || b == TRI_INF) ? TRI_INF : TRI_NINF;
    if (a == TRI_INF || b == TRI_INF) return TRI_INF;
    return clamp128((__int128) a + b);
}

static int64_t neg_bound(int64_t v)
{
    return v == TRI_INF ? TRI_NINF : v == TRI_NINF ? TRI_INF : -v;
}

/* Brings two values of equal exponents to a common quantum: the largest that
 * divides both quanta exactly. */
static void common_quantum(Quantity *a, Quantity *b)
{
    if (a->qnum == b->qnum && a->qden == b->qden) return;
    __int128 x = (__int128) a->qnum * b->qden, y = (__int128) b->qnum * a->qden, d = (__int128) a->qden * b->qden;
    __int128 g = gcd128(x, y);               /* the common quantum is g / d */
    __int128 fa = x / g, fb = y / g;          /* each value in common quanta: value × f */
    a->lo = infinite(a->lo) ? a->lo : clamp128(a->lo * fa);
    a->hi = infinite(a->hi) ? a->hi : clamp128(a->hi * fa);
    b->lo = infinite(b->lo) ? b->lo : clamp128(b->lo * fb);
    b->hi = infinite(b->hi) ? b->hi : clamp128(b->hi * fb);
    set_quantum(a, g, d);
    set_quantum(b, g, d);
}

/* Quotients are computed this many times finer than their operands' quanta,
 * so that little is lost before the final conversion. */
#define DIV_SCALE 1000000

const char *quantity_op(int op, Quantity a, Quantity b, Quantity *out)
{
    if (a.dim >= 0 && !quantity_kinds[a.dim].quantity) return "not a quantity";
    if (b.dim >= 0 && !quantity_kinds[b.dim].quantity) return "not a quantity";
    switch (op) {
    case '+': case '-':
        if (memcmp(a.exp, b.exp, sizeof a.exp)) return "adding or subtracting needs the same dimension";
        common_quantum(&a, &b);
        memcpy(out->exp, a.exp, sizeof a.exp);
        out->qnum = a.qnum;
        out->qden = a.qden;
        if (op == '+') { out->lo = add_bound(a.lo, b.lo); out->hi = add_bound(a.hi, b.hi); }
        else { out->lo = add_bound(a.lo, neg_bound(b.hi)); out->hi = add_bound(a.hi, neg_bound(b.lo)); }
        break;
    case '*':
        for (int i = 0; i < 5; i++) out->exp[i] = (int8_t) (a.exp[i] + b.exp[i]);
        set_quantum(out, (__int128) a.qnum * b.qnum, (__int128) a.qden * b.qden);
        interval_mul(&a, &b, out);
        break;
    case '/':
        for (int i = 0; i < 5; i++) out->exp[i] = (int8_t) (a.exp[i] - b.exp[i]);
        set_quantum(out, (__int128) a.qnum * b.qden, (__int128) a.qden * b.qnum * DIV_SCALE);
        interval_div(&a, &b, DIV_SCALE, out);
        break;
    default:
        return "unknown operator";
    }
    /* named only if it is already in that kind's quanta */
    int d = quantity_kind_for(out);
    out->dim = d >= 0 && quantity_kinds[d].qnum == out->qnum && quantity_kinds[d].qden == out->qden ? d : -1;
    return NULL;
}

/* Evaluates an arithmetic expression. Returns NULL with the result, an error
 * message, or ARITH_UNKNOWN when some argument is not yet a number. */
const char *const ARITH_UNKNOWN = "unknown";

const char *arith_eval(const X *x, bool (*lookup)(void *ctx, Sym tag, Quantity *q), void *ctx, Quantity *out)
{
    switch (x->k) {
    case X_NUM:
        *out = quantity_of(x->u.num.dim, x->u.num.q, x->u.num.q);
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

/* Backward narrowing: given that expression x lies within `want`, narrow the
 * tags it reads, through sums, differences, and scaling by a constant. Each
 * narrowing goes to `narrow` with the tag and the interval it must lie in, in
 * the tag's own kind. Products and quotients of two variables are not
 * inverted. */
void arith_narrow(const X *x, Quantity want, bool (*lookup)(void *ctx, Sym tag, Quantity *q), void *ctx,
                  void (*narrow)(void *ctx, Sym tag, const Quantity *q))
{
    if (x->k == X_TAG) {
        Quantity cur, conv;
        if (!lookup(ctx, x->u.name, &cur) || cur.dim < 0) return;
        if (quantity_to(&want, cur.dim, &conv)) return;
        narrow(ctx, x->u.name, &conv);
        return;
    }
    if (x->k != X_ARITH) return;
    const X *xa = x->u.ar.a, *xb = x->u.ar.b;
    Quantity a, b, r;
    bool ka = !arith_eval(xa, lookup, ctx, &a), kb = !arith_eval(xb, lookup, ctx, &b);
    switch (x->u.ar.op) {
    case '+':                                   /* a ∈ want − b, b ∈ want − a */
        if (kb && !quantity_op('-', want, b, &r)) arith_narrow(xa, r, lookup, ctx, narrow);
        if (ka && !quantity_op('-', want, a, &r)) arith_narrow(xb, r, lookup, ctx, narrow);
        break;
    case '-':                                   /* a ∈ want + b, b ∈ a − want */
        if (kb && !quantity_op('+', want, b, &r)) arith_narrow(xa, r, lookup, ctx, narrow);
        if (ka && !quantity_op('-', a, want, &r)) arith_narrow(xb, r, lookup, ctx, narrow);
        break;
    case '*':                                   /* by a nonzero constant: divide it out */
        if (xb->k == X_NUM && b.lo != 0 && !quantity_op('/', want, b, &r)) arith_narrow(xa, r, lookup, ctx, narrow);
        else if (xa->k == X_NUM && a.lo != 0 && !quantity_op('/', want, a, &r)) arith_narrow(xb, r, lookup, ctx, narrow);
        break;
    case '/':                                   /* by a nonzero constant: multiply it back */
        if (xb->k == X_NUM && b.lo != 0) {
            /* a / b lies in want, and a / b was rounded outward from a, so a
             * lies in want × b widened by one of want's quanta on each side */
            Quantity wider = want;
            wider.lo = wider.lo == TRI_NINF ? wider.lo : wider.lo - 1;
            wider.hi = wider.hi == TRI_INF ? wider.hi : wider.hi + 1;
            if (!quantity_op('*', wider, b, &r)) arith_narrow(xa, r, lookup, ctx, narrow);
        }
        break;
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
    } else if (x->k == X_INTERP) {
        for (int i = 0; i < x->u.in.n; i++) arith_tags(x->u.in.parts[i], out);
    }
}
