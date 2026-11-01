/* The Triangle language server: `triangle lsp`, over stdio.
 *
 * A content build is a directory: every .tri file in the directory of an open
 * document loads together, as the game loads its content directory. Each change
 * reloads the directory, with the text of open documents in place of the
 * files on disk; loading is fast enough (milliseconds) to do on every edit.
 *
 * Diagnostics come from the loader. Hover, definition, references, symbols and
 * completion come from the declarations the loader records (which survive a
 * syntax error) and from a lexical scan of the sources. A spec shown on hover
 * comes from the last build that loaded without errors. */
#include "json.h"
#include "triangle.h"

#include <ctype.h>
#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* --- documents and builds -------------------------------------------------------------- */

typedef struct { char *path; char *text; } Doc;

typedef struct {
    char        *dir;
    char       **files;          /* the sources of `cur`, in load order */
    char       **texts;
    size_t       nfiles;
    TriContent  *cur;            /* the latest load */
    TriContent  *good;           /* the latest load without errors (may be cur) */
    TriDecl     *decls;          /* cur's declarations */
    size_t       ndecls;
    const char **names;          /* their names, sorted, for lookup */
    size_t       nnames;
    char       **published;      /* files given diagnostics last time */
    size_t       npublished;
} Build;

static Doc   *docs;
static size_t ndocs;
static Build *builds;
static size_t nbuilds;

static char *xstrdup(const char *s)
{
    size_t n = strlen(s);
    char *r = malloc(n + 1);
    memcpy(r, s, n + 1);
    return r;
}

static char *xstrndup(const char *s, size_t n)
{
    char *r = malloc(n + 1);
    memcpy(r, s, n);
    r[n] = 0;
    return r;
}

static char *read_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *s = malloc((size_t) (len < 0 ? 0 : len) + 1);
    size_t got = len > 0 ? fread(s, 1, (size_t) len, f) : 0;
    s[got] = 0;
    fclose(f);
    return s;
}

static Doc *doc_find(const char *path)
{
    for (size_t i = 0; i < ndocs; i++) if (!strcmp(docs[i].path, path)) return &docs[i];
    return NULL;
}

static char *dir_of(const char *path)
{
    const char *slash = strrchr(path, '/');
    return slash ? xstrndup(path, (size_t) (slash - path)) : xstrdup(".");
}

static int cmp_str(const void *a, const void *b) { return strcmp(*(char *const *) a, *(char *const *) b); }

static int has_ext(const char *name, const char *ext)
{
    size_t n = strlen(name), e = strlen(ext);
    return n > e && !strcmp(name + n - e, ext);
}

/* The .tri files of a directory, sorted, plus open documents there that are
 * not on disk yet. */
static size_t dir_files(const char *dir, char ***out)
{
    char **v = NULL;
    size_t n = 0, cap = 0;
    DIR *d = opendir(dir);
    struct dirent *e;
    while (d && (e = readdir(d))) {
        if (e->d_name[0] == '.' || !has_ext(e->d_name, ".tri")) continue;
        if (n == cap) v = realloc(v, (cap = cap ? cap * 2 : 16) * sizeof *v);
        size_t len = strlen(dir) + strlen(e->d_name) + 2;
        v[n] = malloc(len);
        snprintf(v[n++], len, "%s/%s", dir, e->d_name);
    }
    if (d) closedir(d);
    for (size_t i = 0; i < ndocs; i++) {
        char *dd = dir_of(docs[i].path);
        int here = !strcmp(dd, dir);
        free(dd);
        if (!here) continue;
        int listed = 0;
        for (size_t k = 0; k < n && !listed; k++) listed = !strcmp(v[k], docs[i].path);
        if (listed) continue;
        if (n == cap) v = realloc(v, (cap = cap ? cap * 2 : 16) * sizeof *v);
        v[n++] = xstrdup(docs[i].path);
    }
    qsort(v, n, sizeof *v, cmp_str);
    *out = v;
    return n;
}

static void free_strings(char **v, size_t n)
{
    for (size_t i = 0; i < n; i++) free(v[i]);
    free(v);
}

static void lines_clear(void);

static void build_reload(Build *b)
{
    lines_clear();
    free_strings(b->files, b->nfiles);
    free_strings(b->texts, b->nfiles);
    b->nfiles = dir_files(b->dir, &b->files);
    b->texts = calloc(b->nfiles ? b->nfiles : 1, sizeof *b->texts);
    for (size_t i = 0; i < b->nfiles; i++) {
        Doc *d = doc_find(b->files[i]);
        b->texts[i] = d ? xstrdup(d->text) : read_file(b->files[i]);
        if (!b->texts[i]) b->texts[i] = xstrdup("");
    }
    TriContent *c = tri_content_load_strings((const char *const *) b->files, (const char *const *) b->texts,
                                             b->nfiles);
    if (b->cur && b->cur != b->good) tri_content_free(b->cur);
    b->cur = c;
    if (tri_content_ok(c)) {
        if (b->good) tri_content_free(b->good);
        b->good = c;
    }
    free(b->decls);
    free(b->names);
    b->ndecls = b->nnames = tri_decl_count(c);
    b->decls = malloc((b->ndecls ? b->ndecls : 1) * sizeof *b->decls);
    b->names = malloc((b->nnames ? b->nnames : 1) * sizeof *b->names);
    TriDecl d;
    for (size_t i = 0; tri_decl(c, i, &d); i++) {
        b->decls[i] = d;
        b->names[i] = d.name;
    }
    qsort(b->names, b->nnames, sizeof *b->names, cmp_str);
}

