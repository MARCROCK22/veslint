# Builds the static library the repro links (run in the repro's directory).
printf 'void* my_ext_fn(void) { return (void*)0x2a; }\n' > ext.c
cc -c -o ext.o ext.c && ar rcs libext.a ext.o
