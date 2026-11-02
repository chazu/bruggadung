#include "test.h"

#include <stdlib.h>

/* References (.a.b), paths into other declarations (wrench_19.size), and let. */

static TriContent *load1(const char *src)
{
    const char *names[] = { "r.tri" };
    const char *srcs[] = { src };
    return load(names, srcs, 1);
}

static TriContent *load1_ok(const char *src)
{
    TriContent *c = load1(src);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) dump_diags(c);
    return c;
}

static int64_t lo_of(const TriNode *n)
{
    int64_t lo = -1, hi = -1;
    if (!tri_node_interval(n, &lo, &hi)) return -999;
    return lo;
}

static const char *refs_content =
    "#Tool: { size: >=1 & <=40, label: text }\n"
    "#Nut: { bore: >=1 & <=50 }\n"
    "#Op: { instrument: #Tool, target: #Nut, steps: [...int] }\n"
    "loosen: #Op & {\n"
    "    instrument: { size: >=6 & <=20 }\n"
    "    target: { bore: .instrument.size }\n"
    "}\n"
    /* a constraint at a reference reaches the field it refers to */
    "wide: #Op & { target: { bore: .instrument.size & >=15 } }\n"
    /* arithmetic, interpolation and list items */
    "sums: #Op & {\n"
    "    instrument: { size: 12, label: \"\\(.instrument.size)mm\" }\n"
    "    target: { bore: .instrument.size + 1 }\n"
    "    steps: [3, .steps[0] + 1]\n"
    "}\n"
    /* a type's references hold in its subtypes */
    "#Matched: #Op & { target: { bore: .instrument.size } }\n"
    "#Big: #Matched & { instrument: { size: >=30 } }\n"
    "big: #Big\n"
    /* paths into other declarations copy */
    "copier: #Op & { instrument: { size: sums.instrument.size }, target: { bore: #Nut.bore & <=9 } }\n"
    "second: #Op & { target: { bore: sums.steps[1] } }\n";

void test_references(void)
{
    TriContent *c = load1_ok(refs_content);
    /* one node: what the instance's spec shows as one tag */
    CHECK_CONTAINS(printed(c, tri_spec(c, "loosen")), "size: $1 & >=6 & <=20");
    CHECK_CONTAINS(printed(c, tri_spec(c, "loosen")), "bore: $1 ");
    TriArena *a = tri_arena_new();
    for (uint64_t seed = 1; seed <= 8; seed++) {
        const TriNode *e = tri_construct(c, "loosen", seed, a);
        CHECK(e && lo_of(tri_at(c, e, "instrument.size")) == lo_of(tri_at(c, e, "target.bore")));
    }
    CHECK(lo_of(tri_at(c, tri_spec(c, "wide"), "instrument.size")) == 15);
    const TriNode *sums = tri_spec(c, "sums");
    CHECK(lo_of(tri_at(c, sums, "target.bore")) == 13);
    CHECK_STR(printed(c, tri_at(c, sums, "instrument.label")), "\"12mm\"");
    CHECK(lo_of(tri_at(c, sums, "steps.rest.first")) == 4);
    CHECK(lo_of(tri_at(c, tri_spec(c, "big"), "target.bore")) == 30);
    /* a path copies: copier's size is sums', but not one node with it */
    const TriNode *copier = tri_spec(c, "copier");
    CHECK(lo_of(tri_at(c, copier, "instrument.size")) == 12);
    CHECK_STR(printed(c, tri_at(c, copier, "target.bore")), ">=1 & <=9");
    CHECK(lo_of(tri_at(c, tri_spec(c, "second"), "target.bore")) == 4);

    /* runtime values take references, and so does matching */
    char err[256] = "";
    const TriNode *v = tri_value(c, "#Op & { instrument: { size: 7 }, target: { bore: .instrument.size } }", a, err,
                                 sizeof err);
    CHECK(v && lo_of(tri_at(c, v, "target.bore")) == 7);
    const TriNode *d = tri_value(c, "#Op & { instrument: { size: 19 } }", a, err, sizeof err);
    TriMatchResult r;
    CHECK(tri_match_instance(c, "loosen", d, &r) == TRI_UNKNOWN);
    CHECK(r.nresidual == 1);
    CHECK_STR(r.residual[0], "target.bore");
    CHECK_STR(printed(c, tri_binding(c, "loosen", ".instrument.size", d)), "19");
    char buf[1024];
    tri_explain_instance(c, "loosen", d, buf, sizeof buf);
    CHECK_CONTAINS(buf, "bindings:\n  .instrument.size = 19\n");
    d = tri_value(c, "#Op & { instrument: { size: 19 }, target: { bore: 19 } }", a, err, sizeof err);
    CHECK(tri_match_instance(c, "loosen", d, &r) == TRI_ENTAILED);
    d = tri_value(c, "#Op & { instrument: { size: 19 }, target: { bore: 20 } }", a, err, sizeof err);
    CHECK(tri_match_instance(c, "loosen", d, &r) == TRI_INCOMPATIBLE);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_reference_packages(void)
{
    const char *names[] = { "core.tri", "shop.tri" };
    const char *srcs[] = {
        "#Tool: { size: >=1 & <=40 }\nbench: #Tool & { size: 3 }\n",
        "package shop\n"
        "bench: #Tool & { size: 5 }\n"
        "a: #Tool & { size: bench.size }\n"          /* the package's own bench */
        "b: #Tool & { size: shop.bench.size }\n",
    };
    TriContent *c = load(names, srcs, 2);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) dump_diags(c);
    CHECK(lo_of(tri_at(c, tri_spec(c, "shop.a"), "size")) == 5);
    CHECK(lo_of(tri_at(c, tri_spec(c, "shop.b"), "size")) == 5);
    tri_content_free(c);
}

