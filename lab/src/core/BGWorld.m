#define BG_COMPONENT_REGISTRY
#import "BGWorld.h"

#include <stdio.h>
#include <stdlib.h>


const char   *BGEdgeKindNames[ BGEdgeKindCount] =
{
   "splitFrom",
   "claimant",
   "claimSubject"
};


/* --- the journal ----------------------------------------------------------- */

typedef enum
{
   BGJournalRecord,
   BGJournalEdgeAdd,
   BGJournalEdgeRemove,
   BGJournalNextID,
   BGJournalEvents
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
   uint64_t      value;
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
   _entities   = [[BGStore alloc] initWithRecordSize:sizeof( BGEntityInfo)];
   _locations  = [[BGStore alloc] initWithRecordSize:sizeof( BGLocation)];
   _tombstones = [[BGStore alloc] initWithRecordSize:sizeof( BGTombstone)];
   _arena      = tri_arena_new();
   _tilesWide  = 32;
   _tilesHigh  = 32;
   _levels     = 1;
   _tileWater  = calloc( (size_t) (_tilesWide * _tilesHigh * _levels), sizeof( int64_t));
   _tileOut    = calloc( (size_t) (_tilesWide * _tilesHigh * _levels), 1);
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
   free( _tileWater);
   free( _tileOut);
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
         if( j->had)
            [j->store setRecord:j->old
                            for:j->entity];
         else
            [j->store removeRecordFor:j->entity];
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
   NSUInteger   k;

   for( k = 0; k < _nkinds; k++)
      if( ! strcmp( BGComponents[ k].name, name))
         return( k);
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


- (void) setRecord:(const void *) record
              kind:(NSUInteger) kind
               for:(BGEntityID) entity
{
   journal_record( self, _kinds[ kind], kind, entity);
   [_kinds[ kind] setRecord:record
                        for:entity];
}


- (void) removeRecord:(NSUInteger) kind
                  for:(BGEntityID) entity
{
   if( ! [_kinds[ kind] recordFor:entity])
      return;
   journal_record( self, _kinds[ kind], kind, entity);
   [_kinds[ kind] removeRecordFor:entity];
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


- (void) setLocation:(BGLocation) location
                  of:(BGEntityID) entity
{
   if( location.form == BGLocationNone && ! [_locations recordFor:entity])
      return;
   journal_record( self, _locations, BGKindLocations, entity);
   if( location.form == BGLocationNone)
      [_locations removeRecordFor:entity];
   else
      [_locations setRecord:&location
                        for:entity];
}


- (NSUInteger) entitiesAt:(BGEntityID) place
                     form:(BGLocationForm) form
                     into:(BGEntityID *) out
                      max:(NSUInteger) max
{
   BGLocation   *loc;
   NSUInteger   i;
   NSUInteger   n;

   n = 0;
   for( i = 0; i < [_locations count]; i++)
   {
      loc = [_locations recordAtIndex:i];
      if( loc->form != form || loc->place != place)
         continue;
      if( n < max)
         out[ n] = [_locations entityAtIndex:i];
      n++;
   }
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
   return( _tileWater[ (level * _tilesHigh + y) * _tilesWide + x]);
}


- (void) setWater:(int64_t) water
              atX:(int32_t) x
                y:(int32_t) y
            level:(int32_t) level
{
   if( [self isTileX:x y:y level:level])
      _tileWater[ (level * _tilesHigh + y) * _tilesWide + x] = water;
}


- (int64_t) totalTileWater
{
   int64_t   sum;
   int32_t   i;

   sum = 0;
   for( i = 0; i < _tilesWide * _tilesHigh * _levels; i++)
      if( ! _tileOut[ i])
         sum += _tileWater[ i];
   return( sum);
}


- (BOOL) isTileCheckedOutX:(int32_t) x
                         y:(int32_t) y
                     level:(int32_t) level
{
   if( ! [self isTileX:x y:y level:level])
      return( NO);
   return( _tileOut[ (level * _tilesHigh + y) * _tilesWide + x] != 0);
}


- (void) setTileCheckedOut:(BOOL) flag
                         x:(int32_t) x
                         y:(int32_t) y
                     level:(int32_t) level
{
   if( [self isTileX:x y:y level:level])
      _tileOut[ (level * _tilesHigh + y) * _tilesWide + x] = flag ? 1 : 0;
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
   return( event.index);
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
   for( i = 0; i < (NSUInteger) (_tilesWide * _tilesHigh * _levels); i++)
      if( _tileWater[ i])
         h = BGMix( h ^ (uint64_t) i ^ ((uint64_t) _tileWater[ i] << 20));
   for( i = 0; i < _nevents; i++)
   {
      ev = &_events[ i];
      h  = BGMixString( h, ev->kind);
      h  = BGMixString( h, ev->detail ? ev->detail : "");
      h  = BGMix( h ^ ev->subject ^ (ev->other << 24) ^ ((uint64_t) ev->amount << 48));
      h  = BGMix( h ^ ev->cause ^ (ev->group << 32) ^ ev->boundary);
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
