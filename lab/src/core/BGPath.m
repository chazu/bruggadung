/*
 * BGPath: a bounded best-first search. Nodes are kept in arrays indexed by
 * the order they were reached, found by an open-addressed table of their
 * tiles, and opened from a binary heap by steps so far plus steps to go,
 * then steps to go, then the order reached: every tie is broken the same
 * way every time.
 */
#import "BGPath.h"

#include <stdlib.h>
#include <string.h>


typedef struct
{
   int32_t    x;
   int32_t    y;
   int64_t    g;            /* steps from the start */
   int64_t    h;            /* steps to go, at least */
   int32_t    parent;       /* -1 for the start */
   BOOL       closed;
} BGPathNode;

static BGPathNode   *nodes;
static NSUInteger   nodecap;
static int32_t      *table;           /* node + 1, or 0 */
static NSUInteger   tablecap;         /* a power of two */
typedef struct
{
   int64_t    f;            /* as it was when pushed: a node pushed again is newer */
   int64_t    h;
   uint32_t   seq;
   int32_t    node;
} BGPathEntry;

static BGPathEntry  *heap;
static NSUInteger   heapcap;
static uint32_t     seq;

static const int    dx[ 4] = { 0, 0, 1, -1 };
static const int    dy[ 4] = { -1, 1, 0, 0 };


static int64_t   to_go( const BGPathQuery *q, int32_t x, int32_t y)
{
   int64_t   ax;
   int64_t   ay;

   if( ! q->targeted)
      return( 0);
   ax = llabs( (int64_t) x - q->tx) - 1;
   ay = llabs( (int64_t) y - q->ty) - 1;
   return( (ax > 0 ? ax : 0) + (ay > 0 ? ay : 0));
}


static NSUInteger   slot( int32_t x, int32_t y)
{
   return( (NSUInteger) BGMix( ((uint64_t) (uint32_t) x << 32) | (uint32_t) y) & (tablecap - 1));
}


/* The node at a tile, or -1. */
static int32_t   node_at( int32_t x, int32_t y)
{
   NSUInteger   i;

   for( i = slot( x, y); table[ i]; i = (i + 1) & (tablecap - 1))
      if( nodes[ table[ i] - 1].x == x && nodes[ table[ i] - 1].y == y)
         return( table[ i] - 1);
   return( -1);
}


static void   table_put( int32_t n)
{
   NSUInteger   i;

   for( i = slot( nodes[ n].x, nodes[ n].y); table[ i]; i = (i + 1) & (tablecap - 1))
      ;
   table[ i] = n + 1;
}


static BOOL   before( const BGPathEntry *a, const BGPathEntry *b)
{
   if( a->f != b->f)
      return( a->f < b->f);
   if( a->h != b->h)
      return( a->h < b->h);
   return( a->seq < b->seq);
}


static void   heap_push( NSUInteger *n, int32_t node)
{
   BGPathEntry   t;
   NSUInteger    i;

   heap[ *n].f    = nodes[ node].g + nodes[ node].h;
   heap[ *n].h    = nodes[ node].h;
   heap[ *n].seq  = seq++;
   heap[ *n].node = node;
   (*n)++;
   for( i = *n - 1; i && before( &heap[ i], &heap[ (i - 1) / 2]); i = (i - 1) / 2)
   {
      t                  = heap[ i];
      heap[ i]           = heap[ (i - 1) / 2];
      heap[ (i - 1) / 2] = t;
   }
}


static int32_t   heap_pop( NSUInteger *n)
{
   BGPathEntry   t;
   NSUInteger    i;
   NSUInteger    c;
   int32_t       top;

   top      = heap[ 0].node;
   heap[ 0] = heap[ --(*n)];
   for( i = 0;; i = c)
   {
      c = 2 * i + 1;
      if( c >= *n)
         break;
      if( c + 1 < *n && before( &heap[ c + 1], &heap[ c]))
         c++;
      if( ! before( &heap[ c], &heap[ i]))
         break;
      t        = heap[ i];
      heap[ i] = heap[ c];
      heap[ c] = t;
   }
   return( top);
}


