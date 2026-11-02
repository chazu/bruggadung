#include "internal.h"

#include <ctype.h>

/* Built-in functions (REFERENCE.md, Built-in functions): CUE's len, div, mod,
 * quo and rem, and a part of its strings, list and math packages. They are
 * evaluated when content loads, with comprehensions (load.c, expand), over
 * data known by then: their arguments arrive as literals, and so does their
 * result. Nothing at runtime calls them. */

typedef struct {
    const char *name;
    int min, max;                 /* arguments */
    const char *sig;              /* for messages */
} Builtin;

static const Builtin builtins[] = {
    { "len", 1, 1, "len(list | struct | string)" },
    { "div", 2, 2, "div(int, int)" },
    { "mod", 2, 2, "mod(int, int)" },
    { "quo", 2, 2, "quo(int, int)" },
    { "rem", 2, 2, "rem(int, int)" },
    { "math.Abs", 1, 1, "math.Abs(number)" },
    { "math.Floor", 1, 1, "math.Floor(int | fixed)" },
    { "math.Ceil", 1, 1, "math.Ceil(int | fixed)" },
    { "math.Round", 1, 1, "math.Round(int | fixed)" },
    { "math.Trunc", 1, 1, "math.Trunc(int | fixed)" },
    { "strings.ToUpper", 1, 1, "strings.ToUpper(string)" },
    { "strings.ToLower", 1, 1, "strings.ToLower(string)" },
    { "strings.TrimSpace", 1, 1, "strings.TrimSpace(string)" },
    { "strings.Contains", 2, 2, "strings.Contains(string, string)" },
    { "strings.HasPrefix", 2, 2, "strings.HasPrefix(string, string)" },
    { "strings.HasSuffix", 2, 2, "strings.HasSuffix(string, string)" },
    { "strings.Index", 2, 2, "strings.Index(string, string)" },
    { "strings.Join", 2, 2, "strings.Join([...string], string)" },
    { "strings.Split", 2, 2, "strings.Split(string, string)" },
    { "strings.Replace", 4, 4, "strings.Replace(string, old, new, int)" },
    { "strings.Repeat", 2, 2, "strings.Repeat(string, int)" },
    { "list.Sum", 1, 1, "list.Sum([...number])" },
    { "list.Product", 1, 1, "list.Product([...int | fixed])" },
    { "list.Max", 1, 1, "list.Max([...number])" },
    { "list.Min", 1, 1, "list.Min([...number])" },
    { "list.Contains", 2, 2, "list.Contains(list, value)" },
    { "list.Concat", 1, 1, "list.Concat([...list])" },
    { "list.Range", 3, 3, "list.Range(int, int, int)" },
    { "list.Slice", 3, 3, "list.Slice(list, int, int)" },
    { "list.Take", 2, 2, "list.Take(list, int)" },
    { "list.Drop", 2, 2, "list.Drop(list, int)" },
    { "list.Repeat", 2, 2, "list.Repeat(list, int)" },
    { "list.SortStrings", 1, 1, "list.SortStrings([...string])" },
};

enum { LIST_MAX = 100000 };

static const Builtin *find(const char *name)
{
    for (size_t i = 0; i < sizeof builtins / sizeof *builtins; i++)
        if (!strcmp(builtins[i].name, name)) return &builtins[i];
    return NULL;
}

size_t tri_function_count(void) { return sizeof builtins / sizeof *builtins; }

const char *tri_function(size_t i, const char **signature)
{
    if (i >= sizeof builtins / sizeof *builtins) return NULL;
    if (signature) *signature = builtins[i].sig;
    return builtins[i].name;
}

const char *builtin_check(Content *c, const char *name, int nargs)
{
    const Builtin *b = find(name);
    if (!b) {
        snprintf(c->failwhy, sizeof c->failwhy,
                 "unknown function %s: the built-ins are len, div, mod, quo, rem, and math., strings. and list. "
                 "functions (REFERENCE.md)", name);
        return c->failwhy;
    }
    if (nargs < b->min || nargs > b->max) {
        snprintf(c->failwhy, sizeof c->failwhy, "%s takes %d argument%s: %s", name, b->min, b->min == 1 ? "" : "s",
                 b->sig);
        return c->failwhy;
    }
    return NULL;
}

/* --- values ------------------------------------------------------------------------ */

