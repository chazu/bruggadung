#include "test.h"

#include <stdlib.h>

/* The engine's limits: how deep a path goes, and how many operations one
 * content object runs (REVIEW.md §4.2, defects 1 and 2). */

static const char *limits_src =
    "#Bag: { items: #List }\n"
    "#Box: { w: length, h: length, girth: length }\n"
    "#Pair: { left: _, right: _ }\n"
    "box: #Box & { w: $w, h: $h, girth: ($w + $h) * 2 }\n"
    "small: box & { w: 10mm, h: 20mm }\n"
    "twins: #Pair & { left: $x, right: $x }\n";

static TriContent *limits(void)
{
    const char *names[] = { "limits.tri" };
    const char *srcs[] = { limits_src };
    TriContent *c = load(names, srcs, 1);
    if (!tri_content_ok(c)) dump_diags(c);
    return c;
}

/* "#Bag & { items: [0, 1, ..., n-1] }", with item `odd` changed to -1. */
static char *bag_expr(int n, int odd)
{
    size_t cap = 64 + (size_t) n * 8;
    char *s = malloc(cap);
    size_t k = (size_t) snprintf(s, cap, "#Bag & { items: [");
    for (int i = 0; i < n; i++)
        k += (size_t) snprintf(s + k, cap - k, "%s%d", i ? ", " : "", i == odd ? -1 : i);
    snprintf(s + k, cap - k, "] }");
    return s;
}

/* A list is a chain of rest arcs, so a list's length is the unifier's depth:
 * a conflict deep in a long list is a deep path. The failure report keeps the
 * path's first and last features and counts those it leaves out. */
void test_long_list_conflict(void)
{
    TriContent *c = limits();
    TriArena *a = tri_arena_new();
    TriFailure f;

    /* item 150 of 300: the path is items, 150 rests, first */
    char *xs = bag_expr(300, -1), *ys = bag_expr(300, 150);
    const TriNode *x = tri_value(c, xs, a, NULL, 0), *y = tri_value(c, ys, a, NULL, 0);
    CHECK(x && y);
    CHECK(!tri_unify(c, x, y, a, &f));
    CHECK_STR(f.left, "150");
    CHECK_STR(f.right, "-1");
    /* 152 features: the first 16, 108 left out, the last 28 */
    CHECK_STR(f.path,
              "items.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.<108 more>."
              "rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest."
              "rest.rest.rest.rest.rest.rest.rest.rest.first");
    CHECK(strlen(f.path) < sizeof f.path - 1);

    /* item 2000 of 2500, far past any fixed stack */
    char *ps = bag_expr(2500, -1), *qs = bag_expr(2500, 2000);
    const TriNode *p = tri_value(c, ps, a, NULL, 0), *q = tri_value(c, qs, a, NULL, 0);
    CHECK(p && q);
    CHECK(!tri_unify(c, p, q, a, &f));
    CHECK_STR(f.left, "2000");
    CHECK_CONTAINS(f.path, "items.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.rest.<1958 more>.rest.");
    CHECK_CONTAINS(f.path, ".rest.first");

    /* the same lists agree, and a shallow conflict afterwards has its own path */
    CHECK(tri_unify(c, p, p, a, &f) != NULL);
    CHECK(tri_unify(c, x, x, a, &f) != NULL);
    const TriNode *u = tri_value(c, "#Pair & { left: 1 }", a, NULL, 0);
    const TriNode *v = tri_value(c, "#Pair & { left: 2 }", a, NULL, 0);
    CHECK(!tri_unify(c, u, v, a, &f));
    CHECK_STR(f.path, "left");

    /* a path that fits is reported whole */
    char *ms = bag_expr(20, -1), *ns = bag_expr(20, 3);
    CHECK(!tri_unify(c, tri_value(c, ms, a, NULL, 0), tri_value(c, ns, a, NULL, 0), a, &f));
    CHECK_STR(f.path, "items.rest.rest.rest.first");

    free(xs); free(ys); free(ps); free(qs); free(ms); free(ns);
    tri_arena_free(a);
    tri_content_free(c);
}

/* The generation counters start each operation's scratch afresh. They are
 * 64-bit: forced to just below 2^32, where 32-bit counters wrapped into a
 * stale scratch pointer, the engine keeps going and gives the same results. */
void test_generation_counters_pass_2_32(void)
{
    TriContent *c = limits();
    TriArena *a = tri_arena_new();
    TriFailure f;
    char want_twins[256], want_small[256], want_copy[256];

    const TriNode *three = tri_value(c, "#Pair & { right: 3 }", a, NULL, 0);
    snprintf(want_twins, sizeof want_twins, "%s", printed(c, tri_unify(c, tri_spec(c, "twins"), three, a, &f)));
    snprintf(want_small, sizeof want_small, "%s", printed(c, tri_construct(c, "small", 7, a)));
    snprintf(want_copy, sizeof want_copy, "%s", printed(c, tri_copy(c, tri_spec(c, "small"), a)));
    CHECK_STR(want_twins, "#Pair & { left: $1 & 3, right: $1 }");
    CHECK_CONTAINS(want_small, "girth: 60mm");

    tri_test_set_generations(c, ((uint64_t) 1 << 32) - 3);
    for (int i = 0; i < 2000; i++) {
        TriArena *t = tri_arena_new();
        const TriNode *n = tri_value(c, "#Pair & { right: 3 }", t, NULL, 0);
        const TriNode *u = tri_unify(c, tri_spec(c, "twins"), n, t, &f);
        if (!u || strcmp(printed(c, u), want_twins) != 0) { CHECK_STR(printed(c, u), want_twins); break; }
        const TriNode *s = tri_construct(c, "small", 7, t);
        if (!s || strcmp(printed(c, s), want_small) != 0) { CHECK_STR(printed(c, s), want_small); break; }
        const TriNode *k = tri_copy(c, tri_spec(c, "small"), t);
        if (!k || strcmp(printed(c, k), want_copy) != 0) { CHECK_STR(printed(c, k), want_copy); break; }
        tri_arena_free(t);
    }
    tri_arena_free(a);
    tri_content_free(c);
}
