#include "test.h"

#include <stdint.h>
#include <stdlib.h>

/* Features beyond the three scenarios, and regressions for bugs found by probing. */

static TriContent *load1(const char *src)
{
    const char *names[] = { "f.tri" };
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

void test_builtin_types(void)
{
    TriContent *c = load1_ok(
        "#Lamp: { lit: bool, label: text, owner: ref, heat: temperature }\n"
        "lamp: #Lamp & { lit: true, label: \"brass lamp\", heat: 20C }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    const TriNode *s = tri_spec(c, "lamp");
    CHECK(s != NULL);
    CHECK_STR(printed(c, tri_at(c, s, "lit")), "true");
    CHECK_STR(printed(c, tri_at(c, s, "label")), "\"brass lamp\"");
    /* referents and free text stay open in a spec: they are bound at runtime */
    CHECK_STR(printed(c, tri_at(c, s, "owner")), "ref");
    CHECK(tri_spec_variation_count(c, "lamp") == 0);
    int64_t lo, hi;
    tri_node_interval(tri_at(c, s, "heat"), &lo, &hi);
    CHECK(lo == 29315 && hi == 29315);               /* 0.01 K quanta */
    tri_node_interval(tri_value(c, "-5C", a, NULL, 0), &lo, &hi);
    CHECK(lo == 26815);
    tri_node_interval(tri_value(c, "-2.5", a, NULL, 0), &lo, &hi);
    CHECK(lo == -2500);
    /* a unit suffix may end in digits */
    tri_node_interval(tri_value(c, "2m3", a, NULL, 0), &lo, &hi);
    CHECK(lo == 2000000);
    /* referents unify only with themselves */
    const TriNode *r7 = tri_value(c, "#Lamp & { owner: ref(7) }", a, err, sizeof err);
    CHECK(r7 != NULL);
    CHECK_STR(printed(c, tri_at(c, r7, "owner")), "ref(7)");
    TriFailure f;
    CHECK(tri_unify(c, r7, tri_value(c, "#Lamp & { owner: ref(7) }", a, NULL, 0), a, &f) != NULL);
    CHECK(!tri_unify(c, r7, tri_value(c, "#Lamp & { owner: ref(8) }", a, NULL, 0), a, &f));
    CHECK(!tri_value(c, "#Lamp & { lit: \"yes\" }", a, err, sizeof err));
    CHECK(!tri_value(c, "#Lamp & { owner: ref(2kg) }", a, err, sizeof err));
    tri_arena_free(a);
    tri_content_free(c);
}

void test_default_override_survives_tie(void)
{
    /* #R overrides #P; #R and #Q tie and are dropped; #P must stay overridden */
    TriContent *c = load1_ok(
        "#F: { f: \"a\" | \"b\" | \"c\" }\n"
        "#P: #F & { f: *\"a\" }\n#Q: #F & { f: *\"b\" }\n#R: #P & { f: *\"c\" }\n"
        "x: #R & #Q\ny: #R\nz: #P & #Q\n");
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "x"), "f")), "(\"a\" | \"b\" | \"c\")");
    CHECK(tri_spec_variation_count(c, "x") == 1);
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "y"), "f")), "\"c\"");
    CHECK(tri_spec_variation_count(c, "z") == 1);
    tri_content_free(c);
}

void test_blueprints_resolve_at_load(void)
{
    /* a blueprint (its type has a component) is checked at load */
    TriContent *c = load1(
        "#Physical: { @component(Physical)\n mass: mass @field(content)\n}\n"
        "rock: #Physical\n");
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "rock: mass is not concrete and has no bounds", 1));
    tri_content_free(c);
    /* other instances (operations, patterns) may stay open */
    c = load1_ok("#Roles: { size: length }\nany_size: #Roles\n");
    CHECK(tri_pattern(c, "any_size") != NULL);
    tri_content_free(c);
}

void test_registry_content_fields(void)
{
    const char *base =
        "#Tool: { @component(Tool)\n"
        "    size: length @field(content, saved)\n"
        "    wear: *0 | >=0 & <=1000 @field(saved, proposable)\n"
        "}\n";
    char src[1024];
    snprintf(src, sizeof src, "%sw: #Tool & { size: 19mm }\n", base);
    TriContent *c = load1_ok(src);              /* the type's default for wear is fine */
    CHECK(tri_spec(c, "w") != NULL);
    tri_content_free(c);
    snprintf(src, sizeof src, "%sw: #Tool & { size: 19mm, wear: 5 }\n", base);
    c = load1(src);
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "w: wear is not a content field (@field(saved, proposable))", 1));
    tri_content_free(c);
    CHECK(1);
}

void test_defaults_with_type_alternatives(void)
{
    TriContent *c = load1_ok(
        "#M: \"steel\" | \"oak\"\n"
        "#H: { h: *5 | int, m: *\"oak\" | #M, n: *3 | >=0 & <=9 }\n"
        "x: #H\ny: #H & { h: 7 }\n");
    const TriNode *x = tri_spec(c, "x");
    CHECK_STR(printed(c, x), "#H & { h: 5, m: \"oak\", n: 3 }");
    CHECK_STR(printed(c, tri_pattern(c, "x")), "#H & { h: int, m: #M, n: >=0 & <=9 }");
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "y"), "h")), "7");
    tri_content_free(c);
    /* separate numbers are not a type */
    c = load1("#H: { h: 1 | 3 }\n");
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "a disjunction of separate numbers is not a type", 1));
    tri_content_free(c);
}

static const char *head_src =
    "#Tool: { @component(Tool)\n"
    "    head: { shape: \"flat\" } | { shape: \"round\", radius: length & >=1mm & <=5mm }\n"
    "    finish: \"black\" | \"bright\" | \"dull\" @vary(0, 1, 9)\n"
    "}\n"
    "#Shape: { kind: \"round\", r: length } | { kind: \"square\", side: length }\n";

void test_type_disjunctions(void)
{
    char src[2048];
    snprintf(src, sizeof src, "%s"
             "any: #Tool\n"
             "round: #Tool & { head: { radius: 3mm } }\n"
             "flat: #Tool & { head: { shape: \"flat\" } }\n", head_src);
    TriContent *c = load1_ok(src);
    TriArena *a = tri_arena_new();
    char err[256];
    /* a feature only one alternative has selects it */
    const TriNode *r = tri_spec(c, "round");
    CHECK_STR(printed(c, tri_at(c, r, "head.shape")), "\"round\"");
    CHECK(tri_spec_variation_count(c, "round") == 1);      /* only finish */
    /* a value only one alternative allows is resolved in the spec */
    const TriNode *f = tri_spec(c, "flat");
    CHECK(tri_at(c, f, "head.radius") == NULL);
    CHECK_CONTAINS(printed(c, tri_at(c, f, "head")), "/{ shape: \"flat\" }");
    /* both alternatives open: construction chooses, then draws inside it */
    CHECK(tri_spec_variation_count(c, "any") == 2);
    int round = 0, flat = 0;
    for (uint64_t seed = 1; seed <= 40; seed++) {
        const TriNode *w = tri_construct(c, "any", seed, a);
        CHECK(w != NULL);
        if (!w) break;
        const TriNode *rad = tri_at(c, w, "head.radius");
        if (rad) {
            int64_t lo, hi;
            tri_node_interval(rad, &lo, &hi);
            CHECK(lo == hi && lo >= 10 && lo <= 50);
            round++;
        } else {
            CHECK_STR(printed(c, tri_at(c, w, "head.shape")), "\"flat\"");
            flat++;
        }
        /* @vary(0, 1, 9): black never */
        CHECK(strcmp(printed(c, tri_at(c, w, "finish")), "\"black\"") != 0);
    }
    CHECK(round > 5 && flat > 5);
    /* a named type defined as a disjunction */
    const TriNode *sq = tri_value(c, "#Shape & { side: 2mm }", a, err, sizeof err);
    CHECK(sq != NULL);
    CHECK_STR(printed(c, tri_at(c, sq, "kind")), "\"square\"");
    CHECK(!tri_value(c, "#Shape & { side: 2mm, r: 1mm }", a, err, sizeof err));
    CHECK(!tri_value(c, "#Shape & { kind: \"round\", side: 1mm }", a, err, sizeof err));
    /* runtime values have no disjunction of structures */
    CHECK(!tri_value(c, "{ shape: \"flat\" } | { side: 2mm }", a, err, sizeof err));
    CHECK_CONTAINS(err, "only in a type or an instance");
    tri_arena_free(a);
    tri_content_free(c);
}

