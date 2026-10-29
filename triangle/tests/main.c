#include "test.h"

int test_failures;
const char *test_current;

TriContent *load(const char *const *names, const char *const *sources, size_t n)
{
    return tri_content_load_strings(names, sources, n);
}

void dump_diags(const TriContent *c)
{
    for (size_t i = 0; i < tri_diag_count(c); i++) fprintf(stderr, "    %s\n", tri_diag_message(c, i));
}

const char *printed(TriContent *c, const TriNode *n)
{
    static char buf[8192];
    if (!n) return "(null)";
    tri_print(c, n, buf, sizeof buf);
    return buf;
}

int has_diag(const TriContent *c, const char *needle, int errors_only)
{
    for (size_t i = 0; i < tri_diag_count(c); i++)
        if ((!errors_only || tri_diag_is_error(c, i)) && strstr(tri_diag_message(c, i), needle)) return 1;
    return 0;
}

#define TESTS(X) \
    X(test_units) X(test_hierarchy) X(test_glb) X(test_unify_tags) X(test_closedness) \
    X(test_lists) X(test_subsumption) X(test_components) \
    X(test_scenario1_order_independence) X(test_scenario1_defaults) X(test_scenario1_variation) \
    X(test_scenario1_conflict) X(test_scenario1_inexact) X(test_scenario1_feature_clash) \
    X(test_scenario2_unknown) X(test_scenario2_wrong_size) X(test_scenario2_hypotheses) \
    X(test_scenario3_recognition) X(test_tdl_front_end) X(test_quick_check)

#define DECLARE(name) void name(void);
TESTS(DECLARE)

int main(int argc, char **argv)
{
    struct { const char *name; void (*fn)(void); } tests[] = {
#define ENTRY(name) { #name, name },
        TESTS(ENTRY)
    };
    int ran = 0;
    for (size_t i = 0; i < sizeof tests / sizeof tests[0]; i++) {
        if (argc > 1 && !strstr(tests[i].name, argv[1])) continue;
        test_current = tests[i].name;
        int before = test_failures;
        tests[i].fn();
        printf("%s %s\n", test_failures == before ? "ok  " : "FAIL", tests[i].name);
        ran++;
    }
    printf("%d tests, %d failed checks\n", ran, test_failures);
    return test_failures ? 1 : 0;
}
