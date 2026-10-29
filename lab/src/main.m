/*
 * lab — the bruggadung simulation laboratory.
 *
 *   lab test [name]          run the tests (those whose names contain `name`)
 *   lab run <scenario>       run a scenario and print its trace and checks:
 *                            marked-nail, marked-nail-a, marked-nail-b
 *   lab save <scenario>      run a scenario and print the save of its end state
 *   lab menu <scenario> <ms> run a scenario to a time and print the worker's menu
 *   lab -C <dir> ...         read content from <dir> (default: content)
 */
#import "BGTest.h"

#import "BGMarkedNail.h"
#import "BGSave.h"
#import "BGActions.h"
#import "BGView.h"

#include <stdio.h>
#include <stdlib.h>


extern const BGTestCase   BGAllTests[];
extern const size_t       BGAllTestsCount;


static int   usage( void)
{
   fprintf( stderr, "usage: lab [-C contentdir] test [name]\n"
                    "       lab [-C contentdir] run|save marked-nail|marked-nail-a|marked-nail-b\n"
                    "       lab [-C contentdir] menu marked-nail|marked-nail-a|marked-nail-b <ms>\n");
   return( 2);
}


static int   run_scenario( const char *name, BOOL save, int64_t menuAt)
{
   BGMarkedNailVariant   variant;
   BGMarkedNail          *scenario;
   BGWorld               *world;
   NSArray               *lines;
   BGStore               *entities;
   NSUInteger            i;

   if( ! strcmp( name, "marked-nail"))
      variant = BGMarkedNailBase;
   else if( ! strcmp( name, "marked-nail-a"))
      variant = BGMarkedNailUnmarked;
   else if( ! strcmp( name, "marked-nail-b"))
      variant = BGMarkedNailMixedGoods;
   else
      return( usage());

   world = BGTestWorld( 42);
   if( ! world)
      return( 1);
   BGReleaseSharedContentAfterUse();
   scenario = [[[BGMarkedNail alloc] initWithWorld:world
                                         committer:BGTestCommitter( world)
                                           variant:variant] autorelease];
   if( menuAt >= 0)
   {
      BGMenu       *menu;
      BGEntityID   reach[ 64];
      BGView       *view;
      NSUInteger   n;

      [scenario runUntil:BGTimeMake( menuAt)];
      view = [BGView viewOf:4 inWorld:world];
      n    = [view reachable:reach max:64];
      printf( "== what the worker (4) can see at t=%lldms\n", (long long) menuAt);
      for( i = 0; i < n && i < 64; i++)
         printf( "%s\n", [[view describeEntity:reach[ i]] UTF8String]);
      menu = [BGMenu menuFor:4 world:world];
      printf( "\n== the worker's menu\n");
      for( i = 0; i < [menu count]; i++)
         printf( "%s\n", [[menu describeAt:i] UTF8String]);
      return( 0);
   }
   [scenario run];
   if( save)
   {
      printf( "%s", [BGSave( world, [scenario committer]) UTF8String]);
      return( [scenario failureCount] ? 1 : 0);
   }

   printf( "== trace\n");
   lines = [[scenario committer] trace];
   for( i = 0; i < [lines count]; i++)
      printf( "%s\n", [[lines objectAtIndex:i] UTF8String]);

   printf( "\n== entities at t=%lldms, boundary %llu\n", (long long) [world time].ms,
           (unsigned long long) [world boundary]);
   entities = [world storeForKind:[world kindNamed:"Body"]];
   for( i = 1; i < [world nextID]; i++)
      printf( "%s\n", [[world describeEntity:(BGEntityID) i] UTF8String]);
   (void) entities;

   printf( "\n== checks\n");
   lines = [scenario results];
   for( i = 0; i < [lines count]; i++)
      printf( "%s\n", [[lines objectAtIndex:i] UTF8String]);
   printf( "state hash %016llx\n", (unsigned long long) [world stateHash]);
   return( [scenario failureCount] ? 1 : 0);
}


int   main( int argc, char *argv[])
{
   NSAutoreleasePool   *pool;
   int                 i;
   int                 status;

#if defined( DEBUG) && defined( __MULLE_OBJC__)
   mulle_objc_global_check_universe( __MULLE_OBJC_UNIVERSENAME__);
#endif
   i = 1;
   if( i + 1 < argc && ! strcmp( argv[ i], "-C"))
   {
      BGContentDir = argv[ i + 1];
      i += 2;
   }
   if( i >= argc)
      return( usage());

   pool = [NSAutoreleasePool new];
   if( ! strcmp( argv[ i], "test"))
      status = BGRunTests( BGAllTests, BGAllTestsCount, i + 1 < argc ? argv[ i + 1] : NULL) ? 1 : 0;
   else if( ! strcmp( argv[ i], "run") && i + 1 < argc)
      status = run_scenario( argv[ i + 1], NO, -1);
   else if( ! strcmp( argv[ i], "save") && i + 1 < argc)
      status = run_scenario( argv[ i + 1], YES, -1);
   else if( ! strcmp( argv[ i], "menu") && i + 2 < argc)
      status = run_scenario( argv[ i + 1], NO, strtoll( argv[ i + 2], NULL, 10));
   else
      status = usage();
   [pool release];
   return( status);
}
