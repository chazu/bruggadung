#include "test.h"

#include <stdlib.h>

/* The scenarios of CONTENT_LANGUAGE.md. */

/* --- Scenario 1: the miller's wrench, from content ------------------------------------ */

static const char *base_tri =
    "#Material: \"steel\" | \"brass\" | \"oak\"\n"
    "#Physical: {\n"
    "    @component(Physical)\n"
    "    mass:     mass      @field(content, saved, perceive(touch))\n"
    "    material: #Material @field(content, saved, perceive(sight))\n"
    "}\n"
    "#Sized: {\n"
    "    @component(Sized)\n"
    "    size: length @field(content, saved, perceive(sight, touch))\n"
    "}\n"
    "#Hard: { hardness: int & >=0 & <=100 }\n"
    "#Steel: #Hard & { hardness: *50 }\n"
    "#ForgedSteel: #Steel & { hardness: *62 }\n"
    "#Tool: #Physical & #Sized & {\n"
    "    @component(Tool)\n"
    "    wear: *0 | >=0 & <=1000 @field(saved, proposable, inspect)\n"
    "}\n"
    "#Wrench: #Tool\n"
    "#Finished: { finish: \"black\" | \"bright\" | \"dull\" }\n";

static const char *mill_tri =
    "miller_wrench: #Wrench & #ForgedSteel & {\n"
    "    material: \"steel\"\n"
    "    size:     19mm\n"
    "    mass:     0.85kg\n"
    "}\n";

static const char *finish_tri =
    "#Painted: #Finished & { finish: *\"black\" }\n"
    "#Oiled:   #Finished & { finish: *\"bright\" }\n"
    "miller_wrench: #Painted & #Oiled\n";

static TriContent *scenario1(void)
{
    const char *names[] = { "base.tri", "mill.tri", "finish.tri" };
    const char *srcs[] = { base_tri, mill_tri, finish_tri };
    TriContent *c = load(names, srcs, 3);
    if (!tri_content_ok(c)) dump_diags(c);
    return c;
}

void test_scenario1_order_independence(void)
{
    const char *names[] = { "base.tri", "mill.tri", "finish.tri" };
    const char *srcs[] = { base_tri, mill_tri, finish_tri };
    int perms[6][3] = { {0,1,2}, {0,2,1}, {1,0,2}, {1,2,0}, {2,0,1}, {2,1,0} };
    uint64_t hash0 = 0;
    char spec0[4096] = { 0 };
    for (int p = 0; p < 6; p++) {
        const char *n[3], *s[3];
        for (int i = 0; i < 3; i++) { n[i] = names[perms[p][i]]; s[i] = srcs[perms[p][i]]; }
        TriContent *c = load(n, s, 3);
        CHECK(tri_content_ok(c));
        if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); continue; }
        char spec[4096];
        tri_print(c, tri_spec(c, "miller_wrench"), spec, sizeof spec);
        if (p == 0) {
            hash0 = tri_content_hash(c);
            strcpy(spec0, spec);
        } else {
            CHECK(tri_content_hash(c) == hash0);
            CHECK_STR(spec, spec0);
        }
        tri_content_free(c);
    }
}

void test_scenario1_defaults(void)
{
    TriContent *c = scenario1();
    const TriNode *spec = tri_spec(c, "miller_wrench");
    CHECK(spec != NULL);
    if (!spec) { dump_diags(c); tri_content_free(c); return; }
    int64_t lo, hi;
    tri_node_interval(tri_at(c, spec, "hardness"), &lo, &hi);
    CHECK(lo == 62 && hi == 62);                     /* #ForgedSteel beats #Steel */
    tri_node_interval(tri_at(c, spec, "wear"), &lo, &hi);
    CHECK(lo == 0 && hi == 0);
    tri_node_interval(tri_at(c, spec, "mass"), &lo, &hi);
    CHECK(lo == 850);                                /* exact quanta */
    tri_node_interval(tri_at(c, spec, "size"), &lo, &hi);
    CHECK(lo == 190);
    /* the generated conjunction type */
    CHECK_STR(tri_type_name(c, tri_node_type(spec)), "#ForgedSteel & #Oiled & #Painted & #Wrench");
    /* incomparable defaults are dropped with a warning */
    CHECK(has_diag(c, "conflicting defaults for finish from #Oiled, #Painted", 0));
    int saw_hardness = 0, saw_finish = 0;
    for (size_t i = 0; i < tri_spec_note_count(c, "miller_wrench"); i++) {
        const char *n = tri_spec_note(c, "miller_wrench", i);
        if (strcmp(n, "hardness <- #ForgedSteel (default)") == 0) saw_hardness = 1;
        if (strcmp(n, "finish <- seed") == 0) saw_finish = 1;
    }
    CHECK(saw_hardness);
    CHECK(saw_finish);
    /* patterns never use defaults */
    const TriNode *pat = tri_pattern(c, "miller_wrench");
    tri_node_interval(tri_at(c, pat, "hardness"), &lo, &hi);
    CHECK(lo == 0 && hi == 100);
    tri_content_free(c);
}

