/*
 * BGReality: anchor kinds read once from content; anchors and leases in
 * small sorted arrays (there are few anchors; leases last a while).
 */
#import "BGReality.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


#define BG_CHUNK_TILES   32

typedef struct
{
   char      *name;
   BGReach   reach[ 3];         /* abstract, reduced, full */
   int32_t   margin;
} BGAnchorKind;

typedef struct
{
   BGEntityID   entity;
   int          kind;
   int32_t      cx;
   int32_t      cy;
   int32_t      z;
   BOOL         centred;
} BGAnchor;

typedef struct
{
   BGEntityID   entity;
   int64_t      until;
} BGLease;

struct BGReality
{
   BGAnchorKind   *kinds;
   int            nkinds;
   char           **contact;
   int            ncontact;
   int64_t        lease;
   BGAnchor       *anchors;
   NSUInteger     nanchors;
   NSUInteger     anchorcap;
   BGLease        *leases;
   NSUInteger     nleases;
   NSUInteger     leasecap;
   BOOL           reducedOwn;      /* reduced agents sense only what they take part in */
   int64_t        reducedEvery;    /* reduced agents' own wakes, put off to this cadence */
};


static BGDetail   detail_by( const BGReality *r, const BGAnchor *anchors, NSUInteger n, int32_t x, int32_t y, int32_t z);


static int64_t   int_at( TriContent *tri, const TriNode *node, const char *path, int64_t otherwise)
{
   int64_t   lo;
   int64_t   hi;

   if( node && tri_node_interval( tri_at( tri, node, path), &lo, &hi) && lo == hi)
      return( lo);
   return( otherwise);
}


static char   *dup_string( const char *s)
{
   size_t   n;
   char     *d;

   n = strlen( s) + 1;
   d = malloc( n);
   memcpy( d, s, n);
   return( d);
}


static const TriNode   *node_of( TriContent *tri, const char *tag)
{
   const TriNode   *node;

   node = tri_spec( tri, tag);          /* its defaults applied */
   return( node ? node : tri_pattern( tri, tag));
}


BGReality   *BGRealityNew( TriContent *tri)
{
   static const char   *levels[ 3] = { "abstract", "reduced", "full" };
   const TriNode       *node;
   const TriNode       *list;
   TriIndex            *family;
   BGReality           *r;
   size_t              i;
   size_t              n;
   size_t              k;
   char                path[ 32];
   char                text[ 64];

   r      = calloc( 1, sizeof( BGReality));
   family = tri_family_index( tri, "anchors");
   n      = family ? tri_index_count( family) : 0;
   r->kinds = calloc( n + 1, sizeof( BGAnchorKind));
   for( i = 0; i < n; i++)
   {
      node = node_of( tri, tri_index_tag( family, i));
      r->kinds[ i].name   = dup_string( tri_index_tag( family, i));
      r->kinds[ i].margin = (int32_t) int_at( tri, node, "margin", 4);
      for( k = 0; k < 3; k++)
      {
         snprintf( path, sizeof( path), "%s.across", levels[ k]);
         r->kinds[ i].reach[ k].across = (int32_t) int_at( tri, node, path, -1);
         snprintf( path, sizeof( path), "%s.up", levels[ k]);
         r->kinds[ i].reach[ k].up = (int32_t) int_at( tri, node, path, 0);
         snprintf( path, sizeof( path), "%s.down", levels[ k]);
         r->kinds[ i].reach[ k].down = (int32_t) int_at( tri, node, path, 0);
      }
   }
   r->nkinds = (int) n;

   family = tri_family_index( tri, "levels");
   for( i = 0; family && i < tri_index_count( family); i++)
   {
      if( strcmp( tri_index_tag( family, i), "reduced"))
         continue;
      node = node_of( tri, tri_index_tag( family, i));
      r->reducedEvery = int_at( tri, node, "every", 0);
      n = node && tri_at( tri, node, "senses") ? tri_print( tri, tri_at( tri, node, "senses"), text, sizeof( text)) : 0;
      r->reducedOwn = n > 0 && ! strcmp( text, "\"own\"");
   }

   family = tri_family_index( tri, "contact");
   node   = family && tri_index_count( family) ? node_of( tri, tri_index_tag( family, 0)) : NULL;
   r->lease = int_at( tri, node, "lease", 0);
   for( list = node ? tri_at( tri, node, "kinds") : NULL; list && tri_at( tri, list, "first");
        list = tri_at( tri, list, "rest"))
   {
      n = tri_print( tri, tri_at( tri, list, "first"), text, sizeof( text));
      if( n < 2 || n >= sizeof( text) || text[ 0] != '"')
         continue;
      text[ n - 1]  = 0;
      r->contact    = realloc( r->contact, (size_t) (r->ncontact + 1) * sizeof( char *));
      r->contact[ r->ncontact++] = dup_string( text + 1);
   }
   return( r);
}


