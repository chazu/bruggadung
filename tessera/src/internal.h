#ifndef TESS_INTERNAL_H
#define TESS_INTERNAL_H

#include "tessera.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    char    *name;
    int32_t *values;
    int32_t  lo, hi;
    uint32_t flags;
} Overlay;

typedef struct {
    tess_note_kind kind;
    uint32_t       flags;
    uint16_t       look;
    tess_point    *points;
    size_t         npoints;
    char          *text;
} Note;

struct tess_scene {
    tess_meta   meta;
    tess_extent ext;
    tess_cell  *cells;
    size_t      ncells;
    char      **looks;           /* looks[k - 1] names key k */
    size_t      nlooks, looks_cap;
    tess_mark  *marks;           /* by id; labels owned */
    size_t      nmarks, marks_cap;
    Overlay    *ovls;
    size_t      novls;
    Note       *notes;
    size_t      nnotes;
};

#define TESS_MAX_LOOKS 65535u

char *tess_strdup(const char *s);
int   tess_extent_ok(tess_extent e, size_t *ncells);
void  tess_cell_blank(tess_cell *c);
int   tess_cell_same(const tess_cell *a, const tess_cell *b);
int   tess_mark_same(const tess_mark *a, const tess_mark *b);
int   tess_overlay_same(const Overlay *a, const Overlay *b, size_t ncells);
int   tess_note_same(const Note *a, const Note *b);
/* Adds a look by name with no checks of its own: decoding builds tables as given. */
int   tess_look_append(tess_scene *s, const char *name, size_t n);

#endif
