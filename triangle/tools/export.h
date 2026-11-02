/* triangle export: instances as JSON or YAML. */
#ifndef TRI_EXPORT_H
#define TRI_EXPORT_H

#include <stdint.h>
#include <stdio.h>

#include "triangle.h"

typedef struct {
    int      yaml;        /* else JSON */
    int      types;       /* each structure's type, as "#type" */
    int      concrete;    /* a value still open is an error */
    int      seeded;      /* blueprints constructed from seed */
    uint64_t seed;
} ExportOptions;

/* Writes the named instances (every instance when nnames is 0) to out.
 * Returns 0, or 1 after reporting errors on stderr. */
int export_content(TriContent *c, const char *const *names, size_t nnames, const ExportOptions *o, FILE *out);

#endif
