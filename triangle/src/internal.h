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

struct TriArena { Chunk *top; Chunk *spare; };   /* spare: one released chunk, kept for reuse */

void *arena_alloc(TriArena *a, size_t n);       /* zeroed */
void *arena_alloc_raw(TriArena *a, size_t n);   /* not zeroed */

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
typedef VEC(U32Vec) PathVec;
typedef VEC(TriNode *) NodeVec;

/* --- units ---------------------------------------------------------------------- */

enum { DIM_INT, DIM_FIXED, DIM_MASS, DIM_LENGTH, DIM_TIME, DIM_TORQUE, DIM_FORCE,
       DIM_HEAT, DIM_TEMPERATURE, DIM_VOLUME, DIM_AMOUNT, DIM_REF, DIM_TEXT, NDIMS };

/* A quantity kind: its exponents over the base units (m, kg, s, K, mol), its
 * quantum in those units (num / den), and how it prints. Products and
 * quotients of quantities follow from the exponents. */
typedef struct {
    int8_t exp[5];
    int64_t qnum, qden;
    const char *display;        /* suffix */
    int64_t per;                /* quanta per display unit */
    bool quantity;              /* false for ref and text */
} QuantityKind;
extern const QuantityKind quantity_kinds[NDIMS];
/* DIM_REF holds a referent number; DIM_TEXT an interned string, as a pointer.
 * Both are concrete when lo == hi and unify by equality. */

extern const char *const dim_names[NDIMS];
/* Parses a numeric literal with optional unit suffix into exact quanta.
 * Returns NULL on success, or an error message. */
const char *units_parse(const char *text, size_t len, bool neg, int *dim, int64_t *q);
void        units_format(Buf *b, int dim, int64_t q);

/* --- arithmetic ------------------------------------------------------------------ */

/* A value in arithmetic: an interval in quanta, with its exponents over the
 * base units and its quantum (qnum / qden in base units). dim is the kind it
 * is in, or -1 for an intermediate no kind has (an area, say). */
typedef struct { int dim; int64_t lo, hi; int8_t exp[5]; int64_t qnum, qden; } Quantity;

/* --- syntax tree -------------------------------------------------------------------- */

typedef struct { Sym file; int line, col; } Loc;

typedef struct { Sym name; char *args; } Attr;

typedef enum { X_TOP, X_NAME, X_ATOM, X_NUM, X_BOUND, X_TAG, X_STRUCT, X_LIST,
               X_AND, X_OR, X_DEFAULT, X_ARITH, X_REGEX } XKind;

typedef struct X X;
typedef struct TriContent Content;
typedef VEC(X *) XPtrVec;
typedef VEC(Sym) SymVec;

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
        struct { X **items; int n; bool open; X *tail; X *elem; } list;   /* elem: [...X] */
        struct { X *a, *b; } bin;
        X *sub;                                           /* DEFAULT */
        struct { X *a, *b; int op; } ar;                  /* ARITH: '+', '-', '*', '/' */
        struct { Sym pat; bool neg; } rx;                 /* REGEX: =~ or !~ a pattern */
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
    const char *doc;     /* the comment directly above, or NULL */
    Sym   pkg;           /* the package its file declares, or NULL (the root) */
} Decl;

typedef VEC(Decl) DeclVec;

/* xtree.c */
void  x_print(Buf *b, const X *x);
char *x_text(const X *x);                     /* malloc'd */
X    *x_new(Content *c, XKind k, Loc loc);
X    *x_name(Content *c, Sym name, Loc loc);
X    *x_and(Content *c, X *a, X *b);
void  x_flatten(X *x, XKind k, XPtrVec *out);
bool  x_interval(const X *x, int *dim, int64_t *lo, int64_t *hi);
bool  x_numeric_or(X *x, int *dim, int64_t *lo, int64_t *hi, bool *contiguous);

