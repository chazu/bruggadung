/*
 * BGTerrain (TERRAIN.md): a kind per cell. The source is a drawing (an
 * authored map, as dense as it is drawn) or a plain fill; a chunk is stored,
 * in a small open-addressed table, only once a cell in it changes, and a
 * world with nothing changed reads straight from the source.
 */
#import "BGTerrain.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BG_MAX_TERRAIN_CELLS   (16 * 1024 * 1024)    /* a drawing, at most */

typedef struct
{
   int32_t         cx;
   int32_t         cy;
   int32_t         z;
   BGTerrainKind   *cells;            /* NULL: an empty slot */
} BGChunk;

/* A chunk's room labels, kept once a room or open ground in it is found:
 * per cell 0 (not known), BG_OPEN, or a room's number. */
typedef struct
{
   int32_t         cx;
   int32_t         cy;
   int32_t         z;
   uint32_t        *cells;            /* NULL: an empty slot */
} BGLabels;

#define BG_OPEN       0xFFFFFFFFu     /* open ground: in no room */
#define BG_VISITING   0xFFFFFFFEu     /* being flooded */

typedef struct
{
   uint32_t        size;              /* cells; 0: a free slot */
   int32_t         x;                 /* its first cell */
   int32_t         y;
   int32_t         z;
   uint32_t        ndoors;            /* the doorways at its side, by y then x */
   int32_t         (*doors)[ 3];
} BGRoom;

typedef struct
{
   int32_t         x;
   int32_t         y;
   uint32_t        was;               /* its label before */
} BGFloodCell;

struct BGTerrain
{
   BGTerrainInfo   *kinds;            /* kinds[ 0] is none */
   NSUInteger      nkinds;
   char            *map;
   int32_t         wide;
   int32_t         high;
   int32_t         levels;
   BGTerrainKind   fill;
   BGTerrainKind   *drawn;            /* wide * high * levels, or NULL: the fill everywhere */
   BGChunk         *chunks;
   NSUInteger      nchunks;
   NSUInteger      cap;               /* a power of two, or 0 */
   BGLabels        *labels;
   NSUInteger      nlabels;
   NSUInteger      labelcap;          /* a power of two, or 0 */
   BGRoom          *rooms;            /* room n is rooms[ n - 1] */
   uint32_t        nrooms;
   uint32_t        roomcap;
   uint32_t        *free;             /* room numbers to use again */
   uint32_t        nfree;
   uint64_t        dropped;
   BGFloodCell     *flood;            /* BG_ROOM_MAX + 1 cells */
};


static void   rooms_changed( BGTerrain *t, int32_t x, int32_t y, int32_t z, BOOL wasRoomy);


static char   *dup_string( const char *s)
{
   size_t   n;
   char     *d;

   n = strlen( s) + 1;
   d = malloc( n);
   memcpy( d, s, n);
   return( d);
}


/* A text field of a content node, malloc'd, or NULL. */
static char   *text_of( TriContent *tri, const TriNode *node, const char *path)
{
   const TriNode   *v;
   size_t          n;
   char            *s;

   v = node ? tri_at( tri, node, path) : NULL;
   if( ! v || (n = tri_text( tri, v, NULL, 0)) == (size_t) -1)
      return( NULL);
   s = malloc( n + 1);
   tri_text( tri, v, s, n + 1);
   return( s);
}


static BOOL   is_true( TriContent *tri, const TriNode *node, const char *path)
{
   const TriNode   *v;

   v = node ? tri_at( tri, node, path) : NULL;
   return( v && tri_node_type( v) == tri_type_named( tri, "true"));
}


/* The kinds content declares, in the `terrain` family's order. */
static BOOL   load_kinds( BGTerrain *t, TriContent *tri, char *error, size_t errlen)
{
   TriIndex        *family;
   const TriNode   *kind;
   const char      *tag;
   size_t          i;
   size_t          n;
   char            *look;
   int64_t         lo;
   int64_t         hi;

   family = tri_family_index( tri, "terrain");
   n      = family ? tri_index_count( family) : 0;
   if( ! n || n >= BG_MAX_TERRAIN)
   {
      snprintf( error, errlen, n ? "too many terrain kinds" : "content has no terrain kinds (the terrain family)");
      return( NO);
   }
   t->kinds  = calloc( n + 1, sizeof( BGTerrainInfo));
   t->nkinds = n;
   for( i = 0; i < n; i++)
   {
      tag  = tri_index_tag( family, i);
      kind = tri_spec( tri, tag);           /* its defaults applied: floored unless said */
      if( ! kind)
         kind = tri_pattern( tri, tag);
      look = text_of( tri, kind, "look");
      t->kinds[ i + 1].name    = dup_string( tag);
      t->kinds[ i + 1].look    = look ? look : dup_string( tag);
      t->kinds[ i + 1].solid   = is_true( tri, kind, "solid");
      t->kinds[ i + 1].opaque  = is_true( tri, kind, "opaque");
      t->kinds[ i + 1].floored = is_true( tri, kind, "floored");
      t->kinds[ i + 1].divides = is_true( tri, kind, "divides");
      if( kind && tri_node_interval( tri_at( tri, kind, "draught"), &lo, &hi) && lo == hi && lo >= 0)
         t->kinds[ i + 1].draught = lo;
   }
   return( YES);
}


