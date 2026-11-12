// Without strictNullChecks the rule reports noStrictNullCheck at line 0 and still checks.
export {};
declare const s: string | undefined;
declare const o: { a: number };
if (o) {}
export const x = s === undefined;
