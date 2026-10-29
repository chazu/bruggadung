#import "BGPlay.h"

#import "BGTest.h"
#import "BGView.h"
#import "BGWorlds.h"
#import "BGSave.h"

#include <stdio.h>
#include <stdlib.h>


@implementation BGPlay

- (void) buildOn:(BGWorld *) world
{
   [_world autorelease];
   [_committer autorelease];
   [_scheduler autorelease];
   [_fluid autorelease];
   [_activities autorelease];
   _world      = [world retain];
   _committer  = [BGTestCommitter( world) retain];
   _fluid      = [[BGFluidDomain alloc] initWithWorld:world];
   _activities = [[BGActivities activitiesWithWorld:world committer:_committer] retain];
   _scheduler  = [[BGScheduler alloc] initWithWorld:world committer:_committer];
   [_scheduler addDomain:_fluid];
   [_scheduler setActivities:_activities];
   [_scheduler setInputs:self];
   _traceShown = 0;
}


+ (instancetype) playWorld:(NSString *) name
                      seed:(uint64_t) seed
                     error:(NSString **) error
{
   BGPlay            *play;
   BGWorld           *world;
   BGProposalGroup   *setup;
   BGEntityID        h[ 8];

   if( ! [name isEqualToString:@"workshop"] && ! [name isEqualToString:@"cistern"])
   {
      if( error)
         *error = [NSString stringWithFormat:@"there is no world %@ (workshop, cistern)", name];
      return( nil);
   }
   world = BGTestWorld( seed);
   if( ! world)
   {
      if( error)
         *error = @"the content does not load";
      return( nil);
   }
   play        = [[self new] autorelease];
   play->_name = [name copy];
   play->_out  = [NSMutableString new];
   [play buildOn:world];
   setup = [name isEqualToString:@"workshop"] ? BGWorkshopSetup( NO, h) : BGCisternSetup( h);
   [play->_committer submit:setup];
   play->_inputDue = YES;
   [play->_scheduler stepUntil:[world time]];
   play->_actor      = [setup idFor:[name isEqualToString:@"workshop"] ? h[ 3] : h[ 6]];
   play->_traceShown = [[play->_committer trace] count];
   [play->_out appendFormat:@"The %@, seed %llu. You are %llu. Type help for the commands.\n", name,
                            (unsigned long long) seed, (unsigned long long) play->_actor];
   return( play);
}


- (void) dealloc
{
   [_name release];
   [_world release];
   [_committer release];
   [_scheduler release];
   [_fluid release];
   [_activities release];
   [_menu release];
   [_out release];
   [super dealloc];
}


- (BGWorld *) world
{
   return( _world);
}


- (BGEntityID) actor
{
   return( _actor);
}


- (NSString *) takeOutput
{
   NSString   *s;

   s = [[_out copy] autorelease];
   [_out setString:@""];
   return( s);
}


/* --- inputs: a command performed now commits at a boundary now ----------------- */

- (BGTime) nextInputTime
{
   return( _inputDue ? [_world time] : BGTimeNever);
}


- (void) deliverInputsAt:(BGTime) t
                   world:(BGWorld *) world
               committer:(BGCommitter *) committer
{
   _inputDue = NO;      /* the groups were submitted when the command was given */
}


- (void) showTrace
{
   NSArray      *trace;
   NSUInteger   i;

   trace = [_committer trace];
   for( i = _traceShown; i < [trace count]; i++)
      [_out appendFormat:@"%@\n", [trace objectAtIndex:i]];
   _traceShown = [trace count];
}


- (void) perform:(BGAction) action
          amount:(int64_t) amount
{
   BGProposalGroup   *g;
   NSString          *error;

   error = nil;
   g     = BGPerform( _world, _committer, action, amount, &error);
   if( ! g)
   {
      [_out appendFormat:@"You can't: %@.\n", error];
      return;
   }
   _inputDue = YES;
   [_scheduler stepUntil:[_world time]];
   [self showTrace];
}


