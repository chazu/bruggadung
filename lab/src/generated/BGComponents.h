/* Generated from Triangle content 15e78bc8998edd9e: do not edit. Type IDs are valid
 * only for this content; regenerate when it changes. */
#ifndef BG_COMPONENTS_H
#define BG_COMPONENTS_H

#include <stdbool.h>
#include <stdint.h>

#define BG_CONTENT_HASH 0x15e78bc8998edd9eULL

typedef struct TriNode TriNode;

/* Combustor, from #Combustor */
typedef struct {
    int64_t         burnRate;    /* int, in quanta of 1; content, saved, inspect */
    bool            damper;    /* bool; content, saved, proposable, inspect, perceive(sight) */
    bool            lit;    /* bool; content, saved, proposable, inspect, perceive(sight) */
} BGCombustor;

/* FuelContainer, from #FuelContainer */
typedef struct {
    int64_t         fuel;    /* mass, in quanta of 1g; content, saved, proposable, inspect */
} BGFuelContainer;

/* GasStore, from #GasStore */
typedef struct {
    int64_t         dioxide;    /* int, in quanta of 1; content, saved, proposable, inspect */
    uint64_t        door;    /* a referent; saved, proposable, inspect */
    int64_t         east;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         gap;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         gasHeat;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         north;    /* int, in quanta of 1; content, saved, inspect */
    uint64_t        opensTo;    /* a referent; saved, proposable, inspect */
    int64_t         oxygen;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         south;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         total;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         west;    /* int, in quanta of 1; content, saved, inspect */
} BGGasStore;

/* Lever, from #Lever */
typedef struct {
    int64_t         leverage;    /* length, in quanta of 0.1mm; content, saved, inspect, perceive(sight) */
    int64_t         limit;    /* torque, in quanta of 0.001Nm; content, saved, proposable, inspect */
    bool            sleeve;    /* bool; content, saved, inspect, perceive(sight) */
} BGLever;

/* OfficeHolder, from #OfficeHolder */
typedef struct {
    uint64_t        office;    /* a referent; saved, proposable, inspect */
} BGOfficeHolder;

/* Respirator, from #Respirator */
typedef struct {
    int64_t         atRest;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         atWork;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         restsAbove;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         restsBelow;    /* int, in quanta of 1; content, saved, proposable, inspect */
} BGRespirator;

/* Scribe, from #Scribe */
typedef struct {
    const char *    handwriting;    /* text; saved, proposable, inspect */
} BGScribe;

/* Sized, from #Sized */
typedef struct {
    int64_t         size;    /* length, in quanta of 0.1mm; content, saved, inspect, perceive(sight) */
} BGSized;

/* ThermalBody, from #ThermalBody */
typedef struct {
    uint64_t        bounds;    /* a referent; saved, proposable, inspect */
    int64_t         heat;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         heatCapacity;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         toAir;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         toOutdoors;    /* int, in quanta of 1; content, saved, inspect */
} BGThermalBody;

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
    int64_t         watchCool;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         watchDioxide;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         watchFloor;    /* int, in quanta of 1; content, saved, proposable, inspect */
    uint64_t        watchHolder;    /* a referent; saved, proposable, inspect */
    int64_t         watchLevel;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         watchWarm;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         watchX;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         watchY;    /* int, in quanta of 1; content, saved, proposable, inspect */
} BGActivity;

/* Authorization, from #Authorization */
typedef struct {
    uint64_t        grantee;    /* a referent; saved, proposable, inspect */
    const char *    grants;    /* text; saved, proposable, inspect */
    uint64_t        over;    /* a referent; saved, proposable, inspect */
} BGAuthorization;

/* Claim, from #Claim */
typedef struct {
    uint32_t        kind;    /* #ClaimKind: a type ID; content, saved, inspect */
    int64_t         quantity;    /* int, in quanta of 1; content, saved, proposable, inspect */
} BGClaim;

/* Information, from #Content */
typedef struct {
    const char *    issuer;    /* text; saved, proposable, inspect */
    const char *    text;    /* text; saved, proposable, inspect */
} BGInformation;

