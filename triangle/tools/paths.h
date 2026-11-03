/* Content on disk: the .tri files a directory stands for, and the content
 * root a source belongs to.
 *
 * A directory stands for every .tri file in it and beneath it: a content
 * root and its topic directories. Names starting with a dot are passed over.
 *
 * A directory's content root is the directory itself or, while the
 * directory above holds .tri files of its own, that one's: so a source in a
 * topic directory loads with the content around it, not alone. */
#ifndef TRIANGLE_TOOLS_PATHS_H
#define TRIANGLE_TOOLS_PATHS_H

#include <stddef.h>

typedef struct { char **v; size_t n, cap; } Paths;

void  paths_add(Paths *p, const char *s);
/* Adds the .tri files beneath `dir`, sorted by path; 0 if it can't be read. */
int   paths_add_tree(Paths *p, const char *dir);
void  paths_free(Paths *p);

/* Whether `dir` holds a .tri file itself, not only in a subdirectory. */
int   paths_holds_tri(const char *dir);
/* The content root of `dir` (malloc'd), as spelt from it: "a/b" rises to
 * "a", "." to "..". */
char *paths_content_root(const char *dir);

#endif
