// Generated from Triangle content d929ae1e94c66905: do not edit. Type IDs are valid
// only for this content; regenerate when it changes.
package lab

import tri "../../triangle/odin/triangle"

CONTENT_HASH :: 0xd929ae1e94c66905

// Combustor, from #Combustor
Combustor :: struct {
	burnRate: i64,    // int, in quanta of 1; content, saved, inspect
	damper: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
	lit: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
}

// FuelContainer, from #FuelContainer
Fuel_Container :: struct {
	fuel: i64,    // mass, in quanta of 1g; content, saved, proposable, inspect, perceive(sight)
}

// GasStore, from #GasStore
Gas_Store :: struct {
	atLevel: i64,    // int, in quanta of 1; content, saved, inspect
	atX: i64,    // int, in quanta of 1; content, saved, inspect
	atY: i64,    // int, in quanta of 1; content, saved, inspect
	dioxide: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	gap: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	gasHeat: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	oxygen: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	total: i64,    // int, in quanta of 1; content, saved, inspect
}

// Hungry, from #Hungry
Hungry :: struct {
	emptiesIn: i64,    // time, in quanta of 1ms; content, saved, inspect
	fedAt: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	harmsEvery: i64,    // time, in quanta of 1ms; content, saved, inspect
	lastsFor: i64,    // time, in quanta of 1ms; content, saved, inspect
	refillsIn: i64,    // time, in quanta of 1ms; content, saved, inspect
	reserves: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	satiety: i64,    // int, in quanta of 1; content, saved, proposable, inspect
}

// Lever, from #Lever
Lever :: struct {
	leverage: i64,    // length, in quanta of 0.1mm; content, saved, inspect, perceive(sight)
	limit: i64,    // torque, in quanta of 0.001Nm; content, saved, proposable, inspect
	sleeve: bool,    // bool; content, saved, inspect, perceive(sight)
}

// OfficeHolder, from #OfficeHolder
Office_Holder :: struct {
	badge: cstring,    // text; content, saved, proposable, inspect, perceive(sight)
	office: u64,    // a referent; saved, proposable, inspect
}

// Perishable, from #Perishable
Perishable :: struct {
	keepsFor: i64,    // time, in quanta of 1ms; content, saved, inspect
	spoiled: cstring,    // text; content, saved, inspect
	spoilsAt: i64,    // time, in quanta of 1ms; saved, proposable, inspect
}

// Food, from #Food
Food :: struct {
	cooking: i64,    // int, in quanta of 1; content, saved, inspect
	keptAs: cstring,    // text; content, saved, inspect
	mealKeepsFor: i64,    // time, in quanta of 1ms; content, saved, inspect
	nourishment: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	raw: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
}

// Respirator, from #Respirator
Respirator :: struct {
	atRest: i64,    // int, in quanta of 1; content, saved, inspect
	atWork: i64,    // int, in quanta of 1; content, saved, inspect
	restsAbove: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	restsBelow: i64,    // int, in quanta of 1; content, saved, proposable, inspect
}

// Scribe, from #Scribe
Scribe :: struct {
	handwriting: cstring,    // text; saved, proposable, inspect
}

// Seed, from #Seed
Seed :: struct {
	sows: cstring,    // text; content, saved, inspect, perceive(sight)
}

// Sized, from #Sized
Sized :: struct {
	size: i64,    // length, in quanta of 0.1mm; content, saved, inspect, perceive(sight)
}

// ThermalBody, from #ThermalBody
Thermal_Body :: struct {
	bounds: u64,    // a referent; saved, proposable, inspect
	heat: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	heatCapacity: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	toAir: i64,    // int, in quanta of 1; content, saved, inspect
	toOutdoors: i64,    // int, in quanta of 1; content, saved, inspect
}

// Activity, from #Activity
Activity :: struct {
	actorRef: u64,    // a referent; saved, proposable, inspect
	amount: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	destinationRef: u64,    // a referent; saved, proposable, inspect
	due: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect, debug
	itemRef: u64,    // a referent; saved, proposable, inspect
	operation: cstring,    // text; saved, proposable, inspect
	pace: i64,    // int, in quanta of 1; content, saved, proposable, inspect, debug
	progress: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect, debug
	stage: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	started: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect, debug
	status: u32,    // #ActivityStatus: a type ID; content, saved, proposable, inspect
	watchAtLeast: i64,    // volume, in quanta of 1mL; content, saved, proposable, inspect
	watchCool: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	watchDioxide: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	watchFloor: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	watchHolder: u64,    // a referent; saved, proposable, inspect
	watchLevel: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	watchWarm: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	watchX: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	watchY: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	way: cstring,    // text; saved, proposable, inspect
	words: cstring,    // text; saved, proposable, inspect
}

// Authorization, from #Authorization
Authorization :: struct {
	grantee: u64,    // a referent; saved, proposable, inspect
	grants: cstring,    // text; saved, proposable, inspect
	over: u64,    // a referent; saved, proposable, inspect
}

// Bond, from #Bond
Bond :: struct {
	bondOf: u64,    // a referent; saved, proposable, inspect
	loyalty: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	tie: u32,    // #Tie: a type ID; content, saved, inspect
	toward: u64,    // a referent; saved, proposable, inspect
}

// Claim, from #Claim
Claim :: struct {
	kind: u32,    // #ClaimKind: a type ID; content, saved, inspect
	quantity: i64,    // int, in quanta of 1; content, saved, proposable, inspect
}

