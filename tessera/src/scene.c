/* Scenes: building, copying, reading. */
#include "internal.h"

char *tess_strdup(const char *s)
{
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *d = malloc(n);
    if (d) memcpy(d, s, n);
    return d;
}

int tess_extent_ok(tess_extent e, size_t *ncells)
{
    if (e.w <= 0 || e.h <= 0 || e.z1 < e.z0 || e.focus < e.z0 || e.focus > e.z1) return 0;
    uint64_t n = (uint64_t) e.w * (uint64_t) e.h * ((uint64_t) e.z1 - (uint64_t) e.z0 + 1u);
    if (n > TESS_MAX_CELLS) return 0;
    /* tile coordinates stay in range */
    if ((int64_t) e.x0 + e.w > INT32_MAX || (int64_t) e.y0 + e.h > INT32_MAX) return 0;
    if (ncells) *ncells = (size_t) n;
    return 1;
}

void tess_cell_blank(tess_cell *c)
{
    memset(c, 0, sizeof *c);
    c->seen = -1;
}

int tess_cell_same(const tess_cell *a, const tess_cell *b)
{
    return a->seen == b->seen && a->fluid == b->fluid && a->terrain == b->terrain && a->flags == b->flags &&
           a->light == b->light;
}

static int str_same(const char *a, const char *b)
{
    return a == b || (a && b && !strcmp(a, b));
}

int tess_mark_same(const tess_mark *a, const tess_mark *b)
{
    return a->id == b->id && a->holder == b->holder && a->seen == b->seen && a->x == b->x && a->y == b->y &&
           a->z == b->z && a->look == b->look && a->stack == b->stack && a->flags == b->flags &&
           str_same(a->label, b->label);
}

int tess_overlay_same(const Overlay *a, const Overlay *b, size_t ncells)
{
    return !strcmp(a->name, b->name) && a->lo == b->lo && a->hi == b->hi && a->flags == b->flags &&
           !memcmp(a->values, b->values, ncells * sizeof *a->values);
}

int tess_note_same(const Note *a, const Note *b)
{
    if (a->kind != b->kind || a->flags != b->flags || a->look != b->look || a->npoints != b->npoints ||
        !str_same(a->text, b->text))
        return 0;
    for (size_t i = 0; i < a->npoints; i++)
        if (a->points[i].x != b->points[i].x || a->points[i].y != b->points[i].y || a->points[i].z != b->points[i].z)
            return 0;
    return 1;
}

/* --- the scene ------------------------------------------------------------------------- */

tess_scene *tess_scene_new(tess_meta meta, tess_extent extent)
{
    size_t n;
    if (!tess_extent_ok(extent, &n) || (meta.view != TESS_TRUTH && meta.view != TESS_KNOWLEDGE)) return NULL;
    tess_scene *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    s->cells = malloc(n * sizeof *s->cells);
    if (!s->cells) { free(s); return NULL; }
    for (size_t i = 0; i < n; i++) tess_cell_blank(&s->cells[i]);
    s->meta = meta;
    s->ext = extent;
    s->ncells = n;
    return s;
}

void tess_scene_free(tess_scene *s)
{
    if (!s) return;
    for (size_t i = 0; i < s->nlooks; i++) free(s->looks[i]);
    free(s->looks);
    for (size_t i = 0; i < s->nmarks; i++) free((char *) s->marks[i].label);
    free(s->marks);
    for (size_t i = 0; i < s->novls; i++) { free(s->ovls[i].name); free(s->ovls[i].values); }
    free(s->ovls);
    for (size_t i = 0; i < s->nnotes; i++) { free(s->notes[i].points); free(s->notes[i].text); }
    free(s->notes);
    free(s->cells);
    free(s);
}

tess_scene *tess_scene_copy(const tess_scene *src)
{
    if (!src) return NULL;
    tess_scene *s = tess_scene_new(src->meta, src->ext);
    if (!s) return NULL;
    memcpy(s->cells, src->cells, src->ncells * sizeof *s->cells);
    for (size_t i = 0; i < src->nlooks; i++)
        if (!tess_look_append(s, src->looks[i], strlen(src->looks[i]))) goto fail;
    for (size_t i = 0; i < src->nmarks; i++)
        if (!tess_mark_put(s, &src->marks[i])) goto fail;
    for (size_t i = 0; i < src->novls; i++) {
        const Overlay *o = &src->ovls[i];
        int32_t *v = tess_overlay_put(s, o->name, o->lo, o->hi, o->flags);
        if (!v) goto fail;
        memcpy(v, o->values, src->ncells * sizeof *v);
    }
    for (size_t i = 0; i < src->nnotes; i++) {
        const Note *n = &src->notes[i];
        if (!tess_note_add(s, n->kind, n->flags, n->look, n->points, n->npoints, n->text)) goto fail;
    }
    return s;
fail:
    tess_scene_free(s);
    return NULL;
}

