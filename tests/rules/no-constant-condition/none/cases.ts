declare let a: any;

// Loops are not checked with checkLoops false.
while (1) {}
do {} while (true);
for (; true; ) {}

// Reported anyway.
if (true) {}
const t = 1 ? a : a;
