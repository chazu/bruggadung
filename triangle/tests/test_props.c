#include "test.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/* Randomised tests: random hierarchies and random descriptions, checked
 * against properties that unification, subsumption, matching, generalisation,
 * the quick check, saves, and construction must have. Seeds are fixed, so a
 * failure reproduces; the seed is printed with it. */

static uint64_t rng;

static uint64_t rnd(void)
{
    uint64_t z = (rng += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

static int pick(int n) { return (int) (rnd() % (uint64_t) n); }

/* TRI_PROPS_SCALE=n runs n times as many cases, for hunting. */
static uint64_t scale(void)
{
    const char *s = getenv("TRI_PROPS_SCALE");
    long v = s ? strtol(s, NULL, 10) : 1;
    return v > 0 ? (uint64_t) v : 1;
}

/* --- random content ----------------------------------------------------------- */

enum { K_INT, K_ENUM, K_TYPE, K_TOP, K_TEXT, K_DISJ, K_DEFAULT, K_LIST, NKINDS };

typedef struct { int kind, lo, hi, type, type2; char name[8]; } Feat;

#define MAXT 12
#define MAXF 24

typedef struct {
    int ntypes, nfeats;
    int parents[MAXT][2], nparents[MAXT];
    int own[MAXT][3], nown[MAXT];          /* features each type introduces */
    Feat feats[MAXF];
    char src[8192];
} Gen;

static bool below(const Gen *g, int a, int b)       /* a ⊑ b in the declared hierarchy */
{
    if (a == b) return true;
    for (int i = 0; i < g->nparents[a]; i++) if (below(g, g->parents[a][i], b)) return true;
    return false;
}

static bool has_feat(const Gen *g, int t, int f)
{
    for (int i = 0; i < g->nown[t]; i++) if (g->own[t][i] == f) return true;
    for (int i = 0; i < g->nparents[t]; i++) if (has_feat(g, g->parents[t][i], f)) return true;
    return false;
}

static const char *atoms[] = { "\"a\"", "\"b\"", "\"c\"", "\"d\"" };

static void gen_content(Gen *g)
{
    memset(g, 0, sizeof *g);
    g->ntypes = 3 + pick(MAXT - 3);
    char *s = g->src;
    size_t left = sizeof g->src;
    int w;
    for (int t = 0; t < g->ntypes; t++) {
        g->nparents[t] = t == 0 ? 0 : pick(3);
        for (int k = 0; k < g->nparents[t]; k++) {
            int p = pick(t);
            bool dup = false;
            for (int q = 0; q < k; q++) dup |= g->parents[t][q] == p;
            if (dup) { g->nparents[t] = k; break; }
            g->parents[t][k] = p;
        }
        g->nown[t] = pick(3);
        for (int k = 0; k < g->nown[t] && g->nfeats < MAXF; k++) {
            Feat *f = &g->feats[g->nfeats];
            snprintf(f->name, sizeof f->name, "f%d", g->nfeats);
            f->kind = pick(NKINDS);
            f->lo = pick(5);
            f->hi = f->lo + pick(6);
            f->type = pick(g->ntypes);              /* may be the type itself, or a later one */
            f->type2 = pick(g->ntypes);
            if (f->kind == K_DISJ && f->type2 == f->type) f->kind = K_TYPE;
            g->own[t][k] = g->nfeats++;
        }
        w = snprintf(s, left, "#T%d: ", t);
        s += w; left -= (size_t) w;
        for (int k = 0; k < g->nparents[t]; k++) {
            w = snprintf(s, left, "#T%d & ", g->parents[t][k]);
            s += w; left -= (size_t) w;
        }
        w = snprintf(s, left, "{");
        s += w; left -= (size_t) w;
        for (int k = 0; k < g->nown[t]; k++) {
            Feat *f = &g->feats[g->own[t][k]];
            switch (f->kind) {
            case K_INT: w = snprintf(s, left, " %s: int & >=%d & <=%d", f->name, f->lo, f->hi); break;
            case K_ENUM: w = snprintf(s, left, " %s: %s | %s%s", f->name, atoms[f->lo % 4], atoms[(f->lo + 1) % 4],
                                      f->hi > f->lo + 2 ? " | \"d\"" : ""); break;
            case K_TYPE: w = snprintf(s, left, " %s: #T%d", f->name, f->type); break;
            case K_TEXT: w = snprintf(s, left, " %s: text", f->name); break;
            case K_DISJ: w = snprintf(s, left, " %s: #T%d | #T%d", f->name, f->type, f->type2); break;
            case K_DEFAULT: w = snprintf(s, left, " %s: *%d | int & >=%d & <=%d", f->name, f->lo + pick(f->hi - f->lo + 1), f->lo, f->hi); break;
            case K_LIST: w = snprintf(s, left, " %s: [...#T%d]", f->name, f->type); break;
            default: w = snprintf(s, left, " %s: _", f->name); break;
            }
            s += w; left -= (size_t) w;
            if (k + 1 < g->nown[t]) { *s++ = ','; left--; }
        }
        w = snprintf(s, left, " }\n");
        s += w; left -= (size_t) w;
    }
}

/* A random description of type t (or a subtype), depth-limited. */
static void gen_value(const Gen *g, int t, int depth, char *out, size_t len)
{
    /* sometimes a subtype */
    for (int tries = 0; tries < 3; tries++) {
        int u = pick(g->ntypes);
        if (below(g, u, t) && pick(2)) { t = u; break; }
    }
    int n = snprintf(out, len, "#T%d", t);
    if (depth <= 0 || pick(4) == 0) return;
    int first = 1;
    bool tagged = false;
    for (int f = 0; f < g->nfeats && (size_t) n < len - 64; f++) {
        if (!has_feat(g, t, f) || pick(2)) continue;
        n += snprintf(out + n, len - (size_t) n, "%s%s: ", first ? " & { " : ", ", g->feats[f].name);
        first = 0;
        const Feat *ft = &g->feats[f];
        char sub[2048];
        switch (ft->kind) {
        case K_DISJ:
            gen_value(g, pick(2) ? ft->type : ft->type2, depth - 1, sub, sizeof sub);
            n += snprintf(out + n, len - (size_t) n, "%s", sub);
            break;
        case K_LIST: {
            int items = pick(3);
            n += snprintf(out + n, len - (size_t) n, "[");
            for (int i = 0; i < items && (size_t) n < len - 600; i++) {
                gen_value(g, ft->type, depth - 1, sub, 512);
                n += snprintf(out + n, len - (size_t) n, "%s%s", i ? ", " : "", sub);
            }
            n += snprintf(out + n, len - (size_t) n, "%s]", pick(3) ? "" : ", ...");
            break;
        }
        case K_DEFAULT:
        case K_INT:
            if (!tagged && pick(5) == 0) { n += snprintf(out + n, len - (size_t) n, "$x"); tagged = true; break; }
            if (pick(3)) n += snprintf(out + n, len - (size_t) n, "%d", ft->lo - 1 + pick(ft->hi - ft->lo + 3));
            else n += snprintf(out + n, len - (size_t) n, ">=%d", ft->lo + pick(4));
            break;
        case K_ENUM:
            n += snprintf(out + n, len - (size_t) n, "%s", atoms[pick(4)]);
            break;
        case K_TYPE:
            gen_value(g, ft->type, depth - 1, sub, sizeof sub);
            n += snprintf(out + n, len - (size_t) n, "%s", sub);
            break;
        case K_TEXT:
            n += snprintf(out + n, len - (size_t) n, "\"%s\"", pick(2) ? "x" : "y");
            break;
        default:
            if (tagged && pick(2)) n += snprintf(out + n, len - (size_t) n, "$x");
            else n += snprintf(out + n, len - (size_t) n, "%d", pick(3));
            break;
        }
    }
    if (!first) snprintf(out + n, len - (size_t) n, " }");
}

/* --- the properties ------------------------------------------------------------- */

static bool equivalent(TriContent *c, const TriNode *a, const TriNode *b)
{
    int f, bk;
    tri_subsumes(c, a, b, &f, &bk);
    return f && bk;
}

static bool subsumes(TriContent *c, const TriNode *a, const TriNode *b)
{
    int f, bk;
    tri_subsumes(c, a, b, &f, &bk);
    return f;
}

#define PCHECK(cond, what) do { \
    if (!(cond)) { \
        if (reported++ < 6) fprintf(stderr, "  property failed (seed %llu): %s\n    content:\n%s    a = %s\n    b = %s\n", \
                                    (unsigned long long) seed, what, g.src, sa, sb); \
        test_failures++; \
    } \
} while (0)

void test_properties(void)
{
    static Gen g;
    int reported = 0;
    size_t contents = 0, pairs = 0, unified = 0;
    for (uint64_t seed = 1; seed <= 60 * scale(); seed++) {
        rng = seed * 7919;
        gen_content(&g);
        const char *names[] = { "gen.tri" };
        const char *srcs[] = { g.src };
        TriContent *c = load(names, srcs, 1);
        if (!tri_content_ok(c)) { tri_content_free(c); continue; }
        contents++;
        TriArena *a = tri_arena_new();
        static char sa[4096], sb[4096], sc[4096];
        for (int k = 0; k < 40; k++) {
            int t = pick(g.ntypes);
            gen_value(&g, t, 3, sa, sizeof sa);
            gen_value(&g, pick(2) ? t : pick(g.ntypes), 3, sb, sizeof sb);
            gen_value(&g, t, 2, sc, sizeof sc);
            const TriNode *x = tri_value(c, sa, a, NULL, 0);
            const TriNode *y = tri_value(c, sb, a, NULL, 0);
            const TriNode *z = tri_value(c, sc, a, NULL, 0);
            if (!x || !y || !z) continue;
            pairs++;
            TriFailure f;
            /* idempotence */
            const TriNode *xx = tri_unify(c, x, x, a, &f);
            PCHECK(xx && equivalent(c, xx, x), "unify(a, a) == a");
            /* commutativity, and the result is below both */
            const TriNode *xy = tri_unify(c, x, y, a, &f);
            const TriNode *yx = tri_unify(c, y, x, a, &f);
            PCHECK((xy == NULL) == (yx == NULL), "unify(a, b) succeeds iff unify(b, a) does");
            if (xy && yx) {
                unified++;
                PCHECK(equivalent(c, xy, yx), "unify(a, b) == unify(b, a)");
                PCHECK(subsumes(c, x, xy) && subsumes(c, y, xy), "a and b subsume unify(a, b)");
                /* unifying again with either input changes nothing */
                const TriNode *again = tri_unify(c, xy, x, a, &f);
                PCHECK(again && equivalent(c, again, xy), "unify(unify(a, b), a) == unify(a, b)");
            }
            /* subsumption agrees with unification */
            if (subsumes(c, x, y)) {
                PCHECK(xy != NULL, "a subsumes b, so they unify");
                if (xy) PCHECK(equivalent(c, xy, y), "a subsumes b, so unify(a, b) == b");
            }
            /* associativity */
            const TriNode *yz = tri_unify(c, y, z, a, &f);
            const TriNode *l = xy ? tri_unify(c, xy, z, a, &f) : NULL;
            const TriNode *r = yz ? tri_unify(c, x, yz, a, &f) : NULL;
            PCHECK((l == NULL) == (r == NULL), "(a & b) & c succeeds iff a & (b & c) does");
            if (l && r) PCHECK(equivalent(c, l, r), "(a & b) & c == a & (b & c)");
            /* matching is subsumption, then compatibility */
            TriMatchResult m;
            TriMatch mr = tri_match(c, x, y, &m);
            if (subsumes(c, x, y)) PCHECK(mr == TRI_ENTAILED, "match is entailed exactly when the pattern subsumes");
            else if (!xy) PCHECK(mr == TRI_INCOMPATIBLE, "match is incompatible exactly when unification fails");
            else PCHECK(mr == TRI_UNKNOWN && m.nresidual > 0, "otherwise unknown, with residuals");
            /* generalisation is above both */
            const TriNode *gl = tri_lgg(c, x, y, a);
            PCHECK(subsumes(c, gl, x) && subsumes(c, gl, y), "lgg(a, b) subsumes a and b");
            /* the quick check never rejects a unification that succeeds */
            const char *qpaths[] = { "f0", "f1", "f2", "f3", "f4", "f5" };
            TriQuickCheck *qc = tri_qc_new(c, qpaths, 6);
            TriType vx[8], vy[8];
            tri_qc_vector(qc, x, vx);
            tri_qc_vector(qc, y, vy);
            if (xy) PCHECK(tri_qc_compatible(qc, vx, vy), "the quick check passes every unifiable pair");
            tri_qc_free(qc);
            /* saves round-trip */
            for (int by_id = 0; by_id <= 1; by_id++) {
                char *text = tri_save(c, x, by_id);
                char err[256];
                const TriNode *back = tri_restore(c, text, a, err, sizeof err);
                PCHECK(back && equivalent(c, back, x), by_id ? "restore(save by ID) == a" : "restore(save by name) == a");
                free(text);
            }
        }
        tri_arena_free(a);
        tri_content_free(c);
    }
    CHECK(contents >= 30 && pairs >= 600 && unified >= 100);
    if (contents < 30 || pairs < 600 || unified < 100)
        fprintf(stderr, "  too few cases: %zu contents, %zu pairs, %zu unified\n", contents, pairs, unified);
}

/* Order independence: the same declarations in any file split and order give
 * the same content hash. */
void test_properties_order(void)
{
    static Gen g;
    for (uint64_t seed = 1; seed <= 25 * scale(); seed++) {
        rng = seed * 104729;
        gen_content(&g);
        /* one declaration per line; deal them into three files at random */
        char *lines[64];
        int nl = 0;
        char *copy = strdup(g.src);
        for (char *l = strtok(copy, "\n"); l && nl < 64; l = strtok(NULL, "\n")) lines[nl++] = l;
        uint64_t h0 = 0;
        for (int trial = 0; trial < 4; trial++) {
            static char files[3][8192];
            for (int f = 0; f < 3; f++) files[f][0] = 0;
            int order[64];
            for (int i = 0; i < nl; i++) order[i] = i;
            for (int i = nl - 1; i > 0; i--) { int j = pick(i + 1), t = order[i]; order[i] = order[j]; order[j] = t; }
            for (int i = 0; i < nl; i++) {
                char *dst = files[pick(3)];
                strcat(dst, lines[order[i]]);
                strcat(dst, "\n");
            }
            const char *names[] = { "x.tri", "y.tri", "z.tri" };
            const char *srcs[] = { files[0], files[1], files[2] };
            TriContent *c = load(names, srcs, 3);
            if (!tri_content_ok(c)) { tri_content_free(c); break; }
            if (trial == 0) h0 = tri_content_hash(c);
            else if (tri_content_hash(c) != h0) {
                fprintf(stderr, "  order changed the content (seed %llu):\n%s", (unsigned long long) seed, g.src);
                if (getenv("TRI_PROPS_DUMP"))
                    for (int f = 0; f < 3; f++) fprintf(stderr, "  --- file %d\n%s", f, files[f]);
                test_failures++;
            }
            tri_content_free(c);
        }
        free(copy);
    }
}

/* Every number exact, every enum a leaf, every disjunction resolved. */
static bool concrete(TriContent *c, const TriNode *n)
{
    int64_t lo, hi;
    if (tri_node_interval(n, &lo, &hi) || strcmp(tri_type_name(c, tri_node_type(n)), "length") == 0 ||
        strcmp(tri_type_name(c, tri_node_type(n)), "int") == 0)
        return lo == hi && lo != INT64_MIN;
    const char *t = tri_type_name(c, tri_node_type(n));
    if (t[0] == '(' && !strchr(t, '/')) return false;      /* an anonymous enum or disjunction */
    static const char *const feats[] = { "colour", "size", "shape", "shade", "count", "tone", "round", "r", "sides" };
    for (size_t i = 0; i < sizeof feats / sizeof feats[0]; i++) {
        const TriNode *v = tri_at(c, n, feats[i]);
        if (v && !concrete(c, v)) return false;
    }
    return strcmp(t, "#Colour") != 0;
}

/* Blueprints: construction makes everything concrete, stays below the spec,
 * and is a function of the seed. */
void test_properties_construct(void)
{
    static const char *src =
        "#Colour: \"red\" | \"green\" | \"blue\"\n"
        "#Shade: { tone: \"light\" | \"dark\" }\n"
        "#Part: { @component(Part)\n"
        "    colour: #Colour @field(content) @vary(1, 2, 3)\n"
        "    size: length & >=1mm & <=20mm @field(content)\n"
        "    shape: { round: true, r: int & >=1 & <=3 } | { round: false, sides: int & >=3 & <=8 } @field(content)\n"
        "    shade: #Shade @field(content)\n"
        "    count: *1 | int & >=1 & <=4 @field(content)\n"
        "}\n"
        "plain: #Part\n"
        "red: #Part & { colour: \"red\" }\n"
        "pick: #Part & ({ size: 2mm } | { size: 4mm, colour: \"blue\" } | { size: 6mm, count: 3 })\n";
    const char *names[] = { "parts.tri" };
    const char *srcs[] = { src };
    TriContent *c = load(names, srcs, 1);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); return; }
    const char *insts[] = { "plain", "red", "pick" };
    TriArena *a = tri_arena_new();
    for (int i = 0; i < 3; i++) {
        const TriNode *spec = tri_spec(c, insts[i]);
        for (uint64_t seed = 1; seed <= 60; seed++) {
            const TriNode *w = tri_construct(c, insts[i], seed, a);
            CHECK(w != NULL);
            if (!w) continue;
            char once[2048];
            snprintf(once, sizeof once, "%s", printed(c, w));
            CHECK_STR(printed(c, tri_construct(c, insts[i], seed, a)), once);
            /* below the spec, unless the spec generalises variants (then below one of them) */
            if (tri_pattern_variant_count(c, insts[i]) == 1) CHECK(subsumes(c, spec, w));
            else CHECK(subsumes(c, tri_pattern(c, insts[i]), w));
            /* nothing open: every number exact, every enum a leaf */
            CHECK(concrete(c, w));
            if (!concrete(c, w)) fprintf(stderr, "    %s\n", once);
        }
    }
    tri_arena_free(a);
    tri_content_free(c);
}