/* Organization, from #Organization */
typedef struct {
    const char *    orgName;    /* text; saved, proposable, inspect */
} BGOrganization;

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
    int64_t         adrenaline;    /* int, in quanta of 1; content, saved, proposable, inspect */
    uint32_t        coat;    /* #Colour: a type ID; content, saved, proposable, inspect, perceive(sight) */
    int64_t         curious;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         fatigue;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         fed;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         fedAt;    /* time, in quanta of 1ms; content, saved, proposable, inspect */
    int64_t         grip;    /* force, in quanta of 0.001N; content, saved, inspect */
    int64_t         hands;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
    int64_t         helpful;    /* int, in quanta of 1; content, saved, proposable, inspect */
    bool            hiding;    /* bool; content, saved, proposable, inspect */
    int64_t         honesty;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         injury;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         memory;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         numbness;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         painting;    /* int, in quanta of 1; content, saved, inspect */
    int64_t         quickness;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         respectful;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         riskTolerance;    /* int, in quanta of 1; content, saved, proposable, inspect */
    int64_t         scruples;    /* int, in quanta of 1; content, saved, proposable, inspect */
} BGAgent;

/* Assembly, from #Assembly */
typedef struct {
    int64_t         slots;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
} BGAssembly;

/* Cock, from #Cock */
typedef struct {
    const char *    serves;    /* text; content, saved, inspect */
    bool            shut;    /* bool; content, saved, proposable, inspect, perceive(sight) */
} BGCock;

/* Container, from #Container */
typedef struct {
    int64_t         capacity;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
} BGContainer;

/* Inscription, from #Copy */
typedef struct {
    const char *    claims;    /* text; saved, proposable, inspect, perceive(sight) */
    int64_t         fidelity;    /* int, in quanta of 1; content, saved, proposable, inspect */
    const char *    impression;    /* text; saved, proposable, inspect, perceive(sight) */
    uint64_t        inscribed;    /* a referent; saved, proposable, inspect */
    const char *    penned;    /* text; saved, proposable, inspect, perceive(sight) */
    const char *    reads;    /* text; saved, proposable, inspect, perceive(sight) */
} BGInscription;

/* Door, from #Door */
typedef struct {
    bool            ajar;    /* bool; content, saved, proposable, inspect, perceive(sight) */
    int64_t         wide;    /* int, in quanta of 1; content, saved, inspect */
} BGDoor;

/* Lamp, from #Lamp */
typedef struct {
    int64_t         reach;    /* int, in quanta of 1; content, saved, inspect */
    bool            shining;    /* bool; content, saved, proposable, inspect, perceive(sight) */
} BGLamp;

/* Latent, from #Latent */
typedef struct {
    int64_t         failedAt;    /* time, in quanta of 1ms; content, saved, proposable, inspect */
    const char *    failure;    /* text; saved, proposable, inspect */
    const TriNode * latent;    /* #LatentSchema: a structure */
    bool            leaking;    /* bool; content, saved, proposable, inspect */
    int64_t         revealed;    /* int, in quanta of 1; content, saved, proposable, inspect */
    uint64_t        riser;    /* a referent; saved, proposable, inspect */
} BGLatent;

/* Log, from #Log */
typedef struct {
    int64_t         sawn;    /* int, in quanta of 1; content, saved, proposable, inspect, perceive(sight) */
} BGLog;

/* Part, from #Part */
typedef struct {
    uint64_t        cameFrom;    /* a referent; saved, proposable, inspect */
    bool            detached;    /* bool; content, saved, proposable, inspect */
    const char *    fits;    /* text; saved, proposable, inspect, perceive(sight) */
    int64_t         wear;    /* int, in quanta of 1; content, saved, proposable, inspect, perceive(sight) */
} BGPart;

/* Pump, from #Pump */
typedef struct {
    int64_t         flow;    /* int, in quanta of 1; content, saved, proposable, inspect */
    bool            opened;    /* bool; content, saved, proposable, inspect, perceive(sight) */
} BGPump;

