#ifndef TRI_INTERNAL_H
#define TRI_INTERNAL_H

#include "triangle.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TRI_INF  INT64_MAX
#define TRI_NINF INT64_MIN

typedef const char *Sym;   /* interned; compare by pointer */

/* --- arena ------------------------------------------------------------------- */

typedef struct Chunk {
    struct Chunk *prev;
    size_t        used, cap;
    char          data[];
} Chunk;

struct TriArena { Chunk *top; };

void *arena_alloc(TriArena *a, size_t n);   /* zeroed */

/* --- utilities --------------------------------------------------------------- */

typedef struct { char *s; size_t len, cap; } Buf;
void buf_putc(Buf *b, char c);
void buf_puts(Buf *b, const char *s);
void buf_printf(Buf *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
void buf_free(Buf *b);

typedef struct { Sym *slots; size_t cap, count; } SymTable;
Sym  sym_intern(SymTable *t, const char *s, size_t len);
void sym_free(SymTable *t);

/* Open-addressing map from uint64 keys to uint64 values. Lookup only: it is
 * never iterated, so it cannot affect determinism. */
typedef struct { uint64_t *keys, *vals; uint8_t *used; size_t cap, count; } U64Map;
bool u64map_get(const U64Map *m, uint64_t key, uint64_t *val);
void u64map_put(U64Map *m, uint64_t key, uint64_t val);
void u64map_clear(U64Map *m);
void u64map_free(U64Map *m);

uint64_t hash64(uint64_t x);
uint64_t fnv1a(uint64_t h, const void *data, size_t n);

#define VEC(T) struct { T *v; size_t n, cap; }
#define VEC_PUSH(vec, x) do { \
    if ((vec).n == (vec).cap) { \
        (vec).cap = (vec).cap ? (vec).cap * 2 : 8; \
        (vec).v = realloc((vec).v, (vec).cap * sizeof *(vec).v); \
    } \
    (vec).v[(vec).n++] = (x); \
} while (0)
#define VEC_FREE(vec) do { free((vec).v); (vec).v = NULL; (vec).n = (vec).cap = 0; } while (0)

typedef VEC(uint32_t) U32Vec;

/* --- units ---------------------------------------------------------------------- */

enum { DIM_INT, DIM_FIXED, DIM_MASS, DIM_LENGTH, DIM_TIME, DIM_TORQUE, DIM_FORCE,
       DIM_HEAT, DIM_TEMPERATURE, NDIMS };

extern const char *const dim_names[NDIMS];
/* Parses a numeric literal with optional unit suffix into exact quanta.
 * Returns NULL on success, or an error message. */
const char *units_parse(const char *text, size_t len, int *dim, int64_t *q);
void        units_format(Buf *b, int dim, int64_t q);

/* --- syntax tree -------------------------------------------------------------------- */

typedef struct { Sym file; int line, col; } Loc;

typedef struct { Sym name; char *args; } Attr;

typedef enum { X_TOP, X_NAME, X_ATOM, X_NUM, X_BOUND, X_TAG, X_STRUCT, X_LIST,
               X_AND, X_OR, X_DEFAULT } XKind;

typedef struct X X;

typedef struct {
    Sym   label;
    X    *value;
    Attr *attrs;
    int   nattrs;
    Loc   loc;
} XField;

enum { B_GE, B_LE, B_GT, B_LT };

struct X {
    XKind k;
    Loc   loc;
    union {
        Sym name;                                         /* NAME, ATOM, TAG */
        struct { int dim; int64_t q; } num;
        struct { int op; int dim; int64_t q; } bound;
        struct { XField *fields; int n; Attr *attrs; int nattrs; } st;
        struct { X **items; int n; bool open; X *tail; } list;
        struct { X *a, *b; } bin;
        X *sub;                                           /* DEFAULT */
    } u;
};

enum { L_DEF, L_ATOM, L_INST };

typedef struct {
    Sym   label;
    int   kind;
    X    *value;
    Attr *attrs;
    int   nattrs;
    Loc   loc;
    bool  addendum;      /* TDL :+ */
    Sym   status;        /* TDL instance status, e.g. lex-entry */
} Decl;

typedef struct TriContent Content;
typedef VEC(Decl) DeclVec;
typedef VEC(X *) XPtrVec;
typedef VEC(Sym) SymVec;

/* Parses a source into declarations appended to the content. Returns false on
 * error (diagnostics recorded). */
bool parse_source(Content *c, Sym file, const char *src, DeclVec *out);
/* Parses a single expression. */
X   *parse_expr_string(Content *c, Sym file, const char *src);

/* --- types ------------------------------------------------------------------------ */

typedef enum { TK_TOP, TK_DIM, TK_ATOMROOT, TK_DEF, TK_ATOM, TK_ANON, TK_GLB } TypeKind;

typedef struct {
    U32Vec path;
    X       *value;
    uint32_t contributor;     /* type, or CONTRIB_INSTANCE */
} DefaultRec;

#define CONTRIB_INSTANCE 0xFFFFFFFEu

typedef VEC(DefaultRec) DefVec;

typedef struct {
    Sym      name;
    TypeKind kind;
    int      dim;                       /* TK_DIM only */
    U32Vec parents;              /* primary first */
    U32Vec children;
    uint64_t *code;                     /* descendants, including self; NULL for leaves */
    int32_t   bit;                      /* position in codes, or -1 for leaves */
    U32Vec feats;                /* appropriate features, ascending */
    VEC(Decl *) decls;                  /* declarations naming this type */
    SymVec    members;                  /* ANON / GLB: member names, for naming */
    int       xstate;                   /* 0 none, 1 in progress, 2 done */
    TriNode  *expansion;
    DefVec    defaults;                 /* own and inherited, relative to root */
    Sym       component;                /* @component name, or NULL */
    VEC(Attr *) field_attrs;            /* parallel to own introduced features */
    U32Vec field_feats;
} TypeInfo;

