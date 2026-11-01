#include "internal.h"

#include <stdarg.h>

/* --- arena ------------------------------------------------------------------- */

#define CHUNK_SIZE (256 * 1024)

TriArena *tri_arena_new(void)
{
    return calloc(1, sizeof(TriArena));
}

void tri_arena_free(TriArena *a)
{
    if (!a) return;
    Chunk *ch = a->top;
    while (ch) {
        Chunk *prev = ch->prev;
        free(ch);
        ch = prev;
    }
    free(a->spare);
    free(a);
}

void *arena_alloc_raw(TriArena *a, size_t n)
{
    n = (n + 15) & ~(size_t) 15;
    Chunk *ch = a->top;
    if (!ch || ch->used + n > ch->cap) {
        Chunk *nc;
        if (a->spare && a->spare->cap >= n) {
            nc = a->spare;
            a->spare = NULL;
        } else {
            size_t cap = n > CHUNK_SIZE ? n : CHUNK_SIZE;
            nc = malloc(sizeof(Chunk) + cap);
            nc->cap = cap;
        }
        nc->prev = ch;
        nc->used = 0;
        a->top = nc;
        ch = nc;
    }
    void *p = ch->data + ch->used;
    ch->used += n;
    return p;
}

void *arena_alloc(TriArena *a, size_t n)
{
    void *p = arena_alloc_raw(a, n);
    memset(p, 0, n);
    return p;
}

TriMark tri_arena_mark(TriArena *a)
{
    TriMark m = { a->top, a->top ? a->top->used : 0 };
    return m;
}

void tri_arena_release(TriArena *a, TriMark m)
{
    while (a->top && a->top != (Chunk *) m.chunk) {
        Chunk *prev = a->top->prev;
        /* keep one standard chunk, so an operation that crosses a chunk
         * boundary doesn't allocate and free one every time */
        if (!a->spare && a->top->cap == CHUNK_SIZE) a->spare = a->top;
        else free(a->top);
        a->top = prev;
    }
    if (a->top) a->top->used = m.used;
}

/* --- buffers ------------------------------------------------------------------ */

static void buf_reserve(Buf *b, size_t extra)
{
    if (b->len + extra + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 64;
        while (cap < b->len + extra + 1) cap *= 2;
        b->s = realloc(b->s, cap);
        b->cap = cap;
    }
}

void buf_putc(Buf *b, char c)
{
    buf_reserve(b, 1);
    b->s[b->len++] = c;
    b->s[b->len] = 0;
}

void buf_puts(Buf *b, const char *s)
{
    size_t n = strlen(s);
    buf_reserve(b, n);
    memcpy(b->s + b->len, s, n + 1);
    b->len += n;
}

void buf_printf(Buf *b, const char *fmt, ...)
{
    va_list ap, ap2;
    va_start(ap, fmt);
    va_copy(ap2, ap);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    buf_reserve(b, (size_t) n);
    vsnprintf(b->s + b->len, (size_t) n + 1, fmt, ap2);
    va_end(ap2);
    b->len += (size_t) n;
}

void buf_free(Buf *b)
{
    free(b->s);
    b->s = NULL;
    b->len = b->cap = 0;
}

/* --- hashing ------------------------------------------------------------------- */

uint64_t hash64(uint64_t x)
{
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return x;
}

uint64_t fnv1a(uint64_t h, const void *data, size_t n)
{
    const unsigned char *p = data;
    for (size_t i = 0; i < n; i++) {
        h ^= p[i];
        h *= 0x100000001b3ULL;
    }
    return h;
}

/* --- symbols ------------------------------------------------------------------- */

static uint64_t str_hash(const char *s, size_t len)
{
    return fnv1a(0xcbf29ce484222325ULL, s, len);
}

Sym sym_intern(SymTable *t, const char *s, size_t len)
{
    if (t->count * 2 >= t->cap) {
        size_t ncap = t->cap ? t->cap * 2 : 256;
        Sym *ns = calloc(ncap, sizeof(Sym));
        for (size_t i = 0; i < t->cap; i++) {
            Sym e = t->slots[i];
            if (!e) continue;
            size_t j = str_hash(e, strlen(e)) & (ncap - 1);
            while (ns[j]) j = (j + 1) & (ncap - 1);
            ns[j] = e;
        }
        free(t->slots);
        t->slots = ns;
        t->cap = ncap;
    }
    size_t j = str_hash(s, len) & (t->cap - 1);
    while (t->slots[j]) {
        if (strlen(t->slots[j]) == len && memcmp(t->slots[j], s, len) == 0)
            return t->slots[j];
        j = (j + 1) & (t->cap - 1);
    }
    char *copy = malloc(len + 1);
    memcpy(copy, s, len);
    copy[len] = 0;
    t->slots[j] = copy;
    t->count++;
    return copy;
}

