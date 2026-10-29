#import "BGContent.h"

#include <stdio.h>

static int failures;
#define EXPECT(c) do { if (!(c)) { fprintf(stderr, "  %s:%d: failed: %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *src = [NSDictionary dictionaryWithObjectsAndKeys:
        @"#Material: \"steel\" | \"brass\"\n"
        @"// Something to hold.\n#Tool: { @component(Tool)\n size: length @field(content)\n"
        @" material: #Material @field(content)\n wear: *0 | >=0 & <=1000 @field(saved)\n}\n"
        @"w: #Tool & { size: 19mm }\n"
        @"#Roles: { target: #Tool }\n"
        @"grab: #Roles & { target: { size: 19mm } } @family(operations)\n", @"base.tri", nil];
    NSError *error = nil;
    BGContent *c = [BGContent contentFromSources:src error:&error];
    EXPECT(c != nil);
    EXPECT([[c documentationFor:@"#Tool"] isEqualToString:@"Something to hold."]);
    BGSpec *w = [c specNamed:@"w"];
    EXPECT([[w variationPaths] isEqualToArray:[NSArray arrayWithObject:@"material"]]);
    EXPECT([[w inspection] rangeOfString:@"wear: 0  <- default from #Tool"].location != NSNotFound);
    TriArena *a = tri_arena_new();
    const TriNode *made = [w constructWithSeed:3 arena:a];
    EXPECT(made && [[c describe:tri_at([c content], made, "material")] hasPrefix:@"\""]);
    NSArray *res = nil;
    const TriNode *d = tri_value([c content], "#Roles & { target: { size: >=10mm & <=20mm } }", a, NULL, 0);
    EXPECT([c match:@"grab" against:d residuals:&res] == TRI_UNKNOWN);
    EXPECT([res isEqualToArray:[NSArray arrayWithObject:@"target.size"]]);
    EXPECT([c indexForFamily:@"operations"] != NULL);
    tri_arena_free(a);
    BGContent *bad = [BGContent contentFromSources:[NSDictionary dictionaryWithObject:@"#A: #Nope\n" forKey:@"bad.tri"]
                                             error:&error];
    EXPECT(bad == nil && [[error localizedDescription] rangeOfString:@"#Nope"].location != NSNotFound);
    [pool release];
    printf("objc wrapper: %d failed checks\n", failures);
    return failures ? 1 : 0;
}
