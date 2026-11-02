/*
 * BGWakes: a binary heap of (time, thing), ties by thing.
 */
#import "BGWakes.h"

#include <stdlib.h>
#include <string.h>


typedef struct
{
   int64_t      at;
   BGEntityID   thing;
} BGWake;

struct BGWakes
{
   BGWake       *heap;
   NSUInteger   n;
   NSUInteger   cap;
};


BGWakes   *BGWakesNew( void)
{
   return( calloc( 1, sizeof( BGWakes)));
}


void   BGWakesClear( BGWakes *q)
{
   q->n = 0;
}


void   BGWakesFree( BGWakes *q)
{
   if( ! q)
      return;
   free( q->heap);
   free( q);
}


NSUInteger   BGWakesCount( const BGWakes *q)
{
   return( q->n);
}


static BOOL   before( const BGWake *x, const BGWake *y)
{
   return( x->at < y->at || (x->at == y->at && x->thing < y->thing));
}


void   BGWakesPush( BGWakes *q, BGEntityID thing, int64_t at)
{
   BGWake       t;
   NSUInteger   i;

   if( at == INT64_MAX)
      return;
   if( q->n == q->cap)
   {
      q->cap  = q->cap ? q->cap * 2 : 64;
      q->heap = realloc( q->heap, q->cap * sizeof( BGWake));
   }
   q->heap[ q->n].at    = at;
   q->heap[ q->n].thing = thing;
   for( i = q->n++; i && before( &q->heap[ i], &q->heap[ (i - 1) / 2]); i = (i - 1) / 2)
   {
      t                      = q->heap[ i];
      q->heap[ i]            = q->heap[ (i - 1) / 2];
      q->heap[ (i - 1) / 2]  = t;
   }
}


static BGWake   pop( BGWakes *q)
{
   BGWake       top;
   BGWake       t;
   NSUInteger   i;
   NSUInteger   c;

   top        = q->heap[ 0];
   q->heap[ 0] = q->heap[ --q->n];
   for( i = 0;; i = c)
   {
      c = 2 * i + 1;
      if( c >= q->n)
         break;
      if( c + 1 < q->n && before( &q->heap[ c + 1], &q->heap[ c]))
         c++;
      if( ! before( &q->heap[ c], &q->heap[ i]))
         break;
      t           = q->heap[ i];
      q->heap[ i] = q->heap[ c];
      q->heap[ c] = t;
   }
   return( top);
}


int64_t   BGWakesNext( BGWakes *q, BGWakeTime now, void *context)
{
   BGWake    top;
   int64_t   at;

   while( q->n)
   {
      top = q->heap[ 0];
      at  = now( context, top.thing);
      if( at == top.at)
         return( at);
      pop( q);
      BGWakesPush( q, top.thing, at);       /* its time now, if it has one */
   }
   return( INT64_MAX);
}


static int   cmp_thing( const void *a, const void *b)
{
   BGEntityID   x;
   BGEntityID   y;

   x = *(const BGEntityID *) a;
   y = *(const BGEntityID *) b;
   return( x < y ? -1 : x > y);
}


BGEntityID   *BGWakesTake( BGWakes *q, int64_t t, BGWakeTime now, void *context, NSUInteger *n)
{
   BGEntityID   *due;
   BGWake       top;
   NSUInteger   k;
   NSUInteger   i;
   int64_t      at;

   due = malloc( (q->n + 1) * sizeof( BGEntityID));
   k   = 0;
   while( q->n && q->heap[ 0].at <= t)
   {
      top = pop( q);
      at  = now( context, top.thing);
      if( at == top.at)
         due[ k++] = top.thing;
      else
         BGWakesPush( q, top.thing, at);    /* stale: its time now */
   }
   qsort( due, k, sizeof( BGEntityID), cmp_thing);
   for( *n = 0, i = 0; i < k; i++)
      if( ! *n || due[ *n - 1] != due[ i])
         due[ (*n)++] = due[ i];
   return( due);
}