typedef struct {
    Content *c;
    const X *call;
    X *(*data)(void *ctx, X *x);
    void *ctx;
    char *err;
    size_t errlen;
} Call;

static X *fail(Call *k, const char *fmt, const char *arg)
{
    char msg[256];
    snprintf(msg, sizeof msg, fmt, arg);
    snprintf(k->err, k->errlen, "%s: %s", k->call->u.call.name, msg);
    return NULL;
}

static X *argv_data(Call *k, X *x) { return k->data(k->ctx, x); }

static bool as_num(Call *k, X *x, int *dim, int64_t *q)
{
    int64_t lo, hi;
    x = argv_data(k, x);
    if (!x_interval(x, dim, &lo, &hi) || lo != hi) return false;
    *q = lo;
    return true;
}

static bool as_int(Call *k, X *x, int64_t *q)
{
    int dim;
    return as_num(k, x, &dim, q) && dim == DIM_INT;
}

/* A string's contents; also an atom's name. */
static bool as_str(Call *k, X *x, Buf *out)
{
    x = argv_data(k, x);
    if (x->k != X_ATOM || x->u.name[0] != '"') return false;
    string_decode(x->u.name, out);
    if (!out->s) buf_puts(out, "");
    return true;
}

static X *as_list(Call *k, X *x)
{
    x = argv_data(k, x);
    if (x->k == X_AND) {
        XPtrVec cj = { 0 };
        x_flatten(x, X_AND, &cj);
        X *l = NULL;
        for (size_t i = 0; i < cj.n && !l; i++) {
            X *d = argv_data(k, cj.v[i]);
            if (d->k == X_LIST) l = d;
        }
        VEC_FREE(cj);
        x = l ? l : x;
    }
    if (x->k != X_LIST || x->u.list.open || x->u.list.tail || x->u.list.elem) return NULL;
    return x;
}

static X *num(Call *k, int dim, int64_t q)
{
    X *x = x_new(k->c, X_NUM, k->call->loc);
    x->u.num.dim = dim;
    x->u.num.q = q;
    return x;
}

static X *str(Call *k, const char *s, size_t n)
{
    X *x = x_new(k->c, X_ATOM, k->call->loc);
    x->u.name = string_canonical(k->c, s, n);
    return x;
}

static X *boolean(Call *k, bool v)
{
    X *x = x_new(k->c, X_ATOM, k->call->loc);
    x->u.name = intern(k->c, v ? "true" : "false");
    return x;
}

static X *list_of(Call *k, X **items, size_t n)
{
    X *x = x_new(k->c, X_LIST, k->call->loc);
    x->u.list.n = (int) n;
    x->u.list.items = arena_alloc(k->c->load, (n ? n : 1) * sizeof(X *));
    if (n) memcpy(x->u.list.items, items, n * sizeof(X *));
    return x;
}

/* Two values known at load are equal: numbers of a kind, or strings and atoms. */
static int equal(Call *k, X *a, X *b)
{
    int da, db;
    int64_t qa, qb;
    if (as_num(k, a, &da, &qa) && as_num(k, b, &db, &qb)) return da == db && qa == qb;
    a = argv_data(k, a);
    b = argv_data(k, b);
    if (a->k == X_ATOM && b->k == X_ATOM) return a->u.name == b->u.name;
    return -1;
}

static const char *find_bytes(const char *h, size_t hn, const char *n, size_t nn)
{
    if (!nn) return h;
    for (size_t i = 0; i + nn <= hn; i++)
        if (h[i] == n[0] && !memcmp(h + i, n, nn)) return h + i;
    return NULL;
}

static int64_t floor_div(int64_t a, int64_t b) { int64_t q = a / b; return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q; }

/* --- the functions ---------------------------------------------------------------- */

static X *call_len(Call *k, X **a)
{
    X *x = argv_data(k, a[0]);
    Buf b = { 0 };
    if (as_str(k, x, &b)) { size_t n = b.len; buf_free(&b); return num(k, DIM_INT, (int64_t) n); }
    X *l = as_list(k, x);
    if (l) return num(k, DIM_INT, l->u.list.n);
    XPtrVec cj = { 0 };
    x_flatten(x, X_AND, &cj);
    int64_t n = 0;
    bool any = false;
    for (size_t i = 0; i < cj.n; i++) {
        X *s = argv_data(k, cj.v[i]);
        if (s->k != X_STRUCT || s->u.st.refs) continue;
        any = true;
        for (int f = 0; f < s->u.st.n; f++) if (s->u.st.fields[f].label) n++;
    }
    VEC_FREE(cj);
    if (!any) return fail(k, "%s", "takes a closed list, a struct, or a string, known when content loads");
    return num(k, DIM_INT, n);
}

