#import "BGSave.h"

#import "BGProposalGroup.h"
#import "BGScheduler.h"

#include <stdio.h>
#include <stdlib.h>


/*
 * The format, one record per line, tokens separated by spaces; strings are
 * quoted with \" \\ \n escapes, and an absent string is -:
 *
 *   bruggadung-save 1
 *   content <hash>
 *   world <seed> <time ms> <boundary> <next ID> <commit position>
 *   entity <id> "<blueprint>" <seed>
 *   record <Kind> <id> <field> <value> ...       a type is "<type name>"
 *   location <id> <location>
 *   edge <kind> <from> <to>
 *   tombstone <id> "<blueprint>" <successor> <cause> "<reason>"
 *   event <index> <boundary> <round> "<kind>" <subject> <other> <amount> <detail> <cause> <group> <location> <actor>
 *   tile <x> <y> <level> water <mL>
 *   group <phase> <cause> <handles> "<source>" <actor>
 *   proposal <kind> <target> <unit> <other> <unit> <value> <edge> <name> <key> <handle> <location>
 *   domain <name> <what the domain keeps>
 *   end
 *
 * where <location> is <form> <place> <x> <y> <level> <slot> "<role>".
 */

#define BG_SAVE_VERSION   1


/* --- writing ----------------------------------------------------------------- */

static void   put_string( NSMutableString *out, const char *s)
{
   if( ! s)
   {
      [out appendString:@" -"];
      return;
   }
   [out appendString:@" \""];
   for( ; *s; s++)
   {
      if( *s == '"' || *s == '\\')
         [out appendFormat:@"\\%c", *s];
      else if( *s == '\n')
         [out appendString:@"\\n"];
      else
         [out appendFormat:@"%c", *s];
   }
   [out appendString:@"\""];
}


static void   put_location( NSMutableString *out, BGLocation loc)
{
   [out appendFormat:@" %d %llu %d %d %d %d", (int) loc.form, (unsigned long long) loc.place,
                     loc.x, loc.y, loc.level, loc.slot];
   put_string( out, loc.role);
}


static void   put_record( NSMutableString *out, BGWorld *world, NSUInteger kind, BGEntityID entity,
                          const uint8_t *record)
{
   const BGComponentInfo   *info;
   const BGFieldInfo       *f;
   const uint8_t           *p;
   size_t                  i;

   info = [world kindInfo:kind];
   [out appendFormat:@"record %s %llu", info->name, (unsigned long long) entity];
   for( i = 0; i < info->nfields; i++)
   {
      f = &info->fields[ i];
      p = record + f->offset;
      switch( f->value)
      {
      case BG_VALUE_QUANTITY:
         [out appendFormat:@" %s %lld", f->name, (long long) *(const int64_t *) p];
         break;
      case BG_VALUE_REF:
         [out appendFormat:@" %s %llu", f->name, (unsigned long long) *(const uint64_t *) p];
         break;
      case BG_VALUE_BOOL:
         [out appendFormat:@" %s %s", f->name, *(const bool *) p ? "true" : "false"];
         break;
      case BG_VALUE_TYPE:
         [out appendFormat:@" %s", f->name];
         put_string( out, tri_type_name( [world tri], *(const uint32_t *) p));
         break;
      case BG_VALUE_TEXT:
         [out appendFormat:@" %s", f->name];
         put_string( out, *(const char *const *) p);
         break;
      default:
         break;      /* structures are not stored yet */
      }
   }
   [out appendString:@"\n"];
}