// Information, from #Content
Information :: struct {
	issuer: cstring,    // text; saved, proposable, inspect
	text: cstring,    // text; saved, proposable, inspect
}

// Law, from #Law
Law :: struct {
	brings: u32,    // #Penalty: a type ID; content, saved, inspect
	common: bool,    // bool; content, saved, inspect
	forbids: cstring,    // text; content, saved, proposable, inspect
	lawOf: u64,    // a referent; saved, proposable, inspect
	weighs: i64,    // int, in quanta of 1; content, saved, inspect
	wrong: u32,    // #Wrong: a type ID; content, saved, inspect
}

// Organization, from #Organization
Organization :: struct {
	orgName: cstring,    // text; saved, proposable, inspect
}

// Body, from #Body
Body :: struct {
	bent: bool,    // bool; saved, proposable, inspect, perceive(sight)
	mass: i64,    // mass, in quanta of 1g; content, saved, proposable, inspect, perceive(touch)
	material: u32,    // #Material: a type ID; content, saved, inspect, perceive(sight)
	surface: u32,    // "flesh" | "metal" | "natural" | "paper" | "wood": a type ID; content, saved, inspect, appears(material)
	toolMarks: i64,    // int, in quanta of 1; saved, proposable, inspect, perceive(sight)
}

// Agent, from #Agent
Agent :: struct {
	abiding: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	adrenaline: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	coat: u32,    // #Colour: a type ID; content, saved, proposable, inspect, perceive(sight)
	curious: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	diligent: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	fatigue: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	generosity: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	gentle: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	grip: i64,    // force, in quanta of 0.001N; content, saved, inspect
	hands: i64,    // int, in quanta of 1; content, saved, inspect, perceive(sight)
	helpful: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	hiding: bool,    // bool; content, saved, proposable, inspect
	hires: cstring,    // text; content, saved, proposable, inspect
	honesty: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	injury: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	instinct: cstring,    // text; content, saved, inspect
	memory: i64,    // int, in quanta of 1; content, saved, inspect
	numbness: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	painting: i64,    // int, in quanta of 1; content, saved, inspect
	patience: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	pride: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	quickness: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	reciprocity: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	remains: cstring,    // text; content, saved, inspect
	respectful: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	riskTolerance: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	scruples: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	shrewdness: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	stalking: i64,    // int, in quanta of 1; content, saved, inspect
	temper: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	trade: cstring,    // text; content, saved, proposable, inspect
	trusting: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	wary: i64,    // int, in quanta of 1; content, saved, inspect
}

// Area, from #Area
Area :: struct {
	east: i64,    // int, in quanta of 1; content, saved, proposable, inspect, perceive(sight)
	south: i64,    // int, in quanta of 1; content, saved, proposable, inspect, perceive(sight)
}

// Assembly, from #Assembly
Assembly :: struct {
	slots: i64,    // int, in quanta of 1; content, saved, inspect, perceive(sight)
}

// Bow, from #Bow
Bow :: struct {
	aim: i64,    // int, in quanta of 1; content, saved, inspect
	spread: i64,    // int, in quanta of 1; content, saved, inspect
	wounds: i64,    // int, in quanta of 1; content, saved, inspect
}

// Cock, from #Cock
Cock :: struct {
	serves: cstring,    // text; content, saved, inspect
	shut: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
}

// Container, from #Container
Container :: struct {
	capacity: i64,    // int, in quanta of 1; content, saved, inspect, perceive(sight)
}

// Inscription, from #Copy
Inscription :: struct {
	claims: cstring,    // text; saved, proposable, inspect, perceive(sight)
	fidelity: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	impression: cstring,    // text; saved, proposable, inspect, perceive(sight)
	inscribed: u64,    // a referent; saved, proposable, inspect
	penned: cstring,    // text; saved, proposable, inspect, perceive(sight)
	reads: cstring,    // text; saved, proposable, inspect, perceive(sight)
}

// Door, from #Door
Door :: struct {
	ajar: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
	wide: i64,    // int, in quanta of 1; content, saved, inspect
}

// HandSaw, from #HandSaw
Hand_Saw :: struct {
	sharpness: i64,    // int, in quanta of 1; content, saved, proposable, inspect, perceive(sight)
}

// Lamp, from #Lamp
Lamp :: struct {
	oil: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	oilAt: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	reach: i64,    // int, in quanta of 1; content, saved, inspect
	shining: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
}

// Latent, from #Latent
Latent :: struct {
	abused: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	blamed: cstring,    // text; saved, proposable, inspect
	failedAt: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	failure: cstring,    // text; saved, proposable, inspect
	latent: ^tri.Node,    // #LatentSchema: a structure
	leaking: bool,    // bool; content, saved, proposable, inspect
	revealed: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	riser: u64,    // a referent; saved, proposable, inspect
	used: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
}

// Log, from #Log
Log :: struct {
	finish: i64,    // int, in quanta of 1; content, saved, proposable, inspect, perceive(sight)
	hardness: i64,    // int, in quanta of 1; content, saved, inspect
	sawn: i64,    // int, in quanta of 1; content, saved, proposable, inspect, perceive(sight)
	splitsInto: cstring,    // text; content, saved, inspect
}

// Pack, from #Pack
Pack :: struct {
	load: i64,    // mass, in quanta of 1g; content, saved, inspect, perceive(sight)
	worn: bool,    // bool; content, saved, inspect, perceive(sight)
}

