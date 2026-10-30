#import "BGCommitter.h"

#include <stdio.h>
#include <stdlib.h>


/* What a group declares it creates or destroys: the only changes to total
 * mass and to each unit's count that conservation allows. */
#define BG_MAX_UNITS   64

typedef struct
{
   const char   *unit;
   int64_t      before;
   int64_t      after;
   int64_t      declared;
} BGUnitTally;

typedef struct
{
   int64_t       mass;
   BGUnitTally   units[ BG_MAX_UNITS];
   NSUInteger    nunits;
} BGTally;

static BGUnitTally   *tally_unit( BGTally *t, const char *unit)
{
   NSUInteger   i;

   for( i = 0; i < t->nunits; i++)
      if( ! strcmp( t->units[ i].unit, unit))
         return( &t->units[ i]);
   if( t->nunits == BG_MAX_UNITS)
      return( NULL);
   memset( &t->units[ t->nunits], 0, sizeof( BGUnitTally));
   t->units[ t->nunits].unit = unit;
   return( &t->units[ t->nunits++]);
}


static void   declare( BGTally *t, const char *unit, int64_t units, int64_t mass)
{
   BGUnitTally   *u;

   t->mass += mass;
   u = unit ? tally_unit( t, unit) : NULL;
   if( u)
      u->declared += units;
}


@implementation BGCommitter

- (id) initWithWorld:(BGWorld *) world
{
   if( ! (self = [super init]))
      return( nil);
   _world     = [world retain];
   _submitted = [NSMutableArray new];
   _deferred  = [NSMutableArray new];
   _reactors  = [NSMutableArray new];
   _listeners = [NSMutableArray new];
   _sources   = [NSMutableDictionary new];
   _trace     = [NSMutableArray new];
   _rounds    = 4;
   return( self);
}


- (void) dealloc
{
   [_world release];
   [_submitted release];
   [_deferred release];
   [_reactors release];
   [_listeners release];
   [_sources release];
   [_trace release];
   [super dealloc];
}


- (BGWorld *) world
{
   return( _world);
}


- (void) setRounds:(NSUInteger) rounds
{
   _rounds = rounds;
}


- (void) addReactor:(id <BGReactor>) reactor
            forKind:(const char *) kind
{
   NSUInteger   k;

   k = [_world kindNamed:kind];
   if( k == NSNotFound)
      return;
   [_reactors addObject:[NSNumber numberWithUnsignedLongLong:k]];
   [_reactors addObject:reactor];
}


- (void) addListener:(id <BGRoundListener>) listener
{
   [_listeners addObject:listener];
}


- (void) submit:(BGProposalGroup *) group
{
   [_submitted addObject:group];
}


- (BOOL) hasPending
{
   return( [_submitted count] || [_deferred count]);
}


- (NSString *) sourceOfPosition:(uint64_t) position
{
   return( [_sources objectForKey:[NSNumber numberWithUnsignedLongLong:position]]);
}


- (uint64_t) position
{
   return( _position);
}


- (void) setPosition:(uint64_t) position
{
   _position = position;
}


- (NSArray *) deferredGroups
{
   return( [_deferred arrayByAddingObjectsFromArray:_submitted]);
}


- (void) restoreDeferred:(NSArray *) groups
{
   [_deferred removeAllObjects];
   [_deferred addObjectsFromArray:groups];
}


- (NSArray *) trace
{
   return( _trace);
}


- (void) note:(NSString *) line
{
   [_trace addObject:line];
}


/* --- ordering -------------------------------------------------------------- */

/* What weights a group in the permutation (ACTIONS.md §8): its actor's
 * quickness, a derived reaction speed; 10 for a group with no agent. */
- (uint64_t) orderWeightOf:(BGProposalGroup *) g
{
   int64_t   v;

   if( [g actor] && [_world getField:"Agent.quickness" of:[g actor] value:&v] && v > 0)
      return( (uint64_t) v);
   return( 10);
}


/* By phase, then a permutation seeded by the world seed, the boundary, and
 * the round: nobody wins by being older, lower in ID, or submitted first.
 * Weighted, when the groups' weights differ: drawn one at a time, each in
 * proportion to its weight, from the same seeded stream, in integers. */