void   BGRealityFree( BGReality *r)
{
   int   i;

   if( ! r)
      return;
   for( i = 0; i < r->nkinds; i++)
      free( r->kinds[ i].name);
   free( r->kinds);
   for( i = 0; i < r->ncontact; i++)
      free( r->contact[ i]);
   free( r->contact);
   free( r->anchors);
   free( r->leases);
   free( r);
}


const char   *BGDetailName( BGDetail detail)
{
   switch( detail)
   {
   case BGDetailFull     : return( "full");
   case BGDetailReduced  : return( "reduced");
   case BGDetailAbstract : return( "abstract");
   default               : return( "frozen");
   }
}


int   BGRealityKindNamed( const BGReality *r, const char *name)
{
   int   i;

   for( i = 0; name && i < r->nkinds; i++)
      if( ! strcmp( r->kinds[ i].name, name))
         return( i);
   return( -1);
}


const char   *BGRealityKindName( const BGReality *r, int kind)
{
   return( kind >= 0 && kind < r->nkinds ? r->kinds[ kind].name : NULL);
}


BGReach   BGRealityReach( const BGReality *r, int kind, BGDetail level)
{
   BGReach   none;

   memset( &none, 0, sizeof( none));
   none.across = -1;
   if( kind < 0 || kind >= r->nkinds || level < BGDetailAbstract || level > BGDetailFull)
      return( none);
   return( r->kinds[ kind].reach[ level - BGDetailAbstract]);
}


/* --- anchors -------------------------------------------------------------------- */

static NSUInteger   anchor_index( const BGReality *r, BGEntityID entity, BOOL *found)
{
   NSUInteger   lo;
   NSUInteger   hi;
   NSUInteger   mid;

   lo = 0;
   hi = r->nanchors;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      if( r->anchors[ mid].entity < entity)
         lo = mid + 1;
      else
         hi = mid;
   }
   *found = lo < r->nanchors && r->anchors[ lo].entity == entity;
   return( lo);
}


static BGAnchor   *anchor_make( BGReality *r, BGEntityID entity)
{
   NSUInteger   i;
   BOOL         found;

   i = anchor_index( r, entity, &found);
   if( found)
      return( &r->anchors[ i]);
   if( r->nanchors == r->anchorcap)
   {
      r->anchorcap = r->anchorcap ? r->anchorcap * 2 : 8;
      r->anchors   = realloc( r->anchors, r->anchorcap * sizeof( BGAnchor));
   }
   memmove( &r->anchors[ i + 1], &r->anchors[ i], (r->nanchors - i) * sizeof( BGAnchor));
   memset( &r->anchors[ i], 0, sizeof( BGAnchor));
   r->anchors[ i].entity = entity;
   r->nanchors++;
   return( &r->anchors[ i]);
}


