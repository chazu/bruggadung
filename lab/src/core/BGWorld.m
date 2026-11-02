#define BG_COMPONENT_REGISTRY
#import "BGWorld.h"
#import "BGIndex.h"
#import "BGReality.h"

#include <stdio.h>
#include <stdlib.h>


const char   *BGEdgeKindNames[ BGEdgeKindCount] =
{
   "splitFrom",
   "claimant",
   "claimSubject",
   "derivedFrom",
   "authorizes",
   "lists"
};


/* --- the journal ----------------------------------------------------------- */

typedef enum
{
   BGJournalRecord,
   BGJournalEdgeAdd,
   BGJournalEdgeRemove,
   BGJournalNextID,
   BGJournalEvents,
   BGJournalTerrain
} BGJournalOp;

typedef struct
{
   BGJournalOp   op;
   BGStore       *store;
   NSUInteger    kind;         /* a component kind, or one of the codes below */
   BGEntityID    entity;
   BOOL          had;
   void          *old;
   BGEdge        edge;
   uint64_t      value;         /* terrain: the kind it was */
   BGLocation    tile;          /* terrain: the cell */
} BGJournalEntry;

/* kind codes for the stores that aren't component kinds */
#define BGKindEntities     ((NSUInteger) 1000001)
#define BGKindLocations    ((NSUInteger) 1000002)
#define BGKindTombstones   ((NSUInteger) 1000003)


void   BGLocationFormat( BGLocation loc, char *buf, size_t len)
{
   switch( loc.form)
   {
   case BGLocationNone:
      snprintf( buf, len, "nowhere");
      break;

   case BGLocationOnTile:
      snprintf( buf, len, "onTile(%d, %d, %d)", loc.x, loc.y, loc.level);
      break;

   case BGLocationIn:
      snprintf( buf, len, "in(%llu)", (unsigned long long) loc.place);
      break;

   case BGLocationHeldBy:
      snprintf( buf, len, "heldBy(%llu, %d)", (unsigned long long) loc.place, loc.slot);
      break;

   case BGLocationPartOf:
      snprintf( buf, len, "partOf(%llu, %s, %d)", (unsigned long long) loc.place, loc.role, loc.slot);
      break;
   }
}


/* --- tile stocks --------------------------------------------------------- */

/* Water per tile, a chunk of BG_CHUNK x BG_CHUNK cells of a level at a
 * time, kept once a tile in it is wet or checked out: a world costs what has
 * ever been wet, not its extent. */
typedef struct
{
   int32_t   cx;
   int32_t   cy;
   int32_t   z;
   int64_t   *water;          /* NULL: an empty slot */
   uint8_t   *out;
} BGStockChunk;

struct BGTileStocks
{
   BGStockChunk   *chunks;
   NSUInteger     n;
   NSUInteger     cap;        /* a power of two, or 0 */
};


static struct BGTileStocks   *stocks_new( void)
{
   return( calloc( 1, sizeof( struct BGTileStocks)));
}


static void   stocks_free( struct BGTileStocks *s)
{
   NSUInteger   i;

   for( i = 0; i < s->cap; i++)
   {
      free( s->chunks[ i].water);
      free( s->chunks[ i].out);
   }
   free( s->chunks);
   free( s);
}


static NSUInteger   stock_slot( int32_t cx, int32_t cy, int32_t z, NSUInteger cap)
{
   return( (NSUInteger) BGMix( ((uint64_t) (uint32_t) cx << 32) ^ ((uint64_t) (uint32_t) cy << 8) ^ (uint64_t) (uint32_t) z) &
           (cap - 1));
}


static BGStockChunk   *stocks_chunk( struct BGTileStocks *s, int32_t x, int32_t y, int32_t z, BOOL make)
{
   BGStockChunk   *old;
   NSUInteger     oldcap;
   NSUInteger     i;
   NSUInteger     j;
   int32_t        cx;
   int32_t        cy;

   cx = x / BG_CHUNK;
   cy = y / BG_CHUNK;
   for( i = s->cap ? stock_slot( cx, cy, z, s->cap) : 0; s->cap && s->chunks[ i].water; i = (i + 1) & (s->cap - 1))
      if( s->chunks[ i].cx == cx && s->chunks[ i].cy == cy && s->chunks[ i].z == z)
         return( &s->chunks[ i]);
   if( ! make)
      return( NULL);
   if( (s->n + 1) * 2 > s->cap)
   {
      old       = s->chunks;
      oldcap    = s->cap;
      s->cap    = oldcap ? oldcap * 2 : 8;
      s->chunks = calloc( s->cap, sizeof( BGStockChunk));
      for( i = 0; i < oldcap; i++)
         if( old[ i].water)
         {
            for( j = stock_slot( old[ i].cx, old[ i].cy, old[ i].z, s->cap); s->chunks[ j].water; j = (j + 1) & (s->cap - 1))
               ;
            s->chunks[ j] = old[ i];
         }
      free( old);
   }
   for( i = stock_slot( cx, cy, z, s->cap); s->chunks[ i].water; i = (i + 1) & (s->cap - 1))
      ;
   s->chunks[ i].cx    = cx;
   s->chunks[ i].cy    = cy;
   s->chunks[ i].z     = z;
   s->chunks[ i].water = calloc( BG_CHUNK * BG_CHUNK, sizeof( int64_t));
   s->chunks[ i].out   = calloc( BG_CHUNK * BG_CHUNK, 1);
   s->n++;
   return( &s->chunks[ i]);
}