BGTerrainKind   BGTerrainKindNamed( const BGTerrain *t, const char *name)
{
   NSUInteger   i;

   for( i = 1; name && i <= t->nkinds; i++)
      if( ! strcmp( t->kinds[ i].name, name))
         return( (BGTerrainKind) i);
   return( 0);
}


static BGTerrain   *terrain_new( TriContent *tri, char *error, size_t errlen)
{
   BGTerrain   *t;

   t = calloc( 1, sizeof( BGTerrain));
   if( ! load_kinds( t, tri, error, errlen))
   {
      BGTerrainFree( t);
      return( NULL);
   }
   return( t);
}


BGTerrain   *BGTerrainNew( TriContent *tri, int32_t wide, int32_t high, int32_t levels, const char *fill,
                           char *error, size_t errlen)
{
   BGTerrain   *t;

   if( wide <= 0 || high <= 0 || levels <= 0)
   {
      snprintf( error, errlen, "an empty extent");
      return( NULL);
   }
   if( ! (t = terrain_new( tri, error, errlen)))
      return( NULL);
   t->wide   = wide;
   t->high   = high;
   t->levels = levels;
   t->fill   = fill ? BGTerrainKindNamed( t, fill) : BGTerrainKindNamed( t, "open_floor");
   if( ! t->fill && ! fill)
      t->fill = 1;
   if( ! t->fill)
   {
      snprintf( error, errlen, "no terrain kind named %s", fill);
      BGTerrainFree( t);
      return( NULL);
   }
   return( t);
}


/* --- a map ---------------------------------------------------------------------------- */

typedef struct
{
   int32_t      z;
   char         *rows;
} BGDrawnLevel;