// Part, from #Part
Part :: struct {
	attrition: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	cameFrom: u64,    // a referent; saved, proposable, inspect
	detached: bool,    // bool; content, saved, proposable, inspect
	fits: cstring,    // text; saved, proposable, inspect, perceive(sight)
	grade: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	tended: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	wear: i64,    // int, in quanta of 1; content, saved, proposable, inspect, perceive(sight)
}

// Patch, from #Patch
Patch :: struct {
	grewAt: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	handfuls: i64,    // int, in quanta of 1; content, saved, proposable, inspect, perceive(sight)
	most: i64,    // int, in quanta of 1; content, saved, inspect
	regrowsIn: i64,    // time, in quanta of 1ms; content, saved, inspect
	yields: cstring,    // text; content, saved, inspect
}

// Plot, from #Plot
Plot :: struct {
	grows: cstring,    // text; content, saved, inspect, perceive(sight)
	kept: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
	reaped: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	ripensIn: i64,    // time, in quanta of 1ms; content, saved, inspect
	sown: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	sownAt: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	stands: u32,    // "bare" | "ripe" | "sown": a type ID; content, saved, proposable, inspect, perceive(sight)
	yields: cstring,    // text; content, saved, inspect
}

// Pump, from #Pump
Pump :: struct {
	draws: u64,    // a referent; saved, proposable, inspect
	flow: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	lift: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	opened: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
}

// Record, from #Record
Record :: struct {
	writing: cstring,    // text; saved, proposable, inspect
}

// Label, from #Label
Label :: struct {
	legible: i64,    // int, in quanta of 1; content, saved, inspect, perceive(sight)
}

// Stack, from #Stack
Stack :: struct {
	count: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	unit: cstring,    // text; content, saved, inspect, perceive(sight)
	unitMass: i64,    // mass, in quanta of 1g; content, saved, inspect
}

// Stamp, from #Stamp
Stamp :: struct {
	presses: cstring,    // text; saved, proposable, inspect, perceive(sight)
	sealOf: cstring,    // text; saved, proposable, inspect, perceive(sight)
}

// Tap, from #Tap
Tap :: struct {
	open: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
	rate: i64,    // int, in quanta of 1; content, saved, proposable, inspect
}

// Trace, from #Trace
Trace :: struct {
	bearer: u64,    // a referent; saved, proposable, inspect
	created: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	expires: i64,    // time, in quanta of 1ms; content, saved, proposable, inspect
	magnitude: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	tileLevel: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	tileX: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	tileY: i64,    // int, in quanta of 1; content, saved, proposable, inspect
	traceKind: cstring,    // text; content, saved, proposable, inspect
}

// Tree, from #Tree
Tree :: struct {
	fellsInto: cstring,    // text; content, saved, inspect
}

// Trunk, from #Trunk
Trunk :: struct {
	cutsInto: cstring,    // text; content, saved, inspect
	lengths: i64,    // int, in quanta of 1; content, saved, proposable, inspect, perceive(sight)
}

// Valve, from #Valve
Valve :: struct {
	breakaway: i64,    // torque, in quanta of 0.001Nm; content, saved, proposable, inspect
	rating: i64,    // torque, in quanta of 0.001Nm; content, saved, inspect, perceive(sight)
	turned: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
}

// WaterStore, from #WaterStore
Water_Store :: struct {
	water: i64,    // volume, in quanta of 1mL; content, saved, proposable, inspect, perceive(sight)
	waterCapacity: i64,    // volume, in quanta of 1mL; content, saved, inspect, perceive(sight)
}

// Carcass, from #Carcass
Carcass :: struct {
	cuts: i64,    // int, in quanta of 1; content, saved, inspect
	hide: cstring,    // text; content, saved, inspect
	yields: cstring,    // text; content, saved, inspect
}

// Fastener, from #Fastener
Fastener :: struct {
	tight: bool,    // bool; content, saved, proposable, inspect, perceive(sight)
}

// #ActivityStatus
ACTIVITYSTATUS_ABORTED :: 981
ACTIVITYSTATUS_COMPLETED :: 982
ACTIVITYSTATUS_EXHAUSTED :: 983
ACTIVITYSTATUS_FAILED :: 984
ACTIVITYSTATUS_RUNNING :: 985
ACTIVITYSTATUS_SUSPENDED :: 986

// #Tie
TIE_EMPLOY :: 1079
TIE_FRIEND :: 1080
TIE_KIN :: 1081
TIE_SWORN :: 1082

// #ClaimKind
CLAIMKIND_CUSTODY :: 988
CLAIMKIND_OWNERSHIP :: 989
CLAIMKIND_RESERVATION :: 990

// #Penalty
PENALTY_FINE :: 1065
PENALTY_ARREST :: 1098
PENALTY_CONFISCATE :: 1099

// #Wrong
WRONG_ANOTHERS :: 1090
WRONG_UNAUTHORIZED :: 1091

// #Material
MATERIAL_CLOTH :: 1044
MATERIAL_EARTH :: 1045
MATERIAL_FOOD :: 1046
MATERIAL_LEATHER :: 1047
MATERIAL_GRAIN :: 1049
MATERIAL_ROT :: 1050
MATERIAL_RUBBER :: 1051
MATERIAL_STONE :: 1052
MATERIAL_TURNIP :: 1053
MATERIAL_WICKER :: 1054
MATERIAL_FLESH :: 1101
MATERIAL_BRASS :: 1103
MATERIAL_IRON :: 1104
MATERIAL_PAPER :: 1105
MATERIAL_STEEL :: 1106
MATERIAL_BIRCH :: 1108
MATERIAL_OAK :: 1109