void test_instance_variants(void)
{
    TriContent *c = load1_ok(
        "#Item: { kind: \"wrench\" | \"pliers\" | \"hammer\", size: length }\n"
        "#Roles: { tool: #Item, target: #Item }\n"
        "grip_op: #Roles & { tool: { kind: \"wrench\", size: $s } | { kind: \"pliers\" }, target: { size: $s } }\n"
        "sized: #Item & { size: 17mm | 19mm | 22mm }\n"
        "pick: #Item & ({ kind: *\"wrench\", size: 19mm } | { kind: \"hammer\", size: 1m })\n"
        "chosen: #Item & { size: 19mm } & (*{ kind: \"wrench\" } | { kind: \"pliers\" })\n");
    TriArena *a = tri_arena_new();
    CHECK(tri_pattern_variant_count(c, "grip_op") == 2);
    /* the generalisation keeps what both share */
    CHECK_STR(printed(c, tri_at(c, tri_pattern(c, "grip_op"), "tool.kind")), "(\"hammer\" | \"pliers\" | \"wrench\")");
    TriMatchResult r;
    const TriNode *d1 = tri_value(c, "#Roles & { tool: { kind: \"wrench\", size: 19mm }, target: { size: 19mm } }", a, NULL, 0);
    CHECK(tri_match_instance(c, "grip_op", d1, &r) == TRI_ENTAILED);
    CHECK_STR(printed(c, tri_binding(c, "grip_op", "s", d1)), "19mm");
    const TriNode *d2 = tri_value(c, "#Roles & { tool: { kind: \"pliers\" }, target: { size: 30mm } }", a, NULL, 0);
    CHECK(tri_match_instance(c, "grip_op", d2, &r) == TRI_ENTAILED);
    const TriNode *d3 = tri_value(c, "#Roles & { tool: { kind: \"hammer\" } }", a, NULL, 0);
    CHECK(tri_match_instance(c, "grip_op", d3, &r) == TRI_INCOMPATIBLE);
    const TriNode *d4 = tri_value(c, "#Roles & { tool: { size: 19mm } }", a, NULL, 0);
    CHECK(tri_match_instance(c, "grip_op", d4, &r) == TRI_UNKNOWN);
    CHECK(r.nresidual >= 1);
    /* separate numbers in an instance are alternatives */
    CHECK(tri_pattern_variant_count(c, "sized") == 3);
    int seen[3] = { 0, 0, 0 };
    for (uint64_t seed = 1; seed <= 30; seed++) {
        int64_t lo, hi;
        tri_node_interval(tri_at(c, tri_construct(c, "sized", seed, a), "size"), &lo, &hi);
        CHECK(lo == hi && (lo == 170 || lo == 190 || lo == 220));
        seen[lo == 170 ? 0 : lo == 190 ? 1 : 2] = 1;
    }
    CHECK(seen[0] && seen[1] && seen[2]);
    /* a default alternative picks its variant for the spec; patterns keep both */
    CHECK(tri_pattern_variant_count(c, "chosen") == 2);
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "chosen"), "kind")), "\"wrench\"");
    CHECK(tri_spec_variation_count(c, "chosen") == 0);
    CHECK(tri_pattern_variant_count(c, "pick") == 2);
    tri_arena_free(a);
    tri_content_free(c);

    /* the expansion cap */
    c = load1("#B: { a: int, b: int, c: int }\n"
              "x: #B & { a: 1 | 3, b: 1 | 3, c: 1 | 3 } @variants(4)\n");
    CHECK(!tri_content_ok(c) && !tri_pattern(c, "x"));
    CHECK(has_diag(c, "x expands to more than 4 variants", 1));
    tri_content_free(c);
    c = load1_ok("#B: { a: int, b: int, c: int }\nx: #B & { a: 1 | 3, b: 1 | 3, c: 1 | 3 } @variants(8)\n");
    CHECK(tri_pattern_variant_count(c, "x") == 8);
    tri_content_free(c);
    /* variants that cannot hold are dropped; none holding is an error */
    c = load1_ok("#B: { a: int & >=0 }\nx: #B & { a: -1 | 2 }\n");
    CHECK(tri_pattern_variant_count(c, "x") == 1);
    tri_content_free(c);
    c = load1("#B: { a: int & >=0 }\nx: #B & { a: -1 | -2 }\n");
    CHECK(!tri_content_ok(c) || !tri_pattern(c, "x"));
    tri_content_free(c);
}

void test_vary_weights(void)
{
    TriContent *c = load1_ok(
        "#Thing: { @component(Thing)\n"
        "    colour: \"red\" | \"green\" | \"blue\" @vary(1, 0, 3) @field(content)\n"
        "}\n"
        "t: #Thing\n"
        "u: #Thing & ({ colour: \"red\" } | { colour: \"blue\" }) @vary(0, 1)\n");
    TriArena *a = tri_arena_new();
    int red = 0, blue = 0;
    for (uint64_t seed = 1; seed <= 200; seed++) {
        const char *col = printed(c, tri_at(c, tri_construct(c, "t", seed, a), "colour"));
        CHECK(strcmp(col, "\"green\"") != 0);
        if (!strcmp(col, "\"red\"")) red++; else blue++;
        CHECK_STR(printed(c, tri_at(c, tri_construct(c, "u", seed, a), "colour")), "\"blue\"");
    }
    CHECK(blue > 2 * red && red > 10);        /* 3:1 */
    tri_arena_free(a);
    tri_content_free(c);
    c = load1("#Thing: { colour: \"red\" | \"green\" @vary(1, 2, 3) }\nt: #Thing\n");
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "@vary(1, 2, 3) needs one whole-number weight per alternative (2)", 1));
    tri_content_free(c);
    c = load1("#Thing: { colour: \"red\" | \"green\" }\nt: #Thing & ({ colour: \"red\" } | { colour: \"green\" }) @vary(1)\n");
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "@vary(1) needs one whole-number weight per alternative (2)", 1));
    tri_content_free(c);
}