BGTerrain   *BGTerrainFromMap( TriContent *tri, const char *map, char *error, size_t errlen)
{
   const TriNode   *node;
   const TriNode   *list;
   const TriNode   *item;
   BGTerrain       *t;
   BGTerrainKind   legend[ 256];
   BGDrawnLevel    drawn[ 64];
   BGTerrainKind   *cells;
   const char      *s;
   char            *glyph;
   char            *kind;
   char            *fill;
   int64_t         lo;
   int64_t         hi;
   int64_t         ncells;
   int             nlevels;
   int             i;
   int32_t         x;
   int32_t         y;
   int32_t         wide;
   int32_t         high;
   int32_t         levels;
   BOOL            ok;

   node = tri_spec( tri, map);
   if( ! node)
      node = tri_pattern( tri, map);
   if( ! node || ! tri_at( tri, node, "levels"))
   {
      snprintf( error, errlen, "no map named %s", map);
      return( NULL);
   }
   if( ! (t = terrain_new( tri, error, errlen)))
      return( NULL);
   t->map = dup_string( map);
   ok     = YES;

   /* the legend, by byte; and the fill */
   memset( legend, 0, sizeof( legend));
   for( list = tri_at( tri, node, "legend"); ok && list && (item = tri_at( tri, list, "first")); list = tri_at( tri, list, "rest"))
   {
      glyph = text_of( tri, item, "glyph");
      kind  = text_of( tri, item, "terrain");
      if( ! glyph || strlen( glyph) != 1)
      {
         snprintf( error, errlen, "%s: a legend's glyph is one character: \"%s\"", map, glyph ? glyph : "");
         ok = NO;
      }
      else if( ! (legend[ (unsigned char) glyph[ 0]] = BGTerrainKindNamed( t, kind)))
      {
         snprintf( error, errlen, "%s: no terrain kind named %s, for '%s'", map, kind ? kind : "", glyph);
         ok = NO;
      }
      free( glyph);
      free( kind);
   }
   fill = text_of( tri, node, "fill");
   if( ok && ! (t->fill = BGTerrainKindNamed( t, fill ? fill : "open_floor")))
   {
      snprintf( error, errlen, "%s: no terrain kind named %s, for its fill", map, fill ? fill : "open_floor");
      ok = NO;
   }
   free( fill);
   if( ! legend[ (unsigned char) ' '])
      legend[ (unsigned char) ' '] = t->fill;

   /* the levels drawn, and the extent they make */
   nlevels = 0;
   wide    = 0;
   high    = 0;
   levels  = 0;
   for( list = tri_at( tri, node, "levels"); ok && list && (item = tri_at( tri, list, "first")); list = tri_at( tri, list, "rest"))
   {
      if( nlevels == 64 || ! tri_node_interval( tri_at( tri, item, "z"), &lo, &hi) || lo != hi || lo < 0 || lo > 63)
      {
         snprintf( error, errlen, "%s: a level's z is 0 to 63, one per level", map);
         ok = NO;
         break;
      }
      for( i = 0; i < nlevels; i++)
         if( drawn[ i].z == (int32_t) lo)
         {
            snprintf( error, errlen, "%s: level %lld is drawn twice", map, (long long) lo);
            ok = NO;
         }
      drawn[ nlevels].z    = (int32_t) lo;
      drawn[ nlevels].rows = text_of( tri, item, "rows");
      if( ! drawn[ nlevels].rows)
         drawn[ nlevels].rows = dup_string( "");
      nlevels++;
      if( levels < (int32_t) lo + 1)
         levels = (int32_t) lo + 1;
      x = 0;
      y = 0;
      for( s = drawn[ nlevels - 1].rows; *s; s++)
      {
         if( *s == '\n')
         {
            y++;
            x = 0;
            continue;
         }
         if( *s != '\r' && ++x > wide)
            wide = x;
      }
      if( x)
         y++;          /* a last row without its newline */
      if( y > high)
         high = y;
   }
   if( tri_node_interval( tri_at( tri, node, "width"), &lo, &hi) && lo == hi && lo > wide && lo <= 4096)
      wide = (int32_t) lo;
   if( tri_node_interval( tri_at( tri, node, "height"), &lo, &hi) && lo == hi && lo > high && lo <= 4096)
      high = (int32_t) lo;
   ncells = (int64_t) wide * high * levels;
   if( ok && (! nlevels || ! wide || ! high))
   {
      snprintf( error, errlen, "%s: nothing is drawn", map);
      ok = NO;
   }
   if( ok && ncells > BG_MAX_TERRAIN_CELLS)
   {
      snprintf( error, errlen, "%s: too large to draw (%lld cells; %d at most)", map, (long long) ncells,
                BG_MAX_TERRAIN_CELLS);
      ok = NO;
   }

   /* the cells */
   cells = NULL;
   if( ok)
   {
      cells = malloc( (size_t) ncells * sizeof( BGTerrainKind));
      for( i = 0; i < ncells; i++)
         cells[ i] = t->fill;
      for( i = 0; ok && i < nlevels; i++)
      {
         x = 0;
         y = 0;
         for( s = drawn[ i].rows; ok && *s; s++)
         {
            if( *s == '\n')
            {
               y++;
               x = 0;
               continue;
            }
            if( *s == '\r')
               continue;
            if( ! legend[ (unsigned char) *s])
            {
               snprintf( error, errlen, "%s: level %d, row %d, column %d: '%c' is in no legend", map, drawn[ i].z,
                         y + 1, x + 1, *s);
               ok = NO;
               break;
            }
            cells[ ((size_t) drawn[ i].z * (size_t) high + (size_t) y) * (size_t) wide + (size_t) x] = legend[ (unsigned char) *s];
            x++;
         }
      }
   }
   for( i = 0; i < nlevels; i++)
      free( drawn[ i].rows);
   if( ! ok)
   {
      free( cells);
      BGTerrainFree( t);
      return( NULL);
   }
   t->wide   = wide;
   t->high   = high;
   t->levels = levels;
   t->drawn  = cells;
   return( t);
}


