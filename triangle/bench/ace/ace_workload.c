/* the same workload in ACE: each rule daughter x each lexical entry, through
 * ACE's own unifier on its compiled image; unify only, then unify + copy of the
 * daughter on success (what tri_unify does) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "dag.h"
#include "rule.h"
#include "lexicon.h"

void ace_load_grammar(char *path);
struct lexeme *get_lex_by_name(char *name);
struct rule *get_rule_by_name(char *name);
struct dg *lexical_dg(struct lexeme *lex, struct dg *rels);
int unify_dg_tmp(struct dg *dg1, struct dg *dg2, int arg);
struct dg *finalize_tmp(struct dg *d, int trim);
void forget_tmp();

static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }

static struct dg *daughter(struct dg *r, int arg)
{
    struct dg *to = dg_hop(r, 0);
    for (int i = 0; to && i < arg; i++) to = dg_hop(to, 2);
    return to ? dg_hop(to, 1) : NULL;
}

int main(int argc, char **argv)
{
    double t0 = now_ms();
    ace_load_grammar(argv[1]);
    printf("ace: image loaded in %.0f ms\n", now_ms() - t0);
    FILE *f = fopen(argv[2], "r");
    char line[512], name[500];
    struct dg *rdg[2000]; int rarg[2000]; int nr = 0;
    struct dg **ldg = malloc(sizeof(struct dg *) * 100000); int nl = 0, missing = 0;
    double tl = 0;
    while (fgets(line, sizeof line, f)) {
        int a;
        if (sscanf(line, "R %499s %d", name, &a) == 2) {
            struct rule *r = get_rule_by_name(name);
            if (!r || !daughter(r->dg, a)) { missing++; continue; }
            rdg[nr] = r->dg; rarg[nr++] = a;
        } else if (sscanf(line, "L %499s", name) == 1) {
            struct lexeme *l = get_lex_by_name(name);
            if (!l) { missing++; continue; }
            double t = now_ms();
            struct dg *d = lexical_dg(l, NULL);
            tl += now_ms() - t;
            if (d) ldg[nl++] = d; else missing++;
        }
    }
    printf("ace: %d daughters, %d entries (expanded in %.0f ms, %.3f ms each), %d missing\n", nr, nl, tl, tl / nl, missing);
    FILE *pairs = argc > 3 ? fopen(argv[3], "w") : NULL;
    for (int copy = 0; copy < 2; copy++)
        for (int rep = 0; rep < 3; rep++) {
            long n = 0, ok = 0;
            double t = now_ms();
            for (int d = 0; d < nr; d++)
                for (int e = 0; e < nl; e++) {
                    n++;
                    if (unify_dg_tmp(ldg[e], rdg[d], rarg[d]) == 0) {
                        ok++;
                        if (!copy && rep == 0 && pairs) fprintf(pairs, "%d %d\n", d, e);
                        if (copy) finalize_tmp(daughter(rdg[d], rarg[d]), 0);
                    }
                    forget_tmp();
                }
            t = now_ms() - t;
            printf("ace %s: %ld unifications, %ld succeeded, %.0f ms = %.2f M/s\n",
                   copy ? "unify+copy" : "unify only", n, ok, t, n / t / 1e3);
        }
    if (pairs) fclose(pairs);
    return 0;
}
