module main

// The collector's heap at the start. Boehm's GC collects whenever what was allocated since the
// last collection reaches a share of the heap, and its heap starts small: a lint collected
// several times while its heap grew to its working size. Starting at 32 MiB took 1 to 3.5 % off
// zod and recharts (one worker and the default workers, without types) with the same peak memory,
// and changed nothing on the TypeScript compiler; 64 MiB took a little more off zod but added up
// to 32 MB to the peak.
const initial_heap_bytes = u64(32 * 1024 * 1024)

fn C.GC_expand_hp(bytes u64) int

// grow_initial_heap adds initial_heap_bytes to the heap the collector starts with (that of
// GC_INITIAL_HEAP_SIZE, which Boehm reads before main runs, when it is set).
fn grow_initial_heap() {
	$if gcboehm ? {
		C.GC_expand_hp(initial_heap_bytes)
	}
}