NSString   *BGSave( BGWorld *world, BGCommitter *committer, NSArray *domains)
{
   NSArray              *state;
   id <BGSavedSystem>   domain;
   const BGEntityInfo   *info;
   const BGTombstone    *stone;
   const BGEvent        *ev;
   const BGEdge         *edge;
   const BGProposal     *p;
   BGProposalGroup      *group;
   NSMutableString      *out;
   NSArray              *deferred;
   BGStore              *store;
   NSUInteger           i;
   NSUInteger           j;
   NSUInteger           k;

   /* stocks at rest first: every domain checks in, and keeps its own state aside */
   out = [NSMutableString string];
   for( i = 0; i < [domains count]; i++)
   {
      domain = [domains objectAtIndex:i];
      state  = [domain savedState];
      for( j = 0; j < [state count]; j++)
         [out appendFormat:@"domain %@ %@\n", [domain name], [state objectAtIndex:j]];
   }
   state = [NSArray arrayWithObject:out];
   out   = [NSMutableString string];
   [out appendFormat:@"bruggadung-save %d\n", BG_SAVE_VERSION];
   [out appendFormat:@"content %016llx\n", (unsigned long long) [[world contentBuild] contentHash]];
   [out appendFormat:@"world %llu %lld %llu %llu %llu\n", (unsigned long long) [world seed], (long long) [world time].ms,
                     (unsigned long long) [world boundary], (unsigned long long) [world nextID],
                     (unsigned long long) [committer position]];
   /* terrain (TERRAIN.md): its map, then the chunks that differ from it,
    * each cell by kind, in runs */
   if( [world terrain])
   {
      const BGTerrain   *terrain;
      BGTerrainKind     cells[ BG_CHUNK * BG_CHUNK];
      int32_t           (*corners)[ 3];
      NSUInteger        nchunks;
      NSUInteger        c;
      NSUInteger        cell;
      NSUInteger        run;

      terrain = [world terrain];
      [out appendFormat:@"terrain %s\n", BGTerrainMap( terrain) ? BGTerrainMap( terrain) : "-"];
      nchunks = BGTerrainChanged( terrain, NULL, 0);
      corners = malloc( (nchunks ? nchunks : 1) * sizeof( *corners));
      BGTerrainChanged( terrain, corners, nchunks);
      for( c = 0; c < nchunks; c++)
      {
         BGTerrainChunkCells( terrain, corners[ c][ 0], corners[ c][ 1], corners[ c][ 2], cells);
         [out appendFormat:@"terrain-chunk %d %d %d", corners[ c][ 0], corners[ c][ 1], corners[ c][ 2]];
         for( cell = 0; cell < BG_CHUNK * BG_CHUNK; cell += run)
         {
            for( run = 1; cell + run < BG_CHUNK * BG_CHUNK && cells[ cell + run] == cells[ cell]; run++)
               ;
            [out appendFormat:@" %s*%lu", cells[ cell] ? BGTerrainKindInfo( terrain, cells[ cell])->name : "-",
                              (unsigned long) run];
         }
         [out appendString:@"\n"];
      }
      free( corners);
   }

   store = [world entities];
   for( i = 0; i < [store count]; i++)
   {
      info = [store recordAtIndex:i];
      [out appendFormat:@"entity %llu", (unsigned long long) [store entityAtIndex:i]];
      put_string( out, info->blueprint);
      [out appendFormat:@" %llu\n", (unsigned long long) info->seed];
   }
   for( k = 0; k < [world kindCount]; k++)
   {
      store = [world storeForKind:k];
      for( i = 0; i < [store count]; i++)
         put_record( out, world, k, [store entityAtIndex:i], [store recordAtIndex:i]);
   }
   store = [world locations];
   for( i = 0; i < [store count]; i++)
   {
      [out appendFormat:@"location %llu", (unsigned long long) [store entityAtIndex:i]];
      put_location( out, *(BGLocation *) [store recordAtIndex:i]);
      [out appendString:@"\n"];
   }
   for( i = 0; i < [world edgeCount]; i++)
   {
      edge = [world edgeAt:i];
      [out appendFormat:@"edge %s %llu %llu\n", BGEdgeKindNames[ edge->kind], (unsigned long long) edge->from,
                        (unsigned long long) edge->to];
   }
   store = [world tombstones];
   for( i = 0; i < [store count]; i++)
   {
      stone = [store recordAtIndex:i];
      [out appendFormat:@"tombstone %llu", (unsigned long long) [store entityAtIndex:i]];
      put_string( out, stone->blueprint);
      [out appendFormat:@" %llu %llu", (unsigned long long) stone->successor, (unsigned long long) stone->cause];
      put_string( out, stone->reason);
      [out appendString:@"\n"];
   }
   for( i = 0; i < [world eventCount]; i++)
   {
      ev = [world eventAt:i];
      [out appendFormat:@"event %llu %llu %u", (unsigned long long) ev->index, (unsigned long long) ev->boundary, ev->round];
      put_string( out, ev->kind);
      [out appendFormat:@" %llu %llu %lld", (unsigned long long) ev->subject, (unsigned long long) ev->other,
                        (long long) ev->amount];
      put_string( out, ev->detail);
      [out appendFormat:@" %llu %llu", (unsigned long long) ev->cause, (unsigned long long) ev->group];
      put_location( out, ev->location);
      [out appendFormat:@" %llu\n", (unsigned long long) ev->actor];
   }
   for( k = 0; k < (NSUInteger) [world levels]; k++)
      for( j = 0; j < (NSUInteger) [world tilesHigh]; j++)
         for( i = 0; i < (NSUInteger) [world tilesWide]; i++)
            if( [world waterAtX:(int32_t) i y:(int32_t) j level:(int32_t) k])
               [out appendFormat:@"tile %lu %lu %lu water %lld\n", (unsigned long) i, (unsigned long) j,
                                 (unsigned long) k, (long long) [world waterAtX:(int32_t) i y:(int32_t) j level:(int32_t) k]];
   deferred = [committer deferredGroups];
   for( i = 0; i < [deferred count]; i++)
   {
      group = [deferred objectAtIndex:i];
      [out appendFormat:@"group %d %llu %llu", (int) [group phase], (unsigned long long) [group cause],
                        (unsigned long long) [group handleCount]];
      put_string( out, [[group source] UTF8String]);
      [out appendFormat:@" %llu %llu\n", (unsigned long long) [group actor], (unsigned long long) [group weight]];
      for( j = 0; j < [group count]; j++)
      {
         p = &[group proposals][ j];
         [out appendFormat:@"proposal %d %llu %u %llu %u %lld %d", (int) p->kind,
                           (unsigned long long) p->target.entity, p->target.unit,
                           (unsigned long long) p->other.entity, p->other.unit,
                           (long long) p->value, (int) p->edge];
         put_string( out, p->name);
         put_string( out, p->key);
         [out appendFormat:@" %llu", (unsigned long long) p->handle];
         put_location( out, p->location);
         [out appendFormat:@" %d", p->expects ? 1 : 0];
         put_location( out, p->expected);
         [out appendString:@"\n"];
      }
   }
   [out appendString:[state objectAtIndex:0]];
   [out appendString:@"end\n"];
   return( out);
}