- (NSArray *) order:(NSArray *) groups
{
   NSMutableArray   *ordered;
   NSMutableArray   *phase;
   BGProposalGroup  *g;
   NSUInteger       i;
   NSUInteger       j;
   NSUInteger       p;
   uint64_t         state;

   ordered = [NSMutableArray array];
   for( p = 0; p < BGPhaseCount; p++)
   {
      phase = [NSMutableArray array];
      for( i = 0; i < [groups count]; i++)
      {
         g = [groups objectAtIndex:i];
         if( [g phase] == (BGPhase) p)
            [phase addObject:g];
      }
      state = BGMix( [_world seed] ^ BGMix( [_world boundary] * 0x100 + _round) ^ (p << 56));
      for( i = 1; i < [phase count] && [self orderWeightOf:[phase objectAtIndex:i]] == [self orderWeightOf:[phase objectAtIndex:0]]; i++)
         ;
      if( i < [phase count])
      {
         /* weighted: successive sampling without replacement */
         while( [phase count])
         {
            uint64_t   total;
            uint64_t   r;

            for( total = 0, i = 0; i < [phase count]; i++)
               total += [self orderWeightOf:[phase objectAtIndex:i]];
            r = BGNext( &state) % total;
            for( i = 0; i + 1 < [phase count] && r >= [self orderWeightOf:[phase objectAtIndex:i]]; i++)
               r -= [self orderWeightOf:[phase objectAtIndex:i]];
            [ordered addObject:[phase objectAtIndex:i]];
            [phase removeObjectAtIndex:i];
         }
         continue;
      }
      for( i = [phase count]; i > 1; i--)
      {
         j = (NSUInteger) (BGNext( &state) % i);
         [phase exchangeObjectAtIndex:i - 1
                    withObjectAtIndex:j];
      }
      [ordered addObjectsFromArray:phase];
   }
   return( ordered);
}


/* --- automatic individuation ----------------------------------------------- */

typedef struct
{
   BGEntityID   entity;
   uint32_t     unit;
   BGEntityID   handle;      /* the split-off unit, or BGNoEntity for the whole entity */
} BGUnitPair;

static void   rewrite_ref( BGRef *r, BGUnitPair *pairs, NSUInteger n)
{
   NSUInteger   i;

   if( ! r->unit)
      return;
   for( i = 0; i < n; i++)
      if( pairs[ i].entity == r->entity && pairs[ i].unit == r->unit)
      {
         if( pairs[ i].handle)
            r->entity = pairs[ i].handle;
         r->unit = 0;
         return;
      }
}


/* Proposals that address one unit of a stack get that unit split off first,
 * whether or not the proposer asked: the group's copy is rewritten so that
 * every proposal naming {stack, n} names the split-off unit. */
- (BGProposal *) individuate:(BGProposalGroup *) group
                       count:(NSUInteger *) count
{
   const BGProposal   *in;
   BGProposal         *out;
   BGProposal         split;
   BGRef              *refs[ 2];
   BGUnitPair         *pairs;
   NSUInteger         i;
   NSUInteger         j;
   NSUInteger         k;
   NSUInteger         n;
   NSUInteger         npairs;
   NSUInteger         q;
   BOOL               found;

   in     = [group proposals];
   n      = [group count];
   out    = malloc( sizeof( BGProposal) * (3 * n + 1));
   pairs  = malloc( sizeof( BGUnitPair) * (2 * n + 1));
   npairs = 0;
   k      = 0;
   for( i = 0; i < n; i++)
   {
      BGRef   r[ 2];

      r[ 0] = in[ i].target;
      r[ 1] = in[ i].other;
      for( j = 0; j < 2; j++)
      {
         if( ! r[ j].unit)
            continue;
         found = NO;
         for( q = 0; q < npairs && ! found; q++)
            found = pairs[ q].entity == r[ j].entity && pairs[ q].unit == r[ j].unit;
         if( found)
            continue;
         pairs[ npairs].entity = r[ j].entity;
         pairs[ npairs].unit   = r[ j].unit;
         pairs[ npairs].handle = BGNoEntity;
         /* units of a stack this group creates can't be split off yet: the whole entity is meant */
         if( ! BGIsHandle( r[ j].entity) && [_world isStack:r[ j].entity] && [_world unitsOf:r[ j].entity] > 1)
         {
            memset( &split, 0, sizeof( split));
            split.kind            = BGProposeSplit;
            split.target          = BGWhole( r[ j].entity);
            split.value           = 1;
            split.handle          = [group newHandle];
            pairs[ npairs].handle = split.handle;
            out[ k++]             = split;
            [self note:[NSString stringWithFormat:@"    individuate: unit %u of %llu is split off first",
                                                  r[ j].unit, (unsigned long long) r[ j].entity]];
         }
         npairs++;
      }
   }
   for( i = 0; i < n; i++)
   {
      out[ k] = in[ i];
      refs[ 0] = &out[ k].target;
      refs[ 1] = &out[ k].other;
      rewrite_ref( refs[ 0], pairs, npairs);
      rewrite_ref( refs[ 1], pairs, npairs);
      k++;
   }
   free( pairs);
   *count = k;
   return( out);
}


