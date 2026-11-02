/* Frames and diffs: the binary form scenes travel in.
 *
 *   "TESS" format kind          kind 1 a frame, 2 a diff
 *   meta                        view, seq, time, content, viewer
 *   frame: extent, looks, cells, marks, overlays, notes
 *   diff:  the seq it follows, focus, looks added, cells changed (spans),
 *          marks removed and put, overlays removed and put, notes (all, if
 *          any changed)
 *
 * Integers are LEB128 varints, signed ones zigzagged; the content hash is
 * eight bytes, little-endian; a string is its length and bytes, one that
 * may be absent its length plus one (0: absent). Runs of equal cells, and
 * of equal overlay values, are stored once with their length. Decoding
 * checks every length against what is left, so no input makes it read out
 * of bounds or allocate more than the input could describe. */
#include "internal.h"

#include <stdio.h>

enum { KIND_FRAME = 1, KIND_DIFF = 2 };

/* --- writing ---------------------------------------------------------------------------------- */

typedef struct { uint8_t *p; size_t n, cap; int ok; } W;

static void w_bytes(W *w, const void *b, size_t n)
{
    if (!w->ok) return;
    if (w->n + n > w->cap) {
        size_t cap = w->cap ? w->cap : 256;
        while (cap < w->n + n) cap *= 2;
        uint8_t *p = realloc(w->p, cap);
        if (!p) { w->ok = 0; return; }
        w->p = p;
        w->cap = cap;
    }
    memcpy(w->p + w->n, b, n);
    w->n += n;
}

static void w_u8(W *w, uint8_t v) { w_bytes(w, &v, 1); }

static void w_uv(W *w, uint64_t v)
{
    uint8_t b[10];
    size_t n = 0;
    do {
        b[n] = (uint8_t) (v & 0x7f);
        v >>= 7;
        if (v) b[n] |= 0x80;
        n++;
    } while (v);
    w_bytes(w, b, n);
}

static void w_sv(W *w, int64_t v) { w_uv(w, ((uint64_t) v << 1) ^ (uint64_t) (v >> 63)); }

static void w_u64(W *w, uint64_t v)
{
    uint8_t b[8];
    for (int i = 0; i < 8; i++) b[i] = (uint8_t) (v >> (8 * i));
    w_bytes(w, b, 8);
}

static void w_str(W *w, const char *s)
{
    size_t n = strlen(s);
    w_uv(w, n);
    w_bytes(w, s, n);
}

static void w_opt_str(W *w, const char *s)
{
    if (!s) { w_uv(w, 0); return; }
    size_t n = strlen(s);
    w_uv(w, (uint64_t) n + 1);
    w_bytes(w, s, n);
}

static void w_cell(W *w, const tess_cell *c)
{
    w_sv(w, c->seen);
    w_uv(w, c->fluid);
    w_uv(w, c->terrain);
    w_uv(w, c->flags);
    w_u8(w, c->light);
}

static void w_mark(W *w, const tess_mark *m)
{
    w_uv(w, m->id);
    w_uv(w, m->holder);
    w_sv(w, m->seen);
    w_sv(w, m->x);
    w_sv(w, m->y);
    w_sv(w, m->z);
    w_uv(w, m->look);
    w_sv(w, m->stack);
    w_uv(w, m->flags);
    w_opt_str(w, m->label);
}

static void w_overlay(W *w, const Overlay *o, size_t ncells)
{
    w_str(w, o->name);
    w_sv(w, o->lo);
    w_sv(w, o->hi);
    w_uv(w, o->flags);
    size_t runs = 0;
    for (size_t i = 0; i < ncells; runs++) {
        size_t j = i + 1;
        while (j < ncells && o->values[j] == o->values[i]) j++;
        i = j;
    }
    w_uv(w, runs);
    for (size_t i = 0; i < ncells;) {
        size_t j = i + 1;
        while (j < ncells && o->values[j] == o->values[i]) j++;
        w_uv(w, j - i);
        w_sv(w, o->values[i]);
        i = j;
    }
}