void test_scenario1_variation(void)
{
    TriContent *c = scenario1();
    CHECK(tri_spec_variation_count(c, "miller_wrench") == 1);
    CHECK_STR(tri_spec_variation_path(c, "miller_wrench", 0), "finish");
    TriArena *a = tri_arena_new();
    char first[1024], again[1024];
    tri_print(c, tri_construct(c, "miller_wrench", 7, a), first, sizeof first);
    tri_print(c, tri_construct(c, "miller_wrench", 7, a), again, sizeof again);
    CHECK_STR(again, first);
    int seen[3] = { 0, 0, 0 };
    const char *names[3] = { "\"black\"", "\"bright\"", "\"dull\"" };
    for (uint64_t seed = 1; seed <= 30; seed++) {
        const TriNode *w = tri_construct(c, "miller_wrench", seed, a);
        const char *f = tri_type_name(c, tri_node_type(tri_at(c, w, "finish")));
        for (int k = 0; k < 3; k++) if (strcmp(f, names[k]) == 0) seen[k] = 1;
    }
    CHECK(seen[0] + seen[1] + seen[2] >= 2);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_scenario1_conflict(void)
{
    const char *names[] = { "base.tri", "mill.tri", "finish.tri", "conflict.tri" };
    const char *srcs[] = { base_tri, mill_tri, finish_tri, "miller_wrench: size: 22mm\n" };
    TriContent *c = load(names, srcs, 4);
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "conflict at size: 19mm vs 22mm", 1) || has_diag(c, "conflict at size: 22mm vs 19mm", 1));
    CHECK(has_diag(c, "conflict.tri", 1));
    CHECK(has_diag(c, "mill.tri", 1));
    tri_content_free(c);
}

void test_scenario1_inexact(void)
{
    const char *names[] = { "base.tri", "bad.tri" };
    const char *srcs[] = { base_tri, "w: #Physical & { mass: 0.8505kg }\n" };
    TriContent *c = load(names, srcs, 2);
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "not a whole number of quanta: 0.8505kg", 1));
    tri_content_free(c);
}

void test_scenario1_feature_clash(void)
{
    const char *names[] = { "base.tri", "nut.tri" };
    const char *srcs[] = { base_tri, "#Nut: #Physical & { size: length }\n" };
    TriContent *c = load(names, srcs, 2);
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "feature 'size' is introduced by both", 1));
    tri_content_free(c);
}

/* --- Scenario 2: the nut of unknown size ------------------------------------------------- */

static const char *ops_tri =
    "#Fastener: #Physical & #Sized & {\n"
    "    @component(Fastener)\n"
    "    state: \"loose\" | \"tight\"\n"
    "}\n"
    "#Nut: #Fastener\n"
    "#Roles: { instrument: _, target: _ }\n"
    "#Requirements: { torque: torque }\n"
    "#Operation: { roles: #Roles, requires: #Requirements }\n"
    "tighten_roles: #Roles & {\n"
    "    instrument: #Wrench & { size: $s }\n"
    "    target:     #Nut    & { size: $s, state: \"loose\" }\n"
    "}\n"
    "tighten_nut: #Operation & {\n"
    "    roles: tighten_roles\n"
    "    requires: torque: >=40Nm\n"
    "}\n";

static TriContent *scenario2(void)
{
    const char *names[] = { "base.tri", "ops.tri" };
    const char *srcs[] = { base_tri, ops_tri };
    TriContent *c = load(names, srcs, 2);
    if (!tri_content_ok(c)) dump_diags(c);
    return c;
}

