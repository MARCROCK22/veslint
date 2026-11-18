// A function: svelte-eslint-parser reads svelte.config.js statically (svelte-config/parser.ts) and
// evaluates no function, so runes are unset here (as in ../unset: the rune symbols decide).
export default {
  compilerOptions: {
    runes: ({ filename }) => !filename.endsWith('cases.svelte'),
  },
};
