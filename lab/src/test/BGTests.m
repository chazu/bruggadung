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
   NSString      *text;          /* a save at the end, agency and knowledge included */
} BGNailsRun;


/* AGENCY.md Scenario 1, as "the missing nails". The worker looks into the bin
 * and walks off past the crate; the smith takes the nails away; then agency
 * takes the worker over, committed to wedging the lock. */
static BGWorld   *restore( NSString *text, BGContent *content, BGCommitter **committer, NSString **error);


/* `saveAt`, if not 0, is when to save, restore into a fresh world, with fresh
 * knowledge and agency from the save, and carry on there. */
static BGNailsRun   missing_nails( BOOL spares, BOOL omniscient, int64_t saveAt)
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
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   crate = [g idFor:ch];
   (void) crate;

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
   run.world  = w;
   run.agency = agency;
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
   base = missing_nails( NO, NO, 0);

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
   again = missing_nails( NO, NO, 0);
   BG_CHECK( [again.world stateHash] == [base.world stateHash]);
   BG_CHECK( [[again.agency logOf:4] isEqualToArray:[base.agency logOf:4]]);
   BG_CHECK( [again.text isEqualToString:base.text]);

   /* A: spare nails in the crate: found, taken, and the lock wedged; wedging was the intention throughout */
   spares = missing_nails( YES, NO, 0);
   BG_CHECK( happened( spares.world, "attempted", 4, 1));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] back to it: have nails is done"));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] drive a nail in: drive"));
   BG_CHECK( logged( spares.agency, @"[wedge the lock] done"));
   BG_CHECK( wedged( spares.world));

   /* B: the omniscient stub knows better, and the behaviour shows it: straight to the crate */
   seer = missing_nails( YES, YES, 0);
   BG_CHECK( ! happened( seer.world, "attempted", 4, 1));
   BG_CHECK( ! logged( seer.agency, @"search for nails"));
   BG_CHECK( wedged( seer.world));
   BG_CHECK( [[seer.agency logOf:4] count] < [[spares.agency logOf:4] count]);

   /* saved mid-search, mid-stride (a boundary the run has anyway: the walk
    * toward the crate just committed), the commitment and the subgoal stacked,
    * fetching passed over: restored, the agent carries on exactly as it would
    * have */
   resumed = missing_nails( YES, NO, 20005);
   BG_CHECK( [resumed.world stateHash] == [spares.world stateHash]);
   BG_CHECK( [resumed.text isEqualToString:spares.text]);
   full = [spares.agency logOf:4];
   rest = [resumed.agency logOf:4];
   BG_CHECK( [rest count] > 0 && [rest count] < [full count]);
   BG_CHECK( [rest count] <= [full count] &&
             [rest isEqualToArray:[full subarrayWithRange:NSMakeRange( [full count] - [rest count], [rest count])]]);
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
