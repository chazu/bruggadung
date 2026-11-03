#include "test.h"

#include <stdlib.h>
#include <unistd.h>

/* The TDL front end, on a small grammar written to a temporary directory. */

static const char *top_tdl =
    ":begin :type.\n"
    ":include \"types\".\n"
    ":end :type.\n"
    ":begin :instance :status lex-entry.\n"
    ":include \"lex\".\n"
    ":end :instance.\n"
    ":begin :instance :status rule.\n"
    ":include \"rules\".\n"
    ":end :instance.\n";

static const char *types_tdl =
    "; a line comment\n"
    "#| a block\n   comment |#\n"
    "*list* := *top*.\n"
    "*cons* := *list* & [ FIRST *top*, REST *list* ].\n"
    "*null* := *list*.\n"
    "*diff-list* := *top* & [ LIST *list*, LAST *list* ].\n"
    "string := *top*.\n"
    "bool := *top*.\n"
    "+ := bool.\n"
    "- := bool.\n"
    "head := *top*.\n"
    "noun := head.\n"
    "verb := head.\n"
    "sign := *top* &\n"
    "  \"\"\"A sign.\"\"\"\n"
    "  [ ORTH *list*,\n"
    "    HEAD head,\n"
    "    INFL bool,\n"
    "    RELS *diff-list* ].\n"
    "word := sign & [ INFL - ].\n"
    "phrase := sign & [ ARGS *list* ].\n"
    "noun-word := word & [ HEAD noun ].\n"
    "mixed := *top*.\n"
    "word :+ mixed.\n"
    "red := *top*.\n"
    "round := *top*.\n"
    "red-round := red & round.\n"
    "holder := *top* & [ PART red & round ].\n"
    "%(letter-set (!s abc\\(\\)))\n";

static const char *lex_tdl =
    "cat_n1 := noun-word & [ ORTH < \"cat\" > ].\n"
    "dog_n1 := noun-word & [ ORTH < \"dog\", \"s\" . #rest >, RELS <! [ HEAD verb ] !> ].\n";

static const char *rules_tdl =
    "head-rule := phrase & [ ARGS < [ HEAD #h ], ... >, HEAD #h ].\n"
    "n_pl_olr :=\n"
    "%suffix (!s !ss) (es eses)\n"
    "\"\"\"Plural\"\"\"\n"
    "sign & [ INFL + ].\n";

static void write_file(const char *dir, const char *name, const char *text)
{
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *f = fopen(path, "w");
    fputs(text, f);
    fclose(f);
}

void test_tdl_front_end(void)
{
#ifdef _WIN32
    const char *tmp = getenv("TEMP");      /* MSYS2's TMPDIR is a POSIX path */
#else
    const char *tmp = getenv("TMPDIR");
#endif
    char dir[1024];
    snprintf(dir, sizeof dir, "%s/triangle-tdl-XXXXXX", tmp ? tmp : "/tmp");
    if (!mkdtemp(dir)) { CHECK(0); return; }
    write_file(dir, "top.tdl", top_tdl);
    write_file(dir, "types.tdl", types_tdl);
    write_file(dir, "lex.tdl", lex_tdl);
    write_file(dir, "rules.tdl", rules_tdl);
    char top[1100];
    snprintf(top, sizeof top, "%s/top.tdl", dir);

    TriContent *c = tri_content_load_tdl(top);
    CHECK(tri_content_ok(c));
    if (!tri_content_ok(c)) { dump_diags(c); tri_content_free(c); return; }

    /* addenda may add supertypes; the declared one stays primary */
    TriType word = tri_type_named(c, "#word");
    CHECK(tri_primary_parent(c, word) == tri_type_named(c, "#sign"));
    CHECK(tri_subtype(c, word, tri_type_named(c, "#mixed")));
    /* strings are subtypes of the grammar's string type */
    CHECK(tri_primary_parent(c, tri_type_named(c, "\"cat\"")) == tri_type_named(c, "#string"));
    CHECK(tri_type_named(c, "#+") != TRI_BOTTOM);
    /* a conjunction is the meet completion provides; TDL gets no conjunction types */
    CHECK(tri_type_named(c, "#red & #round") == TRI_BOTTOM);
    CHECK(tri_meet(c, tri_type_named(c, "#red"), tri_type_named(c, "#round")) == tri_type_named(c, "#red-round"));

    /* statuses from :begin blocks */
    int saw_lex = 0, saw_rule = 0;
    for (size_t i = 0; i < tri_instance_count(c); i++) {
        if (strcmp(tri_instance_name(c, i), "cat_n1") == 0) saw_lex = strcmp(tri_instance_status(c, i), "lex-entry") == 0;
        if (strcmp(tri_instance_name(c, i), "n_pl_olr") == 0) saw_rule = strcmp(tri_instance_status(c, i), "rule") == 0;
    }
    CHECK(saw_lex && saw_rule);

    const TriNode *cat = tri_pattern(c, "cat_n1");
    CHECK_STR(printed(c, tri_at(c, cat, "orth")), "#*cons* & { first: \"cat\", rest: #*null* }");
    CHECK_STR(tri_type_name(c, tri_node_type(tri_at(c, cat, "head"))), "#noun");
    CHECK_STR(tri_type_name(c, tri_node_type(tri_at(c, cat, "infl"))), "#-");

    /* explicit list tails and difference lists */
    const TriNode *dog = tri_pattern(c, "dog_n1");
    CHECK_STR(printed(c, tri_at(c, dog, "orth.rest.rest")), "#*list*");
    CHECK(tri_at(c, dog, "rels.list.rest") == tri_at(c, dog, "rels.last"));
    CHECK_STR(tri_type_name(c, tri_node_type(tri_at(c, dog, "rels.list.first.head"))), "#verb");

    /* a rule daughter shares HEAD with the mother */
    const TriNode *rule = tri_pattern(c, "head-rule");
    CHECK(tri_at(c, rule, "args.first.head") == tri_at(c, rule, "head"));
    TriArena *a = tri_arena_new();
    TriFailure f;
    CHECK(tri_unify(c, tri_at(c, rule, "args.first"), cat, a, &f) != NULL);
    /* an inflected-only rule rejects an uninflected word */
    CHECK(tri_unify(c, tri_pattern(c, "n_pl_olr"), cat, a, &f) == NULL);
    CHECK_STR(f.path, "infl");
    tri_arena_free(a);
    tri_content_free(c);

    const char *files[] = { "top.tdl", "types.tdl", "lex.tdl", "rules.tdl" };
    for (int i = 0; i < 4; i++) {
        char p[1100];
        snprintf(p, sizeof p, "%s/%s", dir, files[i]);
        unlink(p);
    }
    rmdir(dir);
}
