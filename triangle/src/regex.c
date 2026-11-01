#include "internal.h"

/* Regular expressions for =~ and !~: RE2's syntax, which CUE uses, compiled
 * to a Thompson NFA and run by simulation over code points. Matching takes
 * time linear in the text and never backtracks. Only whether a string matches
 * matters, so there are no captures, and lazy quantifiers match as greedy ones
 * would. Not supported: backreferences and lookaround (RE2 has neither),
 * Unicode classes (\pL), and case folding beyond ASCII. */

/* --- code points ------------------------------------------------------------------- */

#define RUNE_MAX 0x10FFFF

static uint32_t rune_at(const char *s, size_t n, size_t i, size_t *len)
{
    const unsigned char *u = (const unsigned char *) s + i;
    size_t left = n - i;
    if (u[0] < 0x80) { *len = 1; return u[0]; }
    int k = u[0] >= 0xF0 ? 4 : u[0] >= 0xE0 ? 3 : u[0] >= 0xC0 ? 2 : 0;
    if (!k || (size_t) k > left) { *len = 1; return 0xFFFD; }
    uint32_t r = u[0] & (0x7F >> k);
    for (int j = 1; j < k; j++) {
        if ((u[j] & 0xC0) != 0x80) { *len = 1; return 0xFFFD; }
        r = r << 6 | (u[j] & 0x3F);
    }
    *len = (size_t) k;
    return r;
}

static bool is_word(uint32_t r)
{
    return (r >= '0' && r <= '9') || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_';
}

/* --- classes ------------------------------------------------------------------------- */

typedef struct { uint32_t lo, hi; } Range;
typedef struct { Range *r; size_t n, cap; bool neg, fold; } Class;

static void class_add(Class *c, uint32_t lo, uint32_t hi)
{
    if (c->n == c->cap) c->r = realloc(c->r, (c->cap = c->cap ? c->cap * 2 : 4) * sizeof *c->r);
    c->r[c->n++] = (Range) { lo, hi };
}

/* Adds the complement of ranges (as written, unsorted) over all code points. */
static void class_add_negated(Class *c, const Range *r, size_t n)
{
    uint32_t next = 0;
    /* the ranges of the built-in classes are sorted and disjoint */
    for (size_t i = 0; i < n; i++) {
        if (r[i].lo > next) class_add(c, next, r[i].lo - 1);
        next = r[i].hi + 1;
    }
    if (next <= RUNE_MAX) class_add(c, next, RUNE_MAX);
}

static bool class_has(const Class *c, uint32_t r)
{
    bool in = false;
    for (size_t i = 0; i < c->n && !in; i++) in = r >= c->r[i].lo && r <= c->r[i].hi;
    if (!in && c->fold && r < 0x80) {
        uint32_t o = r >= 'a' && r <= 'z' ? r - 32 : r >= 'A' && r <= 'Z' ? r + 32 : r;
        for (size_t i = 0; i < c->n && !in; i++) in = o >= c->r[i].lo && o <= c->r[i].hi;
    }
    return in != c->neg;
}

static const Range r_digit[] = { { '0', '9' } };
static const Range r_word[] = { { '0', '9' }, { 'A', 'Z' }, { '_', '_' }, { 'a', 'z' } };
static const Range r_space[] = { { '\t', '\n' }, { '\f', '\r' }, { ' ', ' ' } };

static const struct { const char *name; Range r[4]; size_t n; } posix[] = {
    { "alnum", { { '0', '9' }, { 'A', 'Z' }, { 'a', 'z' } }, 3 },
    { "alpha", { { 'A', 'Z' }, { 'a', 'z' } }, 2 },
    { "ascii", { { 0, 0x7F } }, 1 },
    { "blank", { { '\t', '\t' }, { ' ', ' ' } }, 2 },
    { "cntrl", { { 0, 0x1F }, { 0x7F, 0x7F } }, 2 },
    { "digit", { { '0', '9' } }, 1 },
    { "graph", { { '!', '~' } }, 1 },
    { "lower", { { 'a', 'z' } }, 1 },
    { "print", { { ' ', '~' } }, 1 },
    { "punct", { { '!', '/' }, { ':', '@' }, { '[', '`' }, { '{', '~' } }, 4 },
    { "space", { { '\t', '\r' }, { ' ', ' ' } }, 2 },
    { "upper", { { 'A', 'Z' } }, 1 },
    { "word", { { '0', '9' }, { 'A', 'Z' }, { '_', '_' }, { 'a', 'z' } }, 4 },
    { "xdigit", { { '0', '9' }, { 'A', 'F' }, { 'a', 'f' } }, 3 },
};

