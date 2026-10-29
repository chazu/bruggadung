#include "internal.h"

/* The quick check (Malouf, Carroll & Copestake; Kiefer et al.): each structure
 * gets a vector of the types at a few paths where unification most often
 * fails, and two vectors are compared by meet before unifying. The root type
 * is always the first element. A path a structure doesn't have counts as top,
 * so the check never rejects a unification that would succeed.
 *
 * Pattern indexes keep such vectors for a set of patterns and return the
 * patterns that could match a description. */

struct TriQuickCheck {
    Content *c;
    VEC(U32Vec) paths;
    VEC(char *) names;
};

TriQuickCheck *tri_qc_new(TriContent *c, const char *const *paths, size_t n)
{
    TriQuickCheck *qc = calloc(1, sizeof *qc);
    qc->c = c;
    for (size_t i = 0; i < n; i++) {
        U32Vec p = { 0 };
        if (!path_parse(c, paths[i], &p) || !p.n) { VEC_FREE(p); continue; }
        VEC_PUSH(qc->paths, p);
        size_t len = strlen(paths[i]);
        char *name = malloc(len + 1);
        memcpy(name, paths[i], len + 1);
        VEC_PUSH(qc->names, name);
    }
    return qc;
}

typedef struct { const char *path; size_t n; } Count;

static int by_count(const void *a, const void *b)
{
    const Count *x = a, *y = b;
    if (x->n != y->n) return x->n < y->n ? 1 : -1;
    return strcmp(x->path, y->path);
}

TriQuickCheck *tri_qc_from_failures(TriContent *c, const char *const *failures, size_t n, size_t k)
{
    VEC(Count) counts = { 0 };
    U64Map idx = { 0 };
    for (size_t i = 0; i < n; i++) {
        Sym s = intern(c, failures[i]);
        uint64_t v;
        if (u64map_get(&idx, (uint64_t) (uintptr_t) s, &v)) { counts.v[v - 1].n++; continue; }
        Count ct = { s, 1 };
        VEC_PUSH(counts, ct);
        u64map_put(&idx, (uint64_t) (uintptr_t) s, counts.n);
    }
    qsort(counts.v, counts.n, sizeof(Count), by_count);
    VEC(const char *) chosen = { 0 };
    for (size_t i = 0; i < counts.n && chosen.n < k; i++)
        if (strcmp(counts.v[i].path, "(root)") != 0) VEC_PUSH(chosen, counts.v[i].path);
    TriQuickCheck *qc = tri_qc_new(c, chosen.v, chosen.n);
    VEC_FREE(chosen);
    VEC_FREE(counts);
    u64map_free(&idx);
    return qc;
}

void tri_qc_free(TriQuickCheck *qc)
{
    if (!qc) return;
    for (size_t i = 0; i < qc->paths.n; i++) VEC_FREE(qc->paths.v[i]);
    for (size_t i = 0; i < qc->names.n; i++) free(qc->names.v[i]);
    VEC_FREE(qc->paths);
    VEC_FREE(qc->names);
    free(qc);
}

size_t tri_qc_size(const TriQuickCheck *qc) { return qc->paths.n + 1; }

const char *tri_qc_path(const TriQuickCheck *qc, size_t i)
{
    return i == 0 ? "(root)" : i <= qc->names.n ? qc->names.v[i - 1] : NULL;
}

void tri_qc_vector(const TriQuickCheck *qc, const TriNode *node, TriType *out)
{
    out[0] = node->type;
    for (size_t i = 0; i < qc->paths.n; i++) {
        TriNode *n = node_at((TriNode *) node, qc->paths.v[i].v, qc->paths.v[i].n);
        out[i + 1] = n ? n->type : qc->c->top;
    }
}

int tri_qc_compatible(const TriQuickCheck *qc, const TriType *a, const TriType *b)
{
    size_t k = qc->paths.n + 1;
    for (size_t i = 0; i < k; i++)
        if (a[i] != b[i] && meet(qc->c, a[i], b[i]) == TRI_BOTTOM) return 0;
    return 1;
}

/* --- pattern indexes ----------------------------------------------------------------- */

struct TriIndex {
    const TriQuickCheck *qc;
    size_t k;
    VEC(TriType) vecs;           /* k per pattern */
    VEC(const TriNode *) patterns;
    VEC(void *) tags;
    TriType *query;
};

TriIndex *tri_index_new(const TriQuickCheck *qc)
{
    TriIndex *ix = calloc(1, sizeof *ix);
    ix->qc = qc;
    ix->k = tri_qc_size(qc);
    ix->query = malloc(ix->k * sizeof(TriType));
    return ix;
}

void tri_index_add(TriIndex *ix, const TriNode *pattern, void *tag)
{
    for (size_t i = 0; i < ix->k; i++) VEC_PUSH(ix->vecs, 0);
    tri_qc_vector(ix->qc, pattern, ix->vecs.v + ix->vecs.n - ix->k);
    VEC_PUSH(ix->patterns, pattern);
    VEC_PUSH(ix->tags, tag);
}

size_t tri_index_count(const TriIndex *ix) { return ix->patterns.n; }

size_t tri_index_candidates(TriIndex *ix, const TriNode *description, size_t *out, size_t max)
{
    tri_qc_vector(ix->qc, description, ix->query);
    size_t found = 0;
    for (size_t p = 0; p < ix->patterns.n; p++)
        if (tri_qc_compatible(ix->qc, ix->vecs.v + p * ix->k, ix->query)) {
            if (found < max) out[found] = p;
            found++;
        }
    return found;
}

const TriNode *tri_index_pattern(const TriIndex *ix, size_t i) { return ix->patterns.v[i]; }
void *tri_index_tag(const TriIndex *ix, size_t i) { return ix->tags.v[i]; }

void tri_index_free(TriIndex *ix)
{
    if (!ix) return;
    VEC_FREE(ix->vecs);
    VEC_FREE(ix->patterns);
    VEC_FREE(ix->tags);
    free(ix->query);
    free(ix);
}
