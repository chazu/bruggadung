/* Generated from Triangle content 9a92831ffbe239e8: do not edit. Type IDs are valid
 * only for this content; regenerate when it changes. */
#ifndef BG_COMPONENTS_H
#define BG_COMPONENTS_H

#include <stdbool.h>
#include <stdint.h>

#define BG_CONTENT_HASH 0x9a92831ffbe239e8ULL

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
    int64_t         toolMarks;    /* int, in quanta of 1; saved, proposable, inspect, perceive(sight) */
} BGBody;

/* Agent, from #Agent */
typedef struct {
    int64_t         hands;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
} BGAgent;

/* Assembly, from #Assembly */
typedef struct {
    int64_t         slots;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
} BGAssembly;

/* Container, from #Container */
typedef struct {
    int64_t         capacity;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
} BGContainer;

/* Stack, from #Stack */
typedef struct {
    int64_t         count;    /* int, in quanta of 1; content, saved, proposable, inspect */
    const char *    unit;    /* text; content, saved, inspect, perceive(sight) */
    int64_t         unitMass;    /* mass, in quanta of 1g; content, saved, inspect */
} BGStack;

/* #ClaimKind */
enum {
    BG_CLAIMKIND_CUSTODY = 26,
    BG_CLAIMKIND_OWNERSHIP = 27,
};

/* #Material */
enum {
    BG_MATERIAL_BRASS = 34,
    BG_MATERIAL_FLESH = 35,
    BG_MATERIAL_IRON = 36,
    BG_MATERIAL_OAK = 37,
    BG_MATERIAL_PAPER = 38,
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

#define BG_COMPONENT_COUNT 6

#ifdef BG_COMPONENT_REGISTRY

static const BGFieldInfo BGClaim_fields[] = {
    { "kind", offsetof(BGClaim, kind), BG_VALUE_TYPE, "#ClaimKind", "content, saved, inspect" },
    { "quantity", offsetof(BGClaim, quantity), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGBody_fields[] = {
    { "bent", offsetof(BGBody, bent), BG_VALUE_BOOL, "bool", "saved, proposable, inspect, perceive(sight)" },
    { "mass", offsetof(BGBody, mass), BG_VALUE_QUANTITY, "mass", "content, saved, proposable, inspect, perceive(touch)" },
    { "material", offsetof(BGBody, material), BG_VALUE_TYPE, "#Material", "content, saved, inspect, perceive(sight)" },
    { "toolMarks", offsetof(BGBody, toolMarks), BG_VALUE_QUANTITY, "int", "saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGAgent_fields[] = {
    { "hands", offsetof(BGAgent, hands), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGAssembly_fields[] = {
    { "slots", offsetof(BGAssembly, slots), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGContainer_fields[] = {
    { "capacity", offsetof(BGContainer, capacity), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGStack_fields[] = {
    { "count", offsetof(BGStack, count), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "unit", offsetof(BGStack, unit), BG_VALUE_TEXT, "text", "content, saved, inspect, perceive(sight)" },
    { "unitMass", offsetof(BGStack, unitMass), BG_VALUE_QUANTITY, "mass", "content, saved, inspect" },
};

static const BGComponentInfo BGComponents[BG_COMPONENT_COUNT + 1] = {
    { "Claim", "#Claim", sizeof(BGClaim), 2, BGClaim_fields },
    { "Body", "#Body", sizeof(BGBody), 4, BGBody_fields },
    { "Agent", "#Agent", sizeof(BGAgent), 1, BGAgent_fields },
    { "Assembly", "#Assembly", sizeof(BGAssembly), 1, BGAssembly_fields },
    { "Container", "#Container", sizeof(BGContainer), 1, BGContainer_fields },
    { "Stack", "#Stack", sizeof(BGStack), 3, BGStack_fields },
    { 0 }
};

#endif

#endif
