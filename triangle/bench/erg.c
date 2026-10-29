/* Benchmarks Triangle against a TDL grammar such as the English Resource Grammar.
 *
 *   erg english.tdl [entries]
 *
 * Reports load statistics, then a parsing-shaped workload: every rule
 * daughter (ARGS.FIRST, ARGS.REST.FIRST) unified with a deterministic sample of
 * lexical entries, and subsumption tests between sampled entries. */
#include "triangle.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

/* failure paths: the raw material for choosing quick-check paths */
typedef struct { char path[256]; size_t n; } Tally;
static Tally tallies[4096];
static size_t ntallies, depth_hist[8];

static void tally(const char *path)
{
    size_t depth = strcmp(path, "(root)") == 0 ? 0 : 1;
    for (const char *p = path; *p; p++) if (*p == '.') depth++;
    depth_hist[depth < 7 ? depth : 7]++;
    for (size_t i = 0; i < ntallies; i++)
        if (strcmp(tallies[i].path, path) == 0) { tallies[i].n++; return; }
    if (ntallies < 4096) { snprintf(tallies[ntallies].path, 256, "%s", path); tallies[ntallies++].n = 1; }
}

static int by_count(const void *a, const void *b)
{
    size_t x = ((const Tally *) a)->n, y = ((const Tally *) b)->n;
    return x < y ? 1 : x > y ? -1 : strcmp(((const Tally *) a)->path, ((const Tally *) b)->path);
}

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: %s english.tdl [entries]\n", argv[0]); return 2; }
    size_t want = argc > 2 ? (size_t) atol(argv[2]) : 1000;

    double t0 = now_ms();
    TriContent *c = tri_content_load_tdl(argv[1]);
    double tload = now_ms() - t0;
    size_t nd = tri_diag_count(c), shown = 0;
    for (size_t i = 0; i < nd && shown < 20; i++, shown++) fprintf(stderr, "%s\n", tri_diag_message(c, i));
    if (nd > shown) fprintf(stderr, "... %zu more diagnostics\n", nd - shown);
    TriStats s;
    tri_content_stats(c, &s);
    printf("load: ok=%d in %.0f ms, content hash %016llx\n", tri_content_ok(c), tload,
           (unsigned long long) tri_content_hash(c));
    printf("  types %zu (generated meets %zu, leaf types %zu), features %zu, instances %zu\n",
           s.types, s.glb_types, s.leaf_types, s.features, s.instances);
    printf("  parse %.0f ms, hierarchy %.0f ms, expansion %.0f ms\n", s.parse_ms, s.hierarchy_ms, s.expansion_ms);
    printf("  spec arena %.1f MB, load arena %.1f MB\n", s.spec_bytes / 1e6, s.load_bytes / 1e6);
    if (!tri_content_ok(c)) return 1;

    /* rules and a sample of lexical entries */
    size_t ninst = tri_instance_count(c), nlex = 0;
    for (size_t i = 0; i < ninst; i++)
        if (strcmp(tri_instance_status(c, i), "lex-entry") == 0) nlex++;
    size_t step = nlex / want ? nlex / want : 1;
    const TriNode **dtrs = malloc(sizeof(TriNode *) * ninst * 2);
    const TriNode **lex = malloc(sizeof(TriNode *) * (want + 1));
    size_t ndtr = 0, nrules = 0, nl = 0, k = 0, failed = 0;
    double tr = now_ms();
    for (size_t i = 0; i < ninst; i++) {
        const char *st = tri_instance_status(c, i);
        if (strcmp(st, "rule") != 0 && strcmp(st, "lex-rule") != 0) continue;
        const TriNode *r = tri_pattern(c, tri_instance_name(c, i));
        if (!r) { failed++; continue; }
        nrules++;
        const TriNode *d1 = tri_at(c, r, "args.first");
        const TriNode *d2 = tri_at(c, r, "args.rest.first");
        if (d1) dtrs[ndtr++] = d1;
        if (d2) dtrs[ndtr++] = d2;
    }
    double trules = now_ms() - tr;
    double tl = now_ms();
    for (size_t i = 0; i < ninst && nl < want; i++) {
        if (strcmp(tri_instance_status(c, i), "lex-entry") != 0) continue;
        if (k++ % step) continue;
        const TriNode *e = tri_pattern(c, tri_instance_name(c, i));
        if (e) lex[nl++] = e; else failed++;
    }
    double tlex = now_ms() - tl;
    printf("instances: %zu rules (%zu daughters) in %.0f ms; %zu of %zu lexical entries in %.0f ms (%.3f ms each); %zu failed\n",
           nrules, ndtr, trules, nl, nlex, tlex, nl ? tlex / nl : 0, failed);
    if (failed) {
        size_t nd2 = tri_diag_count(c);
        for (size_t i = nd; i < nd2 && i < nd + 10; i++) fprintf(stderr, "%s\n", tri_diag_message(c, i));
    }

    /* unification: every daughter against every sampled entry */
    char **train = NULL;
    size_t ntrain = 0, trcap = 0;
    TriArena *out = tri_arena_new();
    size_t ok = 0, fail = 0;
    double tu = now_ms();
    for (size_t d = 0; d < ndtr; d++)
        for (size_t e = 0; e < nl; e++) {
            TriMark m = tri_arena_mark(out);
            TriFailure f;
            if (tri_unify(c, dtrs[d], lex[e], out, &f)) ok++;
            else {
                fail++;
                tally(f.path);
                if (e < nl / 2) {                     /* training half, for the quick check */
                    size_t len = strlen(f.path);
                    char *p = malloc(len + 1);
                    memcpy(p, f.path, len + 1);
                    if (ntrain == trcap) { trcap = trcap ? trcap * 2 : 1024; train = realloc(train, trcap * sizeof(char *)); }
                    train[ntrain++] = p;
                }
            }
            tri_arena_release(out, m);
        }
    double tun = now_ms() - tu;
    size_t total = ok + fail;
    printf("unify: %zu unifications in %.0f ms = %.0f per second; %.1f%% failed (%zu succeeded)\n",
           total, tun, total / (tun / 1e3), 100.0 * fail / (total ? total : 1), ok);

    printf("  failure depth:");
    for (int d = 0; d < 8; d++) printf(" %d%s:%.1f%%", d, d == 7 ? "+" : "", 100.0 * depth_hist[d] / (fail ? fail : 1));
    printf("\n  %zu distinct failure paths; the most common:\n", ntallies);
    qsort(tallies, ntallies, sizeof(Tally), by_count);
    size_t cum = 0;
    for (size_t i = 0; i < ntallies && i < 30; i++) {
        cum += tallies[i].n;
        if (i < 12 || i == 19 || i == 29)
            printf("    %2zu %6.2f%% (cumulative %5.1f%%)  %s\n", i + 1, 100.0 * tallies[i].n / fail, 100.0 * cum / fail, tallies[i].path);
    }

    /* quick check: paths chosen from the training half, measured on the test half */
    size_t half = nl / 2;
    size_t ks[] = { 1, 5, 13, 30 };
    double tbase = 0;
    {
        size_t okb = 0;
        double t = now_ms();
        for (size_t d = 0; d < ndtr; d++)
            for (size_t e = half; e < nl; e++) {
                TriMark m = tri_arena_mark(out);
                TriFailure f;
                if (tri_unify(c, dtrs[d], lex[e], out, &f)) okb++;
                tri_arena_release(out, m);
            }
        tbase = now_ms() - t;
        printf("quick check (paths from %zu training failures; test: %zu entries x %zu daughters, %.0f ms unchecked):\n",
               ntrain, nl - half, ndtr, tbase);
    }
    for (size_t ki = 0; ki < sizeof ks / sizeof ks[0]; ki++) {
        TriQuickCheck *qc = tri_qc_from_failures(c, (const char *const *) train, ntrain, ks[ki]);
        size_t K = tri_qc_size(qc);
        TriType *dv = malloc(ndtr * K * sizeof(TriType)), *ev = malloc(nl * K * sizeof(TriType));
        for (size_t d = 0; d < ndtr; d++) tri_qc_vector(qc, dtrs[d], dv + d * K);
        for (size_t e = 0; e < nl; e++) tri_qc_vector(qc, lex[e], ev + e * K);
        size_t rejected = 0, failures = 0, wrong = 0;
        double t = now_ms();
        for (size_t d = 0; d < ndtr; d++)
            for (size_t e = half; e < nl; e++) {
                if (!tri_qc_compatible(qc, dv + d * K, ev + e * K)) { rejected++; continue; }
                TriMark m = tri_arena_mark(out);
                TriFailure f;
                if (!tri_unify(c, dtrs[d], lex[e], out, &f)) failures++;
                tri_arena_release(out, m);
            }
        double tq = now_ms() - t;
        /* soundness: every rejected pair must really fail */
        for (size_t d = 0; d < ndtr; d++)
            for (size_t e = half; e < nl; e++)
                if (!tri_qc_compatible(qc, dv + d * K, ev + e * K)) {
                    TriMark m = tri_arena_mark(out);
                    TriFailure f;
                    if (tri_unify(c, dtrs[d], lex[e], out, &f)) wrong++;
                    tri_arena_release(out, m);
                }
        printf("  %2zu paths: filters %.1f%% of failing unifications, %.0f ms (%.1fx faster), %zu wrongly rejected\n",
               ks[ki], 100.0 * rejected / (rejected + failures ? rejected + failures : 1), tq, tbase / (tq ? tq : 1), wrong);
        if (ks[ki] == 13) {
            TriIndex *ix = tri_index_new(qc);
            for (size_t d = 0; d < ndtr; d++) tri_index_add(ix, dtrs[d], NULL);
            size_t *cand = malloc(ndtr * sizeof(size_t)), total = 0;
            double ti = now_ms();
            for (size_t e = half; e < nl; e++) total += tri_index_candidates(ix, lex[e], cand, ndtr);
            double tix = now_ms() - ti;
            printf("  index of %zu daughters: %.1f candidates per entry on average, %.3f ms per query\n",
                   ndtr, (double) total / (nl - half), tix / (nl - half));
            free(cand);
            tri_index_free(ix);
        }
        free(dv);
        free(ev);
        tri_qc_free(qc);
    }
    for (size_t i = 0; i < ntrain; i++) free(train[i]);
    free(train);

    /* a spot check of one entry */
    if (nl) {
        static char buf[1 << 20];
        size_t len = tri_print(c, lex[0], buf, sizeof buf);
        const TriNode *head = tri_at(c, lex[0], "synsem.local.cat.head");
        printf("spot check: first sampled entry prints to %zu chars; root %s, head %s\n", len,
               tri_type_name(c, tri_node_type(lex[0])), head ? tri_type_name(c, tri_node_type(head)) : "(none)");
    }

    /* subsumption: pairs of sampled entries */
    size_t subs = 0, fwd_or_bwd = 0;
    double ts = now_ms();
    for (size_t a = 0; a < nl; a++)
        for (size_t b = 0; b < nl; b++) {
            int fw, bw;
            tri_subsumes(c, lex[a], lex[b], &fw, &bw);
            subs++;
            if (fw || bw) fwd_or_bwd++;
        }
    double tsub = now_ms() - ts;
    printf("subsume: %zu tests in %.0f ms = %.0f per second; %zu related\n",
           subs, tsub, subs / (tsub / 1e3), fwd_or_bwd);

    tri_content_stats(c, &s);
    printf("memory: spec arena %.1f MB after resolving instances\n", s.spec_bytes / 1e6);
    tri_arena_free(out);
    free(dtrs);
    free(lex);
    tri_content_free(c);
    return 0;
}
