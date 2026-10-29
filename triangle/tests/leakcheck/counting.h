/* Sends the library's allocations to the counting allocator (counting.c). */
#include <stdlib.h>
#include <string.h>
void *cnt_malloc(size_t); void *cnt_calloc(size_t, size_t); void *cnt_realloc(void *, size_t); void cnt_free(void *); char *cnt_strdup(const char *);
#define malloc cnt_malloc
#define calloc cnt_calloc
#define realloc cnt_realloc
#define free cnt_free
#define strdup cnt_strdup