/* Record, from #Record */
typedef struct {
    const char *    writing;    /* text; saved, proposable, inspect */
} BGRecord;

/* Label, from #Label */
typedef struct {
    int64_t         legible;    /* int, in quanta of 1; content, saved, inspect, perceive(sight) */
} BGLabel;

/* Stack, from #Stack */
typedef struct {
    int64_t         count;    /* int, in quanta of 1; content, saved, proposable, inspect */
    const char *    unit;    /* text; content, saved, inspect, perceive(sight) */
    int64_t         unitMass;    /* mass, in quanta of 1g; content, saved, inspect */
} BGStack;

/* Stamp, from #Stamp */
typedef struct {
    const char *    presses;    /* text; saved, proposable, inspect, perceive(sight) */
    const char *    sealOf;    /* text; saved, proposable, inspect, perceive(sight) */
} BGStamp;

/* Tap, from #Tap */
typedef struct {
    bool            open;    /* bool; content, saved, proposable, inspect, perceive(sight) */
    int64_t         rate;    /* int, in quanta of 1; content, saved, proposable, inspect */
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
    BG_ACTIVITYSTATUS_ABORTED = 318,
    BG_ACTIVITYSTATUS_COMPLETED = 319,
    BG_ACTIVITYSTATUS_EXHAUSTED = 320,
    BG_ACTIVITYSTATUS_FAILED = 321,
    BG_ACTIVITYSTATUS_RUNNING = 322,
    BG_ACTIVITYSTATUS_SUSPENDED = 323,
};

/* #ClaimKind */
enum {
    BG_CLAIMKIND_CUSTODY = 325,
    BG_CLAIMKIND_OWNERSHIP = 326,
    BG_CLAIMKIND_RESERVATION = 327,
};

/* #Material */
enum {
    BG_MATERIAL_CLOTH = 377,
    BG_MATERIAL_FOOD = 378,
    BG_MATERIAL_LEATHER = 379,
    BG_MATERIAL_RUBBER = 380,
    BG_MATERIAL_STONE = 381,
    BG_MATERIAL_FLESH = 407,
    BG_MATERIAL_BRASS = 409,
    BG_MATERIAL_IRON = 410,
    BG_MATERIAL_PAPER = 411,
    BG_MATERIAL_STEEL = 412,
    BG_MATERIAL_OAK = 414,
};

/* "flesh" | "metal" | "natural" | "paper" | "wood" */
enum {
    BG_BODY_SURFACE_NATURAL = 255,
    BG_BODY_SURFACE_FLESH = 407,
    BG_BODY_SURFACE_BRASS = 409,
    BG_BODY_SURFACE_IRON = 410,
    BG_BODY_SURFACE_PAPER = 411,
    BG_BODY_SURFACE_STEEL = 412,
    BG_BODY_SURFACE_OAK = 414,
};

