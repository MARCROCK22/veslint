declare let n: number;
declare let big: bigint;
const STEP = 2;
const BACK = -1;

// Reported: the update moves the counter away from the bound.
for (let i = 0; i < 10; i--) {}
for (let i = 0; i <= 10; i--) {}
for (let i = 10; i > 0; i++) {}
for (let i = 10; i >= 0; ++i) {}
for (let i = 0; 10 > i; i--) {}
for (let i = 10; 0 < i; i++) {}
for (let i = 0; i < 10; i -= 1) {}
for (let i = 10; i > 0; i += 1) {}
for (let i = 0; i < 10; i += -1) {}
for (let i = 0; i < 10; i += BACK) {}
for (let i = 10; i > 0; i -= -STEP) {}
for (let i = 10; i > 0; i += true as any) {}
for (let i = 0n; i < 10n; i -= 1n) {}
for (let i = 0; (i) < 10; (i--)) {}
for (let i = 0, j = 0; i < 10; i--, j++) {}
for (let i = 0; i < 10; ((i -= 1))) {}

// Not reported.
for (let i = 0; i < 10; i++) {}
for (let i = 10; i > 0; i--) {}
for (let i = 0; i < 10; i += n) {}
for (let i = 0; i < 10; i -= 0) {}
for (let i = 0; i < 10; i -= NaN) {}
for (let i = 0; i < 10; i -= big) {}
for (let i = 0; i < 10; i--, i--) {}
for (let i = 0; i < 10; i = i - 1) {}
for (let i = 0; i == 10; i--) {}
for (let i = 0; i < 10 && n; i--) {}
for (let i = 0; i < 10; ) {}
for (let i = 0; ; i--) {}
for (let i = 0; i! < 10; i--) {}
for (let i = 0; i < 10; i *= 2) {}
for (const x of [1]) {}