static X *call_intdiv(Call *k, X **a, char op)
{
    int64_t x, y;
    if (!as_int(k, a[0], &x) || !as_int(k, a[1], &y)) return fail(k, "%s", "takes two whole numbers known when content loads");
    if (y == 0) return fail(k, "%s", "division by zero");
    /* div and mod are Euclidean, as in CUE: 0 <= mod < |y|, x = y * div + mod;
     * quo and rem truncate toward zero */
    int64_t m = y < 0 ? -y : y;
    int64_t r = ((x % m) + m) % m;
    switch (op) {
    case 'd': return num(k, DIM_INT, (x - r) / y);
    case 'm': return num(k, DIM_INT, r);
    case 'q': return num(k, DIM_INT, x / y);
    default:  return num(k, DIM_INT, x % y);
    }
}

static X *call_math(Call *k, const char *fn, X **a)
{
    int dim;
    int64_t q;
    if (!as_num(k, a[0], &dim, &q) || dim == DIM_TEXT || dim == DIM_REF) return fail(k, "%s", "takes a number known when content loads");
    if (!strcmp(fn, "Abs")) return num(k, dim, q < 0 ? -q : q);
    if (dim == DIM_INT) return num(k, DIM_INT, q);
    if (dim != DIM_FIXED) return fail(k, "%s", "takes a whole or fixed-point number, not a quantity");
    int64_t scale = 1000;
    int64_t f = floor_div(q, scale), r;
    if (!strcmp(fn, "Floor")) r = f;
    else if (!strcmp(fn, "Ceil")) r = q % scale ? f + 1 : f;
    else if (!strcmp(fn, "Trunc")) r = q / scale;
    else r = q >= 0 ? (q + scale / 2) / scale : -((-q + scale / 2) / scale);   /* half away from zero */
    return num(k, DIM_INT, r);
}

