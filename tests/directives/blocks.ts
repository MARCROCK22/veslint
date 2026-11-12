// Block directives across a file, nested and repeated.
declare const p: Promise<number>;
/* eslint-disable @typescript-eslint/no-floating-promises */
p;
/* eslint-disable @typescript-eslint/no-floating-promises */
p;
/* eslint-enable @typescript-eslint/no-floating-promises */
p;
/* eslint-disable */
/* eslint-enable @typescript-eslint/no-floating-promises */
p;
await 1;
/* eslint-enable */
/* eslint-disable @typescript-eslint/await-thenable */
p;
/* eslint-disable-next-line */
p;
p; /* eslint-disable-line @typescript-eslint/no-floating-promises */ p;
export {};
