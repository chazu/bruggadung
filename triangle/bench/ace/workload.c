/* the bench workload (every rule daughter x an even sample of lexical entries),
 * with no failure reporting; writes the names used so ACE can run the same */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "triangle.h"

static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }

int main(int argc, char **argv)
{
    size_t want = (size_t) atol(argv[2]);
    FILE *names = fopen(argv[3], "w");
    TriContent *c = tri_content_load_tdl(argv[1]);
    if (!tri_content_ok(c)) return 1;
    size_t ninst = tri_instance_count(c), nlex = 0;
    for (size_t i = 0; i < ninst; i++) if (!strcmp(tri_instance_status(c, i), "lex-entry")) nlex++;
    size_t step = nlex / want ? nlex / want : 1;
    const TriNode **dtrs = malloc(sizeof(TriNode *) * ninst), **lex = malloc(sizeof(TriNode *) * (want + 1));
    size_t ndtr = 0, nl = 0, k = 0;
    for (size_t i = 0; i < ninst; i++) {
        const char *st = tri_instance_status(c, i);
        if (strcmp(st, "rule") && strcmp(st, "lex-rule")) continue;
        const TriNode *r = tri_pattern(c, tri_instance_name(c, i));
        const TriNode *d1 = tri_at(c, r, "args.first"), *d2 = tri_at(c, r, "args.rest.first");
        if (d1) { dtrs[ndtr++] = d1; fprintf(names, "R %s 0\n", tri_instance_name(c, i)); }
        if (d2) { dtrs[ndtr++] = d2; fprintf(names, "R %s 1\n", tri_instance_name(c, i)); }
    }
    for (size_t i = 0; i < ninst && nl < want; i++) {
        if (strcmp(tri_instance_status(c, i), "lex-entry")) continue;
        if (k++ % step) continue;
        lex[nl++] = tri_pattern(c, tri_instance_name(c, i));
        fprintf(names, "L %s\n", tri_instance_name(c, i));
    }
    fclose(names);
    FILE *pairs = argc > 4 ? fopen(argv[4], "w") : NULL;
    TriArena *out = tri_arena_new();
    for (int rep = 0; rep < 3; rep++) {
        size_t ok = 0, n = 0;
        double t = now_ms();
        for (size_t d = 0; d < ndtr; d++)
            for (size_t e = 0; e < nl; e++) {
                TriMark m = tri_arena_mark(out);
                if (tri_unify(c, dtrs[d], lex[e], out, NULL)) { ok++; if (rep == 0 && pairs) fprintf(pairs, "%zu %zu\n", d, e); }
                n++;
                tri_arena_release(out, m);
            }
        t = now_ms() - t;
        printf("triangle: %zu daughters x %zu entries = %zu unifications, %zu succeeded, %.0f ms = %.2f M/s\n",
               ndtr, nl, n, ok, t, n / t / 1e3);
    }
    if (pairs) fclose(pairs);
    return 0;
}