void   BGTerrainFree( BGTerrain *t)
{
   NSUInteger   i;

   if( ! t)
      return;
   for( i = 1; t->kinds && i <= t->nkinds; i++)
   {
      free( (char *) t->kinds[ i].name);
      free( (char *) t->kinds[ i].look);
   }
   free( t->kinds);
   for( i = 0; i < t->cap; i++)
      free( t->chunks[ i].cells);
   free( t->chunks);
   free( t->drawn);
   for( i = 0; i < t->labelcap; i++)
      free( t->labels[ i].cells);
   free( t->labels);
   for( i = 0; i < t->nrooms; i++)
      free( t->rooms[ i].doors);
   free( t->rooms);
   free( t->free);
   free( t->flood);
   free( t->map);
   free( t);
}


const char   *BGTerrainMap( const BGTerrain *t)      { return( t->map); }
int32_t       BGTerrainWide( const BGTerrain *t)     { return( t->wide); }
int32_t       BGTerrainHigh( const BGTerrain *t)     { return( t->high); }
int32_t       BGTerrainLevels( const BGTerrain *t)   { return( t->levels); }
NSUInteger    BGTerrainKindCount( const BGTerrain *t) { return( t->nkinds); }


const BGTerrainInfo   *BGTerrainKindInfo( const BGTerrain *t, BGTerrainKind k)
{
   return( k && k <= t->nkinds ? &t->kinds[ k] : NULL);
}


/* --- cells ------------------------------------------------------------------------------ */

static inline BOOL   inside( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   return( x >= 0 && y >= 0 && z >= 0 && x < t->wide && y < t->high && z < t->levels);
}


BGTerrainKind   BGTerrainSource( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   if( ! inside( t, x, y, z))
      return( 0);
   if( ! t->drawn)
      return( t->fill);
   return( t->drawn[ ((size_t) z * (size_t) t->high + (size_t) y) * (size_t) t->wide + (size_t) x]);
}


static NSUInteger   slot_of( int32_t cx, int32_t cy, int32_t z, NSUInteger cap)
{
   return( (NSUInteger) BGMix( ((uint64_t) (uint32_t) cx << 32) ^ ((uint64_t) (uint32_t) cy << 8) ^ (uint64_t) z) &
           (cap - 1));
}


static BGChunk   *chunk_find( const BGTerrain *t, int32_t cx, int32_t cy, int32_t z)
{
   NSUInteger   i;
   BGChunk      *c;

   if( ! t->nchunks)
      return( NULL);
   for( i = slot_of( cx, cy, z, t->cap);; i = (i + 1) & (t->cap - 1))
   {
      c = &t->chunks[ i];
      if( ! c->cells)
         return( NULL);
      if( c->cx == cx && c->cy == cy && c->z == z)
         return( c);
   }
}


