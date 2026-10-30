#import "BGLatentKind.h"

#import "BGProposalGroup.h"


static BOOL   text_of( TriContent *tri, const TriNode *node, const char *path, char *buf, size_t len)
{
   size_t   n;

   n = node ? tri_print( tri, tri_at( tri, node, path), buf, len) : 0;
   if( n < 2 || n >= len || buf[ 0] != '"')
      return( NO);
   memmove( buf, buf + 1, n - 2);
   buf[ n - 2] = 0;
   return( YES);
}


/* The part in the role inside the assembly, or BGNoEntity. */
static BGEntityID   part_in( BGWorld *world, BGEntityID assembly, const char *role)
{
   BGStore      *parts;
   BGLocation   at;
   NSUInteger   i;

   parts = [world storeForKind:[world kindNamed:"Part"]];
   for( i = 0; i < [parts count]; i++)
   {
      at = [world locationOf:[parts entityAtIndex:i]];
      if( at.form == BGLocationPartOf && at.place == assembly && ! strcmp( at.role, role))
         return( [parts entityAtIndex:i]);
   }
   return( BGNoEntity);
}


@implementation BGLatentKind

/* A part out of its assembly for the first time takes its share of the
 * assembly's heat, by heat capacity (DOMAIN_SIMULATION.md Scenario 2, check
 * 3): the heat and the capacity both move, so neither the total nor either
 * one's temperature changes. */
- (void) splitHeatOf:(BGEntityID) part
           committer:(BGCommitter *) committer
               world:(BGWorld *) world
               cause:(uint64_t) cause
{
   const BGPart          *p;
   const BGThermalBody   *mine;
   const BGThermalBody   *whole;
   BGProposalGroup       *g;
   BGLocation            at;
   BGEntityID            assembly;
   int64_t               share;

   p = [world record:[world kindNamed:"Part"] for:part];
   if( ! p || p->detached || ! p->cameFrom)
      return;
   assembly = (BGEntityID) p->cameFrom;
   at       = [world locationOf:part];
   if( at.form == BGLocationPartOf && at.place == assembly)
      return;
   g = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                source:[NSString stringWithFormat:@"part %llu leaves assembly %llu",
                                                                  (unsigned long long) part, (unsigned long long) assembly]];
   [g setCause:cause];
   [g set:"Part.detached" of:BGWhole( part) to:1];
   mine  = [world record:[world kindNamed:"ThermalBody"] for:part];
   whole = [world record:[world kindNamed:"ThermalBody"] for:assembly];
   if( mine && whole && whole->heatCapacity > mine->heatCapacity)
   {
      share = whole->heat * mine->heatCapacity / whole->heatCapacity;
      [g set:"ThermalBody.heat" of:BGWhole( part) to:mine->heat + share];
      [g set:"ThermalBody.heat" of:BGWhole( assembly) to:whole->heat - share];
      [g set:"ThermalBody.heatCapacity" of:BGWhole( assembly) to:whole->heatCapacity - mine->heatCapacity];
   }
   [committer submit:g];
}

- (void) committer:(BGCommitter *) committer
     reactToEvent:(const BGEvent *) event
            world:(BGWorld *) world
{
   const BGLatent   *latent;
   const TriNode    *schema;
   BGProposalGroup  *g;
   BGStore          *assemblies;
   BGEntityID       assembly;
   BGEntityID       through;
   BGEntityID       leak;
   TriContent       *tri;
   NSUInteger       i;
   int64_t          wear;
   int64_t          rate;
   char             out[ 64];
   char             via[ 64];

   if( strcmp( event->kind, "moved"))
      return;
   [self splitHeatOf:event->subject committer:committer world:world cause:event->index];
   tri        = [world tri];
   assemblies = [world storeForKind:[world kindNamed:"Latent"]];
   for( i = 0; i < [assemblies count]; i++)
   {
      assembly = [assemblies entityAtIndex:i];
      latent   = [assemblies recordAtIndex:i];
      if( latent->leaking || ! latent->riser || ! [world isLive:(BGEntityID) latent->riser])
         continue;
      schema = tri_at( tri, tri_pattern( tri, [world info:assembly]->blueprint), "latent");
      if( ! text_of( tri, schema, "pathWhenOut", out, sizeof( out)) || ! text_of( tri, schema, "pathThrough", via, sizeof( via)))
         continue;
      /* revealed, and the part that closed the path out of it */
      if( ! (through = part_in( world, assembly, via)) || part_in( world, assembly, out))
         continue;
      wear = 0;
      [world getField:"Part.wear" of:through value:&wear];
      rate = wear > 50 ? (wear - 50) * 200 : 0;          /* mL a minute */
      g    = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                      source:[NSString stringWithFormat:@"assembly %llu: its %s out, a path through its %s "
                                                                        @"(wear %lld): %lld mL a minute",
                                                                        (unsigned long long) assembly, out, via,
                                                                        (long long) wear, (long long) rate]];
      [g setCause:event->index];
      [g set:"Latent.leaking" of:BGWhole( assembly) to:1];
      if( rate > 0)
      {
         leak = [g create:"leak" key:"the path back" at:BGPartOf( (BGEntityID) latent->riser, "leak", 0)];
         [g set:"Tap.rate" of:BGWhole( leak) to:rate];
      }
      [committer submit:g];
   }
}

@end
