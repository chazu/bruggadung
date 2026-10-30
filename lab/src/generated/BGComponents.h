/* Generated from Triangle content 5ac702cd9022f4f3: do not edit. Type IDs are valid
 * only for this content; regenerate when it changes. */
#ifndef BG_COMPONENTS_H
#define BG_COMPONENTS_H

#include <stdbool.h>
#include <stdint.h>

#define BG_CONTENT_HASH 0x5ac702cd9022f4f3ULL

/* Lever, from #Lever */
typedef struct {
    int64_t         leverage;    /* length, in quanta of 0.1mm; content, saved, inspect, perceive(sight) */
    int64_t         limit;    /* torque, in quanta of 0.001Nm; content, saved, proposable, inspect */
    bool            sleeve;    /* bool; content, saved, inspect, perceive(sight) */
} BGLever;

/* Sized, from #Sized */
typedef struct {
    int64_t         size;    /* length, in quanta of 0.1mm; content, saved, inspect, perceive(sight) */
} BGSized;

/* Activity, from #Activity */
typedef struct {
    uint64_t        actorRef;    /* a referent; saved, proposable, inspect */
    int64_t         amount;    /* int, in quanta of 1; content, saved, proposable, inspect */
    uint64_t        destinationRef;    /* a referent; saved, proposable, inspect */
    int64_t         due;    /* time, in quanta of 1ms; content, saved, proposable, inspect */
    uint64_t        itemRef;    /* a referent; saved, proposable, inspect */
    const char *    operation;    /* text; saved, proposable, inspect */
    int64_t         progress;    /* time, in quanta of 1ms; content, saved, proposable, inspect */
    int64_t         stage;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         started;    /* time, in quanta of 1ms; content, saved, proposable, inspect */
    uint32_t        status;    /* #ActivityStatus: a type ID; content, saved, proposable, inspect */
    int64_t         watchAtLeast;    /* volume, in quanta of 1mL; content, saved, proposable, inspect */
    uint64_t        watchHolder;    /* a referent; saved, proposable, inspect */
} BGActivity;

/* Claim, from #Claim */
typedef struct {
    uint32_t        kind;    /* #ClaimKind: a type ID; content, saved, inspect */
    int64_t         quantity;    /* int, in quanta of 1; content, saved, proposable, inspect */
} BGClaim;

/* Body, from #Body */
typedef struct {
    bool            bent;    /* bool; saved, proposable, inspect, perceive(sight) */
    int64_t         mass;    /* mass, in quanta of 1g; content, saved, proposable, inspect, perceive(touch) */
    uint32_t        material;    /* #Material: a type ID; content, saved, inspect, perceive(sight) */
    uint32_t        surface;    /* "flesh" | "metal" | "natural" | "paper" | "wood": a type ID; content, saved, inspect, appears(material) */
    int64_t         toolMarks;    /* int, in quanta of 1; saved, proposable, inspect, perceive(sight) */
} BGBody;

/* Agent, from #Agent */
typedef struct {
    uint32_t        coat;    /* #Colour: a type ID; content, saved, proposable, inspect, perceive(sight) */
    int64_t         curious;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         fed;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         fedAt;    /* time, in quanta of 1ms; content, saved, proposable, inspect */
    int64_t         grip;    /* force, in quanta of 0.001N; content, saved, inspect */
    int64_t         hands;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
    int64_t         helpful;    /* int, in quanta of 1; content, saved, proposable, inspect */
    bool            hiding;    /* bool; content, saved, proposable, inspect */
    int64_t         honesty;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         memory;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         painting;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         quickness;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         respectful;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         scruples;    /* int, in quanta of 1; content, saved, proposable, inspect */
} BGAgent;

/* Assembly, from #Assembly */
typedef struct {
    int64_t         slots;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
} BGAssembly;

/* Container, from #Container */
typedef struct {
    int64_t         capacity;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
} BGContainer;

/* Record, from #Record */
typedef struct {
    const char *    writing;    /* text; saved, proposable, inspect */
} BGRecord;

/* Stack, from #Stack */
typedef struct {
    int64_t         count;    /* int, in quanta of 1; content, saved, proposable, inspect */
    const char *    unit;    /* text; content, saved, inspect, perceive(sight) */
    int64_t         unitMass;    /* mass, in quanta of 1g; content, saved, inspect */
} BGStack;

