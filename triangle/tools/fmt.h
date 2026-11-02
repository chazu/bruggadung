/* triangle fmt: Triangle source in its canonical layout. */
#ifndef TRI_FMT_H
#define TRI_FMT_H

/* The source laid out canonically: spacing between tokens normalised,
 * lines indented by nesting, runs of fields, lets and attributes aligned.
 * Lines are never joined or split, and the tokens and comments are exactly
 * the source's. Returns a malloc'd string, or NULL with *err set to a
 * malloc'd message (line:col: what). */
char *fmt_source(const char *src, char **err);

#endif