/* --- looking -------------------------------------------------------------------- */

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


- (char) glyphOf:(BGEntityID) e
{
   static const struct { const char *kind; char glyph; } glyphs[] =
   {
      { "Agent", 'A' }, { "Assembly", 'm' }, { "Container", 'u' }, { "WaterStore", 'w' }, { "Stack", '*' },
      { "Body", 'o' }
   };
   size_t   i;

   if( e == _actor)
      return( '@');
   for( i = 0; i < sizeof( glyphs) / sizeof( glyphs[ 0]); i++)
      if( [_world record:[_world kindNamed:glyphs[ i].kind] for:e])
         return( glyphs[ i].glyph);
   return( '?');
}


- (void) look
{
   BGStore      *bodies;
   BGView       *view;
   BGLocation   here;
   BGLocation   loc;
   BGEntityID   e;
   NSUInteger   i;
   int32_t      x;
   int32_t      y;
   char         row[ 32];
   char         g;

   if( ! ground_tile( _world, _actor, &here))
   {
      [_out appendString:@"You are nowhere.\n"];
      return;
   }
   bodies = [_world storeForKind:[_world kindNamed:"Body"]];
   /* the map: what stands on each tile, or water, or floor */
   for( y = here.y - 3; y <= here.y + 3; y++)
   {
      for( x = here.x - 7; x <= here.x + 7; x++)
      {
         g = [_world isTileX:x y:y level:here.level] ? ([_world waterAtX:x y:y level:here.level] ? '~' : '.') : ' ';
         for( i = 0; i < [bodies count]; i++)
         {
            e   = [bodies entityAtIndex:i];
            loc = [_world locationOf:e];
            if( loc.form == BGLocationOnTile && loc.x == x && loc.y == y && loc.level == here.level &&
                (g == '.' || g == '~' || e == _actor))
               g = [self glyphOf:e];
         }
         row[ x - here.x + 7] = g;
      }
      row[ 15] = 0;
      [_out appendFormat:@"   %s\n", row];
   }
   /* what the actor can see of what is near: perceivable fields only */
   view = [BGView viewOf:_actor inWorld:_world];
   for( i = 0; i < [bodies count]; i++)
   {
      e = [bodies entityAtIndex:i];
      if( ! ground_tile( _world, e, &loc) || abs( loc.x - here.x) > 7 || abs( loc.y - here.y) > 3)
         continue;
      [_out appendFormat:@"%c %llu %s: %@\n", [self glyphOf:e], (unsigned long long) e, [_world info:e]->blueprint,
                         [view describeEntity:e]];
   }
}


- (void) showMenu
{
   const BGAction   *a;
   NSUInteger       i;
   int              r;

   [_menu release];
   _menu = [[BGMenu menuFor:_actor world:_world] retain];
   for( i = 0; i < [_menu count]; i++)
   {
      a = [_menu actionAt:i];
      [_out appendFormat:@"%2lu. %s", (unsigned long) i + 1, a->operation];
      for( r = BGRoleItem; r < BGRoleCount; r++)
         if( a->roles[ r])
            [_out appendFormat:@" %s %llu (%s)", BGRoleNames[ r], (unsigned long long) a->roles[ r],
                               [_world info:a->roles[ r]]->blueprint];
      if( [_menu matchAt:i] == TRI_UNKNOWN)
         [_out appendFormat:@"  [unknown: %@]", [[_menu residualsAt:i] componentsJoinedByString:@", "]];
      [_out appendString:@"\n"];
   }
   if( ! [_menu count])
      [_out appendString:@"There is nothing you can do.\n"];
}


/* --- the developer's inspector ------------------------------------------------- */

