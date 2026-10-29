/* A synthetic content build shaped like bruggadung's: component types,
 * material and finish mixins with defaults, blueprints with variation and
 * alternatives, and operations matched against descriptions.
 *
 *   cc -std=c11 -O2 -Iinclude bench/content.c build/libtriangle.a -o build/content
 *   ./build/content [blueprints] [constructions per blueprint]
 *
 * Times are process CPU time, so they hold up when the machine is busy. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "triangle.h"

static double cpu_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t);
    return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

typedef struct { char *s; size_t len, cap; } Text;

static void put(Text *t, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
#include <stdarg.h>
static void put(Text *t, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (t->len + (size_t) n + 1 > t->cap) {
        t->cap = (t->len + (size_t) n + 1) * 2;
        t->s = realloc(t->s, t->cap);
    }
    va_start(ap, fmt);
    vsnprintf(t->s + t->len, (size_t) n + 1, fmt, ap);
    va_end(ap);
    t->len += (size_t) n;
}

static uint64_t rng = 12345;
static int pick(int n)
{
    rng = rng * 6364136223846793005ULL + 1442695040888963407ULL;
    return (int) ((rng >> 33) % (uint64_t) n);
}

int main(int argc, char **argv)
{
    int nbp = argc > 1 ? atoi(argv[1]) : 2000;
    int ncon = argc > 2 ? atoi(argv[2]) : 20;
    int nkinds = 40;
    Text t = { 0 };
    put(&t, "#Material: \"steel\" | \"brass\" | \"oak\" | \"ash\" | \"iron\" | \"bone\"\n"
            "#Finish: \"black\" | \"bright\" | \"dull\" | \"rusty\"\n"
            "#Physical: { @component(Physical)\n"
            "    mass: mass @field(content, saved)\n"
            "    material: #Material @field(content, saved) @vary(4, 2, 2, 1, 3, 1)\n"
            "}\n"
            "#Sized: { @component(Sized)\n size: length @field(content, saved)\n}\n"
            "#Worn: { @component(Worn)\n wear: *0 | >=0 & <=1000 @field(saved)\n"
            "    finish: #Finish @field(content)\n}\n"
            "#Hard: { hardness: int & >=0 & <=100 }\n"
            "#Steel: #Hard & { hardness: *50 }\n#Forged: #Steel & { hardness: *62 }\n"
            "#Painted: { paint: *\"black\" | \"red\" | \"green\" }\n"
            "#Oiled: { oil: *true | false }\n"
            "#Grip: { grip: { kind: \"bare\" } | { kind: \"wrapped\", wraps: int & >=1 & <=6 } }\n"
            "#Tool: #Physical & #Sized & #Worn\n");
    for (int k = 0; k < nkinds; k++)
        put(&t, "#Kind%d: #Tool & { size: >=%dmm & <=%dmm, mass: >=%dg & <=%dg }\n",
            k, 5 + k, 40 + 2 * k, 100 + 10 * k, 900 + 40 * k);
    static const char *mixins[] = { "#Forged", "#Steel", "#Painted", "#Oiled", "#Grip" };
    for (int b = 0; b < nbp; b++) {
        int k = pick(nkinds);
        put(&t, "bp%d: #Kind%d", b, k);
        for (int m = 0; m < 5; m++) if (pick(3) == 0) put(&t, " & %s", mixins[m]);
        put(&t, " & {");
        if (pick(2)) put(&t, " size: %dmm,", 5 + k + pick(30));
        if (pick(3) == 0) put(&t, " material: \"%s\",", pick(2) ? "steel" : "oak");
        put(&t, " finish: *\"dull\" | \"bright\" }");
        if (pick(5) == 0) put(&t, " & ({ mass: 300g } | { mass: 500g })");
        put(&t, "\n");
    }
    put(&t, "#Roles: { instrument: #Tool, target: #Tool }\n");
    for (int o = 0; o < 200; o++)
        put(&t, "op%d: #Roles & { instrument: #Kind%d & { size: $s }, target: { size: $s, finish: \"%s\" } } @family(ops)"
                " @quickcheck(instrument.size, target.finish)\n",
            o, pick(nkinds), pick(2) ? "dull" : "rusty");

    const char *names[] = { "bench.tri" };
    const char *srcs[] = { t.s };
    double t0 = cpu_ms();
    TriContent *c = tri_content_load_strings(names, srcs, 1);
    double t1 = cpu_ms();
    if (!tri_content_ok(c)) {
        for (size_t i = 0; i < tri_diag_count(c) && i < 10; i++) fprintf(stderr, "%s\n", tri_diag_message(c, i));
        return 1;
    }
    TriStats st;
    tri_content_stats(c, &st);
    printf("load: %d blueprints, %zu types, %zu instances, %.0f ms (parse %.0f, hierarchy %.0f, expansion %.0f,"
           " instances and specs %.0f); %.3f ms per blueprint\n",
           nbp, st.types, st.instances, t1 - t0, st.parse_ms, st.hierarchy_ms, st.expansion_ms, st.instances_ms,
           st.instances_ms / nbp);

    TriArena *a = tri_arena_new();
    char name[32];
    size_t made = 0;
    double t2 = cpu_ms();
    for (int b = 0; b < nbp; b++) {
        snprintf(name, sizeof name, "bp%d", b);
        for (int s = 0; s < ncon; s++) {
            TriMark m = tri_arena_mark(a);
            if (tri_construct(c, name, (uint64_t) s + 1, a)) made++;
            tri_arena_release(a, m);
        }
    }
    double t3 = cpu_ms();
    printf("construct: %zu entities in %.0f ms = %.1f k per second\n", made, t3 - t2, made / (t3 - t2));

    /* match every operation against constructed tools, through the family index */
    TriIndex *ix = tri_family_index(c, "ops");
    size_t matches = 0, cands = 0, entailed = 0;
    double t4 = cpu_ms();
    for (int b = 0; b + 1 < nbp && b < 2000; b += 2) {
        snprintf(name, sizeof name, "bp%d", b);
        const TriNode *x = tri_construct(c, name, 7, a);
        snprintf(name, sizeof name, "bp%d", b + 1);
        const TriNode *y = tri_construct(c, name, 7, a);
        Text v = { 0 };
        char bx[4096], by[4096];
        tri_print(c, x, bx, sizeof bx);
        tri_print(c, y, by, sizeof by);
        put(&v, "#Roles & { instrument: %s, target: %s }", bx, by);
        const TriNode *d = tri_value(c, v.s, a, NULL, 0);
        free(v.s);
        if (!d) continue;
        size_t out[256];
        size_t n = tri_index_candidates(ix, d, out, 256);
        cands += n;
        for (size_t i = 0; i < n; i++) {
            TriMatchResult r;
            if (tri_match(c, tri_index_pattern(ix, out[i]), d, &r) == TRI_ENTAILED) entailed++;
            matches++;
        }
    }
    double t5 = cpu_ms();
    printf("match: %zu matches after the index (of %d operations), %zu entailed, %.0f ms = %.1f k per second\n",
           matches, 200, entailed, t5 - t4, matches / (t5 - t4));
    tri_arena_free(a);
    tri_content_free(c);
    free(t.s);
    return 0;
}
