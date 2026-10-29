#import "BGStore.h"

#include <stdlib.h>


@implementation BGStore

- (id) initWithRecordSize:(size_t) size
{
   if( (self = [super init]))
      _size = size;
   return( self);
}


- (void) dealloc
{
   free( _ids);
   free( _records);
   [super dealloc];
}


- (size_t) recordSize
{
   return( _size);
}


- (NSUInteger) count
{
   return( _count);
}


- (BGEntityID) entityAtIndex:(NSUInteger) i
{
   return( _ids[ i]);
}


- (void *) recordAtIndex:(NSUInteger) i
{
   return( _records + i * _size);
}


/* The position of the entity, or where it would be inserted. */
static NSUInteger   position( BGStore *self, BGEntityID entity, BOOL *found)
{
   NSUInteger   hi;
   NSUInteger   lo;
   NSUInteger   mid;

   lo = 0;
   hi = self->_count;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      if( self->_ids[ mid] < entity)
         lo = mid + 1;
      else
         hi = mid;
   }
   *found = lo < self->_count && self->_ids[ lo] == entity;
   return( lo);
}


- (void *) recordFor:(BGEntityID) entity
{
   BOOL         found;
   NSUInteger   i;

   i = position( self, entity, &found);
   return( found ? _records + i * _size : NULL);
}


- (void) setRecord:(const void *) record
               for:(BGEntityID) entity
{
   BOOL         found;
   NSUInteger   i;

   i = position( self, entity, &found);
   if( ! found)
   {
      if( _count == _capacity)
      {
         _capacity = _capacity ? _capacity * 2 : 16;
         _ids      = realloc( _ids, sizeof( BGEntityID) * _capacity);
         _records  = realloc( _records, _size * _capacity);
      }
      memmove( &_ids[ i + 1], &_ids[ i], sizeof( BGEntityID) * (_count - i));
      memmove( _records + (i + 1) * _size, _records + i * _size, _size * (_count - i));
      _ids[ i] = entity;
      _count++;
   }
   memcpy( _records + i * _size, record, _size);
}


- (void) removeRecordFor:(BGEntityID) entity
{
   BOOL         found;
   NSUInteger   i;

   i = position( self, entity, &found);
   if( ! found)
      return;
   memmove( &_ids[ i], &_ids[ i + 1], sizeof( BGEntityID) * (_count - i - 1));
   memmove( _records + i * _size, _records + (i + 1) * _size, _size * (_count - i - 1));
   _count--;
}

@end