- (void) inspect:(BGEntityID) e
{
   const BGActivity   *record;
   const BGEvent      *ev;
   BGStore            *store;
   BGEntityID         other[ 64];
   NSUInteger         i;
   NSUInteger         k;
   NSUInteger         n;
   NSUInteger         shown;

   [_out appendFormat:@"%@\n", [_world describeEntity:e]];
   for( k = 0; k < BGEdgeKindCount; k++)
   {
      n = [_world edges:(BGEdgeKind) k from:e into:other max:64];
      for( i = 0; i < n && i < 64; i++)
         [_out appendFormat:@"  %s -> %llu\n", BGEdgeKindNames[ k], (unsigned long long) other[ i]];
      n = [_world edges:(BGEdgeKind) k to:e into:other max:64];
      for( i = 0; i < n && i < 64; i++)
         [_out appendFormat:@"  %s <- %llu\n", BGEdgeKindNames[ k], (unsigned long long) other[ i]];
   }
   if( [_world isCheckedOut:e])
      [_out appendString:@"  its water is checked out by the fluid domain\n"];
   store = [_world storeForKind:[_world kindNamed:"Activity"]];
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      if( record->actorRef == e || record->itemRef == e || record->destinationRef == e)
         [_out appendFormat:@"  in activity %@\n", [_world describeEntity:[store entityAtIndex:i]]];
   }
   shown = 0;
   for( i = [_world eventCount]; i-- > 0 && shown < 8;)
   {
      ev = [_world eventAt:i];
      if( ev->subject != e && ev->other != e)
         continue;
      [_out appendFormat:@"  event %llu at boundary %llu: %s%s%s (%@)\n", (unsigned long long) ev->index,
                         (unsigned long long) ev->boundary, ev->kind, ev->detail ? " " : "", ev->detail ? ev->detail : "",
                         [self sourceOf:ev]];
      shown++;
   }
}


- (NSString *) sourceOf:(const BGEvent *) ev
{
   NSString   *source;

   source = [_committer sourceOfPosition:ev->group];
   return( source ? source : @"before the save");
}


/* What last changed it, and why: the chain of causes back to an input. */
- (void) why:(BGEntityID) e
{
   const BGEvent   *ev;
   NSUInteger      i;
   NSUInteger      depth;
   char            where[ 64];

   ev = NULL;
   for( i = [_world eventCount]; i-- > 0 && ! ev;)
      if( [_world eventAt:i]->subject == e)
         ev = [_world eventAt:i];
   if( ! ev)
   {
      [_out appendFormat:@"Nothing has happened to %llu.\n", (unsigned long long) e];
      return;
   }
   for( depth = 0; ev && depth < 12; depth++)
   {
      BGLocationFormat( ev->location, where, sizeof( where));
      [_out appendFormat:@"%*s%s %llu%s%s%s%s at boundary %llu, in \"%@\"\n", (int) depth * 2, "", ev->kind,
                         (unsigned long long) ev->subject, ev->detail ? " " : "", ev->detail ? ev->detail : "",
                         ev->location.form ? " to " : "", ev->location.form ? where : "",
                         (unsigned long long) ev->boundary, [self sourceOf:ev]];
      ev = ev->cause ? [_world eventAt:(NSUInteger) ev->cause - 1] : NULL;
      if( ev)
         [_out appendFormat:@"%*sbecause:\n", (int) depth * 2, ""];
   }
}


/* --- saves ------------------------------------------------------------------------ */

- (void) save:(NSString *) path
{
   NSString   *text;
   FILE       *f;

   text = BGSave( _world, _committer, [NSArray arrayWithObject:_fluid]);
   f    = fopen( [path UTF8String], "w");
   if( ! f)
   {
      [_out appendFormat:@"Cannot write %@.\n", path];
      return;
   }
   fputs( [text UTF8String], f);
   fclose( f);
   [_out appendFormat:@"Saved to %@.\n", path];
}


