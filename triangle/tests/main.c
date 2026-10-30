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
    X(test_scenario3_recognition) X(test_tdl_front_end) X(test_quick_check) \
    X(test_builtin_types) X(test_default_override_survives_tie) \
    X(test_blueprints_resolve_at_load) X(test_registry_content_fields) X(test_defaults_with_type_alternatives) \
    X(test_type_disjunctions) X(test_instance_variants) X(test_vary_weights) X(test_typed_lists) \
    X(test_recursive_types) X(test_text_values) X(test_generalize_numbers) X(test_conflict_locations) \
    X(test_explain_and_inspect) X(test_docstrings) X(test_families) X(test_derived_fields) X(test_saves) \
    X(test_lgg) X(test_hypothesis_residuals) X(test_example_file) X(test_docs_guide) \
    X(test_tag_residuals_and_bindings) X(test_alternative_chosen_by_value) X(test_all_conflicts) X(test_compaction) \
    X(test_fixed_and_int) X(test_runtime_is_strict) X(test_build_log_and_clash_hint) X(test_previously_untested) \
    X(test_arithmetic) X(test_clauses) \
    X(test_path_keyed_variation) X(test_arithmetic_exponents_and_backwards) X(test_clause_solutions_distinct) \
    X(test_component_header) X(test_failure_recording_and_sizes) X(test_migration) X(test_packages) \
    X(test_properties) X(test_properties_order) X(test_properties_construct) X(test_fuzz_sources) X(test_properties_arithmetic) \
    X(test_properties_clauses)

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
