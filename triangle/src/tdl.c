#include "internal.h"

#ifndef TRI_NO_TDL      /* a game build can leave the TDL front end out */

#include <ctype.h>

/* TDL front end: reads DELPH-IN type description language into the same
 * syntax tree as the CUE-style parser. Types become `#name`, coreference tags
 * become `$name`, strings and 'symbols become atoms, lists use *cons* and *null*,
 * and difference lists use *diff-list* with LIST and LAST. Identifiers are
 * lowercased. Top files may use :begin/:end blocks and :include. */

typedef struct {
    Content *c;
    Sym file;
    const char *src, *p;
    int line;
    bool err;
    int gensym;
    int kind;          /* L_DEF or L_INST for definitions in this file */
    Sym status;
} TP;

static Loc tloc(TP *t) { return (Loc) { t->file, t->line, 0 }; }

static void terr(TP *t, const char *msg)
{
    if (!t->err) diag(t->c, true, tloc(t), "%s", msg);
    t->err = true;
}

static void adv(TP *t)
{
    if (*t->p == '\n') t->line++;
    if (*t->p) t->p++;
}

static void skip_ws(TP *t)
{
    for (;;) {
        char ch = *t->p;
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\f') { adv(t); continue; }
        if (ch == ';') { while (*t->p && *t->p != '\n') adv(t); continue; }
        if (ch == '#' && t->p[1] == '|') {
            adv(t); adv(t);
            while (*t->p && !(t->p[0] == '|' && t->p[1] == '#')) adv(t);
            if (*t->p) { adv(t); adv(t); }
            continue;
        }
        break;
    }
}

/* Docstrings may appear between terms and before the final dot. */
static void skip_ws_doc(TP *t)
{
    for (;;) {
        skip_ws(t);
        if (t->p[0] == '"' && t->p[1] == '"' && t->p[2] == '"') {
            t->p += 3;
            while (*t->p && !(t->p[0] == '"' && t->p[1] == '"' && t->p[2] == '"')) adv(t);
            if (*t->p) t->p += 3;
            continue;
        }
        break;
    }
}

static bool ident_char(char ch)
{
    if ((unsigned char) ch >= 0x80) return true;
    if (ch <= ' ') return false;
    return !strchr("!\"#$%&'(),./:;<=>[]^|", ch);
}

static Sym read_ident(TP *t, const char *prefix)
{
    const char *s = t->p;
    while (ident_char(*t->p)) adv(t);
    size_t n = (size_t) (t->p - s);
    if (!n) { terr(t, "expected an identifier"); return NULL; }
    size_t pl = strlen(prefix);
    char *buf = malloc(pl + n + 1);
    memcpy(buf, prefix, pl);
    for (size_t i = 0; i < n; i++) buf[pl + i] = (char) tolower((unsigned char) s[i]);
    buf[pl + n] = 0;
    Sym r = intern(t->c, buf);
    free(buf);
    return r;
}

static X *xnew(TP *t, XKind k)
{
    X *x = arena_alloc(t->c->load, sizeof(X));
    x->k = k;
    x->loc = tloc(t);
    return x;
}

static X *xand(TP *t, X *a, X *b)
{
    if (!a) return b;
    X *x = xnew(t, X_AND);
    x->u.bin.a = a;
    x->u.bin.b = b;
    return x;
}

/* Skips a balanced parenthesised group, honouring backslash escapes. */
static void skip_group(TP *t)
{
    int depth = 0;
    do {
        if (*t->p == '\\' && t->p[1]) { adv(t); adv(t); continue; }
        if (*t->p == '(') depth++;
        else if (*t->p == ')') depth--;
        adv(t);
    } while (*t->p && depth > 0);
}

static X *parse_conj(TP *t);

static X *tag_node(TP *t, Sym name)
{
    X *x = xnew(t, X_TAG);
    x->u.name = name;
    return x;
}

static X *parse_string(TP *t)
{
    adv(t);
    Buf b = { 0 };
    buf_putc(&b, '"');
    while (*t->p && *t->p != '"') {
        if (*t->p == '\\' && t->p[1]) adv(t);
        buf_putc(&b, *t->p);
        adv(t);
    }
    if (*t->p != '"') { terr(t, "unterminated string"); buf_free(&b); return NULL; }
    adv(t);
    buf_putc(&b, '"');
    X *x = xnew(t, X_ATOM);
    x->u.name = intern(t->c, b.s);
    buf_free(&b);
    return x;
}