/* arith.c */
extern const char *const ARITH_UNKNOWN;
const char *quantity_op(int op, Quantity a, Quantity b, Quantity *out);
Quantity    quantity_of(int dim, int64_t lo, int64_t hi);
int         quantity_kind_for(const Quantity *q);
const char *quantity_to(const Quantity *q, int dim, Quantity *out);       /* convert to a kind */
void        arith_narrow(const X *x, Quantity want, bool (*lookup)(void *ctx, Sym tag, Quantity *q), void *ctx,
                         void (*narrow)(void *ctx, Sym tag, const Quantity *q));
const char *arith_eval(const X *x, bool (*lookup)(void *ctx, Sym tag, Quantity *q), void *ctx, Quantity *out);
void        arith_tags(const X *x, SymVec *out);

/* regex.c: RE2 syntax, matched anywhere in the text (as CUE's =~). */
typedef struct Regex Regex;
Regex *regex_compile(const char *pat, size_t len, char *err, size_t errlen);   /* NULL with err */
bool   regex_match(const Regex *re, const char *s, size_t n);
void   regex_free(Regex *re);

/* text.c: regex constraints on text (=~, !~), as sets interned per content.
 * An open text value with constraints has lo == TRI_NINF and hi pointing at
 * its set (text_rx); concrete text has lo == hi, its canonical string; open
 * text without constraints is TRI_NINF..TRI_INF. Sets are sorted and
 * interned, so equal sets are the same pointer. */
typedef struct { Sym pat; bool neg; Regex *re; } RxItem;
typedef struct { uint32_t n; RxItem *v; uint64_t hash; } RxSet;
const RxSet *text_rx(int64_t lo, int64_t hi);                       /* NULL unless constrained */
const RxSet *rx_single(Content *c, Sym pat, bool neg, char *err, size_t errlen);
const RxSet *rx_union(Content *c, const RxSet *a, const RxSet *b);
const RxSet *rx_common(Content *c, const RxSet *a, const RxSet *b); /* NULL if they share none */
const RxSet *rx_satisfied(Content *c, const RxSet *s, Sym text);    /* those text meets; NULL if none */
bool         rx_accepts(const RxSet *s, Sym text);                  /* text: a canonical string or a name */
bool         rx_subset(const RxSet *a, const RxSet *b);
void         rx_print(Buf *b, const RxSet *s);                      /* =~"..." & !~"..." */
void         rx_free_all(Content *c);

/* Parses a source into declarations appended to the content. Returns false on
 * error (diagnostics recorded). */
bool parse_source(Content *c, Sym file, const char *src, DeclVec *out);
/* Parses a single expression. */
X   *parse_expr_string(Content *c, Sym file, const char *src);

/* --- types ------------------------------------------------------------------------ */

/* TK_DISJ: an anonymous disjunction of structures; TK_ALT: one of its
 * alternatives (or of a named type defined as a disjunction). */
typedef enum { TK_TOP, TK_DIM, TK_ATOMROOT, TK_DEF, TK_ATOM, TK_ANON, TK_GLB, TK_DISJ, TK_ALT } TypeKind;

/* A disjunction of structures in a type body. Types are referred to by name,
 * since IDs change when the hierarchy is renumbered. */
typedef struct {
    X     *orx;                 /* the disjunction */
    Sym    owner;               /* named type defined by it, or NULL */
    Sym    dname;               /* the disjunction's type */
    XPtrVec altx;               /* alternatives, in written order, defaults unwrapped */
    SymVec alts;                /* their types, in written order */
    int    def;                 /* the default alternative, or -1 */
    Sym    collapse;            /* one alternative subsumes the others: just that type */
    Loc    loc;
} DisjInfo;

/* A default (`*v`) or a @vary record, at a path relative to its contributor. */
typedef struct {
    U32Vec path;
    X       *value;
    uint32_t contributor;     /* type, or CONTRIB_INSTANCE */
    const char *vary;         /* @vary weights; NULL for a default */
} DefaultRec;

#define CONTRIB_INSTANCE 0xFFFFFFFEu

typedef struct { Sym name; U32Vec path; } TagPath;

/* An arithmetic constraint: the value at `path` is `expr`, whose tags are at
 * the given paths (all relative to the structure that declares it). */
typedef struct {
    U32Vec path;
    X     *expr;
    VEC(TagPath) tags;
} ArithRec;
typedef VEC(ArithRec) ArithVec;