static int64_t   *stocks_cell( struct BGTileStocks *s, int32_t x, int32_t y, int32_t z, BOOL make)
{
   BGStockChunk   *c;

   c = stocks_chunk( s, x, y, z, make);
   return( c ? &c->water[ (y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] : NULL);
}


static uint8_t   *stocks_out( struct BGTileStocks *s, int32_t x, int32_t y, int32_t z, BOOL make)
{
   BGStockChunk   *c;

   c = stocks_chunk( s, x, y, z, make);
   return( c ? &c->out[ (y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] : NULL);
}


static BOOL   stocks_any( struct BGTileStocks *s)
{
   NSUInteger   i;
   NSUInteger   k;

   for( i = 0; i < s->cap; i++)
      for( k = 0; s->chunks[ i].water && k < BG_CHUNK * BG_CHUNK; k++)
         if( s->chunks[ i].water[ k] || s->chunks[ i].out[ k])
            return( YES);
   return( NO);
}


static int64_t   stocks_total( struct BGTileStocks *s)
{
   NSUInteger   i;
   NSUInteger   k;
   int64_t      sum;

   sum = 0;
   for( i = 0; i < s->cap; i++)
      for( k = 0; s->chunks[ i].water && k < BG_CHUNK * BG_CHUNK; k++)
         if( ! s->chunks[ i].out[ k])
            sum += s->chunks[ i].water[ k];
   return( sum);
}


static int   cmp_tile( const void *a, const void *b)
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


/* The wet tiles, by level, row, column; how many, filling up to max. */
static NSUInteger   stocks_wet( struct BGTileStocks *s, int32_t (*out)[ 3], NSUInteger max)
{
   NSUInteger   i;
   NSUInteger   k;
   NSUInteger   n;

   n = 0;
   for( i = 0; i < s->cap; i++)
      for( k = 0; s->chunks[ i].water && k < BG_CHUNK * BG_CHUNK; k++)
         if( s->chunks[ i].water[ k])
         {
            if( n < max)
            {
               out[ n][ 0] = s->chunks[ i].cx * BG_CHUNK + (int32_t) (k % BG_CHUNK);
               out[ n][ 1] = s->chunks[ i].cy * BG_CHUNK + (int32_t) (k / BG_CHUNK);
               out[ n][ 2] = s->chunks[ i].z;
            }
            n++;
         }
   if( out && max)
      qsort( out, n < max ? n : max, sizeof( *out), cmp_tile);
   return( n);
}


@implementation BGWorld

+ (instancetype) worldWithContent:(BGContent *) content
                             seed:(uint64_t) seed
                            error:(NSString **) error
{
   BGWorld   *world;

   if( [content contentHash] != BG_CONTENT_HASH)
   {
      if( error)
         *error = [NSString stringWithFormat:@"the content (%016llx) is not what src/generated/BGComponents.h "
                                             @"was generated from (%016llx): run make gen",
                                             (unsigned long long) [content contentHash],
                                             (unsigned long long) BG_CONTENT_HASH];
      return( nil);
   }
   world = [[[self alloc] initWithContent:content
                                     seed:seed] autorelease];
   return( world);
}


- (id) initWithContent:(BGContent *) content
                  seed:(uint64_t) seed
{
   NSUInteger   k;

   if( ! (self = [super init]))
      return( nil);

   _content   = [content retain];
   _seed      = seed;
   _nextID    = 1;
   _nkinds    = BG_COMPONENT_COUNT;
   _kinds     = calloc( _nkinds ? _nkinds : 1, sizeof( BGStore *));
   _kindTypes = calloc( _nkinds ? _nkinds : 1, sizeof( TriType));
   for( k = 0; k < _nkinds; k++)
   {
      _kinds[ k]     = [[BGStore alloc] initWithRecordSize:BGComponents[ k].size];
      _kindTypes[ k] = tri_type_named( [content content], BGComponents[ k].type);
   }
   _trueType   = tri_type_named( [content content], "true");
   _kindTrace    = [self kindNamed:"Trace"];
   _kindGas      = [self kindNamed:"GasStore"];
   _kindActivity = [self kindNamed:"Activity"];
   _entities   = [[BGStore alloc] initWithRecordSize:sizeof( BGEntityInfo)];
   _locations  = [[BGStore alloc] initWithRecordSize:sizeof( BGLocation)];
   _tombstones = [[BGStore alloc] initWithRecordSize:sizeof( BGTombstone)];
   _onGround       = BGIndexNew();
   _inPlace        = BGIndexNew();
   _tracesOnGround = BGIndexNew();
   _tracesBorne    = BGIndexNew();
   _activitiesOf   = BGIndexNew();
   _watching       = BGIndexNew();
   _touching       = BGIndexNew();
   _creations      = BGIndexNew();
   _reality        = BGRealityNew( [content content]);
   _arena      = tri_arena_new();
   _tilesWide  = 32;
   _tilesHigh  = 32;
   _levels     = 1;
   _stocks     = stocks_new();
   {
      char   why[ 256];

      _terrain = BGTerrainNew( [content content], _tilesWide, _tilesHigh, _levels, NULL, why, sizeof( why));
   }
   return( self);
}


- (void) dealloc
{
   NSUInteger   i;

   [self commitGroup];
   for( i = 0; i < _nkinds; i++)
      [_kinds[ i] release];
   free( _kinds);
   free( _kindTypes);
   [_entities release];
   [_locations release];
   [_tombstones release];
   free( _edges);
   free( _events);
   for( i = 0; i < _nstrings; i++)
      free( _strings[ i]);
   free( _strings);
   free( _journal);
   stocks_free( _stocks);
   BGTerrainFree( _terrain);
   free( _roomAir);
   free( _touched);
   free( _vacated);
   BGIndexFree( _onGround);
   BGIndexFree( _inPlace);
   BGIndexFree( _tracesOnGround);
   BGIndexFree( _tracesBorne);
   BGIndexFree( _activitiesOf);
   BGIndexFree( _watching);
   BGIndexFree( _touching);
   BGIndexFree( _creations);
   BGRealityFree( _reality);
   free( _checkedOut);
   tri_arena_free( _arena);
   [_content release];
   [super dealloc];
}


- (BGContent *) contentBuild
{
   return( _content);
}


- (TriContent *) tri
{
   return( [_content content]);
}


- (uint64_t) seed
{
   return( _seed);
}


- (BGTime) time
{
   return( _time);
}


- (void) setTime:(BGTime) time
{
   _time = time;
}


- (uint64_t) boundary
{
   return( _boundary);
}


- (void) setBoundary:(uint64_t) boundary
{
   _boundary = boundary;
}


- (BGEntityID) nextID
{
   return( _nextID);
}


- (void) setNextID:(BGEntityID) nextID
{
   _nextID = nextID;
}


- (void) restoreTombstone:(BGTombstone) stone
                      for:(BGEntityID) entity
{
   stone.blueprint = [self intern:stone.blueprint];
   [_tombstones setRecord:&stone
                      for:entity];
}


- (BGStore *) entities
{
   return( _entities);
}


- (BGStore *) tombstones
{
   return( _tombstones);
}


- (NSUInteger) edgeCount
{
   return( _nedges);
}


- (const BGEdge *) edgeAt:(NSUInteger) i
{
   return( i < _nedges ? &_edges[ i] : NULL);
}


/* --- journal --------------------------------------------------------------- */

static BGJournalEntry   *journal_push( BGWorld *self)
{
   BGJournalEntry   *entries;

   if( self->_njournal == self->_journalCapacity)
   {
      self->_journalCapacity = self->_journalCapacity ? self->_journalCapacity * 2 : 64;
      self->_journal         = realloc( self->_journal, sizeof( BGJournalEntry) * self->_journalCapacity);
   }
   entries = self->_journal;
   memset( &entries[ self->_njournal], 0, sizeof( BGJournalEntry));
   return( &entries[ self->_njournal++]);
}


static void   journal_record( BGWorld *self, BGStore *store, NSUInteger kind, BGEntityID entity)
{
   BGJournalEntry   *j;
   void             *current;

   if( ! self->_open)
      return;
   j         = journal_push( self);
   j->op     = BGJournalRecord;
   j->store  = store;
   j->kind   = kind;
   j->entity = entity;
   current   = [store recordFor:entity];
   j->had    = current != NULL;
   if( current)
   {
      j->old = malloc( [store recordSize]);
      memcpy( j->old, current, [store recordSize]);
   }
}


- (void) beginGroup
{
   [self commitGroup];
   _open = YES;
}


- (void) commitGroup
{
   BGJournalEntry   *entries;
   NSUInteger       i;

   entries = _journal;
   for( i = 0; i < _njournal; i++)
      free( entries[ i].old);
   _njournal = 0;
   _open     = NO;
}


static void   edge_insert_raw( BGWorld *self, BGEdge e);
static void   file_record( BGWorld *self, NSUInteger kind, BGEntityID entity, BOOL add);
static void   edge_remove_raw( BGWorld *self, BGEdge e);


- (void) rollbackGroup
{
   BGJournalEntry   *entries;
   BGJournalEntry   *j;
   NSUInteger       i;

   entries = _journal;
   for( i = _njournal; i-- > 0;)
   {
      j = &entries[ i];
      switch( j->op)
      {
      case BGJournalRecord:
         if( _kindGas < _nkinds && j->store == _kinds[ _kindGas])
            _airAnchors++;
         if( j->store == _locations)
            file_location( self, j->entity, [_locations recordFor:j->entity], NO);
         if( j->kind < _nkinds && j->store == _kinds[ j->kind])
            file_record( self, j->kind, j->entity, NO);
         if( j->had)
            [j->store setRecord:j->old
                            for:j->entity];
         else
            [j->store removeRecordFor:j->entity];
         if( j->store == _locations)
            file_location( self, j->entity, [_locations recordFor:j->entity], YES);
         if( j->kind < _nkinds && j->store == _kinds[ j->kind])
            file_record( self, j->kind, j->entity, YES);
         break;

      case BGJournalEdgeAdd:
         edge_remove_raw( self, j->edge);
         break;

      case BGJournalEdgeRemove:
         edge_insert_raw( self, j->edge);
         break;

      case BGJournalNextID:
         _nextID = j->value;
         break;

      case BGJournalEvents:
         _nevents = (NSUInteger) j->value;
         break;

      case BGJournalTerrain:
         BGTerrainSet( _terrain, j->tile.x, j->tile.y, j->tile.level, (BGTerrainKind) j->value);
         break;
      }
   }
   [self commitGroup];
}


static int   cmp_id( const void *a, const void *b)
{
   BGEntityID   x;
   BGEntityID   y;

   x = *(const BGEntityID *) a;
   y = *(const BGEntityID *) b;
   return( x < y ? -1 : x > y);
}


- (NSUInteger) touched:(BGEntityID *) out
                   max:(NSUInteger) max
{
   BGEntityID       *all;
   BGJournalEntry   *entries;
   NSUInteger       i;
   NSUInteger       n;
   NSUInteger       u;

   entries = _journal;
   all     = malloc( sizeof( BGEntityID) * (_njournal ? _njournal : 1));
   n       = 0;
   for( i = 0; i < _njournal; i++)
      if( entries[ i].op == BGJournalRecord)
         all[ n++] = entries[ i].entity;
   qsort( all, n, sizeof( BGEntityID), cmp_id);
   u = 0;
   for( i = 0; i < n; i++)
      if( ! i || all[ i] != all[ i - 1])
      {
         if( u < max)
            out[ u] = all[ i];
         u++;
      }
   free( all);
   return( u);
}


- (const void *) recordBeforeGroup:(NSUInteger) kind
                               for:(BGEntityID) entity
                           existed:(BOOL *) existed
{
   BGJournalEntry   *entries;
   NSUInteger       i;
   void             *current;

   entries = _journal;
   for( i = 0; i < _njournal; i++)
      if( entries[ i].op == BGJournalRecord && entries[ i].kind == kind && entries[ i].entity == entity)
      {
         *existed = entries[ i].had;
         return( entries[ i].old);
      }
   current  = [_kinds[ kind] recordFor:entity];
   *existed = current != NULL;
   return( current);
}


- (const BGEntityInfo *) infoBeforeGroup:(BGEntityID) entity
{
   BGJournalEntry   *entries;
   NSUInteger       i;

   entries = _journal;
   for( i = 0; i < _njournal; i++)
      if( entries[ i].op == BGJournalRecord && entries[ i].kind == BGKindEntities && entries[ i].entity == entity)
         return( entries[ i].had ? entries[ i].old : NULL);
   return( [_entities recordFor:entity]);
}


/* --- component kinds and fields -------------------------------------------- */

- (NSUInteger) kindCount
{
   return( _nkinds);
}


- (NSUInteger) kindNamed:(const char *) name
{
   NSUInteger   slot;
   NSUInteger   k;

   /* most names asked are literals, the same address each time: kept by
    * it, and checked, as a buffer may hold another name at that address */
   slot = ((uintptr_t) name >> 3) & 63;
   if( _kindCache[ slot].name == name && _kindCache[ slot].kind < _nkinds &&
       ! strcmp( BGComponents[ _kindCache[ slot].kind].name, name))
      return( _kindCache[ slot].kind);
   for( k = 0; k < _nkinds; k++)
      if( ! strcmp( BGComponents[ k].name, name))
      {
         _kindCache[ slot].name = name;
         _kindCache[ slot].kind = k;
         return( k);
      }
   return( NSNotFound);
}


- (const BGComponentInfo *) kindInfo:(NSUInteger) kind
{
   return( &BGComponents[ kind]);
}


- (BGStore *) storeForKind:(NSUInteger) kind
{
   return( _kinds[ kind]);
}


- (const void *) record:(NSUInteger) kind
                    for:(BGEntityID) entity
{
   if( kind >= _nkinds)
      return( NULL);
   return( [_kinds[ kind] recordFor:entity]);
}


static uint64_t   ground_key( int32_t x, int32_t y, int32_t level);


/* Files or unfiles a trace where it is: on what bears it, or its tile. */
static void   file_trace( BGWorld *self, BGEntityID entity, const BGTrace *trace, BOOL add)
{
   struct BGIndex   *index;
   uint64_t         key;

   if( ! trace)
      return;
   if( trace->bearer)
   {
      index = self->_tracesBorne;
      key   = trace->bearer;
   }
   else
   {
      index = self->_tracesOnGround;
      key   = ground_key( (int32_t) trace->tileX, (int32_t) trace->tileY, (int32_t) trace->tileLevel);
   }
   if( add)
      BGIndexAdd( index, key, entity);
   else
      BGIndexRemove( index, key, entity);
}


/* Files or unfiles an activity: under its actor, and, with a watch, among
 * those watching. */
static void   file_activity( BGWorld *self, BGEntityID entity, const BGActivity *activity, BOOL add)
{
   if( ! activity)
      return;
   if( add)
   {
      BGIndexAdd( self->_activitiesOf, activity->actorRef, entity);
      if( activity->actorRef)
         BGIndexAdd( self->_touching, activity->actorRef, entity);
      if( activity->itemRef)
         BGIndexAdd( self->_touching, activity->itemRef, entity);
      if( activity->destinationRef)
         BGIndexAdd( self->_touching, activity->destinationRef, entity);
      if( activity->watchHolder || activity->watchFloor || activity->watchDioxide || activity->watchCool ||
          activity->watchWarm)
         BGIndexAdd( self->_watching, 0, entity);
   }
   else
   {
      BGIndexRemove( self->_activitiesOf, activity->actorRef, entity);
      BGIndexRemove( self->_touching, activity->actorRef, entity);
      BGIndexRemove( self->_touching, activity->itemRef, entity);
      BGIndexRemove( self->_touching, activity->destinationRef, entity);
      BGIndexRemove( self->_watching, 0, entity);
   }
}


/* A thing is leaving where it was: the ground tile under it, noted. */
static void   vacate( BGWorld *self, const BGLocation *was)
{
   BGLocation   at;
   NSUInteger   guard;

   if( ! was)
      return;
   for( at = *was, guard = 0; at.form != BGLocationOnTile && at.form != BGLocationNone && at.place && guard < 64; guard++)
      at = [self locationOf:at.place];
   if( at.form != BGLocationOnTile)
      return;
   if( self->_nvacated == self->_vacatedcap)
   {
      self->_vacatedcap = self->_vacatedcap ? self->_vacatedcap * 2 : 64;
      self->_vacated    = realloc( self->_vacated, self->_vacatedcap * sizeof( BGLocation));
   }
   self->_vacated[ self->_nvacated++] = at;
}


/* An entity changed: noted for those who work when something happens. */
static void   touch( BGWorld *self, BGEntityID entity)
{
   if( self->_ntouched && self->_touched[ self->_ntouched - 1] == entity)
      return;
   if( self->_ntouched == self->_touchedcap)
   {
      self->_touchedcap = self->_touchedcap ? self->_touchedcap * 2 : 256;
      self->_touched    = realloc( self->_touched, self->_touchedcap * sizeof( BGEntityID));
   }
   self->_touched[ self->_ntouched++] = entity;
}


/* Files or unfiles a record in what the world indexes of its kind. */
static void   file_record( BGWorld *self, NSUInteger kind, BGEntityID entity, BOOL add)
{
   if( add)
      touch( self, entity);
   if( add && kind == self->_kindActivity && self->_activityObserver)
      [self->_activityObserver world:self changedRecord:entity kind:kind];
   if( kind == self->_kindTrace)
      file_trace( self, entity, [self->_kinds[ kind] recordFor:entity], add);
   else if( kind == self->_kindActivity)
      file_activity( self, entity, [self->_kinds[ kind] recordFor:entity], add);
}


- (void) setRecord:(const void *) record
              kind:(NSUInteger) kind
               for:(BGEntityID) entity
{
   journal_record( self, _kinds[ kind], kind, entity);
   file_record( self, kind, entity, NO);
   [_kinds[ kind] setRecord:record
                        for:entity];
   file_record( self, kind, entity, YES);
}


- (void) removeRecord:(NSUInteger) kind
                  for:(BGEntityID) entity
{
   if( ! [_kinds[ kind] recordFor:entity])
      return;
   journal_record( self, _kinds[ kind], kind, entity);
   file_record( self, kind, entity, NO);
   [_kinds[ kind] removeRecordFor:entity];
   touch( self, entity);
}


- (BOOL) lookupField:(const char *) path
                kind:(NSUInteger *) kind
               field:(const BGFieldInfo **) field
{
   const char   *dot;
   char         name[ 64];
   NSUInteger   k;
   size_t       i;

   dot = strchr( path, '.');
   if( ! dot || (size_t) (dot - path) >= sizeof( name))
      return( NO);
   memcpy( name, path, (size_t) (dot - path));
   name[ dot - path] = 0;
   k = [self kindNamed:name];
   if( k == NSNotFound)
      return( NO);
   for( i = 0; i < BGComponents[ k].nfields; i++)
      if( ! strcmp( BGComponents[ k].fields[ i].name, dot + 1))
      {
         *kind  = k;
         *field = &BGComponents[ k].fields[ i];
         return( YES);
      }
   return( NO);
}


static int64_t   field_get( const BGFieldInfo *f, const void *record)
{
   const uint8_t   *p;

   p = (const uint8_t *) record + f->offset;
   switch( f->value)
   {
   case BG_VALUE_QUANTITY:
      return( *(const int64_t *) p);
   case BG_VALUE_TYPE:
      return( *(const uint32_t *) p);
   case BG_VALUE_BOOL:
      return( *(const bool *) p);
   case BG_VALUE_REF:
      return( (int64_t) *(const uint64_t *) p);
   default:
      return( 0);
   }
}


static BOOL   field_set( const BGFieldInfo *f, void *record, int64_t value)
{
   uint8_t   *p;

   p = (uint8_t *) record + f->offset;
   switch( f->value)
   {
   case BG_VALUE_QUANTITY:
      *(int64_t *) p = value;
      return( YES);
   case BG_VALUE_TYPE:
      *(uint32_t *) p = (uint32_t) value;
      return( YES);
   case BG_VALUE_BOOL:
      *(bool *) p = value != 0;
      return( YES);
   case BG_VALUE_REF:
      *(uint64_t *) p = (uint64_t) value;
      return( YES);
   default:
      return( NO);
   }
}


- (BOOL) getField:(const char *) path
               of:(BGEntityID) entity
            value:(int64_t *) value
{
   const BGFieldInfo   *f;
   const void          *record;
   NSUInteger          k;

   if( ! [self lookupField:path
                      kind:&k
                     field:&f])
      return( NO);
   record = [_kinds[ k] recordFor:entity];
   if( ! record)
      return( NO);
   *value = field_get( f, record);
   return( YES);
}


- (BOOL) setField:(const char *) path
               of:(BGEntityID) entity
            value:(int64_t) value
{
   const BGFieldInfo   *f;
   const void          *record;
   NSUInteger          k;
   uint8_t             copy[ 512];

   if( ! [self lookupField:path
                      kind:&k
                     field:&f])
      return( NO);
   record = [_kinds[ k] recordFor:entity];
   if( ! record || BGComponents[ k].size > sizeof( copy))
      return( NO);
   memcpy( copy, record, BGComponents[ k].size);
   if( ! field_set( f, copy, value))
      return( NO);
   if( k == _kindGas && f->name[ 0] == 'a' && f->name[ 1] == 't')
      _airAnchors++;                /* atX, atY, atLevel: the air's room may move */
   [self setRecord:copy
              kind:k
               for:entity];
   return( YES);
}


- (BOOL) setField:(const char *) path
               of:(BGEntityID) entity
             text:(const char *) text
{
   const BGFieldInfo   *f;
   const void          *record;
   NSUInteger          k;
   uint8_t             copy[ 512];

   if( ! [self lookupField:path
                      kind:&k
                     field:&f] || f->value != BG_VALUE_TEXT)
      return( NO);
   record = [_kinds[ k] recordFor:entity];
   if( ! record || BGComponents[ k].size > sizeof( copy))
      return( NO);
   memcpy( copy, record, BGComponents[ k].size);
   *(const char **) (copy + f->offset) = text ? [self intern:text] : NULL;
   [self setRecord:copy
              kind:k
               for:entity];
   return( YES);
}


- (const char *) textField:(const char *) path
                        of:(BGEntityID) entity
{
   const BGFieldInfo   *f;
   const uint8_t       *record;
   NSUInteger          k;

   if( ! [self lookupField:path
                      kind:&k
                     field:&f] || f->value != BG_VALUE_TEXT)
      return( NULL);
   record = [_kinds[ k] recordFor:entity];
   return( record ? *(const char *const *) (record + f->offset) : NULL);
}


/* --- entities -------------------------------------------------------------- */

- (BGEntityID) allocateID
{
   BGJournalEntry   *j;

   if( _open)
   {
      j        = journal_push( self);
      j->op    = BGJournalNextID;
      j->value = _nextID;
   }
   return( _nextID++);
}


- (BOOL) isLive:(BGEntityID) entity
{
   return( [_entities recordFor:entity] != NULL);
}


- (const BGEntityInfo *) info:(BGEntityID) entity
{
   return( [_entities recordFor:entity]);
}


- (void) addEntity:(BGEntityID) entity
         blueprint:(const char *) blueprint
              seed:(uint64_t) seed
{
   BGEntityInfo   info;

   info.blueprint = [self intern:blueprint];
   info.seed      = seed;
   journal_record( self, _entities, BGKindEntities, entity);
   [_entities setRecord:&info
                    for:entity];
}


- (BOOL) construct:(BGEntityID) entity
             error:(NSString **) error
{
   const BGEntityInfo   *info;
   const BGFieldInfo    *f;
   const TriNode        *node;
   const TriNode        *v;
   TriContent           *tri;
   TriMark              mark;
   TriType              type;
   char                 text[ 256];
   int64_t              hi;
   int64_t              lo;
   size_t               i;
   size_t               n;
   NSUInteger           k;
   uint8_t              *record;
   BOOL                 ok;

   info = [self info:entity];
   if( ! info)
      return( NO);
   tri  = [self tri];
   mark = tri_arena_mark( _arena);
   node = tri_construct( tri, info->blueprint, info->seed, _arena);
   if( ! node)
   {
      if( error)
         *error = [NSString stringWithFormat:@"blueprint %s cannot be built", info->blueprint];
      tri_arena_release( _arena, mark);
      return( NO);
   }
   type = tri_node_type( node);
   ok   = YES;
   for( k = 0; k < _nkinds && ok; k++)
   {
      if( _kindTypes[ k] == TRI_BOTTOM || ! tri_subtype( tri, type, _kindTypes[ k]))
         continue;
      record = calloc( 1, BGComponents[ k].size);
      for( i = 0; i < BGComponents[ k].nfields && ok; i++)
      {
         f = &BGComponents[ k].fields[ i];
         v = tri_at( tri, node, f->name);
         if( ! v)
            continue;
         switch( f->value)
         {
         case BG_VALUE_REF:
            /* a referent is bound at runtime: left open in a blueprint, it is none */
            if( tri_node_interval( v, &lo, &hi) && lo == hi)
               field_set( f, record, lo);
            break;

         case BG_VALUE_QUANTITY:
            if( ! tri_node_interval( v, &lo, &hi) || lo != hi)
            {
               if( error)
                  *error = [NSString stringWithFormat:@"%s.%s of %s is not concrete",
                                                      BGComponents[ k].name, f->name, info->blueprint];
               ok = NO;
               break;
            }
            field_set( f, record, lo);
            break;

         case BG_VALUE_TYPE:
            field_set( f, record, tri_node_type( v));
            break;

         case BG_VALUE_BOOL:
            field_set( f, record, tri_node_type( v) == _trueType);
            break;

         case BG_VALUE_TEXT:
            n = tri_print( tri, v, text, sizeof( text));
            if( n >= 2 && n < sizeof( text) && text[ 0] == '"')
            {
               text[ n - 1] = 0;
               *(const char **) (record + f->offset) = [self intern:text + 1];
            }
            break;

         default:
            break;      /* structures are not stored yet */
         }
      }
      if( ok)
         [self setRecord:record
                    kind:k
                     for:entity];
      free( record);
   }
   tri_arena_release( _arena, mark);
   return( ok);
}


- (void) destroy:(BGEntityID) entity
       successor:(BGEntityID) successor
           cause:(uint64_t) cause
          reason:(const char *) reason
{
   BGTombstone   stone;
   NSUInteger    k;

   memset( &stone, 0, sizeof( stone));
   stone.blueprint = [self info:entity] ? [self info:entity]->blueprint : "";
   stone.successor = successor;
   stone.cause     = cause;
   strncpy( stone.reason, reason, sizeof( stone.reason) - 1);
   for( k = 0; k < _nkinds; k++)
      [self removeRecord:k
                     for:entity];
   [self setLocation:BGLocationMakeNone()
                  of:entity];
   journal_record( self, _entities, BGKindEntities, entity);
   [_entities removeRecordFor:entity];
   journal_record( self, _tombstones, BGKindTombstones, entity);
   [_tombstones setRecord:&stone
                      for:entity];
}


- (const BGTombstone *) tombstone:(BGEntityID) entity
{
   return( [_tombstones recordFor:entity]);
}


- (BGEntityID) resolve:(BGEntityID) entity
{
   const BGTombstone   *stone;
   NSUInteger          guard;

   for( guard = 0; guard < 1000; guard++)
   {
      if( [self isLive:entity])
         return( entity);
      stone = [self tombstone:entity];
      if( ! stone)
         return( BGNoEntity);
      entity = stone->successor;
   }
   return( BGNoEntity);
}


- (BOOL) isPhysical:(BGEntityID) entity
{
   return( [self record:[self kindNamed:"Body"]
                    for:entity] != NULL);
}


- (BOOL) isStack:(BGEntityID) entity
{
   return( [self record:[self kindNamed:"Stack"]
                    for:entity] != NULL);
}


- (const char *) unitOf:(BGEntityID) entity
{
   const BGStack        *stack;
   const BGEntityInfo   *info;

   stack = [self record:[self kindNamed:"Stack"]
                    for:entity];
   if( stack)
      return( stack->unit);
   info = [self info:entity];
   return( info ? info->blueprint : NULL);
}


- (int64_t) unitsOf:(BGEntityID) entity
{
   const BGStack   *stack;

   stack = [self record:[self kindNamed:"Stack"]
                    for:entity];
   if( stack)
      return( stack->count);
   return( [self isLive:entity] ? 1 : 0);
}


- (int64_t) massOf:(BGEntityID) entity
{
   const BGBody   *body;

   body = [self record:[self kindNamed:"Body"]
                   for:entity];
   return( body ? body->mass : 0);
}


/* --- locations ------------------------------------------------------------- */

- (BGLocation) locationOf:(BGEntityID) entity
{
   BGLocation   *loc;

   loc = [_locations recordFor:entity];
   return( loc ? *loc : BGLocationMakeNone());
}


/* The chunk a tile is filed under. */
static uint64_t   ground_key( int32_t x, int32_t y, int32_t level)
{
   return( ((uint64_t) (uint32_t) (x >> 5) << 32) ^ ((uint64_t) (uint32_t) (y >> 5) << 8) ^ (uint64_t) (uint32_t) level);
}


/* Files or unfiles an entity where it is (BGIndex). */
static void   file_location( BGWorld *self, BGEntityID entity, const BGLocation *loc, BOOL add)
{
   struct BGIndex   *index;
   uint64_t         key;

   if( ! loc || loc->form == BGLocationNone)
      return;
   if( loc->form == BGLocationOnTile)
   {
      index = self->_onGround;
      key   = ground_key( loc->x, loc->y, loc->level);
   }
   else
   {
      index = self->_inPlace;
      key   = loc->place;
   }
   if( add)
      BGIndexAdd( index, key, entity);
   else
      BGIndexRemove( index, key, entity);
}


- (void) setLocation:(BGLocation) location
                  of:(BGEntityID) entity
{
   if( location.form == BGLocationNone && ! [_locations recordFor:entity])
      return;
   journal_record( self, _locations, BGKindLocations, entity);
   file_location( self, entity, [_locations recordFor:entity], NO);
   vacate( self, [_locations recordFor:entity]);
   /* what held it, and what holds it now, have changed too: their contents */
   if( [_locations recordFor:entity] && ((BGLocation *) [_locations recordFor:entity])->form != BGLocationOnTile)
      touch( self, ((BGLocation *) [_locations recordFor:entity])->place);
   if( location.form != BGLocationOnTile && location.form != BGLocationNone)
      touch( self, location.place);
   if( location.form == BGLocationNone)
      [_locations removeRecordFor:entity];
   else
      [_locations setRecord:&location
                        for:entity];
   file_location( self, entity, [_locations recordFor:entity], YES);
   touch( self, entity);
}


/* --- the reality bubble ----------------------------------------------------------- */

- (struct BGReality *) reality
{
   return( _reality);
}


/* Where a thing stands on the ground, through what holds it. */
static BOOL   standing( BGWorld *self, BGEntityID e, BGLocation *tile)
{
   BGLocation   at;
   NSUInteger   guard;

   for( guard = 0; e && guard < 64; guard++)
   {
      at = [self locationOf:e];
      if( at.form == BGLocationOnTile)
      {
         *tile = at;
         return( YES);
      }
      if( at.form == BGLocationNone || ! at.place)
         return( NO);
      e = at.place;
   }
   return( NO);
}


- (BOOL) setAnchor:(BGEntityID) entity
              kind:(const char *) kind
{
   return( BGRealitySetAnchor( _reality, entity, BGRealityKindNamed( _reality, kind)));
}


- (void) removeAnchor:(BGEntityID) entity
{
   BGRealityRemoveAnchor( _reality, entity);
}


- (void) settleAnchors
{
   BGLocation   tile;
   BGEntityID   e;
   NSUInteger   i;

   for( i = 0; i < BGRealityAnchorCount( _reality); i++)
   {
      e = BGRealityAnchorAt( _reality, i, NULL, NULL, NULL, NULL, NULL);
      if( standing( self, e, &tile))
         BGRealityCentre( _reality, e, tile.x, tile.y, tile.level);
   }
   BGRealityPrune( _reality, _time.ms);
}


- (int) detailAt:(BGLocation) tile
{
   if( tile.form != BGLocationOnTile)
      return( BGDetailFull);
   return( BGRealityDetailAt( _reality, tile.x, tile.y, tile.level));
}


- (int) detailOf:(BGEntityID) entity
{
   BGLocation   tile;

   if( ! BGRealityAnchorCount( _reality) || BGRealityLeaseOf( _reality, entity) > _time.ms ||
       ! standing( self, entity, &tile))
      return( BGDetailFull);
   return( BGRealityDetailAt( _reality, tile.x, tile.y, tile.level));
}


- (void) leaseContactsFrom:(NSUInteger) first
{
   const BGEvent   *ev;
   BGEntityID      party[ 3];
   int             detail[ 3];
   int64_t         until;
   NSUInteger      i;
   int             k;
   int             j;

   if( ! BGRealityAnchorCount( _reality))
      return;
   until = _time.ms + BGRealityContactLease( _reality);
   for( i = first; i < _nevents; i++)
   {
      ev = &_events[ i];
      if( ! BGRealityIsContact( _reality, ev->kind))
         continue;
      party[ 0] = ev->actor;
      party[ 1] = ev->subject;
      party[ 2] = ev->other;
      for( k = 0; k < 3; k++)
         detail[ k] = party[ k] ? [self detailOf:party[ k]] : BGDetailFrozen;
      /* one at full detail: the others, raised */
      for( k = 0; k < 3; k++)
         if( party[ k] && detail[ k] == BGDetailFull)
            for( j = 0; j < 3; j++)
               if( party[ j] && detail[ j] != BGDetailFull)
                  BGRealityLease( _reality, party[ j], until);
   }
}


- (void) setActivityObserver:(id <BGRecordObserver>) observer
{
   _activityObserver = observer;
}


- (id <BGRecordObserver>) activityObserver
{
   return( _activityObserver);
}


- (BGLocation *) takeVacated:(NSUInteger *) n
{
   BGLocation   *list;

   list        = _vacated ? _vacated : calloc( 1, sizeof( BGLocation));
   *n          = _nvacated;
   _vacated    = NULL;
   _nvacated   = 0;
   _vacatedcap = 0;
   return( list);
}


- (BGEntityID *) takeTouched:(NSUInteger *) n
{
   BGEntityID   *list;
   NSUInteger   i;
   NSUInteger   k;

   list = _touched;
   qsort( list, _ntouched, sizeof( BGEntityID), cmp_id);
   for( k = 0, i = 0; i < _ntouched; i++)
      if( ! k || list[ k - 1] != list[ i])
         list[ k++] = list[ i];
   *n          = k;
   _touched    = NULL;
   _ntouched   = 0;
   _touchedcap = 0;
   return( list ? list : calloc( 1, sizeof( BGEntityID)));
}


- (NSUInteger) entitiesAt:(BGEntityID) place
                     form:(BGLocationForm) form
                     into:(BGEntityID *) out
                      max:(NSUInteger) max
{
   const BGEntityID   *ids;
   BGLocation         *loc;
   NSUInteger         count;
   NSUInteger         i;
   NSUInteger         n;

   ids = BGIndexGet( _inPlace, place, &count);
   n   = 0;
   for( i = 0; i < count; i++)
   {
      loc = [_locations recordFor:ids[ i]];
      if( ! loc || loc->form != form || loc->place != place)
         continue;
      if( n < max)
         out[ n] = ids[ i];
      n++;
   }
   return( n);
}


- (NSUInteger) thingsNear:(BGLocation) tile
                   radius:(int32_t) radius
                     into:(BGEntityID **) out
{
   BGEntityID   *list;
   NSUInteger   n;
   NSUInteger   cap;
   NSUInteger   i;
   NSUInteger   m;

   n    = [self entitiesNear:tile radius:radius into:NULL max:0];
   cap  = n + 16;
   list = malloc( cap * sizeof( BGEntityID));
   n    = [self entitiesNear:tile radius:radius into:list max:cap];
   for( i = 0; i < n; i++)
   {
      m = [self entitiesIn:list[ i] into:NULL max:0];
      if( n + m > cap)
      {
         cap  = (n + m) * 2;
         list = realloc( list, cap * sizeof( BGEntityID));
      }
      n += [self entitiesIn:list[ i] into:&list[ n] max:m];
   }
   *out = list;
   return( n);
}


- (NSUInteger) tracesNear:(BGLocation) tile
                   radius:(int32_t) radius
                     into:(BGEntityID **) out
{
   const BGEntityID   *ids;
   const BGTrace      *trace;
   BGEntityID         *things;
   BGEntityID         *list;
   NSUInteger         nthings;
   NSUInteger         count;
   NSUInteger         cap;
   NSUInteger         n;
   NSUInteger         i;
   NSUInteger         k;
   int32_t            cx;
   int32_t            cy;

   cap  = 64;
   list = malloc( cap * sizeof( BGEntityID));
   n    = 0;
   if( tile.form == BGLocationOnTile && radius >= 0 && _kindTrace < _nkinds)
   {
      for( cy = (tile.y - radius) >> 5; cy <= (tile.y + radius) >> 5; cy++)
         for( cx = (tile.x - radius) >> 5; cx <= (tile.x + radius) >> 5; cx++)
         {
            ids = BGIndexGet( _tracesOnGround, ground_key( cx * BG_CHUNK, cy * BG_CHUNK, tile.level), &count);
            for( i = 0; i < count; i++)
            {
               trace = [_kinds[ _kindTrace] recordFor:ids[ i]];
               if( ! trace || trace->bearer || trace->tileLevel != tile.level ||
                   llabs( trace->tileX - tile.x) > radius || llabs( trace->tileY - tile.y) > radius)
                  continue;
               if( n == cap)
                  list = realloc( list, (cap *= 2) * sizeof( BGEntityID));
               list[ n++] = ids[ i];
            }
         }
      nthings = [self thingsNear:tile radius:radius into:&things];
      for( k = 0; k < nthings; k++)
      {
         ids = BGIndexGet( _tracesBorne, things[ k], &count);
         for( i = 0; i < count; i++)
         {
            if( n == cap)
               list = realloc( list, (cap *= 2) * sizeof( BGEntityID));
            list[ n++] = ids[ i];
         }
      }
      free( things);
   }
   qsort( list, n, sizeof( BGEntityID), cmp_id);
   *out = list;
   return( n);
}


static NSUInteger   index_list( struct BGIndex *index, uint64_t key, BGEntityID *out, NSUInteger max)
{
   const BGEntityID   *ids;
   NSUInteger         count;
   NSUInteger         i;

   ids = BGIndexGet( index, key, &count);
   for( i = 0; i < count && i < max; i++)
      out[ i] = ids[ i];
   return( count);
}


- (NSUInteger) activitiesOf:(BGEntityID) actor
                       into:(BGEntityID *) out
                        max:(NSUInteger) max
{
   return( index_list( _activitiesOf, actor, out, max));
}


- (NSUInteger) watchingActivities:(BGEntityID *) out
                              max:(NSUInteger) max
{
   return( index_list( _watching, 0, out, max));
}


static BGEntityID   *index_copy( struct BGIndex *index, uint64_t key, NSUInteger *n)
{
   BGEntityID   *list;

   *n   = index_list( index, key, NULL, 0);
   list = malloc( (*n ? *n : 1) * sizeof( BGEntityID));
   index_list( index, key, list, *n);
   return( list);
}


- (BGEntityID *) copyActivitiesOf:(BGEntityID) actor
                            count:(NSUInteger *) n
{
   return( index_copy( _activitiesOf, actor, n));
}


- (BGEntityID *) copyActivitiesTouching:(BGEntityID) entity
                                  count:(NSUInteger *) n
{
   return( index_copy( _touching, entity, n));
}


- (BGEntityID *) copyWatchingActivities:(NSUInteger *) n
{
   return( index_copy( _watching, 0, n));
}


- (NSUInteger) entitiesIn:(BGEntityID) place
                     into:(BGEntityID *) out
                      max:(NSUInteger) max
{
   const BGEntityID   *ids;
   NSUInteger         count;
   NSUInteger         i;

   ids = BGIndexGet( _inPlace, place, &count);
   for( i = 0; i < count && i < max; i++)
      out[ i] = ids[ i];
   return( count);
}


- (NSUInteger) entitiesOnTile:(BGLocation) tile
                         into:(BGEntityID *) out
                          max:(NSUInteger) max
{
   return( [self entitiesNear:tile
                       radius:0
                         into:out
                          max:max]);
}


- (NSUInteger) entitiesNear:(BGLocation) tile
                     radius:(int32_t) radius
                       into:(BGEntityID *) out
                        max:(NSUInteger) max
{
   const BGEntityID   *ids;
   BGLocation         *loc;
   NSUInteger         count;
   NSUInteger         i;
   NSUInteger         n;
   int32_t            cx;
   int32_t            cy;
   BOOL               sorted;

   if( tile.form != BGLocationOnTile || radius < 0)
      return( 0);
   n      = 0;
   sorted = YES;
   for( cy = (tile.y - radius) >> 5; cy <= (tile.y + radius) >> 5; cy++)
      for( cx = (tile.x - radius) >> 5; cx <= (tile.x + radius) >> 5; cx++)
      {
         ids = BGIndexGet( _onGround, ground_key( cx * BG_CHUNK, cy * BG_CHUNK, tile.level), &count);
         for( i = 0; i < count; i++)
         {
            loc = [_locations recordFor:ids[ i]];
            if( ! loc || loc->form != BGLocationOnTile || loc->level != tile.level ||
                abs( loc->x - tile.x) > radius || abs( loc->y - tile.y) > radius)
               continue;
            if( n < max)
            {
               if( n && out[ n - 1] > ids[ i])
                  sorted = NO;
               out[ n] = ids[ i];
            }
            n++;
         }
      }
   if( ! sorted)
      qsort( out, n < max ? n : max, sizeof( BGEntityID), cmp_id);
   return( n);
}


- (BGStore *) locations
{
   return( _locations);
}


/* --- edges ----------------------------------------------------------------- */

static int   cmp_edge( BGEdge a, BGEdge b)
{
   if( a.kind != b.kind)
      return( a.kind < b.kind ? -1 : 1);
   if( a.from != b.from)
      return( a.from < b.from ? -1 : 1);
   if( a.to != b.to)
      return( a.to < b.to ? -1 : 1);
   return( 0);
}


static NSUInteger   edge_position( BGWorld *self, BGEdge e, BOOL *found)
{
   NSUInteger   hi;
   NSUInteger   lo;
   NSUInteger   mid;

   lo = 0;
   hi = self->_nedges;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      if( cmp_edge( self->_edges[ mid], e) < 0)
         lo = mid + 1;
      else
         hi = mid;
   }
   *found = lo < self->_nedges && ! cmp_edge( self->_edges[ lo], e);
   return( lo);
}


static void   edge_insert_raw( BGWorld *self, BGEdge e)
{
   BOOL         found;
   NSUInteger   i;

   i = edge_position( self, e, &found);
   if( found)
      return;
   if( self->_nedges == self->_edgeCapacity)
   {
      self->_edgeCapacity = self->_edgeCapacity ? self->_edgeCapacity * 2 : 16;
      self->_edges        = realloc( self->_edges, sizeof( BGEdge) * self->_edgeCapacity);
   }
   memmove( &self->_edges[ i + 1], &self->_edges[ i], sizeof( BGEdge) * (self->_nedges - i));
   self->_edges[ i] = e;
   self->_nedges++;
}


static void   edge_remove_raw( BGWorld *self, BGEdge e)
{
   BOOL         found;
   NSUInteger   i;

   i = edge_position( self, e, &found);
   if( ! found)
      return;
   memmove( &self->_edges[ i], &self->_edges[ i + 1], sizeof( BGEdge) * (self->_nedges - i - 1));
   self->_nedges--;
}


- (BOOL) hasEdge:(BGEdgeKind) kind
            from:(BGEntityID) from
              to:(BGEntityID) to
{
   BGEdge   e;
   BOOL     found;

   e.kind = kind;
   e.from = from;
   e.to   = to;
   edge_position( self, e, &found);
   return( found);
}


- (void) addEdge:(BGEdgeKind) kind
            from:(BGEntityID) from
              to:(BGEntityID) to
{
   BGEdge           e;
   BGJournalEntry   *j;

   if( [self hasEdge:kind
                from:from
                  to:to])
      return;
   e.kind = kind;
   e.from = from;
   e.to   = to;
   if( _open)
   {
      j       = journal_push( self);
      j->op   = BGJournalEdgeAdd;
      j->edge = e;
   }
   edge_insert_raw( self, e);
}


- (void) removeEdge:(BGEdgeKind) kind
               from:(BGEntityID) from
                 to:(BGEntityID) to
{
   BGEdge           e;
   BGJournalEntry   *j;

   if( ! [self hasEdge:kind
                  from:from
                    to:to])
      return;
   e.kind = kind;
   e.from = from;
   e.to   = to;
   if( _open)
   {
      j       = journal_push( self);
      j->op   = BGJournalEdgeRemove;
      j->edge = e;
   }
   edge_remove_raw( self, e);
}


- (NSUInteger) edges:(BGEdgeKind) kind
                from:(BGEntityID) from
                into:(BGEntityID *) out
                 max:(NSUInteger) max
{
   NSUInteger   i;
   NSUInteger   n;

   n = 0;
   for( i = 0; i < _nedges; i++)
      if( _edges[ i].kind == kind && _edges[ i].from == from)
      {
         if( n < max)
            out[ n] = _edges[ i].to;
         n++;
      }
   return( n);
}


- (NSUInteger) edges:(BGEdgeKind) kind
                  to:(BGEntityID) to
                into:(BGEntityID *) out
                 max:(NSUInteger) max
{
   NSUInteger   i;
   NSUInteger   n;

   n = 0;
   for( i = 0; i < _nedges; i++)
      if( _edges[ i].kind == kind && _edges[ i].to == to)
      {
         if( n < max)
            out[ n] = _edges[ i].from;
         n++;
      }
   return( n);
}


/* --- tiles ----------------------------------------------------------------- */

/* --- terrain --------------------------------------------------------------- */

- (BGTerrain *) terrain
{
   return( _terrain);
}


- (int32_t) tilesWide  { return( _tilesWide); }
- (int32_t) tilesHigh  { return( _tilesHigh); }
- (int32_t) levels     { return( _levels); }


- (BOOL) setTerrainMap:(const char *) map
                 error:(NSString **) error
{
   BGTerrain    *t;
   char         why[ 256];

   if( stocks_any( _stocks))
   {
      if( error)
         *error = @"a map is drawn before any tile holds a stock";
      return( NO);
   }
   if( ! (t = BGTerrainFromMap( [_content content], map, why, sizeof( why))))
   {
      if( error)
         *error = [NSString stringWithUTF8String:why];
      return( NO);
   }
   BGTerrainFree( _terrain);
   _terrain      = t;
   _roomAirKnown = NO;
   _tilesWide    = BGTerrainWide( t);
   _tilesHigh = BGTerrainHigh( t);
   _levels    = BGTerrainLevels( t);
   return( YES);
}


- (BGEntityID) airRegionAt:(BGLocation) tile
{
   if( (tile.form != BGLocationOnTile && tile.form != BGLocationNone) || ! _terrain)
      return( BGNoEntity);
   return( [self airOfRoom:BGTerrainRoomAt( _terrain, tile.x, tile.y, tile.level)]);
}


/* Each room's air, kept while no region of air has come or gone or had its
 * tile set, and no room was let go: its stocks change every step, and
 * leave it be. A region's room is found again, and any other has none. */
- (BGEntityID) airOfRoom:(uint32_t) room
{
   const BGGasStore   *gas;
   BGStore            *stores;
   NSUInteger         i;
   uint32_t           r;

   if( ! room || ! _terrain)
      return( BGNoEntity);
   stores = [self storeForKind:[self kindNamed:"GasStore"]];
   if( ! _roomAirKnown || _roomAirChanges != [stores members] + _airAnchors ||
       _roomAirDropped != BGTerrainRoomsDropped( _terrain))
   {
      memset( _roomAir, 0, _nroomAir * sizeof( BGEntityID));
      for( i = 0; i < [stores count]; i++)
      {
         gas = [stores recordAtIndex:i];
         if( ! (r = BGTerrainRoomAt( _terrain, (int32_t) gas->atX, (int32_t) gas->atY, (int32_t) gas->atLevel)))
            continue;
         if( r > _nroomAir)
         {
            _roomAir = realloc( _roomAir, r * sizeof( BGEntityID));
            memset( &_roomAir[ _nroomAir], 0, (r - _nroomAir) * sizeof( BGEntityID));
            _nroomAir = r;
         }
         if( ! _roomAir[ r - 1])
            _roomAir[ r - 1] = [stores entityAtIndex:i];
      }
      _roomAirChanges = [stores members] + _airAnchors;
      _roomAirDropped = BGTerrainRoomsDropped( _terrain);
      _roomAirKnown   = YES;
   }
   return( room <= _nroomAir ? _roomAir[ room - 1] : BGNoEntity);
}


- (uint32_t) roomOfAir:(BGEntityID) region
{
   const BGGasStore   *gas;

   gas = [self record:[self kindNamed:"GasStore"] for:region];
   if( ! gas || ! _terrain)
      return( 0);
   return( BGTerrainRoomAt( _terrain, (int32_t) gas->atX, (int32_t) gas->atY, (int32_t) gas->atLevel));
}


/* The door standing on a tile, or none. */
- (BGEntityID) doorOnTile:(BGLocation) tile
{
   BGEntityID   here[ 32];
   NSUInteger   n;
   NSUInteger   i;

   n = [self entitiesOnTile:tile
                       into:here
                        max:32];
   for( i = 0; i < n && i < 32; i++)
      if( [self record:[self kindNamed:"Door"] for:here[ i]])
         return( here[ i]);
   return( BGNoEntity);
}


- (NSUInteger) airOpeningsOf:(BGEntityID) region
                        into:(BGAirOpening *) out
                         max:(NSUInteger) max
{
   static const int      dx[ 4] = { 1, -1, 0, 0 };
   static const int      dy[ 4] = { 0, 0, 1, -1 };
   const BGTerrainInfo   *kind;
   const BGDoor          *door;
   BGAirOpening          o;
   int32_t               (*cells)[ 3];
   NSUInteger            ndoors;
   NSUInteger            i;
   NSUInteger            j;
   NSUInteger            n;
   NSUInteger            first;
   uint32_t              room;
   uint32_t              side;
   int32_t               u;
   int32_t               v;
   int                   d;

   if( ! (room = [self roomOfAir:region]))
      return( 0);
   ndoors = BGTerrainRoomDoorways( _terrain, room, NULL, 0);
   cells  = malloc( (ndoors ? ndoors : 1) * sizeof( *cells));
   BGTerrainRoomDoorways( _terrain, room, cells, ndoors);
   n = 0;
   for( i = 0; i < ndoors; i++)
   {
      memset( &o, 0, sizeof( o));
      o.at   = BGOnTile( cells[ i][ 0], cells[ i][ 1], cells[ i][ 2]);
      o.door = [self doorOnTile:o.at];
      kind   = BGTerrainKindInfo( _terrain, BGTerrainAt( _terrain, o.at.x, o.at.y, o.at.level));
      door   = o.door ? [self record:[self kindNamed:"Door"] for:o.door] : NULL;
      o.open = ! door || door->ajar;
      o.flow = door ? (door->ajar ? door->wide : 0) : (kind ? kind->draught : 0);
      first  = n;
      for( d = 0; d < 4; d++)
      {
         u = o.at.x + dx[ d];
         v = o.at.y + dy[ d];
         if( u >= 0 && v >= 0 && u < _tilesWide && v < _tilesHigh && ! BGTerrainRoomy( _terrain, u, v, o.at.level))
            continue;
         if( (side = BGTerrainRoomAt( _terrain, u, v, o.at.level)) == room)
            continue;
         o.beyond = [self airOfRoom:side];
         for( j = first; j < n && j < max && out[ j].beyond != o.beyond; j++)
            ;
         if( j < n && j < max)
            continue;
         if( n < max)
            out[ n] = o;
         n++;
      }
   }
   free( cells);
   return( n);
}


- (BOOL) airIsShutIn:(BGEntityID) region
{
   BGAirOpening   *openings;
   NSUInteger     n;
   NSUInteger     i;
   BOOL           shut;

   n        = [self airOpeningsOf:region into:NULL max:0];
   openings = malloc( (n ? n : 1) * sizeof( BGAirOpening));
   [self airOpeningsOf:region into:openings max:n];
   for( shut = YES, i = 0; i < n && shut; i++)
      shut = ! openings[ i].open;
   free( openings);
   return( shut);
}


- (BOOL) airRegion:(BGEntityID) a
      opensOpenTo:(BGEntityID) b
{
   BGAirOpening   *openings;
   BGEntityID     from;
   BGEntityID     to;
   NSUInteger     n;
   NSUInteger     i;
   BOOL           open;

   from     = a ? a : b;
   to       = a ? b : a;
   n        = [self airOpeningsOf:from into:NULL max:0];
   openings = malloc( (n ? n : 1) * sizeof( BGAirOpening));
   [self airOpeningsOf:from into:openings max:n];
   for( open = NO, i = 0; i < n && ! open; i++)
      open = openings[ i].beyond == to && openings[ i].open;
   free( openings);
   return( open);
}


- (BOOL) setTerrain:(const char *) kind
                atX:(int32_t) x
                  y:(int32_t) y
              level:(int32_t) level
{
   BGJournalEntry   *j;
   BGTerrainKind    k;
   BGTerrainKind    was;

   if( ! _terrain || ! (k = BGTerrainKindNamed( _terrain, kind)) || ! [self isTileX:x y:y level:level])
      return( NO);
   was = BGTerrainSet( _terrain, x, y, level, k);
   if( _open && was != k)
   {
      j        = journal_push( self);
      j->op    = BGJournalTerrain;
      j->value = was;
      j->tile  = BGOnTile( x, y, level);
   }
   return( YES);
}


- (BOOL) isTileX:(int32_t) x
               y:(int32_t) y
           level:(int32_t) level
{
   return( x >= 0 && x < _tilesWide && y >= 0 && y < _tilesHigh && level >= 0 && level < _levels);
}


- (int64_t) waterAtX:(int32_t) x
                   y:(int32_t) y
               level:(int32_t) level
{
   if( ! [self isTileX:x y:y level:level])
      return( 0);
   return( stocks_cell( _stocks, x, y, level, NO) ? *stocks_cell( _stocks, x, y, level, NO) : 0);
}


- (void) setWater:(int64_t) water
              atX:(int32_t) x
                y:(int32_t) y
            level:(int32_t) level
{
   int64_t   *cell;

   if( [self isTileX:x y:y level:level] && (cell = stocks_cell( _stocks, x, y, level, water != 0)))
      *cell = water;
}


- (int64_t) totalTileWater
{
   return( stocks_total( _stocks));
}


- (BOOL) isTileCheckedOutX:(int32_t) x
                         y:(int32_t) y
                     level:(int32_t) level
{
   if( ! [self isTileX:x y:y level:level])
      return( NO);
   uint8_t   *out;

   out = stocks_out( _stocks, x, y, level, NO);
   return( out && *out);
}


- (void) setTileCheckedOut:(BOOL) flag
                         x:(int32_t) x
                         y:(int32_t) y
                     level:(int32_t) level
{
   uint8_t   *out;

   if( [self isTileX:x y:y level:level] && (out = stocks_out( _stocks, x, y, level, flag)))
      *out = flag ? 1 : 0;
}


- (NSUInteger) wetTiles:(int32_t (*)[ 3]) out
                    max:(NSUInteger) max
{
   return( stocks_wet( _stocks, out, max));
}


/* --- checkout -------------------------------------------------------------- */

- (BOOL) isCheckedOut:(BGEntityID) entity
{
   NSUInteger   i;

   for( i = 0; i < _ncheckedOut; i++)
      if( _checkedOut[ i] == entity)
         return( YES);
   return( NO);
}


- (void) setCheckedOut:(BOOL) flag
                   for:(BGEntityID) entity
{
   NSUInteger   i;

   for( i = 0; i < _ncheckedOut && _checkedOut[ i] < entity; i++)
      ;
   if( flag)
   {
      if( i < _ncheckedOut && _checkedOut[ i] == entity)
         return;
      _checkedOut = realloc( _checkedOut, sizeof( BGEntityID) * (_ncheckedOut + 1));
      memmove( &_checkedOut[ i + 1], &_checkedOut[ i], sizeof( BGEntityID) * (_ncheckedOut - i));
      _checkedOut[ i] = entity;
      _ncheckedOut++;
      return;
   }
   if( i < _ncheckedOut && _checkedOut[ i] == entity)
   {
      memmove( &_checkedOut[ i], &_checkedOut[ i + 1], sizeof( BGEntityID) * (_ncheckedOut - i - 1));
      _ncheckedOut--;
   }
}


/* --- claims ---------------------------------------------------------------- */

- (int64_t) claimedUnitsOf:(BGEntityID) entity
{
   const BGClaim   *claim;
   BGEntityID      claims[ 64];
   NSUInteger      i;
   NSUInteger      n;
   int64_t         sum;

   n   = [self edges:BGEdgeClaimSubject
                  to:entity
                into:claims
                 max:64];
   sum = 0;
   for( i = 0; i < n && i < 64; i++)
   {
      claim = [self record:[self kindNamed:"Claim"] for:claims[ i]];
      if( claim)
         sum += claim->quantity;
   }
   return( sum);
}


- (BOOL) claimAllocationResolved:(BGEntityID) claim
{
   const BGClaim   *record;
   BGEntityID      others[ 64];
   BGEntityID      subjects[ 64];
   NSUInteger      i;
   NSUInteger      j;
   NSUInteger      n;
   NSUInteger      m;
   int64_t         units;

   record = [self record:[self kindNamed:"Claim"] for:claim];
   if( ! record)
      return( NO);
   n = [self edges:BGEdgeClaimSubject
              from:claim
              into:subjects
               max:64];
   if( n <= 1)
      return( YES);
   units = 0;
   for( i = 0; i < n && i < 64; i++)
   {
      m = [self edges:BGEdgeClaimSubject
                   to:subjects[ i]
                 into:others
                  max:64];
      for( j = 0; j < m && j < 64; j++)
         if( others[ j] != claim)
            return( NO);
      units += [self unitsOf:subjects[ i]];
   }
   return( units == record->quantity);
}


/* --- history --------------------------------------------------------------- */

- (uint64_t) emit:(BGEvent) event
{
   BGJournalEntry   *j;

   if( _open)
   {
      j        = journal_push( self);
      j->op    = BGJournalEvents;
      j->value = _nevents;
   }
   if( _nevents == _eventCapacity)
   {
      _eventCapacity = _eventCapacity ? _eventCapacity * 2 : 64;
      _events        = realloc( _events, sizeof( BGEvent) * _eventCapacity);
   }
   event.index        = _nevents + 1;
   _events[ _nevents] = event;
   _nevents++;
   if( event.subject && event.kind && ! strcmp( event.kind, "created"))
      BGIndexAdd( _creations, event.subject, (BGEntityID) event.index);
   return( event.index);
}


- (uint64_t) creationOf:(BGEntityID) entity
{
   const BGEntityID   *known;
   const BGEvent      *ev;
   NSUInteger         n;
   NSUInteger         i;

   /* the latest noted that is still so (a group rolled back takes its
    * events with it, and later ones take their places) */
   known = BGIndexGet( _creations, entity, &n);
   for( i = n; i-- > 0;)
   {
      ev = [self eventAt:(NSUInteger) known[ i] - 1];
      if( ev && ev->subject == entity && ! strcmp( ev->kind, "created"))
         return( ev->index);
   }
   /* not noted (a save restored): read the history, once, and note it */
   for( i = _nevents; i-- > 0;)
      if( _events[ i].subject == entity && ! strcmp( _events[ i].kind, "created"))
      {
         BGIndexAdd( _creations, entity, (BGEntityID) _events[ i].index);
         return( _events[ i].index);
      }
   return( 0);
}


- (NSUInteger) eventCount
{
   return( _nevents);
}


- (const BGEvent *) eventAt:(NSUInteger) i
{
   return( i < _nevents ? &_events[ i] : NULL);
}


/* --- the rest -------------------------------------------------------------- */

- (const char *) intern:(const char *) string
{
   NSUInteger   hi;
   NSUInteger   lo;
   NSUInteger   mid;
   int          r;

   lo = 0;
   hi = _nstrings;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      r   = strcmp( _strings[ mid], string);
      if( ! r)
         return( _strings[ mid]);
      if( r < 0)
         lo = mid + 1;
      else
         hi = mid;
   }
   if( _nstrings == _stringCapacity)
   {
      _stringCapacity = _stringCapacity ? _stringCapacity * 2 : 32;
      _strings        = realloc( _strings, sizeof( char *) * _stringCapacity);
   }
   memmove( &_strings[ lo + 1], &_strings[ lo], sizeof( char *) * (_nstrings - lo));
   _strings[ lo] = strdup( string);
   _nstrings++;
   return( _strings[ lo]);
}