// "flesh" | "metal" | "natural" | "paper" | "wood"
BODY_SURFACE_NATURAL :: 720
BODY_SURFACE_FLESH :: 1101
BODY_SURFACE_BRASS :: 1103
BODY_SURFACE_IRON :: 1104
BODY_SURFACE_PAPER :: 1105
BODY_SURFACE_STEEL :: 1106
BODY_SURFACE_BIRCH :: 1108
BODY_SURFACE_OAK :: 1109

// #Colour
COLOUR_BLUE :: 993
COLOUR_BLACK :: 995
COLOUR_BROWN :: 996
COLOUR_GREEN :: 997
COLOUR_GREY :: 998
COLOUR_BEIGE :: 1000
COLOUR_NAVY :: 1001
COLOUR_ORANGE :: 1002
COLOUR_PURPLE :: 1003
COLOUR_RED :: 1004
COLOUR_WHITE :: 1005
COLOUR_YELLOW :: 1006

// "bare" | "ripe" | "sown"
PLOT_STANDS_BARE :: 442
PLOT_STANDS_RIPE :: 801
PLOT_STANDS_SOWN :: 836

// The field registry: what code needs to read and write any component
// generically.

VALUE_QUANTITY :: 0
VALUE_TYPE :: 1
VALUE_TEXT :: 2
VALUE_REF :: 3
VALUE_BOOL :: 4
VALUE_NODE :: 5

Field_Info :: struct {
	name:   cstring,    // the feature
	offset: uintptr,
	value:  i32,        // VALUE_...
	kind:   cstring,    // a quantity kind, an enum's type name, or a structure's type
	flags:  cstring,    // from @field
}

Component_Info :: struct {
	name:    cstring,    // the component
	type:    cstring,    // its Triangle type
	size:    uint,
	nfields: uint,
	fields:  [^]Field_Info,
}

COMPONENT_COUNT :: 50

