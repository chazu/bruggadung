#import "BGTest.h"

#import "BGScheduler.h"
#import "BGMarkedNail.h"

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
   BG_CHECK( [w kindCount] == 6);
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
   /* events bound the first steps; the safe step bounds the rest; the stop bounds the run */
   BG_CHECK( n == 3);
   BG_CHECK( d->nsteps == 3);
   BG_CHECK( d->steps[ 0][ 1] == 300 && d->steps[ 1][ 1] == 700 && d->steps[ 2][ 1] == 1700);
   BG_CHECK( [w time].ms == 2000 && [w boundary] == 3);
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
};

const size_t   BGAllTestsCount = sizeof( BGAllTests) / sizeof( BGAllTests[ 0]);
