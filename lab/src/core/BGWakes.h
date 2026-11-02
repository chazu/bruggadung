/*
 * BGWakes — a queue of wakes (REALITY.md decision 7): when each of many
 * things is next due, earliest first, so a boundary reads only what falls
 * due at it, not all there are. An entry may go stale (the thing is due at
 * another time now, or never); it is checked when it comes up, against
 * what the caller says is so now, and let go. Push again whenever a
 * thing's time changes. Plain C.
 */
#import "BGTypes.h"


typedef struct BGWakes   BGWakes;

/* What is so now: when the thing is next due, or INT64_MAX for never. */
typedef int64_t   (*BGWakeTime)( void *context, BGEntityID thing);

BGWakes      *BGWakesNew( void);
void          BGWakesFree( BGWakes *q);
void          BGWakesClear( BGWakes *q);
/* A thing due at `at`; INT64_MAX is ignored. */
void          BGWakesPush( BGWakes *q, BGEntityID thing, int64_t at);
/* The earliest time still so, stale entries let go; INT64_MAX if none. */
int64_t       BGWakesNext( BGWakes *q, BGWakeTime now, void *context);
/* The things due by `t` (whose time, still so, is at or before it), taken
 * from the queue: malloc'd, in entity order, each once; *n of them. */
BGEntityID   *BGWakesTake( BGWakes *q, int64_t t, BGWakeTime now, void *context, NSUInteger *n);
NSUInteger    BGWakesCount( const BGWakes *q);
