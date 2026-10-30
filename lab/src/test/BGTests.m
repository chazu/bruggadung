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
   BG_CHECK( [w kindCount] == 9);
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
                                   @"take item 3: entailed; take_some item 2: entailed; walk_east: entailed; "
                                   @"walk_north: entailed; walk_south: entailed; walk_west: entailed"]);
   if( [text rangeOfString:@"take_some item 2: entailed; walk_east"].location == NSNotFound)
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
   BG_CHECK( [out rangeOfString:@"moved 11 to partOf(3, wedge, 0) at boundary 9, in \"activity 10: drive completes\"\n"
                                @"because:\n  created 10 activity at boundary 8, in \"4: drive item 7 destination 3\""].location
             != NSNotFound);
   /* walks are activities of a second each: two of them, so the drive is activity 10, and done at 6 s */
   BG_CHECK( [out rangeOfString:@"activity 9: walk_east completes"].location != NSNotFound);
   /* the map's edge: the step off it fails when it would arrive */
   BG_CHECK( [out rangeOfString:@"is off the map"].location != NSNotFound);
   if( [out rangeOfString:@"is off the map"].location == NSNotFound)
      fprintf( stderr, "%s\n", [out UTF8String]);
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
   BGApprenticeSilent
} BGApprentice;


static BGWorld   *restore( NSString *text, BGContent *content, BGCommitter **committer, NSString **error);


/* AGENCY.md Scenario 1, as "the missing nails". The worker looks into the bin
 * and walks off past the crate; the smith takes the nails away (with an
 * apprentice, into the chest, at the bottom of the map, and the apprentice
 * then comes over by the crate); then agency takes the worker over,
 * committed to wedging the lock. `saveAt`, if not 0, is when to save,
 * restore into a fresh world, with fresh knowledge and agency from the
 * save, and carry on there. */
static BGNailsRun   missing_nails( BOOL spares, BOOL omniscient, BGApprentice apprentice, int64_t saveAt)
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
   chest  = BGNoEntity;
   helper = BGNoEntity;
   if( apprentice)
   {
      chest  = [g create:"chest" key:"chest" at:BGOnTile( 2, 12, 0)];
      helper = [g create:"apprentice" key:"apprentice"
                      at:apprentice == BGApprenticeMissed ? BGOnTile( 12, 13, 0) : BGOnTile( 3, 13, 0)];
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

   /* the shift: agency has the worker now */
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
   [s runUntil:BGTimeMake( 120000)];
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
   base = missing_nails( NO, NO, BGNoApprentice, 0);

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
   again = missing_nails( NO, NO, BGNoApprentice, 0);
   BG_CHECK( [again.world stateHash] == [base.world stateHash]);
   BG_CHECK( [[again.agency logOf:4] isEqualToArray:[base.agency logOf:4]]);
   BG_CHECK( [again.text isEqualToString:base.text]);

   /* A: spare nails in the crate: found, taken, and the lock wedged; wedging was the intention throughout */
   spares = missing_nails( YES, NO, BGNoApprentice, 0);
   BG_CHECK( happened( spares.world, "attempted", 4, 1));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] back to it: have nails is done"));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] drive a nail in: drive"));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] done"));
   /* the spare nails are a thing of their own, not the bin's missing ones found again: they look different */
   BG_CHECK( tracks( spares, 4, 2) && tracks( spares, 4, 8) && tracks( spares, 4, 2) != tracks( spares, 4, 8));
   BG_CHECK( wedged( spares.world));

   /* B: the omniscient stub knows better, and the behaviour shows it: straight to the crate */
   seer = missing_nails( YES, YES, BGNoApprentice, 0);
   BG_CHECK( ! happened( seer.world, "attempted", 4, 1));
   BG_CHECK( ! logged( seer.agency, @"search for nails"));
   BG_CHECK( wedged( seer.world));
   BG_CHECK( [[seer.agency logOf:4] count] < [[spares.agency logOf:4] count]);

   /* saved mid-search, mid-stride (a boundary the run has anyway: the walk
    * toward the crate just committed), the commitment and the subgoal stacked,
    * fetching passed over: restored, the agent carries on exactly as it would
    * have */
   resumed = missing_nails( YES, NO, BGNoApprentice, 20005);
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
   const BGReferent   *nails;
   const BGReferent   *chest;
   BGKnowledgeStore   *store;
   NSArray            *full;
   NSArray            *rest;
   BGEntityID         c;

   /* it saw: told where, the worker goes to a chest it has never seen, and wedges the lock */
   saw = missing_nails( NO, NO, BGApprenticeSaw, 0);
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

   again = missing_nails( NO, NO, BGApprenticeSaw, 0);
   BG_CHECK( [again.world stateHash] == [saw.world stateHash]);
   BG_CHECK( [again.text isEqualToString:saw.text]);
   BG_CHECK( [[again.agency logOf:4] isEqualToArray:[saw.agency logOf:4]]);

   /* it didn't see: it says so, and the goal is dropped */
   missed = missing_nails( NO, NO, BGApprenticeMissed, 0);
   BG_CHECK( logged( missed.agency, @"answered: #DontKnow"));
   BG_CHECK( logged( missed.agency, @"[wedge the lock] nothing I know of will do: impossible for now"));
   BG_CHECK( ! wedged( missed.world));
   BG_CHECK( ! believed( missed, missed.apprentice, 2));

   /* nobody answers: the worker waits a while, then gives up on it */
   silent = missing_nails( NO, NO, BGApprenticeSilent, 0);
   BG_CHECK( logged( silent.agency, @"did not answer"));
   BG_CHECK( ! happened( silent.world, "said", silent.apprentice, 4) && ! wedged( silent.world));

   /* saved while it waits, the wait goes on in the restored world, and ends as it would have */
   resumed = missing_nails( NO, NO, BGApprenticeSilent, 30006);
   BG_CHECK( [resumed.world stateHash] == [silent.world stateHash]);
   BG_CHECK( [resumed.text isEqualToString:silent.text]);
   full = [silent.agency logOf:4];
   rest = [resumed.agency logOf:4];
   BG_CHECK( [rest count] > 0 && [rest count] < [full count] &&
             [rest isEqualToArray:[full subarrayWithRange:NSMakeRange( [full count] - [rest count], [rest count])]]);
   BG_CHECK( [rest count] && [[rest objectAtIndex:0] rangeOfString:@"t=35005ms"].location != NSNotFound &&
             [[rest objectAtIndex:0] rangeOfString:@"did not answer"].location != NSNotFound);

   /* the omniscient stub needs no one: straight to the chest */
   seer = missing_nails( NO, YES, BGApprenticeSaw, 0);
   BG_CHECK( ! happened( seer.world, "said", 4, seer.apprentice));
   BG_CHECK( ! happened( seer.world, "attempted", 4, 1) && wedged( seer.world));
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
   /* being asked is noticed even while driving, and answered */
   BG_CHECK( logged( run.agency, @"answering: say R"));
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
   { "stale_belief",                  test_stale_belief },
   { "missing_nails",                 test_missing_nails },
   { "asking",                        test_asking },
   { "rumour",                        test_rumour },
   { "memory_decay",                  test_memory_decay },
   { "salience",                      test_salience },
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