static Build *build_for(const char *path)
{
    char *dir = dir_of(path);
    for (size_t i = 0; i < nbuilds; i++)
        if (!strcmp(builds[i].dir, dir)) { free(dir); return &builds[i]; }
    builds = realloc(builds, (nbuilds + 1) * sizeof *builds);
    Build *b = &builds[nbuilds++];
    memset(b, 0, sizeof *b);
    b->dir = dir;
    return b;
}

static int declared(const Build *b, const char *name)
{
    return bsearch(&name, b->names, b->nnames, sizeof *b->names, cmp_str) != NULL;
}

static const char *build_text(const Build *b, const char *path)
{
    for (size_t i = 0; i < b->nfiles; i++) if (!strcmp(b->files[i], path)) return b->texts[i];
    return NULL;
}

/* --- URIs and positions -------------------------------------------------------------------- */

static char *uri_to_path(const char *uri)
{
    if (!uri) return NULL;
    if (!strncmp(uri, "file://", 7)) uri += 7;
    Str b = { 0 };
    str_puts(&b, "");
    for (const char *s = uri; *s; s++) {
        if (*s == '%' && isxdigit((unsigned char) s[1]) && isxdigit((unsigned char) s[2])) {
            char h[3] = { s[1], s[2], 0 };
            str_putc(&b, (char) strtol(h, NULL, 16));
            s += 2;
        } else str_putc(&b, *s);
    }
    return b.s;
}

static void put_uri(Str *out, const char *path)
{
    Str b = { 0 };
    str_puts(&b, "file://");
    for (const unsigned char *s = (const unsigned char *) path; *s; s++) {
        if (isalnum(*s) || strchr("/-._~", *s)) str_putc(&b, (char) *s);
        else str_printf(&b, "%%%02X", *s);
    }
    str_json(out, b.s);
    str_free(&b);
}

/* Line starts of the sources in use, so positions convert without rescanning
 * a file. Keyed by the text's address: cleared whenever sources change. */
typedef struct { const char *text; size_t *starts, n; } Lines;
static Lines lines_cache[64];
static size_t nlines_cache;

static void lines_clear(void)
{
    for (size_t i = 0; i < nlines_cache; i++) free(lines_cache[i].starts);
    nlines_cache = 0;
}

static const Lines *lines_of(const char *text)
{
    for (size_t i = 0; i < nlines_cache; i++) if (lines_cache[i].text == text) return &lines_cache[i];
    if (nlines_cache == sizeof lines_cache / sizeof *lines_cache) lines_clear();
    Lines *l = &lines_cache[nlines_cache++];
    size_t cap = 64;
    l->text = text;
    l->starts = malloc(cap * sizeof *l->starts);
    l->starts[0] = 0;
    l->n = 1;
    for (size_t i = 0; text[i]; i++)
        if (text[i] == '\n') {
            if (l->n == cap) l->starts = realloc(l->starts, (cap *= 2) * sizeof *l->starts);
            l->starts[l->n++] = i + 1;
        }
    return l;
}

/* Byte offset of the start of a line (from 0); the text's length past the end. */
static size_t line_start(const char *text, int line)
{
    const Lines *l = lines_of(text);
    if (line < 0) return 0;
    return (size_t) line < l->n ? l->starts[line] : strlen(text);
}

/* LSP positions count UTF-16 code units. */
static size_t offset_of(const char *text, int line, int character)
{
    size_t off = line_start(text, line);
    int units = 0;
    while (text[off] && text[off] != '\n' && units < character) {
        unsigned char c = (unsigned char) text[off];
        size_t len = c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
        units += len == 4 ? 2 : 1;
        for (size_t k = 0; k < len && text[off]; k++) off++;
    }
    return off;
}

static void position_of(const char *text, size_t off, int *line, int *character)
{
    const Lines *l = lines_of(text);
    size_t lo = 0, hi = l->n;                   /* the last line starting at or before off */
    while (hi - lo > 1) {
        size_t mid = (lo + hi) / 2;
        if (l->starts[mid] <= off) lo = mid; else hi = mid;
    }
    int units = 0;
    for (size_t i = l->starts[lo]; i < off && text[i];) {
        unsigned char c = (unsigned char) text[i];
        size_t len = c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
        units += len == 4 ? 2 : 1;
        i += len;
    }
    *line = (int) lo;
    *character = units;
}

static void put_range(Str *out, const char *text, size_t start, size_t end)
{
    int l0, c0, l1, c1;
    position_of(text, start, &l0, &c0);
    position_of(text, end, &l1, &c1);
    str_printf(out, "{\"start\":{\"line\":%d,\"character\":%d},\"end\":{\"line\":%d,\"character\":%d}}", l0, c0, l1,
               c1);
}

static void put_location(Str *out, const char *path, const char *text, size_t start, size_t end)
{
    str_puts(out, "{\"uri\":");
    put_uri(out, path);
    str_puts(out, ",\"range\":");
    put_range(out, text, start, end);
    str_putc(out, '}');
}

/* --- a lexical scan of sources ---------------------------------------------------------------- */

typedef enum { K_NAME, K_STRING, K_TAG, K_ATTR, K_NUMBER, K_PUNCT } Kind;
typedef struct { Kind k; size_t start, end; int depth; } Tok;   /* depth: brace and bracket nesting */
typedef struct { Tok *v; size_t n, cap; } Toks;