/* --- applying proposals ---------------------------------------------------- */

static BGEntityID   resolve_ref( BGProposalGroup *g, BGRef r)
{
   return( [g idFor:r.entity]);
}


static BGLocation   resolve_location( BGProposalGroup *g, BGLocation loc)
{
   if( BGIsHandle( loc.place))
      loc.place = [g idFor:loc.place];
   return( loc);
}


- (uint64_t) emit:(const char *) kind
          subject:(BGEntityID) subject
            other:(BGEntityID) other
           amount:(int64_t) amount
           detail:(const char *) detail
         location:(BGLocation) location
            group:(BGProposalGroup *) group
{
   BGEvent   ev;

   memset( &ev, 0, sizeof( ev));
   ev.boundary = [_world boundary];
   ev.round    = _round;
   ev.kind     = kind;
   ev.subject  = subject;
   ev.other    = other;
   ev.amount   = amount;
   ev.detail   = detail ? [_world intern:detail] : NULL;
   ev.location = location;
   ev.cause    = [group cause];
   ev.actor    = [group actor];
   ev.group    = _position;
   return( [_world emit:ev]);
}


static NSString   *live_check( BGWorld *w, BGEntityID e, const char *role)
{
   if( e == BGNoEntity)
      return( [NSString stringWithFormat:@"the %s is not known", role]);
   if( [w tombstone:e])
      return( [NSString stringWithFormat:@"the %s %llu is a tombstone", role, (unsigned long long) e]);
   if( ! [w isLive:e])
      return( [NSString stringWithFormat:@"the %s %llu does not exist", role, (unsigned long long) e]);
   return( nil);
}


/* Why `a` cannot merge into `b`, or nil. */
- (NSString *) mergeObstacle:(BGEntityID) a
                        into:(BGEntityID) b
{
   const BGBody   *ba;
   const BGBody   *bb;
   const char     *ua;
   const char     *ub;
   BGEntityID     claims[ 8];
   BGEntityID     subjects[ 2];
   NSUInteger     body;
   NSUInteger     i;
   NSUInteger     n;

   if( a == b)
      return( @"an entity cannot merge into itself");
   if( ! [_world isPhysical:a] || ! [_world isPhysical:b])
      return( @"only physical units merge");
   if( ! [_world isStack:b])
      return( [NSString stringWithFormat:@"%llu is not a stack", (unsigned long long) b]);
   ua = [_world unitOf:a];
   ub = [_world unitOf:b];
   if( ! ua || ! ub || strcmp( ua, ub))
      return( [NSString stringWithFormat:@"different units (%s, %s)", ua ? ua : "?", ub ? ub : "?"]);
   body = [_world kindNamed:"Body"];
   ba   = [_world record:body for:a];
   bb   = [_world record:body for:b];
   if( ba->bent || bb->bent)
      return( @"units differ physically: one is bent");
   if( ba->toolMarks || bb->toolMarks)
      return( @"units differ physically: one has tool marks");
   if( ! BGLocationEqual( [_world locationOf:a], [_world locationOf:b]))
      return( @"they are not in the same place");
   /* a quantity claim over several entities follows the units; a claim on this one unit alone pins it */
   if( ! [_world isStack:a])
   {
      n = [_world edges:BGEdgeClaimSubject
                     to:a
                   into:claims
                    max:8];
      for( i = 0; i < n && i < 8; i++)
         if( [_world edges:BGEdgeClaimSubject
                      from:claims[ i]
                      into:subjects
                       max:2] == 1)
            return( @"a claim is on this unit alone");
   }
   return( nil);
}


