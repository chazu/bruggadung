#include "test.h"

static const char *core_src =
    "#Material: \"steel\" | \"brass\" | \"oak\"\n"
    "#Physical: {\n"
    "    @component(Physical)\n"
    "    mass:     mass      @field(content, saved, perceive(touch))\n"
    "    material: #Material @field(content, saved, perceive(sight))\n"
    "}\n"
    "#Sized: {\n"
    "    @component(Sized)\n"
    "    size: length @field(content, saved)\n"
    "}\n"
    "#Tool: #Physical & #Sized & {\n"
    "    @component(Tool)\n"
    "    wear: *0 | >=0 & <=1000 @field(saved, proposable, inspect)\n"
    "}\n"
    "#Wrench: #Tool\n"
    "#Pair: { left: _, right: _ }\n"
    "#Bag: { items: #List }\n";

static TriContent *core(void)
{
    const char *names[] = { "core.tri" };
    const char *srcs[] = { core_src };
    TriContent *c = load(names, srcs, 1);
    if (!tri_content_ok(c)) dump_diags(c);
    return c;
}

void test_units(void)
{
    TriContent *c = core();
    CHECK(tri_content_ok(c));
    TriArena *a = tri_arena_new();
    int64_t lo, hi;
    const TriNode *n = tri_value(c, "0.85kg", a, NULL, 0);
    CHECK(n && tri_node_interval(n, &lo, &hi) && lo == 850 && hi == 850);
    n = tri_value(c, "19mm", a, NULL, 0);
    CHECK(n && tri_node_interval(n, &lo, &hi) && lo == 190);
    n = tri_value(c, "1.80m", a, NULL, 0);
    CHECK(n && tri_node_interval(n, &lo, &hi) && lo == 18000);
    n = tri_value(c, ">40Nm", a, NULL, 0);
    CHECK(n && tri_node_interval(n, &lo, &hi) && lo == 40001 && hi == INT64_MAX);
    n = tri_value(c, "2.5", a, NULL, 0);
    CHECK(n && tri_node_interval(n, &lo, &hi) && lo == 2500);
    CHECK_STR(printed(c, tri_value(c, "19.5mm", a, NULL, 0)), "19.5mm");
    char err[256];
    CHECK(!tri_value(c, "0.8505kg", a, err, sizeof err));
    CHECK_CONTAINS(err, "not a whole number of quanta");
    CHECK(!tri_value(c, "3parsecs", a, err, sizeof err));
    CHECK_CONTAINS(err, "unknown unit");
    tri_arena_free(a);
    tri_content_free(c);
}

/* Values made once content has loaded don't grow it: each one's syntax is
 * let go with it, and only what is copied out lives on, in the caller's
 * arena. */