static BOOL   done( const BGPathQuery *q, int32_t x, int32_t y)
{
   if( q->targeted)
      return( llabs( (int64_t) x - q->tx) <= 1 && llabs( (int64_t) y - q->ty) <= 1);
   return( q->goal && q->goal( q->context, x, y));
}


/* The first step on the way from the start to node n. */
static BGStep   first_step( int32_t n)
{
   int32_t   p;
   int       d;

   if( nodes[ n].parent < 0)
      return( BGStepNone);
   while( (p = nodes[ n].parent) >= 0 && nodes[ p].parent >= 0)
      n = p;
   for( d = 0; d < 4; d++)
      if( nodes[ n].x == nodes[ p].x + dx[ d] && nodes[ n].y == nodes[ p].y + dy[ d])
         return( (BGStep) d);
   return( BGStepNone);
}


BGPathResult   BGPathFind( const BGPathQuery *q)
{
   BGPathResult   r;
   NSUInteger     budget;
   NSUInteger     nnodes;
   NSUInteger     nheap;
   NSUInteger     need;
   int32_t        best;
   int32_t        n;
   int32_t        m;
   int32_t        u;
   int32_t        v;
   int            d;

   memset( &r, 0, sizeof( r));
   r.step = BGStepNone;
   budget = q->budget ? q->budget : BG_PATH_BUDGET;
   need   = budget * 4 + 1;                  /* each expanded tile reaches four at most */
   if( nodecap < need)
   {
      nodecap = need;
      nodes   = realloc( nodes, nodecap * sizeof( BGPathNode));
      heap    = realloc( heap, nodecap * sizeof( BGPathEntry));
      heapcap = nodecap;
   }
   if( tablecap < need * 2)
   {
      for( tablecap = tablecap ? tablecap : 64; tablecap < need * 2; tablecap *= 2)
         ;
      table = realloc( table, tablecap * sizeof( int32_t));
   }
   memset( table, 0, tablecap * sizeof( int32_t));

   nnodes = 0;
   nheap  = 0;
   seq    = 0;
   nodes[ 0].x      = q->x;
   nodes[ 0].y      = q->y;
   nodes[ 0].g      = 0;
   nodes[ 0].h      = to_go( q, q->x, q->y);
   nodes[ 0].parent = -1;
   nodes[ 0].closed = NO;
   nnodes = 1;
   table_put( 0);
   heap_push( &nheap, 0);
   best = 0;
   while( nheap && r.expanded < budget)
   {
      n = heap_pop( &nheap);
      if( nodes[ n].closed)
         continue;
      nodes[ n].closed = YES;
      r.expanded++;
      if( done( q, nodes[ n].x, nodes[ n].y))
      {
         r.found = YES;
         best    = n;
         break;
      }
      if( nodes[ n].h < nodes[ best].h || (nodes[ n].h == nodes[ best].h && nodes[ n].g < nodes[ best].g))
         best = n;
      for( d = 0; d < 4; d++)
      {
         u = nodes[ n].x + dx[ d];
         v = nodes[ n].y + dy[ d];
         if( ! q->passable( q->context, u, v))
            continue;
         m = node_at( u, v);
         if( m >= 0)
         {
            if( nodes[ m].closed || nodes[ m].g <= nodes[ n].g + 1)
               continue;
            nodes[ m].g      = nodes[ n].g + 1;
            nodes[ m].parent = n;
         }
         else
         {
            if( nnodes == nodecap)
               continue;
            m = (int32_t) nnodes++;
            nodes[ m].x      = u;
            nodes[ m].y      = v;
            nodes[ m].g      = nodes[ n].g + 1;
            nodes[ m].h      = to_go( q, u, v);
            nodes[ m].parent = n;
            nodes[ m].closed = NO;
            table_put( m);
         }
         if( nheap < heapcap)
            heap_push( &nheap, m);
      }
   }
   if( ! r.found && ! q->targeted)
      return( r);
   r.x     = nodes[ best].x;
   r.y     = nodes[ best].y;
   r.steps = nodes[ best].g;
   r.step  = first_step( best);
   return( r);
}
