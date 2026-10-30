#import "BGActions.h"

#import "BGBodies.h"

#import "BGView.h"
#import "BGProposalGroup.h"
#import "BGKnowledge.h"

#include <stdlib.h>


const char   *BGRoleNames[ BGRoleCount] =
{
   "actor",
   "item",
   "destination"
};


/* --- matching ---------------------------------------------------------------- */

/* Which roles an operation has: the features of its roles' type. */
static BOOL   has_role( TriContent *tri, const TriNode *pattern, BGRole role)
{
   char   path[ 32];

   snprintf( path, sizeof( path), "roles.%s", BGRoleNames[ role]);
   return( tri_at( tri, pattern, path) != NULL);
}


/* NO when the entity's type is strictly more general than the role's: in a
 * description its type would leave the role open, but its kind is perceived. */
static BOOL   kind_fits( BGWorld *world, const TriNode *pattern, BGRole role, BGEntityID entity)
{
   const BGEntityInfo   *info;
   const TriNode        *filler;
   const TriNode        *blueprint;
   TriContent           *tri;
   TriType              wanted;
   TriType              kind;
   char                 path[ 32];

   tri  = [world tri];
   info = [world info:entity];
   snprintf( path, sizeof( path), "roles.%s", BGRoleNames[ role]);
   filler    = tri_at( tri, pattern, path);
   blueprint = info ? tri_pattern( tri, info->blueprint) : NULL;
   if( ! filler || ! blueprint)
      return( YES);
   wanted = tri_node_type( filler);
   kind   = tri_node_type( blueprint);
   return( ! (kind != wanted && tri_subtype( tri, wanted, kind)));
}


/* Matches an operation against its roles' descriptions. */
static TriMatch   match_described( BGWorld *world, const TriNode *pattern, BGAction action, NSString **descriptions,
                                   TriMatchResult *result, NSString **reason)
{
   const TriNode     *description;
   NSMutableString   *expr;
   TriContent        *tri;
   TriArena          *arena;
   TriMatch          match;
   static const char *copied[] = { "duration", "stages", "uses", "attention", "leaves", "removes", NULL };
   char              value[ 1024];
   char              effect[ 64];
   char              err[ 256];
   int               r;
   int               k;

   tri = [world tri];
   tri_print( tri, tri_at( tri, pattern, "effect"), effect, sizeof( effect));
   /* the operation's own type: a walk is a #Walk, an operation by its kind;
    * what the operation itself declares, as it declares it */
   expr = [NSMutableString stringWithFormat:@"%s & { effect: %s, ", tri_type_name( tri, tri_node_type( pattern)), effect];
   for( k = 0; copied[ k]; k++)
      if( tri_at( tri, pattern, copied[ k]))
      {
         tri_print( tri, tri_at( tri, pattern, copied[ k]), value, sizeof( value));
         [expr appendFormat:@"%s: %s, ", copied[ k], value];
      }
   [expr appendString:@"roles: {"];
   for( r = 0; r < BGRoleCount; r++)
      if( descriptions[ r])
         [expr appendFormat:@" %s: %@,", BGRoleNames[ r], descriptions[ r]];
   [expr appendString:@" } }"];
   arena       = tri_arena_new();
   description = tri_value( tri, [expr UTF8String], arena, err, sizeof( err));
   if( ! description)
   {
      if( reason)
         *reason = [NSString stringWithFormat:@"the description does not build: %s, in %@", err, expr];
      tri_arena_free( arena);
      return( TRI_INCOMPATIBLE);
   }
   match = tri_match_instance( tri, action.operation, description, result);
   if( match == TRI_INCOMPATIBLE && reason)
      *reason = [NSString stringWithFormat:@"%s is ruled out at %s", action.operation, result->failure.path];
   tri_arena_free( arena);
   return( match);
}


/* A believed kind more general than a role's isn't one (the same rule as kind_fits). */
static BOOL   believed_kind_fits( BGWorld *world, const TriNode *pattern, BGRole role, const char *kind)
{
   const TriNode   *filler;
   const TriNode   *k;
   TriContent      *tri;
   TriArena        *arena;
   TriType         wanted;
   TriType         have;
   char            path[ 32];
   BOOL            fits;

   tri = [world tri];
   snprintf( path, sizeof( path), "roles.%s", BGRoleNames[ role]);
   filler = tri_at( tri, pattern, path);
   if( ! filler || ! kind)
      return( YES);
   arena = tri_arena_new();
   k     = tri_value( tri, kind, arena, NULL, 0);
   fits  = YES;
   if( k)
   {
      wanted = tri_node_type( filler);
      have   = tri_node_type( k);
      fits   = ! (have != wanted && tri_subtype( tri, wanted, have));
   }
   tri_arena_free( arena);
   return( fits);
}


TriMatch   BGMatchBelieved( BGWorld *world, BGKnowledgeStore *store, BGAction action, TriMatchResult *result,
                            NSString **reason)
{
   const TriNode      *pattern;
   const BGReferent   *me;
   const BGReferent   *ref;
   NSString           *descriptions[ BGRoleCount];
   int                r;

   memset( result, 0, sizeof( *result));
   result->result = TRI_INCOMPATIBLE;
   pattern = action.operation ? tri_pattern( [world tri], action.operation) : NULL;
   if( ! pattern || ! tri_at( [world tri], pattern, "effect"))
   {
      if( reason)
         *reason = [NSString stringWithFormat:@"there is no operation %s", action.operation ? action.operation : "?"];
      return( TRI_INCOMPATIBLE);
   }
   me = [store referent:[store selfReferent]];
   for( r = 0; r < BGRoleCount; r++)
   {
      descriptions[ r] = nil;
      if( ! has_role( [world tri], pattern, (BGRole) r))
         continue;
      ref = [store referent:(uint32_t) action.roles[ r]];
      /* formulate, from the store: the actor is itself; the rest are believed there, in reach */
      if( ! ref || ! me || (r == BGRoleActor) != (ref->id == me->id) || ! ref->present ||
          ref->level != me->level || abs( ref->x - me->x) > 1 || abs( ref->y - me->y) > 1)
      {
         if( reason)
            *reason = [NSString stringWithFormat:@"you don't know of a %s in reach", BGRoleNames[ r]];
         return( TRI_INCOMPATIBLE);
      }
      if( ! believed_kind_fits( world, pattern, (BGRole) r, ref->kind))
      {
         if( reason)
            *reason = [NSString stringWithFormat:@"R%u is not that kind of thing", ref->id];
         return( TRI_INCOMPATIBLE);
      }
      descriptions[ r] = [store describeReferent:ref->id];
   }
   return( match_described( world, pattern, action, descriptions, result, reason));
}