- (NSString *) apply:(BGProposal *) p
               group:(BGProposalGroup *) g
               tally:(BGTally *) tally
{
   BGStack          stack;
   BGBody           body;
   BGStack          *sp;
   BGLocation       loc;
   BGEntityID       a;
   BGEntityID       b;
   BGEntityID       claims[ 64];
   BGEntityID       e;
   NSString         *reason;
   NSString         *error;
   NSUInteger       kbody;
   NSUInteger       kstack;
   NSUInteger       n;
   NSUInteger       i;
   uint64_t         ev;
   uint64_t         seed;
   const BGFieldInfo        *f;
   const BGEntityInfo       *info;
   NSUInteger               k;
   int64_t                  value;

   kbody  = [_world kindNamed:"Body"];
   kstack = [_world kindNamed:"Stack"];
   switch( p->kind)
   {
   case BGProposeCreate:
      e = [_world allocateID];
      [g setID:e
     forHandle:p->handle];
      seed = BGMixString( BGMix( [_world seed] ^ 0x637265617465ULL), p->key ? p->key : p->name);
      [_world addEntity:e
              blueprint:p->name
                   seed:seed];
      error = nil;
      if( ! [_world construct:e
                        error:&error])
         return( error ? error : [NSString stringWithFormat:@"cannot build %s", p->name]);
      loc = resolve_location( g, p->location);
      if( [_world isPhysical:e])
      {
         if( loc.form == BGLocationNone)
            return( [NSString stringWithFormat:@"%s is physical and needs a location", p->name]);
         [_world setLocation:loc
                          of:e];
      }
      else
         if( loc.form != BGLocationNone)
            return( [NSString stringWithFormat:@"%s is informational and has no location", p->name]);
      declare( tally, [_world isPhysical:e] ? [_world unitOf:e] : NULL, [_world unitsOf:e], [_world massOf:e]);
      [self emit:"created" subject:e other:BGNoEntity amount:0 detail:p->name location:loc group:g];
      return( nil);

   case BGProposeDestroy:
      e = resolve_ref( g, p->target);
      if( (reason = live_check( _world, e, "target")))
         return( reason);
      if( [_world isPhysical:e])
         declare( tally, [_world unitOf:e], -[_world unitsOf:e], -[_world massOf:e]);
      ev = [self emit:"destroyed" subject:e other:BGNoEntity amount:0 detail:p->name location:BGLocationMakeNone() group:g];
      [_world destroy:e
            successor:BGNoEntity
                cause:ev
               reason:p->name ? p->name : "destroyed"];
      return( nil);

   case BGProposeSetField:
      e = resolve_ref( g, p->target);
      if( (reason = live_check( _world, e, "target")))
         return( reason);
      if( ! [_world lookupField:p->name
                           kind:&k
                          field:&f])
         return( [NSString stringWithFormat:@"no field %s", p->name]);
      if( ! strstr( f->flags, "proposable"))
         return( [NSString stringWithFormat:@"%s is not proposable", p->name]);
      if( [_world isCheckedOut:e] && ! strcmp( [_world kindInfo:k]->name, "WaterStore"))
         return( [NSString stringWithFormat:@"%llu's water is checked out by its domain; contribute to the domain instead",
                                            (unsigned long long) e]);
      if( ! [_world record:k
                       for:e])
         return( [NSString stringWithFormat:@"%llu has no %s component",
                                            (unsigned long long) e, [_world kindInfo:k]->name]);
      /* a reference to something the group creates: its ID now */
      value = f->value == BG_VALUE_REF && BGIsHandle( (BGEntityID) p->value) ? (int64_t) [g idFor:(BGEntityID) p->value]
                                                                            : p->value;
      if( f->value == BG_VALUE_TEXT ? ! [_world setField:p->name of:e text:p->key]
                                    : ! [_world setField:p->name of:e value:value])
         return( [NSString stringWithFormat:@"%s cannot be set", p->name]);
      [self emit:"changed" subject:e other:BGNoEntity amount:p->value detail:p->name location:BGLocationMakeNone() group:g];
      return( nil);

   case BGProposeMove:
      e = resolve_ref( g, p->target);
      if( (reason = live_check( _world, e, "target")))
         return( reason);
      if( ! [_world isPhysical:e])
         return( [NSString stringWithFormat:@"%llu is informational and has no location", (unsigned long long) e]);
      loc = resolve_location( g, p->location);
      if( loc.form == BGLocationNone)
         return( @"a physical entity cannot be moved nowhere");
      if( p->expects)
      {
         BGLocation   now;
         BGLocation   was;

         now = [_world locationOf:e];
         was = resolve_location( g, p->expected);
         if( now.form != was.form || now.place != was.place || now.slot != was.slot ||
             (now.form == BGLocationOnTile && (now.x != was.x || now.y != was.y || now.level != was.level)))
            return( [NSString stringWithFormat:@"%llu is no longer where it was taken from", (unsigned long long) e]);
      }
      [_world setLocation:loc
                       of:e];
      [self emit:"moved" subject:e other:loc.place amount:0 detail:NULL location:loc group:g];
      return( nil);

   case BGProposeSplit:
      a = resolve_ref( g, p->target);
      if( (reason = live_check( _world, a, "stack")))
         return( reason);
      sp = (BGStack *) [_world record:kstack for:a];
      if( ! sp)
         return( [NSString stringWithFormat:@"%llu is not a stack", (unsigned long long) a]);
      if( p->value < 1 || p->value >= sp->count)
         return( [NSString stringWithFormat:@"cannot split %lld of %lld", (long long) p->value, (long long) sp->count]);
      /* copies: adding the new entity's records may move the store's */
      stack = *sp;
      sp    = NULL;
      body  = *(BGBody *) [_world record:kbody for:a];
      info  = [_world info:a];
      e     = [_world allocateID];
      [g setID:e
     forHandle:p->handle];
      seed  = BGMix( info->seed ^ ((uint64_t) stack.count * 0x9e3779b97f4a7c15ULL));
      loc   = p->location.form == BGLocationNone ? [_world locationOf:a] : resolve_location( g, p->location);
      /* the new entity: an individual of the unit, or a smaller stack */
      if( p->value == 1)
      {
         [_world addEntity:e
                 blueprint:stack.unit
                      seed:seed];
         body.mass = stack.unitMass;
         [_world setRecord:&body
                      kind:kbody
                       for:e];
      }
      else
      {
         [_world addEntity:e
                 blueprint:info->blueprint
                      seed:seed];
         body.mass   = stack.unitMass * p->value;
         stack.count = p->value;
         [_world setRecord:&body
                      kind:kbody
                       for:e];
         [_world setRecord:&stack
                      kind:kstack
                       for:e];
         stack = *(BGStack *) [_world record:kstack for:a];
      }
      /* what remains */
      stack.count -= p->value;
      body         = *(BGBody *) [_world record:kbody for:a];
      body.mass   -= stack.unitMass * p->value;
      [_world setRecord:&stack
                   kind:kstack
                    for:a];
      [_world setRecord:&body
                   kind:kbody
                    for:a];
      [_world setLocation:loc
                       of:e];
      [_world addEdge:BGEdgeSplitFrom
                 from:e
                   to:a];
      /* every claim on the stack extends to what was split off; which units it covers is not assigned */
      n = [_world edges:BGEdgeClaimSubject
                     to:a
                   into:claims
                    max:64];
      for( i = 0; i < n && i < 64; i++)
         [_world addEdge:BGEdgeClaimSubject
                    from:claims[ i]
                      to:e];
      [self emit:"split" subject:e other:a amount:p->value detail:NULL location:loc group:g];
      return( nil);

   case BGProposeMerge:
      a = resolve_ref( g, p->target);
      b = resolve_ref( g, p->other);
      if( (reason = live_check( _world, a, "unit")) || (reason = live_check( _world, b, "stack")))
         return( reason);
      if( (reason = [self mergeObstacle:a
                                   into:b]))
         return( [NSString stringWithFormat:@"cannot merge %llu into %llu: %@",
                                            (unsigned long long) a, (unsigned long long) b, reason]);
      stack        = *(BGStack *) [_world record:kstack for:b];
      body         = *(BGBody *) [_world record:kbody for:b];
      stack.count += [_world unitsOf:a];
      body.mass   += [_world massOf:a];
      [_world setRecord:&stack
                   kind:kstack
                    for:b];
      [_world setRecord:&body
                   kind:kbody
                    for:b];
      /* quantity claims follow the units; each keeps its quantity */
      n = [_world edges:BGEdgeClaimSubject
                     to:a
                   into:claims
                    max:64];
      for( i = 0; i < n && i < 64; i++)
      {
         [_world removeEdge:BGEdgeClaimSubject
                       from:claims[ i]
                         to:a];
         [_world addEdge:BGEdgeClaimSubject
                    from:claims[ i]
                      to:b];
      }
      ev = [self emit:"merged" subject:a other:b amount:[_world unitsOf:a] detail:NULL
             location:[_world locationOf:b] group:g];
      [_world destroy:a
            successor:b
                cause:ev
               reason:"merged"];
      return( nil);

   case BGProposeAddEdge:
   case BGProposeRemoveEdge:
      a = resolve_ref( g, p->target);
      b = resolve_ref( g, p->other);
      if( (reason = live_check( _world, a, "source")) || (reason = live_check( _world, b, "target")))
         return( reason);
      if( p->kind == BGProposeRemoveEdge)
      {
         if( ! [_world hasEdge:p->edge
                          from:a
                            to:b])
            return( [NSString stringWithFormat:@"no %s edge from %llu to %llu",
                                               BGEdgeKindNames[ p->edge], (unsigned long long) a, (unsigned long long) b]);
         [_world removeEdge:p->edge
                       from:a
                         to:b];
         [self emit:"unrelated" subject:a other:b amount:0 detail:BGEdgeKindNames[ p->edge]
           location:BGLocationMakeNone() group:g];
         return( nil);
      }
      /* splitFrom and claimant are many-to-one */
      if( p->edge != BGEdgeClaimSubject && [_world edges:p->edge
                                                    from:a
                                                    into:claims
                                                     max:1])
         return( [NSString stringWithFormat:@"%llu already has a %s", (unsigned long long) a, BGEdgeKindNames[ p->edge]]);
      [_world addEdge:p->edge
                 from:a
                   to:b];
      [self emit:"related" subject:a other:b amount:0 detail:BGEdgeKindNames[ p->edge]
        location:BGLocationMakeNone() group:g];
      return( nil);

   case BGProposeEvent:
      a = resolve_ref( g, p->target);
      b = resolve_ref( g, p->other);
      [self emit:[_world intern:p->name] subject:a other:b amount:p->value
          detail:p->key ? [_world intern:p->key] : NULL
        location:BGLocationMakeNone() group:g];
      return( nil);
   }
   return( @"unknown proposal");
}