static int name_char(char c) { return isalnum((unsigned char) c) || c == '_'; }

static int raw_start(const char *s)
{
    while (*s == '#') s++;
    return *s == '"';
}

static int hashes_at(const char *s, size_t n)
{
    for (size_t k = 0; k < n; k++) if (s[k] != '#') return 0;
    return 1;
}

static void put_utf8(Str *b, unsigned long cp)
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

/* What a string token denotes, decoded (as the loader decodes it). */
static char *string_value(const char *tok, size_t n)
{
    size_t hashes = 0, i = 0;
    while (i < n && tok[i] == '#') { hashes++; i++; }
    i++;
    size_t end = n >= 1 + hashes ? n - 1 - hashes : i;
    Str b = { 0 };
    str_puts(&b, "");
    while (i < end) {
        if (tok[i] != '\\' || !hashes_at(tok + i + 1, hashes) || i + 1 + hashes >= end) { str_putc(&b, tok[i++]); continue; }
        i += 1 + hashes;
        char e = tok[i++];
        const char *simple = strchr("abfnrtv", e);
        if (simple) str_putc(&b, "\a\b\f\n\r\t\v"[simple - "abfnrtv"]);
        else if (e == 'u' || e == 'U') {
            size_t k = e == 'u' ? 4 : 8;
            char hex[9] = { 0 };
            for (size_t q = 0; q < k && i < end; q++) hex[q] = tok[i++];
            put_utf8(&b, strtoul(hex, NULL, 16));
        } else str_putc(&b, e);
    }
    return b.s;
}

/* The canonical spelling of a string, as declarations name atoms. */
static char *string_canonical(const char *v)
{
    Str b = { 0 };
    str_putc(&b, '"');
    for (const unsigned char *s = (const unsigned char *) v; *s; s++) {
        switch (*s) {
        case '"':  str_puts(&b, "\\\""); break;
        case '\\': str_puts(&b, "\\\\"); break;
        case '\n': str_puts(&b, "\\n"); break;
        case '\t': str_puts(&b, "\\t"); break;
        case '\r': str_puts(&b, "\\r"); break;
        default:
            if (*s < 0x20 || *s == 0x7f) str_printf(&b, "\\u%04x", *s);
            else str_putc(&b, (char) *s);
        }
    }
    str_putc(&b, '"');
    return b.s;
}

/* The token starting at s[i] (not whitespace or a comment); *depth tracks nesting. */
static Tok lex_one(const char *s, size_t i, int *depth)
{
    char c = s[i];
    Tok t = { K_PUNCT, i, i + 1, *depth };
    if (isalpha((unsigned char) c) || c == '_' || (c == '#' && (isalpha((unsigned char) s[i + 1]) || s[i + 1] == '_'))) {
        t.k = K_NAME;
        size_t j = i + 1;
        while (name_char(s[j])) j++;
        if (c != '#' && s[j] == '.' && (s[j + 1] == '#' || isalpha((unsigned char) s[j + 1]) || s[j + 1] == '_')) {
            j++;
            if (s[j] == '#') j++;
            while (name_char(s[j])) j++;
        }
        t.end = j;
    } else if (c == '"' || (c == '#' && raw_start(s + i))) {
        /* "..." with escapes, or #"..."# raw: \ escapes only when followed by
         * as many #s as opened it, and "#..# with that many closes */
        t.k = K_STRING;
        size_t j = i, hashes = 0;
        while (s[j] == '#') { hashes++; j++; }
        j++;
        while (s[j] && s[j] != '\n') {
            if (s[j] == '"' && hashes_at(s + j + 1, hashes)) { j += 1 + hashes; break; }
            if (s[j] == '\\' && hashes_at(s + j + 1, hashes) && s[j + 1 + hashes] && s[j + 1 + hashes] != '\n')
                j += 1 + hashes;
            j++;
        }
        t.end = j;
    } else if (c == '$' || c == '@') {
        t.k = c == '$' ? K_TAG : K_ATTR;
        size_t j = i + 1;
        while (name_char(s[j])) j++;
        if (c == '@' && s[j] == '(') {
            int d = 0;
            do {
                if (s[j] == '(') d++;
                if (s[j] == ')') d--;
                j++;
            } while (s[j] && d);
        }
        t.end = j;
    } else if (isdigit((unsigned char) c)) {
        t.k = K_NUMBER;
        size_t j = i;
        while (isalnum((unsigned char) s[j]) || s[j] == '.') j++;
        t.end = j;
    } else if (c == '{' || c == '[' || c == '(') ++*depth;
    else if (c == '}' || c == ']' || c == ')') { if (*depth) --*depth; t.depth = *depth; }
    else if (c == '.' && s[i + 1] == '.' && s[i + 2] == '.') t.end = i + 3;
    else if ((c == '>' || c == '<') && s[i + 1] == '=') t.end = i + 2;
    return t;
}

static void lex(const char *s, Toks *out)
{
    out->n = 0;
    size_t i = 0;
    int depth = 0;
    while (s[i]) {
        char c = s[i];
        if (isspace((unsigned char) c)) { i++; continue; }
        if (c == '/' && s[i + 1] == '/') { while (s[i] && s[i] != '\n') i++; continue; }
        Tok t = lex_one(s, i, &depth);
        if (out->n == out->cap) out->v = realloc(out->v, (out->cap = out->cap ? out->cap * 2 : 256) * sizeof *out->v);
        out->v[out->n++] = t;
        i = t.end;
    }
}

