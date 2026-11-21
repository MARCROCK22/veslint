// gc_heap.h: Boehm's GC_expand_hp for gcheap.v. V calls its collector through wrappers of its own
// and the C it generates does not include gc.h, so the function would be an implicit declaration
// (an error of gcc 14, the one of the Windows build). The signature is gc.h's.
#ifndef VESLINT_GC_HEAP_H
#define VESLINT_GC_HEAP_H

#include <stddef.h>

#ifndef GC_H
extern int GC_expand_hp(size_t number_of_bytes);
#endif

#endif