BOOL   BGRealitySetAnchor( BGReality *r, BGEntityID entity, int kind)
{
   if( kind < 0 || kind >= r->nkinds || ! entity)
      return( NO);
   anchor_make( r, entity)->kind = kind;
   return( YES);
}


void   BGRealityRestoreAnchor( BGReality *r, BGEntityID entity, int kind, int32_t cx, int32_t cy, int32_t z, BOOL centred)
{
   BGAnchor   *a;

   if( kind < 0 || kind >= r->nkinds)
      return;
   a          = anchor_make( r, entity);
   a->kind    = kind;
   a->cx      = cx;
   a->cy      = cy;
   a->z       = z;
   a->centred = centred;
}


void   BGRealityRemoveAnchor( BGReality *r, BGEntityID entity)
{
   NSUInteger   i;
   BOOL         found;

   i = anchor_index( r, entity, &found);
   if( ! found)
      return;
   memmove( &r->anchors[ i], &r->anchors[ i + 1], (r->nanchors - i - 1) * sizeof( BGAnchor));
   r->nanchors--;
}


NSUInteger   BGRealityAnchorCount( const BGReality *r)
{
   return( r->nanchors);
}


BGEntityID   BGRealityAnchorAt( const BGReality *r, NSUInteger i, int *kind, int32_t *cx, int32_t *cy, int32_t *z,
                                BOOL *centred)
{
   const BGAnchor   *a;

   if( i >= r->nanchors)
      return( BGNoEntity);
   a = &r->anchors[ i];
   if( kind)
      *kind = a->kind;
   if( cx)
      *cx = a->cx;
   if( cy)
      *cy = a->cy;
   if( z)
      *z = a->z;
   if( centred)
      *centred = a->centred;
   return( a->entity);
}


static int32_t   chunk_of( int32_t v)
{
   return( v >= 0 ? v / BG_CHUNK_TILES : -((-v + BG_CHUNK_TILES - 1) / BG_CHUNK_TILES));
}


BOOL   BGRealityCentre( BGReality *r, BGEntityID entity, int32_t x, int32_t y, int32_t z)
{
   BGAnchor   *a;
   NSUInteger i;
   int32_t    out;
   int32_t    dx;
   int32_t    dy;
   BOOL       found;

   i = anchor_index( r, entity, &found);
   if( ! found)
      return( NO);
   a = &r->anchors[ i];
   if( a->centred && a->z == z)
   {
      /* how far past its centre's chunk it stands, in tiles */
      dx  = x < a->cx * BG_CHUNK_TILES ? a->cx * BG_CHUNK_TILES - x
                                       : x - (a->cx * BG_CHUNK_TILES + BG_CHUNK_TILES - 1);
      dy  = y < a->cy * BG_CHUNK_TILES ? a->cy * BG_CHUNK_TILES - y
                                       : y - (a->cy * BG_CHUNK_TILES + BG_CHUNK_TILES - 1);
      out = dx > dy ? dx : dy;
      if( out <= r->kinds[ a->kind].margin)
         return( NO);
   }
   a->cx      = chunk_of( x);
   a->cy      = chunk_of( y);
   a->z       = z;
   a->centred = YES;
   return( YES);
}


BGDetail   BGRealityDetailAt( const BGReality *r, int32_t x, int32_t y, int32_t z)
{
   if( ! r)
      return( BGDetailFull);
   return( detail_by( r, r->anchors, r->nanchors, x, y, z));
}


