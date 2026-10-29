#import "BGActions.h"

#import "BGView.h"
#import "BGProposalGroup.h"

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


TriMatch   BGMatchAction( BGWorld *world, BGAction action, TriMatchResult *result, NSString **reason)
{
   const TriNode     *pattern;
   const TriNode     *description;
   NSMutableString   *expr;
   TriContent        *tri;
   TriArena          *arena;
   TriMatch          match;
   BGView            *view;
   NSString          *d;
   char              duration[ 128];
   char              effect[ 64];
   char              err[ 256];
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
   /* the operation's own features, as the pattern has them; the roles, as the actor sees them */
   tri_print( tri, tri_at( tri, pattern, "effect"), effect, sizeof( effect));
   expr = [NSMutableString stringWithFormat:@"#Operation & { effect: %s, ", effect];
   if( tri_at( tri, pattern, "duration"))
   {
      tri_print( tri, tri_at( tri, pattern, "duration"), duration, sizeof( duration));
      [expr appendFormat:@"duration: %s, ", duration];
   }
   [expr appendString:@"roles: {"];
   for( r = 0; r < BGRoleCount; r++)
   {
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
      d = [view describeEntity:action.roles[ r]];
      [expr appendFormat:@" %s: %@,", BGRoleNames[ r], d];
   }
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
         [s appendFormat:@" %s %llu", BGRoleNames[ r], (unsigned long long) _items[ i].roles[ r]];
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
   [g move:BGWhole( a.roles[ BGRoleItem]) to:BGHeldBy( a.roles[ BGRoleActor], hand)];
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


BGProposalGroup   *BGPerform( BGWorld *world, BGCommitter *committer, BGAction action, int64_t amount,
                              NSString **error)
{
   BGProposalGroup   *group;
   TriMatchResult    result;
   NSString          *effect;
   NSString          *reason;
   NSString          *source;
   BGEntityID        activity;
   int64_t           duration;
   int               r;

   reason = nil;
   if( BGMatchAction( world, action, &result, &reason) == TRI_INCOMPATIBLE)
   {
      if( error)
         *error = reason;
      return( nil);
   }
   effect   = BGOperationEffect( world, action.operation);
   duration = BGOperationDuration( world, action.operation);
   source   = [NSString stringWithFormat:@"%llu: %s", (unsigned long long) action.roles[ BGRoleActor], action.operation];
   for( r = BGRoleItem; r < BGRoleCount; r++)
      if( action.roles[ r])
         source = [source stringByAppendingFormat:@" %s %llu", BGRoleNames[ r], (unsigned long long) action.roles[ r]];
   if( amount)
      source = [source stringByAppendingFormat:@" (%lld)", (long long) amount];
   group = [BGProposalGroup groupWithPhase:BGPhaseAction
                                    source:source];
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
      /* a timed activity: the effect commits when it is due */
      activity = start_activity( world, action, amount, group);
      [group set:"Activity.due" of:BGWhole( activity) to:[world time].ms + duration];
   }
   else if( (reason = BGApplyEffect( world, action, amount, group)))
   {
      if( error)
         *error = reason;
      return( nil);
   }
   [committer submit:group];
   return( group);
}
