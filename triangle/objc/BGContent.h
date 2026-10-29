/*
 * BGContent — the Objective-C face of a Triangle content build, for the
 * systems. Manual retain/release, so it builds with mulle-objc as well as
 * Apple's runtime. Feature structure nodes stay C structs (TriNode); only the
 * content, specs, and families are objects.
 */
#ifdef __MULLE_OBJC__
# if __has_include(<MulleFoundation/MulleFoundation.h>)
#  import <MulleFoundation/MulleFoundation.h>
# else
#  import <MulleFoundationBase/MulleFoundationBase.h>     /* enough for this wrapper */
# endif
#else
# import <Foundation/Foundation.h>
#endif

#include "triangle.h"

@class BGSpec;

@interface BGContent : NSObject
{
    TriContent *_content;
}

+ (instancetype) contentFromFiles:(NSArray *) paths error:(NSError **) error;
/* name → source text; names are used in diagnostics */
+ (instancetype) contentFromSources:(NSDictionary *) sources error:(NSError **) error;

- (TriContent *) content;
- (uint64_t) contentHash;
- (NSArray *) diagnostics;

- (TriType) typeNamed:(NSString *) name;
- (NSString *) nameOfType:(TriType) type;
- (NSString *) documentationFor:(NSString *) name;

- (BGSpec *) specNamed:(NSString *) name;            /* nil if not a resolvable instance */
- (const TriNode *) patternNamed:(NSString *) name;
- (TriIndex *) indexForFamily:(NSString *) family;   /* operations, methods, rules */

- (TriMatch) match:(NSString *) instance against:(const TriNode *) description
         residuals:(NSArray **) residuals;
- (NSString *) describe:(const TriNode *) node;
@end

@interface BGSpec : NSObject
{
    BGContent *_owner;
    NSString *_name;
}

- (NSString *) name;
- (const TriNode *) node;
- (NSArray *) variationPaths;
- (NSArray *) notes;
- (NSString *) inspection;
/* every variation point made concrete from the seed, in `arena` */
- (const TriNode *) constructWithSeed:(uint64_t) seed arena:(TriArena *) arena;
@end