tess_meta tess_scene_meta(const tess_scene *s) { return s->meta; }
void tess_scene_set_meta(tess_scene *s, tess_meta meta)
{
    if (meta.view == TESS_TRUTH || meta.view == TESS_KNOWLEDGE) s->meta = meta;
}
tess_extent tess_scene_extent(const tess_scene *s) { return s->ext; }

int tess_scene_set_focus(tess_scene *s, int32_t focus)
{
    if (focus < s->ext.z0 || focus > s->ext.z1) return 0;
    s->ext.focus = focus;
    return 1;
}

/* --- appearance keys ----------------------------------------------------------------------- */

int tess_look_append(tess_scene *s, const char *name, size_t n)
{
    if (s->nlooks >= TESS_MAX_LOOKS) return 0;
    if (s->nlooks == s->looks_cap) {
        size_t cap = s->looks_cap ? s->looks_cap * 2 : 16;
        char **v = realloc(s->looks, cap * sizeof *v);
        if (!v) return 0;
        s->looks = v;
        s->looks_cap = cap;
    }
    char *d = malloc(n + 1);
    if (!d) return 0;
    memcpy(d, name, n);
    d[n] = 0;
    s->looks[s->nlooks++] = d;
    return 1;
}

uint16_t tess_look_find(const tess_scene *s, const char *name)
{
    if (!name || !*name) return 0;
    for (size_t i = 0; i < s->nlooks; i++)
        if (!strcmp(s->looks[i], name)) return (uint16_t) (i + 1);
    return 0;
}

uint16_t tess_look(tess_scene *s, const char *name)
{
    uint16_t k = tess_look_find(s, name);
    if (k || !name || !*name) return k;
    return tess_look_append(s, name, strlen(name)) ? (uint16_t) s->nlooks : 0;
}

const char *tess_look_name(const tess_scene *s, uint16_t key)
{
    return key && key <= s->nlooks ? s->looks[key - 1] : NULL;
}

size_t tess_look_count(const tess_scene *s) { return s->nlooks; }

/* --- cells ------------------------------------------------------------------------------- */

size_t tess_cell_index(const tess_scene *s, int32_t x, int32_t y, int32_t z)
{
    const tess_extent *e = &s->ext;
    int64_t dx = (int64_t) x - e->x0, dy = (int64_t) y - e->y0;
    if (dx < 0 || dy < 0 || dx >= e->w || dy >= e->h || z < e->z0 || z > e->z1) return (size_t) -1;
    return ((size_t) (z - e->z0) * (size_t) e->h + (size_t) dy) * (size_t) e->w + (size_t) dx;
}

tess_cell *tess_cell_at(tess_scene *s, int32_t x, int32_t y, int32_t z)
{
    size_t i = tess_cell_index(s, x, y, z);
    return i == (size_t) -1 ? NULL : &s->cells[i];
}

const tess_cell *tess_cell_get(const tess_scene *s, int32_t x, int32_t y, int32_t z)
{
    size_t i = tess_cell_index(s, x, y, z);
    return i == (size_t) -1 ? NULL : &s->cells[i];
}

size_t tess_cell_count(const tess_scene *s) { return s->ncells; }
const tess_cell *tess_cells(const tess_scene *s) { return s->cells; }

/* --- marks ------------------------------------------------------------------------------- */

static size_t mark_slot(const tess_scene *s, uint64_t id, int *found)
{
    size_t lo = 0, hi = s->nmarks;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (s->marks[mid].id < id) lo = mid + 1;
        else hi = mid;
    }
    *found = lo < s->nmarks && s->marks[lo].id == id;
    return lo;
}

int tess_mark_put(tess_scene *s, const tess_mark *m)
{
    if (!m || !m->id || m->holder == m->id) return 0;
    char *label = NULL;
    if (m->label && !(label = tess_strdup(m->label))) return 0;
    int found;
    size_t i = mark_slot(s, m->id, &found);
    if (found) {
        free((char *) s->marks[i].label);
    } else {
        if (s->nmarks == s->marks_cap) {
            size_t cap = s->marks_cap ? s->marks_cap * 2 : 64;
            tess_mark *v = realloc(s->marks, cap * sizeof *v);
            if (!v) { free(label); return 0; }
            s->marks = v;
            s->marks_cap = cap;
        }
        memmove(&s->marks[i + 1], &s->marks[i], (s->nmarks - i) * sizeof *s->marks);
        s->nmarks++;
    }
    s->marks[i] = *m;
    s->marks[i].label = label;
    return 1;
}