/* --- the syntax tree --------------------------------------------------------------------- */

typedef enum { N_EMPTY, N_CLASS, N_ANY, N_ASSERT, N_CAT, N_ALT, N_STAR, N_PLUS, N_QUEST } NodeKind;
enum { A_BOL, A_EOL, A_BEGIN, A_END, A_WORD, A_NOTWORD };

typedef struct RxNode RxNode;
struct RxNode {
    NodeKind k;
    int      cls;          /* N_CLASS: index into the classes */
    bool     dotnl;        /* N_ANY: matches a newline too */
    int      assert;       /* N_ASSERT */
    RxNode  *a, *b;
};

#define MAX_NODES 20000
#define MAX_REPEAT 1000

typedef struct {
    const char *s, *end;
    const char *err;
    bool fold, dotnl, multi;     /* flags i, s, m */
    RxNode *nodes;
    size_t nnodes;
    Class *classes;
    size_t nclasses, ccap;
} RxParser;

static RxNode *node(RxParser *p, NodeKind k, RxNode *a, RxNode *b)
{
    if (p->nnodes == MAX_NODES) { if (!p->err) p->err = "the expression is too large"; return NULL; }
    RxNode *n = &p->nodes[p->nnodes++];
    memset(n, 0, sizeof *n);
    n->k = k;
    n->a = a;
    n->b = b;
    return n;
}

static int new_class(RxParser *p)
{
    if (p->nclasses == p->ccap) p->classes = realloc(p->classes, (p->ccap = p->ccap ? p->ccap * 2 : 8) * sizeof *p->classes);
    Class *c = &p->classes[p->nclasses];
    memset(c, 0, sizeof *c);
    c->fold = p->fold;
    return (int) p->nclasses++;
}

static RxNode *class_node(RxParser *p, int cls)
{
    RxNode *n = node(p, N_CLASS, NULL, NULL);
    if (n) n->cls = cls;
    return n;
}

static RxNode *literal(RxParser *p, uint32_t r)
{
    int k = new_class(p);
    class_add(&p->classes[k], r, r);
    return class_node(p, k);
}

static bool more(RxParser *p) { return p->s < p->end; }

static uint32_t take_rune(RxParser *p)
{
    size_t len;
    uint32_t r = rune_at(p->s, (size_t) (p->end - p->s), 0, &len);
    p->s += len;
    return r;
}

static int hexval(char ch)
{
    if (ch >= '0' && ch <= '9') return ch - '0';
    if ((ch | 0x20) >= 'a' && (ch | 0x20) <= 'f') return (ch | 0x20) - 'a' + 10;
    return -1;
}

/* \xHH or \x{H...}: p->s is past the x */
static bool hex_escape(RxParser *p, uint32_t *out)
{
    uint32_t v = 0;
    if (more(p) && *p->s == '{') {
        p->s++;
        int digits = 0;
        while (more(p) && *p->s != '}') {
            int h = hexval(*p->s++);
            if (h < 0 || ++digits > 6) { p->err = "bad \\x{...} escape"; return false; }
            v = v * 16 + (uint32_t) h;
        }
        if (!more(p) || !digits) { p->err = "bad \\x{...} escape"; return false; }
        p->s++;
    } else {
        for (int k = 0; k < 2; k++) {
            int h = more(p) ? hexval(*p->s++) : -1;
            if (h < 0) { p->err = "\\x takes two hex digits, or braces"; return false; }
            v = v * 16 + (uint32_t) h;
        }
    }
    if (v > RUNE_MAX) { p->err = "code point out of range"; return false; }
    *out = v;
    return true;
}

/* A Perl class letter (d, w, s and their capitals) into cls, or false. */
static bool perl_class(char ch, Class *cls)
{
    const Range *r;
    size_t n;
    switch (ch | 0x20) {
    case 'd': r = r_digit; n = 1; break;
    case 'w': r = r_word; n = 4; break;
    case 's': r = r_space; n = 3; break;
    default: return false;
    }
    if (ch >= 'a') for (size_t i = 0; i < n; i++) class_add(cls, r[i].lo, r[i].hi);
    else class_add_negated(cls, r, n);
    return true;
}