void sym_free(SymTable *t)
{
    for (size_t i = 0; i < t->cap; i++) free((void *) t->slots[i]);
    free(t->slots);
    t->slots = NULL;
    t->cap = t->count = 0;
}

/* --- u64 map ----------------------------------------------------------------------- */

static void u64map_grow(U64Map *m)
{
    size_t ncap = m->cap ? m->cap * 2 : 64;
    U64Map n = { calloc(ncap, 8), calloc(ncap, 8), calloc(ncap, 1), ncap, 0 };
    for (size_t i = 0; i < m->cap; i++)
        if (m->used[i]) u64map_put(&n, m->keys[i], m->vals[i]);
    u64map_free(m);
    *m = n;
}

bool u64map_get(const U64Map *m, uint64_t key, uint64_t *val)
{
    if (!m->cap) return false;
    size_t j = hash64(key) & (m->cap - 1);
    while (m->used[j]) {
        if (m->keys[j] == key) {
            if (val) *val = m->vals[j];
            return true;
        }
        j = (j + 1) & (m->cap - 1);
    }
    return false;
}

void u64map_put(U64Map *m, uint64_t key, uint64_t val)
{
    if ((m->count + 1) * 2 > m->cap) u64map_grow(m);
    size_t j = hash64(key) & (m->cap - 1);
    while (m->used[j]) {
        if (m->keys[j] == key) {
            m->vals[j] = val;
            return;
        }
        j = (j + 1) & (m->cap - 1);
    }
    m->used[j] = 1;
    m->keys[j] = key;
    m->vals[j] = val;
    m->count++;
}

void u64map_clear(U64Map *m)
{
    if (m->cap) memset(m->used, 0, m->cap);
    m->count = 0;
}

void u64map_free(U64Map *m)
{
    free(m->keys);
    free(m->vals);
    free(m->used);
    memset(m, 0, sizeof *m);
}

/* --- strings ---------------------------------------------------------------------- */

void string_escape_into(Buf *b, const char *bytes, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        unsigned char ch = (unsigned char) bytes[i];
        switch (ch) {
        case '"':  buf_puts(b, "\\\""); break;
        case '\\': buf_puts(b, "\\\\"); break;
        case '\n': buf_puts(b, "\\n"); break;
        case '\t': buf_puts(b, "\\t"); break;
        case '\r': buf_puts(b, "\\r"); break;
        default:
            if (ch < 0x20 || ch == 0x7f) buf_printf(b, "\\u%04x", ch);
            else buf_putc(b, (char) ch);
        }
    }
}

Sym string_canonical(Content *c, const char *bytes, size_t n)
{
    Buf b = { 0 };
    buf_putc(&b, '"');
    string_escape_into(&b, bytes, n);
    buf_putc(&b, '"');
    Sym r = sym_intern(&c->syms, b.s, b.len);
    buf_free(&b);
    return r;
}

/* Decodes a canonical string (the only escapes are those string_canonical
 * writes); a name without quotes, such as true, is copied as it is. */
void string_decode(const char *q, Buf *out)
{
    buf_puts(out, "");
    if (*q != '"') { buf_puts(out, q); return; }
    for (q++; *q && !(q[0] == '"' && q[1] == 0); q++) {
        if (*q != '\\' || !q[1]) { buf_putc(out, *q); continue; }
        q++;
        switch (*q) {
        case 'n': buf_putc(out, '\n'); break;
        case 't': buf_putc(out, '\t'); break;
        case 'r': buf_putc(out, '\r'); break;
        case 'u': {
            unsigned v = 0;
            for (int k = 1; k <= 4 && q[k]; k++) {
                char h = q[k];
                v = v * 16 + (unsigned) (h <= '9' ? h - '0' : (h | 0x20) - 'a' + 10);
            }
            buf_putc(out, (char) v);       /* canonical \u escapes are control bytes only */
            q += 4;
            break;
        }
        default: buf_putc(out, *q);        /* \" and \\ */
        }
    }
}

/* --- diagnostics ------------------------------------------------------------------- */

void diag(Content *c, bool error, Loc loc, const char *fmt, ...)
{
    Buf b = { 0 };
    if (loc.file) buf_printf(&b, "%s:%d:%d: ", loc.file, loc.line, loc.col);
    buf_puts(&b, error ? "error: " : "warning: ");
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    char *msg = malloc((size_t) n + 1);
    va_start(ap, fmt);
    vsnprintf(msg, (size_t) n + 1, fmt, ap);
    va_end(ap);
    buf_puts(&b, msg);
    free(msg);
    Diag d = { error, b.s, loc };
    VEC_PUSH(c->diags, d);
    if (error) c->nerrors++;
}

Sym intern(Content *c, const char *s)
{
    return sym_intern(&c->syms, s, strlen(s));
}
