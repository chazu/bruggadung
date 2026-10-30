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
   BG_CHECK( [w kindCount] == 11);
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
                                   @"take item 3: entailed; take_some item 2: entailed; test_scratch item 1: entailed; "
                                   @"test_scratch item 3: entailed; touch_up item 3: entailed; "
                                   @"walk_east: entailed; walk_north: entailed; walk_south: entailed; walk_west: entailed; "
                                   @"wash_floor: entailed; watch_closely: entailed"]);
   if( [text rangeOfString:@"wash_floor: entailed; watch_closely: entailed"].location == NSNotFound)
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
                                        @"walk n", @"walk n", @"walk n", @"hash", nil];
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
   BGApprenticeSurly             /* it saw, and won't help */
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
static BGNailsRun   missing_nails( BOOL spares, BOOL omniscient, BGApprentice apprentice, int64_t saveAt,
                                   int64_t shiftUntil)
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
   if( shiftUntil > BG_EIGHT)
   {
      /* breakfast at 7:30, before the shift */
      [g set:"Agent.fed" of:BGWhole( 4) to:100];
      [g set:"Agent.fedAt" of:BGWhole( 4) to:BG_EIGHT - 1800000];
   }
   chest  = BGNoEntity;
   helper = BGNoEntity;
   if( apprentice)
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
   (void) crate;
   if( apprentice && apprentice != BGApprenticeSilent)
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
   if( apprentice)
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


