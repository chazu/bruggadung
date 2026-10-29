/*
 * Saves (ARCHITECTURE.md "Saves"): the world's authoritative state and the
 * committer's, as text. Saved: the entity table and ID counter, every
 * component store, locations, edges, tombstones, history, the clock and
 * boundary, and the commit position and deferred groups. Rebuilt on load:
 * everything derived (there are no indexes yet). A restored world takes the
 * same next step as one that never saved.
 *
 * Fields and types are written by name, so a save can be read into content
 * that has changed: a field the content no longer has is an error, and a
 * field the save lacks starts at zero.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"


/* The save as text. Each saved system (domains, knowledge) checks in first,
 * and adds what it keeps itself as "domain <name> ..." lines. */
NSString   *BGSave( BGWorld *world, BGCommitter *committer, NSArray *domains);

/* A world restored from a save, on `content`, or nil with the reason. The
 * groups that were deferred come back in `deferred`, for the committer made
 * on the new world (with -restoreDeferred:), and its commit position in
 * `position`. */
BGWorld    *BGRestore( NSString *text,
                       BGContent *content,
                       NSArray **deferred,
                       uint64_t *position,
                       NSString **error);

/* The lines a save keeps for the named domain, for -restoreSavedState:. */
NSArray    *BGSavedDomainState( NSString *text, NSString *domain);
