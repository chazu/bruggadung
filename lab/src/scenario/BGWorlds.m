#import "BGWorlds.h"


BGProposalGroup   *BGWorkshopSetup( BOOL mixedGoods, BGEntityID h[ 8])
{
   BGProposalGroup   *g;

   g     = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                    source:@"setup: the workshop"];
   h[ 0] = [g create:"bin" key:"bin" at:BGOnTile( 3, 4, 0)];
   h[ 1] = [g create:"nails_30" key:"the smith's nails" at:BGIn( h[ 0])];
   h[ 2] = [g create:"lock" key:"lock" at:BGOnTile( 5, 4, 0)];
   h[ 3] = [g create:"worker" key:"worker" at:BGOnTile( 4, 4, 0)];
   h[ 4] = [g create:"smith" key:"smith" at:BGOnTile( 2, 4, 0)];
   h[ 5] = [g create:"ownership" key:"the smith's claim" at:BGLocationMakeNone()];
   [g set:"Claim.quantity" of:BGWhole( h[ 5]) to:30];
   [g relate:BGEdgeClaimant from:BGWhole( h[ 5]) to:BGWhole( h[ 4])];
   [g relate:BGEdgeClaimSubject from:BGWhole( h[ 5]) to:BGWhole( h[ 1])];
   h[ 6] = BGNoEntity;
   h[ 7] = BGNoEntity;
   if( mixedGoods)
   {
      h[ 6] = [g create:"nails_10" key:"the worker's nails" at:BGHeldBy( h[ 3], 0)];
      h[ 7] = [g create:"ownership" key:"the worker's claim" at:BGLocationMakeNone()];
      [g set:"Claim.quantity" of:BGWhole( h[ 7]) to:10];
      [g relate:BGEdgeClaimant from:BGWhole( h[ 7]) to:BGWhole( h[ 3])];
      [g relate:BGEdgeClaimSubject from:BGWhole( h[ 7]) to:BGWhole( h[ 6])];
   }
   return( g);
}


BGProposalGroup   *BGCisternSetup( BGEntityID h[ 8])
{
   BGProposalGroup   *g;

   g     = [BGProposalGroup groupWithPhase:BGPhaseSystem source:@"setup: the cistern room"];
   h[ 0] = [g create:"cistern" key:"cistern" at:BGOnTile( 5, 5, 0)];
   h[ 1] = [g create:"tap" key:"tap A" at:BGPartOf( h[ 0], "tap", 0)];
   h[ 2] = [g create:"tap" key:"tap B" at:BGPartOf( h[ 0], "tap", 1)];
   h[ 3] = [g create:"crack" key:"crack" at:BGPartOf( h[ 0], "crack", 0)];
   h[ 4] = [g create:"bucket" key:"bucket A" at:BGIn( h[ 1])];
   h[ 5] = [g create:"bucket" key:"bucket B" at:BGIn( h[ 2])];
   h[ 6] = [g create:"agent_a" key:"agent A" at:BGOnTile( 4, 5, 0)];
   h[ 7] = [g create:"agent_b" key:"agent B" at:BGOnTile( 6, 5, 0)];
   return( g);
}