/* Mutated sources never crash the loader (run under the sanitizers). */
void test_fuzz_sources(void)
{
    static const char *seeds[] = {
        ("#Material: \"steel\" | \"brass\"\n#Tool: { @component(Tool)\n size: length @field(content)\n"
         " wear: *0 | >=0 & <=1000 }\nw: #Tool & { size: 19mm, material: _ }\n"),
        "#A: { x: [...#A], y: { p: 1 } | { q: 2 } }\na: #A & { x: [{ y: { p: 1 } }, ...] }\n",
        "#P: { l: int, r: int }\np: #P & { l: $s & >=1 & <=9, r: $s } @family(f) @quickcheck(l)\n",
        "// doc\n#T: #P & { l: *3 | 4 }\n#P: { l: int }\nt: #T @variants(2)\n\"dark\": \"grey\" | \"black\"\n",
    };
    static char buf[4096];
    static const char tokens[] = "{}[]()|&*:,$#@\"._>=<1a\n ";
    size_t crashes_avoided = 0;
    rng = 4242;
    for (uint64_t round = 0; round < 1500 * scale(); round++) {
        const char *s = seeds[pick(4)];
        size_t n = strlen(s);
        memcpy(buf, s, n + 1);
        int edits = 1 + pick(4);
        for (int e = 0; e < edits; e++) {
            size_t pos = (size_t) pick((int) n + 1);
            int op = pick(3);
            if (op == 0 && n) {                         /* delete */
                memmove(buf + pos, buf + pos + 1, n - pos);
                n--;
            } else if (op == 1 && n < sizeof buf - 2) { /* insert */
                memmove(buf + pos + 1, buf + pos, n - pos + 1);
                buf[pos] = tokens[pick((int) sizeof tokens - 1)];
                n++;
            } else if (n && pos < n) {                  /* replace */
                buf[pos] = tokens[pick((int) sizeof tokens - 1)];
            }
        }
        const char *names[] = { "fuzz.tri" };
        const char *srcs[] = { buf };
        TriContent *c = load(names, srcs, 1);
        if (tri_content_ok(c)) {
            /* exercise what loaded */
            TriArena *a = tri_arena_new();
            for (size_t i = 0; i < tri_instance_count(c); i++) {
                const char *in = tri_instance_name(c, i);
                tri_construct(c, in, 1, a);
                char out[512];
                tri_inspect(c, in, out, sizeof out);
                const TriNode *p = tri_pattern(c, in);
                if (p) { char *t = tri_save(c, p, 0); tri_restore(c, t, a, out, sizeof out); free(t); }
            }
            tri_arena_free(a);
        }
        crashes_avoided++;
        tri_content_free(c);
    }
    CHECK(crashes_avoided == 1500 * scale());
}


