/*
 * The laboratory's worlds, as the system groups that set them up. The
 * scenarios and interactive sessions build them the same way, so the same
 * world seed gives the same entities and IDs.
 */
#import "BGProposalGroup.h"


/* The workshop of COMPONENTS.md Scenario 1. Handles: 0 bin, 1 the smith's
 * nails, 2 lock, 3 worker, 4 smith, 5 the smith's claim; with mixed goods
 * also 6 the worker's nails (in the worker's hand) and 7 the worker's claim. */
BGProposalGroup   *BGWorkshopSetup( BOOL mixedGoods, BGEntityID handles[ 8]);

/* The cistern room of DOMAIN_SIMULATION.md Scenario 3. Handles: 0 cistern,
 * 1 tap A, 2 tap B, 3 crack, 4 bucket A, 5 bucket B, 6 agent A, 7 agent B. */
BGProposalGroup   *BGCisternSetup( BGEntityID handles[ 8]);
