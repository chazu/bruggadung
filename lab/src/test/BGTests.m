#import "BGTest.h"

#import "BGScheduler.h"
#import "BGMarkedNail.h"
#import "BGSave.h"
#import "BGActions.h"
#import "BGView.h"
#import "BGCistern.h"
#import "BGActivities.h"
#import "BGPlay.h"
#import "BGKnowledge.h"
#import "BGWorlds.h"
#import "BGAgency.h"
#import "BGTraces.h"
#import "BGBodies.h"
#import "BGAtmosphere.h"
#import "BGThermal.h"

#include <stdio.h>


/* --- stores and the registry ------------------------------------------------ */

static void   test_store( void)
{
   BGStore    *store;
   int64_t    v;

   store = [[[BGStore alloc] initWithRecordSize:sizeof( int64_t)] autorelease];
   v = 30;
   [store setRecord:&v for:30];
   v = 10;
   [store setRecord:&v for:10];
   v = 20;
   [store setRecord:&v for:20];
   BG_CHECK( [store count] == 3);
   BG_CHECK( [store entityAtIndex:0] == 10 && [store entityAtIndex:1] == 20 && [store entityAtIndex:2] == 30);
   v = 21;
   [store setRecord:&v for:20];
   BG_CHECK( [store count] == 3 && *(int64_t *) [store recordFor:20] == 21);
   [store removeRecordFor:10];
   BG_CHECK( [store count] == 2 && [store recordFor:10] == NULL && [store entityAtIndex:0] == 20);
}


static BGEntityID   commit_create( BGCommitter *committer, const char *blueprint, BGLocation at)
{
   BGProposalGroup   *g;
   BGEntityID        h;

   g = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                source:@"create"];
   h = [g create:blueprint key:blueprint at:at];
   [committer submit:g];
   [committer commitBoundary];
   return( [g applied] ? [g idFor:h] : BGNoEntity);
}


static void   test_registry_and_construction( void)
{
   BGWorld          *w;
   BGCommitter      *c;
   BGEntityID       bin;
   BGEntityID       nails;
   int64_t          v;
   const BGStack    *stack;

   w = BGTestWorld( 1);
   c = BGTestCommitter( w);
   BG_CHECK( [w kindCount] == 35);
   BG_CHECK( [w kindNamed:"Body"] != NSNotFound && [w kindNamed:"Nonesuch"] == NSNotFound);
   bin   = commit_create( c, "bin", BGOnTile( 0, 0, 0));
   nails = commit_create( c, "nails_30", BGIn( bin));
   BG_CHECK( bin == 1 && nails == 2);
   BG_CHECK( [w getField:"Body.mass" of:bin value:&v] && v == 4000);
   BG_CHECK( [w getField:"Container.capacity" of:bin value:&v] && v == 50);
   /* the stack's mass comes from Triangle arithmetic: 30 × 3 g */
   BG_CHECK( [w getField:"Body.mass" of:nails value:&v] && v == 90);
   stack = [w record:[w kindNamed:"Stack"] for:nails];
   BG_CHECK( stack && stack->count == 30 && ! strcmp( stack->unit, "iron_nail"));
   BG_CHECK( [w isPhysical:nails] && [w isStack:nails] && ! [w isStack:bin]);
   BG_CHECK( [[w describeEntity:nails] rangeOfString:@"Body.mass=90g"].location != NSNotFound);
   BG_CHECK( ! [w getField:"Body.nonesuch" of:bin value:&v]);
}


static void   test_rollback( void)
{
   BGWorld      *w;
   BGCommitter  *c;
   BGEntityID   bin;
   BGEntityID   e;
   BGEvent      ev;
   uint64_t     before;

   w      = BGTestWorld( 1);
   c      = BGTestCommitter( w);
   bin    = commit_create( c, "bin", BGOnTile( 0, 0, 0));
   before = [w stateHash];
   [w beginGroup];
   e = [w allocateID];
   [w addEntity:e blueprint:"nails_30" seed:5];
   BG_CHECK( [w construct:e error:NULL]);
   [w setLocation:BGIn( bin) of:e];
   [w addEdge:BGEdgeSplitFrom from:e to:bin];
   [w setField:"Body.mass" of:bin value:1];
   memset( &ev, 0, sizeof( ev));
   ev.kind = "test";
   [w emit:ev];
   BG_CHECK( [w stateHash] != before);
   [w rollbackGroup];
   BG_CHECK( [w stateHash] == before);
   BG_CHECK( ! [w isLive:e] && [w nextID] == e && ! [w hasEdge:BGEdgeSplitFrom from:e to:bin]);
}


/* --- commitment ------------------------------------------------------------- */

static void   test_validation( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGProposalGroup   *g;
   BGEntityID        bin;
   BGEntityID        nails;
   BGEntityID        worker;
   BGEntityID        claim;
   uint64_t          before;

   w      = BGTestWorld( 1);
   c      = BGTestCommitter( w);
   bin    = commit_create( c, "bin", BGOnTile( 0, 0, 0));
   nails  = commit_create( c, "nails_30", BGIn( bin));
   worker = commit_create( c, "worker", BGOnTile( 1, 0, 0));
   claim  = commit_create( c, "ownership", BGLocationMakeNone());
   BG_CHECK( claim != BGNoEntity && ! [w isPhysical:claim]);
   BG_CHECK( commit_create( c, "bin", BGLocationMakeNone()) == BGNoEntity);      /* physical needs a location */
   BG_CHECK( commit_create( c, "nonesuch", BGOnTile( 0, 0, 0)) == BGNoEntity);
   before = [w stateHash];

   /* mass can't change without a declared process */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g set:"Body.mass" of:BGWhole( nails) to:91];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"mass is not conserved"].location != NSNotFound);

   /* only proposable fields */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g set:"Body.material" of:BGWhole( nails) to:1];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"not proposable"].location != NSNotFound);

   /* informational entities have no location */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g move:BGWhole( claim) to:BGOnTile( 0, 0, 0)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied]);

   /* one hand holds one thing; one bad proposal rejects the whole group */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g split:BGWhole( nails) count:2 to:BGHeldBy( worker, 0)];
   [g split:BGWhole( nails) count:3 to:BGHeldBy( worker, 0)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"already holds"].location != NSNotFound);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g split:BGWhole( nails) count:2 to:BGHeldBy( worker, 2)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"no hand 2"].location != NSNotFound);

   /* nothing goes inside itself */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g move:BGWhole( bin) to:BGIn( bin)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied]);

   /* tombstones and unknown entities are refused */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g move:BGWhole( 999) to:BGIn( bin)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"does not exist"].location != NSNotFound);

   BG_CHECK( [w stateHash] == before);
}


static void   test_individuation_and_merge_rules( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGProposalGroup   *g;
   BGEntityID        bin;
   BGEntityID        nails;
   BGEntityID        other;
   BGEntityID        parts[ 4];
   BGEntityID        lock;

   w     = BGTestWorld( 1);
   c     = BGTestCommitter( w);
   bin   = commit_create( c, "bin", BGOnTile( 0, 0, 0));
   nails = commit_create( c, "nails_30", BGIn( bin));
   lock  = commit_create( c, "lock", BGOnTile( 2, 0, 0));

   /* addressing one unit splits it off: the stack keeps 29, the unit is an individual */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g set:"Body.toolMarks" of:BGUnit( nails, 1) to:2];
   [g move:BGUnit( nails, 1) to:BGPartOf( lock, "pin", 0)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( [g applied]);
   if( ! [g applied]) fprintf( stderr, "DEBUG %s\n", [[g rejection] UTF8String]);
   BG_CHECK( [w unitsOf:nails] == 29 && [w massOf:nails] == 87);
   BG_CHECK( [w entitiesAt:lock form:BGLocationPartOf into:parts max:4] == 1);
   BG_CHECK( ! [w isStack:parts[ 0]] && [w massOf:parts[ 0]] == 3);
   BG_CHECK( [w hasEdge:BGEdgeSplitFrom from:parts[ 0] to:nails]);
   BG_CHECK( ! strcmp( [w unitOf:parts[ 0]], "iron_nail"));

   /* merging needs the same place, the same unit, and no marks */
   other = commit_create( c, "nails_10", BGOnTile( 0, 0, 0));
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g merge:BGWhole( other) into:BGWhole( nails)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"not in the same place"].location != NSNotFound);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g merge:BGWhole( lock) into:BGWhole( nails)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"different units"].location != NSNotFound);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
   [g move:BGWhole( parts[ 0]) to:BGOnTile( 0, 0, 0)];
   [g merge:BGWhole( parts[ 0]) into:BGWhole( other)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"tool marks"].location != NSNotFound);

   /* the Body reaction merges a clean stack put into the bin */
   g = [BGProposalGroup groupWithPhase:BGPhaseAction source:@"t"];
   [g move:BGWhole( other) to:BGIn( bin)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( [w unitsOf:nails] == 39 && [w resolve:other] == nails);
   BG_CHECK( [w tombstone:other] && ! strcmp( [w tombstone:other]->reason, "merged"));

   /* a claim on one unit alone pins it; a quantity claim over several entities follows the units */
   {
      BGEntityID   claim;
      BGEntityID   unit;
      BGEntityID   h;

      claim = commit_create( c, "ownership", BGLocationMakeNone());
      g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
      h     = [g split:BGWhole( nails) count:1 to:BGIn( bin)];
      [g relate:BGEdgeClaimSubject from:BGWhole( claim) to:BGWhole( h)];
      [c submit:g];
      [c commitBoundary];
      unit = [g idFor:h];
      BG_CHECK( [g applied] && ! [w isStack:unit]);
      g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
      [g merge:BGWhole( unit) into:BGWhole( nails)];
      [c submit:g];
      [c commitBoundary];
      BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"claim is on this unit alone"].location != NSNotFound);
      g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"t"];
      [g relate:BGEdgeClaimSubject from:BGWhole( claim) to:BGWhole( nails)];
      [g merge:BGWhole( unit) into:BGWhole( nails)];
      [c submit:g];
      [c commitBoundary];
      BG_CHECK( [g applied] && [w resolve:unit] == nails && [w hasEdge:BGEdgeClaimSubject from:claim to:nails]);
   }
}


/* Two groups want the same hand: the seeded order decides, the same way for
 * the same seed, and over many seeds neither wins every time. */
static BGEntityID   winner( uint64_t seed)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGProposalGroup   *a;
   BGProposalGroup   *b;
   BGEntityID        bin;
   BGEntityID        nails;
   BGEntityID        worker;

   w      = BGTestWorld( seed);
   c      = BGTestCommitter( w);
   bin    = commit_create( c, "bin", BGOnTile( 0, 0, 0));
   nails  = commit_create( c, "nails_30", BGIn( bin));
   worker = commit_create( c, "worker", BGOnTile( 1, 0, 0));
   [w setBoundary:7];
   a = [BGProposalGroup groupWithPhase:BGPhaseAction source:@"a"];
   [a split:BGWhole( nails) count:2 to:BGHeldBy( worker, 0)];
   b = [BGProposalGroup groupWithPhase:BGPhaseAction source:@"b"];
   [b split:BGWhole( nails) count:3 to:BGHeldBy( worker, 0)];
   [c submit:a];
   [c submit:b];
   [c commitBoundary];
   if( [a applied] == [b applied])
      return( 0);
   return( [a applied] ? 2 : 3);
}


static void   test_seeded_order( void)
{
   uint64_t   seed;
   int        twos;
   int        threes;
   BGEntityID w;

   twos   = 0;
   threes = 0;
   for( seed = 1; seed <= 24; seed++)
   {
      w = winner( seed);
      BG_CHECK( w != 0);
      BG_CHECK( winner( seed) == w);
      if( w == 2)
         twos++;
      if( w == 3)
         threes++;
   }
   /* over many seeds, neither group wins every time */
   BG_CHECK( twos > 0 && threes > 0);
}


/* A reactor that answers every ping with another: the rounds bound cuts it
 * off, and the rest is deferred to the next boundary. */
@interface BGPingReactor : NSObject <BGReactor>
@end

@implementation BGPingReactor

- (void) committer:(BGCommitter *) committer
     reactToEvent:(const BGEvent *) event
            world:(BGWorld *) world
{
   BGProposalGroup   *g;

   if( strcmp( event->kind, "ping"))
      return;
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"pong"];
   [g setCause:event->index];
   [g emit:"ping" subject:BGWhole( event->subject) other:BGWhole( BGNoEntity)];
   [committer submit:g];
}

@end


static void   test_reaction_rounds( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGProposalGroup   *g;
   BGEntityID        claim;
   NSArray           *groups;

   w     = BGTestWorld( 1);
   c     = BGTestCommitter( w);
   [c addReactor:[[BGPingReactor new] autorelease] forKind:"Claim"];
   claim = commit_create( c, "ownership", BGLocationMakeNone());
   [c setRounds:3];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"ping"];
   [g emit:"ping" subject:BGWhole( claim) other:BGWhole( BGNoEntity)];
   [c submit:g];
   groups = [c commitBoundary];
   BG_CHECK( [groups count] == 3);
   BG_CHECK( [c hasPending]);
   BG_CHECK( [[[c trace] lastObject] rangeOfString:@"deferred to the next boundary"].location != NSNotFound);
   /* each reaction's event names its cause */
   BG_CHECK( [w eventAt:[w eventCount] - 1]->cause == [w eventAt:[w eventCount] - 2]->index);
}


/* --- the scheduler ---------------------------------------------------------- */

@interface BGTestDomain : NSObject <BGDomain>
{
@public
   int64_t   steps[ 16][ 2];
   int       nsteps;
}
@end

@implementation BGTestDomain

- (NSString *) name
{
   return( @"test");
}


- (BOOL) isActive
{
   return( YES);
}


- (BGHorizon) horizonAt:(BGTime) t
{
   BGHorizon   h;

   h.safeStep  = BGTimeMake( 1000);
   h.nextEvent = t.ms < 300 ? BGTimeMake( 300) : t.ms < 700 ? BGTimeMake( 700) : BGTimeNever;
   return( h);
}


- (void) checkInAll
{
}


- (NSArray *) savedState
{
   return( [NSArray array]);
}


- (void) restoreSavedState:(NSArray *) lines
{
}


- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
{
   if( nsteps < 16)
   {
      steps[ nsteps][ 0] = t0.ms;
      steps[ nsteps][ 1] = t1.ms;
      nsteps++;
   }
}

@end


static void   test_scheduler_horizons( void)
{
   BGWorld        *w;
   BGCommitter    *c;
   BGScheduler    *s;
   BGTestDomain   *d;
   NSUInteger     n;

   w = BGTestWorld( 1);
   c = BGTestCommitter( w);
   s = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   d = [[BGTestDomain new] autorelease];
   [s addDomain:d];
   n = [s runUntil:BGTimeMake( 2000)];
   /* events bound the first steps; the safe step bounds the next; the stop is a boundary too */
   BG_CHECK( n == 4);
   BG_CHECK( d->nsteps == 4);
   BG_CHECK( d->steps[ 0][ 1] == 300 && d->steps[ 1][ 1] == 700 && d->steps[ 2][ 1] == 1700);
   BG_CHECK( d->steps[ 3][ 0] == 1700 && d->steps[ 3][ 1] == 2000);
   BG_CHECK( [w time].ms == 2000 && [w boundary] == 4);
}


/* --- the marked nail -------------------------------------------------------- */

static BGMarkedNail   *run_marked_nail( BGMarkedNailVariant variant, uint64_t seed)
{
   BGWorld        *w;
   BGMarkedNail   *scenario;

   w        = BGTestWorld( seed);
   scenario = [[[BGMarkedNail alloc] initWithWorld:w
                                         committer:BGTestCommitter( w)
                                           variant:variant] autorelease];
   [scenario run];
   return( scenario);
}


static void   check_scenario( BGMarkedNail *scenario)
{
   NSArray      *results;
   NSUInteger   i;

   results = [scenario results];
   for( i = 0; i < [results count]; i++)
      if( [[results objectAtIndex:i] hasPrefix:@"FAIL"])
         fprintf( stderr, "    %s\n", [[results objectAtIndex:i] UTF8String]);
   BG_CHECK( [results count] > 0);
   BG_CHECK( [scenario failureCount] == 0);
}


static void   test_marked_nail( void)
{
   check_scenario( run_marked_nail( BGMarkedNailBase, 42));
}


static void   test_marked_nail_a( void)
{
   check_scenario( run_marked_nail( BGMarkedNailUnmarked, 42));
}


static void   test_marked_nail_b( void)
{
   check_scenario( run_marked_nail( BGMarkedNailMixedGoods, 42));
}


/* Acceptance check 7: a replay is bit-identical, IDs and state and trace. */
static void   test_marked_nail_replay( void)
{
   BGMarkedNail   *a;
   BGMarkedNail   *b;
   BGMarkedNail   *other;

   a     = run_marked_nail( BGMarkedNailBase, 42);
   b     = run_marked_nail( BGMarkedNailBase, 42);
   other = run_marked_nail( BGMarkedNailBase, 43);
   BG_CHECK( [[a world] stateHash] == [[b world] stateHash]);
   BG_CHECK( [[a world] nextID] == [[b world] nextID]);
   BG_CHECK( [[[a committer] trace] isEqualToArray:[[b committer] trace]]);
   /* another world seed draws other seeds, but the story comes out the same */
   BG_CHECK( [other failureCount] == 0);
   BG_CHECK( [[other world] stateHash] != [[a world] stateHash]);
}


/* --- the action menu ------------------------------------------------------- */

static NSString   *menu_text( BGWorld *w, BGEntityID actor)
{
   BGMenu           *menu;
   NSMutableArray   *lines;
   NSUInteger       i;

   menu  = [BGMenu menuFor:actor world:w];
   lines = [NSMutableArray array];
   for( i = 0; i < [menu count]; i++)
      [lines addObject:[menu describeAt:i]];
   return( [lines componentsJoinedByString:@"; "]);
}


static void   test_menu( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGMarkedNail      *scenario;
   BGProposalGroup   *g;
   TriArena          *arena;
   TriMatchResult    r;
   NSString          *error;
   NSString          *text;
   const TriNode     *seen;
   const TriNode     *wants;

   /* the workshop: bin 1 holding nails 2, lock 3, worker 4, smith 5 (out of reach) */
   w        = BGTestWorld( 42);
   c        = BGTestCommitter( w);
   scenario = [[[BGMarkedNail alloc] initWithWorld:w committer:c variant:BGMarkedNailBase] autorelease];
   [scenario runUntil:BGTimeMake( 0)];
   text = menu_text( w, 4);
   BG_CHECK( [text isEqualToString:@"look_in item 1: entailed; take item 1: entailed; take item 2: entailed; "
                                   @"take item 3: entailed; take_some item 2: entailed; take_up item 1: entailed; "
                                   @"take_up item 2: entailed; take_up item 3: entailed; test_scratch item 1: entailed; "
                                   @"test_scratch item 3: entailed; touch_up item 3: entailed; "
                                   @"walk_east: entailed; walk_north: entailed; walk_south: entailed; walk_west: entailed; "
                                   @"wash_floor: entailed; watch_closely: entailed; while_away: entailed"]);
   if( [text rangeOfString:@"watch_closely: entailed; while_away: entailed"].location == NSNotFound)
      fprintf( stderr, "    menu: %s\n", [text UTF8String]);

   /* a description carries perceivable fields only: the stack's count is hidden */
   text = [[BGView viewOf:4 inWorld:w] describeEntity:2];
   BG_CHECK( [text hasPrefix:@"#Stack & { id: ref(2), place: #Inside & { container: ref(1) }"]);
   BG_CHECK( [text rangeOfString:@"unit: \"iron_nail\""].location != NSNotFound);
   BG_CHECK( [text rangeOfString:@"count"].location == NSNotFound);
   /* so a pattern on the count is unknown, never incompatible, and says what to find out */
   arena = tri_arena_new();
   seen  = tri_value( [w tri], [text UTF8String], arena, NULL, 0);
   wants = tri_value( [w tri], "#Stack & { count: >=5 }", arena, NULL, 0);
   BG_CHECK( seen && wants && tri_match( [w tri], wants, seen, &r) == TRI_UNKNOWN);
   BG_CHECK( r.nresidual == 1 && ! strcmp( r.residual[ 0], "count"));
   tri_arena_free( arena);

   /* what isn't on the menu can't be performed */
   error = nil;
   BG_CHECK( ! BGPerform( w, c, BGActionMake( "put_in", 4, 2, 1), 0, &error));
   BG_CHECK( [error rangeOfString:@"ruled out at roles.item.place"].location != NSNotFound);
   BG_CHECK( ! BGPerform( w, c, BGActionMake( "take", 4, 5, BGNoEntity), 0, &error));
   BG_CHECK( [error rangeOfString:@"not in the actor's reach"].location != NSNotFound);
   BG_CHECK( ! BGPerform( w, c, BGActionMake( "fly", 4, BGNoEntity, BGNoEntity), 0, &error));
   BG_CHECK( ! BGPerform( w, c, BGActionMake( "take_some", 4, 2, BGNoEntity), 0, &error));
   BG_CHECK( [error rangeOfString:@"how many"].location != NSNotFound);

   /* take five: then they can be put back, driven, or split between hands */
   g = BGPerform( w, c, BGActionMake( "take_some", 4, 2, BGNoEntity), 5, &error);
   BG_CHECK( g != nil);
   [w setBoundary:[w boundary] + 1];
   [c commitBoundary];
   BG_CHECK( [g applied] && [g idFor:[g proposals][ 0].handle] == 7);      /* the claim is 6 */
   text = menu_text( w, 4);
   BG_CHECK( [text rangeOfString:@"put_in item 7 destination 1: entailed"].location != NSNotFound);
   BG_CHECK( [text rangeOfString:@"drive item 7 destination 3: entailed"].location != NSNotFound);
   BG_CHECK( [text rangeOfString:@"take_some item 7: entailed"].location != NSNotFound);
   /* the bin is no assembly, and the lock no container */
   BG_CHECK( [text rangeOfString:@"drive item 7 destination 1"].location == NSNotFound);
   BG_CHECK( [text rangeOfString:@"put_in item 7 destination 3"].location == NSNotFound);
}


/* --- activities ------------------------------------------------------------ */

static const char   *status_of( BGWorld *w, BGEntityID a)
{
   const BGActivity   *record;

   record = [w record:[w kindNamed:"Activity"] for:a];
   return( record ? tri_type_name( [w tri], record->status) : "none");
}


/* A timed activity whose item merges away before it is due: the recheck
 * suspends it (a hard interruption), and it can't be resumed. */
static void   test_activity_interrupted( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGActivities      *activities;
   BGProposalGroup   *g;
   BGEntityID        bin;
   BGEntityID        nails;
   BGEntityID        lock;
   BGEntityID        worker;
   BGEntityID        handful;
   BGEntityID        a;
   NSString          *error;

   w          = BGTestWorld( 5);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   bin    = commit_create( c, "bin", BGOnTile( 0, 0, 0));
   nails  = commit_create( c, "nails_30", BGIn( bin));
   lock   = commit_create( c, "lock", BGOnTile( 2, 0, 0));
   worker = commit_create( c, "worker", BGOnTile( 1, 0, 0));

   g = BGPerform( w, c, BGActionMake( "take_some", worker, nails, BGNoEntity), 5, &error);
   [s runUntil:BGTimeMake( 10)];
   handful = [g idFor:[g proposals][ 0].handle];
   BG_CHECK( [w unitsOf:handful] == 5);

   g = BGPerform( w, c, BGActionMake( "drive", worker, handful, lock), 0, &error);
   BG_CHECK( g != nil);
   [s runUntil:BGTimeMake( 20)];
   a = [g idFor:[g proposals][ 0].handle];
   BG_CHECK( ! strcmp( status_of( w, a), "\"running\""));
   BG_CHECK( [activities nextCompletion].ms == 10 + 4000);      /* from the command, at 10ms */
   BG_CHECK( [w unitsOf:handful] == 5);                       /* nothing happens until it is due */

   /* the nails go back in the bin and merge away before the drive is due */
   BGPerform( w, c, BGActionMake( "put_in", worker, handful, bin), 0, &error);
   [s runUntil:BGTimeMake( 30)];
   BG_CHECK( [w resolve:handful] == nails);
   BG_CHECK( ! strcmp( status_of( w, a), "\"suspended\""));
   BG_CHECK( ! [activities resume:a error:&error] && [error rangeOfString:@"is gone"].location != NSNotFound);
   [s runUntil:BGTimeMake( 6000)];
   BG_CHECK( [activities nextCompletion].ms == BGTimeNever.ms);
   BG_CHECK( [w unitsOf:nails] == 30);
}


/* A completion commitment rejects fails its activity: the lock has four
 * slots, and the fifth nail has nowhere to go. */
static void   test_activity_fails( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGActivities      *activities;
   BGProposalGroup   *g;
   BGEntityID        bin;
   BGEntityID        nails;
   BGEntityID        lock;
   BGEntityID        worker;
   BGEntityID        handful;
   BGEntityID        a;
   BGEntityID        parts[ 8];
   NSString          *error;
   int               i;

   w          = BGTestWorld( 5);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   bin    = commit_create( c, "bin", BGOnTile( 0, 0, 0));
   nails  = commit_create( c, "nails_30", BGIn( bin));
   lock   = commit_create( c, "lock", BGOnTile( 2, 0, 0));
   worker = commit_create( c, "worker", BGOnTile( 1, 0, 0));
   g = BGPerform( w, c, BGActionMake( "take_some", worker, nails, BGNoEntity), 10, &error);
   [s runUntil:BGTimeMake( 10)];
   handful = [g idFor:[g proposals][ 0].handle];
   a       = BGNoEntity;
   for( i = 0; i < 5; i++)
   {
      g = BGPerform( w, c, BGActionMake( "drive", worker, handful, lock), 0, &error);
      [s runUntil:BGTimeMake( [w time].ms + 5000)];
      a = [g idFor:[g proposals][ 0].handle];
   }
   BG_CHECK( [w entitiesAt:lock form:BGLocationPartOf into:parts max:8] == 4);
   BG_CHECK( ! strcmp( status_of( w, a), "\"failed\""));
   BG_CHECK( [w unitsOf:handful] == 6);
}


/* Two stages, walked away from and come back to: progress is kept across a
 * suspension, and resuming runs only what is left. */
static void   test_stages_and_suspension( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGActivities      *activities;
   BGProposalGroup   *g;
   BGEntityID        lock;
   BGEntityID        worker;
   BGEntityID        nail;
   BGEntityID        a;
   NSString          *error;
   int64_t           v;
   const BGActivity  *record;

   w          = BGTestWorld( 5);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   lock   = commit_create( c, "lock", BGOnTile( 2, 0, 0));
   worker = commit_create( c, "worker", BGOnTile( 1, 0, 0));
   nail   = commit_create( c, "iron_nail", BGPartOf( lock, "wedge", 0));

   /* pry it out: 3 s loosening, 2 s pulling */
   g = BGPerform( w, c, BGActionMake( "pry_out", worker, nail, BGNoEntity), 0, &error);
   BG_CHECK( g != nil);
   [s runUntil:BGTimeMake( 1000)];
   a = [g idFor:[g proposals][ 0].handle];
   BG_CHECK( ! strcmp( status_of( w, a), "\"running\""));

   /* a second in, the worker walks away: the prying goes on while it walks
    * (hands and legs), and is suspended when it arrives out of reach, with
    * the two seconds kept */
   BG_CHECK( BGPerform( w, c, BGActionMake( "walk_west", worker, BGNoEntity, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 1999)];
   BG_CHECK( ! strcmp( status_of( w, a), "\"running\"") && [w locationOf:worker].x == 1);
   /* one walk at a time: its legs are busy */
   BG_CHECK( ! BGPerform( w, c, BGActionMake( "walk_east", worker, BGNoEntity, BGNoEntity), 0, &error) &&
             [error rangeOfString:@"its legs are busy with activity"].location != NSNotFound);
   [s runUntil:BGTimeMake( 2000)];
   record = [w record:[w kindNamed:"Activity"] for:a];
   BG_CHECK( [w locationOf:worker].x == 0);
   BG_CHECK( ! strcmp( status_of( w, a), "\"suspended\"") && record->progress == 2000 && record->stage == 0);
   BG_CHECK( ! [activities resume:a error:&error] && [error rangeOfString:@"out of reach"].location != NSNotFound);
   [s runUntil:BGTimeMake( 10000)];
   BG_CHECK( [w getField:"Body.toolMarks" of:nail value:&v] && v == 0);      /* nothing happened meanwhile */

   /* back, and resumed at 11 s: what is left of the loosening, then 2 s of pulling */
   BGPerform( w, c, BGActionMake( "walk_east", worker, BGNoEntity, BGNoEntity), 0, &error);
   [s runUntil:BGTimeMake( 11000)];
   BG_CHECK( [activities resume:a error:&error] != nil);
   [s runUntil:BGTimeMake( 11001)];
   record = [w record:[w kindNamed:"Activity"] for:a];
   BG_CHECK( record->due == 11000 + 1000);
   [s runUntil:BGTimeMake( 12000)];
   BG_CHECK( [w getField:"Body.toolMarks" of:nail value:&v] && v == 1);      /* loosened */
   record = [w record:[w kindNamed:"Activity"] for:a];
   BG_CHECK( record->stage == 1 && record->due == 12000 + 2000);
   [s runUntil:BGTimeMake( 14001)];
   BG_CHECK( ! strcmp( status_of( w, a), "\"completed\""));
   BG_CHECK( [w locationOf:nail].form == BGLocationHeldBy && [w locationOf:nail].place == worker);

   /* and suspended by choice, then resumed: the same accounting */
   g = BGPerform( w, c, BGActionMake( "drive", worker, nail, lock), 0, &error);
   [s runUntil:BGTimeMake( 15001)];
   a = [g idFor:[g proposals][ 0].handle];
   BG_CHECK( [activities suspend:a because:@"a break" error:&error] != nil);
   [s runUntil:BGTimeMake( 20000)];
   BG_CHECK( [activities resume:a error:&error] != nil);
   [s runUntil:BGTimeMake( 20001)];
   record = [w record:[w kindNamed:"Activity"] for:a];
   BG_CHECK( record->progress == 1000 && record->due == 20000 + 3000);
}


/* --- the command interface ------------------------------------------------- */

static NSString   *session( NSString *world, NSArray *commands, uint64_t *hash)
{
   BGPlay            *play;
   NSMutableString   *out;
   NSUInteger        i;

   play = [BGPlay playWorld:world seed:42 error:NULL];
   out  = [NSMutableString stringWithString:[play takeOutput]];
   for( i = 0; i < [commands count]; i++)
   {
      [play command:[commands objectAtIndex:i]];
      [out appendString:[play takeOutput]];
   }
   *hash = [[play world] stateHash];
   return( out);
}


/* A session in the workshop: look, take five nails, walk, drive one into the
 * lock, inspect it, and ask why. The same commands give the same world. */
static void   test_play( void)
{
   NSArray    *commands;
   NSString   *out;
   NSString   *again;
   uint64_t   h1;
   uint64_t   h2;

   commands = [NSArray arrayWithObjects:@"look", @"menu", @"do 1", @"menu", @"do 5 5", @"walk w", @"walk e", @"menu",
                                        @"do 1", @"idle", @"inspect 11", @"why 11", @"knows", @"walk n", @"walk n",
                                        @"walk n", @"walk n", @"walk n", @"look", @"knows", @"hash", nil];
   out   = session( @"workshop", commands, &h1);
   again = session( @"workshop", commands, &h2);
   BG_CHECK( h1 == h2);
   BG_CHECK( [out isEqualToString:again]);
   /* the map, from what the worker knows: the smith (A), the bin (u), itself (@), the lock (m) */
   BG_CHECK( [out rangeOfString:@"Au@m"].location != NSNotFound);
   /* the menu comes from the knowledge view: the nails only once it has looked into the bin */
   BG_CHECK( [out rangeOfString:@" 1. look_in item R2 (#Container)"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"you notice: R5: #Stack, at (3, 4)"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@" 5. take_some item R5 (#Stack)"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"you notice: R6: #Stack, at (4, 4)"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@" 1. drive item R6 (#Stack) destination R3 (#Assembly)"].location != NSNotFound);
   /* the drive completes as an activity, and the nail it split off is in the lock, bent */
   BG_CHECK( [out rangeOfString:@"activity 10: drive completes"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"Body.bent=true"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"at partOf(3, wedge, 0)"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"R7 #Body, seen at 6000ms, truth 11"].location != NSNotFound);
   /* why: the move into the lock, in the drive's completion, because the worker started the drive */
   BG_CHECK( [out rangeOfString:@"moved 11 to partOf(3, wedge, 0) at boundary 10, in \"activity 10: drive completes\"\n"
                                @"because:\n  created 10 activity at boundary 9, in \"4: drive item 7 destination 3\""].location
             != NSNotFound);
   /* walks are activities of a second each: two of them, so the drive is activity 10, and done at 6 s */
   BG_CHECK( [out rangeOfString:@"activity 9: walk_east completes"].location != NSNotFound);
   /* KNOWLEDGE.md Scenario 3's check 1: the map renders from the knowledge
    * store, and what is remembered carries its age, never refreshed: the
    * nails in the bin, last seen when it looked in, at the start */
   BG_CHECK( [out rangeOfString:@"R5 #Stack in R2, as you saw it 11s ago"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"R5 #Stack, seen at 0ms, truth 2"].location != NSNotFound);
   /* the map's edge: the step off it fails when it would arrive */
   BG_CHECK( [out rangeOfString:@"is off the map"].location != NSNotFound);
   if( [out rangeOfString:@"is off the map"].location == NSNotFound)
      fprintf( stderr, "%s\n", [out UTF8String]);
}


/* Talking in a session: the worker looks into the bin, steps over by the
 * smith, tells the smith where the nails are, asks where they are and who
 * said so, then takes them and says they are still in the bin: a lie. The
 * smith answers through agency. */
static void   test_play_talk( void)
{
   NSArray    *commands;
   NSString   *out;
   NSString   *again;
   uint64_t   h1;
   uint64_t   h2;

   commands = [NSArray arrayWithObjects:@"do 1", @"walk w", @"tell R4 R5", @"ask R4 where R5", @"ask R4 who R5",
                                        @"menu", @"do 5", @"tell R4 R5 in R2", @"knows", @"knows 5", @"tell R4",
                                        @"ask R4 where R99", @"help", nil];
   out   = session( @"workshop", commands, &h1);
   again = session( @"workshop", commands, &h2);
   BG_CHECK( h1 == h2);
   BG_CHECK( [out isEqualToString:again]);
   /* told, from what the worker saw */
   BG_CHECK( [out rangeOfString:@"said: 4, other 5, #IsIn & { what: #Stack"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"attribution: #Saw & { sure: 30 } }"].location != NSNotFound);
   /* asked, the smith answers, naming the worker by its coat */
   BG_CHECK( [out rangeOfString:@"said: 4, other 5, #WhereIs"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"you notice: R4 says to R1: #IsIn"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"#Heard & { from: #Agent & {"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"coat: \"blue\""].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"said: 4, other 5, #WhoToldYou"].location != NSNotFound);
   /* the lie: the worker knows it didn't believe it, and the developer sees it made up */
   BG_CHECK( [out rangeOfString:@"(not believed)"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"truly made up by 4"].location != NSNotFound);
   /* what it can't say */
   BG_CHECK( [out rangeOfString:@"Tell whom what?"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"Ask whom, where or who, of what?"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"ask <R> where|who <R>, tell <R> <R> [in <R>]"].location != NSNotFound);
}


/* --- knowledge ------------------------------------------------------------- */

static uint32_t   referent_of( BGKnowledgeStore *store, BGEntityID truth)
{
   NSUInteger   i;

   for( i = 0; i < [store count]; i++)
      if( [store referentAt:i]->truth == truth)
         return( [store referentAt:i]->id);
   return( 0);
}


static BOOL   believed_menu_has( BGWorld *w, BGKnowledgeStore *store, NSString *entry)
{
   BGMenu       *menu;
   NSUInteger   i;

   menu = [BGMenu menuFor:store world:w believed:YES];
   for( i = 0; i < [menu count]; i++)
      if( [[menu describeAt:i] hasPrefix:entry])
         return( YES);
   return( NO);
}


/* KNOWLEDGE.md Scenario 3, in the workshop: the worker looks into the bin,
 * walks away; the smith takes the nails out of sight; back by the bin, the
 * worker still believes them there, the menu offers them, and the attempt
 * corrects the belief. */
static void   test_stale_belief( void)
{
   BGWorld            *w;
   BGWorld            *w2;
   BGCommitter        *c;
   BGScheduler        *s;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGKnowledge        *restored;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   const BGReferent   *nails;
   BGEntityID         h[ 8];
   NSString           *error;
   NSString           *text;
   NSArray            *deferred;
   uint32_t           rbin;
   uint32_t           rnails;
   uint64_t           position;
   int64_t            taken;
   int                i;

   w          = BGTestWorld( 11);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [c submit:BGWorkshopSetup( NO, h)];
   [s runUntil:BGTimeMake( 1)];
   store = [knowledge storeOf:4];

   /* the worker sees the bin, the lock, and the smith; not what is in the bin */
   rbin = referent_of( store, 1);
   BG_CHECK( rbin && referent_of( store, 3) && referent_of( store, 5) && ! referent_of( store, 2));
   BG_CHECK( [store referent:[store selfReferent]]->truth == 4);
   BG_CHECK( (believed_menu_has( w, store, [NSString stringWithFormat:@"look_in item R%u", rbin])));

   /* it looks in, and knows the nails are there */
   g = BGPerformBelieved( w, c, store, BGActionMake( "look_in", [store selfReferent], rbin, BGNoEntity), 0, &error);
   BG_CHECK( g != nil);
   [s runUntil:BGTimeMake( 2)];
   rnails = referent_of( store, 2);
   BG_CHECK( rnails && [store referent:rnails]->form == BGLocationIn && [store referent:rnails]->container == rbin);

   /* it walks away, out of sight */
   for( i = 0; i < 6; i++)
   {
      BGPerform( w, c, BGActionMake( "walk_east", 4, BGNoEntity, BGNoEntity), 0, &error);
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
   }
   /* the smith takes the nails and walks off */
   taken = [w time].ms;
   BG_CHECK( BGPerform( w, c, BGActionMake( "take", 5, 2, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( [w time].ms + 1000)];
   for( i = 0; i < 5; i++)
   {
      BGPerform( w, c, BGActionMake( "walk_south", 5, BGNoEntity, BGNoEntity), 0, &error);
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
   }
   nails = [store referent:rnails];
   BG_CHECK( nails->present && nails->form == BGLocationIn);           /* it saw none of that */
   BG_CHECK( [store tileSeenAtX:3 y:4] < taken);                        /* nor the bin's tile, since */

   /* back by the bin: it sees the bin, not into it */
   for( i = 0; i < 6; i++)
   {
      BGPerform( w, c, BGActionMake( "walk_west", 4, BGNoEntity, BGNoEntity), 0, &error);
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
   }
   BG_CHECK( [store referent:rnails]->present);
   /* the menu comes from the knowledge view: it offers the nails it remembers */
   BG_CHECK( (believed_menu_has( w, store, [NSString stringWithFormat:@"take_some item R%u", rnails])));
   BG_CHECK( ! [[BGMenu menuFor:4 world:w] count] ||
             [[[BGMenu menuFor:4 world:w] describeAt:0] rangeOfString:@"item 2"].location == NSNotFound);

   /* the attempt: it reaches into the bin, and now knows they are gone */
   g = BGPerformBelieved( w, c, store, BGActionMake( "take_some", [store selfReferent], rnails, BGNoEntity), 5, &error);
   BG_CHECK( g != nil && [[g source] rangeOfString:@"an attempt"].location != NSNotFound);
   [s runUntil:BGTimeMake( [w time].ms + 1)];
   BG_CHECK( ! [store referent:rnails]->present);
   BG_CHECK( ([[store news] containsObject:[NSString stringWithFormat:@"R%u is not where it was", rnails]]));
   BG_CHECK( (! believed_menu_has( w, store, [NSString stringWithFormat:@"take_some item R%u", rnails])));
   /* the world is as it was: the smith has the nails */
   BG_CHECK( [w locationOf:2].form == BGLocationHeldBy && [w locationOf:2].place == 5);

   /* knowledge is saved, and restored the same */
   text = BGSave( w, c, [NSArray arrayWithObject:knowledge]);
   w2   = BGRestore( text, [w contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( text, @"knowledge")];
   BG_CHECK( [[restored dump:4] isEqualToString:[knowledge dump:4]]);
   BG_CHECK( [[restored dump:5] isEqualToString:[knowledge dump:5]]);
}


/* --- agency ---------------------------------------------------------------- */

typedef struct
{
   BGWorld       *world;
   BGAgency      *agency;
   BGKnowledge   *knowledge;
   BGEntityID    apprentice;
   NSString      *text;          /* a save at the end, agency and knowledge included */
} BGNailsRun;


/* Whether there is an apprentice, and what it does: sees the smith put the
 * nails in the chest, or is too far off to; it answers when asked, unless it
 * is silent (agency doesn't control it). */
typedef enum
{
   BGNoApprentice = 0,
   BGApprenticeSaw,
   BGApprenticeMissed,
   BGApprenticeSilent,
   BGApprenticeSurly,            /* it saw, and won't help */
   BGStrangerGlimpsed            /* no apprentice; a stranger glimpsed nails in the sack, and says so */
} BGApprentice;


static BGWorld   *restore( NSString *text, BGContent *content, BGCommitter **committer, NSString **error);

static NSUInteger   log_count( BGAgency *agency, BGEntityID agent, NSString *text);

#define BG_EIGHT   (8 * 3600000LL)        /* 8:00, the shift's start */


/* AGENCY.md Scenario 1, as "the missing nails". The worker looks into the bin
 * and walks off past the crate; the smith takes the nails away (with an
 * apprentice, into the chest, at the bottom of the map, and the apprentice
 * then comes over by the crate); then agency takes the worker over,
 * committed to wedging the lock. `saveAt`, if not 0, is when to save,
 * restore into a fresh world, with fresh knowledge and agency from the
 * save, and carry on there. */
/* `curious`: the worker's curiosity, with spare nails in a sack in the far
 * corner, which the worker has seen; -1, no sack. */
static BGNailsRun   missing_nails( BOOL spares, BOOL omniscient, BGApprentice apprentice, int64_t saveAt,
                                   int64_t shiftUntil, int curious)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGActivities      *activities;
   BGKnowledge       *knowledge;
   BGAgency          *agency;
   BGProposalGroup   *g;
   BGEntityID        h[ 8];
   BGEntityID        crate;
   BGEntityID        ch;
   BGEntityID        chest;
   BGEntityID        helper;
   BGEntityID        sack;
   BGEntityID        sacked;
   NSString          *error;
   NSString          *text;
   BGNailsRun        run;
   int               i;

   w          = BGTestWorld( 13);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:w committer:c knowledge:knowledge] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [knowledge setOmniscient:omniscient];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [s setDecision:agency];
   [c submit:BGWorkshopSetup( NO, h)];
   g  = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the crate"];
   ch = [g create:"crate" key:"crate" at:BGOnTile( 8, 7, 0)];
   if( spares)
      [g create:"nails_4" key:"spare nails" at:BGIn( ch)];
   sacked = BGNoEntity;
   if( curious >= 0)
   {
      sack   = [g create:"sack" key:"sack" at:BGOnTile( 13, 8, 0)];
      sacked = [g create:"nails_4" key:"spare nails" at:BGIn( sack)];
      [g set:"Agent.curious" of:BGWhole( 4) to:curious];
   }
   if( shiftUntil > BG_EIGHT)
   {
      /* breakfast at 7:30, before the shift */
      [g set:"Agent.fed" of:BGWhole( 4) to:100];
      [g set:"Agent.fedAt" of:BGWhole( 4) to:BG_EIGHT - 1800000];
   }
   chest  = BGNoEntity;
   helper = BGNoEntity;
   if( apprentice == BGStrangerGlimpsed)
      helper = [g create:"stranger" key:"stranger" at:BGOnTile( 13, 9, 0)];
   else if( apprentice)
   {
      chest  = [g create:"chest" key:"chest" at:BGOnTile( 2, 12, 0)];
      helper = [g create:"apprentice" key:"apprentice"
                      at:apprentice == BGApprenticeMissed ? BGOnTile( 12, 13, 0) : BGOnTile( 3, 13, 0)];
      if( apprentice == BGApprenticeSurly)
         [g set:"Agent.helpful" of:BGWhole( helper) to:-25];
   }
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   crate  = [g idFor:ch];
   chest  = [g idFor:chest];
   helper = [g idFor:helper];
   sacked = sacked ? [g idFor:sacked] : BGNoEntity;
   (void) crate;
   if( apprentice && apprentice != BGApprenticeSilent && apprentice != BGStrangerGlimpsed)
      [agency control:helper];

   /* the worker looks into the bin, then walks off east */
   BGPerform( w, c, BGActionMake( "look_in", 4, 1, BGNoEntity), 0, &error);
   [s runUntil:BGTimeMake( 2)];
   for( i = 0; i < 6; i++)
   {
      BGPerform( w, c, BGActionMake( "walk_east", 4, BGNoEntity, BGNoEntity), 0, &error);
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
   }
   /* the smith takes the nails and walks off south */
   BGPerform( w, c, BGActionMake( "take", 5, 2, BGNoEntity), 0, &error);
   [s runUntil:BGTimeMake( [w time].ms + 1000)];
   for( i = 0; i < 5; i++)
   {
      BGPerform( w, c, BGActionMake( "walk_south", 5, BGNoEntity, BGNoEntity), 0, &error);
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
   }
   if( apprentice == BGStrangerGlimpsed)
   {
      /* the stranger looks into the sack, comes over, and tells the worker
       * nails are there; it only glimpsed them, and says so (sure: 5), so
       * the worker doesn't believe it */
      BGKnowledgeStore   *seen;
      NSString           *claim;
      BGAction           say;

      BG_CHECK( BGPerform( w, c, BGActionMake( "look_in", helper, [g idFor:sack], BGNoEntity), 0, &error) != nil);
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
      g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the stranger comes over"];
      [g move:BGWhole( helper) to:BGOnTile( 11, 4, 0)];
      [c submit:g];
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
      seen  = [knowledge storeOf:helper];
      claim = [seen claimAbout:referent_of( seen, sacked)];
      claim = [claim stringByReplacingOccurrencesOfString:@"sure: 30" withString:@"sure: 5"];
      BG_CHECK( claim != nil);
      say         = BGActionMake( "say", helper, 4, BGNoEntity);
      say.content = [w intern:[claim UTF8String]];
      BG_CHECK( BGPerform( w, c, say, 0, &error) != nil);
      [s runUntil:BGTimeMake( [w time].ms + 3000)];
   }
   else if( apprentice)
   {
      /* on into the chest, where the apprentice may see it */
      for( i = 0; i < 2; i++)
      {
         BGPerform( w, c, BGActionMake( "walk_south", 5, BGNoEntity, BGNoEntity), 0, &error);
         [s runUntil:BGTimeMake( [w time].ms + 1000)];
      }
      BG_CHECK( BGPerform( w, c, BGActionMake( "put_in", 5, 2, chest), 0, &error) != nil);
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
      /* the apprentice comes over, by the crate */
      g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the apprentice comes over"];
      [g move:BGWhole( helper) to:BGOnTile( 10, 8, 0)];
      [c submit:g];
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
   }

   /* the shift: agency has the worker now; or, from 8:00, the worker's
    * employment does (the routine generator) */
   if( shiftUntil)
      BG_CHECK( [agency undertake:4 goal:"wedge_lock" from:shiftUntil > BG_EIGHT ? BG_EIGHT : 0 until:shiftUntil
                           source:"employment"]);
   else
      BG_CHECK( [agency commit:4 toGoal:"wedge_lock"]);
   [s runUntil:BGTimeMake( [w time].ms + 1)];
   if( saveAt)
   {
      [s runUntil:BGTimeMake( saveAt)];
      text  = BGSave( w, c, [NSArray arrayWithObjects:knowledge, agency, nil]);
      error = nil;
      w     = restore( text, [w contentBuild], &c, &error);
      BG_CHECK( w != nil);
      activities = [BGActivities activitiesWithWorld:w committer:c];
      knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
      agency     = [[[BGAgency alloc] initWithWorld:w committer:c knowledge:knowledge] autorelease];
      s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
      [knowledge setOmniscient:omniscient];
      [knowledge restoreSavedState:BGSavedDomainState( text, @"knowledge")];
      [agency restoreSavedState:BGSavedDomainState( text, @"agency")];
      [s setActivities:activities];
      [s setPerception:knowledge];
      [s setDecision:agency];
      BG_CHECK( [BGSave( w, c, [NSArray arrayWithObjects:knowledge, agency, nil]) isEqualToString:text]);
   }
   [s runUntil:BGTimeMake( shiftUntil > BG_EIGHT ? BG_EIGHT + 120000 : 120000)];
   run.world      = w;
   run.agency     = agency;
   run.knowledge  = knowledge;
   run.apprentice = helper;
   run.text   = BGSave( w, c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


static BOOL   happened( BGWorld *w, const char *kind, BGEntityID actor, BGEntityID other)
{
   const BGEvent   *ev;
   NSUInteger      i;

   for( i = 0; i < [w eventCount]; i++)
   {
      ev = [w eventAt:i];
      if( ! strcmp( ev->kind, kind) && ev->actor == actor && ev->other == other)
         return( YES);
   }
   return( NO);
}


static uint64_t   first_at( BGWorld *w, const char *kind, BGEntityID actor, BGEntityID other)
{
   const BGEvent   *ev;
   NSUInteger      i;

   for( i = 0; i < [w eventCount]; i++)
   {
      ev = [w eventAt:i];
      if( ! strcmp( ev->kind, kind) && ev->actor == actor && ev->other == other)
         return( ev->index);
   }
   return( 0);
}


static BOOL   wedged( BGWorld *w)
{
   BGEntityID   parts[ 4];

   return( [w entitiesAt:3 form:BGLocationPartOf into:parts max:4] > 0);
}


static BOOL   logged( BGAgency *agency, NSString *text)
{
   NSArray      *log;
   NSUInteger   i;

   log = [agency logOf:4];
   for( i = 0; i < [log count]; i++)
      if( [[log objectAtIndex:i] rangeOfString:text].location != NSNotFound)
         return( YES);
   return( NO);
}


/* the referent of the agent's that tracks the entity, present or not; developer-only */
static uint32_t   tracks( BGNailsRun run, BGEntityID agent, BGEntityID truth)
{
   BGKnowledgeStore   *store;
   NSUInteger         i;

   store = [run.knowledge storeOf:agent];
   for( i = 0; i < [store count]; i++)
      if( [store referentAt:i]->truth == truth)
         return( [store referentAt:i]->id);
   return( 0);
}


static NSUInteger   log_index( BGAgency *agency, BGEntityID agent, NSString *text);


static void   test_missing_nails( void)
{
   BGNailsRun   base;
   BGNailsRun   again;
   BGNailsRun   spares;
   BGNailsRun   seer;
   BGNailsRun   resumed;
   BGNailsRun   incurious;
   BGNailsRun   curious;
   BGNailsRun   glimpsed;
   BGEntityID   crate;
   NSArray      *full;
   NSArray      *rest;

   crate = 7;           /* after the workshop's six */

   /* base: the bin first (believed), then the crate; nowhere left: dropped, with why */
   base = missing_nails( NO, NO, BGNoApprentice, 0, 0, -1);

   BG_CHECK( happened( base.world, "attempted", 4, 1));
   BG_CHECK( happened( base.world, "looked", 4, crate));
   BG_CHECK( first_at( base.world, "attempted", 4, 1) < first_at( base.world, "looked", 4, crate));
   BG_CHECK( logged( base.agency, @"[wedge the lock] drive a nail in: have nails first"));
   BG_CHECK( logged( base.agency, @"[have nails] fetch nails: take_some"));
   BG_CHECK( logged( base.agency, @"[have nails] fetch nails no longer holds"));
   BG_CHECK( logged( base.agency, @"[have nails] search for nails: look_in"));
   BG_CHECK( logged( base.agency, @"[have nails] nothing I know of will do: impossible for now"));
   BG_CHECK( logged( base.agency, @"[wedge the lock] drive a nail in has failed: it needed have nails"));
   BG_CHECK( logged( base.agency, @"[wedge the lock] nothing I know of will do: impossible for now"));
   BG_CHECK( ! wedged( base.world) && [base.agency mindOf:4]->nintentions == 0);

   /* the same run is the same, decisions and all */
   again = missing_nails( NO, NO, BGNoApprentice, 0, 0, -1);
   BG_CHECK( [again.world stateHash] == [base.world stateHash]);
   BG_CHECK( [[again.agency logOf:4] isEqualToArray:[base.agency logOf:4]]);
   BG_CHECK( [again.text isEqualToString:base.text]);

   /* A: spare nails in the crate: found, taken, and the lock wedged; wedging was the intention throughout */
   spares = missing_nails( YES, NO, BGNoApprentice, 0, 0, -1);
   BG_CHECK( happened( spares.world, "attempted", 4, 1));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] back to it: have nails is done"));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] drive a nail in: drive"));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] done"));
   /* the spare nails are a thing of their own, not the bin's missing ones found again: they look different */
   BG_CHECK( tracks( spares, 4, 2) && tracks( spares, 4, 8) && tracks( spares, 4, 2) != tracks( spares, 4, 8));
   BG_CHECK( wedged( spares.world));

   /* B: the omniscient stub knows better, and the behaviour shows it: straight to the crate */
   seer = missing_nails( YES, YES, BGNoApprentice, 0, 0, -1);
   BG_CHECK( ! happened( seer.world, "attempted", 4, 1));
   BG_CHECK( ! logged( seer.agency, @"search for nails"));
   BG_CHECK( wedged( seer.world));
   BG_CHECK( [[seer.agency logOf:4] count] < [[spares.agency logOf:4] count]);

   /* A (AGENCY.md's): spares in a sack in the far corner, which the worker has
    * seen. The search looks into two places, the bin and the crate, and
    * gives up; a curious worker's goes on, to the sack, and finds them */
   incurious = missing_nails( NO, NO, BGNoApprentice, 0, 0, 0);
   BG_CHECK( happened( incurious.world, "looked", 4, crate));
   BG_CHECK( ! happened( incurious.world, "looked", 4, crate + 1));
   BG_CHECK( logged( incurious.agency, @"[have nails] nothing I know of will do: impossible for now"));
   BG_CHECK( ! wedged( incurious.world));
   /* AGENCY.md §5, the places to look ordered by the belief that the thing
    * is there: a stranger, barely sure, says nails are in the far sack; the
    * worker doesn't believe it (it doesn't go to fetch them from there),
    * but when the bin it believed held nails is empty, its search goes to
    * the sack first, before the nearer crate, and finds them */
   glimpsed = missing_nails( NO, NO, BGStrangerGlimpsed, 0, 0, 0);
   BG_CHECK( log_index( glimpsed.agency, 4, @"search for nails: ") != NSNotFound &&
             log_index( glimpsed.agency, 4, @"search for nails: ") ==
             log_index( glimpsed.agency, 4, @"search for nails: walk_east, toward R7 at (13, 8)"));
   BG_CHECK( log_index( glimpsed.agency, 4, @"fetch nails: walk_east, toward R7") == NSNotFound);
   BG_CHECK( happened( glimpsed.world, "looked", 4, crate + 1));
   BG_CHECK( ! happened( glimpsed.world, "looked", 4, crate) ||
             first_at( glimpsed.world, "looked", 4, crate + 1) < first_at( glimpsed.world, "looked", 4, crate));
   BG_CHECK( wedged( glimpsed.world));

   curious = missing_nails( NO, NO, BGNoApprentice, 0, 0, 50);
   BG_CHECK( happened( curious.world, "looked", 4, crate));
   BG_CHECK( happened( curious.world, "looked", 4, crate + 1));
   BG_CHECK( first_at( curious.world, "looked", 4, crate) < first_at( curious.world, "looked", 4, crate + 1));
   BG_CHECK( wedged( curious.world));

   /* saved mid-search, mid-stride (a boundary the run has anyway: the walk
    * toward the crate just committed), the commitment and the subgoal stacked,
    * fetching passed over: restored, the agent carries on exactly as it would
    * have */
   resumed = missing_nails( YES, NO, BGNoApprentice, 20005, 0, -1);
   BG_CHECK( [resumed.world stateHash] == [spares.world stateHash]);
   BG_CHECK( [resumed.text isEqualToString:spares.text]);
   full = [spares.agency logOf:4];
   rest = [resumed.agency logOf:4];
   BG_CHECK( [rest count] > 0 && [rest count] < [full count]);
   BG_CHECK( [rest count] <= [full count] &&
             [rest isEqualToArray:[full subarrayWithRange:NSMakeRange( [full count] - [rest count], [rest count])]]);
}


static BOOL   logged_by( BGAgency *agency, BGEntityID agent, NSString *text)
{
   NSArray      *log;
   NSUInteger   i;

   log = [agency logOf:agent];
   for( i = 0; i < [log count]; i++)
      if( [[log objectAtIndex:i] rangeOfString:text].location != NSNotFound)
         return( YES);
   return( NO);
}


static const BGReferent   *believed( BGNailsRun run, BGEntityID agent, BGEntityID truth)
{
   BGKnowledgeStore   *store;
   NSUInteger         i;

   store = [run.knowledge storeOf:agent];
   for( i = 0; i < [store count]; i++)
      if( [store referentAt:i]->truth == truth && [store referentAt:i]->present)
         return( [store referentAt:i]);
   return( NULL);
}


/* AGENCY.md Scenario 1's "ask a coworker", with KNOWLEDGE.md's event
 * perception and claims: the search fails, and the worker asks the
 * apprentice, who may have seen the smith put the nails in the chest. */
static void   test_asking( void)
{
   BGNailsRun         saw;
   BGNailsRun         again;
   BGNailsRun         missed;
   BGNailsRun         silent;
   BGNailsRun         resumed;
   BGNailsRun         seer;
   BGNailsRun         surly;
   const BGReferent   *nails;
   const BGReferent   *chest;
   BGKnowledgeStore   *store;
   NSArray            *full;
   NSArray            *rest;
   BGEntityID         c;

   /* it saw: told where, the worker goes to a chest it has never seen, and wedges the lock */
   saw = missing_nails( NO, NO, BGApprenticeSaw, 0, 0, -1);
   c   = 8;                 /* the crate is 7 */
   BG_CHECK( logged( saw.agency, @"[have nails] ask where nails are: say R"));
   BG_CHECK( logged( saw.agency, @": #WhereIs"));
   BG_CHECK( logged( saw.agency, @"answered: #IsIn"));
   BG_CHECK( logged_by( saw.agency, saw.apprentice, @"answering: say R"));
   BG_CHECK( happened( saw.world, "said", 4, saw.apprentice) && happened( saw.world, "said", saw.apprentice, 4));
   BG_CHECK( first_at( saw.world, "looked", 4, 7) < first_at( saw.world, "said", 4, saw.apprentice));
   BG_CHECK( ! happened( saw.world, "looked", 4, c));
   BG_CHECK( wedged( saw.world));
   /* the apprentice saw the nails go in: believed in the chest, not told */
   nails = believed( saw, saw.apprentice, 2);
   chest = believed( saw, saw.apprentice, c);
   BG_CHECK( nails && chest && nails->form == BGLocationIn && nails->container == chest->id && ! nails->toldBy);
   /* the worker was told of the chest, then saw it: what it was told is seen
    * true, and it trusts the apprentice more */
   chest = believed( saw, 4, c);
   store = [saw.knowledge storeOf:4];
   BG_CHECK( chest && ! chest->toldBy && [store testimonyCount] == 1);
   BG_CHECK( [store testimonyAt:0]->container == chest->id && [store testimonyAt:0]->settled == 1 &&
             [store testimonyAt:0]->attribution == BGSaw);
   BG_CHECK( [store trustIn:[store testimonyAt:0]->source] == BG_TRUST + BG_CONFIRMED);
   BG_CHECK( [[saw.knowledge dump:4] rangeOfString:@"seen true; truly seen by"].location != NSNotFound);
   BG_CHECK( [[saw.knowledge dump:4] rangeOfString:@"said R"].location != NSNotFound);

   again = missing_nails( NO, NO, BGApprenticeSaw, 0, 0, -1);
   BG_CHECK( [again.world stateHash] == [saw.world stateHash]);
   BG_CHECK( [again.text isEqualToString:saw.text]);
   BG_CHECK( [[again.agency logOf:4] isEqualToArray:[saw.agency logOf:4]]);

   /* it didn't see: it says so, and the goal is dropped */
   missed = missing_nails( NO, NO, BGApprenticeMissed, 0, 0, -1);
   BG_CHECK( logged( missed.agency, @"answered: #DontKnow"));
   BG_CHECK( logged( missed.agency, @"[wedge the lock] nothing I know of will do: impossible for now"));
   BG_CHECK( ! wedged( missed.world));
   BG_CHECK( ! believed( missed, missed.apprentice, 2));

   /* nobody answers: the worker waits a while, then gives up on it */
   silent = missing_nails( NO, NO, BGApprenticeSilent, 0, 0, -1);
   BG_CHECK( logged( silent.agency, @"did not answer"));
   BG_CHECK( ! happened( silent.world, "said", silent.apprentice, 4) && ! wedged( silent.world));

   /* saved while it waits, the wait goes on in the restored world, and ends as it would have */
   resumed = missing_nails( NO, NO, BGApprenticeSilent, 30006, 0, -1);
   BG_CHECK( [resumed.world stateHash] == [silent.world stateHash]);
   BG_CHECK( [resumed.text isEqualToString:silent.text]);
   full = [silent.agency logOf:4];
   rest = [resumed.agency logOf:4];
   BG_CHECK( [rest count] > 0 && [rest count] < [full count] &&
             [rest isEqualToArray:[full subarrayWithRange:NSMakeRange( [full count] - [rest count], [rest count])]]);
   BG_CHECK( [rest count] && [[rest objectAtIndex:0] rangeOfString:@"t=35005ms"].location != NSNotFound &&
             [[rest objectAtIndex:0] rangeOfString:@"did not answer"].location != NSNotFound);

   /* asked, a surly apprentice weighs answering at less than nothing, and says it won't: the goal is dropped */
   surly = missing_nails( NO, NO, BGApprenticeSurly, 0, 0, -1);
   BG_CHECK( logged_by( surly.agency, surly.apprentice, @"asked by R"));
   BG_CHECK( logged_by( surly.agency, surly.apprentice, @"worth -5, refusing"));
   BG_CHECK( logged_by( surly.agency, surly.apprentice, @"refusing: say R"));
   BG_CHECK( logged( surly.agency, @"answered: #WontSay"));
   BG_CHECK( logged( surly.agency, @"[wedge the lock] nothing I know of will do: impossible for now"));
   BG_CHECK( ! wedged( surly.world));
   /* a helpful one weighed it at the trust in the asker */
   BG_CHECK( logged_by( saw.agency, saw.apprentice, @"worth +20, answering"));

   /* the omniscient stub needs no one: straight to the chest */
   seer = missing_nails( NO, YES, BGApprenticeSaw, 0, 0, -1);
   BG_CHECK( ! happened( seer.world, "said", 4, seer.apprentice));
   BG_CHECK( ! happened( seer.world, "attempted", 4, 1) && wedged( seer.world));
}


/* AGENCY.md Scenario 1 as written: the worker's shift (an employment
 * commitment from 8:00) is what puts wedging the lock in its mind: the
 * routine generator, at 8:00, nothing else to weigh it against. */
static void   test_routine( void)
{
   BGNailsRun   shift;
   BGNailsRun   fruitless;
   BGNailsRun   closing;
   BGNailsRun   hurried;
   BGNailsRun   resumed;
   NSArray      *log;
   NSArray      *full;
   NSArray      *rest;

   /* the shift, 8:00 to 16:00: at 8:00, and not before, the worker takes up
    * wedging the lock, worth its duty; no urgency yet */
   shift = missing_nails( YES, NO, BGNoApprentice, 0, BG_EIGHT + 8 * 3600000LL, -1);
   log   = [shift.agency logOf:4];
   BG_CHECK( [log count] && [[log objectAtIndex:0] rangeOfString:@"t=28800000ms [-] weighing wedge the lock: +20 "
                                                                 @"(employment, duty +20, urgency +0) against nothing: "
                                                                 @"switching"].location != NSNotFound);
   BG_CHECK( logged_by( shift.agency, 4, @"t=28800000ms [wedge the lock] drive a nail in: have nails first"));
   BG_CHECK( wedged( shift.world));
   /* done, it is settled for the shift: not taken up again */
   BG_CHECK( log_count( shift.agency, 4, @"switching") == 1);

   /* without spares, impossible, and settled too: not taken up again and again */
   fruitless = missing_nails( NO, NO, BGNoApprentice, 0, BG_EIGHT + 8 * 3600000LL, -1);
   BG_CHECK( logged_by( fruitless.agency, 4, @"[wedge the lock] nothing I know of will do: impossible for now"));
   BG_CHECK( log_count( fruitless.agency, 4, @"switching") == 1 && ! wedged( fruitless.world));

   /* a shift of five seconds closes mid-search: the commitment is over, and
    * what it needed with it */
   closing = missing_nails( YES, NO, BGNoApprentice, 0, BG_EIGHT + 5000, -1);
   BG_CHECK( logged_by( closing.agency, 4, @"t=28805000ms [have nails] wedge the lock is over: its window has closed"));
   BG_CHECK( ! wedged( closing.world) && [closing.agency mindOf:4]->nintentions == 0);

   /* urgency rises toward the deadline: a window from 0 to 40 s, taken up
    * at 12 s, three tenths of the way: 6 of 20 */
   hurried = missing_nails( YES, NO, BGNoApprentice, 0, 40000, -1);
   BG_CHECK( logged_by( hurried.agency, 4, @"t=12003ms [-] weighing wedge the lock: +26 (employment, duty +20, urgency +6)"));

   /* saved mid-shift, restored, the same end */
   resumed = missing_nails( YES, NO, BGNoApprentice, BG_EIGHT + 6001, BG_EIGHT + 8 * 3600000LL, -1);
   BG_CHECK( [resumed.world stateHash] == [shift.world stateHash]);
   BG_CHECK( [resumed.text isEqualToString:shift.text]);
   full = [shift.agency logOf:4];
   rest = [resumed.agency logOf:4];
   BG_CHECK( [rest count] > 0 && [rest count] < [full count] &&
             [rest isEqualToArray:[full subarrayWithRange:NSMakeRange( [full count] - [rest count], [rest count])]]);
}


/* AGENCY.md §6: the worker, holding nails of its own and its supper, by the
 * lock. `fed` is how fed it is at 0; `drive`, whether it is driving a nail
 * when agency takes it over; it runs to `until`. */
typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGAgency      *agency;
   BGEntityID    supper;
   int32_t       feltDriving;    /* what it felt while driving */
   NSUInteger    boundaries;
   NSString      *text;
} BGHungerRun;


static BGHungerRun   hunger_run( int64_t fed, BOOL drive, int64_t until)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGActivities      *activities;
   BGKnowledge       *knowledge;
   BGAgency          *agency;
   BGProposalGroup   *g;
   BGEntityID        h[ 8];
   BGEntityID        supper;
   NSString          *error;
   BGHungerRun       run;

   memset( &run, 0, sizeof( run));
   w          = BGTestWorld( 47);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:w committer:c knowledge:knowledge] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [agency setActivities:activities];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [s setDecision:agency];
   [s addDomain:[[[BGBodies alloc] initWithWorld:w] autorelease]];
   [c submit:BGWorkshopSetup( YES, h)];
   [s runUntil:BGTimeMake( 1)];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: supper, and how fed the worker is"];
   supper = [g create:"supper" key:"supper" at:BGHeldBy( 4, 1)];
   [g set:"Agent.fed" of:BGWhole( 4) to:fed];
   [c submit:g];
   [s runUntil:BGTimeMake( 2)];
   run.supper = [g idFor:supper];

   if( drive)
   {
      error = nil;
      BG_CHECK( BGPerform( w, c, BGActionMake( "drive", 4, 7, 3), 0, &error) != nil);
      [s runUntil:BGTimeMake( 1000)];
   }
   [agency control:4];
   if( drive)
   {
      [s runUntil:BGTimeMake( 2000)];
      run.feltDriving = [[knowledge storeOf:4] feels:"hunger"];
   }
   run.boundaries = [s runUntil:BGTimeMake( until)];
   run.world      = w;
   run.knowledge  = knowledge;
   run.agency     = agency;
   run.text       = BGSave( w, c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


static void   test_needs( void)
{
   BGHungerRun        hungry;
   BGHungerRun        busy;
   BGHungerRun        later;
   BGHungerRun        again;
   const BGAgent      *agent;
   BGWorld            *w2;
   BGKnowledge        *restored;
   NSArray            *deferred;
   NSString           *error;
   uint64_t           position;

   /* hungry (70), idle: the needs generator raises eating, worth what it
    * feels, and it eats its supper */
   hungry = hunger_run( 30, NO, 120000);
   BG_CHECK( logged_by( hungry.agency, 4, @"weighing eat something: +35 (hunger +35) against nothing: switching"));
   BG_CHECK( logged_by( hungry.agency, 4, @"[eat something] eat what I have: eat R"));
   BG_CHECK( logged_by( hungry.agency, 4, @"[eat something] done"));
   BG_CHECK( ! [hungry.world isLive:hungry.supper]);
   agent = [hungry.world record:[hungry.world kindNamed:"Agent"] for:4];
   BG_CHECK( agent && agent->fed == 80);
   BG_CHECK( [[hungry.knowledge storeOf:4] feels:"hunger"] == 20);

   /* driving a nail, its hunger (50) dulled by the attention the drive
    * demands: it feels 30, and eats only once the drive is done */
   busy = hunger_run( 50, YES, 120000);
   BG_CHECK( busy.feltDriving == 30);
   BG_CHECK( logged_by( busy.agency, 4, @"t=4002ms [-] weighing eat something: +25 (hunger +25)"));
   BG_CHECK( log_count( busy.agency, 4, @"weighing") == 1);
   BG_CHECK( ! [busy.world isLive:busy.supper]);

   /* fed (80), it grows hungry as time passes, a point every three minutes,
    * computed when read: the body domain wakes it at each band, and at 90
    * minutes it feels 50 and eats; nothing is computed between */
   later = hunger_run( 80, NO, 2 * 3600000LL);
   BG_CHECK( logged_by( later.agency, 4, @"t=5400000ms [-] weighing eat something: +25 (hunger +25)"));
   BG_CHECK( later.boundaries < 12);
   BG_CHECK( ! [later.world isLive:later.supper]);

   /* the same on replay; what it feels is saved */
   again = hunger_run( 80, NO, 2 * 3600000LL);
   BG_CHECK( [again.text isEqualToString:later.text]);
   w2 = BGRestore( later.text, [later.world contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( later.text, @"knowledge")];
   BG_CHECK( [[restored dump:4] isEqualToString:[later.knowledge dump:4]]);
}


/* AGENCY.md §8: each morning the worker is handed nails, and puts them away.
 * Days 1 to 3 (if `practised`) it knows only the crate, two tiles off, and
 * puts them there, watched by a curious apprentice. On day 4 a bin stands
 * right beside it. On day 45 it puts them away again. */
typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGAgency      *agency;
   BGEntityID    crate;
   BGEntityID    bin;
   BGEntityID    apprentice;
   NSString      *text;
} BGHabitRun;


#define BG_DAY   86400000LL

static void   hand_nails( BGWorld *w, BGCommitter *c, BGScheduler *s, BGAgency *agency, int64_t day)
{
   BGProposalGroup   *g;

   [s runUntil:BGTimeMake( day * BG_DAY)];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: in at the door, with nails for the day"];
   [g move:BGWhole( 4) to:BGOnTile( 5, 5, 0)];
   [g create:"nails_10" key:[[NSString stringWithFormat:@"nails of day %lld", (long long) day] UTF8String]
          at:BGHeldBy( 4, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( day * BG_DAY + 1)];
   BG_CHECK( [agency commit:4 toGoal:"put_away"]);
   [s runUntil:BGTimeMake( day * BG_DAY + 10000)];
}


static BGHabitRun   habits_run( BOOL practised)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGActivities      *activities;
   BGKnowledge       *knowledge;
   BGAgency          *agency;
   BGProposalGroup   *g;
   BGEntityID        crate;
   BGEntityID        apprentice;
   BGEntityID        bin;
   BGHabitRun        run;
   int               day;

   memset( &run, 0, sizeof( run));
   w          = BGTestWorld( 53);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:w committer:c knowledge:knowledge] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [agency setActivities:activities];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [s setDecision:agency];
   g          = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the workshop"];
   [g create:"lock" key:"lock" at:BGOnTile( 20, 20, 0)];
   [g create:"lock" key:"lock 2" at:BGOnTile( 21, 20, 0)];
   [g create:"smith" key:"smith" at:BGOnTile( 22, 20, 0)];
   [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   crate      = [g create:"crate" key:"crate" at:BGOnTile( 5, 7, 0)];
   apprentice = [g create:"apprentice" key:"apprentice" at:BGOnTile( 7, 4, 0)];
   [g set:"Agent.curious" of:BGWhole( apprentice) to:100];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   BG_CHECK( [g idFor:BGHandle( 4)] == 4);
   run.crate      = [g idFor:crate];
   run.apprentice = [g idFor:apprentice];
   [agency control:4];

   for( day = 1; practised && day <= 3; day++)
      hand_nails( w, c, s, agency, day);

   /* day 4: a bin beside the worker */
   [s runUntil:BGTimeMake( 4 * BG_DAY - 1000)];
   g   = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a bin, right beside"];
   bin = [g create:"bin" key:"bin" at:BGOnTile( 4, 5, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 4 * BG_DAY - 500)];
   run.bin = [g idFor:bin];
   hand_nails( w, c, s, agency, 4);
   if( practised)
      hand_nails( w, c, s, agency, 45);

   run.world     = w;
   run.knowledge = knowledge;
   run.agency    = agency;
   run.text      = BGSave( w, c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


/* how many nails lie in the container */
static int64_t   nails_in( BGWorld *w, BGEntityID container)
{
   BGEntityID   inside[ 16];
   NSUInteger   n;
   NSUInteger   i;
   int64_t      units;

   n     = [w entitiesAt:container form:BGLocationIn into:inside max:16];
   units = 0;
   for( i = 0; i < n; i++)
      units += [w unitsOf:inside[ i]];
   return( units);
}


static void   test_habits( void)
{
   BGHabitRun         practised;
   BGHabitRun         fresh;
   BGHabitRun         again;
   BGKnowledgeStore   *store;
   const BGFinding    *f;

   practised = habits_run( YES);
   fresh     = habits_run( NO);

   /* a method default: three days of the crate, and on day 4 the worker
    * walks past the bin beside it to the crate; with no habit, the bin */
   BG_CHECK( nails_in( fresh.world, fresh.bin) == 10 && nails_in( fresh.world, fresh.crate) == 0);
   BG_CHECK( nails_in( practised.world, practised.crate) == 40);
   /* the method, habitual too: 10 a day, less a point for each day between: 27 by day 4 */
   BG_CHECK( logged_by( practised.agency, 4, @"scoring put them in a box +2 (habit +2)"));
   BG_CHECK( log_count( practised.agency, 4, @"put them in a box: put_in R") == 5);
   /* on day 45 the habit has faded, and the bin beside it wins */
   BG_CHECK( nails_in( practised.world, practised.bin) == 10);

   /* the apprentice, who watched, believes the worker usually puts things in the crate */
   store = [practised.knowledge storeOf:practised.apprentice];
   f     = [store finding:"#Habit" about:referent_of( store, 4)];
   BG_CHECK( f && f->choice == referent_of( store, practised.crate) && ! strcmp( f->rule, "usually_puts"));
   /* and its breaking it on day 45 is salient: an anomaly */
   BG_CHECK( [[practised.knowledge dump:practised.apprentice] rangeOfString:@"salience 25"].location != NSNotFound);

   /* the same on replay */
   again = habits_run( YES);
   BG_CHECK( [again.text isEqualToString:practised.text]);
}


/* --- the rumour ------------------------------------------------------------ */

/* KNOWLEDGE.md Scenario 1, "the witness and the rumour", in the workshop: the
 * apprentice (Marius) and the neighbour (Nadia) see the smith put the nails
 * in the chest. Day 1: the apprentice tells the carter (Teodor) and the
 * porter (Ulla). Day 2: the carter tells the foreman (Ines), naming the
 * apprentice; the porter tells the foreman, naming no one; the foreman asks
 * the porter who told it. Day 3: the neighbour tells the foreman what it saw.
 * Days are seconds here, and people are brought together by system moves.
 * Questions are the test's; answers are agency's. Single: only the carter
 * tells the foreman. Lie (variant A): the smith keeps the nails, and the
 * apprentice, who saw nothing go in, says it did; the foreman looks in the
 * chest. Decay (variant B): the apprentice walks off, and the foreman asks
 * it on day 10, and again on day 20. */
typedef enum
{
   BGRumourFull = 0,
   BGRumourSingle,
   BGRumourLie,
   BGRumourDecay
} BGRumourVariant;


typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGEntityID    smith;
   BGEntityID    apprentice;
   BGEntityID    carter;
   BGEntityID    porter;
   BGEntityID    neighbour;
   BGEntityID    foreman;
   int32_t       told;           /* the foreman's credence after the carter */
   int32_t       rumoured;       /* ... and the porter: step 5 */
   int32_t       questioned;     /* ... and the porter's answer: step 6 */
   int32_t       corroborated;   /* ... and the neighbour: step 7 */
   NSString      *rumouredDump;
   NSString      *questionedDump;
   NSString      *freshDump;     /* decay: the apprentice's store, just after */
   NSString      *dayOneDump;    /* ... and a day later */
   NSString      *text;          /* a save at the end */
} BGRumour;


typedef struct
{
   BGWorld       *w;
   BGCommitter   *c;
   BGScheduler   *s;
} BGStage;


static void   stage_move( BGStage *st, BGEntityID e, int32_t x, int32_t y)
{
   BGProposalGroup   *g;

   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: someone comes over"];
   [g move:BGWhole( e) to:BGOnTile( x, y, 0)];
   [st->c submit:g];
   [st->s runUntil:BGTimeMake( [st->w time].ms + 1000)];
}


static void   stage_say( BGStage *st, BGEntityID speaker, BGEntityID hearer, NSString *content)
{
   NSString   *error;
   BGAction   action;

   error          = nil;
   action         = BGActionMake( "say", speaker, hearer, BGNoEntity);
   action.content = [st->w intern:[content UTF8String]];
   BG_CHECK( BGPerform( st->w, st->c, action, 0, &error) != nil);
   /* a second to say it, and time for a second's answer */
   [st->s runUntil:BGTimeMake( [st->w time].ms + 3000)];
}


static uint64_t   last_said( BGWorld *w, BGEntityID actor, BGEntityID other)
{
   const BGEvent   *ev;
   NSUInteger      i;

   for( i = [w eventCount]; i > 0; i--)
   {
      ev = [w eventAt:i - 1];
      if( ! strcmp( ev->kind, "said") && ev->actor == actor && ev->other == other)
         return( ev->index);
   }
   return( 0);
}


/* the foreman's credence in the first claim it heard */
static int32_t   credence_of( BGKnowledge *knowledge, BGEntityID agent)
{
   BGKnowledgeStore   *store;

   store = [knowledge storeOf:agent];
   if( ! [store testimonyCount])
      return( BG_PRIOR);
   return( [store credenceThat:[store testimonyAt:0]->thing isIn:[store testimonyAt:0]->container]);
}


static NSString   *const nails_in_chest = @"#IsIn & { what: #Stack & { unit: \"iron_nail\" }, "
                                          @"within: #Container & { material: \"oak\", capacity: 40, "
                                          @"place: #OnTile & { x: 2, y: 20, level: 0 } }, attribution: %@ }";


static BGRumour   rumour( BGRumourVariant variant)
{
   BGStage           st;
   BGActivities      *activities;
   BGKnowledge       *knowledge;
   BGAgency          *agency;
   BGProposalGroup   *g;
   BGEntityID        h[ 8];
   NSString          *error;
   NSString          *where;
   BGRumour          run;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 17);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];

   g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the rumour of the nails"];
   h[ 0] = [g create:"chest" key:"chest" at:BGOnTile( 2, 20, 0)];
   h[ 1] = [g create:"smith" key:"smith" at:BGOnTile( 3, 20, 0)];
   h[ 2] = [g create:"nails_30" key:"nails" at:BGHeldBy( h[ 1], 0)];
   h[ 3] = [g create:"apprentice" key:"apprentice" at:BGOnTile( 5, 21, 0)];
   h[ 4] = [g create:"neighbour" key:"neighbour" at:BGOnTile( 4, 23, 0)];
   h[ 5] = [g create:"carter" key:"carter" at:BGOnTile( 20, 4, 0)];
   h[ 6] = [g create:"porter" key:"porter" at:BGOnTile( 26, 4, 0)];
   h[ 7] = [g create:"foreman" key:"foreman" at:BGOnTile( 20, 28, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   run.world      = st.w;
   run.knowledge  = knowledge;
   run.smith      = [g idFor:h[ 1]];
   run.apprentice = [g idFor:h[ 3]];
   run.neighbour  = [g idFor:h[ 4]];
   run.carter     = [g idFor:h[ 5]];
   run.porter     = [g idFor:h[ 6]];
   run.foreman    = [g idFor:h[ 7]];
   [agency control:run.apprentice];
   [agency control:run.neighbour];
   [agency control:run.carter];
   [agency control:run.porter];
   where = @"#WhereIs & { what: #Stack & { unit: \"iron_nail\" } }";

   /* night: the smith puts the nails in the chest, in sight of the apprentice and the neighbour */
   if( variant != BGRumourLie)
   {
      error = nil;
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "put_in", run.smith, [g idFor:h[ 2]], [g idFor:h[ 0]]), 0,
                           &error) != nil);
   }
   [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];

   if( variant == BGRumourDecay)
   {
      /* the apprentice goes off, out of sight of it all; asked on day 10, it
       * remembers less, and less surely; on day 20, nothing */
      run.freshDump = [knowledge dump:run.apprentice];
      stage_move( &st, run.apprentice, 12, 12);
      [st.s runUntil:BGTimeMake( BG_MEMORY_STEP + 3000)];
      run.dayOneDump = [knowledge dump:run.apprentice];
      [st.s runUntil:BGTimeMake( 10 * BG_MEMORY_STEP + 3000)];
      stage_move( &st, run.foreman, 13, 12);
      stage_say( &st, run.foreman, run.apprentice, where);
      run.told = credence_of( knowledge, run.foreman);
      [st.s runUntil:BGTimeMake( 20 * BG_MEMORY_STEP + 3000)];
      stage_say( &st, run.foreman, run.apprentice, where);
      goto done;
   }

   /* day 1: the apprentice tells the carter, then the porter; lying, it says it saw */
   stage_move( &st, run.apprentice, 20, 5);
   if( variant == BGRumourLie)
      stage_say( &st, run.apprentice, run.carter, [NSString stringWithFormat:nails_in_chest, @"#Saw"]);
   else
      stage_say( &st, run.carter, run.apprentice, where);
   stage_move( &st, run.apprentice, 26, 5);
   if( variant == BGRumourLie)
      stage_say( &st, run.apprentice, run.porter, [NSString stringWithFormat:nails_in_chest, @"#Saw"]);
   else
      stage_say( &st, run.porter, run.apprentice, where);
   stage_move( &st, run.apprentice, 5, 21);

   /* day 2: the carter tells the foreman, naming the apprentice */
   stage_move( &st, run.carter, 20, 27);
   stage_say( &st, run.foreman, run.carter, where);
   stage_move( &st, run.carter, 20, 4);
   run.told = credence_of( knowledge, run.foreman);
   if( variant == BGRumourSingle)
      goto done;
   if( variant == BGRumourLie)
   {
      /* the foreman goes to look for itself, and finds the chest empty */
      stage_move( &st, run.foreman, 3, 21);
      error = nil;
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "look_in", run.foreman, [g idFor:h[ 0]], BGNoEntity), 0,
                           &error) != nil);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
      goto done;
   }

   /* the porter tells the foreman, naming no one: step 5 */
   stage_move( &st, run.porter, 21, 27);
   stage_say( &st, run.porter, run.foreman, [NSString stringWithFormat:nails_in_chest, @"#Heard"]);
   run.rumoured     = credence_of( knowledge, run.foreman);
   run.rumouredDump = [knowledge dump:run.foreman];

   /* the foreman asks the porter who told it: step 6 */
   stage_say( &st, run.foreman, run.porter,
              @"#WhoToldYou & { what: #Stack & { unit: \"iron_nail\" }, "
              @"within: #Container & { place: #OnTile & { x: 2, y: 20, level: 0 } } }");
   stage_move( &st, run.porter, 26, 4);
   run.questioned     = credence_of( knowledge, run.foreman);
   run.questionedDump = [knowledge dump:run.foreman];

   /* day 3: the neighbour tells the foreman what it saw: step 7 */
   stage_move( &st, run.neighbour, 19, 27);
   stage_say( &st, run.foreman, run.neighbour, where);
   run.corroborated = credence_of( knowledge, run.foreman);

done:
   run.text = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


static void   test_rumour( void)
{
   BGRumour           full;
   BGRumour           again;
   BGRumour           single;
   BGRumour           lie;
   BGKnowledgeStore   *store;
   BGKnowledge        *restored;
   const BGAncestry   *a;
   const BGEvent      *ev;
   BGWorld            *w2;
   NSArray            *deferred;
   NSString           *error;
   uint64_t           position;
   uint32_t           apprentice;
   uint32_t           carter;
   NSUInteger         i;

   full   = rumour( BGRumourFull);
   single = rumour( BGRumourSingle);

   /* the claims were said, and answered, as the scenario has it */
   BG_CHECK( last_said( full.world, full.apprentice, full.carter) && last_said( full.world, full.apprentice, full.porter));
   BG_CHECK( last_said( full.world, full.carter, full.foreman) && last_said( full.world, full.neighbour, full.foreman));

   /* 1: no IDs in what agents say: content describes, it never names */
   for( i = 0; i < [full.world eventCount]; i++)
   {
      ev = [full.world eventAt:i];
      if( ! strcmp( ev->kind, "said"))
         BG_CHECK( ev->detail && ! strstr( ev->detail, "ref(") && ! strstr( ev->detail, "id:"));
   }

   /* the carter names the apprentice; the foreman knows the apprentice only by that */
   store = [full.knowledge storeOf:full.foreman];
   BG_CHECK( [store testimonyCount] == 3);
   BG_CHECK( [store testimonyAt:0]->attribution == BGHeardFrom);
   apprentice = [store testimonyAt:0]->root;
   BG_CHECK( apprentice && ! [store referent:apprentice]->present && ! [store referent:apprentice]->truth);

   /* 2: credence follows perceived ancestry: the porter's rumour, its root
    * unknown, counts again (step 5); asked, the porter names the apprentice,
    * the groups merge, and credence is the single source's (step 6) */
   BG_CHECK( full.told == BG_PRIOR + BG_TRUST - BG_HEARSAY);
   BG_CHECK( full.rumoured == full.told + BG_TRUST - BG_RUMOUR);
   BG_CHECK( full.rumoured > full.questioned);
   BG_CHECK( full.questioned == single.told);
   BG_CHECK( [store testimonyAt:1]->attribution == BGHeardFrom && [store testimonyAt:1]->root == apprentice);

   /* 3: the neighbour saw it: an independent root, and credence rises above the single source's */
   BG_CHECK( full.corroborated > full.questioned);
   BG_CHECK( full.corroborated == full.questioned + BG_TRUST);
   BG_CHECK( [store testimonyAt:2]->attribution == BGSaw);

   /* 4: true ancestry: the carter's word comes from the apprentice's, which
    * the apprentice saw; the neighbour's is its own; the inspector flags step
    * 5's false corroboration, and not step 6's merged group */
   a = [full.knowledge ancestryOf:last_said( full.world, full.carter, full.foreman)];
   BG_CHECK( a && a->relayed && a->parent == last_said( full.world, full.apprentice, full.carter));
   a = [full.knowledge rootOf:last_said( full.world, full.carter, full.foreman)];
   BG_CHECK( a && ! a->relayed && ! a->fabricated && a->speaker == full.apprentice && a->origin == full.apprentice);
   a = [full.knowledge ancestryOf:last_said( full.world, full.porter, full.foreman)];
   BG_CHECK( a && a->relayed && a->origin == full.apprentice);
   a = [full.knowledge ancestryOf:last_said( full.world, full.neighbour, full.foreman)];
   BG_CHECK( a && ! a->relayed && ! a->fabricated && a->origin == full.neighbour);
   BG_CHECK( [full.rumouredDump rangeOfString:@"false corroboration"].location != NSNotFound);
   BG_CHECK( [full.questionedDump rangeOfString:@"false corroboration"].location == NSNotFound);

   /* the same run is the same */
   again = rumour( BGRumourFull);
   BG_CHECK( [again.world stateHash] == [full.world stateHash]);
   BG_CHECK( [again.text isEqualToString:full.text]);

   /* knowledge, testimony, and ancestry are saved, and restored the same */
   w2 = BGRestore( full.text, [full.world contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( full.text, @"knowledge")];
   BG_CHECK( [[restored dump:full.foreman] isEqualToString:[full.knowledge dump:full.foreman]]);
   BG_CHECK( [[restored dump:full.porter] isEqualToString:[full.knowledge dump:full.porter]]);
   BG_CHECK( [restored rootOf:last_said( full.world, full.carter, full.foreman)]->origin == full.apprentice);

   /* 5: variant A: the apprentice made it up. History records a fabrication
    * root, and the apprentice's store marks it as not believed; the carter
    * relays it in good faith */
   lie = rumour( BGRumourLie);
   a   = [lie.knowledge ancestryOf:last_said( lie.world, lie.apprentice, lie.carter)];
   BG_CHECK( a && a->fabricated && ! a->relayed && a->origin == lie.apprentice);
   a = [lie.knowledge ancestryOf:last_said( lie.world, lie.carter, lie.foreman)];
   BG_CHECK( a && a->fabricated && a->relayed && a->origin == lie.apprentice);
   BG_CHECK( [[lie.knowledge dump:lie.apprentice] rangeOfString:@"(not believed)"].location != NSNotFound);
   BG_CHECK( [[lie.knowledge dump:lie.carter] rangeOfString:@"(not believed)"].location == NSNotFound);
   BG_CHECK( [[lie.knowledge dump:lie.foreman] rangeOfString:@"truly made up by"].location != NSNotFound);

   /* the foreman looks, finds the chest empty, and sees the nails in the
    * smith's hand: the claim is found false, and it trusts the carter and the
    * apprentice less */
   store      = [lie.knowledge storeOf:lie.foreman];
   carter     = [store testimonyAt:0]->source;
   apprentice = [store testimonyAt:0]->root;
   BG_CHECK( [store testimonyAt:0]->settled == -1);
   BG_CHECK( [store referent:[store testimonyAt:0]->thing]->form == BGLocationHeldBy);
   BG_CHECK( [store trustIn:carter] == BG_TRUST - BG_REFUTED && [store trustIn:apprentice] == BG_TRUST - BG_REFUTED);
   /* what they say next weighs less than it did */
   BG_CHECK( [store weightOf:[store testimonyAt:0]] < BG_TRUST - BG_HEARSAY);
}


/* KNOWLEDGE.md Scenario 1's variant B, and §12: memory decays along the
 * feature hierarchy, the strength of a belief fades, and what fades too far
 * is forgotten; deterministic, and the same on replay. */
static void   test_memory_decay( void)
{
   BGRumour           decay;
   BGRumour           again;
   BGKnowledgeStore   *store;
   const BGEvent      *first;
   const BGEvent      *second;
   NSUInteger         i;
   uint64_t           asked;

   decay = rumour( BGRumourDecay);

   /* just after, the apprentice remembers the oak chest, the smith's brown
    * coat, and iron nails; a day later, a wooden chest, a dark coat, and
    * nails of some metal it can't say */
   BG_CHECK( [decay.freshDump rangeOfString:@"material: \"oak\""].location != NSNotFound);
   BG_CHECK( [decay.freshDump rangeOfString:@"coat: \"brown\""].location != NSNotFound);
   BG_CHECK( [decay.dayOneDump rangeOfString:@"material: \"oak\""].location == NSNotFound);
   BG_CHECK( [decay.dayOneDump rangeOfString:@"material: \"wood\""].location != NSNotFound);
   BG_CHECK( [decay.dayOneDump rangeOfString:@"material: \"metal\""].location != NSNotFound);
   BG_CHECK( [decay.dayOneDump rangeOfString:@"coat: \"dark\""].location != NSNotFound);
   BG_CHECK( [decay.dayOneDump rangeOfString:@"coat: \"brown\""].location == NSNotFound);
   /* its own coat it sees */
   BG_CHECK( [decay.dayOneDump rangeOfString:@"coat: \"navy\""].location != NSNotFound);

   /* day 10: it still says where, though its description has lost its
    * detail, and it says how sure it is: its memory's strength */
   first  = NULL;
   second = NULL;
   for( i = 0; i < [decay.world eventCount]; i++)
      if( ! strcmp( [decay.world eventAt:i]->kind, "said") && [decay.world eventAt:i]->actor == decay.apprentice)
      {
         if( ! first)
            first = [decay.world eventAt:i];
         else
            second = [decay.world eventAt:i];
      }
   BG_CHECK( first && strstr( first->detail, "#IsIn") && strstr( first->detail, "sure: 10 "));
   BG_CHECK( first && ! strstr( first->detail, "oak") && ! strstr( first->detail, "wood") &&
             ! strstr( first->detail, "iron"));
   /* the foreman believes it less than a fresh account: it weighs no more than the apprentice is sure */
   BG_CHECK( decay.told == BG_PRIOR + BG_SEEN - 10 * BG_FADE);
   BG_CHECK( decay.told < BG_PRIOR + BG_TRUST);
   asked = first ? first->index : 0;
   BG_CHECK( [decay.knowledge ancestryOf:asked] && [decay.knowledge ancestryOf:asked]->origin == decay.apprentice &&
             ! [decay.knowledge ancestryOf:asked]->fabricated);

   /* day 20: it has forgotten, and says so */
   BG_CHECK( second && strstr( second->detail, "#DontKnow"));
   store = [decay.knowledge storeOf:decay.apprentice];
   for( i = 0; i < [store count]; i++)
      if( [store referentAt:i]->truth == decay.smith)
         BG_CHECK( ! [store referentAt:i]->present);
   BG_CHECK( [[decay.knowledge dump:decay.apprentice] rangeOfString:@"not there any more"].location != NSNotFound);

   /* the same on replay */
   again = rumour( BGRumourDecay);
   BG_CHECK( [again.world stateHash] == [decay.world stateHash]);
   BG_CHECK( [again.text isEqualToString:decay.text]);
   BG_CHECK( [again.dayOneDump isEqualToString:decay.dayOneDump]);
}


/* --- salience ------------------------------------------------------------- */

typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGAgency      *agency;
   BGEntityID    gossip;
   NSUInteger    idle;           /* the worker's observations of the smith, with nothing in mind */
   NSUInteger    concerned;      /* ... once the nails concern it */
   NSUInteger    busy;           /* ... while it drives a nail */
   NSString      *text;
} BGSalienceRun;


static NSUInteger   observed_by( BGKnowledgeStore *store, uint32_t actor, const char *kind)
{
   NSUInteger   i;
   NSUInteger   n;

   n = 0;
   for( i = 0; i < [store observationCount]; i++)
      if( [store observationAt:i]->actor == actor && ! strcmp( [store observationAt:i]->kind, kind))
         n++;
   return( n);
}


/* The workshop, with the worker holding nails of its own. At rest, with
 * nothing in mind, the worker sees the smith take the smith's nails; then,
 * committed to wedging the lock, which the nails concern, sees the smith put
 * them back; then, driving a nail, sees the smith take them again, and the
 * gossip asks it something. The gossip, who keeps four observations, asks
 * the smith something too, and is told five things. */
static BGSalienceRun   salience_run( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGActivities      *activities;
   BGKnowledge       *knowledge;
   BGAgency          *agency;
   BGAgency          *copy;
   BGKnowledgeStore  *store;
   BGProposalGroup   *g;
   BGEntityID        h[ 8];
   BGEntityID        gossip;
   NSString          *error;
   NSString          *where;
   BGAction          action;
   BGSalienceRun     run;
   uint32_t          smith;
   int               i;

   w          = BGTestWorld( 19);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:w committer:c knowledge:knowledge] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [s setDecision:agency];
   [c submit:BGWorkshopSetup( YES, h)];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the gossip"];
   gossip = [g create:"gossip" key:"gossip" at:BGOnTile( 3, 5, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   gossip = [g idFor:gossip];
   [agency control:4];
   store = [knowledge storeOf:4];
   smith = referent_of( store, 5);
   where = @"#WhereIs & { what: #Stack & { unit: \"iron_nail\" } }";

   /* at rest, nothing in mind: routine */
   BG_CHECK( BGPerform( w, c, BGActionMake( "take", 5, 2, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( [w time].ms + 1000)];
   run.idle = observed_by( store, smith, "moved");
   BG_CHECK( [store referent:referent_of( store, 2)]->form == BGLocationHeldBy);   /* seen all the same */

   /* the nails concern it now; it sets to driving one of its own into the lock */
   BG_CHECK( [agency commit:4 toGoal:"wedge_lock"]);
   BG_CHECK( BGPerform( w, c, BGActionMake( "put_in", 5, 2, 1), 0, &error) != nil);
   [s runUntil:BGTimeMake( [w time].ms + 1000)];
   run.concerned = observed_by( store, smith, "moved");

   /* driving, it misses what concerns it, but not being spoken to */
   BG_CHECK( BGPerform( w, c, BGActionMake( "take", 5, 2, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( [w time].ms + 1000)];
   run.busy = observed_by( store, smith, "moved");
   action         = BGActionMake( "say", gossip, 4, BGNoEntity);
   action.content = [w intern:[where UTF8String]];
   BG_CHECK( BGPerform( w, c, action, 0, &error) != nil);
   [s runUntil:BGTimeMake( [w time].ms + 1000)];
   /* the question put off is part of the worker's mind, and saved with it */
   copy = [[[BGAgency alloc] initWithWorld:w committer:c knowledge:knowledge] autorelease];
   [copy restoreSavedState:[agency savedState]];
   [knowledge setConcerns:agency];
   BG_CHECK( [[copy savedState] isEqualToArray:[agency savedState]]);
   BG_CHECK( [agency mindOf:4]->nquestions == 1 && [[[agency savedState] componentsJoinedByString:@"\n"]
                                                     rangeOfString:@"question 4 "].location != NSNotFound);

   /* the gossip asks the smith, and is told five things */
   action         = BGActionMake( "say", gossip, 5, BGNoEntity);
   action.content = [w intern:[where UTF8String]];
   BG_CHECK( BGPerform( w, c, action, 0, &error) != nil);
   [s runUntil:BGTimeMake( [w time].ms + 1000)];
   for( i = 0; i < 5; i++)
   {
      action         = BGActionMake( "say", 5, gossip, BGNoEntity);
      action.content = [w intern:[[NSString stringWithFormat:@"#WhereIs & { what: #Stack & { count: %d } }", i + 1]
                                    UTF8String]];
      BG_CHECK( BGPerform( w, c, action, 0, &error) != nil);
      [s runUntil:BGTimeMake( [w time].ms + 1000)];
   }
   [s runUntil:BGTimeMake( 30000)];

   run.world     = w;
   run.knowledge = knowledge;
   run.agency    = agency;
   run.gossip    = gossip;
   run.text      = BGSave( w, c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


/* the index of the first line of the agent's log with the text, or NSNotFound */
static NSUInteger   log_index( BGAgency *agency, BGEntityID agent, NSString *text)
{
   NSArray      *log;
   NSUInteger   i;

   log = [agency logOf:agent];
   for( i = 0; i < [log count]; i++)
      if( [[log objectAtIndex:i] rangeOfString:text].location != NSNotFound)
         return( i);
   return( NSNotFound);
}


/* KNOWLEDGE.md §7 and §12, AGENCY.md §10: what is kept is what is salient,
 * a busy agent notices less, and a store keeps what fits, the least salient
 * evicted first. */
static void   test_salience( void)
{
   BGSalienceRun      run;
   BGSalienceRun      again;
   BGKnowledgeStore   *store;
   BGKnowledge        *restored;
   const BGObservation *o;
   BGWorld            *w2;
   NSArray            *deferred;
   NSString           *error;
   uint64_t           position;
   NSUInteger         i;

   run   = salience_run();
   store = [run.knowledge storeOf:4];

   /* routine goes unkept; what its goal concerns is kept; while it drives, not */
   BG_CHECK( run.idle == 0);
   BG_CHECK( run.concerned == 1);
   BG_CHECK( run.busy == 1);
   BG_CHECK( logged( run.agency, @"[wedge the lock] drive a nail in: drive"));
   for( i = 0; i < [store observationCount]; i++)
   {
      o = [store observationAt:i];
      if( ! strcmp( o->kind, "moved") && o->actor != [store selfReferent])
         BG_CHECK( o->salience == BG_CONCERN);
   }
   /* being asked is noticed even while driving; answering is put off until the drive is done */
   BG_CHECK( logged( run.agency, @"worth -15, busy: not now"));
   BG_CHECK( logged( run.agency, @"answering: say R"));
   BG_CHECK( log_index( run.agency, 4, @"busy: not now") < log_index( run.agency, 4, @"answering: say R"));
   /* ... at the boundary the drive completes, still holding its goal */
   BG_CHECK( logged( run.agency, @"t=5002ms [wedge the lock] asked by R5: worth +15, answering"));
   BG_CHECK( [[run.knowledge dump:4] rangeOfString:@"salience 30"].location != NSNotFound);

   /* the gossip keeps four: what it said itself goes first, then the oldest it was told */
   store = [run.knowledge storeOf:run.gossip];
   BG_CHECK( [store observationCount] == 4);
   for( i = 0; i < [store observationCount]; i++)
   {
      o = [store observationAt:i];
      BG_CHECK( o->salience == BG_ADDRESSED && o->other == [store selfReferent]);
      BG_CHECK( o->content && strstr( o->content, [[NSString stringWithFormat:@"count: %d", (int) i + 2] UTF8String]));
   }
   BG_CHECK( [store nextSerial] > [store observationAt:3]->serial);

   /* the same on replay, and saved and restored the same */
   again = salience_run();
   BG_CHECK( [again.world stateHash] == [run.world stateHash]);
   BG_CHECK( [again.text isEqualToString:run.text]);
   w2 = BGRestore( run.text, [run.world contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( run.text, @"knowledge")];
   BG_CHECK( [[restored dump:4] isEqualToString:[run.knowledge dump:4]]);
   BG_CHECK( [[restored dump:run.gossip] isEqualToString:[run.knowledge dump:run.gossip]]);
   BG_CHECK( [[restored storeOf:run.gossip] nextSerial] == [store nextSerial]);
}


/* --- traces --------------------------------------------------------------- */

/* the agent's percept of a trace of that kind, present, or NULL */
static const BGTraceSeen   *traced( BGKnowledgeStore *store, const char *kind)
{
   NSUInteger   i;

   for( i = 0; i < [store traceCount]; i++)
      if( ! strcmp( [store traceAt:i]->kind, kind) && [store traceAt:i]->present)
         return( [store traceAt:i]);
   return( NULL);
}


static BOOL   any_trace( BGWorld *w, const char *kind)
{
   BGStore      *traces;
   NSUInteger   i;

   traces = [w storeForKind:[w kindNamed:"Trace"]];
   for( i = 0; i < [traces count]; i++)
      if( ! strcmp( [w textField:"Trace.traceKind" of:[traces entityAtIndex:i]], kind))
         return( YES);
   return( NO);
}


/* KNOWLEDGE.md Scenario 2's first half, "the cleaned workshop", with the
 * workshop's lock: at night the smith wedges the lock, which leaves tool
 * marks on it and scuffs on the floor; then washes the floor and touches up
 * the paint, which removes them and leaves traces of their own. The next
 * morning the foreman comes by. */
static void   test_traces( void)
{
   BGWorld            *w;
   BGWorld            *w2;
   BGCommitter        *c;
   BGScheduler        *s;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGKnowledge        *restored;
   BGTraces           *traces;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   const BGTraceSeen  *paint;
   const BGTraceSeen  *smell;
   const BGTraceSeen  *soap;
   const BGEvent      *ev;
   TriIndex           *family;
   NSArray            *deferred;
   NSString           *error;
   NSString           *text;
   BGEntityID         lock;
   BGEntityID         smith;
   BGEntityID         nails;
   BGEntityID         foreman;
   uint64_t           position;
   int64_t            dried;
   NSUInteger         boundaries;
   NSUInteger         i;
   int                n;

   w          = BGTestWorld( 23);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   traces     = [[[BGTraces alloc] initWithWorld:w] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [s addDomain:traces];
   g       = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the workshop at night"];
   lock    = [g create:"lock" key:"lock" at:BGOnTile( 5, 4, 0)];
   smith   = [g create:"smith" key:"smith" at:BGOnTile( 4, 4, 0)];
   nails   = [g create:"nails_10" key:"nails" at:BGHeldBy( smith, 0)];
   foreman = [g create:"foreman" key:"foreman" at:BGOnTile( 20, 20, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   lock    = [g idFor:lock];
   smith   = [g idFor:smith];
   nails   = [g idFor:nails];
   foreman = [g idFor:foreman];

   /* 2: every operation that removes traces leaves some of its own */
   family = tri_family_index( [w tri], "operations");
   n      = 0;
   for( i = 0; family && i < tri_index_count( family); i++)
      if( tri_at( [w tri], tri_pattern( [w tri], tri_index_tag( family, i)), "removes.first"))
      {
         BG_CHECK( tri_at( [w tri], tri_pattern( [w tri], tri_index_tag( family, i)), "leaves.first") != NULL);
         n++;
      }
   BG_CHECK( n == 2);

   /* the wedging leaves tool marks on the lock and scuffs on the floor */
   BG_CHECK( BGPerform( w, c, BGActionMake( "drive", smith, nails, lock), 0, &error) != nil);
   [s runUntil:BGTimeMake( 6000)];
   BG_CHECK( any_trace( w, "tool_marks") && any_trace( w, "scuffs"));

   /* the cover-up: each removal leaves its own */
   BG_CHECK( BGPerform( w, c, BGActionMake( "wash_floor", smith, BGNoEntity, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 17000)];
   BG_CHECK( ! any_trace( w, "scuffs") && any_trace( w, "damp_floor") && any_trace( w, "soap_smell"));
   BG_CHECK( BGPerform( w, c, BGActionMake( "touch_up", smith, lock, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 38000)];
   BG_CHECK( ! any_trace( w, "tool_marks") && any_trace( w, "fresh_paint") && any_trace( w, "paint_smell"));
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the smith goes home"];
   [g move:BGWhole( smith) to:BGOnTile( 25, 25, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 39000)];

   /* 1: traces cost nothing overnight: the night passes in a boundary or two,
    * the damp floor's run out, removed exactly when it does */
   boundaries = 0;
   while( any_trace( w, "damp_floor") && [s stepUntil:BGTimeMake( 12 * 3600000LL)])
      boundaries++;
   dried       = [w time].ms;
   boundaries += [s runUntil:BGTimeMake( 12 * 3600000LL)];
   BG_CHECK( boundaries <= 3);
   BG_CHECK( dried == 16000 + 6 * 3600000LL);          /* washed from 6 s to 16 s */
   BG_CHECK( ! any_trace( w, "damp_floor") && any_trace( w, "soap_smell"));

   /* the morning: the foreman by the lock perceives fresh paint and smells
    * it; nothing of the tool marks, the scuffs, or the damp; the smell of
    * soap is too faint to notice in passing; and only what the traces are,
    * never what made them */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the foreman comes by"];
   [g move:BGWhole( foreman) to:BGOnTile( 4, 5, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 12 * 3600000LL + 1000)];
   store = [knowledge storeOf:foreman];
   paint = traced( store, "fresh_paint");
   smell = traced( store, "paint_smell");
   BG_CHECK( paint && smell && ! traced( store, "soap_smell"));
   BG_CHECK( ! traced( store, "tool_marks") && ! traced( store, "scuffs") && ! traced( store, "damp_floor"));
   BG_CHECK( paint && paint->bearer && [store referent:paint->bearer]->truth == lock);
   /* aged analytically, from when it was made (the touch-up done at 37 s):
    * fresh paint lasts 3 days */
   BG_CHECK( paint && paint->strength == 80 * (37000 + 3 * 86400000LL - [w time].ms) / (3 * 86400000LL));
   BG_CHECK( ! [store finding:"#Cleaned" about:referent_of( store, lock)]);

   /* it investigates (KNOWLEDGE.md §9, deliberate): half a minute watching
    * closely, and it notices the faint smell of soap (the wash at 16 s; it
    * lasts a day), and draws what takes thought: someone cleaned up by the
    * lock */
   BG_CHECK( BGPerform( w, c, BGActionMake( "watch_closely", foreman, BGNoEntity, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 12 * 3600000LL + 32000)];
   soap  = traced( store, "soap_smell");
   smell = traced( store, "paint_smell");
   BG_CHECK( soap && ! soap->bearer && soap->x == 4 && soap->y == 4);
   BG_CHECK( soap && soap->strength == 50 * (16000 + 86400000LL - soap->seen) / 86400000LL);
   BG_CHECK( soap && soap->strength < BG_TRACE_FLOOR && smell && soap->strength < smell->strength);
   BG_CHECK( [store finding:"#Cleaned" about:referent_of( store, lock)] &&
             ! strcmp( [store finding:"#Cleaned" about:referent_of( store, lock)]->rule, "cleaned_nearby"));
   /* the developer sees where each came from: its creation, in the touch-up's completion */
   for( i = 0; i < [w eventCount]; i++)
   {
      ev = [w eventAt:i];
      if( paint && ! strcmp( ev->kind, "created") && ev->subject == paint->truth)
         BG_CHECK( [[c sourceOfPosition:ev->group] rangeOfString:@"touch_up completes"].location != NSNotFound);
   }

   /* saved and restored the same */
   text = BGSave( w, c, [NSArray arrayWithObjects:knowledge, traces, nil]);
   w2   = BGRestore( text, [w contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( text, @"knowledge")];
   BG_CHECK( [[restored dump:foreman] isEqualToString:[knowledge dump:foreman]]);
}


/* KNOWLEDGE.md §4 and Scenario 2's plated fitting: the fitting looks brass
 * and is steel. The foreman sees brass; a scratch test reveals steel, which
 * the foreman then knows however often it sees brass again, and leaves a
 * scratch anyone can see. The smith, watching, still sees brass. */
static void   test_appearance( void)
{
   BGWorld            *w;
   BGWorld            *w2;
   BGCommitter        *c;
   BGScheduler        *s;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGKnowledge        *restored;
   BGTraces           *traces;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   NSArray            *deferred;
   NSString           *error;
   NSString           *text;
   NSString           *fittingSeen;
   BGEntityID         fitting;
   BGEntityID         lock;
   BGEntityID         smith;
   BGEntityID         foreman;
   uint64_t           position;
   uint32_t           r;

   w          = BGTestWorld( 29);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   traces     = [[[BGTraces alloc] initWithWorld:w] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [s addDomain:traces];
   g       = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the fitting"];
   fitting = [g create:"fitting" key:"fitting" at:BGOnTile( 5, 4, 0)];
   lock    = [g create:"lock" key:"lock" at:BGOnTile( 5, 5, 0)];
   foreman = [g create:"foreman" key:"foreman" at:BGOnTile( 4, 4, 0)];
   smith   = [g create:"smith" key:"smith" at:BGOnTile( 2, 4, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   fitting = [g idFor:fitting];
   lock    = [g idFor:lock];
   foreman = [g idFor:foreman];
   smith   = [g idFor:smith];

   /* 3: perception reports the appearance: brass */
   store       = [knowledge storeOf:foreman];
   r           = referent_of( store, fitting);
   fittingSeen = [store describeReferent:r];
   BG_CHECK( [fittingSeen rangeOfString:@"material: \"brass\""].location != NSNotFound);
   BG_CHECK( [fittingSeen rangeOfString:@"steel"].location == NSNotFound);
   BG_CHECK( tri_subtype( [w tri], ((const BGBody *) [w record:[w kindNamed:"Body"] for:fitting])->material,
                          tri_type_named( [w tri], "\"steel\"")));

   /* only the scratch test reveals steel, and leaves a scratch */
   BG_CHECK( BGPerform( w, c, BGActionMake( "test_scratch", foreman, fitting, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 5000)];
   BG_CHECK( [[store describeReferent:r] rangeOfString:@"material: \"steel\""].location != NSNotFound);
   BG_CHECK( [[store describeReferent:r] rangeOfString:@"brass"].location == NSNotFound);
   BG_CHECK( any_trace( w, "scratch"));
   BG_CHECK( traced( store, "scratch") && traced( store, "scratch")->bearer == r);
   /* seen again, it still looks brass; the foreman still knows steel */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the foreman steps back"];
   [g move:BGWhole( foreman) to:BGOnTile( 3, 4, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 6000)];
   BG_CHECK( [store referentAt:0] && [store referent:r]->seen == 6000);
   BG_CHECK( [[store describeReferent:r] rangeOfString:@"material: \"steel\""].location != NSNotFound);
   /* the smith, who watched, sees the scratch, and still brass */
   BG_CHECK( traced( [knowledge storeOf:smith], "scratch"));
   BG_CHECK( [[[knowledge storeOf:smith] describeReferent:referent_of( [knowledge storeOf:smith], fitting)]
              rangeOfString:@"material: \"brass\""].location != NSNotFound);

   /* a thing that is what it looks like: the test says so */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the foreman goes to the lock"];
   [g move:BGWhole( foreman) to:BGOnTile( 4, 5, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 7000)];
   BG_CHECK( BGPerform( w, c, BGActionMake( "test_scratch", foreman, lock, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 11000)];
   BG_CHECK( [store referent:referent_of( store, lock)]->deeper &&
             ! strcmp( [store referent:referent_of( store, lock)]->deeper, "material: \"brass\""));

   /* saved and restored the same */
   text = BGSave( w, c, [NSArray arrayWithObjects:knowledge, traces, nil]);
   w2   = BGRestore( text, [w contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( text, @"knowledge")];
   BG_CHECK( [[restored dump:foreman] isEqualToString:[knowledge dump:foreman]]);
}


/* KNOWLEDGE.md Scenario 2's second half, interpretation: the smith wedges the
 * lock at night, with the porter, who can't paint, watching; the porter goes
 * home, and the smith touches up the paint. In the morning the foreman, a
 * painter, the porter, and the carter, who neither paints nor saw the marks,
 * come by the lock. */
static void   test_interpretation( void)
{
   BGWorld            *w;
   BGWorld            *w2;
   BGCommitter        *c;
   BGScheduler        *s;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGKnowledge        *restored;
   BGTraces           *traces;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   const BGFinding    *f;
   NSArray            *deferred;
   NSString           *error;
   NSString           *text;
   BGEntityID         lock;
   BGEntityID         smith;
   BGEntityID         nails;
   BGEntityID         foreman;
   BGEntityID         porter;
   BGEntityID         carter;
   uint64_t           position;

   w          = BGTestWorld( 31);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   traces     = [[[BGTraces alloc] initWithWorld:w] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [s addDomain:traces];
   g       = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the workshop at night"];
   lock    = [g create:"lock" key:"lock" at:BGOnTile( 5, 4, 0)];
   smith   = [g create:"smith" key:"smith" at:BGOnTile( 4, 4, 0)];
   nails   = [g create:"nails_10" key:"nails" at:BGHeldBy( smith, 0)];
   porter  = [g create:"porter" key:"porter" at:BGOnTile( 7, 6, 0)];
   foreman = [g create:"foreman" key:"foreman" at:BGOnTile( 25, 25, 0)];
   carter  = [g create:"carter" key:"carter" at:BGOnTile( 25, 2, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   lock    = [g idFor:lock];
   smith   = [g idFor:smith];
   nails   = [g idFor:nails];
   porter  = [g idFor:porter];
   foreman = [g idFor:foreman];
   carter  = [g idFor:carter];

   /* the wedging, watched by the porter, who sees the tool marks */
   BG_CHECK( BGPerform( w, c, BGActionMake( "drive", smith, nails, lock), 0, &error) != nil);
   [s runUntil:BGTimeMake( 6000)];
   store = [knowledge storeOf:porter];
   BG_CHECK( traced( store, "tool_marks"));
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the porter goes home"];
   [g move:BGWhole( porter) to:BGOnTile( 25, 12, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 7000)];

   /* the touch-up, unwatched */
   BG_CHECK( BGPerform( w, c, BGActionMake( "touch_up", smith, lock, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 28000)];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the smith goes home"];
   [g move:BGWhole( smith) to:BGOnTile( 30, 30, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 8 * 3600000LL)];

   /* the morning */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: they come by the lock"];
   [g move:BGWhole( foreman) to:BGOnTile( 4, 4, 0)];
   [g move:BGWhole( porter) to:BGOnTile( 6, 4, 0)];
   [g move:BGWhole( carter) to:BGOnTile( 5, 6, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 8 * 3600000LL + 1000)];

   /* everyone sees the fresh paint */
   BG_CHECK( traced( [knowledge storeOf:foreman], "fresh_paint"));
   BG_CHECK( traced( [knowledge storeOf:porter], "fresh_paint"));
   BG_CHECK( traced( [knowledge storeOf:carter], "fresh_paint"));

   /* 5: expertise gates interpretation: the painter concludes something
    * happened to the lock; the others see only paint */
   store = [knowledge storeOf:foreman];
   f     = [store finding:"#Tampered" about:referent_of( store, lock)];
   BG_CHECK( f && f->credence == 10 && ! strcmp( f->rule, "touched_up"));
   BG_CHECK( ! [[knowledge storeOf:porter] finding:"#Tampered" about:referent_of( [knowledge storeOf:porter], lock)]);
   BG_CHECK( ! [[knowledge storeOf:carter] findingCount]);

   /* 4: prior beliefs gate interpretation: the porter, who saw the tool
    * marks, and sees them gone under fresh paint, concludes they were painted
    * over; the painter, who never saw them, doesn't */
   store = [knowledge storeOf:porter];
   BG_CHECK( ! traced( store, "tool_marks"));
   f = [store finding:"#CoveredUp" about:referent_of( store, lock)];
   BG_CHECK( f && f->credence == 20 && ! strcmp( f->rule, "covered_up"));
   BG_CHECK( ! [[knowledge storeOf:foreman] finding:"#CoveredUp" about:referent_of( [knowledge storeOf:foreman], lock)]);
   BG_CHECK( f && f->time >= 8 * 3600000LL);           /* drawn in the morning, when it saw the paint */

   /* 6: no truth in what they conclude: a finding is about a referent of
    * theirs, with the rule that drew it, never what made the traces */
   BG_CHECK( [[knowledge dump:porter] rangeOfString:@"finding #CoveredUp about R"].location != NSNotFound);

   /* saved and restored the same */
   text = BGSave( w, c, [NSArray arrayWithObjects:knowledge, traces, nil]);
   w2   = BGRestore( text, [w contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( text, @"knowledge")];
   BG_CHECK( [[restored dump:foreman] isEqualToString:[knowledge dump:foreman]]);
   BG_CHECK( [[restored dump:porter] isEqualToString:[knowledge dump:porter]]);
}


/* KNOWLEDGE.md Scenario 3's notebook: the worker looks into the bin and
 * writes down where the nails are, puts the notebook in the bin, and goes;
 * the smith takes it and reads it. */
static void   test_notebook( void)
{
   BGWorld            *w;
   BGWorld            *w2;
   BGCommitter        *c;
   BGScheduler        *s;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGKnowledge        *restored;
   BGKnowledgeStore   *store;
   BGKnowledgeStore   *thief;
   BGProposalGroup    *g;
   const BGTestimony  *t;
   const BGReferent   *nails;
   NSArray            *deferred;
   NSString           *error;
   NSString           *text;
   NSString           *writing;
   NSString           *before;
   BGEntityID         h[ 8];
   BGEntityID         notebook;
   uint64_t           position;
   uint32_t           rnails;
   uint32_t           rbook;
   NSUInteger         told;
   NSUInteger         i;

   w          = BGTestWorld( 37);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [c submit:BGWorkshopSetup( NO, h)];
   [s runUntil:BGTimeMake( 1)];
   g        = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the worker's notebook"];
   notebook = [g create:"notebook" key:"notebook" at:BGHeldBy( 4, 1)];       /* the worker's */
   [c submit:g];
   [s runUntil:BGTimeMake( 2)];
   BG_CHECK( [g applied]);
   notebook = [g idFor:notebook];

   /* the worker looks into the bin, and writes down where the nails are */
   store = [knowledge storeOf:4];
   BG_CHECK( BGPerform( w, c, BGActionMake( "look_in", 4, 1, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 3)];
   rnails  = referent_of( store, 2);
   rbook   = referent_of( store, notebook);
   writing = [store writingAbout:rnails];
   BG_CHECK( writing && rbook);
   {
      BGAction   action;

      action         = BGActionMake( "write_down", [store selfReferent], rbook, BGNoEntity);
      action.content = [w intern:[writing UTF8String]];
      BG_CHECK( BGPerformBelieved( w, c, store, action, 0, &error) != nil);
   }
   [s runUntil:BGTimeMake( 4)];

   /* 3: notebook content is a content entity authored by the character, with
    * claims copied from beliefs at the time of writing */
   text = [NSString stringWithUTF8String:(char *) [w textField:"Record.writing" of:notebook]];
   BG_CHECK( [text hasPrefix:@"#Writing & { author: #Agent & {"]);
   BG_CHECK( [text rangeOfString:@"coat: \"blue\""].location != NSNotFound);
   BG_CHECK( [text rangeOfString:@"entries: [#IsIn & { what: #Stack"].location != NSNotFound);
   BG_CHECK( [text rangeOfString:@"attribution: #Saw & { sure: 30 }"].location != NSNotFound);
   BG_CHECK( [text rangeOfString:@"ref("].location == NSNotFound);
   BG_CHECK( happened( w, "wrote", 4, notebook));

   /* it puts the notebook in the bin, and goes off */
   BG_CHECK( BGPerform( w, c, BGActionMake( "put_in", 4, notebook, 1), 0, &error) != nil);
   [s runUntil:BGTimeMake( 5)];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the worker goes off"];
   [g move:BGWhole( 4) to:BGOnTile( 20, 20, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 6)];
   nails  = [store referent:rnails];
   before = [store describeReferent:rnails];
   told   = [store testimonyCount];
   BG_CHECK( nails->present && nails->form == BGLocationIn && ! nails->toldBy);

   /* the smith takes it from the bin, and reads it */
   BG_CHECK( BGPerform( w, c, BGActionMake( "take", 5, notebook, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 1000)];
   BG_CHECK( BGPerform( w, c, BGActionMake( "read", 5, notebook, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 2000)];

   /* 4: the thief's beliefs cite the notebook, with the character as perceived root */
   thief = [knowledge storeOf:5];
   BG_CHECK( [thief testimonyCount] == 1);
   t = [thief testimonyCount] ? [thief testimonyAt:0] : NULL;
   BG_CHECK( t && t->via == referent_of( thief, notebook));
   BG_CHECK( t && t->source == referent_of( thief, 4) && t->root == t->source && t->attribution == BGSaw);
   BG_CHECK( t && [thief referent:t->thing]->present && [thief referent:t->thing]->container == referent_of( thief, 1));
   BG_CHECK( [[knowledge dump:5] rangeOfString:@"wrote so in R"].location != NSNotFound);

   /* 5: the theft leaves the worker's memory as it was */
   BG_CHECK( [[store describeReferent:rnails] isEqualToString:before]);
   BG_CHECK( [store testimonyCount] == told);
   for( i = 0; i < [store count]; i++)
      BG_CHECK( [store referentAt:i]->truth != 5 || [store referentAt:i]->present);

   /* saved and restored the same */
   text = BGSave( w, c, [NSArray arrayWithObject:knowledge]);
   w2   = BGRestore( text, [w contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( text, @"knowledge")];
   BG_CHECK( [[restored dump:5] isEqualToString:[knowledge dump:5]]);
}


/* 6: the player's out-of-character notes never reach the character's
 * knowledge; the notebook view shows what the character knows, as it knows
 * it, without truth links */
static void   test_play_notebook( void)
{
   NSArray    *commands;
   NSString   *out;
   NSRange    knows;
   NSRange    book;
   uint64_t   h;

   commands = [NSArray arrayWithObjects:@"do 1", @"walk w", @"tell R4 R5", @"ask R4 where R5", @"notebook",
                                        @"note check the loft again", @"notes", @"knows", @"write R5", nil];
   out = session( @"workshop", commands, &h);
   BG_CHECK( [out rangeOfString:@"Things you know of:\n"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"  R5 #Stack, in R2"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"R4 said so, having heard it from you"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"1. check the loft again"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"You hold no notebook."].location != NSNotFound);
   /* the character's store, as the developer sees it, has no note in it */
   knows = [out rangeOfString:@"what 4 knows"];
   BG_CHECK( knows.location != NSNotFound &&
             [[out substringFromIndex:knows.location] rangeOfString:@"loft"].location == NSNotFound);
   /* the notebook view has no truth links */
   book = [out rangeOfString:@"Things you know of:"];
   BG_CHECK( book.location != NSNotFound && book.location < knows.location &&
             [[out substringWithRange:NSMakeRange( book.location, knows.location - book.location)]
               rangeOfString:@"truth"].location == NSNotFound);

   /* nor do they change what the character says: told the same, with and
    * without a note, the world is the same to the bit */
   {
      NSString   *with;
      NSString   *without;
      uint64_t   h1;
      uint64_t   h2;

      with    = session( @"workshop", [NSArray arrayWithObjects:@"do 1", @"walk w", @"note the nails are in the loft",
                                                                 @"tell R4 R5", @"hash", nil], &h1);
      without = session( @"workshop", [NSArray arrayWithObjects:@"do 1", @"walk w", @"tell R4 R5", @"hash", nil], &h2);
      BG_CHECK( h1 == h2);
      BG_CHECK( [with rangeOfString:@"said: 4, other 5, #IsIn"].location != NSNotFound);
      BG_CHECK( [[with substringFromIndex:[with rangeOfString:@"said: 4"].location] rangeOfString:@"loft"].location == NSNotFound);
      (void) without;
   }
}


/* COMPONENTS.md Scenario 1's step 4: afterwards, someone looking into the bin finds the bent nail, an
 * individual among the clean ones, tool marks and all: evidence (§4). */
static void   test_marked_nail_found( void)
{
   BGMarkedNail       *scenario;
   BGWorld            *w;
   BGCommitter        *c;
   BGScheduler        *s;
   BGKnowledge        *knowledge;
   BGKnowledgeStore   *store;
   const BGReferent   *r;
   NSString           *error;
   NSString           *seen;
   NSUInteger         i;
   uint32_t           bin;
   BOOL               found;

   scenario  = run_marked_nail( BGMarkedNailBase, 42);
   w         = [scenario world];
   c         = [scenario committer];
   knowledge = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   s         = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setPerception:knowledge];
   [s runUntil:BGTimeMake( [w time].ms + 1)];
   store = [knowledge storeOf:5];
   bin   = referent_of( store, 1);
   BG_CHECK( bin != 0);
   error = nil;
   BG_CHECK( BGPerformBelieved( w, c, store, BGActionMake( "look_in", [store selfReferent], bin, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( [w time].ms + 1)];
   found = NO;
   for( i = 0; i < [store count]; i++)
   {
      r     = [store referentAt:i];
      seen  = [store describeReferent:r->id];
      found = found || (r->form == BGLocationIn && r->container == bin && ! strcmp( r->kind, "#Body") &&
                        [seen rangeOfString:@"bent: true"].location != NSNotFound);
   }
   BG_CHECK( found);
   BG_CHECK( [[knowledge dump:5] rangeOfString:@"trace tool_marks on"].location != NSNotFound);
}


/* KNOWLEDGE.md Scenario 2's swap: the worker sees the workshop's worn wrench
 * on the bench (`saw`, or not), goes off, and meanwhile the wrench is swapped
 * for a new one; back, it sees the new one. Its knowledge, dumped. */
static NSString   *swap_run( BOOL saw)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         old;

   st.w      = BGTestWorld( 127);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the bench"];
   worker = [g create:"worker" key:"worker" at:saw ? BGOnTile( 5, 6, 0) : BGOnTile( 20, 20, 0)];
   old    = [g create:"wrench_250" key:"the old wrench" at:BGOnTile( 6, 6, 0)];
   [g set:"Body.toolMarks" of:BGWhole( old) to:40];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   old    = [g idFor:old];
   stage_move( &st, worker, 20, 20);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the swap"];
   [g move:BGWhole( old) to:BGOnTile( 25, 2, 0)];
   [g create:"wrench_250" key:"the new wrench" at:BGOnTile( 6, 6, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
   stage_move( &st, worker, 5, 6);
   [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
   {
      BGKnowledge   *restored;
      NSString      *text;

      /* what it noticed is saved */
      text     = BGSave( st.w, st.c, [NSArray arrayWithObject:knowledge]);
      restored = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
      [restored restoreSavedState:BGSavedDomainState( text, @"knowledge")];
      BG_CHECK( [[restored dump:worker] isEqualToString:[knowledge dump:worker]]);
   }
   return( [knowledge dump:worker]);
}


/* 4: prior beliefs gate interpretation. Recognition takes the new wrench
 * for the old (same kind, same place); one who saw the old one worn sees it
 * lose its tool marks, which don't wear off, and concludes it was replaced.
 * One who never saw the old one sees a new-looking wrench: nothing. */
static void   test_wrench_replaced( void)
{
   NSString   *saw;
   NSString   *never;

   saw   = swap_run( YES);
   never = swap_run( NO);
   BG_CHECK( [saw rangeOfString:@"toolMarks: 0"].location != NSNotFound);
   BG_CHECK( [saw rangeOfString:@"finding #Replaced about R2, +15 dB, by replaced"].location != NSNotFound);
   BG_CHECK( [never rangeOfString:@"#Wrench"].location != NSNotFound);
   BG_CHECK( [never rangeOfString:@"#Replaced"].location == NSNotFound);
   BG_CHECK( [swap_run( YES) isEqualToString:saw]);
}


/* KNOWLEDGE.md Scenario 3's check 2, the bump. By day the worker sees the
 * door open, and goes off; night falls, and someone shuts it. Back beside it
 * in the dark, it can't make it out, and remembers it open: the menu offers
 * going through, from the stale belief. Going through is a bump into the
 * shut door, which it feels: it believes it shut, and stays where it was.
 * `lamp`: it carries a shining lamp, and sees the door shut beside it. */
static NSString   *door_run( BOOL lamp, NSString **menuText, NSString **afar, BGEntityID *where)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   BGMenu             *menu;
   BGEntityID         worker;
   BGEntityID         door;
   NSString           *error;
   NSMutableArray     *entries;
   NSUInteger         i;
   uint32_t           rdoor;

   st.w      = BGTestWorld( 137);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the loft door"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 4, 5, 0)];
   door   = [g create:"room_door" key:"the loft door" at:BGOnTile( 4, 6, 0)];
   [g set:"Door.ajar" of:BGWhole( door) to:1];
   if( lamp)
      [g create:"lamp" key:"lamp" at:BGHeldBy( worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   door   = [g idFor:door];
   store  = [knowledge storeOf:worker];
   rdoor  = referent_of( store, door);

   /* off, night, the door shut behind its back */
   stage_move( &st, worker, 4, 15);
   [knowledge setAmbient:0];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: someone shuts the loft door"];
   [g set:"Door.ajar" of:BGWhole( door) to:0];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
   /* coming back: three tiles off, in the dark, it sees nothing there, and
    * doesn't take that for its absence */
   stage_move( &st, worker, 4, 3);
   *afar = [[store describeReferent:rdoor] stringByAppendingString:[store referent:rdoor]->present ? @" (there)" : @" (gone)"];
   stage_move( &st, worker, 4, 5);

   menu    = [BGMenu menuFor:store world:st.w believed:YES];
   entries = [NSMutableArray array];
   for( i = 0; i < [menu count]; i++)
      [entries addObject:[menu describeAt:i]];
   *menuText = [entries componentsJoinedByString:@"; "];
   error = nil;
   if( [*menuText rangeOfString:@"go_through"].location != NSNotFound)
   {
      BG_CHECK( BGPerformBelieved( st.w, st.c, store, BGActionMake( "go_through", [store selfReferent], rdoor, BGNoEntity), 0,
                                   &error) != nil);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
   }
   *where = [st.w locationOf:worker].form == BGLocationOnTile ? (BGEntityID) [st.w locationOf:worker].y : 0;
   return( [store describeReferent:rdoor]);
}


static void   test_door_in_the_dark( void)
{
   NSString     *menu;
   NSString     *afar;
   NSString     *door;
   BGEntityID   y;

   door = door_run( NO, &menu, &afar, &y);
   BG_CHECK( [afar rangeOfString:@"ajar: true"].location != NSNotFound && [afar hasSuffix:@" (there)"]);
   BG_CHECK( [menu rangeOfString:@"go_through item R"].location != NSNotFound);
   BG_CHECK( [door rangeOfString:@"ajar: false"].location != NSNotFound);
   BG_CHECK( y == 5);

   /* with a lamp (its reach two tiles), beside the door it sees it shut,
    * and the menu doesn't offer going through */
   door = door_run( YES, &menu, &afar, &y);
   BG_CHECK( [door rangeOfString:@"ajar: false"].location != NSNotFound);
   BG_CHECK( [menu rangeOfString:@"go_through"].location == NSNotFound && y == 5);
}


/* COMPONENTS.md Scenario 2, "the forged permit". The harbour office's
 * permit P lets Alun into the warehouse: an authorization the office made,
 * linked to P; Alun holds a copy, C1, sealed with the office's seal; the
 * office's ledger lists P. A forger borrows C1 and, with a carved fake
 * stamp, makes C2 with the name changed; the guard sees it. A: a clerk makes
 * an exact duplicate, C3. B: C1 burns. */
static void   test_forged_permit( void)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   BGEntityID         office;
   BGEntityID         permit;
   BGEntityID         auth;
   BGEntityID         reg;
   BGEntityID         ledger;
   BGEntityID         c1;
   BGEntityID         c2;
   BGEntityID         c3;
   BGEntityID         altered;
   BGEntityID         seal;
   BGEntityID         fake;
   BGEntityID         alun;
   BGEntityID         forger;
   BGEntityID         clerk;
   BGEntityID         guard;
   BGEntityID         veteran;
   BGEntityID         warehouse;
   const BGEvent      *ev;
   const BGEdge       *edge;
   NSString           *error;
   NSString           *seen;
   NSArray            *authority;
   BGAction           forge;
   NSUInteger         i;
   int64_t            v;
   BOOL               derived;
   BOOL               madeByForger;
   BOOL               stamped;

   st.w      = BGTestWorld( 151);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   g         = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the harbour office's procedure"];
   office    = [g create:"harbour_office" key:"the harbour office" at:BGLocationMakeNone()];
   warehouse = [g create:"storeroom" key:"the warehouse" at:BGOnTile( 20, 4, 0)];
   alun      = [g create:"alun" key:"Alun" at:BGOnTile( 3, 3, 0)];
   forger    = [g create:"forger" key:"the forger" at:BGOnTile( 4, 3, 0)];
   clerk     = [g create:"clerk" key:"the clerk" at:BGOnTile( 10, 10, 0)];
   guard     = [g create:"guard" key:"the guard" at:BGOnTile( 19, 4, 0)];
   permit    = [g create:"content" key:"permit P" at:BGLocationMakeNone()];
   [g set:"Information.text" of:BGWhole( permit) toText:"Alun may enter the warehouse"];
   [g set:"Information.issuer" of:BGWhole( permit) toText:"the harbour office"];
   auth      = [g create:"authorization" key:"Alun's authorization" at:BGLocationMakeNone()];
   [g set:"Authorization.grants" of:BGWhole( auth) toText:"enter"];
   [g set:"Authorization.over" of:BGWhole( auth) to:(int64_t) warehouse];
   [g set:"Authorization.grantee" of:BGWhole( auth) to:(int64_t) alun];
   [g relate:BGEdgeAuthorizes from:BGWhole( auth) to:BGWhole( permit)];
   reg       = [g create:"content" key:"the register" at:BGLocationMakeNone()];
   [g set:"Information.text" of:BGWhole( reg) toText:"permits issued"];
   [g relate:BGEdgeLists from:BGWhole( reg) to:BGWhole( permit)];
   ledger    = [g create:"ledger" key:"the office's ledger" at:BGOnTile( 10, 11, 0)];
   [g set:"Inscription.inscribed" of:BGWhole( ledger) to:(int64_t) reg];
   seal      = [g create:"stamp" key:"the office seal" at:BGOnTile( 11, 10, 0)];
   [g set:"Stamp.presses" of:BGWhole( seal) toText:"the harbour anchor"];
   [g set:"Stamp.sealOf" of:BGWhole( seal) toText:"the harbour office"];
   veteran   = [g create:"guard" key:"a veteran guard, at the office" at:BGOnTile( 11, 11, 0)];
   c1        = [g create:"paper_copy" key:"C1" at:BGHeldBy( alun, 0)];
   [g set:"Inscription.inscribed" of:BGWhole( c1) to:(int64_t) permit];
   [g set:"Inscription.reads" of:BGWhole( c1) toText:"Alun may enter the warehouse"];
   [g set:"Inscription.claims" of:BGWhole( c1) toText:"the harbour office"];
   [g set:"Inscription.penned" of:BGWhole( c1) toText:"a clerk's round hand"];
   [g set:"Inscription.impression" of:BGWhole( c1) toText:"the harbour anchor"];
   fake      = [g create:"stamp" key:"a carved fake stamp" at:BGHeldBy( forger, 1)];
   [g set:"Stamp.presses" of:BGWhole( fake) toText:"an anchor, crudely cut"];
   [g set:"Scribe.handwriting" of:BGWhole( forger) toText:"a careful, cramped hand"];
   [g set:"Scribe.handwriting" of:BGWhole( clerk) toText:"a clerk's round hand"];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   office    = [g idFor:office];
   warehouse = [g idFor:warehouse];
   alun      = [g idFor:alun];
   forger    = [g idFor:forger];
   clerk     = [g idFor:clerk];
   guard     = [g idFor:guard];
   veteran   = [g idFor:veteran];
   permit    = [g idFor:permit];
   auth      = [g idFor:auth];
   reg       = [g idFor:reg];
   ledger    = [g idFor:ledger];
   seal      = [g idFor:seal];
   c1        = [g idFor:c1];
   fake      = [g idFor:fake];
   BG_CHECK( [st.w getField:"Inscription.inscribed" of:c1 value:&v] && v == (int64_t) permit);

   /* 1: the forger borrows C1 and makes C2, the name changed, pressed with its fake stamp */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: Alun lends C1"];
   [g move:BGWhole( c1) to:BGHeldBy( forger, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 2)];
   forge         = BGActionMake( "copy_out", forger, c1, BGNoEntity);
   forge.content = [st.w intern:"Bran may enter the warehouse"];
   error         = nil;
   g = BGPerform( st.w, st.c, forge, 0, &error);
   BG_CHECK( g != nil);
   [st.s runUntil:BGTimeMake( 3)];
   c2 = BGNoEntity;
   for( i = 0; i < [g count]; i++)
      if( [g proposals][ i].kind == BGProposeCreate && ! strcmp( [g proposals][ i].name, "paper_copy"))
         c2 = [g idFor:[g proposals][ i].handle];
   BG_CHECK( c2 && [st.w getField:"Inscription.inscribed" of:c2 value:&v]);
   altered = (BGEntityID) v;
   BG_CHECK( altered != permit && ! strcmp( [st.w textField:"Information.text" of:altered], "Bran may enter the warehouse"));

   /* 2: the guard sees C2: what it says, and what can be seen of it */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the forger shows C2 at the warehouse"];
   [g move:BGWhole( forger) to:BGOnTile( 18, 4, 0)];
   [g move:BGWhole( c2) to:BGOnTile( 18, 4, 0)];
   [g move:BGWhole( veteran) to:BGOnTile( 18, 5, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 4)];
   store = [knowledge storeOf:guard];
   seen  = [store describeReferent:referent_of( store, c2)];
   BG_CHECK( [seen rangeOfString:@"reads: \"Bran may enter the warehouse\""].location != NSNotFound);
   BG_CHECK( [seen rangeOfString:@"claims: \"the harbour office\""].location != NSNotFound);
   BG_CHECK( [seen rangeOfString:@"penned: \"a careful, cramped hand\""].location != NSNotFound);
   BG_CHECK( [seen rangeOfString:@"impression: \"an anchor, crudely cut\""].location != NSNotFound);
   /* 3: the player's view has only the claimed origin; the actual is in history */
   BG_CHECK( [seen rangeOfString:@"inscribed"].location == NSNotFound);
   /* whether it is believed (KNOWLEDGE.md §4): the guard, who has never seen
    * the office's seal, can't tell; the veteran, who has, sees the crude
    * anchor isn't it, and finds C2 forged */
   BG_CHECK( [[knowledge dump:guard] rangeOfString:@"#Forged"].location == NSNotFound);
   store = [knowledge storeOf:veteran];
   BG_CHECK( [store finding:"#Forged" about:referent_of( store, c2)] != NULL);
   BG_CHECK( referent_of( store, c1) && [store finding:"#Forged" about:referent_of( store, c1)] == NULL);

   /* 1 (checks): content, the office, the authorization have no location;
    * copies, the ledger, the stamps have one */
   BG_CHECK( [st.w locationOf:permit].form == BGLocationNone && [st.w locationOf:altered].form == BGLocationNone &&
             [st.w locationOf:office].form == BGLocationNone && [st.w locationOf:auth].form == BGLocationNone);
   BG_CHECK( [st.w locationOf:c1].form != BGLocationNone && [st.w locationOf:c2].form != BGLocationNone &&
             [st.w locationOf:ledger].form != BGLocationNone && [st.w locationOf:fake].form != BGLocationNone);

   /* 2: P′ derived from P; its actual creation is the forger's; 3: it claims the office */
   derived = NO;
   for( i = 0; i < [st.w edgeCount]; i++)
   {
      edge    = [st.w edgeAt:i];
      derived = derived || (edge->kind == BGEdgeDerivedFrom && edge->from == altered && edge->to == permit);
   }
   madeByForger = NO;
   stamped      = NO;
   for( i = 0; i < [st.w eventCount]; i++)
   {
      ev           = [st.w eventAt:i];
      madeByForger = madeByForger || (! strcmp( ev->kind, "created") && ev->subject == altered && ev->actor == forger);
      stamped      = stamped || (! strcmp( ev->kind, "stamped") && ev->subject == fake && ev->other == c2);
   }
   BG_CHECK( derived && madeByForger);
   BG_CHECK( ! strcmp( [st.w textField:"Information.issuer" of:altered], "the harbour office"));
   /* 5: authority over the warehouse is the office's authorization alone; P′ confers nothing */
   authority = BGAuthorizationsOver( st.w, warehouse);
   BG_CHECK( [authority count] == 1 && [[authority objectAtIndex:0] unsignedLongLongValue] == auth);
   BG_CHECK( BGContentAuthorizes( st.w, permit) && ! BGContentAuthorizes( st.w, altered));
   /* authorize(action): Alun's going into the warehouse has the office's
    * authorization; the forger's, none; neither is blocked by it */
   BG_CHECK( [BGAuthorize( st.w, BGActionMake( "look_in", alun, warehouse, BGNoEntity)) count] == 1);
   BG_CHECK( [BGAuthorize( st.w, BGActionMake( "look_in", forger, warehouse, BGNoEntity)) count] == 0);
   /* 6: the fake stamp, P′, C2 and the forger's creation are found through provenance */
   BG_CHECK( stamped);

   /* A: the clerk makes an exact duplicate, C3: a new copy of P itself */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: C1 to the clerk, at the office"];
   [g move:BGWhole( c1) to:BGHeldBy( clerk, 0)];
   [g move:BGWhole( seal) to:BGHeldBy( clerk, 1)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 5)];
   g = BGPerform( st.w, st.c, BGActionMake( "copy_out", clerk, c1, BGNoEntity), 0, &error);
   BG_CHECK( g != nil);
   [st.s runUntil:BGTimeMake( 6)];
   c3 = BGNoEntity;
   for( i = 0; i < [g count]; i++)
      if( [g proposals][ i].kind == BGProposeCreate)
         c3 = [g idFor:[g proposals][ i].handle];
   BG_CHECK( c3 && [st.w getField:"Inscription.inscribed" of:c3 value:&v] && v == (int64_t) permit);
   BG_CHECK( ! strcmp( [st.w textField:"Inscription.impression" of:c3], "the harbour anchor"));

   /* B: C1 burns; P persists, referenced by the ledger's register and by C3;
    * what referred to C1 resolves to its tombstone; 4 */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: C1 burns"];
   [g destroy:BGWhole( c1) reason:"burnt"];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 7)];
   BG_CHECK( ! [st.w isLive:c1] && [st.w tombstone:c1] != NULL);
   BG_CHECK( [st.w isLive:permit] && [st.w isLive:reg] && [st.w isLive:c3]);
   BG_CHECK( [authority count] == 1);

   /* saved and restored: the content, its derivation, and the authority, the same */
   {
      BGWorld    *w2;
      NSArray    *deferred;
      uint64_t   position;

      w2 = BGRestore( BGSave( st.w, st.c, [NSArray arrayWithObject:knowledge]), [st.w contentBuild], &deferred, &position,
                      &error);
      BG_CHECK( w2 && [w2 stateHash] == [st.w stateHash]);
      BG_CHECK( w2 && [BGAuthorizationsOver( w2, warehouse) count] == 1 && ! BGContentAuthorizes( w2, altered));
   }
}


/* DOMAIN_SIMULATION.md Scenario 2 and COMPONENTS.md §7, latent assembly
 * (provisional): the crank pump `key` (its seed), a "flow loss" committed
 * against it at hour 300, opened two levels by a worker with a wrench at
 * `openAt`; `saveAt`, if not 0: saved then, and opened in the restored world.
 * What was revealed: "role blueprint wear; ..." in role order, and the
 * culprit's role, or "" if none. */
typedef struct
{
   NSString     *parts;
   NSString     *culprit;
   NSString     *menu;          /* the worker's, before opening */
   int64_t      pumpMass;      /* g, after */
   int64_t      total;         /* g, the pump and its parts */
   BOOL         inside;        /* every part partOf the pump */
} BGPumpRun;


static BGPumpRun   pump_open( const char *key, const char *failure, int64_t openAt, int64_t saveAt)
{
   BGStage            st;
   BGProposalGroup    *g;
   BGEntityID         pump;
   BGEntityID         worker;
   BGEntityID         wrench;
   BGStore            *parts;
   BGLocation         at;
   BGMenu             *menu;
   NSMutableArray     *found;
   NSMutableArray     *entries;
   NSString           *error;
   BGPumpRun          run;
   NSUInteger         i;
   int64_t            v;

   memset( &run, 0, sizeof( run));
   st.w   = BGTestWorld( 157);
   st.c   = BGTestCommitter( st.w);
   st.s   = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump house"];
   pump   = [g create:"crank_pump" key:key at:BGOnTile( 5, 5, 0)];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 4, 5, 0)];
   wrench = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   pump   = [g idFor:pump];
   worker = [g idFor:worker];
   wrench = [g idFor:wrench];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"history: a failure"];
   [g set:"Latent.failure" of:BGWhole( pump) toText:failure];
   [g set:"Latent.failedAt" of:BGWhole( pump) to:300 * 3600000LL];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 2)];

   menu    = [BGMenu menuFor:worker world:st.w];
   entries = [NSMutableArray array];
   for( i = 0; i < [menu count]; i++)
      [entries addObject:[menu describeAt:i]];
   run.menu = [entries componentsJoinedByString:@"; "];

   if( saveAt)
   {
      NSString   *text;

      [st.s runUntil:BGTimeMake( saveAt)];
      text = BGSave( st.w, st.c, [NSArray array]);
      error = nil;
      st.w  = restore( text, [st.w contentBuild], &st.c, &error);
      st.s  = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   }
   [st.s runUntil:BGTimeMake( openAt)];
   error = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( openAt + 1000)];
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( openAt + 2000)];

   found       = [NSMutableArray array];
   run.culprit = @"";
   run.inside  = YES;
   parts       = [st.w storeForKind:[st.w kindNamed:"Part"]];
   [st.w getField:"Body.mass" of:pump value:&run.pumpMass];
   run.total = run.pumpMass;
   for( i = 0; i < [parts count]; i++)
   {
      BGEntityID   e;

      e  = [parts entityAtIndex:i];
      at = [st.w locationOf:e];
      run.inside = run.inside && at.form == BGLocationPartOf && at.place == pump;
      [st.w getField:"Part.wear" of:e value:&v];
      [found addObject:[NSString stringWithFormat:@"%s %s %lld", at.role, [st.w info:e]->blueprint, (long long) v]];
      if( v >= 60)
         run.culprit = [NSString stringWithUTF8String:at.role];
      [st.w getField:"Body.mass" of:e value:&v];
      run.total += v;
   }
   run.parts = [found componentsJoinedByString:@"; "];
   return( run);
}


/* DOMAIN_SIMULATION.md Scenario 2's drain: the pump `key` under its header
 * tank (100 L), opened, and its piston taken out: through a leaky outlet
 * valve the tank drains onto the floor; an hour on, how much left the tank,
 * and whether the water is the same in all, every boundary. */
static int64_t   pump_drain( const char *key, BOOL *conserved, BOOL *leaking)
{
   BGStage            st;
   BGFluidDomain      *fluid;
   BGProposalGroup    *g;
   BGEntityID         pump;
   BGEntityID         tank;
   BGEntityID         worker;
   BGEntityID         wrench;
   BGEntityID         piston;
   BGStore            *parts;
   NSString           *error;
   NSUInteger         i;
   int64_t            v;
   int64_t            total;
   int64_t            sum;

   st.w   = BGTestWorld( 163);
   st.c   = BGTestCommitter( st.w);
   fluid  = [[[BGFluidDomain alloc] initWithWorld:st.w] autorelease];
   st.s   = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s addDomain:fluid];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump house"];
   pump   = [g create:"crank_pump" key:key at:BGOnTile( 5, 5, 0)];
   tank   = [g create:"header_tank" key:"the header tank" at:BGOnTile( 5, 5, 0)];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 4, 5, 0)];
   wrench = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   [g set:"Latent.riser" of:BGWhole( pump) to:(int64_t) tank];
   [g set:"Latent.failure" of:BGWhole( pump) toText:"flow_loss"];
   [g set:"Latent.failedAt" of:BGWhole( pump) to:0];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   pump   = [g idFor:pump];
   tank   = [g idFor:tank];
   worker = [g idFor:worker];
   wrench = [g idFor:wrench];
   error  = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 1000)];
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 2000)];
   piston = BGNoEntity;
   parts  = [st.w storeForKind:[st.w kindNamed:"Part"]];
   for( i = 0; i < [parts count]; i++)
      if( ! strcmp( [st.w info:[parts entityAtIndex:i]]->blueprint, "piston"))
         piston = [parts entityAtIndex:i];
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take", worker, piston, BGNoEntity), 0, &error) != nil);
   *conserved = YES;
   total      = 100000;
   while( [st.w time].ms < 3600000)
   {
      if( ! [st.s stepUntil:BGTimeMake( 3600000)])
         [st.s runUntil:BGTimeMake( 3600000)];
      sum = [st.w totalTileWater] + [fluid checkedOutWater];
      if( ! [st.w isCheckedOut:tank] && [st.w getField:"WaterStore.water" of:tank value:&v])
         sum += v;
      *conserved = *conserved && sum == total;
   }
   *leaking = [st.w getField:"Latent.leaking" of:pump value:&v] && v;
   BG_CHECK( [st.w locationOf:piston].form == BGLocationHeldBy);
   /* what left the tank is on the floor (checked out by the domain, or in) */
   [st.w getField:"WaterStore.water" of:tank value:&v];
   return( total - v);
}


/* Check 3's heat: the warm pump (305 K, 18 kJ/K) opened and its piston
 * (1.8 kJ/K) taken out: the piston leaves with its share of the heat, by
 * heat capacity; the total is the same, and both are at 305 K. */
static void   test_pump_heat( void)
{
   BGStage            st;
   BGProposalGroup    *g;
   BGEntityID         pump;
   BGEntityID         worker;
   BGEntityID         wrench;
   BGEntityID         piston;
   BGStore            *parts;
   NSString           *error;
   NSUInteger         i;
   int64_t            pumpHeat;
   int64_t            pumpCap;
   int64_t            pistonHeat;
   int64_t            pistonCap;
   int64_t            v;

   st.w   = BGTestWorld( 167);
   st.c   = BGTestCommitter( st.w);
   st.s   = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a warm pump"];
   pump   = [g create:"warm_pump" key:"pump 1" at:BGOnTile( 5, 5, 0)];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 4, 5, 0)];
   wrench = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   pump   = [g idFor:pump];
   worker = [g idFor:worker];
   wrench = [g idFor:wrench];
   error  = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 1000)];
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 2000)];
   piston = BGNoEntity;
   parts  = [st.w storeForKind:[st.w kindNamed:"Part"]];
   for( i = 0; i < [parts count]; i++)
      if( ! strcmp( [st.w info:[parts entityAtIndex:i]]->blueprint, "piston"))
         piston = [parts entityAtIndex:i];
   /* inside, it has none of its own: its heat is the pump's */
   BG_CHECK( piston && [st.w getField:"ThermalBody.heat" of:piston value:&v] && v == 0);
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take", worker, piston, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 3000)];
   [st.w getField:"ThermalBody.heat" of:pump value:&pumpHeat];
   [st.w getField:"ThermalBody.heatCapacity" of:pump value:&pumpCap];
   [st.w getField:"ThermalBody.heat" of:piston value:&pistonHeat];
   [st.w getField:"ThermalBody.heatCapacity" of:piston value:&pistonCap];
   BG_CHECK( pumpHeat + pistonHeat == 5490000);
   BG_CHECK( pumpCap == 16200 && pistonCap == 1800);
   BG_CHECK( pumpHeat * 1000 / pumpCap == 305000 && pistonHeat * 1000 / pistonCap == 305000);
   BG_CHECK( [st.w getField:"Part.detached" of:piston value:&v] && v == 1);
}


/* ACTIONS.md Scenario 3's steps 3 and 4, and check 2: the worker, with a
 * wrench and a spare leather cup, is to mend the pump `key`. Nothing is bound
 * to the worn part until opening shows one: it opens the pump, a level at a
 * time, sees the worn part, and replaces it. The agency, for its log. */
static BGAgency   *mend_run( const char *key, BGWorld **world, BGEntityID *spare)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGEntityID         pump;
   BGEntityID         worker;

   st.w       = BGTestWorld( 157);       /* as pump_open: the same units, the same culprits */
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump house"];
   pump   = [g create:"crank_pump" key:key at:BGOnTile( 5, 5, 0)];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 4, 5, 0)];
   [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   *spare = [g create:"leather_cup" key:"a spare leather cup" at:BGHeldBy( worker, 1)];
   [g set:"Part.fits" of:BGWhole( *spare) toText:"piston_seal"];
   [g set:"Latent.failure" of:BGWhole( pump) toText:"flow_loss"];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   *spare = [g idFor:*spare];
   BG_CHECK( [agency commit:worker toGoal:"mend_pump"]);
   [st.s runUntil:BGTimeMake( 60000)];
   *world = st.w;
   return( agency);
}


/* COMPONENTS.md Scenario 3, the pump from the component side. The miller
 * owns the hand pump; a flow loss has left it at 20%. The player opens it,
 * takes the piston out (itself an assembly, with the seal inside), opens it,
 * cuts a strip from its own hide, shapes it into a seal, replaces the worn
 * one, and puts the piston back. `inPlace`: the piston opened before it is
 * taken out. The new seal's wear, for reveal-order independence. */
static int64_t   component_pump( BOOL inPlace, BOOL check)
{
   BGStage            st;
   BGThermal          *thermal;
   BGProposalGroup    *g;
   BGEntityID         pump;
   BGEntityID         worker;
   BGEntityID         miller;
   BGEntityID         wrench;
   BGEntityID         hide;
   BGEntityID         claim;
   BGEntityID         mine;
   BGEntityID         piston;
   BGEntityID         seal;
   BGEntityID         strip;
   BGEntityID         source;
   BGStore            *parts;
   NSString           *error;
   NSUInteger         i;
   int64_t            v;
   int64_t            sealWear;
   int64_t            masses;

   st.w    = BGTestWorld( 179);
   st.c    = BGTestCommitter( st.w);
   thermal = [[[BGThermal alloc] initWithWorld:st.w] autorelease];
   st.s    = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:[BGActivities activitiesWithWorld:st.w committer:st.c]];
   [st.s addDomain:thermal];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the miller's pump"];
   pump   = [g create:"hand_pump" key:"the miller's pump" at:BGOnTile( 5, 5, 0)];
   miller = [g create:"smith" key:"the miller" at:BGOnTile( 20, 20, 0)];
   worker = [g create:"worker" key:"the player" at:BGOnTile( 4, 5, 0)];
   wrench = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   hide   = [g create:"hide" key:"the player's hide" at:BGOnTile( 4, 5, 0)];
   claim  = [g create:"ownership" key:"the miller's claim" at:BGLocationMakeNone()];
   [g relate:BGEdgeClaimant from:BGWhole( claim) to:BGWhole( miller)];
   [g relate:BGEdgeClaimSubject from:BGWhole( claim) to:BGWhole( pump)];
   mine   = [g create:"ownership" key:"the player's claim" at:BGLocationMakeNone()];
   [g relate:BGEdgeClaimant from:BGWhole( mine) to:BGWhole( worker)];
   [g relate:BGEdgeClaimSubject from:BGWhole( mine) to:BGWhole( hide)];
   [g set:"Latent.failure" of:BGWhole( pump) toText:"flow_loss"];
   [g set:"Pump.flow" of:BGWhole( pump) to:20];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   pump   = [g idFor:pump];
   miller = [g idFor:miller];
   worker = [g idFor:worker];
   wrench = [g idFor:wrench];
   hide   = [g idFor:hide];
   claim  = [g idFor:claim];
   mine   = [g idFor:mine];
   error  = nil;

   /* 1: opening the cover reveals level 1, carved from the pump */
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 1000)];
   piston = BGNoEntity;
   parts  = [st.w storeForKind:[st.w kindNamed:"Part"]];
   for( i = 0; i < [parts count]; i++)
      if( ! strcmp( [st.w info:[parts entityAtIndex:i]]->blueprint, "nested_piston"))
         piston = [parts entityAtIndex:i];
   masses = 0;
   [st.w getField:"Body.mass" of:pump value:&masses];
   for( i = 0; i < [parts count]; i++)
      if( [st.w getField:"Body.mass" of:[parts entityAtIndex:i] value:&v])
         masses += v;
   if( check)
   {
      BG_CHECK( piston && [st.w locationOf:piston].form == BGLocationPartOf && [parts count] == 5);
      BG_CHECK( masses == 40000);
      /* the piston, the culprit, takes the failure on; it isn't worn itself */
      BG_CHECK( ! strcmp( [st.w textField:"Latent.failure" of:piston], "flow_loss"));
      BG_CHECK( [st.w getField:"Part.wear" of:piston value:&v] && v < 60);
      /* 4: inspection alone changes nothing aggregate */
      BG_CHECK( [st.w getField:"Pump.flow" of:pump value:&v] && v == 20);
      /* 6: inside, the piston joins no domain */
      BG_CHECK( ! [thermal participates:piston]);
   }

   /* 2: the piston out; its nested level opened, in place or out */
   if( inPlace)
   {
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, piston), 0, &error) != nil);
      [st.s runUntil:BGTimeMake( 2000)];
   }
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take", worker, piston, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 2500)];
   if( ! inPlace)
   {
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, piston), 0, &error) != nil);
      [st.s runUntil:BGTimeMake( 3000)];
   }
   if( check)
      BG_CHECK( [st.w locationOf:piston].form == BGLocationHeldBy && [thermal participates:piston]);
   seal = BGNoEntity;
   for( i = 0; i < [parts count]; i++)
      if( [st.w locationOf:[parts entityAtIndex:i]].form == BGLocationPartOf &&
          [st.w locationOf:[parts entityAtIndex:i]].place == piston)
         seal = [parts entityAtIndex:i];
   sealWear = -1;
   [st.w getField:"Part.wear" of:seal value:&sealWear];

   /* 3: a strip cut from the hide; shaped into a seal (the wrench and the
    * piston set down, for hands) */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: hands free for the hide"];
   [g move:BGWhole( wrench) to:BGOnTile( 4, 5, 0)];
   [g move:BGWhole( hide) to:BGHeldBy( worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 4000)];
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "cut_strip", worker, hide, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 5000)];
   strip = BGNoEntity;
   for( i = 0; i < [parts count]; i++)
      if( ! strcmp( [st.w info:[parts entityAtIndex:i]]->blueprint, "leather_strip"))
         strip = [parts entityAtIndex:i];
   if( check)
   {
      /* 2: the strip carved exactly from the hide */
      BG_CHECK( strip && [st.w getField:"Body.mass" of:hide value:&v] && v == 900);
      BG_CHECK( [st.w getField:"Body.mass" of:strip value:&v] && v == 100);
      BG_CHECK( [st.w edges:BGEdgeSplitFrom from:strip into:&source max:1] == 1 && source == hide);
   }
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the strip in hand"];
   [g move:BGWhole( hide) to:BGOnTile( 4, 5, 0)];
   [g move:BGWhole( strip) to:BGHeldBy( worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 6000)];
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "shape_seal", worker, strip, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 7000)];

   /* 4: the new seal installed in the piston, the old one out: the pump's
    * flow changes by the old seal's loss */
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "replace_part", worker, strip, seal), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 13000)];
   if( check)
   {
      BG_CHECK( [st.w locationOf:strip].form == BGLocationPartOf && [st.w locationOf:strip].place == piston);
      BG_CHECK( [st.w locationOf:seal].form == BGLocationOnTile);
      BG_CHECK( [st.w getField:"Pump.flow" of:pump value:&v] && v == 100);
   }

   /* 5: the piston back in its place */
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "install_part", worker, piston, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 14000)];
   if( check)
   {
      BG_CHECK( [st.w locationOf:piston].form == BGLocationPartOf && [st.w locationOf:piston].place == pump);
      /* 6: in again, out of the domain */
      BG_CHECK( ! [thermal participates:piston]);
      /* 5: the miller's claim covers the pump's parts, and the old seal by
       * its provenance; the new seal keeps the player's too: whose it is
       * now is an open question, not settled silently */
      BG_CHECK( [BGClaimsCovering( st.w, piston) containsObject:[NSNumber numberWithUnsignedLongLong:claim]]);
      BG_CHECK( [BGClaimsCovering( st.w, seal) containsObject:[NSNumber numberWithUnsignedLongLong:claim]] &&
                ! BGOwnershipOpen( st.w, seal));
      BG_CHECK( [BGClaimsCovering( st.w, strip) containsObject:[NSNumber numberWithUnsignedLongLong:claim]] &&
                [BGClaimsCovering( st.w, strip) containsObject:[NSNumber numberWithUnsignedLongLong:mine]]);
      BG_CHECK( BGOwnershipOpen( st.w, strip));
      /* 1: every part is part of exactly one assembly, or elsewhere */
      for( i = 0; i < [parts count]; i++)
         BG_CHECK( [st.w locationOf:[parts entityAtIndex:i]].form != BGLocationNone);
   }
   return( sealWear);
}


static void   test_component_pump( void)
{
   int64_t   out;
   int64_t   in;

   out = component_pump( NO, YES);
   /* 3: the nested level opened in place, before the piston comes out,
    * gives the same seal */
   in  = component_pump( YES, NO);
   BG_CHECK( out >= 60 && out == in);
}


/* ACTIONS.md Scenario 3's step 6 and check 7: the piston out of the pump
 * `key`, the worker sets to clean out its cylinder, watching the floor. With
 * the outlet valve leaking, the water rises at its feet: the watch fires
 * within the domain's tolerance (a spreading step, 10 s) of the crossing, and
 * the activity is interrupted, its watch removed. Returns the status. */
static const char   *flood_run( const char *key, int64_t *crossed, int64_t *interrupted, int64_t *watch)
{
   BGStage            st;
   BGFluidDomain      *fluid;
   BGProposalGroup    *g;
   BGEntityID         pump;
   BGEntityID         tank;
   BGEntityID         worker;
   BGEntityID         wrench;
   BGEntityID         piston;
   BGEntityID         a;
   BGStore            *parts;
   NSString           *error;
   NSUInteger         i;

   st.w   = BGTestWorld( 163);
   st.c   = BGTestCommitter( st.w);
   fluid  = [[[BGFluidDomain alloc] initWithWorld:st.w] autorelease];
   st.s   = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:[BGActivities activitiesWithWorld:st.w committer:st.c]];
   [st.s addDomain:fluid];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump house"];
   pump   = [g create:"crank_pump" key:key at:BGOnTile( 5, 5, 0)];
   tank   = [g create:"header_tank" key:"the header tank" at:BGOnTile( 5, 5, 0)];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 4, 5, 0)];
   wrench = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   [g set:"Latent.riser" of:BGWhole( pump) to:(int64_t) tank];
   [g set:"Latent.failure" of:BGWhole( pump) toText:"flow_loss"];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   pump   = [g idFor:pump];
   worker = [g idFor:worker];
   wrench = [g idFor:wrench];
   error  = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 1000)];
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "open_up", worker, wrench, pump), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 2000)];
   piston = BGNoEntity;
   parts  = [st.w storeForKind:[st.w kindNamed:"Part"]];
   for( i = 0; i < [parts count]; i++)
      if( ! strcmp( [st.w info:[parts entityAtIndex:i]]->blueprint, "piston"))
         piston = [parts entityAtIndex:i];
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take", worker, piston, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 3000)];
   g = BGPerform( st.w, st.c, BGActionMake( "clean_out", worker, wrench, pump), 0, &error);
   BG_CHECK( g != nil);
   [st.s runUntil:BGTimeMake( 4000)];
   a      = [g idFor:[g proposals][ 0].handle];
   *watch = -1;
   [st.w getField:"Activity.watchFloor" of:a value:watch];
   *crossed     = 0;
   *interrupted = 0;
   while( [st.w time].ms < 20 * 60000)
   {
      if( ! [st.s stepUntil:BGTimeMake( 20 * 60000)])
         [st.s runUntil:BGTimeMake( 20 * 60000)];
      if( ! *crossed && [st.w waterAtX:4 y:5 level:0] >= 500)
         *crossed = [st.w time].ms;
      if( ! *interrupted && strcmp( status_of( st.w, a), "\"running\""))
         *interrupted = [st.w time].ms;
   }
   [st.w getField:"Activity.watchFloor" of:a value:watch];

   /* DOMAIN_SIMULATION.md Scenario 2's check 5: saved now, the piston
    * out, the puddle as it is, the work suspended; restored with its fluid
    * domain, the next step is the same, to the byte */
   {
      BGStage         st2;
      BGFluidDomain   *fluid2;
      NSString        *text;
      int64_t         next;

      text    = BGSave( st.w, st.c, [NSArray arrayWithObject:fluid]);
      st2.w   = restore( text, [st.w contentBuild], &st2.c, &error);
      fluid2  = [[[BGFluidDomain alloc] initWithWorld:st2.w] autorelease];
      [fluid2 restoreSavedState:BGSavedDomainState( text, @"fluid")];
      st2.s   = [[[BGScheduler alloc] initWithWorld:st2.w committer:st2.c] autorelease];
      [st2.s setActivities:[BGActivities activitiesWithWorld:st2.w committer:st2.c]];
      [st2.s addDomain:fluid2];
      BG_CHECK( st2.w && [st2.w stateHash] == [st.w stateHash]);
      next = [st.w time].ms + 60000;
      [st.s runUntil:BGTimeMake( next)];
      [st2.s runUntil:BGTimeMake( next)];
      BG_CHECK( [BGSave( st2.w, st2.c, [NSArray arrayWithObject:fluid2]) isEqualToString:
                 BGSave( st.w, st.c, [NSArray arrayWithObject:fluid])]);
   }
   return( status_of( st.w, a));
}


/* ACTIONS.md Scenario 3's step 5: dismantling suspended, the wrench taken;
 * resuming is refused, for nothing turns the gland nut; the worker
 * improvises with a spanner, and the dismantling goes on to the end. */
static void   test_improvise( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         smith;
   BGEntityID         wrench;
   BGEntityID         spanner;
   BGEntityID         pump;
   BGEntityID         a;
   NSString           *error;
   int64_t            v;

   st.w       = BGTestWorld( 181);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:activities];
   g       = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the mill"];
   pump    = [g create:"pump" key:"pump" at:BGOnTile( 5, 5, 0)];
   worker  = [g create:"worker" key:"worker" at:BGOnTile( 4, 5, 0)];
   smith   = [g create:"smith" key:"smith" at:BGOnTile( 4, 6, 0)];
   wrench  = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   spanner = [g create:"spanner_19" key:"spanner" at:BGOnTile( 4, 5, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   pump    = [g idFor:pump];
   worker  = [g idFor:worker];
   smith   = [g idFor:smith];
   wrench  = [g idFor:wrench];
   spanner = [g idFor:spanner];
   error   = nil;
   g = BGPerform( st.w, st.c, BGActionMake( "dismantle", worker, wrench, pump), 0, &error);
   BG_CHECK( g != nil);
   [st.s runUntil:BGTimeMake( 4000)];
   a = [g idFor:[g proposals][ 0].handle];
   BG_CHECK( [activities suspend:a because:@"called away" error:&error] != nil);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the smith takes the wrench"];
   [g move:BGWhole( wrench) to:BGHeldBy( smith, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 5000)];
   /* resuming finds nothing to turn the gland nut */
   BG_CHECK( [activities resume:a error:&error] == nil && [error rangeOfString:@"no longer holds"].location != NSNotFound);
   /* the wrench won't do from the smith's hand; a spanner, taken up, will */
   BG_CHECK( [activities improvise:a with:wrench error:&error] == nil);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the worker picks up the spanner"];
   [g move:BGWhole( spanner) to:BGHeldBy( worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 6000)];
   BG_CHECK( [activities improvise:a with:spanner error:&error] != nil);
   [st.s runUntil:BGTimeMake( 7000)];
   BG_CHECK( [st.w getField:"Activity.itemRef" of:a value:&v] && v == (int64_t) spanner);
   BG_CHECK( [activities resume:a error:&error] != nil);
   [st.s runUntil:BGTimeMake( 20000)];
   BG_CHECK( ! strcmp( status_of( st.w, a), "\"completed\""));
   BG_CHECK( [st.w getField:"Pump.opened" of:pump value:&v] && v);
}


static void   test_latent_pump( void)
{
   BGPumpRun   early;
   BGPumpRun   late;
   BGPumpRun   saved;
   BGPumpRun   seized;
   BGPumpRun   other;
   BOOL        seal;
   BOOL        outlet;
   BOOL        none;
   char        key[ 32];
   int         k;

   /* opened two levels: six parts, part of it; 3: its mass carved, not duplicated */
   early = pump_open( "pump 1", "flow_loss", 300 * 3600000LL, 0);
   BG_CHECK( early.inside && [[early.parts componentsSeparatedByString:@"; "] count] == 6);
   BG_CHECK( early.total == 40000 && early.pumpMass < 40000);

   /* 2: deterministic reveal: at hour 400, the same parts and culprit; only
    * the culprit's wear, grown since the failure, differs */
   late = pump_open( "pump 1", "flow_loss", 400 * 3600000LL, 0);
   BG_CHECK( [early.parts isEqualToString:@"handle pump_handle 9; cover pump_cover 8; piston piston 12; "
                                          @"piston_seal leather_cup 60; inlet_valve inlet_valve 0; outlet_valve outlet_valve 2"]);
   BG_CHECK( [late.culprit isEqualToString:early.culprit] && [early.culprit isEqualToString:@"piston_seal"]);
   BG_CHECK( [late.parts isEqualToString:[early.parts stringByReplacingOccurrencesOfString:@"leather_cup 60"
                                                                                withString:@"leather_cup 70"]]);
   /* reloading a save made before opening gives the same */
   saved = pump_open( "pump 1", "flow_loss", 300 * 3600000LL, 200 * 3600000LL);
   BG_CHECK( [saved.parts isEqualToString:early.parts]);

   /* the culprit varies with the unit's seed, among the candidates; the
    * housing is no part at these levels: cause unresolved, none invented */
   seal = outlet = none = NO;
   for( k = 0; k < 24; k++)
   {
      snprintf( key, sizeof( key), "pump %d", k);
      other  = pump_open( key, "flow_loss", 300 * 3600000LL, 0);
      seal   = seal || [other.culprit isEqualToString:@"piston_seal"];
      outlet = outlet || [other.culprit isEqualToString:@"outlet_valve"];
      none   = none || [other.culprit isEqualToString:@""];
      /* 6: the menu before opening says nothing of it */
      BG_CHECK( [other.menu isEqualToString:early.menu]);
   }
   BG_CHECK( seal && outlet && none);
   /* check 1: the piston out, the open cylinder is a path: through the
    * outlet valve, the culprit, the header tank drains onto the floor, the
    * water conserved exactly at every boundary; with the seal the culprit,
    * the valve holds and nothing drains */
   for( k = 0; k < 24; k++)
   {
      snprintf( key, sizeof( key), "pump %d", k);
      if( [pump_open( key, "flow_loss", 300 * 3600000LL, 0).culprit isEqualToString:@"outlet_valve"])
         break;
   }
   {
      BOOL      conserved;
      BOOL      leaking;
      int64_t   floor;

      floor = pump_drain( key, &conserved, &leaking);
      BG_CHECK( leaking && conserved && floor > 10000);
      floor = pump_drain( "pump 1", &conserved, &leaking);
      BG_CHECK( leaking && conserved && floor == 0);
   }

   /* steps 3 and 4: inspection binds the faulty part */
   {
      BGAgency     *agency;
      BGWorld      *w;
      BGEntityID   spare;
      BGLocation   at;

      /* "pump 1": the seal. It opens the pump, a level at a time, with
       * nothing bound to the worn part; seen worn, the seal is replaced
       * with the spare, and the failure is mended */
      agency = mend_run( "pump 1", &w, &spare);
      BG_CHECK( log_index( agency, 2, @"open it further: open_up") < log_index( agency, 2, @"replace the worn part: replace_part"));
      BG_CHECK( logged_by( agency, 2, @"[mend the pump] replace the worn part: replace_part R4 into R8"));
      BG_CHECK( logged_by( agency, 2, @"[mend the pump] done"));
      at = [w locationOf:spare];
      BG_CHECK( at.form == BGLocationPartOf && ! strcmp( at.role, "piston_seal"));
      BG_CHECK( ! strcmp( [w textField:"Latent.failure" of:1], ""));
      /* the housing the culprit: no part is worn, nothing to bind; opened
       * through, it finds none, and none is invented */
      for( k = 0; k < 24; k++)
      {
         snprintf( key, sizeof( key), "pump %d", k);
         if( [pump_open( key, "flow_loss", 300 * 3600000LL, 0).culprit isEqualToString:@""])
            break;
      }
      agency = mend_run( key, &w, &spare);
      BG_CHECK( ! logged_by( agency, 2, @"replace_part"));
      BG_CHECK( logged_by( agency, 2, @"there is nothing further to open"));
      BG_CHECK( [w locationOf:spare].form == BGLocationHeldBy);
   }

   /* check 7: the watch on rising water */
   {
      const char   *status;
      int64_t      crossed;
      int64_t      interrupted;
      int64_t      watch;

      for( k = 0; k < 24; k++)
      {
         snprintf( key, sizeof( key), "pump %d", k);
         if( [pump_open( key, "flow_loss", 300 * 3600000LL, 0).culprit isEqualToString:@"outlet_valve"])
            break;
      }
      /* the outlet valve leaking: the water at its feet reaches 500 mL, and
       * the work is interrupted at that boundary (the tolerance, a spreading
       * step of 10 s), its watch removed */
      status = flood_run( key, &crossed, &interrupted, &watch);
      BG_CHECK( ! strcmp( status, "\"suspended\"") && watch == 0);
      BG_CHECK( crossed > 0 && interrupted >= crossed && interrupted <= crossed + 10000);
      /* the seal at fault: no water; the work runs its ten minutes, its watch removed as it ends */
      status = flood_run( "pump 1", &crossed, &interrupted, &watch);
      BG_CHECK( ! strcmp( status, "\"completed\"") && crossed == 0 && watch == 0);
   }

   /* a failure with no candidates: nothing marked */
   seized = pump_open( "pump 1", "seized", 300 * 3600000LL, 0);
   BG_CHECK( [seized.culprit isEqualToString:@""]);
}


/* ACTIONS.md §2: an office holder's capability, issuing a permit. The
 * harbour office's clerk, its seal in hand, issues Alun a permit for the
 * warehouse, across the town: the permit's content claims the office, the
 * office's authorization is linked to it, and a sealed copy is in Alun's
 * hand. A worker who holds no office can't; and the clerk, who can issue,
 * isn't itself permitted. */
static void   test_issue_permit( void)
{
   BGStage            st;
   BGProposalGroup    *g;
   BGEntityID         office;
   BGEntityID         clerk;
   BGEntityID         worker;
   BGEntityID         alun;
   BGEntityID         seal;
   BGEntityID         warehouse;
   BGEntityID         copy;
   BGEntityID         content;
   BGEntityID         held[ 2];
   NSArray            *auth;
   NSString           *error;
   BGAction           issue;
   int64_t            v;

   st.w      = BGTestWorld( 191);
   st.c      = BGTestCommitter( st.w);
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   g         = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the harbour office"];
   office    = [g create:"harbour_office" key:"the harbour office" at:BGLocationMakeNone()];
   [g set:"Organization.orgName" of:BGWhole( office) toText:"the harbour office"];
   warehouse = [g create:"storeroom" key:"the warehouse" at:BGOnTile( 20, 4, 0)];
   clerk     = [g create:"office_clerk" key:"the clerk" at:BGOnTile( 10, 10, 0)];
   [g set:"OfficeHolder.office" of:BGWhole( clerk) to:(int64_t) office];
   [g set:"Scribe.handwriting" of:BGWhole( clerk) toText:"a clerk's round hand"];
   seal      = [g create:"stamp" key:"the office seal" at:BGHeldBy( clerk, 0)];
   [g set:"Stamp.presses" of:BGWhole( seal) toText:"the harbour anchor"];
   [g set:"Stamp.sealOf" of:BGWhole( seal) toText:"the harbour office"];
   alun      = [g create:"alun" key:"Alun" at:BGOnTile( 11, 10, 0)];
   worker    = [g create:"worker" key:"a worker" at:BGOnTile( 10, 11, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   office    = [g idFor:office];
   warehouse = [g idFor:warehouse];
   clerk     = [g idFor:clerk];
   alun      = [g idFor:alun];
   worker    = [g idFor:worker];

   /* a worker holds no office: it can't issue one */
   error         = nil;
   issue         = BGActionMake( "issue_permit", worker, alun, BGNoEntity);
   issue.content = [st.w intern:"#Container & { place: #OnTile & { x: 20, y: 4, level: 0 } }"];
   BG_CHECK( BGPerform( st.w, st.c, issue, 0, &error) == nil);

   issue.roles[ BGRoleActor] = clerk;
   BG_CHECK( BGPerform( st.w, st.c, issue, 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 2)];

   /* the authorization: the office's, over the warehouse, to Alun */
   auth = BGAuthorize( st.w, BGActionMake( "look_in", alun, warehouse, BGNoEntity));
   BG_CHECK( [auth count] == 1);
   /* the clerk can issue; that is no permission of its own */
   BG_CHECK( [BGAuthorize( st.w, BGActionMake( "look_in", clerk, warehouse, BGNoEntity)) count] == 0);
   /* a sealed copy in Alun's hand, its content claiming the office, and stating the authorization */
   BG_CHECK( [st.w entitiesAt:alun form:BGLocationHeldBy into:held max:2] == 1);
   copy = held[ 0];
   BG_CHECK( [st.w getField:"Inscription.inscribed" of:copy value:&v]);
   content = (BGEntityID) v;
   BG_CHECK( ! strcmp( [st.w textField:"Inscription.impression" of:copy], "the harbour anchor"));
   BG_CHECK( ! strcmp( [st.w textField:"Information.issuer" of:content], "the harbour office"));
   BG_CHECK( BGContentAuthorizes( st.w, content));
   BG_CHECK( [st.w locationOf:content].form == BGLocationNone);
}


/* --- the false alarm -------------------------------------------------------- */

typedef enum
{
   BGAlarmNoRumour = 0,          /* A */
   BGAlarmRumour,                /* B */
   BGAlarmDeflated,              /* C: the rumour has one named source */
   BGAlarmRepeated,              /* D: B, with noise after noise */
   BGAlarmAsked,                 /* C, the long way: B's rumours, both from the neighbour, and Bela asks */
   BGAlarmAutopilot,             /* E: B, the watchman the player's, on autopilot */
   BGAlarmAutopilotQuiet         /* E under A: the noise alone */
} BGAlarm;


typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGAgency      *agency;
   BGEntityID    watchman;
   BGEntityID    carter;
   BGEntityID    porter;
   BGEntityID    storeroom;
   BGEntityID    cat;
   NSArray       *notices;
   NSString      *text;
} BGAlarmRun;


/* AGENCY.md Scenario 2, "the false alarm", in the workshop: the watchman
 * walks past the storeroom, then sits down by the gate to eat supper, eight
 * tiles off, out of sight and in earshot. The carter and the porter tell it
 * someone has been getting into the storeroom (B, D: neither names a source;
 * C: both heard it from the neighbour). Then a cat by the storeroom knocks
 * something over (D: again and again). `tolerance`: the watchman's risk
 * tolerance. */
static BGAlarmRun   false_alarm( BGAlarm variant, int64_t saveAt, int tolerance)
{
   BGStage           st;
   BGActivities      *activities;
   BGKnowledge       *knowledge;
   BGAgency          *agency;
   BGProposalGroup   *g;
   BGEntityID        h[ 8];
   NSString          *error;
   NSString          *source;
   NSString          *rumour;
   BGAlarmRun        run;
   NSString          *text;
   int               i;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 41);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   [st.s addDomain:[[[BGTraces alloc] initWithWorld:st.w] autorelease]];

   g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the storeroom at night"];
   h[ 0] = [g create:"storeroom" key:"storeroom" at:BGOnTile( 12, 4, 0)];
   h[ 1] = [g create:"cat" key:"cat" at:BGOnTile( 12, 5, 0)];
   h[ 2] = [g create:"watchman" key:"watchman" at:BGOnTile( 9, 4, 0)];
   h[ 3] = [g create:"supper" key:"supper" at:BGHeldBy( h[ 2], 0)];
   [g set:"Agent.riskTolerance" of:BGWhole( h[ 2]) to:tolerance];
   h[ 4] = [g create:"carter" key:"carter" at:BGOnTile( 3, 5, 0)];
   h[ 5] = [g create:"porter" key:"porter" at:BGOnTile( 5, 5, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   run.world     = st.w;
   run.knowledge = knowledge;
   run.agency    = agency;
   run.storeroom = [g idFor:h[ 0]];
   run.cat       = [g idFor:h[ 1]];
   run.watchman  = [g idFor:h[ 2]];
   run.carter    = [g idFor:h[ 4]];
   run.porter    = [g idFor:h[ 5]];
   if( variant < BGAlarmAutopilot)
      [agency control:run.watchman];

   /* past the storeroom (it sees it, under the cat's eye), to the gate */
   stage_move( &st, run.watchman, 4, 4);

   /* C, the long way: far off, out of earshot, the neighbour tells the
    * carter and the porter; they come back; they will answer through agency */
   if( variant == BGAlarmAsked)
   {
      BGProposalGroup   *n;
      BGEntityID        neighbour;

      n         = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the neighbour"];
      neighbour = [n create:"neighbour" key:"neighbour" at:BGOnTile( 20, 25, 0)];
      [st.c submit:n];
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
      neighbour = [n idFor:neighbour];
      stage_move( &st, run.carter, 20, 24);
      stage_move( &st, run.porter, 21, 25);
      rumour = @"#IsIn & { what: #Agent, within: #Container & { place: #OnTile & { x: 12, y: 4, level: 0 } }, "
               @"attribution: #Saw & { sure: 30 } }";
      stage_say( &st, neighbour, run.carter, rumour);
      stage_say( &st, neighbour, run.porter, rumour);
      stage_move( &st, run.carter, 3, 5);
      stage_move( &st, run.porter, 5, 5);
      [agency control:run.carter];
      [agency control:run.porter];
   }

   /* the rumour */
   if( variant != BGAlarmNoRumour && variant != BGAlarmAutopilotQuiet)
   {
      source = variant == BGAlarmDeflated
                  ? @"#Heard & { from: #Agent & { material: \"flesh\", hands: 2, coat: \"grey\", mass: 60kg } }"
                  : @"#Heard";
      rumour = [NSString stringWithFormat:@"#IsIn & { what: #Agent, within: #Container & { place: #OnTile & "
                                          @"{ x: 12, y: 4, level: 0 } }, attribution: %@ }", source];
      stage_say( &st, run.carter, run.watchman, rumour);
      stage_say( &st, run.porter, run.watchman, rumour);
   }
   if( variant == BGAlarmAsked)
   {
      /* where did you hear it? both answer: from the neighbour */
      rumour = @"#WhoToldYou & { what: #Agent, within: #Container & { place: #OnTile & { x: 12, y: 4, level: 0 } } }";
      stage_say( &st, run.watchman, run.carter, rumour);
      stage_say( &st, run.watchman, run.porter, rumour);
   }
   stage_move( &st, run.carter, 3, 20);
   stage_move( &st, run.porter, 5, 20);

   /* supper; E: the player puts the watchman on autopilot, to come back for
    * anything worth more than 25 */
   if( variant >= BGAlarmAutopilot)
      BG_CHECK( [agency autopilot:run.watchman toGoal:"eat_supper" threshold:25]);
   else
      BG_CHECK( [agency commit:run.watchman toGoal:"eat_supper"]);
   [st.s runUntil:BGTimeMake( [st.w time].ms + 2000)];

   /* the cat */
   for( i = 0; i < (variant == BGAlarmRepeated ? 5 : 1); i++)
   {
      error = nil;
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "knock_over", [g idFor:h[ 1]], BGNoEntity, BGNoEntity), 0,
                           &error) != nil);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1500)];
   }
   if( saveAt)
   {
      /* saved, restored into a fresh world, and carried on there */
      [st.s runUntil:BGTimeMake( saveAt)];
      text  = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
      error = nil;
      st.w  = restore( text, [st.w contentBuild], &st.c, &error);
      BG_CHECK( st.w != nil);
      activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
      knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
      agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
      st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
      [knowledge restoreSavedState:BGSavedDomainState( text, @"knowledge")];
      [agency restoreSavedState:BGSavedDomainState( text, @"agency")];
      [agency setActivities:activities];
      [st.s setActivities:activities];
      [st.s setPerception:knowledge];
      [st.s setDecision:agency];
      [st.s addDomain:[[[BGTraces alloc] initWithWorld:st.w] autorelease]];
      BG_CHECK( [BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]) isEqualToString:text]);
      run.world     = st.w;
      run.knowledge = knowledge;
      run.agency    = agency;
   }
   [st.s runUntil:BGTimeMake( 120000)];
   run.notices = [agency takeNotices];
   run.text    = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


static NSUInteger   log_count( BGAgency *agency, BGEntityID agent, NSString *text)
{
   NSArray      *log;
   NSUInteger   i;
   NSUInteger   n;

   log = [agency logOf:agent];
   n   = 0;
   for( i = 0; i < [log count]; i++)
      if( [[log objectAtIndex:i] rangeOfString:text].location != NSNotFound)
         n++;
   return( n);
}


static void   test_false_alarm( void)
{
   BGAlarmRun         a;
   BGAlarmRun         b;
   BGAlarmRun         c;
   BGAlarmRun         d;
   BGAlarmRun         again;
   BGAlarmRun         resumed;
   BGAlarmRun         e;
   BGAlarmRun         quiet;
   BGAlarmRun         bold;
   BGAlarmRun         asked;
   BGAlarmRun         timid;
   BGKnowledgeStore   *store;

   a = false_alarm( BGAlarmNoRumour, 0, 50);
   b = false_alarm( BGAlarmRumour, 0, 50);
   c = false_alarm( BGAlarmDeflated, 0, 50);

   /* everyone hears the cat, and makes of it that something stirred by the storeroom */
   BG_CHECK( logged_by( a.agency, a.watchman, @"weighing investigate the disturbance"));
   BG_CHECK( logged_by( c.agency, c.watchman, @"weighing investigate the disturbance"));

   /* 1, 2: credence changes the decision; the margin and the interruption
    * decide the comparison with supper. A: the noise alone, credence 0: 15
    * against supper's 20 + 5 + 5, it stays. B: two rumours whose sources it
    * doesn't know, two groups, credence 20: 35, it switches. C: one named
    * source, one group, credence 15: 30, not more than 30, it stays. */
   BG_CHECK( logged_by( a.agency, a.watchman, @"+15 (credence +0, +20, risk -5) against eat supper +20 (+20) + margin 5 + "
                                              @"interruption 5: staying"));
   BG_CHECK( logged_by( b.agency, b.watchman, @"+35 (credence +20, +20, risk -5) against eat supper +20 (+20) + margin 5 + "
                                              @"interruption 5: switching"));
   BG_CHECK( logged_by( c.agency, c.watchman, @"+30 (credence +15, +20, risk -5) against eat supper +20 (+20) + margin 5 + "
                                              @"interruption 5: staying"));
   BG_CHECK( ! logged_by( a.agency, a.watchman, @"switching") && ! logged_by( c.agency, c.watchman, @"switching"));

   /* C, the long way: B's two rumours, naming no one, but Bela asks each
    * where it came from; both heard it from the neighbour, the groups merge,
    * and credence falls to C's: it stays at supper */
   asked = false_alarm( BGAlarmAsked, 0, 50);
   BG_CHECK( logged_by( asked.agency, asked.watchman, @"+30 (credence +15, +20, risk -5) against eat supper +20 (+20) + "
                                                      @"margin 5 + interruption 5: staying"));
   BG_CHECK( ! happened( asked.world, "looked", asked.watchman, asked.storeroom));

   /* the risk, as risk tolerance weighs it: a bold watchman, in C's
    * conditions, makes nothing of it, 35, and gets up; a timid one, in B's,
    * makes double of it, 30, and stays */
   bold  = false_alarm( BGAlarmDeflated, 0, 100);
   timid = false_alarm( BGAlarmRumour, 0, 0);
   BG_CHECK( logged_by( bold.agency, bold.watchman, @"+35 (credence +15, +20, risk +0) against eat supper +20 (+20) + "
                                                    @"margin 5 + interruption 5: switching"));
   BG_CHECK( happened( bold.world, "looked", bold.watchman, bold.storeroom));
   BG_CHECK( logged_by( timid.agency, timid.watchman, @"+30 (credence +20, +20, risk -10) against eat supper +20 (+20) + "
                                                      @"margin 5 + interruption 5: staying"));
   BG_CHECK( ! happened( timid.world, "looked", timid.watchman, timid.storeroom));
   BG_CHECK( ! happened( a.world, "looked", a.watchman, a.storeroom) && ! happened( c.world, "looked", c.watchman, c.storeroom));

   /* B: it puts supper down, looks, and goes back to it, resuming where it left off */
   BG_CHECK( logged_by( b.agency, b.watchman, @"suspending eat"));
   BG_CHECK( happened( b.world, "looked", b.watchman, b.storeroom));
   BG_CHECK( logged_by( b.agency, b.watchman, @"[investigate the disturbance] done"));
   BG_CHECK( logged_by( b.agency, b.watchman, @"back to it: investigate the disturbance is done"));
   BG_CHECK( logged_by( b.agency, b.watchman, @"[eat supper] eat: resuming eat"));
   BG_CHECK( logged_by( b.agency, b.watchman, @"[eat supper] done"));
   BG_CHECK( log_index( b.agency, b.watchman, @"switching") < log_index( b.agency, b.watchman, @"resuming eat"));

   /* 4: no one was there: the claim is found false, and it trusts the carter
    * and the porter less */
   store = [b.knowledge storeOf:b.watchman];
   BG_CHECK( [store testimonyCount] == 2 && [store testimonyAt:0]->settled == -1 && [store testimonyAt:1]->settled == -1);
   BG_CHECK( [store trustIn:referent_of( store, b.carter)] == BG_TRUST - BG_REFUTED);
   BG_CHECK( [store trustIn:referent_of( store, b.porter)] == BG_TRUST - BG_REFUTED);
   /* untested, in A and C */
   store = [c.knowledge storeOf:c.watchman];
   BG_CHECK( [store trustIn:referent_of( store, c.carter)] == BG_TRUST);

   /* 3: no dithering: noise after noise, the intention changes once */
   d = false_alarm( BGAlarmRepeated, 0, 50);
   BG_CHECK( log_count( d.agency, d.watchman, @"switching") == 1);
   BG_CHECK( log_count( d.agency, d.watchman, @"staying") == 0);
   BG_CHECK( log_count( d.agency, d.watchman, @"suspending eat") == 1);
   BG_CHECK( happened( d.world, "looked", d.watchman, d.storeroom));

   /* 6: determinism */
   again = false_alarm( BGAlarmRumour, 0, 50);
   BG_CHECK( [again.world stateHash] == [b.world stateHash]);
   BG_CHECK( [again.text isEqualToString:b.text]);
   BG_CHECK( [[again.agency logOf:again.watchman] isEqualToArray:[b.agency logOf:b.watchman]]);

   /* saved mid-investigation, supper suspended beneath it, restored: the same
    * end (a boundary the run has: a step toward the storeroom) */
   resumed = false_alarm( BGAlarmRumour, 10003, 50);
   BG_CHECK( [resumed.world stateHash] == [b.world stateHash]);
   BG_CHECK( [resumed.text isEqualToString:b.text]);
   BG_CHECK( logged_by( resumed.agency, resumed.watchman, @"[eat supper] eat: resuming eat"));

   /* 5: E, autopilot: in B's conditions, the noise is worth more than the
    * player's 25: control returns at that weighing, supper still under way,
    * nothing looked into; autopilot used nothing the watchman didn't know */
   e = false_alarm( BGAlarmAutopilot, 0, 50);
   BG_CHECK( [e.notices count] == 1 &&
             [[e.notices objectAtIndex:0] isEqualToString:@"Control returns to you: investigate the disturbance (R2) is "
                                                         @"worth +35, more than your +25."]);
   BG_CHECK( ! [e.agency controls:e.watchman]);
   BG_CHECK( ! logged_by( e.agency, e.watchman, @"switching") && ! logged_by( e.agency, e.watchman, @"suspending"));
   BG_CHECK( ! happened( e.world, "looked", e.watchman, e.storeroom));
   /* 5: autopilot uses nothing Bela lacks: what it weighed is Bela's
    * belief, from the rumours and the clatter it heard, that someone is in
    * the storeroom (R2), a someone with no truth behind it at all */
   store = [e.knowledge storeOf:e.watchman];
   BG_CHECK( referent_of( store, e.storeroom) == 2);
   BG_CHECK( [store finding:"#Disturbance" about:2] != NULL);
   {
      const BGReferent   *r;
      NSUInteger         i;
      BOOL               intruder;

      intruder = NO;
      for( i = 0; i < [store count]; i++)
      {
         r = [store referentAt:i];
         intruder = intruder || (r->form == BGLocationIn && r->container == 2 && r->truth == 0 &&
                                 ! strcmp( r->kind, "#Agent"));
      }
      BG_CHECK( intruder);
   }
   /* in A's, it eats on, and hands back when supper is done */
   quiet = false_alarm( BGAlarmAutopilotQuiet, 0, 50);
   BG_CHECK( [quiet.notices count] == 1 &&
             [[quiet.notices objectAtIndex:0] isEqualToString:@"Control returns to you: there is nothing left to do."]);
   BG_CHECK( logged_by( quiet.agency, quiet.watchman, @"[eat supper] done"));
}


/* Autopilot in a session: the worker looks into the bin, then hands itself
 * to agency to wedge the lock; it fetches nails, drives one, and control
 * returns. */
static void   test_play_autopilot( void)
{
   NSArray    *commands;
   NSString   *out;
   NSString   *again;
   uint64_t   h1;
   uint64_t   h2;

   commands = [NSArray arrayWithObjects:@"do 1", @"autopilot wedge_lock 100", @"autopilot nonesuch", @"menu", nil];
   out   = session( @"workshop", commands, &h1);
   again = session( @"workshop", commands, &h2);
   BG_CHECK( h1 == h2 && [out isEqualToString:again]);
   BG_CHECK( [out rangeOfString:@"Autopilot: wedge_lock, until something is worth more than 100."].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"action 4: take_some item 2"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"drive completes"].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"Control returns to you: there is nothing left to do."].location != NSNotFound);
   BG_CHECK( [out rangeOfString:@"There is no goal nonesuch."].location != NSNotFound);
}


/* --- the tempting purse ----------------------------------------------------- */

typedef enum
{
   BGPurseBase = 0,
   BGPurseNoticed,               /* A: Mira isn't hiding, and Kasimir sees her */
   BGPurseHonest,                /* B: an honest Kasimir, the same debt */
   BGPurseNoWitness,             /* C: Mira isn't there */
   BGPurseRepaid,                /* B, and on until the loan's term is out */
   BGPurseLost                   /* that, but the wages are lost on the third day */
} BGPurse;


typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGAgency      *agency;
   BGEntityID    purse;
   BGEntityID    kasimir;
   BGEntityID    mira;
   BGEntityID    merchant;
   BGEntityID    carter;
   BGEntityID    wages;
   BOOL          owedLate;      /* the wages still Kasimir's on the sixth day */
   NSString      *text;
} BGPurseRun;


/* AGENCY.md Scenario 3, "the tempting purse": a purse on the counter, the
 * merchant's; Kasimir, who owes, beside it; the carter across the room, a
 * friend to borrow from; and Mira, half hidden in a doorway, who sees
 * Kasimir, unseen. The merchant turns away to serve someone out of sight,
 * and Kasimir's debt falls due. Later the merchant comes back and asks Mira
 * where the purse is. */
static BGPurseRun   tempting_purse( BGPurse variant)
{
   BGStage           st;
   BGActivities      *activities;
   BGKnowledge       *knowledge;
   BGAgency          *agency;
   BGProposalGroup   *g;
   BGEntityID        h[ 8];
   BGPurseRun        run;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 43);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];

   g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the market stall"];
   h[ 0] = [g create:"purse" key:"purse" at:BGOnTile( 10, 10, 0)];
   h[ 1] = [g create:"merchant" key:"merchant" at:BGOnTile( 11, 10, 0)];
   h[ 2] = [g create:"kasimir" key:"kasimir" at:BGOnTile( 9, 10, 0)];
   h[ 3] = [g create:"carter" key:"carter" at:BGOnTile( 5, 10, 0)];
   h[ 5] = [g create:"purse" key:"the carter's wages" at:BGHeldBy( h[ 3], 0)];
   h[ 4] = BGNoEntity;
   if( variant != BGPurseNoWitness)
   {
      h[ 4] = [g create:"mira" key:"mira" at:BGOnTile( 12, 12, 0)];
      if( variant == BGPurseNoticed)
         [g set:"Agent.hiding" of:BGWhole( h[ 4]) to:0];
   }
   if( variant == BGPurseHonest || variant == BGPurseRepaid || variant == BGPurseLost)
      [g set:"Agent.honesty" of:BGWhole( h[ 2]) to:90];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   run.world     = st.w;
   run.knowledge = knowledge;
   run.agency    = agency;
   run.purse     = [g idFor:h[ 0]];
   run.merchant  = [g idFor:h[ 1]];
   run.kasimir   = [g idFor:h[ 2]];
   run.carter    = [g idFor:h[ 3]];
   run.wages     = [g idFor:h[ 5]];
   [agency control:run.carter];
   run.mira      = h[ 4] ? [g idFor:h[ 4]] : BGNoEntity;
   if( run.mira)
      [agency control:run.mira];

   /* the merchant turns away, out of sight */
   stage_move( &st, run.merchant, 25, 10);

   /* the debt falls due */
   BG_CHECK( [agency commit:run.kasimir toGoal:"get_money"]);
   [st.s runUntil:BGTimeMake( 30000)];

   /* the merchant comes back, by Mira, and asks her where the purse is */
   if( run.mira)
   {
      stage_move( &st, run.merchant, 12, 13);
      stage_say( &st, run.merchant, run.mira, @"#WhereIs & { what: #Body & { material: \"cloth\" } }");
   }
   [st.s runUntil:BGTimeMake( 90000)];
   if( variant == BGPurseRepaid || variant == BGPurseLost)
   {
      if( variant == BGPurseLost)
      {
         [st.s runUntil:BGTimeMake( 3 * 86400000LL)];
         g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the wages lost"];
         [g destroy:BGWhole( run.wages) reason:"lost"];
         [st.c submit:g];
      }
      /* still owed on the sixth day; handed back on the seventh */
      [st.s runUntil:BGTimeMake( 6 * 86400000LL - 60000)];
      run.owedLate = [st.w locationOf:run.wages].place == run.kasimir;
      [st.s runUntil:BGTimeMake( 7 * 86400000LL + 60000)];
   }
   run.text = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


/* The promise the source made the agent, or NULL. */
static const BGTestimony   *pledge_from( BGKnowledgeStore *store, uint32_t source)
{
   NSUInteger   i;

   for( i = 0; i < [store testimonyCount]; i++)
      if( [store testimonyAt:i]->attribution == BGPledged && [store testimonyAt:i]->source == source)
         return( [store testimonyAt:i]);
   return( NULL);
}


static void   test_tempting_purse( void)
{
   BGPurseRun         base;
   BGPurseRun         noticed;
   BGPurseRun         honest;
   BGPurseRun         alone;
   BGPurseRun         again;
   BGPurseRun         repaid;
   BGPurseRun         lost;
   BGKnowledgeStore   *store;
   const BGReferent   *purse;
   const BGTestimony  *t;
   NSUInteger         i;
   BOOL               saw;

   base = tempting_purse( BGPurseBase);

   /* 1, 4: the debt drives the goal; Kasimir believes no one is watching
    * (the merchant is gone, Mira unseen), so taking the purse scores best,
    * though a witness is truly there */
   BG_CHECK( logged_by( base.agency, base.kasimir, @"take the purse +20 (+30, honesty -5, scruples -5, unwatched +0)"));
   BG_CHECK( logged_by( base.agency, base.kasimir, @"borrow from a friend +10 (+10)"));
   BG_CHECK( logged_by( base.agency, base.kasimir, @"[get money] take the purse: take R"));
   BG_CHECK( [base.world locationOf:base.purse].form == BGLocationHeldBy &&
             [base.world locationOf:base.purse].place == base.kasimir);
   BG_CHECK( ! referent_of( [base.knowledge storeOf:base.kasimir], base.mira));

   /* 5: Mira saw it, and keeps it: curious, she notices what is routine to others */
   store = [base.knowledge storeOf:base.mira];
   saw   = NO;
   for( i = 0; i < [store observationCount]; i++)
      if( ! strcmp( [store observationAt:i]->kind, "moved") &&
          [store observationAt:i]->actor == referent_of( store, base.kasimir) &&
          [store observationAt:i]->subject == referent_of( store, base.purse))
         saw = YES;
   BG_CHECK( saw);
   /* asked, she tells the merchant that Kasimir has it, and the merchant believes her */
   BG_CHECK( logged_by( base.agency, base.mira, @"answering: say R"));
   store = [base.knowledge storeOf:base.merchant];
   purse = [store referent:referent_of( store, base.purse)];
   BG_CHECK( purse && purse->present && purse->form == BGLocationHeldBy &&
             purse->container == referent_of( store, base.kasimir));
   t = [store testimonyCount] ? [store testimonyAt:0] : NULL;
   BG_CHECK( t && t->source == referent_of( store, base.mira) && t->attribution == BGSaw &&
             t->thing == purse->id && t->container == referent_of( store, base.kasimir));
   /* and when it sees Kasimir with it, so it is: it trusts Mira more */
   BG_CHECK( t && t->settled == 1 && [store trustIn:t->source] == BG_TRUST + BG_CONFIRMED);

   /* 2: A: Kasimir sees Mira, believes himself watched, and taking scores
    * below nothing: unthinkable. He borrows instead: Mira has nothing to
    * lend, and the carter lends him his wages */
   noticed = tempting_purse( BGPurseNoticed);
   BG_CHECK( referent_of( [noticed.knowledge storeOf:noticed.kasimir], noticed.mira));
   BG_CHECK( logged_by( noticed.agency, noticed.kasimir, @"take the purse -20 (+30, honesty -5, scruples -5, watched -40)"));
   BG_CHECK( logged_by( noticed.agency, noticed.kasimir, @"borrow from a friend: say R"));
   BG_CHECK( logged_by( noticed.agency, noticed.kasimir, @"answered: #HaveNone"));
   BG_CHECK( logged_by( noticed.agency, noticed.kasimir, @"answered: #Granted"));
   BG_CHECK( logged_by( noticed.agency, noticed.kasimir, @"[get money] done"));
   BG_CHECK( [noticed.world locationOf:noticed.purse].form == BGLocationOnTile);
   BG_CHECK( [noticed.world locationOf:noticed.wages].form == BGLocationHeldBy &&
             [noticed.world locationOf:noticed.wages].place == noticed.kasimir);

   /* 3: B: an honest Kasimir, unwatched, never takes it; asked, the carter
    * weighs lending at its trust in him less the parting, and lends */
   honest = tempting_purse( BGPurseHonest);
   BG_CHECK( logged_by( honest.agency, honest.kasimir, @"take the purse -20 (+30, honesty -45, scruples -5, unwatched +0)"));
   BG_CHECK( ! logged_by( honest.agency, honest.kasimir, @"take R"));
   BG_CHECK( [honest.world locationOf:honest.purse].form == BGLocationOnTile);
   BG_CHECK( logged_by( honest.agency, honest.carter, @"worth +5, granting"));
   BG_CHECK( logged_by( honest.agency, honest.carter, @"granting: give R"));
   BG_CHECK( [honest.world locationOf:honest.wages].place == honest.kasimir);
   BG_CHECK( logged_by( noticed.agency, noticed.mira, @"for something it hasn't"));
   /* a loan is a debt (AGENCY.md §7): Kasimir owes the carter its wages
    * back within the week, a commitment, saved like any other */
   BG_CHECK( logged_by( honest.agency, honest.kasimir, @"owes R"));
   BG_CHECK( [honest.text rangeOfString:@" repay "].location != NSNotFound &&
             [honest.text rangeOfString:@" debt "].location != NSNotFound);
   /* kept on the loan's last day, not before: the wages back in the carter's hand */
   repaid = tempting_purse( BGPurseRepaid);
   BG_CHECK( repaid.owedLate);
   BG_CHECK( logged_by( repaid.agency, repaid.kasimir, @"hand it back: give R"));
   BG_CHECK( [repaid.world locationOf:repaid.wages].form == BGLocationHeldBy &&
             [repaid.world locationOf:repaid.wages].place == repaid.carter);
   /* and promised so (§7): the carter holds it as a claim about the
    * seventh day, kept when the wages are back in its hand, and trusts
    * Kasimir more */
   BG_CHECK( logged_by( repaid.agency, repaid.kasimir, @"promising: say R"));
   store = [repaid.knowledge storeOf:repaid.carter];
   t     = pledge_from( store, referent_of( store, repaid.kasimir));
   BG_CHECK( t && t->settled == 1 && t->container == [store selfReferent]);
   BG_CHECK( [store trustIn:referent_of( store, repaid.kasimir)] == BG_TRUST + BG_CONFIRMED);
   /* lost on the third day, it can't be: due, the carter, with Kasimir in
    * sight and nothing back in its hand, finds the promise broken */
   lost = tempting_purse( BGPurseLost);
   store = [lost.knowledge storeOf:lost.carter];
   t     = pledge_from( store, referent_of( store, lost.kasimir));
   BG_CHECK( t && t->settled == -1);
   BG_CHECK( [store trustIn:referent_of( store, lost.kasimir)] == BG_TRUST - BG_REFUTED);

   /* 1: C: no one is there, and Kasimir decides just the same */
   alone = tempting_purse( BGPurseNoWitness);
   BG_CHECK( [[alone.agency logOf:alone.kasimir] isEqualToArray:[base.agency logOf:base.kasimir]]);

   /* 6: determinism */
   again = tempting_purse( BGPurseBase);
   BG_CHECK( [again.world stateHash] == [base.world stateHash]);
   BG_CHECK( [again.text isEqualToString:base.text]);
}


/* AGENCY.md §7: in the workshop, the smith, having looked into the bin,
 * promises the worker beside it that the nails will be in the crate by the
 * deadline. The worker looks into the crate once early, and once after. */
typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGAgency      *agency;
   BGEntityID    crate;
   int           earlySettled;   /* the worker's promise testimony, after looking early */
   NSString      *text;
} BGPromiseRun;


static void   look_into( BGStage *st, BGEntityID agent, BGEntityID container, int32_t x, int32_t y)
{
   NSString   *error;

   stage_move( st, agent, x, y);
   error = nil;
   BG_CHECK( BGPerform( st->w, st->c, BGActionMake( "look_in", agent, container, BGNoEntity), 0, &error) != nil);
   [st->s runUntil:BGTimeMake( [st->w time].ms + 500)];
}


static BGPromiseRun   promise_run( int64_t deadline)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGKnowledgeStore   *smith;
   BGProposalGroup    *g;
   BGEntityID         h[ 8];
   NSString           *error;
   BGPromiseRun       run;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 59);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   [st.c submit:BGWorkshopSetup( NO, h)];
   [st.s runUntil:BGTimeMake( 1)];
   g         = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the crate"];
   run.crate = [g create:"crate" key:"crate" at:BGOnTile( 6, 4, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 2)];
   run.crate = [g idFor:run.crate];

   /* the smith looks into the bin; the worker stands beside it */
   error = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "look_in", 5, 1, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 3)];
   stage_move( &st, 4, 3, 5);

   /* the promise */
   smith = [knowledge storeOf:5];
   BG_CHECK( [agency promise:5 to:referent_of( smith, 4) goods:referent_of( smith, 2) in:referent_of( smith, run.crate)
                          by:[st.w time].ms + deadline]);
   [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];

   /* the worker looks into the crate early: not due, nothing settled */
   look_into( &st, 4, run.crate, 7, 5);
   run.earlySettled = [[knowledge storeOf:4] testimonyCount] ? [[knowledge storeOf:4] testimonyAt:0]->settled : 9;
   stage_move( &st, 4, 3, 7);

   /* after the deadline, it looks again */
   [st.s runUntil:BGTimeMake( [st.w time].ms + deadline + 5000)];
   look_into( &st, 4, run.crate, 7, 5);
   run.world     = st.w;
   run.knowledge = knowledge;
   run.agency    = agency;
   run.text      = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


static void   test_promises( void)
{
   BGPromiseRun        kept;
   BGPromiseRun        broken;
   BGPromiseRun        again;
   BGKnowledgeStore    *store;
   const BGTestimony   *t;

   /* kept: the promise is the smith's commitment, and it delivers */
   kept = promise_run( 60000);
   BG_CHECK( logged_by( kept.agency, 5, @"promising: say R"));
   BG_CHECK( logged_by( kept.agency, 5, @"weighing deliver it: +20 (promise, duty +20, urgency +0) against nothing: switching"));
   BG_CHECK( logged_by( kept.agency, 5, @"[hold it] pick it up: take R"));
   BG_CHECK( logged_by( kept.agency, 5, @"[deliver it] bring it: put_in R"));
   BG_CHECK( logged_by( kept.agency, 5, @"[deliver it] done"));
   BG_CHECK( [kept.world locationOf:2].form == BGLocationIn && [kept.world locationOf:2].place == kept.crate);
   /* the worker held it as a promise, about then: looking early settled nothing; after, kept, and it trusts the smith more */
   store = [kept.knowledge storeOf:4];
   t     = [store testimonyCount] ? [store testimonyAt:0] : NULL;
   BG_CHECK( t && t->attribution == BGPledged && t->source == referent_of( store, 5));
   BG_CHECK( kept.earlySettled == 0);
   BG_CHECK( t && t->settled == 1 && [store trustIn:t->source] == BG_TRUST + BG_CONFIRMED);
   BG_CHECK( [[kept.knowledge dump:4] rangeOfString:@"promised, root R"].location != NSNotFound);

   /* broken: three seconds isn't enough; the window closes, the promise is
    * broken, and the worker, finding the crate empty after the deadline,
    * trusts the smith less */
   broken = promise_run( 3000);
   BG_CHECK( logged_by( broken.agency, 5, @"deliver it is over: its window has closed; the promise is broken"));
   BG_CHECK( [broken.world locationOf:2].form != BGLocationIn || [broken.world locationOf:2].place != broken.crate);
   store = [broken.knowledge storeOf:4];
   t     = [store testimonyCount] ? [store testimonyAt:0] : NULL;
   BG_CHECK( broken.earlySettled == 0);
   BG_CHECK( t && t->settled == -1 && [store trustIn:t->source] == BG_TRUST - BG_REFUTED);

   /* the same on replay */
   again = promise_run( 60000);
   BG_CHECK( [again.text isEqualToString:kept.text]);
}


/* --- two hands, one seal ---------------------------------------------------- */

/* ACTIONS.md Scenario 2's conflict, on the committer: the spare seal on the
 * bench, reserved for A (the worker); A and B (the smith) take it at the same
 * boundary. 1 if A gets it, 2 if B does. `swap` creates B first, so their
 * IDs swap. */
static int   seal_race( uint64_t seed, int64_t quickA, int64_t quickB, BOOL swap)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGProposalGroup   *g;
   BGProposalGroup   *ga;
   BGProposalGroup   *gb;
   BGEntityID        seal;
   BGEntityID        a;
   BGEntityID        b;
   BGEntityID        claim;

   w    = BGTestWorld( seed);
   c    = BGTestCommitter( w);
   g    = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the bench"];
   seal = [g create:"seal" key:"seal" at:BGOnTile( 6, 6, 0)];
   b    = swap ? [g create:"smith" key:"B" at:BGOnTile( 7, 6, 0)] : BGNoEntity;
   a    = [g create:"worker" key:"A" at:BGOnTile( 5, 6, 0)];
   if( ! swap)
      b = [g create:"smith" key:"B" at:BGOnTile( 7, 6, 0)];
   claim = [g create:"reservation" key:"A's reservation" at:BGLocationMakeNone()];
   [g relate:BGEdgeClaimant from:BGWhole( claim) to:BGWhole( a)];
   [g relate:BGEdgeClaimSubject from:BGWhole( claim) to:BGWhole( seal)];
   [g set:"Agent.quickness" of:BGWhole( a) to:quickA];
   [g set:"Agent.quickness" of:BGWhole( b) to:quickB];
   [c submit:g];
   [c commitBoundary];
   seal = [g idFor:seal];
   a    = [g idFor:a];
   b    = [g idFor:b];
   [w setBoundary:7];
   ga = [BGProposalGroup groupWithPhase:BGPhaseAction source:@"A takes the seal"];
   [ga setActor:a];
   [ga move:BGWhole( seal) to:BGHeldBy( a, 0) expecting:BGOnTile( 6, 6, 0)];
   gb = [BGProposalGroup groupWithPhase:BGPhaseAction source:@"B takes the seal"];
   [gb setActor:b];
   [gb move:BGWhole( seal) to:BGHeldBy( b, 0) expecting:BGOnTile( 6, 6, 0)];
   [c submit:ga];
   [c submit:gb];
   [c commitBoundary];
   if( [ga applied] == [gb applied])
      return( 0);
   return( [ga applied] ? 1 : 2);
}


/* The scenario with activities: A and B start taking the seal up at the
 * same boundary; B, if `agency`, decides for itself, `respectful` of
 * reservations it knows of, and A tells it first that the seal is A's: by
 * saying so (1), or by a tag beside the seal B sights, legible from a step
 * away (2) or only from on it (3). */
typedef struct
{
   BGWorld       *world;
   BGCommitter   *committer;
   BGKnowledge   *knowledge;
   BGAgency      *agency;
   BGEntityID    seal;
   BGEntityID    a;
   BGEntityID    b;
} BGSealRun;


static BGSealRun   seal_scene( uint64_t seed, int agency, int64_t respectful)
{
   BGStage           st;
   BGActivities      *activities;
   BGKnowledge       *knowledge;
   BGAgency          *minds;
   BGProposalGroup   *g;
   BGEntityID        h[ 3];
   NSString          *error;
   NSString          *reserved;
   BGAction          action;
   BGSealRun         run;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( seed);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   minds      = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [minds setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:minds];
   g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the bench"];
   h[ 0] = [g create:"seal" key:"seal" at:BGOnTile( 6, 6, 0)];
   h[ 1] = [g create:"worker" key:"A" at:BGOnTile( 5, 6, 0)];
   h[ 2] = [g create:"smith" key:"B" at:BGOnTile( 6, 7, 0)];
   [g set:"Agent.respectful" of:BGWhole( h[ 2]) to:respectful];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   run.seal = [g idFor:h[ 0]];
   run.a    = [g idFor:h[ 1]];
   run.b    = [g idFor:h[ 2]];
   if( agency)
   {
      /* A tells B the seal is A's; B wants it */
      reserved = [[knowledge storeOf:run.a] reservationOf:referent_of( [knowledge storeOf:run.a], run.seal)
                                                      for:[[knowledge storeOf:run.a] selfReferent]];
      error = nil;
      if( agency == 1)
      {
         action         = BGActionMake( "say", run.a, run.b, BGNoEntity);
         action.content = [st.w intern:[reserved UTF8String]];
         BG_CHECK( BGPerform( st.w, st.c, action, 0, &error) != nil);
      }
      else
      {
         /* a tag beside it, in A's hand: B sights it */
         g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: A's tag"];
         h[ 0] = [g create:"seal_tag" key:"tag" at:BGOnTile( 6, 6, 0)];
         [g set:"Record.writing" of:BGWhole( h[ 0])
         toText:[st.w intern:[[NSString stringWithFormat:@"#Writing & { author: %@, entries: [%@] }",
                                [[knowledge storeOf:run.a] describeLooks:[[knowledge storeOf:run.a] selfReferent]],
                                reserved] UTF8String]]];
         if( agency == 3)
            [g set:"Label.legible" of:BGWhole( h[ 0]) to:0];
         [st.c submit:g];
      }
      [st.s runUntil:BGTimeMake( 1000)];
      BG_CHECK( [minds commit:run.b toGoal:"get_the_seal"]);
      /* A starts as B's decision does: both takes complete at one boundary */
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1)];
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take_up", run.a, run.seal, BGNoEntity), 0, &error) != nil);
   }
   else
   {
      error = nil;
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take_up", run.a, run.seal, BGNoEntity), 0, &error) != nil);
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take_up", run.b, run.seal, BGNoEntity), 0, &error) != nil);
   }
   [st.s runUntil:BGTimeMake( 6000)];
   run.world     = st.w;
   run.committer = st.c;
   run.knowledge = knowledge;
   run.agency    = minds;
   return( run);
}


static void   test_two_hands( void)
{
   BGSealRun          race;
   BGSealRun          respect;
   BGSealRun          ignore;
   BGKnowledgeStore   *store;
   const BGReferent   *seal;
   NSString           *trace;
   BGEntityID         winner;
   BGEntityID         loser;
   uint64_t           seed;
   int                a;
   int                swapped;
   int                weighted;
   int                w;

   /* 1, 2: exactly one take applies; the other is rejected whole, and its
    * activity fails with the reason; the loser sees the seal in the winner's
    * hand */
   race = seal_scene( 61, NO, 50);
   BG_CHECK( [race.world locationOf:race.seal].form == BGLocationHeldBy);
   winner = [race.world locationOf:race.seal].place;
   loser  = winner == race.a ? race.b : race.a;
   BG_CHECK( winner == race.a || winner == race.b);
   trace = [[race.committer trace] componentsJoinedByString:@"\n"];
   BG_CHECK( [trace rangeOfString:@": failed ("].location != NSNotFound);
   store = [race.knowledge storeOf:loser];
   seal  = [store referent:referent_of( store, race.seal)];
   BG_CHECK( seal && seal->form == BGLocationHeldBy && seal->container == referent_of( store, winner));

   /* 3, 5, 6: fair: with equal weights, over 1,000 seeds, each wins about
    * half; swapping their IDs leaves that so; the reservation blocks
    * nothing; the same seed, the same winner */
   a        = 0;
   swapped  = 0;
   weighted = 0;
   for( seed = 1; seed <= 1000; seed++)
   {
      w = seal_race( seed, 10, 10, NO);
      BG_CHECK( w != 0);
      if( w == 1)
         a++;
      if( seal_race( seed, 10, 10, YES) == 1)
         swapped++;
      /* 4: weighted 1 to 3, B wins about three times in four */
      if( seal_race( seed, 10, 30, NO) == 2)
         weighted++;
   }
   BG_CHECK( a > 430 && a < 570);
   BG_CHECK( swapped > 430 && swapped < 570);
   BG_CHECK( weighted > 700 && weighted < 800);
   BG_CHECK( seal_race( 77, 10, 10, NO) == seal_race( 77, 10, 10, NO));

   /* A: B, told the seal is A's and disposed to respect that, never starts:
    * taking it scores below nothing; A takes it */
   respect = seal_scene( 61, YES, 50);
   BG_CHECK( logged_by( respect.agency, respect.b, @"take the seal -30 (+10, reserved -40)"));
   BG_CHECK( ! logged_by( respect.agency, respect.b, @"take_up R"));
   BG_CHECK( [respect.world locationOf:respect.seal].place == respect.a);
   /* or B sights a tag beside the seal saying so, a step away, and reads
    * it at a glance (ACTIONS.md §7's physical marker): the same */
   respect = seal_scene( 61, 2, 50);
   BG_CHECK( logged_by( respect.agency, respect.b, @"take the seal -30 (+10, reserved -40)"));
   BG_CHECK( [respect.world locationOf:respect.seal].place == respect.a);
   store = [respect.knowledge storeOf:respect.b];
   BG_CHECK( [store finding:"#Reserved" about:referent_of( store, respect.seal)] != NULL);
   /* a tag legible only from on it, a step away, says nothing */
   ignore = seal_scene( 61, 3, 50);
   BG_CHECK( logged_by( ignore.agency, ignore.b, @"take the seal +10 (+10, unreserved +0)"));
   store = [ignore.knowledge storeOf:ignore.b];
   BG_CHECK( [store finding:"#Reserved" about:referent_of( store, ignore.seal)] == NULL);
   /* B: B, who doesn't mind, races A for it, and wins the draw: the
    * reservation doesn't block the commit. A's take fails with the reason;
    * A, who knew the seal was reserved for it, sees it in B's hand */
   for( w = 61; w < 81; w++)
   {
      ignore = seal_scene( (uint64_t) w, YES, 0);
      if( [ignore.world locationOf:ignore.seal].place == ignore.b)
         break;
   }
   BG_CHECK( logged_by( ignore.agency, ignore.b, @"take the seal +10 (+10, reserved +0)"));
   BG_CHECK( logged_by( ignore.agency, ignore.b, @"take_up R"));
   BG_CHECK( [ignore.world locationOf:ignore.seal].form == BGLocationHeldBy &&
             [ignore.world locationOf:ignore.seal].place == ignore.b);
   trace = [[ignore.committer trace] componentsJoinedByString:@"\n"];
   BG_CHECK( [trace rangeOfString:@"rejected: 1 is no longer where it was taken from"].location != NSNotFound);
   store = [ignore.knowledge storeOf:ignore.a];
   seal  = [store referent:referent_of( store, ignore.seal)];
   BG_CHECK( seal && seal->form == BGLocationHeldBy && seal->container == referent_of( store, ignore.b));
}


/* --- the coat at dusk ------------------------------------------------------- */

typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGEntityID    porter;
   BGEntityID    visitor;
   BGEntityID    smith;
   NSString      *atDusk;        /* the visitor's referent, after the dusk sighting */
   NSUInteger    compactions;    /* of the porter's knowledge arena */
   int32_t       before;         /* the hypothesis' credence, made */
   NSString      *text;
} BGCoatRun;


/* CONTENT_LANGUAGE.md Scenario 3, "the coat at dusk": the porter (Ulla) sees
 * a visitor in a grey coat by day; at dusk, a figure three tiles off whose
 * coat looks only dark; next morning, a figure in a brown coat (B: a
 * stranger of the visitor's build; A: the visitor, in a brown coat now); a
 * week later, the brown-coated figure again. */
static BGCoatRun   coat_at_dusk( BOOL sameOne, BOOL compactAlways)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGProposalGroup    *g;
   BGEntityID         figure;
   BGCoatRun          run;
   int64_t            day;

   memset( &run, 0, sizeof( run));
   day        = 86400000LL;
   st.w       = BGTestWorld( 67);
   st.c       = BGTestCommitter( st.w);
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   [knowledge setCompactAlways:compactAlways];
   g           = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the yard"];
   run.porter  = [g create:"porter" key:"Ulla" at:BGOnTile( 10, 10, 0)];
   run.visitor = [g create:"agent_a" key:"the visitor" at:BGOnTile( 12, 10, 0)];
   run.smith   = [g create:"stranger" key:"the stranger" at:BGOnTile( 30, 30, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   run.porter  = [g idFor:run.porter];
   run.visitor = [g idFor:run.visitor];
   run.smith   = [g idFor:run.smith];
   stage_move( &st, run.visitor, 25, 25);

   /* dusk: a figure three tiles off, its coat only dark */
   [knowledge setDusk:YES];
   [st.s runUntil:BGTimeMake( 3600000)];
   stage_move( &st, run.visitor, 13, 10);
   run.atDusk = [[knowledge storeOf:run.porter] describeReferent:referent_of( [knowledge storeOf:run.porter], run.visitor)];
   stage_move( &st, run.visitor, 25, 25);
   [knowledge setDusk:NO];

   /* the morning: a figure in a brown coat at the pump */
   figure = sameOne ? run.visitor : run.smith;
   [st.s runUntil:BGTimeMake( 12 * 3600000LL)];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a figure in a brown coat"];
   if( sameOne)
      [g set:"Agent.coat" of:BGWhole( figure) to:tri_type_named( [st.w tri], "\"brown\"")];
   [g move:BGWhole( figure) to:BGOnTile( 13, 11, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 12 * 3600000LL + 1000)];
   run.before = [[knowledge storeOf:run.porter] identityCount] ? [[knowledge storeOf:run.porter] identityAt:0]->credence : 99;
   stage_move( &st, figure, 30, 30);

   /* a week passes; the brown-coated figure again */
   [st.s runUntil:BGTimeMake( 12 * 3600000LL + 7 * day)];
   stage_move( &st, figure, 13, 11);

   run.world     = st.w;
   run.knowledge = knowledge;
   run.text      = BGSave( st.w, st.c, [NSArray arrayWithObject:knowledge]);
   run.compactions = [[knowledge storeOf:run.porter] compactions];
   return( run);
}


static void   test_coat_at_dusk( void)
{
   BGCoatRun          b;
   BGCoatRun          a;
   BGCoatRun          again;
   BGCoatRun          compacted;
   BGKnowledgeStore   *store;
   const BGIdentity   *h;
   BGWorld            *w2;
   BGKnowledge        *restored;
   NSArray            *deferred;
   NSString           *error;
   uint64_t           position;

   b     = coat_at_dusk( NO, NO);
   store = [b.knowledge storeOf:b.porter];

   /* at dusk the coat looks only dark; it unifies with the visitor's grey,
    * and memory keeps the more specific */
   BG_CHECK( [b.atDusk rangeOfString:@"coat: \"grey\""].location != NSNotFound);

   /* 1, 2: the brown coat fails to unify at exactly one path, the coat; a
    * coat changes daily, so it is a new referent that may be the visitor,
    * not an error */
   BG_CHECK( [store identityCount] == 1);
   h = [store identityCount] ? [store identityAt:0] : NULL;
   BG_CHECK( h && ! strcmp( h->paths, "coat"));
   BG_CHECK( h && h->b == referent_of( store, b.visitor) && h->a == referent_of( store, b.smith));
   BG_CHECK( b.before == BG_PRIOR + 3 * 5 - 5);          /* five features agree, the coat doesn't */

   /* 3, 4: a week on, both coats have decayed past telling; the brown-coated
    * figure fits both, and that alone raises the credence that they are one */
   BG_CHECK( h && h->credence == b.before + 10);
   /* B: they are not: the inspector flags the false merge */
   BG_CHECK( [[b.knowledge dump:b.porter] rangeOfString:@"truly not: false merge"].location != NSNotFound);

   /* A: the visitor itself, in a brown coat: the decayed memory leads to the
    * right answer, for a weak reason */
   a     = coat_at_dusk( YES, NO);
   store = [a.knowledge storeOf:a.porter];

   BG_CHECK( [store identityCount] == 1 && [store identityAt:0]->credence == b.before + 10);
   BG_CHECK( [[a.knowledge dump:a.porter] rangeOfString:@"truly the same"].location != NSNotFound);

   /* the same on replay, and saved */
   again = coat_at_dusk( NO, NO);
   BG_CHECK( [again.text isEqualToString:b.text]);

   /* 6: compaction: the porter's knowledge arena compacted at every
    * boundary changes nothing observable; the save is the same to the byte */
   compacted = coat_at_dusk( NO, YES);
   BG_CHECK( compacted.compactions >= 5 && compacted.compactions > b.compactions);
   BG_CHECK( [compacted.text isEqualToString:b.text]);
   BG_CHECK( [[compacted.knowledge dump:compacted.porter] isEqualToString:[b.knowledge dump:b.porter]]);
   w2 = BGRestore( b.text, [b.world contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   restored = [[[BGKnowledge alloc] initWithWorld:w2] autorelease];
   [restored restoreSavedState:BGSavedDomainState( b.text, @"knowledge")];
   BG_CHECK( [[restored dump:b.porter] isEqualToString:[b.knowledge dump:b.porter]]);
}


/* --- the nut of unknown size ------------------------------------------------- */

typedef struct
{
   BGWorld       *world;
   BGKnowledge   *knowledge;
   BGAgency      *agency;
   BGEntityID    nut;
   NSString      *fromAfar;      /* the worker's referent of the nut, before it looks closer */
   NSString      *text;
} BGNutRun;


/* CONTENT_LANGUAGE.md Scenario 2, "the nut of unknown size": the worker,
 * holding a spanner, is to tighten the pump's gland nut, four tiles off,
 * whose size it sees only roughly from there. `spare`, if not NULL: another
 * spanner lying on the bench by the nut. */
static BGNutRun   nut_run( const char *nut, const char *spanner, BOOL omniscient, const char *spare)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGNutRun           run;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 71);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [knowledge setOmniscient:omniscient];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g       = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump"];
   worker  = [g create:"worker" key:"Oskar" at:BGOnTile( 2, 2, 0)];
   [g create:spanner key:"spanner" at:BGHeldBy( worker, 0)];
   run.nut = [g create:nut key:"gland nut" at:BGOnTile( 6, 2, 0)];
   if( spare)
      [g create:spare key:"spare spanner" at:BGOnTile( 5, 3, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker   = [g idFor:worker];
   run.nut  = [g idFor:run.nut];
   run.fromAfar = [[knowledge storeOf:worker] describeReferent:referent_of( [knowledge storeOf:worker], run.nut)];
   BG_CHECK( [agency commit:worker toGoal:"tighten_nut"]);
   [st.s runUntil:BGTimeMake( 30000)];
   run.world     = st.w;
   run.knowledge = knowledge;
   run.agency    = agency;
   run.text      = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


/* CONTENT_LANGUAGE.md Scenario 2's variant C: the worker has seen the nut
 * plainly (19 mm) from beside it, then stands four tiles off; it half
 * remembers the nut was replaced with a 22 mm one, at `doubt` in 1000. */
static BGNutRun   doubtful_nut_run( int32_t doubt, int32_t doubt24, int64_t *massSeen)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGKnowledgeStore   *store;
   BGEntityID         worker;
   BGNutRun           run;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 71);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g       = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump"];
   worker  = [g create:"worker" key:"Oskar" at:BGOnTile( 5, 2, 0)];
   [g create:"spanner_19" key:"spanner" at:BGHeldBy( worker, 0)];
   run.nut = [g create:"gland_nut" key:"gland nut" at:BGOnTile( 6, 2, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker  = [g idFor:worker];
   run.nut = [g idFor:run.nut];
   stage_move( &st, worker, 2, 2);
   store = [knowledge storeOf:worker];
   [store suppose:@"size: 22mm" about:referent_of( store, run.nut) mass:doubt];
   if( doubt24)
      [store suppose:@"size: 24mm" about:referent_of( store, run.nut) mass:doubt24];
   *massSeen    = [store supposedMassOf:referent_of( store, run.nut)];
   run.fromAfar = [knowledge dump:worker];
   {
      BGKnowledge   *restored;
      NSString      *text;

      /* the doubt is saved */
      text     = BGSave( st.w, st.c, [NSArray arrayWithObject:knowledge]);
      restored = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
      [restored restoreSavedState:BGSavedDomainState( text, @"knowledge")];
      BG_CHECK( [[restored dump:worker] isEqualToString:run.fromAfar]);
   }
   BG_CHECK( [agency commit:worker toGoal:"tighten_nut"]);
   [st.s runUntil:BGTimeMake( 30000)];
   run.world     = st.w;
   run.knowledge = knowledge;
   run.agency    = agency;
   run.text      = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


/* The menu, beside the nut, while it half remembers a 22 mm one at `doubt`
 * in 1000: the tighten entry, described. */
static NSString   *doubtful_menu( int32_t doubt)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGProposalGroup    *g;
   BGKnowledgeStore   *store;
   BGMenu             *menu;
   BGEntityID         worker;
   BGEntityID         nut;
   NSUInteger         i;

   st.w      = BGTestWorld( 71);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump"];
   worker = [g create:"worker" key:"Oskar" at:BGOnTile( 5, 2, 0)];
   [g create:"spanner_19" key:"spanner" at:BGHeldBy( worker, 0)];
   nut    = [g create:"gland_nut" key:"gland nut" at:BGOnTile( 6, 2, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   nut    = [g idFor:nut];
   store  = [knowledge storeOf:worker];
   if( doubt)
      [store suppose:@"size: 22mm" about:referent_of( store, nut) mass:doubt];
   menu = [BGMenu menuFor:store world:st.w believed:YES];
   for( i = 0; i < [menu count]; i++)
      if( ! strcmp( [menu actionAt:i]->operation, "tighten"))
         return( [menu describeAt:i]);
   return( @"");
}


/* AGENCY.md §7's urgency curve: the worker, beside the nut, is committed
 * to tightening it within [0, 100 s], and takes it up at 90 s: by the goal's
 * curve, barely urgent yet. */
static BGAgency   *urgent_nut( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGEntityID         worker;

   st.w       = BGTestWorld( 71);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump"];
   worker = [g create:"worker" key:"Oskar" at:BGOnTile( 5, 2, 0)];
   [g create:"spanner_19" key:"spanner" at:BGHeldBy( worker, 0)];
   [g create:"gland_nut" key:"gland nut" at:BGOnTile( 6, 2, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 90000)];
   worker = [g idFor:worker];
   BG_CHECK( [agency undertake:worker goal:"tighten_nut" from:0 until:100000 source:"employment"]);
   [agency control:worker];
   [st.s runUntil:BGTimeMake( 95000)];
   return( agency);
}


/* AGENCY.md §14, autopilot "carry out this recipe": at the mill, the
 * worker, holding the wrench, reads the diagram; the player hands it to
 * agency to follow the recipe. It shuts the line the diagram says, opens
 * the pump, and control returns. Saved midway, the recipe is kept. A
 * method that isn't a recipe can't be handed over so. */
static void   test_recipe_autopilot( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         pump;
   BGEntityID         trough;
   BGEntityID         diagram;
   NSArray            *notices;
   NSString           *text;
   NSString           *error;
   int64_t            v;

   st.w       = BGTestWorld( 83);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g       = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the mill"];
   pump    = [g create:"pump" key:"pump" at:BGOnTile( 10, 10, 0)];
   trough  = [g create:"cock_trough" key:"the trough line's cock" at:BGOnTile( 9, 9, 0)];
   [g create:"cock_pump" key:"the riser's cock" at:BGOnTile( 11, 9, 0)];
   worker  = [g create:"worker" key:"worker" at:BGOnTile( 10, 9, 0)];
   [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   diagram = [g create:"diagram" key:"diagram" at:BGHeldBy( worker, 1)];
   [g set:"Record.writing" of:BGWhole( diagram)
   toText:[st.w intern:"#Writing & { author: #Agent & { coat: \"white\" }, entries: [#Serves & { what: #Cock & "
                       "{ place: #OnTile & { x: 9, y: 9, level: 0 } }, line: \"pump\", attribution: #Saw & { sure: 30 } }] }"]];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   pump    = [g idFor:pump];
   trough  = [g idFor:trough];
   worker  = [g idFor:worker];
   diagram = [g idFor:diagram];
   error   = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "read", worker, diagram, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 1000)];

   BG_CHECK( ! [agency autopilot:worker recipe:"borrow_money" threshold:50]);
   BG_CHECK( [agency autopilot:worker recipe:"the_recipe" threshold:50]);
   [st.s runUntil:BGTimeMake( 3000)];
   text = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   BG_CHECK( [text rangeOfString:@" the_recipe"].location != NSNotFound);
   [st.s runUntil:BGTimeMake( 60000)];
   BG_CHECK( logged_by( agency, worker, @"[repair the pump] follow the recipe: shut_off R"));
   BG_CHECK( [st.w getField:"Cock.shut" of:trough value:&v] && v);
   BG_CHECK( [st.w getField:"Pump.opened" of:pump value:&v] && v);
   notices = [agency takeNotices];
   BG_CHECK( [notices count] == 1 &&
             [[notices objectAtIndex:0] isEqualToString:@"Control returns to you: there is nothing left to do."]);
}


/* AGENCY.md §14, autopilot "auto-explore": the player hands a worker,
 * alone in the middle of the map, to agency to explore. It walks toward the
 * nearest tile it has never seen, a step at a time, until it has seen every
 * one; then control returns. Saved midway, the mode is kept. */
static void   test_explore_autopilot( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGAgency           *restored;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   BGEntityID         worker;
   NSArray            *notices;
   NSString           *text;
   NSString           *mode;
   int32_t            x;
   int32_t            y;
   int                unseen;

   st.w       = BGTestWorld( 179);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: an empty map"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 16, 16, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   BG_CHECK( [agency autopilotExplore:worker threshold:50]);

   /* midway: under way, and the mode saved */
   [st.s runUntil:BGTimeMake( 10000)];
   BG_CHECK( [[agency takeNotices] count] == 0 && logged_by( agency, worker, @"exploring: walk_"));
   text     = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   mode     = [NSString stringWithFormat:@"explore %llu", (unsigned long long) worker];
   BG_CHECK( [text rangeOfString:mode].location != NSNotFound);
   restored = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   [restored restoreSavedState:BGSavedDomainState( text, @"agency")];
   BG_CHECK( [restored mindOf:worker]->explore && [restored mindOf:worker]->autopilot);

   /* on until it has seen it all */
   [st.s runUntil:BGTimeMake( 600000)];
   store  = [knowledge storeOf:worker];
   unseen = 0;
   for( y = 0; y < 32; y++)
      for( x = 0; x < 32; x++)
         if( [store tileSeenAtX:x y:y] < 0)
            unseen++;
   BG_CHECK( unseen == 0);
   notices = [agency takeNotices];
   BG_CHECK( [notices count] == 1 &&
             [[notices objectAtIndex:0] isEqualToString:@"Control returns to you: there is nothing left to explore."]);
   BG_CHECK( ! [agency controls:worker]);
}


/* Talking takes time (ACTIONS.md §5, AGENCY.md §11: conversations are
 * communicate activities): a remark is a second on the voice, the words
 * said when it ends. Walking while talking works; a second remark at once
 * doesn't, its voice taken; once said, it can speak again. */
static void   test_talking_takes_time( void)
{
   BGStage            st;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         smith;
   BGAction           say;
   NSString           *error;
   NSUInteger         i;
   NSUInteger         said;
   int64_t            when;

   st.w   = BGTestWorld( 173);
   st.c   = BGTestCommitter( st.w);
   st.s   = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:[BGActivities activitiesWithWorld:st.w committer:st.c]];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: two in the yard"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   smith  = [g create:"smith" key:"smith" at:BGOnTile( 6, 5, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   smith  = [g idFor:smith];

   error       = nil;
   say         = BGActionMake( "say", worker, smith, BGNoEntity);
   say.content = [st.w intern:"#Here & {}"];
   BG_CHECK( BGPerform( st.w, st.c, say, 0, &error) != nil);
   when = [st.w time].ms;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "walk_south", worker, BGNoEntity, BGNoEntity), 0, &error) != nil);
   BG_CHECK( BGPerform( st.w, st.c, say, 0, &error) == nil);
   BG_CHECK( [error isEqualToString:@"its voice is taken by say, starting"]);

   /* not said yet half a second in; said, with its words, at the second */
   [st.s runUntil:BGTimeMake( when + 500)];
   said = 0;
   for( i = 0; i < [st.w eventCount]; i++)
      if( ! strcmp( [st.w eventAt:i]->kind, "said"))
         said++;
   BG_CHECK( said == 0);
   [st.s runUntil:BGTimeMake( when + 1001)];
   for( i = 0; i < [st.w eventCount]; i++)
      if( ! strcmp( [st.w eventAt:i]->kind, "said"))
      {
         said++;
         BG_CHECK( ! strcmp( [st.w eventAt:i]->detail, "#Here & {}") && [st.w eventAt:i]->actor == worker &&
                   [st.w eventAt:i]->other == smith);
      }
   BG_CHECK( said == 1);
   /* and it walked meanwhile */
   BG_CHECK( [st.w locationOf:worker].y == 6);
   error = nil;
   BG_CHECK( BGPerform( st.w, st.c, say, 0, &error) != nil);
}


/* AGENCY.md §14, autopilot "continue my routine": the player hands Oskar,
 * beside the nut with a spanner, to agency from the start, past a
 * threshold of 10; his shift has him tighten the nut between 60 s and
 * 120 s. He waits for it, control not returning; at 60 s he takes it up,
 * worth more than the threshold (it is his routine); done, his routine is
 * done, and control returns. */
static void   test_routine_autopilot( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         nut;
   NSArray            *notices;
   int64_t            v;

   st.w       = BGTestWorld( 71);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump"];
   worker = [g create:"worker" key:"Oskar" at:BGOnTile( 5, 2, 0)];
   [g create:"spanner_19" key:"spanner" at:BGHeldBy( worker, 0)];
   nut    = [g create:"gland_nut" key:"gland nut" at:BGOnTile( 6, 2, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   nut    = [g idFor:nut];
   BG_CHECK( [agency undertake:worker goal:"tighten_nut" from:60000 until:120000 source:"employment"]);
   BG_CHECK( [agency autopilotRoutine:worker threshold:10]);

   /* waiting for its routine: control stays with agency */
   [st.s runUntil:BGTimeMake( 30000)];
   BG_CHECK( [[agency takeNotices] count] == 0 && [agency controls:worker]);
   BG_CHECK( ! ([st.w getField:"Fastener.tight" of:nut value:&v] && v));

   /* its shift: taken up, though worth more than the threshold */
   [st.s runUntil:BGTimeMake( 90000)];
   BG_CHECK( logged_by( agency, worker, @"t=60000ms [-] weighing tighten the nut"));
   BG_CHECK( [st.w getField:"Fastener.tight" of:nut value:&v] && v);
   notices = [agency takeNotices];
   BG_CHECK( [notices count] == 1 && [[notices objectAtIndex:0] isEqualToString:@"Control returns to you: its routine is done."]);
}


/* KNOWLEDGE.md §11: conflicting beliefs coexist as competing hypotheses.
 * The worker has seen the nut plainly (19 mm) and stands four tiles off;
 * the smith, beside it, says the nut is 22 mm. Its belief and the smith's
 * claim coexist, the claim as credible as it finds the smith; less than
 * sure, it looks closer before it tightens. */
static BGNutRun   told_nut_run( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         smith;
   BGNutRun           run;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 71);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g       = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pump"];
   worker  = [g create:"worker" key:"Oskar" at:BGOnTile( 5, 2, 0)];
   smith   = [g create:"smith" key:"a fitter" at:BGOnTile( 3, 3, 0)];
   [g create:"spanner_19" key:"spanner" at:BGHeldBy( worker, 0)];
   run.nut = [g create:"gland_nut" key:"gland nut" at:BGOnTile( 6, 2, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker  = [g idFor:worker];
   smith   = [g idFor:smith];
   run.nut = [g idFor:run.nut];
   stage_move( &st, worker, 2, 2);
   stage_say( &st, smith, worker, @"#IsLike & { what: #Fastener & { place: #OnTile & { x: 6, y: 2, level: 0 } }, "
                                  @"as: #Fastener & { size: 22mm }, attribution: #Saw & { sure: 30 } }");
   run.fromAfar = [knowledge dump:worker];
   BG_CHECK( [agency commit:worker toGoal:"tighten_nut"]);
   [st.s runUntil:BGTimeMake( 30000)];
   run.world     = st.w;
   run.knowledge = knowledge;
   run.agency    = agency;
   return( run);
}


static BOOL   tightened( BGNutRun run)
{
   int64_t   v;

   return( [run.world getField:"Fastener.tight" of:run.nut value:&v] && v);
}


static void   test_unknown_nut( void)
{
   BGNutRun   base;
   BGNutRun   wrong;
   BGNutRun   seer;
   BGNutRun   tag;
   BGNutRun   again;
   BGNutRun   spare;
   BGNutRun   misfit;
   BGNutRun   doubtful;
   BGNutRun   sure;
   BGNutRun   told;
   BGAgency   *urgent;
   int64_t    mass;

   /* 1: four tiles off, the nut's size is only 16 to 22 mm: whether the 19
    * mm spanner fits is unknown, with the residual nut.size and nothing else */
   base = nut_run( "gland_nut", "spanner_19", NO, NULL);
   BG_CHECK( [base.fromAfar rangeOfString:@"size: >=16mm & <=22mm"].location != NSNotFound);
   /* 2: the residual becomes a goal: it looks closer, and then tightens it */
   BG_CHECK( logged_by( base.agency, 1, @"[tighten the nut] tighten it: unknown at nut.size: look closer first"));
   BG_CHECK( logged_by( base.agency, 1, @"[look closer] go and peer at it: walk_east"));
   BG_CHECK( [[[base.knowledge storeOf:1] describeReferent:referent_of( [base.knowledge storeOf:1], base.nut)]
              rangeOfString:@"size: 19mm"].location != NSNotFound);     /* within reach, it sees it plainly */
   BG_CHECK( logged_by( base.agency, 1, @"[tighten the nut] back to it: look closer is done"));
   BG_CHECK( logged_by( base.agency, 1, @"[tighten the nut] tighten it: tighten R"));
   BG_CHECK( tightened( base));

   /* A: the nut is truly 22 mm: up close it is incompatible, and the method
    * fails; finding a spanner that fits (22 mm, the size it now believes) is
    * impossible too, for it knows of none */
   wrong = nut_run( "gland_nut_22", "spanner_19", NO, NULL);
   BG_CHECK( logged_by( wrong.agency, 1, @"look closer first"));
   BG_CHECK( logged_by( wrong.agency, 1, @"[tighten the nut] get one that fits: find a spanner that fits first"));
   BG_CHECK( logged_by( wrong.agency, 1, @"[find a spanner that fits] nothing I know of will do: impossible for now"));
   BG_CHECK( logged_by( wrong.agency, 1, @"[tighten the nut] nothing I know of will do: impossible for now"));
   BG_CHECK( ! tightened( wrong));

   /* A, with a 22 mm spanner on the bench by the nut: up close, it picks that
    * one up, and tightens the nut with it */
   spare = nut_run( "gland_nut_22", "spanner_19", NO, "spanner_22");
   BG_CHECK( logged_by( spare.agency, 1, @"look closer first"));
   BG_CHECK( logged_by( spare.agency, 1, @"[find a spanner that fits] pick up one that fits: take_up"));
   BG_CHECK( logged_by( spare.agency, 1, @"[tighten the nut] back to it: find a spanner that fits is done"));
   BG_CHECK( tightened( spare));
   /* with a 19 mm one there instead, nothing fits: it leaves it lying */
   misfit = nut_run( "gland_nut_22", "spanner_19", NO, "spanner_19");
   BG_CHECK( ! logged_by( misfit.agency, 1, @"take_up") && ! tightened( misfit));

   /* 3, B: the omniscient stub knows the size from afar: it never looks closer */
   seer = nut_run( "gland_nut", "spanner_19", YES, NULL);
   BG_CHECK( ! logged_by( seer.agency, 1, @"look closer") && ! logged_by( seer.agency, 1, @"peer_at"));
   BG_CHECK( tightened( seer));

   /* 4: tags: with a 22 mm spanner instead, the same closer look finds it incompatible */
   tag = nut_run( "gland_nut", "spanner_22", NO, NULL);
   BG_CHECK( logged_by( tag.agency, 1, @"look closer first"));
   BG_CHECK( logged_by( tag.agency, 1, @"impossible for now") && ! tightened( tag));

   /* the urgency curve: at 90% of its window, +2, where a straight line
    * would give +18 */
   urgent = urgent_nut();
   BG_CHECK( logged_by( urgent, 1, @"urgency +2"));

   /* 5: determinism */
   again = nut_run( "gland_nut", "spanner_19", NO, NULL);
   BG_CHECK( [again.text isEqualToString:base.text]);

   /* C: two hypotheses, 19 mm as it saw it, or 22 mm as it half remembers.
    * At 300 in 1000 for 22, only 700 entails: under tightening's 900, so it
    * looks closer first, and seen plainly the doubt is gone */
   doubtful = doubtful_nut_run( 300, 0, &mass);
   BG_CHECK( mass == 300 && [doubtful.fromAfar rangeOfString:@"or, 300 in 1000: size: 22mm"].location != NSNotFound);
   BG_CHECK( [doubtful.fromAfar rangeOfString:@"size: 19mm"].location != NSNotFound);
   BG_CHECK( logged_by( doubtful.agency, 1, @"tighten it: unknown at nut.size (700 in 1000 entails, under 900): look closer first"));
   BG_CHECK( tightened( doubtful));
   BG_CHECK( [[doubtful.knowledge dump:1] rangeOfString:@"or, 300 in 1000"].location == NSNotFound);
   /* told otherwise: its belief and the claim coexist */
   told = told_nut_run();
   BG_CHECK( [told.fromAfar rangeOfString:@"size: 19mm"].location != NSNotFound);
   BG_CHECK( [told.fromAfar rangeOfString:@"or, 990 in 1000: size: 22mm\n"].location != NSNotFound);
   BG_CHECK( logged_by( told.agency, 1, @"tighten it: unknown at nut.size (10 in 1000 entails, under 900): look closer first"));
   BG_CHECK( tightened( told));

   /* the menu shows how sure: doubted, it is unknown, with the mass that
    * entails and what to find out; undoubted, entailed */
   BG_CHECK( [doubtful_menu( 300) rangeOfString:@": unknown (700 in 1000 entails) (find out destination.size)"].location
             != NSNotFound);
   BG_CHECK( [doubtful_menu( 0) rangeOfString:@": entailed"].location != NSNotFound);
   /* at 50 in 1000, 950 entails: sure enough, it tightens it without looking */
   sure = doubtful_nut_run( 50, 0, &mass);
   BG_CHECK( ! logged_by( sure.agency, 1, @"look closer") && tightened( sure));

   /* more than one: 22 mm at 60, 24 mm at 50, so 890 entails, under 900,
    * and it looks closer; both are kept, and saved, until it does */
   doubtful = doubtful_nut_run( 60, 50, &mass);
   BG_CHECK( mass == 110);
   BG_CHECK( [doubtful.fromAfar rangeOfString:@"or, 60 in 1000: size: 22mm\n    or, 50 in 1000: size: 24mm"].location
             != NSNotFound);
   BG_CHECK( logged_by( doubtful.agency, 1, @"tighten it: unknown at nut.size (890 in 1000 entails, under 900)"));
   BG_CHECK( tightened( doubtful));
   /* 22 mm at 60, 24 mm at 30: 910 entails, sure enough */
   sure = doubtful_nut_run( 60, 30, &mass);
   BG_CHECK( mass == 90 && ! logged_by( sure.agency, 1, @"look closer") && tightened( sure));
}


/* --- the seized valve ------------------------------------------------------- */

typedef struct
{
   BGWorld       *world;
   BGCommitter   *committer;
   BGKnowledge   *knowledge;
   BGEntityID    valve;
   BGEntityID    worker;
   BGEntityID    wrench;
   BGEntityID    pipe;
   int64_t       delay;         /* bringing them to bear, ms */
   BOOL          early;         /* turned before the stage and the delay were done */
   NSString      *menu;          /* the worker's, before it acts */
   NSString      *trace;
   BOOL          turned;
   BOOL          bent;
} BGValveRun;


/* ACTIONS.md Scenario 1: the worker beside a valve (`valve`, seized or
 * not), holding what `tools` names ("", "wrench", "wrench pipe", "stone
 * wrench"), turns it; `steady`, if not 0, holds the torque there (Nm). With
 * a stone, it strikes the valve first and then holds the wrench alone.
 * "wrench near" and "pipe near" lie on tiles beside it, "pipe sacked" in a
 * sack on its tile, "pipe theirs" in a bystander's hand, "pipe far" out of
 * reach; "spare" lays a second wrench beside it. */
static BGValveRun   valve_run( const char *valve, const char *tools, int64_t steady, uint64_t seed)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         pipe;
   BGEntityID         stone;
   BGEntityID         sack;
   BGEntityID         other;
   BGKnowledgeStore   *store;
   BGMenu             *menu;
   NSMutableArray     *entries;
   NSString           *error;
   NSUInteger         i;
   BGValveRun         run;
   int64_t            v;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( seed);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s addDomain:[[[BGTraces alloc] initWithWorld:st.w] autorelease]];
   g          = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the water line"];
   worker     = [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   run.valve  = [g create:valve key:"valve" at:BGOnTile( 6, 5, 0)];
   run.wrench = BGNoEntity;
   pipe       = BGNoEntity;
   stone      = BGNoEntity;
   if( strstr( tools, "stone"))
      stone = [g create:"stone" key:"stone" at:BGHeldBy( worker, 0)];
   else if( strstr( tools, "wrench near"))
      run.wrench = [g create:"wrench_250" key:"wrench" at:BGOnTile( 4, 5, 0)];
   else if( strstr( tools, "wrench"))
      run.wrench = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   if( strstr( tools, "pipe near"))
      pipe = [g create:"pipe_600" key:"pipe" at:BGOnTile( 4, 6, 0)];
   else if( strstr( tools, "pipe sacked"))
   {
      sack = [g create:"sack" key:"sack" at:BGOnTile( 5, 5, 0)];
      pipe = [g create:"pipe_600" key:"pipe" at:BGIn( sack)];
   }
   else if( strstr( tools, "pipe theirs"))
   {
      other = [g create:"worker" key:"bystander" at:BGOnTile( 5, 6, 0)];
      pipe  = [g create:"pipe_600" key:"pipe" at:BGHeldBy( other, 0)];
   }
   else if( strstr( tools, "pipe far"))
      pipe = [g create:"pipe_600" key:"pipe" at:BGOnTile( 8, 5, 0)];
   else if( strstr( tools, "pipe"))
      pipe = [g create:"pipe_600" key:"pipe" at:BGHeldBy( worker, 1)];
   if( strstr( tools, "spare"))
      [g create:"wrench_250" key:"a spare wrench" at:BGOnTile( 5, 4, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker     = [g idFor:worker];
   run.valve  = [g idFor:run.valve];
   run.wrench = run.wrench ? [g idFor:run.wrench] : BGNoEntity;
   run.pipe   = pipe ? [g idFor:pipe] : BGNoEntity;
   run.worker = worker;
   stone      = stone ? [g idFor:stone] : BGNoEntity;

   /* the menu, as the worker knows it */
   store   = [knowledge storeOf:worker];
   menu    = [BGMenu menuFor:store world:st.w believed:YES];
   entries = [NSMutableArray array];
   for( i = 0; i < [menu count]; i++)
      [entries addObject:[menu describeAt:i]];
   run.menu = [entries componentsJoinedByString:@"; "];

   error = nil;
   if( stone)
   {
      /* a blow first, then the wrench in that hand */
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "strike", worker, stone, run.valve), 0, &error) != nil);
      [st.s runUntil:BGTimeMake( 1000)];
      g          = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the stone down, the wrench up"];
      [g move:BGWhole( stone) to:BGOnTile( 4, 5, 0)];
      run.wrench = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
      [st.c submit:g];
      [st.s runUntil:BGTimeMake( 2000)];
      run.wrench = [g idFor:run.wrench];
   }
   run.delay = BGAccessDelay( st.w, BGActionMake( "rotate_valve", worker, run.valve, BGNoEntity));
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "rotate_valve", worker, run.valve, BGNoEntity), steady, &error) != nil);
   [st.s runUntil:BGTimeMake( [st.w time].ms + 2000 + run.delay - 1)];
   run.early = [st.w getField:"Valve.turned" of:run.valve value:&v] && v;
   [st.s runUntil:BGTimeMake( [st.w time].ms + 3000)];
   run.world     = st.w;
   run.committer = st.c;
   run.knowledge = knowledge;
   run.trace     = [[st.c trace] componentsJoinedByString:@"\n"];
   run.turned    = [st.w getField:"Valve.turned" of:run.valve value:&v] && v;
   run.bent      = run.wrench && [st.w getField:"Body.bent" of:run.wrench value:&v] && v;
   return( run);
}


/* ACTIONS.md §5: each provider belongs to at most one activity at a time,
 * counting those started for the same boundary and not yet committed:
 * taking up two things at once, the second is refused; walking while
 * taking one up is not; and once the first is done, the second can begin. */
static void   test_providers_pending( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         seal;
   BGEntityID         stone;
   NSString           *error;

   st.w       = BGTestWorld( 7);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:activities];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the bench"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   seal   = [g create:"seal" key:"seal" at:BGOnTile( 6, 5, 0)];
   stone  = [g create:"stone" key:"stone" at:BGOnTile( 5, 6, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   seal   = [g idFor:seal];
   stone  = [g idFor:stone];

   error = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take_up", worker, seal, BGNoEntity), 0, &error) != nil);
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take_up", worker, stone, BGNoEntity), 0, &error) == nil);
   BG_CHECK( [error rangeOfString:@"its hands are taken by take_up"].location != NSNotFound);
   error = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "walk_east", worker, BGNoEntity, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 2)];
   /* committed now, it is busy as before */
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take_up", worker, stone, BGNoEntity), 0, &error) == nil);
   BG_CHECK( [error rangeOfString:@"its hands are busy"].location != NSNotFound);
   [st.s runUntil:BGTimeMake( 1500)];
   BG_CHECK( [st.w locationOf:seal].place == worker);
   error = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take_up", worker, stone, BGNoEntity), 0, &error) != nil);
}


/* Suspended while bringing wrench and pipe to bear, the stage owes, on
 * resuming, the rest of the stage and bringing them to bear as they lie
 * then: the pipe, put into a sack meanwhile, takes twice as long. */
static void   test_access_resume( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         valve;
   BGEntityID         wrench;
   BGEntityID         pipe;
   BGEntityID         sack;
   BGEntityID         a;
   const BGActivity   *record;
   NSString           *error;
   int64_t            v;

   st.w       = BGTestWorld( 5);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:activities];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the water line"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   valve  = [g create:"seized_valve" key:"valve" at:BGOnTile( 6, 5, 0)];
   wrench = [g create:"wrench_250" key:"wrench" at:BGOnTile( 4, 5, 0)];
   pipe   = [g create:"pipe_600" key:"pipe" at:BGOnTile( 4, 6, 0)];
   sack   = [g create:"sack" key:"sack" at:BGOnTile( 5, 5, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   valve  = [g idFor:valve];
   wrench = [g idFor:wrench];
   pipe   = [g idFor:pipe];
   sack   = [g idFor:sack];

   /* 2 s of turning, 2 s of taking them up */
   error = nil;
   g     = BGPerform( st.w, st.c, BGActionMake( "rotate_valve", worker, valve, BGNoEntity), 75, &error);
   BG_CHECK( g != nil);
   [st.s runUntil:BGTimeMake( 2)];
   a      = [g idFor:[g proposals][ 0].handle];
   record = [st.w record:[st.w kindNamed:"Activity"] for:a];
   BG_CHECK( record && record->due == 1 + 2000 + 2000);
   [st.s runUntil:BGTimeMake( 1501)];
   BG_CHECK( [activities suspend:a because:@"a shout" error:&error] != nil);
   [st.s runUntil:BGTimeMake( 1502)];

   /* meanwhile the pipe goes into the sack */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the pipe sacked"];
   [g move:BGWhole( pipe) to:BGIn( sack)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 5000)];

   /* resumed: 2 s of the stage and 3 s of bringing them to bear, less 1.5 s done */
   BG_CHECK( [activities resume:a error:&error] != nil);
   [st.s runUntil:BGTimeMake( 5001)];
   record = [st.w record:[st.w kindNamed:"Activity"] for:a];
   BG_CHECK( record->progress == 1500 && record->due == 5000 + 2000 + 3000 - 1500);
   [st.s runUntil:BGTimeMake( 8499)];
   BG_CHECK( ! ([st.w getField:"Valve.turned" of:valve value:&v] && v));
   [st.s runUntil:BGTimeMake( 8600)];
   BG_CHECK( [st.w getField:"Valve.turned" of:valve value:&v] && v);
   BG_CHECK( [st.w locationOf:pipe].place == worker && [st.w locationOf:wrench].place == worker);
}


static void   test_seized_valve( void)
{
   BGValveRun   free_;
   BGValveRun   bare;
   BGValveRun   wrench;
   BGValveRun   full;
   BGValveRun   steady;
   BGValveRun   struck;
   BGValveRun   again;
   NSString     *seen;
   uint64_t     seed;
   int          bends;
   int          frees;

   /* 1: no leak: the menu for a seized valve is the menu for a free one */
   free_ = valve_run( "water_valve", "", 0, 73);
   bare  = valve_run( "seized_valve", "", 0, 73);
   BG_CHECK( [free_.menu isEqualToString:bare.menu]);
   BG_CHECK( [bare.menu rangeOfString:@"rotate_valve item"].location != NSNotFound);
   BG_CHECK( free_.turned);

   /* bare hands: 15 Nm, which the valve answers with nothing */
   BG_CHECK( ! bare.turned);
   BG_CHECK( [bare.trace rangeOfString:@": 15 Nm against 70 Nm: holds (expected to turn: rated 12 Nm)"].location != NSNotFound);

   /* the wrench: 50 Nm, still nothing; the wrench is worn, in the stage's group */
   wrench = valve_run( "seized_valve", "wrench", 0, 73);
   BG_CHECK( ! wrench.turned && ! wrench.bent);
   BG_CHECK( [wrench.trace rangeOfString:@": 50 Nm against 70 Nm: holds"].location != NSNotFound);
   BG_CHECK( any_trace( wrench.world, "tool_marks"));

   /* 2, 3: wrench and pipe: the chain found reaches 0.6 m, 120 Nm, past the
    * wrench's 80: risk, not refusal. Over seeds, sometimes the wrench bends
    * first, sometimes the valve frees; the same seed, the same */
   bends = 0;
   frees = 0;
   for( seed = 1; seed <= 20; seed++)
   {
      full = valve_run( "seized_valve", "wrench pipe", 0, seed);
      BG_CHECK( full.turned != full.bent);
      if( full.bent)
         bends++;
      if( full.turned)
         frees++;
   }
   BG_CHECK( bends > 0 && frees > 0);
   full  = valve_run( "seized_valve", "wrench pipe", 0, 5);
   again = valve_run( "seized_valve", "wrench pipe", 0, 5);
   BG_CHECK( full.turned == again.turned && [full.trace isEqualToString:again.trace]);

   /* a steady 75 Nm frees it, no risk */
   steady = valve_run( "seized_valve", "wrench pipe", 75, 5);
   BG_CHECK( steady.turned && ! steady.bent);
   BG_CHECK( [steady.trace rangeOfString:@": 75 Nm against 70 Nm: turns"].location != NSNotFound);

   /* the chain is searched in reach (ACTIONS.md §2), not only in hand:
    * wrench and pipe lying beside it are taken up, into both hands */
   steady = valve_run( "seized_valve", "wrench near pipe near", 75, 5);
   BG_CHECK( steady.turned && ! steady.bent);
   BG_CHECK( [steady.trace rangeOfString:@"takes up one in reach; takes up one in reach"].location != NSNotFound);
   BG_CHECK( [steady.world locationOf:steady.wrench].form == BGLocationHeldBy &&
             [steady.world locationOf:steady.wrench].place == steady.worker);
   BG_CHECK( [steady.world locationOf:steady.pipe].place == steady.worker);
   /* which takes time: a take_up's second for each, added to the stage */
   BG_CHECK( steady.delay == 2000 && ! steady.early);
   /* a pipe in a sack standing on its tile: further to reach, still in
    * reach, and twice as long to bring out */
   steady = valve_run( "seized_valve", "wrench pipe sacked", 75, 5);
   BG_CHECK( steady.turned && steady.delay == 2000 && ! steady.early);
   BG_CHECK( [steady.world locationOf:steady.pipe].place == steady.worker);
   /* in hand already, none */
   steady = valve_run( "seized_valve", "wrench pipe", 75, 5);
   BG_CHECK( steady.turned && steady.delay == 0);
   /* not a pipe in another's hand, nor one out of reach: the wrench alone */
   wrench = valve_run( "seized_valve", "wrench pipe theirs", 0, 73);
   BG_CHECK( ! wrench.turned && [wrench.trace rangeOfString:@": 50 Nm against 70 Nm: holds"].location != NSNotFound);
   BG_CHECK( [wrench.world locationOf:wrench.pipe].place != wrench.worker);
   wrench = valve_run( "seized_valve", "wrench pipe far", 0, 73);
   BG_CHECK( [wrench.trace rangeOfString:@": 50 Nm against 70 Nm: holds"].location != NSNotFound);
   /* the same reach: the one held, not a spare beside it */
   wrench = valve_run( "seized_valve", "wrench spare", 0, 73);
   BG_CHECK( [wrench.trace rangeOfString:@"takes up"].location == NSNotFound);
   /* the search is the same on every replay */
   full  = valve_run( "seized_valve", "wrench near pipe near", 0, 5);
   again = valve_run( "seized_valve", "wrench near pipe near", 0, 5);
   BG_CHECK( [full.trace isEqualToString:again.trace]);

   /* 5: a blow with the stone loosens the bond, and the wrench alone turns it */
   struck = valve_run( "seized_valve", "stone", 0, 73);
   BG_CHECK( [struck.trace rangeOfString:@"struck, breaks free at 40 Nm now"].location != NSNotFound);
   BG_CHECK( struck.turned);

   /* 4: outcomes in the player's text are what can be perceived: the
    * breakaway never appears */
   seen = [bare.knowledge dump:1];
   BG_CHECK( [seen rangeOfString:@"breakaway"].location == NSNotFound && [seen rangeOfString:@"70Nm"].location == NSNotFound);
   BG_CHECK( [seen rangeOfString:@"rating: 12Nm, turned: false"].location != NSNotFound);
   /* and what it perceives of the outcome: freed, it hears the valve creak
    * and sees it turned; bent, it hears the clang and sees the wrench bent;
    * held, it hears nothing */
   seen = [steady.knowledge dump:1];
   BG_CHECK( [seen rangeOfString:@"trace creak on"].location != NSNotFound);
   BG_CHECK( [seen rangeOfString:@"turned: true"].location != NSNotFound);
   for( seed = 1; seed <= 20; seed++)
   {
      full = valve_run( "seized_valve", "wrench pipe", 0, seed);
      if( full.bent)
         break;
   }
   seen = [full.knowledge dump:1];
   BG_CHECK( full.bent && [seen rangeOfString:@"trace clang on"].location != NSNotFound);
   BG_CHECK( [seen rangeOfString:@"bent: true"].location != NSNotFound);
   seen = [bare.knowledge dump:1];
   BG_CHECK( [seen rangeOfString:@"trace creak"].location == NSNotFound && [seen rangeOfString:@"trace clang"].location == NSNotFound);
}


/* ACTIONS.md Scenario 3's recheck on resume: the worker, driving a nail of
 * its own into the lock, puts the drive down at 2 s; the smith takes its
 * nails; resuming is refused, with the reason, until they are back in its
 * hand. */
static void   test_resume_recheck( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGActivities      *activities;
   BGProposalGroup   *g;
   BGEntityID        h[ 8];
   BGEntityID        a;
   NSString          *error;

   w          = BGTestWorld( 79);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   [c submit:BGWorkshopSetup( YES, h)];
   [s runUntil:BGTimeMake( 1)];

   g = BGPerform( w, c, BGActionMake( "drive", 4, 7, 3), 0, &error);
   BG_CHECK( g != nil);
   [s runUntil:BGTimeMake( 2001)];
   a = [g idFor:[g proposals][ 0].handle];
   BG_CHECK( [activities suspend:a because:@"a shout" error:&error] != nil);
   [s runUntil:BGTimeMake( 2002)];
   BG_CHECK( ! strcmp( status_of( w, a), "\"suspended\""));

   /* the smith, beside the worker, takes the nails: still within reach, no
    * longer in its hand */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the smith takes the nails"];
   [g move:BGWhole( 5) to:BGOnTile( 4, 5, 0)];
   [g move:BGWhole( 7) to:BGHeldBy( 5, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 3000)];
   error = nil;
   BG_CHECK( ! [activities resume:a error:&error]);
   BG_CHECK( error && [error rangeOfString:@"what it needs no longer holds, at "].location != NSNotFound);
   BG_CHECK( ! strcmp( status_of( w, a), "\"suspended\""));

   /* back in its hand: it resumes */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the nails back"];
   [g move:BGWhole( 7) to:BGHeldBy( 4, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 4000)];
   BG_CHECK( [activities resume:a error:&error] != nil);
}


/* --- the interrupted repair --------------------------------------------------- */

/* the agent's activity of the operation, in that status ("running"), or 0 */
static BGEntityID   activity_of( BGWorld *w, BGEntityID actor, const char *operation, const char *status)
{
   const BGActivity   *record;
   BGStore            *store;
   NSUInteger         i;
   char               quoted[ 32];

   snprintf( quoted, sizeof( quoted), "\"%s\"", status);
   store = [w storeForKind:[w kindNamed:"Activity"]];
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      if( (BGEntityID) record->actorRef == actor && record->status == (uint32_t) tri_type_named( [w tri], quoted) &&
          ! strcmp( [w textField:"Activity.operation" of:[store entityAtIndex:i]], operation))
         return( [store entityAtIndex:i]);
   }
   return( BGNoEntity);
}


typedef struct
{
   BGWorld       *world;
   BGAgency      *agency;
   BGEntityID    worker;
   BGEntityID    trough;
   BGEntityID    riser;
   BGEntityID    pump;
   int64_t       stage;          /* the dismantling, when suspended */
   int64_t       progress;
   BOOL          openWhileSuspended;
   BOOL          saved;          /* a save while suspended restores the same */
   BOOL          nextSame;       /* and, restored, takes the same next boundary */
   BOOL          talked;         /* saying something while dismantling */
   NSString      *refused;       /* why a second activity for the hands was refused */
} BGRepairRun;


/* ACTIONS.md Scenario 3, "the interrupted repair": the worker, with a wrench
 * and the miller's diagram (which wrongly shows the trough line's cock as
 * the pump's shutoff), repairs the pump by the recipe. At 60% of the last
 * stage of dismantling it is called away, and puts it down; the smith,
 * beside it, takes the wrench; later the wrench is back. `omniscient`: the
 * stub, which needs no diagram. */
static BGRepairRun   repair_run( BOOL omniscient, BOOL shout)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGEntityID         wrench;
   BGEntityID         diagram;
   BGEntityID         smith;
   BGEntityID         a;
   NSString           *error;
   NSString           *text;
   BGWorld            *w2;
   NSArray            *deferred;
   uint64_t           position;
   BGRepairRun        run;
   int64_t            start;
   int64_t            v;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 83);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [knowledge setOmniscient:omniscient];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g          = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the mill"];
   run.pump   = [g create:"pump" key:"pump" at:BGOnTile( 10, 10, 0)];
   run.trough = [g create:"cock_trough" key:"the trough line's cock" at:BGOnTile( 9, 9, 0)];
   run.riser  = [g create:"cock_pump" key:"the riser's cock" at:BGOnTile( 11, 9, 0)];
   run.worker = [g create:"worker" key:"worker" at:BGOnTile( 10, 9, 0)];
   smith      = [g create:"smith" key:"smith" at:BGOnTile( 11, 10, 0)];
   wrench     = [g create:"wrench_250" key:"wrench" at:BGHeldBy( run.worker, 0)];
   diagram    = [g create:"diagram" key:"diagram" at:BGHeldBy( run.worker, 1)];
   [g set:"Record.writing" of:BGWhole( diagram)
   toText:[st.w intern:"#Writing & { author: #Agent & { coat: \"white\" }, entries: [#Serves & { what: #Cock & "
                       "{ place: #OnTile & { x: 9, y: 9, level: 0 } }, line: \"pump\", attribution: #Saw & { sure: 30 } }] }"]];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   run.pump   = [g idFor:run.pump];
   run.trough = [g idFor:run.trough];
   run.riser  = [g idFor:run.riser];
   run.worker = [g idFor:run.worker];
   smith      = [g idFor:smith];
   wrench     = [g idFor:wrench];
   diagram    = [g idFor:diagram];

   /* it reads the diagram, and sets to the repair */
   error = nil;
   if( ! omniscient)
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "read", run.worker, diagram, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 1000)];
   BG_CHECK( [agency commit:run.worker toGoal:"repair_pump"]);
   [st.s runUntil:BGTimeMake( 3000)];
   a     = activity_of( st.w, run.worker, "dismantle", "running");
   start = 0;
   BG_CHECK( a && [st.w getField:"Activity.started" of:a value:&start]);

   /* 3: talking runs with the dismantling; a second activity for the hands
    * is refused, with the reason */
   [st.s runUntil:BGTimeMake( start + 1000)];
   {
      BGAction   talk;

      talk         = BGActionMake( "say", run.worker, smith, BGNoEntity);
      talk.content = [st.w intern:"#Here & {}"];
      run.talked   = BGPerform( st.w, st.c, talk, 0, &error) != nil;
      error        = nil;
      if( ! BGPerform( st.w, st.c, BGActionMake( "dismantle", run.worker, wrench, run.pump), 0, &error))
         run.refused = [[error copy] autorelease];
      error = nil;
   }

   /* stage 3 is 60% done: called away, it puts the work down; the smith takes the wrench */
   if( shout)
   {
      /* the smith shouts its name, a second's shout ending then: agency decides */
      BGAction   call;

      [st.s runUntil:BGTimeMake( start + 3000 + 3000 + 2000)];
      call         = BGActionMake( "say", smith, run.worker, BGNoEntity);
      call.content = [st.w intern:"#Call & { what: #Agent & { coat: \"blue\" } }"];
      BG_CHECK( BGPerform( st.w, st.c, call, 0, &error) != nil);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1000 + 2)];
      [st.w getField:"Activity.progress" of:a value:&run.progress];
      [st.s runUntil:BGTimeMake( [st.w time].ms + 10000)];
      run.world  = st.w;
      run.agency = agency;
      return( run);
   }
   [st.s runUntil:BGTimeMake( start + 3000 + 3000 + 3000)];
   BG_CHECK( [activities suspend:a because:@"someone shouts its name" error:&error] != nil);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the smith takes the wrench"];
   [g move:BGWhole( wrench) to:BGHeldBy( smith, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
   [st.w getField:"Activity.stage" of:a value:&run.stage];
   [st.w getField:"Activity.progress" of:a value:&run.progress];
   run.openWhileSuspended = [st.w getField:"Pump.opened" of:run.pump value:&v] && v;

   /* saved while suspended, and restored the same */
   text      = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   w2        = BGRestore( text, [st.w contentBuild], &deferred, &position, &error);
   run.saved = w2 && [w2 stateHash] == [st.w stateHash];

   /* 5: restored, with its own knowledge and agency, it takes the next
    * boundary exactly as the run that never saved */
   {
      BGStage        st2;
      BGActivities   *activities2;
      BGKnowledge    *knowledge2;
      BGAgency       *agency2;
      int64_t        next;

      st2.w       = restore( text, [st.w contentBuild], &st2.c, &error);
      activities2 = [BGActivities activitiesWithWorld:st2.w committer:st2.c];
      knowledge2  = [[[BGKnowledge alloc] initWithWorld:st2.w] autorelease];
      agency2     = [[[BGAgency alloc] initWithWorld:st2.w committer:st2.c knowledge:knowledge2] autorelease];
      st2.s       = [[[BGScheduler alloc] initWithWorld:st2.w committer:st2.c] autorelease];
      [knowledge2 setOmniscient:omniscient];
      [knowledge2 restoreSavedState:BGSavedDomainState( text, @"knowledge")];
      [agency2 restoreSavedState:BGSavedDomainState( text, @"agency")];
      [agency2 setActivities:activities2];
      [st2.s setActivities:activities2];
      [st2.s setPerception:knowledge2];
      [st2.s setDecision:agency2];
      /* nothing is due while it is suspended: the next boundary is the stop */
      next         = [st.w time].ms + 2000;
      run.nextSame = [st2.s runUntil:BGTimeMake( next)] == 1;
      run.nextSame = [st.s runUntil:BGTimeMake( next)] == 1 && run.nextSame && [st2.w time].ms == next &&
                     [st2.w stateHash] == [st.w stateHash] &&
                     [BGSave( st2.w, st2.c, [NSArray arrayWithObjects:knowledge2, agency2, nil])
                        isEqualToString:BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil])];
   }

   /* the wrench back: the repair goes on */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the wrench back"];
   [g move:BGWhole( wrench) to:BGHeldBy( run.worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( [st.w time].ms + 10000)];
   run.world  = st.w;
   run.agency = agency;
   return( run);
}


static void   test_interrupted_repair( void)
{
   BGRepairRun   run;
   BGRepairRun   seer;
   BGRepairRun   shout;
   int64_t       v;

   /* 1: the recipe binds through knowledge: by the diagram, the trough line's cock */
   run = repair_run( NO, NO);
   BG_CHECK( logged_by( run.agency, run.worker, @"[repair the pump] follow the recipe: shut_off R"));
   BG_CHECK( [run.world getField:"Cock.shut" of:run.trough value:&v] && v);
   BG_CHECK( [run.world getField:"Cock.shut" of:run.riser value:&v] && ! v);
   /* the omniscient stub binds the riser's */
   seer = repair_run( YES, NO);
   BG_CHECK( [seer.world getField:"Cock.shut" of:seer.riser value:&v] && v);
   BG_CHECK( [seer.world getField:"Cock.shut" of:seer.trough value:&v] && ! v);

   /* 4: suspended at 60% of the last stage: its progress kept, nothing committed */
   BG_CHECK( run.stage == 2 && run.progress == 3000);
   BG_CHECK( ! run.openWhileSuspended);
   /* 6: resuming without the wrench is refused, with the reason */
   BG_CHECK( logged_by( run.agency, run.worker, @"could not resume dismantle: what it needs no longer holds"));
   /* 5: saved while suspended, restored the same, and the next boundary the same */
   BG_CHECK( run.saved);
   BG_CHECK( run.nextSame);
   /* 3: talking ran with the dismantling; a second dismantling was refused, its hands busy */
   BG_CHECK( run.talked);
   BG_CHECK( run.refused && [run.refused rangeOfString:@"its hands are busy with activity"].location != NSNotFound);
   /* the wrench back, it resumes, and the pump is open */
   BG_CHECK( logged_by( run.agency, run.worker, @"follow the recipe: resuming dismantle"));
   BG_CHECK( [run.world getField:"Pump.opened" of:run.pump value:&v] && v);
   BG_CHECK( logged_by( run.agency, run.worker, @"[repair the pump] done"));

   /* the shout as a soft interruption agency decides on: worth 15, more than
    * the interruption, it puts the dismantling down, answers, and goes back */
   shout = repair_run( NO, YES);
   BG_CHECK( logged_by( shout.agency, shout.worker, @"called by R"));
   BG_CHECK( logged_by( shout.agency, shout.worker, @": worth +15: putting dismantle down"));
   BG_CHECK( logged_by( shout.agency, shout.worker, @"answering: say R"));
   BG_CHECK( logged_by( shout.agency, shout.worker, @"follow the recipe: resuming dismantle"));
   BG_CHECK( shout.progress == 3000);            /* put down as the shout is heard, 60% of the way */
   BG_CHECK( [shout.world getField:"Pump.opened" of:shout.pump value:&v] && v);
}


/* --- the unattended stove ------------------------------------------------------ */

typedef struct
{
   BGWorld        *world;
   BGCommitter    *committer;
   BGAtmosphere   *air;
   BGThermal      *thermal;
   BGEntityID     room;
   BGEntityID     shell;
   BGEntityID     stove;
   BGEntityID     rest;
   int64_t        outAt;          /* when the stove went out, ms; 0 if it didn't */
   int64_t        wokenAt;        /* when the rest ended */
   NSUInteger     boundaries;
   int64_t        litAt;
   int64_t        roomHottest;    /* mK */
   int64_t        stoveHottest;
   NSUInteger     thermalBeforeLit;    /* the thermal domain's steps before the fire's heat reached it */
   BOOL           balanced;       /* after every boundary, both domains, and between them */
   NSString       *text;
} BGStoveRun;


/* DOMAIN_SIMULATION.md Scenario 1, "the unattended stove": a room of stone
 * with a stove and 3 kg of wood; a lodger, breathing, lights it and rests
 * for 8 hours, with a watch on the air. `stepped`: in one-minute steps
 * (variant C). `reversed`: the domains added the other way round.
 * `restsAbove`: the lodger rests easy only above it (mK), and lies down two
 * hours after lighting the stove, once the room has warmed. */
static BGStoveRun   stove_run( BOOL damper, BOOL stepped, BOOL reversed, int64_t restsAbove)
{
   BGWorld            *w;
   BGCommitter        *c;
   BGScheduler        *s;
   BGActivities       *activities;
   BGAtmosphere       *air;
   BGThermal          *thermal;
   BGProposalGroup    *g;
   BGEntityID         worker;
   NSString           *error;
   BGStoveRun         run;
   int64_t            v;
   int64_t            end;

   memset( &run, 0, sizeof( run));
   w          = BGTestWorld( 89);
   c          = BGTestCommitter( w);
   activities = [BGActivities activitiesWithWorld:w committer:c];
   air        = [[[BGAtmosphere alloc] initWithWorld:w] autorelease];
   thermal    = [[[BGThermal alloc] initWithWorld:w] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s setActivities:activities];
   [s addDomain:reversed ? (id) thermal : (id) air];
   [s addDomain:reversed ? (id) air : (id) thermal];
   g         = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the room"];
   run.room  = [g create:"room_air" key:"the room's air" at:BGLocationMakeNone()];
   run.shell = [g create:"room_shell" key:"the room's walls" at:BGLocationMakeNone()];
   run.stove = [g create:"stove" key:"stove" at:BGOnTile( 2, 2, 0)];
   worker    = [g create:"lodger" key:"lodger" at:BGOnTile( 3, 2, 0)];
   if( ! damper)
      [g set:"Combustor.damper" of:BGWhole( run.stove) to:0];
   if( restsAbove)
      [g set:"Respirator.restsAbove" of:BGWhole( worker) to:restsAbove];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   run.room  = [g idFor:run.room];
   run.shell = [g idFor:run.shell];
   run.stove = [g idFor:run.stove];
   worker    = [g idFor:worker];
   g         = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the walls bound the room"];
   [g set:"ThermalBody.bounds" of:BGWhole( run.shell) to:(int64_t) run.room];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];

   error = nil;
   run.thermalBeforeLit = [thermal steps];
   BG_CHECK( BGPerform( w, c, BGActionMake( "light", worker, run.stove, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 2)];
   if( [w getField:"Combustor.lit" of:run.stove value:&v] && v)
      run.litAt = [w time].ms;
   if( restsAbove)
      [s runUntil:BGTimeMake( 2 * 3600000LL)];
   g = BGPerform( w, c, BGActionMake( "while_away", worker, BGNoEntity, BGNoEntity), 0, &error);
   BG_CHECK( g != nil);
   [s runUntil:BGTimeMake( [w time].ms + 1)];
   run.rest     = [g idFor:[g proposals][ 0].handle];
   run.balanced = YES;
   end          = 8 * 3600000LL + 10000;
   while( [w time].ms < end)
   {
      if( stepped)
         [s runUntil:BGTimeMake( [w time].ms - [w time].ms % 60000 + 60000)];
      else if( ! [s stepUntil:BGTimeMake( end)])
         break;
      run.boundaries++;
      run.balanced = run.balanced && [air balanced] && [thermal balanced] &&
                     [air sent] == [thermal received] + [thermal pending];
      if( [air temperatureOf:run.room] > run.roomHottest)
         run.roomHottest = [air temperatureOf:run.room];
      if( [thermal temperatureOf:run.stove] > run.stoveHottest)
         run.stoveHottest = [thermal temperatureOf:run.stove];
      if( ! run.outAt && [w getField:"Combustor.lit" of:run.stove value:&v] && ! v)
         run.outAt = [w time].ms;
      if( ! run.wokenAt && strcmp( status_of( w, run.rest), "\"running\""))
         run.wokenAt = [w time].ms;
   }
   run.world     = w;
   run.committer = c;
   run.air       = air;
   run.thermal   = thermal;
   run.text      = BGSave( w, c, [NSArray arrayWithObjects:air, thermal, nil]);
   return( run);
}


static void   test_unattended_stove( void)
{
   BGStoveRun     a;
   BGStoveRun     again;
   BGStoveRun     b;
   BGStoveRun     stepped;
   BGStoveRun     reversed;
   BGStoveRun     d;
   BGAtmosphere   *restored;
   BGThermal      *restoredThermal;
   NSString       *trace;
   NSRange        at;
   int64_t        fuel;
   int64_t        v;
   long long      reached;
   long long      cooled;

   /* A, the flue open: the fire burns 3 kg at 0.25 g a second, 12,000 s, and
    * goes out then, to the millisecond, a predicted event; its iron takes
    * three tenths of the heat and warms the room, and the room its walls; the
    * lodger breathes, and its carbon dioxide stays well below stuffy; the
    * rest runs its 8 hours; and every step balances exactly, in each domain
    * and between them, with what is in transit */
   a = stove_run( YES, NO, NO, 0);
   BG_CHECK( a.balanced);
   BG_CHECK( a.litAt > 0 && a.outAt == a.litAt + 12000000);
   BG_CHECK( [a.world getField:"FuelContainer.fuel" of:a.stove value:&fuel] && fuel == 0);
   BG_CHECK( a.wokenAt >= 8 * 3600000LL);
   BG_CHECK( a.stoveHottest > 330000 && a.roomHottest > 285000);
   BG_CHECK( [a.air temperatureOf:a.room] > 277000);
   BG_CHECK( [a.thermal temperatureOf:a.shell] > 277000);
   BG_CHECK( [a.world getField:"GasStore.dioxide" of:a.room value:&v] && v > 1500 && v < 3000);
   /* 2: time jumps: hundreds of steps for eight hours, not hundreds of
    * thousands. The exchange with the solids lags a step and bounds them
    * while it runs, and the lodger's warmth keeps it running: about 400 */
   BG_CHECK( a.boundaries < 1000);
   /* 6: the thermal domain sleeps until the fire's heat reaches it */
   BG_CHECK( a.thermalBeforeLit == 0 && [a.thermal steps] > 0);

   /* B, the damper left closed: the fire fills the room with carbon dioxide,
    * and the watch wakes the rest at the boundary it crosses, within the
    * event tolerance of a second */
   b = stove_run( NO, NO, NO, 0);
   BG_CHECK( b.balanced);
   BG_CHECK( b.wokenAt > 0 && b.wokenAt < 3600000);
   trace = [[b.committer trace] componentsJoinedByString:@"\n"];
   at    = [trace rangeOfString:@"reaches "];
   reached = at.location != NSNotFound ? atoll( [[trace substringFromIndex:at.location + 8] UTF8String]) : 0;
   BG_CHECK( reached >= 4000 && reached < 4000 + 50);

   /* 3, C: the same, in 480 one-minute steps: exactly as conserved, the
    * fuel all burned, and the room's and walls' temperatures within a
    * kelvin */
   stepped = stove_run( YES, YES, NO, 0);
   BG_CHECK( stepped.balanced);
   BG_CHECK( [stepped.world getField:"FuelContainer.fuel" of:stepped.stove value:&fuel] && fuel == 0);
   BG_CHECK( llabs( [stepped.air temperatureOf:stepped.room] - [a.air temperatureOf:a.room]) < 1000);
   BG_CHECK( llabs( [stepped.thermal temperatureOf:stepped.shell] - [a.thermal temperatureOf:a.shell]) < 1000);
   BG_CHECK( stepped.boundaries >= 480);

   /* determinism, and the domains' state saved */
   again = stove_run( YES, NO, NO, 0);
   BG_CHECK( [again.text isEqualToString:a.text]);
   restored = [[[BGAtmosphere alloc] initWithWorld:a.world] autorelease];
   [restored restoreSavedState:BGSavedDomainState( a.text, @"atmosphere")];
   BG_CHECK( [[restored savedState] isEqualToArray:[a.air savedState]]);
   restoredThermal = [[[BGThermal alloc] initWithWorld:a.world] autorelease];
   [restoredThermal restoreSavedState:BGSavedDomainState( a.text, @"thermal")];
   BG_CHECK( [[restoredThermal savedState] isEqualToArray:[a.thermal savedState]]);

   /* 4: order independence: the domains run the other way round, bit for bit
    * the same */
   reversed = stove_run( YES, NO, YES, 0);
   BG_CHECK( [reversed.text isEqualToString:a.text]);

   /* D, the comfort band: the lodger lies down in the warmed room, resting
    * easy above 280 K, and the cold wakes it after the fire is out */
   d = stove_run( YES, NO, NO, 280000);
   BG_CHECK( d.balanced);
   BG_CHECK( d.wokenAt > d.outAt && d.wokenAt < 8 * 3600000LL);
   trace  = [[d.committer trace] componentsJoinedByString:@"\n"];
   at     = [trace rangeOfString:@"cools to "];
   cooled = at.location != NSNotFound ? atoll( [[trace substringFromIndex:at.location + 9] UTF8String]) : 0;
   BG_CHECK( cooled < 280000 && cooled > 280000 - 5);     /* within a second of the crossing */
}


/* DOMAIN_SIMULATION.md Scenario 1's check 6, local wake. A room of stale air
 * behind a tight door (no gap), off a corridor ten times its size that opens
 * to the outdoors; a second room off the corridor, through a gap; the room's
 * walls bound it. Everything else is fresh and at 275 K, so nothing moves:
 * both domains sleep, and an hour passes in a step. A worker opens the door:
 * the room and the corridor wake, and the room airs out; the back room, and
 * the thermal domain, sleep through it. Once the corridor has settled with
 * the outdoors, everything sleeps again. */
static void   test_local_wake( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGAtmosphere      *air;
   BGThermal         *thermal;
   BGProposalGroup   *g;
   BGEntityID        room;
   BGEntityID        corridor;
   BGEntityID        back;
   BGEntityID        door;
   BGEntityID        shell;
   BGEntityID        worker;
   NSString          *error;
   NSUInteger        n;
   NSUInteger        before;
   BOOL              balanced;
   int64_t           v;
   int64_t           u;

   w       = BGTestWorld( 97);
   c       = BGTestCommitter( w);
   air     = [[[BGAtmosphere alloc] initWithWorld:w] autorelease];
   thermal = [[[BGThermal alloc] initWithWorld:w] autorelease];
   s       = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [s addDomain:air];
   [s addDomain:thermal];
   g        = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the rooms"];
   corridor = [g create:"corridor" key:"the corridor" at:BGLocationMakeNone()];
   room     = [g create:"room_air" key:"the room's air" at:BGLocationMakeNone()];
   back     = [g create:"back_room" key:"the back room's air" at:BGLocationMakeNone()];
   shell    = [g create:"room_shell" key:"the room's walls" at:BGLocationMakeNone()];
   door     = [g create:"room_door" key:"the room's door" at:BGOnTile( 4, 6, 0)];
   worker   = [g create:"worker" key:"worker" at:BGOnTile( 4, 5, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   corridor = [g idFor:corridor];
   room     = [g idFor:room];
   back     = [g idFor:back];
   shell    = [g idFor:shell];
   door     = [g idFor:door];
   worker   = [g idFor:worker];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the doors, and a night's stale air"];
   [g set:"GasStore.opensTo" of:BGWhole( room) to:(int64_t) corridor];
   [g set:"GasStore.door" of:BGWhole( room) to:(int64_t) door];
   [g set:"GasStore.gap" of:BGWhole( room) to:0];
   [g set:"GasStore.dioxide" of:BGWhole( room) to:1600];
   [g set:"GasStore.opensTo" of:BGWhole( back) to:(int64_t) corridor];
   [g set:"ThermalBody.bounds" of:BGWhole( shell) to:(int64_t) room];
   [c submit:g];
   [s runUntil:BGTimeMake( 2)];

   /* asleep: an hour in a step */
   BG_CHECK( ! [air isActive] && ! [thermal isActive]);
   n = [s runUntil:BGTimeMake( 3600000)];
   BG_CHECK( n == 1 && [air steps] == 0 && [thermal steps] == 0);

   /* the door opens: the room and the corridor wake, not the back room */
   error = nil;
   BG_CHECK( BGPerform( w, c, BGActionMake( "open_door", worker, door, BGNoEntity), 0, &error) != nil);
   [s runUntil:BGTimeMake( 3600001)];
   BG_CHECK( [w getField:"Door.ajar" of:door value:&v] && v == 1);
   BG_CHECK( [air isActive]);
   balanced = YES;
   while( [w time].ms < 2 * 3600000)
   {
      if( ! [s stepUntil:BGTimeMake( 2 * 3600000)])
         [s runUntil:BGTimeMake( 2 * 3600000)];
      balanced = balanced && [air balanced];
   }
   BG_CHECK( [air stepsOf:room] > 0 && [air stepsOf:corridor] > 0);
   BG_CHECK( [air stepsOf:back] == 0 && [thermal steps] == 0);
   /* aired: within the settle tolerance of the corridor, scaled */
   BG_CHECK( [w getField:"GasStore.dioxide" of:room value:&v] && [w getField:"GasStore.dioxide" of:corridor value:&u] &&
             llabs( v - u / 10) <= 100);

   /* then everything settles and sleeps, in a few dozen steps */
   before = [air steps];
   while( [w time].ms < 24 * 3600000)
   {
      if( ! [s stepUntil:BGTimeMake( 24 * 3600000)])
         [s runUntil:BGTimeMake( 24 * 3600000)];
      balanced = balanced && [air balanced];
   }
   BG_CHECK( balanced);
   BG_CHECK( ! [air isActive] && ! [thermal isActive]);
   BG_CHECK( [air steps] - before < 40);
   BG_CHECK( [air stepsOf:back] == 0 && [thermal steps] == 0);
}


/* AGENCY.md §6's warmth: a lodger by the cold stove, its body at `kelvin`
 * (mK). Interoception feels its body's heat, the thermal domain's, as
 * cold; cold enough, the needs generator raises *get warm*, and it lights
 * the stove. */
static BGStoveRun   cold_lodger( int64_t kelvin, int64_t numbness, BGAgency **minds, BGKnowledge **known)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGAtmosphere       *air;
   BGThermal          *thermal;
   BGProposalGroup    *g;
   BGEntityID         lodger;
   BGStoveRun         run;

   memset( &run, 0, sizeof( run));
   st.w       = BGTestWorld( 101);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   air        = [[[BGAtmosphere alloc] initWithWorld:st.w] autorelease];
   thermal    = [[[BGThermal alloc] initWithWorld:st.w] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   [st.s addDomain:air];
   [st.s addDomain:thermal];
   g         = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a cold room"];
   run.room  = [g create:"room_air" key:"the room's air" at:BGLocationMakeNone()];
   run.stove = [g create:"stove" key:"stove" at:BGOnTile( 2, 2, 0)];
   lodger    = [g create:"lodger" key:"lodger" at:BGOnTile( 3, 2, 0)];
   [g set:"ThermalBody.heat" of:BGWhole( lodger) to:kelvin * 245000 / 1000];
   [g set:"Agent.numbness" of:BGWhole( lodger) to:numbness];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   run.room  = [g idFor:run.room];
   run.stove = [g idFor:run.stove];
   run.rest  = [g idFor:lodger];         /* the lodger */
   [agency control:run.rest];
   [st.s runUntil:BGTimeMake( 60000)];
   run.world     = st.w;
   run.committer = st.c;
   run.air       = air;
   run.thermal   = thermal;
   *minds        = agency;
   *known        = knowledge;
   return( run);
}


/* The lodger, resting by the cold stove, cools (it breathes at rest): its
 * body crossing 307 K is felt as cold 30 at a boundary the thermal domain
 * predicted, not hours after. Returns how far below 307 K the body was then,
 * mK, or -1 if it never was. */
static int64_t   cooling_lodger( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGThermal          *thermal;
   BGProposalGroup    *g;
   BGEntityID         lodger;
   NSString           *error;

   st.w       = BGTestWorld( 113);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   thermal    = [[[BGThermal alloc] initWithWorld:st.w] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s addDomain:[[[BGAtmosphere alloc] initWithWorld:st.w] autorelease]];
   [st.s addDomain:thermal];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a cold room"];
   [g create:"room_air" key:"the room's air" at:BGLocationMakeNone()];
   lodger = [g create:"lodger" key:"lodger" at:BGOnTile( 3, 2, 0)];
   [g set:"ThermalBody.heat" of:BGWhole( lodger) to:307100LL * 245000 / 1000];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   lodger = [g idFor:lodger];
   error  = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "while_away", lodger, BGNoEntity, BGNoEntity), 0, &error) != nil);
   while( [st.w time].ms < 4 * 3600000LL && [st.s stepUntil:BGTimeMake( 4 * 3600000LL)])
      if( [[knowledge storeOf:lodger] feels:"cold"] >= 30)
         return( 307000 - [thermal temperatureOf:lodger]);
   return( -1);
}


static void   test_cold_lodger( void)
{
   BGStoveRun   cold;
   BGStoveRun   cool;
   BGAgency     *agency;
   BGKnowledge  *knowledge;
   int64_t      v;
   int64_t      below;

   /* 305 K, five below: it feels cold 50, more than 30: it lights the stove */
   cold = cold_lodger( 305000, 0, &agency, &knowledge);
   BG_CHECK( [[knowledge storeOf:cold.rest] feels:"cold"] == 50);
   BG_CHECK( logged_by( agency, cold.rest, @"[get warm] light the stove: light R"));
   /* the pressure, by its curve: cold 50 is worth 30 (a straight line by 5
    * tenths would give 25) */
   BG_CHECK( logged_by( agency, cold.rest, @"weighing get warm: +30 (cold +30)"));
   BG_CHECK( [cold.world getField:"Combustor.lit" of:cold.stove value:&v] && v);
   BG_CHECK( logged_by( agency, cold.rest, @"[get warm] done"));

   /* resting, it cools past 307 K, and feels it within a few mK */
   below = cooling_lodger();
   BG_CHECK( below >= 0 && below < 5);

   /* numb (30), at 305 K it feels only 20: its body is as cold, but it
    * leaves the stove cold (AGENCY.md §6: numbness hides cold) */
   cool = cold_lodger( 305000, 30, &agency, &knowledge);
   BG_CHECK( [[knowledge storeOf:cool.rest] feels:"cold"] == 20);
   BG_CHECK( [cool.world getField:"Combustor.lit" of:cool.stove value:&v] && ! v);

   /* 308.5 K: cold 10, not pressing: the stove stays cold */
   cool = cold_lodger( 308500, 0, &agency, &knowledge);
   BG_CHECK( [[knowledge storeOf:cool.rest] feels:"cold"] == 10);
   BG_CHECK( ! logged_by( agency, cool.rest, @"get warm"));
   BG_CHECK( [cool.world getField:"Combustor.lit" of:cool.stove value:&v] && ! v);
}


/* AGENCY.md §6's air: a lodger in a room whose air holds `dioxide` mmol,
 * beside its shut door to the corridor. Interoception feels the air's carbon
 * dioxide as shortness of breath; enough, and it airs the room. */
static BOOL   stuffy_lodger( int64_t dioxide, int32_t *felt, BGAgency **minds, BGEntityID *who)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGAtmosphere       *air;
   BGProposalGroup    *g;
   BGEntityID         room;
   BGEntityID         corridor;
   BGEntityID         door;
   BGEntityID         lodger;
   int64_t            v;

   st.w       = BGTestWorld( 103);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   air        = [[[BGAtmosphere alloc] initWithWorld:st.w] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   [st.s addDomain:air];
   g        = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a shut room"];
   corridor = [g create:"corridor" key:"the corridor" at:BGLocationMakeNone()];
   room     = [g create:"room_air" key:"the room's air" at:BGLocationMakeNone()];
   door     = [g create:"room_door" key:"the room's door" at:BGOnTile( 4, 6, 0)];
   lodger   = [g create:"lodger" key:"lodger" at:BGOnTile( 4, 5, 0)];
   [g set:"GasStore.dioxide" of:BGWhole( room) to:dioxide];
   [g set:"GasStore.gap" of:BGWhole( room) to:0];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   room     = [g idFor:room];
   corridor = [g idFor:corridor];
   door     = [g idFor:door];
   lodger   = [g idFor:lodger];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the door"];
   [g set:"GasStore.opensTo" of:BGWhole( room) to:(int64_t) corridor];
   [g set:"GasStore.door" of:BGWhole( room) to:(int64_t) door];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 2)];
   *felt  = [[knowledge storeOf:lodger] feels:"stuffy"];
   [agency control:lodger];
   [st.s runUntil:BGTimeMake( 30000)];
   *minds = agency;
   *who   = lodger;
   return( [st.w getField:"Door.ajar" of:door value:&v] && v);
}


static void   test_stuffy_lodger( void)
{
   BGAgency     *agency;
   BGEntityID   lodger;
   int32_t      felt;

   /* 0.5% carbon dioxide: short of breath 40, more than 30: it opens the door */
   BG_CHECK( stuffy_lodger( 10000, &felt, &agency, &lodger));
   BG_CHECK( felt == 40);
   BG_CHECK( logged_by( agency, lodger, @"[air the room] open a door: open_door R"));
   BG_CHECK( logged_by( agency, lodger, @"[air the room] done"));
   /* 0.12%: 0, and the door stays shut */
   BG_CHECK( ! stuffy_lodger( 2400, &felt, &agency, &lodger));
   BG_CHECK( felt == 0 && ! logged_by( agency, lodger, @"air the room"));
}


/* ACTIONS.md §5's partial effects: the worker saws a log through, eight
 * seconds with three checkpoints. `stop`: what happens at five seconds,
 * 62.5% of the way: nothing (0), suspended (1), aborted (2), or the saw
 * taken from its hand, so that completing fails (3). Then three seconds
 * more, and resuming if suspended. The log's cut as it goes, at each
 * second, into `cut`. */
static BOOL   saw_run( int stop, int64_t cut[ 12], const char **status)
{
   BGStage            st;
   BGActivities       *activities;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         log;
   BGEntityID         saw;
   BGEntityID         smith;
   BGEntityID         a;
   NSString           *error;
   int64_t            start;
   int                i;

   st.w       = BGTestWorld( 107);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:activities];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the sawhorse"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 3, 3, 0)];
   smith  = [g create:"smith" key:"smith" at:BGOnTile( 3, 4, 0)];
   log    = [g create:"log" key:"log" at:BGOnTile( 4, 3, 0)];
   saw    = [g create:"hand_saw" key:"saw" at:BGHeldBy( worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   smith  = [g idFor:smith];
   log    = [g idFor:log];
   saw    = [g idFor:saw];
   error  = nil;
   g      = BGPerform( st.w, st.c, BGActionMake( "saw_through", worker, saw, log), 0, &error);
   BG_CHECK( g != nil);
   [st.s runUntil:BGTimeMake( 2)];
   a = [g idFor:[g proposals][ 0].handle];
   [st.w getField:"Activity.started" of:a value:&start];
   for( i = 0; i < 12; i++)
   {
      [st.s runUntil:BGTimeMake( start + i * 1000)];
      cut[ i] = -1;
      [st.w getField:"Log.sawn" of:log value:&cut[ i]];
      if( i == 5 && stop == 1)
         BG_CHECK( [activities suspend:a because:@"called away" error:&error] != nil);
      if( i == 5 && stop == 2)
         BG_CHECK( [activities abort:a because:@"enough" error:&error] != nil);
      if( i == 5 && stop == 3)
      {
         BGProposalGroup   *take;

         take = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the smith takes the saw"];
         [take move:BGWhole( saw) to:BGHeldBy( smith, 0)];
         [st.c submit:take];
      }
      if( i == 8 && stop == 1)
         BG_CHECK( [activities resume:a error:&error] != nil);
   }
   *status = status_of( st.w, a);
   return( YES);
}


/* A hard interruption, as the stage declares: a take whose item is snatched
 * from where it lay fails at once, there being nothing to come back to;
 * sawing whose saw is taken is suspended (below). */
static void   test_hard_fail( void)
{
   BGStage           st;
   BGActivities      *activities;
   BGProposalGroup   *g;
   BGProposalGroup   *take;
   BGEntityID        worker;
   BGEntityID        smith;
   BGEntityID        saw;
   BGEntityID        a;
   NSString          *error;
   NSString          *trace;
   int64_t           start;

   st.w       = BGTestWorld( 109);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:activities];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a saw on the bench"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 3, 3, 0)];
   smith  = [g create:"smith" key:"smith" at:BGOnTile( 3, 4, 0)];
   saw    = [g create:"hand_saw" key:"saw" at:BGOnTile( 4, 3, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   smith  = [g idFor:smith];
   saw    = [g idFor:saw];
   error  = nil;
   g      = BGPerform( st.w, st.c, BGActionMake( "take_up", worker, saw, BGNoEntity), 0, &error);
   BG_CHECK( g != nil);
   [st.s runUntil:BGTimeMake( 2)];
   a = [g idFor:[g proposals][ 0].handle];
   [st.w getField:"Activity.started" of:a value:&start];
   take = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the smith snatches the saw"];
   [take move:BGWhole( saw) to:BGHeldBy( smith, 0)];
   [st.c submit:take];
   [st.s runUntil:BGTimeMake( start + 500)];
   BG_CHECK( ! strcmp( status_of( st.w, a), "\"failed\""));
   trace = [[st.c trace] componentsJoinedByString:@"\n"];
   BG_CHECK( [trace rangeOfString:@": failed (what it needs no longer holds, at roles.item.place)"].location != NSNotFound);
   [st.s runUntil:BGTimeMake( start + 2000)];
   BG_CHECK( [st.w locationOf:saw].place == smith);
}


/* AGENCY.md §6's rest: a worker already somewhat tired (40) saws a log
 * through, which takes it out of it (exertion 30): it feels tired 70, more
 * than 50, and lies down; rested through, eight hours on, its fatigue is
 * gone. */
static void   test_tired_worker( void)
{
   BGStage            st;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         log;
   BGEntityID         saw;
   NSString           *error;
   int64_t            fatigue;

   st.w       = BGTestWorld( 131);
   st.c       = BGTestCommitter( st.w);
   activities = [BGActivities activitiesWithWorld:st.w committer:st.c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:st.w committer:st.c knowledge:knowledge] autorelease];
   st.s       = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [agency setActivities:activities];
   [st.s setActivities:activities];
   [st.s setPerception:knowledge];
   [st.s setDecision:agency];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the sawhorse"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 3, 3, 0)];
   log    = [g create:"log" key:"log" at:BGOnTile( 4, 3, 0)];
   saw    = [g create:"hand_saw" key:"saw" at:BGHeldBy( worker, 0)];
   [g set:"Agent.fatigue" of:BGWhole( worker) to:40];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   log    = [g idFor:log];
   saw    = [g idFor:saw];
   BG_CHECK( [[knowledge storeOf:worker] feels:"tired"] == 40);
   /* fed 80, it feels hunger 20, as precisely as ever */
   BG_CHECK( [[knowledge storeOf:worker] feels:"hunger"] == 20);
   error = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "saw_through", worker, saw, log), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 10000)];
   BG_CHECK( [st.w getField:"Agent.fatigue" of:worker value:&fatigue] && fatigue == 70);
   BG_CHECK( [[knowledge storeOf:worker] feels:"tired"] == 70);
   /* exhausted, it would feel hunger only to the twenty: at 90, its 30 is felt 20 */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: worn out, and hungrier"];
   [g set:"Agent.fatigue" of:BGWhole( worker) to:90];
   [g set:"Agent.fed" of:BGWhole( worker) to:70];
   [g set:"Agent.fedAt" of:BGWhole( worker) to:[st.w time].ms];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( [st.w time].ms + 2)];
   BG_CHECK( [[knowledge storeOf:worker] feels:"hunger"] == 20 && [[knowledge storeOf:worker] feels:"tired"] == 90);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: as tired as it was"];
   [g set:"Agent.fatigue" of:BGWhole( worker) to:70];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( [st.w time].ms + 2)];
   BG_CHECK( [[knowledge storeOf:worker] feels:"hunger"] == 30);
   [agency control:worker];
   [st.s runUntil:BGTimeMake( 20000)];
   BG_CHECK( logged_by( agency, worker, @"weighing get some rest: +35 (tired +35)"));
   BG_CHECK( logged_by( agency, worker, @"[get some rest] lie down: while_away"));
   [st.s runUntil:BGTimeMake( 9 * 3600000LL)];
   BG_CHECK( [st.w getField:"Agent.fatigue" of:worker value:&fatigue] && fatigue == 0);
   BG_CHECK( [[knowledge storeOf:worker] feels:"tired"] == 0);
   BG_CHECK( logged_by( agency, worker, @"[get some rest] done"));
}


/* AGENCY.md §6's pain: injury, a component field, is felt as pain, to the
 * band; adrenaline dulls it, not the injury. */
static void   test_pain( void)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGProposalGroup    *g;
   BGEntityID         worker;
   int64_t            injury;

   st.w      = BGTestWorld( 139);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a hurt hand"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 3, 3, 0)];
   [g set:"Agent.injury" of:BGWhole( worker) to:45];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   BG_CHECK( [[knowledge storeOf:worker] feels:"pain"] == 40);
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a fright"];
   [g set:"Agent.adrenaline" of:BGWhole( worker) to:30];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 2)];
   BG_CHECK( [[knowledge storeOf:worker] feels:"pain"] == 10);
   BG_CHECK( [st.w getField:"Agent.injury" of:worker value:&injury] && injury == 45);
   BG_CHECK( [[knowledge dump:worker] rangeOfString:@"pain 10"].location != NSNotFound);
}


/* KNOWLEDGE.md §5: "Each perceiver has an attention budget per boundary.
 * Salience decides what gets attention first." Mira, curious (she notices
 * anything), watches `takes` workers take up a stone each at one boundary,
 * the last of them speaking to her as well, while something clatters among
 * them. At rest she attends to ten events: the remark first (being
 * addressed), then the first nine takes; the rest go unnoticed. What is
 * left goes to the clatter, then to thinking it over. */
static BOOL   disturbed( BGKnowledgeStore *store);
static BOOL   heard_clatter( BGKnowledgeStore *store);


static void   attention_scene( NSUInteger takes)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   BGEntityID         mira;
   BGEntityID         workers[ 12];
   BGEntityID         stones[ 12];
   BGAction           say;
   NSString           *error;
   NSUInteger         i;
   NSUInteger         moves;
   NSUInteger         said;
   NSUInteger         n;
   NSUInteger         e;
   int64_t            at;

   st.w      = BGTestWorld( 167);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   [st.s setActivities:[BGActivities activitiesWithWorld:st.w committer:st.c]];
   g    = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a yard"];
   /* two rows of six, in sight of her; the last beside her */
   mira = [g create:"mira" key:"mira" at:BGOnTile( 8, 8, 0)];
   [g set:"Agent.hiding" of:BGWhole( mira) to:0];
   for( i = 0; i < 12; i++)
   {
      BGLocation   at;

      at          = BGOnTile( 4 + (int32_t) (i % 6), i < 6 ? 7 : 9, 0);
      workers[ i] = [g create:"worker" key:[[NSString stringWithFormat:@"worker %lu", (unsigned long) i] UTF8String]
                           at:at];
      stones[ i]  = [g create:"stone" key:[[NSString stringWithFormat:@"stone %lu", (unsigned long) i] UTF8String]
                           at:at];
   }
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   mira = [g idFor:mira];
   for( i = 0; i < 12; i++)
   {
      workers[ i] = [g idFor:workers[ i]];
      stones[ i]  = [g idFor:stones[ i]];
   }
   /* the last worker starts speaking to her, a second's remark */
   error       = nil;
   say         = BGActionMake( "say", workers[ 11], mira, BGNoEntity);
   say.content = [st.w intern:"#Here & { what: #Agent }"];
   BG_CHECK( BGPerform( st.w, st.c, say, 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 1000)];

   /* and as it ends, they all take up their stones */
   for( i = 12 - takes; i < 12; i++)
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take", workers[ i], stones[ i], BGNoEntity), 0, &error) != nil);
   /* and a clatter on the floor among them */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: something falls"];
   BGMakeTrace( st.w, g, "clatter", BGNoEntity, BGOnTile( 8, 9, 0), 60, "a falling tin");
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1001)];
   at = [st.w time].ms;

   store = [knowledge storeOf:mira];
   moves = 0;
   said  = 0;
   for( i = 0; i < [store observationCount]; i++)
   {
      if( [store observationAt:i]->time != at)
         continue;
      if( ! strcmp( [store observationAt:i]->kind, "moved"))
         moves++;
      if( ! strcmp( [store observationAt:i]->kind, "said"))
         said++;
   }
   BG_CHECK( said == 1 && moves == (takes < 9 ? takes : 9));
   /* the first nine takes, in the order they happened (committed) */
   n = 0;
   for( e = 0; e < [st.w eventCount]; e++)
   {
      const BGEvent   *ev;
      NSUInteger      k;
      BOOL            kept;

      ev = [st.w eventAt:e];
      if( strcmp( ev->kind, "moved") || ev->actor == ev->subject || ! ev->actor || ev->actor == mira)
         continue;
      kept = NO;
      for( k = 0; k < [store observationCount]; k++)
         if( [store observationAt:k]->time == at && ! strcmp( [store observationAt:k]->kind, "moved") &&
             [store observationAt:k]->actor == referent_of( store, ev->actor))
            kept = YES;
      BG_CHECK( kept == (n < 9));
      n++;
   }
   BG_CHECK( n == takes);

   /* the clatter, new to her: with twelve takes, no attention is left to
    * hear it; with eight, she hears it, but none is left to think it over
    * (KNOWLEDGE.md §9: immediate interpretation, within the budget). At
    * the next, quiet boundary, while it can still be heard, she does both */
   BG_CHECK( heard_clatter( store) == (takes < 9));
   BG_CHECK( ! disturbed( store));
   [st.s runUntil:BGTimeMake( 1500)];
   BG_CHECK( heard_clatter( store) && disturbed( store));
}


static void   test_attention_budget( void)
{
   attention_scene( 12);
   attention_scene( 8);
}


/* Whether the store has perceived a clatter. */
static BOOL   heard_clatter( BGKnowledgeStore *store)
{
   NSUInteger   i;

   for( i = 0; i < [store traceCount]; i++)
      if( ! strcmp( [store traceAt:i]->kind, "clatter"))
         return( YES);
   return( NO);
}


/* Whether the store has concluded a disturbance about anything. */
static BOOL   disturbed( BGKnowledgeStore *store)
{
   NSUInteger   i;

   for( i = 0; i < [store findingCount]; i++)
      if( ! strcmp( [store findingAt:i]->kind, "#Disturbance"))
         return( YES);
   return( NO);
}


/* KNOWLEDGE.md §3: "Traces on stacks trigger automatic individuation ...
 * marked units never merge." Ten nails on the floor; a scratch and a creak
 * put on the stack in one group mark one nail, split off first, and it
 * won't merge back. A nail with only a creak merges back once the creak
 * has run out. */
static void   test_traced_units( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGScheduler       *s;
   BGProposalGroup   *g;
   BGEntityID        nails;
   BGEntityID        marked;
   BGEntityID        bearers[ 2];
   BGStore           *traces;
   NSUInteger        i;
   NSUInteger        n;

   w     = BGTestWorld( 163);
   c     = BGTestCommitter( w);
   nails = commit_create( c, "nails_10", BGOnTile( 3, 3, 0));
   g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"a scratch and a creak, on the stack"];
   BGMakeTrace( w, g, "scratch", nails, BGLocationMakeNone(), 40, "a file");
   BGMakeTrace( w, g, "creak", nails, BGLocationMakeNone(), 40, "a file");
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( [g applied]);
   BG_CHECK( [w unitsOf:nails] == 9);
   traces = [w storeForKind:[w kindNamed:"Trace"]];
   n      = 0;
   for( i = 0; i < [traces count] && n < 2; i++)
      bearers[ n++] = (BGEntityID) ((const BGTrace *) [traces recordAtIndex:i])->bearer;
   BG_CHECK( n == 2 && bearers[ 0] == bearers[ 1] && bearers[ 0] != nails);
   marked = bearers[ 0];
   BG_CHECK( [w isLive:marked] && [w unitsOf:marked] == 1 && [w hasEdge:BGEdgeSplitFrom from:marked to:nails]);

   /* marked, it won't merge back */
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"put the marked nail back"];
   [g merge:BGWhole( marked) into:BGWhole( nails)];
   [c submit:g];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"one bears a trace"].location != NSNotFound);

   /* a nail with only a creak on it: once the creak has run out, it does */
   s = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"a creak alone, on the stack"];
   BGMakeTrace( w, g, "creak", nails, BGLocationMakeNone(), 40, "a file");
   [c submit:g];
   [s runUntil:BGTimeMake( [w time].ms + 1)];
   BG_CHECK( [g applied] && [w unitsOf:nails] == 8);
   marked = [g idFor:[g proposals][ 0].handle];
   marked = (BGEntityID) ((const BGTrace *) [traces recordFor:marked])->bearer;
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"put it back, creaking"];
   [g merge:BGWhole( marked) into:BGWhole( nails)];
   [c submit:g];
   [s runUntil:BGTimeMake( [w time].ms + 1)];
   BG_CHECK( ! [g applied]);
   [s runUntil:BGTimeMake( [w time].ms + 5000)];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"put it back, quiet now"];
   [g merge:BGWhole( marked) into:BGWhole( nails)];
   [c submit:g];
   [s runUntil:BGTimeMake( [w time].ms + 1)];
   BG_CHECK( [g applied] && [w unitsOf:nails] == 9);
}


/* KNOWLEDGE.md §3: "A trace whose perceivability would fall below its
 * kind's floor is removed at that time, which the trace system reports to
 * the scheduler as a nextEvent." A soap smell (floor 20), made at 60 to
 * last a day, is gone when it falls below 20: two thirds of the way, at
 * 16 h, a boundary of its own; scuffs (no floor) last their thirty days. */
static void   test_trace_floor( void)
{
   BGStage            st;
   BGTraces           *traces;
   BGProposalGroup    *g;
   BGEntityID         soap;
   BGEntityID         scuffs;
   const BGTrace      *record;
   int64_t            born;

   st.w   = BGTestWorld( 181);
   st.c   = BGTestCommitter( st.w);
   st.s   = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   traces = [[[BGTraces alloc] initWithWorld:st.w] autorelease];
   [st.s addDomain:traces];
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a washed floor"];
   BGMakeTrace( st.w, g, "soap_smell", BGNoEntity, BGOnTile( 4, 4, 0), 60, "a scrubbing");
   BGMakeTrace( st.w, g, "scuffs", BGNoEntity, BGOnTile( 4, 5, 0), 60, "boots");
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   soap   = [g idFor:[g proposals][ 0].handle];
   scuffs = BGNoEntity;
   {
      NSUInteger   i;

      for( i = 1; i < [g count]; i++)
         if( [g proposals][ i].kind == BGProposeCreate)
            scuffs = [g idFor:[g proposals][ i].handle];
   }
   record = [st.w record:[st.w kindNamed:"Trace"] for:soap];
   BG_CHECK( record && BGTraceGone( st.w, record) == record->created + 16 * 3600000LL + 1);
   born = record->created;
   BG_CHECK( [traces horizonAt:[st.w time]].nextEvent.ms == born + 16 * 3600000LL + 1);
   /* still there just before; gone at its own boundary */
   BG_CHECK( [st.s runUntil:BGTimeMake( born + 16 * 3600000LL)] == 1);
   BG_CHECK( [st.w isLive:soap]);
   BG_CHECK( [st.s runUntil:BGTimeMake( born + 17 * 3600000LL)] == 2);
   BG_CHECK( ! [st.w isLive:soap] && [st.w isLive:scuffs]);
}


/* KNOWLEDGE.md §3: foot traffic speeds a trace's decay, as its kind
 * declares. A damp floor and scuffs on one tile, a damp floor on the next;
 * a worker steps onto the first, off, and on again. Each step takes a
 * quarter of the damp's remaining life there; scuffs, and the damp next
 * door, keep theirs. */
static void   test_trodden( void)
{
   BGStage            st;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         damp;
   BGEntityID         scuffs;
   BGEntityID         beside;
   NSString           *error;
   int64_t            v;
   int64_t            left;
   int64_t            born;

   st.w   = BGTestWorld( 157);
   st.c   = BGTestCommitter( st.w);
   st.s   = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setActivities:[BGActivities activitiesWithWorld:st.w committer:st.c]];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a mopped floor"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   BGMakeTrace( st.w, g, "damp_floor", BGNoEntity, BGOnTile( 6, 5, 0), 80, "a mop");
   BGMakeTrace( st.w, g, "scuffs", BGNoEntity, BGOnTile( 6, 5, 0), 50, "boots");
   BGMakeTrace( st.w, g, "damp_floor", BGNoEntity, BGOnTile( 7, 5, 0), 80, "a mop");
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   damp   = BGNoEntity;
   scuffs = BGNoEntity;
   beside = BGNoEntity;
   {
      NSUInteger   i;

      for( i = 0; i < [g count]; i++)
         if( [g proposals][ i].kind == BGProposeCreate)
         {
            BGEntityID   e;

            e = [g idFor:[g proposals][ i].handle];
            if( [st.w textField:"Trace.traceKind" of:e] && ! strcmp( [st.w textField:"Trace.traceKind" of:e], "scuffs"))
               scuffs = e;
            else if( [st.w getField:"Trace.tileX" of:e value:&v] && v == 7)
               beside = e;
            else if( [st.w getField:"Trace.tileX" of:e value:&v] && v == 6)
               damp = e;
         }
   }
   BG_CHECK( damp && scuffs && beside);

   /* onto it: a quarter of what is left of six hours, gone (within the
    * second the step takes) */
   BG_CHECK( [st.w getField:"Trace.created" of:damp value:&born]);
   error = nil;
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "walk_east", worker, BGNoEntity, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 1001)];
   BG_CHECK( [st.w getField:"Trace.expires" of:damp value:&left]);
   BG_CHECK( llabs( (left - born) - 6 * 3600000LL * 3 / 4) < 2000);
   BG_CHECK( [st.w getField:"Trace.expires" of:scuffs value:&v] && v == born + 30 * 86400000LL);
   BG_CHECK( [st.w getField:"Trace.expires" of:beside value:&v] && v == born + 6 * 3600000LL);
   /* off, and on again: another quarter of what is left */
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "walk_west", worker, BGNoEntity, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 2002)];
   BG_CHECK( [st.w getField:"Trace.expires" of:damp value:&v] && v == left);
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "walk_east", worker, BGNoEntity, BGNoEntity), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( 3003)];
   BG_CHECK( [st.w getField:"Trace.expires" of:damp value:&v] &&
             llabs( (v - born) - 6 * 3600000LL * 9 / 16) < 4000);
}


/* KNOWLEDGE.md §12: strength "decays at a rate set by salience and
 * repetition". The worker sees a stone beside it (`sightings` times, going
 * away for two minutes between), or moves it itself into a bin (`moves`),
 * then goes
 * away for ten days. The strength of its belief of where the stone is. */
static int32_t   remembered( int sightings, BOOL moves)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         stone;
   BGEntityID         bin;
   NSString           *error;
   int                i;

   st.w      = BGTestWorld( 151);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a stone"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   stone  = [g create:"stone" key:"stone" at:BGOnTile( 6, 5, 0)];
   bin    = [g create:"bin" key:"bin" at:BGOnTile( 4, 5, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   stone  = [g idFor:stone];
   bin    = [g idFor:bin];
   for( i = 1; i < sightings; i++)
   {
      stage_move( &st, worker, 25, 25);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 120000)];
      stage_move( &st, worker, 5, 5);
   }
   if( moves)
   {
      error = nil;
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take", worker, stone, BGNoEntity), 0, &error) != nil);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "put_in", worker, stone, bin), 0, &error) != nil);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
   }
   stage_move( &st, worker, 25, 25);
   [st.s runUntil:BGTimeMake( [st.w time].ms + 10 * BG_MEMORY_STEP)];
   store = [knowledge storeOf:worker];
   return( [store strengthOf:referent_of( store, stone)]);
}


/* Forgetting is a scheduled `nextEvent` (KNOWLEDGE.md §12): a stone seen
 * once fades below belief on the sixteenth day after it was last seen;
 * with nothing else happening, a boundary comes then, and it is forgotten
 * there, not at the next boundary something else brings. */
static void   test_scheduled_forgetting( void)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         stone;
   int64_t            when;
   int64_t            seen;

   st.w      = BGTestWorld( 151);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: a stone"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   stone  = [g create:"stone" key:"stone" at:BGOnTile( 6, 5, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   stone  = [g idFor:stone];
   stage_move( &st, worker, 25, 25);
   store = [knowledge storeOf:worker];
   seen  = [store referent:referent_of( store, stone)]->seen;
   when  = [store forgettingOf:referent_of( store, stone)];
   BG_CHECK( when == seen + 16 * BG_MEMORY_STEP);
   BG_CHECK( [knowledge nextForgetting].ms == when);
   /* nothing but the forgetting between: one boundary there, one at the end */
   BG_CHECK( [st.s runUntil:BGTimeMake( when - 1)] == 1);
   BG_CHECK( [store referent:referent_of( store, stone)]->present);
   BG_CHECK( [st.s runUntil:BGTimeMake( when + 3600000)] == 2);
   BG_CHECK( ! [store referent:referent_of( store, stone)]->present);
   BG_CHECK( [knowledge nextForgetting].ms == BGTimeNever.ms);
}


static void   test_memory_rates( void)
{
   /* seen once: BG_FADE a day */
   BG_CHECK( remembered( 1, NO) == BG_SEEN - 10 * BG_FADE);
   /* sighted three times: half as fast */
   BG_CHECK( remembered( 3, NO) == BG_SEEN - 10 * BG_FADE / 2);
   /* moved by its own hand (salience BG_OWN_DEED): half as fast too */
   BG_CHECK( remembered( 1, YES) == BG_SEEN - 10 * BG_FADE * BG_NOTICE / BG_OWN_DEED);
}


/* AGENCY.md Scenario 1's belief from habit. The worker puts the wrench
 * in the bin `times` times, taking it out again, then once in the crate,
 * and goes away. Six weeks on (its own doing, the wrench is remembered
 * twice as long as something only seen: a month isn't enough), its memory
 * of where the wrench is has faded:
 * by habit it believes it in the bin (wrongly, as Oskar does the hook);
 * with no habit, it doesn't know. The referent, described. */
static NSString   *habitual_belief( int times, BOOL *present)
{
   BGStage            st;
   BGKnowledge        *knowledge;
   BGKnowledgeStore   *store;
   BGProposalGroup    *g;
   BGEntityID         worker;
   BGEntityID         wrench;
   BGEntityID         bin;
   BGEntityID         crate;
   NSString           *error;
   int                i;

   st.w      = BGTestWorld( 149);
   st.c      = BGTestCommitter( st.w);
   knowledge = [[[BGKnowledge alloc] initWithWorld:st.w] autorelease];
   st.s      = [[[BGScheduler alloc] initWithWorld:st.w committer:st.c] autorelease];
   [st.s setPerception:knowledge];
   g      = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the tool bin"];
   worker = [g create:"worker" key:"worker" at:BGOnTile( 5, 5, 0)];
   bin    = [g create:"bin" key:"bin" at:BGOnTile( 6, 5, 0)];
   crate  = [g create:"crate" key:"crate" at:BGOnTile( 4, 5, 0)];
   wrench = [g create:"wrench_250" key:"wrench" at:BGHeldBy( worker, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   worker = [g idFor:worker];
   bin    = [g idFor:bin];
   crate  = [g idFor:crate];
   wrench = [g idFor:wrench];
   error  = nil;
   for( i = 0; i < times; i++)
   {
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "put_in", worker, wrench, bin), 0, &error) != nil);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
      BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "take", worker, wrench, BGNoEntity), 0, &error) != nil);
      [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
   }
   BG_CHECK( BGPerform( st.w, st.c, BGActionMake( "put_in", worker, wrench, crate), 0, &error) != nil);
   [st.s runUntil:BGTimeMake( [st.w time].ms + 1000)];
   stage_move( &st, worker, 25, 25);
   [st.s runUntil:BGTimeMake( 42 * BG_MEMORY_STEP)];
   store    = [knowledge storeOf:worker];
   *present = [store referent:referent_of( store, wrench)]->present;
   return( [NSString stringWithFormat:@"%@ (bin R%u, crate R%u)", [store describeReferent:referent_of( store, wrench)],
                                      referent_of( store, bin), referent_of( store, crate)]);
}


static void   test_habitual_belief( void)
{
   NSString   *habit;
   NSString   *none;
   BOOL       present;

   /* three times in the bin: six weeks on, it believes the wrench there,
    * though it last put it in the crate */
   habit = habitual_belief( 3, &present);
   BG_CHECK( present && [habit rangeOfString:@"place: #Inside & { container: ref(2) }"].location != NSNotFound &&
             [habit rangeOfString:@"(bin R2, crate R3)"].location != NSNotFound);
   /* once: no habit, and it doesn't know where it is, last seen in the crate */
   none  = habitual_belief( 1, &present);
   BG_CHECK( ! present && [none rangeOfString:@"container: ref(3)"].location != NSNotFound);
}


static void   test_partial_effects( void)
{
   int64_t      cut[ 12];
   const char   *status;

   /* the checkpoints are boundaries, at 2, 4 and 6 s: the cut shows a
    * quarter at a time, then the whole on completion */
   saw_run( 0, cut, &status);
   BG_CHECK( cut[ 1] == 0 && cut[ 2] == 25 && cut[ 3] == 25 && cut[ 4] == 50 && cut[ 6] == 75 && cut[ 7] == 75);
   BG_CHECK( cut[ 8] == 100 && ! strcmp( status, "\"completed\""));

   /* suspended at 5 s: 62% shows, its progress kept; resumed at 8 s, it
    * goes on from there, through the last checkpoint at 9 s, to the whole
    * at 11 s */
   saw_run( 1, cut, &status);
   BG_CHECK( cut[ 5] == 50 && cut[ 6] == 62 && cut[ 8] == 62);
   BG_CHECK( cut[ 9] == 75 && cut[ 10] == 75 && cut[ 11] == 100 && ! strcmp( status, "\"completed\""));

   /* aborted at 5 s: its progress discarded, the 62% cut stays in the world */
   saw_run( 2, cut, &status);
   BG_CHECK( cut[ 6] == 62 && cut[ 11] == 62 && ! strcmp( status, "\"aborted\""));

   /* the saw taken from its hand at 5 s: what sawing needs no longer holds,
    * a hard interruption, and the cut stays where it got to */
   saw_run( 3, cut, &status);
   BG_CHECK( cut[ 6] == 62 && cut[ 11] == 62 && ! strcmp( status, "\"suspended\""));
}


/* --- the cistern ----------------------------------------------------------- */

static BGCistern   *run_cistern( BGCisternVariant variant)
{
   BGWorld     *w;
   BGCistern   *scenario;

   w        = BGTestWorld( 7);
   scenario = [[[BGCistern alloc] initWithWorld:w committer:BGTestCommitter( w) variant:variant] autorelease];
   [scenario run];
   return( scenario);
}


static void   check_cistern( BGCistern *scenario)
{
   NSArray      *results;
   NSUInteger   i;

   results = [scenario results];
   for( i = 0; i < [results count]; i++)
      if( [[results objectAtIndex:i] hasPrefix:@"FAIL"])
         fprintf( stderr, "    %s\n", [[results objectAtIndex:i] UTF8String]);
   BG_CHECK( [results count] >= 4);
   BG_CHECK( [scenario failureCount] == 0);
}


static void   test_cistern( void)
{
   BGCistern   *base;
   int64_t     a;
   int64_t     b;

   base = run_cistern( BGCisternBase);
   check_cistern( base);
   /* the doc's numbers: about 7 L in each bucket, about 0.7 L on the floor */
   [[base world] getField:"WaterStore.water" of:5 value:&a];
   [[base world] getField:"WaterStore.water" of:6 value:&b];
   BG_CHECK( a > 7000 && a < 7300 && b > 7000 && b < 7300);
   BG_CHECK( [[base world] totalTileWater] > 650 && [[base world] totalTileWater] < 800);
   /* the puddle spread from the tile below the crack, and then settled: the domain sleeps */
   {
      int32_t   x;
      int32_t   y;
      int       wet;

      wet = 0;
      for( y = 0; y < 32; y++)
         for( x = 0; x < 32; x++)
            if( [[base world] waterAtX:x y:y level:0])
               wet++;
      BG_CHECK( wet > 9 && [[base world] waterAtX:5 y:5 level:0] < 100);
      BG_CHECK( [[base fluid] checkedOutWater] == 0 && ! [[base world] isTileCheckedOutX:5 y:5 level:0]);
      BG_CHECK( [[base fluid] horizonAt:[[base world] time]].nextEvent.ms == BGTimeNever.ms);
   }
}


static void   test_cistern_b( void)
{
   check_cistern( run_cistern( BGCisternEarlier));
}


/* A watch: A stops at 3 L, closing the tap; B fills on */
static void   test_cistern_e( void)
{
   check_cistern( run_cistern( BGCisternStopsEarly));
}


/* 2. order independence: the domain's inside order can't change anything */
static void   test_cistern_d( void)
{
   BGCistern   *base;
   BGCistern   *reversed;

   base     = run_cistern( BGCisternBase);
   reversed = run_cistern( BGCisternReversed);
   check_cistern( reversed);
   BG_CHECK( [[reversed world] stateHash] == [[base world] stateHash]);
   BG_CHECK( [[[reversed fluid] log] isEqualToArray:[[base fluid] log]]);
}


/* While the water flows, the domain has it: commitment refuses to set it. */
static void   test_checked_out( void)
{
   BGWorld           *w;
   BGCommitter       *c;
   BGCistern         *scenario;
   BGProposalGroup   *g;

   w        = BGTestWorld( 7);
   c        = BGTestCommitter( w);
   scenario = [[[BGCistern alloc] initWithWorld:w committer:c variant:BGCisternBase] autorelease];
   [scenario runUntil:BGTimeMake( 30000)];
   BG_CHECK( [w isCheckedOut:5] && [[scenario fluid] checkedOutWater] > 0);
   g = [BGProposalGroup groupWithPhase:BGPhaseAction source:@"pour it out"];
   [g set:"WaterStore.water" of:BGWhole( 5) to:0];
   [c submit:g];
   [w setBoundary:[w boundary] + 1];
   [c commitBoundary];
   BG_CHECK( ! [g applied] && [[g rejection] rangeOfString:@"checked out"].location != NSNotFound);
   BG_CHECK( [scenario totalWater] == 15000);
}


/* Saving while the water flows: the domain checks in and keeps its carries,
 * and a world restored from the save, with a fresh domain given them, ends
 * exactly where the run that never saved does. */
static void   test_cistern_save( void)
{
   BGCistern   *reference;
   BGCistern   *scenario;
   BGWorld     *w1;
   BGWorld     *w2;
   BGCommitter *c1;
   BGCommitter *c2;
   NSString    *text;
   NSString    *error;
   NSArray     *deferred;
   uint64_t    position;

   w1        = BGTestWorld( 7);
   reference = [[[BGCistern alloc] initWithWorld:w1 committer:BGTestCommitter( w1) variant:BGCisternBase] autorelease];
   [reference runUntil:BGTimeMake( 30000)];
   [reference finish];
   w1        = BGTestWorld( 7);
   c1        = BGTestCommitter( w1);
   scenario  = [[[BGCistern alloc] initWithWorld:w1 committer:c1 variant:BGCisternBase] autorelease];
   [scenario runUntil:BGTimeMake( 30000)];
   text = BGSave( w1, c1, [NSArray arrayWithObject:[scenario fluid]]);
   BG_CHECK( [text rangeOfString:@"domain fluid carry"].location != NSNotFound);
   BG_CHECK( ! [w1 isCheckedOut:5] && [scenario totalWater] == 15000);

   error = nil;
   w2    = BGRestore( text, [w1 contentBuild], &deferred, &position, &error);
   BG_CHECK( w2 != nil);
   if( ! w2)
   {
      fprintf( stderr, "    %s\n", [error UTF8String]);
      return;
   }
   BG_CHECK( [w2 stateHash] == [w1 stateHash]);
   c2 = BGTestCommitter( w2);
   [c2 setPosition:position];
   [c2 restoreDeferred:deferred];
   [scenario resumeWithWorld:w2
                   committer:c2
                  fluidState:BGSavedDomainState( text, @"fluid")];
   [scenario finish];
   check_cistern( scenario);
   BG_CHECK( [w2 stateHash] == [[reference world] stateHash]);
}


/* --- saves ----------------------------------------------------------------- */

static BGWorld   *restore( NSString *text, BGContent *content, BGCommitter **committer, NSString **error)
{
   BGWorld    *world;
   NSArray    *deferred;
   uint64_t   position;

   world = BGRestore( text, content, &deferred, &position, error);
   if( ! world)
      return( nil);
   *committer = BGTestCommitter( world);
   [*committer setPosition:position];
   [*committer restoreDeferred:deferred];
   return( world);
}


/* Save halfway through the marked nail, restore into a fresh world, and carry
 * on: the restored world takes exactly the steps the original would have. */
static void   test_save_and_resume( void)
{
   BGMarkedNail   *reference;
   BGMarkedNail   *scenario;
   BGWorld        *w1;
   BGWorld        *w2;
   BGCommitter    *c1;
   BGCommitter    *c2;
   NSString       *text;
   NSString       *error;
   NSArray        *full;
   NSArray        *rest;
   NSUInteger     before;

   /* the reference stops where the saving run does: a stop is a boundary */
   w1        = BGTestWorld( 42);
   reference = [[[BGMarkedNail alloc] initWithWorld:w1 committer:BGTestCommitter( w1) variant:BGMarkedNailBase]
                autorelease];
   [reference runUntil:BGTimeMake( 5500)];
   [reference finish];
   w1        = BGTestWorld( 42);
   c1        = BGTestCommitter( w1);
   scenario  = [[[BGMarkedNail alloc] initWithWorld:w1 committer:c1 variant:BGMarkedNailBase] autorelease];
   [scenario runUntil:BGTimeMake( 5500)];          /* after the hammering, before the nail comes out */
   text   = BGSave( w1, c1, nil);
   before = [[c1 trace] count];

   error = nil;
   w2    = restore( text, [w1 contentBuild], &c2, &error);
   BG_CHECK( w2 != nil);
   if( ! w2)
   {
      fprintf( stderr, "    %s\n", [error UTF8String]);
      return;
   }
   BG_CHECK( [w2 stateHash] == [w1 stateHash]);
   BG_CHECK( [BGSave( w2, c2, nil) isEqualToString:text]);
   BG_CHECK( [w2 time].ms == 5500 && [w2 boundary] == [w1 boundary] && [w2 nextID] == [w1 nextID]);

   [scenario resumeWithWorld:w2 committer:c2];
   [scenario finish];
   check_scenario( scenario);
   BG_CHECK( [w2 stateHash] == [[reference world] stateHash]);
   /* the trace after the save is the reference's, line for line */
   full = [[reference committer] trace];
   rest = [c2 trace];
   BG_CHECK( before + [rest count] == [full count]);
   BG_CHECK( [full count] >= before && [rest isEqualToArray:[full subarrayWithRange:NSMakeRange( before, [full count] - before)]]);
}


/* Deferred groups are saved too: they commit at the restored world's next boundary. */
static void   test_save_deferred_groups( void)
{
   BGWorld           *w1;
   BGWorld           *w2;
   BGCommitter       *c1;
   BGCommitter       *c2;
   BGProposalGroup   *g;
   BGEntityID        claim;
   NSString          *error;

   w1    = BGTestWorld( 3);
   c1    = BGTestCommitter( w1);
   claim = commit_create( c1, "ownership", BGLocationMakeNone());
   g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"later"];
   [g set:"Claim.quantity" of:BGWhole( claim) to:12];
   [c1 restoreDeferred:[NSArray arrayWithObject:g]];
   w2 = restore( BGSave( w1, c1, nil), [w1 contentBuild], &c2, &error);
   BG_CHECK( w2 && [[c2 deferredGroups] count] == 1);
   [w2 setBoundary:[w2 boundary] + 1];
   [c2 commitBoundary];
   BG_CHECK( [[c2 deferredGroups] count] == 0);
   {
      int64_t   q;

      BG_CHECK( [w2 getField:"Claim.quantity" of:claim value:&q] && q == 12);
   }
}


static void   test_restore_errors( void)
{
   BGWorld       *w;
   BGCommitter   *c;
   BGContent     *content;
   NSString      *error;
   NSString      *text;

   w       = BGTestWorld( 1);
   c       = BGTestCommitter( w);
   content = [w contentBuild];
   commit_create( c, "bin", BGOnTile( 0, 0, 0));
   text    = BGSave( w, c, nil);

   error = nil;
   BG_CHECK( ! BGRestore( @"not a save\n", content, NULL, NULL, &error));
   BG_CHECK( [error rangeOfString:@"not a bruggadung save"].location != NSNotFound);
   BG_CHECK( ! BGRestore( [text stringByReplacingOccurrencesOfString:@"capacity" withString:@"volume"],
                          content, NULL, NULL, &error));
   BG_CHECK( [error rangeOfString:@"no field Container.volume"].location != NSNotFound);
   BG_CHECK( ! BGRestore( [text stringByReplacingOccurrencesOfString:@"\\\"oak\\\"" withString:@"\\\"teak\\\""],
                          content, NULL, NULL, &error));
   BG_CHECK( [error rangeOfString:@"no type \"teak\""].location != NSNotFound);
   BG_CHECK( ! BGRestore( [text stringByReplacingOccurrencesOfString:@"end\n" withString:@""],
                          content, NULL, NULL, &error));
   BG_CHECK( [error rangeOfString:@"ends early"].location != NSNotFound);
}


const BGTestCase   BGAllTests[] =
{
   { "store",                         test_store },
   { "registry_and_construction",     test_registry_and_construction },
   { "rollback",                      test_rollback },
   { "validation",                    test_validation },
   { "individuation_and_merge_rules", test_individuation_and_merge_rules },
   { "seeded_order",                  test_seeded_order },
   { "reaction_rounds",               test_reaction_rounds },
   { "scheduler_horizons",            test_scheduler_horizons },
   { "marked_nail",                   test_marked_nail },
   { "marked_nail_a",                 test_marked_nail_a },
   { "marked_nail_found",             test_marked_nail_found },
   { "marked_nail_b",                 test_marked_nail_b },
   { "marked_nail_replay",            test_marked_nail_replay },
   { "menu",                          test_menu },
   { "activity_interrupted",          test_activity_interrupted },
   { "activity_fails",                test_activity_fails },
   { "stages_and_suspension",         test_stages_and_suspension },
   { "play",                          test_play },
   { "play_talk",                     test_play_talk },
   { "stale_belief",                  test_stale_belief },
   { "missing_nails",                 test_missing_nails },
   { "asking",                        test_asking },
   { "routine",                       test_routine },
   { "needs",                         test_needs },
   { "habits",                        test_habits },
   { "promises",                      test_promises },
   { "two_hands",                     test_two_hands },
   { "coat_at_dusk",                  test_coat_at_dusk },
   { "unknown_nut",                   test_unknown_nut },
   { "seized_valve",                  test_seized_valve },
   { "access_resume",                 test_access_resume },
   { "providers_pending",             test_providers_pending },
   { "memory_rates",                  test_memory_rates },
   { "scheduled_forgetting",          test_scheduled_forgetting },
   { "trodden",                       test_trodden },
   { "trace_floor",                   test_trace_floor },
   { "traced_units",                  test_traced_units },
   { "attention_budget",              test_attention_budget },
   { "routine_autopilot",             test_routine_autopilot },
   { "talking_takes_time",            test_talking_takes_time },
   { "explore_autopilot",             test_explore_autopilot },
   { "recipe_autopilot",              test_recipe_autopilot },
   { "resume_recheck",                test_resume_recheck },
   { "interrupted_repair",            test_interrupted_repair },
   { "unattended_stove",              test_unattended_stove },
   { "local_wake",                    test_local_wake },
   { "cold_lodger",                   test_cold_lodger },
   { "stuffy_lodger",                 test_stuffy_lodger },
   { "partial_effects",               test_partial_effects },
   { "hard_fail",                     test_hard_fail },
   { "tired_worker",                  test_tired_worker },
   { "pain",                          test_pain },
   { "habitual_belief",               test_habitual_belief },
   { "forged_permit",                 test_forged_permit },
   { "issue_permit",                  test_issue_permit },
   { "latent_pump",                   test_latent_pump },
   { "pump_heat",                     test_pump_heat },
   { "component_pump",                test_component_pump },
   { "improvise",                     test_improvise },
   { "door_in_the_dark",              test_door_in_the_dark },
   { "wrench_replaced",               test_wrench_replaced },
   { "rumour",                        test_rumour },
   { "memory_decay",                  test_memory_decay },
   { "salience",                      test_salience },
   { "traces",                        test_traces },
   { "appearance",                    test_appearance },
   { "interpretation",                test_interpretation },
   { "notebook",                      test_notebook },
   { "play_notebook",                 test_play_notebook },
   { "false_alarm",                   test_false_alarm },
   { "play_autopilot",                test_play_autopilot },
   { "tempting_purse",                test_tempting_purse },
   { "cistern",                       test_cistern },
   { "cistern_b",                     test_cistern_b },
   { "cistern_d",                     test_cistern_d },
   { "cistern_e",                     test_cistern_e },
   { "checked_out",                   test_checked_out },
   { "cistern_save",                  test_cistern_save },
   { "save_and_resume",               test_save_and_resume },
   { "save_deferred_groups",          test_save_deferred_groups },
   { "restore_errors",                test_restore_errors },
};

const size_t   BGAllTestsCount = sizeof( BGAllTests) / sizeof( BGAllTests[ 0]);
