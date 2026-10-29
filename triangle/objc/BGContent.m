#import "BGContent.h"

static NSString *const BGContentErrorDomain = @"BGContentErrorDomain";

/* MulleFoundation declares stringWithUTF8String: with a non-const parameter */
static NSString *string(const char *s)
{
    return [NSString stringWithUTF8String:(char *) s];
}

@interface BGSpec (Private)
- (id) initWithOwner:(BGContent *) owner name:(NSString *) name;
@end

@implementation BGContent

- (id) initWithContent:(TriContent *) content
{
    if ((self = [super init])) _content = content;
    return self;
}

- (void) dealloc
{
    tri_content_free(_content);
    [super dealloc];
}

static id finish(BGContent *c, NSError **error)
{
    if (tri_content_ok([c content])) return [c autorelease];
    if (error) {
        NSString *msg = [[c diagnostics] componentsJoinedByString:@"\n"];
        *error = [NSError errorWithDomain:BGContentErrorDomain code:1
                                 userInfo:[NSDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey]];
    }
    [c release];
    return nil;
}

+ (instancetype) contentFromFiles:(NSArray *) paths error:(NSError **) error
{
    NSUInteger n = [paths count];
    const char **cpaths = malloc(sizeof(char *) * (n ? n : 1));
    for (NSUInteger i = 0; i < n; i++) cpaths[i] = [[paths objectAtIndex:i] UTF8String];      /* paths are UTF-8 on our platforms */
    BGContent *c = [[self alloc] initWithContent:tri_content_load(cpaths, n)];
    free(cpaths);
    return finish(c, error);
}

+ (instancetype) contentFromSources:(NSDictionary *) sources error:(NSError **) error
{
    NSArray *names = [[sources allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger n = [names count];
    const char **cn = malloc(sizeof(char *) * (n ? n : 1));
    const char **cs = malloc(sizeof(char *) * (n ? n : 1));
    for (NSUInteger i = 0; i < n; i++) {
        cn[i] = [[names objectAtIndex:i] UTF8String];
        cs[i] = [[sources objectForKey:[names objectAtIndex:i]] UTF8String];
    }
    BGContent *c = [[self alloc] initWithContent:tri_content_load_strings(cn, cs, n)];
    free(cn);
    free(cs);
    return finish(c, error);
}

- (TriContent *) content { return _content; }
- (uint64_t) contentHash { return tri_content_hash(_content); }

- (NSArray *) diagnostics
{
    NSMutableArray *a = [NSMutableArray array];
    for (size_t i = 0; i < tri_diag_count(_content); i++)
        [a addObject:string(tri_diag_message(_content, i))];
    return a;
}

- (TriType) typeNamed:(NSString *) name { return tri_type_named(_content, [name UTF8String]); }

- (NSString *) nameOfType:(TriType) type
{
    const char *s = tri_type_name(_content, type);
    return s ? string(s) : nil;
}

- (NSString *) documentationFor:(NSString *) name
{
    const char *s = tri_doc(_content, [name UTF8String]);
    return s ? string(s) : nil;
}

- (BGSpec *) specNamed:(NSString *) name
{
    if (!tri_spec(_content, [name UTF8String])) return nil;
    return [[[BGSpec alloc] initWithOwner:self name:name] autorelease];
}

- (const TriNode *) patternNamed:(NSString *) name { return tri_pattern(_content, [name UTF8String]); }
- (TriIndex *) indexForFamily:(NSString *) family { return tri_family_index(_content, [family UTF8String]); }

- (TriMatch) match:(NSString *) instance against:(const TriNode *) description residuals:(NSArray **) residuals
{
    TriMatchResult r;
    TriMatch m = tri_match_instance(_content, [instance UTF8String], description, &r);
    if (residuals) {
        NSMutableArray *a = [NSMutableArray array];
        for (size_t i = 0; i < r.nresidual; i++) [a addObject:string(r.residual[i])];
        *residuals = a;
    }
    return m;
}

- (NSString *) describe:(const TriNode *) node
{
    size_t n = tri_print(_content, node, NULL, 0);
    char *buf = malloc(n + 1);
    tri_print(_content, node, buf, n + 1);
    NSString *s = string(buf);
    free(buf);
    return s;
}

@end

@implementation BGSpec

- (id) initWithOwner:(BGContent *) owner name:(NSString *) name
{
    if ((self = [super init])) {
        _owner = [owner retain];
        _name = [name copy];
    }
    return self;
}

- (void) dealloc
{
    [_owner release];
    [_name release];
    [super dealloc];
}

- (NSString *) name { return _name; }
- (const TriNode *) node { return tri_spec([_owner content], [_name UTF8String]); }

- (NSArray *) variationPaths
{
    NSMutableArray *a = [NSMutableArray array];
    const char *n = [_name UTF8String];
    for (size_t i = 0; i < tri_spec_variation_count([_owner content], n); i++)
        [a addObject:string(tri_spec_variation_path([_owner content], n, i))];
    return a;
}

- (NSArray *) notes
{
    NSMutableArray *a = [NSMutableArray array];
    const char *n = [_name UTF8String];
    for (size_t i = 0; i < tri_spec_note_count([_owner content], n); i++)
        [a addObject:string(tri_spec_note([_owner content], n, i))];
    return a;
}

- (NSString *) inspection
{
    size_t n = tri_inspect([_owner content], [_name UTF8String], NULL, 0);
    char *buf = malloc(n + 1);
    tri_inspect([_owner content], [_name UTF8String], buf, n + 1);
    NSString *s = string(buf);
    free(buf);
    return s;
}

- (const TriNode *) constructWithSeed:(uint64_t) seed arena:(TriArena *) arena
{
    return tri_construct([_owner content], [_name UTF8String], seed, arena);
}

@end
