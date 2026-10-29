/* one line per generated meet type: its declared supertypes, sorted, in ACE's spelling */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "triangle.h"

static int cmp(const void *a, const void *b) { return strcmp(*(char **) a, *(char **) b); }

int main(int argc, char **argv)
{
    TriContent *c = tri_content_load_tdl(argv[1]);
    if (!tri_content_ok(c)) return 1;
    size_t n = tri_type_count(c);
    TriType *decl = malloc(n * sizeof *decl);
    size_t nd = 0;
    for (TriType t = 0; t < n; t++) {
        const char *nm = tri_type_name(c, t);
        if (nm[0] == '#' && strncmp(nm, "glb[", 4) != 0) decl[nd++] = t;
    }
    char **names = malloc(n * sizeof *names);
    for (TriType t = 0; t < n; t++) {
        if (strncmp(tri_type_name(c, t), "glb[", 4) != 0) continue;
        size_t k = 0;
        for (size_t i = 0; i < nd; i++)
            if (decl[i] != t && tri_subtype(c, t, decl[i])) names[k++] = (char *) tri_type_name(c, decl[i]) + 1;
        qsort(names, k, sizeof *names, cmp);
        for (size_t i = 0; i < k; i++) printf("%s%s", i ? " " : "", names[i]);
        printf("\n");
    }
    return 0;
}