NSArray   *BGSavedDomainState( NSString *text, NSString *domain)
{
   NSMutableArray   *lines;
   NSArray          *all;
   NSString         *prefix;
   NSString         *line;
   NSUInteger       i;

   lines  = [NSMutableArray array];
   prefix = [NSString stringWithFormat:@"domain %@ ", domain];
   all    = [text componentsSeparatedByString:@"\n"];
   for( i = 0; i < [all count]; i++)
   {
      line = [all objectAtIndex:i];
      if( [line hasPrefix:prefix])
         [lines addObject:[line substringFromIndex:[prefix length]]];
   }
   return( lines);
}


/* --- reading ----------------------------------------------------------------- */

#define BG_MAX_TOKENS   1100     /* a terrain chunk: up to 1024 runs */

typedef struct
{
   char   *tokens[ BG_MAX_TOKENS];
   BOOL   quoted[ BG_MAX_TOKENS];
   int    n;
} BGLine;

/* Splits a line in place. NO if a string is unterminated or there are too many tokens. */
static BOOL   split_line( char *s, BGLine *line)
{
   char   *w;

   line->n = 0;
   for( ;;)
   {
      while( *s == ' ')
         s++;
      if( ! *s)
         return( YES);
      if( line->n == BG_MAX_TOKENS)
         return( NO);
      line->quoted[ line->n] = *s == '"';
      if( *s == '"')
      {
         w                      = ++s;
         line->tokens[ line->n] = w;
         while( *s && *s != '"')
         {
            if( *s == '\\' && s[ 1])
            {
               s++;
               *w++ = *s == 'n' ? '\n' : *s;
               s++;
               continue;
            }
            *w++ = *s++;
         }
         if( *s != '"')
            return( NO);
         s++;
         *w = 0;
      }
      else
      {
         line->tokens[ line->n] = s;
         while( *s && *s != ' ')
            s++;
         if( *s)
            *s++ = 0;
      }
      line->n++;
   }
}