TriMatch   BGMatchAction( BGWorld *world, BGAction action, TriMatchResult *result, NSString **reason)
{
   const TriNode     *pattern;
   TriContent        *tri;
   BGView            *view;
   NSString          *descriptions[ BGRoleCount];
   int               r;

   tri     = [world tri];
   pattern = action.operation ? tri_pattern( tri, action.operation) : NULL;
   memset( result, 0, sizeof( *result));
   result->result = TRI_INCOMPATIBLE;
   if( ! pattern || ! tri_at( tri, pattern, "effect"))
   {
      if( reason)
         *reason = [NSString stringWithFormat:@"there is no operation %s", action.operation ? action.operation : "?"];
      return( TRI_INCOMPATIBLE);
   }
   view = [BGView viewOf:action.roles[ BGRoleActor]
                 inWorld:world];
   for( r = 0; r < BGRoleCount; r++)
   {
      descriptions[ r] = nil;
      if( ! has_role( tri, pattern, (BGRole) r))
         continue;
      /* formulate: the actor can bind only what it can reach, and not itself to another role */
      if( ! action.roles[ r] || ! [view canReach:action.roles[ r]] ||
          (r != BGRoleActor && action.roles[ r] == action.roles[ BGRoleActor]))
      {
         if( reason)
            *reason = [NSString stringWithFormat:@"the %s is not in the actor's reach", BGRoleNames[ r]];
         return( TRI_INCOMPATIBLE);
      }
      /* what kind of thing something is can be seen: a thing more general than the role isn't one */
      if( ! kind_fits( world, pattern, (BGRole) r, action.roles[ r]))
      {
         if( reason)
            *reason = [NSString stringWithFormat:@"the %s %llu is not that kind of thing", BGRoleNames[ r],
                                                 (unsigned long long) action.roles[ r]];
         return( TRI_INCOMPATIBLE);
      }
      descriptions[ r] = [view describeEntity:action.roles[ r]];
   }
   return( match_described( world, pattern, action, descriptions, result, reason));
}


/* --- the menu ---------------------------------------------------------------- */

static int   cmp_string( const void *a, const void *b)
{
   return( strcmp( *(const char *const *) a, *(const char *const *) b));
}


@implementation BGMenu

- (void) dealloc
{
   free( _items);
   free( _matches);
   [_residuals release];
   [super dealloc];
}


- (void) add:(BGAction) action
       match:(TriMatch) match
      result:(TriMatchResult *) result
{
   NSMutableArray   *res;
   size_t           i;

   if( _count == _capacity)
   {
      _capacity = _capacity ? _capacity * 2 : 16;
      _items    = realloc( _items, sizeof( BGAction) * _capacity);
      _matches  = realloc( _matches, sizeof( TriMatch) * _capacity);
   }
   _items[ _count]   = action;
   _matches[ _count] = match;
   res = [NSMutableArray array];
   for( i = 0; i < result->nresidual; i++)
      [res addObject:[NSString stringWithUTF8String:result->residual[ i]]];
   [_residuals addObject:res];
   _count++;
}


+ (instancetype) menuFor:(BGEntityID) actor
                   world:(BGWorld *) world
{
   BGMenu           *menu;
   BGView           *view;
   TriContent       *tri;
   TriIndex         *family;
   TriMatchResult   result;
   TriMatch         match;
   const TriNode    *pattern;
   const char       **ops;
   BGEntityID       reach[ 256];
   BGAction         action;
   NSUInteger       nreach;
   NSUInteger       i;
   NSUInteger       j;
   size_t           nops;
   size_t           o;
   BOOL             item;
   BOOL             destination;

   menu             = [[self new] autorelease];
   menu->_residuals = [NSMutableArray new];
   tri              = [world tri];
   family           = tri_family_index( tri, "operations");
   if( ! family)
      return( menu);
   nops = tri_index_count( family);
   ops  = malloc( sizeof( char *) * (nops ? nops : 1));
   for( o = 0; o < nops; o++)
      ops[ o] = tri_index_tag( family, o);
   qsort( ops, nops, sizeof( char *), cmp_string);
   /* the index has an entry per variant: each operation once */
   for( o = j = 0; o < nops; o++)
      if( ! j || strcmp( ops[ o], ops[ j - 1]))
         ops[ j++] = ops[ o];
   nops = j;

   view   = [BGView viewOf:actor
                   inWorld:world];
   nreach = [view reachable:reach
                        max:256];
   if( nreach > 256)
      nreach = 256;
   for( o = 0; o < nops; o++)
   {
      pattern     = tri_pattern( tri, ops[ o]);
      item        = has_role( tri, pattern, BGRoleItem);
      destination = has_role( tri, pattern, BGRoleDestination);
      /* every binding of the roles it has to entities in reach, in ID order */
      for( i = 0; i < (item ? nreach : 1); i++)
         for( j = 0; j < (destination ? nreach : 1); j++)
         {
            action = BGActionMake( [world intern:ops[ o]], actor,
                                   item ? reach[ i] : BGNoEntity,
                                   destination ? reach[ j] : BGNoEntity);
            if( (item && reach[ i] == actor) || (destination && reach[ j] == actor) ||
                (item && destination && reach[ i] == reach[ j]))
               continue;
            match = BGMatchAction( world, action, &result, NULL);
            if( match != TRI_INCOMPATIBLE)
               [menu add:action
                   match:match
                  result:&result];
         }
   }
   free( ops);
   return( menu);
}


