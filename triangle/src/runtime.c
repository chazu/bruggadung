#include "internal.h"

#include <errno.h>
#include <inttypes.h>

/* Runtime services over loaded content: docstrings, pattern families with
 * their compiled indexes, and saving and restoring descriptions. */

/* --- docstrings --------------------------------------------------------------------- */

const char *tri_doc(TriContent *c, const char *name)
{
    Sym s = intern(c, name);
    uint32_t t = type_lookup(c, s);
    if (t != TRI_BOTTOM) {
        for (size_t k = 0; k < c->types.v[t].decls.n; k++)
            if (c->types.v[t].decls.v[k]->doc) return c->types.v[t].decls.v[k]->doc;
        return NULL;
    }
    uint64_t v;
    if (u64map_get(&c->instidx, (uint64_t) (uintptr_t) s, &v))
        for (size_t k = 0; k < c->insts.v[v - 1].decls.n; k++)
            if (c->insts.v[v - 1].decls.v[k]->doc) return c->insts.v[v - 1].decls.v[k]->doc;
    return NULL;
}

/* --- families ---------------------------------------------------------------------- */

/* Instances marked @family(name) form a family: the patterns one system
 * applies (operations, methods, rules). Their @quickcheck paths are pooled,
 * and the family's index is compiled at load. */

static char *trim(const char *s, size_t n)
{
    while (n && (*s == ' ' || *s == '\t')) { s++; n--; }
    while (n && (s[n - 1] == ' ' || s[n - 1] == '\t')) n--;
    char *r = malloc(n + 1);
    memcpy(r, s, n);
    r[n] = 0;
    return r;
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(char *const *) a, *(char *const *) b);
}

void families_build(Content *c)
{
    for (size_t i = 0; i < c->insts.n; i++) {
        InstInfo *in = &c->insts.v[i];
        for (size_t k = 0; k < in->decls.n; k++) {
            const char *fam = attr_args(in->decls.v[k]->attrs, in->decls.v[k]->nattrs, "family");
            if (!fam) continue;
            char *name = trim(fam, strlen(fam));
            Sym s = intern(c, name);
            free(name);
            Family *f = NULL;
            for (size_t q = 0; q < c->families.n && !f; q++) if (c->families.v[q].name == s) f = &c->families.v[q];
            if (!f) {
                Family nf = { 0 };
                nf.name = s;
                VEC_PUSH(c->families, nf);
                f = &c->families.v[c->families.n - 1];
            }
            bool dup = false;
            for (size_t q = 0; q < f->insts.n && !dup; q++) dup = f->insts.v[q] == (uint32_t) i;
            if (!dup) VEC_PUSH(f->insts, (uint32_t) i);
        }
    }
    /* families in name order; instances within them in name order */
    for (size_t a = 1; a < c->families.n; a++)
        for (size_t b = a; b > 0 && strcmp(c->families.v[b - 1].name, c->families.v[b].name) > 0; b--) {
            Family t = c->families.v[b]; c->families.v[b] = c->families.v[b - 1]; c->families.v[b - 1] = t;
        }
    for (size_t fi = 0; fi < c->families.n; fi++) {
        Family *f = &c->families.v[fi];
        for (size_t a = 1; a < f->insts.n; a++)
            for (size_t b = a; b > 0 && strcmp(c->insts.v[f->insts.v[b - 1]].name, c->insts.v[f->insts.v[b]].name) > 0; b--) {
                uint32_t t = f->insts.v[b]; f->insts.v[b] = f->insts.v[b - 1]; f->insts.v[b - 1] = t;
            }
        VEC(char *) paths = { 0 };
        for (size_t q = 0; q < f->insts.n; q++) {
            InstInfo *in = &c->insts.v[f->insts.v[q]];
            for (size_t k = 0; k < in->decls.n; k++) {
                const char *qc = attr_args(in->decls.v[k]->attrs, in->decls.v[k]->nattrs, "quickcheck");
                if (!qc) continue;
                const char *s = qc;
                while (*s) {
                    const char *e = strchr(s, ',');
                    size_t n = e ? (size_t) (e - s) : strlen(s);
                    char *p = trim(s, n);
                    U32Vec pv = { 0 };
                    if (!*p || !path_parse(c, p, &pv)) {
                        diag(c, true, in->decls.v[k]->loc, "%s: @quickcheck path '%s' has an unknown feature", in->name, p);
                        free(p);
                    } else {
                        bool dup = false;
                        for (size_t z = 0; z < paths.n && !dup; z++) dup = strcmp(paths.v[z], p) == 0;
                        if (dup) free(p);
                        else VEC_PUSH(paths, p);
                    }
                    VEC_FREE(pv);
                    if (!e) break;
                    s = e + 1;
                }
            }
        }
        qsort(paths.v, paths.n, sizeof(char *), cmp_str);
        f->qc = tri_qc_new(c, (const char *const *) paths.v, paths.n);
        f->index = tri_index_new(f->qc);
        for (size_t q = 0; q < f->insts.n; q++) {
            InstInfo *in = &c->insts.v[f->insts.v[q]];
            if (in->pstate != 2) continue;
            for (size_t v = 0; v < in->vars.n; v++) tri_index_add(f->index, in->vars.v[v].pattern, (void *) in->name);
        }
        for (size_t z = 0; z < paths.n; z++) free(paths.v[z]);
        VEC_FREE(paths);
    }
}

