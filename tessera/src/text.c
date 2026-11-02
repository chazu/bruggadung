/* A scene as text: a line for each thing in it, in a fixed order, cells and
 * overlay values only where they differ from blank. Two scenes print the
 * same exactly when they are the same. */
#include "internal.h"

#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>

typedef struct { char *buf; size_t size, len; } T;

static void put(T *t, const char *fmt, ...)
{
    char small[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(small, sizeof small, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if ((size_t) n >= sizeof small) {                 /* long: format straight into place */
        if (t->len < t->size) {
            va_start(ap, fmt);
            vsnprintf(t->buf + t->len, t->size - t->len, fmt, ap);
            va_end(ap);
        }
    } else if (t->len < t->size) {
        size_t room = t->size - t->len;
        memcpy(t->buf + t->len, small, (size_t) n < room ? (size_t) n : room);
    }
    t->len += (size_t) n;
    if (t->size) t->buf[t->len < t->size ? t->len : t->size - 1] = 0;
}

static void put_quoted(T *t, const char *s)
{
    put(t, "\"");
    for (; *s; s++) {
        unsigned char c = (unsigned char) *s;
        if (c == '"' || c == '\\') put(t, "\\%c", c);
        else if (c == '\n') put(t, "\\n");
        else if (c < 0x20 || c == 0x7f) put(t, "\\x%02x", c);
        else put(t, "%c", c);
    }
    put(t, "\"");
}

static void put_xyz(T *t, const tess_scene *s, size_t i)
{
    const tess_extent *e = &s->ext;
    size_t per = (size_t) e->w * (size_t) e->h;
    put(t, "%" PRId64 " %" PRId64 " %" PRId64, (int64_t) e->x0 + (int64_t) (i % per % (size_t) e->w),
        (int64_t) e->y0 + (int64_t) (i % per / (size_t) e->w), (int64_t) e->z0 + (int64_t) (i / per));
}

size_t tess_scene_text(const tess_scene *s, char *buf, size_t size)
{
    T t = { buf, size, 0 };
    if (size) buf[0] = 0;
    const tess_meta *m = &s->meta;
    const tess_extent *e = &s->ext;
    put(&t, "tessera %s seq %" PRIu64 " time %" PRId64 " content %016" PRIx64 " viewer %" PRIu64 "\n",
        m->view == TESS_TRUTH ? "truth" : "knowledge", m->seq, m->time, m->content, m->viewer);
    put(&t, "extent %d %d %d %d levels %d %d focus %d\n", e->x0, e->y0, e->w, e->h, e->z0, e->z1, e->focus);
    for (size_t i = 0; i < s->nlooks; i++) {
        put(&t, "look %zu ", i + 1);
        put_quoted(&t, s->looks[i]);
        put(&t, "\n");
    }
    tess_cell blank;
    tess_cell_blank(&blank);
    for (size_t i = 0; i < s->ncells; i++) {
        const tess_cell *c = &s->cells[i];
        if (tess_cell_same(c, &blank)) continue;
        put(&t, "cell ");
        put_xyz(&t, s, i);
        put(&t, " terrain %u seen %" PRId64 " light %u fluid %u flags %u\n", c->terrain, c->seen, c->light, c->fluid,
            c->flags);
    }
    for (size_t i = 0; i < s->nmarks; i++) {
        const tess_mark *k = &s->marks[i];
        put(&t, "mark %" PRIu64 " at %d %d %d look %u stack %d flags %u seen %" PRId64 " holder %" PRIu64, k->id, k->x,
            k->y, k->z, k->look, k->stack, k->flags, k->seen, k->holder);
        if (k->label) {
            put(&t, " label ");
            put_quoted(&t, k->label);
        }
        put(&t, "\n");
    }
    for (size_t i = 0; i < s->novls; i++) {
        const Overlay *o = &s->ovls[i];
        put(&t, "overlay ");
        put_quoted(&t, o->name);
        put(&t, " lo %d hi %d flags %u\n", o->lo, o->hi, o->flags);
        for (size_t k = 0; k < s->ncells; k++)
            if (o->values[k]) {
                put(&t, "  at ");
                put_xyz(&t, s, k);
                put(&t, " %d\n", o->values[k]);
            }
    }
    static const char *const kinds[] = { "line", "arrow", "path", "callout" };
    for (size_t i = 0; i < s->nnotes; i++) {
        const Note *n = &s->notes[i];
        put(&t, "note %s flags %u look %u points", kinds[n->kind], n->flags, n->look);
        for (size_t k = 0; k < n->npoints; k++) put(&t, " %d,%d,%d", n->points[k].x, n->points[k].y, n->points[k].z);
        if (n->text) {
            put(&t, " text ");
            put_quoted(&t, n->text);
        }
        put(&t, "\n");
    }
    return t.len;
}
