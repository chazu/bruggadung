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
