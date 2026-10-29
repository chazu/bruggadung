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

@end