void families_free(Content *c)
{
    for (size_t i = 0; i < c->families.n; i++) {
        tri_index_free(c->families.v[i].index);
        tri_qc_free(c->families.v[i].qc);
        VEC_FREE(c->families.v[i].insts);
        u64map_free(&c->families.v[i].failcount);
        VEC_FREE(c->families.v[i].failpaths);
    }
    VEC_FREE(c->families);
}

/* --- measuring workloads ----------------------------------------------------------- */

/* While recording, every failed match of a family's instance counts its
 * failure path, so scenario runs show which paths a quick check should test. */

void tri_record_failures(TriContent *c, int on) { c->recording = on != 0; }

void family_record_failure(Content *c, uint32_t inst, const char *path)
{
    Sym p = intern(c, path[0] ? path : "(root)");
    for (size_t f = 0; f < c->families.n; f++) {
        Family *fam = &c->families.v[f];
        bool member = false;
        for (size_t k = 0; k < fam->insts.n && !member; k++) member = fam->insts.v[k] == inst;
        if (!member) continue;
        uint64_t n = 0;
        if (!u64map_get(&fam->failcount, (uint64_t) (uintptr_t) p, &n)) VEC_PUSH(fam->failpaths, p);
        u64map_put(&fam->failcount, (uint64_t) (uintptr_t) p, n + 1);
    }
}

size_t tri_family_suggest_quickcheck(TriContent *c, const char *family, size_t k, char *buf, size_t len)
{
    Sym s = intern(c, family);
    Family *fam = NULL;
    for (size_t i = 0; i < c->families.n && !fam; i++) if (c->families.v[i].name == s) fam = &c->families.v[i];
    Buf b = { 0 };
    if (fam) {
        /* the most frequent failure paths, ties by name; the root is always checked anyway */
        size_t n = fam->failpaths.n;
        Sym *order = malloc(sizeof(Sym) * (n ? n : 1));
        memcpy(order, fam->failpaths.v, sizeof(Sym) * n);
        for (size_t i = 1; i < n; i++)
            for (size_t j = i; j > 0; j--) {
                uint64_t ca = 0, cb = 0;
                u64map_get(&fam->failcount, (uint64_t) (uintptr_t) order[j - 1], &ca);
                u64map_get(&fam->failcount, (uint64_t) (uintptr_t) order[j], &cb);
                if (ca > cb || (ca == cb && strcmp(order[j - 1], order[j]) <= 0)) break;
                Sym t = order[j]; order[j] = order[j - 1]; order[j - 1] = t;
            }
        size_t taken = 0;
        buf_puts(&b, "@quickcheck(");
        for (size_t i = 0; i < n && taken < k; i++) {
            if (strcmp(order[i], "(root)") == 0) continue;
            buf_printf(&b, "%s%s", taken ? ", " : "", order[i]);
            taken++;
        }
        buf_putc(&b, ')');
        free(order);
        if (!taken) b.len = 0;
    }
    size_t n = b.len;
    if (len) snprintf(buf, len, "%s", b.s ? b.s : "");
    buf_free(&b);
    return n;
}

/* --- sizes, for knowledge stores ------------------------------------------------------ */