static X *parse_avm(TP *t)
{
    X *x = xnew(t, X_STRUCT);
    adv(t);                                     /* [ */
    XPtrVec items = { 0 };
    VEC(XField) fields = { 0 };
    skip_ws_doc(t);
    while (*t->p && *t->p != ']' && !t->err) {
        /* path: FEAT(.FEAT)* */
        SymVec path = { 0 };
        Loc floc = tloc(t);
        for (;;) {
            Sym f = read_ident(t, "");
            if (!f) break;
            VEC_PUSH(path, f);
            /* inside a feature structure a dot always continues the path; the
             * ERG has at least one path with a space before the dot */
            skip_ws(t);
            if (*t->p == '.') { adv(t); skip_ws(t); continue; }
            break;
        }
        if (t->err) { VEC_FREE(path); break; }
        skip_ws_doc(t);
        X *v = parse_conj(t);
        if (!v) { VEC_FREE(path); break; }
        /* nest the path from the inside out */
        for (size_t i = path.n; i-- > 1;) {
            X *s = xnew(t, X_STRUCT);
            s->u.st.fields = arena_alloc(t->c->load, sizeof(XField));
            s->u.st.fields[0].label = path.v[i];
            s->u.st.fields[0].value = v;
            s->u.st.fields[0].loc = floc;
            s->u.st.n = 1;
            v = s;
        }
        XField fl = { path.v[0], v, NULL, 0, floc, NULL };
        VEC_PUSH(fields, fl);
        VEC_FREE(path);
        skip_ws_doc(t);
        if (*t->p == ',') { adv(t); skip_ws_doc(t); continue; }
        if (*t->p != ']') terr(t, "expected ',' or ']' in feature structure");
    }
    if (*t->p == ']') adv(t);
    else terr(t, "unterminated feature structure");
    x->u.st.n = (int) fields.n;
    if (fields.n) {
        x->u.st.fields = arena_alloc(t->c->load, fields.n * sizeof(XField));
        memcpy(x->u.st.fields, fields.v, fields.n * sizeof(XField));
    }
    VEC_FREE(fields);
    VEC_FREE(items);
    return t->err ? NULL : x;
}

static X *finish_list(TP *t, XPtrVec *items, bool open, X *tail)
{
    X *x = xnew(t, X_LIST);
    x->u.list.n = (int) items->n;
    x->u.list.open = open;
    x->u.list.tail = tail;
    if (items->n) {
        x->u.list.items = arena_alloc(t->c->load, items->n * sizeof(X *));
        memcpy(x->u.list.items, items->v, items->n * sizeof(X *));
    }
    VEC_FREE(*items);
    return x;
}

static X *parse_list(TP *t)
{
    adv(t);                                     /* < */
    XPtrVec items = { 0 };
    bool open = false;
    X *tail = NULL;
    skip_ws_doc(t);
    if (t->p[0] == '.' && t->p[1] == '.' && t->p[2] == '.') { t->p += 3; open = true; skip_ws_doc(t); }
    while (*t->p && *t->p != '>' && !t->err && !open) {
        X *item = parse_conj(t);
        if (!item) break;
        VEC_PUSH(items, item);
        skip_ws_doc(t);
        if (*t->p == ',') {
            adv(t);
            skip_ws_doc(t);
            if (t->p[0] == '.' && t->p[1] == '.' && t->p[2] == '.') { t->p += 3; open = true; skip_ws_doc(t); }
            continue;
        }
        if (*t->p == '.') {
            adv(t);
            skip_ws_doc(t);
            tail = parse_conj(t);
            skip_ws_doc(t);
            break;
        }
        if (*t->p != '>') terr(t, "expected ',', '.', or '>' in list");
    }
    if (*t->p == '>') adv(t);
    else terr(t, "unterminated list");
    return t->err ? NULL : finish_list(t, &items, open, tail);
}