/* The package a source declares, or NULL. */
static char *source_package(const char *text)
{
    Toks t = { 0 };
    lex(text, &t);
    char *pkg = NULL;
    if (t.n >= 2 && t.v[0].k == K_NAME && t.v[0].end - t.v[0].start == 7 && !strncmp(text + t.v[0].start, "package", 7) &&
        t.v[1].k == K_NAME && !(t.n > 2 && t.v[2].k == K_PUNCT && text[t.v[2].start] == ':'))
        pkg = xstrndup(text + t.v[1].start, t.v[1].end - t.v[1].start);
    free(t.v);
    return pkg;
}

/* Resolves a name token as written in a source of package `pkg` to the
 * declaration name it means: a package's plain name is its own if it declares
 * one, else the root's. A string means an atom, or else the instance it names. */
static char *resolve(const Build *b, const char *pkg, const char *tok, size_t n)
{
    char buf[512];
    if (n + (pkg ? strlen(pkg) : 0) + 2 >= sizeof buf) return NULL;
    if (tok[0] == '"' || tok[0] == '#' ) {
        if (tok[0] == '#' && !raw_start(tok)) goto name;    /* a type name */
        char *v = string_value(tok, n);
        char *canon = string_canonical(v);
        char *r = NULL;
        if (declared(b, canon)) r = xstrdup(canon);
        else if (strlen(v) + (pkg ? strlen(pkg) : 0) + 2 < sizeof buf) r = resolve(b, pkg, v, strlen(v));
        free(canon);
        free(v);
        return r;
    }
name:
    if (!memchr(tok, '.', n) && pkg) {
        snprintf(buf, sizeof buf, "%s.%.*s", pkg, (int) n, tok);
        if (declared(b, buf)) return xstrdup(buf);
    }
    snprintf(buf, sizeof buf, "%.*s", (int) n, tok);
    return declared(b, buf) ? xstrdup(buf) : NULL;
}

/* The token under an offset (or just before it, at its end). */
static int token_at(const char *text, size_t off, Tok *out)
{
    Toks t = { 0 };
    lex(text, &t);
    int found = 0;
    for (size_t i = 0; i < t.n && !found; i++)
        if (t.v[i].start <= off && off <= t.v[i].end && t.v[i].k != K_PUNCT) {
            *out = t.v[i];
            found = 1;
        }
    free(t.v);
    return found;
}

/* --- declarations -------------------------------------------------------------------------------- */

/* A declaration's label starts at its location; it runs to the next
 * declaration in the same file, less the comments and blank lines before that
 * one (its docstring). */
static void decl_span(const Build *b, const TriDecl *d, const char *text, size_t *start, size_t *label_end,
                      size_t *end)
{
    *start = line_start(text, d->line - 1) + (size_t) (d->col - 1);
    int depth = 0;
    *label_end = text[*start] ? lex_one(text, *start, &depth).end : *start;
    size_t next = strlen(text);
    for (size_t i = 0; i < b->ndecls; i++) {
        TriDecl o = b->decls[i];
        if (strcmp(o.file, d->file)) continue;
        size_t s = line_start(text, o.line - 1) + (size_t) (o.col - 1);
        if (s > *start && s < next) next = s;
    }
    /* back to the start of the next declaration's line, then over the blank
     * and comment-only lines above it */
    size_t e = next;
    while (e > *start && text[e - 1] != '\n') e--;
    if (e <= *start) e = next;                  /* the next one is on this line */
    else for (;;) {
        size_t le = e - 1, ls = le;             /* the line before e: [ls, le) */
        while (ls > *start && text[ls - 1] != '\n') ls--;
        if (ls <= *start) break;                /* the declaration's own first line */
        size_t k = ls;
        while (k < le && (text[k] == ' ' || text[k] == '\t')) k++;
        if (k == le || (text[k] == '/' && text[k + 1] == '/')) e = ls;
        else break;
    }
    while (e > *start && (isspace((unsigned char) text[e - 1]) || text[e - 1] == ',')) e--;
    *end = e > *label_end ? e : *label_end;
}

static const char *kind_word(TriDeclKind k)
{
    return k == TRI_DECL_TYPE ? "type" : k == TRI_DECL_ATOM ? "atom" : "instance";
}

/* --- JSON-RPC ------------------------------------------------------------------------------------- */

static void send(const Str *body)
{
    printf("Content-Length: %zu\r\n\r\n%s", body->len, body->s);
    fflush(stdout);
}

static void reply(const J *id, const char *result_json)
{
    Str b = { 0 };
    str_puts(&b, "{\"jsonrpc\":\"2.0\",\"id\":");
    str_value(&b, id);
    str_puts(&b, ",\"result\":");
    str_puts(&b, result_json ? result_json : "null");
    str_putc(&b, '}');
    send(&b);
    str_free(&b);
}

static void reply_error(const J *id, int code, const char *msg)
{
    Str b = { 0 };
    str_puts(&b, "{\"jsonrpc\":\"2.0\",\"id\":");
    str_value(&b, id);
    str_printf(&b, ",\"error\":{\"code\":%d,\"message\":", code);
    str_json(&b, msg);
    str_puts(&b, "}}");
    send(&b);
    str_free(&b);
}

