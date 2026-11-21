// Module gcheap grows the collector's heap when the program starts, before the constants of
// veslint's modules are made: treesitter imports it (`as _`), and _vinit initializes the modules in
// the order of their imports, treesitter before the others of veslint. Their maps of constants
// took the collector through several collections while its heap grew, at every start (the command
// line and the server): `veslint --version` took 17.9 ms, 15.0 ms with the heap grown first.
module gcheap

// The collector's heap at the start. Boehm's GC collects whenever what was allocated since the
// last collection reaches a share of the heap, and its heap starts small: a lint collected
// several times while its heap grew to its working size. Starting at 32 MiB took 1 to 3.5 % off
// zod and recharts (one worker and the default workers, without types) with the same peak memory,
// and changed nothing on the TypeScript compiler; 64 MiB took a little more off zod but added up
// to 32 MB to the peak.
const initial_heap_bytes = u64(32 * 1024 * 1024)

#include "@VMODROOT/gcheap/gc_heap.h"

fn C.GC_expand_hp(bytes u64) int

// init adds initial_heap_bytes to the heap the collector starts with (that of
// GC_INITIAL_HEAP_SIZE, which Boehm reads when it starts, when it is set).
fn init() {
	$if gcboehm ? {
		C.GC_expand_hp(initial_heap_bytes)
	}
}