static uint64_t   hash_record( uint64_t h, const BGComponentInfo *info, const void *record)
{
   const BGFieldInfo   *f;
   const char          *text;
   size_t              i;

   for( i = 0; i < info->nfields; i++)
   {
      f = &info->fields[ i];
      if( f->value == BG_VALUE_TEXT)
      {
         text = *(const char *const *) ((const uint8_t *) record + f->offset);
         h    = BGMixString( h, text ? text : "");
      }
      else
         h = BGMix( h ^ (uint64_t) field_get( f, record));
   }
   return( h);
}


- (uint64_t) stateHash
{
   const BGEntityInfo   *info;
   const BGLocation     *loc;
   const BGTombstone    *stone;
   const BGEvent        *ev;
   uint64_t             h;
   NSUInteger           i;
   NSUInteger           k;

   h = BGMix( _seed ^ _nextID);
   for( i = 0; i < [_entities count]; i++)
   {
      info = [_entities recordAtIndex:i];
      h    = BGMix( h ^ [_entities entityAtIndex:i]);
      h    = BGMixString( h, info->blueprint);
      h    = BGMix( h ^ info->seed);
   }
   for( k = 0; k < _nkinds; k++)
   {
      h = BGMix( h ^ k);
      for( i = 0; i < [_kinds[ k] count]; i++)
      {
         h = BGMix( h ^ [_kinds[ k] entityAtIndex:i]);
         h = hash_record( h, &BGComponents[ k], [_kinds[ k] recordAtIndex:i]);
      }
   }
   for( i = 0; i < [_locations count]; i++)
   {
      loc = [_locations recordAtIndex:i];
      h   = BGMix( h ^ [_locations entityAtIndex:i]);
      h   = BGMix( h ^ (uint64_t) loc->form ^ (loc->place << 4));
      h   = BGMix( h ^ (uint64_t) (uint32_t) loc->x ^ ((uint64_t) (uint32_t) loc->y << 32));
      h   = BGMix( h ^ (uint64_t) (uint32_t) loc->level ^ ((uint64_t) (uint32_t) loc->slot << 32));
      h   = BGMixString( h, loc->role);
   }
   for( i = 0; i < [_tombstones count]; i++)
   {
      stone = [_tombstones recordAtIndex:i];
      h     = BGMix( h ^ [_tombstones entityAtIndex:i]);
      h     = BGMixString( h, stone->blueprint);
      h     = BGMix( h ^ stone->successor ^ (stone->cause << 20));
      h     = BGMixString( h, stone->reason);
   }
   for( i = 0; i < _nedges; i++)
      h = BGMix( h ^ (uint64_t) _edges[ i].kind ^ (_edges[ i].from << 8) ^ (_edges[ i].to << 36));
   {
      int32_t      (*wet)[ 3];
      NSUInteger   nwet;
      NSUInteger   w;
      uint64_t     cell;

      nwet = stocks_wet( _stocks, NULL, 0);
      wet  = malloc( (nwet ? nwet : 1) * sizeof( *wet));
      stocks_wet( _stocks, wet, nwet);
      for( w = 0; w < nwet; w++)
      {
         cell = ((uint64_t) wet[ w][ 2] * (uint64_t) _tilesHigh + (uint64_t) wet[ w][ 1]) * (uint64_t) _tilesWide +
                (uint64_t) wet[ w][ 0];
         h = BGMix( h ^ cell ^ ((uint64_t) [self waterAtX:wet[ w][ 0] y:wet[ w][ 1] level:wet[ w][ 2]] << 20));
      }
      free( wet);
   }
   if( _terrain)
      h = BGMix( h ^ BGTerrainHash( _terrain));
   h = BGRealityHash( _reality, h);
   for( i = 0; i < _nevents; i++)
   {
      ev = &_events[ i];
      h  = BGMixString( h, ev->kind);
      h  = BGMixString( h, ev->detail ? ev->detail : "");
      h  = BGMix( h ^ ev->subject ^ (ev->other << 24) ^ ((uint64_t) ev->amount << 48));
      h  = BGMix( h ^ ev->cause ^ (ev->group << 32) ^ ev->boundary);
      h  = BGMix( h ^ ev->actor);
   }
   return( h);
}


