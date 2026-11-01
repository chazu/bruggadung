#include "json.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* --- strings ---------------------------------------------------------------------- */

static void str_grow(Str *b, size_t extra)
{
    if (b->len + extra + 1 <= b->cap) return;
    size_t cap = b->cap ? b->cap : 64;
    while (cap < b->len + extra + 1) cap *= 2;
    b->s = realloc(b->s, cap);
    b->cap = cap;
}

void str_putn(Str *b, const char *s, size_t n)
{
    str_grow(b, n);
    memcpy(b->s + b->len, s, n);
    b->len += n;
    b->s[b->len] = 0;
}

void str_putc(Str *b, char c) { str_putn(b, &c, 1); }
void str_puts(Str *b, const char *s) { str_putn(b, s, strlen(s)); }

void str_printf(Str *b, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    str_grow(b, (size_t) n);
    va_start(ap, fmt);
    vsnprintf(b->s + b->len, (size_t) n + 1, fmt, ap);
    va_end(ap);
    b->len += (size_t) n;
}

void str_free(Str *b)
{
    free(b->s);
    b->s = NULL;
    b->len = b->cap = 0;
}

void str_jsonn(Str *b, const char *s, size_t n)
{
    str_putc(b, '"');
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char) s[i];
        switch (c) {
        case '"':  str_puts(b, "\\\""); break;
        case '\\': str_puts(b, "\\\\"); break;
        case '\n': str_puts(b, "\\n"); break;
        case '\r': str_puts(b, "\\r"); break;
        case '\t': str_puts(b, "\\t"); break;
        default:
            if (c < 0x20) str_printf(b, "\\u%04x", c);
            else str_putc(b, (char) c);
        }
    }
    str_putc(b, '"');
}

void str_json(Str *b, const char *s) { str_jsonn(b, s ? s : "", s ? strlen(s) : 0); }

void str_value(Str *b, const J *j)
{
    if (!j) { str_puts(b, "null"); return; }
    switch (j->k) {
    case J_NULL:  str_puts(b, "null"); break;
    case J_FALSE: str_puts(b, "false"); break;
    case J_TRUE:  str_puts(b, "true"); break;
    case J_NUM:
        if (j->num == (double) (long long) j->num) str_printf(b, "%lld", (long long) j->num);
        else str_printf(b, "%.17g", j->num);
        break;
    case J_STR: str_json(b, j->str); break;
    case J_ARR:
    case J_OBJ:
        str_putc(b, j->k == J_ARR ? '[' : '{');
        for (size_t i = 0; i < j->n; i++) {
            if (i) str_putc(b, ',');
            if (j->k == J_OBJ) { str_json(b, j->items[i].key); str_putc(b, ':'); }
            str_value(b, &j->items[i]);
        }
        str_putc(b, j->k == J_ARR ? ']' : '}');
        break;
    }
}

/* --- parsing ---------------------------------------------------------------------- */

typedef struct { const char *s, *end; int depth; } P;

static void ws(P *p)
{
    while (p->s < p->end && (*p->s == ' ' || *p->s == '\t' || *p->s == '\n' || *p->s == '\r')) p->s++;
}

static void put_utf8(Str *b, unsigned cp)
{
    if (cp < 0x80) str_putc(b, (char) cp);
    else if (cp < 0x800) { str_putc(b, (char) (0xC0 | cp >> 6)); str_putc(b, (char) (0x80 | (cp & 0x3F))); }
    else if (cp < 0x10000) {
        str_putc(b, (char) (0xE0 | cp >> 12));
        str_putc(b, (char) (0x80 | ((cp >> 6) & 0x3F)));
        str_putc(b, (char) (0x80 | (cp & 0x3F)));
    } else {
        str_putc(b, (char) (0xF0 | cp >> 18));
        str_putc(b, (char) (0x80 | ((cp >> 12) & 0x3F)));
        str_putc(b, (char) (0x80 | ((cp >> 6) & 0x3F)));
        str_putc(b, (char) (0x80 | (cp & 0x3F)));
    }
}