- (void) load:(NSString *) path
{
   NSString   *text;
   NSString   *error;
   NSArray    *deferred;
   BGWorld    *world;
   uint64_t   position;
   char       *buf;
   long       len;
   FILE       *f;

   f = fopen( [path UTF8String], "r");
   if( ! f)
   {
      [_out appendFormat:@"Cannot read %@.\n", path];
      return;
   }
   fseek( f, 0, SEEK_END);
   len = ftell( f);
   fseek( f, 0, SEEK_SET);
   buf = calloc( 1, (size_t) len + 1);
   fread( buf, 1, (size_t) len, f);
   fclose( f);
   text = [NSString stringWithUTF8String:buf];
   free( buf);
   error = nil;
   world = BGRestore( text, [_world contentBuild], &deferred, &position, &error);
   if( ! world)
   {
      [_out appendFormat:@"%@\n", error];
      return;
   }
   [self buildOn:world];
   [_committer setPosition:position];
   [_committer restoreDeferred:deferred];
   [_fluid restoreSavedState:BGSavedDomainState( text, @"fluid")];
   [_out appendFormat:@"Loaded %@: t=%lldms.\n", path, (long long) [_world time].ms];
}


/* --- the commands ------------------------------------------------------------------ */

- (BOOL) actorBusy
{
   const BGActivity   *record;
   BGStore            *store;
   NSUInteger         i;
   TriType            running;

   store   = [_world storeForKind:[_world kindNamed:"Activity"]];
   running = tri_type_named( [_world tri], "\"running\"");
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      if( record->actorRef == _actor && record->status == (uint32_t) running)
         return( YES);
   }
   return( NO);
}


- (void) listActivities
{
   const BGActivity   *record;
   BGStore            *store;
   NSUInteger         i;
   BOOL               any;

   store = [_world storeForKind:[_world kindNamed:"Activity"]];
   any   = NO;
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      if( record->actorRef != _actor)
         continue;
      [_out appendFormat:@"%llu %s: %s, stage %lld, %lldms done%@\n", (unsigned long long) [store entityAtIndex:i],
                         [_world textField:"Activity.operation" of:[store entityAtIndex:i]],
                         tri_type_name( [_world tri], record->status), (long long) record->stage,
                         (long long) record->progress,
                         record->due ? [NSString stringWithFormat:@", due at %lldms", (long long) record->due] : @""];
      any = YES;
   }
   if( ! any)
      [_out appendString:@"You have done nothing yet.\n"];
}