void test_typed_lists(void)
{
    TriContent *c = load1_ok(
        "#Item: { w: mass }\n#Bag: { items: [...#Item] }\n"
        "#Pair: { left: _, right: _ }\nbag: #Bag & { items: [{ w: 1kg }, { w: 2kg }] }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    const TriNode *b = tri_pattern(c, "bag");
    CHECK_STR(printed(c, tri_at(c, b, "items.rest.first.w")), "2000g");
    CHECK_STR(tri_type_name(c, tri_node_type(tri_at(c, b, "items.rest.rest"))), "#Null");
    CHECK(!tri_value(c, "#Bag & { items: [3] }", a, err, sizeof err));
    CHECK(tri_value(c, "#Bag & { items: [] }", a, err, sizeof err) != NULL);
    CHECK_STR(printed(c, tri_value(c, "#Bag", a, NULL, 0)), "#Bag & { items: [...#Item] }");
    /* items before the ellipsis are not constrained by it */
    const TriNode *p = tri_value(c, "#Pair & { left: [1, ...#Item] }", a, err, sizeof err);
    CHECK(p != NULL);
    CHECK_STR(printed(c, tri_at(c, p, "left.rest")), "[...#Item]");
    /* lists of different element types meet in the empty list */
    CHECK(!tri_value(c, "#Bag & { items: [{ w: 1kg }] } & #Bag & { items: [] }", a, err, sizeof err));
    tri_arena_free(a);
    tri_content_free(c);
}

void test_recursive_types(void)
{
    TriContent *c = load1_ok(
        "#Person: { name: text, mother: #Person }\n"
        "#N: { val: int, next: #N & { val: >=0 } }\n"
        "#Tree: { label: text, kids: [...#Tree] }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    const TriNode *p = tri_value(c, "#Person & { mother: { mother: { name: \"Eve\" } } }", a, err, sizeof err);
    CHECK(p != NULL);
    CHECK_STR(printed(c, tri_at(c, p, "mother.mother.name")), "\"Eve\"");
    CHECK_STR(printed(c, tri_at(c, p, "mother.mother.mother")), "#Person");
    /* paths reach into untouched recursive structure: its type's constraint */
    CHECK_STR(printed(c, tri_at(c, p, "mother.mother.mother.name")), "text");
    CHECK_STR(printed(c, tri_at(c, p, "mother.mother.mother.mother.mother.name")), "text");
    const TriNode *n = tri_value(c, "#N", a, NULL, 0);
    CHECK_STR(printed(c, tri_at(c, n, "next.next.next.val")), ">=0");
    CHECK(tri_at(c, n, "next.nonesuch") == NULL);
    /* the constraint applies at every depth it is used */
    CHECK(!tri_value(c, "#N & { next: { next: { val: -1 } } }", a, err, sizeof err));
    CHECK(tri_value(c, "#N & { val: -1, next: { next: { val: 2 } } }", a, err, sizeof err) != NULL);
    CHECK(!tri_value(c, "#Tree & { kids: [{ label: \"a\", kids: [{ label: 3 }] }] }", a, err, sizeof err));
    /* subsumption and matching see a lazy node as its full constraint */
    const TriNode *gen = tri_value(c, "#N", a, NULL, 0);
    const TriNode *deep = tri_value(c, "#N & { next: { next: { val: 3 } } }", a, NULL, 0);
    int fw, bw;
    tri_subsumes(c, gen, deep, &fw, &bw);
    CHECK(fw && !bw);
    const TriNode *pat = tri_value(c, "#N & { next: { next: { val: 3 } } }", a, NULL, 0);
    TriMatchResult r;
    CHECK(tri_match(c, pat, gen, &r) == TRI_UNKNOWN);
    CHECK(r.nresidual == 1);
    CHECK_STR(r.residual[0], "next.next.val");
    CHECK(tri_match(c, pat, deep, &r) == TRI_ENTAILED);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_text_values(void)
{
    TriContent *c = load1_ok("#M: \"steel\" | \"oak\"\n#X: { m: #M, t: text }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    /* strings first seen at runtime are text */
    const TriNode *x = tri_value(c, "#X & { t: \"never seen at load\" }", a, err, sizeof err);
    CHECK(x != NULL);
    CHECK_STR(printed(c, tri_at(c, x, "t")), "\"never seen at load\"");
    TriFailure f;
    CHECK(tri_unify(c, x, tri_value(c, "#X & { t: \"never seen at load\" }", a, NULL, 0), a, &f) != NULL);
    CHECK(!tri_unify(c, x, tri_value(c, "#X & { t: \"other\" }", a, NULL, 0), a, &f));
    /* an enum's atom is still text where text is expected */
    CHECK_STR(printed(c, tri_value(c, "#X & { t: \"steel\", m: \"steel\" }", a, NULL, 0)), "#X & { m: \"steel\", t: \"steel\" }");
    CHECK(!tri_value(c, "#X & { m: \"gold\" }", a, err, sizeof err));
    TriMatchResult r;
    CHECK(tri_match(c, tri_value(c, "#X & { t: \"a\" }", a, NULL, 0), tri_value(c, "#X", a, NULL, 0), &r) == TRI_UNKNOWN);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_generalize_numbers(void)
{
    TriContent *c = load1_ok(
        "#Person: { height: length & >=0.5m & <=2.5m @widen(5cm), weight: mass, name: text }\n");
    TriArena *a = tri_arena_new();
    const TriNode *p = tri_value(c, "#Person & { height: 1.80m, weight: 70kg, name: \"Ines\" }", a, NULL, 0);
    CHECK_STR(printed(c, tri_at(c, tri_generalize(c, p, "height", 1, a), "height")), ">=1750mm & <=1850mm");
    CHECK_STR(printed(c, tri_at(c, tri_generalize(c, p, "height", 3, a), "height")), ">=1650mm & <=1950mm");
    /* never beyond what the type allows */
    CHECK_STR(printed(c, tri_at(c, tri_generalize(c, p, "height", 100, a), "height")), ">=500mm & <=2500mm");
    /* without a declared step, one step forgets the value */
    CHECK_STR(printed(c, tri_at(c, tri_generalize(c, p, "weight", 1, a), "weight")), "mass");
    CHECK_STR(printed(c, tri_at(c, tri_generalize(c, p, "name", 1, a), "name")), "text");
    CHECK_STR(printed(c, tri_at(c, tri_generalize(c, p, "height", 0, a), "height")), "1800mm");
    /* the root generalises along its primary parents */
    tri_content_free(c);
    c = load1_ok("#Thing: { w: mass }\n#Coat: #Thing & { colour: text }\n#WoolCoat: #Coat & { grade: int }\n");
    const TriNode *wc = tri_value(c, "#WoolCoat & { grade: 2, colour: \"grey\", w: 1kg }", a, NULL, 0);
    CHECK_STR(printed(c, tri_generalize(c, wc, "", 1, a)), "#Coat & { colour: \"grey\", w: 1000g }");
    CHECK_STR(printed(c, tri_generalize(c, wc, "", 2, a)), "#Thing & { w: 1000g }");
    tri_arena_free(a);
    tri_content_free(c);
}

void test_conflict_locations(void)
{
    TriContent *c = load1(
        "#Hard: { hardness: int & >=0 & <=100 }\n"
        "#Soft: #Hard & {\n    hardness: 150\n}\n"
        "#T: { a: 1 }\n#T: { a: 2 }\n");
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "f.tri:3:5: error: #Soft inheriting from #Hard: conflict at hardness: 150 vs >=0 & <=100, with #Hard at f.tri:1", 1));
    CHECK(has_diag(c, "f.tri:6:7: error: field: conflict at a: 1 vs 2, with the declaration at f.tri:5", 1));
    tri_content_free(c);
}

void test_explain_and_inspect(void)
{
    TriContent *c = load1_ok(
        "#Sized: { @component(Sized)\n size: length @field(content)\n}\n"
        "#Hard: { hardness: int & >=0 & <=100 }\n#Steel: #Hard & { hardness: *50 }\n"
        "#Tool: #Sized & #Steel & { @component(Tool)\n grip: \"bare\" | \"wrapped\"\n}\n"
        "w: #Tool & { size: 19mm }\n"
        "#Roles: { instrument: _, target: _ }\n"
        "fit: #Roles & { instrument: #Tool & { size: $s }, target: #Sized & { size: $s } }\n");
    char buf[2048];
    tri_inspect(c, "w", buf, sizeof buf);
    CHECK_CONTAINS(buf, "w: #Tool\n");
    CHECK_CONTAINS(buf, "  grip: (\"bare\" | \"wrapped\")  <- seed\n");
    CHECK_CONTAINS(buf, "  hardness: 50  <- default from #Steel\n");
    CHECK_CONTAINS(buf, "  size: 19mm  <- the instance\n");
    TriArena *a = tri_arena_new();
    const TriNode *d = tri_value(c, "#Roles & { instrument: #Tool & { size: 19mm }, target: #Sized & { size: 22mm } }", a, NULL, 0);
    tri_explain_instance(c, "fit", d, buf, sizeof buf);
    CHECK_CONTAINS(buf, "result: incompatible\n");
    CHECK_CONTAINS(buf, "$s at instrument.size = 19mm\n");
    CHECK_CONTAINS(buf, "first failing path: target.size: 19mm vs 22mm\n");
    d = tri_value(c, "#Roles & { instrument: #Tool & { size: 19mm }, target: #Sized }", a, NULL, 0);
    tri_explain(c, tri_pattern(c, "fit"), d, buf, sizeof buf);
    CHECK_CONTAINS(buf, "result: unknown\n");
    CHECK_CONTAINS(buf, "$1 at instrument.size = 19mm\n");
    CHECK_CONTAINS(buf, "residuals: target.size\n");
    tri_arena_free(a);
    tri_content_free(c);
}

void test_docstrings(void)
{
    TriContent *c = load1_ok(
        "// A tool anyone can hold.\n// Second line.\n#Tool: { size: length }\n"
        "// not attached: a blank line follows\n\n#Other: {}\n"
        "#Bare: {} // trailing comments are not docstrings\n"
        "// The miller's wrench.\nw: #Tool & { size: 19mm }\n");
    CHECK_STR(tri_doc(c, "#Tool"), "A tool anyone can hold.\nSecond line.");
    CHECK(tri_doc(c, "#Other") == NULL);
    CHECK(tri_doc(c, "#Bare") == NULL);
    CHECK_STR(tri_doc(c, "w"), "The miller's wrench.");
    tri_content_free(c);
}

void test_families(void)
{
    TriContent *c = load1_ok(
        "#Nut: { size: length, state: \"loose\" | \"tight\" }\n"
        "#Roles: { target: #Nut }\n"
        "tighten: #Roles & { target: { state: \"loose\" } } @family(operations) @quickcheck(target.state)\n"
        "loosen: #Roles & { target: { state: \"tight\" } } @family(operations)\n"
        "inspect: #Roles @family(operations) @quickcheck(target.size, target.state)\n"
        "greet: #Roles @family(methods)\n");
    CHECK(tri_family_count(c) == 2);
    CHECK_STR(tri_family_name(c, 0), "methods");
    CHECK_STR(tri_family_name(c, 1), "operations");
    TriIndex *ix = tri_family_index(c, "operations");
    CHECK(ix != NULL && tri_index_count(ix) == 3);
    TriArena *a = tri_arena_new();
    const TriNode *d = tri_value(c, "#Roles & { target: { state: \"tight\" } }", a, NULL, 0);
    size_t cand[8];
    size_t n = tri_index_candidates(ix, d, cand, 8);
    CHECK(n == 2);
    for (size_t i = 0; i < n; i++) CHECK(strcmp((const char *) tri_index_tag(ix, cand[i]), "tighten") != 0);
    CHECK(tri_family_index(c, "nonesuch") == NULL);
    tri_arena_free(a);
    tri_content_free(c);
}

static int lever_torque(void *ctx, TriContent *c, const TriNode *owner, int64_t *lo, int64_t *hi)
{
    (void) ctx;
    int64_t flo, fhi, llo, lhi;
    tri_node_interval(tri_at(c, owner, "force"), &flo, &fhi);
    tri_node_interval(tri_at(c, owner, "arm"), &llo, &lhi);
    if (flo != fhi || llo != lhi) return 0;
    *lo = *hi = flo * llo / 10000;        /* mN × 0.1 mm → mN·m */
    return 1;
}

void test_derived_fields(void)
{
    TriContent *c = load1_ok(
        "#Lever: { @component(Lever)\n"
        "    force: force & >=1N & <=100N @field(content)\n"
        "    arm: length @field(content)\n"
        "    torque: torque @fn(lever_torque)\n"
        "}\n"
        "bar: #Lever & { force: 50N, arm: 0.3m }\n");
    TriArena *a = tri_arena_new();
    /* unregistered: left open */
    CHECK_STR(printed(c, tri_at(c, tri_construct(c, "bar", 1, a), "torque")), "torque");
    tri_register_fn(c, "lever_torque", lever_torque, NULL);
    CHECK_STR(printed(c, tri_at(c, tri_construct(c, "bar", 1, a), "torque")), "15Nm");
    TriFailure f;
    const TriNode *d = tri_derive(c, tri_value(c, "#Lever & { force: 10N, arm: 1m }", a, NULL, 0), a, &f);
    CHECK_STR(printed(c, tri_at(c, d, "torque")), "10Nm");
    CHECK(!tri_derive(c, tri_value(c, "#Lever & { force: 10N, arm: 1m, torque: 3Nm }", a, NULL, 0), a, &f));
    tri_arena_free(a);
    tri_content_free(c);
}

void test_saves(void)
{
    const char *v1 =
        "#Colour: \"grey\" | \"brown\"\n#Coat: { colour: #Colour }\n"
        "#Person: { coat: #Coat, height: length, name: text, left: _, right: _ }\n";
    TriContent *c = load1_ok(v1);
    TriArena *a = tri_arena_new();
    char err[256];
    const TriNode *p = tri_value(c,
        "#Person & { coat: { colour: \"grey\" }, height: >=1.7m & <=1.9m, name: \"Marius\", left: $x & ref(12), right: $x }",
        a, err, sizeof err);
    CHECK(p != NULL);
    char before[1024];
    snprintf(before, sizeof before, "%s", printed(c, p));
    for (int by_id = 0; by_id <= 1; by_id++) {
        char *text = tri_save(c, p, by_id);
        const TriNode *q = tri_restore(c, text, a, err, sizeof err);
        CHECK(q != NULL);
        if (!q) fprintf(stderr, "    %s\n%s", err, text);
        else CHECK_STR(printed(c, q), before);       /* including the shared node */
        free(text);
    }
    char *by_name = tri_save(c, p, 0);
    char *by_id = tri_save(c, p, 1);
    tri_content_free(c);
    /* new content: a feature added, a colour added; a save by name migrates */
    c = load1_ok(
        "#Colour: \"grey\" | \"brown\" | \"navy\"\n#Coat: { colour: #Colour, buttons: int }\n"
        "#Person: { coat: #Coat, height: length, name: text, left: _, right: _, age: int }\n");
    const TriNode *q = tri_restore(c, by_name, a, err, sizeof err);
    CHECK(q != NULL);
    if (!q) fprintf(stderr, "    %s\n", err);
    CHECK_STR(printed(c, tri_at(c, q, "coat")), "#Coat & { buttons: int, colour: \"grey\" }");
    CHECK_STR(printed(c, tri_at(c, q, "name")), "\"Marius\"");
    CHECK(tri_at(c, q, "left") == tri_at(c, q, "right"));
    CHECK(!tri_restore(c, by_id, a, err, sizeof err));
    CHECK_CONTAINS(err, "different content");
    tri_content_free(c);
    /* a type that no longer exists fails loudly */
    c = load1_ok("#Colour: \"brown\"\n#Coat: { colour: #Colour }\n#Person: { coat: #Coat }\n");
    CHECK(!tri_restore(c, by_name, a, err, sizeof err));
    CHECK_CONTAINS(err, "no longer exists");
    CHECK(!tri_restore(c, "tri-save 1 0 names\n(\"#Coat\" \"colour\"", a, err, sizeof err));
    CHECK(!tri_restore(c, "garbage", a, err, sizeof err));
    tri_content_free(c);
    free(by_name);
    free(by_id);
    tri_arena_free(a);
}

void test_lgg(void)
{
    TriContent *c = load1_ok(
        "#Colour: \"dark\" | \"light\"\n\"dark\": \"grey\" | \"black\"\n"
        "#Coat: { colour: #Colour }\n#WoolCoat: #Coat & { grade: int }\n#Person: { coat: #Coat, height: length }\n");
    TriArena *a = tri_arena_new();
    const TriNode *x = tri_value(c, "#Person & { coat: #WoolCoat & { colour: \"grey\", grade: 2 }, height: 1.8m }", a, NULL, 0);
    const TriNode *y = tri_value(c, "#Person & { coat: { colour: \"black\" }, height: 1.7m }", a, NULL, 0);
    const TriNode *g = tri_lgg(c, x, y, a);
    CHECK_STR(printed(c, g), "#Person & { coat: #Coat & { colour: \"dark\" }, height: >=1700mm & <=1800mm }");
    int fw, bw;
    tri_subsumes(c, g, x, &fw, &bw);
    CHECK(fw);
    tri_subsumes(c, g, y, &fw, &bw);
    CHECK(fw);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_hypothesis_residuals(void)
{
    TriContent *c = load1_ok("#S: { a: length, b: length }\n");
    TriArena *a = tri_arena_new();
    const TriNode *p = tri_value(c, "#S & { a: 1mm, b: 2mm }", a, NULL, 0);
    const TriNode *hs[3] = {
        tri_value(c, "#S & { a: 1mm }", a, NULL, 0),
        tri_value(c, "#S & { b: 2mm }", a, NULL, 0),
        tri_value(c, "#S", a, NULL, 0),
    };
    uint32_t cr[3] = { 20000, 20000, 25536 };
    TriMasses m = tri_match_hypotheses(c, p, hs, cr, 3);
    CHECK(m.unknown == 65536 && m.entailed == 0);
    CHECK(m.nresidual == 2);
    CHECK_STR(m.residual[0], "b");
    CHECK_STR(m.residual[1], "a");
    tri_arena_free(a);
    tri_content_free(c);
}

/* The example file of CONTENT_LANGUAGE.md §17, read from the spec itself, with
 * the types it assumes from the other systems' content. */
static const char *example_support =
    "// What the example file assumes from the other systems' content.\n"
    "#Roles:        { instrument: _, target: _ }\n"
    "#Requirements: { torque: torque }\n"
    "#Operation:    { roles: #Roles, requires: #Requirements, effects: #Roles }\n"
    "#Placed:       { place: ref }\n"
    "#AboutItem:    { item: ref }\n"
    "#Proposition:  #Placed & { persistence: time }\n"
    "#Attitude:     #Proposition & { what: _ }\n"
    "#Observed:     #Attitude\n"
    "#Believed:     #Attitude\n"
    "#Floor:        { wetness: \"dry\" | \"damp\" | \"wet\" }\n"
    "#Smell:        { kind: \"soap\" | \"smoke\" | \"rot\" }\n"
    "#Climate:      { humidity: \"dry\" | \"humid\" }\n"
    "#Expertise:    {}\n"
    "#Domestic:     #Expertise\n"
    "#InterpretationRule: {\n"
    "    expertise:  #Expertise\n"
    "    premises:   [...#Proposition]\n"
    "    conclusion: #Proposition\n"
    "    strength:   fixed\n"
    "}\n"
    "#Action:    {}\n"
    "#Go:        #Action & { to: ref }\n"
    "#Take:      #Action & #AboutItem\n"
    "#Holding:   #Proposition & #AboutItem\n"
    "#LocatedAt: #Proposition & #AboutItem\n"
    "#Method: {\n"
    "    goal:      #Proposition\n"
    "    pre:       [...#Proposition]\n"
    "    steps:     [...#Action]\n"
    "    onUnknown: \"skip\" | \"subgoal\"\n"
    "}\n"
;

void test_example_file(void)
{
    FILE *f = fopen("../CONTENT_LANGUAGE.md", "rb");
    if (!f) { fprintf(stderr, "    (skipped: ../CONTENT_LANGUAGE.md not found)\n"); return; }
    static char doc[200000];
    size_t n = fread(doc, 1, sizeof doc - 1, f);
    fclose(f);
    doc[n] = 0;
    const char *sec = strstr(doc, "### 17. An example file");
    const char *start = sec ? strstr(sec, "```cue\n") : NULL;
    const char *end = start ? strstr(start + 7, "\n```") : NULL;
    CHECK(start && end);
    if (!start || !end) return;
    static char example[20000];
    snprintf(example, sizeof example, "%.*s\n", (int) (end - start - 7), start + 7);
    const char *names[] = { "support.tri", "example.tri" };
    const char *srcs[] = { example_support, example };
    TriContent *c = load(names, srcs, 2);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); return; }
    CHECK_STR(printed(c, tri_spec(c, "wrench_19")), "#Wrench & { mass: 850g, material: \"steel\", size: 19mm, wear: 0 }");
    /* the operation shares the size between instrument and target */
    const TriNode *op = tri_pattern(c, "tighten_nut");
    CHECK(tri_at(c, op, "roles.instrument.size") == tri_at(c, op, "roles.target.size"));
    CHECK_STR(printed(c, tri_at(c, op, "effects.target.state")), "\"tight\"");
    /* the rule's premises are typed, and  is one referent throughout */
    const TriNode *rule = tri_pattern(c, "recently_cleaned");
    CHECK(tri_at(c, rule, "premises.first.place") == tri_at(c, rule, "conclusion.place"));
    CHECK(tri_at(c, rule, "premises.rest.rest.first.place") == tri_at(c, rule, "conclusion.place"));
    CHECK_STR(printed(c, tri_at(c, rule, "strength")), "2.5");
    /* the method's steps go to where its precondition finds the tool */
    const TriNode *m = tri_pattern(c, "fetch_tool");
    CHECK(tri_at(c, m, "pre.first.place") == tri_at(c, m, "steps.first.to"));
    CHECK(tri_at(c, m, "goal.item") == tri_at(c, m, "steps.rest.first.item"));
    /* and a description of a damp, soapy room matches its first premise */
    TriArena *a = tri_arena_new();
    const TriNode *seen = tri_value(c, "#Observed & { what: #Floor & { wetness: \"damp\" }, place: ref(4) }", a, NULL, 0);
    TriMatchResult r;
    CHECK(tri_match(c, tri_at(c, rule, "premises.first"), seen, &r) == TRI_ENTAILED);
    tri_arena_free(a);
    tri_content_free(c);
}

/* docs/GUIDE.md: every cue block in it is one content file, which loads and
 * gives the results the guide quotes. */
void test_docs_guide(void)
{
    FILE *f = fopen("docs/GUIDE.md", "rb");
    if (!f) { fprintf(stderr, "    (skipped: docs/GUIDE.md not found)\n"); return; }
    static char doc[100000], src[50000];
    size_t n = fread(doc, 1, sizeof doc - 1, f), len = 0;
    fclose(f);
    doc[n] = 0;
    for (const char *p = doc; (p = strstr(p, "```cue\n")); ) {
        p += 7;
        const char *e = strstr(p, "\n```");
        if (!e) break;
        len += (size_t) snprintf(src + len, sizeof src - len, "%.*s\n", (int) (e - p), p);
        p = e + 4;
    }
    CHECK(len > 1000 && len < sizeof src);
    const char *names[] = { "guide.tri" };
    const char *srcs[] = { src };
    TriContent *c = load(names, srcs, 1);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); return; }
    CHECK(has_diag(c, "warning: hammer: conflicting defaults for material from #Wooden, #Metal; both dropped", 0));
    CHECK_STR(tri_doc(c, "#Physical"), "Anything with mass and a material.");
    /* §4–5: specs, defaults, the inspector */
    CHECK_STR(printed(c, tri_spec(c, "wrench_19")), "#Wrench & { mass: 850g, material: \"steel\", size: 19mm, wear: 0 }");
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "hammer"), "material")), "#Material");
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "mallet"), "material")), "\"ash\"");
    char buf[2048];
    tri_inspect(c, "mallet", buf, sizeof buf);
    CHECK_CONTAINS(buf, "material: \"ash\"  <- default from the instance");
    CHECK_CONTAINS(buf, "wear: 0  <- default from #Tool");
    /* §6: four nuts */
    TriArena *a = tri_arena_new();
    static const char *nuts[] = {
        "#Nut & { mass: 39g, material: \"brass\", size: 12.4mm, state: \"loose\" }",
        "#Nut & { mass: 9g, material: \"brass\", size: 12mm, state: \"loose\" }",
        "#Nut & { mass: 10g, material: \"brass\", size: 13.1mm, state: \"loose\" }",
        "#Nut & { mass: 5g, material: \"steel\", size: 16mm, state: \"loose\" }",
    };
    for (uint64_t seed = 1; seed <= 4; seed++) CHECK_STR(printed(c, tri_construct(c, "nut", seed, a)), nuts[seed - 1]);
    CHECK(tri_spec_variation_count(c, "wrench_19") == 1);
    /* §7: variants, and a disjunction type */
    CHECK(tri_pattern_variant_count(c, "spanner") == 3);
    CHECK(tri_construct(c, "file_tool", 1, a) != NULL);
    /* §8: the matching table, the explainer, and the family index */
    static const struct { const char *nut; TriMatch m; const char *residuals; } rows[] = {
        { "#Nut & { size: 19mm, state: \"tight\" }", TRI_ENTAILED, "" },
        { "#Nut & { size: >=17mm & <=21mm, state: \"tight\" }", TRI_UNKNOWN, "target.size " },
        { "#Nut & { size: 13mm }", TRI_INCOMPATIBLE, "" },
        { "#Nut", TRI_UNKNOWN, "target.size target.state " },
    };
    char expr[256];
    for (size_t i = 0; i < 4; i++) {
        snprintf(expr, sizeof expr, "#Roles & { instrument: #Wrench & { size: 19mm }, target: %s }", rows[i].nut);
        const TriNode *d = tri_value(c, expr, a, NULL, 0);
        TriMatchResult r;
        CHECK(tri_match_instance(c, "loosen", d, &r) == rows[i].m);
        char res[256] = "";
        for (size_t k = 0; k < r.nresidual; k++) { strcat(res, r.residual[k]); strcat(res, " "); }
        CHECK_STR(res, rows[i].residuals);
        if (rows[i].m == TRI_INCOMPATIBLE) {
            CHECK_STR(r.failure.path, "target.size");
            CHECK_STR(r.failure.right, "13mm");
        }
        if (i == 1) {
            tri_explain_instance(c, "loosen", d, buf, sizeof buf);
            CHECK_CONTAINS(buf, "result: unknown\nbindings:\n  $s at instrument.size = 19mm\nresiduals: target.size");
        }
    }
    TriIndex *ix = tri_family_index(c, "operations");
    CHECK(ix && tri_index_count(ix) == 2);
    const TriNode *loose = tri_value(c, "#Roles & { instrument: #Wrench & { size: 19mm }, target: #Nut & { state: \"loose\" } }", a, NULL, 0);
    size_t out[4];
    CHECK(ix && tri_index_candidates(ix, loose, out, 4) == 1);
    if (ix) CHECK_STR((const char *) tri_index_tag(ix, out[0]), "tighten");
    /* §9–10: arithmetic and clauses */
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "breaker"), "torque")), "40Nm");
    const TriNode *sol[8];
    int trunc;
    CHECK(tri_solve(c, tri_value(c, "#Way & { from: \"kitchen\" }", a, NULL, 0), 10, sol, 8, a, &trunc) == 3 && !trunc);
    CHECK_STR(printed(c, sol[0]), "#Way & { from: \"kitchen\", length: 3000mm, to: \"yard\" }");
    CHECK_STR(printed(c, sol[2]), "#Way & { from: \"kitchen\", length: 1000mm, to: \"hall\" }");
    CHECK(tri_solve(c, tri_value(c, "#Way & { from: \"kitchen\", length: <=2m }", a, NULL, 0), 10, sol, 8, a, &trunc) == 2);
    tri_arena_free(a);
    tri_content_free(c);
}

