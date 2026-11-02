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
   uint32_t        *rooms;            /* each cell's room, or NULL until asked, and after a change */
};


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
   free( t->rooms);
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
   if( was != k && t->rooms)
   {
      free( t->rooms);            /* the rooms are found again when next asked */
      t->rooms = NULL;
   }
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

static BOOL   roomy( const BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   BGTerrainKind   k;

   k = BGTerrainAt( t, x, y, z);
   return( k && ! t->kinds[ k].solid && ! t->kinds[ k].divides);
}


/* Every cell's room, by flood fill over each level, side by side. */
static void   find_rooms( BGTerrain *t)
{
   static const int   dx[ 4] = { 1, -1, 0, 0 };
   static const int   dy[ 4] = { 0, 0, 1, -1 };
   size_t             n;
   size_t             i;
   size_t             j;
   size_t             top;
   size_t             *stack;
   uint32_t           room;
   int32_t            x;
   int32_t            y;
   int32_t            z;
   int32_t            u;
   int32_t            v;
   int                d;

   n        = (size_t) t->wide * (size_t) t->high * (size_t) t->levels;
   t->rooms = calloc( n ? n : 1, sizeof( uint32_t));
   stack    = malloc( (n ? n : 1) * sizeof( size_t));
   room     = 0;
   for( i = 0; i < n; i++)
   {
      if( t->rooms[ i])
         continue;
      x = (int32_t) (i % (size_t) t->wide);
      y = (int32_t) (i / (size_t) t->wide % (size_t) t->high);
      z = (int32_t) (i / ((size_t) t->wide * (size_t) t->high));
      if( ! roomy( t, x, y, z))
         continue;
      t->rooms[ i] = ++room;
      top = 0;
      stack[ top++] = i;
      while( top)
      {
         j = stack[ --top];
         x = (int32_t) (j % (size_t) t->wide);
         y = (int32_t) (j / (size_t) t->wide % (size_t) t->high);
         for( d = 0; d < 4; d++)
         {
            u = x + dx[ d];
            v = y + dy[ d];
            if( ! inside( t, u, v, z) || ! roomy( t, u, v, z))
               continue;
            j = ((size_t) z * (size_t) t->high + (size_t) v) * (size_t) t->wide + (size_t) u;
            if( ! t->rooms[ j])
            {
               t->rooms[ j]  = room;
               stack[ top++] = j;
            }
         }
      }
   }
   free( stack);
}


uint32_t   BGTerrainRoomAt( BGTerrain *t, int32_t x, int32_t y, int32_t z)
{
   if( ! inside( t, x, y, z))
      return( 0);
   if( ! t->rooms)
      find_rooms( t);
   return( t->rooms[ ((size_t) z * (size_t) t->high + (size_t) y) * (size_t) t->wide + (size_t) x]);
}
