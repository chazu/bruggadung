#import "BGTraces.h"


int64_t   BGTraceStrength( const BGTrace *trace, int64_t t)
{
   int64_t   life;

   if( t >= trace->expires)
      return( 0);
   life = trace->expires - trace->created;
   if( life <= 0 || t <= trace->created)
      return( trace->magnitude);
   return( trace->magnitude * (trace->expires - t) / life);
}


@implementation BGTraces

- (id) initWithWorld:(BGWorld *) world
{
   if( ! (self = [super init]))
      return( nil);
   _world = [world retain];
   return( self);
}


- (void) dealloc
{
   [_world release];
   [super dealloc];
}


- (NSString *) name
{
   return( @"traces");
}


- (BGStore *) traces
{
   return( [_world storeForKind:[_world kindNamed:"Trace"]]);
}


- (BOOL) isActive
{
   return( [[self traces] count] > 0);
}


/* Nothing continuous: only the next expiry. */
- (BGHorizon) horizonAt:(BGTime) t
{
   const BGTrace   *record;
   BGStore         *traces;
   BGHorizon       h;
   NSUInteger      i;

   h.safeStep  = BGTimeNever;
   h.nextEvent = BGTimeNever;
   traces      = [self traces];
   for( i = 0; i < [traces count]; i++)
   {
      record = [traces recordAtIndex:i];
      if( record->expires > t.ms && record->expires < h.nextEvent.ms)
         h.nextEvent = BGTimeMake( record->expires);
   }
   return( h);
}


/* What has run out by t1 is removed at t1, in trace order. */
- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
{
   const BGTrace     *record;
   BGProposalGroup   *group;
   BGStore           *traces;
   NSUInteger        i;

   traces = [self traces];
   group  = nil;
   for( i = 0; i < [traces count]; i++)
   {
      record = [traces recordAtIndex:i];
      if( record->expires > t1.ms)
         continue;
      if( ! group)
         group = [BGProposalGroup groupWithPhase:BGPhaseProcess source:@"traces: run out"];
      [group destroy:BGWhole( [traces entityAtIndex:i]) reason:"run out"];
   }
   if( group)
      [committer submit:group];
}


- (void) checkInAll
{
}


- (NSArray *) savedState
{
   return( [NSArray array]);
}


- (void) restoreSavedState:(NSArray *) lines
{
}

@end