typedef VEC(DefaultRec) DefVec;

typedef struct {
    Sym      name;
    TypeKind kind;
    int      dim;                       /* TK_DIM only */
    U32Vec parents;              /* primary first */
    U32Vec children;
    uint64_t *code;                     /* descendants, including self; NULL for leaves */
    uint32_t  wlo, whi;                 /* the code's non-zero words lie in [wlo, whi) */
    int32_t   bit;                      /* position in codes, or -1 for leaves */
    U32Vec feats;                /* appropriate features, ascending */
    VEC(Decl *) decls;                  /* declarations naming this type */
    SymVec    members;                  /* ANON / GLB: member names, for naming */
    int       xstate;                   /* 0 none, 1 in progress, 2 done */
    TriNode  *expansion;
    DefVec    defaults;                 /* own and inherited, relative to root */
    DefVec    varies;                   /* @vary records, likewise */
    ArithVec  ariths;                   /* arithmetic constraints, own and inherited */
    Sym       component;                /* @component name, or NULL */
    bool      isdisj;                   /* its subtypes are alternatives (TK_ALT) */
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
    bool     forced;             /* a lazy node whose constraint this operation applied */
} Scratch;

/* NF_LAZY: the constraint of the node's type is not applied yet, because the
 * type was being expanded when the node was made (a recursive constraint). It
 * is applied when unification adds structure to the node. */
enum { NF_SCRATCH = 1, NF_DIM = 2, NF_LAZY = 4 };

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


/* One combination of an instance's alternatives (an instance without
 * disjunctions of structures has exactly one). */
typedef struct {
    TriNode  *pattern;
    VEC(TagPath) tags;
    DefVec    defaults;          /* instance-level */
    DefVec    varies;            /* instance-level @vary records */
    uint64_t  weight;            /* product of @vary weights of the alternatives taken */
    uint64_t  hasdef, tookdef;   /* defaulted disjunctions crossed, and those whose default it took */
    TriNode  *spec;              /* set if the variant survives into the spec */
    PathVec   varpaths;          /* its variation points */
    DefVec    specvaries;        /* @vary records over the spec, kept once constructed */
    ArithVec  ariths;            /* instance-level arithmetic constraints */
    bool      vcached;
} InstVariant;

typedef struct {
    Sym       name;
    VEC(Decl *) decls;
    int       pstate;            /* 0 none, 1 in progress, 2 done, 3 failed */
    VEC(InstVariant) vars;
    TriNode  *pattern;           /* the only variant's pattern, or the generalisation */
    int       sstate;
    TriNode  *spec;              /* likewise for specs */
    U32Vec    specvars;          /* variants that are specs: defaults may choose among them */
    VEC(char *) variation;       /* paths, printable */
    VEC(char *) notes;
} InstInfo;

/* --- families and functions ------------------------------------------------------------ */

typedef struct {
    Sym name;
    U32Vec insts;                /* member instances, in name order */
    TriQuickCheck *qc;
    TriIndex *index;
    U64Map failcount;            /* failure path Sym → count, when recording */
    SymVec failpaths;            /* the paths, in the order first seen */
} Family;

typedef struct { Sym name; TriFn fn; void *ctx; } FnReg;

/* --- the content object ------------------------------------------------------------- */

