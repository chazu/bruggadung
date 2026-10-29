/*
 * Triangle — the bruggadung content language: a typed feature structure core.
 *
 * Prototype of the engine specified in CONTENT_LANGUAGE.md: TDL semantics,
 * CUE-style syntax, quasi-destructive unification, three-valued matching.
 * Plain C11; no garbage collector; single-threaded per content object.
 */
#ifndef TRIANGLE_H
#define TRIANGLE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TriContent TriContent;
typedef struct TriNode    TriNode;
typedef struct TriArena   TriArena;
typedef uint32_t          TriType;

#define TRI_BOTTOM ((TriType) 0xFFFFFFFFu)

/* --- arenas ---------------------------------------------------------------- */

typedef struct { void *chunk; size_t used; } TriMark;

TriArena *tri_arena_new(void);
void      tri_arena_free(TriArena *arena);
TriMark   tri_arena_mark(TriArena *arena);
void      tri_arena_release(TriArena *arena, TriMark mark);

/* --- loading ----------------------------------------------------------------- */

/* Loads content from files, or from in-memory sources named for diagnostics.
 * Always returns a content object; check tri_content_ok and the diagnostics. */
TriContent *tri_content_load(const char *const *paths, size_t n);
TriContent *tri_content_load_strings(const char *const *names,
                                     const char *const *sources, size_t n);
/* Loads a TDL grammar from a top file using :begin/:end blocks and :include,
 * such as the English Resource Grammar's english.tdl. Instances resolve lazily. */
TriContent *tri_content_load_tdl(const char *topfile);
void        tri_content_free(TriContent *content);

typedef struct {
    double parse_ms, hierarchy_ms, expansion_ms, instances_ms;
    size_t types, glb_types, leaf_types, features, instances;
    size_t spec_bytes, load_bytes;
} TriStats;

void        tri_content_stats(const TriContent *content, TriStats *stats);
size_t      tri_instance_count(const TriContent *content);
const char *tri_instance_name(const TriContent *content, size_t i);
const char *tri_instance_status(const TriContent *content, size_t i);  /* TDL :status */

int         tri_content_ok(const TriContent *content);
uint64_t    tri_content_hash(const TriContent *content);
size_t      tri_diag_count(const TriContent *content);
const char *tri_diag_message(const TriContent *content, size_t i);
int         tri_diag_is_error(const TriContent *content, size_t i);

/* --- types ------------------------------------------------------------------- */

size_t      tri_type_count(const TriContent *content);
TriType     tri_type_named(const TriContent *content, const char *name);
const char *tri_type_name(const TriContent *content, TriType t);
TriType     tri_meet(TriContent *content, TriType a, TriType b);
int         tri_subtype(const TriContent *content, TriType a, TriType b); /* a ⊑ b */
TriType     tri_primary_parent(const TriContent *content, TriType t);

/* Component kinds declared with @component, and their fields' @field flags. */
size_t      tri_component_count(const TriContent *content);
const char *tri_component_name(const TriContent *content, size_t i);
TriType     tri_component_type(const TriContent *content, size_t i);
size_t      tri_component_field_count(const TriContent *content, size_t i);
const char *tri_component_field(const TriContent *content, size_t i, size_t j,
                                const char **flags);

/* --- feature structures -------------------------------------------------------- */

TriType        tri_node_type(const TriNode *node);
int            tri_node_interval(const TriNode *node, int64_t *lo, int64_t *hi);
const TriNode *tri_at(const TriContent *content, const TriNode *node, const char *path);
size_t         tri_print(TriContent *content, const TriNode *node, char *buf, size_t len);

/* Builds a description from an expression, e.g. "#Nut & { size: 19mm }". */
const TriNode *tri_value(TriContent *content, const char *expr, TriArena *out,
                         char *err, size_t errlen);

typedef struct {
    char path[256];
    char left[128];
    char right[128];
} TriFailure;

/* The result may share unchanged structure with its inputs (structure
 * sharing): keep the inputs' arenas alive while the result is in use. The two
 * inputs must not share nodes at different positions, e.g. a structure and one
 * of its own substructures. */
