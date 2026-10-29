/* Counting allocator: the library is compiled with counting.h, which sends
 * its malloc, calloc, realloc, free, and strdup here. */
#include <stdlib.h>
#include <string.h>

long cnt_live;

void *cnt_malloc(size_t n) { void *p = malloc(n); if (p) cnt_live++; return p; }
void *cnt_calloc(size_t a, size_t b) { void *p = calloc(a, b); if (p) cnt_live++; return p; }
void *cnt_realloc(void *q, size_t n) { void *p = realloc(q, n); if (!q && p) cnt_live++; return p; }
void cnt_free(void *p) { if (p) cnt_live--; free(p); }
char *cnt_strdup(const char *s) { char *p = strdup(s); if (p) cnt_live++; return p; }