/* An escaped literal: p->s is past the backslash. 0x110000 means "not a literal". */
static uint32_t escaped_rune(RxParser *p, char ch)
{
    switch (ch) {
    case 'a': return 7;
    case 'f': return 12;
    case 't': return 9;
    case 'n': return 10;
    case 'r': return 13;
    case 'v': return 11;
    case 'x': { uint32_t v; return hex_escape(p, &v) ? v : 0x110000; }
    }
    if ((ch >= 0x21 && ch <= 0x2F) || (ch >= 0x3A && ch <= 0x40) || (ch >= 0x5B && ch <= 0x60) || (ch >= 0x7B && ch <= 0x7E))
        return (uint32_t) (unsigned char) ch;   /* punctuation stands for itself */
    if (ch == 'p' || ch == 'P') p->err = "Unicode classes (\\p) are not supported";
    else if (ch >= '0' && ch <= '9') p->err = "backreferences and octal escapes are not supported";
    else if (!p->err) p->err = "unknown escape in the expression";
    return 0x110000;
}

static RxNode *parse_class(RxParser *p)
{
    /* p->s is past the '[' */
    int k = new_class(p);
    if (more(p) && *p->s == '^') { p->classes[k].neg = true; p->s++; }
    bool first = true;
    while (more(p) && (*p->s != ']' || first)) {
        first = false;
        Class *cls = &p->classes[k];
        if (p->end - p->s >= 2 && p->s[0] == '[' && p->s[1] == ':') {
            const char *close = p->s + 2;
            while (close < p->end - 1 && !(close[0] == ':' && close[1] == ']')) close++;
            if (close >= p->end - 1) { p->err = "unterminated [:class:]"; return NULL; }
            const char *name = p->s + 2;
            bool negp = *name == '^';
            if (negp) name++;
            size_t len = (size_t) (close - name);
            size_t i = 0;
            for (; i < sizeof posix / sizeof *posix; i++)
                if (strlen(posix[i].name) == len && !memcmp(posix[i].name, name, len)) break;
            if (i == sizeof posix / sizeof *posix) { p->err = "unknown [:class:]"; return NULL; }
            if (negp) class_add_negated(cls, posix[i].r, posix[i].n);
            else for (size_t j = 0; j < posix[i].n; j++) class_add(cls, posix[i].r[j].lo, posix[i].r[j].hi);
            p->s = close + 2;
            continue;
        }
        uint32_t lo;
        if (*p->s == '\\') {
            p->s++;
            if (!more(p)) { p->err = "trailing backslash"; return NULL; }
            char ch = *p->s++;
            if (perl_class(ch, cls)) continue;
            lo = escaped_rune(p, ch);
            if (lo > RUNE_MAX) return NULL;
        } else lo = take_rune(p);
        uint32_t hi = lo;
        if (p->end - p->s >= 2 && p->s[0] == '-' && p->s[1] != ']') {
            p->s++;
            if (*p->s == '\\') {
                p->s++;
                if (!more(p)) { p->err = "trailing backslash"; return NULL; }
                hi = escaped_rune(p, *p->s++);
                if (hi > RUNE_MAX) { if (!p->err) p->err = "bad range in a class"; return NULL; }
            } else hi = take_rune(p);
            if (hi < lo) { p->err = "a range in a class runs backwards"; return NULL; }
        }
        class_add(cls, lo, hi);
    }
    if (!more(p)) { p->err = "missing ] in a class"; return NULL; }
    p->s++;
    return class_node(p, k);
}

static RxNode *parse_alt(RxParser *p);

/* Copies a subtree, for counted repetition; classes are shared. */
static RxNode *copy_tree(RxParser *p, const RxNode *n)
{
    if (!n) return NULL;
    RxNode *a = copy_tree(p, n->a), *b = copy_tree(p, n->b);
    RxNode *r = node(p, n->k, a, b);
    if (r) { r->cls = n->cls; r->dotnl = n->dotnl; r->assert = n->assert; }
    return r;
}