void test_let(void)
{
    TriContent *c = load1_ok(
        "#Tool: { size: >=1 & <=40, label: text }\n"
        "#Nut: { bore: >=1 & <=50 }\n"
        "#Op: { instrument: #Tool, target: #Nut }\n"
        /* used before it is bound, as fields may be */
        "early: #Op & { instrument: { size: base } }\n"
        "let base = 8\n"
        "twice: #Op & {\n"
        "    let doubled = base * 2\n"
        "    instrument: { size: doubled, label: \"\\(doubled) mm\" }\n"
        "}\n"
        /* a let copies: two uses of an open range are two values */
        "let range = >=10 & <=30\n"
        "apart: #Op & { instrument: { size: range }, target: { bore: range } }\n"
        /* but a reference it binds still shares */
        "same: #Op & {\n"
        "    let s = .instrument.size\n"
        "    instrument: { size: range }\n"
        "    target: { bore: s }\n"
        "}\n");
    CHECK(lo_of(tri_at(c, tri_spec(c, "early"), "instrument.size")) == 8);
    CHECK(lo_of(tri_at(c, tri_spec(c, "twice"), "instrument.size")) == 16);
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "twice"), "instrument.label")), "\"16 mm\"");
    CHECK(!strchr(printed(c, tri_spec(c, "apart")), '$'));
    CHECK_CONTAINS(printed(c, tri_spec(c, "same")), "bore: $1 ");
    TriArena *a = tri_arena_new();
    int differ = 0;
    for (uint64_t seed = 1; seed <= 12; seed++) {
        const TriNode *e1 = tri_construct(c, "apart", seed, a), *e2 = tri_construct(c, "same", seed, a);
        if (lo_of(tri_at(c, e1, "instrument.size")) != lo_of(tri_at(c, e1, "target.bore"))) differ++;
        CHECK(lo_of(tri_at(c, e2, "instrument.size")) == lo_of(tri_at(c, e2, "target.bore")));
    }
    CHECK(differ > 0);
    /* lets in runtime values */
    char err[256] = "";
    const TriNode *v = tri_value(c, "#Op & { let n = 4\n instrument: { size: n }, target: { bore: n + 1 } }", a, err,
                                 sizeof err);
    CHECK(v && lo_of(tri_at(c, v, "target.bore")) == 5);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_reference_errors(void)
{
    static const char *base =
        "#Tool: { size: >=1 & <=40, label: text }\n"
        "#Nut: { bore: >=1 & <=50 }\n"
        "#Op: { instrument: #Tool, target: #Nut }\n";
    static const struct { const char *src, *diag; } cases[] = {
        { "x: #Op & { target: { bore: .nosuch } }\n", "r.tri:4:28: error: unknown feature 'nosuch'" },
        { "x: #Op & { target: { bore: .target.size } }\n",
          "r.tri:4:28: error: the reference .target.size: target is #Nut, which has no field size" },
        { "x: #Op & { target: { bore: .instrument.label } }\n",
          "the reference .instrument.label: conflict at instrument.label: text vs >=1 & <=50" },
        { "x: #Op & { instrument: { label: .instrument } }\n",
          "r.tri:4:33: error: .instrument refers to a field that contains it (.instrument.label)" },
        { "x: #Op & { .instrument: 3 }\n", "a field's label is a plain name; a reference (.a.b) is a value" },
        { "x: #Op & { instrument = 3 }\n", "expected ':' after field label ('=' only binds a let)" },
        { "y: #Op & { instrument: { size: x.nosuch } }\nx: #Op\n", "r.tri:4:32: error: x has no field nosuch (in x.nosuch)" },
        { "y: #Op & { instrument: { size: z.size } }\n", "unknown name z.size" },
        { "x: #Op\nlet x = 4\n", "r.tri:5:5: error: let x: an instance has this name, and a let may not hide it" },
        { "let text = 4\n", "let text: a built-in type has this name" },
        { "let a = b\nlet b = a\ny: #Op & { instrument: { size: a } }\n", "let a refers to itself" },
        { "let a = 1\nlet a = 2\n", "r.tri:5:5: error: let a: the name is already bound, by the let at 4:5" },
        { "let a = 1\ny: #Op & { let a = 2 }\n", "let a: the name is already bound" },
        { "let true = 1\n", "'true' can't be a let's name" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        char src[1024];
        snprintf(src, sizeof src, "%s%s", base, cases[i].src);
        TriContent *c = load1(src);
        CHECK(!tri_content_ok(c));
        if (!has_diag(c, cases[i].diag, 1)) { fprintf(stderr, "    case %zu:\n", i); dump_diags(c); }
        CHECK(has_diag(c, cases[i].diag, 1));
        tri_content_free(c);
    }
}