static BGDetail   detail_by( const BGReality *r, const BGAnchor *anchors, NSUInteger n, int32_t x, int32_t y, int32_t z)
{
   const BGAnchor   *a;
   const BGReach    *reach;
   BGDetail         best;
   NSUInteger       i;
   int32_t          d;
   int32_t          dx;
   int32_t          dy;
   int32_t          dz;
   int              k;

   if( ! n)
      return( BGDetailFull);
   best = BGDetailFrozen;
   for( i = 0; i < n && best < BGDetailFull; i++)
   {
      a = &anchors[ i];
      if( ! a->centred)
         continue;
      dx = chunk_of( x) - a->cx;
      dy = chunk_of( y) - a->cy;
      d  = abs( dx) > abs( dy) ? abs( dx) : abs( dy);
      dz = z - a->z;
      for( k = 2; k >= 0 && (BGDetail) (k + 1) > best; k--)
      {
         reach = &r->kinds[ a->kind].reach[ k];
         if( reach->across >= 0 && d <= reach->across && dz <= reach->up && -dz <= reach->down)
         {
            best = (BGDetail) (k + 1);
            break;
         }
      }
   }
   return( best);
}


/* --- anchors kept ------------------------------------------------------------------- */

struct BGAnchorsKept
{
   NSUInteger   n;
   BGAnchor     anchors[];
};


BGAnchorsKept   *BGRealityKeepAnchors( const BGReality *r)
{
   BGAnchorsKept   *kept;

   kept    = malloc( sizeof( BGAnchorsKept) + (r->nanchors + 1) * sizeof( BGAnchor));
   kept->n = r->nanchors;
   if( r->nanchors)
      memcpy( kept->anchors, r->anchors, r->nanchors * sizeof( BGAnchor));
   return( kept);
}


NSUInteger   BGRealityKeptCount( const BGAnchorsKept *kept)
{
   return( kept ? kept->n : 0);
}


BGDetail   BGRealityDetailKept( const BGReality *r, const BGAnchorsKept *kept, int32_t x, int32_t y, int32_t z)
{
   return( kept ? detail_by( r, kept->anchors, kept->n, x, y, z) : BGDetailFull);
}


/* An anchor's box, the chunks its abstract reach covers: (cx, cy, z) low
 * and high. `same`: the anchor is as it is now, same kind, same centre. */
BOOL   BGRealityKeptBox( const BGReality *r, const BGAnchorsKept *kept, NSUInteger i, BGEntityID *entity,
                         int32_t *lo, int32_t *hi, BOOL *same)
{
   const BGAnchor   *a;
   const BGAnchor   *now;
   const BGReach    *reach;
   NSUInteger       k;
   BOOL             found;

   a = kept ? (i < kept->n ? &kept->anchors[ i] : NULL) : (i < r->nanchors ? &r->anchors[ i] : NULL);
   if( ! a || ! a->centred)
      return( NO);
   reach   = &r->kinds[ a->kind].reach[ 0];        /* abstract reaches furthest */
   lo[ 0]  = a->cx - reach->across;
   lo[ 1]  = a->cy - reach->across;
   lo[ 2]  = a->z - reach->down;
   hi[ 0]  = a->cx + reach->across;
   hi[ 1]  = a->cy + reach->across;
   hi[ 2]  = a->z + reach->up;
   *entity = a->entity;
   if( same && kept)
   {
      /* kept: is it as it is now? */
      k   = anchor_index( r, a->entity, &found);
      now = found ? &r->anchors[ k] : NULL;
      *same = now && now->kind == a->kind && now->centred == a->centred && now->cx == a->cx && now->cy == a->cy &&
              now->z == a->z;
   }
   return( YES);
}


BOOL   BGRealityKeptSame( const BGReality *r, const BGAnchorsKept *kept, NSUInteger i)
{
   const BGAnchor   *now;
   NSUInteger       k;

   if( i >= r->nanchors)
      return( NO);
   now = &r->anchors[ i];
   for( k = 0; kept && k < kept->n; k++)
      if( kept->anchors[ k].entity == now->entity)
         return( kept->anchors[ k].kind == now->kind && kept->anchors[ k].centred == now->centred &&
                 kept->anchors[ k].cx == now->cx && kept->anchors[ k].cy == now->cy && kept->anchors[ k].z == now->z);
   return( NO);
}


/* --- leases ----------------------------------------------------------------------- */

