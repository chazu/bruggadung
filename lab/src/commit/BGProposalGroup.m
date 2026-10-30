#import "BGProposalGroup.h"

#include <stdlib.h>


const char   *BGPhaseNames[ BGPhaseCount] =
{
   "process",
   "action",
   "system"
};


@implementation BGProposalGroup

+ (instancetype) groupWithPhase:(BGPhase) phase
                         source:(NSString *) source
{
   BGProposalGroup   *group;

   group          = [[self new] autorelease];
   group->_phase  = phase;
   group->_source = [source copy];
   return( group);
}


- (void) dealloc
{
   NSUInteger   i;

   for( i = 0; i < _nstrings; i++)
      free( _strings[ i]);
   free( _strings);
   free( _proposals);
   free( _ids);
   [_source release];
   [_rejection release];
   [super dealloc];
}


- (BGPhase) phase
{
   return( _phase);
}


- (NSString *) source
{
   return( _source);
}


- (uint64_t) cause
{
   return( _cause);
}


- (void) setCause:(uint64_t) cause
{
   _cause = cause;
}


- (BGEntityID) actor
{
   return( _actor);
}


- (void) setActor:(BGEntityID) actor
{
   _actor = actor;
}


- (uint64_t) weight
{
   return( _weight);
}


- (void) setWeight:(uint64_t) weight
{
   _weight = weight;
}


- (NSUInteger) count
{
   return( _count);
}


- (const BGProposal *) proposals
{
   return( _proposals);
}


- (BGEntityID) newHandle
{
   return( BGHandle( ++_handles));
}


- (uint64_t) handleCount
{
   return( _handles);
}


- (void) setHandleCount:(uint64_t) count
{
   _handles = count;
}


/* The group keeps its own copies of the strings its proposals name. */
static const char   *keep( BGProposalGroup *self, const char *s)
{
   if( ! s)
      return( NULL);
   self->_strings                    = realloc( self->_strings, sizeof( char *) * (self->_nstrings + 1));
   self->_strings[ self->_nstrings]  = strdup( s);
   return( self->_strings[ self->_nstrings++]);
}


- (void) addProposal:(BGProposal) proposal
{
   if( _count == _capacity)
   {
      _capacity  = _capacity ? _capacity * 2 : 8;
      _proposals = realloc( _proposals, sizeof( BGProposal) * _capacity);
   }
   proposal.name        = keep( self, proposal.name);
   proposal.key         = keep( self, proposal.key);
   _proposals[ _count++] = proposal;
}


static BGProposal   proposal( BGProposalKind kind, BGRef target)
{
   BGProposal   p;

   memset( &p, 0, sizeof( p));
   p.kind   = kind;
   p.target = target;
   return( p);
}


- (BGEntityID) create:(const char *) blueprint
                  key:(const char *) key
                   at:(BGLocation) location
{
   BGProposal   p;

   p          = proposal( BGProposeCreate, BGWhole( BGNoEntity));
   p.name     = blueprint;
   p.key      = key;
   p.location = location;
   p.handle   = [self newHandle];
   [self addProposal:p];
   return( p.handle);
}


- (void) destroy:(BGRef) target
          reason:(const char *) reason
{
   BGProposal   p;

   p      = proposal( BGProposeDestroy, target);
   p.name = reason;
   [self addProposal:p];
}


- (void) set:(const char *) field
          of:(BGRef) target
          to:(int64_t) value
{
   BGProposal   p;

   p       = proposal( BGProposeSetField, target);
   p.name  = field;
   p.value = value;
   [self addProposal:p];
}


- (void) set:(const char *) field
          of:(BGRef) target
      toText:(const char *) text
{
   BGProposal   p;

   p      = proposal( BGProposeSetField, target);
   p.name = field;
   p.key  = text ? text : "";
   [self addProposal:p];
}


- (void) move:(BGRef) target
           to:(BGLocation) location
{
   BGProposal   p;

   p          = proposal( BGProposeMove, target);
   p.location = location;
   [self addProposal:p];
}


- (void) move:(BGRef) target
           to:(BGLocation) location
    expecting:(BGLocation) from
{
   BGProposal   p;

   p          = proposal( BGProposeMove, target);
   p.location = location;
   p.expected = from;
   p.expects  = YES;
   [self addProposal:p];
}


- (BGEntityID) split:(BGRef) stack
               count:(int64_t) count
                  to:(BGLocation) location
{
   BGProposal   p;

   p          = proposal( BGProposeSplit, stack);
   p.value    = count;
   p.location = location;
   p.handle   = [self newHandle];
   [self addProposal:p];
   return( p.handle);
}


- (void) merge:(BGRef) target
          into:(BGRef) stack
{
   BGProposal   p;

   p       = proposal( BGProposeMerge, target);
   p.other = stack;
   [self addProposal:p];
}


- (void) relate:(BGEdgeKind) edge
           from:(BGRef) from
             to:(BGRef) to
{
   BGProposal   p;

   p       = proposal( BGProposeAddEdge, from);
   p.other = to;
   p.edge  = edge;
   [self addProposal:p];
}


- (void) unrelate:(BGEdgeKind) edge
             from:(BGRef) from
               to:(BGRef) to
{
   BGProposal   p;

   p       = proposal( BGProposeRemoveEdge, from);
   p.other = to;
   p.edge  = edge;
   [self addProposal:p];
}


- (void) emit:(const char *) kind
      subject:(BGRef) subject
        other:(BGRef) other
{
   BGProposal   p;

   p       = proposal( BGProposeEvent, subject);
   p.other = other;
   p.name  = kind;
   [self addProposal:p];
}


- (void) emit:(const char *) kind
      subject:(BGRef) subject
        other:(BGRef) other
       amount:(int64_t) amount
       detail:(const char *) detail
{
   BGProposal   p;

   p       = proposal( BGProposeEvent, subject);
   p.other = other;
   p.name  = kind;
   p.value = amount;
   p.key   = detail;
   [self addProposal:p];
}


- (void) emit:(const char *) kind
      subject:(BGRef) subject
        other:(BGRef) other
       detail:(const char *) detail
{
   BGProposal   p;

   p       = proposal( BGProposeEvent, subject);
   p.other = other;
   p.name  = kind;
   p.key   = detail;          /* an event has no key: its detail rides there, and saves keep it */
   [self addProposal:p];
}


- (BOOL) applied
{
   return( _applied);
}


- (NSString *) rejection
{
   return( _rejection);
}


- (uint64_t) position
{
   return( _position);
}


- (BGEntityID) idFor:(BGEntityID) handle
{
   uint64_t   n;

   if( ! BGIsHandle( handle))
      return( handle);
   n = handle & ~BGHandleBit;
   if( n == 0 || n > _nids)
      return( BGNoEntity);
   return( _ids[ n - 1]);
}


- (void) setApplied:(BOOL) applied
          rejection:(NSString *) rejection
           position:(uint64_t) position
{
   _applied  = applied;
   _position = position;
   [_rejection autorelease];
   _rejection = [rejection copy];
}


- (void) setID:(BGEntityID) entity
     forHandle:(BGEntityID) handle
{
   uint64_t     n;
   NSUInteger   i;

   n = handle & ~BGHandleBit;
   if( ! BGIsHandle( handle) || n == 0)
      return;
   if( n > _nids)
   {
      _ids = realloc( _ids, sizeof( BGEntityID) * n);
      for( i = _nids; i < n; i++)
         _ids[ i] = BGNoEntity;
      _nids = (NSUInteger) n;
   }
   _ids[ n - 1] = entity;
}

@end