const TriNode *tri_unify(TriContent *content, const TriNode *a, const TriNode *b,
                         TriArena *out, TriFailure *failure);
void           tri_subsumes(TriContent *content, const TriNode *a, const TriNode *b,
                            int *forward, int *backward);

/* Memory decay: generalise the node at path by up to `steps` primary parents. */
const TriNode *tri_generalize(TriContent *content, const TriNode *node,
                              const char *path, int steps, TriArena *out);

/* --- instances ------------------------------------------------------------------- */

/* The indefeasible structure of an instance: what patterns use. */
const TriNode *tri_pattern(TriContent *content, const char *instance);
/* A blueprint spec: defaults resolved, variation points recorded. */
const TriNode *tri_spec(TriContent *content, const char *instance);
size_t         tri_spec_variation_count(TriContent *content, const char *instance);
const char    *tri_spec_variation_path(TriContent *content, const char *instance, size_t i);
size_t         tri_spec_note_count(TriContent *content, const char *instance);
const char    *tri_spec_note(TriContent *content, const char *instance, size_t i);
/* Makes every variation point concrete from the seed. */
const TriNode *tri_construct(TriContent *content, const char *instance, uint64_t seed,
                             TriArena *out);

/* --- matching -------------------------------------------------------------------- */

typedef enum { TRI_ENTAILED, TRI_UNKNOWN, TRI_INCOMPATIBLE } TriMatch;

#define TRI_MAX_RESIDUAL 16

typedef struct {
    TriMatch   result;
    size_t     nresidual;
    char       residual[TRI_MAX_RESIDUAL][128];
    TriFailure failure;          /* set when incompatible */
} TriMatchResult;

TriMatch tri_match(TriContent *content, const TriNode *pattern, const TriNode *description,
                   TriMatchResult *result);

/* The node in `description` bound to `tag` of the named pattern instance. */
const TriNode *tri_binding(TriContent *content, const char *instance, const char *tag,
                           const TriNode *description);

/* Credence masses over competing hypotheses. Credences are Q16 probabilities. */
typedef struct { uint32_t entailed, unknown, incompatible; } TriMasses;

TriMasses tri_match_hypotheses(TriContent *content, const TriNode *pattern,
                               const TriNode *const *descriptions,
                               const uint32_t *credences, size_t n);

/* --- quick check and pattern indexes ----------------------------------------------- */

/* A vector of types at a few failure-prone paths (plus the root), compared by
 * meet before unifying. It never rejects a unification that would succeed. */
typedef struct TriQuickCheck TriQuickCheck;

TriQuickCheck *tri_qc_new(TriContent *content, const char *const *paths, size_t n);
/* Chooses the k most frequent paths from recorded failure paths (TriFailure.path). */
TriQuickCheck *tri_qc_from_failures(TriContent *content, const char *const *failures, size_t n, size_t k);
void           tri_qc_free(TriQuickCheck *qc);
size_t         tri_qc_size(const TriQuickCheck *qc);            /* vector length, root included */
const char    *tri_qc_path(const TriQuickCheck *qc, size_t i);
void           tri_qc_vector(const TriQuickCheck *qc, const TriNode *node, TriType *out);
int            tri_qc_compatible(const TriQuickCheck *qc, const TriType *a, const TriType *b);

/* Patterns with precomputed vectors; candidates are those that could match. */
typedef struct TriIndex TriIndex;

TriIndex      *tri_index_new(const TriQuickCheck *qc);
void           tri_index_add(TriIndex *index, const TriNode *pattern, void *tag);
size_t         tri_index_count(const TriIndex *index);
/* Writes up to max candidate positions; returns how many there are in all. */
size_t         tri_index_candidates(TriIndex *index, const TriNode *description, size_t *out, size_t max);
const TriNode *tri_index_pattern(const TriIndex *index, size_t i);
void          *tri_index_tag(const TriIndex *index, size_t i);
void           tri_index_free(TriIndex *index);

#ifdef __cplusplus
}
#endif

#endif
