#include "test.h"

#include <stdlib.h>

/* Comprehensions: for and if in lists and structs, and computed labels. */

static TriContent *load1(const char *src)
{
    const char *names[] = { "c.tri" };
    const char *srcs[] = { src };
    return load(names, srcs, 1);
}

static int64_t num(TriContent *c, const TriNode *n, const char *path)
{
    int64_t lo = -1, hi = -1;
    const TriNode *v = tri_at(c, n, path);
    if (!v || !tri_node_interval(v, &lo, &hi) || lo != hi) return -999;
    return lo;
}

static const char *comp_content =
    "#Material: \"steel\" | \"brass\" | \"oak\"\n"
    "#Point: { input: int, output: int }\n"
    "#Curve: { points: [...#Point] }\n"
    /* a type's fields, one per member of an enum */
    "#Stock: { for m in #Material { (m): int & >=0 & <=100 }, note: text }\n"
    "#Shelf: { stock: #Stock, sizes: [...length], labels: [...text], lead: >=0mm & <=10mm }\n"
    "let table = [[30, 10], [60, 40], [100, 60]]\n"
    "warm: #Curve & { points: [for p in table { input: p[0], output: p[1] }] }\n"
    "let sizes = [13mm, 17mm, 19mm, 24mm]\n"
    "shelf: #Shelf & {\n"
    "    lead: 2mm\n"
    "    sizes: [for s in sizes if s >= 17mm && s != 19mm { s + .lead }]\n"
    "    labels: [for i, s in sizes if i < 2 { \"\\(i): \\(s)\" }]\n"
    "    stock: { for m in #Material { (m): 0 }, if !false { note: \"counted\" } }\n"
    "}\n"
    "let counts = { steel: 4, brass: 2 }\n"
    "counted: #Shelf & { stock: { for k, v in counts { \"\\(k)\": v * 10 }, oak: 1 } }\n"
    /* sources in other declarations, and nested comprehensions */
    "grid: #Curve & { points: [for i in warm.points for j in [1, 2] { input: i.input * j, output: j }] }\n"
    /* read before it is declared: the other declaration expands first */
    "mirror: #Shelf & { labels: [for s in later.labels { s }] }\n"
    "later: #Shelf & { labels: [for s in [\"a\", \"b\"] { \"\\(s)!\" }] }\n";

void test_comprehensions(void)
{
    TriContent *c = load1(comp_content);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); return; }
    const TriNode *warm = tri_spec(c, "warm");
    CHECK(num(c, warm, "points.first.input") == 30 && num(c, warm, "points.rest.rest.first.output") == 60);
    CHECK(tri_node_type(tri_at(c, warm, "points.rest.rest.rest")) == tri_type_named(c, "#Null"));
    const TriNode *shelf = tri_spec(c, "shelf");
    CHECK_STR(printed(c, tri_at(c, shelf, "sizes.first")), "19mm");
    CHECK_STR(printed(c, tri_at(c, shelf, "sizes.rest.first")), "26mm");
    CHECK(tri_node_type(tri_at(c, shelf, "sizes.rest.rest")) == tri_type_named(c, "#Null"));
    CHECK_STR(printed(c, tri_at(c, shelf, "labels.first")), "\"0: 13mm\"");
    CHECK_STR(printed(c, tri_at(c, shelf, "labels.rest.first")), "\"1: 17mm\"");
    CHECK(tri_node_type(tri_at(c, shelf, "labels.rest.rest")) == tri_type_named(c, "#Null"));
    CHECK(num(c, shelf, "stock.oak") == 0 && num(c, shelf, "stock.steel") == 0);
    CHECK_STR(printed(c, tri_at(c, shelf, "stock.note")), "\"counted\"");
    const TriNode *counted = tri_spec(c, "counted");
    CHECK(num(c, counted, "stock.steel") == 40 && num(c, counted, "stock.brass") == 20 && num(c, counted, "stock.oak") == 1);
    /* the type's comprehension made its fields */
    TriType st = tri_type_named(c, "#Stock");
    CHECK(tri_type_feature_count(c, st) == 4);
    const TriNode *grid = tri_spec(c, "grid");
    CHECK(num(c, grid, "points.first.input") == 30 && num(c, grid, "points.rest.first.input") == 60);
    CHECK(num(c, grid, "points.rest.rest.rest.rest.rest.first.input") == 200);
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "mirror"), "labels.rest.first")), "\"b!\"");
    /* runtime values */
    TriArena *a = tri_arena_new();
    char err[256] = "";
    const TriNode *v = tri_value(c, "#Curve & { points: [for x in [1, 2, 3] if x > 1 { input: x, output: x * x }] }", a,
                                 err, sizeof err);
    CHECK(v && num(c, v, "points.rest.first.output") == 9);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_comprehension_errors(void)
{
    static const char *base = "#Shelf: { sizes: [...int], note: text, steel: int }\n";
    static const struct { const char *src, *diag; } cases[] = {
        { "x: #Shelf & { sizes: [for s in .nope { s }] }\n",
          "c.tri:2:32: error: .nope is not written in this declaration, so a comprehension can't read it" },
        { "x: #Shelf & { sizes: [for s in [1, ...] { s }] }\n", "a comprehension can't go through an open list" },
        { "x: #Shelf & { sizes: [for s in [1, 2] if s { s }] }\n",
          "an if's condition is true or false, known when content loads: not 1" },
        { "x: #Shelf & { for i, s in [1] { \"\\(i)\": s } }\n", "a computed label must be a field's name: not \"0\"" },
        { "x: #Shelf & { (1): 2 }\n", "a computed label is a string: not 1" },
        { "shelf: #Shelf\nx: #Shelf & { sizes: [for shelf in [1] { shelf }] }\n",
          "for shelf: an instance has this name, and a for's variable may not hide it" },
        { "x: #Shelf & { note: 1 == 2 }\n", "a comparison (==, !=, &&, ||) belongs only in an if" },
        { "x: #Shelf & { sizes: [for s in [1] for s in [2] { s }] }\n", "s: the name is already bound, by the for at 2:27" },
        { "x: #Shelf & { sizes: [for s of [1] { s }] }\n", "expected 'in' after for's variables" },
        { "x: #Shelf & { sizes: [for s in [1] if s == \"a\" { s }] }\n", "an if compares values known when content loads" },
        { "x: #Shelf & { sizes: [for s in [1mm] if s > 1 { 1 }] }\n", "an if compares numbers of different kinds" },
        { "x: #Shelf & { sizes: [for s in [1] { s.size }] }\n", "s.size: its value has no such field or item" },
        { "x: #Shelf & { sizes: [for s in #Shelf { 1 }] }\n",
          "a comprehension goes through a list, a struct, or an enum, written in the content: not #Shelf" },
        { "x: #Shelf & { for s in [1] { nope: s } }\n", "unknown feature 'nope'" },
        { "x: #Shelf & { sizes: [for s in [1] if s > 0 ] }\n", "expected '{' after a comprehension's clauses" },
        { "let n = 1\nx: #Shelf & { sizes: [for n in [1] { n }] }\n", "n: the name is already bound, by the let at 2:5" },
        { "y: #Shelf & { steel: 2, sizes: [.steel] }\nx: #Shelf & { sizes: [for s in y.sizes { s }] }\n",
          "y.sizes holds .steel, which belongs to y: a comprehension reads values as written" },
        { "y: #Shelf & { sizes: [for s in x.sizes { s }] }\nx: #Shelf & { sizes: [for s in y.sizes { s }] }\n",
          "its comprehensions read y, whose comprehensions read it back" },
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