/* --- validation ------------------------------------------------------------ */

/* Why the place a physical entity is in can't hold it, or nil. */
- (NSString *) placeObstacle:(BGEntityID) e
                          at:(BGLocation) loc
{
   const BGAgent       *agent;
   const BGContainer   *container;
   const BGAssembly    *assembly;
   BGEntityID          others[ 256];
   BGEntityID          up;
   BGLocation          other;
   NSUInteger          guard;
   NSUInteger          i;
   NSUInteger          n;

   if( loc.form == BGLocationOnTile)
      return( [_world isTileX:loc.x y:loc.y level:loc.level]
              ? nil : [NSString stringWithFormat:@"(%d, %d) is off the map", loc.x, loc.y]);
   if( ! [_world isLive:loc.place])
      return( [NSString stringWithFormat:@"%llu is in %llu, which does not exist",
                                         (unsigned long long) e, (unsigned long long) loc.place]);
   /* nothing is inside itself, however deep */
   up = loc.place;
   for( guard = 0; up && guard < 64; guard++)
   {
      if( up == e)
         return( [NSString stringWithFormat:@"%llu would be inside itself", (unsigned long long) e]);
      up = [_world locationOf:up].place;
   }
   n = [_world entitiesAt:loc.place
                     form:loc.form
                     into:others
                      max:256];
   switch( loc.form)
   {
   case BGLocationHeldBy:
      agent = [_world record:[_world kindNamed:"Agent"] for:loc.place];
      if( ! agent)
         return( [NSString stringWithFormat:@"%llu has no hands", (unsigned long long) loc.place]);
      if( loc.slot < 0 || loc.slot >= agent->hands)
         return( [NSString stringWithFormat:@"%llu has no hand %d", (unsigned long long) loc.place, loc.slot]);
      for( i = 0; i < n && i < 256; i++)
      {
         other = [_world locationOf:others[ i]];
         if( others[ i] != e && other.slot == loc.slot)
            return( [NSString stringWithFormat:@"hand %d of %llu already holds %llu",
                                               loc.slot, (unsigned long long) loc.place, (unsigned long long) others[ i]]);
      }
      return( nil);

   case BGLocationIn:
      container = [_world record:[_world kindNamed:"Container"] for:loc.place];
      if( ! container)
         return( [NSString stringWithFormat:@"%llu is not a container", (unsigned long long) loc.place]);
      if( (int64_t) n > container->capacity)
         return( [NSString stringWithFormat:@"%llu is full (%lld)", (unsigned long long) loc.place,
                                            (long long) container->capacity]);
      return( nil);

   case BGLocationPartOf:
      assembly = [_world record:[_world kindNamed:"Assembly"] for:loc.place];
      if( ! assembly)
         return( [NSString stringWithFormat:@"%llu is not an assembly", (unsigned long long) loc.place]);
      if( loc.slot < 0 || loc.slot >= assembly->slots)
         return( [NSString stringWithFormat:@"%llu has no slot %d", (unsigned long long) loc.place, loc.slot]);
      for( i = 0; i < n && i < 256; i++)
      {
         other = [_world locationOf:others[ i]];
         if( others[ i] != e && other.slot == loc.slot && ! strcmp( other.role, loc.role))
            return( [NSString stringWithFormat:@"%s %d of %llu is taken", loc.role, loc.slot,
                                               (unsigned long long) loc.place]);
      }
      return( nil);

   default:
      return( nil);
   }
}