@(rodata) Combustor_fields := [?]Field_Info{
	{"burnRate", offset_of(Combustor, burnRate), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"damper", offset_of(Combustor, damper), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
	{"lit", offset_of(Combustor, lit), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Fuel_Container_fields := [?]Field_Info{
	{"fuel", offset_of(Fuel_Container, fuel), VALUE_QUANTITY, "mass", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Gas_Store_fields := [?]Field_Info{
	{"atLevel", offset_of(Gas_Store, atLevel), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"atX", offset_of(Gas_Store, atX), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"atY", offset_of(Gas_Store, atY), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"dioxide", offset_of(Gas_Store, dioxide), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"gap", offset_of(Gas_Store, gap), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"gasHeat", offset_of(Gas_Store, gasHeat), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"oxygen", offset_of(Gas_Store, oxygen), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"total", offset_of(Gas_Store, total), VALUE_QUANTITY, "int", "content, saved, inspect"},
}
@(rodata) Hungry_fields := [?]Field_Info{
	{"emptiesIn", offset_of(Hungry, emptiesIn), VALUE_QUANTITY, "time", "content, saved, inspect"},
	{"fedAt", offset_of(Hungry, fedAt), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"harmsEvery", offset_of(Hungry, harmsEvery), VALUE_QUANTITY, "time", "content, saved, inspect"},
	{"lastsFor", offset_of(Hungry, lastsFor), VALUE_QUANTITY, "time", "content, saved, inspect"},
	{"refillsIn", offset_of(Hungry, refillsIn), VALUE_QUANTITY, "time", "content, saved, inspect"},
	{"reserves", offset_of(Hungry, reserves), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"satiety", offset_of(Hungry, satiety), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
}
@(rodata) Lever_fields := [?]Field_Info{
	{"leverage", offset_of(Lever, leverage), VALUE_QUANTITY, "length", "content, saved, inspect, perceive(sight)"},
	{"limit", offset_of(Lever, limit), VALUE_QUANTITY, "torque", "content, saved, proposable, inspect"},
	{"sleeve", offset_of(Lever, sleeve), VALUE_BOOL, "bool", "content, saved, inspect, perceive(sight)"},
}
@(rodata) Office_Holder_fields := [?]Field_Info{
	{"badge", offset_of(Office_Holder, badge), VALUE_TEXT, "text", "content, saved, proposable, inspect, perceive(sight)"},
	{"office", offset_of(Office_Holder, office), VALUE_REF, "ref", "saved, proposable, inspect"},
}
@(rodata) Perishable_fields := [?]Field_Info{
	{"keepsFor", offset_of(Perishable, keepsFor), VALUE_QUANTITY, "time", "content, saved, inspect"},
	{"spoiled", offset_of(Perishable, spoiled), VALUE_TEXT, "text", "content, saved, inspect"},
	{"spoilsAt", offset_of(Perishable, spoilsAt), VALUE_QUANTITY, "time", "saved, proposable, inspect"},
}
@(rodata) Food_fields := [?]Field_Info{
	{"cooking", offset_of(Food, cooking), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"keptAs", offset_of(Food, keptAs), VALUE_TEXT, "text", "content, saved, inspect"},
	{"mealKeepsFor", offset_of(Food, mealKeepsFor), VALUE_QUANTITY, "time", "content, saved, inspect"},
	{"nourishment", offset_of(Food, nourishment), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"raw", offset_of(Food, raw), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Respirator_fields := [?]Field_Info{
	{"atRest", offset_of(Respirator, atRest), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"atWork", offset_of(Respirator, atWork), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"restsAbove", offset_of(Respirator, restsAbove), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"restsBelow", offset_of(Respirator, restsBelow), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
}
@(rodata) Scribe_fields := [?]Field_Info{
	{"handwriting", offset_of(Scribe, handwriting), VALUE_TEXT, "text", "saved, proposable, inspect"},
}
@(rodata) Seed_fields := [?]Field_Info{
	{"sows", offset_of(Seed, sows), VALUE_TEXT, "text", "content, saved, inspect, perceive(sight)"},
}
@(rodata) Sized_fields := [?]Field_Info{
	{"size", offset_of(Sized, size), VALUE_QUANTITY, "length", "content, saved, inspect, perceive(sight)"},
}
@(rodata) Thermal_Body_fields := [?]Field_Info{
	{"bounds", offset_of(Thermal_Body, bounds), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"heat", offset_of(Thermal_Body, heat), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"heatCapacity", offset_of(Thermal_Body, heatCapacity), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"toAir", offset_of(Thermal_Body, toAir), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"toOutdoors", offset_of(Thermal_Body, toOutdoors), VALUE_QUANTITY, "int", "content, saved, inspect"},
}
@(rodata) Activity_fields := [?]Field_Info{
	{"actorRef", offset_of(Activity, actorRef), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"amount", offset_of(Activity, amount), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"destinationRef", offset_of(Activity, destinationRef), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"due", offset_of(Activity, due), VALUE_QUANTITY, "time", "content, saved, proposable, inspect, debug"},
	{"itemRef", offset_of(Activity, itemRef), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"operation", offset_of(Activity, operation), VALUE_TEXT, "text", "saved, proposable, inspect"},
	{"pace", offset_of(Activity, pace), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, debug"},
	{"progress", offset_of(Activity, progress), VALUE_QUANTITY, "time", "content, saved, proposable, inspect, debug"},
	{"stage", offset_of(Activity, stage), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"started", offset_of(Activity, started), VALUE_QUANTITY, "time", "content, saved, proposable, inspect, debug"},
	{"status", offset_of(Activity, status), VALUE_TYPE, "#ActivityStatus", "content, saved, proposable, inspect"},
	{"watchAtLeast", offset_of(Activity, watchAtLeast), VALUE_QUANTITY, "volume", "content, saved, proposable, inspect"},
	{"watchCool", offset_of(Activity, watchCool), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"watchDioxide", offset_of(Activity, watchDioxide), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"watchFloor", offset_of(Activity, watchFloor), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"watchHolder", offset_of(Activity, watchHolder), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"watchLevel", offset_of(Activity, watchLevel), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"watchWarm", offset_of(Activity, watchWarm), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"watchX", offset_of(Activity, watchX), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"watchY", offset_of(Activity, watchY), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"way", offset_of(Activity, way), VALUE_TEXT, "text", "saved, proposable, inspect"},
	{"words", offset_of(Activity, words), VALUE_TEXT, "text", "saved, proposable, inspect"},
}
@(rodata) Authorization_fields := [?]Field_Info{
	{"grantee", offset_of(Authorization, grantee), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"grants", offset_of(Authorization, grants), VALUE_TEXT, "text", "saved, proposable, inspect"},
	{"over", offset_of(Authorization, over), VALUE_REF, "ref", "saved, proposable, inspect"},
}
@(rodata) Bond_fields := [?]Field_Info{
	{"bondOf", offset_of(Bond, bondOf), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"loyalty", offset_of(Bond, loyalty), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"tie", offset_of(Bond, tie), VALUE_TYPE, "#Tie", "content, saved, inspect"},
	{"toward", offset_of(Bond, toward), VALUE_REF, "ref", "saved, proposable, inspect"},
}
@(rodata) Claim_fields := [?]Field_Info{
	{"kind", offset_of(Claim, kind), VALUE_TYPE, "#ClaimKind", "content, saved, inspect"},
	{"quantity", offset_of(Claim, quantity), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
}
@(rodata) Information_fields := [?]Field_Info{
	{"issuer", offset_of(Information, issuer), VALUE_TEXT, "text", "saved, proposable, inspect"},
	{"text", offset_of(Information, text), VALUE_TEXT, "text", "saved, proposable, inspect"},
}
@(rodata) Law_fields := [?]Field_Info{
	{"brings", offset_of(Law, brings), VALUE_TYPE, "#Penalty", "content, saved, inspect"},
	{"common", offset_of(Law, common), VALUE_BOOL, "bool", "content, saved, inspect"},
	{"forbids", offset_of(Law, forbids), VALUE_TEXT, "text", "content, saved, proposable, inspect"},
	{"lawOf", offset_of(Law, lawOf), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"weighs", offset_of(Law, weighs), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"wrong", offset_of(Law, wrong), VALUE_TYPE, "#Wrong", "content, saved, inspect"},
}
@(rodata) Organization_fields := [?]Field_Info{
	{"orgName", offset_of(Organization, orgName), VALUE_TEXT, "text", "saved, proposable, inspect"},
}
@(rodata) Body_fields := [?]Field_Info{
	{"bent", offset_of(Body, bent), VALUE_BOOL, "bool", "saved, proposable, inspect, perceive(sight)"},
	{"mass", offset_of(Body, mass), VALUE_QUANTITY, "mass", "content, saved, proposable, inspect, perceive(touch)"},
	{"material", offset_of(Body, material), VALUE_TYPE, "#Material", "content, saved, inspect, perceive(sight)"},
	{"surface", offset_of(Body, surface), VALUE_TYPE, "\"flesh\" | \"metal\" | \"natural\" | \"paper\" | \"wood\"", "content, saved, inspect, appears(material)"},
	{"toolMarks", offset_of(Body, toolMarks), VALUE_QUANTITY, "int", "saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Agent_fields := [?]Field_Info{
	{"abiding", offset_of(Agent, abiding), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"adrenaline", offset_of(Agent, adrenaline), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"coat", offset_of(Agent, coat), VALUE_TYPE, "#Colour", "content, saved, proposable, inspect, perceive(sight)"},
	{"curious", offset_of(Agent, curious), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"diligent", offset_of(Agent, diligent), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"fatigue", offset_of(Agent, fatigue), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"generosity", offset_of(Agent, generosity), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"gentle", offset_of(Agent, gentle), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"grip", offset_of(Agent, grip), VALUE_QUANTITY, "force", "content, saved, inspect"},
	{"hands", offset_of(Agent, hands), VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)"},
	{"helpful", offset_of(Agent, helpful), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"hiding", offset_of(Agent, hiding), VALUE_BOOL, "bool", "content, saved, proposable, inspect"},
	{"hires", offset_of(Agent, hires), VALUE_TEXT, "text", "content, saved, proposable, inspect"},
	{"honesty", offset_of(Agent, honesty), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"injury", offset_of(Agent, injury), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"instinct", offset_of(Agent, instinct), VALUE_TEXT, "text", "content, saved, inspect"},
	{"memory", offset_of(Agent, memory), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"numbness", offset_of(Agent, numbness), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"painting", offset_of(Agent, painting), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"patience", offset_of(Agent, patience), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"pride", offset_of(Agent, pride), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"quickness", offset_of(Agent, quickness), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"reciprocity", offset_of(Agent, reciprocity), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"remains", offset_of(Agent, remains), VALUE_TEXT, "text", "content, saved, inspect"},
	{"respectful", offset_of(Agent, respectful), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"riskTolerance", offset_of(Agent, riskTolerance), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"scruples", offset_of(Agent, scruples), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"shrewdness", offset_of(Agent, shrewdness), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"stalking", offset_of(Agent, stalking), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"temper", offset_of(Agent, temper), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"trade", offset_of(Agent, trade), VALUE_TEXT, "text", "content, saved, proposable, inspect"},
	{"trusting", offset_of(Agent, trusting), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"wary", offset_of(Agent, wary), VALUE_QUANTITY, "int", "content, saved, inspect"},
}
@(rodata) Area_fields := [?]Field_Info{
	{"east", offset_of(Area, east), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)"},
	{"south", offset_of(Area, south), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Assembly_fields := [?]Field_Info{
	{"slots", offset_of(Assembly, slots), VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)"},
}
@(rodata) Bow_fields := [?]Field_Info{
	{"aim", offset_of(Bow, aim), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"spread", offset_of(Bow, spread), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"wounds", offset_of(Bow, wounds), VALUE_QUANTITY, "int", "content, saved, inspect"},
}
@(rodata) Cock_fields := [?]Field_Info{
	{"serves", offset_of(Cock, serves), VALUE_TEXT, "text", "content, saved, inspect"},
	{"shut", offset_of(Cock, shut), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Container_fields := [?]Field_Info{
	{"capacity", offset_of(Container, capacity), VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)"},
}
@(rodata) Inscription_fields := [?]Field_Info{
	{"claims", offset_of(Inscription, claims), VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)"},
	{"fidelity", offset_of(Inscription, fidelity), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"impression", offset_of(Inscription, impression), VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)"},
	{"inscribed", offset_of(Inscription, inscribed), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"penned", offset_of(Inscription, penned), VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)"},
	{"reads", offset_of(Inscription, reads), VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Door_fields := [?]Field_Info{
	{"ajar", offset_of(Door, ajar), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
	{"wide", offset_of(Door, wide), VALUE_QUANTITY, "int", "content, saved, inspect"},
}
@(rodata) Hand_Saw_fields := [?]Field_Info{
	{"sharpness", offset_of(Hand_Saw, sharpness), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Lamp_fields := [?]Field_Info{
	{"oil", offset_of(Lamp, oil), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"oilAt", offset_of(Lamp, oilAt), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"reach", offset_of(Lamp, reach), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"shining", offset_of(Lamp, shining), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Latent_fields := [?]Field_Info{
	{"abused", offset_of(Latent, abused), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"blamed", offset_of(Latent, blamed), VALUE_TEXT, "text", "saved, proposable, inspect"},
	{"failedAt", offset_of(Latent, failedAt), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"failure", offset_of(Latent, failure), VALUE_TEXT, "text", "saved, proposable, inspect"},
	{"latent", offset_of(Latent, latent), VALUE_NODE, "#LatentSchema", ""},
	{"leaking", offset_of(Latent, leaking), VALUE_BOOL, "bool", "content, saved, proposable, inspect"},
	{"revealed", offset_of(Latent, revealed), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"riser", offset_of(Latent, riser), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"used", offset_of(Latent, used), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
}
@(rodata) Log_fields := [?]Field_Info{
	{"finish", offset_of(Log, finish), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)"},
	{"hardness", offset_of(Log, hardness), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"sawn", offset_of(Log, sawn), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)"},
	{"splitsInto", offset_of(Log, splitsInto), VALUE_TEXT, "text", "content, saved, inspect"},
}
@(rodata) Pack_fields := [?]Field_Info{
	{"load", offset_of(Pack, load), VALUE_QUANTITY, "mass", "content, saved, inspect, perceive(sight)"},
	{"worn", offset_of(Pack, worn), VALUE_BOOL, "bool", "content, saved, inspect, perceive(sight)"},
}
@(rodata) Part_fields := [?]Field_Info{
	{"attrition", offset_of(Part, attrition), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"cameFrom", offset_of(Part, cameFrom), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"detached", offset_of(Part, detached), VALUE_BOOL, "bool", "content, saved, proposable, inspect"},
	{"fits", offset_of(Part, fits), VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)"},
	{"grade", offset_of(Part, grade), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"tended", offset_of(Part, tended), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"wear", offset_of(Part, wear), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Patch_fields := [?]Field_Info{
	{"grewAt", offset_of(Patch, grewAt), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"handfuls", offset_of(Patch, handfuls), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)"},
	{"most", offset_of(Patch, most), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"regrowsIn", offset_of(Patch, regrowsIn), VALUE_QUANTITY, "time", "content, saved, inspect"},
	{"yields", offset_of(Patch, yields), VALUE_TEXT, "text", "content, saved, inspect"},
}
@(rodata) Plot_fields := [?]Field_Info{
	{"grows", offset_of(Plot, grows), VALUE_TEXT, "text", "content, saved, inspect, perceive(sight)"},
	{"kept", offset_of(Plot, kept), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
	{"reaped", offset_of(Plot, reaped), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"ripensIn", offset_of(Plot, ripensIn), VALUE_QUANTITY, "time", "content, saved, inspect"},
	{"sown", offset_of(Plot, sown), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"sownAt", offset_of(Plot, sownAt), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"stands", offset_of(Plot, stands), VALUE_TYPE, "\"bare\" | \"ripe\" | \"sown\"", "content, saved, proposable, inspect, perceive(sight)"},
	{"yields", offset_of(Plot, yields), VALUE_TEXT, "text", "content, saved, inspect"},
}
@(rodata) Pump_fields := [?]Field_Info{
	{"draws", offset_of(Pump, draws), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"flow", offset_of(Pump, flow), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"lift", offset_of(Pump, lift), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"opened", offset_of(Pump, opened), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Record_fields := [?]Field_Info{
	{"writing", offset_of(Record, writing), VALUE_TEXT, "text", "saved, proposable, inspect"},
}
@(rodata) Label_fields := [?]Field_Info{
	{"legible", offset_of(Label, legible), VALUE_QUANTITY, "int", "content, saved, inspect, perceive(sight)"},
}
@(rodata) Stack_fields := [?]Field_Info{
	{"count", offset_of(Stack, count), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"unit", offset_of(Stack, unit), VALUE_TEXT, "text", "content, saved, inspect, perceive(sight)"},
	{"unitMass", offset_of(Stack, unitMass), VALUE_QUANTITY, "mass", "content, saved, inspect"},
}
@(rodata) Stamp_fields := [?]Field_Info{
	{"presses", offset_of(Stamp, presses), VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)"},
	{"sealOf", offset_of(Stamp, sealOf), VALUE_TEXT, "text", "saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Tap_fields := [?]Field_Info{
	{"open", offset_of(Tap, open), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
	{"rate", offset_of(Tap, rate), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
}
@(rodata) Trace_fields := [?]Field_Info{
	{"bearer", offset_of(Trace, bearer), VALUE_REF, "ref", "saved, proposable, inspect"},
	{"created", offset_of(Trace, created), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"expires", offset_of(Trace, expires), VALUE_QUANTITY, "time", "content, saved, proposable, inspect"},
	{"magnitude", offset_of(Trace, magnitude), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"tileLevel", offset_of(Trace, tileLevel), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"tileX", offset_of(Trace, tileX), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"tileY", offset_of(Trace, tileY), VALUE_QUANTITY, "int", "content, saved, proposable, inspect"},
	{"traceKind", offset_of(Trace, traceKind), VALUE_TEXT, "text", "content, saved, proposable, inspect"},
}
@(rodata) Tree_fields := [?]Field_Info{
	{"fellsInto", offset_of(Tree, fellsInto), VALUE_TEXT, "text", "content, saved, inspect"},
}
@(rodata) Trunk_fields := [?]Field_Info{
	{"cutsInto", offset_of(Trunk, cutsInto), VALUE_TEXT, "text", "content, saved, inspect"},
	{"lengths", offset_of(Trunk, lengths), VALUE_QUANTITY, "int", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Valve_fields := [?]Field_Info{
	{"breakaway", offset_of(Valve, breakaway), VALUE_QUANTITY, "torque", "content, saved, proposable, inspect"},
	{"rating", offset_of(Valve, rating), VALUE_QUANTITY, "torque", "content, saved, inspect, perceive(sight)"},
	{"turned", offset_of(Valve, turned), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
}
@(rodata) Water_Store_fields := [?]Field_Info{
	{"water", offset_of(Water_Store, water), VALUE_QUANTITY, "volume", "content, saved, proposable, inspect, perceive(sight)"},
	{"waterCapacity", offset_of(Water_Store, waterCapacity), VALUE_QUANTITY, "volume", "content, saved, inspect, perceive(sight)"},
}
@(rodata) Carcass_fields := [?]Field_Info{
	{"cuts", offset_of(Carcass, cuts), VALUE_QUANTITY, "int", "content, saved, inspect"},
	{"hide", offset_of(Carcass, hide), VALUE_TEXT, "text", "content, saved, inspect"},
	{"yields", offset_of(Carcass, yields), VALUE_TEXT, "text", "content, saved, inspect"},
}
@(rodata) Fastener_fields := [?]Field_Info{
	{"tight", offset_of(Fastener, tight), VALUE_BOOL, "bool", "content, saved, proposable, inspect, perceive(sight)"},
}

COMPONENTS := [COMPONENT_COUNT + 1]Component_Info{
	{"Combustor", "#Combustor", size_of(Combustor), 3, &Combustor_fields[0]},
	{"FuelContainer", "#FuelContainer", size_of(Fuel_Container), 1, &Fuel_Container_fields[0]},
	{"GasStore", "#GasStore", size_of(Gas_Store), 8, &Gas_Store_fields[0]},
	{"Hungry", "#Hungry", size_of(Hungry), 7, &Hungry_fields[0]},
	{"Lever", "#Lever", size_of(Lever), 3, &Lever_fields[0]},
	{"OfficeHolder", "#OfficeHolder", size_of(Office_Holder), 2, &Office_Holder_fields[0]},
	{"Perishable", "#Perishable", size_of(Perishable), 3, &Perishable_fields[0]},
	{"Food", "#Food", size_of(Food), 5, &Food_fields[0]},
	{"Respirator", "#Respirator", size_of(Respirator), 4, &Respirator_fields[0]},
	{"Scribe", "#Scribe", size_of(Scribe), 1, &Scribe_fields[0]},
	{"Seed", "#Seed", size_of(Seed), 1, &Seed_fields[0]},
	{"Sized", "#Sized", size_of(Sized), 1, &Sized_fields[0]},
	{"ThermalBody", "#ThermalBody", size_of(Thermal_Body), 5, &Thermal_Body_fields[0]},
	{"Activity", "#Activity", size_of(Activity), 22, &Activity_fields[0]},
	{"Authorization", "#Authorization", size_of(Authorization), 3, &Authorization_fields[0]},
	{"Bond", "#Bond", size_of(Bond), 4, &Bond_fields[0]},
	{"Claim", "#Claim", size_of(Claim), 2, &Claim_fields[0]},
	{"Information", "#Content", size_of(Information), 2, &Information_fields[0]},
	{"Law", "#Law", size_of(Law), 6, &Law_fields[0]},
	{"Organization", "#Organization", size_of(Organization), 1, &Organization_fields[0]},
	{"Body", "#Body", size_of(Body), 5, &Body_fields[0]},
	{"Agent", "#Agent", size_of(Agent), 33, &Agent_fields[0]},
	{"Area", "#Area", size_of(Area), 2, &Area_fields[0]},
	{"Assembly", "#Assembly", size_of(Assembly), 1, &Assembly_fields[0]},
	{"Bow", "#Bow", size_of(Bow), 3, &Bow_fields[0]},
	{"Cock", "#Cock", size_of(Cock), 2, &Cock_fields[0]},
	{"Container", "#Container", size_of(Container), 1, &Container_fields[0]},
	{"Inscription", "#Copy", size_of(Inscription), 6, &Inscription_fields[0]},
	{"Door", "#Door", size_of(Door), 2, &Door_fields[0]},
	{"HandSaw", "#HandSaw", size_of(Hand_Saw), 1, &Hand_Saw_fields[0]},
	{"Lamp", "#Lamp", size_of(Lamp), 4, &Lamp_fields[0]},
	{"Latent", "#Latent", size_of(Latent), 9, &Latent_fields[0]},
	{"Log", "#Log", size_of(Log), 4, &Log_fields[0]},
	{"Pack", "#Pack", size_of(Pack), 2, &Pack_fields[0]},
	{"Part", "#Part", size_of(Part), 7, &Part_fields[0]},
	{"Patch", "#Patch", size_of(Patch), 5, &Patch_fields[0]},
	{"Plot", "#Plot", size_of(Plot), 8, &Plot_fields[0]},
	{"Pump", "#Pump", size_of(Pump), 4, &Pump_fields[0]},
	{"Record", "#Record", size_of(Record), 1, &Record_fields[0]},
	{"Label", "#Label", size_of(Label), 1, &Label_fields[0]},
	{"Stack", "#Stack", size_of(Stack), 3, &Stack_fields[0]},
	{"Stamp", "#Stamp", size_of(Stamp), 2, &Stamp_fields[0]},
	{"Tap", "#Tap", size_of(Tap), 2, &Tap_fields[0]},
	{"Trace", "#Trace", size_of(Trace), 8, &Trace_fields[0]},
	{"Tree", "#Tree", size_of(Tree), 1, &Tree_fields[0]},
	{"Trunk", "#Trunk", size_of(Trunk), 2, &Trunk_fields[0]},
	{"Valve", "#Valve", size_of(Valve), 3, &Valve_fields[0]},
	{"WaterStore", "#WaterStore", size_of(Water_Store), 2, &Water_Store_fields[0]},
	{"Carcass", "#Carcass", size_of(Carcass), 3, &Carcass_fields[0]},
	{"Fastener", "#Fastener", size_of(Fastener), 1, &Fastener_fields[0]},
	{},
}