+ (instancetype) menuFor:(BGKnowledgeStore *) store
                   world:(BGWorld *) world
                 believed:(BOOL) believed
{
   BGMenu             *menu;
   TriContent         *tri;
   TriIndex           *family;
   TriMatchResult     result;
   TriMatch           match;
   const TriNode      *pattern;
   const BGReferent   *me;
   const BGReferent   *ref;
   const char         **ops;
   BGEntityID         reach[ 256];
   BGEntityID         actor;
   BGAction           action;
   NSUInteger         nreach;
   NSUInteger         i;
   NSUInteger         j;
   size_t             nops;
   size_t             o;
   BOOL               item;
   BOOL               destination;

   menu             = [[self new] autorelease];
   menu->_residuals = [NSMutableArray new];
   tri              = [world tri];
   family           = tri_family_index( tri, "operations");
   me               = [store referent:[store selfReferent]];
   if( ! family || ! me)
      return( menu);
   actor = me->id;
   nops  = tri_index_count( family);
   ops   = malloc( sizeof( char *) * (nops ? nops : 1));
   for( o = 0; o < nops; o++)
      ops[ o] = tri_index_tag( family, o);
   qsort( ops, nops, sizeof( char *), cmp_string);
   for( o = j = 0; o < nops; o++)
      if( ! j || strcmp( ops[ o], ops[ j - 1]))
         ops[ j++] = ops[ o];
   nops = j;
   /* what the actor believes is here, in reach, by referent */
   nreach = 0;
   for( i = 0; i < [store count] && nreach < 256; i++)
   {
      ref = [store referentAt:i];
      if( ref->present && ref->id != me->id && ref->level == me->level &&
          abs( ref->x - me->x) <= 1 && abs( ref->y - me->y) <= 1)
         reach[ nreach++] = ref->id;
   }
   for( o = 0; o < nops; o++)
   {
      pattern     = tri_pattern( tri, ops[ o]);
      item        = has_role( tri, pattern, BGRoleItem);
      destination = has_role( tri, pattern, BGRoleDestination);
      for( i = 0; i < (item ? nreach : 1); i++)
         for( j = 0; j < (destination ? nreach : 1); j++)
         {
            if( item && destination && reach[ i] == reach[ j])
               continue;
            action = BGActionMake( [world intern:ops[ o]], actor, item ? reach[ i] : BGNoEntity,
                                   destination ? reach[ j] : BGNoEntity);
            match  = BGMatchBelieved( world, store, action, &result, NULL);
            if( match != TRI_INCOMPATIBLE)
               [menu add:action
                   match:match
                  result:&result];
         }
   }
   free( ops);
   menu->_believed = believed;
   return( menu);
}


- (BOOL) believed
{
   return( _believed);
}


- (NSUInteger) count
{
   return( _count);
}


- (const BGAction *) actionAt:(NSUInteger) i
{
   return( &_items[ i]);
}


- (TriMatch) matchAt:(NSUInteger) i
{
   return( _matches[ i]);
}


- (NSArray *) residualsAt:(NSUInteger) i
{
   return( [_residuals objectAtIndex:i]);
}


- (NSString *) describeAt:(NSUInteger) i
{
   NSMutableString   *s;
   int               r;

   s = [NSMutableString stringWithFormat:@"%s", _items[ i].operation];
   for( r = BGRoleItem; r < BGRoleCount; r++)
      if( _items[ i].roles[ r])
         [s appendFormat:_believed ? @" %s R%llu" : @" %s %llu", BGRoleNames[ r], (unsigned long long) _items[ i].roles[ r]];
   [s appendString:_matches[ i] == TRI_ENTAILED ? @": entailed" : @": unknown"];
   if( [[self residualsAt:i] count])
      [s appendFormat:@" (find out %@)", [[self residualsAt:i] componentsJoinedByString:@", "]];
   return( s);
}

@end


/* --- effects ----------------------------------------------------------------- */

typedef NSString   *(*BGEffect)( BGWorld *world, BGAction action, int64_t amount, BGProposalGroup *group);

static NSString   *effect_take( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   int32_t   hand;

   hand = BGFreeHand( world, a.roles[ BGRoleActor]);
   if( hand < 0)
      return( @"no hand is free");
   /* from where it is now: if someone else gets it first, this fails */
   [g move:BGWhole( a.roles[ BGRoleItem]) to:BGHeldBy( a.roles[ BGRoleActor], hand)
 expecting:[world locationOf:a.roles[ BGRoleItem]]];
   return( nil);
}


static NSString   *effect_take_some( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   int32_t   hand;

   if( amount < 1)
      return( @"take how many?");
   hand = BGFreeHand( world, a.roles[ BGRoleActor]);
   if( hand < 0)
      return( @"no hand is free");
   if( amount >= [world unitsOf:a.roles[ BGRoleItem]])
      [g move:BGWhole( a.roles[ BGRoleItem]) to:BGHeldBy( a.roles[ BGRoleActor], hand)];
   else
      [g split:BGWhole( a.roles[ BGRoleItem]) count:amount to:BGHeldBy( a.roles[ BGRoleActor], hand)];
   return( nil);
}


static NSString   *effect_put_in( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g move:BGWhole( a.roles[ BGRoleItem]) to:BGIn( a.roles[ BGRoleDestination])];
   return( nil);
}