/* Interval arithmetic is sound: for concrete arguments it is exact (division
 * to the enclosing whole numbers), and for intervals it contains the result
 * for every choice of concrete arguments inside them. */
static int64_t floor_div(int64_t a, int64_t b) { int64_t q = a / b; if ((a % b) && ((a < 0) != (b < 0))) q--; return q; }

void test_properties_arithmetic(void)
{
    static const char *src =
        "#Q: { a: $a & int, b: $b & int, s: $a + $b, d: $a - $b, p: $a * $b, q: $a / $b & int }\n";
    const char *names[] = { "q.tri" };
    const char *srcs[] = { src };
    TriContent *c = load(names, srcs, 1);
    CHECK(tri_content_ok(c));
    TriArena *a = tri_arena_new();
    rng = 777;
    char expr[256];
    for (uint64_t it = 0; it < 400 * scale(); it++) {
        int64_t alo = pick(41) - 20, ahi = alo + pick(6), blo = pick(41) - 20, bhi = blo + pick(6);
        snprintf(expr, sizeof expr, "#Q & { a: >=%lld & <=%lld, b: >=%lld & <=%lld }",
                 (long long) alo, (long long) ahi, (long long) blo, (long long) bhi);
        const TriNode *v = tri_value(c, expr, a, NULL, 0);
        CHECK(v != NULL);
        if (!v) continue;
        int64_t r[4][2];
        const char *fs[4] = { "s", "d", "p", "q" };
        for (int k = 0; k < 4; k++) tri_node_interval(tri_at(c, v, fs[k]), &r[k][0], &r[k][1]);
        for (int64_t x = alo; x <= ahi; x++)
            for (int64_t y = blo; y <= bhi; y++) {
                CHECK(r[0][0] <= x + y && x + y <= r[0][1]);
                CHECK(r[1][0] <= x - y && x - y <= r[1][1]);
                CHECK(r[2][0] <= x * y && x * y <= r[2][1]);
                if (y != 0 && !(blo <= 0 && bhi >= 0)) {
                    CHECK(r[3][0] <= floor_div(x, y) && -floor_div(-x, y) <= r[3][1]);
                }
            }
        /* concrete arguments: exact */
        if (alo == ahi && blo == bhi && blo != 0) {
            CHECK(r[0][0] == r[0][1] && r[1][0] == r[1][1] && r[2][0] == r[2][1]);
            CHECK(r[3][0] == floor_div(alo, blo) && r[3][1] == -floor_div(-alo, blo));
        }
    }
    tri_arena_free(a);
    tri_content_free(c);
}