size_t tri_arena_bytes(const TriArena *a)
{
    size_t n = 0;
    for (const Chunk *ch = a->top; ch; ch = ch->prev) n += ch->used;
    return n;
}

static size_t count_rec(TriNode *n, U64Map *seen)
{
    uint64_t k = (uint64_t) (uintptr_t) n;
    if (u64map_get(seen, k, NULL)) return 0;
    u64map_put(seen, k, 1);
    size_t total = 1;
    if (!(n->flags & NF_DIM))
        for (uint32_t i = 0; i < n->narcs; i++) total += count_rec(n->arcs[i].val, seen);
    return total;
}

size_t tri_node_count(const TriNode *node)
{
    U64Map seen = { 0 };
    size_t n = count_rec((TriNode *) node, &seen);
    u64map_free(&seen);
    return n;
}

/* --- migration ---------------------------------------------------------------------- */

const TriNode *tri_migrate(TriContent *from, TriContent *to, const TriNode *node, TriArena *out, char *err, size_t errlen)
{
    char *text = tri_save(from, node, 0);           /* by name: IDs mean nothing in other content */
    const TriNode *r = tri_restore(to, text, out, err, errlen);
    free(text);
    return r;
}

/* --- generated component structs ------------------------------------------------------ */

static void c_ident(Buf *b, const char *s, bool upper)
{
    if (*s == '#' || *s == '"') s++;
    for (; *s; s++) {
        char ch = *s;
        if (ch == '"') continue;
        if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9'))) ch = '_';
        if (upper && ch >= 'a' && ch <= 'z') ch = (char) (ch - 32);
        buf_putc(b, ch);
    }
}

static void put_c_string(Buf *b, const char *s)
{
    buf_putc(b, '"');
    for (; *s; s++) {
        if (*s == '"' || *s == '\\') buf_putc(b, '\\');
        buf_putc(b, *s);
    }
    buf_putc(b, '"');
}

/* The enum members of an atom type: its leaf atoms, in ID order. */
static void enum_members(Content *c, uint32_t t, U32Vec *out)
{
    for (uint32_t u = 0; u < c->types.n; u++)
        if (c->types.v[u].kind == TK_ATOM && !c->types.v[u].children.n && is_subtype(c, u, t)) VEC_PUSH(*out, u);
}