static X *call_strings(Call *k, const char *fn, X **a, int n)
{
    Buf s = { 0 }, t = { 0 }, u = { 0 }, out = { 0 };
    X *r = NULL;
    if (!strcmp(fn, "Join")) {
        X *l = as_list(k, a[0]);
        if (!l || !as_str(k, a[1], &t)) { r = fail(k, "%s", "takes a closed list of strings and a separator"); goto done; }
        buf_puts(&out, "");
        for (int i = 0; i < l->u.list.n; i++) {
            Buf item = { 0 };
            if (!as_str(k, l->u.list.items[i], &item)) { buf_free(&item); r = fail(k, "%s", "joins only strings"); goto done; }
            if (i) buf_printf(&out, "%.*s", (int) t.len, t.s);
            buf_printf(&out, "%.*s", (int) item.len, item.s);
            buf_free(&item);
        }
        r = str(k, out.s, out.len);
        goto done;
    }
    if (!as_str(k, a[0], &s)) { r = fail(k, "%s", "takes a string known when content loads"); goto done; }
    if (!strcmp(fn, "ToUpper") || !strcmp(fn, "ToLower")) {
        for (size_t i = 0; i < s.len; i++)
            s.s[i] = (char) (fn[2] == 'U' ? toupper((unsigned char) s.s[i]) : tolower((unsigned char) s.s[i]));
        r = str(k, s.s, s.len);
    } else if (!strcmp(fn, "TrimSpace")) {
        size_t b = 0, e = s.len;
        while (b < e && isspace((unsigned char) s.s[b])) b++;
        while (e > b && isspace((unsigned char) s.s[e - 1])) e--;
        r = str(k, s.s + b, e - b);
    } else if (!strcmp(fn, "Repeat")) {
        int64_t times;
        if (!as_int(k, a[1], &times) || times < 0 || (int64_t) s.len * times > 1000000) {
            r = fail(k, "%s", "repeats a string a whole number of times, to at most a million bytes");
            goto done;
        }
        buf_puts(&out, "");
        for (int64_t i = 0; i < times; i++) buf_printf(&out, "%.*s", (int) s.len, s.s);
        r = str(k, out.s, out.len);
    } else {
        if (!as_str(k, a[1], &t)) { r = fail(k, "%s", "takes strings known when content loads"); goto done; }
        const char *hit = t.len ? find_bytes(s.s, s.len, t.s, t.len) : s.s;
        if (!strcmp(fn, "Contains")) r = boolean(k, hit != NULL);
        else if (!strcmp(fn, "HasPrefix")) r = boolean(k, s.len >= t.len && !memcmp(s.s, t.s, t.len));
        else if (!strcmp(fn, "HasSuffix")) r = boolean(k, s.len >= t.len && !memcmp(s.s + s.len - t.len, t.s, t.len));
        else if (!strcmp(fn, "Index")) r = num(k, DIM_INT, hit ? (int64_t) (hit - s.s) : -1);
        else if (!strcmp(fn, "Split")) {
            VEC(X *) parts = { 0 };
            if (!t.len) {                                  /* into UTF-8 characters */
                for (size_t i = 0; i < s.len;) {
                    size_t j = i + 1;
                    while (j < s.len && ((unsigned char) s.s[j] & 0xC0) == 0x80) j++;
                    VEC_PUSH(parts, str(k, s.s + i, j - i));
                    i = j;
                }
            } else {
                size_t i = 0;
                for (;;) {
                    const char *h = find_bytes(s.s + i, s.len - i, t.s, t.len);
                    size_t e = h ? (size_t) (h - s.s) : s.len;
                    VEC_PUSH(parts, str(k, s.s + i, e - i));
                    if (!h || parts.n > LIST_MAX) break;
                    i = e + t.len;
                }
            }
            r = parts.n > LIST_MAX ? fail(k, "%s", "too many parts") : list_of(k, parts.v, parts.n);
            VEC_FREE(parts);
        } else if (!strcmp(fn, "Replace") && n == 4) {
            int64_t times;
            if (!as_str(k, a[2], &u) || !as_int(k, a[3], &times)) {
                r = fail(k, "%s", "takes a string, old, new, and how many (-1 for all)");
                goto done;
            }
            buf_puts(&out, "");
            size_t i = 0;
            int64_t done = 0;
            while (i <= s.len) {
                const char *h = t.len && (times < 0 || done < times) ? find_bytes(s.s + i, s.len - i, t.s, t.len) : NULL;
                if (!h) { buf_printf(&out, "%.*s", (int) (s.len - i), s.s + i); break; }
                buf_printf(&out, "%.*s%.*s", (int) (h - (s.s + i)), s.s + i, (int) u.len, u.s ? u.s : "");
                i = (size_t) (h - s.s) + t.len;
                done++;
            }
            r = str(k, out.s, out.len);
        }
    }
done:
    buf_free(&s);
    buf_free(&t);
    buf_free(&u);
    buf_free(&out);
    return r;
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(const char *const *) a, *(const char *const *) b);
}

