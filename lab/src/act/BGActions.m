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
   static const char *copied[] = { "duration", "stages", "uses", "attention", "leaves", "removes", "partial",
                                   "checkpoints", "hard", "exertion", "floodWatch", "contest", NULL };
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


/* As believed, with `supposing`'s competing hypothesis in place of its
 * belief (0: none). */
static TriMatch   match_believed( BGWorld *world, BGKnowledgeStore *store, BGAction action, TriMatchResult *result,
                                  NSString **reason, uint32_t supposing, NSUInteger h)
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
      descriptions[ r] = ref->id == supposing ? [store describeSupposed:ref->id hypothesis:h]
                                              : [store describeReferent:ref->id];
   }
   return( match_described( world, pattern, action, descriptions, result, reason));
}


TriMatch   BGMatchBelieved( BGWorld *world, BGKnowledgeStore *store, BGAction action, TriMatchResult *result,
                            NSString **reason)
{
   return( match_believed( world, store, action, result, reason, 0, 0));
}


/* The credence mass, in thousandths, of the hypotheses under which the
 * action is entailed (CONTENT_LANGUAGE.md §9); `any` gets whether some
 * hypothesis isn't incompatible. */
static int32_t   entailed_mass( BGWorld *world, BGKnowledgeStore *store, BGAction action, TriMatch believed, BOOL *any)
{
   TriMatchResult   result;
   TriMatch         supposed;
   NSUInteger       h;
   uint32_t         doubted;
   int32_t          mass;
   int32_t          entailed;
   int              r;

   *any = believed != TRI_INCOMPATIBLE;
   for( r = 0; r < BGRoleCount; r++)
      if( action.roles[ r] && (mass = [store supposedMassOf:(uint32_t) action.roles[ r]]) > 0)
      {
         doubted  = (uint32_t) action.roles[ r];
         entailed = believed == TRI_ENTAILED ? 1000 - mass : 0;
         for( h = 0; h < [store hypothesesOf:doubted]; h++)
         {
            supposed  = match_believed( world, store, action, &result, NULL, doubted, h);
            *any      = *any || supposed != TRI_INCOMPATIBLE;
            entailed += supposed == TRI_ENTAILED ? [store massOf:doubted hypothesis:h] : 0;
         }
         return( entailed);
      }
   return( believed == TRI_ENTAILED ? 1000 : 0);
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
   free( _masses);
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
      _masses   = realloc( _masses, sizeof( int32_t) * _capacity);
   }
   _items[ _count]   = action;
   _matches[ _count] = match;
   _masses[ _count]  = match == TRI_ENTAILED ? 1000 : 0;
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
   BOOL               any;
   int32_t            mass;
   int                r;

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
            mass   = entailed_mass( world, store, action, match, &any);
            /* excluded only when every hypothesis rules it out */
            if( any)
            {
               [menu add:action
                   match:mass == 1000 ? TRI_ENTAILED : TRI_UNKNOWN
                  result:&result];
               menu->_masses[ menu->_count - 1] = mass;
               /* what to find out: where the hypotheses part */
               for( r = 0; mass < 1000 && r < BGRoleCount; r++)
                  if( action.roles[ r] && [store supposedMassOf:(uint32_t) action.roles[ r]] > 0)
                  {
                     char   key[ 64];

                     strncpy( key, [store overridesOf:(uint32_t) action.roles[ r] hypothesis:0], sizeof( key) - 1);
                     key[ sizeof( key) - 1]   = 0;
                     key[ strcspn( key, ":")] = 0;
                     [[menu->_residuals lastObject] addObject:[NSString stringWithFormat:@"%s.%s", BGRoleNames[ r], key]];
                  }
            }
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
   if( _masses && _masses[ i] > 0 && _masses[ i] < 1000)
      [s appendFormat:@" (%d in 1000 entails)", _masses[ i]];
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


static void   tread( BGWorld *world, BGLocation at, BGProposalGroup *g);


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
   tread( world, at, g);
   return( nil);
}


/* A step onto a tile (KNOWLEDGE.md §3, foot traffic): each floor trace
 * there whose kind is `trodden` loses that percent of the life it has
 * left, in the step's group. */
