// A function: svelte-eslint-parser reads svelte.config.js statically (svelte-config/parser.ts) and
// evaluates no function, so runes are unset here (as in ../unset: the rune symbols decide), and
// veslint does not call it either. (A function in parserOptions.svelteConfig is called, by
// svelte-eslint-parser and by veslint's resolver of an eslint.config.*: tests/svelte-lint/runes.)
export default {
  compilerOptions: {
    runes: ({ filename }) => !filename.endsWith('cases.svelte'),
  },
};