static RxNode *parse_atom(RxParser *p)
{
    char ch = *p->s;
    if (ch == '(') {
        p->s++;
        bool fold = p->fold, dotnl = p->dotnl, multi = p->multi;
        if (more(p) && *p->s == '?') {
            p->s++;
            if (more(p) && (*p->s == '=' || *p->s == '!' || (*p->s == '<' && p->s + 1 < p->end && (p->s[1] == '=' || p->s[1] == '!')))) {
                p->err = "lookaround is not supported (RE2 syntax)";
                return NULL;
            }
            if (more(p) && (*p->s == 'P' || *p->s == '<')) {           /* a named group */
                if (*p->s == 'P') p->s++;
                if (!more(p) || *p->s != '<') { p->err = "bad named group"; return NULL; }
                while (more(p) && *p->s != '>') p->s++;
                if (!more(p)) { p->err = "bad named group"; return NULL; }
                p->s++;
            } else {
                bool on = true, any = false;
                while (more(p) && *p->s != ':' && *p->s != ')') {
                    char f = *p->s++;
                    any = true;
                    if (f == '-') { on = false; continue; }
                    if (f == 'i') p->fold = on;
                    else if (f == 's') p->dotnl = on;
                    else if (f == 'm') p->multi = on;
                    else if (f == 'U') continue;                       /* ungreedy: no effect on whether it matches */
                    else { p->err = "unknown flag in (?...)"; return NULL; }
                }
                if (!more(p) || (!any && *p->s == ')')) { p->err = "bad (?...) group"; return NULL; }
                if (*p->s == ')') {                                    /* (?i): flags for the rest of the group */
                    p->s++;
                    return node(p, N_EMPTY, NULL, NULL);
                }
                p->s++;                                                /* (?i:...) */
            }
        }
        RxNode *in = parse_alt(p);
        if (!in) return NULL;
        if (!more(p) || *p->s != ')') { p->err = "missing )"; return NULL; }
        p->s++;
        p->fold = fold;
        p->dotnl = dotnl;
        p->multi = multi;
        return in;
    }
    p->s++;
    switch (ch) {
    case ')': p->err = "unexpected )"; return NULL;
    case '[': return parse_class(p);
    case '.': { RxNode *n = node(p, N_ANY, NULL, NULL); if (n) n->dotnl = p->dotnl; return n; }
    case '^': { RxNode *n = node(p, N_ASSERT, NULL, NULL); if (n) n->assert = p->multi ? A_BOL : A_BEGIN; return n; }
    case '$': { RxNode *n = node(p, N_ASSERT, NULL, NULL); if (n) n->assert = p->multi ? A_EOL : A_END; return n; }
    case '*': case '+': case '?': p->err = "missing argument to a repetition operator"; return NULL;
    case '\\': {
        if (!more(p)) { p->err = "trailing backslash"; return NULL; }
        char e = *p->s++;
        int a = e == 'A' ? A_BEGIN : e == 'z' ? A_END : e == 'b' ? A_WORD : e == 'B' ? A_NOTWORD : -1;
        if (a >= 0) { RxNode *n = node(p, N_ASSERT, NULL, NULL); if (n) n->assert = a; return n; }
        if (e == 'Q') {                                                /* \Q...\E: literal text */
            RxNode *r = node(p, N_EMPTY, NULL, NULL);
            while (r && more(p) && !(p->end - p->s >= 2 && p->s[0] == '\\' && p->s[1] == 'E'))
                r = node(p, N_CAT, r, literal(p, take_rune(p)));
            if (more(p)) p->s += 2;
            return r;
        }
        int k = new_class(p);
        if (perl_class(e, &p->classes[k])) return class_node(p, k);
        p->nclasses--;
        uint32_t r = escaped_rune(p, e);
        return r > RUNE_MAX ? NULL : literal(p, r);
    }
    }
    p->s--;
    return literal(p, take_rune(p));
}

/* {n}, {n,}, {n,m}: false (and nothing consumed) if what follows isn't one */
static bool counted(RxParser *p, int *min, int *max)
{
    const char *s = p->s + 1;
    int a = 0, b = -1, digits = 0;
    while (s < p->end && *s >= '0' && *s <= '9') { a = a * 10 + (*s++ - '0'); if (++digits > 4) return false; }
    if (!digits) return false;
    if (s < p->end && *s == ',') {
        s++;
        if (s < p->end && *s >= '0' && *s <= '9') {
            b = 0;
            digits = 0;
            while (s < p->end && *s >= '0' && *s <= '9') { b = b * 10 + (*s++ - '0'); if (++digits > 4) return false; }
        }
    } else b = a;
    if (s >= p->end || *s != '}') return false;
    p->s = s + 1;
    *min = a;
    *max = b;
    return true;
}