static void w_notes(W *w, const tess_scene *s)
{
    w_uv(w, s->nnotes);
    for (size_t i = 0; i < s->nnotes; i++) {
        const Note *n = &s->notes[i];
        w_u8(w, (uint8_t) n->kind);
        w_uv(w, n->flags);
        w_uv(w, n->look);
        w_uv(w, n->npoints);
        for (size_t k = 0; k < n->npoints; k++) {
            w_sv(w, n->points[k].x);
            w_sv(w, n->points[k].y);
            w_sv(w, n->points[k].z);
        }
        w_opt_str(w, n->text);
    }
}

static void w_head(W *w, int kind, const tess_meta *m)
{
    w_bytes(w, "TESS", 4);
    w_u8(w, TESS_FORMAT);
    w_u8(w, (uint8_t) kind);
    w_u8(w, (uint8_t) m->view);
    w_uv(w, m->seq);
    w_sv(w, m->time);
    w_u64(w, m->content);
    w_uv(w, m->viewer);
}

static int finish(W *w, tess_bytes *out)
{
    if (!w->ok) { free(w->p); out->data = NULL; out->len = 0; return 0; }
    out->data = w->p;
    out->len = w->n;
    return 1;
}

void tess_bytes_free(tess_bytes *b)
{
    if (!b) return;
    free(b->data);
    b->data = NULL;
    b->len = 0;
}

int tess_encode_frame(const tess_scene *s, tess_bytes *out)
{
    W w = { NULL, 0, 0, 1 };
    w_head(&w, KIND_FRAME, &s->meta);
    w_sv(&w, s->ext.x0);
    w_sv(&w, s->ext.y0);
    w_uv(&w, (uint64_t) s->ext.w);
    w_uv(&w, (uint64_t) s->ext.h);
    w_sv(&w, s->ext.z0);
    w_sv(&w, s->ext.z1);
    w_sv(&w, s->ext.focus);
    w_uv(&w, s->nlooks);
    for (size_t i = 0; i < s->nlooks; i++) w_str(&w, s->looks[i]);
    /* cells, in runs */
    size_t runs = 0;
    for (size_t i = 0; i < s->ncells; runs++) {
        size_t j = i + 1;
        while (j < s->ncells && tess_cell_same(&s->cells[j], &s->cells[i])) j++;
        i = j;
    }
    w_uv(&w, runs);
    for (size_t i = 0; i < s->ncells;) {
        size_t j = i + 1;
        while (j < s->ncells && tess_cell_same(&s->cells[j], &s->cells[i])) j++;
        w_uv(&w, j - i);
        w_cell(&w, &s->cells[i]);
        i = j;
    }
    w_uv(&w, s->nmarks);
    for (size_t i = 0; i < s->nmarks; i++) w_mark(&w, &s->marks[i]);
    w_uv(&w, s->novls);
    for (size_t i = 0; i < s->novls; i++) w_overlay(&w, &s->ovls[i], s->ncells);
    w_notes(&w, s);
    return finish(&w, out);
}

/* Whether `to` can be said as changes to `from`. */
static int diffable(const tess_scene *from, const tess_scene *to)
{
    const tess_extent *a = &from->ext, *b = &to->ext;
    if (from->meta.view != to->meta.view || from->meta.viewer != to->meta.viewer || a->x0 != b->x0 ||
        a->y0 != b->y0 || a->w != b->w || a->h != b->h || a->z0 != b->z0 || a->z1 != b->z1)
        return 0;
    if (to->nlooks < from->nlooks) return 0;
    for (size_t i = 0; i < from->nlooks; i++)
        if (strcmp(from->looks[i], to->looks[i])) return 0;
    return 1;
}

static const Overlay *overlay_named(const tess_scene *s, const char *name)
{
    for (size_t i = 0; i < s->novls; i++)
        if (!strcmp(s->ovls[i].name, name)) return &s->ovls[i];
    return NULL;
}