/* One nail is driven, even from a stack: the proposal names one unit, and
 * commitment splits it off. */
static NSString   *effect_drive( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   BGEntityID   parts[ 64];
   BGRef        nail;
   NSUInteger   i;
   NSUInteger   n;
   int32_t      index;

   nail  = [world isStack:a.roles[ BGRoleItem]] ? BGUnit( a.roles[ BGRoleItem], 1) : BGWhole( a.roles[ BGRoleItem]);
   n     = [world entitiesAt:a.roles[ BGRoleDestination]
                        form:BGLocationPartOf
                        into:parts
                         max:64];
   index = 0;
   for( i = 0; i < n && i < 64; i++)
      if( ! strcmp( [world locationOf:parts[ i]].role, "wedge"))
         index++;
   [g set:"Body.bent" of:nail to:1];
   [g set:"Body.toolMarks" of:nail to:3];
   [g move:nail to:BGPartOf( a.roles[ BGRoleDestination], "wedge", index)];
   return( nil);
}


static NSString   *effect_open_tap( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g set:"Tap.open" of:BGWhole( a.roles[ BGRoleItem]) to:1];
   return( nil);
}


static NSString   *effect_walk( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   BGLocation   at;
   const char   *direction;

   at        = [world locationOf:a.roles[ BGRoleActor]];
   direction = strchr( a.operation, '_');
   if( at.form != BGLocationOnTile || ! direction)
      return( @"one can walk only on the ground");
   switch( direction[ 1])
   {
   case 'n': at.y--; break;
   case 's': at.y++; break;
   case 'e': at.x++; break;
   case 'w': at.x--; break;
   default:  return( @"walk where?");
   }
   [g move:BGWhole( a.roles[ BGRoleActor]) to:at];
   return( nil);
}


/* A stage of prying: the item works loose, and takes a mark. */
static NSString   *effect_loosen( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   int64_t   marks;

   marks = 0;
   [world getField:"Body.toolMarks" of:a.roles[ BGRoleItem] value:&marks];
   [g set:"Body.toolMarks" of:BGWhole( a.roles[ BGRoleItem]) to:marks + 1];
   return( nil);
}


/* Saying changes nothing in the world either: the "said" event carries the
 * content, and whoever is in earshot perceives it (KNOWLEDGE.md §10). */
static NSString   *effect_say( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   if( ! a.content || ! *a.content)
      return( @"say what?");
   [g emit:"said" subject:BGWhole( a.roles[ BGRoleActor]) other:BGWhole( a.roles[ BGRoleItem]) detail:a.content];
   return( nil);
}


/* An analysis (KNOWLEDGE.md §4): what the actor finds beneath the item's
 * appearance, as the detail of an "analysed" event it perceives: its true
 * material. */
static NSString   *effect_analyse( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGBody   *body;
   char           detail[ 128];

   body = [world record:[world kindNamed:"Body"] for:a.roles[ BGRoleItem]];
   if( ! body)
      return( @"there is nothing there to analyse");
   snprintf( detail, sizeof( detail), "material: %s", tri_type_name( [world tri], body->material));
   [g emit:"analysed" subject:BGWhole( a.roles[ BGRoleActor]) other:BGWhole( a.roles[ BGRoleItem])
    detail:[world intern:detail]];
   return( nil);
}


/* Writing (the copy operation, KNOWLEDGE.md §15): the command's #Writing,
 * its entries appended to what the record holds, under the author it has. */
static NSString   *effect_write( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   NSMutableArray   *entries;
   NSArray          *added;
   NSArray          *old;
   NSString         *author;
   NSString         *was;
   const char       *written;

   if( ! a.content || ! *a.content)
      return( @"write what?");
   author  = nil;
   was     = nil;
   added   = BGWritingEntries( a.content, &author);
   written = [world textField:"Record.writing" of:a.roles[ BGRoleItem]];
   old     = written && *written ? BGWritingEntries( written, &was) : nil;
   if( ! added || ! author)
      return( @"that is not writing");
   entries = [NSMutableArray arrayWithArray:old ? old : [NSArray array]];
   [entries addObjectsFromArray:added];
   [g set:"Record.writing" of:BGWhole( a.roles[ BGRoleItem])
   toText:[world intern:[[NSString stringWithFormat:@"#Writing & { author: %@, entries: [%@] }", was ? was : author,
                                                    [entries componentsJoinedByString:@", "]] UTF8String]]];
   [g emit:"wrote" subject:BGWhole( a.roles[ BGRoleActor]) other:BGWhole( a.roles[ BGRoleItem]) detail:a.content];
   return( nil);
}


/* Reading: an event the reader perceives, carrying what the record holds. */
static NSString   *effect_read( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const char   *written;

   written = [world textField:"Record.writing" of:a.roles[ BGRoleItem]];
   if( ! written || ! *written)
      return( @"nothing is written in it");
   [g emit:"read" subject:BGWhole( a.roles[ BGRoleActor]) other:BGWhole( a.roles[ BGRoleItem]) detail:written];
   return( nil);
}


/* Eating: the food is gone, and the eater is fed, half its stock more. */
static NSString   *effect_eat( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGAgent   *agent;
   int64_t         fed;

   agent = [world record:[world kindNamed:"Agent"] for:a.roles[ BGRoleActor]];
   if( ! agent)
      return( @"only an agent eats");
   fed = BGSatiety( agent, [world time].ms) + 50;
   [g set:"Agent.fed" of:BGWhole( a.roles[ BGRoleActor]) to:fed > 100 ? 100 : fed];
   [g set:"Agent.fedAt" of:BGWhole( a.roles[ BGRoleActor]) to:[world time].ms];
   [g destroy:BGWhole( a.roles[ BGRoleItem]) reason:"eaten"];
   return( nil);
}


