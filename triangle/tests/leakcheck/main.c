/* Every allocation made while loading, using, and freeing content is freed:
 * the library is built against a counting allocator, and the count of live
 * allocations must return to where it was. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "triangle.h"

extern long cnt_live;
void cnt_free(void *p);

static const char *sources[] = {
    /* the features the scenarios and feature tests use */
    "#Material: \"steel\" | \"brass\"\n#Finish: { finish: \"black\" | \"bright\" | \"dull\" }\n"
    "#Painted: #Finish & { finish: *\"black\" }\n#Oiled: #Finish & { finish: *\"bright\" }\n"
    "// a part\n#Part: { @component(Part)\n"
    "    colour: \"red\" | \"green\" @vary(1, 2) @field(content)\n"
    "    size: length & >=1mm & <=20mm @field(content) @widen(1mm)\n"
    "    shape: { round: true } | { round: false, sides: int & >=3 & <=8 } @field(content)\n"
    "    material: *\"steel\" | #Material @field(content)\n"
    "    kids: [...#Part]\n    torque: torque @fn(none)\n    label: text\n    owner: ref\n}\n"
    "#Person: { name: text, mother: #Person }\n"
    "pick: #Part & #Painted & #Oiled & ({ size: 2mm } | { size: 4mm }) @family(parts) @quickcheck(size) @variants(4)\n"
    "#Roles: { tool: #Part, target: #Part }\n"
    "op: #Roles & { tool: { size: $s }, target: { size: $s } } @family(ops)\n",
    /* errors of several kinds */
    "#A: #Nope\n#B: { x: 1 | 3 }\n#C: { y: 1 }\n#C: { y: 2 }\nz: #C & { q: 1 }\n",
    "#P: { @component(P)\n m: mass @field(content)\n}\np: #P\n",
    "#T: { a: int }\nt: #T & { a: 1 | 3 | 5 } @variants(2)\n",
    "#S: { v: *1 | int @vary(3) }\n",
    "this is not triangle",
    /* arithmetic and clauses */
    "#L: { f: $f & force, a: $a & length, t: $f * $a, half: $a / 2 }\nl: #L & { f: 2N, a: 1m }\n"
    "#E: { from: text, to: text, d: length }\n#R: { from: text, to: text, d: length }\n"
    "e1: #Fact & { head: #E & { from: \"a\", to: \"b\", d: 1m } }\n"
    "r1: #Clause & { head: #R & { from: $x, to: $y, d: $d }, body: [#E & { from: $x, to: $y, d: $d }] }\n"
    "r2: #Clause & { head: #R & { from: $x, to: $z, d: $p + $q }, body: [#E & { from: $x, to: $y, d: $p }, #R & { from: $y, to: $z, d: $q }] }\n",
};

int main(void)
{
    int bad = 0;
    for (size_t s = 0; s < sizeof sources / sizeof sources[0]; s++) {
        for (int round = 0; round < 2; round++) {
            long before = cnt_live;
            const char *names[] = { "leak.tri" };
            const char *srcs[] = { sources[s] };
            TriContent *c = tri_content_load_strings(names, srcs, 1);
            TriArena *a = tri_arena_new();
            char buf[2048];
            for (size_t i = 0; i < tri_instance_count(c); i++) {
                const char *in = tri_instance_name(c, i);
                const TriNode *p = tri_pattern(c, in);
                const TriNode *w = tri_construct(c, in, (uint64_t) round + 1, a);
                tri_inspect(c, in, buf, sizeof buf);
                if (p) {
                    char *t = tri_save(c, p, round);
                    tri_restore(c, t, a, buf, sizeof buf);
                    cnt_free(t);
                    tri_explain_instance(c, in, p, buf, sizeof buf);
                    tri_explain(c, p, p, buf, sizeof buf);
                    tri_lgg(c, p, w ? w : p, a);
                    TriFailure f;
                    tri_unify(c, p, p, a, &f);
                    tri_derive(c, p, a, &f);
                    char paths[4][256];
                    tri_conflicts(c, p, w ? w : p, paths, 4);
                    tri_copy(c, p, a);
                    tri_generalize(c, p, "", 1, a);
                    TriMatchResult mr;
                    tri_match_instance(c, in, p, &mr);
                    tri_binding(c, in, "s", p);
                }
            }
            tri_value(c, "#Person & { mother: { name: \"x\" } }", a, buf, sizeof buf);
            const TriNode *q = tri_value(c, "#R & { from: \"a\" }", a, buf, sizeof buf);
            if (q) {
                const TriNode *sol[8];
                int trunc;
                tri_solve(c, q, 6, sol, 8, a, &trunc);
            }
            tri_value(c, "#L & { f: 1N, a: 2m, t: 9Nm }", a, buf, sizeof buf);
            tri_record_failures(c, 1);
            for (size_t i = 0; i < tri_instance_count(c); i++) {
                TriMatchResult mr;
                const TriNode *p = tri_pattern(c, tri_instance_name(c, i));
                if (p) tri_match_instance(c, tri_instance_name(c, 0), p, &mr);
            }
            tri_family_suggest_quickcheck(c, "ops", 3, buf, sizeof buf);
            size_t hn = tri_component_header(c, "BG", NULL, 0);
            (void) hn;
            if (tri_instance_count(c)) {
                const TriNode *p0 = tri_pattern(c, tri_instance_name(c, 0));
                if (p0) { tri_migrate(c, c, p0, a, buf, sizeof buf); tri_node_count(p0); }
            }
            tri_arena_bytes(a);
            tri_value(c, "{ broken", a, buf, sizeof buf);
            tri_arena_free(a);
            tri_content_free(c);
            if (cnt_live != before) {
                fprintf(stderr, "  source %zu: %ld allocations not freed\n", s, cnt_live - before);
                bad++;
            }
        }
    }
    printf("leak check: %s\n", bad ? "FAILED" : "every allocation freed");
    return bad ? 1 : 0;
}
