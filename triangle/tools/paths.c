/* Content on disk: see paths.h. */
#include "paths.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static int cmp_str(const void *a, const void *b) { return strcmp(*(char *const *) a, *(char *const *) b); }

static int is_tri(const char *name)
{
    size_t n = strlen(name);
    return n >= 5 && !strcmp(name + n - 4, ".tri");
}

static char *dup_str(const char *s)
{
    size_t n = strlen(s) + 1;
    char *r = malloc(n);
    memcpy(r, s, n);
    return r;
}

static char *join(const char *dir, const char *name)
{
    size_t n = strlen(dir);
    int slash = n && dir[n - 1] == '/';
    size_t len = n + strlen(name) + 2;
    char *s = malloc(len);
    snprintf(s, len, "%s%s%s", dir, slash ? "" : "/", name);
    return s;
}

void paths_add(Paths *p, const char *s)
{
    if (p->n == p->cap) p->v = realloc(p->v, (p->cap = p->cap ? p->cap * 2 : 16) * sizeof *p->v);
    size_t len = strlen(s) + 1;
    p->v[p->n] = malloc(len);
    memcpy(p->v[p->n++], s, len);
}

static int add_dir(Paths *p, const char *dir)
{
    DIR *d = opendir(dir);
    if (!d) return 0;
    int ok = 1;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char *path = join(dir, e->d_name);
        struct stat st;
        if (stat(path, &st) == 0) {
            if (S_ISDIR(st.st_mode)) ok &= add_dir(p, path);
            else if (is_tri(e->d_name)) paths_add(p, path);
        }
        free(path);
    }
    closedir(d);
    return ok;
}

int paths_add_tree(Paths *p, const char *dir)
{
    size_t first = p->n;
    int ok = add_dir(p, dir);
    qsort(p->v + first, p->n - first, sizeof *p->v, cmp_str);
    return ok;
}

void paths_free(Paths *p)
{
    for (size_t i = 0; i < p->n; i++) free(p->v[i]);
    free(p->v);
    p->v = NULL;
    p->n = p->cap = 0;
}

int paths_holds_tri(const char *dir)
{
    DIR *d = opendir(dir);
    if (!d) return 0;
    int found = 0;
    struct dirent *e;
    while (!found && (e = readdir(d))) {
        if (e->d_name[0] == '.' || !is_tri(e->d_name)) continue;
        char *path = join(dir, e->d_name);
        struct stat st;
        found = stat(path, &st) == 0 && !S_ISDIR(st.st_mode);
        free(path);
    }
    closedir(d);
    return found;
}

/* The directory above `dir`, as spelt from it; NULL above "/". */
static char *parent_of(const char *dir)
{
    size_t n = strlen(dir);
    while (n > 1 && dir[n - 1] == '/') n--;
    if (n == 1 && dir[0] == '/') return NULL;
    const char *last = dir;
    for (size_t i = 0; i < n; i++) if (dir[i] == '/') last = dir + i + 1;
    size_t lastlen = (size_t) (dir + n - last);
    if ((lastlen == 1 && last[0] == '.') || (lastlen == 2 && last[0] == '.' && last[1] == '.')) {
        /* "." and ".." can only rise by going further up */
        size_t len = n + 4;
        char *s = malloc(len);
        if (lastlen == 1 && last == dir) snprintf(s, len, "..");
        else snprintf(s, len, "%.*s/..", (int) (lastlen == 1 ? n - 2 : n), dir);
        return s;
    }
    if (last == dir) return dup_str(".");
    size_t keep = (size_t) (last - dir) - 1;
    if (keep == 0) return dup_str("/");
    char *s = malloc(keep + 1);
    memcpy(s, dir, keep);
    s[keep] = 0;
    return s;
}

char *paths_content_root(const char *dir)
{
    char *root = dup_str(dir);
    for (int depth = 0; depth < 64; depth++) {
        char *up = parent_of(root);
        if (!up) break;
        if (!paths_holds_tri(up)) { free(up); break; }
        free(root);
        root = up;
    }
    return root;
}