int tess_mark_remove(tess_scene *s, uint64_t id)
{
    int found;
    size_t i = mark_slot(s, id, &found);
    if (!found) return 0;
    free((char *) s->marks[i].label);
    memmove(&s->marks[i], &s->marks[i + 1], (s->nmarks - i - 1) * sizeof *s->marks);
    s->nmarks--;
    return 1;
}

size_t tess_mark_count(const tess_scene *s) { return s->nmarks; }
const tess_mark *tess_mark_at(const tess_scene *s, size_t i) { return i < s->nmarks ? &s->marks[i] : NULL; }

const tess_mark *tess_mark_find(const tess_scene *s, uint64_t id)
{
    int found;
    size_t i = mark_slot(s, id, &found);
    return found ? &s->marks[i] : NULL;
}

/* --- overlays and notes -------------------------------------------------------------------- */

int32_t *tess_overlay_put(tess_scene *s, const char *name, int32_t lo, int32_t hi, uint32_t flags)
{
    if (!name || !*name) return NULL;
    for (size_t i = 0; i < s->novls; i++)
        if (!strcmp(s->ovls[i].name, name)) {
            s->ovls[i].lo = lo;
            s->ovls[i].hi = hi;
            s->ovls[i].flags = flags;
            return s->ovls[i].values;
        }
    Overlay *v = realloc(s->ovls, (s->novls + 1) * sizeof *v);
    if (!v) return NULL;
    s->ovls = v;
    Overlay o = { tess_strdup(name), calloc(s->ncells, sizeof(int32_t)), lo, hi, flags };
    if (!o.name || !o.values) { free(o.name); free(o.values); return NULL; }
    size_t at = 0;                         /* by name: the order never depends on history */
    while (at < s->novls && strcmp(s->ovls[at].name, name) < 0) at++;
    memmove(&s->ovls[at + 1], &s->ovls[at], (s->novls - at) * sizeof *s->ovls);
    s->ovls[at] = o;
    s->novls++;
    return o.values;
}

size_t tess_overlay_count(const tess_scene *s) { return s->novls; }

tess_overlay tess_overlay_at(const tess_scene *s, size_t i)
{
    tess_overlay r = { 0 };
    if (i < s->novls) {
        r.name = s->ovls[i].name;
        r.values = s->ovls[i].values;
        r.lo = s->ovls[i].lo;
        r.hi = s->ovls[i].hi;
        r.flags = s->ovls[i].flags;
    }
    return r;
}

int tess_note_add(tess_scene *s, tess_note_kind kind, uint32_t flags, uint16_t look, const tess_point *points,
                  size_t npoints, const char *text)
{
    if (!points || !npoints || (kind == TESS_CALLOUT && npoints != 1) || (unsigned) kind > TESS_CALLOUT) return 0;
    if (npoints > SIZE_MAX / sizeof *points) return 0;
    Note n = { kind, flags, look, malloc(npoints * sizeof *points), npoints, NULL };
    if (!n.points || (text && !(n.text = tess_strdup(text)))) { free(n.points); return 0; }
    memcpy(n.points, points, npoints * sizeof *points);
    Note *v = realloc(s->notes, (s->nnotes + 1) * sizeof *v);
    if (!v) { free(n.points); free(n.text); return 0; }
    s->notes = v;
    s->notes[s->nnotes++] = n;
    return 1;
}

size_t tess_note_count(const tess_scene *s) { return s->nnotes; }

tess_note tess_note_at(const tess_scene *s, size_t i)
{
    tess_note r = { 0 };
    if (i < s->nnotes) {
        r.kind = s->notes[i].kind;
        r.flags = s->notes[i].flags;
        r.look = s->notes[i].look;
        r.points = s->notes[i].points;
        r.npoints = s->notes[i].npoints;
        r.text = s->notes[i].text;
    }
    return r;
}

size_t tess_strip_developer(tess_scene *s)
{
    size_t removed = 0, k = 0;
    for (size_t i = 0; i < s->novls; i++) {
        if (s->ovls[i].flags & TESS_DEVELOPER) { free(s->ovls[i].name); free(s->ovls[i].values); removed++; }
        else s->ovls[k++] = s->ovls[i];
    }
    s->novls = k;
    k = 0;
    for (size_t i = 0; i < s->nnotes; i++) {
        if (s->notes[i].flags & TESS_DEVELOPER) { free(s->notes[i].points); free(s->notes[i].text); removed++; }
        else s->notes[k++] = s->notes[i];
    }
    s->nnotes = k;
    return removed;
}