/* --- from an independent audit of the spec against the code ---------------------------------- */

void test_tag_residuals_and_bindings(void)
{
    /* the residual is the tagged path whose value is still open, whatever the feature order */
    TriContent *c = load1_ok(
        "#Fastener: { size: length }\n"
        "#R: { target: #Fastener, tool: #Fastener }\n"
        "op: #R & { target: { size: $s }, tool: { size: $s } }\n"
        "#Coat: { colour: \"dark\" | \"light\" }\n\"dark\": \"grey\" | \"black\"\n"
        "#WoolCoat: #Coat & { grade: int }\n#P: { coat: #Coat, a: _, b: _ }\n");
    TriArena *a = tri_arena_new();
    const TriNode *d = tri_value(c, "#R & { target: { size: >=17mm & <=24mm }, tool: { size: 19mm } }", a, NULL, 0);
    TriMatchResult r;
    CHECK(tri_match_instance(c, "op", d, &r) == TRI_UNKNOWN);
    CHECK(r.nresidual == 1);
    CHECK_STR(r.residual[0], "target.size");
    CHECK_STR(printed(c, tri_binding(c, "op", "s", d)), "19mm");
    char buf[1024];
    tri_explain_instance(c, "op", d, buf, sizeof buf);
    CHECK_CONTAINS(buf, "$s at tool.size = 19mm");
    /* a too-general type: the open field below it shows too */
    const TriNode *p = tri_value(c, "#P & { coat: #WoolCoat & { colour: \"grey\" } }", a, NULL, 0);
    const TriNode *q = tri_value(c, "#P & { coat: { colour: \"dark\" } }", a, NULL, 0);
    CHECK(tri_match(c, p, q, &r) == TRI_UNKNOWN);
    CHECK(r.nresidual == 2);
    CHECK_STR(r.residual[0], "coat");
    CHECK_STR(r.residual[1], "coat.colour");
    /* equal but separate structures under one tag: whether they are one thing is what is open */
    const TriNode *pt = tri_value(c, "#P & { a: $x, b: $x }", a, NULL, 0);
    const TriNode *two = tri_value(c, "#P & { a: #Coat & { colour: \"grey\" }, b: #Coat & { colour: \"grey\" } }", a, NULL, 0);
    CHECK(tri_match(c, pt, two, &r) == TRI_UNKNOWN);
    CHECK(r.nresidual == 2);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_alternative_chosen_by_value(void)
{
    TriContent *c = load1_ok("#Shape: { kind: \"round\", r: length } | { kind: \"square\", side: length }\n"
                             "#Box: { shape: #Shape }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    const TriNode *s = tri_value(c, "#Shape & { kind: \"round\" }", a, err, sizeof err);
    CHECK(s != NULL);
    CHECK_STR(printed(c, tri_at(c, s, "r")), "length");
    CHECK(!tri_value(c, "#Shape & { kind: \"oval\" }", a, err, sizeof err));
    CHECK_CONTAINS(err, "no alternative of #Shape fits");
    /* unification resolves it too, so matching the alternative is entailed */
    TriFailure f;
    const TriNode *u = tri_unify(c, tri_value(c, "#Box", a, NULL, 0), tri_value(c, "#Box & { shape: { kind: \"square\" } }", a, NULL, 0), a, &f);
    CHECK(u && tri_at(c, u, "shape.side") != NULL);
    TriMatchResult r;
    CHECK(tri_match(c, tri_value(c, "#Box & { shape: { side: length } }", a, NULL, 0), u, &r) == TRI_ENTAILED);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_all_conflicts(void)
{
    TriContent *c = load1_ok("#Coat: { colour: \"grey\" | \"brown\" }\n#Person: { coat: #Coat, height: length, name: text }\n");
    TriArena *a = tri_arena_new();
    const TriNode *x = tri_value(c, "#Person & { coat: { colour: \"grey\" }, height: 1.8m, name: \"a\" }", a, NULL, 0);
    const TriNode *y = tri_value(c, "#Person & { coat: { colour: \"brown\" }, height: 1.5m, name: \"a\" }", a, NULL, 0);
    char paths[8][256];
    size_t n = tri_conflicts(c, x, y, paths, 8);
    CHECK(n == 2);
    CHECK_STR(paths[0], "coat.colour");
    CHECK_STR(paths[1], "height");
    CHECK(tri_conflicts(c, x, x, paths, 8) == 0);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_compaction(void)
{
    /* copying live descriptions into a fresh arena and freeing the old one changes nothing observable */
    TriContent *c = load1_ok("#Coat: { colour: \"grey\" | \"brown\" }\n#Person: { coat: #Coat, mother: #Person, l: _, r: _ }\n");
    TriArena *old = tri_arena_new();
    const TriNode *x = tri_value(c, "#Person & { coat: { colour: \"grey\" }, mother: { coat: { colour: \"brown\" } }, l: $t & 4, r: $t }", old, NULL, 0);
    const TriNode *pat = tri_value(c, "#Person & { mother: { coat: { colour: \"brown\" } } }", old, NULL, 0);
    char before[1024], save_before[2048];
    snprintf(before, sizeof before, "%s", printed(c, x));
    char *t = tri_save(c, x, 0);
    snprintf(save_before, sizeof save_before, "%s", t);
    free(t);
    TriArena *fresh = tri_arena_new();
    const TriNode *y = tri_copy(c, x, fresh);
    const TriNode *p2 = tri_copy(c, pat, fresh);
    tri_arena_free(old);
    CHECK_STR(printed(c, y), before);
    CHECK(tri_at(c, y, "l") == tri_at(c, y, "r"));
    t = tri_save(c, y, 0);
    CHECK_STR(t, save_before);
    free(t);
    TriMatchResult r;
    CHECK(tri_match(c, p2, y, &r) == TRI_ENTAILED);
    tri_arena_free(fresh);
    tri_content_free(c);
}

void test_fixed_and_int(void)
{
    TriContent *c = load1_ok("#K: { k: fixed & >=0 & <=1, n: fixed }\nk: #K & { k: 1, n: 2 }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    CHECK_STR(printed(c, tri_pattern(c, "k")), "#K & { k: 1, n: 2 }");
    CHECK(tri_value(c, "#K & { k: 0.25 }", a, err, sizeof err) != NULL);
    CHECK(!tri_value(c, "#K & { k: 2 }", a, err, sizeof err));
    tri_arena_free(a);
    tri_content_free(c);
}

void test_runtime_is_strict(void)
{
    TriContent *c = load1_ok("#H: { h: int, m: length }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    CHECK(!tri_value(c, "#H & { h: *5 | int }", a, err, sizeof err));
    CHECK_CONTAINS(err, "a default (*) has no meaning in a runtime value");
    CHECK(!tri_value(c, "#H & { m: 1m | 2m }", a, err, sizeof err));
    CHECK_CONTAINS(err, "separate numbers");
    CHECK(tri_value(c, "#H & { m: >=1m & <=2m | >=2m & <=3m }", a, err, sizeof err) != NULL);   /* a range */
    tri_arena_free(a);
    tri_content_free(c);
    c = load1("#T: { m: \"steel\" | \"oak\" }\nx: #T & { m: \"steel\" | \"oak\" } @vary(1, 0)\n");
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "x: @vary(1, 0) after a declaration weights its top-level alternatives", 1));
    tri_content_free(c);
}

void test_build_log_and_clash_hint(void)
{
    TriContent *c = load1_ok(
        "#A: {}\n#B: {}\n#C: #A & #B\n#D: #A & #B\n"
        "#F: { f: \"x\" | \"y\" }\n#P: #F & { f: *\"x\" }\n#Q: #F & { f: *\"y\" }\n#M: { @component(M)\n g: int @field(content)\n}\n"
        "w: #P & #Q & #M & { g: 1 }\n#S: { s: { a: 1 } | { b: 2 } }\n#L: { l: [...#A] }\n");
    int meet = 0, conj = 0, disj = 0, alt = 0, list = 0, dropped = 0;
    for (size_t i = 0; i < tri_log_count(c); i++) {
        const char *m = tri_log_message(c, i);
        meet += strstr(m, "meet type glb[#C,#D], below #A, #B") != NULL;
        conj += strstr(m, "conjunction type #M & #P & #Q") != NULL;
        disj += strstr(m, "disjunction type ({ a: 1 } | { b: 2 })") != NULL;
        alt += strstr(m, "alternative type ({ a: 1 } | { b: 2 })/{ a: 1 }") != NULL;
        list += strstr(m, "typed list type [...#A]") != NULL;
        dropped += strstr(m, "dropped defaults: w: f from #P, #Q") != NULL;
    }
    CHECK(meet == 1 && conj == 1 && disj == 1 && alt == 1 && list == 1 && dropped == 1);
    tri_content_free(c);
    c = load1("#Sized: { size: length }\n#Tool: { size: length }\n");
    CHECK(has_diag(c, "feature 'size' is introduced by both #Sized (f.tri:1) and #Tool (f.tri:2); declare it once on a new common supertype (say #HasSize)", 1));
    tri_content_free(c);
    c = load1("#Thing: {}\n#Sized: #Thing & { size: length }\n#Tool: #Thing & { size: length }\n");
    CHECK(has_diag(c, "declare it once on #Thing, which both inherit from", 1));
    tri_content_free(c);
}

void test_previously_untested(void)
{
    /* additions may not add supertypes */
    TriContent *c = load1("#A: {}\n#B: {}\n#C: #A\n#C: #B\n");
    CHECK(has_diag(c, "supertypes of #C are already declared at f.tri:3; additions may not add supertypes", 1));
    tri_content_free(c);
    /* overlapping and adjacent ranges are their hull */
    c = load1_ok("#H: { h: >=1 & <=3 | >=4 & <=6, i: 1 | 2 | 3 }\n");
    TriArena *a = tri_arena_new();
    CHECK_STR(printed(c, tri_at(c, tri_value(c, "#H", a, NULL, 0), "h")), ">=1 & <=6");
    CHECK_STR(printed(c, tri_at(c, tri_value(c, "#H", a, NULL, 0), "i")), ">=1 & <=3");
    tri_content_free(c);
    /* an instance's default beats a type's */
    c = load1_ok("#H: { h: *5 | int }\nx: #H & { h: *7 | int }\n");
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "x"), "h")), "7");
    tri_content_free(c);
    /* a save that no longer fits its types is refused, with the reason */
    c = load1_ok("#P: { height: length }\n");
    char *t = tri_save(c, tri_value(c, "#P & { height: 1.8m }", a, NULL, 0), 0);
    tri_content_free(c);
    c = load1_ok("#P: { height: length & <=1m }\n");
    char err[256];
    CHECK(!tri_restore(c, t, a, err, sizeof err));
    CHECK_CONTAINS(err, "no longer fits: 1800mm vs <=1000mm");
    free(t);
    tri_content_free(c);
    /* quick-check paths learned from failures: most frequent first, unknown paths skipped */
    c = load1_ok("#S: { a: int, b: int }\n");
    const char *fails[] = { "a", "(root)", "b", "b", "zz", "b", "a" };
    TriQuickCheck *qc = tri_qc_from_failures(c, fails, 7, 3);
    CHECK(tri_qc_size(qc) == 3);
    CHECK_STR(tri_qc_path(qc, 1), "b");
    CHECK_STR(tri_qc_path(qc, 2), "a");
    tri_qc_free(qc);
    tri_arena_free(a);
    tri_content_free(c);
}

