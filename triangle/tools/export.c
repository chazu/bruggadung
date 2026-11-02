/* triangle export: instances as JSON or YAML, as `cue export` writes
 * configuration. A blueprint is written as its spec (or, with --seed, as one
 * entity constructed from it), a pattern as itself. Concrete values are JSON
 * values; a value still open (a range, an enum, open text) is written as the
 * constraint Triangle prints, in a string, or with --concrete is an error. */
#include "export.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "json.h"

/* --- an output tree, so JSON and YAML write the same thing ----------------------------- */

typedef enum { V_OBJ, V_ARR, V_STR, V_RAW } VKind;     /* V_RAW: a number, true, false */
typedef struct V V;
struct V {
    VKind k;
    char *s;
    char **keys;
    V **items;
    size_t n, cap;
};

static V *v_new(VKind k, const char *s)
{
    V *v = calloc(1, sizeof *v);
    v->k = k;
    if (s) {
        size_t n = strlen(s) + 1;
        v->s = malloc(n);
        memcpy(v->s, s, n);
    }
    return v;
}

static void v_add(V *v, const char *key, V *item)
{
    if (v->n == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 8;
        v->items = realloc(v->items, v->cap * sizeof *v->items);
        v->keys = realloc(v->keys, v->cap * sizeof *v->keys);
    }
    char *k = NULL;
    if (key) {
        size_t n = strlen(key) + 1;
        k = malloc(n);
        memcpy(k, key, n);
    }
    v->keys[v->n] = k;
    v->items[v->n++] = item;
}

static void v_free(V *v)
{
    if (!v) return;
    for (size_t i = 0; i < v->n; i++) { free(v->keys[i]); v_free(v->items[i]); }
    free(v->keys);
    free(v->items);
    free(v->s);
    free(v);
}

/* --- from feature structures ----------------------------------------------------------- */

typedef struct {
    TriContent *c;
    const ExportOptions *o;
    Str path;
    int errors;
    TriType cons, null, list;
} Ex;

static char *printed(TriContent *c, const TriNode *n)
{
    size_t len = tri_print(c, n, NULL, 0);
    char *b = malloc(len + 1);
    tri_print(c, n, b, len + 1);
    return b;
}

static V *open_value(Ex *e, const TriNode *n)
{
    char *p = printed(e->c, n);
    if (e->o->concrete) {
        fprintf(stderr, "triangle: %s is not concrete: %s\n", e->path.len ? e->path.s : "(the instance)", p);
        e->errors++;
    }
    V *v = v_new(V_STR, p);
    free(p);
    return v;
}

static int is_quantity_kind(const char *t)
{
    static const char *const kinds[] = { "mass", "length", "time", "torque", "force", "heat", "temperature", "volume",
                                         "amount", "ref" };
    for (size_t i = 0; i < sizeof kinds / sizeof *kinds; i++) if (!strcmp(t, kinds[i])) return 1;
    return 0;
}

static V *value(Ex *e, const TriNode *n, int depth);

static V *field(Ex *e, const TriNode *n, const char *name, int depth)
{
    size_t keep = e->path.len;
    str_printf(&e->path, "%s%s", keep ? "." : "", name);
    V *v = value(e, n, depth);
    e->path.len = keep;
    if (e->path.s) e->path.s[keep] = 0;
    return v;
}

static V *value(Ex *e, const TriNode *n, int depth)
{
    TriContent *c = e->c;
    if (depth > 200) {
        fprintf(stderr, "triangle: %s: too deep, or cyclic\n", e->path.s ? e->path.s : "");
        e->errors++;
        return v_new(V_STR, "...");
    }
    TriType t = tri_node_type(n);
    const char *tn = tri_type_name(c, t);
    int64_t lo, hi;
    /* numbers */
    if (!strcmp(tn, "int") || !strcmp(tn, "fixed") || is_quantity_kind(tn)) {
        if (!tri_node_interval(n, &lo, &hi) || lo != hi) return open_value(e, n);
        char buf[64];
        if (!strcmp(tn, "int")) snprintf(buf, sizeof buf, "%lld", (long long) lo);
        else if (!strcmp(tn, "fixed")) {
            long long a = lo < 0 ? -lo : lo;
            snprintf(buf, sizeof buf, "%s%lld.%03lld", lo < 0 ? "-" : "", a / 1000, a % 1000);
            size_t k = strlen(buf);
            while (buf[k - 1] == '0') buf[--k] = 0;
            if (buf[k - 1] == '.') buf[--k] = 0;
        } else {                                   /* a quantity keeps its unit: "19mm" */
            char *p = printed(c, n);
            V *v = v_new(V_STR, p);
            free(p);
            return v;
        }
        return v_new(V_RAW, buf);
    }
    if (!strcmp(tn, "true") || !strcmp(tn, "false")) return v_new(V_RAW, tn);
    /* lists */
    if (e->cons != TRI_BOTTOM && tri_subtype(c, t, e->list)) {
        V *a = v_new(V_ARR, NULL);
        const TriNode *cell = n;
        for (size_t i = 0;; i++) {
            TriType ct = tri_node_type(cell);
            if (tri_subtype(c, ct, e->null)) return a;
            if (!tri_subtype(c, ct, e->cons)) { v_free(a); return open_value(e, n); }
            char idx[32];
            snprintf(idx, sizeof idx, "%zu", i);
            size_t keep = e->path.len;
            str_printf(&e->path, "[%zu]", i);
            V *item = value(e, tri_at(c, cell, "first"), depth + 1);
            e->path.len = keep;
            if (e->path.s) e->path.s[keep] = 0;
            v_add(a, NULL, item);
            cell = tri_at(c, cell, "rest");
            if (!cell) { v_free(a); return open_value(e, n); }
        }
    }
    /* structures */
    size_t nf = tri_type_feature_count(c, t);
    if (nf) {
        V *o = v_new(V_OBJ, NULL);
        if (e->o->types) v_add(o, "#type", v_new(V_STR, tn));
        for (size_t i = 0; i < nf; i++) {
            const char *f = tri_type_feature(c, t, i);
            const TriNode *ch = tri_at(c, n, f);
            if (ch) v_add(o, f, field(e, ch, f, depth + 1));
        }
        return o;
    }
    /* strings and atoms */
    size_t len = tri_text(c, n, NULL, 0);
    if (len != (size_t) -1 && strcmp(tn, "_") && strcmp(tn, "bool") && strcmp(tn, "atom")) {
        char *b = malloc(len + 1);
        tri_text(c, n, b, len + 1);
        V *v = v_new(V_STR, b);
        free(b);
        return v;
    }
    return open_value(e, n);
}