/* --- diagnostics ------------------------------------------------------------------------------------ */

static void publish(Build *b, const char *trigger)
{
    /* every file of the build, and any published before that has gone */
    size_t nf = b->nfiles;
    char **files = malloc((nf + b->npublished + 1) * sizeof *files);
    for (size_t i = 0; i < nf; i++) files[i] = xstrdup(b->files[i]);
    for (size_t i = 0; i < b->npublished; i++) {
        int dup = 0;
        for (size_t k = 0; k < b->nfiles && !dup; k++) dup = !strcmp(b->published[i], b->files[k]);
        if (!dup) files[nf++] = xstrdup(b->published[i]);
    }
    TriContent *c = b->cur;
    for (size_t f = 0; f < nf; f++) {
        const char *text = build_text(b, files[f]);
        if (!text) text = "";
        Str m = { 0 };
        str_puts(&m, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":");
        put_uri(&m, files[f]);
        str_puts(&m, ",\"diagnostics\":[");
        int first = 1;
        for (size_t i = 0; i < tri_diag_count(c); i++) {
            const char *file = NULL;
            int line = 0, col = 0;
            int located = tri_diag_location(c, i, &file, &line, &col) && build_text(b, file);
            if (located ? strcmp(file, files[f]) != 0 : strcmp(trigger, files[f]) != 0) continue;
            size_t start = located ? line_start(text, line - 1) + (size_t) (col - 1) : 0, end = start;
            Tok t;
            if (located && token_at(text, start, &t) && t.start == start) end = t.end;
            else if (located && text[start] && text[start] != '\n') end = start + 1;
            if (!first) str_putc(&m, ',');
            first = 0;
            str_puts(&m, "{\"range\":");
            put_range(&m, text, start, end);
            str_printf(&m, ",\"severity\":%d,\"source\":\"triangle\",\"message\":", tri_diag_is_error(c, i) ? 1 : 2);
            str_json(&m, located ? tri_diag_text(c, i) : tri_diag_message(c, i));
            str_putc(&m, '}');
        }
        str_puts(&m, "]}}");
        send(&m);
        str_free(&m);
    }
    free_strings(b->published, b->npublished);
    b->published = files;
    b->npublished = nf;
}

static void refresh(const char *path)
{
    Build *b = build_for(path);
    build_reload(b);
    publish(b, path);
}

/* --- requests ------------------------------------------------------------------------------------------ */

typedef struct {
    char       *path;
    Build      *b;
    const char *text;
    size_t      off;
} At;

static int at_position(const J *params, At *at)
{
    at->path = uri_to_path(json_str(json_path(params, "textDocument.uri")));
    if (!at->path) return 0;
    at->b = build_for(at->path);
    if (!at->b->cur) build_reload(at->b);
    at->text = build_text(at->b, at->path);
    if (!at->text) { free(at->path); return 0; }
    int line = (int) json_num(json_path(params, "position.line"), 0);
    int ch = (int) json_num(json_path(params, "position.character"), 0);
    at->off = offset_of(at->text, line, ch);
    return 1;
}

/* The declaration name meant by the token at the position, or NULL. */
static char *name_at(const At *at, Tok *tok)
{
    Tok t;
    if (!token_at(at->text, at->off, &t) || (t.k != K_NAME && t.k != K_STRING)) return NULL;
    if (tok) *tok = t;
    char *pkg = source_package(at->text);
    char *name = resolve(at->b, pkg, at->text + t.start, t.end - t.start);
    free(pkg);
    return name;
}

static void put_excerpt(Str *md, const Build *b, const TriDecl *d)
{
    const char *text = build_text(b, d->file);
    if (!text) return;
    size_t s, le, e;
    decl_span(b, d, text, &s, &le, &e);
    int lines = 0;
    size_t cut = s;
    while (cut < e && lines < 24) if (text[cut++] == '\n') lines++;
    str_puts(md, "```triangle\n");
    str_putn(md, text + s, cut - s);
    if (cut < e) str_puts(md, "\n// …");
    str_puts(md, "\n```\n");
}