/* --- arithmetic and definite clauses (built on request; the spec had deferred them) ------------- */

void test_arithmetic(void)
{
    TriContent *c = load1_ok(
        "#Lever: { @component(Lever)\n"
        "    force: $f & force & >=1N & <=100N @field(content)\n"
        "    arm: $a & length & >=0.1m & <=1m @field(content)\n"
        "    torque: $f * $a\n"
        "}\n"
        "#Box: { w: $w & length, h: $h & length, girth: ($w + $h) * 2, ratio: $w / $h, half: $w / 2 }\n"
        "bar: #Lever & { force: 50N, arm: 0.3m }\n"
        "any: #Lever\n"
        "#K: { k: fixed, n: int, m: $k * $n & fixed, k: $k, n: $n }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    /* constants fold; constraints compute what their arguments allow */
    CHECK_STR(printed(c, tri_at(c, tri_spec(c, "bar"), "torque")), "15Nm");
    CHECK_STR(printed(c, tri_at(c, tri_pattern(c, "any"), "torque")), ">=0.1Nm & <=100Nm");
    /* a derived field is never drawn: construction computes it */
    CHECK(tri_spec_variation_count(c, "any") == 2);
    for (uint64_t seed = 1; seed <= 20; seed++) {
        const TriNode *w = tri_construct(c, "any", seed, a);
        int64_t flo, fhi, alo, ahi, tlo, thi;
        tri_node_interval(tri_at(c, w, "force"), &flo, &fhi);
        tri_node_interval(tri_at(c, w, "arm"), &alo, &ahi);
        tri_node_interval(tri_at(c, w, "torque"), &tlo, &thi);
        CHECK(flo == fhi && alo == ahi);
        /* the exact product, or the one-quantum interval holding it */
        CHECK(tlo * 10000 <= flo * alo && thi * 10000 >= flo * alo && thi - tlo <= 1);
    }
    /* runtime values propagate, and contradictions fail */
    const TriNode *b = tri_value(c, "#Box & { w: 1m, h: 2mm }", a, err, sizeof err);
    CHECK_STR(printed(c, tri_at(c, b, "girth")), "2004mm");
    CHECK_STR(printed(c, tri_at(c, b, "ratio")), "500");
    CHECK_STR(printed(c, tri_at(c, b, "half")), "500mm");
    /* open arguments: the result waits (an open interval), and narrows as they do */
    const TriNode *open = tri_value(c, "#Box & { w: >=1m & <=2m }", a, err, sizeof err);
    CHECK_STR(printed(c, tri_at(c, open, "girth")), "length");
    const TriNode *closed = tri_value(c, "#Box & { h: 1m }", a, NULL, 0);
    TriFailure f;
    const TriNode *u = tri_unify(c, open, closed, a, &f);
    CHECK_STR(printed(c, tri_at(c, u, "girth")), ">=4000mm & <=6000mm");
    CHECK(!tri_value(c, "#Lever & { force: 10N, arm: 1m, torque: 3Nm }", a, err, sizeof err));
    CHECK_CONTAINS(err, "arithmetic at torque");
    CHECK_STR(printed(c, tri_at(c, tri_value(c, "#K & { k: 0.5, n: 3 }", a, NULL, 0), "m")), "1.5");
    tri_arena_free(a);
    tri_content_free(c);
    /* errors at load: dimensions, unbound tags */
    c = load1("#B: { w: $w & length, m: $m & mass, s: $w + $m }\n");
    CHECK(!tri_content_ok(c));
    CHECK(has_diag(c, "adding or subtracting needs the same dimension", 1));
    tri_content_free(c);
    c = load1("#B: { w: length, s: $nope * 2 }\n");
    CHECK(has_diag(c, "the tag $nope in arithmetic is not bound to a field", 1));
    tri_content_free(c);
}

static const char *graph_src =
    "#Place: \"kitchen\" | \"hall\" | \"cellar\" | \"yard\"\n"
    "#Link: { from: #Place, to: #Place }\n#Weighted: #Link & { d: length }\n"
    "#Edge: #Weighted\n#Reach: #Link\n#Dist: #Weighted\n"
    "e1: #Fact & { head: #Edge & { from: \"kitchen\", to: \"hall\", d: 4m } }\n"
    "e2: #Fact & { head: #Edge & { from: \"hall\", to: \"cellar\", d: 3m } }\n"
    "e3: #Fact & { head: #Edge & { from: \"cellar\", to: \"yard\", d: 10m } }\n"
    "r1: #Clause & { head: #Reach & { from: $x, to: $y }, body: [#Edge & { from: $x, to: $y }] }\n"
    "r2: #Clause & { head: #Reach & { from: $x, to: $z }, body: [#Edge & { from: $x, to: $y }, #Reach & { from: $y, to: $z }] }\n"
    "d1: #Clause & { head: #Dist & { from: $x, to: $y, d: $d }, body: [#Edge & { from: $x, to: $y, d: $d }] }\n"
    "d2: #Clause & { head: #Dist & { from: $x, to: $z, d: $a + $b },\n"
    "                body: [#Edge & { from: $x, to: $y, d: $a }, #Dist & { from: $y, to: $z, d: $b }] }\n";

void test_clauses(void)
{
    TriContent *c = load1_ok(graph_src);
    TriArena *a = tri_arena_new();
    const TriNode *sol[16];
    int trunc;
    size_t n = tri_solve(c, tri_value(c, "#Reach & { from: \"kitchen\" }", a, NULL, 0), 20, sol, 16, a, &trunc);
    CHECK(n == 3 && !trunc);
    CHECK_STR(printed(c, sol[0]), "#Reach & { from: \"kitchen\", to: \"hall\" }");
    CHECK_STR(printed(c, sol[2]), "#Reach & { from: \"kitchen\", to: \"yard\" }");
    CHECK(tri_solve(c, tri_value(c, "#Reach & { to: \"kitchen\" }", a, NULL, 0), 20, sol, 16, a, &trunc) == 0);
    CHECK(tri_solve(c, tri_value(c, "#Reach", a, NULL, 0), 20, sol, 16, a, &trunc) == 6);
    /* arithmetic in a clause waits for its arguments through the recursion */
    n = tri_solve(c, tri_value(c, "#Dist & { from: \"kitchen\", to: \"yard\" }", a, NULL, 0), 20, sol, 16, a, &trunc);
    CHECK(n == 1);
    CHECK_STR(printed(c, tri_at(c, sol[0], "d")), "17000mm");
    n = tri_solve(c, tri_value(c, "#Dist & { from: \"kitchen\", d: <=8m }", a, NULL, 0), 20, sol, 16, a, &trunc);
    CHECK(n == 2);
    /* the depth limit cuts a cycle short, and says so */
    tri_arena_free(a);
    tri_content_free(c);
    char src[4096];
    snprintf(src, sizeof src, "%se4: #Fact & { head: #Edge & { from: \"yard\", to: \"kitchen\", d: 20m } }\n", graph_src);
    c = load1_ok(src);
    a = tri_arena_new();
    n = tri_solve(c, tri_value(c, "#Reach & { from: \"kitchen\" }", a, NULL, 0), 10, sol, 16, a, &trunc);
    CHECK(n >= 4 && trunc);
    /* a clause pattern is an ordinary instance: content without clauses keeps head and body free */
    tri_arena_free(a);
    tri_content_free(c);
    c = load1_ok("#Tool: { head: \"flat\" | \"round\", body: length }\n");
    a = tri_arena_new();
    CHECK(tri_solve(c, tri_value(c, "#Tool", a, NULL, 0), 5, sol, 4, a, &trunc) == 0);
    tri_arena_free(a);
    tri_content_free(c);
}

/* --- the decided open questions ------------------------------------------------------------ */

void test_path_keyed_variation(void)
{
    /* adding a field to a blueprint leaves the other fields' draws alone */
    const char *v1 = "#Thing: { @component(Thing)\n colour: \"red\" | \"green\" | \"blue\" @field(content)\n"
                     " size: length & >=1mm & <=99mm @field(content)\n}\nt: #Thing\n";
    const char *v2 = "#Thing: { @component(Thing)\n colour: \"red\" | \"green\" | \"blue\" @field(content)\n"
                     " grip: \"bare\" | \"wrapped\" @field(content)\n"
                     " size: length & >=1mm & <=99mm @field(content)\n}\nt: #Thing\n";
    TriContent *a1 = load1_ok(v1), *a2 = load1_ok(v2);
    TriArena *a = tri_arena_new();
    int same = 0;
    for (uint64_t seed = 1; seed <= 30; seed++) {
        const TriNode *x = tri_construct(a1, "t", seed, a), *y = tri_construct(a2, "t", seed, a);
        char cx[64], sx[64];
        snprintf(cx, sizeof cx, "%s", printed(a1, tri_at(a1, x, "colour")));
        snprintf(sx, sizeof sx, "%s", printed(a1, tri_at(a1, x, "size")));
        if (!strcmp(cx, printed(a2, tri_at(a2, y, "colour"))) && !strcmp(sx, printed(a2, tri_at(a2, y, "size")))) same++;
    }
    CHECK(same == 30);
    tri_content_free(a1);
    tri_content_free(a2);
    /* a range peaked by @vary(mode: v) */
    TriContent *c = load1_ok("#R: { @component(R)\n size: length & >=10mm & <=20mm @field(content) @vary(mode: 11mm)\n}\nr: #R\n");
    int low = 0;
    int64_t sum = 0;
    for (uint64_t seed = 1; seed <= 400; seed++) {
        int64_t lo, hi;
        tri_node_interval(tri_at(c, tri_construct(c, "r", seed, a), "size"), &lo, &hi);
        CHECK(lo == hi && lo >= 100 && lo <= 200);
        sum += lo;
        if (lo < 150) low++;
    }
    CHECK(low > 240);                          /* the peak is near the bottom */
    CHECK(sum / 400 > 125 && sum / 400 < 148);  /* the mean (10 + 11 + 20) / 3 = 13.7 mm */
    tri_arena_free(a);
    tri_content_free(c);
}

void test_arithmetic_exponents_and_backwards(void)
{
    TriContent *c = load1_ok(
        "#Box: { w: $w & length, h: $h & length, total: $w + $h, half: $w / 2, triple: $h * 3 }\n"
        "#Cube: { l: $l & length, vol: $l * $l * $l, f: $f & force, work: $f * $l & torque }\n");
    TriArena *a = tri_arena_new();
    /* backwards: a known total and width give the height; scaling inverts */
    const TriNode *b = tri_value(c, "#Box & { total: 3m, w: 1m }", a, NULL, 0);
    CHECK_STR(printed(c, tri_at(c, b, "h")), "2000mm");
    CHECK_STR(printed(c, tri_at(c, tri_value(c, "#Box & { triple: 3m }", a, NULL, 0), "h")), "1000mm");
    const TriNode *hb = tri_value(c, "#Box & { half: 500mm }", a, NULL, 0);
    int64_t lo, hi;
    tri_node_interval(tri_at(c, hb, "w"), &lo, &hi);
    CHECK(lo <= 10000 && hi >= 10000 && hi - lo <= 4);
    CHECK_STR(printed(c, tri_at(c, tri_value(c, "#Box & { total: >=1m & <=2m, w: >=0.5m }", a, NULL, 0), "h")), "<=1500mm");
    /* exponents: an area on the way to a volume, force times length as torque */
    const TriNode *cu = tri_value(c, "#Cube & { l: 2m, f: 3N }", a, NULL, 0);
    CHECK_STR(printed(c, tri_at(c, cu, "vol")), "8000000mL");
    CHECK_STR(printed(c, tri_at(c, cu, "work")), "6Nm");
    tri_arena_free(a);
    tri_content_free(c);
    c = load1("#D: { m: $m & mass, v: $v & volume, d: $m / $v }\n");
    CHECK(has_diag(c, "no quantity has this dimension", 1));
    tri_content_free(c);
}

void test_clause_solutions_distinct(void)
{
    char src[4096];
    snprintf(src, sizeof src, "%se4: #Fact & { head: #Edge & { from: \"yard\", to: \"kitchen\", d: 20m } }\n", graph_src);
    TriContent *c = load1_ok(src);
    TriArena *a = tri_arena_new();
    const TriNode *sol[16];
    int trunc;
    size_t n = tri_solve(c, tri_value(c, "#Reach & { from: \"kitchen\" }", a, NULL, 0), 14, sol, 16, a, &trunc);
    CHECK(n == 4 && trunc);                  /* each place once, though the cycle repeats them */
    tri_arena_free(a);
    tri_content_free(c);
}

void test_component_header(void)
{
    TriContent *c = load1_ok(
        "#Material: \"steel\" | \"brass\"\n"
        "#Tool: { @component(Tool)\n mass: mass @field(content, saved)\n material: #Material @field(content)\n"
        " lit: bool @field(saved)\n label: text\n owner: ref\n finish: \"black\" | \"dull\"\n}\n");
    char buf[4096];
    size_t n = tri_component_header(c, "BG", buf, sizeof buf);
    CHECK(n > 0 && n < sizeof buf);
    CHECK_CONTAINS(buf, "#define BG_CONTENT_HASH 0x");
    CHECK_CONTAINS(buf, "int64_t         mass;    /* mass, in quanta of 1g; content, saved */");
    CHECK_CONTAINS(buf, "uint32_t        material;    /* #Material: a type ID; content */");
    CHECK_CONTAINS(buf, "bool            lit;");
    CHECK_CONTAINS(buf, "const char *    label;");
    CHECK_CONTAINS(buf, "uint64_t        owner;");
    CHECK_CONTAINS(buf, "} BGTool;");
    CHECK_CONTAINS(buf, "BG_MATERIAL_STEEL = ");
    CHECK_CONTAINS(buf, "BG_TOOL_FINISH_BLACK = ");
    /* the field registry, for reading and writing any component generically */
    CHECK_CONTAINS(buf, "#ifdef BG_COMPONENT_REGISTRY");
    CHECK(strstr(buf, "} BGFieldInfo;") < strstr(buf, "#ifdef BG_COMPONENT_REGISTRY"));
    CHECK_CONTAINS(buf, "{ \"mass\", offsetof(BGTool, mass), BG_VALUE_QUANTITY, \"mass\", \"content, saved\" },");
    CHECK_CONTAINS(buf, "{ \"material\", offsetof(BGTool, material), BG_VALUE_TYPE, \"#Material\", \"content\" },");
    CHECK_CONTAINS(buf, "{ \"label\", offsetof(BGTool, label), BG_VALUE_TEXT, \"text\", \"\" },");
    CHECK_CONTAINS(buf, "#define BG_COMPONENT_COUNT 1");
    CHECK_CONTAINS(buf, "{ \"Tool\", \"#Tool\", sizeof(BGTool), 6, BGTool_fields },");
    tri_content_free(c);
    /* a structure-valued field declares TriNode before using it; an empty component still has a member */
    c = load1_ok("#Shape: { w: length }\n#Tool: { @component(Tool)\n shape: #Shape\n bent: *false | true\n}\n#Mark: { @component(Mark) }\n");
    tri_component_header(c, "BG", buf, sizeof buf);
    const char *td = strstr(buf, "typedef struct TriNode TriNode;"), *st = strstr(buf, "const TriNode * shape;");
    CHECK(td && st && td < st);
    CHECK_CONTAINS(buf, "char            unused_;");
    CHECK_CONTAINS(buf, "bool            bent;");
    /* raw quanta, formatted for traces and inspectors */
    tri_format_quantity("mass", 850, buf, sizeof buf);
    CHECK_STR(buf, "850g");
    tri_format_quantity("length", 195, buf, sizeof buf);
    CHECK_STR(buf, "19.5mm");
    tri_format_quantity("int", 7, buf, sizeof buf);
    CHECK_STR(buf, "7");
    tri_format_quantity("nonesuch", 7, buf, sizeof buf);
    CHECK_STR(buf, "7");
    tri_content_free(c);
}

void test_failure_recording_and_sizes(void)
{
    TriContent *c = load1_ok(
        "#Nut: { size: length, state: \"loose\" | \"tight\" }\n#Roles: { target: #Nut }\n"
        "tighten: #Roles & { target: { state: \"loose\" } } @family(ops)\n"
        "big: #Roles & { target: { size: >=30mm } } @family(ops)\n");
    TriArena *a = tri_arena_new();
    tri_record_failures(c, 1);
    const char *ds[] = { "#Roles & { target: { state: \"tight\", size: 10mm } }",
                         "#Roles & { target: { state: \"tight\", size: 40mm } }",
                         "#Roles & { target: { state: \"loose\", size: 10mm } }" };
    TriMatchResult r;
    for (int i = 0; i < 3; i++) {
        const TriNode *d = tri_value(c, ds[i], a, NULL, 0);
        tri_match_instance(c, "tighten", d, &r);
        tri_match_instance(c, "big", d, &r);
    }
    char buf[256];
    tri_family_suggest_quickcheck(c, "ops", 4, buf, sizeof buf);
    CHECK_STR(buf, "@quickcheck(target.size, target.state)");
    tri_family_suggest_quickcheck(c, "ops", 1, buf, sizeof buf);
    CHECK_STR(buf, "@quickcheck(target.size)");
    /* sizes a knowledge store measures */
    const TriNode *d = tri_value(c, ds[0], a, NULL, 0);
    CHECK(tri_node_count(d) == 4);
    CHECK(tri_arena_bytes(a) > 0);
    tri_arena_free(a);
    tri_content_free(c);
}

void test_migration(void)
{
    TriContent *old = load1_ok("#Coat: { colour: \"grey\" | \"brown\" }\n#Person: { coat: #Coat, name: text }\n");
    TriContent *new = load1_ok("#Coat: { colour: \"grey\" | \"brown\" | \"navy\", buttons: int }\n#Person: { coat: #Coat, name: text, age: int }\n");
    TriArena *a = tri_arena_new();
    char err[256];
    const TriNode *p = tri_value(old, "#Person & { coat: { colour: \"grey\" }, name: \"Ines\" }", a, NULL, 0);
    const TriNode *q = tri_migrate(old, new, p, a, err, sizeof err);
    CHECK(q != NULL);
    CHECK_STR(printed(new, q), "#Person & { age: int, coat: #Coat & { buttons: int, colour: \"grey\" }, name: \"Ines\" }");
    tri_arena_free(a);
    tri_content_free(old);
    tri_content_free(new);
}


/* Packages (CONTENT_LANGUAGE.md decision 12): a file's `package` scopes the
 * types, blueprints and components it declares; features stay global. Two
 * packages each declare a #Wrench and a `wrench`; inside a package a plain
 * name is its own, else the root's; across, it is qualified. */
static int diag_says(TriContent *c, const char *text)
{
    for (size_t i = 0; i < tri_diag_count(c); i++)
        if (strstr(tri_diag_message(c, i), text)) return 1;
    return 0;
}

void test_packages(void)
{
    const char *names[] = { "core.tri", "tools.tri", "kitchen.tri" };
    const char *srcs[] = {
        "#Thing: { mass: mass }\n#Tool: #Thing & {}\n",
        "package tools\n"
        "#Wrench: #Tool & { size: length }\n"
        "wrench: #Wrench & { mass: 400g, size: 19mm }\n",
        "package kitchen\n"
        "#Wrench: #Tool & { @component(Gadget)\n handle: length @field(content) }\n"
        "wrench: #Wrench & { mass: 90g, handle: 120mm }\n"
        "spare: tools.#Wrench & { mass: 500g, size: 22mm }\n",
    };
    TriContent *c = load(names, srcs, 3);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) dump_diags(c);
    /* two types of one name, one in each package; none in the root */
    TriType tw = tri_type_named(c, "tools.#Wrench"), kw = tri_type_named(c, "kitchen.#Wrench");
    CHECK(tw != kw && tri_type_named(c, "#Wrench") == tri_type_named(c, "#Nonesuch"));
    /* a plain name inside a package is its own */
    CHECK(tri_spec(c, "tools.wrench") && tri_spec(c, "kitchen.wrench") && ! tri_spec(c, "wrench"));
    CHECK_STR(tri_type_name(c, tri_node_type(tri_spec(c, "kitchen.wrench"))), "kitchen.#Wrench");
    /* across, qualified: the kitchen's spare is a tools wrench */
    const TriNode *spare = tri_spec(c, "kitchen.spare");
    CHECK(spare && !strcmp(tri_type_name(c, tri_node_type(spare)), "tools.#Wrench"));
    int64_t lo, hi;
    CHECK(tri_node_interval(tri_at(c, spare, "size"), &lo, &hi) && lo == 220);
    /* what prints parses back */
    TriArena *a = tri_arena_new();
    char err[256];
    CHECK(tri_value(c, "tools.#Wrench & { size: 19mm }", a, err, sizeof err) != NULL);
    CHECK(!tri_value(c, "#Wrench & { size: 19mm }", a, err, sizeof err));
    tri_arena_free(a);
    /* a packaged component's generated names carry its package */
    char buf[8192];
    tri_component_header(c, "BG", buf, sizeof buf);
    CHECK_CONTAINS(buf, "} BGkitchen_Gadget;");
    CHECK_CONTAINS(buf, "{ \"kitchen.Gadget\", \"kitchen.#Wrench\", sizeof(BGkitchen_Gadget)");
    tri_content_free(c);

    /* features take no package; a declaration is named in its own files; an
     * unknown qualified name is unknown; the root sees no package's names */
    const char *bad1[] = { "package tools\n#Wrench: { tools.size: length }\n" };
    const char *n1[] = { "a.tri" };
    c = load(n1, bad1, 1);
    CHECK(!tri_content_ok(c) && diag_says(c, "features are global"));
    tri_content_free(c);
    const char *bad2[] = { "tools.#Wrench: { size: length }\n" };
    c = load(n1, bad2, 1);
    CHECK(!tri_content_ok(c) && diag_says(c, "declare it in its package's files"));
    tri_content_free(c);
    const char *bad3[] = { "package tools\n#Wrench: { size: length }\n", "x: kitchen.#Wrench & {}\n" };
    const char *n3[] = { "a.tri", "b.tri" };
    c = load(n3, bad3, 2);
    CHECK(!tri_content_ok(c));
    tri_content_free(c);
    const char *bad4[] = { "package tools\n#Wrench: { size: length }\n", "x: #Wrench & {}\n" };
    c = load(n3, bad4, 2);
    CHECK(!tri_content_ok(c));
    tri_content_free(c);
}