static const char   *token_string( BGLine *line, int i)
{
   if( i >= line->n)
      return( NULL);
   if( ! line->quoted[ i] && ! strcmp( line->tokens[ i], "-"))
      return( NULL);
   return( line->tokens[ i]);
}


static uint64_t   token_u64( BGLine *line, int i)
{
   return( i < line->n ? strtoull( line->tokens[ i], NULL, 10) : 0);
}


static int64_t   token_i64( BGLine *line, int i)
{
   return( i < line->n ? strtoll( line->tokens[ i], NULL, 10) : 0);
}


static BGLocation   token_location( BGLine *line, int i)
{
   BGLocation   loc;
   const char   *role;

   loc       = BGLocationMakeNone();
   loc.form  = (BGLocationForm) token_i64( line, i);
   loc.place = token_u64( line, i + 1);
   loc.x     = (int32_t) token_i64( line, i + 2);
   loc.y     = (int32_t) token_i64( line, i + 3);
   loc.level = (int32_t) token_i64( line, i + 4);
   loc.slot  = (int32_t) token_i64( line, i + 5);
   role      = token_string( line, i + 6);
   if( role)
      strncpy( loc.role, role, sizeof( loc.role) - 1);
   return( loc);
}


static NSString   *restore_record( BGWorld *world, BGLine *line)
{
   const BGComponentInfo   *info;
   const BGFieldInfo       *f;
   const char              *text;
   NSUInteger              kind;
   TriType                 type;
   uint8_t                 *record;
   uint8_t                 *p;
   size_t                  j;
   int                     i;

   kind = [world kindNamed:line->tokens[ 1]];
   if( kind == NSNotFound)
      return( [NSString stringWithFormat:@"the content has no component %s", line->tokens[ 1]]);
   info   = [world kindInfo:kind];
   record = calloc( 1, info->size);
   for( i = 3; i + 1 < line->n; i += 2)
   {
      f = NULL;
      for( j = 0; j < info->nfields && ! f; j++)
         if( ! strcmp( info->fields[ j].name, line->tokens[ i]))
            f = &info->fields[ j];
      if( ! f)
      {
         free( record);
         return( [NSString stringWithFormat:@"the content has no field %s.%s", info->name, line->tokens[ i]]);
      }
      p = record + f->offset;
      switch( f->value)
      {
      case BG_VALUE_QUANTITY:
         *(int64_t *) p = token_i64( line, i + 1);
         break;
      case BG_VALUE_REF:
         *(uint64_t *) p = token_u64( line, i + 1);
         break;
      case BG_VALUE_BOOL:
         *(bool *) p = ! strcmp( line->tokens[ i + 1], "true");
         break;
      case BG_VALUE_TYPE:
         type = tri_type_named( [world tri], line->tokens[ i + 1]);
         if( type == TRI_BOTTOM)
         {
            free( record);
            return( [NSString stringWithFormat:@"the content has no type %s (for %s.%s)", line->tokens[ i + 1],
                                               info->name, f->name]);
         }
         *(uint32_t *) p = (uint32_t) type;
         break;
      case BG_VALUE_TEXT:
         text = token_string( line, i + 1);
         *(const char **) p = text ? [world intern:text] : NULL;
         break;
      default:
         break;
      }
   }
   [world setRecord:record
               kind:kind
                for:token_u64( line, 2)];
   free( record);
   return( nil);
}