- (NSString *) validate:(BGTally *) tally
{
   const BGBody         *body;
   const BGStack        *stack;
   const BGEntityInfo   *info;
   BGUnitTally          *u;
   BGEntityID           *touched;
   BGLocation           loc;
   NSString             *reason;
   NSUInteger           i;
   NSUInteger           kbody;
   NSUInteger           kstack;
   NSUInteger           n;
   int64_t              after;
   int64_t              before;
   BOOL                 hadBody;
   BOOL                 hadStack;

   kbody   = [_world kindNamed:"Body"];
   kstack  = [_world kindNamed:"Stack"];
   n       = [_world touched:NULL
                         max:0];
   touched = malloc( sizeof( BGEntityID) * (n ? n : 1));
   [_world touched:touched
               max:n];
   reason = nil;
   before = 0;
   after  = 0;
   for( i = 0; i < n && ! reason; i++)
   {
      /* location: every physical entity has exactly one, in a place that can hold it */
      if( [_world isLive:touched[ i]])
      {
         loc = [_world locationOf:touched[ i]];
         if( [_world isPhysical:touched[ i]])
         {
            if( loc.form == BGLocationNone)
               reason = [NSString stringWithFormat:@"%llu has no location", (unsigned long long) touched[ i]];
            else
               reason = [self placeObstacle:touched[ i]
                                         at:loc];
         }
         else
            if( loc.form != BGLocationNone)
               reason = [NSString stringWithFormat:@"%llu is informational but has a location",
                                                   (unsigned long long) touched[ i]];
      }

      /* conservation: mass, and each unit's count */
      body = [_world recordBeforeGroup:kbody
                                   for:touched[ i]
                               existed:&hadBody];
      if( hadBody)
      {
         before += body->mass;
         stack   = [_world recordBeforeGroup:kstack
                                         for:touched[ i]
                                     existed:&hadStack];
         info    = [_world infoBeforeGroup:touched[ i]];
         u       = tally_unit( tally, hadStack ? stack->unit : (info ? info->blueprint : "?"));
         if( u)
            u->before += hadStack ? stack->count : 1;
      }
      if( [_world isPhysical:touched[ i]])
      {
         after += [_world massOf:touched[ i]];
         u      = tally_unit( tally, [_world unitOf:touched[ i]]);
         if( u)
            u->after += [_world unitsOf:touched[ i]];
      }
   }
   free( touched);
   if( reason)
      return( reason);
   if( after - before != tally->mass)
      return( [NSString stringWithFormat:@"mass is not conserved: %lldg before, %lldg after, %lldg declared",
                                         (long long) before, (long long) after, (long long) tally->mass]);
   for( i = 0; i < tally->nunits; i++)
   {
      u = &tally->units[ i];
      if( u->after - u->before != u->declared)
         return( [NSString stringWithFormat:@"the count of %s is not conserved: %lld before, %lld after, %lld declared",
                                            u->unit, (long long) u->before, (long long) u->after, (long long) u->declared]);
   }
   return( nil);
}