/* Giving: into the receiver's free hand. */
static NSString   *effect_give( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   int32_t   hand;

   hand = BGFreeHand( world, a.roles[ BGRoleDestination]);
   if( hand < 0)
      return( @"no hand of theirs is free");
   [g move:BGWhole( a.roles[ BGRoleItem]) to:BGHeldBy( a.roles[ BGRoleDestination], hand)];
   return( nil);
}


/* Investigating changes nothing: it ends in an event the investigator
 * perceives, a close look. */
static NSString   *effect_investigate( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g emit:"investigated" subject:BGWhole( a.roles[ BGRoleActor]) other:BGWhole( a.roles[ BGRoleActor])];
   return( nil);
}


/* Tightening: the nut is tight. */
static NSString   *effect_tighten( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g set:"Fastener.tight" of:BGWhole( a.roles[ BGRoleDestination]) to:1];
   return( nil);
}


/* A trace of wear made by an effect: tool marks on what was used. */
static void   wear( BGWorld *world, BGProposalGroup *g, BGEntityID on, int64_t strength)
{
   BGEntityID   t;

   t = [g create:"trace" key:"tool marks, from use" at:BGLocationMakeNone()];
   [g set:"Trace.traceKind" of:BGWhole( t) toText:[world intern:"tool_marks"]];
   [g set:"Trace.bearer" of:BGWhole( t) to:(int64_t) on];
   [g set:"Trace.magnitude" of:BGWhole( t) to:strength];
   [g set:"Trace.created" of:BGWhole( t) to:[world time].ms];
   [g set:"Trace.expires" of:BGWhole( t) to:[world time].ms + 365 * 86400000LL];
}


/* Turning a valve (ACTIONS.md Scenario 1). The chain is what the actor
 * holds, searched the same way every time to depth 3: the bare hand on the
 * handle (75 mm), a lever, or a lever with a sleeve over its handle; the one
 * that reaches furthest, the lower entity first. Torque is grip times reach,
 * held at the command's amount (Nm) if any. Past the lever's limit there is
 * risk, not refusal: a seeded draw, in proportion to the excess, bends it,
 * giving way before the valve does (the valve feels half its limit). The stage commits the
 * torque applied, with what the turner expected from the valve's rating;
 * the valve decides. Using a lever wears it. */
static NSString   *effect_rotate( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGAgent   *agent;
   const BGLever   *l;
   const BGLever   *s;
   const BGLever   *inner;
   const BGValve   *valve;
   BGEntityID      held[ 4];
   BGEntityID      lever;
   NSUInteger      n;
   NSUInteger      i;
   NSUInteger      j;
   NSUInteger      lk;
   int64_t         reach;
   int64_t         best;
   int64_t         applied;
   int64_t         limit;
   uint64_t        state;
   char            detail[ 96];

   agent = [world record:[world kindNamed:"Agent"] for:a.roles[ BGRoleActor]];
   valve = [world record:[world kindNamed:"Valve"] for:a.roles[ BGRoleItem]];
   if( ! agent || ! valve)
      return( @"there is nothing to turn");
   lk    = [world kindNamed:"Lever"];
   n     = [world entitiesAt:a.roles[ BGRoleActor] form:BGLocationHeldBy into:held max:4];
   best  = 750;                  /* the bare hand on the handle: 75 mm */
   lever = BGNoEntity;
   inner = NULL;
   for( i = 0; i < n; i++)
   {
      l = [world record:lk for:held[ i]];
      if( ! l || l->sleeve)
         continue;
      reach = l->leverage;
      if( reach > best)
      {
         best  = reach;
         lever = held[ i];
         inner = l;
      }
      for( j = 0; j < n; j++)
      {
         s = [world record:lk for:held[ j]];
         if( j == i || ! s || ! s->sleeve || s->leverage <= best)
            continue;
         best  = s->leverage;
         lever = held[ i];
         inner = l;
      }
   }
   applied = agent->grip * best / 10000;
   if( amount > 0 && amount * 1000 < applied)
      applied = amount * 1000;
   snprintf( detail, sizeof( detail), "expected to %s: rated %lld Nm",
             applied >= valve->rating ? "turn" : "hold", (long long) valve->rating / 1000);
   if( inner)
   {
      limit = inner->limit;
      if( applied > limit)
      {
         state = BGMix( [world seed] ^ BGMix( [world boundary] * 0x100 + a.roles[ BGRoleItem]));
         if( (int64_t) (BGNext( &state) % (uint64_t) applied) < applied - limit)
         {
            /* it bends: a trace, and less it bears from now on */
            [g set:"Body.bent" of:BGWhole( lever) to:1];
            [g set:"Lever.limit" of:BGWhole( lever) to:limit / 2];
            wear( world, g, lever, 60);
            applied = limit / 2;
            strncat( detail, "; the lever bends", sizeof( detail) - strlen( detail) - 1);
         }
      }
      wear( world, g, lever, 10);
   }
   [g emit:"torqued" subject:BGWhole( a.roles[ BGRoleItem]) other:BGWhole( a.roles[ BGRoleActor]) amount:applied
    detail:[world intern:detail]];
   return( nil);
}


/* A blow with a stone: the valve feels it, and loosens. */
static NSString   *effect_strike( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g emit:"struck" subject:BGWhole( a.roles[ BGRoleDestination]) other:BGWhole( a.roles[ BGRoleActor]) amount:30000
    detail:NULL];
   return( nil);
}


/* Shutting a cock. */
static NSString   *effect_shut( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g set:"Cock.shut" of:BGWhole( a.roles[ BGRoleItem]) to:1];
   return( nil);
}


/* Dismantling's last stage: the pump is open. */
static NSString   *effect_dismantle( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g set:"Pump.opened" of:BGWhole( a.roles[ BGRoleDestination]) to:1];
   return( nil);
}


