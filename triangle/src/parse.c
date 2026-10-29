#include "internal.h"

#include <ctype.h>

typedef enum {
    T_EOF, T_IDENT, T_DEF, T_STRING, T_NUMBER, T_TAG, T_ATTR,
    T_COLON, T_COMMA, T_LBRACE, T_RBRACE, T_LBRACK, T_RBRACK, T_LPAREN, T_RPAREN,
    T_AND, T_OR, T_STAR, T_GE, T_LE, T_GT, T_LT, T_ELLIPSIS, T_PLUS, T_MINUS, T_SLASH,
} TokKind;

typedef struct {
    TokKind k;
    const char *s;     /* start in source */
    size_t len;
    Loc loc;
    Sym attr_name;     /* T_ATTR */
    char *attr_args;
} Tok;

typedef struct { int line; const char *s; size_t len; } Comment;   /* a comment alone on its line */

typedef struct {
    Content *c;
    Sym file;
    VEC(Tok) toks;
    size_t pos;
    bool error;
    VEC(Comment) comments;
} Parser;

static void perr(Parser *p, Loc loc, const char *msg)
{
    if (!p->error) diag(p->c, true, loc, "%s", msg);
    p->error = true;
}

/* --- lexer --------------------------------------------------------------------- */

static bool operand_end(TokKind k)
{
    return k == T_NUMBER || k == T_IDENT || k == T_DEF || k == T_TAG || k == T_STRING || k == T_RPAREN ||
           k == T_RBRACE || k == T_RBRACK;
}