static X *parse_difflist(TP *t)
{
    t->p += 2;                                  /* <! */
    XPtrVec items = { 0 };
    skip_ws_doc(t);
    while (*t->p && !(t->p[0] == '!' && t->p[1] == '>') && !t->err) {
        X *item = parse_conj(t);
        if (!item) break;
        VEC_PUSH(items, item);
        skip_ws_doc(t);
        if (*t->p == ',') { adv(t); skip_ws_doc(t); continue; }
        if (!(t->p[0] == '!' && t->p[1] == '>')) terr(t, "expected ',' or '!>' in difference list");
    }
    if (t->p[0] == '!' && t->p[1] == '>') t->p += 2;
    else terr(t, "unterminated difference list");
    if (t->err) { VEC_FREE(items); return NULL; }
    char name[32];
    snprintf(name, sizeof name, "$__dl%d", ++t->gensym);
    Sym last = intern(t->c, name);
    X *list = finish_list(t, &items, false, tag_node(t, last));
    X *x = xnew(t, X_STRUCT);
    x->u.st.fields = arena_alloc(t->c->load, 2 * sizeof(XField));
    x->u.st.fields[0] = (XField) { intern(t->c, "list"), list, NULL, 0, tloc(t), NULL };
    x->u.st.fields[1] = (XField) { intern(t->c, "last"), tag_node(t, last), NULL, 0, tloc(t), NULL };
    x->u.st.n = 2;
    return x;
}

static X *parse_term(TP *t)
{
    skip_ws_doc(t);
    char ch = *t->p;
    if (ch == '[') return parse_avm(t);
    if (ch == '<' && t->p[1] == '!') return parse_difflist(t);
    if (ch == '<') return parse_list(t);
    if (ch == '"') return parse_string(t);
    if (ch == '#') {
        adv(t);
        return tag_node(t, read_ident(t, "$"));
    }
    if (ch == '\'') {
        adv(t);
        const char *s = t->p;
        while (ident_char(*t->p)) adv(t);
        Buf b = { 0 };
        buf_putc(&b, '"');
        for (const char *q = s; q < t->p; q++) buf_putc(&b, *q);
        buf_putc(&b, '"');
        X *x = xnew(t, X_ATOM);
        x->u.name = intern(t->c, b.s);
        buf_free(&b);
        return x;
    }
    if (ch == '^') {
        /* a regular expression (token mapping rules): kept as an opaque atom */
        Buf b = { 0 };
        buf_putc(&b, '"');
        while (*t->p && *t->p != '$') {
            if (*t->p == '\\' && t->p[1]) { buf_putc(&b, *t->p); adv(t); }
            buf_putc(&b, *t->p);
            adv(t);
        }
        if (*t->p != '$') { terr(t, "unterminated regular expression"); buf_free(&b); return NULL; }
        buf_putc(&b, '$');
        adv(t);
        buf_putc(&b, '"');
        X *x = xnew(t, X_ATOM);
        x->u.name = intern(t->c, b.s);
        buf_free(&b);
        return x;
    }
    if (ident_char(ch)) {
        Sym name = read_ident(t, "#");
        if (!name) return NULL;
        if (strcmp(name, "#*top*") == 0) return xnew(t, X_TOP);
        X *x = xnew(t, X_NAME);
        x->u.name = name;
        return x;
    }
    terr(t, "expected a term");
    return NULL;
}

static X *parse_conj(TP *t)
{
    X *r = NULL;
    for (;;) {
        X *term = parse_term(t);
        if (!term) return NULL;
        r = xand(t, r, term);
        skip_ws_doc(t);
        if (*t->p != '&') break;
        adv(t);
    }
    return r;
}

static bool parse_file(Content *c, const char *path, int kind, Sym status, int depth);

static bool read_file(Content *c, const char *path, char **out)
{
    FILE *f = fopen(path, "rb");
    if (!f) { diag(c, true, (Loc) { 0 }, "cannot open %s", path); return false; }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *s = malloc((size_t) len + 1);
    size_t got = fread(s, 1, (size_t) len, f);
    s[got] = 0;
    fclose(f);
    *out = s;
    return true;
}

