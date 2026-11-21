# Writes the header of the opaque C struct the repro compares pointers to (run in its directory).
printf 'typedef struct Opaque Opaque;\nstatic Opaque *opaque_get(void) { static int x; return (Opaque *)&x; }\n' > opaque.h
