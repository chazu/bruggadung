#include "test.h"

#include <stdlib.h>

/* Strings: escapes, raw strings, regex constraints, and interpolation. */

static TriContent *load1(const char *src)
{
    const char *names[] = { "s.tri" };
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

static const char *text_of(TriContent *c, const TriNode *n)
{
    static char buf[256];
    if (tri_text(c, n, buf, sizeof buf) == (size_t) -1) return "(not text)";
    return buf;
}

void test_string_escapes(void)
{
    TriContent *c = load1_ok(
        "#Note: { says: text }\n"
        "n1: #Note & { says: \"she said \\\"no\\\"\\n\\tthen \\\\left\\/\" }\n"
        "n2: #Note & { says: \"caf\\u00e9 \\U0001F600\" }\n"
        "n3: #Note & { says: \"\\a\\b\\f\\v\\r\" }\n");
    const TriNode *s1 = tri_at(c, tri_spec(c, "n1"), "says");
    CHECK_STR(text_of(c, s1), "she said \"no\"\n\tthen \\left/");
    /* printed in the canonical spelling, which reads back as the same value */
    CHECK_STR(printed(c, s1), "\"she said \\\"no\\\"\\n\\tthen \\\\left/\"");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "n2"), "says")), "caf\xc3\xa9 \xf0\x9f\x98\x80");
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "n2"), "says")), "\"caf\xc3\xa9 \xf0\x9f\x98\x80\"");
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "n3"), "says")), "\"\\u0007\\u0008\\u000c\\u000b\\r\"");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "n3"), "says")), "\a\b\f\v\r");

    TriArena *a = tri_arena_new();
    char err[256] = "";
    const TriNode *v = tri_value(c, printed(c, tri_spec(c, "n1")), a, err, sizeof err);
    CHECK(v != NULL);
    CHECK_STR(text_of(c, tri_at(c, v, "says")), "she said \"no\"\n\tthen \\left/");
    /* saves keep the bytes, by name and by ID */
    for (int by_id = 0; by_id <= 1; by_id++) {
        char *saved = tri_save(c, v, by_id);
        const TriNode *back = tri_restore(c, saved, a, err, sizeof err);
        CHECK(back != NULL);
        CHECK_STR(text_of(c, tri_at(c, back, "says")), "she said \"no\"\n\tthen \\left/");
        free(saved);
    }
    /* runtime values take escapes too */
    v = tri_value(c, "#Note & { says: \"a\\tb\" }", a, err, sizeof err);
    CHECK_STR(text_of(c, tri_at(c, v, "says")), "a\tb");
    CHECK(tri_text(c, tri_spec(c, "n1"), NULL, 0) == (size_t) -1);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_string_spellings_are_one_value(void)
{
    /* one atom, however it is spelled */
    TriContent *c = load1_ok(
        "#Mark: \"a\\\"b\" | \"plain\"\n"
        "#Tag: { mark: #Mark, note: text }\n"
        "t1: #Tag & { mark: \"a\\u0022b\", note: #\"x\\dy\"# }\n"
        "t2: #Tag & { mark: \"a\\\"b\", note: \"x\\\\dy\" }\n");
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "t1"), "mark")), "\"a\\\"b\"");
    CHECK(tri_node_type(tri_at(c, tri_spec(c, "t1"), "mark")) == tri_node_type(tri_at(c, tri_spec(c, "t2"), "mark")));
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "t1"), "mark")), "a\"b");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "t1"), "note")), "x\\dy");
    CHECK_STR(printed(c, tri_spec(c, "t1")), printed(c, tri_spec(c, "t2")));
    TriArena *a = tri_arena_new();
    char err[256] = "";
    const TriNode *v = tri_value(c, "#Tag & { note: \"x\\\\dy\" }", a, err, sizeof err);
    TriMatchResult r;
    CHECK(tri_match(c, tri_pattern(c, "t1"), tri_unify(c, v, tri_value(c, "#Tag & { mark: \"a\\\"b\" }", a, err, sizeof err), a, NULL), &r) == TRI_ENTAILED);
    tri_arena_free(a);
    tri_content_free(c);

    /* raw strings: only \# escapes, and "# closes; more #s allow "# inside */
    c = load1_ok(
        "#Note: { says: text }\n"
        "r1: #Note & { says: #\"a\\nb\\#nc\"# }\n"
        "r2: #Note & { says: ##\"say \"#hi\"# twice\"## }\n"
        "r3: #Note & { says: #\"ends in \\\"# }\n");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "r1"), "says")), "a\\nb\nc");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "r2"), "says")), "say \"#hi\"# twice");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "r3"), "says")), "ends in \\");
    tri_content_free(c);

    /* an atom enum declared with an escape */
    c = load1_ok("#Saying: \"say \\\"hi\\\"\" | \"other\"\n\"say \\\"hi\\\"\": \"say \\\"hi\\\" loudly\"\n#Q: { q: \"say \\u0022hi\\u0022\" }\n"
                 "q1: #Q & { q: \"say \\\"hi\\\" loudly\" }\n");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "q1"), "q")), "say \"hi\" loudly");
    tri_content_free(c);
}