static X *call_list(Call *k, const char *fn, X **a)
{
    if (!strcmp(fn, "Range")) {
        int64_t from, to, step;
        if (!as_int(k, a[0], &from) || !as_int(k, a[1], &to) || !as_int(k, a[2], &step) || step == 0)
            return fail(k, "%s", "takes whole numbers start, limit, and a step that isn't 0");
        VEC(X *) items = { 0 };
        for (int64_t i = from; step > 0 ? i < to : i > to; i += step) {
            if (items.n >= LIST_MAX) { VEC_FREE(items); return fail(k, "%s", "makes too many items"); }
            VEC_PUSH(items, num(k, DIM_INT, i));
        }
        X *r = list_of(k, items.v, items.n);
        VEC_FREE(items);
        return r;
    }
    X *l = as_list(k, a[0]);
    if (!l) return fail(k, "%s", "takes a closed list known when content loads");
    int n = l->u.list.n;
    X **it = l->u.list.items;
    if (!strcmp(fn, "Sum") || !strcmp(fn, "Product") || !strcmp(fn, "Max") || !strcmp(fn, "Min")) {
        bool sum = fn[0] == 'S', prod = fn[0] == 'P';
        if (!n && !sum && !prod) return fail(k, "%s", "of an empty list");
        int dim = DIM_INT;
        int64_t acc = prod ? 1 : 0;
        for (int i = 0; i < n; i++) {
            int d;
            int64_t q;
            if (!as_num(k, it[i], &d, &q) || d == DIM_TEXT || d == DIM_REF) return fail(k, "%s", "takes numbers known when content loads");
            if (i && d != dim) return fail(k, "%s", "takes numbers of one kind");
            dim = d;
            if (prod && d != DIM_INT) return fail(k, "%s", "multiplies whole numbers only");
            if (sum) acc = i ? acc + q : q;
            else if (prod) acc *= q;
            else if (!i || (fn[1] == 'a' ? q > acc : q < acc)) acc = q;
        }
        return num(k, dim, acc);
    }
    if (!strcmp(fn, "Contains")) {
        for (int i = 0; i < n; i++) {
            int e = equal(k, it[i], a[1]);
            if (e < 0) return fail(k, "%s", "compares numbers, strings and atoms only");
            if (e) return boolean(k, true);
        }
        return boolean(k, false);
    }
    if (!strcmp(fn, "Concat")) {
        VEC(X *) items = { 0 };
        for (int i = 0; i < n; i++) {
            X *sub = as_list(k, it[i]);
            if (!sub) { VEC_FREE(items); return fail(k, "%s", "takes a list of closed lists"); }
            for (int j = 0; j < sub->u.list.n; j++) VEC_PUSH(items, sub->u.list.items[j]);
        }
        X *r = list_of(k, items.v, items.n);
        VEC_FREE(items);
        return r;
    }
    if (!strcmp(fn, "SortStrings")) {
        const char **keys = malloc((size_t) (n ? n : 1) * sizeof *keys);
        for (int i = 0; i < n; i++) {
            X *d = argv_data(k, it[i]);
            if (d->k != X_ATOM || d->u.name[0] != '"') { free(keys); return fail(k, "%s", "sorts strings only"); }
            keys[i] = d->u.name;
        }
        qsort(keys, (size_t) n, sizeof *keys, cmp_str);   /* canonical spellings: byte order of contents, mostly */
        X **items = malloc((size_t) (n ? n : 1) * sizeof *items);
        for (int i = 0; i < n; i++) {
            items[i] = x_new(k->c, X_ATOM, k->call->loc);
            items[i]->u.name = keys[i];
        }
        X *r = list_of(k, items, (size_t) n);
        free(items);
        free(keys);
        return r;
    }
    int64_t i0, i1 = n;
    if (!as_int(k, a[1], &i0)) return fail(k, "%s", "takes whole numbers for its positions");
    if (!strcmp(fn, "Slice") && !as_int(k, a[2], &i1)) return fail(k, "%s", "takes whole numbers for its positions");
    if (!strcmp(fn, "Take")) { i1 = i0 < n ? i0 : n; i0 = 0; }
    if (!strcmp(fn, "Drop")) { i0 = i0 < n ? i0 : n; i1 = n; }
    if (!strcmp(fn, "Repeat")) {
        if (i0 < 0 || (int64_t) n * i0 > LIST_MAX) return fail(k, "%s", "repeats a list a whole number of times, within limits");
        VEC(X *) items = { 0 };
        for (int64_t r = 0; r < i0; r++) for (int j = 0; j < n; j++) VEC_PUSH(items, it[j]);
        X *res = list_of(k, items.v, items.n);
        VEC_FREE(items);
        return res;
    }
    if (i0 < 0 || i1 < i0 || i1 > n) return fail(k, "%s", "positions outside the list");
    return list_of(k, it + i0, (size_t) (i1 - i0));
}

X *builtin_call(Content *c, const X *call, X **args, X *(*data)(void *ctx, X *x), void *ctx, char *err, size_t errlen)
{
    Call k = { c, call, data, ctx, err, errlen };
    const char *name = call->u.call.name;
    int n = call->u.call.n;
    err[0] = 0;
    if (!strcmp(name, "len")) return call_len(&k, args);
    if (!strcmp(name, "div")) return call_intdiv(&k, args, 'd');
    if (!strcmp(name, "mod")) return call_intdiv(&k, args, 'm');
    if (!strcmp(name, "quo")) return call_intdiv(&k, args, 'q');
    if (!strcmp(name, "rem")) return call_intdiv(&k, args, 'r');
    if (!strncmp(name, "math.", 5)) return call_math(&k, name + 5, args);
    if (!strncmp(name, "strings.", 8)) return call_strings(&k, name + 8, args, n);
    if (!strncmp(name, "list.", 5)) return call_list(&k, name + 5, args);
    return fail(&k, "%s", "is not a built-in function");
}