static int hex4(P *p, unsigned *out)
{
    if (p->end - p->s < 4) return 0;
    unsigned v = 0;
    for (int i = 0; i < 4; i++) {
        char c = *p->s++;
        v <<= 4;
        if (c >= '0' && c <= '9') v |= (unsigned) (c - '0');
        else if (c >= 'a' && c <= 'f') v |= (unsigned) (c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') v |= (unsigned) (c - 'A' + 10);
        else return 0;
    }
    *out = v;
    return 1;
}

static char *string(P *p)
{
    if (p->s >= p->end || *p->s != '"') return NULL;
    p->s++;
    Str b = { 0 };
    str_puts(&b, "");
    while (p->s < p->end && *p->s != '"') {
        char c = *p->s++;
        if (c != '\\') { str_putc(&b, c); continue; }
        if (p->s >= p->end) break;
        c = *p->s++;
        switch (c) {
        case 'n': str_putc(&b, '\n'); break;
        case 't': str_putc(&b, '\t'); break;
        case 'r': str_putc(&b, '\r'); break;
        case 'b': str_putc(&b, '\b'); break;
        case 'f': str_putc(&b, '\f'); break;
        case 'u': {
            unsigned cp;
            if (!hex4(p, &cp)) { str_free(&b); return NULL; }
            if (cp >= 0xD800 && cp < 0xDC00 && p->end - p->s >= 6 && p->s[0] == '\\' && p->s[1] == 'u') {
                unsigned lo;
                p->s += 2;
                if (!hex4(p, &lo)) { str_free(&b); return NULL; }
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            }
            put_utf8(&b, cp);
            break;
        }
        default: str_putc(&b, c);
        }
    }
    if (p->s >= p->end) { str_free(&b); return NULL; }
    p->s++;
    return b.s;
}

static int value(P *p, J *out);

static int push(J **items, size_t *n, size_t *cap, J *v)
{
    if (*n == *cap) {
        *cap = *cap ? *cap * 2 : 4;
        *items = realloc(*items, *cap * sizeof **items);
    }
    (*items)[(*n)++] = *v;
    return 1;
}

static void clear(J *j)
{
    free(j->str);
    free(j->key);
    for (size_t i = 0; i < j->n; i++) clear(&j->items[i]);
    free(j->items);
}

static int value(P *p, J *out)
{
    memset(out, 0, sizeof *out);
    ws(p);
    if (p->s >= p->end || ++p->depth > 256) return 0;
    char c = *p->s;
    int ok = 1;
    if (c == '"') {
        out->k = J_STR;
        ok = (out->str = string(p)) != NULL;
    } else if (c == '{' || c == '[') {
        out->k = c == '{' ? J_OBJ : J_ARR;
        char close = c == '{' ? '}' : ']';
        p->s++;
        size_t cap = 0;
        ws(p);
        if (p->s < p->end && *p->s == close) p->s++;
        else for (;;) {
            char *key = NULL;
            if (out->k == J_OBJ) {
                ws(p);
                if (!(key = string(p))) { ok = 0; break; }
                ws(p);
                if (p->s >= p->end || *p->s != ':') { free(key); ok = 0; break; }
                p->s++;
            }
            J v;
            if (!value(p, &v)) { free(key); clear(&v); ok = 0; break; }
            v.key = key;
            push(&out->items, &out->n, &cap, &v);
            ws(p);
            if (p->s < p->end && *p->s == ',') { p->s++; continue; }
            if (p->s < p->end && *p->s == close) { p->s++; break; }
            ok = 0;
            break;
        }
    } else if (c == 't' && p->end - p->s >= 4 && !memcmp(p->s, "true", 4)) { out->k = J_TRUE; p->s += 4; }
    else if (c == 'f' && p->end - p->s >= 5 && !memcmp(p->s, "false", 5)) { out->k = J_FALSE; p->s += 5; }
    else if (c == 'n' && p->end - p->s >= 4 && !memcmp(p->s, "null", 4)) { out->k = J_NULL; p->s += 4; }
    else if (c == '-' || (c >= '0' && c <= '9')) {
        char buf[64];
        size_t n = 0;
        while (p->s < p->end && n < sizeof buf - 1 && strchr("+-0123456789.eE", *p->s)) buf[n++] = *p->s++;
        buf[n] = 0;
        char *e;
        out->k = J_NUM;
        out->num = strtod(buf, &e);
        ok = e != buf;
    } else ok = 0;
    p->depth--;
    return ok;
}

J *json_parse(const char *text, size_t len)
{
    P p = { text, text + len, 0 };
    J *j = malloc(sizeof *j);
    if (!value(&p, j)) { clear(j); free(j); return NULL; }
    return j;
}

void json_free(J *j)
{
    if (!j) return;
    clear(j);
    free(j);
}

const J *json_get(const J *obj, const char *key)
{
    if (!obj || obj->k != J_OBJ) return NULL;
    for (size_t i = 0; i < obj->n; i++)
        if (!strcmp(obj->items[i].key, key)) return &obj->items[i];
    return NULL;
}

const J *json_path(const J *j, const char *dotted)
{
    char key[128];
    while (j && *dotted) {
        size_t n = strcspn(dotted, ".");
        if (n >= sizeof key) return NULL;
        memcpy(key, dotted, n);
        key[n] = 0;
        j = json_get(j, key);
        dotted += n;
        if (*dotted == '.') dotted++;
    }
    return j;
}

const char *json_str(const J *j) { return j && j->k == J_STR ? j->str : NULL; }
double json_num(const J *j, double fallback) { return j && j->k == J_NUM ? j->num : fallback; }
