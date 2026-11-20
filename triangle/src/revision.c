/* The revision of the sources the library was built from: tools/revision.sh,
 * which the Makefile writes into build/revision.h. */
#include "triangle.h"
#include "revision.h"

const char *tri_revision(void) { return TRI_REVISION; }
