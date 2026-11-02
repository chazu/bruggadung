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
/* The build log, for the developer: every type the loader generated (meet,
 * conjunction, disjunction, alternative, anonymous enum, typed list), and
 * every pair of conflicting defaults it dropped. */
size_t      tri_log_count(const TriContent *content);
const char *tri_log_message(const TriContent *content, size_t i);
size_t      tri_diag_count(const TriContent *content);
const char *tri_diag_message(const TriContent *content, size_t i);
int         tri_diag_is_error(const TriContent *content, size_t i);
/* Where a diagnostic points: 1 with its file, line and column (both from 1;
 * the column counts bytes), or 0 if it has no location. */
int         tri_diag_location(const TriContent *content, size_t i, const char **file, int *line, int *col);
/* The message without its location and severity prefix. */
const char *tri_diag_text(const TriContent *content, size_t i);

/* Every declaration as written, in load order (a name declared several times
 * appears once per declaration). Names are qualified by their package. The
 * location is the label's; the doc is its docstring or NULL. A file that fails
 * to parse keeps the declarations before its error. */
typedef enum { TRI_DECL_TYPE, TRI_DECL_ATOM, TRI_DECL_INSTANCE } TriDeclKind;
typedef struct {
    const char *name;
    TriDeclKind kind;
    const char *package;       /* NULL in the root */
    const char *file;
    int         line, col;
    const char *doc;
} TriDecl;

size_t      tri_decl_count(const TriContent *content);
int         tri_decl(const TriContent *content, size_t i, TriDecl *out);

/* The comment directly above a type's or instance's declaration. */
const char *tri_doc(TriContent *content, const char *name);

/* --- types ------------------------------------------------------------------- */

size_t      tri_type_count(const TriContent *content);
TriType     tri_type_named(const TriContent *content, const char *name);
const char *tri_type_name(const TriContent *content, TriType t);
TriType     tri_meet(TriContent *content, TriType a, TriType b);
int         tri_subtype(const TriContent *content, TriType a, TriType b); /* a ⊑ b */
TriType     tri_primary_parent(const TriContent *content, TriType t);
/* The features a type has (its own and inherited), in a fixed order: the
 * count, and the name of the i-th. */
size_t      tri_type_feature_count(const TriContent *content, TriType t);
const char *tri_type_feature(const TriContent *content, TriType t, size_t i);
/* The built-in functions content may call (len, strings.ToUpper, ...): the
 * count, and the name of the i-th, with its signature. */
size_t      tri_function_count(void);
const char *tri_function(size_t i, const char **signature);

/* Component kinds declared with @component, and their fields' @field flags. */
size_t      tri_component_count(const TriContent *content);
const char *tri_component_name(const TriContent *content, size_t i);
TriType     tri_component_type(const TriContent *content, size_t i);
/* An entity type's components: the component types among its supertypes, as
 * component indices. Writes up to max and returns how many there are. */
size_t      tri_type_components(const TriContent *content, TriType type, size_t *out, size_t max);
size_t      tri_component_field_count(const TriContent *content, size_t i);
const char *tri_component_field(const TriContent *content, size_t i, size_t j,
                                const char **flags);

/* --- feature structures -------------------------------------------------------- */

TriType        tri_node_type(const TriNode *node);
int            tri_node_interval(const TriNode *node, int64_t *lo, int64_t *hi);
const TriNode *tri_at(const TriContent *content, const TriNode *node, const char *path);
size_t         tri_print(TriContent *content, const TriNode *node, char *buf, size_t len);
/* The contents of a string value, decoded: the text of a concrete text node,
 * or the name of an atom ("steel" gives steel; true gives true). Returns the
 * full length, writing as much as fits; (size_t) -1 if the node is neither. */
size_t         tri_text(TriContent *content, const TriNode *node, char *buf, size_t len);

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

/* A deep copy into `out` that shares nothing with the source: a knowledge
 * store compacts by copying its live descriptions into a fresh arena and
 * freeing the old one. */
const TriNode *tri_copy(TriContent *content, const TriNode *node, TriArena *out);

/* Every path where a and b conflict (unification reports only the first);
 * writes up to max paths and returns how many. Recognition weighs these
 * against the paths that agree. */
size_t         tri_conflicts(TriContent *content, const TriNode *a, const TriNode *b,
                             char (*paths)[256], size_t max);

/* The most specific structure subsuming both (least general generalisation). */
const TriNode *tri_lgg(TriContent *content, const TriNode *a, const TriNode *b, TriArena *out);

/* Memory decay: generalise the node at path by up to `steps` primary parents. */
const TriNode *tri_generalize(TriContent *content, const TriNode *node,
                              const char *path, int steps, TriArena *out);

/* --- instances ------------------------------------------------------------------- */

/* The indefeasible structure of an instance: what patterns use. */
const TriNode *tri_pattern(TriContent *content, const char *instance);
/* An instance with disjunctions of structures has one variant per combination
 * of alternatives; tri_pattern is then their generalisation. */
size_t         tri_pattern_variant_count(TriContent *content, const char *instance);
const TriNode *tri_pattern_variant(TriContent *content, const char *instance, size_t i);
/* A blueprint spec: defaults resolved, variation points recorded. With
 * several variants, the generalisation of those that defaults leave. */
const TriNode *tri_spec(TriContent *content, const char *instance);
size_t         tri_spec_variation_count(TriContent *content, const char *instance);
const char    *tri_spec_variation_path(TriContent *content, const char *instance, size_t i);
size_t         tri_spec_note_count(TriContent *content, const char *instance);
const char    *tri_spec_note(TriContent *content, const char *instance, size_t i);
/* The spec as an indented structure, each value annotated with its origin:
 * the instance, a type, a default, a forced alternative, or the seed. */
