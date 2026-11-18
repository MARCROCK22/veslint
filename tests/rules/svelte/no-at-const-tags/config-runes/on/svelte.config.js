// compilerOptions.runes through a const and a spread: svelte-eslint-parser reads it statically.
const base = { runes: true };
const compilerOptions = { ...base };
const config = {
  kit: {},
  compilerOptions,
};
export default config;
