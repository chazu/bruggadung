/*
 * The laboratory's test runner: `lab test` runs every registered test and
 * exits non-zero if any check fails.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"


extern const char   *BGContentDir;

void   BGTestCheck( int ok, const char *what, const char *file, int line);

#define BG_CHECK( cond)   BGTestCheck( (cond) ? 1 : 0, #cond, __FILE__, __LINE__)

/* The content in BGContentDir (every *.tri, in name order), or nil with the
 * diagnostics printed. */
BGContent    *BGLoadContent( void);
/* A fresh world on that content, with a committer that has the kinds'
 * reactors. */
BGWorld      *BGTestWorld( uint64_t seed);
BGCommitter  *BGTestCommitter( BGWorld *world);
/* The shared content stays alive while the worlds holding it do; this drops
 * the runner's own reference, so leak checks come out clean. */
void         BGReleaseSharedContentAfterUse( void);

typedef void   (*BGTestFunction)( void);

typedef struct
{
   const char       *name;
   BGTestFunction   function;
} BGTestCase;

/* Runs the tests whose names contain `only` (all, if NULL). Returns the
 * number of failed checks. */
int   BGRunTests( const BGTestCase *tests, size_t n, const char *only);
