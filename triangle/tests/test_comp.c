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
          "a condition is true or false, known when content loads: not 1" },
        { "x: #Shelf & { for i, s in [1] { \"\\(i)\": s } }\n", "a computed label must be a field's name: not \"0\"" },
        { "x: #Shelf & { (1): 2 }\n", "a computed label is a string: not 1" },
        { "shelf: #Shelf\nx: #Shelf & { sizes: [for shelf in [1] { shelf }] }\n",
          "for shelf: an instance has this name, and a for's variable may not hide it" },
        { "x: #Shelf & { steel: 1 == 2 }\n", "conflict at steel: int vs false" },
        { "x: #Shelf & { steel: 2, note: .steel == \"a\" }\n", "a comparison is of values known when content loads" },
        { "x: #Shelf & { sizes: [for s in [1] for s in [2] { s }] }\n", "s: the name is already bound, by the for at 2:27" },
        { "x: #Shelf & { sizes: [for s of [1] { s }] }\n", "expected 'in' after for's variables" },
        { "x: #Shelf & { sizes: [for s in [1] if s == \"a\" { s }] }\n", "a comparison is of values known when content loads" },
        { "x: #Shelf & { sizes: [for s in [1mm] if s > 1 { 1 }] }\n", "a comparison of numbers of different kinds" },
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
        { "#T: { a: [...int], b: [...int] }\nt: #T & { a: [for x in .b { x }], b: [for x in .a { x }] }\n",
          "references that comprehensions read go around in a circle" },
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

/* Built-in functions, comparisons as values, and hidden fields. */
void test_builtins(void)
{
    TriContent *c = load1(
        "#R: { n: int, s: text, ok: bool, no: bool, l: [...int], ts: [...text], f: int, len: length, i: int, x: fixed,\n"
        "      odd: [...int], counted: int }\n"
        "let names = [\"oak\", \"Ash \", \"elm\"]\n"
        "r: #R & {\n"
        "    _base: 10\n"
        "    n: len(names) * _base + div(-7, 2) + mod(-7, 2)\n"
        "    s: strings.Join([for x in names { strings.ToUpper(strings.TrimSpace(x)) }], \"-\")\n"
        "    ok: strings.HasPrefix(\"wrench\", \"wr\") && !strings.Contains(\"oak\", \"z\") && len(\"héllo\") == 6\n"
        "    no: list.Contains([1, 2], 3) || 2 < 1\n"
        "    l: list.Range(0, 10, 3)\n"
        "    ts: list.SortStrings(strings.Split(\"c,a,b\", \",\"))\n"
        "    f: math.Round(2.5) + list.Sum([1, 2, 3]) + list.Max([4, 9, 2]) + len({ a: 1, b: 2 })\n"
        "    len: list.Sum([1mm, 2.5mm]) + math.Abs(-1mm)\n"
        "    i: quo(-7, 2) * 10 + rem(-7, 2) + strings.Index(\"spanner\", \"ann\") + len(list.Concat([[1], [2, 3]]))\n"
        "    x: 0.5\n"
        "    odd: [for v in [1, 2, 3] if mod(v, 2) == 1 { v }]\n"
        "    counted: len(.odd)\n"
        "}\n"
        /* a hidden field is a let: it is no feature, and each use copies it */
        "#P: { a: int, b: int }\n"
        "_range: >=1 & <=5\n"
        "p: #P & { a: _range, b: _range & 3 }\n");
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); return; }
    const TriNode *r = tri_spec(c, "r");
    CHECK(num(c, r, "n") == 27);
    CHECK_STR(printed(c, tri_at(c, r, "s")), "\"OAK-ASH-ELM\"");
    CHECK_STR(printed(c, tri_at(c, r, "ok")), "true");
    CHECK_STR(printed(c, tri_at(c, r, "no")), "false");
    CHECK(num(c, r, "l.rest.rest.rest.first") == 9 && tri_node_type(tri_at(c, r, "l.rest.rest.rest.rest")) == tri_type_named(c, "#Null"));
    CHECK_STR(printed(c, tri_at(c, r, "ts.first")), "\"a\"");
    CHECK_STR(printed(c, tri_at(c, r, "ts.rest.rest.first")), "\"c\"");
    CHECK(num(c, r, "f") == 20);
    CHECK(num(c, r, "counted") == 2);           /* len of a field that a comprehension makes: its items */
    CHECK_STR(printed(c, tri_at(c, r, "len")), "4.5mm");
    CHECK(num(c, r, "i") == -30 - 1 + 2 + 3);      /* quo, rem truncate; "ann" is at 2 */
    const TriNode *p = tri_spec(c, "p");
    CHECK_STR(printed(c, tri_at(c, p, "a")), ">=1 & <=5");
    CHECK(num(c, p, "b") == 3);
    CHECK(tri_type_feature_count(c, tri_type_named(c, "#P")) == 2);
    tri_content_free(c);

    static const char *base = "#R: { n: int, s: text }\n";
    static const struct { const char *src, *diag; } cases[] = {
        { "r: #R & { n: lenn([1]) }\n", "unknown function lenn: the built-ins are len, div, mod, quo, rem" },
        { "r: #R & { n: div(1) }\n", "div takes 2 arguments: div(int, int)" },
        { "r: #R & { n: div(1, 0) }\n", "div: division by zero" },
        { "r: #R & { n: len(3) }\n", "len: takes a closed list, a struct, or a string" },
        { "r: #R & { n: list.Max([]) }\n", "list.Max: of an empty list" },
        { "r: #R & { n: list.Sum([1, 1mm]) }\n", "list.Sum: takes numbers of one kind" },
        { "r: #R & { n: len(.s) }\n", ".s is not written in this declaration" },
        { "r: #R & { n: list.Range(0, 5, 0) }\n", "list.Range: takes whole numbers start, limit, and a step that isn't 0" },
        { "_x: 1\n_x: 2\n", "_x: the name is already bound" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        char src[1024];
        snprintf(src, sizeof src, "%s%s", base, cases[i].src);
        c = load1(src);
        CHECK(!tri_content_ok(c));
        if (!has_diag(c, cases[i].diag, 1)) { fprintf(stderr, "    case %zu:\n", i); dump_diags(c); }
        CHECK(has_diag(c, cases[i].diag, 1));
        tri_content_free(c);
    }
}