void test_runtime_values_keep_content(void)
{
    TriContent *c = core();
    CHECK(tri_content_ok(c));
    TriArena *a = tri_arena_new();
    TriStats before, after;
    const TriNode *n = tri_value(c, "#Wrench & { mass: 0.85kg, material: \"steel\" }", a, NULL, 0);
    CHECK(n != NULL);
    tri_content_stats(c, &before);
    for (int i = 0; i < 2000; i++) {
        char expr[128];
        snprintf(expr, sizeof expr, "#Wrench & { mass: %d.%02dkg, size: %dmm }", i / 100, i % 100, i + 1);
        n = tri_value(c, expr, a, NULL, 0);
        CHECK(n != NULL);
    }
    CHECK(!tri_value(c, "#Wrench & { mass: ", a, NULL, 0));
    tri_content_stats(c, &after);
    CHECK(after.load_bytes == before.load_bytes);
    int64_t lo, hi;
    CHECK(n && tri_node_interval(tri_at(c, n, "mass"), &lo, &hi) && lo == 19990);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_hierarchy(void)
{
    TriContent *c = core();
    TriType steel = tri_type_named(c, "\"steel\"");
    TriType mat = tri_type_named(c, "#Material");
    TriType tool = tri_type_named(c, "#Tool");
    TriType wrench = tri_type_named(c, "#Wrench");
    TriType phys = tri_type_named(c, "#Physical");
    CHECK(steel != TRI_BOTTOM && mat != TRI_BOTTOM);
    CHECK(tri_subtype(c, steel, mat));
    CHECK(tri_subtype(c, wrench, phys));
    CHECK(tri_meet(c, tool, phys) == tool);
    CHECK(tri_meet(c, steel, tri_type_named(c, "\"oak\"")) == TRI_BOTTOM);
    CHECK(tri_primary_parent(c, steel) == mat);
    CHECK(tri_primary_parent(c, tool) == phys);
    /* parents get lower IDs than children */
    CHECK(phys < tool && tool < wrench);
    tri_content_free(c);
}

void test_glb(void)
{
    const char *names[] = { "glb.tri" };
    const char *srcs[] = {
        "#A: {}\n#B: {}\n#C: #A & #B\n#D: #A & #B\n"
    };
    TriContent *c = load(names, srcs, 1);
    CHECK(tri_content_ok(c));
    TriType A = tri_type_named(c, "#A"), B = tri_type_named(c, "#B");
    TriType m = tri_meet(c, A, B);
    CHECK_STR(tri_type_name(c, m), "glb[#C,#D]");
    CHECK(tri_subtype(c, tri_type_named(c, "#C"), m));
    CHECK(tri_subtype(c, tri_type_named(c, "#D"), m));
    tri_content_free(c);
}

void test_unify_tags(void)
{
    TriContent *c = core();
    TriArena *a = tri_arena_new();
    const TriNode *x = tri_value(c, "#Pair & { left: $x, right: $x }", a, NULL, 0);
    const TriNode *y = tri_value(c, "#Pair & { left: 3 }", a, NULL, 0);
    CHECK(x && y);
    TriFailure f;
    const TriNode *u = tri_unify(c, x, y, a, &f);
    CHECK_STR(printed(c, u), "#Pair & { left: $1 & 3, right: $1 }");
    /* information flows both ways through the tag */
    const TriNode *z = tri_value(c, "#Pair & { right: 4 }", a, NULL, 0);
    CHECK(!tri_unify(c, u, z, a, &f));
    CHECK_STR(f.path, "right");
    /* intervals intersect */
    const TriNode *w1 = tri_value(c, "#Sized & { size: >=10mm & <=20mm }", a, NULL, 0);
    const TriNode *w2 = tri_value(c, "#Sized & { size: >=15mm }", a, NULL, 0);
    CHECK_STR(printed(c, tri_unify(c, w1, w2, a, &f)), "#Sized & { size: >=15mm & <=20mm }");
    tri_arena_free(a);
    tri_content_free(c);
}

void test_closedness(void)
{
    TriContent *c = core();
    TriArena *a = tri_arena_new();
    char err[256];
    CHECK(!tri_value(c, "#Pair & { other: 1 }", a, err, sizeof err));
    CHECK_CONTAINS(err, "unknown feature");
    /* mass is introduced by #Physical, which has nothing in common with #Pair */
    CHECK(!tri_value(c, "#Pair & { mass: 1g }", a, err, sizeof err));
    /* but #Sized and #Physical meet in #Tool */
    CHECK_STR(tri_type_name(c, tri_node_type(tri_value(c, "#Sized & { mass: 1g }", a, NULL, 0))), "#Tool");
    /* an untyped struct gets the type introducing its features */
    CHECK_STR(printed(c, tri_value(c, "{ size: 19mm }", a, NULL, 0)), "#Sized & { size: 19mm }");
    /* dimensions don't mix */
    CHECK(!tri_value(c, "#Sized & { size: 1kg }", a, err, sizeof err));
    tri_arena_free(a);
    tri_content_free(c);
}

void test_lists(void)
{
    TriContent *c = core();
    TriArena *a = tri_arena_new();
    const TriNode *n = tri_value(c, "#Bag & { items: [1, 2] }", a, NULL, 0);
    CHECK_STR(printed(c, n), "#Bag & { items: #Cons & { first: 1, rest: #Cons & { first: 2, rest: #Null } } }");
    const TriNode *o = tri_value(c, "#Bag & { items: [1, ...] }", a, NULL, 0);
    CHECK_STR(printed(c, o), "#Bag & { items: #Cons & { first: 1, rest: #List } }");
    TriFailure f;
    CHECK(tri_unify(c, n, o, a, &f) != NULL);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_subsumption(void)
{
    TriContent *c = core();
    TriArena *a = tri_arena_new();
    const TriNode *gen = tri_value(c, "#Tool", a, NULL, 0);
    const TriNode *spec = tri_value(c, "#Wrench & { size: 19mm, material: \"steel\" }", a, NULL, 0);
    int f, b;
    tri_subsumes(c, gen, spec, &f, &b);
    CHECK(f && !b);
    tri_subsumes(c, spec, spec, &f, &b);
    CHECK(f && b);
    const TriNode *other = tri_value(c, "#Wrench & { size: 22mm }", a, NULL, 0);
    tri_subsumes(c, spec, other, &f, &b);
    CHECK(!f && !b);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_components(void)
{
    TriContent *c = core();
    CHECK(tri_component_count(c) == 3);
    int found = 0;
    for (size_t i = 0; i < tri_component_count(c); i++) {
        if (strcmp(tri_component_name(c, i), "Physical") != 0) continue;
        found = 1;
        CHECK(tri_component_field_count(c, i) == 2);
        const char *flags;
        CHECK_STR(tri_component_field(c, i, 0, &flags), "mass");
        CHECK_STR(flags, "content, saved, perceive(touch)");
    }
    CHECK(found);
    /* a wrench's components: the component types among its supertypes */
    size_t comps[8];
    size_t n = tri_type_components(c, tri_type_named(c, "#Wrench"), comps, 8);
    CHECK(n == 3);
    for (size_t i = 0; i < n && i < 8; i++) CHECK(comps[i] < tri_component_count(c));
    CHECK(tri_type_components(c, tri_type_named(c, "#Pair"), comps, 8) == 0);
    tri_content_free(c);
}
