/*
 * BGBench: a crowd, measured.
 */
#import "BGBench.h"

#import "BGTest.h"
#import "BGScheduler.h"
#import "BGActivities.h"
#import "BGKnowledge.h"
#import "BGAgency.h"

#include <stdio.h>
#include <string.h>
#include <time.h>


static double   ms_of( uint64_t ns)
{
   return( (double) ns / 1e6);
}


int   BGBenchCrowd( int agents, int64_t seconds)
{
   return( BGBenchCrowdSpread( agents, seconds, NO, NO));
}


int   BGBenchCrowdSpread( int agents, int64_t seconds, BOOL spread, BOOL anchored)
{
   int32_t            side;
   BGWorld            *w;
   BGCommitter        *c;
   BGScheduler        *s;
   BGActivities       *activities;
   BGKnowledge        *knowledge;
   BGAgency           *agency;
   BGProposalGroup    *g;
   BGSchedulerStats   st;
   BGSchedulerStats   st0;
   uint64_t           p0;
   uint64_t           d0;
   NSUInteger         e0;
   BGEntityID         *ids;
   struct timespec    t0;
   struct timespec    t1;
   double             wall;
   int                i;

   w = BGTestWorld( 211);
   if( ! [w setTerrainMap:spread ? "plain_map" : "yard_map" error:NULL])
   {
      fprintf( stderr, "bench: no map\n");
      return( 1);
   }
   /* spread: as many to a stretch of plain however many there are, ten
    * tiles apart on a square; else all on the yard */
   for( side = 1; side * side < agents; side++)
      ;
   c          = BGTestCommitter( w);
   [c setTracing:NO];                  /* a large world's: no trace kept */
   activities = [BGActivities activitiesWithWorld:w committer:c];
   knowledge  = [[[BGKnowledge alloc] initWithWorld:w] autorelease];
   agency     = [[[BGAgency alloc] initWithWorld:w committer:c knowledge:knowledge] autorelease];
   s          = [[[BGScheduler alloc] initWithWorld:w committer:c] autorelease];
   [agency setActivities:activities];
   [s setActivities:activities];
   [s setPerception:knowledge];
   [s setDecision:agency];
   ids = malloc( (size_t) (agents + 1) * sizeof( BGEntityID));
   g   = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"bench: a crowd on the yard"];
   for( i = 0; i < agents; i++)
      ids[ i] = [g create:"worker"
                      key:[[NSString stringWithFormat:@"worker %d", i] UTF8String]
                       at:spread ? BGOnTile( 20 + (i % side) * 10, 20 + (i / side) * 10, 0)
                                 : BGOnTile( (i * 37) % 96, (i * 23) % 64, 0)];
   [c submit:g];
   [s runUntil:BGTimeMake( 1)];
   for( i = 0; i < agents; i++)
      ids[ i] = [g idFor:ids[ i]];
   /* they start through the first second, not all at once, as a crowd
    * would: their walks end at their own times */
   for( i = 0; i < agents; i++)
   {
      [s runUntil:BGTimeMake( 2 + (int64_t) i * 997 / agents)];
      if( i % 2)
         [agency control:ids[ i]];
      else
         [agency autopilotExplore:ids[ i] threshold:50];
   }
   /* the first anchors the reality bubble: the rest further off, less exactly */
   if( anchored)
   {
      [w setAnchor:ids[ 0] kind:"player"];
      [w settleAnchors];
   }
   st0 = [s stats];
   p0  = [knowledge perceptions];
   d0  = [agency decisions];
   e0  = [w eventCount];

   clock_gettime( CLOCK_MONOTONIC, &t0);
   [s runUntil:BGTimeMake( 1 + seconds * 1000)];
   clock_gettime( CLOCK_MONOTONIC, &t1);
   wall = (double) (t1.tv_sec - t0.tv_sec) * 1e3 + (double) (t1.tv_nsec - t0.tv_nsec) / 1e6;

   st = [s stats];
   st.boundaries   -= st0.boundaries;
   st.horizonNs    -= st0.horizonNs;
   st.domainsNs    -= st0.domainsNs;
   st.commitNs     -= st0.commitNs;
   st.perceptionNs -= st0.perceptionNs;
   st.decisionNs   -= st0.decisionNs;
   printf( "crowd%s%s: %d agents (%d exploring), %lld s of world time\n", spread ? " spread" : "",
           anchored ? ", anchored" : "", agents, (agents + 1) / 2, (long long) seconds);
   if( anchored)
   {
      int   levels[ 4];

      memset( levels, 0, sizeof( levels));
      for( i = 0; i < agents; i++)
         levels[ [w detailOf:ids[ i]]]++;
      printf( "  levels        %d full, %d reduced, %d abstract, %d frozen\n", levels[ 3], levels[ 2], levels[ 1],
              levels[ 0]);
   }
   printf( "  wall          %10.1f ms  (%.1f ms a world second)\n", wall, wall / (double) seconds);
   printf( "  boundaries    %10llu     (%.1f a world second)\n", (unsigned long long) st.boundaries,
           (double) st.boundaries / (double) seconds);
   printf( "  perceptions   %10llu     (%.1f a boundary)\n", (unsigned long long) ([knowledge perceptions] - p0),
           st.boundaries ? (double) ([knowledge perceptions] - p0) / (double) st.boundaries : 0.0);
   printf( "  decisions     %10llu     (%.1f a boundary)\n", (unsigned long long) ([agency decisions] - d0),
           st.boundaries ? (double) ([agency decisions] - d0) / (double) st.boundaries : 0.0);
   printf( "  horizon       %10.1f ms\n", ms_of( st.horizonNs));
   printf( "  domains       %10.1f ms\n", ms_of( st.domainsNs));
   printf( "  commit        %10.1f ms\n", ms_of( st.commitNs));
   printf( "  perception    %10.1f ms\n", ms_of( st.perceptionNs));
   printf( "  decision      %10.1f ms\n", ms_of( st.decisionNs));
   printf( "  events        %10lu\n", (unsigned long) ([w eventCount] - e0));
   free( ids);
   return( 0);
}