size_t tri_component_header(TriContent *c, const char *prefix, char *buf, size_t len)
{
    Buf head = { 0 }, b = { 0 }, up = { 0 };
    c_ident(&up, prefix, true);
    buf_printf(&head, "/* Generated from Triangle content %016llx: do not edit. Type IDs are valid\n"
                      " * only for this content; regenerate when it changes. */\n"
                      "#ifndef %s_COMPONENTS_H\n#define %s_COMPONENTS_H\n\n"
                      "#include <stdbool.h>\n#include <stdint.h>\n\n"
                      "#define %s_CONTENT_HASH 0x%016llxULL\n\n",
               (unsigned long long) c->hash, up.s, up.s, up.s, (unsigned long long) c->hash);
    Buf enums = { 0 }, reg = { 0 }, regtab = { 0 };
    U64Map emitted = { 0 };
    bool nodes = false;
    size_t ncomp = 0;
    for (uint32_t t = 0; t < c->types.n; t++) {
        TypeInfo *ti = &c->types.v[t];
        if (!ti->component) continue;
        TriNode *e = type_expansion(c, t);
        buf_printf(&b, "/* %s, from %s */\ntypedef struct {\n", ti->component, ti->name);
        Buf sname = { 0 };
        buf_puts(&sname, prefix);
        c_ident(&sname, ti->component, false);
        buf_printf(&reg, "static const %sFieldInfo %s_fields[] = {\n", prefix, sname.s);
        size_t nfields = 0;
        for (uint32_t f = 0; f < c->feats.n; f++) {
            if (c->feats.v[f].intro != t) continue;
            TriNode *v = e ? node_arc(e, f) : NULL;
            const char *flags = field_flags(c, f);
            Buf fld = { 0 }, note = { 0 };
            c_ident(&fld, c->feats.v[f].name, false);
            const TypeInfo *vt = v ? &c->types.v[v->type] : NULL;
            const char *ctype, *vkind, *kname;
            if (v && (v->flags & NF_DIM)) {
                int dim = vt->dim;
                kname = dim_names[dim];
                if (dim == DIM_TEXT) { ctype = "const char *"; vkind = "TEXT"; buf_puts(&note, "text"); }
                else if (dim == DIM_REF) { ctype = "uint64_t"; vkind = "REF"; buf_puts(&note, "a referent"); }
                else {
                    ctype = "int64_t";
                    vkind = "QUANTITY";
                    buf_printf(&note, "%s, in quanta of ", dim_names[dim]);
                    units_format(&note, dim, 1);
                }
            } else if (v && c->tbool != TRI_BOTTOM && is_subtype(c, v->type, c->tbool)) {     /* bool, or true | false with a default */
                ctype = "bool";
                vkind = "BOOL";
                kname = "bool";
                buf_puts(&note, "bool");
            } else if (v && is_subtype(c, v->type, c->atomroot)) {
                ctype = "uint32_t";
                vkind = "TYPE";
                kname = vt->name;
                buf_printf(&note, "%s: a type ID", vt->name);
                if (!u64map_get(&emitted, v->type, NULL)) {
                    u64map_put(&emitted, v->type, 1);
                    U32Vec members = { 0 };
                    enum_members(c, v->type, &members);
                    buf_printf(&enums, "/* %s */\nenum {\n", vt->name);
                    for (size_t m = 0; m < members.n; m++) {
                        buf_printf(&enums, "    %s_", up.s);
                        if (vt->kind == TK_ANON) {
                            c_ident(&enums, ti->component, true);
                            buf_putc(&enums, '_');
                            c_ident(&enums, c->feats.v[f].name, true);
                        } else {
                            c_ident(&enums, vt->name, true);
                        }
                        buf_putc(&enums, '_');
                        c_ident(&enums, c->types.v[members.v[m]].name, true);
                        buf_printf(&enums, " = %u,\n", members.v[m]);
                    }
                    buf_puts(&enums, "};\n\n");
                    VEC_FREE(members);
                }
            } else {
                ctype = "const TriNode *";
                vkind = "NODE";
                kname = vt ? vt->name : "_";
                nodes = true;
                buf_printf(&note, "%s: a structure", kname);
            }
            buf_printf(&b, "    %-15s %s;", ctype, fld.s);
            buf_printf(&b, "    /* %s%s%s */\n", note.s ? note.s : "", flags ? "; " : "", flags ? flags : "");
            buf_printf(&reg, "    { \"%s\", offsetof(%s, %s), %s_VALUE_%s, ", c->feats.v[f].name, sname.s, fld.s, up.s, vkind);
            put_c_string(&reg, kname);
            buf_puts(&reg, ", ");
            put_c_string(&reg, flags ? flags : "");
            buf_puts(&reg, " },\n");
            nfields++;
            buf_free(&fld);
            buf_free(&note);
        }
        if (!nfields) buf_puts(&b, "    char            unused_;    /* no fields */\n");
        buf_printf(&b, "} %s;\n\n", sname.s);
        if (!nfields) buf_printf(&reg, "    { 0 },\n");
        buf_puts(&reg, "};\n\n");
        buf_printf(&regtab, "    { \"%s\", ", ti->component);
        put_c_string(&regtab, ti->name);
        buf_printf(&regtab, ", sizeof(%s), %zu, %s_fields },\n", sname.s, nfields, sname.s);
        buf_free(&sname);
        ncomp++;
    }
    if (enums.s) buf_puts(&b, enums.s);
    /* the field registry: what code needs to read and write any component generically */
    buf_printf(&b, "/* The field registry: what code needs to read and write any component\n"
                   " * generically. Define %s_COMPONENT_REGISTRY in one file to get the tables. */\n\n"
                   "#include <stddef.h>\n\n", up.s);
    buf_printf(&b, "enum { %s_VALUE_QUANTITY, %s_VALUE_TYPE, %s_VALUE_TEXT, %s_VALUE_REF, %s_VALUE_BOOL, %s_VALUE_NODE };\n\n",
               up.s, up.s, up.s, up.s, up.s, up.s);
    buf_printf(&b, "typedef struct {\n    const char *name;       /* the feature */\n    size_t      offset;\n"
                   "    int         value;      /* %s_VALUE_... */\n"
                   "    const char *kind;       /* a quantity kind, an enum's type name, or a structure's type */\n"
                   "    const char *flags;      /* from @field */\n} %sFieldInfo;\n\n", up.s, prefix);
    buf_printf(&b, "typedef struct {\n    const char *name;       /* the component */\n    const char *type;       /* its Triangle type */\n"
                   "    size_t      size;\n    size_t      nfields;\n    const %sFieldInfo *fields;\n} %sComponentInfo;\n\n",
               prefix, prefix);
    buf_printf(&b, "#define %s_COMPONENT_COUNT %zu\n\n#ifdef %s_COMPONENT_REGISTRY\n\n", up.s, ncomp, up.s);
    if (reg.s) buf_puts(&b, reg.s);
    buf_printf(&b, "static const %sComponentInfo %sComponents[%s_COMPONENT_COUNT + 1] = {\n%s    { 0 }\n};\n\n",
               prefix, prefix, up.s, regtab.s ? regtab.s : "");
    buf_printf(&b, "#endif\n\n#endif\n");
    /* structure-valued fields need TriNode declared, whether or not triangle.h is included */
    if (nodes) buf_puts(&head, "typedef struct TriNode TriNode;\n\n");
    buf_puts(&head, b.s);
    buf_free(&b);
    b = head;
    buf_free(&enums);
    buf_free(&reg);
    buf_free(&regtab);
    buf_free(&up);
    u64map_free(&emitted);
    size_t n = b.len;
    if (len) snprintf(buf, len, "%s", b.s ? b.s : "");
    buf_free(&b);
    return n;
}

