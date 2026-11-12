declare const flag: boolean;
declare const maybe: boolean | undefined;

// Without strictNullChecks the rule reports at line 0, and `undefined` vanishes from unions.
const a = flag === true;
const b = maybe !== false;

export { a, b };
