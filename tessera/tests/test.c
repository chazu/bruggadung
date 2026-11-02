/* Tessera's tests: building scenes, the text form, frames and diffs, and
 * decoding anything without harm. */
#include "tessera.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures, checks;
static const char *current;

#define CHECK(cond) do { \
    checks++; \
    if (!(cond)) { fprintf(stderr, "  %s:%d: [%s] CHECK failed: %s\n", __FILE__, __LINE__, current, #cond); failures++; } \
} while (0)

#define CHECK_STR(actual, expected) do { \
    const char *a_ = (actual), *e_ = (expected); \
    checks++; \
    if (!a_ || strcmp(a_, e_)) { \
        fprintf(stderr, "  %s:%d: [%s] expected:\n%s\n  got:\n%s\n", __FILE__, __LINE__, current, e_, a_ ? a_ : "(null)"); \
        failures++; \
    } \
} while (0)

/* The scene as text, malloc'd. */
static char *text(const tess_scene *s)
{
    size_t n = tess_scene_text(s, NULL, 0);
    char *b = malloc(n + 1);
    tess_scene_text(s, b, n + 1);
    return b;
}

static int same(const tess_scene *a, const tess_scene *b)
{
    char *x = text(a), *y = text(b);
    int r = !strcmp(x, y);
    if (!r) fprintf(stderr, "  differ:\n%s  --\n%s", x, y);
    free(x);
    free(y);
    return r;
}

static const tess_meta KNOW = { TESS_KNOWLEDGE, 1, 1000, 0xab, 4 };
static const tess_extent ROOM = { 3, 2, 4, 3, 0, 1, 0 };

/* A room as a character knows it: a floor, a wall, the character and a
 * pump, a cup in the character's hand, an overlay, notes. */
static tess_scene *room(void)
{
    tess_scene *s = tess_scene_new(KNOW, ROOM);
    uint16_t floor = tess_look(s, "floor"), wall = tess_look(s, "wall.stone");
    for (int32_t y = 2; y < 5; y++)
        for (int32_t x = 3; x < 7; x++) {
            tess_cell *c = tess_cell_at(s, x, y, 0);
            c->terrain = x == 6 ? wall : floor;
            c->seen = 1000;
            c->light = 200;
            c->flags = TESS_CELL_IN_SIGHT;
        }
    tess_cell_at(s, 4, 3, 0)->fluid = 500;
    tess_mark me = { 4, 0, 1000, 3, 3, 0, tess_look(s, "#Agent"), 0, TESS_MARK_ACTOR | TESS_MARK_IN_SIGHT, "R4" };
    tess_mark pump = { 7, 0, 900, 5, 2, 0, tess_look(s, "#Pump"), 0, TESS_MARK_IN_SIGHT, NULL };
    tess_mark cup = { 9, 4, 1000, 3, 3, 0, tess_look(s, "#Part"), 0, 0, "a \"cup\"" };
    tess_mark_put(s, &cup);
    tess_mark_put(s, &me);
    tess_mark_put(s, &pump);
    int32_t *heat = tess_overlay_put(s, "heat", 270, 320, TESS_DEVELOPER);
    heat[tess_cell_index(s, 5, 2, 0)] = 305;
    tess_point path[] = { { 3, 3, 0 }, { 4, 3, 0 }, { 5, 2, 0 } };
    tess_note_add(s, TESS_PATH, 0, 0, path, 3, "to the pump");
    tess_note_add(s, TESS_CALLOUT, TESS_DEVELOPER, 0, path + 2, 1, "worn 30");
    return s;
}