static bool lex(Parser *p, const char *src)
{
    int line = 1, col = 1;
    const char *s = src;
#define ADV() do { if (*s == '\n') { line++; col = 1; } else col++; s++; } while (0)
    while (*s) {
        if (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') { ADV(); continue; }
        if (s[0] == '/' && s[1] == '/') {
            Comment cm = { line, s + 2, 0 };
            bool alone = !p->toks.n || p->toks.v[p->toks.n - 1].loc.line != line;
            while (*s && *s != '\n') ADV();
            cm.len = (size_t) (s - cm.s);
            if (alone) VEC_PUSH(p->comments, cm);
            continue;
        }
        Tok t = { 0 };
        t.s = s;
        t.loc = (Loc) { p->file, line, col };
        char ch = *s;
        if (isalpha((unsigned char) ch) || ch == '_' ||
            (ch == '#' && (isalpha((unsigned char) s[1]) || s[1] == '_'))) {
            t.k = ch == '#' ? T_DEF : T_IDENT;
            ADV();
            while (isalnum((unsigned char) *s) || *s == '_') ADV();
        } else if (ch == '$') {
            t.k = T_TAG;
            ADV();
            if (!isalnum((unsigned char) *s) && *s != '_') {
                perr(p, t.loc, "expected a tag name after '$'");
                return false;
            }
            while (isalnum((unsigned char) *s) || *s == '_') ADV();
        } else if (ch == '-' && p->toks.n && operand_end(p->toks.v[p->toks.n - 1].k)) {
            /* after an operand, '-' subtracts */
            t.k = T_MINUS;
            ADV();
        } else if (isdigit((unsigned char) ch) || (ch == '-' && isdigit((unsigned char) s[1]))) {
            t.k = T_NUMBER;
            ADV();
            while (isdigit((unsigned char) *s) || *s == '.') {
                if (*s == '.' && s[1] == '.') break;
                ADV();
            }
            while (isalpha((unsigned char) *s)) ADV();
        } else if (ch == '"') {
            t.k = T_STRING;
            ADV();
            while (*s && *s != '"') {
                if (*s == '\n') { perr(p, t.loc, "unterminated string"); return false; }
                ADV();
            }
            if (!*s) { perr(p, t.loc, "unterminated string"); return false; }
            ADV();
        } else if (ch == '@') {
            t.k = T_ATTR;
            ADV();
            const char *n0 = s;
            while (isalnum((unsigned char) *s) || *s == '_') ADV();
            if (s == n0) { perr(p, t.loc, "expected an attribute name after '@'"); return false; }
            t.attr_name = sym_intern(&p->c->syms, n0, (size_t) (s - n0));
            if (*s == '(') {
                ADV();
                const char *a0 = s;
                int depth = 1;
                while (*s && depth) {
                    if (*s == '(') depth++;
                    if (*s == ')') depth--;
                    if (depth) ADV();
                }
                if (!*s) { perr(p, t.loc, "unterminated attribute"); return false; }
                size_t n = (size_t) (s - a0);
                t.attr_args = arena_alloc(p->c->load, n + 1);
                memcpy(t.attr_args, a0, n);
                ADV();
            } else {
                t.attr_args = arena_alloc(p->c->load, 1);
            }
        } else {
            ADV();
            switch (ch) {
            case ':': t.k = T_COLON; break;
            case ',': t.k = T_COMMA; break;
            case '{': t.k = T_LBRACE; break;
            case '}': t.k = T_RBRACE; break;
            case '[': t.k = T_LBRACK; break;
            case ']': t.k = T_RBRACK; break;
            case '(': t.k = T_LPAREN; break;
            case ')': t.k = T_RPAREN; break;
            case '&': t.k = T_AND; break;
            case '|': t.k = T_OR; break;
            case '*': t.k = T_STAR; break;
            case '+': t.k = T_PLUS; break;
            case '/': t.k = T_SLASH; break;
            case '>': if (*s == '=') { ADV(); t.k = T_GE; } else t.k = T_GT; break;
            case '<': if (*s == '=') { ADV(); t.k = T_LE; } else t.k = T_LT; break;
            case '.':
                if (s[0] == '.' && s[1] == '.') { ADV(); ADV(); t.k = T_ELLIPSIS; break; }
                /* fallthrough */
            default: {
                char msg[64];
                snprintf(msg, sizeof msg, "unexpected character '%c'", ch);
                perr(p, t.loc, msg);
                return false;
            }
            }
        }
        t.len = (size_t) (s - t.s);
        VEC_PUSH(p->toks, t);
    }
    Tok e = { 0 };
    e.k = T_EOF;
    e.loc = (Loc) { p->file, line, col };
    VEC_PUSH(p->toks, e);
    return true;
#undef ADV
}

/* --- parser ------------------------------------------------------------------- */

static Tok *peek(Parser *p, size_t k)
{
    size_t i = p->pos + k;
    if (i >= p->toks.n) i = p->toks.n - 1;
    return &p->toks.v[i];
}

static Tok *next(Parser *p)
{
    Tok *t = peek(p, 0);
    if (p->pos < p->toks.n - 1) p->pos++;
    return t;
}

static bool expect(Parser *p, TokKind k, const char *what)
{
    if (peek(p, 0)->k != k) {
        char msg[96];
        snprintf(msg, sizeof msg, "expected %s", what);
        perr(p, peek(p, 0)->loc, msg);
        return false;
    }
    next(p);
    return true;
}

static X *xnew(Parser *p, XKind k, Loc loc)
{
    X *x = arena_alloc(p->c->load, sizeof(X));
    x->k = k;
    x->loc = loc;
    return x;
}

static Sym tok_sym(Parser *p, Tok *t)
{
    return sym_intern(&p->c->syms, t->s, t->len);
}

static X *parse_expr(Parser *p);

static void parse_attrs(Parser *p, Attr **attrs, int *n)
{
    VEC(Attr) v = { 0 };
    while (peek(p, 0)->k == T_ATTR) {
        Tok *t = next(p);
        Attr a = { t->attr_name, t->attr_args };
        VEC_PUSH(v, a);
    }
    if (v.n) {
        *attrs = arena_alloc(p->c->load, v.n * sizeof(Attr));
        memcpy(*attrs, v.v, v.n * sizeof(Attr));
    }
    *n = (int) v.n;
    VEC_FREE(v);
}

/* A field value, allowing the path shorthand `a: b: c`. */
static X *parse_field_value(Parser *p, Attr **attrs, int *nattrs)
{
    if (peek(p, 0)->k == T_IDENT && peek(p, 1)->k == T_COLON) {
        Tok *lab = next(p);
        next(p);
        XField f = { 0 };
        f.label = tok_sym(p, lab);
        f.loc = lab->loc;
        f.value = parse_field_value(p, &f.attrs, &f.nattrs);
        if (!f.value) return NULL;
        X *x = xnew(p, X_STRUCT, lab->loc);
        x->u.st.fields = arena_alloc(p->c->load, sizeof(XField));
        x->u.st.fields[0] = f;
        x->u.st.n = 1;
        *attrs = NULL;
        *nattrs = 0;
        return x;
    }
    X *v = parse_expr(p);
    if (!v) return NULL;
    parse_attrs(p, attrs, nattrs);
    return v;
}

static X *parse_struct(Parser *p)
{
    Tok *open = next(p);
    X *x = xnew(p, X_STRUCT, open->loc);
    VEC(XField) fields = { 0 };
    VEC(Attr) dattrs = { 0 };
    while (peek(p, 0)->k != T_RBRACE) {
        if (peek(p, 0)->k == T_EOF) { perr(p, open->loc, "unterminated struct"); return NULL; }
        if (peek(p, 0)->k == T_ATTR) {
            Tok *t = next(p);
            Attr a = { t->attr_name, t->attr_args };
            VEC_PUSH(dattrs, a);
            continue;
        }
        if (peek(p, 0)->k == T_COMMA) { next(p); continue; }
        Tok *lab = peek(p, 0);
        if (lab->k != T_IDENT) { perr(p, lab->loc, "expected a field label"); return NULL; }
        next(p);
        if (!expect(p, T_COLON, "':' after field label")) return NULL;
        XField f = { 0 };
        f.label = tok_sym(p, lab);
        f.loc = lab->loc;
        f.value = parse_field_value(p, &f.attrs, &f.nattrs);
        if (!f.value) return NULL;
        VEC_PUSH(fields, f);
    }
    next(p);
    x->u.st.n = (int) fields.n;
    if (fields.n) {
        x->u.st.fields = arena_alloc(p->c->load, fields.n * sizeof(XField));
        memcpy(x->u.st.fields, fields.v, fields.n * sizeof(XField));
    }
    x->u.st.nattrs = (int) dattrs.n;
    if (dattrs.n) {
        x->u.st.attrs = arena_alloc(p->c->load, dattrs.n * sizeof(Attr));
        memcpy(x->u.st.attrs, dattrs.v, dattrs.n * sizeof(Attr));
    }
    VEC_FREE(fields);
    VEC_FREE(dattrs);
    return x;
}

static X *parse_list(Parser *p)
{
    Tok *open = next(p);
    X *x = xnew(p, X_LIST, open->loc);
    XPtrVec items = { 0 };
    while (peek(p, 0)->k != T_RBRACK) {
        if (peek(p, 0)->k == T_ELLIPSIS) {
            next(p);
            x->u.list.open = true;
            if (peek(p, 0)->k != T_RBRACK) {          /* [...X]: the rest are all X */
                x->u.list.elem = parse_expr(p);
                if (!x->u.list.elem) return NULL;
            }
            break;
        }
        X *item = parse_expr(p);
        if (!item) return NULL;
        VEC_PUSH(items, item);
        if (peek(p, 0)->k == T_COMMA) next(p);
        else if (peek(p, 0)->k != T_RBRACK) { perr(p, peek(p, 0)->loc, "expected ',' or ']'"); return NULL; }
    }
    if (!expect(p, T_RBRACK, "']'")) return NULL;
    x->u.list.n = (int) items.n;
    if (items.n) {
        x->u.list.items = arena_alloc(p->c->load, items.n * sizeof(X *));
        memcpy(x->u.list.items, items.v, items.n * sizeof(X *));
    }
    VEC_FREE(items);
    return x;
}

static bool number(Parser *p, Tok *t, int *dim, int64_t *q)
{
    bool neg = t->s[0] == '-';
    const char *err = units_parse(t->s + neg, t->len - neg, neg, dim, q);
    if (err) {
        char msg[160];
        snprintf(msg, sizeof msg, "%s: %.*s", err, (int) t->len, t->s);
        perr(p, t->loc, msg);
        return false;
    }
    return true;
}

static X *parse_primary(Parser *p)
{
    Tok *t = peek(p, 0);
    switch (t->k) {
    case T_IDENT: {
        next(p);
        if (t->len == 1 && t->s[0] == '_') return xnew(p, X_TOP, t->loc);
        if ((t->len == 4 && memcmp(t->s, "true", 4) == 0) || (t->len == 5 && memcmp(t->s, "false", 5) == 0)) {
            X *x = xnew(p, X_ATOM, t->loc);
            x->u.name = tok_sym(p, t);
            return x;
        }
        if (t->len == 3 && memcmp(t->s, "ref", 3) == 0 && peek(p, 0)->k == T_LPAREN) {
            /* a referent handle: ref(12) */
            next(p);
            Tok *n = peek(p, 0);
            if (n->k != T_NUMBER || memchr(n->s, '.', n->len) || n->s[0] == '-') {
                perr(p, n->loc, "expected a referent number in ref(...)");
                return NULL;
            }
            next(p);
            X *x = xnew(p, X_NUM, t->loc);
            int dim;
            if (!number(p, n, &dim, &x->u.num.q)) return NULL;
            if (dim != DIM_INT) { perr(p, n->loc, "a referent number has no unit"); return NULL; }
            x->u.num.dim = DIM_REF;
            if (!expect(p, T_RPAREN, "')' after the referent number")) return NULL;
            return x;
        }
        X *x = xnew(p, X_NAME, t->loc);
        x->u.name = tok_sym(p, t);
        return x;
    }
    case T_DEF: {
        next(p);
        X *x = xnew(p, X_NAME, t->loc);
        x->u.name = tok_sym(p, t);
        return x;
    }
    case T_STRING: {
        next(p);
        X *x = xnew(p, X_ATOM, t->loc);
        x->u.name = tok_sym(p, t);
        return x;
    }
    case T_NUMBER: {
        next(p);
        X *x = xnew(p, X_NUM, t->loc);
        if (!number(p, t, &x->u.num.dim, &x->u.num.q)) return NULL;
        return x;
    }
    case T_TAG: {
        next(p);
        X *x = xnew(p, X_TAG, t->loc);
        x->u.name = tok_sym(p, t);
        return x;
    }
    case T_LBRACE: return parse_struct(p);
    case T_LBRACK: return parse_list(p);
    case T_LPAREN: {
        next(p);
        X *x = parse_expr(p);
        if (!x || !expect(p, T_RPAREN, "')'")) return NULL;
        return x;
    }
    default:
        perr(p, t->loc, "expected a value");
        return NULL;
    }
}

static X *parse_unary(Parser *p)
{
    Tok *t = peek(p, 0);
    if (t->k == T_STAR) {
        next(p);
        X *sub = parse_unary(p);
        if (!sub) return NULL;
        X *x = xnew(p, X_DEFAULT, t->loc);
        x->u.sub = sub;
        return x;
    }
    if (t->k == T_GE || t->k == T_LE || t->k == T_GT || t->k == T_LT) {
        next(p);
        Tok *n = peek(p, 0);
        if (n->k != T_NUMBER) { perr(p, n->loc, "expected a number after a bound"); return NULL; }
        next(p);
        X *x = xnew(p, X_BOUND, t->loc);
        x->u.bound.op = t->k == T_GE ? B_GE : t->k == T_LE ? B_LE : t->k == T_GT ? B_GT : B_LT;
        if (!number(p, n, &x->u.bound.dim, &x->u.bound.q)) return NULL;
        return x;
    }
    return parse_primary(p);
}

/* Arithmetic binds tighter than &: products, then sums. A '*' after an
 * operand multiplies; at the start of a term it marks a default. */
static X *parse_product(Parser *p)
{
    X *a = parse_unary(p);
    while (a && (peek(p, 0)->k == T_STAR || peek(p, 0)->k == T_SLASH)) {
        Tok *op = next(p);
        X *b = parse_unary(p);
        if (!b) return NULL;
        X *x = xnew(p, X_ARITH, op->loc);
        x->u.ar.a = a;
        x->u.ar.b = b;
        x->u.ar.op = op->k == T_STAR ? '*' : '/';
        a = x;
    }
    return a;
}

static X *parse_sum(Parser *p)
{
    X *a = parse_product(p);
    while (a && (peek(p, 0)->k == T_PLUS || peek(p, 0)->k == T_MINUS)) {
        Tok *op = next(p);
        X *b = parse_product(p);
        if (!b) return NULL;
        X *x = xnew(p, X_ARITH, op->loc);
        x->u.ar.a = a;
        x->u.ar.b = b;
        x->u.ar.op = op->k == T_PLUS ? '+' : '-';
        a = x;
    }
    return a;
}

static X *parse_conj(Parser *p)
{
    X *a = parse_sum(p);
    while (a && peek(p, 0)->k == T_AND) {
        Tok *op = next(p);
        X *b = parse_sum(p);
        if (!b) return NULL;
        X *x = xnew(p, X_AND, op->loc);
        x->u.bin.a = a;
        x->u.bin.b = b;
        a = x;
    }
    return a;
}

static X *parse_expr(Parser *p)
{
    X *a = parse_conj(p);
    while (a && peek(p, 0)->k == T_OR) {
        Tok *op = next(p);
        X *b = parse_conj(p);
        if (!b) return NULL;
        X *x = xnew(p, X_OR, op->loc);
        x->u.bin.a = a;
        x->u.bin.b = b;
        a = x;
    }
    return a;
}

static void parser_free(Parser *p)
{
    VEC_FREE(p->toks);
    VEC_FREE(p->comments);
}

/* The comment lines directly above line `line`, joined: a docstring. */
static const char *doc_above(Parser *p, int line)
{
    size_t end = 0;
    while (end < p->comments.n && p->comments.v[end].line < line) end++;
    size_t start = end;
    int want = line - 1;
    while (start > 0 && p->comments.v[start - 1].line == want) { start--; want--; }
    if (start == end) return NULL;
    Buf b = { 0 };
    for (size_t i = start; i < end; i++) {
        const char *t = p->comments.v[i].s;
        size_t n = p->comments.v[i].len;
        if (n && *t == ' ') { t++; n--; }
        while (n && (t[n - 1] == ' ' || t[n - 1] == '\r')) n--;
        if (i > start) buf_putc(&b, '\n');
        buf_printf(&b, "%.*s", (int) n, t);
    }
    char *r = arena_alloc(p->c->load, b.len + 1);
    memcpy(r, b.s ? b.s : "", b.len + 1);
    buf_free(&b);
    return r;
}

bool parse_source(Content *c, Sym file, const char *src, DeclVec *out)
{
    Parser p = { c, file, { 0 }, 0, false, { 0 } };
    if (!lex(&p, src)) { parser_free(&p); return false; }
    while (peek(&p, 0)->k != T_EOF && !p.error) {
        Tok *lab = peek(&p, 0);
        if (lab->k == T_COMMA) { next(&p); continue; }
        Decl d = { 0 };
        if (lab->k == T_DEF) d.kind = L_DEF;
        else if (lab->k == T_STRING) d.kind = L_ATOM;
        else if (lab->k == T_IDENT) d.kind = L_INST;
        else { perr(&p, lab->loc, "expected a declaration"); break; }
        next(&p);
        d.label = tok_sym(&p, lab);
        d.loc = lab->loc;
        d.doc = doc_above(&p, lab->loc.line);
        if (!expect(&p, T_COLON, "':' after declaration label")) break;
        d.value = parse_field_value(&p, &d.attrs, &d.nattrs);
        if (!d.value) break;
        VEC_PUSH(*out, d);
    }
    bool ok = !p.error;
    parser_free(&p);
    return ok;
}

X *parse_expr_string(Content *c, Sym file, const char *src)
{
    Parser p = { c, file, { 0 }, 0, false, { 0 } };
    X *x = NULL;
    if (lex(&p, src)) {
        x = parse_expr(&p);
        if (x && peek(&p, 0)->k != T_EOF) {
            perr(&p, peek(&p, 0)->loc, "unexpected input after expression");
            x = NULL;
        }
    }
    parser_free(&p);
    return p.error ? NULL : x;
}
