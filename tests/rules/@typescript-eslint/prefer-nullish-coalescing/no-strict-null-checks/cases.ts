// Without strictNullChecks the rule reports noStrictNullCheck at line 0 and still checks.
export {};
declare const s: string | undefined;
declare const a: any;
export const x = s || 'x';
export const y = a || 'y';