int tess_encode_diff(const tess_scene *from, const tess_scene *to, tess_bytes *out, int *is_frame)
{
    if (!from || !diffable(from, to)) {
        if (is_frame) *is_frame = 1;
        return tess_encode_frame(to, out);
    }
    if (is_frame) *is_frame = 0;
    W w = { NULL, 0, 0, 1 };
    w_head(&w, KIND_DIFF, &to->meta);
    w_uv(&w, from->meta.seq);
    w_sv(&w, to->ext.focus);
    w_uv(&w, to->nlooks - from->nlooks);
    for (size_t i = from->nlooks; i < to->nlooks; i++) w_str(&w, to->looks[i]);
    /* cells: spans of changed ones, each after a gap from the last */
    size_t spans = 0;
    for (size_t i = 0; i < to->ncells;) {
        if (tess_cell_same(&from->cells[i], &to->cells[i])) { i++; continue; }
        while (i < to->ncells && !tess_cell_same(&from->cells[i], &to->cells[i])) i++;
        spans++;
    }
    w_uv(&w, spans);
    size_t end = 0;
    for (size_t i = 0; i < to->ncells;) {
        if (tess_cell_same(&from->cells[i], &to->cells[i])) { i++; continue; }
        size_t j = i;
        while (j < to->ncells && !tess_cell_same(&from->cells[j], &to->cells[j])) j++;
        w_uv(&w, i - end);
        w_uv(&w, j - i);
        for (size_t k = i; k < j; k++) w_cell(&w, &to->cells[k]);
        end = j;
        i = j;
    }
    /* marks: removed (ids rising, by their gaps), then put */
    size_t removed = 0, put = 0;
    for (size_t i = 0; i < from->nmarks; i++) removed += !tess_mark_find(to, from->marks[i].id);
    for (size_t i = 0; i < to->nmarks; i++) {
        const tess_mark *was = tess_mark_find(from, to->marks[i].id);
        put += !was || !tess_mark_same(was, &to->marks[i]);
    }
    w_uv(&w, removed);
    uint64_t last = 0;
    for (size_t i = 0; i < from->nmarks; i++)
        if (!tess_mark_find(to, from->marks[i].id)) {
            w_uv(&w, from->marks[i].id - last);
            last = from->marks[i].id;
        }
    w_uv(&w, put);
    for (size_t i = 0; i < to->nmarks; i++) {
        const tess_mark *was = tess_mark_find(from, to->marks[i].id);
        if (!was || !tess_mark_same(was, &to->marks[i])) w_mark(&w, &to->marks[i]);
    }
    /* overlays: removed by name, then put whole */
    removed = put = 0;
    for (size_t i = 0; i < from->novls; i++) removed += !overlay_named(to, from->ovls[i].name);
    for (size_t i = 0; i < to->novls; i++) {
        const Overlay *was = overlay_named(from, to->ovls[i].name);
        put += !was || !tess_overlay_same(was, &to->ovls[i], to->ncells);
    }
    w_uv(&w, removed);
    for (size_t i = 0; i < from->novls; i++)
        if (!overlay_named(to, from->ovls[i].name)) w_str(&w, from->ovls[i].name);
    w_uv(&w, put);
    for (size_t i = 0; i < to->novls; i++) {
        const Overlay *was = overlay_named(from, to->ovls[i].name);
        if (!was || !tess_overlay_same(was, &to->ovls[i], to->ncells)) w_overlay(&w, &to->ovls[i], to->ncells);
    }
    /* notes: all of them, if any changed */
    int same = from->nnotes == to->nnotes;
    for (size_t i = 0; same && i < to->nnotes; i++) same = tess_note_same(&from->notes[i], &to->notes[i]);
    w_u8(&w, same ? 0 : 1);
    if (!same) w_notes(&w, to);
    return finish(&w, out);
}

/* --- reading ------------------------------------------------------------------------------------ */

typedef struct { const uint8_t *p, *end; const char *err; } R;

static void r_fail(R *r, const char *why) { if (!r->err) r->err = why; }

static uint8_t r_u8(R *r)
{
    if (r->err || r->p >= r->end) { r_fail(r, "truncated"); return 0; }
    return *r->p++;
}

static uint64_t r_uv(R *r)
{
    uint64_t v = 0;
    for (int shift = 0; shift < 70; shift += 7) {
        uint8_t b = r_u8(r);
        if (r->err) return 0;
        if (shift == 63 && b > 1) { r_fail(r, "a number too large"); return 0; }
        v |= (uint64_t) (b & 0x7f) << shift;
        if (!(b & 0x80)) return v;
    }
    r_fail(r, "a number too large");
    return 0;
}