size_t         tri_inspect(TriContent *content, const char *instance, char *buf, size_t len);
/* Code that computes a derived field, named in content by @fn(name). It reads
 * the structure holding the field and returns 1 with an interval (an exact
 * value when lo == hi), or 0 to leave the field as it is. */
typedef int (*TriFn)(void *ctx, TriContent *content, const TriNode *owner, int64_t *lo, int64_t *hi);
void           tri_register_fn(TriContent *content, const char *name, TriFn fn, void *ctx);
/* Applies registered functions to every @fn field of a structure. NULL if a
 * computed value conflicts with the structure. */
const TriNode *tri_derive(TriContent *content, const TriNode *node, TriArena *out, TriFailure *failure);
/* Makes every variation point concrete from the seed, then derives @fn fields. */
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

/* Matches against every variant of an instance: entailed if any variant is,
 * incompatible if all are, otherwise unknown. */
TriMatch tri_match_instance(TriContent *content, const char *instance, const TriNode *description,
                            TriMatchResult *result);

/* The node in `description` bound to `tag` of the named pattern instance:
 * a tag ("s" or "$s"), or a reference as written (".tool.size"). */
const TriNode *tri_binding(TriContent *content, const char *instance, const char *tag,
                           const TriNode *description);

/* Credence masses over competing hypotheses. Credences are Q16 probabilities.
 * The residuals are those of the unknown hypotheses, without repeats. */
typedef struct {
    uint32_t entailed, unknown, incompatible;
    size_t   nresidual;
    char     residual[TRI_MAX_RESIDUAL][128];
} TriMasses;

TriMasses tri_match_hypotheses(TriContent *content, const TriNode *pattern,
                               const TriNode *const *descriptions,
                               const uint32_t *credences, size_t n);

/* A readable account of a match: the result, the tag bindings, the residuals,
 * and the first failing path. Returns the length of the full text. */
size_t tri_explain(TriContent *content, const TriNode *pattern, const TriNode *description,
                   char *buf, size_t len);
/* The same for a named pattern instance, with its tag names (and variants). */
size_t tri_explain_instance(TriContent *content, const char *instance, const TriNode *description,
                            char *buf, size_t len);

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

/* --- definite clauses -------------------------------------------------------------------- */

/* Relations over feature structures, for recursion such as reachability.
 * Content writes clauses as instances of the built-in #Clause (head, body: a
 * list of goals) and #Fact (no body). tri_solve proves `query` by resolution,
 * depth-first, clauses in name order, each proof at most depth_limit steps
 * deep. Writes up to max distinct solutions (the query made specific by each
 * proof) to `out` and returns how many; *truncated says whether the depth limit cut any
 * proof short, so more solutions may exist. */
size_t tri_solve(TriContent *content, const TriNode *query, size_t depth_limit,
                 const TriNode **solutions, size_t max, TriArena *out, int *truncated);

/* --- families ------------------------------------------------------------------------- */

/* Instances marked @family(name) are a family; their @quickcheck(paths) are
 * pooled and the family's pattern index is compiled at load. Index tags are
 * instance names (const char *). */
size_t      tri_family_count(const TriContent *content);
const char *tri_family_name(const TriContent *content, size_t i);
TriIndex   *tri_family_index(TriContent *content, const char *family);

/* While recording, a failed tri_match_instance of a family's instance counts
 * its failure path. The suggestion is the k most frequent, as a @quickcheck
 * attribute to paste into content. */
void        tri_record_failures(TriContent *content, int on);
size_t      tri_family_suggest_quickcheck(TriContent *content, const char *family, size_t k, char *buf, size_t len);

/* --- code generation ------------------------------------------------------------------ */

/* A C header with one struct per @component type, named prefix + component:
 * numbers as int64_t quanta, text as strings, referents as uint64_t, bool,
 * enums as type IDs with an enum of their members, other structures as
 * TriNode pointers. Field comments give units and @field flags. */
size_t tri_component_header(TriContent *content, const char *prefix, char *buf, size_t len);

/* A number of quanta of a quantity kind ("mass", "length", "int", ...) as
 * content would write it: tri_format_quantity("mass", 850, ...) is "850g".
 * An unknown kind prints the plain number. */
size_t tri_format_quantity(const char *kind, int64_t quanta, char *buf, size_t len);

/* --- knowledge stores ------------------------------------------------------------------ */

/* Bytes an arena holds, and distinct nodes a structure has: what a store
 * measures to decide when to compact (tri_copy) and to keep its bound. */
size_t tri_arena_bytes(const TriArena *arena);
size_t tri_node_count(const TriNode *node);

/* Moves a description from one content build to another (a reload, a mod),
 * by name; NULL with the reason if a type is gone or it no longer fits. */
const TriNode *tri_migrate(TriContent *from, TriContent *to, const TriNode *node, TriArena *out,
                           char *err, size_t errlen);

/* --- saves ---------------------------------------------------------------------------- */

/* Writes a description as text (malloc'd). By ID is compact but restores only
 * into the same content; by name restores into changed content too. */
char          *tri_save(TriContent *content, const TriNode *node, int by_id);
/* NULL on failure, with the reason in err: a type or feature that no longer
 * exists, or a structure that no longer fits its types. */
const TriNode *tri_restore(TriContent *content, const char *text, TriArena *out, char *err, size_t errlen);

#ifdef __cplusplus
}
#endif

#endif