typedef struct {
    Sym      name;
    uint32_t intro;
} FeatInfo;

/* --- nodes -------------------------------------------------------------------------- */

typedef struct { uint32_t feat; TriNode *val; } Arc;

/* Per-operation scratch, allocated on first touch in the scratch arena and
 * valid only while its generation is current. Keeping it out of the node
 * makes nodes 48 bytes. */
typedef struct {
    TriNode *fwd;                /* unification forward; subsumption a→b */
    TriNode *bwd;                /* subsumption b→a */
    Arc     *carcs;              /* comp-arcs added during unification */
    uint32_t ncarcs, ccap;
    int64_t  slo, shi;           /* narrowed interval */
    bool     hasiv;
} Scratch;

enum { NF_SCRATCH = 1, NF_DIM = 2 };

struct TriNode {
    uint32_t type;
    uint16_t narcs;
    uint16_t flags;
    union {
        Arc *arcs;               /* sorted by feature id; non-dimension nodes */
        struct { int64_t lo, hi; };   /* dimension nodes */
    };
    Scratch *sx;
    uint32_t sxgen;
    uint32_t cpygen;
    TriNode *cpy;
};

/* --- instances -------------------------------------------------------------------- */

typedef struct { Sym name; U32Vec path; } TagPath;

typedef struct {
    Sym       name;
    VEC(Decl *) decls;
    int       pstate;            /* 0 none, 1 in progress, 2 done, 3 failed */
    TriNode  *pattern;
    DefVec    defaults;          /* instance-level */
    VEC(TagPath) tags;
    int       sstate;
    TriNode  *spec;
    VEC(char *) variation;       /* paths, printable */
    VEC(U32Vec) varpaths;
    VEC(char *) notes;
} InstInfo;

/* --- the content object ------------------------------------------------------------- */

typedef struct { bool error; char *msg; } Diag;

struct TriContent {
    SymTable syms;
    TriArena *load, *spec, *scratch;
    VEC(Diag) diags;
    int nerrors;

    DeclVec decls;
    VEC(TypeInfo) types;
    U64Map typeidx;              /* Sym → type id + 1 */
    size_t codewords, nbits;
    uint32_t *bittype;           /* bit → type */
    size_t nglb;
    U64Map codeidx;              /* hash(code) → type id + 1 (first with that hash) */
    U64Map meetmemo;

    VEC(FeatInfo) feats;
    U64Map featidx;              /* Sym → feature id + 1 */

    VEC(InstInfo) insts;
    U64Map instidx;

    bool tdl;
    uint32_t top, atomroot, stringroot, dimtype[NDIMS], tlist, tcons, tnull;
    uint32_t ffirst, frest;

    /* generations */
    uint32_t gen, genctr, cgenctr;
    int opdepth;                 /* nesting of operations; 1 = top level */

    /* failure recording */
    uint32_t pathstack[128];
    int depth;
    bool failed;
    TriFailure fail;

    uint64_t hash;
    TriStats stats;
    bool cyclic;                 /* set when sharing meets a cycle during copy_out */
};

void diag(Content *c, bool error, Loc loc, const char *fmt, ...) __attribute__((format(printf, 4, 5)));
Sym  intern(Content *c, const char *s);

/* types.c */
bool     types_build(Content *c);
bool     tdl_parse_top(Content *c, const char *path, int kind);
uint32_t type_lookup(const Content *c, Sym name);         /* TRI_BOTTOM if none */
uint32_t feat_lookup(const Content *c, Sym name);         /* TRI_BOTTOM if none */
bool     is_subtype(const Content *c, uint32_t a, uint32_t b);
uint32_t meet(Content *c, uint32_t a, uint32_t b);
bool     approp(const Content *c, uint32_t t, uint32_t f);
bool     is_dim(const Content *c, uint32_t t);
bool     is_leaf(const Content *c, uint32_t t);           /* no subtypes, no features */
Sym      anon_name(Content *c, X *orx);

/* fs.c */
uint32_t op_begin(Content *c);
void     op_end(Content *c, uint32_t saved);
TriNode *node_new(Content *c, TriArena *a, uint32_t type);
Scratch *sx_get(Content *c, TriNode *n);
Scratch *sx_make(Content *c, TriNode *n);
TriNode *carc_find(Content *c, TriNode *n, uint32_t f);
void     carc_add(Content *c, TriNode *n, uint32_t f, TriNode *v);
TriNode *leaf_new(Content *c, TriArena *a, uint32_t type, int64_t lo, int64_t hi);
TriNode *deref(Content *c, TriNode *n);
bool     unify1(Content *c, TriNode *a, TriNode *b);
TriNode *copy_raw(Content *c, TriArena *a, TriNode *n);
TriNode *copy_out(Content *c, TriArena *a, TriNode *n, bool *closed_ok);
TriNode *node_arc(TriNode *n, uint32_t f);                /* final structures only */
void     node_iv(Content *c, TriNode *n, int64_t *lo, int64_t *hi);
void     fs_print(Content *c, Buf *b, TriNode *n);
void     path_format(Content *c, Buf *b, const uint32_t *path, size_t n);
bool     path_parse(Content *c, const char *s, U32Vec *out);
TriNode *node_at(TriNode *n, const uint32_t *path, size_t len);
bool     ext_equal(Content *c, TriNode *a, TriNode *b);

/* load.c */
TriNode *type_expansion(Content *c, uint32_t t);
bool     inst_pattern(Content *c, uint32_t inst);

#endif