- (BOOL) command:(NSString *) line
{
   NSMutableArray   *words;
   NSString         *error;
   NSArray          *parts;
   NSString         *verb;
   NSString         *w;
   const BGAction   *a;
   BGEntityID       e;
   NSUInteger       i;
   NSUInteger       n;
   int64_t          amount;
   char             walk[ 16];

   parts = [line componentsSeparatedByString:@" "];
   words = [NSMutableArray array];
   for( i = 0; i < [parts count]; i++)
   {
      w = [parts objectAtIndex:i];
      if( [w length])
         [words addObject:w];
   }
   if( ! [words count] || [[words objectAtIndex:0] hasPrefix:@"#"])
      return( YES);
   verb = [words objectAtIndex:0];
   n    = [words count] > 1 ? (NSUInteger) [[words objectAtIndex:1] longLongValue] : 0;
   e    = (BGEntityID) n;

   if( [verb isEqualToString:@"quit"])
      return( NO);
   if( [verb isEqualToString:@"help"])
      [_out appendString:@"look, menu, do <n> [amount], walk n|s|e|w, wait <ms>, step, idle, as <id>,\n"
                         @"activities, suspend <id>, resume <id>, inspect <id>, why <id>, trace [n],\n"
                         @"save <file>, load <file>, time, hash, quit\n"];
   else if( [verb isEqualToString:@"look"])
      [self look];
   else if( [verb isEqualToString:@"menu"])
      [self showMenu];
   else if( [verb isEqualToString:@"do"])
   {
      if( ! _menu)
         [self showMenu];
      if( n < 1 || n > [_menu count])
         [_out appendString:@"There is no such entry; type menu.\n"];
      else
      {
         a      = [_menu actionAt:n - 1];
         amount = [words count] > 2 ? [[words objectAtIndex:2] longLongValue] : 0;
         [self perform:*a amount:amount];
      }
   }
   else if( [verb isEqualToString:@"walk"] && [words count] > 1)
   {
      w = [words objectAtIndex:1];
      snprintf( walk, sizeof( walk), "walk_%s",
                [w hasPrefix:@"n"] ? "north" : [w hasPrefix:@"s"] ? "south" : [w hasPrefix:@"e"] ? "east" : "west");
      [self perform:BGActionMake( [_world intern:walk], _actor, BGNoEntity, BGNoEntity) amount:0];
   }
   else if( [verb isEqualToString:@"wait"])
   {
      [_scheduler runUntil:BGTimeMake( [_world time].ms + (int64_t) n)];
      [self showTrace];
      [_out appendFormat:@"t=%lldms\n", (long long) [_world time].ms];
   }
   else if( [verb isEqualToString:@"step"])
   {
      if( ! [_scheduler stepUntil:BGTimeMake( INT64_MAX - 1)])
         [_out appendString:@"Nothing more happens.\n"];
      [self showTrace];
      [_out appendFormat:@"t=%lldms\n", (long long) [_world time].ms];
   }
   else if( [verb isEqualToString:@"idle"])
   {
      while( [self actorBusy] && [_scheduler stepUntil:BGTimeMake( [_world time].ms + 600000)])
         ;
      [self showTrace];
      [_out appendFormat:@"t=%lldms\n", (long long) [_world time].ms];
   }
   else if( [verb isEqualToString:@"as"])
   {
      if( ! [_world record:[_world kindNamed:"Agent"] for:e])
         [_out appendFormat:@"%llu is not an agent.\n", (unsigned long long) e];
      else
      {
         _actor = e;
         [_menu release];
         _menu = nil;
         [_out appendFormat:@"You are %llu.\n", (unsigned long long) e];
      }
   }
   else if( [verb isEqualToString:@"activities"])
      [self listActivities];
   else if( [verb isEqualToString:@"suspend"] || [verb isEqualToString:@"resume"])
   {
      error = nil;
      if( [verb isEqualToString:@"suspend"] ? ! [_activities suspend:e because:@"the actor's choice" error:&error]
                                            : ! [_activities resume:e error:&error])
         [_out appendFormat:@"You can't: %@.\n", error];
      else
      {
         _inputDue = YES;
         [_scheduler stepUntil:[_world time]];
         [self showTrace];
      }
   }
   else if( [verb isEqualToString:@"inspect"])
      [self inspect:e];
   else if( [verb isEqualToString:@"why"])
      [self why:e];
   else if( [verb isEqualToString:@"trace"])
   {
      parts = [_committer trace];
      for( i = [parts count] > (n ? n : 20) ? [parts count] - (n ? n : 20) : 0; i < [parts count]; i++)
         [_out appendFormat:@"%@\n", [parts objectAtIndex:i]];
   }
   else if( [verb isEqualToString:@"save"] && [words count] > 1)
      [self save:[words objectAtIndex:1]];
   else if( [verb isEqualToString:@"load"] && [words count] > 1)
      [self load:[words objectAtIndex:1]];
   else if( [verb isEqualToString:@"time"])
      [_out appendFormat:@"t=%lldms, boundary %llu\n", (long long) [_world time].ms,
                         (unsigned long long) [_world boundary]];
   else if( [verb isEqualToString:@"hash"])
      [_out appendFormat:@"state hash %016llx\n", (unsigned long long) [_world stateHash]];
   else
      [_out appendFormat:@"What is \"%@\"? Type help.\n", verb];
   return( YES);
}

@end
