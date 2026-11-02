/* triangle fmt: Triangle source in its canonical layout, as gofmt and
 * cue fmt give Go and CUE theirs.
 *
 * The layout is decided line by line, and lines are never joined or split:
 * a line's tokens are spaced by rule (one space after ',' and ':', around
 * binary operators, inside '{ }'; none inside '[ ]' and '( )', or after a
 * prefix such as '>=' or '*'; elsewhere as written, one space at most). A
 * line is indented by what is open at its start: four spaces past the line
 * that opened a bracket left open at its end, or, opened with more on its
 * line, at the first thing after it. Consecutive fields at one level are
 * aligned (their values, then their trailing attributes), as are
 * consecutive lets; comment lines don't break a run, blank lines do. At most
 * two blank lines are kept together.
 *
 * Formatting is checked: the result must scan to exactly the source's
 * tokens and comments, or nothing is returned. */
#include "fmt.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { F_WORD, F_REF, F_TAG, F_NUM, F_STR, F_ATTR, F_PUNCT, F_COMMENT } FKind;

typedef struct {
    FKind k;
    const char *s;
    size_t n;
    int line, col;     /* 1-based, in the source */
} FTok;

typedef struct { FTok *v; size_t n, cap; } FToks;

static void push(FToks *t, FTok x)
{
    if (t->n == t->cap) t->v = realloc(t->v, (t->cap = t->cap ? t->cap * 2 : 256) * sizeof *t->v);
    t->v[t->n++] = x;
}

static char *errorf(int line, int col, const char *what)
{
    char *m = malloc(strlen(what) + 32);
    sprintf(m, "%d:%d: %s", line, col, what);
    return m;
}

/* --- scanning, with the loader's token boundaries --------------------------------------- */

static int name_start(char c) { return isalpha((unsigned char) c) || c == '_'; }
static int name_char(char c) { return isalnum((unsigned char) c) || c == '_'; }

static int punct_is(const FTok *t, const char *p) { return t->k == F_PUNCT && t->n == strlen(p) && !memcmp(t->s, p, t->n); }

static int operand_end(const FTok *t)
{
    if (!t) return 0;
    if (t->k == F_WORD || t->k == F_REF || t->k == F_TAG || t->k == F_NUM || t->k == F_STR) return 1;
    return punct_is(t, ")") || punct_is(t, "]") || punct_is(t, "}");
}

static size_t path_segments(const char *s)
{
    const char *t = s;
    for (;;) {
        if (t[0] == '.' && name_start(t[1])) {
            t++;
            while (name_char(*t)) t++;
        } else if (t[0] == '[' && isdigit((unsigned char) t[1])) {
            const char *u = t + 1;
            while (isdigit((unsigned char) *u)) u++;
            if (*u != ']') break;
            t = u + 1;
        } else break;
    }
    return (size_t) (t - s);
}

static int hashes_at(const char *s, int n)
{
    for (int k = 0; k < n; k++) if (s[k] != '#') return 0;
    return 1;
}

static int raw_start(const char *s)
{
    while (*s == '#') s++;
    return *s == '"';
}

