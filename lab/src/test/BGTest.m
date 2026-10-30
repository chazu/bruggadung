#import "BGTest.h"

#import "BGBodyKind.h"
#import "BGValveKind.h"
#import "BGLatentKind.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>


const char   *BGContentDir = "content";

static int         checks;
static int         failures;
static BGContent   *sharedContent;      /* loaded once per run, released at the end */


void   BGTestCheck( int ok, const char *what, const char *file, int line)
{
   const char   *base;

   checks++;
   if( ok)
      return;
   failures++;
   base = strrchr( file, '/');
   fprintf( stderr, "    %s:%d: failed: %s\n", base ? base + 1 : file, line, what);
}


static int   cmp_name( const void *a, const void *b)
{
   return( strcmp( *(char *const *) a, *(char *const *) b));
}


BGContent   *BGLoadContent( void)
{
   BGContent        *content;
   NSMutableArray   *paths;
   NSError          *error;
   DIR              *dir;
   struct dirent    *ent;
   char             **names;
   size_t           len;
   size_t           i;
   size_t           n;

   dir = opendir( BGContentDir);
   if( ! dir)
   {
      fprintf( stderr, "lab: cannot open the content directory %s\n", BGContentDir);
      return( nil);
   }
   names = NULL;
   n     = 0;
   while( (ent = readdir( dir)))
   {
      len = strlen( ent->d_name);
      if( len < 5 || strcmp( ent->d_name + len - 4, ".tri"))
         continue;
      names      = realloc( names, sizeof( char *) * (n + 1));
      names[ n++] = strdup( ent->d_name);
   }
   closedir( dir);
   qsort( names, n, sizeof( char *), cmp_name);
   paths = [NSMutableArray array];
   for( i = 0; i < n; i++)
   {
      [paths addObject:[NSString stringWithFormat:@"%s/%s", BGContentDir, names[ i]]];
      free( names[ i]);
   }
   free( names);
   error   = nil;
   content = [BGContent contentFromFiles:paths
                                   error:&error];
   if( ! content)
      fprintf( stderr, "lab: the content does not load:\n%s\n", [[error localizedDescription] UTF8String]);
   return( content);
}


BGWorld   *BGTestWorld( uint64_t seed)
{
   BGWorld    *world;
   NSString   *error;

   if( ! sharedContent)
      sharedContent = [BGLoadContent() retain];
   if( ! sharedContent)
      return( nil);
   error = nil;
   world = [BGWorld worldWithContent:sharedContent
                                seed:seed
                               error:&error];
   if( ! world)
      fprintf( stderr, "lab: %s\n", [error UTF8String]);
   return( world);
}


void   BGReleaseSharedContentAfterUse( void)
{
   [sharedContent release];
   sharedContent = nil;
}


BGCommitter   *BGTestCommitter( BGWorld *world)
{
   BGCommitter   *committer;

   committer = [[[BGCommitter alloc] initWithWorld:world] autorelease];
   [committer addReactor:[[BGBodyKind new] autorelease]
                 forKind:"Body"];
   [committer addReactor:[[BGValveKind new] autorelease]
                 forKind:"Valve"];
   [committer addReactor:[[BGLatentKind new] autorelease]
                 forKind:"Part"];
   return( committer);
}


int   BGRunTests( const BGTestCase *tests, size_t n, const char *only)
{
   NSAutoreleasePool   *pool;
   size_t              i;
   size_t              run;
   int                 before;

   run = 0;
   for( i = 0; i < n; i++)
   {
      if( only && ! strstr( tests[ i].name, only))
         continue;
      before = failures;
      pool   = [NSAutoreleasePool new];
      tests[ i].function();
      [pool release];
      printf( "%s %s\n", failures == before ? "ok  " : "FAIL", tests[ i].name);
      run++;
   }
   printf( "%zu tests, %d checks, %d failed\n", run, checks, failures);
   [sharedContent release];
   sharedContent = nil;
   return( failures);
}