/* Every solution a proof finds is an instance of the query. */
void test_properties_clauses(void)
{
    static const char *src =
        "#N: \"0\" | \"1\" | \"2\" | \"3\" | \"4\" | \"5\"\n"
        "#Step: { from: #N, to: #N }\n#Path: #Step\n";
    rng = 4711;
    for (uint64_t seed = 0; seed < 20 * scale(); seed++) {
        static char text[4096];
        int n = snprintf(text, sizeof text, "%s"
            "p1: #Clause & { head: #Path & { from: $x, to: $y }, body: [#Step & { from: $x, to: $y }] }\n"
            "p2: #Clause & { head: #Path & { from: $x, to: $z }, body: [#Step & { from: $x, to: $y }, #Path & { from: $y, to: $z }] }\n",
            src);
        int edges = 3 + pick(6);
        for (int e = 0; e < edges; e++)
            n += snprintf(text + n, sizeof text - (size_t) n, "s%d: #Fact & { head: #Step & { from: \"%d\", to: \"%d\" } }\n",
                          e, pick(6), pick(6));
        const char *names[] = { "g.tri" };
        const char *srcs[] = { text };
        TriContent *c = load(names, srcs, 1);
        CHECK(tri_content_ok(c));
        TriArena *a = tri_arena_new();
        char q[64];
        snprintf(q, sizeof q, "#Path & { from: \"%d\" }", pick(6));
        const TriNode *query = tri_value(c, q, a, NULL, 0);
        const TriNode *sol[64];
        int trunc;
        size_t m = tri_solve(c, query, 8, sol, 64, a, &trunc);
        for (size_t i = 0; i < m; i++) {
            int fw, bw;
            tri_subsumes(c, query, sol[i], &fw, &bw);
            CHECK(fw);
            /* and its endpoints are connected by facts: the last step of a proof is a fact */
            CHECK(tri_at(c, sol[i], "to") != NULL);
        }
        tri_arena_free(a);
        tri_content_free(c);
    }
}