/* A bound by a value named: a let, a field of this declaration or another,
 * a sum of those; read when content loads, as comprehensions read data. */
void test_named_bounds(void)
{
    static const char *src =
        "let worn = 60\n"
        "let lo = 2mm\n"
        "#R: { a: int, b: length, c: int, d: int }\n"
        "#Fresh: #R & { a: <worn }\n"
        "r: #R & { a: <worn, b: >=lo & <=(lo * 3), c: >.d, d: 5 }\n"
        "s: #R & { a: >=r.d & <=worn, b: 1mm, c: 1, d: 1 }\n"
        "t: #Fresh & { a: 59, b: 1mm, c: 1, d: 1 }\n";
    TriContent *c = load1(src);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); return; }
    TriArena *a = tri_arena_new();
    const TriNode *r = tri_value(c, "r", a, NULL, 0);
    CHECK_STR(printed(c, tri_at(c, r, "a")), "<=59");
    CHECK_STR(printed(c, tri_at(c, r, "b")), ">=2mm & <=6mm");
    CHECK_STR(printed(c, tri_at(c, r, "c")), ">=6");
    const TriNode *s = tri_value(c, "s", a, NULL, 0);
    CHECK_STR(printed(c, tri_at(c, s, "a")), ">=5 & <=60");
    CHECK(tri_spec(c, "t") != NULL);
    tri_arena_free(a);
    tri_content_free(c);

    static const struct { const char *src, *diag; } cases[] = {
        { "let x = \"s\"\nr: #R & { a: <x }\n", "a bound's value must be a number written in the content, and \"s\" is not one" },
        { "r: #R & { a: <nope }\n", "and nope is not one" },
        { "r: #R & { a: <.b, b: 1mm }\n", "conflict" },
        { "r: #R & { a: < }\n", "expected a number after a bound" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        char buf[512];
        snprintf(buf, sizeof buf, "#R: { a: int, b: length }\n%s", cases[i].src);
        TriContent *e = load1(buf);
        CHECK(!tri_content_ok(e));
        if (!has_diag(e, cases[i].diag, 1)) { fprintf(stderr, "    case %zu:\n", i); dump_diags(e); }
        CHECK(has_diag(e, cases[i].diag, 1));
        tri_content_free(e);
    }
}

/* @embed, as CUE's: a field's value unified with a file's text, the file
 * beside the source. */
void test_embed(void)
{
    const char *names[] = { "tests/embed/e.tri" };
    const char *ok[] = {
        "#Level: { z: int, rows: text }\n"
        "cellar: #Level & { z: 0, rows: _ @embed(file=\"room.map\", type=text) }\n"
        "note: #Level & { z: 1, rows: text @embed(file=note.txt) }\n" };
    TriContent *c = load(names, ok, 1);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) dump_diags(c);
    char buf[64];
    CHECK(tri_text(c, tri_at(c, tri_spec(c, "cellar"), "rows"), buf, sizeof buf) == 18 &&
          !strcmp(buf, "#####\n#..+#\n#####\n"));
    CHECK(tri_text(c, tri_at(c, tri_spec(c, "note"), "rows"), buf, sizeof buf) != (size_t) -1 &&
          !strcmp(buf, "hello \"there\"\n"));
    tri_content_free(c);

    static const struct { const char *src, *diag; } cases[] = {
        { "x: #L & { r: _ @embed(file=\"../x.txt\") }\n", "@embed: ../x.txt is outside this file's directory" },
        { "x: #L & { r: _ @embed(file=/etc/hosts) }\n", "outside this file's directory" },
        { "x: #L & { r: _ @embed(file=room.map) }\n", "say what room.map is: @embed(file=room.map, type=text)" },
        { "x: #L & { r: _ @embed(file=nope.txt) }\n", "@embed: can't read nope.txt" },
        { "x: #L & { r: _ @embed(file=note.txt, type=json) }\n", "type=json is not supported" },
        { "x: #L & { r: _ @embed() }\n", "@embed needs a file" },
        { "x: #L & { r: int @embed(file=note.txt) }\n", "conflict" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        char src[512];
        snprintf(src, sizeof src, "#L: { r: _ }\n%s", cases[i].src);
        const char *srcs[] = { src };
        TriContent *e = load(names, srcs, 1);
        CHECK(!tri_content_ok(e));
        if (!has_diag(e, cases[i].diag, 1)) { fprintf(stderr, "    case %zu:\n", i); dump_diags(e); }
        CHECK(has_diag(e, cases[i].diag, 1));
        tri_content_free(e);
    }
}
