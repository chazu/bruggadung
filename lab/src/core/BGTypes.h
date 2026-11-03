/*
 * The types every part of the laboratory shares: entity IDs, simulation
 * time, seeds, and locations. Plain C, so stores and proposals can hold them
 * by value.
 */
#ifndef BG_TYPES_H
#define BG_TYPES_H

#ifdef __MULLE_OBJC__
# import "import-private.h"
#else
# import <Foundation/Foundation.h>
#endif

#ifdef _WIN32
/* GNUstep's Foundation brings in <windows.h>, which makes these macros. */
# undef near
# undef far
#endif

#include <stdbool.h>
#include <stdint.h>
#include <string.h>


/* An entity is an ID from the world's counter, never reused. 0 is no entity.
 * A proposal group names the entities it creates by handles, which have the
 * top bit set until the group applies. */
typedef uint64_t   BGEntityID;

#define BGNoEntity       ((BGEntityID) 0)
#define BGHandleBit      0x8000000000000000ULL
#define BGHandle( n)     ((BGEntityID) (BGHandleBit | (uint64_t) (n)))
#define BGIsHandle( e)   (((e) & BGHandleBit) != 0)


/* Simulation time, in milliseconds. */
typedef struct
{
   int64_t   ms;
} BGTime;

static inline BGTime   BGTimeMake( int64_t ms)
{
   BGTime   t;

   t.ms = ms;
   return( t);
}

#define BGTimeNever   BGTimeMake( INT64_MAX)


/* Seeds and the deterministic streams drawn from them (splitmix64). Nothing
 * that must not depend on creation order derives from an entity ID. */
static inline uint64_t   BGMix( uint64_t x)
{
   x += 0x9e3779b97f4a7c15ULL;
   x  = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
   x  = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
   return( x ^ (x >> 31));
}

static inline uint64_t   BGMixString( uint64_t h, const char *s)
{
   while( s && *s)
      h = BGMix( h ^ (uint8_t) *s++);
   return( BGMix( h ^ 0xff));
}

static inline uint64_t   BGNext( uint64_t *state)
{
   *state = BGMix( *state);
   return( *state);
}


/* Location: the one exclusive relation every physical entity has. */
typedef enum
{
   BGLocationNone = 0,
   BGLocationOnTile,      /* x, y, level */
   BGLocationIn,          /* place: a container */
   BGLocationHeldBy,      /* place: an agent; slot: the hand */
   BGLocationPartOf       /* place: an assembly; role and slot: the index */
} BGLocationForm;

typedef struct
{
   BGLocationForm   form;
   BGEntityID       place;
   int32_t          x;
   int32_t          y;
   int32_t          level;
   int32_t          slot;
   char             role[ 16];
} BGLocation;

static inline BGLocation   BGLocationMakeNone( void)
{
   BGLocation   loc;

   memset( &loc, 0, sizeof( loc));
   return( loc);
}

static inline BGLocation   BGOnTile( int32_t x, int32_t y, int32_t level)
{
   BGLocation   loc;

   loc       = BGLocationMakeNone();
   loc.form  = BGLocationOnTile;
   loc.x     = x;
   loc.y     = y;
   loc.level = level;
   return( loc);
}

static inline BGLocation   BGIn( BGEntityID container)
{
   BGLocation   loc;

   loc       = BGLocationMakeNone();
   loc.form  = BGLocationIn;
   loc.place = container;
   return( loc);
}

static inline BGLocation   BGHeldBy( BGEntityID agent, int32_t hand)
{
   BGLocation   loc;

   loc       = BGLocationMakeNone();
   loc.form  = BGLocationHeldBy;
   loc.place = agent;
   loc.slot  = hand;
   return( loc);
}

static inline BGLocation   BGPartOf( BGEntityID assembly, const char *role, int32_t index)
{
   BGLocation   loc;

   loc       = BGLocationMakeNone();
   loc.form  = BGLocationPartOf;
   loc.place = assembly;
   loc.slot  = index;
   strncpy( loc.role, role, sizeof( loc.role) - 1);
   return( loc);
}

static inline bool   BGLocationEqual( BGLocation a, BGLocation b)
{
   return( a.form == b.form && a.place == b.place && a.x == b.x && a.y == b.y &&
           a.level == b.level && a.slot == b.slot && ! strcmp( a.role, b.role));
}

/* Writes the location as text, such as "in(7)" or "heldBy(3, 0)". */
void   BGLocationFormat( BGLocation loc, char *buf, size_t len);

#endif