static int64_t r_sv(R *r)
{
    uint64_t u = r_uv(r);
    return (int64_t) (u >> 1) ^ -(int64_t) (u & 1);
}

static int32_t r_s32(R *r)
{
    int64_t v = r_sv(r);
    if (v < INT32_MIN || v > INT32_MAX) { r_fail(r, "a coordinate out of range"); return 0; }
    return (int32_t) v;
}

static uint64_t r_bounded(R *r, uint64_t max, const char *what)
{
    uint64_t v = r_uv(r);
    if (!r->err && v > max) r_fail(r, what);
    return r->err ? 0 : v;
}

static uint64_t r_u64(R *r)
{
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= (uint64_t) r_u8(r) << (8 * i);
    return v;
}

/* A count of items each at least `least` bytes: no more than the rest could hold. */
static size_t r_count(R *r, size_t least)
{
    uint64_t n = r_uv(r);
    if (!r->err && n > (uint64_t) (r->end - r->p) / (least ? least : 1)) r_fail(r, "a count larger than the data");
    return r->err ? 0 : (size_t) n;
}

/* A string's bytes, in the data (not terminated), or NULL. */
static const char *r_str(R *r, size_t *n, int optional, int *absent)
{
    uint64_t len = r_uv(r);
    if (r->err) return NULL;
    if (optional) {
        if (!len) { *absent = 1; *n = 0; return NULL; }
        len--;
    }
    if (absent) *absent = 0;
    if (len > (uint64_t) (r->end - r->p)) { r_fail(r, "truncated"); return NULL; }
    const char *s = (const char *) r->p;
    if (memchr(s, 0, (size_t) len)) { r_fail(r, "a string with a NUL in it"); return NULL; }
    r->p += len;
    *n = (size_t) len;
    return s;
}

/* A string copied out and terminated (or NULL when absent); the caller frees it. */
static char *r_dup(R *r, int optional)
{
    size_t n;
    int absent = 0;
    const char *s = r_str(r, &n, optional, &absent);
    if (r->err || absent) return NULL;
    char *d = malloc(n + 1);
    if (!d) { r_fail(r, "out of memory"); return NULL; }
    memcpy(d, s, n);
    d[n] = 0;
    return d;
}

static void r_cell(R *r, tess_cell *c)
{
    c->seen = r_sv(r);
    c->fluid = (uint32_t) r_bounded(r, UINT32_MAX, "a fluid out of range");
    c->terrain = (uint16_t) r_bounded(r, UINT16_MAX, "a key out of range");
    c->flags = (uint16_t) r_bounded(r, UINT16_MAX, "cell flags out of range");
    c->light = r_u8(r);
}

static int r_mark(R *r, tess_scene *s)
{
    tess_mark m;
    m.id = r_uv(r);
    m.holder = r_uv(r);
    m.seen = r_sv(r);
    m.x = r_s32(r);
    m.y = r_s32(r);
    m.z = r_s32(r);
    m.look = (uint16_t) r_bounded(r, UINT16_MAX, "a key out of range");
    int64_t stack = r_sv(r);
    if (stack < INT16_MIN || stack > INT16_MAX) r_fail(r, "a stack order out of range");
    m.stack = (int16_t) stack;
    m.flags = (uint16_t) r_bounded(r, UINT16_MAX, "mark flags out of range");
    char *label = r_dup(r, 1);
    m.label = label;
    if (!r->err && !tess_mark_put(s, &m)) r_fail(r, "a mark without an id, or its own holder");
    free(label);
    return !r->err;
}

static int r_overlay(R *r, tess_scene *s)
{
    char *name = r_dup(r, 0);
    int32_t lo = r_s32(r), hi = r_s32(r);
    uint32_t flags = (uint32_t) r_bounded(r, UINT32_MAX, "overlay flags out of range");
    size_t runs = r_count(r, 2);
    if (r->err || !name || !*name) { free(name); r_fail(r, "an overlay without a name"); return 0; }
    int32_t *v = tess_overlay_put(s, name, lo, hi, flags);
    free(name);
    if (!v) { r_fail(r, "out of memory"); return 0; }
    size_t at = 0;
    for (size_t i = 0; i < runs && !r->err; i++) {
        uint64_t n = r_uv(r);
        int32_t value = r_s32(r);
        if (r->err) break;
        if (!n || n > s->ncells - at) { r_fail(r, "an overlay's runs don't fit its cells"); break; }
        for (uint64_t k = 0; k < n; k++) v[at++] = value;
    }
    if (!r->err && at != s->ncells) r_fail(r, "an overlay's runs don't fit its cells");
    return !r->err;
}

