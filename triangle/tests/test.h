#ifndef TRI_TEST_H
#define TRI_TEST_H

#include "triangle.h"

#include <stdio.h>
#include <string.h>

extern int test_failures;
extern const char *test_current;

#define CHECK(cond) do { \
    if (!(cond)) { \
        fprintf(stderr, "  %s:%d: [%s] CHECK failed: %s\n", __FILE__, __LINE__, test_current, #cond); \
        test_failures++; \
    } \
} while (0)

#define CHECK_STR(actual, expected) do { \
    const char *a_ = (actual), *e_ = (expected); \
    if (!a_ || strcmp(a_, e_) != 0) { \
        fprintf(stderr, "  %s:%d: [%s] expected \"%s\"\n      got      \"%s\"\n", __FILE__, __LINE__, \
                test_current, e_, a_ ? a_ : "(null)"); \
        test_failures++; \
    } \
} while (0)

#define CHECK_CONTAINS(actual, needle) do { \
    const char *a_ = (actual), *n_ = (needle); \
    if (!a_ || !strstr(a_, n_)) { \
        fprintf(stderr, "  %s:%d: [%s] expected to contain \"%s\"\n      got \"%s\"\n", __FILE__, __LINE__, \
                test_current, n_, a_ ? a_ : "(null)"); \
        test_failures++; \
    } \
} while (0)

/* helpers */
TriContent *load(const char *const *names, const char *const *sources, size_t n);
void        dump_diags(const TriContent *c);
const char *printed(TriContent *c, const TriNode *n);      /* static buffer */
int         has_diag(const TriContent *c, const char *needle, int errors_only);

#endif