/* :begin :type.  :begin :instance :status lex-entry.  :end :type.  :include "file". */
static bool directive(TP *t, int *kind, Sym *status, int depth, const char *dir)
{
    SymVec words = { 0 };
    char *incl = NULL;
    while (*t->p && *t->p != '.') {
        skip_ws(t);
        if (*t->p == ':') {
            adv(t);
            VEC_PUSH(words, read_ident(t, ""));
        } else if (*t->p == '"') {
            X *s = parse_string(t);
            if (!s) break;
            size_t n = strlen(s->u.name);
            incl = malloc(n);
            memcpy(incl, s->u.name + 1, n - 2);
            incl[n - 2] = 0;
        } else if (ident_char(*t->p)) {
            VEC_PUSH(words, read_ident(t, ""));     /* e.g. the value of :status */
        } else if (*t->p != '.') {
            terr(t, "malformed directive");
            break;
        }
        skip_ws(t);
    }
    if (*t->p == '.') adv(t);
    bool ok = !t->err;
    if (ok && words.n && strcmp(words.v[0], "begin") == 0) {
        for (size_t i = 1; i < words.n; i++) {
            if (strcmp(words.v[i], "type") == 0) { *kind = L_DEF; *status = NULL; }
            else if (strcmp(words.v[i], "instance") == 0) { *kind = L_INST; *status = NULL; }
            else if (strcmp(words.v[i], "status") == 0 && i + 1 < words.n) *status = words.v[++i];
        }
    } else if (ok && words.n && strcmp(words.v[0], "include") == 0 && incl) {
        Buf p = { 0 };
        if (incl[0] != '/') buf_puts(&p, dir);
        buf_puts(&p, incl);
        size_t n = strlen(incl);
        if (n < 4 || strcmp(incl + n - 4, ".tdl") != 0) buf_puts(&p, ".tdl");
        ok = parse_file(t->c, p.s, *kind, *status, depth + 1);
        buf_free(&p);
    }
    /* :end restores the enclosing block's mode in the caller */
    free(incl);
    VEC_FREE(words);
    return ok;
}

static bool parse_file(Content *c, const char *path, int kind, Sym status, int depth)
{
    if (depth > 32) { diag(c, true, (Loc) { 0 }, "includes nested too deeply at %s", path); return false; }
    char *src;
    if (!read_file(c, path, &src)) return false;
    char dir[1024] = "";
    const char *slash = strrchr(path, '/');
    if (slash && (size_t) (slash - path + 1) < sizeof dir) {
        memcpy(dir, path, (size_t) (slash - path + 1));
        dir[slash - path + 1] = 0;
    }
    TP t = { c, intern(c, path), src, src, 1, false, 0, kind, status };
    int kstack[16];
    Sym sstack[16];
    int sp = 0;
    while (!t.err) {
        skip_ws_doc(&t);
        if (!*t.p) break;
        if (*t.p == ':') {
            const char *save = t.p;
            int k = t.kind;
            Sym s = t.status;
            bool is_end = strncmp(t.p, ":end", 4) == 0;
            bool is_begin = strncmp(t.p, ":begin", 6) == 0;
            if (is_begin && sp < 16) { kstack[sp] = t.kind; sstack[sp] = t.status; sp++; }
            (void) save;
            if (!directive(&t, &k, &s, depth, dir)) { t.err = true; break; }
            if (is_begin) { t.kind = k; t.status = s; }
            if (is_end && sp) { sp--; t.kind = kstack[sp]; t.status = sstack[sp]; }
            continue;
        }
        if (*t.p == '%') {                      /* %(letter-set ...) */
            adv(&t);
            skip_group(&t);
            continue;
        }
        Loc loc = tloc(&t);
        Sym name = read_ident(&t, t.kind == L_DEF ? "#" : "");
        if (!name) break;
        skip_ws_doc(&t);
        bool addendum = false;
        if (t.p[0] == ':' && (t.p[1] == '=' || t.p[1] == '<')) t.p += 2;
        else if (t.p[0] == ':' && t.p[1] == '+') { t.p += 2; addendum = true; }
        else { terr(&t, "expected ':=' or ':+'"); break; }
        skip_ws_doc(&t);
        if (*t.p == '%') {                      /* %suffix / %prefix rules */
            while (*t.p && *t.p != '(' && *t.p != '\n') adv(&t);
            skip_ws(&t);
            while (*t.p == '(') { skip_group(&t); skip_ws(&t); }
        }
        X *value = parse_conj(&t);
        if (!value) break;
        skip_ws_doc(&t);
        if (*t.p != '.') { terr(&t, "expected '.' at the end of a definition"); break; }
        adv(&t);
        Decl d = { 0 };
        d.label = name;
        d.kind = t.kind;
        d.value = value;
        d.loc = loc;
        d.addendum = addendum;
        d.status = t.status;
        if (strcmp(name, "#*top*") != 0) VEC_PUSH(c->decls, d);
    }
    free(src);
    return !t.err;
}

bool tdl_parse_top(Content *c, const char *path, int kind)
{
    return parse_file(c, path, kind, NULL, 0);
}

#endif