static void clear_notes(tess_scene *s)
{
    for (size_t i = 0; i < s->nnotes; i++) { free(s->notes[i].points); free(s->notes[i].text); }
    s->nnotes = 0;
}

static int r_notes(R *r, tess_scene *s)
{
    size_t n = r_count(r, 5);
    for (size_t i = 0; i < n && !r->err; i++) {
        uint8_t kind = r_u8(r);
        uint32_t flags = (uint32_t) r_bounded(r, UINT32_MAX, "note flags out of range");
        uint16_t look = (uint16_t) r_bounded(r, UINT16_MAX, "a key out of range");
        size_t np = r_count(r, 3);
        if (r->err) break;
        tess_point *pts = malloc((np ? np : 1) * sizeof *pts);
        if (!pts) { r_fail(r, "out of memory"); break; }
        for (size_t k = 0; k < np; k++) {
            pts[k].x = r_s32(r);
            pts[k].y = r_s32(r);
            pts[k].z = r_s32(r);
        }
        char *text = r_dup(r, 1);
        if (!r->err && !tess_note_add(s, (tess_note_kind) kind, flags, look, pts, np, text))
            r_fail(r, "a note of no kind, or without its points");
        free(pts);
        free(text);
    }
    return !r->err;
}

static void set_err(char *err, size_t errlen, const char *why)
{
    if (err && errlen) snprintf(err, errlen, "%s", why);
}

static tess_scene *decode_frame(R *r, tess_meta meta)
{
    tess_extent e;
    e.x0 = r_s32(r);
    e.y0 = r_s32(r);
    e.w = (int32_t) r_bounded(r, INT32_MAX, "an extent out of range");
    e.h = (int32_t) r_bounded(r, INT32_MAX, "an extent out of range");
    e.z0 = r_s32(r);
    e.z1 = r_s32(r);
    e.focus = r_s32(r);
    if (r->err) return NULL;
    tess_scene *s = tess_scene_new(meta, e);
    if (!s) { r_fail(r, "an empty or oversized extent, or an unknown view"); return NULL; }
    size_t nlooks = r_count(r, 1);
    if (nlooks > TESS_MAX_LOOKS) r_fail(r, "too many appearance keys");
    for (size_t i = 0; i < nlooks && !r->err; i++) {
        size_t n;
        const char *name = r_str(r, &n, 0, NULL);
        if (!r->err && (!n || !tess_look_append(s, name, n))) r_fail(r, "an empty appearance key");
    }
    size_t runs = r_count(r, 6), at = 0;
    for (size_t i = 0; i < runs && !r->err; i++) {
        uint64_t n = r_uv(r);
        tess_cell c;
        r_cell(r, &c);
        if (r->err) break;
        if (!n || n > s->ncells - at) { r_fail(r, "the cells' runs don't fit the extent"); break; }
        for (uint64_t k = 0; k < n; k++) s->cells[at++] = c;
    }
    if (!r->err && at != s->ncells) r_fail(r, "the cells' runs don't fit the extent");
    size_t nm = r_count(r, 10);
    for (size_t i = 0; i < nm && !r->err; i++) r_mark(r, s);
    size_t no = r_count(r, 6);
    for (size_t i = 0; i < no && !r->err; i++) r_overlay(r, s);
    if (!r->err) r_notes(r, s);
    if (r->err) { tess_scene_free(s); return NULL; }
    return s;
}