size_t tri_family_count(const TriContent *c) { return c->families.n; }

const char *tri_family_name(const TriContent *c, size_t i)
{
    return i < c->families.n ? c->families.v[i].name : NULL;
}

TriIndex *tri_family_index(TriContent *c, const char *family)
{
    Sym s = intern(c, family);
    for (size_t i = 0; i < c->families.n; i++) if (c->families.v[i].name == s) return c->families.v[i].index;
    return NULL;
}

/* --- saves ------------------------------------------------------------------------- */

/* A description is saved as text:
 *
 *   tri-save 1 <content hash> names|ids
 *   (<type> [=lo hi | ="text"] [~] <feature> <node> ...)
 *
 * Shared nodes are written once and referred to later as @n, numbering nodes
 * in the order they are first written. With the same content hash, types and
 * features may be written by ID; otherwise by name, so a save can be restored
 * into changed content, failing on names that no longer exist. */

static void put_quoted(Buf *b, const char *s)
{
    buf_putc(b, '"');
    for (; *s; s++) {
        if (*s == '"' || *s == '\\') buf_putc(b, '\\');
        if (*s == '\n') { buf_puts(b, "\\n"); continue; }
        buf_putc(b, *s);
    }
    buf_putc(b, '"');
}

static void put_q(Buf *b, int64_t q)
{
    if (q == TRI_NINF) buf_puts(b, "-inf");
    else if (q == TRI_INF) buf_puts(b, "inf");
    else buf_printf(b, "%" PRId64, q);
}

static void save_rec(Content *c, Buf *b, TriNode *n, bool ids, U64Map *num, uint64_t *next)
{
    uint64_t k = (uint64_t) (uintptr_t) n, v;
    if (u64map_get(num, k, &v)) { buf_printf(b, "@%" PRIu64, v); return; }
    u64map_put(num, k, (*next)++);
    buf_putc(b, '(');
    if (ids) buf_printf(b, "%u", n->type);
    else put_quoted(b, c->types.v[n->type].name);
    if (n->flags & NF_DIM) {
        int dim = c->types.v[n->type].dim;
        if (dim == DIM_TEXT && n->lo == n->hi) {
            buf_puts(b, " =");
            put_quoted(b, (const char *) (intptr_t) n->lo);
        } else if (dim != DIM_TEXT && (n->lo != TRI_NINF || n->hi != TRI_INF)) {
            buf_puts(b, " =");
            put_q(b, n->lo);
            buf_putc(b, ' ');
            put_q(b, n->hi);
        }
    }
    if (n->flags & NF_LAZY) buf_puts(b, " ~");
    if (!(n->flags & NF_DIM))
        for (uint32_t i = 0; i < n->narcs; i++) {
            buf_putc(b, ' ');
            if (ids) buf_printf(b, ":%u", n->arcs[i].feat);
            else put_quoted(b, c->feats.v[n->arcs[i].feat].name);
            buf_putc(b, ' ');
            save_rec(c, b, n->arcs[i].val, ids, num, next);
        }
    buf_putc(b, ')');
}