void test_string_errors(void)
{
    static const struct { const char *src, *diag; } cases[] = {
        { "#N: { s: text }\nn: #N & { s: \"a\\qb\" }\n", "s.tri:2:16: error: unknown escape" },
        { "#N: { s: text }\nn: #N & { s: \"a\\u12\" }\n", "s.tri:2:16: error: \\u takes four hex digits" },
        { "#N: { s: text }\nn: #N & { s: \"\\U0000004\" }\n", "\\U takes eight hex digits" },
        { "#N: { s: text }\nn: #N & { s: \"\\ud800\" }\n", "not a Unicode scalar value" },
        { "#N: { s: text }\nn: #N & { s: \"\\U00110000\" }\n", "not a Unicode scalar value" },
        { "#N: { s: text }\nn: #N & { s: \"\\u0000\" }\n", "may not contain U+0000" },
        { "#N: { s: text }\nn: #N & { s: \"abc\n\" }\n", "s.tri:2:14: error: unterminated string" },
        { "#N: { s: text }\nn: #N & { s: #\"abc\" }\n", "unterminated string" },
        { "#N: { s: text }\nn: #N & { s: \"ends \\\" }\n", "unterminated string" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        TriContent *c = load1(cases[i].src);
        CHECK(!tri_content_ok(c));
        if (!has_diag(c, cases[i].diag, 1)) { fprintf(stderr, "    case %zu:\n", i); dump_diags(c); }
        CHECK(has_diag(c, cases[i].diag, 1));
        tri_content_free(c);
    }
    /* a token after an escape keeps its column */
    TriContent *c = load1("#N: { s: text, n: int }\nn: #N & { s: \"\\u00e9\", n: \"x\" }\n");
    const char *file;
    int line = 0, col = 0;
    for (size_t i = 0; i < tri_diag_count(c); i++)
        if (tri_diag_is_error(c, i) && tri_diag_location(c, i, &file, &line, &col)) break;
    CHECK(line == 2);
    tri_content_free(c);
}

/* A default among text: `*"a" | text` is text, its default the string,
 * through a subtype too, and constructed as it; an instance's own string
 * wins. Alternatives text covers (a regex) are text too. A string an enum
 * lists is an atom, not text, and can't stand beside it. */
void test_text_defaults(void)
{
    TriContent *c = load1_ok(
        "#Log: { splitsInto: *\"firewood_20\" | text }\n"
        "#Trunk: #Log & { lengths: int }\n"
        "#Rx: { r: *\"ab\" | =~\"^z\" | text }\n"
        "log1: #Log & {}\n"
        "log2: #Log & { splitsInto: \"kindling\" }\n"
        "trunk1: #Trunk & { lengths: 3 }\n"
        "rx1: #Rx & {}\n"
        "rx2: #Rx & { r: \"zz\" }\n");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "log1"), "splitsInto")), "firewood_20");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "log2"), "splitsInto")), "kindling");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "trunk1"), "splitsInto")), "firewood_20");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "rx1"), "r")), "ab");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "rx2"), "r")), "zz");
    TriArena *a = tri_arena_new();
    CHECK_STR(text_of(c, tri_at(c, tri_construct(c, "trunk1", 7, a), "splitsInto")), "firewood_20");
    tri_arena_free(a);
    tri_content_free(c);

    c = load1("\"wood\": \"oak\" | \"birch\"\n#M: { m: *\"oak\" | text }\nm1: #M & {}\n");
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "s.tri:2:11: error: \"oak\" is an enum's atom, not text", 1));
    tri_content_free(c);
}