/* Tap, from #Tap */
typedef struct {
    bool            open;    /* bool; content, saved, proposable, inspect, perceive(sight) */
    int64_t         rate;    /* int, in quanta of 1; content, saved, inspect */
} BGTap;

/* Trace, from #Trace */
typedef struct {
    uint64_t        bearer;    /* a referent; saved, proposable, inspect */
    int64_t         created;    /* time, in quanta of 1ms; content, saved, proposable, inspect */
    int64_t         expires;    /* time, in quanta of 1ms; content, saved, proposable, inspect */
    int64_t         magnitude;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         tileLevel;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         tileX;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         tileY;    /* int, in quanta of 1; content, saved, proposable, inspect */
    const char *    traceKind;    /* text; content, saved, proposable, inspect */
} BGTrace;

/* Valve, from #Valve */
typedef struct {
    int64_t         breakaway;    /* torque, in quanta of 0.001Nm; content, saved, proposable, inspect */
    int64_t         rating;    /* torque, in quanta of 0.001Nm; content, saved, inspect, perceive(sight) */
    bool            turned;    /* bool; content, saved, proposable, inspect, perceive(sight) */
} BGValve;

/* WaterStore, from #WaterStore */
typedef struct {
    int64_t         water;    /* volume, in quanta of 1mL; content, saved, proposable, inspect, perceive(sight) */
    int64_t         waterCapacity;    /* volume, in quanta of 1mL; content, saved, inspect, perceive(sight) */
} BGWaterStore;

/* Fastener, from #Fastener */
typedef struct {
    bool            tight;    /* bool; content, saved, proposable, inspect, perceive(sight) */
} BGFastener;

/* #ActivityStatus */
enum {
    BG_ACTIVITYSTATUS_COMPLETED = 206,
    BG_ACTIVITYSTATUS_EXHAUSTED = 207,
    BG_ACTIVITYSTATUS_FAILED = 208,
    BG_ACTIVITYSTATUS_RUNNING = 209,
    BG_ACTIVITYSTATUS_SUSPENDED = 210,
};

/* #ClaimKind */
enum {
    BG_CLAIMKIND_CUSTODY = 212,
    BG_CLAIMKIND_OWNERSHIP = 213,
    BG_CLAIMKIND_RESERVATION = 214,
};

/* #Material */
enum {
    BG_MATERIAL_CLOTH = 251,
    BG_MATERIAL_FOOD = 252,
    BG_MATERIAL_RUBBER = 253,
    BG_MATERIAL_STONE = 254,
    BG_MATERIAL_FLESH = 279,
    BG_MATERIAL_BRASS = 281,
    BG_MATERIAL_IRON = 282,
    BG_MATERIAL_PAPER = 283,
    BG_MATERIAL_STEEL = 284,
    BG_MATERIAL_OAK = 286,
};

/* "flesh" | "metal" | "natural" | "paper" | "wood" */
enum {
    BG_BODY_SURFACE_NATURAL = 176,
    BG_BODY_SURFACE_FLESH = 279,
    BG_BODY_SURFACE_BRASS = 281,
    BG_BODY_SURFACE_IRON = 282,
    BG_BODY_SURFACE_PAPER = 283,
    BG_BODY_SURFACE_STEEL = 284,
    BG_BODY_SURFACE_OAK = 286,
};

/* #Colour */
enum {
    BG_COLOUR_BLUE = 217,
    BG_COLOUR_BLACK = 219,
    BG_COLOUR_BROWN = 220,
    BG_COLOUR_GREEN = 221,
    BG_COLOUR_GREY = 222,
    BG_COLOUR_BEIGE = 224,
    BG_COLOUR_NAVY = 225,
    BG_COLOUR_RED = 226,
    BG_COLOUR_WHITE = 227,
    BG_COLOUR_YELLOW = 228,
};

/* The field registry: what code needs to read and write any component
 * generically. Define BG_COMPONENT_REGISTRY in one file to get the tables. */

#include <stddef.h>