static const char *view_shadow =
    "#Roles & { instrument: #Wrench & { size: 19mm }, "
    "target: #Nut & { size: >=17mm & <=24mm, state: \"loose\" } }";
static const char *view_inspected =
    "#Roles & { instrument: #Wrench & { size: 19mm }, target: #Nut & { size: 19mm, state: \"loose\" } }";
static const char *view_wrong =
    "#Roles & { instrument: #Wrench & { size: 19mm }, target: #Nut & { size: 22mm, state: \"loose\" } }";

static const TriNode *shadow_view(TriContent *c, TriArena *a)
{
    return tri_value(c, view_shadow, a, NULL, 0);
}

void test_scenario2_unknown(void)
{
    TriContent *c = scenario2();
    CHECK(tri_content_ok(c));
    TriArena *a = tri_arena_new();
    const TriNode *pat = tri_pattern(c, "tighten_roles");
    char err[256];
    const TriNode *shadow = tri_value(c, view_shadow, a, err, sizeof err);
    CHECK(shadow != NULL);
    if (!shadow) fprintf(stderr, "    %s\n", err);
    TriMatchResult r;
    CHECK(tri_match(c, pat, shadow, &r) == TRI_UNKNOWN);
    CHECK(r.nresidual == 1);
    CHECK_STR(r.residual[0], "target.size");
    /* after inspecting: entailed, and $s is bound to 19 mm */
    const TriNode *seen = tri_value(c, view_inspected, a, NULL, 0);
    CHECK(tri_match(c, pat, seen, &r) == TRI_ENTAILED);
    CHECK_STR(printed(c, tri_binding(c, "tighten_roles", "s", seen)), "19mm");
    /* names copy: the operation contains the roles pattern */
    const TriNode *op = tri_pattern(c, "tighten_nut");
    CHECK(tri_match(c, tri_at(c, op, "roles"), seen, &r) == TRI_ENTAILED);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_scenario2_wrong_size(void)
{
    TriContent *c = scenario2();
    TriArena *a = tri_arena_new();
    const TriNode *pat = tri_pattern(c, "tighten_roles");
    const TriNode *wrong = tri_value(c, view_wrong, a, NULL, 0);
    TriMatchResult r;
    CHECK(tri_match(c, pat, wrong, &r) == TRI_INCOMPATIBLE);
    CHECK_STR(r.failure.path, "target.size");
    /* changing the instrument instead flips the inspected view to incompatible too */
    const TriNode *big = tri_value(c,
        "#Roles & { instrument: #Wrench & { size: 22mm }, target: #Nut & { size: 19mm, state: \"loose\" } }",
        a, NULL, 0);
    CHECK(tri_match(c, pat, big, &r) == TRI_INCOMPATIBLE);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_scenario2_hypotheses(void)
{
    TriContent *c = scenario2();
    TriArena *a = tri_arena_new();
    const TriNode *pat = tri_pattern(c, "tighten_roles");
    const TriNode *hs[2] = { tri_value(c, view_inspected, a, NULL, 0), tri_value(c, view_wrong, a, NULL, 0) };
    uint32_t cred[2] = { 45875, 19661 };              /* 0.7 and 0.3 in Q16 */
    TriMasses m = tri_match_hypotheses(c, pat, hs, cred, 2);
    CHECK(m.entailed == 45875 && m.incompatible == 19661 && m.unknown == 0);
    tri_arena_free(a);
    tri_content_free(c);
}

/* --- Scenario 3: the coat at dusk ----------------------------------------------------------- */

static const char *people_tri =
    "#Colour: \"dark\" | \"light\"\n"
    "\"dark\": \"grey\" | \"black\" | \"navy\" | \"brown\"\n"
    "#Coat: { colour: #Colour }\n"
    "#WoolCoat: #Coat & { grade: int }\n"
    "#Person: { coat: #Coat, height: length }\n";

void test_scenario3_recognition(void)
{
    const char *names[] = { "people.tri" };
    const char *srcs[] = { people_tri };
    TriContent *c = load(names, srcs, 1);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); return; }
    TriArena *a = tri_arena_new();
    TriFailure f;
    const TriNode *r7 = tri_value(c,
        "#Person & { coat: #WoolCoat & { colour: \"grey\" }, height: >=1.75m & <=1.85m }", a, NULL, 0);
    /* 1. dusk: a dark coat, a vaguer height; a strong match that keeps the specific values */
    const TriNode *dusk = tri_value(c,
        "#Person & { coat: { colour: \"dark\" }, height: >=1.70m & <=1.90m }", a, NULL, 0);
    const TriNode *merged = tri_unify(c, r7, dusk, a, &f);
    CHECK(merged != NULL);
    CHECK_STR(printed(c, tri_at(c, merged, "coat.colour")), "\"grey\"");
    CHECK_STR(printed(c, tri_at(c, merged, "height")), ">=1750mm & <=1850mm");
    /* 2. morning: a brown coat fails at exactly one path */
    const TriNode *brown = tri_value(c,
        "#Person & { coat: { colour: \"brown\" }, height: 1.80m }", a, NULL, 0);
    CHECK(tri_unify(c, r7, brown, a, &f) == NULL);
    CHECK_STR(f.path, "coat.colour");
    /* 4. a week later the memory decays along primary parents */
    const TriNode *d1 = tri_generalize(c, r7, "coat.colour", 1, a);
    CHECK_STR(printed(c, tri_at(c, d1, "coat.colour")), "\"dark\"");
    const TriNode *d2 = tri_generalize(c, d1, "coat", 1, a);
    CHECK_STR(tri_type_name(c, tri_node_type(tri_at(c, d2, "coat"))), "#Coat");
    CHECK(tri_at(c, d2, "coat.grade") == NULL);
    /* decay never goes above what the feature allows */
    const TriNode *d3 = tri_generalize(c, d1, "coat.colour", 5, a);
    CHECK_STR(printed(c, tri_at(c, d3, "coat.colour")), "#Colour");
    /* 5. the decayed memory now unifies with the brown coat: an honest false merge */
    CHECK(tri_unify(c, d2, brown, a, &f) != NULL);
    tri_arena_free(a);
    tri_content_free(c);
}

