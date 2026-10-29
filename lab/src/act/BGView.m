#import "BGView.h"

#include <stdio.h>
#include <stdlib.h>


int32_t   BGFreeHands( BGWorld *world, BGEntityID agent)
{
   const BGAgent   *a;
   BGEntityID      held[ 8];
   NSUInteger      n;

   a = [world record:[world kindNamed:"Agent"] for:agent];
   if( ! a)
      return( 0);
   n = [world entitiesAt:agent
                    form:BGLocationHeldBy
                    into:held
                     max:8];
   return( (int32_t) a->hands - (int32_t) n);
}


int32_t   BGFreeHand( BGWorld *world, BGEntityID agent)
{
   const BGAgent   *a;
   BGEntityID      held[ 8];
   NSUInteger      i;
   NSUInteger      n;
   int32_t         hand;
   BOOL            taken;

   a = [world record:[world kindNamed:"Agent"] for:agent];
   if( ! a)
      return( -1);
   n = [world entitiesAt:agent
                    form:BGLocationHeldBy
                    into:held
                     max:8];
   for( hand = 0; hand < a->hands; hand++)
   {
      taken = NO;
      for( i = 0; i < n && i < 8 && ! taken; i++)
         taken = [world locationOf:held[ i]].slot == hand;
      if( ! taken)
         return( hand);
   }
   return( -1);
}


@implementation BGView

+ (instancetype) viewOf:(BGEntityID) actor
                inWorld:(BGWorld *) world
{
   BGView   *view;

   view         = [[self new] autorelease];
   view->_world = [world retain];
   view->_actor = actor;
   return( view);
}


- (void) dealloc
{
   [_world release];
   [super dealloc];
}


- (BGEntityID) actor
{
   return( _actor);
}


/* The tile something is on, through whatever holds it; NO if none. */
static BOOL   ground_tile( BGWorld *world, BGEntityID e, BGLocation *tile)
{
   BGLocation   loc;
   NSUInteger   guard;

   for( guard = 0; guard < 64; guard++)
   {
      loc = [world locationOf:e];
      if( loc.form == BGLocationOnTile)
      {
         *tile = loc;
         return( YES);
      }
      if( loc.form == BGLocationNone || ! loc.place)
         return( NO);
      e = loc.place;
   }
   return( NO);
}


- (BOOL) canReach:(BGEntityID) entity
{
   BGLocation   here;
   BGLocation   there;

   if( ! [_world isLive:entity] || ! [_world isPhysical:entity])
      return( NO);
   if( ! ground_tile( _world, _actor, &here) || ! ground_tile( _world, entity, &there))
      return( NO);
   return( here.level == there.level && abs( here.x - there.x) <= 1 && abs( here.y - there.y) <= 1);
}


- (NSUInteger) reachable:(BGEntityID *) out
                     max:(NSUInteger) max
{
   BGStore      *bodies;
   BGEntityID   e;
   NSUInteger   i;
   NSUInteger   n;

   bodies = [_world storeForKind:[_world kindNamed:"Body"]];
   n      = 0;
   for( i = 0; i < [bodies count]; i++)
   {
      e = [bodies entityAtIndex:i];
      if( ! [self canReach:e])
         continue;
      if( n < max)
         out[ n] = e;
      n++;
   }
   return( n);
}


static void   append_text( NSMutableString *s, const char *text)
{
   [s appendString:@"\""];
   for( ; text && *text; text++)
      if( *text != '"' && *text != '\n')
         [s appendFormat:@"%c", *text];
   [s appendString:@"\""];
}


static void   append_place( NSMutableString *s, BGLocation loc)
{
   switch( loc.form)
   {
   case BGLocationOnTile:
      [s appendFormat:@"#OnTile & { x: %d, y: %d, level: %d }", loc.x, loc.y, loc.level];
      break;
   case BGLocationIn:
      [s appendFormat:@"#Inside & { container: ref(%llu) }", (unsigned long long) loc.place];
      break;
   case BGLocationHeldBy:
      [s appendFormat:@"#Held & { by: ref(%llu), hand: %d }", (unsigned long long) loc.place, loc.slot];
      break;
   case BGLocationPartOf:
      [s appendFormat:@"#Installed & { assembly: ref(%llu), role: ", (unsigned long long) loc.place];
      append_text( s, loc.role);
      [s appendFormat:@", index: %d }", loc.slot];
      break;
   default:
      [s appendString:@"#Place"];
      break;
   }
}


- (NSString *) describeEntity:(BGEntityID) entity
{
   const BGEntityInfo        *info;
   const BGComponentInfo     *kind;
   const BGFieldInfo         *f;
   const TriNode             *pattern;
   const uint8_t             *record;
   NSMutableString           *s;
   char                      buf[ 64];
   size_t                    i;
   NSUInteger                k;

   info = [_world info:entity];
   if( ! info)
      return( nil);
   /* the type of the blueprint it was built from */
   pattern = tri_pattern( [_world tri], info->blueprint);
   s       = [NSMutableString stringWithFormat:@"%s & { id: ref(%llu)",
                                               pattern ? tri_type_name( [_world tri], tri_node_type( pattern)) : "#Thing",
                                               (unsigned long long) entity];
   if( [_world isPhysical:entity])
   {
      [s appendString:@", place: "];
      append_place( s, [_world locationOf:entity]);
   }
   if( [_world record:[_world kindNamed:"Agent"] for:entity])
      [s appendFormat:@", freeHands: %d", BGFreeHands( _world, entity)];
   /* the perceivable fields of each component; the rest stay open */
   for( k = 0; k < [_world kindCount]; k++)
   {
      record = [_world record:k for:entity];
      if( ! record)
         continue;
      kind = [_world kindInfo:k];
      for( i = 0; i < kind->nfields; i++)
      {
         f = &kind->fields[ i];
         if( ! strstr( f->flags, "perceive"))
            continue;
         [s appendFormat:@", %s: ", f->name];
         switch( f->value)
         {
         case BG_VALUE_QUANTITY:
            tri_format_quantity( f->kind, *(const int64_t *) (record + f->offset), buf, sizeof( buf));
            [s appendFormat:@"%s", buf];
            break;
         case BG_VALUE_TYPE:
            [s appendFormat:@"%s", tri_type_name( [_world tri], *(const uint32_t *) (record + f->offset))];
            break;
         case BG_VALUE_BOOL:
            [s appendString:*(const bool *) (record + f->offset) ? @"true" : @"false"];
            break;
         case BG_VALUE_REF:
            [s appendFormat:@"ref(%llu)", (unsigned long long) *(const uint64_t *) (record + f->offset)];
            break;
         case BG_VALUE_TEXT:
            append_text( s, *(const char *const *) (record + f->offset));
            break;
         default:
            [s appendString:@"_"];
            break;
         }
      }
   }
   [s appendString:@" }"];
   return( s);
}

@end