typedef struct { bool error; char *msg; Loc loc; } Diag;   /* loc.file NULL: no location */

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
    struct { uint64_t key; uint32_t val; } meetcache[4096];   /* direct-mapped, in front of meetmemo */

    VEC(FeatInfo) feats;
    U64Map featidx;              /* Sym → feature id + 1 */

    VEC(InstInfo) insts;
    U64Map instidx;

    U32Vec **leafcache;          /* type → its enum leaves, computed on demand */

    XPtrVec listelems;           /* element expressions of typed lists [...X] */
    VEC(Family) families;
    bool recording;              /* count failure paths of family matches */
    VEC(char *) buildlog;        /* generated types and dropped defaults, for the developer */
    size_t narith;               /* arithmetic constraints anywhere: none means nothing to propagate */
    const ArithVec *varskip;     /* instance-level arithmetic targets, not variation points */
    VEC(FnReg) fns;
    VEC(RxSet *) rxsets;         /* interned regex constraint sets */
    U64Map rxsetidx;             /* hash of a set → index + 1 (probed) */
    U64Map rxcache;              /* pattern Sym → compiled Regex */
    VEC(DisjInfo) disjs;
    U64Map disjidx;              /* X * of a disjunction → index + 1 */

    bool tdl;
    uint32_t top, atomroot, stringroot, dimtype[NDIMS], tlist, tcons, tnull, tbool;
    uint32_t ffirst, frest;

    /* generations */
    uint32_t gen, genctr, cgenctr;
    int opdepth;                 /* nesting of operations; 1 = top level */

    /* failure recording */
    uint32_t pathstack[128];
    int depth;
    bool failed;
    TriFailure fail_;            /* formatted on demand: read it through fail_info() */
    bool failfmt;                /* fail_ is up to date */
    uint32_t failpath[128];      /* the failing path, as feature IDs */
    int faildepth;
    struct { const char *why; uint32_t ltype, rtype; int64_t llo, lhi, rlo, rhi; bool hasr; } failraw;
    char failwhy[256];           /* a failure's reason, when it is made up on the spot */

    uint64_t hash;
    bool loaded;                 /* load is over: the rest are runtime operations */
    TriStats stats;
    bool cyclic;                 /* set when sharing meets a cycle during copy_out */
};

/* Strings are interned in one canonical spelling, quotes included: what a
 * literal means, re-escaped so it reads back the same ("a\"b", never
 * "a\u0022b"). string_canonical makes it from the bytes a literal denotes;
 * string_decode gives those bytes back. */
Sym  string_canonical(Content *c, const char *bytes, size_t n);
void string_decode(const char *quoted, Buf *out);

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
const U32Vec *enum_leaves(Content *c, uint32_t t);        /* an enum's leaves, ascending */
Sym      anon_name(Content *c, X *orx);
Sym      list_type_name(Content *c, const X *elem, bool cons);

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
TriFailure *fail_info(Content *c);                        /* the last failure, formatted */
TriNode *copy_raw(Content *c, TriArena *a, TriNode *n);
TriNode *copy_out(Content *c, TriArena *a, TriNode *n, bool *closed_ok);
void     copy_out_many(Content *c, TriArena *a, TriNode **roots, size_t n);
TriNode *node_arc(TriNode *n, uint32_t f);                /* final structures only */
void     node_iv(Content *c, TriNode *n, int64_t *lo, int64_t *hi);
void     fs_print(Content *c, Buf *b, TriNode *n);
void     path_format(Content *c, Buf *b, const uint32_t *path, size_t n);
bool     path_parse(Content *c, const char *s, U32Vec *out);
TriNode *node_at(TriNode *n, const uint32_t *path, size_t len);
bool     ext_equal(Content *c, TriNode *a, TriNode *b);
TriNode *fs_generalise(Content *c, TriArena *out, TriNode *a, TriNode *b);

/* runtime.c */
void     families_build(Content *c);
void     families_free(Content *c);
void     family_record_failure(Content *c, uint32_t inst, const char *path);

/* load.c */
TriNode *type_expansion(Content *c, uint32_t t);      /* NULL while t is being expanded */
TriNode *type_instance(Content *c, uint32_t t, TriArena *a);   /* a copy, or a lazy node */
bool     is_lazy(Content *c, TriNode *n);
TriNode *materialize(Content *c, TriNode *n);
bool     inst_pattern(Content *c, uint32_t inst);
bool     inst_spec(Content *c, uint32_t inst);
TriNode *settle_alternatives(Content *c, TriNode *root, TriArena *arena, TriFailure *fail);
TriNode *settle(Content *c, TriNode *root, const ArithVec *extra, TriArena *arena, TriFailure *fail);
const char *field_flags(const Content *c, uint32_t f);
bool     has_flag(const char *flags, const char *flag);
const char *attr_args(const Attr *attrs, int n, const char *name);
const char *field_attr(Content *c, uint32_t t, uint32_t f, const char *name);

#endif
