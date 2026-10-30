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


int64_t   BGTraceGone( BGWorld *world, const BGTrace *trace)
{
   const TriNode   *v;
   int64_t         floor;
   int64_t         lo;
   int64_t         hi;
   int64_t         life;
   int64_t         t;

   v     = trace->traceKind ? tri_at( [world tri], tri_pattern( [world tri], trace->traceKind), "floor") : NULL;
   floor = v && tri_node_interval( v, &lo, &hi) && lo == hi ? lo : 0;
   life  = trace->expires - trace->created;
   if( floor <= 0 || life <= 0)
      return( trace->expires);
   if( trace->magnitude < floor)
      return( trace->created);
   /* strength(t) = magnitude * (expires - t) / life, below floor from about
    * expires - floor * life / magnitude; settled to the first such moment */
   t = trace->expires - floor * life / trace->magnitude;
   while( t > trace->created && BGTraceStrength( trace, t - 1) < floor)
      t--;
   while( t < trace->expires && BGTraceStrength( trace, t) >= floor)
      t++;
   return( t);
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


/* Nothing continuous: only the next trace gone. */
- (BGHorizon) horizonAt:(BGTime) t
{
   const BGTrace   *record;
   BGStore         *traces;
   BGHorizon       h;
   NSUInteger      i;
   int64_t         gone;

   h.safeStep  = BGTimeNever;
   h.nextEvent = BGTimeNever;
   traces      = [self traces];
   for( i = 0; i < [traces count]; i++)
   {
      record = [traces recordAtIndex:i];
      gone   = BGTraceGone( _world, record);
      if( gone > t.ms && gone < h.nextEvent.ms)
         h.nextEvent = BGTimeMake( gone);
   }
   return( h);
}


/* What is gone by t1 is removed at t1, in trace order. */
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
      if( BGTraceGone( world, record) > t1.ms)
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
