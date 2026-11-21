module main

// The collector's heap at the start. Boehm's GC collects whenever what was allocated since the
// last collection reaches a share of the heap, and its heap starts small: a lint collected
// several times while its heap grew to its working size. Starting at 32 MiB took 1 to 3.5 % off
// zod and recharts (one worker and the default workers, without types) with the same peak memory,
// and changed nothing on the TypeScript compiler; 64 MiB took a little more off zod but added up
// to 32 MB to the peak.
const initial_heap_bytes = u64(32 * 1024 * 1024)

#include "@VMODROOT/gc_heap.h"

fn C.GC_expand_hp(bytes u64) int

// grow_initial_heap adds initial_heap_bytes to the heap the collector starts with (that of
// GC_INITIAL_HEAP_SIZE, which Boehm reads before main runs, when it is set).
fn grow_initial_heap() {
	$if gcboehm ? {
		C.GC_expand_hp(initial_heap_bytes)
	}
}

fn C.veslint_gc_unmap_env_done()

// The collector keeps the free blocks of its heap on a command line instead of giving them back to
// the system after a few collections (gc_heap.h): a lint allocates again what it freed, and each
// page given back was a page fault and a page cleared by the kernel when it came back. On the
// TypeScript compiler, typed, it gave back and took again about 1.2 GB (300,000 of 795,000 page
// faults; 2.6 % of the instructions, and 0.7 s of the 2.3 s of system time), with the same peak
// memory. A server gives back what a large lint took.
// unmap_env_done takes GC_UNMAP_THRESHOLD out of the environment when veslint put it there.
fn unmap_env_done() {
	$if gcboehm ? {
		C.veslint_gc_unmap_env_done()
	}
}
