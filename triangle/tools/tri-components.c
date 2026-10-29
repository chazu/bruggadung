/* Writes the C structs for a content build's components to standard output.
 *
 *   tri-components PREFIX file.tri ... > components.h
 *
 * Content is the source of truth: run this as a build step, so the structs
 * the component stores use always match the @component types. */
#include <stdio.h>
#include <stdlib.h>

#include "triangle.h"

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s PREFIX file.tri ...\n", argv[0]);
        return 2;
    }
    TriContent *c = tri_content_load((const char *const *) argv + 2, (size_t) argc - 2);
    for (size_t i = 0; i < tri_diag_count(c); i++) fprintf(stderr, "%s\n", tri_diag_message(c, i));
    if (!tri_content_ok(c)) { tri_content_free(c); return 1; }
    size_t n = tri_component_header(c, argv[1], NULL, 0);
    char *buf = malloc(n + 1);
    tri_component_header(c, argv[1], buf, n + 1);
    fputs(buf, stdout);
    free(buf);
    tri_content_free(c);
    return 0;
}
