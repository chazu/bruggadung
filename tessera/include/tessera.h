/* Tessera: scenes of tile worlds with z-levels, for anything that draws them
 * (TESSERA.md).
 *
 * A scene is plain data: an extent of tiles over levels; a cell for each
 * tile at each level (its terrain, when it was seen, its light, its fluid);
 * marks, the things drawn on cells; overlays, scalar fields over the cells;
 * and notes, lines and callouts. A producer builds one from a simulation, a
 * backend draws it, and neither touches the other.
 *
 * Every scene has a view. A truth scene (the developer's) names entities; a
 * knowledge scene (one character's) names that character's referents, and
 * shows only what it knows. Overlays and notes may be tagged
 * TESS_DEVELOPER; a backend showing a player's view strips them.
 *
 * Scenes travel as frames (complete) and diffs (the changes since an earlier
 * frame), in a compact binary form: in-process, over a pipe, or in a
 * recording. */
#ifndef TESSERA_H
#define TESSERA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TESS_FORMAT 1                  /* the encoding's version */

typedef enum { TESS_TRUTH = 0, TESS_KNOWLEDGE = 1 } tess_view;

/* A rectangle of tiles over a range of levels, and the level looked at. */
typedef struct {
    int32_t x0, y0, w, h;              /* tiles */
    int32_t z0, z1;                    /* levels, inclusive */
    int32_t focus;                     /* z0 <= focus <= z1 */
} tess_extent;

/* What a scene is of: its view, its place in a stream of frames, the
 * simulation time, the content its appearance keys belong to, and (a
 * knowledge scene) whose knowledge it is. */
typedef struct {
    tess_view view;
    uint64_t  seq;                     /* frame sequence: a diff names the one it follows */
    int64_t   time;                    /* simulation ms */
    uint64_t  content;                 /* the content's hash */
    uint64_t  viewer;                  /* knowledge: the entity whose store it is */
} tess_meta;

/* A tile at one level. A new scene's cells are blank: terrain 0 (none),
 * never seen, dark, dry, no flags. */
enum {
    TESS_CELL_IN_SIGHT = 1u << 0,      /* seen now, not remembered */
    TESS_CELL_OPEN     = 1u << 1,      /* no floor: the level below shows through */
    TESS_CELL_DOOR     = 1u << 2,
};
typedef struct {
    int64_t  seen;                     /* ms it was last seen; -1 never */
    uint32_t fluid;                    /* water, mL on the tile */
    uint16_t terrain;                  /* appearance key of what the cell is */
    uint16_t flags;
    uint8_t  light;                    /* 0 dark .. 255 full daylight */
} tess_cell;

/* A thing drawn: on a cell, or, with a holder, held by or inside another
 * mark (drawn as that one; listed by a backend). */
enum {
    TESS_MARK_ACTOR    = 1u << 0,      /* the one the viewer plays or follows */
    TESS_MARK_GONE     = 1u << 1,      /* knowledge: no longer believed where it was seen */
    TESS_MARK_IN_SIGHT = 1u << 2,      /* knowledge: seen now, not remembered */
};
typedef struct {
    uint64_t    id;                    /* entity (truth) or referent (knowledge); unique in a scene, not 0 */
    uint64_t    holder;                /* the mark it is held by or inside, or 0 */
    int64_t     seen;                  /* knowledge: ms it was last seen */
    int32_t     x, y, z;               /* its tile (a held mark: its holder's) */
    uint16_t    look;                  /* appearance key */
    int16_t     stack;                 /* order among the marks on one cell, lowest first */
    uint16_t    flags;
    const char *label;                 /* or NULL; the scene keeps its own copy */
} tess_mark;

/* Overlays and notes the player may not see. */
#define TESS_DEVELOPER 1u

/* A scalar field over the extent's cells (heat, CO2, light, knowledge age),
 * with the range a backend maps to its palette. */
typedef struct {
    const char    *name;
    const int32_t *values;             /* one per cell, as tess_cell_index orders them */
    int32_t        lo, hi;
    uint32_t       flags;
} tess_overlay;

typedef enum { TESS_LINE = 0, TESS_ARROW = 1, TESS_PATH = 2, TESS_CALLOUT = 3 } tess_note_kind;
typedef struct { int32_t x, y, z; } tess_point;

/* A line, an arrow, a path through tiles, or a callout at a point. */
typedef struct {
    tess_note_kind    kind;
    uint32_t          flags;
    uint16_t          look;
    const tess_point *points;
    size_t            npoints;
    const char       *text;            /* or NULL */
} tess_note;