/* Tending changes nothing but traces, which the operation declares. */
static NSString   *effect_tend( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   return( nil);
}


/* Looking changes nothing in the world; it is an event the looker perceives. */
static NSString   *effect_look( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g emit:"looked" subject:BGWhole( a.roles[ BGRoleActor]) other:BGWhole( a.roles[ BGRoleItem])];
   return( nil);
}


static const struct
{
   const char   *name;
   BGEffect     function;
} effects[] =
{
   { "take",      effect_take },
   { "take_some", effect_take_some },
   { "put_in",    effect_put_in },
   { "drive",     effect_drive },
   { "open_tap",  effect_open_tap },
   { "walk",      effect_walk },
   { "loosen",    effect_loosen },
   { "look",      effect_look },
   { "say",       effect_say },
   { "tend",      effect_tend },
   { "analyse",   effect_analyse },
   { "write",     effect_write },
   { "read",      effect_read },
   { "eat",       effect_eat },
   { "give",      effect_give },
   { "investigate", effect_investigate },
   { "tighten",   effect_tighten },
   { "rotate",    effect_rotate },
   { "shut",      effect_shut },
   { "dismantle", effect_dismantle },
   { "strike",    effect_strike },
};


NSString   *BGOperationEffect( BGWorld *world, const char *operation)
{
   const TriNode   *pattern;
   char            effect[ 64];
   size_t          n;

   pattern = operation ? tri_pattern( [world tri], operation) : NULL;
   if( ! pattern || ! tri_at( [world tri], pattern, "effect"))
      return( nil);
   n = tri_print( [world tri], tri_at( [world tri], pattern, "effect"), effect, sizeof( effect));
   if( n < 2 || n >= sizeof( effect))
      return( nil);
   effect[ n - 1] = 0;          /* without its quotes */
   return( [NSString stringWithUTF8String:effect + 1]);
}


int64_t   BGOperationDuration( BGWorld *world, const char *operation)
{
   const TriNode   *pattern;
   int64_t         hi;
   int64_t         lo;

   pattern = operation ? tri_pattern( [world tri], operation) : NULL;
   if( ! pattern || ! tri_node_interval( tri_at( [world tri], pattern, "duration"), &lo, &hi) || lo != hi)
      return( 0);
   return( lo);
}


BOOL   BGOperationStage( BGWorld *world, const char *operation, int64_t index, int64_t *duration, NSString **effect)
{
   const TriNode     *pattern;
   const TriNode     *stage;
   NSMutableString   *path;
   TriContent        *tri;
   int64_t           hi;
   int64_t           k;
   char              text[ 64];
   size_t            n;

   tri     = [world tri];
   pattern = operation ? tri_pattern( tri, operation) : NULL;
   if( ! pattern)
      return( NO);
   if( ! tri_at( tri, pattern, "stages.first"))
   {
      /* one stage: the operation's own duration and effect */
      *duration = BGOperationDuration( world, operation);
      *effect   = BGOperationEffect( world, operation);
      return( index == 0 && *duration > 0);
   }
   path = [NSMutableString stringWithString:@"stages"];
   for( k = 0; k < index; k++)
      [path appendString:@".rest"];
   [path appendString:@".first"];
   stage = tri_at( tri, pattern, [path UTF8String]);
   if( ! stage || ! tri_node_interval( tri_at( tri, stage, "duration"), duration, &hi) || *duration != hi)
      return( NO);
   n = tri_print( tri, tri_at( tri, stage, "effect"), text, sizeof( text));
   if( n < 2 || n >= sizeof( text))
      return( NO);
   text[ n - 1] = 0;
   *effect = [NSString stringWithUTF8String:text + 1];
   return( YES);
}


BGProposalGroup   *BGPerformBelieved( BGWorld *world, BGCommitter *committer, BGKnowledgeStore *store,
                                      BGAction action, int64_t amount, NSString **error)
{
   const BGReferent   *ref;
   const BGReferent   *holder;
   BGProposalGroup    *group;
   TriMatchResult     result;
   NSString           *reason;
   BGAction           truth;
   BGEntityID         where;
   int                r;

   reason = nil;
   if( BGMatchBelieved( world, store, action, &result, &reason) == TRI_INCOMPATIBLE)
   {
      if( error)
         *error = reason;
      return( nil);
   }
   /* the world's side: what the referents actually track */
   truth = action;
   truth.roles[ BGRoleActor] = [store agent];
   for( r = BGRoleItem; r < BGRoleCount; r++)
   {
      ref            = action.roles[ r] ? [store referent:(uint32_t) action.roles[ r]] : NULL;
      truth.roles[ r] = ref ? ref->truth : BGNoEntity;
   }
   if( BGMatchAction( world, truth, &result, NULL) != TRI_INCOMPATIBLE)
      return( BGPerform( world, committer, truth, amount, error));

   /* it isn't as believed: the attempt is what happens, where the actor reached */
   ref    = [store referent:(uint32_t) action.roles[ BGRoleItem]];
   holder = ref && ref->form == BGLocationIn ? [store referent:ref->container] : NULL;
   where  = holder ? holder->truth : (ref ? ref->truth : BGNoEntity);
   group  = [BGProposalGroup groupWithPhase:BGPhaseAction
                                     source:[NSString stringWithFormat:@"%llu: %s (an attempt)",
                                                                       (unsigned long long) [store agent], action.operation]];
   [group setActor:[store agent]];
   [group emit:"attempted"
       subject:BGWhole( [store agent])
         other:BGWhole( where)];
   [committer submit:group];
   return( group);
}