static RxNode *parse_repeat(RxParser *p)
{
    RxNode *a = parse_atom(p);
    bool quantified = false;
    while (a && more(p)) {
        char ch = *p->s;
        int min, max;
        if (ch == '*' || ch == '+' || ch == '?') {
            if (quantified) { p->err = "a repetition of a repetition; group it first"; return NULL; }
            p->s++;
            a = node(p, ch == '*' ? N_STAR : ch == '+' ? N_PLUS : N_QUEST, a, NULL);
        } else if (ch == '{' && counted(p, &min, &max)) {
            if (quantified) { p->err = "a repetition of a repetition; group it first"; return NULL; }
            if (min > MAX_REPEAT || max > MAX_REPEAT) { p->err = "a repeat count is more than 1000"; return NULL; }
            if (max >= 0 && max < min) { p->err = "a repeat range runs backwards"; return NULL; }
            RxNode *r = node(p, N_EMPTY, NULL, NULL);
            for (int i = 0; r && i < min; i++) r = node(p, N_CAT, r, copy_tree(p, a));
            if (max < 0) r = r ? node(p, N_CAT, r, node(p, N_STAR, copy_tree(p, a), NULL)) : NULL;
            else for (int i = min; r && i < max; i++) r = node(p, N_CAT, r, node(p, N_QUEST, copy_tree(p, a), NULL));
            a = r;
        } else break;
        quantified = true;
        if (more(p) && *p->s == '?') p->s++;          /* lazy: no effect on whether it matches */
    }
    return a;
}

static RxNode *parse_concat(RxParser *p)
{
    RxNode *r = node(p, N_EMPTY, NULL, NULL);
    while (r && more(p) && *p->s != '|' && *p->s != ')') {
        RxNode *a = parse_repeat(p);
        if (!a) return NULL;
        r = node(p, N_CAT, r, a);
    }
    return r;
}

static RxNode *parse_alt(RxParser *p)
{
    RxNode *a = parse_concat(p);
    while (a && more(p) && *p->s == '|') {
        p->s++;
        RxNode *b = parse_concat(p);
        if (!b) return NULL;
        a = node(p, N_ALT, a, b);
    }
    return a;
}

/* --- the program ----------------------------------------------------------------------------- */

typedef enum { I_CLASS, I_ANY, I_ANYNL, I_ASSERT, I_SPLIT, I_JMP, I_MATCH } Op;
typedef struct { Op op; int x, y; } Inst;    /* CLASS: x = class; ASSERT: x = kind; SPLIT: x, y; JMP: x */

struct Regex {
    Inst  *prog;
    size_t n;
    Class *classes;
    size_t nclasses;
};

#define MAX_PROG 50000

typedef struct { Inst *v; size_t n, cap; bool over; } Prog;

static int emit(Prog *g, Op op, int x, int y)
{
    if (g->n >= MAX_PROG) { g->over = true; return (int) g->n; }
    if (g->n == g->cap) g->v = realloc(g->v, (g->cap = g->cap ? g->cap * 2 : 64) * sizeof *g->v);
    g->v[g->n] = (Inst) { op, x, y };
    return (int) g->n++;
}

static void gen(Prog *g, const RxNode *n)
{
    if (g->over) return;
    switch (n->k) {
    case N_EMPTY: break;
    case N_CLASS: emit(g, I_CLASS, n->cls, 0); break;
    case N_ANY: emit(g, n->dotnl ? I_ANYNL : I_ANY, 0, 0); break;
    case N_ASSERT: emit(g, I_ASSERT, n->assert, 0); break;
    case N_CAT: gen(g, n->a); gen(g, n->b); break;
    case N_ALT: {
        int split = emit(g, I_SPLIT, 0, 0);
        gen(g, n->a);
        int jmp = emit(g, I_JMP, 0, 0);
        int second = (int) g->n;
        gen(g, n->b);
        if (g->over) return;
        g->v[split].x = split + 1;
        g->v[split].y = second;
        g->v[jmp].x = (int) g->n;
        break;
    }
    case N_STAR: {
        int split = emit(g, I_SPLIT, 0, 0);
        gen(g, n->a);
        emit(g, I_JMP, split, 0);
        if (g->over) return;
        g->v[split].x = split + 1;
        g->v[split].y = (int) g->n;
        break;
    }
    case N_PLUS: {
        int start = (int) g->n;
        gen(g, n->a);
        emit(g, I_SPLIT, start, (int) g->n + 1);
        break;
    }
    case N_QUEST: {
        int split = emit(g, I_SPLIT, 0, 0);
        gen(g, n->a);
        if (g->over) return;
        g->v[split].x = split + 1;
        g->v[split].y = (int) g->n;
        break;
    }
    }
}

