/* A small JSON reader and writer for the language server. */
#ifndef TRI_JSON_H
#define TRI_JSON_H

#include <stddef.h>

typedef enum { J_NULL, J_FALSE, J_TRUE, J_NUM, J_STR, J_ARR, J_OBJ } JKind;

typedef struct J J;
struct J {
    JKind  k;
    double num;
    char  *str;        /* J_STR; for members of an object, also the key */
    char  *key;
    J     *items;      /* J_ARR, J_OBJ: an array of n */
    size_t n;
};

/* NULL on malformed input. */
J          *json_parse(const char *text, size_t len);
void        json_free(J *j);
const J    *json_get(const J *obj, const char *key);         /* NULL if absent or not an object */
const J    *json_path(const J *j, const char *dotted);       /* "params.textDocument.uri" */
const char *json_str(const J *j);                            /* NULL unless a string */
double      json_num(const J *j, double fallback);

/* A growable string. */
typedef struct { char *s; size_t len, cap; } Str;
void str_putc(Str *b, char c);
void str_puts(Str *b, const char *s);
void str_putn(Str *b, const char *s, size_t n);
void str_printf(Str *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
void str_free(Str *b);
/* Appends s as a JSON string literal, quoted and escaped. */
void str_json(Str *b, const char *s);
void str_jsonn(Str *b, const char *s, size_t n);
/* Appends a parsed value back as JSON. */
void str_value(Str *b, const J *j);

#endif
