/* Writes the C structs for a content build's components to standard output,
 * or, with -odin, the same as an Odin file.
 *
 *   tri-components PREFIX file.tri ... > components.h
 *   tri-components -odin PACKAGE TRIANGLE-IMPORT file.tri ... > components.odin
 *
 * Content is the source of truth: run this as a build step, so the structs
 * the component stores use always match the @component types. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "triangle.h"

int main(int argc, char **argv)
{
    int odin = argc > 1 && !strcmp(argv[1], "-odin");
    int first = odin ? 4 : 2;
    if (argc <= first) {
        fprintf(stderr, "usage: %s PREFIX file.tri ...\n       %s -odin PACKAGE TRIANGLE-IMPORT file.tri ...\n",
                argv[0], argv[0]);
        return 2;
    }
    TriContent *c = tri_content_load((const char *const *) argv + first, (size_t) (argc - first));
    for (size_t i = 0; i < tri_diag_count(c); i++) fprintf(stderr, "%s\n", tri_diag_message(c, i));
    if (!tri_content_ok(c)) { tri_content_free(c); return 1; }
    size_t n = odin ? tri_component_odin(c, argv[2], argv[3], NULL, 0) : tri_component_header(c, argv[1], NULL, 0);
    char *buf = malloc(n + 1);
    if (odin) tri_component_odin(c, argv[2], argv[3], buf, n + 1);
    else tri_component_header(c, argv[1], buf, n + 1);
    fputs(buf, stdout);
    free(buf);
    tri_content_free(c);
    return 0;
}