static void test_building(void)
{
    current = "building";
    tess_extent bad[] = { { 0, 0, 0, 1, 0, 0, 0 }, { 0, 0, 1, 1, 1, 0, 0 }, { 0, 0, 1, 1, 0, 1, 2 },
                          { 0, 0, 100000, 100000, 0, 0, 0 }, { INT32_MAX, 0, 2, 1, 0, 0, 0 } };
    for (size_t i = 0; i < sizeof bad / sizeof *bad; i++) CHECK(tess_scene_new(KNOW, bad[i]) == NULL);
    tess_meta odd = KNOW;
    odd.view = (tess_view) 7;
    CHECK(tess_scene_new(odd, ROOM) == NULL);

    tess_scene *s = tess_scene_new(KNOW, ROOM);
    CHECK(tess_cell_count(s) == 24);
    CHECK(tess_cell_at(s, 2, 2, 0) == NULL && tess_cell_at(s, 7, 2, 0) == NULL && tess_cell_at(s, 3, 2, 2) == NULL);
    CHECK(tess_cell_get(s, 3, 2, 0)->seen == -1 && tess_cell_get(s, 3, 2, 0)->terrain == 0);
    CHECK(tess_cell_index(s, 4, 2, 1) == 13);
    /* appearance keys: made once, in order; none for nothing */
    CHECK(tess_look(s, "floor") == 1 && tess_look(s, "wall") == 2 && tess_look(s, "floor") == 1);
    CHECK(tess_look(s, "") == 0 && tess_look(s, NULL) == 0 && tess_look_find(s, "door") == 0);
    CHECK(!strcmp(tess_look_name(s, 2), "wall") && tess_look_name(s, 3) == NULL && tess_look_name(s, 0) == NULL);
    /* marks: by id; put again, replaced; no id, or its own holder, refused */
    tess_mark a = { 5, 0, 0, 3, 2, 0, 1, 0, 0, "five" }, b = { 2, 5, 0, 3, 2, 0, 1, 0, 0, NULL };
    CHECK(tess_mark_put(s, &a) && tess_mark_put(s, &b));
    CHECK(tess_mark_at(s, 0)->id == 2 && tess_mark_at(s, 1)->id == 5);
    a.x = 4;
    a.label = "moved";
    CHECK(tess_mark_put(s, &a) && tess_mark_count(s) == 2 && tess_mark_find(s, 5)->x == 4);
    CHECK(!strcmp(tess_mark_find(s, 5)->label, "moved"));
    tess_mark zero = { 0 }, own = { 3, 3, 0, 0, 0, 0, 0, 0, 0, NULL };
    CHECK(!tess_mark_put(s, &zero) && !tess_mark_put(s, &own));
    CHECK(tess_mark_remove(s, 2) && !tess_mark_remove(s, 2) && tess_mark_count(s) == 1);
    /* overlays: one per name */
    int32_t *v = tess_overlay_put(s, "heat", 0, 10, 0);
    CHECK(v && tess_overlay_put(s, "heat", 0, 20, TESS_DEVELOPER) == v && tess_overlay_count(s) == 1);
    CHECK(tess_overlay_at(s, 0).hi == 20 && tess_overlay_at(s, 0).flags == TESS_DEVELOPER);
    CHECK(tess_overlay_put(s, "", 0, 1, 0) == NULL);
    /* notes: points needed, a callout has one */
    tess_point p[] = { { 1, 1, 0 }, { 2, 2, 0 } };
    CHECK(tess_note_add(s, TESS_ARROW, 0, 0, p, 2, NULL));
    CHECK(!tess_note_add(s, TESS_CALLOUT, 0, 0, p, 2, "x") && !tess_note_add(s, TESS_LINE, 0, 0, p, 0, NULL));
    CHECK(!tess_note_add(s, (tess_note_kind) 9, 0, 0, p, 1, NULL));
    /* focus moves within the levels */
    CHECK(tess_scene_set_focus(s, 1) && !tess_scene_set_focus(s, 2) && tess_scene_extent(s).focus == 1);
    /* a copy is the same, and apart */
    tess_scene *c = tess_scene_copy(s);
    CHECK(same(s, c));
    tess_cell_at(c, 3, 2, 0)->terrain = 1;
    CHECK(tess_cell_get(s, 3, 2, 0)->terrain == 0);
    tess_scene_free(c);
    tess_scene_free(s);
}

static void test_text(void)
{
    current = "text";
    tess_scene *s = tess_scene_new(KNOW, (tess_extent) { 0, 0, 2, 1, 0, 0, 0 });
    tess_cell_at(s, 1, 0, 0)->terrain = tess_look(s, "floor");
    tess_cell_at(s, 1, 0, 0)->seen = 500;
    tess_mark m = { 4, 0, 500, 1, 0, 0, tess_look(s, "#Agent"), 0, TESS_MARK_ACTOR, "R\"4\"" };
    tess_mark_put(s, &m);
    tess_overlay_put(s, "age", 0, 60, 0)[1] = 30;
    tess_point p = { 1, 0, 0 };
    tess_note_add(s, TESS_CALLOUT, TESS_DEVELOPER, 0, &p, 1, "hi\n");
    char *t = text(s);
    CHECK_STR(t, "tessera knowledge seq 1 time 1000 content 00000000000000ab viewer 4\n"
                 "extent 0 0 2 1 levels 0 0 focus 0\n"
                 "look 1 \"floor\"\n"
                 "look 2 \"#Agent\"\n"
                 "cell 1 0 0 terrain 1 seen 500 light 0 fluid 0 flags 0\n"
                 "mark 4 at 1 0 0 look 2 stack 0 flags 1 seen 500 holder 0 label \"R\\\"4\\\"\"\n"
                 "overlay \"age\" lo 0 hi 60 flags 0\n"
                 "  at 1 0 0 30\n"
                 "note callout flags 1 look 0 points 1,0,0 text \"hi\\n\"\n");
    /* snprintf's contract: truncated, terminated, the length needed */
    char small[16];
    CHECK(tess_scene_text(s, small, sizeof small) == strlen(t) && strlen(small) == 15);
    free(t);
    tess_scene_free(s);
}