/* #Colour */
enum {
    BG_COLOUR_BLUE = 330,
    BG_COLOUR_BLACK = 332,
    BG_COLOUR_BROWN = 333,
    BG_COLOUR_GREEN = 334,
    BG_COLOUR_GREY = 335,
    BG_COLOUR_NAVY = 336,
    BG_COLOUR_RED = 337,
    BG_COLOUR_YELLOW = 338,
    BG_COLOUR_BEIGE = 352,
    BG_COLOUR_WHITE = 374,
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

#define BG_COMPONENT_COUNT 35

#ifdef BG_COMPONENT_REGISTRY

static const BGFieldInfo BGCombustor_fields[] = {
    { "burnRate", offsetof(BGCombustor, burnRate), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "damper", offsetof(BGCombustor, damper), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
    { "lit", offsetof(BGCombustor, lit), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGFuelContainer_fields[] = {
    { "fuel", offsetof(BGFuelContainer, fuel), BG_VALUE_QUANTITY, "mass", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGGasStore_fields[] = {
    { "dioxide", offsetof(BGGasStore, dioxide), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "door", offsetof(BGGasStore, door), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "east", offsetof(BGGasStore, east), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "gap", offsetof(BGGasStore, gap), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "gasHeat", offsetof(BGGasStore, gasHeat), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "north", offsetof(BGGasStore, north), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "opensTo", offsetof(BGGasStore, opensTo), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "oxygen", offsetof(BGGasStore, oxygen), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "south", offsetof(BGGasStore, south), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "total", offsetof(BGGasStore, total), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "west", offsetof(BGGasStore, west), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
};

static const BGFieldInfo BGLever_fields[] = {
    { "leverage", offsetof(BGLever, leverage), BG_VALUE_QUANTITY, "length", "content, saved, inspect, perceive(sight)" },
    { "limit", offsetof(BGLever, limit), BG_VALUE_QUANTITY, "torque", "content, saved, proposable, inspect" },
    { "sleeve", offsetof(BGLever, sleeve), BG_VALUE_BOOL, "bool", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGOfficeHolder_fields[] = {
    { "office", offsetof(BGOfficeHolder, office), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
};

static const BGFieldInfo BGRespirator_fields[] = {
    { "atRest", offsetof(BGRespirator, atRest), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "atWork", offsetof(BGRespirator, atWork), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "restsAbove", offsetof(BGRespirator, restsAbove), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "restsBelow", offsetof(BGRespirator, restsBelow), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGScribe_fields[] = {
    { "handwriting", offsetof(BGScribe, handwriting), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
};

static const BGFieldInfo BGSized_fields[] = {
    { "size", offsetof(BGSized, size), BG_VALUE_QUANTITY, "length", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGThermalBody_fields[] = {
    { "bounds", offsetof(BGThermalBody, bounds), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "heat", offsetof(BGThermalBody, heat), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "heatCapacity", offsetof(BGThermalBody, heatCapacity), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "toAir", offsetof(BGThermalBody, toAir), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "toOutdoors", offsetof(BGThermalBody, toOutdoors), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
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
    { "watchCool", offsetof(BGActivity, watchCool), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "watchDioxide", offsetof(BGActivity, watchDioxide), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "watchFloor", offsetof(BGActivity, watchFloor), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "watchHolder", offsetof(BGActivity, watchHolder), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "watchLevel", offsetof(BGActivity, watchLevel), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "watchWarm", offsetof(BGActivity, watchWarm), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "watchX", offsetof(BGActivity, watchX), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "watchY", offsetof(BGActivity, watchY), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGAuthorization_fields[] = {
    { "grantee", offsetof(BGAuthorization, grantee), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "grants", offsetof(BGAuthorization, grants), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
    { "over", offsetof(BGAuthorization, over), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
};

static const BGFieldInfo BGClaim_fields[] = {
    { "kind", offsetof(BGClaim, kind), BG_VALUE_TYPE, "#ClaimKind", "content, saved, inspect" },
    { "quantity", offsetof(BGClaim, quantity), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGInformation_fields[] = {
    { "issuer", offsetof(BGInformation, issuer), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
    { "text", offsetof(BGInformation, text), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
};

static const BGFieldInfo BGOrganization_fields[] = {
    { "orgName", offsetof(BGOrganization, orgName), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
};

static const BGFieldInfo BGBody_fields[] = {
    { "bent", offsetof(BGBody, bent), BG_VALUE_BOOL, "bool", "saved, proposable, inspect, perceive(sight)" },
    { "mass", offsetof(BGBody, mass), BG_VALUE_QUANTITY, "mass", "content, saved, proposable, inspect, perceive(touch)" },
    { "material", offsetof(BGBody, material), BG_VALUE_TYPE, "#Material", "content, saved, inspect, perceive(sight)" },
    { "surface", offsetof(BGBody, surface), BG_VALUE_TYPE, "\"flesh\" | \"metal\" | \"natural\" | \"paper\" | \"wood\"", "content, saved, inspect, appears(material)" },
    { "toolMarks", offsetof(BGBody, toolMarks), BG_VALUE_QUANTITY, "int", "saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGAgent_fields[] = {
    { "adrenaline", offsetof(BGAgent, adrenaline), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "coat", offsetof(BGAgent, coat), BG_VALUE_TYPE, "#Colour", "content, saved, proposable, inspect, perceive(sight)" },
    { "curious", offsetof(BGAgent, curious), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "fatigue", offsetof(BGAgent, fatigue), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "fed", offsetof(BGAgent, fed), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "fedAt", offsetof(BGAgent, fedAt), BG_VALUE_QUANTITY, "time", "content, saved, proposable, inspect" },
    { "grip", offsetof(BGAgent, grip), BG_VALUE_QUANTITY, "force", "content, saved, inspect" },
    { "hands", offsetof(BGAgent, hands), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
    { "helpful", offsetof(BGAgent, helpful), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "hiding", offsetof(BGAgent, hiding), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect" },
    { "honesty", offsetof(BGAgent, honesty), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "injury", offsetof(BGAgent, injury), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "memory", offsetof(BGAgent, memory), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "numbness", offsetof(BGAgent, numbness), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "painting", offsetof(BGAgent, painting), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "quickness", offsetof(BGAgent, quickness), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "respectful", offsetof(BGAgent, respectful), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "riskTolerance", offsetof(BGAgent, riskTolerance), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "scruples", offsetof(BGAgent, scruples), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
};

static const BGFieldInfo BGAssembly_fields[] = {
    { "slots", offsetof(BGAssembly, slots), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGCock_fields[] = {
    { "serves", offsetof(BGCock, serves), BG_VALUE_TEXT, "text", "content, saved, inspect" },
    { "shut", offsetof(BGCock, shut), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGContainer_fields[] = {
    { "capacity", offsetof(BGContainer, capacity), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGInscription_fields[] = {
    { "claims", offsetof(BGInscription, claims), BG_VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)" },
    { "fidelity", offsetof(BGInscription, fidelity), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "impression", offsetof(BGInscription, impression), BG_VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)" },
    { "inscribed", offsetof(BGInscription, inscribed), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "penned", offsetof(BGInscription, penned), BG_VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)" },
    { "reads", offsetof(BGInscription, reads), BG_VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGDoor_fields[] = {
    { "ajar", offsetof(BGDoor, ajar), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
    { "wide", offsetof(BGDoor, wide), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
};

static const BGFieldInfo BGLamp_fields[] = {
    { "reach", offsetof(BGLamp, reach), BG_VALUE_QUANTITY, "int", "content, saved, inspect" },
    { "shining", offsetof(BGLamp, shining), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGLatent_fields[] = {
    { "failedAt", offsetof(BGLatent, failedAt), BG_VALUE_QUANTITY, "time", "content, saved, proposable, inspect" },
    { "failure", offsetof(BGLatent, failure), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
    { "latent", offsetof(BGLatent, latent), BG_VALUE_NODE, "#LatentSchema", "" },
    { "leaking", offsetof(BGLatent, leaking), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect" },
    { "revealed", offsetof(BGLatent, revealed), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "riser", offsetof(BGLatent, riser), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
};

static const BGFieldInfo BGLog_fields[] = {
    { "sawn", offsetof(BGLog, sawn), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGPart_fields[] = {
    { "cameFrom", offsetof(BGPart, cameFrom), BG_VALUE_REF, "ref", "saved, proposable, inspect" },
    { "detached", offsetof(BGPart, detached), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect" },
    { "fits", offsetof(BGPart, fits), BG_VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)" },
    { "wear", offsetof(BGPart, wear), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGPump_fields[] = {
    { "flow", offsetof(BGPump, flow), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "opened", offsetof(BGPump, opened), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGRecord_fields[] = {
    { "writing", offsetof(BGRecord, writing), BG_VALUE_TEXT, "text", "saved, proposable, inspect" },
};

static const BGFieldInfo BGLabel_fields[] = {
    { "legible", offsetof(BGLabel, legible), BG_VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)" },
};

static const BGFieldInfo BGStack_fields[] = {
    { "count", offsetof(BGStack, count), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
    { "unit", offsetof(BGStack, unit), BG_VALUE_TEXT, "text", "content, saved, inspect, perceive(sight)" },
    { "unitMass", offsetof(BGStack, unitMass), BG_VALUE_QUANTITY, "mass", "content, saved, inspect" },
};

static const BGFieldInfo BGStamp_fields[] = {
    { "presses", offsetof(BGStamp, presses), BG_VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)" },
    { "sealOf", offsetof(BGStamp, sealOf), BG_VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)" },
};

static const BGFieldInfo BGTap_fields[] = {
    { "open", offsetof(BGTap, open), BG_VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)" },
    { "rate", offsetof(BGTap, rate), BG_VALUE_QUANTITY, "int", "content, saved, proposable, inspect" },
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
    { "Combustor", "#Combustor", sizeof(BGCombustor), 3, BGCombustor_fields },
    { "FuelContainer", "#FuelContainer", sizeof(BGFuelContainer), 1, BGFuelContainer_fields },
    { "GasStore", "#GasStore", sizeof(BGGasStore), 11, BGGasStore_fields },
    { "Lever", "#Lever", sizeof(BGLever), 3, BGLever_fields },
    { "OfficeHolder", "#OfficeHolder", sizeof(BGOfficeHolder), 1, BGOfficeHolder_fields },
    { "Respirator", "#Respirator", sizeof(BGRespirator), 4, BGRespirator_fields },
    { "Scribe", "#Scribe", sizeof(BGScribe), 1, BGScribe_fields },
    { "Sized", "#Sized", sizeof(BGSized), 1, BGSized_fields },
    { "ThermalBody", "#ThermalBody", sizeof(BGThermalBody), 5, BGThermalBody_fields },
    { "Activity", "#Activity", sizeof(BGActivity), 19, BGActivity_fields },
    { "Authorization", "#Authorization", sizeof(BGAuthorization), 3, BGAuthorization_fields },
    { "Claim", "#Claim", sizeof(BGClaim), 2, BGClaim_fields },
    { "Information", "#Content", sizeof(BGInformation), 2, BGInformation_fields },
    { "Organization", "#Organization", sizeof(BGOrganization), 1, BGOrganization_fields },
    { "Body", "#Body", sizeof(BGBody), 5, BGBody_fields },
    { "Agent", "#Agent", sizeof(BGAgent), 19, BGAgent_fields },
    { "Assembly", "#Assembly", sizeof(BGAssembly), 1, BGAssembly_fields },
    { "Cock", "#Cock", sizeof(BGCock), 2, BGCock_fields },
    { "Container", "#Container", sizeof(BGContainer), 1, BGContainer_fields },
    { "Inscription", "#Copy", sizeof(BGInscription), 6, BGInscription_fields },
    { "Door", "#Door", sizeof(BGDoor), 2, BGDoor_fields },
    { "Lamp", "#Lamp", sizeof(BGLamp), 2, BGLamp_fields },
    { "Latent", "#Latent", sizeof(BGLatent), 6, BGLatent_fields },
    { "Log", "#Log", sizeof(BGLog), 1, BGLog_fields },
    { "Part", "#Part", sizeof(BGPart), 4, BGPart_fields },
    { "Pump", "#Pump", sizeof(BGPump), 2, BGPump_fields },
    { "Record", "#Record", sizeof(BGRecord), 1, BGRecord_fields },
    { "Label", "#Label", sizeof(BGLabel), 1, BGLabel_fields },
    { "Stack", "#Stack", sizeof(BGStack), 3, BGStack_fields },
    { "Stamp", "#Stamp", sizeof(BGStamp), 2, BGStamp_fields },
    { "Tap", "#Tap", sizeof(BGTap), 2, BGTap_fields },
    { "Trace", "#Trace", sizeof(BGTrace), 8, BGTrace_fields },
    { "Valve", "#Valve", sizeof(BGValve), 3, BGValve_fields },
    { "WaterStore", "#WaterStore", sizeof(BGWaterStore), 2, BGWaterStore_fields },
    { "Fastener", "#Fastener", sizeof(BGFastener), 1, BGFastener_fields },
    { 0 }
};

#endif

#endif