typedef struct tess_scene tess_scene;

/* --- building --------------------------------------------------------------------------- */

/* A blank scene, or NULL if the extent is empty, inverted, its focus out of
 * range, or over TESS_MAX_CELLS cells. */
#define TESS_MAX_CELLS (64u * 1024u * 1024u)
tess_scene *tess_scene_new(tess_meta meta, tess_extent extent);
tess_scene *tess_scene_copy(const tess_scene *s);
void        tess_scene_free(tess_scene *s);

tess_meta   tess_scene_meta(const tess_scene *s);
void        tess_scene_set_meta(tess_scene *s, tess_meta meta);
tess_extent tess_scene_extent(const tess_scene *s);
/* The focus may move within the extent's levels; 0 if it can't. */
int         tess_scene_set_focus(tess_scene *s, int32_t focus);

/* Appearance keys: a name's key, made if new (1, 2, ...); 0 for NULL or "".
 * Keys stay as they are made: a scene copied keeps them, and adds after. */
uint16_t    tess_look(tess_scene *s, const char *name);
uint16_t    tess_look_find(const tess_scene *s, const char *name);   /* 0 if none */
const char *tess_look_name(const tess_scene *s, uint16_t key);        /* NULL if none */
size_t      tess_look_count(const tess_scene *s);

/* The cell at a tile and level, or NULL outside the extent. */
tess_cell       *tess_cell_at(tess_scene *s, int32_t x, int32_t y, int32_t z);
const tess_cell *tess_cell_get(const tess_scene *s, int32_t x, int32_t y, int32_t z);
/* Cells in order: level by level from z0, row by row, x fastest. */
size_t           tess_cell_count(const tess_scene *s);
size_t           tess_cell_index(const tess_scene *s, int32_t x, int32_t y, int32_t z);   /* (size_t)-1 outside */
const tess_cell *tess_cells(const tess_scene *s);

/* Adds a mark, or replaces the one with its id; 0 if the id is 0 or its
 * holder is itself. Marks are kept in id order. */
int              tess_mark_put(tess_scene *s, const tess_mark *m);
int              tess_mark_remove(tess_scene *s, uint64_t id);
size_t           tess_mark_count(const tess_scene *s);
const tess_mark *tess_mark_at(const tess_scene *s, size_t i);
const tess_mark *tess_mark_find(const tess_scene *s, uint64_t id);

/* Adds an overlay, its values all 0, or returns the one of that name (its
 * range and flags updated): its values, to fill in; NULL for no name.
 * Overlays are kept in name order. */
int32_t     *tess_overlay_put(tess_scene *s, const char *name, int32_t lo, int32_t hi, uint32_t flags);
size_t       tess_overlay_count(const tess_scene *s);
tess_overlay tess_overlay_at(const tess_scene *s, size_t i);

/* Adds a note; 0 if it has no points, or a callout more than one. */
int       tess_note_add(tess_scene *s, tess_note_kind kind, uint32_t flags, uint16_t look,
                        const tess_point *points, size_t npoints, const char *text);
size_t    tess_note_count(const tess_scene *s);
tess_note tess_note_at(const tess_scene *s, size_t i);

/* What a player's view may show: the developer's overlays and notes taken
 * out. Returns how many were. */
size_t tess_strip_developer(tess_scene *s);

/* --- frames and diffs --------------------------------------------------------------------- */

typedef struct { uint8_t *data; size_t len; } tess_bytes;
void tess_bytes_free(tess_bytes *b);

/* A frame: the whole scene. */
int tess_encode_frame(const tess_scene *s, tess_bytes *out);
/* A diff: what `to` changes of `from` (whose seq it names). When a diff can't
 * say it (another view, extent, or viewer, or appearance keys not extending
 * from's), a frame instead. *is_frame (if given) says which. */
int tess_encode_diff(const tess_scene *from, const tess_scene *to, tess_bytes *out, int *is_frame);

/* A scene from a frame, or from a diff applied to `base` (whose seq it must
 * follow; base is left as it is). NULL, with the reason in err, if the data
 * is malformed, truncated, of another format, or a diff without its base. */
tess_scene *tess_decode(const uint8_t *data, size_t len, const tess_scene *base, char *err, size_t errlen);

/* --- text --------------------------------------------------------------------------------- */

/* The scene as text, a line for each thing in it, in a fixed order: for
 * tests, logs and diffs by eye. snprintf's contract: the length it needs. */
size_t tess_scene_text(const tess_scene *s, char *buf, size_t size);

#ifdef __cplusplus
}
#endif

#endif