BGWorld   *BGRestore( NSString *text,
                      BGContent *content,
                      NSArray **deferred,
                      uint64_t *position,
                      NSString **error)
{
   BGWorld           *world;
   BGProposalGroup   *group;
   NSMutableArray    *groups;
   NSString          *problem;
   BGTombstone       stone;
   BGEvent           ev;
   BGProposal        p;
   BGLine            line;
   const char        *s;
   char              *buf;
   char              *next;
   char              *cur;
   int               edge;
   int               lineno;
   BOOL              ended;

   buf     = strdup( [text UTF8String]);
   world   = nil;
   group   = nil;
   groups  = [NSMutableArray array];
   problem = nil;
   ended   = NO;
   lineno  = 0;
   for( cur = buf; cur && *cur && ! problem && ! ended; cur = next)
   {
      next = strchr( cur, '\n');
      if( next)
         *next++ = 0;
      lineno++;
      if( ! split_line( cur, &line))
      {
         problem = @"a malformed line";
         break;
      }
      if( ! line.n)
         continue;
      s = line.tokens[ 0];
      if( lineno == 1)
      {
         if( strcmp( s, "bruggadung-save") || token_i64( &line, 1) != BG_SAVE_VERSION)
            problem = @"not a bruggadung save of a version this lab reads";
         continue;
      }
      if( ! strcmp( s, "content"))
         continue;         /* by name, so other content can read it */
      if( ! strcmp( s, "world"))
      {
         world = [BGWorld worldWithContent:content
                                      seed:token_u64( &line, 1)
                                     error:&problem];
         [world setTime:BGTimeMake( token_i64( &line, 2))];
         [world setBoundary:token_u64( &line, 3)];
         [world setNextID:token_u64( &line, 4)];
         if( position)
            *position = token_u64( &line, 5);
         continue;
      }
      if( ! world)
      {
         problem = @"no world line before the state";
         break;
      }
      if( ! strcmp( s, "entity"))
         [world addEntity:token_u64( &line, 1)
                blueprint:token_string( &line, 2) ? token_string( &line, 2) : ""
                     seed:token_u64( &line, 3)];
      else if( ! strcmp( s, "record"))
         problem = line.n >= 3 ? restore_record( world, &line) : @"a short record";
      else if( ! strcmp( s, "location"))
         [world setLocation:token_location( &line, 2)
                         of:token_u64( &line, 1)];
      else if( ! strcmp( s, "edge"))
      {
         for( edge = 0; edge < BGEdgeKindCount; edge++)
            if( line.n > 1 && ! strcmp( line.tokens[ 1], BGEdgeKindNames[ edge]))
               break;
         if( edge == BGEdgeKindCount)
            problem = @"an unknown edge kind";
         else
            [world addEdge:(BGEdgeKind) edge
                      from:token_u64( &line, 2)
                        to:token_u64( &line, 3)];
      }
      else if( ! strcmp( s, "tombstone"))
      {
         memset( &stone, 0, sizeof( stone));
         stone.blueprint = token_string( &line, 2) ? token_string( &line, 2) : "";
         stone.successor = token_u64( &line, 3);
         stone.cause     = token_u64( &line, 4);
         if( token_string( &line, 5))
            strncpy( stone.reason, token_string( &line, 5), sizeof( stone.reason) - 1);
         [world restoreTombstone:stone
                             for:token_u64( &line, 1)];
      }
      else if( ! strcmp( s, "event"))
      {
         memset( &ev, 0, sizeof( ev));
         ev.boundary = token_u64( &line, 2);
         ev.round    = (uint32_t) token_u64( &line, 3);
         ev.kind     = [world intern:token_string( &line, 4) ? token_string( &line, 4) : ""];
         ev.subject  = token_u64( &line, 5);
         ev.other    = token_u64( &line, 6);
         ev.amount   = token_i64( &line, 7);
         ev.detail   = token_string( &line, 8) ? [world intern:token_string( &line, 8)] : NULL;
         ev.cause    = token_u64( &line, 9);
         ev.group    = token_u64( &line, 10);
         ev.location = token_location( &line, 11);
         ev.actor    = token_u64( &line, 18);
         if( [world emit:ev] != token_u64( &line, 1))
            problem = @"events out of order";
      }
      else if( ! strcmp( s, "terrain"))
      {
         if( token_string( &line, 1))
            [world setTerrainMap:token_string( &line, 1) error:&problem];
      }
      else if( ! strcmp( s, "terrain-chunk"))
      {
         int32_t   x0;
         int32_t   y0;
         int32_t   z;
         int       t;
         long      at;
         long      run;
         long      r;
         char      *star;

         x0 = (int32_t) token_i64( &line, 1);
         y0 = (int32_t) token_i64( &line, 2);
         z  = (int32_t) token_i64( &line, 3);
         at = 0;
         for( t = 4; t < line.n && ! problem; t++)
         {
            star = strrchr( line.tokens[ t], '*');
            run  = star ? strtol( star + 1, NULL, 10) : 0;
            if( ! star || run <= 0 || at + run > BG_CHUNK * BG_CHUNK)
            {
               problem = @"a malformed terrain chunk";
               break;
            }
            *star = 0;
            for( r = 0; r < run; r++, at++)
               if( strcmp( line.tokens[ t], "-") &&
                   ! [world setTerrain:line.tokens[ t] atX:x0 + (int32_t) (at % BG_CHUNK) y:y0 + (int32_t) (at / BG_CHUNK)
                                 level:z])
                  problem = [NSString stringWithFormat:@"no terrain kind %s, or a chunk off the map", line.tokens[ t]];
         }
         if( ! problem && at != BG_CHUNK * BG_CHUNK)
            problem = @"a malformed terrain chunk";
      }
      else if( ! strcmp( s, "tile"))
      {
         if( line.n < 6 || strcmp( line.tokens[ 4], "water"))
            problem = @"an unknown tile stock";
         else
            [world setWater:token_i64( &line, 5)
                        atX:(int32_t) token_i64( &line, 1)
                          y:(int32_t) token_i64( &line, 2)
                      level:(int32_t) token_i64( &line, 3)];
      }
      else if( ! strcmp( s, "group"))
      {
         group = [BGProposalGroup groupWithPhase:(BGPhase) token_i64( &line, 1)
                                          source:[NSString stringWithUTF8String:(char *) (token_string( &line, 4) ? token_string( &line, 4) : "")]];
         [group setCause:token_u64( &line, 2)];
         [group setHandleCount:token_u64( &line, 3)];
         [group setActor:token_u64( &line, 5)];
         [group setWeight:token_u64( &line, 6)];
         [groups addObject:group];
      }
      else if( ! strcmp( s, "proposal"))
      {
         if( ! group)
         {
            problem = @"a proposal outside a group";
            break;
         }
         memset( &p, 0, sizeof( p));
         p.kind          = (BGProposalKind) token_i64( &line, 1);
         p.target.entity = token_u64( &line, 2);
         p.target.unit   = (uint32_t) token_u64( &line, 3);
         p.other.entity  = token_u64( &line, 4);
         p.other.unit    = (uint32_t) token_u64( &line, 5);
         p.value         = token_i64( &line, 6);
         p.edge          = (BGEdgeKind) token_i64( &line, 7);
         p.name          = token_string( &line, 8);
         p.key           = token_string( &line, 9);
         p.handle        = token_u64( &line, 10);
         p.location      = token_location( &line, 11);
         p.expects       = token_i64( &line, 18) != 0;
         p.expected      = token_location( &line, 19);
         [group addProposal:p];
      }
      else if( ! strcmp( s, "domain"))
         ;         /* the domain's own: BGSavedDomainState */
      else if( ! strcmp( s, "end"))
         ended = YES;
      else
         problem = [NSString stringWithFormat:@"an unknown record \"%s\"", s];
   }
   free( buf);
   if( ! problem && ! ended)
      problem = @"the save ends early";
   if( problem)
   {
      if( error)
         *error = [NSString stringWithFormat:@"cannot restore the save: %@ (line %d)", problem, lineno];
      return( nil);
   }
   if( deferred)
      *deferred = groups;
   return( world);
}
