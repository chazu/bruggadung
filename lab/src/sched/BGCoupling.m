#import "BGCoupling.h"


@implementation BGSnapshot

- (void) dealloc
{
   free( _entities);
   free( _quantities);
   free( _values);
   [super dealloc];
}


- (void) setQuantity:(BGQuantity) quantity
                  of:(BGEntityID) entity
                  to:(int64_t) value
{
   NSUInteger   i;

   for( i = 0; i < _count; i++)
      if( _entities[ i] == entity && _quantities[ i] == quantity)
      {
         _values[ i] = value;
         return;
      }
   if( _count == _size)
   {
      _size       = _size ? _size * 2 : 16;
      _entities   = realloc( _entities, _size * sizeof( BGEntityID));
      _quantities = realloc( _quantities, _size * sizeof( BGQuantity));
      _values     = realloc( _values, _size * sizeof( int64_t));
   }
   _entities[ _count]   = entity;
   _quantities[ _count] = quantity;
   _values[ _count]     = value;
   _count++;
}


- (BOOL) quantity:(BGQuantity) quantity
               of:(BGEntityID) entity
            value:(int64_t *) value
{
   NSUInteger   i;

   for( i = 0; i < _count; i++)
      if( _entities[ i] == entity && _quantities[ i] == quantity)
      {
         *value = _values[ i];
         return( YES);
      }
   return( NO);
}

@end


@implementation BGContributions

- (void) dealloc
{
   free( _items);
   [super dealloc];
}


- (void) addContribution:(BGContribution) contribution
{
   if( _count == _size)
   {
      _size  = _size ? _size * 2 : 16;
      _items = realloc( _items, _size * sizeof( BGContribution));
   }
   _items[ _count++] = contribution;
}


- (NSUInteger) count
{
   return( _count);
}


- (BGContribution) contributionAtIndex:(NSUInteger) i
{
   return( _items[ i]);
}

@end
