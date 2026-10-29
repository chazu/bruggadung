#include "internal.h"

/* The unit descriptors: one per quantity kind, with its quantum, following
 * DOMAIN_SIMULATION.md §12 (heat 100 J, mass 1 g, gas amount 1 mmol, water
 * volume 1 mL, temperature 0.01 K, time 1 ms), and CONTENT_LANGUAGE.md's
 * decisions for length (0.1 mm), force (1 mN), and torque (1 mN·m). Torque and
 * heat share exponents; a product that could be either is torque, the first
 * listed. */

const char *const dim_names[NDIMS] = {
    "int", "fixed", "mass", "length", "time", "torque", "force", "heat", "temperature", "volume", "amount",
    "ref", "text",
};

/*                                       m  kg   s   K mol   quantum (SI)    display  per */
const QuantityKind quantity_kinds[NDIMS] = {
    [DIM_INT]         = { { 0, 0, 0, 0, 0 }, 1, 1,         "",    1, true },
    [DIM_FIXED]       = { { 0, 0, 0, 0, 0 }, 1, 1000,      "",    1000, true },
    [DIM_MASS]        = { { 0, 1, 0, 0, 0 }, 1, 1000,      "g",   1, true },
    [DIM_LENGTH]      = { { 1, 0, 0, 0, 0 }, 1, 10000,     "mm",  10, true },
    [DIM_TIME]        = { { 0, 0, 1, 0, 0 }, 1, 1000,      "ms",  1, true },
    [DIM_TORQUE]      = { { 2, 1, -2, 0, 0 }, 1, 1000,     "Nm",  1000, true },
    [DIM_FORCE]       = { { 1, 1, -2, 0, 0 }, 1, 1000,     "N",   1000, true },
    [DIM_HEAT]        = { { 2, 1, -2, 0, 0 }, 100, 1,      "J",   1, true },    /* printed in joules */
    [DIM_TEMPERATURE] = { { 0, 0, 0, 1, 0 }, 1, 100,       "K",   100, true },
    [DIM_VOLUME]      = { { 3, 0, 0, 0, 0 }, 1, 1000000,   "mL",  1, true },
    [DIM_AMOUNT]      = { { 0, 0, 0, 0, 1 }, 1, 1000,      "mmol", 1, true },
    [DIM_REF]         = { { 0, 0, 0, 0, 0 }, 1, 1,         "",    1, false },
    [DIM_TEXT]        = { { 0, 0, 0, 0, 0 }, 1, 1,         "",    1, false },
};

typedef struct { const char *suffix; int dim; int64_t num, den, offset; } Unit;

/* One unit is num/den quanta; a scale with an offset zero (Celsius) adds
 * `offset` quanta. */
static const Unit units[] = {
    { "g",   DIM_MASS, 1, 1, 0 },          { "kg",  DIM_MASS, 1000, 1, 0 },
    { "t",   DIM_MASS, 1000000, 1, 0 },
    { "mm",  DIM_LENGTH, 10, 1, 0 },        { "cm",  DIM_LENGTH, 100, 1, 0 },
    { "m",   DIM_LENGTH, 10000, 1, 0 },     { "km",  DIM_LENGTH, 10000000, 1, 0 },
    { "ms",  DIM_TIME, 1, 1, 0 },           { "s",   DIM_TIME, 1000, 1, 0 },
    { "min", DIM_TIME, 60000, 1, 0 },       { "h",   DIM_TIME, 3600000, 1, 0 },
    { "d",   DIM_TIME, 86400000, 1, 0 },
    { "mNm", DIM_TORQUE, 1, 1, 0 },         { "Nm",  DIM_TORQUE, 1000, 1, 0 },
    { "mN",  DIM_FORCE, 1, 1, 0 },          { "N",   DIM_FORCE, 1000, 1, 0 },
    { "kN",  DIM_FORCE, 1000000, 1, 0 },
    { "J",   DIM_HEAT, 1, 100, 0 },         { "kJ",  DIM_HEAT, 10, 1, 0 },
    { "MJ",  DIM_HEAT, 10000, 1, 0 },
    { "K",   DIM_TEMPERATURE, 100, 1, 0 },  { "C",   DIM_TEMPERATURE, 100, 1, 27315 },
    { "degC", DIM_TEMPERATURE, 100, 1, 27315 },
    { "mL",  DIM_VOLUME, 1, 1, 0 },         { "L",   DIM_VOLUME, 1000, 1, 0 },
    { "m3",  DIM_VOLUME, 1000000, 1, 0 },
    { "mmol", DIM_AMOUNT, 1, 1, 0 },        { "mol", DIM_AMOUNT, 1000, 1, 0 },
};

const char *units_parse(const char *text, size_t len, bool neg, int *dim, int64_t *q)
{
    size_t i = 0;
    __int128 mant = 0;
    int scale = 0;
    bool point = false;
    while (i < len && ((text[i] >= '0' && text[i] <= '9') || text[i] == '.')) {
        if (text[i] == '.') {
            if (point) return "malformed number";
            point = true;
        } else {
            mant = mant * 10 + (text[i] - '0');
            if (point) scale++;
            if (mant > (__int128) INT64_MAX) return "number out of range";
        }
        i++;
    }
    const char *suffix = text + i;
    size_t slen = len - i;
    __int128 num = 1, den = 1, offset = 0;
    if (slen == 0) {
        if (point) { *dim = DIM_FIXED; num = 1000; }
        else *dim = DIM_INT;
    } else {
        const Unit *u = NULL;
        for (size_t k = 0; k < sizeof units / sizeof units[0]; k++)
            if (strlen(units[k].suffix) == slen && memcmp(units[k].suffix, suffix, slen) == 0)
                u = &units[k];
        if (!u) return "unknown unit";
        *dim = u->dim;
        num = u->num;
        den = u->den;
        offset = u->offset;
    }
    __int128 p10 = 1;
    for (int k = 0; k < scale; k++) p10 *= 10;
    __int128 top = mant * num, bottom = den * p10;
    if (top % bottom != 0) return "literal is not a whole number of quanta";
    __int128 v = (neg ? -(top / bottom) : top / bottom) + offset;
    if (v > (__int128) INT64_MAX || v <= (__int128) INT64_MIN) return "quantity out of range";
    *q = (int64_t) v;
    return NULL;
}

void units_format(Buf *b, int dim, int64_t q)
{
    if (dim == DIM_TEXT) {
        buf_puts(b, (const char *) (intptr_t) q);
        return;
    }
    if (dim == DIM_REF) {
        buf_printf(b, "ref(%lld)", (long long) q);
        return;
    }
    if (dim == DIM_HEAT) {
        buf_printf(b, "%lldJ", (long long) q * 100);
        return;
    }
    int64_t per = quantity_kinds[dim].per;
    int64_t whole = q / per, frac = q % per;
    if (frac == 0) {
        buf_printf(b, "%lld%s", (long long) whole, quantity_kinds[dim].display);
        return;
    }
    if (q < 0 && whole == 0) buf_putc(b, '-');
    buf_printf(b, "%lld.", (long long) whole);
    if (frac < 0) frac = -frac;
    int digits = 0;
    for (int64_t p = per; p > 1; p /= 10) digits++;
    char tmp[32];
    snprintf(tmp, sizeof tmp, "%0*lld", digits, (long long) frac);
    size_t n = strlen(tmp);
    while (n > 1 && tmp[n - 1] == '0') tmp[--n] = 0;
    buf_printf(b, "%s%s", tmp, quantity_kinds[dim].display);
}
