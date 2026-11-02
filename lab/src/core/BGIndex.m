/*
 * BGIndex: an open-addressed table of keys, linear probing, removed by
 * shifting back (no tombstones); a key goes when its list empties.
 */
#import "BGIndex.h"

#include <stdlib.h>
#include <string.h>


typedef struct
{
   uint64_t     key;
   BGEntityID   *ids;          /* NULL: an empty slot */
   NSUInteger   n;
   NSUInteger   cap;
} BGIndexSlot;

struct BGIndex
{
   BGIndexSlot   *slots;
   NSUInteger    cap;          /* a power of two, or 0 */
   NSUInteger    count;
};


BGIndex   *BGIndexNew( void)
{
   return( calloc( 1, sizeof( BGIndex)));
}


void   BGIndexClear( BGIndex *index)
{
   NSUInteger   i;

   for( i = 0; i < index->cap; i++)
      free( index->slots[ i].ids);
   free( index->slots);
   index->slots = NULL;
   index->cap   = 0;
   index->count = 0;
}


void   BGIndexFree( BGIndex *index)
{
   if( ! index)
      return;
   BGIndexClear( index);
   free( index);
}


static NSUInteger   home( uint64_t key, NSUInteger cap)
{
   return( (NSUInteger) BGMix( key) & (cap - 1));
}


static BGIndexSlot   *find( const BGIndex *index, uint64_t key)
{
   NSUInteger   i;

   if( ! index->count)
      return( NULL);
   for( i = home( key, index->cap); index->slots[ i].ids; i = (i + 1) & (index->cap - 1))
      if( index->slots[ i].key == key)
         return( &index->slots[ i]);
   return( NULL);
}


static void   grow( BGIndex *index)
{
   BGIndexSlot   *old;
   NSUInteger    oldcap;
   NSUInteger    i;
   NSUInteger    j;

   old          = index->slots;
   oldcap       = index->cap;
   index->cap   = oldcap ? oldcap * 2 : 16;
   index->slots = calloc( index->cap, sizeof( BGIndexSlot));
   for( i = 0; i < oldcap; i++)
      if( old[ i].ids)
      {
         for( j = home( old[ i].key, index->cap); index->slots[ j].ids; j = (j + 1) & (index->cap - 1))
            ;
         index->slots[ j] = old[ i];
      }
   free( old);
}


/* Where an entity is, or would go, in a sorted list. */
static NSUInteger   position( const BGIndexSlot *s, BGEntityID e, BOOL *found)
{
   NSUInteger   lo;
   NSUInteger   hi;
   NSUInteger   mid;

   lo = 0;
   hi = s->n;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      if( s->ids[ mid] < e)
         lo = mid + 1;
      else
         hi = mid;
   }
   *found = lo < s->n && s->ids[ lo] == e;
   return( lo);
}


void   BGIndexAdd( BGIndex *index, uint64_t key, BGEntityID entity)
{
   BGIndexSlot   *s;
   NSUInteger    i;
   BOOL          found;

   if( ! (s = find( index, key)))
   {
      if( (index->count + 1) * 2 > index->cap)
         grow( index);
      for( i = home( key, index->cap); index->slots[ i].ids; i = (i + 1) & (index->cap - 1))
         ;
      s      = &index->slots[ i];
      s->key = key;
      s->cap = 4;
      s->n   = 0;
      s->ids = malloc( s->cap * sizeof( BGEntityID));
      index->count++;
   }
   i = position( s, entity, &found);
   if( found)
      return;
   if( s->n == s->cap)
   {
      s->cap *= 2;
      s->ids  = realloc( s->ids, s->cap * sizeof( BGEntityID));
   }
   memmove( &s->ids[ i + 1], &s->ids[ i], (s->n - i) * sizeof( BGEntityID));
   s->ids[ i] = entity;
   s->n++;
}


void   BGIndexRemove( BGIndex *index, uint64_t key, BGEntityID entity)
{
   BGIndexSlot   *s;
   NSUInteger    i;
   NSUInteger    j;
   NSUInteger    k;
   BOOL          found;

   if( ! (s = find( index, key)))
      return;
   i = position( s, entity, &found);
   if( ! found)
      return;
   memmove( &s->ids[ i], &s->ids[ i + 1], (s->n - i - 1) * sizeof( BGEntityID));
   if( --s->n)
      return;
   /* the key goes: shift back what probed past it */
   free( s->ids);
   memset( s, 0, sizeof( *s));
   index->count--;
   i = (NSUInteger) (s - index->slots);
   for( j = (i + 1) & (index->cap - 1); index->slots[ j].ids; j = (j + 1) & (index->cap - 1))
   {
      k = home( index->slots[ j].key, index->cap);
      /* move j to i if its home is not in (i, j] cyclically */
      if( (j > i && (k <= i || k > j)) || (j < i && k <= i && k > j))
      {
         index->slots[ i] = index->slots[ j];
         memset( &index->slots[ j], 0, sizeof( BGIndexSlot));
         i = j;
      }
   }
}


const BGEntityID   *BGIndexGet( const BGIndex *index, uint64_t key, NSUInteger *n)
{
   BGIndexSlot   *s;

   s  = find( index, key);
   *n = s ? s->n : 0;
   return( s ? s->ids : NULL);
}


NSUInteger   BGIndexKeys( const BGIndex *index)
{
   return( index->count);
}