static NSUInteger   lease_index( const BGReality *r, BGEntityID entity, BOOL *found)
{
   NSUInteger   lo;
   NSUInteger   hi;
   NSUInteger   mid;

   lo = 0;
   hi = r->nleases;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      if( r->leases[ mid].entity < entity)
         lo = mid + 1;
      else
         hi = mid;
   }
   *found = lo < r->nleases && r->leases[ lo].entity == entity;
   return( lo);
}


void   BGRealityLease( BGReality *r, BGEntityID entity, int64_t until)
{
   NSUInteger   i;
   BOOL         found;

   if( ! entity)
      return;
   i = lease_index( r, entity, &found);
   if( found)
   {
      if( until > r->leases[ i].until)
         r->leases[ i].until = until;
      return;
   }
   if( r->nleases == r->leasecap)
   {
      r->leasecap = r->leasecap ? r->leasecap * 2 : 16;
      r->leases   = realloc( r->leases, r->leasecap * sizeof( BGLease));
   }
   memmove( &r->leases[ i + 1], &r->leases[ i], (r->nleases - i) * sizeof( BGLease));
   r->leases[ i].entity = entity;
   r->leases[ i].until  = until;
   r->nleases++;
}


int64_t   BGRealityLeaseOf( const BGReality *r, BGEntityID entity)
{
   NSUInteger   i;
   BOOL         found;

   i = lease_index( r, entity, &found);
   return( found ? r->leases[ i].until : 0);
}


void   BGRealityPrune( BGReality *r, int64_t now)
{
   NSUInteger   i;
   NSUInteger   k;

   for( k = 0, i = 0; i < r->nleases; i++)
      if( r->leases[ i].until > now)
         r->leases[ k++] = r->leases[ i];
   r->nleases = k;
}


NSUInteger   BGRealityLeaseCount( const BGReality *r)
{
   return( r->nleases);
}


BGEntityID   BGRealityLeaseAt( const BGReality *r, NSUInteger i, int64_t *until)
{
   if( i >= r->nleases)
      return( BGNoEntity);
   if( until)
      *until = r->leases[ i].until;
   return( r->leases[ i].entity);
}


BOOL   BGRealityOwnSensesAt( const BGReality *r, BGDetail level)
{
   return( level < BGDetailFull && r->reducedOwn);
}


int64_t   BGRealityCadenceAt( const BGReality *r, BGDetail level)
{
   return( level < BGDetailFull ? r->reducedEvery : 0);
}


int64_t   BGRealityBeat( const BGReality *r, BGDetail level, int64_t at)
{
   int64_t   every;

   every = BGRealityCadenceAt( r, level);
   if( every <= 0 || at <= 0 || at == INT64_MAX)
      return( at);
   return( (at + every - 1) / every * every);
}


BOOL   BGRealityIsContact( const BGReality *r, const char *kind)
{
   int   i;

   for( i = 0; kind && i < r->ncontact; i++)
      if( ! strcmp( r->contact[ i], kind))
         return( YES);
   return( NO);
}


int64_t   BGRealityContactLease( const BGReality *r)
{
   return( r->lease);
}


uint64_t   BGRealityHash( const BGReality *r, uint64_t h)
{
   NSUInteger   i;

   for( i = 0; i < r->nanchors; i++)
      h = BGMix( h ^ r->anchors[ i].entity ^ ((uint64_t) (uint32_t) r->anchors[ i].kind << 40) ^
                 ((uint64_t) (uint32_t) r->anchors[ i].cx << 8) ^ ((uint64_t) (uint32_t) r->anchors[ i].cy << 24) ^
                 ((uint64_t) (uint32_t) r->anchors[ i].z << 56) ^ (uint64_t) r->anchors[ i].centred);
   for( i = 0; i < r->nleases; i++)
      h = BGMix( h ^ r->leases[ i].entity ^ ((uint64_t) r->leases[ i].until << 16));
   return( h);
}
