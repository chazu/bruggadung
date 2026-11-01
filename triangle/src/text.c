#include "internal.h"

/* Regex constraints on text: the =~ and !~ of a text value that is not yet
 * concrete. A value carries the set of constraints it must meet; unifying two
 * values takes the union of their sets, and a concrete string must meet every
 * constraint in the set. Sets are interned per content, so they compare by
 * pointer and live as long as the content. */

const RxSet *text_rx(int64_t lo, int64_t hi)
{
    return lo == TRI_NINF && hi != TRI_INF ? (const RxSet *) (intptr_t) hi : NULL;
}

static int cmp_item(const RxItem *a, const RxItem *b)
{
    int d = strcmp(a->pat, b->pat);
    return d ? d : (int) a->neg - (int) b->neg;
}

static uint64_t set_hash(const RxItem *v, uint32_t n)
{
    uint64_t h = 0x7E57;
    for (uint32_t i = 0; i < n; i++) {
        h = fnv1a(h, v[i].pat, strlen(v[i].pat));
        h = hash64(h ^ (uint64_t) v[i].neg);
    }
    return h ? h : 1;
}

/* The interned set with these items (sorted, without repeats). */
static const RxSet *intern_set(Content *c, const RxItem *v, uint32_t n)
{
    if (!n) return NULL;
    uint64_t h = set_hash(v, n), k = h, idx;
    while (u64map_get(&c->rxsetidx, k, &idx)) {
        const RxSet *s = c->rxsets.v[idx - 1];
        if (s->hash == h && s->n == n) {
            uint32_t i = 0;
            while (i < n && s->v[i].pat == v[i].pat && s->v[i].neg == v[i].neg) i++;
            if (i == n) return s;
        }
        k = hash64(k);
    }
    RxSet *s = malloc(sizeof *s);
    s->n = n;
    s->hash = h;
    s->v = malloc(n * sizeof *s->v);
    memcpy(s->v, v, n * sizeof *v);
    VEC_PUSH(c->rxsets, s);
    u64map_put(&c->rxsetidx, k, c->rxsets.n);
    return s;
}

const RxSet *rx_single(Content *c, Sym pat, bool neg, char *err, size_t errlen)
{
    uint64_t v;
    Regex *re;
    if (u64map_get(&c->rxcache, (uint64_t) (uintptr_t) pat, &v)) re = (Regex *) (uintptr_t) v;
    else {
        Buf b = { 0 };
        string_decode(pat, &b);
        re = regex_compile(b.s, b.len, err, errlen);
        buf_free(&b);
        if (!re) return NULL;
        u64map_put(&c->rxcache, (uint64_t) (uintptr_t) pat, (uint64_t) (uintptr_t) re);
    }
    RxItem it = { pat, neg, re };
    return intern_set(c, &it, 1);
}

const RxSet *rx_union(Content *c, const RxSet *a, const RxSet *b)
{
    if (!a || a == b) return b ? b : a;
    if (!b) return a;
    RxItem *v = malloc((a->n + b->n) * sizeof *v);
    uint32_t i = 0, j = 0, n = 0;
    while (i < a->n || j < b->n) {
        int d = i == a->n ? 1 : j == b->n ? -1 : cmp_item(&a->v[i], &b->v[j]);
        if (d <= 0) v[n++] = a->v[i++];
        else v[n++] = b->v[j++];
        if (d == 0) j++;
    }
    const RxSet *r = intern_set(c, v, n);
    free(v);
    return r;
}

const RxSet *rx_common(Content *c, const RxSet *a, const RxSet *b)
{
    if (!a || !b) return NULL;
    if (a == b) return a;
    RxItem *v = malloc((a->n < b->n ? a->n : b->n) * sizeof *v + 1);
    uint32_t i = 0, j = 0, n = 0;
    while (i < a->n && j < b->n) {
        int d = cmp_item(&a->v[i], &b->v[j]);
        if (d == 0) { v[n++] = a->v[i]; i++; j++; }
        else if (d < 0) i++;
        else j++;
    }
    const RxSet *r = intern_set(c, v, n);
    free(v);
    return r;
}

static bool item_accepts(const RxItem *it, const char *s, size_t n)
{
    return regex_match(it->re, s, n) != it->neg;
}

bool rx_accepts(const RxSet *set, Sym text)
{
    if (!set) return true;
    Buf b = { 0 };
    string_decode(text, &b);
    bool ok = true;
    for (uint32_t i = 0; i < set->n && ok; i++) ok = item_accepts(&set->v[i], b.s, b.len);
    buf_free(&b);
    return ok;
}

const RxSet *rx_satisfied(Content *c, const RxSet *set, Sym text)
{
    if (!set) return NULL;
    Buf b = { 0 };
    string_decode(text, &b);
    RxItem *v = malloc(set->n * sizeof *v);
    uint32_t n = 0;
    for (uint32_t i = 0; i < set->n; i++)
        if (item_accepts(&set->v[i], b.s, b.len)) v[n++] = set->v[i];
    buf_free(&b);
    const RxSet *r = intern_set(c, v, n);
    free(v);
    return r;
}

bool rx_subset(const RxSet *a, const RxSet *b)
{
    if (!a || a == b) return true;
    if (!b) return false;
    uint32_t j = 0;
    for (uint32_t i = 0; i < a->n; i++) {
        while (j < b->n && cmp_item(&b->v[j], &a->v[i]) < 0) j++;
        if (j == b->n || cmp_item(&b->v[j], &a->v[i]) != 0) return false;
    }
    return true;
}

void rx_print(Buf *b, const RxSet *s)
{
    for (uint32_t i = 0; s && i < s->n; i++) {
        if (i) buf_puts(b, " & ");
        buf_puts(b, s->v[i].neg ? "!~" : "=~");
        buf_puts(b, s->v[i].pat);
    }
}

static void free_regex_val(uint64_t v) { regex_free((Regex *) (uintptr_t) v); }

void rx_free_all(Content *c)
{
    for (size_t i = 0; i < c->rxsets.n; i++) { free(c->rxsets.v[i]->v); free(c->rxsets.v[i]); }
    VEC_FREE(c->rxsets);
    u64map_free(&c->rxsetidx);
    /* the cache map is never iterated elsewhere; walk its slots to free them */
    for (size_t i = 0; i < c->rxcache.cap; i++)
        if (c->rxcache.used[i]) free_regex_val(c->rxcache.vals[i]);
    u64map_free(&c->rxcache);
}