char *tri_save(TriContent *c, const TriNode *node, int by_id)
{
    Buf b = { 0 };
    buf_printf(&b, "tri-save 1 %016" PRIx64 " %s\n", c->hash, by_id ? "ids" : "names");
    U64Map num = { 0 };
    uint64_t next = 0;
    save_rec(c, &b, (TriNode *) node, by_id != 0, &num, &next);
    buf_putc(&b, '\n');
    u64map_free(&num);
    return b.s;
}

typedef struct {
    Content *c;
    const char *s;
    bool ids;
    VEC(TriNode *) nodes;
    char err[256];
} Reader;

static void skip_ws(Reader *r)
{
    while (*r->s == ' ' || *r->s == '\n' || *r->s == '\t' || *r->s == '\r') r->s++;
}

static bool rerr(Reader *r, const char *fmt, const char *arg)
{
    if (!r->err[0]) snprintf(r->err, sizeof r->err, fmt, arg);
    return false;
}

static char *get_quoted(Reader *r)
{
    skip_ws(r);
    if (*r->s != '"') { rerr(r, "%s", "expected a quoted name"); return NULL; }
    r->s++;
    Buf b = { 0 };
    while (*r->s && *r->s != '"') {
        if (*r->s == '\\' && r->s[1]) {
            r->s++;
            buf_putc(&b, *r->s == 'n' ? '\n' : *r->s);
        } else {
            buf_putc(&b, *r->s);
        }
        r->s++;
    }
    if (*r->s != '"') { buf_free(&b); rerr(r, "%s", "unterminated name"); return NULL; }
    r->s++;
    return b.s ? b.s : calloc(1, 1);
}

static bool get_q(Reader *r, int64_t *q)
{
    skip_ws(r);
    if (!strncmp(r->s, "-inf", 4)) { *q = TRI_NINF; r->s += 4; return true; }
    if (!strncmp(r->s, "inf", 3)) { *q = TRI_INF; r->s += 3; return true; }
    char *end;
    errno = 0;
    long long v = strtoll(r->s, &end, 10);
    if (end == r->s || errno) return rerr(r, "%s", "expected a number");
    r->s = end;
    *q = v;
    return true;
}

static int cmp_arc_feat(const void *a, const void *b)
{
    uint32_t x = ((const Arc *) a)->feat, y = ((const Arc *) b)->feat;
    return x < y ? -1 : x > y;
}