- (NSString *) describeEntity:(BGEntityID) entity
{
   const BGFieldInfo    *f;
   const BGEntityInfo   *info;
   const BGTombstone    *stone;
   const uint8_t        *record;
   const char           *text;
   NSMutableString      *s;
   char                 buf[ 128];
   size_t               i;
   NSUInteger           k;

   info = [self info:entity];
   if( ! info)
   {
      stone = [self tombstone:entity];
      if( ! stone)
         return( [NSString stringWithFormat:@"%llu: unknown", (unsigned long long) entity]);
      return( [NSString stringWithFormat:@"%llu: tombstone of %s, %s, successor %llu",
                                         (unsigned long long) entity, stone->blueprint, stone->reason,
                                         (unsigned long long) stone->successor]);
   }
   s = [NSMutableString stringWithFormat:@"%llu %s:", (unsigned long long) entity, info->blueprint];
   for( k = 0; k < _nkinds; k++)
   {
      record = [_kinds[ k] recordFor:entity];
      if( ! record)
         continue;
      for( i = 0; i < BGComponents[ k].nfields; i++)
      {
         f = &BGComponents[ k].fields[ i];
         switch( f->value)
         {
         case BG_VALUE_QUANTITY:
            tri_format_quantity( f->kind, field_get( f, record), buf, sizeof( buf));
            break;
         case BG_VALUE_TYPE:
            snprintf( buf, sizeof( buf), "%s", tri_type_name( [self tri], (TriType) field_get( f, record)));
            break;
         case BG_VALUE_BOOL:
            snprintf( buf, sizeof( buf), "%s", field_get( f, record) ? "true" : "false");
            break;
         case BG_VALUE_REF:
            snprintf( buf, sizeof( buf), "ref(%lld)", (long long) field_get( f, record));
            break;
         case BG_VALUE_TEXT:
            text = *(const char *const *) (record + f->offset);
            snprintf( buf, sizeof( buf), "\"%s\"", text ? text : "");
            break;
         default:
            snprintf( buf, sizeof( buf), "_");
            break;
         }
         [s appendFormat:@" %s.%s=%s", BGComponents[ k].name, f->name, buf];
      }
   }
   BGLocationFormat( [self locationOf:entity], buf, sizeof( buf));
   [s appendFormat:@" at %s", buf];
   return( s);
}

@end