static tess_scene *decode_diff(R *r, tess_meta meta, const tess_scene *base)
{
    uint64_t from = r_uv(r);
    int32_t focus = r_s32(r);
    if (r->err) return NULL;
    if (!base) { r_fail(r, "a diff without the frame it follows"); return NULL; }
    if (from != base->meta.seq) { r_fail(r, "a diff that follows another frame"); return NULL; }
    if (meta.view != base->meta.view || meta.viewer != base->meta.viewer) {
        r_fail(r, "a diff of another view");
        return NULL;
    }
    tess_scene *s = tess_scene_copy(base);
    if (!s) { r_fail(r, "out of memory"); return NULL; }
    s->meta = meta;
    if (!tess_scene_set_focus(s, focus)) r_fail(r, "a focus outside the extent");
    size_t added = r_count(r, 1);
    if (s->nlooks + added > TESS_MAX_LOOKS) r_fail(r, "too many appearance keys");
    for (size_t i = 0; i < added && !r->err; i++) {
        size_t n;
        const char *name = r_str(r, &n, 0, NULL);
        if (!r->err && (!n || !tess_look_append(s, name, n))) r_fail(r, "an empty appearance key");
    }
    size_t spans = r_count(r, 2), at = 0;
    for (size_t i = 0; i < spans && !r->err; i++) {
        uint64_t gap = r_uv(r), n = r_uv(r);
        if (r->err) break;
        if (gap > s->ncells - at || !n || n > s->ncells - at - gap) { r_fail(r, "changed cells outside the extent"); break; }
        at += (size_t) gap;
        for (uint64_t k = 0; k < n && !r->err; k++) r_cell(r, &s->cells[at++]);
    }
    size_t nr = r_count(r, 1);
    uint64_t id = 0;
    for (size_t i = 0; i < nr && !r->err; i++) {
        uint64_t gap = r_uv(r);
        if (r->err) break;
        if (!gap || gap > UINT64_MAX - id) { r_fail(r, "marks removed out of order"); break; }
        id += gap;
        if (!tess_mark_remove(s, id)) r_fail(r, "a mark removed that isn't there");
    }
    size_t np = r_count(r, 10);
    for (size_t i = 0; i < np && !r->err; i++) r_mark(r, s);
    size_t ro = r_count(r, 1);
    for (size_t i = 0; i < ro && !r->err; i++) {
        char *name = r_dup(r, 0);
        size_t k = 0;
        while (name && k < s->novls && strcmp(s->ovls[k].name, name)) k++;
        if (!r->err && (!name || k == s->novls)) r_fail(r, "an overlay removed that isn't there");
        else if (!r->err) {
            free(s->ovls[k].name);
            free(s->ovls[k].values);
            memmove(&s->ovls[k], &s->ovls[k + 1], (s->novls - k - 1) * sizeof *s->ovls);
            s->novls--;
        }
        free(name);
    }
    size_t po = r_count(r, 6);
    for (size_t i = 0; i < po && !r->err; i++) r_overlay(r, s);
    uint8_t notes = r_u8(r);
    if (!r->err && notes > 1) r_fail(r, "a diff's notes are malformed");
    if (!r->err && notes) {
        clear_notes(s);
        r_notes(r, s);
    }
    if (r->err) { tess_scene_free(s); return NULL; }
    return s;
}

tess_scene *tess_decode(const uint8_t *data, size_t len, const tess_scene *base, char *err, size_t errlen)
{
    R r = { data, data + len, NULL };
    if (!data || len < 6 || memcmp(data, "TESS", 4)) { set_err(err, errlen, "not a Tessera frame or diff"); return NULL; }
    r.p += 4;
    uint8_t format = r_u8(&r), kind = r_u8(&r);
    if (format != TESS_FORMAT) { set_err(err, errlen, "another version of the format"); return NULL; }
    tess_meta meta;
    uint8_t view = r_u8(&r);
    meta.view = (tess_view) view;
    meta.seq = r_uv(&r);
    meta.time = r_sv(&r);
    meta.content = r_u64(&r);
    meta.viewer = r_uv(&r);
    if (!r.err && view > TESS_KNOWLEDGE) r_fail(&r, "an unknown view");
    tess_scene *s = NULL;
    if (!r.err) {
        if (kind == KIND_FRAME) s = decode_frame(&r, meta);
        else if (kind == KIND_DIFF) s = decode_diff(&r, meta, base);
        else r_fail(&r, "neither a frame nor a diff");
    }
    if (!r.err && r.p != r.end) {
        r_fail(&r, "data after the end");
        tess_scene_free(s);
        s = NULL;
    }
    if (!s) set_err(err, errlen, r.err ? r.err : "malformed");
    return s;
}