static TriNode *read_node(Reader *r, TriArena *a)
{
    Content *c = r->c;
    skip_ws(r);
    if (*r->s == '@') {
        r->s++;
        char *end;
        unsigned long long k = strtoull(r->s, &end, 10);
        if (end == r->s || k >= r->nodes.n) { rerr(r, "%s", "bad back-reference"); return NULL; }
        r->s = end;
        return r->nodes.v[k];
    }
    if (*r->s != '(') { rerr(r, "%s", "expected '('"); return NULL; }
    r->s++;
    uint32_t t;
    if (r->ids) {
        char *end;
        unsigned long v = strtoul(r->s, &end, 10);
        if (end == r->s || v >= c->types.n) { rerr(r, "%s", "bad type id"); return NULL; }
        r->s = end;
        t = (uint32_t) v;
    } else {
        char *name = get_quoted(r);
        if (!name) return NULL;
        t = type_lookup(c, intern(c, name));
        if (t == TRI_BOTTOM) { rerr(r, "the saved type %s no longer exists", name); free(name); return NULL; }
        free(name);
    }
    TriNode *n = node_new(c, a, t);
    VEC_PUSH(r->nodes, n);
    skip_ws(r);
    if (*r->s == '=') {
        r->s++;
        skip_ws(r);
        if (!(n->flags & NF_DIM)) { rerr(r, "%s has no value", c->types.v[t].name); return NULL; }
        if (*r->s == '"') {
            char *text = get_quoted(r);
            if (!text) return NULL;
            int64_t q = (int64_t) (intptr_t) intern(c, text);
            free(text);
            n->lo = n->hi = q;
        } else if (!get_q(r, &n->lo) || !get_q(r, &n->hi)) {
            return NULL;
        }
    }
    skip_ws(r);
    if (*r->s == '~') { n->flags |= NF_LAZY; r->s++; }
    VEC(Arc) arcs = { 0 };
    for (;;) {
        skip_ws(r);
        if (*r->s == ')') { r->s++; break; }
        uint32_t f;
        if (r->ids) {
            if (*r->s != ':') { VEC_FREE(arcs); rerr(r, "%s", "expected ':feature'"); return NULL; }
            r->s++;
            char *end;
            unsigned long v = strtoul(r->s, &end, 10);
            if (end == r->s || v >= c->feats.n) { VEC_FREE(arcs); rerr(r, "%s", "bad feature id"); return NULL; }
            r->s = end;
            f = (uint32_t) v;
        } else {
            char *name = get_quoted(r);
            if (!name) { VEC_FREE(arcs); return NULL; }
            f = feat_lookup(c, intern(c, name));
            if (f == TRI_BOTTOM) { rerr(r, "the saved feature %s no longer exists", name); free(name); VEC_FREE(arcs); return NULL; }
            free(name);
        }
        TriNode *v = read_node(r, a);
        if (!v) { VEC_FREE(arcs); return NULL; }
        Arc arc = { f, v };
        VEC_PUSH(arcs, arc);
    }
    if (arcs.n) {
        if (n->flags & NF_DIM) { VEC_FREE(arcs); rerr(r, "%s has no features", c->types.v[t].name); return NULL; }
        qsort(arcs.v, arcs.n, sizeof(Arc), cmp_arc_feat);
        for (size_t k = 1; k < arcs.n; k++)
            if (arcs.v[k].feat == arcs.v[k - 1].feat) { VEC_FREE(arcs); rerr(r, "%s", "a feature is saved twice"); return NULL; }
        n->arcs = arena_alloc(a, arcs.n * sizeof(Arc));
        memcpy(n->arcs, arcs.v, arcs.n * sizeof(Arc));
        n->narcs = (uint16_t) arcs.n;
    }
    VEC_FREE(arcs);
    return n;
}

const TriNode *tri_restore(TriContent *c, const char *text, TriArena *out, char *err, size_t errlen)
{
    Reader r = { c, text, false, { 0 }, { 0 } };
    unsigned version = 0;
    uint64_t hash = 0;
    char enc[8] = { 0 };
    int used = 0;
    const TriNode *result = NULL;
    if (sscanf(text, "tri-save %u %" SCNx64 " %7s%n", &version, &hash, enc, &used) != 3 || version != 1 ||
        (strcmp(enc, "ids") && strcmp(enc, "names"))) {
        rerr(&r, "%s", "not a version 1 save");
    } else if (!strcmp(enc, "ids") && hash != c->hash) {
        rerr(&r, "%s", "saved by ID for different content; save by name to migrate");
    } else {
        r.ids = !strcmp(enc, "ids");
        r.s = text + used;
        TriMark m = tri_arena_mark(c->scratch);
        bool same = hash == c->hash;
        /* with the same content the structure is trusted; otherwise it is
         * rebuilt in scratch and every node made to satisfy its type again */
        TriNode *n = read_node(&r, same ? out : c->scratch);
        skip_ws(&r);
        if (n && *r.s) rerr(&r, "%s", "unexpected text after the saved structure");
        else if (n && same) result = n;
        else if (n) {
            uint32_t saved = op_begin(c);
            c->failed = false;
            c->depth = 0;
            bool ok = true;
            for (size_t k = 0; k < r.nodes.n && ok; k++) {
                TriNode *e = type_instance(c, r.nodes.v[k]->type, c->scratch);
                ok = e && unify1(c, r.nodes.v[k], e);
            }
            if (ok) {
                bool closed;
                result = copy_out(c, out, n, &closed);
                if (!closed) { result = NULL; rerr(&r, "%s", "a saved feature is not appropriate in the current content"); }
            } else {
                Buf b = { 0 };
                buf_printf(&b, "the saved structure no longer fits: %s vs %s", fail_info(c)->left,
                           fail_info(c)->right[0] ? fail_info(c)->right : "(missing)");
                rerr(&r, "%s", b.s);
                buf_free(&b);
            }
            op_end(c, saved);
        }
        tri_arena_release(c->scratch, m);
    }
    VEC_FREE(r.nodes);
    if (err && errlen) snprintf(err, errlen, "%s", r.err);
    return result;
}