/* The tokens and comments of src; NULL error, or a message. */
static char *scan(const char *src, FToks *out)
{
    const char *s = src;
    int line = 1, col = 1;
#define ADV() do { if (*s == '\n') { line++; col = 1; } else col++; s++; } while (0)
    while (*s) {
        if (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') { ADV(); continue; }
        FTok t = { F_PUNCT, s, 0, line, col };
        char ch = *s;
        if (s[0] == '/' && s[1] == '/') {
            t.k = F_COMMENT;
            while (*s && *s != '\n') ADV();
            while (s > t.s && (s[-1] == ' ' || s[-1] == '\t' || s[-1] == '\r')) { s--; col--; }   /* not its trailing space */
            t.n = (size_t) (s - t.s);
            while (*s == ' ' || *s == '\t' || *s == '\r') ADV();
            push(out, t);
            continue;
        }
        if (name_start(ch) || (ch == '#' && name_start(s[1]))) {
            t.k = F_WORD;
            ADV();
            while (name_char(*s)) ADV();
            if (ch != '#' && *s == '.' && s[1] == '#') {
                ADV();
                ADV();
                while (name_char(*s)) ADV();
            }
            for (size_t n = path_segments(s); n; n--) ADV();
        } else if (ch == '.' && name_start(s[1])) {
            t.k = F_REF;
            for (size_t n = path_segments(s); n; n--) ADV();
        } else if (ch == '$') {
            t.k = F_TAG;
            ADV();
            while (name_char(*s)) ADV();
        } else if (ch == '-' && out->n && operand_end(&out->v[out->n - 1])) {
            ADV();
        } else if (isdigit((unsigned char) ch) || (ch == '-' && isdigit((unsigned char) s[1]))) {
            t.k = F_NUM;
            ADV();
            while (isdigit((unsigned char) *s) || *s == '.') {
                if (*s == '.' && s[1] == '.') break;
                ADV();
            }
            if (isalpha((unsigned char) *s))
                while (isalnum((unsigned char) *s)) ADV();
        } else if (ch == '"' || (ch == '#' && raw_start(s))) {
            t.k = F_STR;
            int hashes = 0;
            while (*s == '#') { hashes++; ADV(); }
            ADV();
            for (;;) {
                if (!*s || *s == '\n') return errorf(t.line, t.col, "unterminated string");
                if (*s == '"' && hashes_at(s + 1, hashes)) {
                    ADV();
                    for (int k = 0; k < hashes; k++) ADV();
                    break;
                }
                if (*s != '\\' || !hashes_at(s + 1, hashes)) { ADV(); continue; }
                ADV();
                for (int k = 0; k < hashes; k++) ADV();
                if (*s == '(') {                      /* \(expr), over any strings inside */
                    ADV();
                    int depth = 1;
                    while (*s && *s != '\n' && depth) {
                        if (*s == '"') {
                            ADV();
                            while (*s && *s != '"' && *s != '\n') { if (*s == '\\' && s[1]) ADV(); ADV(); }
                            if (*s == '"') ADV();
                            continue;
                        }
                        if (*s == '(') depth++;
                        if (*s == ')' && --depth == 0) break;
                        ADV();
                    }
                    if (*s != ')') return errorf(t.line, t.col, "unterminated interpolation");
                    ADV();
                    continue;
                }
                if (*s && *s != '\n') ADV();           /* the escaped character */
            }
        } else if (ch == '@') {
            t.k = F_ATTR;
            ADV();
            while (name_char(*s)) ADV();
            if (*s == '(') {
                int depth = 0;
                do {
                    if (*s == '(') depth++;
                    if (*s == ')') depth--;
                    if (*s == '\n') return errorf(t.line, t.col, "an attribute across lines can't be formatted");
                    ADV();
                } while (*s && depth);
                if (depth) return errorf(t.line, t.col, "unterminated attribute");
            }
        } else {
            static const char *const two[] = { "&&", "||", ">=", "<=", "=~", "!~", "==", "!=" };
            if (s[0] == '.' && s[1] == '.' && s[2] == '.') { ADV(); ADV(); ADV(); }
            else {
                int k = 0;
                for (size_t i = 0; i < sizeof two / sizeof *two && !k; i++)
                    if (s[0] == two[i][0] && s[1] == two[i][1]) k = 2;
                if (!k && !strchr(":,{}[]()&|*+-/<>=!", ch)) {
                    char m[48];
                    snprintf(m, sizeof m, "unexpected character '%c'", ch);
                    return errorf(line, col, m);
                }
                for (k = k ? k : 1; k; k--) ADV();
            }
        }
        t.n = (size_t) (s - t.s);
        push(out, t);
    }
    return NULL;
#undef ADV
}

/* --- spacing within a line ---------------------------------------------------------------- */

static int is_open(const FTok *t) { return punct_is(t, "{") || punct_is(t, "[") || punct_is(t, "("); }
static int is_close(const FTok *t) { return punct_is(t, "}") || punct_is(t, "]") || punct_is(t, ")"); }

/* Whether t, after prev, is a binary operator (spaced) rather than a prefix. */
static int binary(const FTok *t, const FTok *prev)
{
    if (t->k != F_PUNCT) return 0;
    static const char *const always[] = { "&", "|", "&&", "||", "==", "!=", "+", "/", "=" };
    for (size_t i = 0; i < sizeof always / sizeof *always; i++) if (punct_is(t, always[i])) return 1;
    if (punct_is(t, "*") || punct_is(t, "-") || punct_is(t, ">=") || punct_is(t, "<=") || punct_is(t, ">") ||
        punct_is(t, "<"))
        return operand_end(prev);
    return 0;
}

static int prefix(const FTok *t, const FTok *prev)
{
    if (t->k != F_PUNCT) return 0;
    if (punct_is(t, "!") || punct_is(t, "=~") || punct_is(t, "!~") || punct_is(t, "...")) return 1;
    if (punct_is(t, "*") || punct_is(t, "-") || punct_is(t, ">=") || punct_is(t, "<=") || punct_is(t, ">") ||
        punct_is(t, "<"))
        return !operand_end(prev);
    return 0;
}

/* The space between a and b on one line: 0 or 1. pa is the token before a. */
static int space_between(const FTok *pa, const FTok *a, const FTok *b, int written)
{
    if (b->k == F_COMMENT || b->k == F_ATTR) return 1;
    if (punct_is(b, ",") || punct_is(b, ":")) return 0;
    if (punct_is(a, ",") || punct_is(a, ":")) return 1;
    if (binary(b, a) || binary(a, pa)) return 1;
    if (punct_is(a, "{")) return !punct_is(b, "}");
    if (punct_is(b, "}")) return 1;
    if (punct_is(a, "[") || punct_is(a, "(") || punct_is(b, "]") || punct_is(b, ")")) return 0;
    if (prefix(a, pa)) return 0;
    return written ? 1 : 0;
}

/* --- lines ------------------------------------------------------------------------------- */

typedef struct {
    size_t first, n;       /* its tokens */
    int blank;
    char *body;            /* tokens spaced, without indentation */
    size_t *off;           /* each token's offset in body */
    int indent;
    int carried;           /* it carries on the line of code before (which ended in an operator) */
    int context;           /* the innermost bracket open at its start (a token index), or -1 */
    int kind;              /* 1 a field, 2 a let, 3 a comment alone, 0 other */
    size_t label_end;      /* a field's offset after its ':', a let's after its name */
    size_t value_at;       /* where its value starts, after alignment */
    int attr_tok;          /* its first trailing attribute (index in line), or -1 */
    int comment_tok;       /* its trailing comment, or -1 */
} Line;

typedef struct { char *s; size_t n, cap; } Out;

static void out_put(Out *o, const char *s, size_t n)
{
    if (o->n + n + 1 > o->cap) {
        while (o->n + n + 1 > o->cap) o->cap = o->cap ? o->cap * 2 : 4096;
        o->s = realloc(o->s, o->cap);
    }
    memcpy(o->s + o->n, s, n);
    o->n += n;
    o->s[o->n] = 0;
}

static void out_spaces(Out *o, size_t n) { while (n--) out_put(o, " ", 1); }

/* Lay a line's tokens out, with `pad[i]` extra spaces before token i. */
static void layout(Line *l, const FTok *tok, const size_t *pad)
{
    Out o = { 0 };
    out_put(&o, "", 0);
    free(l->off);
    l->off = malloc((l->n ? l->n : 1) * sizeof *l->off);
    for (size_t i = 0; i < l->n; i++) {
        const FTok *t = &tok[l->first + i];
        if (i) {
            const FTok *a = t - 1, *pa = i >= 2 ? t - 2 : NULL;
            int written = a->s + a->n < t->s;
            out_spaces(&o, (size_t) space_between(pa, a, t, written) + (pad ? pad[i] : 0));
        }
        l->off[i] = o.n;
        out_put(&o, t->s, t->n);
    }
    free(l->body);
    l->body = o.s;
}

/* A field's line: a label (a name, a string, or a parenthesised label) and
 * ':', and nothing left open at its end; a let's: let name = value. */
static void classify(Line *l, const FTok *tok)
{
    const FTok *t = &tok[l->first];
    l->kind = 0;
    l->attr_tok = l->comment_tok = -1;
    if (!l->n) return;
    if (l->n == 1 && t->k == F_COMMENT) { l->kind = 3; return; }
    size_t end = l->n;
    if (tok[l->first + end - 1].k == F_COMMENT) l->comment_tok = (int) --end;
    size_t a = end;
    while (a > 1 && tok[l->first + a - 1].k == F_ATTR) a--;
    if (a < end && a > 0) l->attr_tok = (int) a;
    int depth = 0;
    for (size_t i = 0; i < end; i++) {
        if (is_open(&t[i])) depth++;
        else if (is_close(&t[i]) && --depth < 0) return;
        else if (!depth && punct_is(&t[i], ",") && i + 1 < end) return;     /* more than one field */
    }
    size_t colon = 0;
    if (t[0].k == F_WORD || t[0].k == F_STR) colon = 1;
    else if (punct_is(&t[0], "(")) {
        int d = 0;
        for (size_t i = 0; i < end; i++) {
            if (is_open(&t[i])) d++;
            else if (is_close(&t[i]) && --d == 0) { colon = i + 1; break; }
        }
    }
    if (t[0].k == F_WORD && t[0].n == 3 && !memcmp(t[0].s, "let", 3) && end >= 4 && t[1].k == F_WORD &&
        punct_is(&t[2], "=") && !depth) {
        l->kind = 2;
        l->label_end = 2;
        return;
    }
    /* a field whose value only opens a block (`roles: {`) stands apart;
     * one whose value is more and runs on (`match: #Wedging & {`) lines up
     * with the fields around it */
    if (colon && colon + 1 < end && punct_is(&t[colon], ":") &&
        !(depth && colon + 2 == end && is_open(&t[colon + 1]))) {
        l->kind = 1;
        l->label_end = colon + 1;
    }
}

/* Indentation, from what is open at each line's start. */
typedef struct { int tok; int hanging; int line_indent; int col; int col_after; } Open;

static char *indent_lines(Line *lines, size_t nl, const FTok *tok, int *parent)
{
    Open *st = malloc(sizeof *st);
    size_t sn = 0, scap = 1;
    char *err = NULL;
    int carried = 0;          /* the last line of code ended in an operator: this one carries on */
    for (size_t li = 0; li < nl && !err; li++) {
        Line *l = &lines[li];
        l->context = sn ? st[sn - 1].tok : -1;
        if (!l->n) { l->indent = 0; continue; }
        const FTok *t0 = &tok[l->first];
        if (is_close(t0) && sn) l->indent = st[sn - 1].hanging ? st[sn - 1].line_indent : st[sn - 1].col;
        else if (sn) l->indent = st[sn - 1].hanging ? st[sn - 1].line_indent + 4 : st[sn - 1].col_after;
        else l->indent = 0;
        l->carried = carried;
        if (carried && !is_close(t0)) l->indent += 4;
        size_t last = l->n;
        while (last && tok[l->first + last - 1].k == F_COMMENT) last--;
        if (last) {
            const FTok *e = &tok[l->first + last - 1];
            carried = binary(e, e > tok ? e - 1 : NULL) || punct_is(e, ":");
        }
        for (size_t i = 0; i < l->n; i++) {
            const FTok *t = &tok[l->first + i];
            if (is_open(t)) {
                if (sn == scap) st = realloc(st, (scap *= 2) * sizeof *st);
                Open o = { (int) (l->first + i), i + 1 >= last, l->indent, l->indent + (int) l->off[i], 0 };
                o.col_after = i + 1 < last ? l->indent + (int) l->off[i + 1] : o.col + 1;
                parent[l->first + i] = sn ? st[sn - 1].tok : -1;
                st[sn++] = o;
            } else if (is_close(t)) {
                const FTok *o = sn ? &tok[st[sn - 1].tok] : NULL;
                char want = punct_is(t, "}") ? '{' : punct_is(t, "]") ? '[' : '(';
                if (!o || o->s[0] != want) {
                    err = errorf(t->line, t->col, "unbalanced brackets");
                    break;
                }
                sn--;
            }
        }
    }
    if (!err && sn) err = errorf(tok[st[sn - 1].tok].line, tok[st[sn - 1].tok].col, "a bracket left open");
    free(st);
    return err;
}

/* Align a run of fields (or lets): their values, and their trailing
 * attributes and comments where two or more have them. */
static void align_run(Line *lines, const size_t *run, size_t n, const FTok *tok)
{
    size_t want = 0;
    for (size_t r = 0; r < n; r++) {
        Line *l = &lines[run[r]];
        size_t e = l->off[l->label_end - 1] + tok[l->first + l->label_end - 1].n;
        if (e > want) want = e;
    }
    for (size_t r = 0; r < n; r++) {
        Line *l = &lines[run[r]];
        size_t *pad = calloc(l->n, sizeof *pad);
        size_t e = l->off[l->label_end - 1] + tok[l->first + l->label_end - 1].n;
        pad[l->label_end] = want - e;
        layout(l, tok, pad);
        free(pad);
    }
    /* then the trailing attributes, and the trailing comments */
    /* trailing attributes, then trailing comments, where the run sets one
     * apart by two spaces or more: at the furthest right of those, and a
     * line reaching past it has one space. Alignment is completed, never
     * begun: with none set apart, each has one space. */
    for (int pass = 0; pass < 2; pass++) {
        size_t with = 0, col = 0;
        for (size_t r = 0; r < n; r++) {
            Line *l = &lines[run[r]];
            int at = pass ? l->comment_tok : l->attr_tok;
            if (at < 0) continue;
            with++;
            const FTok *before = &tok[l->first + (size_t) at - 1];
            size_t end = l->off[at - 1] + before->n;
            size_t was = (size_t) tok[l->first + (size_t) at].col - 1;
            size_t was_end = (size_t) before->col - 1 + before->n;
            if (was >= was_end + 2 && end + (was - was_end) > col) col = end + (was - was_end);
        }
        if (!with || !col) continue;
        for (size_t r = 0; r < n; r++) {
            Line *l = &lines[run[r]];
            int at = pass ? l->comment_tok : l->attr_tok;
            if (at < 0) continue;
            size_t *pad = calloc(l->n, sizeof *pad);
            /* keep the value alignment just made */
            size_t e = l->off[l->label_end - 1] + tok[l->first + l->label_end - 1].n;
            pad[l->label_end] = l->off[l->label_end] - e - 1;
            if (pass && l->attr_tok >= 0) pad[l->attr_tok] = l->off[l->attr_tok] - l->off[l->attr_tok - 1] -
                                                             tok[l->first + (size_t) l->attr_tok - 1].n - 1;
            size_t now = l->off[at - 1] + tok[l->first + (size_t) at - 1].n + 1;
            pad[at] = col > now ? col - now : 0;
            layout(l, tok, pad);
            free(pad);
        }
    }
}

static int within(const int *parent, int ctx, int c)
{
    if (c < 0) return ctx >= 0;
    for (int k = ctx; k >= 0; k = parent[k]) if (k == c) return 1;
    return 0;
}

/* Runs of fields (or of lets) at one level, one after another: a blank
 * line, or anything else at that level but a comment line, ends one. The lines
 * of a field's value that runs on below it belong to the field. Each level
 * (each bracket, and the file's top) is taken in turn. */
static void align(Line *lines, size_t nl, const FTok *tok, const int *parent, size_t ntok)
{
    size_t *run = malloc((nl ? nl : 1) * sizeof *run);
    for (long c = -1; c < (long) ntok; c++) {
        if (c >= 0 && !is_open(&tok[c])) continue;
        size_t from = c < 0 ? 0 : (size_t) tok[c].line - 1;
        size_t n = 0;
        int kind = 0, seen = 0;
        for (size_t li = from; li <= nl; li++) {
            Line *l = li < nl ? &lines[li] : NULL;
            if (l && l->context != (int) c && within(parent, l->context, (int) c)) continue;   /* deeper */
            if (l && n && l->carried && l->context == (int) c) continue;      /* the field before, carried on */
            int here = l && l->context == (int) c;
            if (here) seen = 1;
            if (here && l->kind == 3) continue;               /* a comment line: the run goes on */
            if (here && (l->kind == 1 || l->kind == 2) && n && l->kind == kind) {
                run[n++] = li;
                continue;
            }
            if (n) align_run(lines, run, n, tok);
            n = 0;
            if (!here) {
                if (seen) break;                          /* the level has closed */
                continue;
            }
            if (l->kind == 1 || l->kind == 2) {
                run[n++] = li;
                kind = l->kind;
            }
        }
    }
    free(run);
}

/* --- the whole --------------------------------------------------------------------------- */

static int same_tokens(const FToks *a, const FToks *b)
{
    if (a->n != b->n) return 0;
    for (size_t i = 0; i < a->n; i++)
        if (a->v[i].k != b->v[i].k || a->v[i].n != b->v[i].n || memcmp(a->v[i].s, b->v[i].s, a->v[i].n)) return 0;
    return 1;
}

char *fmt_source(const char *src, char **err)
{
    FToks toks = { 0 };
    *err = scan(src, &toks);
    if (*err) { free(toks.v); return NULL; }

    /* the source's lines, each with its tokens */
    size_t nl = 1;
    for (const char *s = src; *s; s++) nl += *s == '\n';
    Line *lines = calloc(nl, sizeof *lines);
    size_t ti = 0;
    for (size_t li = 0; li < nl; li++) {
        lines[li].first = ti;
        while (ti < toks.n && toks.v[ti].line == (int) li + 1) ti++;
        lines[li].n = ti - lines[li].first;
        lines[li].blank = lines[li].n == 0;
        layout(&lines[li], toks.v, NULL);
        classify(&lines[li], toks.v);
    }

    /* indentation, then alignment, then indentation again: a bracket's
     * column can move with the alignment of its line */
    int *parent = malloc((toks.n ? toks.n : 1) * sizeof *parent);
    for (size_t i = 0; i < toks.n; i++) parent[i] = -1;
    *err = indent_lines(lines, nl, toks.v, parent);
    if (!*err) {
        align(lines, nl, toks.v, parent, toks.n);
        *err = indent_lines(lines, nl, toks.v, parent);
    }
    free(parent);

    Out o = { 0 };
    out_put(&o, "", 0);
    if (!*err) {
        size_t first = 0, last = nl;
        while (first < nl && lines[first].blank) first++;
        while (last > first && lines[last - 1].blank) last--;
        int blanks = 0;
        for (size_t li = first; li < last; li++) {
            Line *l = &lines[li];
            if (l->blank) {
                if (++blanks <= 2) out_put(&o, "\n", 1);
                continue;
            }
            blanks = 0;
            out_spaces(&o, (size_t) l->indent);
            out_put(&o, l->body, strlen(l->body));
            out_put(&o, "\n", 1);
        }
    }
    for (size_t li = 0; li < nl; li++) { free(lines[li].body); free(lines[li].off); }
    free(lines);

    /* the check: exactly the source's tokens and comments */
    if (!*err) {
        FToks again = { 0 };
        char *e2 = scan(o.s, &again);
        if (e2 || !same_tokens(&toks, &again))
            *err = errorf(1, 1, "formatting would change the source's tokens (a bug in triangle fmt); left as it is");
        free(e2);
        free(again.v);
    }
    free(toks.v);
    if (*err) { free(o.s); return NULL; }
    return o.s;
}
