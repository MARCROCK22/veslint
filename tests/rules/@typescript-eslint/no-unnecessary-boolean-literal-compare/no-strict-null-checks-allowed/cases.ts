declare const flag: boolean;
declare const maybe: boolean | undefined;

// The option silences the line 0 report; without strictNullChecks `undefined` vanishes from unions.
const a = flag === true;
const b = maybe !== false;

export { a, b };
