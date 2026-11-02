/*
 * BGStore — every component of one kind, keyed by entity ID and iterated in
 * ID order. Records are the C structs generated from content; the store
 * knows only their size.
 */
#import "BGTypes.h"


@interface BGStore : NSObject
{
   size_t       _size;
   NSUInteger   _count;
   NSUInteger   _capacity;
   BGEntityID   *_ids;
   uint8_t      *_records;
   uint64_t     _changes;
   uint64_t     _members;
}

- (id) initWithRecordSize:(size_t) size;

- (size_t) recordSize;
- (NSUInteger) count;
- (BGEntityID) entityAtIndex:(NSUInteger) i;
- (void *) recordAtIndex:(NSUInteger) i;

/* NULL if the entity has no record here */
- (void *) recordFor:(BGEntityID) entity;
/* Inserts or replaces the entity's record with a copy of `record`. */
- (void) setRecord:(const void *) record
               for:(BGEntityID) entity;
- (void) removeRecordFor:(BGEntityID) entity;
/* How many times a record was set or removed: a cache over the store is good
 * while this is as it was. */
- (uint64_t) changes;
/* How many times an entity was added or removed: a cache of which entities
 * are here is good while this is as it was. */
- (uint64_t) members;

@end
