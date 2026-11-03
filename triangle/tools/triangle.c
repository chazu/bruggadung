/* triangle: the command-line tool for Triangle content.
 *
 *   triangle check [PATH...]              load content and report its diagnostics
 *   triangle inspect NAME [PATH...]       a type, or an instance's spec with origins
 *   triangle components PREFIX [PATH...]  the C structs for the content's components
 *   triangle export [OPTIONS] [PATH...]   instances as JSON or YAML
 *   triangle fmt [--check] [PATH...]      lay sources out canonically
 *   triangle lsp                          the language server, over stdio
 *
 * A PATH is a .tri file or a directory, which stands for the .tri files in it
 * and beneath it (its topic directories); with none, the current directory. */
#include "triangle.h"
#include "export.h"
#include "fmt.h"
#include "paths.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define TRIANGLE_VERSION "0.1.0"

int lsp_main(void);

/* A PATH: a file as itself, a directory as the .tri files beneath it. */
static int expand(Paths *out, const char *path)
{
    struct stat st;
    if (stat(path, &st) != 0) { fprintf(stderr, "triangle: cannot read %s\n", path); return 0; }
    if (!S_ISDIR(st.st_mode)) { paths_add(out, path); return 1; }
    if (!paths_add_tree(out, path)) { fprintf(stderr, "triangle: cannot read %s\n", path); return 0; }
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

static char *read_file(const char *path)
{
    FILE *f = !strcmp(path, "-") ? stdin : fopen(path, "rb");
    if (!f) return NULL;
    size_t n = 0, cap = 4096;
    char *b = malloc(cap);
    size_t got;
    while ((got = fread(b + n, 1, cap - n - 1, f)) > 0) {
        n += got;
        if (n + 1 >= cap) b = realloc(b, cap *= 2);
    }
    b[n] = 0;
    if (f != stdin) fclose(f);
    return b;
}

static char *dir_of(const char *path)
{
    const char *slash = strrchr(path, '/');
    size_t n = slash ? (size_t) (slash - path) : 1;
    char *d = malloc(n + 1);
    memcpy(d, slash ? path : ".", n);
    d[n] = 0;
    return d;
}

/* The content root a source loads in (paths.h): its directory's. */
static char *root_of(const char *path)
{
    char *d = dir_of(path);
    char *r = paths_content_root(d);
    free(d);
    return r;
}

/* Whether two paths name one file: by device and inode, or on Windows,
 * which has no inodes, by full path. */
static int same_file(const char *a, const char *b)
{
    if (!strcmp(a, b)) return 1;
#ifdef _WIN32
    char *fa = _fullpath(NULL, a, 0), *fb = _fullpath(NULL, b, 0);
    int same = fa && fb && !_stricmp(fa, fb);
    free(fa);
    free(fb);
    return same;
#else
    struct stat sa, sb;
    return stat(a, &sa) == 0 && stat(b, &sb) == 0 && sa.st_dev == sb.st_dev && sa.st_ino == sb.st_ino;
#endif
}

/* Whether formatting the files of one content root keeps its content's meaning:
 * loaded as it is and as formatted, the two hash the same. Content that
 * doesn't load as it is can't be compared; the token check stands alone. */
static int same_meaning(const char *dir, Paths *files, char **formatted)
{
    Paths all = { 0 };
    if (!expand(&all, dir)) return 1;
    const char **before = calloc(all.n ? all.n : 1, sizeof *before);
    const char **after = calloc(all.n ? all.n : 1, sizeof *after);
    char **owned = calloc(all.n ? all.n : 1, sizeof *owned);
    int ok = 1;
    for (size_t i = 0; i < all.n; i++) {
        before[i] = owned[i] = read_file(all.v[i]);
        after[i] = before[i] ? before[i] : "";
        if (!before[i]) before[i] = "";
        for (size_t j = 0; j < files->n; j++)
            if (formatted[j] && same_file(files->v[j], all.v[i])) after[i] = formatted[j];
    }
    TriContent *a = tri_content_load_strings((const char *const *) all.v, before, all.n);
    if (tri_content_ok(a)) {
        TriContent *b = tri_content_load_strings((const char *const *) all.v, after, all.n);
        ok = tri_content_ok(b) && tri_content_hash(a) == tri_content_hash(b);
        tri_content_free(b);
    }
    tri_content_free(a);
    for (size_t i = 0; i < all.n; i++) free(owned[i]);
    free(owned);
    free(before);
    free(after);
    paths_free(&all);
    return ok;
}

static int cmd_fmt(char **args, int n)
{
    int check = 0;
    Paths files = { 0 };
    int ok = 1, any = 0;
    for (int i = 0; i < n; i++) {
        if (!strcmp(args[i], "--check") || !strcmp(args[i], "-l")) check = 1;
        else if (!strcmp(args[i], "-")) {
            /* stdin to stdout */
            char *src = read_file("-"), *err = NULL;
            char *out = src ? fmt_source(src, &err) : NULL;
            if (!out) { fprintf(stderr, "triangle: <stdin>:%s\n", err ? err : " cannot read"); free(err); free(src); return 1; }
            fputs(out, stdout);
            free(out);
            free(src);
            return 0;
        } else if (args[i][0] == '-') {
            fprintf(stderr, "usage: triangle fmt [--check] [PATH...]   (or - for stdin to stdout)\n");
            paths_free(&files);
            return 2;
        } else {
            any = 1;
            ok &= expand(&files, args[i]);
        }
    }
    if (!any) ok &= expand(&files, ".");
    if (!ok) { paths_free(&files); return 2; }

    char **formatted = calloc(files.n ? files.n : 1, sizeof *formatted);
    int failed = 0, changed = 0;
    for (size_t i = 0; i < files.n; i++) {
        char *src = read_file(files.v[i]), *err = NULL;
        if (!src) { fprintf(stderr, "triangle: cannot read %s\n", files.v[i]); failed = 1; continue; }
        char *out = fmt_source(src, &err);
        if (!out) {
            fprintf(stderr, "%s:%s\n", files.v[i], err);
            free(err);
            failed = 1;
        } else if (strcmp(out, src)) formatted[i] = out;
        else free(out);
        free(src);
    }
    /* each content root's meaning kept, or nothing in it is written */
    for (size_t i = 0; i < files.n; i++) {
        if (!formatted[i]) continue;
        char *d = root_of(files.v[i]);
        int seen = 0;
        for (size_t j = 0; j < i && !seen; j++) {
            char *e = formatted[j] ? root_of(files.v[j]) : NULL;
            seen = e && !strcmp(d, e);
            free(e);
        }
        if (!seen && !same_meaning(d, &files, formatted)) {
            fprintf(stderr, "triangle: formatting %s would change what its content means (a bug in triangle fmt); "
                            "left as it is\n", d);
            for (size_t j = 0; j < files.n; j++) {
                char *e = root_of(files.v[j]);
                if (!strcmp(d, e)) { free(formatted[j]); formatted[j] = NULL; }
                free(e);
            }
            failed = 1;
        }
        free(d);
    }
    for (size_t i = 0; i < files.n; i++) {
        if (!formatted[i]) continue;
        changed = 1;
        if (check) { printf("%s\n", files.v[i]); continue; }
        FILE *f = fopen(files.v[i], "wb");
        if (!f || fputs(formatted[i], f) < 0) { fprintf(stderr, "triangle: cannot write %s\n", files.v[i]); failed = 1; }
        if (f) fclose(f);
    }
    for (size_t i = 0; i < files.n; i++) free(formatted[i]);
    free(formatted);
    paths_free(&files);
    if (failed) return 1;
    return check && changed ? 1 : 0;
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
          "  fmt [--check] [PATH...]      lay sources out canonically, in place (--check: list\n"
          "                               the files it would change; -: stdin to stdout)\n"
          "  lsp                          run the language server over stdio\n"
          "  version                      print the version\n\n"
          "A PATH is a .tri file or a directory of them, its subdirectories included; the default\n"
          "is the current directory.\n",
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
    if (!strcmp(cmd, "fmt")) return cmd_fmt(rest, n);
    if (!strcmp(cmd, "lsp") || !strcmp(cmd, "--lsp")) return lsp_main();
    if (!strcmp(cmd, "version") || !strcmp(cmd, "--version")) { printf("triangle %s\n", TRIANGLE_VERSION); return 0; }
    if (!strcmp(cmd, "help") || !strcmp(cmd, "--help") || !strcmp(cmd, "-h")) { usage(stdout); return 0; }
    fprintf(stderr, "triangle: unknown command %s\n", cmd);
    usage(stderr);
    return 2;
}