static void   tread( BGWorld *world, BGLocation at, BGProposalGroup *g)
{
   const BGTrace   *trace;
   const TriNode   *v;
   BGEntityID      *here;
   NSUInteger      n;
   NSUInteger      i;
   int64_t         now;
   int64_t         lo;
   int64_t         hi;

   now = [world time].ms;
   n   = [world tracesNear:at radius:0 into:&here];      /* the spatial index: this tile's alone */
   for( i = 0; i < n; i++)
   {
      trace = [world record:[world kindNamed:"Trace"] for:here[ i]];
      if( ! trace || trace->bearer || trace->tileX != at.x || trace->tileY != at.y || trace->tileLevel != at.level ||
          ! trace->traceKind || trace->expires <= now)
         continue;
      v = tri_at( [world tri], tri_pattern( [world tri], trace->traceKind), "trodden");
      if( ! v || ! tri_node_interval( v, &lo, &hi) || lo != hi || lo <= 0)
         continue;
      [g set:"Trace.expires" of:BGWhole( here[ i])
          to:now + (trace->expires - now) * (100 - lo) / 100];
   }
   free( here);
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


/* What it costs the actor to bring a lever in reach to bear (ACTIONS.md
 * §2): 0 held, 1 on a tile in reach, 2 in a container (one it carries, or
 * one standing there); -1 if it isn't the actor's to take up: in another's
 * hand, or part of something. */
static int   access_cost( BGWorld *world, BGEntityID actor, BGEntityID e)
{
   BGLocation   at;
   int          cost;
   int          depth;

   cost = 0;
   for( depth = 0; depth < 8; depth++)
   {
      at = [world locationOf:e];
      switch( at.form)
      {
      case BGLocationHeldBy :
         return( at.place == actor ? cost : -1);
      case BGLocationOnTile :
         return( cost ? cost : 1);
      case BGLocationIn :
         cost = 2;
         e    = at.place;
         continue;
      default :
         return( -1);
      }
   }
   return( -1);
}


/* The valve-turning chain (ACTIONS.md Scenario 1), searched in what the
 * actor can reach (§2), the same way every time to depth 3: the bare hand
 * on the handle (75 mm), a lever, or a lever with a sleeve over its handle.
 * The one that reaches furthest wins; at the same reach, the one cheaper to
 * bring to bear (held, then on a tile, then in a container), then the lower
 * entities. A chain needing more hands than are free isn't one. Returns the
 * reach (0.1 mm); `chain` gets the lever and sleeve (or none), `cost` what
 * each costs to bring to bear. */
static int64_t   turning_chain( BGWorld *world, BGEntityID actor, BGEntityID chain[ 2], int cost[ 2])
{
   const BGLever   *l;
   const BGLever   *s;
   BGEntityID      reach[ 256];
   BGEntityID      cand[ 64];
   int             ccost[ 64];
   NSUInteger      nreach;
   NSUInteger      nc;
   NSUInteger      i;
   NSUInteger      j;
   NSUInteger      lk;
   int32_t         hands;
   int32_t         need;
   int             c;
   int             bestCost;
   int64_t         best;

   lk     = [world kindNamed:"Lever"];
   nreach = [[BGView viewOf:actor inWorld:world] reachable:reach max:256];
   if( nreach > 256)
      nreach = 256;
   nc = 0;
   for( i = 0; i < nreach && nc < 64; i++)
   {
      if( ! [world record:lk for:reach[ i]] || (c = access_cost( world, actor, reach[ i])) < 0)
         continue;
      cand[ nc]    = reach[ i];
      ccost[ nc++] = c;
   }
   hands    = BGFreeHands( world, actor);
   best     = 750;               /* the bare hand on the handle: 75 mm */
   bestCost = 0;
   chain[ 0] = chain[ 1] = BGNoEntity;
   cost[ 0]  = cost[ 1]  = 0;
   for( i = 0; i < nc; i++)
   {
      l = [world record:lk for:cand[ i]];
      if( l->sleeve)
         continue;
      if( (ccost[ i] ? 1 : 0) <= hands &&
          (l->leverage > best || (l->leverage == best && chain[ 0] && ccost[ i] < bestCost)))
      {
         best      = l->leverage;
         bestCost  = ccost[ i];
         chain[ 0] = cand[ i];
         chain[ 1] = BGNoEntity;
         cost[ 0]  = ccost[ i];
         cost[ 1]  = 0;
      }
      for( j = 0; j < nc; j++)
      {
         s = [world record:lk for:cand[ j]];
         if( j == i || ! s->sleeve)
            continue;
         need = (ccost[ i] ? 1 : 0) + (ccost[ j] ? 1 : 0);
         if( need > hands)
            continue;
         if( s->leverage > best || (s->leverage == best && ccost[ i] + ccost[ j] < bestCost))
         {
            best      = s->leverage;
            bestCost  = ccost[ i] + ccost[ j];
            chain[ 0] = cand[ i];
            chain[ 1] = cand[ j];
            cost[ 0]  = ccost[ i];
            cost[ 1]  = ccost[ j];
         }
      }
   }
   return( best);
}


int64_t   BGWorkRate( BGWorld *world, BGEntityID actor, const char *operation, int64_t index)
{
   const BGAgent   *agent;
   int64_t         worn;

   agent = [world record:[world kindNamed:"Agent"] for:actor];
   if( ! agent || BGOperationExertion( world, operation, index) <= 0)
      return( 100);
   worn = (int64_t) agent->fatigue + (int64_t) agent->injury;
   return( 100 * 200 / (200 + (worn > 0 ? worn : 0)));
}


BOOL   BGCurveAt( TriContent *tri, const TriNode *curve, int64_t x, int32_t *out)
{
   const TriNode   *p;
   int64_t         at[ 16];
   int64_t         w[ 16];
   int64_t         lo;
   int64_t         hi;
   int             n;
   int             k;

   for( n = 0; curve && n < 16 && (p = tri_at( tri, curve, "first")); curve = tri_at( tri, curve, "rest"))
   {
      if( ! tri_node_interval( tri_at( tri, p, "input"), &lo, &hi) || lo != hi)
         continue;
      at[ n] = lo;
      if( ! tri_node_interval( tri_at( tri, p, "output"), &lo, &hi) || lo != hi)
         continue;
      w[ n++] = lo;
   }
   if( ! n)
      return( NO);
   if( x <= at[ 0])
   {
      *out = (int32_t) w[ 0];
      return( YES);
   }
   for( k = 1; k < n; k++)
      if( x <= at[ k])
      {
         *out = (int32_t) (w[ k - 1] + (w[ k] - w[ k - 1]) * (x - at[ k - 1]) / (at[ k] - at[ k - 1]));
         return( YES);
      }
   *out = (int32_t) w[ n - 1];
   return( YES);
}


static BOOL   trace_site( BGWorld *world, BGAction action, const char *site, BGEntityID *bearer, BGLocation *tile);
static BOOL   text_of( TriContent *tri, const TriNode *node, const char *path, char *buf, size_t len);


/* A role's entity by its site's name ("item"), or none. */
static BGEntityID   role_named( BGAction action, const char *site)
{
   int   r;

   for( r = 0; r < BGRoleCount; r++)
      if( ! strcmp( BGRoleNames[ r], site))
         return( action.roles[ r]);
   return( BGNoEntity);
}


int64_t   BGCapacity( BGWorld *world, BGAction action)
{
   const TriNode   *graded;
   TriContent      *tri;
   int64_t         offered;
   int64_t         demanded;
   char            site[ 32];
   char            field[ 96];

   tri    = [world tri];
   graded = action.operation ? tri_at( tri, tri_pattern( tri, action.operation), "graded") : NULL;
   if( ! graded || ! text_of( tri, graded, "offerer", site, sizeof( site)) ||
       ! text_of( tri, graded, "offers", field, sizeof( field)) ||
       ! [world getField:field of:role_named( action, site) value:&offered] ||
       ! text_of( tri, graded, "demander", site, sizeof( site)) ||
       ! text_of( tri, graded, "demands", field, sizeof( field)) ||
       ! [world getField:field of:role_named( action, site) value:&demanded] || demanded <= 0)
      return( -1);
   return( offered * 100 / demanded);
}


int64_t   BGGradedRate( BGWorld *world, BGAction action, int64_t rate)
{
   int64_t   capacity;
   int32_t   slowing;

   capacity = BGCapacity( world, action);
   if( capacity < 0 ||
       ! BGCurveAt( [world tri], tri_at( [world tri], tri_pattern( [world tri], action.operation), "graded.slowing"),
                    capacity, &slowing) || slowing <= 0)
      return( rate);
   return( rate * 100 / slowing);
}


/* As the effect commits (ACTIONS.md decision 11): a mishap, by the chance
 * the `mishap` curve gives the capacity, a seeded draw, leaving its `slip`;
 * and the result's quality, as the `quality` curve gives it, set on
 * `grades`, a field of the demanding role's entity. */
static void   grade( BGWorld *world, BGAction action, BGProposalGroup *group)
{
   const TriNode   *graded;
   const TriNode   *v;
   TriContent      *tri;
   BGEntityID      bearer;
   BGLocation      tile;
   int64_t         capacity;
   int64_t         lo;
   int64_t         hi;
   int32_t         chance;
   int32_t         quality;
   uint64_t        state;
   char            kind[ 64];
   char            site[ 32];
   char            field[ 96];

   tri      = [world tri];
   capacity = BGCapacity( world, action);
   graded   = capacity >= 0 ? tri_at( tri, tri_pattern( tri, action.operation), "graded") : NULL;
   if( ! graded)
      return;
   if( BGCurveAt( tri, tri_at( tri, graded, "mishap"), capacity, &chance) && chance > 0)
   {
      state = BGMix( [world seed] ^ BGMix( [world boundary] * 0x100 + action.roles[ BGRoleActor]) ^ 0x6d6973686170ULL);
      if( (int64_t) (BGNext( &state) % 1000) < chance &&
          text_of( tri, graded, "slip.trace", kind, sizeof( kind)) && text_of( tri, graded, "slip.on", site, sizeof( site)) &&
          trace_site( world, action, site, &bearer, &tile))
      {
         v = tri_at( tri, graded, "slip.strength");
         BGMakeTrace( world, group, kind, bearer, tile, v && tri_node_interval( v, &lo, &hi) && lo == hi ? lo : 0,
                      action.operation);
         [group emit:"mishap" subject:BGWhole( action.roles[ BGRoleActor]) other:BGWhole( bearer) detail:"slip"];
      }
   }
   if( BGCurveAt( tri, tri_at( tri, graded, "quality"), capacity, &quality) &&
       text_of( tri, graded, "grades", field, sizeof( field)) &&
       text_of( tri, graded, "demander", site, sizeof( site)) && role_named( action, site))
      [group set:field of:BGWhole( role_named( action, site)) to:quality];
}


uint64_t   BGContestWeight( BGWorld *world, BGEntityID actor, const char *operation)
{
   const TriNode   *pattern;
   const TriNode   *v;
   char            field[ 96];
   char            printed[ 64];
   int64_t         value;
   size_t          n;

   pattern = operation ? tri_pattern( [world tri], operation) : NULL;
   v       = pattern ? tri_at( [world tri], pattern, "contest") : NULL;
   n       = v ? tri_print( [world tri], v, printed, sizeof( printed)) : 0;
   if( n < 3 || printed[ 0] != '"')
      return( 0);
   printed[ n - 1] = 0;
   snprintf( field, sizeof( field), "Agent.%s", printed + 1);
   value = 0;
   if( ! [world getField:field of:actor value:&value] || value <= 0)
      return( 0);
   return( (uint64_t) value);
}


int64_t   BGAccessDelay( BGWorld *world, BGAction action)
{
   const TriNode   *said;
   const TriNode   *list;
   TriArena        *arena;
   BGEntityID      chain[ 2];
   int             cost[ 2];
   int64_t         take;
   int64_t         claims;
   NSString        *effect;

   effect = BGOperationEffect( world, action.operation);
   /* talking takes as long as what is said (ACTIONS.md decision 14): an
    * account a second more for each claim after the first */
   if( [effect isEqualToString:@"say"] && action.content)
   {
      arena  = tri_arena_new();
      said   = tri_value( [world tri], action.content, arena, NULL, 0);
      claims = 0;
      if( said && tri_subtype( [world tri], tri_node_type( said), tri_type_named( [world tri], "#Account")))
         for( list = tri_at( [world tri], said, "entries"); list && tri_at( [world tri], list, "first");
              list = tri_at( [world tri], list, "rest"))
            claims++;
      tri_arena_free( arena);
      return( claims > 1 ? (claims - 1) * BGOperationDuration( world, action.operation) : 0);
   }
   if( ! [effect isEqualToString:@"rotate"])
      return( 0);
   take = BGOperationDuration( world, "take_up");
   turning_chain( world, action.roles[ BGRoleActor], chain, cost);
   return( take * (cost[ 0] + cost[ 1]));
}


/* Turning a valve (ACTIONS.md Scenario 1), with the chain found as above.
 * A part not held is taken up into a free hand in the stage's group, from
 * where it is (if someone else gets it first, the stage fails); the time
 * that takes was added to the stage when it started (BGAccessDelay).
 * Torque is grip times reach, held at the command's amount (Nm) if any.
 * Past the lever's limit there is risk, not refusal: a seeded draw, in
 * proportion to the excess, bends it, giving way before the valve does
 * (the valve feels half its limit). The stage commits the torque applied,
 * with what the turner expected from the valve's rating; the valve
 * decides. Using a lever wears it. */
static NSString   *effect_rotate( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGAgent   *agent;
   const BGLever   *inner;
   const BGValve   *valve;
   BGEntityID      actor;
   BGEntityID      held[ 8];
   BGEntityID      chain[ 2];
   BGEntityID      lever;
   NSUInteger      n;
   NSUInteger      i;
   NSUInteger      k;
   int32_t         hand;
   int             cost[ 2];
   int64_t         best;
   int64_t         applied;
   int64_t         limit;
   uint64_t        state;
   BOOL            taken;
   char            detail[ 160];

   actor = a.roles[ BGRoleActor];
   agent = [world record:[world kindNamed:"Agent"] for:actor];
   valve = [world record:[world kindNamed:"Valve"] for:a.roles[ BGRoleItem]];
   if( ! agent || ! valve)
      return( @"there is nothing to turn");
   best  = turning_chain( world, actor, chain, cost);
   lever = chain[ 0];
   inner = lever ? [world record:[world kindNamed:"Lever"] for:lever] : NULL;

   applied = agent->grip * best / 10000;
   if( amount > 0 && amount * 1000 < applied)
      applied = amount * 1000;
   snprintf( detail, sizeof( detail), "expected to %s: rated %lld Nm",
             applied >= valve->rating ? "turn" : "hold", (long long) valve->rating / 1000);

   /* what isn't held is taken up, into the free hands in order */
   n    = [world entitiesAt:actor form:BGLocationHeldBy into:held max:8];
   hand = 0;
   for( k = 0; k < 2; k++)
   {
      if( ! chain[ k] || ! cost[ k])
         continue;
      for( ; hand < (int32_t) agent->hands; hand++)
      {
         taken = NO;
         for( i = 0; i < n && i < 8 && ! taken; i++)
            taken = [world locationOf:held[ i]].slot == hand;
         if( ! taken)
            break;
      }
      [g move:BGWhole( chain[ k]) to:BGHeldBy( actor, hand++) expecting:[world locationOf:chain[ k]]];
      strncat( detail, "; takes up one in reach", sizeof( detail) - strlen( detail) - 1);
   }

   if( inner)
   {
      limit = inner->limit;
      if( applied > limit)
      {
         state = BGMix( [world seed] ^ BGMix( [world boundary] * 0x100 + a.roles[ BGRoleItem]));
         if( (int64_t) (BGNext( &state) % (uint64_t) applied) < applied - limit)
         {
            /* it bends: a trace, a clang, and less it bears from now on */
            [g set:"Body.bent" of:BGWhole( lever) to:1];
            BGMakeTrace( world, g, "clang", lever, BGLocationMakeNone(), 80, "a lever giving");
            [g set:"Lever.limit" of:BGWhole( lever) to:limit / 2];
            wear( world, g, lever, 60);
            applied = limit / 2;
            strncat( detail, "; the lever bends", sizeof( detail) - strlen( detail) - 1);
         }
      }
      wear( world, g, lever, 10);
   }
   [g emit:"torqued" subject:BGWhole( a.roles[ BGRoleItem]) other:BGWhole( actor) amount:applied
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


/* Copying (COMPONENTS.md §8): a new copy, set down on the copier's tile, in
 * its hand, pressed with the seal it holds, if any. Copied as it is, it
 * references the same content. In other words (the command's), it is new
 * content, `derivedFrom` the original and claiming its issuer still; its
 * actual origin is this group's creation, the copier's. */
static NSString   *effect_copy( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGInscription   *source;
   const BGScribe        *scribe;
   BGStore               *stamps;
   BGEntityID            seal;
   BGLocation            at;
   BGEntityID            content;
   BGEntityID            copy;
   NSUInteger            i;
   const char            *reads;
   const char            *issuer;
   const char            *presses;

   source = [world record:[world kindNamed:"Inscription"] for:a.roles[ BGRoleItem]];
   if( ! source || ! source->inscribed)
      return( @"there is nothing written there to copy");
   content = (BGEntityID) source->inscribed;
   reads   = [world textField:"Information.text" of:content];
   issuer  = [world textField:"Information.issuer" of:content];
   scribe  = [world record:[world kindNamed:"Scribe"] for:a.roles[ BGRoleActor]];
   presses = "";
   seal    = BGNoEntity;
   stamps  = [world storeForKind:[world kindNamed:"Stamp"]];
   for( i = 0; i < [stamps count] && ! seal; i++)
   {
      at = [world locationOf:[stamps entityAtIndex:i]];
      if( at.form == BGLocationHeldBy && at.place == a.roles[ BGRoleActor])
      {
         seal    = [stamps entityAtIndex:i];
         presses = [world textField:"Stamp.presses" of:seal];
      }
   }
   if( a.content && *a.content && (! reads || strcmp( a.content, reads)))
   {
      /* altered: new content, derived from the original */
      content = [g create:"content" key:"altered content" at:BGLocationMakeNone()];
      [g set:"Information.text" of:BGWhole( content) toText:a.content];
      [g set:"Information.issuer" of:BGWhole( content) toText:issuer ? issuer : ""];
      [g relate:BGEdgeDerivedFrom from:BGWhole( content) to:BGWhole( (BGEntityID) source->inscribed)];
      reads = a.content;
   }
   at   = [world locationOf:a.roles[ BGRoleActor]];
   copy = [g create:"paper_copy" key:"a copy" at:at.form == BGLocationOnTile ? at : BGLocationMakeNone()];
   [g set:"Inscription.inscribed" of:BGWhole( copy) to:(int64_t) content];
   [g set:"Inscription.reads" of:BGWhole( copy) toText:reads ? reads : ""];
   [g set:"Inscription.claims" of:BGWhole( copy) toText:issuer ? issuer : ""];
   [g set:"Inscription.penned" of:BGWhole( copy)
   toText:scribe && [world textField:"Scribe.handwriting" of:a.roles[ BGRoleActor]]
          ? [world textField:"Scribe.handwriting" of:a.roles[ BGRoleActor]] : "an unknown hand"];
   [g set:"Inscription.impression" of:BGWhole( copy) toText:presses ? presses : ""];
   /* the seal pressed it: provenance, for whoever investigates */
   if( seal)
      [g emit:"stamped" subject:BGWhole( seal) other:BGWhole( copy)];
   return( nil);
}


/* A text feature of a node, unquoted, into buf; NO if it hasn't one. */
static BOOL   text_feature( TriContent *tri, const TriNode *node, const char *path, char *buf, size_t len)
{
   const TriNode   *at;
   size_t          n;

   at = node ? tri_at( tri, node, path) : NULL;
   n  = at ? tri_print( tri, at, buf, len) : 0;
   if( n < 2 || n >= len || buf[ 0] != '"')
      return( NO);
   memmove( buf, buf + 1, n - 2);
   buf[ n - 2] = 0;
   return( YES);
}


/* Latent wear (LATENT_ASSEMBLY.md decisions 4-6,
 * content/machines/latent.tri): the assembly's use shared out among its roles
 * by how fast each wears, how hard abuse strains it, and its hidden
 * quality. */
#define BG_WEARS        2               /* a role's points in 100 h of use, unless it says */
#define BG_PART_FAILED  60              /* the wear a failure leaves its culprit at, at least */
#define BG_WEAR_SPAN    (100 * 3600000LL)      /* the 100 h `wears` and `chance` are per */


/* The schema's entry for `role` among its parts, or NULL. */
static const TriNode   *latent_role( TriContent *tri, const TriNode *schema, const char *role)
{
   const TriNode   *list;
   const TriNode   *entry;
   char            name[ 64];

   for( list = tri_at( tri, schema, "parts"); list && (entry = tri_at( tri, list, "first")); list = tri_at( tri, list, "rest"))
      if( text_feature( tri, entry, "roleName", name, sizeof( name)) && ! strcmp( name, role))
         return( entry);
   return( NULL);
}


static int64_t   int_feature( TriContent *tri, const TriNode *node, const char *path, int64_t otherwise)
{
   int64_t   lo;
   int64_t   hi;

   return( node && tri_node_interval( tri_at( tri, node, path), &lo, &hi) && lo == hi ? lo : otherwise);
}


/* A role's hidden quality, 0 to 100: 50, give or take 20 by the unit's seed,
 * and the schema's bias for its kind of part. A candidate that is no part
 * (the housing) has a quality all the same. */
static int64_t   latent_quality( TriContent *tri, const TriNode *schema, uint64_t seed, const char *role)
{
   const TriNode   *entry;
   const TriNode   *list;
   const TriNode   *bias;
   char            kind[ 64];
   char            text[ 64];
   int64_t         q;

   q     = 30 + (int64_t) (BGMixString( BGMix( seed ^ 0x7175616c697479ULL), role) % 41);
   entry = latent_role( tri, schema, role);
   if( entry && text_feature( tri, entry, "partKind", kind, sizeof( kind)))
      for( list = tri_at( tri, schema, "biases"); list && (bias = tri_at( tri, list, "first")); list = tri_at( tri, list, "rest"))
         if( text_feature( tri, bias, "biased", text, sizeof( text)) && ! strcmp( text, kind))
            q += int_feature( tri, bias, "bias", 0);
   return( q < 0 ? 0 : q > 100 ? 100 : q);
}


/* How fast a role wears, in hundredths of a point per 100 h of use: what it
 * `wears`, by the quality of what fills it (half again as fast at 0, half
 * as fast at 100). */
static int64_t   role_rate( TriContent *tri, const TriNode *schema, const char *role, int64_t quality)
{
   return( int_feature( tri, latent_role( tri, schema, role), "wears", BG_WEARS) * (150 - quality));
}


/* What `used` ms of use, `abused` of them abused (the role wears `strain`
 * times as fast then), wear what fills a role, in ten-thousandths of a
 * point. */
static int64_t   role_attrition( TriContent *tri, const TriNode *schema, const char *role, int64_t quality,
                                 int64_t used, int64_t abused)
{
   int64_t   strain;

   strain = int_feature( tri, latent_role( tri, schema, role), "strain", 1);
   return( role_rate( tri, schema, role, quality) * 100 * (used + abused * (strain - 1)) / BG_WEAR_SPAN);
}


/* A role's wear unopened, in hundredths of a point: by the assembly's
 * history and the role's hidden quality. */
static int64_t   latent_wear( TriContent *tri, const TriNode *schema, uint64_t seed, const char *role,
                              int64_t used, int64_t abused)
{
   return( role_attrition( tri, schema, role, latent_quality( tri, schema, seed, role), used, abused) / 100);
}


/* A part's quality: what it was made with, revealed from its assembly;
 * else 50, give or take 20, by its own seed. */
static int64_t   part_quality( BGWorld *world, BGEntityID part, const BGPart *p)
{
   return( p->grade >= 0 ? p->grade : 30 + (int64_t) (BGMix( [world info:part]->seed ^ 0x7175616c697479ULL) % 41));
}


/* How worn a part is, in ten-thousandths of a point: its attrition, or its
 * wear if that says more (a part content made worn). */
static int64_t   part_attrition( const BGPart *p)
{
   return( p->attrition > p->wear * 10000 ? p->attrition : p->wear * 10000);
}


/* The part in an assembly's role, or none. */
static BGEntityID   latent_part( BGWorld *world, BGEntityID assembly, const char *role)
{
   BGEntityID   in[ 64];
   NSUInteger   n;
   NSUInteger   i;

   n = [world entitiesAt:assembly form:BGLocationPartOf into:in max:64];
   for( i = 0; i < n; i++)
      if( ! strcmp( [world locationOf:in[ i]].role, role))
         return( in[ i]);
   return( BGNoEntity);
}


/* A role's wear, in hundredths of a point, after `d` ms more use, `dry` of
 * them abused; and how fast it wears (decision 7). Opened, it is the part's
 * in it, by that part's quality; an opened role empty has none. Unopened,
 * or no part (the housing), it is the role's, by the assembly's history. */
static int64_t   latent_condition( BGWorld *world, BGEntityID assembly, const BGLatent *latent, const TriNode *schema,
                                   const char *role, int64_t d, int64_t dry, int64_t *rate)
{
   const TriNode   *entry;
   const BGPart    *p;
   TriContent      *tri;
   BGEntityID      part;
   uint64_t        seed;
   int64_t         q;

   tri   = [world tri];
   seed  = [world info:assembly]->seed;
   entry = latent_role( tri, schema, role);
   if( entry && int_feature( tri, entry, "depth", 1) <= latent->revealed)
   {
      part = latent_part( world, assembly, role);
      p    = part ? [world record:[world kindNamed:"Part"] for:part] : NULL;
      if( ! p)
      {
         *rate = 0;
         return( 0);
      }
      q     = part_quality( world, part, p);
      *rate = role_rate( tri, schema, role, q);
      return( (part_attrition( p) + role_attrition( tri, schema, role, q, d, dry)) / 100);
   }
   *rate = role_rate( tri, schema, role, latent_quality( tri, schema, seed, role));
   return( latent_wear( tri, schema, seed, role, latent->used + d, latent->abused + dry));
}


/* The culprit of `failure` among its candidates, after `d` ms more use,
 * `dry` of them abused: drawn by the seed, each weighted by its wear, as if
 * a hundred hours more worn, so that a unit new to use is weighted by how
 * fast each wears. "" if it has no candidates. */
static void   latent_culprit( BGWorld *world, BGEntityID assembly, const BGLatent *latent, const TriNode *schema,
                              const char *failure, int64_t d, int64_t dry, char *culprit, size_t len)
{
   const TriNode   *list;
   const TriNode   *entry;
   const TriNode   *cands;
   TriContent      *tri;
   char            text[ 64];
   char            role[ 64];
   int64_t         total;
   int64_t         rate;
   int64_t         k;

   tri         = [world tri];
   culprit[ 0] = 0;
   for( list = tri_at( tri, schema, "culprits"); list && (entry = tri_at( tri, list, "first")); list = tri_at( tri, list, "rest"))
   {
      if( ! text_feature( tri, entry, "failing", text, sizeof( text)) || strcmp( text, failure))
         continue;
      total = 0;
      for( cands = tri_at( tri, entry, "candidates"); cands && text_feature( tri, cands, "first", role, sizeof( role));
           cands = tri_at( tri, cands, "rest"))
         total += latent_condition( world, assembly, latent, schema, role, d, dry, &rate) + rate;
      if( total <= 0)
         return;
      k = (int64_t) (BGMixString( BGMix( [world info:assembly]->seed ^ 0x63756c70726974ULL), failure) % (uint64_t) total);
      for( cands = tri_at( tri, entry, "candidates"); cands && text_feature( tri, cands, "first", role, sizeof( role));
           cands = tri_at( tri, cands, "rest"))
      {
         k -= latent_condition( world, assembly, latent, schema, role, d, dry, &rate) + rate;
         if( k < 0)
         {
            snprintf( culprit, len, "%s", role);
            return;
         }
      }
      return;
   }
}


/* An assembly's use, `d` ms, `dry` of them abused, passed on to the parts
 * in it: each wears as its role does, by its own quality; one that is
 * itself an assembly is used as long, and so on in. The part blamed for a
 * failure now is worn at least as a failure leaves it; one that is an
 * assembly takes the failure on. */
static void   latent_use( BGWorld *world, BGProposalGroup *g, BGEntityID assembly, int64_t d, int64_t dry,
                          const char *blamed, const char *failure, int depth)
{
   const BGLatent       *latent;
   const BGLatent       *inner;
   const BGPart         *p;
   const BGEntityInfo   *info;
   const TriNode        *schema;
   TriContent           *tri;
   BGEntityID           in[ 64];
   BGLocation           at;
   NSUInteger           n;
   NSUInteger           i;
   int64_t              worn;
   BOOL                 culprit;

   tri    = [world tri];
   latent = [world record:[world kindNamed:"Latent"] for:assembly];
   info   = [world info:assembly];
   schema = latent && info ? tri_at( tri, tri_pattern( tri, info->blueprint), "latent") : NULL;
   if( ! schema || depth > 8)
      return;
   n = [world entitiesAt:assembly form:BGLocationPartOf into:in max:64];
   for( i = 0; i < n; i++)
   {
      if( ! (p = [world record:[world kindNamed:"Part"] for:in[ i]]))
         continue;
      at      = [world locationOf:in[ i]];
      culprit = blamed && ! strcmp( at.role, blamed);
      if( (inner = [world record:[world kindNamed:"Latent"] for:in[ i]]))
      {
         [g set:"Latent.used" of:BGWhole( in[ i]) to:inner->used + d];
         [g set:"Latent.abused" of:BGWhole( in[ i]) to:inner->abused + dry];
         if( culprit)
         {
            [g set:"Latent.failure" of:BGWhole( in[ i]) toText:[world intern:failure]];
            [g set:"Latent.failedAt" of:BGWhole( in[ i]) to:[world time].ms];
         }
         latent_use( world, g, in[ i], d, dry, NULL, NULL, depth + 1);
         continue;
      }
      worn = part_attrition( p) + role_attrition( tri, schema, at.role, part_quality( world, in[ i], p), d, dry);
      if( culprit && worn < BG_PART_FAILED * 10000)
         worn = BG_PART_FAILED * 10000;
      worn = worn > 1000000 ? 1000000 : worn;
      [g set:"Part.attrition" of:BGWhole( in[ i]) to:worn];
      [g set:"Part.wear" of:BGWhole( in[ i]) to:worn / 10000];
   }
}


/* Working a pump an hour (content/machines/pump.tri): it lifts water from
 * the store it draws from into its riser, at its flow; what it can't draw,
 * the store dry, it is worked dry, abused. The use risks each failure the
 * schema names: its chance, by the wear of its most worn candidate, drawn by
 * the seed and the use so far. Failed, its culprit is decided then, and a
 * flow loss costs it the flow its culprit's loss does. The parts opened in it
 * wear on. Seized, it can't be worked. */
static NSString   *effect_work( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGLatent       *latent;
   const BGPump         *pump;
   const BGEntityInfo   *info;
   const TriNode        *schema;
   const TriNode        *list;
   const TriNode        *entry;
   const TriNode        *cands;
   TriContent           *tri;
   BGEntityID           e;
   int64_t              d;
   int64_t              want;
   int64_t              have;
   int64_t              room;
   int64_t              level;
   int64_t              got;
   int64_t              dry;
   int64_t              worst;
   int64_t              w;
   int64_t              rate;
   int64_t              ppm;
   int64_t              cap;
   BOOL                 store;
   BOOL                 failed;
   char                 failing[ 64];
   char                 role[ 64];
   char                 culprit[ 64];

   tri    = [world tri];
   e      = a.roles[ BGRoleItem];
   latent = [world record:[world kindNamed:"Latent"] for:e];
   pump   = [world record:[world kindNamed:"Pump"] for:e];
   info   = [world info:e];
   schema = latent && pump && info ? tri_at( tri, tri_pattern( tri, info->blueprint), "latent") : NULL;
   if( ! schema)
      return( @"there is no pump to work");
   if( latent->failure && ! strcmp( latent->failure, "seized"))
      return( @"it is seized");
   d = BGOperationDuration( world, a.operation);

   /* the water: what its flow would lift, what the source has, what the riser takes */
   dry  = 0;
   want = pump->lift * pump->flow / 100 * d / 60000;
   if( want > 0 && pump->draws)
   {
      have  = 0;
      level = 0;
      [world getField:"WaterStore.water" of:pump->draws value:&have];
      room  = want;
      store = latent->riser && [world getField:"WaterStore.water" of:latent->riser value:&level] &&
              [world getField:"WaterStore.waterCapacity" of:latent->riser value:&cap];
      if( store)
         room = cap - level;
      got = want < have ? want : have;
      got = got < room ? got : room;
      got = got < 0 ? 0 : got;
      dry = have < want ? d * (want - have) / want : 0;
      if( got)
      {
         [g set:"WaterStore.water" of:BGWhole( pump->draws) to:have - got];
         if( store)
            [g set:"WaterStore.water" of:BGWhole( latent->riser) to:level + got];
      }
   }
   [g set:"Latent.used" of:BGWhole( e) to:latent->used + d];
   [g set:"Latent.abused" of:BGWhole( e) to:latent->abused + dry];

   /* the risk: each failure in turn, while none has happened */
   failed      = NO;
   culprit[ 0] = 0;
   if( ! latent->failure || ! *latent->failure)
      for( list = tri_at( tri, schema, "culprits"); ! failed && list && (entry = tri_at( tri, list, "first"));
           list = tri_at( tri, list, "rest"))
      {
         if( ! text_feature( tri, entry, "failing", failing, sizeof( failing)))
            continue;
         worst = 0;
         for( cands = tri_at( tri, entry, "candidates"); cands && text_feature( tri, cands, "first", role, sizeof( role));
              cands = tri_at( tri, cands, "rest"))
            if( latent_role( tri, schema, role) &&
                (w = latent_condition( world, e, latent, schema, role, 0, 0, &rate) / 100) > worst)
               worst = w > 100 ? 100 : w;
         /* in a million, for this use: chance/1000 per 100 h, ×(1 + 3 wear/100) */
         ppm = int_feature( tri, entry, "chance", 0) * 10 * (100 + 3 * worst) * d / BG_WEAR_SPAN;
         failed = (int64_t) (BGMixString( BGMix( info->seed ^ (uint64_t) latent->used ^ 0x6661696cULL), failing) % 1000000) < ppm;
         if( failed)
            latent_culprit( world, e, latent, schema, failing, d, dry, culprit, sizeof( culprit));
      }

   /* the parts opened in it wear on; the culprit among them, as a failure leaves it */
   latent_use( world, g, e, d, dry, failed ? culprit : NULL, failed ? failing : NULL, 0);
   if( failed)
   {
      [g set:"Latent.failure" of:BGWhole( e) toText:[world intern:failing]];
      [g set:"Latent.failedAt" of:BGWhole( e) to:[world time].ms];
      [g set:"Latent.blamed" of:BGWhole( e) toText:[world intern:culprit]];
      if( ! strcmp( failing, "flow_loss") && latent_role( tri, schema, culprit))
         [g set:"Pump.flow" of:BGWhole( e) to:pump->flow > 80 ? pump->flow - 80 : 0];
      [g emit:"failed" subject:BGWhole( e) other:BGWhole( a.roles[ BGRoleActor])];
   }
   return( nil);
}


/* Opening a latent assembly a level further (content/machines/latent.tri): the
 * level's parts become entities, part of it, their mass carved out of its
 * own; each one worn by the assembly's use. The culprit of a failure
 * committed against it, decided at the failure or else now, is worn at least
 * as a failure leaves it; one that is itself an assembly takes the failure
 * on instead, and its use. */
static NSString   *effect_reveal( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGLatent       *latent;
   const BGEntityInfo   *info;
   const TriNode        *schema;
   const TriNode        *list;
   const TriNode        *entry;
   TriContent           *tri;
   BGEntityID           assembly;
   BGEntityID           part;
   uint64_t             seed;
   int64_t              depth;
   int64_t              lo;
   int64_t              hi;
   int64_t              mass;
   int64_t              carved;
   int64_t              worn;
   int64_t              quality;
   const char           *failure;
   char                 culprit[ 64];
   char                 role[ 64];
   char                 kind[ 64];
   BOOL                 any;

   tri      = [world tri];
   assembly = a.roles[ BGRoleDestination];
   latent   = [world record:[world kindNamed:"Latent"] for:assembly];
   info     = [world info:assembly];
   schema   = latent && info ? tri_at( tri, tri_pattern( tri, info->blueprint), "latent") : NULL;
   if( ! schema)
      return( @"there is nothing inside to open");
   seed  = info->seed;
   depth = latent->revealed + 1;

   /* the culprit: decided at the failure, or, a failure a scenario set, now
    * and for good */
   culprit[ 0] = 0;
   failure     = [world textField:"Latent.failure" of:assembly];
   if( failure && *failure)
   {
      if( latent->blamed && *latent->blamed)
         snprintf( culprit, sizeof( culprit), "%s", latent->blamed);
      else
      {
         latent_culprit( world, assembly, latent, schema, failure, 0, 0, culprit, sizeof( culprit));
         [g set:"Latent.blamed" of:BGWhole( assembly) toText:[world intern:culprit]];
      }
   }

   /* the level's parts */
   any    = NO;
   carved = 0;
   for( list = tri_at( tri, schema, "parts"); list && (entry = tri_at( tri, list, "first")); list = tri_at( tri, list, "rest"))
   {
      if( ! tri_node_interval( tri_at( tri, entry, "depth"), &lo, &hi) || lo != depth ||
          ! text_feature( tri, entry, "roleName", role, sizeof( role)) ||
          ! text_feature( tri, entry, "partKind", kind, sizeof( kind)))
         continue;
      any  = YES;
      mass = tri_node_interval( tri_at( tri, tri_pattern( tri, kind), "mass"), &lo, &hi) && lo == hi ? lo : 0;
      part = [g create:[world intern:kind] key:[world intern:role] at:BGPartOf( assembly, [world intern:role], 0)];
      quality = latent_quality( tri, schema, seed, role);
      worn    = role_attrition( tri, schema, role, quality, latent->used, latent->abused);
      if( ! strcmp( role, culprit) && worn < BG_PART_FAILED * 10000)
         worn = BG_PART_FAILED * 10000;
      /* an assembly within: worn by its own parts, as long used; the
       * culprit, it takes the failure on */
      if( tri_at( tri, tri_pattern( tri, kind), "latent"))
      {
         worn = 0;
         [g set:"Latent.used" of:BGWhole( part) to:latent->used];
         [g set:"Latent.abused" of:BGWhole( part) to:latent->abused];
         if( ! strcmp( role, culprit))
         {
            [g set:"Latent.failure" of:BGWhole( part) toText:failure];
            [g set:"Latent.failedAt" of:BGWhole( part) to:latent->failedAt];
         }
      }
      worn = worn > 1000000 ? 1000000 : worn;
      [g set:"Part.attrition" of:BGWhole( part) to:worn];
      [g set:"Part.wear" of:BGWhole( part) to:worn / 10000];
      [g set:"Part.grade" of:BGWhole( part) to:quality];
      [g set:"Part.cameFrom" of:BGWhole( part) to:(int64_t) assembly];
      [g set:"Part.fits" of:BGWhole( part) toText:[world intern:role]];
      [g emit:"revealed" subject:BGWhole( part) other:BGWhole( assembly)];
      carved += mass;
   }
   if( ! any)
      return( @"there is nothing further to open");
   [g set:"Body.mass" of:BGWhole( assembly) to:[world getField:"Body.mass" of:assembly value:&mass] ? mass - carved : 0];
   [g set:"Latent.revealed" of:BGWhole( assembly) to:depth];
   return( nil);
}


/* Replacing a part (provisional, content/machines/latent.tri): the worn one
 * out onto the actor's tile, the spare into its place; a part worn by the
 * assembly's failure, replaced, repairs it. */
static NSString   *effect_replace( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGPart   *worn;
   BGLocation     place;
   BGLocation     floor;
   BGEntityID     e;
   int            k;

   worn  = [world record:[world kindNamed:"Part"] for:a.roles[ BGRoleDestination]];
   place = [world locationOf:a.roles[ BGRoleDestination]];
   if( ! worn || place.form != BGLocationPartOf)
      return( @"there is no part in place to replace");
   for( e = a.roles[ BGRoleActor], k = 0; k < 16 && (floor = [world locationOf:e]).form != BGLocationOnTile; k++)
      e = floor.place;
   if( floor.form != BGLocationOnTile)
      return( @"there is nowhere to put the old part");
   [g move:BGWhole( a.roles[ BGRoleDestination]) to:floor];
   [g move:BGWhole( a.roles[ BGRoleItem]) to:place];
   [g set:"Part.cameFrom" of:BGWhole( a.roles[ BGRoleItem]) to:(int64_t) place.place];
   if( worn->wear >= 60 && [world record:[world kindNamed:"Latent"] for:place.place])
   {
      [g set:"Latent.failure" of:BGWhole( place.place) toText:""];
      [g set:"Latent.blamed" of:BGWhole( place.place) toText:""];
   }
   /* the pump's flow, by the delta: the old part's loss off, the new one's
    * on (COMPONENTS.md §7) */
   {
      const BGPart   *spare;
      BGEntityID     pump;
      int64_t        flow;
      int64_t        delta;
      int            n;

      spare = [world record:[world kindNamed:"Part"] for:a.roles[ BGRoleItem]];
      delta = (worn->wear >= 60 ? 80 : 0) - (spare && spare->wear >= 60 ? 80 : 0);
      for( pump = place.place, n = 0; pump && n < 8 && ! [world record:[world kindNamed:"Pump"] for:pump]; n++)
      {
         const BGPart   *p;
         BGLocation     in;

         in   = [world locationOf:pump];
         p    = [world record:[world kindNamed:"Part"] for:pump];
         pump = in.form == BGLocationPartOf ? in.place : p ? (BGEntityID) p->cameFrom : BGNoEntity;
      }
      if( pump && delta && [world getField:"Pump.flow" of:pump value:&flow])
         [g set:"Pump.flow" of:BGWhole( pump) to:flow + delta > 100 ? 100 : flow + delta < 0 ? 0 : flow + delta];
   }
   return( nil);
}


/* Cutting a strip from a hide (COMPONENTS.md Scenario 3): an individual
 * divided; the strip, a new entity on the floor, carved from it, with a
 * splitFrom edge. */
static NSString   *effect_cut( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   BGLocation   floor;
   BGEntityID   e;
   BGEntityID   strip;
   int64_t      lo;
   int64_t      hi;
   int64_t      mass;
   int64_t      cut;
   int          k;

   cut = tri_node_interval( tri_at( [world tri], tri_pattern( [world tri], "leather_strip"), "mass"), &lo, &hi) && lo == hi
            ? lo : 0;
   if( ! [world getField:"Body.mass" of:a.roles[ BGRoleItem] value:&mass] || mass <= cut)
      return( @"there is not enough of it to cut a strip");
   for( e = a.roles[ BGRoleActor], k = 0; k < 16 && (floor = [world locationOf:e]).form != BGLocationOnTile; k++)
      e = floor.place;
   strip = [g create:"leather_strip" key:"a strip" at:floor];
   [g relate:BGEdgeSplitFrom from:BGWhole( strip) to:BGWhole( a.roles[ BGRoleItem])];
   [g set:"Body.mass" of:BGWhole( a.roles[ BGRoleItem]) to:mass - cut];
   return( nil);
}


/* Issuing a permit (ACTIONS.md §2, an office holder's capability): the
 * place from the command's description; the content, the office's
 * authorization linked to it, and a sealed copy in the grantee's hand. */
static NSString   *effect_issue( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGOfficeHolder   *holder;
   const TriNode          *place;
   TriArena               *arena;
   BGStore                *store;
   BGLocation             at;
   BGEntityID             office;
   BGEntityID             where;
   BGEntityID             content;
   BGEntityID             auth;
   BGEntityID             copy;
   NSUInteger             i;
   int64_t                x;
   int64_t                y;
   int64_t                level;
   int64_t                lo;
   int64_t                hi;
   int32_t                hand;
   const char             *issuer;
   const char             *presses;
   char                   text[ 256];

   holder = [world record:[world kindNamed:"OfficeHolder"] for:a.roles[ BGRoleActor]];
   office = holder ? (BGEntityID) holder->office : BGNoEntity;
   if( ! office || ! [world record:[world kindNamed:"Organization"] for:office])
      return( @"it holds no office that issues permits");
   if( ! a.content || ! *a.content)
      return( @"a permit for where?");
   arena = tri_arena_new();
   place = tri_value( [world tri], a.content, arena, NULL, 0);
   where = BGNoEntity;
   if( place && tri_node_interval( tri_at( [world tri], place, "place.x"), &x, &hi) &&
       tri_node_interval( tri_at( [world tri], place, "place.y"), &y, &hi) &&
       tri_node_interval( tri_at( [world tri], place, "place.level"), &level, &hi))
   {
      store = [world storeForKind:[world kindNamed:"Container"]];
      for( i = 0; i < [store count] && ! where; i++)
      {
         at = [world locationOf:[store entityAtIndex:i]];
         if( at.form == BGLocationOnTile && at.x == x && at.y == y && at.level == level)
            where = [store entityAtIndex:i];
      }
   }
   tri_arena_free( arena);
   (void) lo;
   if( ! where)
      return( @"there is no such place");
   if( (hand = BGFreeHand( world, a.roles[ BGRoleItem])) < 0)
      return( @"they have no hand free to take it");
   issuer  = [world textField:"Organization.orgName" of:office];
   presses = "";
   store   = [world storeForKind:[world kindNamed:"Stamp"]];
   for( i = 0; i < [store count]; i++)
   {
      at = [world locationOf:[store entityAtIndex:i]];
      if( at.form == BGLocationHeldBy && at.place == a.roles[ BGRoleActor])
         presses = [world textField:"Stamp.presses" of:[store entityAtIndex:i]];
   }
   snprintf( text, sizeof( text), "the bearer may enter the place at (%lld, %lld)", (long long) x, (long long) y);
   content = [g create:"content" key:"an issued permit" at:BGLocationMakeNone()];
   [g set:"Information.text" of:BGWhole( content) toText:[world intern:text]];
   [g set:"Information.issuer" of:BGWhole( content) toText:issuer ? issuer : ""];
   auth = [g create:"authorization" key:"an issued authorization" at:BGLocationMakeNone()];
   [g set:"Authorization.grants" of:BGWhole( auth) toText:"enter"];
   [g set:"Authorization.over" of:BGWhole( auth) to:(int64_t) where];
   [g set:"Authorization.grantee" of:BGWhole( auth) to:(int64_t) a.roles[ BGRoleItem]];
   [g relate:BGEdgeAuthorizes from:BGWhole( auth) to:BGWhole( content)];
   copy = [g create:"paper_copy" key:"the issued copy" at:BGHeldBy( a.roles[ BGRoleItem], hand)];
   [g set:"Inscription.inscribed" of:BGWhole( copy) to:(int64_t) content];
   [g set:"Inscription.reads" of:BGWhole( copy) toText:[world intern:text]];
   [g set:"Inscription.claims" of:BGWhole( copy) toText:issuer ? issuer : ""];
   [g set:"Inscription.penned" of:BGWhole( copy)
   toText:[world textField:"Scribe.handwriting" of:a.roles[ BGRoleActor]]
          ? [world textField:"Scribe.handwriting" of:a.roles[ BGRoleActor]] : "an unknown hand"];
   [g set:"Inscription.impression" of:BGWhole( copy) toText:presses ? presses : ""];
   [g emit:"issued" subject:BGWhole( a.roles[ BGRoleActor]) other:BGWhole( a.roles[ BGRoleItem])];
   return( nil);
}


/* Shaping a strip into a seal: it fits a seal's role. */
static NSString   *effect_shape( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g set:"Part.fits" of:BGWhole( a.roles[ BGRoleItem]) toText:"seal"];
   return( nil);
}


/* Servicing a part in place (LATENT_ASSEMBLY.md decision 8): it undoes its
 * role's `mends` per cent of the wear since the part was last serviced
 * (`tended`; since it was made, if never), and that is where it was last
 * serviced now. Quality is untouched: a poor part, serviced, wears as fast
 * again. Worn through, it is past servicing. */
static NSString   *effect_service( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const BGPart         *p;
   const BGEntityInfo   *info;
   const TriNode        *schema;
   TriContent           *tri;
   BGEntityID           part;
   BGLocation           place;
   int64_t              worn;
   int64_t              since;
   int64_t              mends;

   tri   = [world tri];
   part  = a.roles[ BGRoleItem];
   p     = [world record:[world kindNamed:"Part"] for:part];
   place = [world locationOf:part];
   info  = place.form == BGLocationPartOf ? [world info:place.place] : NULL;
   schema = info && [world record:[world kindNamed:"Latent"] for:place.place]
            ? tri_at( tri, tri_pattern( tri, info->blueprint), "latent") : NULL;
   if( ! p || ! schema)
      return( @"there is no part in place to service");
   if( [world record:[world kindNamed:"Latent"] for:part])
      return( @"it has parts of its own to service");
   worn = part_attrition( p);
   if( worn >= BG_PART_FAILED * 10000)
      return( @"it is worn through, past servicing: it has to be replaced");
   mends = int_feature( tri, latent_role( tri, schema, place.role), "mends", 0);
   if( mends <= 0)
      return( @"servicing won't help it");
   since = worn > p->tended ? worn - p->tended : 0;
   worn -= since * mends / 100;
   [g set:"Part.attrition" of:BGWhole( part) to:worn];
   [g set:"Part.wear" of:BGWhole( part) to:worn / 10000];
   [g set:"Part.tended" of:BGWhole( part) to:worn];
   [g emit:"serviced" subject:BGWhole( part) other:BGWhole( a.roles[ BGRoleActor])];
   return( nil);
}


/* Putting a part back into its assembly, in its role. */
static NSString   *effect_install( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   const char   *role;

   role = [world textField:"Part.fits" of:a.roles[ BGRoleItem]];
   if( ! role || ! *role)
      return( @"it fits no place in it");
   [g move:BGWhole( a.roles[ BGRoleItem]) to:BGPartOf( a.roles[ BGRoleDestination], role, 0)];
   [g set:"Part.cameFrom" of:BGWhole( a.roles[ BGRoleItem]) to:(int64_t) a.roles[ BGRoleDestination]];
   return( nil);
}


/* The claims covering an entity (COMPONENTS.md Scenario 3): on it; on an
 * assembly it is part of, or came out of, for kinds that cover parts
 * (content's `coverage`); and on what it was divided from. */
/* Whether claims of this kind cover what is part of what they claim. */
static BOOL   covers_parts( BGWorld *world, const BGClaim *claim)
{
   const TriNode   *c;
   TriIndex        *family;
   size_t          i;
   char            kind[ 64];

   family = tri_family_index( [world tri], "coverage");
   for( i = 0; claim && family && i < tri_index_count( family); i++)
   {
      c = tri_pattern( [world tri], tri_index_tag( family, i));
      if( tri_print( [world tri], tri_at( [world tri], c, "claimKind"), kind, sizeof( kind)) > 2 &&
          ! strncmp( kind + 1, tri_type_name( [world tri], claim->kind) + 1, strlen( kind) - 2) &&
          tri_node_type( tri_at( [world tri], c, "viaPartOf")) == tri_type_named( [world tri], "true"))
         return( YES);
   }
   return( NO);
}


static void   add_claims( BGWorld *world, BGEntityID on, BOOL partsOnly, NSMutableArray *found)
{
   BGEntityID   claims[ 16];
   NSNumber     *n;
   NSUInteger   m;
   NSUInteger   j;

   m = [world edges:BGEdgeClaimSubject to:on into:claims max:16];
   for( j = 0; j < m; j++)
   {
      n = [NSNumber numberWithUnsignedLongLong:claims[ j]];
      if( ( ! partsOnly || covers_parts( world, [world record:[world kindNamed:"Claim"] for:claims[ j]])) &&
          ! [found containsObject:n])
         [found addObject:n];
   }
}


NSArray   *BGClaimsCovering( BGWorld *world, BGEntityID entity)
{
   NSMutableArray   *found;
   const BGPart     *part;
   BGLocation       at;
   BGEntityID       up;
   BGEntityID       source;
   int              k;

   found = [NSMutableArray array];
   /* on it */
   add_claims( world, entity, NO, found);
   /* on what it was divided from */
   if( [world edges:BGEdgeSplitFrom from:entity into:&source max:1])
      add_claims( world, source, NO, found);
   /* on the assemblies it is part of, or came out of, up the chain: only
    * for a part with no claim of its own (COMPONENTS.md decision 11:
    * installing transfers nothing) */
   for( up = [found count] ? BGNoEntity : entity, k = 0; up && k < 8; k++)
   {
      at   = [world locationOf:up];
      part = [world record:[world kindNamed:"Part"] for:up];
      up   = at.form == BGLocationPartOf ? at.place : part ? (BGEntityID) part->cameFrom : BGNoEntity;
      if( up)
         add_claims( world, up, YES, found);
   }
   return( found);
}


/* Whether ownership of it is an open question: claims covering it name
 * different claimants. */
BOOL   BGOwnershipOpen( BGWorld *world, BGEntityID entity)
{
   NSArray      *claims;
   BGEntityID   who;
   BGEntityID   first;
   NSUInteger   i;

   claims = BGClaimsCovering( world, entity);
   first  = BGNoEntity;
   for( i = 0; i < [claims count]; i++)
   {
      if( ! [world edges:BGEdgeClaimant from:(BGEntityID) [[claims objectAtIndex:i] unsignedLongLongValue] into:&who max:1])
         continue;
      if( first && who != first)
         return( YES);
      first = who;
   }
   return( NO);
}


/* What authority there is over an entity (COMPONENTS.md Scenario 2): the
 * reified authorizations over it, each linked to the content that states
 * it. Content no authorization links to confers nothing. */
NSArray   *BGAuthorizationsOver( BGWorld *world, BGEntityID entity)
{
   const BGAuthorization   *auth;
   NSMutableArray          *found;
   BGStore                 *store;
   NSUInteger              i;

   found = [NSMutableArray array];
   store = [world storeForKind:[world kindNamed:"Authorization"]];
   for( i = 0; i < [store count]; i++)
   {
      auth = [store recordAtIndex:i];
      if( (BGEntityID) auth->over == entity)
         [found addObject:[NSNumber numberWithUnsignedLongLong:[store entityAtIndex:i]]];
   }
   return( found);
}


/* ACTIONS.md §3's authorize(action), past its stub: the authorizations
 * granting the actor something over what the action binds. It never blocks
 * an attempt: whether an institution permits or forbids is §6's. */
NSArray   *BGAuthorize( BGWorld *world, BGAction action)
{
   const BGAuthorization   *auth;
   NSMutableArray          *found;
   BGStore                 *store;
   NSUInteger              i;
   int                     r;

   found = [NSMutableArray array];
   store = [world storeForKind:[world kindNamed:"Authorization"]];
   for( i = 0; i < [store count]; i++)
   {
      auth = [store recordAtIndex:i];
      if( (BGEntityID) auth->grantee != action.roles[ BGRoleActor])
         continue;
      for( r = BGRoleItem; r < BGRoleCount; r++)
         if( action.roles[ r] && (BGEntityID) auth->over == action.roles[ r])
         {
            [found addObject:[NSNumber numberWithUnsignedLongLong:[store entityAtIndex:i]]];
            break;
         }
   }
   return( found);
}


BOOL   BGClaimedByAnother( BGWorld *world, BGEntityID entity, BGEntityID who)
{
   const BGClaim   *claim;
   NSArray         *claims;
   BGEntityID      c;
   BGEntityID      claimant;
   NSUInteger      i;

   claims = BGClaimsCovering( world, entity);
   for( i = 0; i < [claims count]; i++)
   {
      c     = (BGEntityID) [[claims objectAtIndex:i] unsignedLongLongValue];
      claim = [world record:[world kindNamed:"Claim"] for:c];
      if( ! claim || claim->kind == (uint32_t) tri_type_named( [world tri], "\"reservation\""))
         continue;      /* a reservation is no claim to it, unless an institution says so */
      if( [world edges:BGEdgeClaimant from:c into:&claimant max:1] && claimant != who)
         return( YES);
   }
   return( NO);
}


NSArray   *BGLawsBroken( BGWorld *world, BGAction action)
{
   const BGLaw      *law;
   NSMutableArray   *broken;
   NSString         *effect;
   BGStore          *laws;
   TriContent       *tri;
   NSUInteger       i;
   BOOL             authorized;
   BOOL             wrong;

   broken     = [NSMutableArray array];
   effect     = BGOperationEffect( world, action.operation);
   tri        = [world tri];
   laws       = [world storeForKind:[world kindNamed:"Law"]];
   authorized = [BGAuthorize( world, action) count] > 0;
   for( i = 0; effect && i < [laws count]; i++)
   {
      law = [laws recordAtIndex:i];
      if( ! law->forbids || ! [effect isEqualToString:[NSString stringWithUTF8String:law->forbids]])
         continue;
      if( law->wrong == (uint32_t) tri_type_named( tri, "\"anothers\""))
         wrong = ! authorized && action.roles[ BGRoleItem] &&
                 BGClaimedByAnother( world, action.roles[ BGRoleItem], action.roles[ BGRoleActor]);
      else
         wrong = ! authorized;
      if( wrong)
         [broken addObject:[NSNumber numberWithUnsignedLongLong:[laws entityAtIndex:i]]];
   }
   return( broken);
}


/* Whether any authorization links to the content. */
BOOL   BGContentAuthorizes( BGWorld *world, BGEntityID content)
{
   NSUInteger   i;

   for( i = 0; i < [world edgeCount]; i++)
      if( [world edgeAt:i]->kind == BGEdgeAuthorizes && [world edgeAt:i]->to == content)
         return( YES);
   return( NO);
}


/* A custody claim (INSTITUTIONS.md decision 7) of the actor's on the
 * entity, in the group. */
static void   take_custody( BGProposalGroup *g, BGEntityID actor, BGEntityID of, const char *key)
{
   BGEntityID   claim;

   claim = [g create:"custody" key:key at:BGLocationMakeNone()];
   [g relate:BGEdgeClaimant from:BGWhole( claim) to:BGWhole( actor)];
   [g relate:BGEdgeClaimSubject from:BGWhole( claim) to:BGWhole( of)];
}


/* Confiscating: the thing out of its holder's hand into the officer's, from
 * where it is (if it has moved meanwhile, the stage fails), and into the
 * watch's custody. */
static NSString   *effect_confiscate( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   int32_t   hand;

   hand = BGFreeHand( world, a.roles[ BGRoleActor]);
   if( hand < 0)
      return( @"no hand is free");
   [g move:BGWhole( a.roles[ BGRoleItem]) to:BGHeldBy( a.roles[ BGRoleActor], hand)
 expecting:[world locationOf:a.roles[ BGRoleItem]]];
   take_custody( g, a.roles[ BGRoleActor], a.roles[ BGRoleItem], "confiscated");
   return( nil);
}


/* Arresting: the person into the watch's custody, an event it perceives;
 * what it does then is its own decision. */
static NSString   *effect_arrest( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   take_custody( g, a.roles[ BGRoleActor], a.roles[ BGRoleItem], "under arrest");
   [g emit:"arrested" subject:BGWhole( a.roles[ BGRoleItem]) other:BGWhole( a.roles[ BGRoleActor]) detail:NULL];
   return( nil);
}


/* Fleeing: four tiles straight away from the one fled, on the map. */
static NSString   *effect_flee( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   BGLocation   at;
   BGLocation   from;
   int32_t      dx;
   int32_t      dy;
   int          k;

   at   = [world locationOf:a.roles[ BGRoleActor]];
   from = [world locationOf:a.roles[ BGRoleItem]];
   if( at.form != BGLocationOnTile || from.form != BGLocationOnTile)
      return( @"one can flee only on the ground");
   dx = at.x > from.x ? 1 : at.x < from.x ? -1 : 0;
   dy = at.y > from.y ? 1 : at.y < from.y ? -1 : 0;
   if( ! dx && ! dy)
      dx = 1;
   for( k = 0; k < 4 && [world isTileX:at.x + dx y:at.y + dy level:at.level]; k++)
   {
      at.x += dx;
      at.y += dy;
   }
   [g move:BGWhole( a.roles[ BGRoleActor]) to:at];
   tread( world, at, g);
   return( nil);
}


/* A blow (AGENCY.md §13): an injury to the one hit, which it feels, and
 * knows who dealt. Hitting oneself does nothing. */
static NSString   *effect_hit( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   int64_t   injury;

   if( a.roles[ BGRoleItem] == a.roles[ BGRoleActor])
      return( @"one cannot hit oneself");
   injury = 0;
   [world getField:"Agent.injury" of:a.roles[ BGRoleItem] value:&injury];
   [g set:"Agent.injury" of:BGWhole( a.roles[ BGRoleItem]) to:injury + 15 > 100 ? 100 : injury + 15];
   [g emit:"struck" subject:BGWhole( a.roles[ BGRoleItem]) other:BGWhole( a.roles[ BGRoleActor]) detail:NULL];
   return( nil);
}


/* Hiring (AGENCY.md decision 15): the one hired is bound to the actor, its
 * loyalty to whoever employs it (decision 12). */
static NSString   *effect_hire( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   BGEntityID   bond;

   if( a.roles[ BGRoleItem] == a.roles[ BGRoleActor])
      return( @"one cannot hire oneself");
   bond = [g create:"work_bond" key:"employment" at:BGLocationMakeNone()];
   [g set:"Bond.bondOf" of:BGWhole( bond) to:(int64_t) a.roles[ BGRoleItem]];
   [g set:"Bond.toward" of:BGWhole( bond) to:(int64_t) a.roles[ BGRoleActor]];
   return( nil);
}


/* Through a door: onto its tile. */
static NSString   *effect_pass( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g move:BGWhole( a.roles[ BGRoleActor]) to:[world locationOf:a.roles[ BGRoleItem]]];
   return( nil);
}


/* Sawing's end: the log is sawn through. */
static NSString   *effect_saw( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g set:"Log.sawn" of:BGWhole( a.roles[ BGRoleDestination]) to:100];
   return( nil);
}