/* --- one group ------------------------------------------------------------- */

- (NSString *) describeEvent:(const BGEvent *) ev
{
   char   where[ 64];

   BGLocationFormat( ev->location, where, sizeof( where));
   return( [NSString stringWithFormat:@"    event %llu %s: %llu%s%@%@%@%s%s",
                                      (unsigned long long) ev->index, ev->kind, (unsigned long long) ev->subject,
                                      ev->other ? ", other " : "",
                                      ev->other ? [NSString stringWithFormat:@"%llu", (unsigned long long) ev->other] : @"",
                                      ev->amount ? [NSString stringWithFormat:@", %lld", (long long) ev->amount] : @"",
                                      ev->detail ? [NSString stringWithFormat:@", %s", ev->detail] : @"",
                                      ev->location.form ? ", to " : "",
                                      ev->location.form ? where : ""]);
}


- (void) commitGroup:(BGProposalGroup *) group
{
   BGProposal   *proposals;
   BGTally      tally;
   NSString     *reason;
   NSUInteger   first;
   NSUInteger   i;
   NSUInteger   n;

   _position++;
   [_sources setObject:[group source]
                forKey:[NSNumber numberWithUnsignedLongLong:_position]];
   [self note:[NSString stringWithFormat:@"b%llu r%u #%llu %s %@", (unsigned long long) [_world boundary], _round,
                                         (unsigned long long) _position, BGPhaseNames[ [group phase]], [group source]]];
   memset( &tally, 0, sizeof( tally));
   [_world beginGroup];
   first     = [_world eventCount];
   proposals = [self individuate:group
                           count:&n];
   reason    = nil;
   for( i = 0; i < n && ! reason; i++)
      reason = [self apply:&proposals[ i]
                     group:group
                     tally:&tally];
   if( ! reason)
      reason = [self validate:&tally];
   free( proposals);
   if( reason)
   {
      [_world rollbackGroup];
      [group setApplied:NO
              rejection:reason
               position:_position];
      [self note:[NSString stringWithFormat:@"    rejected: %@", reason]];
      return;
   }
   [_world commitGroup];
   [group setApplied:YES
           rejection:nil
            position:_position];
   for( i = first; i < [_world eventCount]; i++)
      [self note:[self describeEvent:[_world eventAt:i]]];
}


