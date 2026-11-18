// A default value of a destructuring: `runes` is undefined in the object, so the default counts.
const { compilerOptions = { runes: false } } = { kit: {} };
export default { compilerOptions };