static NSString   *effect_open_door( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g set:"Door.ajar" of:BGWhole( a.roles[ BGRoleItem]) to:1];
   return( nil);
}


/* Dismantling's last stage: the pump is open. */
static NSString   *effect_dismantle( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   [g set:"Pump.opened" of:BGWhole( a.roles[ BGRoleDestination]) to:1];
   return( nil);
}


/* Lighting a stove: it burns, while it has fuel. */
static NSString   *effect_light( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   int64_t   fuel;

   if( ! [world getField:"FuelContainer.fuel" of:a.roles[ BGRoleItem] value:&fuel] || fuel <= 0)
      return( @"there is nothing in it to burn");
   [g set:"Combustor.lit" of:BGWhole( a.roles[ BGRoleItem]) to:1];
   return( nil);
}


/* The region of air (a GasStore) over the entity's tile, or 0. */
BGEntityID   BGAirOver( BGWorld *world, BGEntityID e)
{
   BGLocation   at;
   BGEntityID   p;
   int          k;

   for( p = e, k = 0; p && k < 64; k++)
   {
      at = [world locationOf:p];
      if( at.form == BGLocationOnTile)
         break;
      p = at.place;
   }
   if( at.form != BGLocationOnTile)
      return( BGNoEntity);
   return( [world airRegionAt:at]);       /* the room's air (TERRAIN.md step 3) */
}