/* The entity a trace site names, or the actor's tile for "tile" (0). */
static BOOL   trace_site( BGWorld *world, BGAction action, const char *site, BGEntityID *bearer, BGLocation *tile)
{
   BGLocation   at;
   BGEntityID   e;
   int          k;

   *bearer = BGNoEntity;
   memset( tile, 0, sizeof( *tile));
   if( ! strcmp( site, "tile"))
   {
      for( e = action.roles[ BGRoleActor], k = 0; e && k < 64; k++)
      {
         at = [world locationOf:e];
         if( at.form == BGLocationOnTile)
         {
            *tile = at;
            return( YES);
         }
         e = at.place;
      }
      return( NO);
   }
   *bearer = ! strcmp( site, "actor") ? action.roles[ BGRoleActor]
           : ! strcmp( site, "item") ? action.roles[ BGRoleItem]
           : ! strcmp( site, "destination") ? action.roles[ BGRoleDestination] : BGNoEntity;
   return( *bearer != BGNoEntity);
}


static BOOL   text_of( TriContent *tri, const TriNode *node, const char *path, char *buf, size_t len)
{
   const TriNode   *v;
   size_t          n;

   v = node ? tri_at( tri, node, path) : NULL;
   if( ! v)
      return( NO);
   n = tri_print( tri, v, buf, len);
   if( n < 2 || buf[ 0] != '"' || buf[ n - 1] != '"')
      return( NO);
   memmove( buf, buf + 1, n - 2);
   buf[ n - 2] = 0;
   return( YES);
}


void   BGLeaveTraces( BGWorld *world, BGAction action, BGProposalGroup *group)
{
   const TriNode      *pattern;
   const TriNode      *list;
   const TriNode      *v;
   const BGTrace      *record;
   BGStore            *traces;
   BGEntityID         bearer;
   BGEntityID         t;
   BGLocation         tile;
   TriContent         *tri;
   NSUInteger         i;
   int64_t            lo;
   int64_t            hi;
   int64_t            strength;
   int64_t            lasts;
   char               kind[ 64];
   char               site[ 32];
   char               key[ 128];
   const char         *text;

   tri     = [world tri];
   pattern = action.operation ? tri_pattern( tri, action.operation) : NULL;
   traces  = [world storeForKind:[world kindNamed:"Trace"]];
   for( list = pattern ? tri_at( tri, pattern, "removes") : NULL; list && tri_at( tri, list, "first");
        list = tri_at( tri, list, "rest"))
   {
      if( ! text_of( tri, tri_at( tri, list, "first"), "trace", kind, sizeof( kind)) ||
          ! text_of( tri, tri_at( tri, list, "first"), "on", site, sizeof( site)) ||
          ! trace_site( world, action, site, &bearer, &tile))
         continue;
      for( i = 0; i < [traces count]; i++)
      {
         record = [traces recordAtIndex:i];
         t      = [traces entityAtIndex:i];
         text   = [world textField:"Trace.traceKind" of:t];
         if( ! text || strcmp( text, kind) || (BGEntityID) record->bearer != bearer)
            continue;
         if( ! bearer && (record->tileX != tile.x || record->tileY != tile.y || record->tileLevel != tile.level))
            continue;
         [group destroy:BGWhole( t) reason:"removed"];
      }
   }
   for( list = pattern ? tri_at( tri, pattern, "leaves") : NULL; list && tri_at( tri, list, "first");
        list = tri_at( tri, list, "rest"))
   {
      if( ! text_of( tri, tri_at( tri, list, "first"), "trace", kind, sizeof( kind)) ||
          ! text_of( tri, tri_at( tri, list, "first"), "on", site, sizeof( site)) ||
          ! trace_site( world, action, site, &bearer, &tile))
         continue;
      v        = tri_at( tri, tri_at( tri, list, "first"), "strength");
      strength = v && tri_node_interval( v, &lo, &hi) && lo == hi ? lo : 0;
      v        = tri_at( tri, tri_pattern( tri, kind), "lasts");
      lasts    = v && tri_node_interval( v, &lo, &hi) && lo == hi ? lo : 0;
      snprintf( key, sizeof( key), "%s, left by %s", kind, action.operation);
      t = [group create:"trace" key:key at:BGLocationMakeNone()];
      [group set:"Trace.traceKind" of:BGWhole( t) toText:[world intern:kind]];
      [group set:"Trace.bearer" of:BGWhole( t) to:(int64_t) bearer];
      [group set:"Trace.tileX" of:BGWhole( t) to:tile.x];
      [group set:"Trace.tileY" of:BGWhole( t) to:tile.y];
      [group set:"Trace.tileLevel" of:BGWhole( t) to:tile.level];
      [group set:"Trace.magnitude" of:BGWhole( t) to:strength];
      [group set:"Trace.created" of:BGWhole( t) to:[world time].ms];
      [group set:"Trace.expires" of:BGWhole( t) to:[world time].ms + lasts];
   }
}


NSString   *BGApplyNamedEffect( BGWorld *world, NSString *effect, BGAction action, int64_t amount,
                                BGProposalGroup *group)
{
   size_t   i;

   for( i = 0; i < sizeof( effects) / sizeof( effects[ 0]); i++)
      if( effect && ! strcmp( effects[ i].name, [effect UTF8String]))
         return( effects[ i].function( world, action, amount, group));
   return( [NSString stringWithFormat:@"no code for the effect %@", effect]);
}


NSString   *BGApplyEffect( BGWorld *world, BGAction action, int64_t amount, BGProposalGroup *group)
{
   NSString     *effect;
   size_t       i;

   effect = BGOperationEffect( world, action.operation);
   for( i = 0; i < sizeof( effects) / sizeof( effects[ 0]); i++)
      if( effect && ! strcmp( effects[ i].name, [effect UTF8String]))
         return( effects[ i].function( world, action, amount, group));
   return( [NSString stringWithFormat:@"no code for the effect %@", effect]);
}