/* --- regex constraints ----------------------------------------------------------------- */

static const char *rx_content =
    "#Material: \"metal\" | \"stone\" | \"oak\"\n"
    "\"metal\": \"steel\" | \"brass\" | \"iron\"\n"
    "#Thing: { material: #Material, label: text, code: _ }\n"
    "#Coded: #Thing & { label: =~\"^[a-z]+-\\\\d+$\" }\n"
    "tagged: #Coded & { material: \"steel\", label: \"ab-12\", code: \"x\" }\n"
    "p_label: #Thing & { label: =~\"^ab\" & !~\"9\" }\n"
    "p_metal: #Thing & { material: =~\"^(steel|brass|iron)$\" }\n"
    "p_steel: #Thing & { material: \"steel\" & =~\"^s\" }\n"
    "p_code: #Thing & { code: =~\"^s\" }\n";

void test_regex_on_text(void)
{
    TriContent *c = load1_ok(rx_content);
    /* a type's regex constrains its instances; the spec keeps the concrete value */
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "tagged"), "label")), "ab-12");
    /* constraints conjoin, printed sorted, and read back */
    const char *lab = printed(c, tri_at(c, tri_pattern(c, "p_label"), "label"));
    CHECK_STR(lab, "!~\"9\" & =~\"^ab\"");
    TriArena *a = tri_arena_new();
    char err[256] = "";
    const TriNode *v = tri_value(c, "#Thing & { label: =~\"^ab\" & !~\"9\" }", a, err, sizeof err);
    CHECK(v != NULL);
    CHECK_STR(printed(c, tri_at(c, v, "label")), lab);
    /* unification: a concrete string must meet every constraint */
    const TriNode *ok = tri_value(c, "#Thing & { label: \"abc\" }", a, err, sizeof err);
    const TriNode *bad = tri_value(c, "#Thing & { label: \"ab9\" }", a, err, sizeof err);
    TriFailure f;
    const TriNode *u = tri_unify(c, v, ok, a, &f);
    CHECK(u && !strcmp(text_of(c, tri_at(c, u, "label")), "abc"));
    CHECK(tri_unify(c, v, bad, a, &f) == NULL);
    CHECK_STR(f.path, "label");
    /* two constrained values: the union of their constraints */
    const TriNode *w = tri_value(c, "#Thing & { label: =~\"c$\" & =~\"^ab\" }", a, err, sizeof err);
    u = tri_unify(c, v, w, a, &f);
    CHECK_STR(printed(c, tri_at(c, u, "label")), "!~\"9\" & =~\"^ab\" & =~\"c$\"");
    /* a regex on a number is a conflict of kinds */
    CHECK(tri_value(c, "#Thing & { code: 3 & =~\"3\" }", a, err, sizeof err) == NULL);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_regex_on_atoms(void)
{
    TriContent *c = load1_ok(rx_content);
    /* a regex tests an atom's name and keeps the atom */
    const TriNode *m = tri_at(c, tri_pattern(c, "p_steel"), "material");
    CHECK(tri_node_type(m) == tri_type_named(c, "\"steel\""));
    /* narrowing an enum to exactly a sub-enum's atoms gives the sub-enum */
    CHECK(tri_node_type(tri_at(c, tri_pattern(c, "p_metal"), "material")) == tri_type_named(c, "\"metal\""));
    TriArena *a = tri_arena_new();
    char err[256] = "";
    /* none, one, all */
    CHECK(tri_value(c, "#Thing & { material: =~\"^z\" }", a, err, sizeof err) == NULL);
    const TriNode *one = tri_value(c, "#Thing & { material: =~\"^st[e]\" }", a, err, sizeof err);
    CHECK(one && tri_node_type(tri_at(c, one, "material")) == tri_type_named(c, "\"steel\""));
    const TriNode *all = tri_value(c, "#Thing & { material: =~\".\" }", a, err, sizeof err);
    CHECK(all && tri_node_type(tri_at(c, all, "material")) == tri_type_named(c, "#Material"));
    /* at runtime, some that no enum is exactly: the covering enum, never a failure */
    const TriNode *some = tri_value(c, "#Thing & { material: =~\"^s\" }", a, err, sizeof err);
    CHECK(some && tri_node_type(tri_at(c, some, "material")) == tri_type_named(c, "#Material"));
    tri_arena_free(a);
    tri_content_free(c);

    /* at load, the same is an error that says what to do */
    const char *names[] = { "s.tri" };
    char src[2048];
    snprintf(src, sizeof src, "%sbad: #Thing & { material: =~\"^s\" }\n", rx_content);
    const char *srcs[] = { src };
    c = load(names, srcs, 1);
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "=~\"^s\" (allows only \"steel\" and \"stone\", and no enum is exactly those: declare one) vs #Material", 1));
    tri_content_free(c);
    snprintf(src, sizeof src, "%sbad: #Thing & { material: \"oak\" & =~\"^s\" }\n", rx_content);
    c = load(names, srcs, 1);
    CHECK(has_diag(c, "conflict at material: =~\"^s\" vs \"oak\"", 1));
    tri_content_free(c);
}

