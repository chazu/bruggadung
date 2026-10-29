/*
 * lab — the bruggadung simulation laboratory.
 *
 *   lab test [name]          run the tests (those whose names contain `name`)
 *   lab run <scenario>       run a scenario and print its trace and checks:
 *                            marked-nail, marked-nail-a, marked-nail-b,
 *                            cistern, cistern-b, cistern-d, cistern-e
 *   lab save <scenario>      run a scenario and print the save of its end state
 *   lab menu <scenario> <ms> run a scenario to a time and print the worker's menu
 *   lab play <world> [--seed n] [--log file]
 *                            an interactive session on workshop or cistern;
 *                            the commands read are its replay log
 *   lab -C <dir> ...         read content from <dir> (default: content)
 */
#import "BGTest.h"

#import "BGMarkedNail.h"
#import "BGSave.h"
#import "BGActions.h"
#import "BGView.h"
#import "BGCistern.h"
#import "BGPlay.h"

#include <unistd.h>

#include <stdio.h>
#include <stdlib.h>


extern const BGTestCase   BGAllTests[];
extern const size_t       BGAllTestsCount;


static int   usage( void)
{
   fprintf( stderr, "usage: lab [-C contentdir] test [name]\n"
                    "       lab [-C contentdir] run|save marked-nail|marked-nail-a|marked-nail-b\n"
                    "       lab [-C contentdir] menu marked-nail|marked-nail-a|marked-nail-b <ms>\n"
                    "       lab [-C contentdir] play workshop|cistern [--seed n] [--log file]\n");
   return( 2);
}


static int   play( int argc, char *argv[], int i)
{
   BGPlay     *session;
   NSString   *error;
   FILE       *log;
   uint64_t   seed;
   char       line[ 1024];
   size_t     len;
   BOOL       tty;
   int        k;

   seed = 42;
   log  = NULL;
   for( k = i + 2; k + 1 < argc; k += 2)
   {
      if( ! strcmp( argv[ k], "--seed"))
         seed = strtoull( argv[ k + 1], NULL, 10);
      else if( ! strcmp( argv[ k], "--log"))
         log = fopen( argv[ k + 1], "w");
   }
   error   = nil;
   session = [BGPlay playWorld:[NSString stringWithUTF8String:argv[ i + 1]]
                          seed:seed
                         error:&error];
   if( ! session)
   {
      fprintf( stderr, "lab: %s\n", [error UTF8String]);
      return( 1);
   }
   tty = isatty( 0);
   printf( "%s", [[session takeOutput] UTF8String]);
   for( ;;)
   {
      if( tty)
      {
         printf( "> ");
         fflush( stdout);
      }
      if( ! fgets( line, sizeof( line), stdin))
         break;
      len = strlen( line);
      while( len && (line[ len - 1] == '\n' || line[ len - 1] == '\r'))
         line[ --len] = 0;
      if( ! tty)
         printf( "> %s\n", line);
      if( log)
         fprintf( log, "%s\n", line);
      if( ! [session command:[NSString stringWithUTF8String:line]])
         break;
      printf( "%s", [[session takeOutput] UTF8String]);
   }
   if( log)
      fclose( log);
   return( 0);
}


static int   run_cistern( const char *name)
{
   BGCisternVariant   variant;
   BGCistern          *scenario;
   BGWorld            *world;
   NSArray            *lines;
   NSUInteger         i;

   if( ! strcmp( name, "cistern"))
      variant = BGCisternBase;
   else if( ! strcmp( name, "cistern-b"))
      variant = BGCisternEarlier;
   else if( ! strcmp( name, "cistern-e"))
      variant = BGCisternStopsEarly;
   else
      variant = BGCisternReversed;
   world = BGTestWorld( 7);
   if( ! world)
      return( 1);
   BGReleaseSharedContentAfterUse();
   scenario = [[[BGCistern alloc] initWithWorld:world
                                      committer:BGTestCommitter( world)
                                        variant:variant] autorelease];
   [scenario run];
   printf( "== trace\n");
   lines = [[scenario committer] trace];
   for( i = 0; i < [lines count]; i++)
      printf( "%s\n", [[lines objectAtIndex:i] UTF8String]);
   printf( "\n== the fluid domain, per step\n");
   lines = [[scenario fluid] log];
   for( i = 0; i < [lines count]; i++)
      printf( "%s\n", [[lines objectAtIndex:i] UTF8String]);
   printf( "\n== entities\n");
   for( i = 1; i < [world nextID]; i++)
      printf( "%s\n", [[world describeEntity:(BGEntityID) i] UTF8String]);
   printf( "on the floor: %lld mL\n", (long long) [world totalTileWater]);
   printf( "\n== checks\n");
   lines = [scenario results];
   for( i = 0; i < [lines count]; i++)
      printf( "%s\n", [[lines objectAtIndex:i] UTF8String]);
   return( [scenario failureCount] ? 1 : 0);
}


static int   run_scenario( const char *name, BOOL save, int64_t menuAt)
{
   BGMarkedNailVariant   variant;
   BGMarkedNail          *scenario;
   BGWorld               *world;
   NSArray               *lines;
   BGStore               *entities;
   NSUInteger            i;

   if( ! strncmp( name, "cistern", 7))
      return( run_cistern( name));
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
      printf( "%s", [BGSave( world, [scenario committer], nil) UTF8String]);
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
   else if( ! strcmp( argv[ i], "play") && i + 1 < argc)
      status = play( argc, argv, i);
   else if( ! strcmp( argv[ i], "menu") && i + 2 < argc)
      status = run_scenario( argv[ i + 1], NO, strtoll( argv[ i + 2], NULL, 10));
   else
      status = usage();
   [pool release];
   return( status);
}
