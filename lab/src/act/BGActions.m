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
   tri_print( tri, tri_at( tri, pattern, "effect"), effect, sizeof( effect));
   expr = [NSMutableString stringWithFormat:@"#Operation & { effect: %s, roles: {", effect];
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
      d = [view describeEntity:action.roles[ r]];
      [expr appendFormat:@" %s: %@,", BGRoleNames[ r], d];
   }
   [expr appendString:@" } }"];
   arena       = tri_arena_new();
   description = tri_value( tri, [expr UTF8String], arena, err, sizeof( err));
   if( ! description)
   {
      if( reason)
         *reason = [NSString stringWithFormat:@"the description does not build: %s", err];
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
};


BGProposalGroup   *BGPerform( BGWorld *world, BGCommitter *committer, BGAction action, int64_t amount,
                              NSString **error)
{
   BGProposalGroup   *group;
   TriMatchResult    result;
   NSString          *reason;
   NSString          *source;
   char              effect[ 64];
   size_t            i;
   size_t            n;
   int               r;

   reason = nil;
   if( BGMatchAction( world, action, &result, &reason) == TRI_INCOMPATIBLE)
   {
      if( error)
         *error = reason;
      return( nil);
   }
   n = tri_print( [world tri], tri_at( [world tri], tri_pattern( [world tri], action.operation), "effect"),
                  effect, sizeof( effect));
   /* the effect's name, without its quotes */
   if( n >= 2 && n < sizeof( effect))
   {
      memmove( effect, effect + 1, n - 2);
      effect[ n - 2] = 0;
   }
   source = [NSMutableString stringWithFormat:@"%llu: %s", (unsigned long long) action.roles[ BGRoleActor],
                                              action.operation];
   for( r = BGRoleItem; r < BGRoleCount; r++)
      if( action.roles[ r])
         source = [source stringByAppendingFormat:@" %s %llu", BGRoleNames[ r], (unsigned long long) action.roles[ r]];
   if( amount)
      source = [source stringByAppendingFormat:@" (%lld)", (long long) amount];
   group = [BGProposalGroup groupWithPhase:BGPhaseAction
                                    source:source];
   for( i = 0; i < sizeof( effects) / sizeof( effects[ 0]); i++)
      if( ! strcmp( effects[ i].name, effect))
         break;
   if( i == sizeof( effects) / sizeof( effects[ 0]))
   {
      if( error)
         *error = [NSString stringWithFormat:@"no code for the effect %s", effect];
      return( nil);
   }
   reason = effects[ i].function( world, action, amount, group);
   if( reason)
   {
      if( error)
         *error = reason;
      return( nil);
   }
   [committer submit:group];
   return( group);
}