enum { BG_VALUE_QUANTITY, BG_VALUE_TYPE, BG_VALUE_TEXT, BG_VALUE_REF, BG_VALUE_BOOL, BG_VALUE_NODE };

typedef struct {
    const char *name;       /* the feature */
    size_t      offset;
    int         value;      /* BG_VALUE_... */
    const char *kind;       /* a quantity kind, an enum's type name, or a structure's type */
    const char *flags;      /* from @field */
} BGFieldInfo;

typedef struct {
    const char *name;       /* the component */
    const char *type;       /* its Triangle type */
    size_t      size;
    size_t      nfields;
    const BGFieldInfo *fields;
} BGComponentInfo;

#define BG_COMPONENT_COUNT 15

#ifdef BG_COMPONENT_REGISTRY

static const BGFieldInfo BGLever_fields[] = {
    { "leverage", offsetof(BGLever, leverage), BG_VALUE_QUANTITY, "length", "content, saved, inspect, perceive(sight)" },
    { "limit", offsetof(BGLever, limit), BG_VALUE_QUANTITY, "torque", "content, saved, proposable, inspect" },
    { "sleeve", offsetof(BGLever, sleeve), BG_VALUE_BOOL, "bool", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGSized_fields[] = {
    { "size", offsetof(BGSized, size), BG_VALUE_QUANTITY, "length", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGActivity_fields[] = {
    { "actorRef", offsetof(BGActivity, actorRef), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "amount", offsetof(BGActivity, amount), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "destinationRef", offsetof(BGActivity, destinationRef), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "due", offsetof(BGActivity, due), BG_VALUE_QUANTITY, "time", "content, saved, proposable, inspect" },
    { "itemRef", offsetof(BGActivity, itemRef), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "operation", offsetof(BGActivity, operation), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
    { "progress", offsetof(BGActivity, progress), BG_VALUE_QUANTITY, "time", "content, saved, proposable, inspect" },
    { "stage", offsetof(BGActivity, stage), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "started", offsetof(BGActivity, started), BG_VALUE_QUANTITY, "time", "content, saved, proposable, inspect" },
    { "status", offsetof(BGActivity, status), BG_VALUE_TYPE, "#ActivityStatus", "content, saved, proposable, inspect" },
    { "watchAtLeast", offsetof(BGActivity, watchAtLeast), BG_VALUE_QUANTITY, "volume", "content, saved, proposable, inspect" },
    { "watchHolder", offsetof(BGActivity, watchHolder), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
};

static const BGFieldInfo BGClaim_fields[] = {
    { "kind", offsetof(BGClaim, kind), BG_VALUE_TYPE, "#ClaimKind", "content, saved, inspect" },
    { "quantity", offsetof(BGClaim, quantity), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGBody_fields[] = {
    { "bent", offsetof(BGBody, bent), BG_VALUE_BOOL, "bool", "saved, proposable, inspect, perceive(sight)" },
    { "mass", offsetof(BGBody, mass), BG_VALUE_QUANTITY, "mass", "content, saved, proposable, inspect, perceive(touch)" },
    { "material", offsetof(BGBody, material), BG_VALUE_TYPE, "#Material", "content, saved, inspect, perceive(sight)" },
    { "surface", offsetof(BGBody, surface), BG_VALUE_TYPE, "\"flesh\" | \"metal\" | \"natural\" | \"paper\" | \"wood\"", "content, saved, inspect, appears(material)" },
    { "toolMarks", offsetof(BGBody, toolMarks), BG_VALUE_QUANTITY, "int", "saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGAgent_fields[] = {
    { "coat", offsetof(BGAgent, coat), BG_VALUE_TYPE, "#Colour", "content, saved, proposable, inspect, perceive(sight)" },
    { "curious", offsetof(BGAgent, curious), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "fed", offsetof(BGAgent, fed), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "fedAt", offsetof(BGAgent, fedAt), BG_VALUE_QUANTITY, "time", "content, saved, proposable, inspect" },
    { "grip", offsetof(BGAgent, grip), BG_VALUE_QUANTITY, "force", "content, saved, inspect" },
    { "hands", offsetof(BGAgent, hands), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
    { "helpful", offsetof(BGAgent, helpful), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "hiding", offsetof(BGAgent, hiding), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect" },
    { "honesty", offsetof(BGAgent, honesty), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "memory", offsetof(BGAgent, memory), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "painting", offsetof(BGAgent, painting), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "quickness", offsetof(BGAgent, quickness), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "respectful", offsetof(BGAgent, respectful), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "scruples", offsetof(BGAgent, scruples), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGAssembly_fields[] = {
    { "slots", offsetof(BGAssembly, slots), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGContainer_fields[] = {
    { "capacity", offsetof(BGContainer, capacity), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGRecord_fields[] = {
    { "writing", offsetof(BGRecord, writing), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
};

static const BGFieldInfo BGStack_fields[] = {
    { "count", offsetof(BGStack, count), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "unit", offsetof(BGStack, unit), BG_VALUE_TEXT, "text", "content, saved, inspect, perceive(sight)" },
    { "unitMass", offsetof(BGStack, unitMass), BG_VALUE_QUANTITY, "mass", "content, saved, inspect" },
};

static const BGFieldInfo BGTap_fields[] = {
    { "open", offsetof(BGTap, open), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
    { "rate", offsetof(BGTap, rate), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
};

static const BGFieldInfo BGTrace_fields[] = {
    { "bearer", offsetof(BGTrace, bearer), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "created", offsetof(BGTrace, created), BG_VALUE_QUANTITY, "time", "content, saved, proposable, inspect" },
    { "expires", offsetof(BGTrace, expires), BG_VALUE_QUANTITY, "time", "content, saved, proposable, inspect" },
    { "magnitude", offsetof(BGTrace, magnitude), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "tileLevel", offsetof(BGTrace, tileLevel), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "tileX", offsetof(BGTrace, tileX), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "tileY", offsetof(BGTrace, tileY), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "traceKind", offsetof(BGTrace, traceKind), BG_VALUE_TEXT, "text", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGValve_fields[] = {
    { "breakaway", offsetof(BGValve, breakaway), BG_VALUE_QUANTITY, "torque", "content, saved, proposable, inspect" },
    { "rating", offsetof(BGValve, rating), BG_VALUE_QUANTITY, "torque", "content, saved, inspect, perceive(sight)" },
    { "turned", offsetof(BGValve, turned), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGWaterStore_fields[] = {
    { "water", offsetof(BGWaterStore, water), BG_VALUE_QUANTITY, "volume", "content, saved, proposable, inspect, perceive(sight)" },
    { "waterCapacity", offsetof(BGWaterStore, waterCapacity), BG_VALUE_QUANTITY, "volume", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGFastener_fields[] = {
    { "tight", offsetof(BGFastener, tight), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
};

static const BGComponentInfo BGComponents[BG_COMPONENT_COUNT + 1] = {
    { "Lever", "#Lever", sizeof(BGLever), 3, BGLever_fields },
    { "Sized", "#Sized", sizeof(BGSized), 1, BGSized_fields },
    { "Activity", "#Activity", sizeof(BGActivity), 12, BGActivity_fields },
    { "Claim", "#Claim", sizeof(BGClaim), 2, BGClaim_fields },
    { "Body", "#Body", sizeof(BGBody), 5, BGBody_fields },
    { "Agent", "#Agent", sizeof(BGAgent), 14, BGAgent_fields },
    { "Assembly", "#Assembly", sizeof(BGAssembly), 1, BGAssembly_fields },
    { "Container", "#Container", sizeof(BGContainer), 1, BGContainer_fields },
    { "Record", "#Record", sizeof(BGRecord), 1, BGRecord_fields },
    { "Stack", "#Stack", sizeof(BGStack), 3, BGStack_fields },
    { "Tap", "#Tap", sizeof(BGTap), 2, BGTap_fields },
    { "Trace", "#Trace", sizeof(BGTrace), 8, BGTrace_fields },
    { "Valve", "#Valve", sizeof(BGValve), 3, BGValve_fields },
    { "WaterStore", "#WaterStore", sizeof(BGWaterStore), 2, BGWaterStore_fields },
    { "Fastener", "#Fastener", sizeof(BGFastener), 1, BGFastener_fields },
    { 0 }
};

#endif

#endif