static tess_scene *roundtrip(const tess_scene *s, size_t *len)
{
    tess_bytes b;
    char err[128];
    if (!tess_encode_frame(s, &b)) return NULL;
    if (len) *len = b.len;
    tess_scene *r = tess_decode(b.data, b.len, NULL, err, sizeof err);
    if (!r) fprintf(stderr, "  decode: %s\n", err);
    tess_bytes_free(&b);
    return r;
}

static void test_frames(void)
{
    current = "frames";
    tess_scene *s = room();
    size_t len;
    tess_scene *r = roundtrip(s, &len);
    CHECK(r && same(s, r));
    tess_scene_free(r);
    tess_scene_free(s);
    /* a large blank map is small: runs of equal cells */
    tess_meta truth = { TESS_TRUTH, 1, 0, 0, 0 };
    s = tess_scene_new(truth, (tess_extent) { -100, -100, 512, 512, -2, 2, 0 });
    r = roundtrip(s, &len);
    CHECK(r && same(s, r) && len < 64);
    tess_scene_free(r);
    tess_scene_free(s);
}

/* The room a moment later: the character moved, a tile wet, a key added,
 * the pump gone from sight, the overlay changed, a note dropped, the focus
 * a level up. */
static tess_scene *later(const tess_scene *s)
{
    tess_scene *t = tess_scene_copy(s);
    tess_meta m = tess_scene_meta(t);
    m.seq = 2;
    m.time = 2000;
    tess_scene_set_meta(t, m);
    tess_mark me = *tess_mark_find(t, 4);
    me.x = 4;
    me.seen = 2000;
    tess_mark_put(t, &me);
    tess_mark_remove(t, 7);
    tess_mark door = { 12, 0, 2000, 6, 3, 0, tess_look(t, "#Door"), 1, 0, NULL };
    tess_mark_put(t, &door);
    tess_cell_at(t, 5, 4, 0)->fluid = 250;
    tess_cell_at(t, 3, 4, 1)->seen = 2000;
    tess_overlay_put(t, "heat", 270, 320, TESS_DEVELOPER)[0] = 290;
    tess_overlay_put(t, "age", 0, 60, 0);
    tess_strip_developer(t);          /* the callout goes, and the heat with it */
    tess_overlay_put(t, "heat", 270, 320, TESS_DEVELOPER)[1] = 280;
    tess_scene_set_focus(t, 1);
    return t;
}

static void test_diffs(void)
{
    current = "diffs";
    tess_scene *a = room(), *b = later(a);
    tess_bytes d, f;
    int is_frame = -1;
    char err[128];
    CHECK(tess_encode_diff(a, b, &d, &is_frame) && is_frame == 0);
    CHECK(tess_encode_frame(b, &f) && d.len < f.len);
    tess_scene *r = tess_decode(d.data, d.len, a, err, sizeof err);
    CHECK(r && same(r, b));
    tess_scene_free(r);
    /* the base is left as it was */
    tess_scene *a2 = room();
    CHECK(same(a, a2));
    tess_scene_free(a2);
    /* a diff needs its own frame */
    CHECK(tess_decode(d.data, d.len, NULL, err, sizeof err) == NULL && strstr(err, "without the frame"));
    CHECK(tess_decode(d.data, d.len, b, err, sizeof err) == NULL && strstr(err, "follows another frame"));
    tess_bytes_free(&d);
    tess_bytes_free(&f);

    /* nothing changed: a diff of almost nothing */
    CHECK(tess_encode_diff(b, b, &d, &is_frame) && is_frame == 0 && d.len < 40);
    tess_meta m = tess_scene_meta(b);
    m.seq = 3;
    tess_scene_set_meta(b, m);
    tess_bytes_free(&d);

    /* what a diff can't say is a frame: another extent, another view, or
     * appearance keys made in another order */
    tess_scene *other = tess_scene_new(KNOW, (tess_extent) { 0, 0, 4, 3, 0, 1, 0 });
    CHECK(tess_encode_diff(a, other, &d, &is_frame) && is_frame == 1);
    r = tess_decode(d.data, d.len, a, err, sizeof err);
    CHECK(r && same(r, other));
    tess_scene_free(r);
    tess_bytes_free(&d);
    tess_scene_free(other);
    other = tess_scene_new((tess_meta) { TESS_TRUTH, 2, 0, 0, 0 }, ROOM);
    CHECK(tess_encode_diff(a, other, &d, &is_frame) && is_frame == 1);
    tess_bytes_free(&d);
    tess_scene_free(other);
    other = tess_scene_new(KNOW, ROOM);
    tess_look(other, "wall.stone");
    tess_look(other, "floor");
    CHECK(tess_encode_diff(a, other, &d, &is_frame) && is_frame == 1);
    tess_bytes_free(&d);
    tess_scene_free(other);
    CHECK(tess_encode_diff(NULL, a, &d, &is_frame) && is_frame == 1);
    tess_bytes_free(&d);

    /* a stream: each diff applied to the last scene decoded */
    tess_scene *shown = roundtrip(a, NULL), *now = tess_scene_copy(a);
    for (int step = 0; step < 20; step++) {
        tess_scene *next = tess_scene_copy(now);
        tess_meta mm = tess_scene_meta(next);
        mm.seq++;
        mm.time += 1000;
        tess_scene_set_meta(next, mm);
        tess_mark me = *tess_mark_find(next, 4);
        me.x = 3 + step % 4;
        tess_mark_put(next, &me);
        tess_cell_at(next, 3 + step % 4, 4, step % 2)->seen = mm.time;
        if (step == 10) tess_look(next, "#Lamp");
        tess_encode_diff(now, next, &d, NULL);
        tess_scene *got = tess_decode(d.data, d.len, shown, err, sizeof err);
        tess_bytes_free(&d);
        CHECK(got != NULL);
        if (!got) { tess_scene_free(next); break; }
        tess_scene_free(shown);
        shown = got;
        tess_scene_free(now);
        now = next;
    }
    CHECK(same(shown, now));
    tess_scene_free(shown);
    tess_scene_free(now);
    tess_scene_free(a);
    tess_scene_free(b);
}

