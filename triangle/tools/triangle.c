/* triangle: the command-line tool for Triangle content.
 *
 *   triangle check [PATH...]              load content and report its diagnostics
 *   triangle inspect NAME [PATH...]       a type, or an instance's spec with origins
 *   triangle components PREFIX [PATH...]  the C structs for the content's components
 *   triangle export [OPTIONS] [PATH...]   instances as JSON or YAML
 *   triangle lsp                          the language server, over stdio
 *
 * A PATH is a .tri file or a directory, which stands for the .tri files in it;
 * with none, the current directory. */
#include "triangle.h"
#include "export.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define TRIANGLE_VERSION "0.1.0"

int lsp_main(void);

typedef struct { char **v; size_t n, cap; } Paths;

static void add(Paths *p, const char *s)
{
    if (p->n == p->cap) p->v = realloc(p->v, (p->cap = p->cap ? p->cap * 2 : 16) * sizeof *p->v);
    size_t len = strlen(s) + 1;
    p->v[p->n] = malloc(len);
    memcpy(p->v[p->n++], s, len);
}

static int cmp_str(const void *a, const void *b) { return strcmp(*(char *const *) a, *(char *const *) b); }

static int expand(Paths *out, const char *path)
{
    struct stat st;
    if (stat(path, &st) != 0) { fprintf(stderr, "triangle: cannot read %s\n", path); return 0; }
    if (!S_ISDIR(st.st_mode)) { add(out, path); return 1; }
    DIR *d = opendir(path);
    if (!d) { fprintf(stderr, "triangle: cannot read %s\n", path); return 0; }
    size_t first = out->n;
    struct dirent *e;
    while ((e = readdir(d))) {
        size_t n = strlen(e->d_name);
        if (e->d_name[0] == '.' || n < 5 || strcmp(e->d_name + n - 4, ".tri")) continue;
        char buf[4096];
        snprintf(buf, sizeof buf, "%s%s%s", path, path[strlen(path) - 1] == '/' ? "" : "/", e->d_name);
        add(out, buf);
    }
    closedir(d);
    qsort(out->v + first, out->n - first, sizeof *out->v, cmp_str);
    return 1;
}

/* Loads the content named by args (files and directories, or "."). */
static TriContent *load(char **args, int n, int quiet)
{
    Paths p = { 0 };
    int ok = 1;
    if (n == 0) ok = expand(&p, ".");
    for (int i = 0; i < n; i++) ok &= expand(&p, args[i]);
    if (!ok) return NULL;
    if (!p.n) { fprintf(stderr, "triangle: no .tri files\n"); free(p.v); return NULL; }
    TriContent *c = tri_content_load((const char *const *) p.v, p.n);
    for (size_t i = 0; i < p.n; i++) free(p.v[i]);
    free(p.v);
    if (!quiet || !tri_content_ok(c))
        for (size_t i = 0; i < tri_diag_count(c); i++) fprintf(stderr, "%s\n", tri_diag_message(c, i));
    return c;
}

static int cmd_check(char **args, int n)
{
    TriContent *c = load(args, n, 0);
    if (!c) return 2;
    int ok = tri_content_ok(c);
    if (ok) {
        TriStats st;
        tri_content_stats(c, &st);
        size_t warnings = tri_diag_count(c);
        printf("ok: %zu types, %zu instances, %zu components, %zu warning%s; hash %016llx\n", st.types - st.glb_types,
               tri_instance_count(c), tri_component_count(c), warnings, warnings == 1 ? "" : "s",
               (unsigned long long) tri_content_hash(c));
    }
    tri_content_free(c);
    return ok ? 0 : 1;
}

static int cmd_inspect(char **args, int n)
{
    if (n < 1) { fprintf(stderr, "usage: triangle inspect NAME [PATH...]\n"); return 2; }
    TriContent *c = load(args + 1, n - 1, 1);
    if (!c) return 2;
    if (!tri_content_ok(c)) { tri_content_free(c); return 1; }
    const char *name = args[0];
    int found = 0;
    const char *doc = tri_doc(c, name);
    if (doc) printf("%s\n\n", doc);
    TriType t = tri_type_named(c, name);
    size_t d0 = tri_diag_count(c);
    if (t != TRI_BOTTOM) {
        found = 1;
        printf("type %s", name);
        for (TriType p = tri_primary_parent(c, t); p != TRI_BOTTOM && p != t;) {
            printf(" < %s", tri_type_name(c, p));
            TriType q = tri_primary_parent(c, p);
            if (q == p) break;
            p = q;
        }
        printf("\n");
        size_t comps[32];
        size_t nc = tri_type_components(c, t, comps, 32);
        for (size_t i = 0; i < nc && i < 32; i++) printf("component %s\n", tri_component_name(c, comps[i]));
    } else if (tri_spec(c, name)) {
        found = 1;
        size_t len = tri_inspect(c, name, NULL, 0);
        char *buf = malloc(len + 1);
        tri_inspect(c, name, buf, len + 1);
        fputs(buf, stdout);
        free(buf);
        for (size_t i = 0; i < tri_spec_note_count(c, name); i++) printf("note: %s\n", tri_spec_note(c, name, i));
    } else {
        /* an instance without a spec (a pattern with open fields, say): say why */
        for (size_t i = 0; i < tri_instance_count(c) && !found; i++) found = !strcmp(tri_instance_name(c, i), name);
        if (found) {
            fprintf(stderr, "triangle: %s has no spec (`triangle export -e %s` shows it as written):\n", name, name);
            for (size_t i = d0; i < tri_diag_count(c); i++) fprintf(stderr, "%s\n", tri_diag_message(c, i));
            tri_content_free(c);
            return 1;
        }
    }
    tri_content_free(c);
    if (!found) { fprintf(stderr, "triangle: no type or instance named %s\n", name); return 1; }
    return 0;
}