static void   test_missing_nails( void)
{
   BGNailsRun   base;
   BGNailsRun   again;
   BGNailsRun   spares;
   BGNailsRun   seer;
   BGNailsRun   resumed;
   BGEntityID   crate;
   NSArray      *full;
   NSArray      *rest;

   crate = 7;           /* after the workshop's six */

   /* base: the bin first (believed), then the crate; nowhere left: dropped, with why */
   base = missing_nails( NO, NO, BGNoApprentice, 0, 0);

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
   again = missing_nails( NO, NO, BGNoApprentice, 0, 0);
   BG_CHECK( [again.world stateHash] == [base.world stateHash]);
   BG_CHECK( [[again.agency logOf:4] isEqualToArray:[base.agency logOf:4]]);
   BG_CHECK( [again.text isEqualToString:base.text]);

   /* A: spare nails in the crate: found, taken, and the lock wedged; wedging was the intention throughout */
   spares = missing_nails( YES, NO, BGNoApprentice, 0, 0);
   BG_CHECK( happened( spares.world, "attempted", 4, 1));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] back to it: have nails is done"));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] drive a nail in: drive"));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] done"));
   /* the spare nails are a thing of their own, not the bin's missing ones found again: they look different */
   BG_CHECK( tracks( spares, 4, 2) && tracks( spares, 4, 8) && tracks( spares, 4, 2) != tracks( spares, 4, 8));
   BG_CHECK( wedged( spares.world));

   /* B: the omniscient stub knows better, and the behaviour shows it: straight to the crate */
   seer = missing_nails( YES, YES, BGNoApprentice, 0, 0);
   BG_CHECK( ! happened( seer.world, "attempted", 4, 1));
   BG_CHECK( ! logged( seer.agency, @"search for nails"));
   BG_CHECK( wedged( seer.world));
   BG_CHECK( [[seer.agency logOf:4] count] < [[spares.agency logOf:4] count]);

   /* saved mid-search, mid-stride (a boundary the run has anyway: the walk
    * toward the crate just committed), the commitment and the subgoal stacked,
    * fetching passed over: restored, the agent carries on exactly as it would
    * have */
   resumed = missing_nails( YES, NO, BGNoApprentice, 20005, 0);
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
   saw = missing_nails( NO, NO, BGApprenticeSaw, 0, 0);
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

   again = missing_nails( NO, NO, BGApprenticeSaw, 0, 0);
   BG_CHECK( [again.world stateHash] == [saw.world stateHash]);
   BG_CHECK( [again.text isEqualToString:saw.text]);
   BG_CHECK( [[again.agency logOf:4] isEqualToArray:[saw.agency logOf:4]]);

   /* it didn't see: it says so, and the goal is dropped */
   missed = missing_nails( NO, NO, BGApprenticeMissed, 0, 0);
   BG_CHECK( logged( missed.agency, @"answered: #DontKnow"));
   BG_CHECK( logged( missed.agency, @"[wedge the lock] nothing I know of will do: impossible for now"));
   BG_CHECK( ! wedged( missed.world));
   BG_CHECK( ! believed( missed, missed.apprentice, 2));

   /* nobody answers: the worker waits a while, then gives up on it */
   silent = missing_nails( NO, NO, BGApprenticeSilent, 0, 0);
   BG_CHECK( logged( silent.agency, @"did not answer"));
   BG_CHECK( ! happened( silent.world, "said", silent.apprentice, 4) && ! wedged( silent.world));

   /* saved while it waits, the wait goes on in the restored world, and ends as it would have */
   resumed = missing_nails( NO, NO, BGApprenticeSilent, 30006, 0);
   BG_CHECK( [resumed.world stateHash] == [silent.world stateHash]);
   BG_CHECK( [resumed.text isEqualToString:silent.text]);
   full = [silent.agency logOf:4];
   rest = [resumed.agency logOf:4];
   BG_CHECK( [rest count] > 0 && [rest count] < [full count] &&
             [rest isEqualToArray:[full subarrayWithRange:NSMakeRange( [full count] - [rest count], [rest count])]]);
   BG_CHECK( [rest count] && [[rest objectAtIndex:0] rangeOfString:@"t=35005ms"].location != NSNotFound &&
             [[rest objectAtIndex:0] rangeOfString:@"did not answer"].location != NSNotFound);

   /* asked, a surly apprentice weighs answering at less than nothing, and says it won't: the goal is dropped */
   surly = missing_nails( NO, NO, BGApprenticeSurly, 0, 0);
   BG_CHECK( logged_by( surly.agency, surly.apprentice, @"asked by R"));
   BG_CHECK( logged_by( surly.agency, surly.apprentice, @"worth -5, refusing"));
   BG_CHECK( logged_by( surly.agency, surly.apprentice, @"refusing: say R"));
   BG_CHECK( logged( surly.agency, @"answered: #WontSay"));
   BG_CHECK( logged( surly.agency, @"[wedge the lock] nothing I know of will do: impossible for now"));
   BG_CHECK( ! wedged( surly.world));
   /* a helpful one weighed it at the trust in the asker */
   BG_CHECK( logged_by( saw.agency, saw.apprentice, @"worth +20, answering"));

   /* the omniscient stub needs no one: straight to the chest */
   seer = missing_nails( NO, YES, BGApprenticeSaw, 0, 0);
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
   shift = missing_nails( YES, NO, BGNoApprentice, 0, BG_EIGHT + 8 * 3600000LL);
   log   = [shift.agency logOf:4];
   BG_CHECK( [log count] && [[log objectAtIndex:0] rangeOfString:@"t=28800000ms [-] weighing wedge the lock: +20 "
                                                                 @"(employment, duty +20, urgency +0) against nothing: "
                                                                 @"switching"].location != NSNotFound);
   BG_CHECK( logged_by( shift.agency, 4, @"t=28800000ms [wedge the lock] drive a nail in: have nails first"));
   BG_CHECK( wedged( shift.world));
   /* done, it is settled for the shift: not taken up again */
   BG_CHECK( log_count( shift.agency, 4, @"switching") == 1);

   /* without spares, impossible, and settled too: not taken up again and again */
   fruitless = missing_nails( NO, NO, BGNoApprentice, 0, BG_EIGHT + 8 * 3600000LL);
   BG_CHECK( logged_by( fruitless.agency, 4, @"[wedge the lock] nothing I know of will do: impossible for now"));
   BG_CHECK( log_count( fruitless.agency, 4, @"switching") == 1 && ! wedged( fruitless.world));

   /* a shift of five seconds closes mid-search: the commitment is over, and
    * what it needed with it */
   closing = missing_nails( YES, NO, BGNoApprentice, 0, BG_EIGHT + 5000);
   BG_CHECK( logged_by( closing.agency, 4, @"t=28805000ms [have nails] wedge the lock is over: its window has closed"));
   BG_CHECK( ! wedged( closing.world) && [closing.agency mindOf:4]->nintentions == 0);

   /* urgency rises toward the deadline: a window from 0 to 40 s, taken up
    * at 12 s, three tenths of the way: 6 of 20 */
   hurried = missing_nails( YES, NO, BGNoApprentice, 0, 40000);
   BG_CHECK( logged_by( hurried.agency, 4, @"t=12003ms [-] weighing wedge the lock: +26 (employment, duty +20, urgency +6)"));

   /* saved mid-shift, restored, the same end */
   resumed = missing_nails( YES, NO, BGNoApprentice, BG_EIGHT + 6001, BG_EIGHT + 8 * 3600000LL);
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
   [st->s runUntil:BGTimeMake( [st->w time].ms + 1000)];
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
}


