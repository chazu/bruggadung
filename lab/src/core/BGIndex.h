/*
 * BGIndex — a map from a key to the entities filed under it, each list in
 * entity order, so a lookup costs what it finds, and reads the same however
 * it was built. The world files what stands on the ground by chunk, and
 * what is in, on, held by or part of a thing by that thing (TERRAIN.md,
 * the spatial index). Plain C.
 */
#import "BGTypes.h"


typedef struct BGIndex   BGIndex;

BGIndex            *BGIndexNew( void);
void                BGIndexFree( BGIndex *index);
void                BGIndexClear( BGIndex *index);
/* Files an entity under a key (once); unfiles it. */
void                BGIndexAdd( BGIndex *index, uint64_t key, BGEntityID entity);
void                BGIndexRemove( BGIndex *index, uint64_t key, BGEntityID entity);
/* What is filed under a key, in entity order: *n of them, or NULL. */
const BGEntityID   *BGIndexGet( const BGIndex *index, uint64_t key, NSUInteger *n);
/* Keys with anything filed. */
NSUInteger          BGIndexKeys( const BGIndex *index);