BGTerrainKind   BGTerrainAt( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   BGChunk   *c;

   if( ! inside( t, x, y, z))
      return( 0);
   if( t->nchunks && (c = chunk_find( t, x / BG_CHUNK, y / BG_CHUNK, z)))
      return( c->cells[ (y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK]);
   return( BGTerrainSource( t, x, y, z));
}


BOOL   BGTerrainSolid( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   BGTerrainKind   k;

   k = BGTerrainAt( t, x, y, z);
   return( ! k || t->kinds[ k].solid);
}


BOOL   BGTerrainOpaque( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   BGTerrainKind   k;

   k = BGTerrainAt( t, x, y, z);
   return( ! k || t->kinds[ k].opaque);
}


BOOL   BGTerrainFloored( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   BGTerrainKind   k;

   k = BGTerrainAt( t, x, y, z);
   return( k && t->kinds[ k].floored);
}


void   BGTerrainChunkCells( const BGTerrain *t, int32_t x0, int32_t y0, int32_t z, BGTerrainKind *cells)
{
   int32_t   x;
   int32_t   y;

   for( y = 0; y < BG_CHUNK; y++)
      for( x = 0; x < BG_CHUNK; x++)
         cells[ y * BG_CHUNK + x] = BGTerrainAt( t, x0 + x, y0 + y, z);
}


static void   grow( BGTerrain *t)
{
   BGChunk      *old;
   NSUInteger   oldcap;
   NSUInteger   i;
   NSUInteger   j;

   old    = t->chunks;
   oldcap = t->cap;
   t->cap = oldcap ? oldcap * 2 : 16;
   t->chunks = calloc( t->cap, sizeof( BGChunk));
   for( i = 0; i < oldcap; i++)
      if( old[ i].cells)
      {
         for( j = slot_of( old[ i].cx, old[ i].cy, old[ i].z, t->cap); t->chunks[ j].cells; j = (j + 1) & (t->cap - 1))
            ;
         t->chunks[ j] = old[ i];
      }
   free( old);
}


BGTerrainKind   BGTerrainSet( BGTerrain *t, int32_t x, int32_t y, int32_t z, BGTerrainKind k)
{
   BGChunk         *c;
   BGTerrainKind   was;
   NSUInteger      i;
   int32_t         cx;
   int32_t         cy;

   if( ! inside( t, x, y, z) || ! k || k > t->nkinds)
      return( 0);
   cx = x / BG_CHUNK;
   cy = y / BG_CHUNK;
   if( ! (c = chunk_find( t, cx, cy, z)))
   {
      BGTerrainKind   *cells;
      int32_t         u;
      int32_t         v;

      cells = malloc( BG_CHUNK * BG_CHUNK * sizeof( BGTerrainKind));       /* as the source has it */
      for( v = 0; v < BG_CHUNK; v++)
         for( u = 0; u < BG_CHUNK; u++)
            cells[ v * BG_CHUNK + u] = BGTerrainSource( t, cx * BG_CHUNK + u, cy * BG_CHUNK + v, z);
      if( (t->nchunks + 1) * 2 > t->cap)
         grow( t);
      for( i = slot_of( cx, cy, z, t->cap); t->chunks[ i].cells; i = (i + 1) & (t->cap - 1))
         ;
      c        = &t->chunks[ i];
      c->cx    = cx;
      c->cy    = cy;
      c->z     = z;
      c->cells = cells;
      t->nchunks++;
   }
   was = c->cells[ (y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK];
   c->cells[ (y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] = k;
   if( was && (t->kinds[ was].solid != t->kinds[ k].solid || t->kinds[ was].divides != t->kinds[ k].divides))
      rooms_changed( t, x, y, z, ! t->kinds[ was].solid && ! t->kinds[ was].divides);
   return( was);
}


static int   cmp_corner( const void *a, const void *b)
{
   const int32_t   *p;
   const int32_t   *q;
   int             k;

   p = a;
   q = b;
   for( k = 2; k >= 0; k--)
      if( p[ k] != q[ k])
         return( p[ k] < q[ k] ? -1 : 1);
   return( 0);
}


/* Whether a stored chunk differs from its source. */
static BOOL   differs( const BGTerrain *t, const BGChunk *c)
{
   int32_t   x;
   int32_t   y;

   for( y = 0; y < BG_CHUNK; y++)
      for( x = 0; x < BG_CHUNK; x++)
         if( c->cells[ y * BG_CHUNK + x] != BGTerrainSource( t, c->cx * BG_CHUNK + x, c->cy * BG_CHUNK + y, c->z))
            return( YES);
   return( NO);
}


NSUInteger   BGTerrainChanged( const BGTerrain *t, int32_t (*corners)[ 3], NSUInteger max)
{
   int32_t      (*all)[ 3];
   NSUInteger   n;
   NSUInteger   i;

   all = malloc( (t->nchunks ? t->nchunks : 1) * sizeof( *all));
   n   = 0;
   for( i = 0; i < t->cap; i++)
      if( t->chunks[ i].cells && differs( t, &t->chunks[ i]))
      {
         all[ n][ 0] = t->chunks[ i].cx * BG_CHUNK;
         all[ n][ 1] = t->chunks[ i].cy * BG_CHUNK;
         all[ n][ 2] = t->chunks[ i].z;
         n++;
      }
   qsort( all, n, sizeof( *all), cmp_corner);      /* level, row, column: the same every time */
   if( corners)
      memcpy( corners, all, (n < max ? n : max) * sizeof( *all));
   free( all);
   return( n);
}


uint64_t   BGTerrainHash( const BGTerrain *t)
{
   BGTerrainKind   cells[ BG_CHUNK * BG_CHUNK];
   int32_t         (*corners)[ 3];
   uint64_t        h;
   NSUInteger      n;
   NSUInteger      i;
   NSUInteger      k;

   h = BGMixString( 0x7465727261696eULL, t->map ? t->map : "");
   h = BGMix( h ^ (uint64_t) t->wide ^ ((uint64_t) t->high << 20) ^ ((uint64_t) t->levels << 40) ^ ((uint64_t) t->fill << 50));
   n = BGTerrainChanged( t, NULL, 0);
   if( ! n)
      return( h);
   corners = malloc( n * sizeof( *corners));
   BGTerrainChanged( t, corners, n);
   for( i = 0; i < n; i++)
   {
      BGTerrainChunkCells( t, corners[ i][ 0], corners[ i][ 1], corners[ i][ 2], cells);
      h = BGMix( h ^ (uint64_t) corners[ i][ 0] ^ ((uint64_t) corners[ i][ 1] << 21) ^ ((uint64_t) corners[ i][ 2] << 42));
      for( k = 0; k < BG_CHUNK * BG_CHUNK; k++)
         if( cells[ k] != BGTerrainSource( t, corners[ i][ 0] + (int32_t) (k % BG_CHUNK), corners[ i][ 1] + (int32_t) (k / BG_CHUNK),
                                           corners[ i][ 2]))
            h = BGMix( h ^ k ^ ((uint64_t) cells[ k] << 16));
   }
   free( corners);
   return( h);
}


/* --- rooms (TERRAIN.md step 3) ------------------------------------------------------ */

/* Rooms are found from a cell out, when first asked, and labelled per chunk:
 * nothing is kept for ground no one has asked of, and nothing is ever found
 * over the whole world. A flood stops at the world's edge, or past
 * BG_ROOM_MAX cells, or on meeting ground already known to be open: the
 * cells it reached are open. A change lets go of the rooms beside it, which
 * are found again when next asked; a wall that parts open ground floods each
 * side, as far as BG_ROOM_MAX, for one it has enclosed. */

static const int   dx[ 4] = { 1, -1, 0, 0 };
static const int   dy[ 4] = { 0, 0, 1, -1 };


BOOL   BGTerrainRoomy( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   BGTerrainKind   k;

   k = BGTerrainAt( t, x, y, z);
   return( k && ! t->kinds[ k].solid && ! t->kinds[ k].divides);
}


static BGLabels   *labels_find( const BGTerrain *t, int32_t cx, int32_t cy, int32_t z)
{
   NSUInteger   i;
   BGLabels     *l;

   if( ! t->nlabels)
      return( NULL);
   for( i = slot_of( cx, cy, z, t->labelcap);; i = (i + 1) & (t->labelcap - 1))
   {
      l = &t->labels[ i];
      if( ! l->cells)
         return( NULL);
      if( l->cx == cx && l->cy == cy && l->z == z)
         return( l);
   }
}


static void   labels_grow( BGTerrain *t)
{
   BGLabels     *old;
   NSUInteger   oldcap;
   NSUInteger   i;
   NSUInteger   j;

   old         = t->labels;
   oldcap      = t->labelcap;
   t->labelcap = oldcap ? oldcap * 2 : 16;
   t->labels   = calloc( t->labelcap, sizeof( BGLabels));
   for( i = 0; i < oldcap; i++)
      if( old[ i].cells)
      {
         for( j = slot_of( old[ i].cx, old[ i].cy, old[ i].z, t->labelcap); t->labels[ j].cells;
              j = (j + 1) & (t->labelcap - 1))
            ;
         t->labels[ j] = old[ i];
      }
   free( old);
}


/* A cell's label (inside the extent): 0 if none is kept. */
static uint32_t   label_at( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   BGLabels   *l;

   l = labels_find( t, x / BG_CHUNK, y / BG_CHUNK, z);
   return( l ? l->cells[ (y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] : 0);
}


static void   label_set( BGTerrain *t, int32_t x, int32_t y, int32_t z, uint32_t label)
{
   BGLabels     *l;
   NSUInteger   i;
   int32_t      cx;
   int32_t      cy;

   cx = x / BG_CHUNK;
   cy = y / BG_CHUNK;
   if( ! (l = labels_find( t, cx, cy, z)))
   {
      if( ! label)
         return;
      if( (t->nlabels + 1) * 2 > t->labelcap)
         labels_grow( t);
      for( i = slot_of( cx, cy, z, t->labelcap); t->labels[ i].cells; i = (i + 1) & (t->labelcap - 1))
         ;
      l        = &t->labels[ i];
      l->cx    = cx;
      l->cy    = cy;
      l->z     = z;
      l->cells = calloc( BG_CHUNK * BG_CHUNK, sizeof( uint32_t));
      t->nlabels++;
   }
   l->cells[ (y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] = label;
}


static uint32_t   room_new( BGTerrain *t)
{
   uint32_t   n;

   if( t->nfree)
      n = t->free[ --t->nfree];
   else
   {
      if( t->nrooms == t->roomcap)
      {
         t->roomcap = t->roomcap ? t->roomcap * 2 : 16;
         t->rooms   = realloc( t->rooms, t->roomcap * sizeof( BGRoom));
         t->free    = realloc( t->free, t->roomcap * sizeof( uint32_t));
      }
      n = ++t->nrooms;
   }
   memset( &t->rooms[ n - 1], 0, sizeof( BGRoom));
   return( n);
}


static const BGRoom   *room_of( const BGTerrain *t, uint32_t n)
{
   return( n && n <= t->nrooms && t->rooms[ n - 1].size ? &t->rooms[ n - 1] : NULL);
}


static void   add_door( BGRoom *room, int32_t x, int32_t y, int32_t z, uint32_t *cap)
{
   uint32_t   i;

   for( i = 0; i < room->ndoors; i++)
      if( room->doors[ i][ 0] == x && room->doors[ i][ 1] == y)
         return;
   if( room->ndoors == *cap)
   {
      *cap        = *cap ? *cap * 2 : 4;
      room->doors = realloc( room->doors, *cap * sizeof( *room->doors));
   }
   room->doors[ room->ndoors][ 0] = x;
   room->doors[ room->ndoors][ 1] = y;
   room->doors[ room->ndoors][ 2] = z;
   room->ndoors++;
}


static int   cmp_door( const void *a, const void *b)
{
   const int32_t   *p;
   const int32_t   *q;

   p = a;
   q = b;
   if( p[ 1] != q[ 1])
      return( p[ 1] < q[ 1] ? -1 : 1);
   return( p[ 0] < q[ 0] ? -1 : p[ 0] > q[ 0]);
}


/* Floods the roomy cells joined side by side to (x, y, z), marking them
 * visiting, into t->flood with their labels before: returns how many. *open
 * when it met the world's edge, more than BG_ROOM_MAX cells, or, unless
 * `throughOpen`, ground known to be open; it stops there. The doorways at
 * its side go to `room`, if given. */
static uint32_t   flood( BGTerrain *t, int32_t x, int32_t y, int32_t z, BOOL throughOpen, BOOL *open, BGRoom *room)
{
   BGTerrainKind   k;
   uint32_t        n;
   uint32_t        head;
   uint32_t        label;
   uint32_t        cap;
   int32_t         u;
   int32_t         v;
   int             d;

   if( ! t->flood)
      t->flood = malloc( (BG_ROOM_MAX + 1) * sizeof( BGFloodCell));
   *open = NO;
   cap   = 0;
   t->flood[ 0].x   = x;
   t->flood[ 0].y   = y;
   t->flood[ 0].was = label_at( t, x, y, z);
   n = 1;
   label_set( t, x, y, z, BG_VISITING);
   for( head = 0; head < n && ! *open; head++)
      for( d = 0; d < 4; d++)
      {
         u = t->flood[ head].x + dx[ d];
         v = t->flood[ head].y + dy[ d];
         if( ! inside( t, u, v, z))
         {
            *open = YES;
            break;
         }
         k = BGTerrainAt( t, u, v, z);
         if( t->kinds[ k].solid)
            continue;
         if( t->kinds[ k].divides)
         {
            if( room)
               add_door( room, u, v, z, &cap);
            continue;
         }
         label = label_at( t, u, v, z);
         if( label == BG_VISITING)
            continue;
         if( (label == BG_OPEN && ! throughOpen) || n == BG_ROOM_MAX)
         {
            *open = YES;
            break;
         }
         t->flood[ n].x   = u;
         t->flood[ n].y   = v;
         t->flood[ n].was = label;
         n++;
         label_set( t, u, v, z, BG_VISITING);
      }
   return( n);
}


/* The room of a roomy cell not yet labelled, or BG_OPEN: found, and every
 * cell reached labelled so. */
static uint32_t   find_room( BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   BGRoom     room;
   uint32_t   label;
   uint32_t   n;
   uint32_t   i;
   BOOL       open;

   memset( &room, 0, sizeof( room));
   n = flood( t, x, y, z, NO, &open, &room);
   if( open)
   {
      free( room.doors);
      label = BG_OPEN;
   }
   else
   {
      label  = room_new( t);
      room.size = n;
      room.x    = t->flood[ 0].x;
      room.y    = t->flood[ 0].y;
      room.z    = z;
      for( i = 1; i < n; i++)
         if( t->flood[ i].y < room.y || (t->flood[ i].y == room.y && t->flood[ i].x < room.x))
         {
            room.x = t->flood[ i].x;
            room.y = t->flood[ i].y;
         }
      if( room.ndoors > 1)
         qsort( room.doors, room.ndoors, sizeof( *room.doors), cmp_door);
      t->rooms[ label - 1] = room;
   }
   for( i = 0; i < n; i++)
      label_set( t, t->flood[ i].x, t->flood[ i].y, z, label);
   return( label);
}


/* Lets a room go: its cells' labels, from one of them, and its number. */
static void   drop_room( BGTerrain *t, uint32_t n, int32_t x, int32_t y, int32_t z)
{
   uint32_t   top;
   int32_t    u;
   int32_t    v;
   int        d;

   if( ! t->flood)
      t->flood = malloc( (BG_ROOM_MAX + 1) * sizeof( BGFloodCell));
   label_set( t, x, y, z, 0);
   t->flood[ 0].x = x;
   t->flood[ 0].y = y;
   top = 1;
   while( top)
   {
      top--;
      x = t->flood[ top].x;
      y = t->flood[ top].y;
      for( d = 0; d < 4; d++)
      {
         u = x + dx[ d];
         v = y + dy[ d];
         if( inside( t, u, v, z) && label_at( t, u, v, z) == n && top <= BG_ROOM_MAX)
         {
            label_set( t, u, v, z, 0);
            t->flood[ top].x = u;
            t->flood[ top].y = v;
            top++;
         }
      }
   }
   if( room_of( t, n))
   {
      free( t->rooms[ n - 1].doors);
      memset( &t->rooms[ n - 1], 0, sizeof( BGRoom));
      t->free[ t->nfree++] = n;
   }
   t->dropped++;
}


/* A cell's kind changed whether it is solid or divides: the rooms beside it
 * are let go; and where it parted open ground, a side it enclosed is
 * forgotten as open, to be found a room. */
static void   rooms_changed( BGTerrain *t, int32_t x, int32_t y, int32_t z, BOOL wasRoomy)
{
   uint32_t   label;
   uint32_t   n;
   uint32_t   i;
   int32_t    u;
   int32_t    v;
   int        d;
   BOOL       open;

   if( ! t->nlabels)
      return;
   for( d = -1; d < 4; d++)
   {
      u = d < 0 ? x : x + dx[ d];
      v = d < 0 ? y : y + dy[ d];
      if( ! inside( t, u, v, z))
         continue;
      label = label_at( t, u, v, z);
      if( label && label != BG_OPEN && label != BG_VISITING)
         drop_room( t, label, u, v, z);
   }
   label_set( t, x, y, z, 0);
   if( ! wasRoomy || BGTerrainRoomy( t, x, y, z))
      return;
   for( d = 0; d < 4; d++)
   {
      u = x + dx[ d];
      v = y + dy[ d];
      if( ! inside( t, u, v, z) || label_at( t, u, v, z) != BG_OPEN)
         continue;
      n = flood( t, u, v, z, YES, &open, NULL);
      for( i = 0; i < n; i++)
         label_set( t, t->flood[ i].x, t->flood[ i].y, z, open ? t->flood[ i].was : 0);
   }
}


uint32_t   BGTerrainRoomAt( BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   uint32_t   label;

   if( ! inside( t, x, y, z) || ! BGTerrainRoomy( t, x, y, z))
      return( 0);
   if( ! (label = label_at( t, x, y, z)))
      label = find_room( t, x, y, z);
   return( label == BG_OPEN ? 0 : label);
}


uint32_t   BGTerrainRoomSize( const BGTerrain *t, uint32_t room)
{
   const BGRoom   *r;

   r = room_of( t, room);
   return( r ? r->size : 0);
}


BOOL   BGTerrainRoomCorner( const BGTerrain *t, uint32_t room, int32_t *x, int32_t *y, int32_t *z)
{
   const BGRoom   *r;

   if( ! (r = room_of( t, room)))
      return( NO);
   *x = r->x;
   *y = r->y;
   *z = r->z;
   return( YES);
}


NSUInteger   BGTerrainRoomDoorways( const BGTerrain *t, uint32_t room, int32_t (*cells)[ 3], NSUInteger max)
{
   const BGRoom   *r;
   NSUInteger     i;

   if( ! (r = room_of( t, room)))
      return( 0);
   for( i = 0; i < r->ndoors && i < max; i++)
   {
      cells[ i][ 0] = r->doors[ i][ 0];
      cells[ i][ 1] = r->doors[ i][ 1];
      cells[ i][ 2] = r->doors[ i][ 2];
   }
   return( r->ndoors);
}


uint64_t   BGTerrainRoomsDropped( const BGTerrain *t)
{
   return( t->dropped);
}