/* --- the false alarm -------------------------------------------------------- */

typedef enum
{
   BGAlarmNoRumour = 0,          /* A */
   BGAlarmRumour,                /* B */
   BGAlarmDeflated,              /* C: the rumour has one named source */
   BGAlarmRepeated,              /* D: B, with noise after noise */
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
   NSArray       *notices;
   NSString      *text;
} BGAlarmRun;


/* AGENCY.md Scenario 2, "the false alarm", in the workshop: the watchman
 * walks past the storeroom, then sits down by the gate to eat supper, eight
 * tiles off, out of sight and in earshot. The carter and the porter tell it
 * someone has been getting into the storeroom (B, D: neither names a source;
 * C: both heard it from the neighbour). Then a cat by the storeroom knocks
 * something over (D: again and again). */
static BGAlarmRun   false_alarm( BGAlarm variant, int64_t saveAt)
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
   h[ 4] = [g create:"carter" key:"carter" at:BGOnTile( 3, 5, 0)];
   h[ 5] = [g create:"porter" key:"porter" at:BGOnTile( 5, 5, 0)];
   [st.c submit:g];
   [st.s runUntil:BGTimeMake( 1)];
   run.world     = st.w;
   run.knowledge = knowledge;
   run.agency    = agency;
   run.storeroom = [g idFor:h[ 0]];
   run.watchman  = [g idFor:h[ 2]];
   run.carter    = [g idFor:h[ 4]];
   run.porter    = [g idFor:h[ 5]];
   if( variant < BGAlarmAutopilot)
      [agency control:run.watchman];

   /* past the storeroom (it sees it, under the cat's eye), to the gate */
   stage_move( &st, run.watchman, 4, 4);

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
   BGKnowledgeStore   *store;

   a = false_alarm( BGAlarmNoRumour, 0);
   b = false_alarm( BGAlarmRumour, 0);
   c = false_alarm( BGAlarmDeflated, 0);

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
   d = false_alarm( BGAlarmRepeated, 0);
   BG_CHECK( log_count( d.agency, d.watchman, @"switching") == 1);
   BG_CHECK( log_count( d.agency, d.watchman, @"staying") == 0);
   BG_CHECK( log_count( d.agency, d.watchman, @"suspending eat") == 1);
   BG_CHECK( happened( d.world, "looked", d.watchman, d.storeroom));

   /* 6: determinism */
   again = false_alarm( BGAlarmRumour, 0);
   BG_CHECK( [again.world stateHash] == [b.world stateHash]);
   BG_CHECK( [again.text isEqualToString:b.text]);
   BG_CHECK( [[again.agency logOf:again.watchman] isEqualToArray:[b.agency logOf:b.watchman]]);

   /* saved mid-investigation, supper suspended beneath it, restored: the same
    * end (a boundary the run has: a step toward the storeroom) */
   resumed = false_alarm( BGAlarmRumour, 10003);
   BG_CHECK( [resumed.world stateHash] == [b.world stateHash]);
   BG_CHECK( [resumed.text isEqualToString:b.text]);
   BG_CHECK( logged_by( resumed.agency, resumed.watchman, @"[eat supper] eat: resuming eat"));

   /* 5: E, autopilot: in B's conditions, the noise is worth more than the
    * player's 25: control returns at that weighing, supper still under way,
    * nothing looked into; autopilot used nothing the watchman didn't know */
   e = false_alarm( BGAlarmAutopilot, 0);
   BG_CHECK( [e.notices count] == 1 &&
             [[e.notices objectAtIndex:0] isEqualToString:@"Control returns to you: investigate the disturbance (R2) is "
                                                         @"worth +35, more than your +25."]);
   BG_CHECK( ! [e.agency controls:e.watchman]);
   BG_CHECK( ! logged_by( e.agency, e.watchman, @"switching") && ! logged_by( e.agency, e.watchman, @"suspending"));
   BG_CHECK( ! happened( e.world, "looked", e.watchman, e.storeroom));
   /* in A's, it eats on, and hands back when supper is done */
   quiet = false_alarm( BGAlarmAutopilotQuiet, 0);
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
   BGPurseNoWitness              /* C: Mira isn't there */
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
   if( variant == BGPurseHonest)
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
   run.text = BGSave( st.w, st.c, [NSArray arrayWithObjects:knowledge, agency, nil]);
   return( run);
}


static void   test_tempting_purse( void)
{
   BGPurseRun         base;
   BGPurseRun         noticed;
   BGPurseRun         honest;
   BGPurseRun         alone;
   BGPurseRun         again;
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