static int cmd_export(char **args, int n)
{
    ExportOptions o = { 0 };
    const char **names = malloc((size_t) (n ? n : 1) * sizeof *names);
    size_t nn = 0;
    char **paths = malloc((size_t) (n ? n : 1) * sizeof *paths);
    int np = 0;
    for (int i = 0; i < n; i++) {
        const char *a = args[i];
        if (!strcmp(a, "--yaml")) o.yaml = 1;
        else if (!strcmp(a, "--json")) o.yaml = 0;
        else if (!strcmp(a, "--types")) o.types = 1;
        else if (!strcmp(a, "--concrete")) o.concrete = 1;
        else if (!strcmp(a, "--seed") && i + 1 < n) { o.seeded = 1; o.seed = strtoull(args[++i], NULL, 10); }
        else if (!strcmp(a, "-e") && i + 1 < n) names[nn++] = args[++i];
        else if (a[0] == '-') {
            fprintf(stderr, "usage: triangle export [--yaml] [--types] [--concrete] [--seed N] [-e NAME]... [PATH...]\n");
            free(names);
            free(paths);
            return 2;
        } else paths[np++] = args[i];
    }
    TriContent *c = load(paths, np, 1);
    free(paths);
    if (!c) { free(names); return 2; }
    if (!tri_content_ok(c)) { tri_content_free(c); free(names); return 1; }
    int r = export_content(c, names, nn, &o, stdout);
    tri_content_free(c);
    free(names);
    return r;
}

static int cmd_components(char **args, int n)
{
    if (n < 1) { fprintf(stderr, "usage: triangle components PREFIX [PATH...]\n"); return 2; }
    TriContent *c = load(args + 1, n - 1, 1);
    if (!c) return 2;
    if (!tri_content_ok(c)) { tri_content_free(c); return 1; }
    size_t len = tri_component_header(c, args[0], NULL, 0);
    char *buf = malloc(len + 1);
    tri_component_header(c, args[0], buf, len + 1);
    fputs(buf, stdout);
    free(buf);
    tri_content_free(c);
    return 0;
}

static void usage(FILE *f)
{
    fputs("usage: triangle COMMAND [ARGS]\n\n"
          "  check [PATH...]              load content and report its diagnostics\n"
          "  inspect NAME [PATH...]       a type, or an instance's spec with the origin of each value\n"
          "  components PREFIX [PATH...]  the C structs for the content's components\n"
          "  export [OPTIONS] [PATH...]   instances as JSON (or --yaml): blueprints as their specs\n"
          "                               (--seed N: one entity each), patterns as they are;\n"
          "                               -e NAME for some, --types for #type, --concrete to\n"
          "                               refuse values still open\n"
          "  lsp                          run the language server over stdio\n"
          "  version                      print the version\n\n"
          "A PATH is a .tri file or a directory of them; the default is the current directory.\n",
          f);
}

int main(int argc, char **argv)
{
    if (argc < 2) { usage(stderr); return 2; }
    const char *cmd = argv[1];
    char **rest = argv + 2;
    int n = argc - 2;
    if (!strcmp(cmd, "check")) return cmd_check(rest, n);
    if (!strcmp(cmd, "inspect")) return cmd_inspect(rest, n);
    if (!strcmp(cmd, "components")) return cmd_components(rest, n);
    if (!strcmp(cmd, "export")) return cmd_export(rest, n);
    if (!strcmp(cmd, "lsp") || !strcmp(cmd, "--lsp")) return lsp_main();
    if (!strcmp(cmd, "version") || !strcmp(cmd, "--version")) { printf("triangle %s\n", TRIANGLE_VERSION); return 0; }
    if (!strcmp(cmd, "help") || !strcmp(cmd, "--help") || !strcmp(cmd, "-h")) { usage(stdout); return 0; }
    fprintf(stderr, "triangle: unknown command %s\n", cmd);
    usage(stderr);
    return 2;
}