static void test_developer(void)
{
    current = "developer";
    tess_scene *s = room();
    CHECK(tess_strip_developer(s) == 2);
    CHECK(tess_overlay_count(s) == 0 && tess_note_count(s) == 1 && !strcmp(tess_note_at(s, 0).text, "to the pump"));
    CHECK(tess_strip_developer(s) == 0);
    tess_scene_free(s);
}

/* No input harms the decoder: every truncation fails cleanly, and every
 * byte changed either fails or gives a scene. */
static void test_malformed(void)
{
    current = "malformed";
    tess_scene *a = room(), *b = later(a);
    tess_bytes f, d;
    char err[128];
    tess_encode_frame(a, &f);
    tess_encode_diff(a, b, &d, NULL);
    int clean = 1;
    for (int which = 0; which < 2; which++) {
        tess_bytes *x = which ? &d : &f;
        for (size_t n = 0; n < x->len; n++) {
            tess_scene *r = tess_decode(x->data, n, a, err, sizeof err);
            if (r) { clean = 0; tess_scene_free(r); }
        }
        uint8_t *copy = malloc(x->len);
        for (size_t i = 0; i < x->len; i++)
            for (int bit = 0; bit < 8; bit++) {
                memcpy(copy, x->data, x->len);
                copy[i] ^= (uint8_t) (1u << bit);
                tess_scene_free(tess_decode(copy, x->len, a, err, sizeof err));
            }
        free(copy);
    }
    CHECK(clean);
    uint8_t junk[] = "TESS\x01\x01\x00\x01";
    CHECK(tess_decode(junk, sizeof junk - 1, NULL, err, sizeof err) == NULL && strstr(err, "truncated"));
    uint8_t version[] = "TESS\x09\x01";
    CHECK(tess_decode(version, sizeof version - 1, NULL, err, sizeof err) == NULL && strstr(err, "version"));
    CHECK(tess_decode((const uint8_t *) "nope", 4, NULL, err, sizeof err) == NULL);
    /* a count that claims more than the data holds is refused, not allocated */
    uint8_t huge[64];
    size_t n = 0;
    memcpy(huge, "TESS\x01\x01\x00\x01\x00", 9);
    n = 9;
    memset(huge + n, 0, 8);                   /* content */
    n += 8;
    huge[n++] = 0;                            /* viewer */
    uint8_t ext[] = { 0, 0, 2, 1, 0, 0, 0 };  /* 2 x 1, one level */
    memcpy(huge + n, ext, sizeof ext);
    n += sizeof ext;
    uint8_t lots[] = { 0xff, 0xff, 0xff, 0xff, 0x0f };   /* looks: 4 billion */
    memcpy(huge + n, lots, sizeof lots);
    n += sizeof lots;
    CHECK(tess_decode(huge, n, NULL, err, sizeof err) == NULL && strstr(err, "count larger"));
    tess_bytes_free(&f);
    tess_bytes_free(&d);
    tess_scene_free(a);
    tess_scene_free(b);
}

int main(void)
{
    test_building();
    test_text();
    test_frames();
    test_diffs();
    test_developer();
    test_malformed();
    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