void test_regex_matching(void)
{
    TriContent *c = load1_ok(rx_content);
    TriArena *a = tri_arena_new();
    char err[256] = "";
    const TriNode *pat = tri_pattern(c, "p_label");
    static const struct { const char *desc; TriMatch want; } rows[] = {
        { "#Thing & { label: \"abc\" }", TRI_ENTAILED },
        { "#Thing & { label: \"ab9\" }", TRI_INCOMPATIBLE },
        { "#Thing & { label: \"xbc\" }", TRI_INCOMPATIBLE },
        { "#Thing", TRI_UNKNOWN },
        /* constraints that include the pattern's: entailed without a string */
        { "#Thing & { label: =~\"^ab\" & !~\"9\" & =~\"c$\" }", TRI_ENTAILED },
        /* a different regex that happens to imply it: unknown, not proved */
        { "#Thing & { label: =~\"^abc\" & !~\"[0-9]\" }", TRI_UNKNOWN },
    };
    for (size_t i = 0; i < sizeof rows / sizeof *rows; i++) {
        const TriNode *d = tri_value(c, rows[i].desc, a, err, sizeof err);
        TriMatchResult r;
        TriMatch m = tri_match(c, pat, d, &r);
        if (m != rows[i].want) fprintf(stderr, "    row %zu: got %d\n", i, (int) m);
        CHECK(m == rows[i].want);
        if (m == TRI_UNKNOWN) CHECK(r.nresidual == 1 && !strcmp(r.residual[0], "label"));
    }
    /* residuals don't depend on where constraint sets happen to be in memory:
     * many sets, made before and after the pattern's, all leave label open */
    for (int i = 0; i < 40; i++) {
        char d[128];
        snprintf(d, sizeof d, "#Thing & { label: =~\"^ab%c\" & !~\"[0-9]\" }", 'a' + i % 26);
        TriMatchResult rr;
        const TriNode *dn = tri_value(c, d, a, err, sizeof err);
        CHECK(tri_match(c, pat, dn, &rr) == TRI_UNKNOWN);
        CHECK(rr.nresidual == 1 && !strcmp(rr.residual[0], "label"));
    }
    /* the same, with the description's set interned before the pattern's */
    {
        const char *names[] = { "s.tri" };
        const char *srcs[] = {
            "#Thing: { label: text }\n"
            "early: #Thing & { label: =~\"^abc\" & !~\"[0-9]\" }\n"
            "late: #Thing & { label: =~\"^ab\" & !~\"9\" }\n" };
        TriContent *c2 = load(names, srcs, 1);
        TriArena *a2 = tri_arena_new();
        TriMatchResult rr;
        const TriNode *dn = tri_value(c2, "#Thing & { label: =~\"^abc\" & !~\"[0-9]\" }", a2, err, sizeof err);
        CHECK(tri_match(c2, tri_pattern(c2, "late"), dn, &rr) == TRI_UNKNOWN);
        CHECK(rr.nresidual == 1 && !strcmp(rr.residual[0], "label"));
        CHECK(tri_match(c2, tri_pattern(c2, "early"), tri_value(c2, "#Thing & { label: =~\"^ab\" & !~\"9\" }", a2, err, sizeof err), &rr) == TRI_UNKNOWN);
        CHECK(rr.nresidual == 1 && !strcmp(rr.residual[0], "label"));
        tri_arena_free(a2);
        tri_content_free(c2);
    }
    /* a regex in a pattern against an atom: by its name */
    const TriNode *code = tri_pattern(c, "p_code");
    TriMatchResult r;
    CHECK(tri_match(c, code, tri_value(c, "#Thing & { code: \"steel\" }", a, err, sizeof err), &r) == TRI_ENTAILED);
    CHECK(tri_match(c, code, tri_value(c, "#Thing & { code: \"oak\" }", a, err, sizeof err), &r) == TRI_INCOMPATIBLE);
    CHECK(tri_match(c, code, tri_value(c, "#Thing & { code: \"sunny\" }", a, err, sizeof err), &r) == TRI_ENTAILED);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_regex_generalise_save_and_migrate(void)
{
    TriContent *c = load1_ok(rx_content);
    TriArena *a = tri_arena_new();
    char err[256] = "";
    const TriNode *x = tri_value(c, "#Thing & { label: =~\"^ab\" & =~\"c$\" }", a, err, sizeof err);
    const TriNode *y = tri_value(c, "#Thing & { label: \"abd\" }", a, err, sizeof err);
    const TriNode *z = tri_value(c, "#Thing & { label: \"abc\" }", a, err, sizeof err);
    /* the generalisation keeps the constraints both meet */
    CHECK_STR(printed(c, tri_at(c, tri_lgg(c, x, y, a), "label")), "=~\"^ab\"");
    CHECK_STR(printed(c, tri_at(c, tri_lgg(c, x, z, a), "label")), "=~\"^ab\" & =~\"c$\"");
    CHECK_STR(printed(c, tri_at(c, tri_lgg(c, y, z, a), "label")), "text");
    const TriNode *w = tri_value(c, "#Thing & { label: =~\"^ab\" & !~\"x\" }", a, err, sizeof err);
    CHECK_STR(printed(c, tri_at(c, tri_lgg(c, x, w, a), "label")), "=~\"^ab\"");
    int fwd, bwd;
    tri_subsumes(c, tri_lgg(c, x, y, a), x, &fwd, &bwd);
    CHECK(fwd && !bwd);
    /* memory decay forgets a field's constraints down to its type's own */
    const TriNode *coded = tri_value(c, "#Coded & { label: \"ab-12\" }", a, err, sizeof err);
    CHECK_STR(printed(c, tri_at(c, tri_generalize(c, coded, "label", 1, a), "label")), "=~\"^[a-z]+-\\\\d+$\"");
    /* saves keep constraints, by name and by ID */
    for (int by_id = 0; by_id <= 1; by_id++) {
        char *saved = tri_save(c, x, by_id);
        const TriNode *back = tri_restore(c, saved, a, err, sizeof err);
        CHECK(back != NULL);
        CHECK_STR(printed(c, tri_at(c, back, "label")), "=~\"^ab\" & =~\"c$\"");
        free(saved);
    }
    /* and moving to another build of the content compiles them there */
    const char *names[] = { "s.tri" };
    const char *srcs[] = { rx_content };
    TriContent *c2 = load(names, srcs, 1);
    TriArena *a2 = tri_arena_new();
    const TriNode *moved = tri_migrate(c, c2, x, a2, err, sizeof err);
    CHECK(moved != NULL);
    CHECK_STR(printed(c2, tri_at(c2, moved, "label")), "=~\"^ab\" & =~\"c$\"");
    /* the content hash depends on constraints' contents, not their addresses */
    CHECK(tri_content_hash(c) == tri_content_hash(c2));
    tri_arena_free(a2);
    tri_content_free(c2);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_regex_errors(void)
{
    static const struct { const char *src, *diag; } cases[] = {
        { "#N: { s: text }\nn: #N & { s: =~\"(ab\" }\n", "s.tri:2:16: error: bad regular expression: missing )" },
        { "#N: { s: text }\nn: #N & { s: =~\"\\d\" }\n", "(in a regex, write a raw string such as #\"\\d+\"#" },
        { "#N: { s: text }\nn: #N & { s: =~ 5 }\n", "expected a string after =~ or !~" },
        { "#N: { s: text }\nn: #N & { s: = \"x\" }\n", "unexpected '='; did you mean ':' or '=~'?" },
        { "#N: { s: text }\nn: #N & { s: =~#\"(?=a)\"# }\n", "lookaround is not supported" },
        { "#N: { s: text }\nn: #N & { s: \"abc\" & !~\"b\" }\n", "conflict at s: \"abc\" vs !~\"b\"" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        TriContent *c = load1(cases[i].src);
        CHECK(!tri_content_ok(c));
        if (!has_diag(c, cases[i].diag, 1)) { fprintf(stderr, "    case %zu:\n", i); dump_diags(c); }
        CHECK(has_diag(c, cases[i].diag, 1));
        tri_content_free(c);
    }
}

/* --- interpolation ---------------------------------------------------------------------- */

static const char *in_content =
    "#Tone: \"dark\" | \"light\"\n"
    "#Shade: \"dark_red\" | \"light_red\"\n"
    "#Person: { given: text & $f, family: text & $l, full: \"\\($f) \\($l)\" }\n"
    "#Bolt: { size: length & $s, count: int & $n, label: \"M\\($s) x\\($n * 2)\" }\n"
    "#Paint: { tone: #Tone & $t, shade: #Shade & \"\\($t)_red\" }\n"
    "ada: #Person & { given: \"Ada\", family: \"Lovelace\" }\n"
    "bolt: #Bolt & { size: 19mm, count: 3 }\n"
    "paint: #Paint & { tone: \"dark\" }\n"
    "any_paint: #Paint\n"
    "#Note: { says: text }\n"
    "constant: #Note & { says: \"a\\(1 + 2)b \\(\"(x)\")\" }\n"
    "raw: #Note & { says: #\"\\(not this) but \\#(\"this\")\"# }\n"
    "escaped: #Note & { says: \"\\\\(not interpolated)\" }\n";

void test_interpolation(void)
{
    TriContent *c = load1_ok(in_content);
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "ada"), "full")), "Ada Lovelace");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "bolt"), "label")), "M19mm x6");
    /* a result some enum lists is its atom */
    const TriNode *shade = tri_at(c, tri_spec(c, "paint"), "shade");
    CHECK(tri_node_type(shade) == tri_type_named(c, "\"dark_red\""));
    /* constants, strings with parentheses inside, raw strings, and \\( escaped */
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "constant"), "says")), "a3b (x)");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "raw"), "says")), "\\(not this) but this");
    CHECK_STR(text_of(c, tri_at(c, tri_spec(c, "escaped"), "says")), "\\(not interpolated)");
    /* construction from a seed: the shade follows whichever tone is drawn */
    TriArena *a = tri_arena_new();
    for (uint64_t seed = 1; seed <= 6; seed++) {
        const TriNode *p = tri_construct(c, "any_paint", seed, a);
        CHECK(p != NULL);
        char tone[32], sh[32];
        tri_text(c, tri_at(c, p, "tone"), tone, sizeof tone);
        tri_text(c, tri_at(c, p, "shade"), sh, sizeof sh);
        char want[40];
        snprintf(want, sizeof want, "%s_red", tone);
        CHECK_STR(sh, want);
    }
    /* runtime values, and unification that makes the parts concrete */
    char err[256] = "";
    const TriNode *v = tri_value(c, "#Person & { given: \"A\", family: \"B\" }", a, err, sizeof err);
    CHECK_STR(text_of(c, tri_at(c, v, "full")), "A B");
    const TriNode *half = tri_value(c, "#Person & { given: \"Grace\" }", a, err, sizeof err);
    CHECK(half && tri_text(c, tri_at(c, half, "full"), NULL, 0) == (size_t) -1);
    TriFailure f;
    const TriNode *u = tri_unify(c, half, tri_value(c, "#Person & { family: \"Hopper\" }", a, err, sizeof err), a, &f);
    CHECK(u != NULL);
    CHECK_STR(text_of(c, tri_at(c, u, "full")), "Grace Hopper");
    /* and a conflict with what it gives */
    CHECK(tri_unify(c, u, tri_value(c, "#Person & { full: \"Grace Brewster\" }", a, err, sizeof err), a, &f) == NULL);
    tri_arena_free(a);
    tri_content_free(c);

    /* content that contradicts what an interpolation gives */
    char src[2048];
    snprintf(src, sizeof src, "%swrong: #Person & { given: \"Ada\", family: \"Byron\", full: \"Ada Lovelace\" }\n", in_content);
    c = load1(src);
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "full", 1));
    tri_content_free(c);
}