/* Tending changes nothing but traces, which the operation declares. */
static NSString   *effect_tend( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   return( nil);
}


/* A rest, rested through: fatigue is gone. */
static NSString   *effect_rest( BGWorld *world, BGAction a, int64_t amount, BGProposalGroup *g)
{
   if( [world record:[world kindNamed:"Agent"] for:a.roles[ BGRoleActor]])
      [g set:"Agent.fatigue" of:BGWhole( a.roles[ BGRoleActor]) to:0];
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
   { "confiscate", effect_confiscate },
   { "arrest",    effect_arrest },
   { "flee",      effect_flee },
   { "hit",       effect_hit },
   { "hire",      effect_hire },
   { "work",      effect_work },
   { "shut",      effect_shut },
   { "dismantle", effect_dismantle },
   { "light",     effect_light },
   { "open_door", effect_open_door },
   { "saw",       effect_saw },
   { "pass",      effect_pass },
   { "copy",      effect_copy },
   { "reveal",    effect_reveal },
   { "replace",   effect_replace },
   { "service",   effect_service },
   { "cut",       effect_cut },
   { "shape",     effect_shape },
   { "install",   effect_install },
   { "issue",     effect_issue },
   { "rest",      effect_rest },
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


BOOL   BGOperationPartial( BGWorld *world, const char *operation, int64_t index,
                           const char **field, int *role, int64_t *whole, int64_t *checkpoints)
{
   const TriNode     *pattern;
   const TriNode     *stage;
   NSMutableString   *path;
   TriContent        *tri;
   int64_t           lo;
   int64_t           hi;
   int64_t           k;
   char              text[ 64];
   size_t            n;

   tri     = [world tri];
   pattern = operation ? tri_pattern( tri, operation) : NULL;
   if( ! pattern)
      return( NO);
   stage = pattern;
   if( tri_at( tri, pattern, "stages.first"))
   {
      path = [NSMutableString stringWithString:@"stages"];
      for( k = 0; k < index; k++)
         [path appendString:@".rest"];
      [path appendString:@".first"];
      stage = tri_at( tri, pattern, [path UTF8String]);
   }
   else if( index)
      return( NO);
   n = stage ? tri_print( tri, tri_at( tri, stage, "partial.field"), text, sizeof( text)) : 0;
   if( n < 3 || n >= sizeof( text) || text[ 0] != '"' ||
       ! tri_node_interval( tri_at( tri, stage, "partial.whole"), &lo, &hi) || lo != hi)
      return( NO);
   text[ n - 1] = 0;
   *field = [world intern:text + 1];
   *whole = lo;
   *role  = BGRoleDestination;
   n      = tri_print( tri, tri_at( tri, stage, "partial.showsOn"), text, sizeof( text));
   if( n > 2 && ! strcmp( text, "\"item\""))
      *role = BGRoleItem;
   *checkpoints = tri_node_interval( tri_at( tri, stage, "checkpoints"), &lo, &hi) && lo == hi ? lo : 0;
   return( YES);
}


int64_t   BGOperationExertion( BGWorld *world, const char *operation, int64_t index)
{
   const TriNode     *pattern;
   const TriNode     *stage;
   NSMutableString   *path;
   TriContent        *tri;
   int64_t           k;
   int64_t           lo;
   int64_t           hi;

   tri     = [world tri];
   pattern = operation ? tri_pattern( tri, operation) : NULL;
   if( ! pattern)
      return( 0);
   stage = pattern;
   if( tri_at( tri, pattern, "stages.first"))
   {
      path = [NSMutableString stringWithString:@"stages"];
      for( k = 0; k < index; k++)
         [path appendString:@".rest"];
      [path appendString:@".first"];
      stage = tri_at( tri, pattern, [path UTF8String]);
   }
   return( stage && tri_node_interval( tri_at( tri, stage, "exertion"), &lo, &hi) && lo == hi ? lo : 0);
}


BOOL   BGOperationFailsHard( BGWorld *world, const char *operation, int64_t index)
{
   const TriNode     *pattern;
   const TriNode     *stage;
   NSMutableString   *path;
   TriContent        *tri;
   int64_t           k;
   char              text[ 16];

   tri     = [world tri];
   pattern = operation ? tri_pattern( tri, operation) : NULL;
   if( ! pattern)
      return( NO);
   stage = pattern;
   if( tri_at( tri, pattern, "stages.first"))
   {
      path = [NSMutableString stringWithString:@"stages"];
      for( k = 0; k < index; k++)
         [path appendString:@".rest"];
      [path appendString:@".first"];
      stage = tri_at( tri, pattern, [path UTF8String]);
   }
   return( stage && tri_print( tri, tri_at( tri, stage, "hard"), text, sizeof( text)) > 2 &&
           ! strcmp( text, "\"fail\""));
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


void   BGLeaveStageTraces( BGWorld *world, BGAction action, int64_t index, BGProposalGroup *group)
{
   const TriNode     *pattern;
   const TriNode     *stage;
   const TriNode     *list;
   const TriNode     *v;
   NSMutableString   *path;
   TriContent        *tri;
   BGEntityID        bearer;
   BGLocation        tile;
   int64_t           lo;
   int64_t           hi;
   int64_t           k;
   char              kind[ 64];
   char              site[ 32];

   tri     = [world tri];
   pattern = action.operation ? tri_pattern( tri, action.operation) : NULL;
   if( ! pattern || ! tri_at( tri, pattern, "stages.first"))
      return;      /* one stage: the operation's own, left when it completes */
   path = [NSMutableString stringWithString:@"stages"];
   for( k = 0; k < index; k++)
      [path appendString:@".rest"];
   [path appendString:@".first"];
   stage = tri_at( tri, pattern, [path UTF8String]);
   for( list = stage ? tri_at( tri, stage, "leaves") : NULL; list && tri_at( tri, list, "first");
        list = tri_at( tri, list, "rest"))
   {
      if( ! text_of( tri, tri_at( tri, list, "first"), "trace", kind, sizeof( kind)) ||
          ! text_of( tri, tri_at( tri, list, "first"), "on", site, sizeof( site)) ||
          ! trace_site( world, action, site, &bearer, &tile))
         continue;
      v = tri_at( tri, tri_at( tri, list, "first"), "strength");
      BGMakeTrace( world, group, kind, bearer, tile, v && tri_node_interval( v, &lo, &hi) && lo == hi ? lo : 0,
                   action.operation);
   }
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
   char               kind[ 64];
   char               site[ 32];
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
      BGMakeTrace( world, group, kind, bearer, tile, strength, action.operation);
   }
   grade( world, action, group);
}


void   BGMakeTrace( BGWorld *world, BGProposalGroup *group, const char *kind, BGEntityID bearer,
                    BGLocation tile, int64_t strength, const char *by)
{
   const TriNode   *v;
   BGEntityID      t;
   int64_t         lo;
   int64_t         hi;
   int64_t         lasts;
   char            key[ 128];

   v     = tri_at( [world tri], tri_pattern( [world tri], kind), "lasts");
   lasts = v && tri_node_interval( v, &lo, &hi) && lo == hi ? lo : 0;
   snprintf( key, sizeof( key), "%s, left by %s", kind, by);
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
   if( action.content && *action.content)
      [g set:"Activity.words" of:BGWhole( a) toText:action.content];
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
   BGEntityID         *mine;
   NSString           *busy;
   NSUInteger         nmine;
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
   running = tri_type_named( tri, "\"running\"");
   mine    = [world copyActivitiesOf:actor count:&nmine];
   busy    = nil;
   for( i = 0; nwanted && ! busy && i < nmine; i++)
   {
      record = [world record:[world kindNamed:"Activity"] for:mine[ i]];
      if( ! record || record->status != (uint32_t) running || mine[ i] == except)
         continue;
      other = [world textField:"Activity.operation" of:mine[ i]];
      nused = providers_of( tri, other, used, 4);
      for( j = 0; j < nwanted && ! busy; j++)
         for( k = 0; k < nused && ! busy; k++)
            if( ! strcmp( wanted[ j], used[ k]))
               busy = [NSString stringWithFormat:@"its %s %s busy with activity %llu (%s)", wanted[ j],
                                                 strcmp( wanted[ j], "voice") ? "are" : "is",
                                                 (unsigned long long) mine[ i], other];
   }
   free( mine);
   return( busy);
}


/* The same, for activities started but not yet committed: an actor's
 * providers are its own to allocate (ACTIONS.md §5), so two activities
 * submitted for one boundary can't both have its hands. */
static NSString   *providers_pending( BGWorld *world, BGCommitter *committer, BGEntityID actor, const char *operation)
{
   const BGProposal   *p;
   BGProposalGroup    *group;
   NSArray            *pending;
   TriContent         *tri;
   NSUInteger         nwanted;
   NSUInteger         nused;
   NSUInteger         i;
   NSUInteger         j;
   NSUInteger         k;
   NSUInteger         q;
   char               wanted[ 4][ 16];
   char               used[ 4][ 16];

   tri     = [world tri];
   nwanted = providers_of( tri, operation, wanted, 4);
   pending = nwanted ? [committer deferredGroups] : nil;
   for( i = 0; i < [pending count]; i++)
   {
      group = [pending objectAtIndex:i];
      if( [group actor] != actor)
         continue;
      for( q = 0; q < [group count]; q++)
      {
         p = &[group proposals][ q];
         if( p->kind != BGProposeSetField || ! p->name || strcmp( p->name, "Activity.operation") ||
             ! BGIsHandle( p->target.entity))
            continue;
         nused = providers_of( tri, p->key, used, 4);
         for( j = 0; j < nwanted; j++)
            for( k = 0; k < nused; k++)
               if( ! strcmp( wanted[ j], used[ k]))
                  return( [NSString stringWithFormat:@"its %s %s taken by %s, starting", wanted[ j],
                                                     strcmp( wanted[ j], "voice") ? "are" : "is", p->key]);
      }
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
   int64_t           rate;
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
       ((reason = BGProvidersBusy( world, action.roles[ BGRoleActor], action.operation, BGNoEntity)) ||
        (reason = providers_pending( world, committer, action.roles[ BGRoleActor], action.operation))))
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
   [group setWeight:BGContestWeight( world, action.roles[ BGRoleActor], action.operation)];
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
      rate = BGGradedRate( world, action, BGWorkRate( world, action.roles[ BGRoleActor], action.operation, 0));
      [group set:"Activity.pace" of:BGWhole( activity) to:rate];
      [group set:"Activity.due" of:BGWhole( activity)
              to:[world time].ms + BGAtRate( duration, rate) + BGAccessDelay( world, action)];
      /* a watch on the floor at the actor's feet */
      {
         const TriNode   *v;
         BGLocation      floor;
         BGEntityID      e;
         int64_t         lo;
         int64_t         hi;
         int             k;

         v = tri_at( [world tri], tri_pattern( [world tri], action.operation), "floodWatch");
         for( e = action.roles[ BGRoleActor], k = 0; k < 16 && (floor = [world locationOf:e]).form != BGLocationOnTile; k++)
            e = floor.place;
         if( v && tri_node_interval( v, &lo, &hi) && lo == hi && lo > 0 && floor.form == BGLocationOnTile)
         {
            [group set:"Activity.watchFloor" of:BGWhole( activity) to:lo];
            [group set:"Activity.watchX" of:BGWhole( activity) to:floor.x];
            [group set:"Activity.watchY" of:BGWhole( activity) to:floor.y];
            [group set:"Activity.watchLevel" of:BGWhole( activity) to:floor.level];
         }
      }
      if( [effect isEqualToString:@"rest"] && BGAirOver( world, action.roles[ BGRoleActor]))
      {
         const BGRespirator   *breather;

         /* resting, with a watch on the air: woken when it grows stuffy, or
          * leaves the band the sleeper rests easy in */
         [group set:"Activity.watchHolder" of:BGWhole( activity) to:(int64_t) BGAirOver( world, action.roles[ BGRoleActor])];
         [group set:"Activity.watchDioxide" of:BGWhole( activity) to:amount > 0 ? amount : 4000];
         breather = [world record:[world kindNamed:"Respirator"] for:action.roles[ BGRoleActor]];
         if( breather && breather->restsAbove)
            [group set:"Activity.watchCool" of:BGWhole( activity) to:breather->restsAbove];
         if( breather && breather->restsBelow)
            [group set:"Activity.watchWarm" of:BGWhole( activity) to:breather->restsBelow];
      }
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