static void hover(const J *id, const J *params)
{
    At at;
    if (!at_position(params, &at)) { reply(id, NULL); return; }
    Tok tok;
    char *name = name_at(&at, &tok);
    if (!name) { free(at.path); reply(id, NULL); return; }
    Str md = { 0 };
    const char *doc = NULL;
    int shown = 0;
    TriDeclKind kind = TRI_DECL_INSTANCE;
    for (size_t i = 0; i < at.b->ndecls; i++) {
        TriDecl d = at.b->decls[i];
        if (strcmp(d.name, name)) continue;
        if (!shown) str_printf(&md, "**%s** `%s`\n\n", kind_word(d.kind), name);
        kind = d.kind;
        if (d.doc && !doc) doc = d.doc;
        if (shown < 3) put_excerpt(&md, at.b, &d);
        shown++;
    }
    if (shown > 3) str_printf(&md, "\n*and %d more declarations*\n", shown - 3);
    if (doc) str_printf(&md, "\n%s\n", doc);
    TriContent *g = at.b->good;
    if (g && kind == TRI_DECL_TYPE) {
        TriType t = tri_type_named(g, name);
        if (t != TRI_BOTTOM) {
            str_puts(&md, "\n---\n");
            TriType p = tri_primary_parent(g, t);
            if (p != TRI_BOTTOM && p != t) {
                str_puts(&md, "\nSupertypes: ");
                for (int n = 0; p != TRI_BOTTOM && n < 16; n++) {
                    str_printf(&md, "%s`%s`", n ? " → " : "", tri_type_name(g, p));
                    TriType q = tri_primary_parent(g, p);
                    if (q == p) break;
                    p = q;
                }
                str_putc(&md, '\n');
            }
            size_t comps[32];
            size_t nc = tri_type_components(g, t, comps, 32);
            if (nc) {
                str_puts(&md, "\nComponents: ");
                for (size_t i = 0; i < nc && i < 32; i++)
                    str_printf(&md, "%s`%s`", i ? ", " : "", tri_component_name(g, comps[i]));
                str_putc(&md, '\n');
            }
        }
    } else if (g && kind == TRI_DECL_INSTANCE && tri_spec(g, name)) {
        size_t n = tri_inspect(g, name, NULL, 0);
        char *buf = malloc(n + 1);
        tri_inspect(g, name, buf, n + 1);
        str_puts(&md, "\n---\n\nSpec:\n```\n");
        str_putn(&md, buf, n > 4000 ? 4000 : n);
        str_puts(&md, n > 4000 ? "\n…\n```\n" : "```\n");
        free(buf);
    }
    Str r = { 0 };
    str_puts(&r, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
    str_json(&r, md.s);
    str_puts(&r, "},\"range\":");
    put_range(&r, at.text, tok.start, tok.end);
    str_putc(&r, '}');
    reply(id, r.s);
    str_free(&r);
    str_free(&md);
    free(name);
    free(at.path);
}

static void definition(const J *id, const J *params)
{
    At at;
    if (!at_position(params, &at)) { reply(id, "[]"); return; }
    char *name = name_at(&at, NULL);
    Str r = { 0 };
    str_putc(&r, '[');
    int first = 1;
    for (size_t i = 0; name && i < at.b->ndecls; i++) {
        TriDecl d = at.b->decls[i];
        const char *text = build_text(at.b, d.file);
        if (strcmp(d.name, name) || !text) continue;
        size_t s, le, e;
        decl_span(at.b, &d, text, &s, &le, &e);
        if (!first) str_putc(&r, ',');
        first = 0;
        put_location(&r, d.file, text, s, le);
    }
    str_putc(&r, ']');
    reply(id, r.s);
    str_free(&r);
    free(name);
    free(at.path);
}

static void references(const J *id, const J *params)
{
    At at;
    if (!at_position(params, &at)) { reply(id, "[]"); return; }
    char *name = name_at(&at, NULL);
    int with_decl = !json_path(params, "context.includeDeclaration") ||
                    json_path(params, "context.includeDeclaration")->k == J_TRUE;
    Str r = { 0 };
    str_putc(&r, '[');
    int first = 1;
    Toks t = { 0 };
    for (size_t f = 0; name && f < at.b->nfiles; f++) {
        const char *text = at.b->texts[f];
        char *pkg = source_package(text);
        lex(text, &t);
        for (size_t i = 0; i < t.n; i++) {
            Tok *k = &t.v[i];
            if (k->k != K_NAME && k->k != K_STRING) continue;
            /* a declaration's label: an unnested name followed by ':' */
            int label = k->depth == 0 && i + 1 < t.n && t.v[i + 1].k == K_PUNCT && text[t.v[i + 1].start] == ':';
            if (label && !with_decl) continue;
            char *m = resolve(at.b, pkg, text + k->start, k->end - k->start);
            if (m && !strcmp(m, name)) {
                if (!first) str_putc(&r, ',');
                first = 0;
                put_location(&r, at.b->files[f], text, k->start, k->end);
            }
            free(m);
        }
        free(pkg);
    }
    free(t.v);
    str_putc(&r, ']');
    reply(id, r.s);
    str_free(&r);
    free(name);
    free(at.path);
}

static int symbol_kind(TriDeclKind k) { return k == TRI_DECL_TYPE ? 5 : k == TRI_DECL_ATOM ? 22 : 19; }

static const char *unqualified(const char *name)
{
    const char *dot = strchr(name, '.');
    return dot && name[0] != '"' ? dot + 1 : name;
}

static void put_doc_line(Str *r, const char *doc)
{
    str_jsonn(r, doc, strcspn(doc, "\n"));
}

static void document_symbols(const J *id, const J *params)
{
    char *path = uri_to_path(json_str(json_path(params, "textDocument.uri")));
    Build *b = path ? build_for(path) : NULL;
    if (b && !b->cur) build_reload(b);
    const char *text = b ? build_text(b, path) : NULL;
    Str r = { 0 };
    str_putc(&r, '[');
    int first = 1;
    for (size_t i = 0; text && i < b->ndecls; i++) {
        TriDecl d = b->decls[i];
        if (strcmp(d.file, path)) continue;
        size_t s, le, e;
        decl_span(b, &d, text, &s, &le, &e);
        if (!first) str_putc(&r, ',');
        first = 0;
        str_puts(&r, "{\"name\":");
        str_json(&r, unqualified(d.name));
        str_printf(&r, ",\"kind\":%d", symbol_kind(d.kind));
        if (d.doc) { str_puts(&r, ",\"detail\":"); put_doc_line(&r, d.doc); }
        str_puts(&r, ",\"range\":");
        put_range(&r, text, s, e);
        str_puts(&r, ",\"selectionRange\":");
        put_range(&r, text, s, le);
        str_putc(&r, '}');
    }
    str_putc(&r, ']');
    reply(id, r.s);
    str_free(&r);
    free(path);
}

static int contains_ci(const char *hay, const char *needle)
{
    size_t n = strlen(needle);
    for (; *hay; hay++)
        if (!strncasecmp(hay, needle, n)) return 1;
    return n == 0;
}

static void workspace_symbols(const J *id, const J *params)
{
    const char *q = json_str(json_path(params, "query"));
    if (!q) q = "";
    Str r = { 0 };
    str_putc(&r, '[');
    int first = 1;
    for (size_t bi = 0; bi < nbuilds; bi++) {
        Build *b = &builds[bi];
        for (size_t i = 0; b->cur && i < b->ndecls; i++) {
            TriDecl d = b->decls[i];
            const char *text = build_text(b, d.file);
            if (!text || !contains_ci(d.name, q)) continue;
            size_t s, le, e;
            decl_span(b, &d, text, &s, &le, &e);
            if (!first) str_putc(&r, ',');
            first = 0;
            str_puts(&r, "{\"name\":");
            str_json(&r, d.name);
            str_printf(&r, ",\"kind\":%d,\"location\":", symbol_kind(d.kind));
            put_location(&r, d.file, text, s, le);
            if (d.package) { str_puts(&r, ",\"containerName\":"); str_json(&r, d.package); }
            str_putc(&r, '}');
        }
    }
    str_putc(&r, ']');
    reply(id, r.s);
    str_free(&r);
}

static const char *const attributes[][2] = {
    { "component", "@component(Name): the type is a component kind" },
    { "field", "@field(flags): flags of a component's field" },
    { "vary", "@vary(weights): weights of the alternatives a blueprint varies over" },
    { "fn", "@fn(name): a field derived by registered code" },
    { "family", "@family(name): the instance is in a pattern family" },
    { "quickcheck", "@quickcheck(paths): quick-check paths for the instance's family" },
    { "variants", "@variants(n): raise the limit on an instance's variants" },
    { "widen", "@widen: see REFERENCE.md, Attributes" },
};

static const char *const builtins[] = {
    "_", "atom", "bool", "int", "fixed", "text", "ref", "mass", "length", "time", "force", "torque",
    "heat", "temperature", "volume", "amount", "true", "false", "package", "#List", "#Cons", "#Null",
    "#Clause", "#Fact",
};

typedef struct { Str *r; int first; size_t start, end; const char *text; } Items;

static void item(Items *it, const char *label, int kind, const char *detail, const char *doc)
{
    if (!it->first) str_putc(it->r, ',');
    it->first = 0;
    str_puts(it->r, "{\"label\":");
    str_json(it->r, label);
    str_printf(it->r, ",\"kind\":%d", kind);
    if (detail) { str_puts(it->r, ",\"detail\":"); str_json(it->r, detail); }
    if (doc) { str_puts(it->r, ",\"documentation\":"); str_json(it->r, doc); }
    str_puts(it->r, ",\"textEdit\":{\"range\":");
    put_range(it->r, it->text, it->start, it->end);
    str_puts(it->r, ",\"newText\":");
    str_json(it->r, label);
    str_puts(it->r, "}}");
}

static void completion(const J *id, const J *params)
{
    At at;
    if (!at_position(params, &at)) { reply(id, "[]"); return; }
    const char *text = at.text;
    size_t start = at.off;
    while (start > 0 && (name_char(text[start - 1]) || text[start - 1] == '#' || text[start - 1] == '.')) start--;
    int attr = start > 0 && text[start - 1] == '@';
    Str r = { 0 };
    Items it = { &r, 1, start, at.off, text };
    str_puts(&r, "{\"isIncomplete\":false,\"items\":[");
    if (attr) {
        for (size_t i = 0; i < sizeof attributes / sizeof *attributes; i++)
            item(&it, attributes[i][0], 14, NULL, attributes[i][1]);
    } else {
        char *pkg = source_package(text);
        size_t pl = pkg ? strlen(pkg) : 0;
        const char *w = text + start;
        size_t wl = at.off - start;
        int qualified_word = memchr(w, '.', wl) != NULL;
        /* declared names, each written as this file would write it */
        for (size_t i = 0; i < at.b->ndecls; i++) {
            TriDecl d = at.b->decls[i];
            if (d.kind == TRI_DECL_ATOM) continue;
            char *label;
            if (!d.package) {
                if (qualified_word) continue;
                /* shadowed by the file's own package? */
                char buf[512];
                if (pkg && snprintf(buf, sizeof buf, "%s.%s", pkg, d.name) && declared(at.b, buf)) continue;
                label = xstrdup(d.name);
            } else if (pkg && !strcmp(d.package, pkg) && !qualified_word) {
                label = xstrdup(d.name + pl + 1);
            } else label = xstrdup(d.name);
            int dup = 0;
            for (size_t k = 0; !dup && k < i; k++) {
                TriDecl o = at.b->decls[k];
                dup = !strcmp(o.name, d.name);
            }
            if (!dup) item(&it, label, d.kind == TRI_DECL_TYPE ? 7 : 6, kind_word(d.kind), d.doc);
            free(label);
        }
        if (!qualified_word) {
            for (size_t i = 0; i < sizeof builtins / sizeof *builtins; i++)
                item(&it, builtins[i], !strcmp(builtins[i], "package") ? 14 : 7, "built-in", NULL);
            /* feature labels: names followed by ':' inside a structure */
            char **feats = NULL;
            size_t nf = 0, cap = 0;
            Toks t = { 0 };
            for (size_t f = 0; f < at.b->nfiles; f++) {
                const char *src = at.b->texts[f];
                lex(src, &t);
                for (size_t i = 0; i + 1 < t.n; i++)
                    if (t.v[i].k == K_NAME && t.v[i].depth > 0 && t.v[i + 1].k == K_PUNCT && src[t.v[i + 1].start] == ':' &&
                        src[t.v[i].start] != '#') {
                        if (nf == cap) feats = realloc(feats, (cap = cap ? cap * 2 : 64) * sizeof *feats);
                        feats[nf++] = xstrndup(src + t.v[i].start, t.v[i].end - t.v[i].start);
                    }
            }
            free(t.v);
            qsort(feats, nf, sizeof *feats, cmp_str);
            for (size_t i = 0; i < nf; i++)
                if (!i || strcmp(feats[i], feats[i - 1])) item(&it, feats[i], 5, "feature", NULL);
            free_strings(feats, nf);
        }
        free(pkg);
    }
    str_puts(&r, "]}");
    reply(id, r.s);
    str_free(&r);
    free(at.path);
}

/* --- the loop ------------------------------------------------------------------------------------------- */

static char *read_message(void)
{
    char line[1024];
    long len = -1;
    for (;;) {
        if (!fgets(line, sizeof line, stdin)) return NULL;
        if (!strcmp(line, "\r\n") || !strcmp(line, "\n")) break;
        if (!strncasecmp(line, "Content-Length:", 15)) len = strtol(line + 15, NULL, 10);
    }
    if (len < 0) return NULL;
    char *body = malloc((size_t) len + 1);
    if (fread(body, 1, (size_t) len, stdin) != (size_t) len) { free(body); return NULL; }
    body[len] = 0;
    return body;
}

static void open_doc(const char *path, const char *text)
{
    Doc *d = doc_find(path);
    if (!d) {
        docs = realloc(docs, (ndocs + 1) * sizeof *docs);
        d = &docs[ndocs++];
        d->path = xstrdup(path);
        d->text = NULL;
    }
    free(d->text);
    d->text = xstrdup(text ? text : "");
}

static void close_doc(const char *path)
{
    for (size_t i = 0; i < ndocs; i++)
        if (!strcmp(docs[i].path, path)) {
            free(docs[i].path);
            free(docs[i].text);
            docs[i] = docs[--ndocs];
            return;
        }
}

static const char *capabilities =
    "{\"capabilities\":{"
    "\"textDocumentSync\":{\"openClose\":true,\"change\":1,\"save\":{\"includeText\":false}},"
    "\"hoverProvider\":true,\"definitionProvider\":true,\"referencesProvider\":true,"
    "\"documentSymbolProvider\":true,\"workspaceSymbolProvider\":true,"
    "\"completionProvider\":{\"triggerCharacters\":[\"#\",\"@\",\".\"]}"
    "},\"serverInfo\":{\"name\":\"triangle\",\"version\":\"0.1.0\"}}";

int lsp_main(void)
{
    int shutdown = 0;
    for (;;) {
        char *body = read_message();
        if (!body) return shutdown ? 0 : 1;
        J *msg = json_parse(body, strlen(body));
        free(body);
        if (!msg) continue;
        const char *method = json_str(json_get(msg, "method"));
        const J *id = json_get(msg, "id");
        const J *params = json_get(msg, "params");
        if (!method) { json_free(msg); continue; }      /* a response to us: we send no requests */
        if (!strcmp(method, "initialize")) reply(id, capabilities);
        else if (!strcmp(method, "shutdown")) { shutdown = 1; reply(id, NULL); }
        else if (!strcmp(method, "exit")) { json_free(msg); return shutdown ? 0 : 1; }
        else if (!strcmp(method, "textDocument/didOpen") || !strcmp(method, "textDocument/didChange")) {
            char *path = uri_to_path(json_str(json_path(params, "textDocument.uri")));
            const char *text = json_str(json_path(params, "textDocument.text"));
            const J *changes = json_get(params, "contentChanges");
            if (changes && changes->k == J_ARR && changes->n)
                text = json_str(json_get(&changes->items[changes->n - 1], "text"));
            if (path && text) { open_doc(path, text); refresh(path); }
            free(path);
        } else if (!strcmp(method, "textDocument/didSave")) {
            char *path = uri_to_path(json_str(json_path(params, "textDocument.uri")));
            if (path) refresh(path);
            free(path);
        } else if (!strcmp(method, "textDocument/didClose")) {
            char *path = uri_to_path(json_str(json_path(params, "textDocument.uri")));
            if (path) { close_doc(path); refresh(path); }
            free(path);
        } else if (!strcmp(method, "textDocument/hover")) hover(id, params);
        else if (!strcmp(method, "textDocument/definition")) definition(id, params);
        else if (!strcmp(method, "textDocument/references")) references(id, params);
        else if (!strcmp(method, "textDocument/documentSymbol")) document_symbols(id, params);
        else if (!strcmp(method, "workspace/symbol")) workspace_symbols(id, params);
        else if (!strcmp(method, "textDocument/completion")) completion(id, params);
        else if (id) reply_error(id, -32601, "method not supported");
        json_free(msg);
    }
}