Regex *regex_compile(const char *pat, size_t len, char *err, size_t errlen)
{
    RxParser p = { pat, pat + len, NULL, false, false, false, NULL, 0, NULL, 0, 0 };
    p.nodes = malloc(MAX_NODES * sizeof *p.nodes);
    RxNode *root = parse_alt(&p);
    if (root && more(&p) && !p.err) p.err = "unexpected )";
    Regex *re = NULL;
    if (root && !p.err) {
        Prog g = { 0 };
        gen(&g, root);
        emit(&g, I_MATCH, 0, 0);
        if (g.over) {
            p.err = "the expression is too large";
            free(g.v);
        } else {
            re = calloc(1, sizeof *re);
            re->prog = g.v;
            re->n = g.n;
            re->classes = p.classes;
            re->nclasses = p.nclasses;
            p.classes = NULL;
        }
    }
    if (p.err && err && errlen) snprintf(err, errlen, "%s", p.err);
    for (size_t i = 0; p.classes && i < p.nclasses; i++) free(p.classes[i].r);
    free(p.classes);
    free(p.nodes);
    return re;
}

void regex_free(Regex *re)
{
    if (!re) return;
    for (size_t i = 0; i < re->nclasses; i++) free(re->classes[i].r);
    free(re->classes);
    free(re->prog);
    free(re);
}

/* --- matching ------------------------------------------------------------------------------- */

typedef struct { int *pc; size_t n; } List;

static bool assert_holds(int kind, const char *s, size_t n, size_t i)
{
    size_t len;
    uint32_t prev = 0, next = 0;
    bool hasprev = i > 0, hasnext = i < n;
    if (hasprev) {
        size_t j = i - 1;
        while (j > 0 && ((unsigned char) s[j] & 0xC0) == 0x80) j--;
        prev = rune_at(s, n, j, &len);
    }
    if (hasnext) next = rune_at(s, n, i, &len);
    switch (kind) {
    case A_BEGIN: return i == 0;
    case A_END: return i == n;
    case A_BOL: return i == 0 || prev == '\n';
    case A_EOL: return i == n || next == '\n';
    case A_WORD: return (hasprev && is_word(prev)) != (hasnext && is_word(next));
    case A_NOTWORD: return (hasprev && is_word(prev)) == (hasnext && is_word(next));
    }
    return false;
}

/* Adds pc and everything reachable from it without consuming input. */
static bool add(const Regex *re, List *l, uint32_t *mark, uint32_t gen, int pc, const char *s, size_t n, size_t i,
                int *stack)
{
    size_t top = 0;
    stack[top++] = pc;
    while (top) {
        int k = stack[--top];
        if (mark[k] == gen) continue;
        mark[k] = gen;
        const Inst *in = &re->prog[k];
        switch (in->op) {
        case I_JMP: stack[top++] = in->x; break;
        case I_SPLIT: stack[top++] = in->y; stack[top++] = in->x; break;
        case I_ASSERT: if (assert_holds(in->x, s, n, i)) stack[top++] = k + 1; break;
        case I_MATCH: return true;
        default: l->pc[l->n++] = k;
        }
    }
    return false;
}

bool regex_match(const Regex *re, const char *s, size_t n)
{
    size_t m = re->n;
    /* two thread lists of at most m each, and a stack for following empty
     * moves: each instruction is expanded once per add and pushes at most two,
     * so 2m + 1 entries suffice */
    int *buf = malloc((4 * m + 1) * sizeof *buf);
    uint32_t *mark = calloc(m, sizeof *mark);
    List cur = { buf, 0 }, nxt = { buf + m, 0 };
    int *bigstack = buf + 2 * m;
    uint32_t gen = 1;
    bool matched = false;
    for (size_t i = 0;; ) {
        /* unanchored: a new attempt may start at every position */
        if (add(re, &cur, mark, gen, 0, s, n, i, bigstack)) { matched = true; break; }
        if (i >= n) break;
        size_t len;
        uint32_t r = rune_at(s, n, i, &len);
        gen++;
        nxt.n = 0;
        for (size_t t = 0; t < cur.n; t++) {
            const Inst *in = &re->prog[cur.pc[t]];
            bool ok = in->op == I_ANYNL || (in->op == I_ANY && r != '\n') ||
                      (in->op == I_CLASS && class_has(&re->classes[in->x], r));
            if (ok && add(re, &nxt, mark, gen, cur.pc[t] + 1, s, n, i + len, bigstack)) { matched = true; break; }
        }
        if (matched) break;
        List tmp = cur;
        cur = nxt;
        nxt = tmp;
        i += len;
    }
    free(mark);
    free(buf);
    return matched;
}
