// gc_heap.h: Boehm's GC_expand_hp for gc_heap.v. V calls its collector through wrappers of its own
// and the C it generates does not include gc.h, so the function would be an implicit declaration
// (an error of gcc 14, the one of the Windows build). The signature is gc.h's.
#ifndef VESLINT_GC_HEAP_H
#define VESLINT_GC_HEAP_H

#include <stddef.h>

#ifndef GC_H
extern int GC_expand_hp(size_t number_of_bytes);
#endif

// The collector gives a free block of its heap back to the system after it stayed free for a few
// collections (GC_unmap_threshold, from the environment variable GC_UNMAP_THRESHOLD, which GC_init
// reads when main starts; "0" keeps the blocks). Where V builds the collector with unmapping (Linux
// and macOS), a command line (not `--server`) sets the variable before main, when the user did not,
// and veslint_gc_unmap_env_done takes it out of the environment again once the collector read it,
// so that the programs veslint starts do not get it.
#if defined(__linux__) || defined(__APPLE__)
#include <stdlib.h>
#include <string.h>

static int veslint_gc_unmap_env_set = 0;

__attribute__((constructor, used)) static void veslint_gc_keep_mapped(int argc, char **argv) {
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--server") == 0) {
			return;
		}
	}
	if (getenv("GC_UNMAP_THRESHOLD") == NULL && setenv("GC_UNMAP_THRESHOLD", "0", 0) == 0) {
		veslint_gc_unmap_env_set = 1;
	}
}

static inline void veslint_gc_unmap_env_done(void) {
	if (veslint_gc_unmap_env_set) {
		unsetenv("GC_UNMAP_THRESHOLD");
		veslint_gc_unmap_env_set = 0;
	}
}
#else
static inline void veslint_gc_unmap_env_done(void) {}
#endif

#endif