void test_interpolation_errors(void)
{
    static const struct { const char *src, *diag; } cases[] = {
        { "#N: { s: text }\nn: #N & { s: \"a\\(1 + )b\" }\n", "s.tri:2:22: error: expected a value" },
        { "#N: { s: text }\nn: #N & { s: \"a\\(1 b\" }\n", "s.tri:2:16: error: unterminated interpolation" },
        { "#N: { s: text }\nn: #N & { s: \"a\\()b\" }\n", "an empty interpolation" },
        { "#N: { s: text }\nn: #N & { s: \"a\\(1) \\(2 3)\" }\n", "s.tri:2:25: error: unexpected input in an interpolation" },
        { "#N: { s: text }\nn: #N & { s: \"\\($x)\" }\n", "the tag $x in an interpolation is not bound to a field" },
        { "#N: { s: text, t: _ & $t }\nn: #N & { t: $t & { s: \"x\" }, s: \"\\($t)\" }\n", "a structure can't be interpolated" },
        { "#N: { s: text }\nn: #N & { s: =~\"\\(1)\" }\n", "a regex can't be interpolated" },
        { "#E: \"x\" | \"y\"\n\"\\(1)\": \"z\"\n", "a declaration's label can't be interpolated" },
        { "#N: { s: text }\nn: #N & { s: \"\\({ a: 1 })\" }\n", "only tags, strings, numbers and arithmetic can be interpolated" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        TriContent *c = load1(cases[i].src);
        CHECK(!tri_content_ok(c));
        if (!has_diag(c, cases[i].diag, 1)) { fprintf(stderr, "    case %zu:\n", i); dump_diags(c); }
        CHECK(has_diag(c, cases[i].diag, 1));
        tri_content_free(c);
    }
}