/* --- the quick check and pattern indexes ---------------------------------------------------- */

void test_quick_check(void)
{
    TriContent *c = scenario2();
    TriArena *a = tri_arena_new();
    const char *paths[] = { "target.size", "target.state" };
    TriQuickCheck *qc = tri_qc_new(c, paths, 2);
    CHECK(tri_qc_size(qc) == 3);
    CHECK_STR(tri_qc_path(qc, 0), "(root)");
    const TriNode *pat = tri_pattern(c, "tighten_roles");
    const TriNode *loose = tri_value(c, view_inspected, a, NULL, 0);
    const TriNode *tight = tri_value(c,
        "#Roles & { instrument: #Wrench & { size: 19mm }, target: #Nut & { size: 19mm, state: \"tight\" } }",
        a, NULL, 0);
    TriType vp[3], vl[3], vt[3];
    tri_qc_vector(qc, pat, vp);
    tri_qc_vector(qc, loose, vl);
    tri_qc_vector(qc, tight, vt);
    CHECK(tri_qc_compatible(qc, vp, vl));
    CHECK(!tri_qc_compatible(qc, vp, vt));          /* "loose" vs "tight" */
    /* paths learned from failures: the most frequent first, (root) skipped */
    const char *fails[] = { "a.b", "(root)", "target.state", "target.state", "a.b", "target.state" };
    TriQuickCheck *learned = tri_qc_from_failures(c, fails, 6, 1);
    CHECK(tri_qc_size(learned) == 2 || tri_qc_size(learned) == 1);  /* a.b is not a real path */
    tri_qc_free(learned);
    /* an index returns only patterns that could match */
    TriIndex *ix = tri_index_new(qc);
    tri_index_add(ix, pat, (void *) "tighten");
    tri_index_add(ix, tri_value(c, "#Roles & { target: #Nut & { state: \"tight\" } }", a, NULL, 0), (void *) "loosen");
    size_t cand[4];
    CHECK(tri_index_candidates(ix, loose, cand, 4) == 1);
    CHECK_STR((const char *) tri_index_tag(ix, cand[0]), "tighten");
    CHECK(tri_index_candidates(ix, shadow_view(c, a), cand, 4) == 1);
    tri_index_free(ix);
    tri_qc_free(qc);
    tri_arena_free(a);
    tri_content_free(c);
}