/* The activity entity an action starts, with its bindings. */
static BGEntityID   start_activity( BGWorld *world, BGAction action, int64_t amount, BGProposalGroup *g)
{
   BGEntityID   a;
   char         key[ 96];

   snprintf( key, sizeof( key), "activity of %llu at %llu: %s", (unsigned long long) action.roles[ BGRoleActor],
             (unsigned long long) [world boundary], action.operation);
   a = [g create:"activity" key:key at:BGLocationMakeNone()];
   [g set:"Activity.operation" of:BGWhole( a) toText:action.operation];
   [g set:"Activity.actorRef" of:BGWhole( a) to:(int64_t) action.roles[ BGRoleActor]];
   [g set:"Activity.itemRef" of:BGWhole( a) to:(int64_t) action.roles[ BGRoleItem]];
   [g set:"Activity.destinationRef" of:BGWhole( a) to:(int64_t) action.roles[ BGRoleDestination]];
   [g set:"Activity.amount" of:BGWhole( a) to:amount];
   return( a);
}


/* The providers an operation's activity uses: "hands", "legs". */
static NSUInteger   providers_of( TriContent *tri, const char *operation, char (*out)[ 16], NSUInteger max)
{
   const TriNode   *list;
   NSUInteger      n;
   char            text[ 32];
   size_t          len;

   n = 0;
   for( list = operation ? tri_at( tri, tri_pattern( tri, operation), "uses") : NULL;
        list && tri_at( tri, list, "first") && n < max;
        list = tri_at( tri, list, "rest"))
   {
      tri_print( tri, tri_at( tri, list, "first"), text, sizeof( text));
      len = strlen( text);
      if( len > 2 && text[ 0] == '"' && text[ len - 1] == '"')
         snprintf( out[ n++], 16, "%.*s", (int) (len - 2), text + 1);
   }
   return( n);
}


NSString   *BGProvidersBusy( BGWorld *world, BGEntityID actor, const char *operation, BGEntityID except)
{
   const BGActivity   *record;
   const char         *other;
   BGStore            *store;
   TriContent         *tri;
   TriType            running;
   NSUInteger         nwanted;
   NSUInteger         nused;
   NSUInteger         i;
   NSUInteger         j;
   NSUInteger         k;
   char               wanted[ 4][ 16];
   char               used[ 4][ 16];

   tri     = [world tri];
   nwanted = providers_of( tri, operation, wanted, 4);
   store   = [world storeForKind:[world kindNamed:"Activity"]];
   running = tri_type_named( tri, "\"running\"");
   for( i = 0; nwanted && i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      if( record->actorRef != actor || record->status != (uint32_t) running || [store entityAtIndex:i] == except)
         continue;
      other = [world textField:"Activity.operation" of:[store entityAtIndex:i]];
      nused = providers_of( tri, other, used, 4);
      for( j = 0; j < nwanted; j++)
         for( k = 0; k < nused; k++)
            if( ! strcmp( wanted[ j], used[ k]))
               return( [NSString stringWithFormat:@"its %s are busy with activity %llu (%s)", wanted[ j],
                                                  (unsigned long long) [store entityAtIndex:i], other]);
   }
   return( nil);
}


BGProposalGroup   *BGPerform( BGWorld *world, BGCommitter *committer, BGAction action, int64_t amount,
                              NSString **error)
{
   BGProposalGroup   *group;
   TriMatchResult    result;
   NSString          *effect;
   NSString          *reason;
   NSString          *source;
   BGEntityID        activity;
   NSString          *stageEffect;
   int64_t           duration;
   int               r;

   reason = nil;
   if( BGMatchAction( world, action, &result, &reason) == TRI_INCOMPATIBLE)
   {
      if( error)
         *error = reason;
      return( nil);
   }
   effect = BGOperationEffect( world, action.operation);
   if( ! BGOperationStage( world, action.operation, 0, &duration, &stageEffect))
      duration = 0;
   if( (duration > 0 || [effect isEqualToString:@"fill"]) &&
       (reason = BGProvidersBusy( world, action.roles[ BGRoleActor], action.operation, BGNoEntity)))
   {
      if( error)
         *error = reason;
      return( nil);
   }
   source   = [NSString stringWithFormat:@"%llu: %s", (unsigned long long) action.roles[ BGRoleActor], action.operation];
   for( r = BGRoleItem; r < BGRoleCount; r++)
      if( action.roles[ r])
         source = [source stringByAppendingFormat:@" %s %llu", BGRoleNames[ r], (unsigned long long) action.roles[ r]];
   if( amount)
      source = [source stringByAppendingFormat:@" (%lld)", (long long) amount];
   group = [BGProposalGroup groupWithPhase:BGPhaseAction
                                    source:source];
   [group setActor:action.roles[ BGRoleActor]];
   if( [effect isEqualToString:@"fill"])
   {
      /* an activity that ends by its watch on the bucket, or by the tap running dry */
      if( amount < 1)
      {
         if( error)
            *error = @"fill to how many millilitres?";
         return( nil);
      }
      activity = start_activity( world, action, amount, group);
      [group set:"Activity.watchHolder" of:BGWhole( activity) to:(int64_t) action.roles[ BGRoleDestination]];
      [group set:"Activity.watchAtLeast" of:BGWhole( activity) to:amount];
      [group set:"Tap.open" of:BGWhole( action.roles[ BGRoleItem]) to:1];
   }
   else if( duration > 0)
   {
      /* a timed activity: its first stage's effect commits when the stage is due */
      activity = start_activity( world, action, amount, group);
      [group set:"Activity.started" of:BGWhole( activity) to:[world time].ms];
      [group set:"Activity.due" of:BGWhole( activity) to:[world time].ms + duration];
   }
   else if( (reason = BGApplyEffect( world, action, amount, group)))
   {
      if( error)
         *error = reason;
      return( nil);
   }
   else
      BGLeaveTraces( world, action, group);
   [committer submit:group];
   return( group);
}