/* --- writing ------------------------------------------------------------------------------ */

static void json_out(FILE *f, const V *v, int indent)
{
    Str s = { 0 };
    switch (v->k) {
    case V_RAW: fputs(v->s, f); return;
    case V_STR: str_json(&s, v->s); fputs(s.s, f); str_free(&s); return;
    case V_OBJ: case V_ARR: {
        char open = v->k == V_OBJ ? '{' : '[', close = v->k == V_OBJ ? '}' : ']';
        if (!v->n) { fprintf(f, "%c%c", open, close); return; }
        fprintf(f, "%c\n", open);
        for (size_t i = 0; i < v->n; i++) {
            fprintf(f, "%*s", indent + 2, "");
            if (v->k == V_OBJ) { str_json(&s, v->keys[i]); fprintf(f, "%s: ", s.s); s.len = 0; }
            json_out(f, v->items[i], indent + 2);
            fputs(i + 1 < v->n ? ",\n" : "\n", f);
        }
        fprintf(f, "%*s%c", indent, "", close);
        str_free(&s);
        return;
    }
    }
}

static int plain_key(const char *k)
{
    if (!*k) return 0;
    for (const char *p = k; *p; p++)
        if (!(*p == '_' || *p == '.' || *p == '-' || (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9')))
            return 0;
    return !(k[0] >= '0' && k[0] <= '9') && strcmp(k, "true") && strcmp(k, "false") && strcmp(k, "null");
}

static void yaml_scalar(FILE *f, const V *v)
{
    if (v->k == V_RAW) { fputs(v->s, f); return; }
    Str s = { 0 };
    str_json(&s, v->s);                           /* a JSON string is a YAML double-quoted scalar */
    fputs(s.s, f);
    str_free(&s);
}

static int yaml_inline(const V *v) { return v->k == V_RAW || v->k == V_STR || !v->n; }

static void yaml_key(FILE *f, const char *k)
{
    if (plain_key(k)) fputs(k, f);
    else { Str s = { 0 }; str_json(&s, k); fputs(s.s, f); str_free(&s); }
}

static void yaml_out(FILE *f, const V *v, int indent);

/* An item's value after "key:" or "-": inline, or on the lines below. */
static void yaml_after(FILE *f, const V *v, int indent)
{
    if (yaml_inline(v)) {
        fputc(' ', f);
        if (v->k == V_OBJ) fputs("{}", f);
        else if (v->k == V_ARR) fputs("[]", f);
        else yaml_scalar(f, v);
        fputc('\n', f);
    } else {
        fputc('\n', f);
        yaml_out(f, v, indent + 2);
    }
}

static void yaml_out(FILE *f, const V *v, int indent)
{
    for (size_t i = 0; i < v->n; i++) {
        fprintf(f, "%*s", indent, "");
        if (v->k == V_OBJ) {
            yaml_key(f, v->keys[i]);
            fputc(':', f);
        } else fputc('-', f);
        yaml_after(f, v->items[i], indent);
    }
}

/* --- the command -------------------------------------------------------------------------- */

int export_content(TriContent *c, const char *const *names, size_t nnames, const ExportOptions *o, FILE *out)
{
    Ex e = { c, o, { 0 }, 0, tri_type_named(c, "#Cons"), tri_type_named(c, "#Null"), tri_type_named(c, "#List") };
    V *top = v_new(V_OBJ, NULL);
    TriArena *a = tri_arena_new();
    size_t count = nnames ? nnames : tri_instance_count(c);
    for (size_t i = 0; i < count; i++) {
        const char *name = nnames ? names[i] : tri_instance_name(c, i);
        const TriNode *n = NULL;
        if (o->seeded) n = tri_construct(c, name, o->seed, a);
        if (!n) n = tri_spec(c, name);
        if (!n) n = tri_value(c, name, a, NULL, 0);              /* a pattern, as it is */
        if (!n) {
            fprintf(stderr, "triangle: no instance named %s\n", name);
            e.errors++;
            continue;
        }
        e.path.len = 0;
        str_puts(&e.path, "");
        str_puts(&e.path, name);
        V *v = value(&e, n, 0);
        v_add(top, name, v);
    }
    if (o->yaml) {
        if (!top->n) fputs("{}\n", out);
        else yaml_out(out, top, 0);
    } else {
        json_out(out, top, 0);
        fputc('\n', out);
    }
    v_free(top);
    str_free(&e.path);
    tri_arena_free(a);
    return e.errors ? 1 : 0;
}