/* --- a boundary ------------------------------------------------------------ */

- (void) reactToEventsFrom:(NSUInteger) first
{
   const BGEvent   *ev;
   id              reactor;
   NSUInteger      i;
   NSUInteger      k;
   NSUInteger      kind;
   NSUInteger      last;

   last = [_world eventCount];
   /* engine machinery that follows each round, such as activities */
   for( k = 0; k < [_listeners count]; k++)
      [[_listeners objectAtIndex:k] committer:self
                              didCommitRound:_round
                                  eventsFrom:first
                                          to:last];
   for( i = first; i < last; i++)
   {
      ev = [_world eventAt:i];
      for( k = 0; k + 1 < [_reactors count]; k += 2)
      {
         kind    = (NSUInteger) [[_reactors objectAtIndex:k] unsignedLongLongValue];
         reactor = [_reactors objectAtIndex:k + 1];
         if( [_world record:kind for:ev->subject])
            [reactor committer:self
                  reactToEvent:ev
                         world:_world];
      }
   }
}


- (NSArray *) commitBoundary
{
   NSMutableArray   *current;
   NSMutableArray   *processed;
   NSArray          *ordered;
   NSUInteger       first;
   NSUInteger       i;

   processed = [NSMutableArray array];
   current   = [NSMutableArray arrayWithArray:_deferred];
   [current addObjectsFromArray:_submitted];
   [_deferred removeAllObjects];
   [_submitted removeAllObjects];
   for( _round = 0; [current count] && _round < _rounds; _round++)
   {
      ordered = [self order:current];
      first   = [_world eventCount];
      for( i = 0; i < [ordered count]; i++)
      {
         [self commitGroup:[ordered objectAtIndex:i]];
         [processed addObject:[ordered objectAtIndex:i]];
      }
      [self reactToEventsFrom:first];
      [current removeAllObjects];
      [current addObjectsFromArray:_submitted];
      [_submitted removeAllObjects];
   }
   if( [current count])
   {
      [self note:[NSString stringWithFormat:@"b%llu: %lu groups deferred to the next boundary",
                                            (unsigned long long) [_world boundary], (unsigned long) [current count]]];
      [_deferred addObjectsFromArray:current];
   }
   return( processed);
}

@end
