# Changelog

Each version is a release on GitHub with the veslint binaries (Linux x64, Windows x64) and the VS Code extension. The section of a version is the text of its release.

## 0.35.3

- **Svelte: a `runes` function in `parserOptions.svelteConfig`** of an `eslint.config.*` (`runes: ({ filename }) => …`) is called for each `.svelte` file with its path when ESLint resolves the configuration, as svelte-eslint-parser and eslint-plugin-svelte call it; the parse, the types and the rules (`svelte/valid-compile`…) follow what it gives (it was taken as unset), also from a saved `--print-config`, which keeps it per file.

## 0.35.2

- **`parserOptions` of an `eslint.config.*` kept whole:** `vueFeatures`, `svelteFeatures` and `svelteConfig` given in an `eslint.config.*` were lost (only a JSON configuration passed them on); now they reach the parse and the rules.
- **Vue:** `parserOptions.vueFeatures` is read (`filter`, `interpolationAsNonHTML`, `styleCSSVariableInjection`, `customMacros`), as vue-eslint-parser reads it; `export type { … }` in a `<script setup>` next to a `<script>` is the fatal parsing error ESLint gives; `lang="TS"`, `lang="typescript"` and other spellings of TypeScript are linted as TypeScript, as with typescript-eslint's parser.
- **Svelte:** `lang="TS"` and other spellings are TypeScript too; `bind:value={x}` no longer makes `no-const-assign` (and `no-class-assign`, `no-func-assign`, `no-global-assign`) report `x`, as in ESLint; a `runes` written as a function in `svelte.config.js` is unset, as svelte-eslint-parser reads it (in `parserOptions.svelteConfig` it is a limit: veslint does not call JavaScript functions; README).
- Internal: 21 helpers of eslint-plugin-vue ported twice by parallel batches are one each now (the output is the same).

## 0.35.1

- **Svelte: the runes setting of the configuration in the parse**, as svelte-eslint-parser resolves it (`parserOptions.svelteFeatures.runes`, then `<svelte:options runes>`, then `compilerOptions.runes` of `parserOptions.svelteConfig` or `svelte.config.js`): with `runes: false` the runes are not declared and `$bindable` props are plain, in the types and the scopes the rules see (it was only read by the svelte/* rules).
- **`vue/max-len` in `.svelte` files** measures the whole file, as ESLint does with svelte-eslint-parser's tokens (a long HTML comment after `</script>` was not measured).
- Test tooling: `tests/vue-lint` and `tests/svelte-lint` compare again (the Vue configuration no longer loads the svelte/* rules; the Svelte one gives svelte-eslint-parser TypeScript 6, as its JavaScript files need), pinned with every rule.

## 0.35.0

- **eslint-plugin-svelte complete: all 86 rules.** `svelte/valid-compile` and the `unused` message of `svelte/no-unused-svelte-ignore` give the Svelte compiler's warnings (accessibility, unused CSS selectors, runes, `$:`…) from a port of the analysis of Svelte 5.56.0's `compile()` to V (`svelte_compiler/`), with no JavaScript runtime: identical to `compile()` on 6,319 files. `svelte/indent` and `svelte/@typescript-eslint/no-unnecessary-condition` complete the plugin. `<style>` blocks in sass, less or stylus are left out of the compiler's input (their CSS warnings are missing).
- **`svelte.config.js` is read** without running it, as svelte-eslint-parser reads it: `compilerOptions.runes` and `kit.files` (`parserOptions.svelteConfig` takes precedence).
- **eslint-plugin-vue complete: all 256 rules**, with `vue/html-indent` and `vue/script-indent` (eslint-plugin-vue's indent engine).
- **Warnings are told from errors, as in ESLint:** a problem of a rule set to `"warn"` ends its line with the field `warning`, in the output, with `--fixes` and in the answers of `--server` (README, "The line format"); the line of an error is the same as before.
- **VS Code extension:** each problem is shown with its rule's level, an error as an error and a warning as a warning, as the ESLint extension does. `veslint.severity` is now `auto` by default; `error`, `warning`, `information` or `hint` still show every problem of a rule with that severity. With an older veslint, `auto` shows them all as errors.

## 0.34.0

- **eslint-plugin-svelte 3.24.1: 83 of its 88 rules**, on the template, the `<style>` and the script of `.svelte` files (and on the `.svelte.ts` modules and TypeScript files the script rules also lint):
  - **Template:** `button-has-type`, `no-at-html-tags`, `no-target-blank`, `valid-each-key`, `require-each-key`, `html-quotes`, `html-self-closing`, `mustache-spacing`, `shorthand-attribute`, `shorthand-directive`, `sort-attributes`, `max-attributes-per-line`, `no-useless-mustaches`… and `svelte/comment-directive` with the plugin's processor (`<!-- eslint-disable -->` in templates).
  - **Styles:** `no-dupe-style-properties`, `prefer-style-directive`, `no-unused-class-name`, `consistent-selector-style`, `valid-style-parse`…, on a port of postcss, postcss-safe-parser, postcss-scss and postcss-selector-parser (`postcss/`).
  - **Script:** stores (`require-store-reactive-access`, `no-store-async`…), runes (`prefer-svelte-reactivity`, `prefer-writable-derived`, `no-unnecessary-state-wrap`…), `$:` reactivity (`infinite-reactive-loop`, `no-reactive-reassign`…), SvelteKit (`no-navigation-without-resolve`, `valid-prop-names-in-kit-pages`…), `no-unused-props`, and the plugin's versions of `prefer-const`, `no-inner-declarations` and `no-trailing-spaces`.
- Each one gives what ESLint gives and passes the cases of its upstream tests (with `lang="ts"` for the JavaScript ones). Left: `svelte/indent`, `svelte/valid-compile` and the `unused` message of `svelte/no-unused-svelte-ignore`, which needs the Svelte compiler's warnings (being ported). `svelte.config.js` is not read: its `kit.files.routes` and `compilerOptions.runes` can be given as `parserOptions.svelteConfig` and `parserOptions.svelteFeatures.runes`.

## 0.33.0

- **Svelte files (`.svelte`), their TypeScript script:** `veslint .` brings the `.svelte` files and the `.svelte.ts` modules, and every rule veslint has (with types) lints their `<script lang="ts">` as ESLint does with svelte-eslint-parser 1.10.1 and typescript-eslint's parser: runes, stores (`$store`), `$:` statements, props, snippets and generics as svelte-eslint-parser models them, with the same problems, positions, fixes and suggestions (compared on 1,890 Svelte files with every rule, `tests/svelte-lint`). Types come from the code typescript-eslint type-checks for a `.svelte`, given to the TypeScript 7 compiler as a file of its own that is never written to disk; in other files, `import App from './App.svelte'` keeps the type of the `*.svelte` declaration, as in ESLint. `--fix`, `--server` and the VS Code extension handle `.svelte` too. The parser (`svelte/`) is a port of svelte-eslint-parser and of the Svelte 5 compiler's template parser it reads.
- **Not yet:** the rules of eslint-plugin-svelte (they come in the next versions). A `.svelte` whose script is JavaScript is not linted (veslint reads TypeScript only), with a warning.

## 0.32.0

- **93 more rules of eslint-plugin-vue 10.12.1: 254 of its 256** (`vue/html-indent` and `vue/script-indent` come later):
  - **Template:** 23 rules, among them `attributes-order`, `max-len`, `max-attributes-per-line`, `html-self-closing`, `singleline-` and `multiline-html-element-content-newline`, `padding-line-between-blocks` and `-tags`, `valid-v-for`, `valid-v-model`, `valid-v-slot`, `no-duplicate-class-names`, `no-unsupported-features` and `block-lang`.
  - **Template and component:** 22 rules, among them `no-undef-components`, `no-unused-components`, `no-undef-properties`, `no-unused-properties`, `no-mutating-props`, `require-explicit-emits`, `no-unused-emit-declarations`, `v-on-handler-style` and `component-name-in-template-casing`.
  - **Components:** 48 rules on the script side, among them `order-in-components`, `define-macros-order`, `require-default-prop`, `require-valid-default-prop`, `no-setup-props-reactivity-loss`, `no-ref-as-operand`, `no-async-in-computed-properties`, `no-dupe-keys`, `sort-keys`, `block-order` and the `html-comment-*` rules. Props declared by type (`defineProps<T>()`) get their runtime types and `required` from the TypeScript checker, and `withDefaults` its defaults.
- Each one gives what ESLint gives and passes the cases of its upstream tests: 10,085 cases of eslint-plugin-vue in all, 5 of them known differences.
- **Fixes found with all the rules together:** a `.vue` with both `<script>` and `<script setup>` no longer reports the variables of the setup's inner functions as unused (vue-eslint-parser leaves those scopes out of the tree); `vue/no-undef-properties` reports a name where ESLint does whatever the order of the rules; `vue/no-parsing-error` gives TypeScript's message for an unterminated string.

## 0.31.0

- **112 more rules of eslint-plugin-vue 10.12.1 (161 of its 256):**
  - **Template:** 28 rules, among them `attribute-hyphenation`, `v-on-event-hyphenation`, `html-quotes`, `html-closing-bracket-newline` and `-spacing`, `first-attribute-linebreak`, `this-in-template`, `no-unused-vars`, `no-dupe-v-else-if`, `v-slot-style`, `no-deprecated-slot-attribute` and `valid-v-memo`.
  - **Components:** 46 rules on the script side, with the detection of Vue components (options objects, `defineComponent`, `<script setup>` and its macros: `defineProps`, `defineEmits`, `defineModel`…), among them `prop-name-casing`, `require-prop-types`, `require-default-export`, `no-reserved-keys`, `no-props-shadow`, `define-props-declaration` and `component-definition-name-casing`. Eight of them read types, as their TypeScript versions do.
  - **The template's expressions:** the 38 rules that apply an ESLint or @stylistic rule to them (`vue/eqeqeq`, `vue/no-extra-parens`, `vue/space-infix-ops`, `vue/object-curly-spacing`…), each with ESLint's or @stylistic's version as eslint-plugin-vue picks it (@stylistic when the project has it).
- Each one gives what ESLint gives and passes the cases of its upstream tests: 2,795 cases of eslint-plugin-vue in all, 2 of them known differences (`tests/upstream/known.txt`).

## 0.30.0

- **eslint-plugin-vue 10.12.1, the first 49 rules: the templates of `.vue` files are linted.** `vue/comment-directive` (`<!-- eslint-disable -->`, `-line`, `-next-line` and `eslint-enable` in a template, with the unused ones reported as the `vue/vue` processor does), `vue/no-parsing-error` (TypeScript's own messages for template expressions), the `valid-v-*` rules (bind, cloak, html, once, pre, text, show, if, else-if, else, is, on), the `no-deprecated-*` template rules, `require-v-for-key`, `no-use-v-if-with-v-for`, `v-on-style`, `v-bind-style`, `html-end-tags`, `mustache-interpolation-spacing` and more: the README lists them. Each one gives what ESLint gives, with its fixes, and passes the cases of its upstream tests (the ones with a JavaScript script are run with `lang="ts"`, their expectation taken from ESLint on the converted case). The other `vue/*` rules come in the next versions and are skipped with a warning.

## 0.29.0

- **Vue files (`.vue`), their TypeScript script:** `veslint .` brings the `.vue` files, and every rule veslint has (with types) lints their `<script lang="ts">` and `<script setup lang="ts">` as ESLint does with vue-eslint-parser 10.4.2 and typescript-eslint's parser: the same problems, positions, fixes and suggestions (compared on 5,963 Vue files with every rule, `tests/vue-lint`). Types come from the code typescript-eslint type-checks for a `.vue`, given to the TypeScript 7 compiler as a file of its own that is never written to disk; in other files, `import App from './App.vue'` keeps the type of the `*.vue` declaration, as in ESLint. `--fix`, `--server` and the VS Code extension handle `.vue` too.
- **Not yet:** the rules of eslint-plugin-vue and the template (they come in the next versions). A `.vue` whose script is JavaScript is not linted (veslint reads TypeScript only), with a warning.
- **A file given by name that is neither TypeScript nor Vue** (`.js`, `.md`…) is rejected with a clear message, instead of failing in the compiler.

## 0.28.0

- **The resolved configuration is cached:** resolving an `eslint.config.*` starts bun and loads ESLint and every plugin, more than a second for a usual configuration. veslint now saves what ESLint resolved in `node_modules/.cache/veslint` and uses it again until something it came from changes: the configuration, a file or module it reads (the plugins too), an environment variable it reads, the files to lint, or the `eslint.config.*` that applies to a folder. On @marcrock22/eslintcf, `veslint .` goes from 3.8 s to 2.1 s, and `--print-config` from 1.7 s to 0.06 s. `VESLINT_CONFIG_CACHE=0` turns it off.
- **A resolved configuration saved outside the project** (`--print-config`) finds none of its files, since its paths are relative to its own folder: the README says where to save it, and the error names the folder its paths are relative to.

## 0.27.0

- **On npm:** `npm install --save-dev @marcrock22/veslint` (or `bun add -d`, `pnpm add -D`) installs the `veslint` command: `npx veslint .`. The package runs the binary of your platform, which npm installs with the optional dependency `@marcrock22/veslint-linux-x64` or `@marcrock22/veslint-win32-x64`, together with the TypeScript 7 compiler it uses. Each release publishes them (`npm/`, `npm/stage.sh`).
- **The extension uses the project's veslint from npm:** with `veslint.path` not set, the binary of `@marcrock22/veslint` in the workspace's `node_modules` (npm, pnpm, bun or yarn) comes before the one `veslint: Update veslint` downloaded, so the editor lints with the version the project pins; such a workspace is not updated from GitHub.
- **The compiler is looked for as Node resolves a dependency:** in the `node_modules` next to the binary, as before, and otherwise in the closest `node_modules` above it, where npm may install it.

## 0.26.1

- **`--fix` no longer grows in memory with every pass:** V keeps a closure, and what it captures, alive until it is released, and closures of the rules captured the checker of the pass, with its caches. `--fix` makes a checker per pass, so none was freed: on `src/services` of the TypeScript compiler (168 files) veslint went over 5 GB and took more than 20 minutes. Each file is now linted in a closure lifetime that releases them: on 73 of those files, 108 s and 470 MB, where it took 158 s and 5.3 GB (ESLint: 102 s, 2.8 GB). `veslint --server`, which lints again on every change, gained the same.
- **Fixes:** `no-loop-func` and `strict` end the report of a method at the end of the method (it ended after its parameters); `@stylistic/list-style` writes a private name without its `#` in its messages (`'signal'`), as the value of its token is in typescript-estree.
- **`--bench`:** `slowest_rules` lists every rule that ran, slowest first (it listed 20).
- **`tests/eval_eslintcf.sh`** has four more projects: seyfert, valibot and ky (downloaded at a pinned commit) and, when named, `src/services` of the TypeScript compiler. veslint reports what ESLint does in all of them, but for the members of unions TypeScript 7.1 orders otherwise, and `--fix` leaves the same files but where veslint fixes otherwise on purpose (`sort-switch-case`, `(infer M)[]`).

## 0.26.0

- **@stylistic/eslint-plugin 6.0.1:** the 54 `@stylistic/*` rules follow 6.0.1 (they followed 5.10.0) and pass the cases of its tests. What changes for a configuration:
  - `@stylistic/exp-list-style` is now `@stylistic/list-style`; its overrides take `multiLine` (not `multiline`), and the new option `empty` handles empty lists, imports and exports.
  - New defaults: `dot-location` is `property`, and `no-multi-spaces` has no `exceptions`.
  - Options removed: `"avoid-escape"` and a boolean `allowTemplateLiterals` of `quotes`, `"unix"` and `"windows"` of `eol-last`, the boolean of `no-mixed-spaces-and-tabs`, `overrides.arrow` of `type-annotation-spacing` (which no longer checks `=>`). A configuration that still has them is rejected, as ESLint does.
  - New options: `before` and `after` of `type-generic-spacing`, `ignoreOperators` of `space-infix-ops`, the `questionMark` override and `"ignore"` of `type-annotation-spacing`.
  - What the rules report: the `=` of a type parameter's default is checked by `space-infix-ops` (no longer by `type-generic-spacing`); the space before a class body's `{` by `space-before-blocks` (no longer by `keyword-spacing`); `keyword-spacing` checks `for await` as `for` and keeps comments in its fixes; `no-extra-parens` checks more type positions and JSX spread attributes and keeps the parentheses of an arrow body that starts with an object literal; `list-style` finds the `]` of a typed array pattern and the `)` of a call whose last argument is parenthesized (it no longer undoes `type-annotation-spacing` on `([a, b]: T) => …`); and fixes in `block-spacing`, `comma-spacing`, `key-spacing`, `multiline-ternary`, `object-curly-spacing`, `rest-spread-spacing`, `space-before-function-paren` and `spaced-comment`.
- **`@stylistic/no-extra-parens` keeps the parentheses of `(infer M)[]` and `(infer M)['k']`:** TypeScript reads `infer M[]` as `infer (M[])`, and @stylistic 6.0.1, which now checks these type positions, removes them and breaks the code (it did so in 3 files of zod). As with `(type satisfies never);`, veslint differs from ESLint here on purpose.
- `@marcrock22/eslintcf` uses @stylistic 6 too: `list-style` in place of `exp-list-style`, and without the rules 6 deprecates in favor of it (`array-bracket-spacing`, `function-call-argument-newline`, `function-paren-newline`, `object-curly-newline`, `object-curly-spacing`, `object-property-newline`).

## 0.25.2

- **`--fix` stops at a fix that breaks the code:** when the fixes of a pass give code that TypeScript's parser rejects, the file is reported with that error, `Parsing error: …`, and nothing else, and it is not fixed further, as ESLint does. tree-sitter reads some of that code (`type satisfies never;`, a declaration `type satisfies` without `=`; `<T>(x: T) => x` in a `.tsx` file, an unclosed JSX element), and such a fix went on unnoticed. Only the errors the fixes add count: the parser of tsgo 7.1 rejects some code that the one of TypeScript 6.0.3, which ESLint uses, takes (`x < 0 as any ** 2`).
- **`@stylistic/no-extra-parens` keeps the parentheses that make an expression of a statement** that TypeScript would otherwise read as a declaration: `(type satisfies never);`, `(namespace as X);`, and the same with `module`, `global` and `using`. @stylistic removes them and the code no longer parses (`void (type satisfies never);` became that through `@typescript-eslint/no-meaningless-void-operator`); here veslint differs from ESLint on purpose.
- **Fixes:** `unicorn/new-for-builtins` no longer reports the type of `(f as Function)()`, which does not call `Function`.
- **`tests/eval_eslintcf.sh`** runs the whole configuration of `@marcrock22/eslintcf` on real projects (Spider-Byte, zod, recharts and eslintcf itself) with ESLint and with veslint, and compares the findings, what `--fix` leaves and what each fix brings.

## 0.25.1

- **`perfectionist/sort-switch-case`: the cases of a block move together.** When the fix moves a block of cases that fall through (`case a:` `case b: {…}`), its cases stay together and the blank lines between blocks stay where they were. eslint-plugin-perfectionist puts each case in the place of another and can leave a blank line inside the block, which `no-fallthrough` then reports; here veslint fixes otherwise than ESLint on purpose.
- **`--bench`** lists the rules that took the longest (`slowest_rules`, at most 20, with their milliseconds).

## 0.25.0

- **20 more rules of typescript-eslint 8.72.2** (127 in all), the last of the ones `@marcrock22/eslintcf` turns on: `@typescript-eslint/ban-ts-comment`, `@typescript-eslint/ban-tslint-comment`, `@typescript-eslint/default-param-last`, `@typescript-eslint/explicit-function-return-type`, `@typescript-eslint/explicit-member-accessibility`, `@typescript-eslint/explicit-module-boundary-types`, `@typescript-eslint/init-declarations`, `@typescript-eslint/max-params`, `@typescript-eslint/member-ordering`, `@typescript-eslint/method-signature-style`, `@typescript-eslint/no-empty-object-type`, `@typescript-eslint/no-generated-empty-object-type`, `@typescript-eslint/no-invalid-this`, `@typescript-eslint/no-magic-numbers`, `@typescript-eslint/no-non-null-assertion`, `@typescript-eslint/no-redeclare`, `@typescript-eslint/no-restricted-types`, `@typescript-eslint/no-unsafe-enum-assignment`, `@typescript-eslint/parameter-properties`, `@typescript-eslint/prefer-literal-enum-member`. They come with their options, fixes and suggestions, and pass the cases of typescript-eslint's own tests.
- **14 rules of eslint-plugin-perfectionist 5.13.0**, for sorting: `perfectionist/sort-array-includes`, `perfectionist/sort-classes`, `perfectionist/sort-export-attributes`, `perfectionist/sort-exports`, `perfectionist/sort-heritage-clauses`, `perfectionist/sort-import-attributes`, `perfectionist/sort-imports`, `perfectionist/sort-intersection-types`, `perfectionist/sort-maps`, `perfectionist/sort-named-exports`, `perfectionist/sort-named-imports`, `perfectionist/sort-sets`, `perfectionist/sort-switch-case`, `perfectionist/sort-union-types`. They come with their options (groups, custom groups, partitions, newlines, comments above, `settings.perfectionist`), fixes, and pass the 3,278 cases of perfectionist's own tests.
- **The 4 rules of `@marcrock22/eslintcf` itself:** `marcrock/no-newline-if-body-class-empty`, `marcrock/numeric-separators`, `marcrock/prefer-at`, `marcrock/uppercase-first-class-letter`, with the cases of its tests.
- **Sorting as Node sorts:** `localeCompare` (perfectionist's alphabetical order, `@typescript-eslint/switch-exhaustiveness-check`) is the Unicode Collation Algorithm of ICU 78.3, the one of Node, for every string (checked on 964,714 pairs).
- **Options:** the JSON schemas take `exclusiveMinimum` and `exclusiveMaximum`, and a `default` inside `anyOf`/`oneOf`/`not`, as ESLint's ajv does.
- **Faster on files of many tsconfig files:** the state of each TypeScript project is let go after its last file, so the memory stays small and the garbage collector has less to walk (veslint's 1,529 test fixtures, each with its own tsconfig: 2 to 9 times faster per rule, 58 MB instead of 1.2 GB).
- **`--rule` and the configuration:** `--rule <rule>` takes the rule's options from the closest `eslint.config.*` (and its languageOptions, settings and ignores), as the configuration lints the files; `--no-config-lookup` keeps the default options.
- **Fixes:** `@typescript-eslint/naming-convention` no longer reports the keys of import attributes (`with { type: 'json' }`) as properties of an object literal, as ESLint does not.
- **`--rule` and directive comments:** an `eslint-disable` comment for another rule (or for every rule) is no longer reported as unused when only one rule runs, so `--fix --rule` no longer removes it.

## 0.24.1

- **Code read as TypeScript reads it** (it was a syntax error, or read otherwise):
  - A line break ends `return`, `break` and `continue`: `return⏎-a` is `return;` and `-a;` (rules such as `no-unreachable` see the second statement).
  - `namespace Foo` with its `{` on the next line is one declaration.
  - An index signature of a class may be `static`, and an index signature may have several parameters.
  - A mapped type may have no type (`{ [K in T] }`) and white space in `? :`, `-? :` and `+? :`.
  - `export` and `default` on separate lines.

## 0.24.0

- **The other 30 rules of @stylistic/eslint-plugin 5.10.0**, all of the plugin that `@marcrock22/eslintcf` turns on (54 in all): `@stylistic/arrow-parens`, `@stylistic/brace-style`, `@stylistic/comma-dangle`, `@stylistic/comma-style`, `@stylistic/dot-location`, `@stylistic/eol-last`, `@stylistic/exp-jsx-props-style`, `@stylistic/exp-list-style`, `@stylistic/function-call-argument-newline`, `@stylistic/function-paren-newline`, `@stylistic/implicit-arrow-linebreak`, `@stylistic/lines-between-class-members`, `@stylistic/member-delimiter-style`, `@stylistic/multiline-ternary`, `@stylistic/new-parens`, `@stylistic/no-extra-parens`, `@stylistic/no-extra-semi`, `@stylistic/no-floating-decimal`, `@stylistic/no-mixed-spaces-and-tabs`, `@stylistic/no-multi-spaces`, `@stylistic/no-trailing-spaces`, `@stylistic/nonblock-statement-body-position`, `@stylistic/object-curly-newline`, `@stylistic/object-property-newline`, `@stylistic/one-var-declaration-per-line`, `@stylistic/quote-props`, `@stylistic/quotes`, `@stylistic/semi`, `@stylistic/semi-style`, `@stylistic/spaced-comment`. They come with their options and fixes, and pass the cases of @stylistic's own tests.
- **Options:** the JSON schemas of the options have `patternProperties`, as ESLint's ajv; and `Infinity` in an `eslint.config.mjs` (an option of `@stylistic/exp-list-style` and `@stylistic/exp-jsx-props-style`) is taken as ESLint takes it.
- **Fixes:** the `/>` of a JSX element is two tokens, as in typescript-estree.

## 0.23.0

- **24 rules of @stylistic/eslint-plugin 5.10.0**, the first of the plugin, for spacing: `@stylistic/array-bracket-spacing`, `@stylistic/arrow-spacing`, `@stylistic/block-spacing`, `@stylistic/comma-spacing`, `@stylistic/computed-property-spacing`, `@stylistic/function-call-spacing`, `@stylistic/key-spacing`, `@stylistic/keyword-spacing`, `@stylistic/no-whitespace-before-property`, `@stylistic/object-curly-spacing`, `@stylistic/rest-spread-spacing`, `@stylistic/semi-spacing`, `@stylistic/space-before-blocks`, `@stylistic/space-before-function-paren`, `@stylistic/space-in-parens`, `@stylistic/space-infix-ops`, `@stylistic/space-unary-ops`, `@stylistic/switch-colon-spacing`, `@stylistic/template-curly-spacing`, `@stylistic/template-tag-spacing`, `@stylistic/type-annotation-spacing`, `@stylistic/type-generic-spacing`, `@stylistic/type-named-tuple-spacing`, `@stylistic/yield-star-spacing`. They come with their options and fixes, and pass the cases of @stylistic's own tests.
- **VS Code extension:** a quick fix that disables a rule for the entire file (`/* eslint-disable <rule> */` on the first line, after a `#!` line), besides the one for a line. The one for a line adds the rule to the `eslint-disable-next-line` comment already above the line (`// eslint-disable-next-line no-var, eqeqeq`) instead of a second comment on top of it, which would have disabled the rule for that comment and not for the line.
- **Fixes:**
  - The text inside a JSX element is one token, as typescript-estree gives it (JSXText, with its white space), a JSX attribute's string is JSXText and a name in a tag a JSXIdentifier: rules that look at tokens no longer take a `,` or a `(` in JSX text for punctuation.
  - `no-useless-computed-key` leaves abstract fields alone, and `no-unexpected-multiline` a dynamic `import(…)`, as ESLint does.

## 0.22.0

- **11 rules of eslint-plugin-unicorn for modules:** `unicorn/no-anonymous-default-export`, `unicorn/no-named-default`, `unicorn/no-process-exit`, `unicorn/prefer-export-from`, `unicorn/prefer-import-meta-properties`, `unicorn/prefer-json-parse-buffer`, `unicorn/prefer-module`, `unicorn/prefer-node-protocol`, `unicorn/relative-url-style`, `unicorn/require-module-attributes` and `unicorn/require-module-specifiers`. `unicorn/relative-url-style` comes with a port of the WHATWG URL parser (checked against Node's `URL` on 15,931 inputs); hosts with non-ASCII letters are not resolved yet, so they are never reported.
- **14 rules of eslint-plugin-unicorn for functions, classes and objects:** `unicorn/consistent-function-scoping`, `unicorn/isolated-functions`, `unicorn/no-accessor-recursion`, `unicorn/no-keyword-prefix`, `unicorn/no-static-only-class`, `unicorn/no-this-assignment`, `unicorn/no-unreadable-iife`, `unicorn/no-unused-properties`, `unicorn/no-useless-undefined`, `unicorn/prefer-class-fields`, `unicorn/prefer-default-parameters`, `unicorn/prefer-object-from-entries`, `unicorn/prefer-prototype-methods` and `unicorn/prefer-reflect-apply`.
- **`unicorn/better-regex`**, which unicorn 79 removed: it reports nothing, as `unicorn/prefer-json-parse-buffer` (deprecated in unicorn 79).
- They come with their options, fixes and suggestions, and pass the cases of unicorn's own tests.
- **Fixes:**
  - 16 unicorn rules put a `;` before a fix that starts with `[`, `(` or a template after a statement that ends without one (`counter++`), as unicorn 79 does.
  - `export default class {}` and `export default function () {}` end at their `}`, as TypeScript reads them: a line that starts with `(` or `[` after them is another statement.
  - `export * from 'm' with {type: 'json'}` (import attributes after the `from` of an export) is read as TypeScript reads it.
  - `new X!.y()` is `new (X!.y)()`, as TypeScript reads it: the code is analyzed instead of being skipped.
  - `no-invalid-this` reports a `this` that is the default value of a parameter (`function f(a = this)`).
  - `unicorn/isolated-functions` and `unicorn/no-keyword-prefix` accept every option ESLint accepts.

## 0.21.0

- **8 rules of eslint-plugin-unicorn for spreads and redundant calls:** `unicorn/consistent-empty-array-spread`, `unicorn/no-immediate-mutation`, `unicorn/no-useless-collection-argument`, `unicorn/no-useless-fallback-in-spread`, `unicorn/no-useless-iterator-to-array`, `unicorn/no-useless-spread`, `unicorn/prefer-single-call` and `unicorn/prefer-spread`.
- **9 rules of eslint-plugin-unicorn for promises, async code and web APIs:** `unicorn/no-await-expression-member`, `unicorn/no-await-in-promise-methods`, `unicorn/no-invalid-fetch-options`, `unicorn/no-single-promise-in-promise-methods`, `unicorn/no-thenable`, `unicorn/no-unnecessary-await`, `unicorn/no-useless-promise-resolve-reject`, `unicorn/prefer-blob-reading-methods` and `unicorn/prefer-response-static-json`.
- They come with their options, fixes and suggestions, and pass the cases of unicorn's own tests.
- **Fixes:**
  - The unicorn rules use TypeScript's types only when the parser has a program, as unicorn does (`withTypeInformation`): with `projectService: false`, some of them looked at the types all the same.
  - `getStaticValue` reads the value of a shorthand property (`{method}`) as the identifier it is.

## 0.20.0

- **7 rules that `@marcrock22/eslintcf` turns on:** `array-callback-return`, `no-lonely-if`, `no-negated-condition`, `no-throw-literal` and `require-atomic-updates` of ESLint core, and `@typescript-eslint/class-methods-use-this` and `@typescript-eslint/no-explicit-any`. They come with their options, fixes and suggestions, and pass the cases of their own tests.
- **The rules follow ESLint 10.15.0, typescript-eslint 8.72.2 and eslint-plugin-unicorn 79.0.0** (the versions of `@marcrock22/eslintcf` 0.0.1), instead of ESLint 10.6.0, typescript-eslint 8.62.0 and unicorn 64.0.0. 125 ported rules changed in those versions — new checks, messages, fixes and suggestions — and give what the new versions give; every rule passes the cases of its new upstream tests.
- **Renamed and removed rules:** `unicorn/no-array-for-each` is now `unicorn/no-for-each`. `unicorn/no-hex-escape` is deprecated in unicorn 79 and reports nothing.
- **New options:**
  - `preserve-caught-error`: `errorClassNames`.
  - `no-unmodified-loop-condition`: `checkConditionalExpressions`.
  - `@typescript-eslint/await-thenable`: `allowMixedPromiseArrays`.
  - `@typescript-eslint/no-misused-promises`: `checksConditionals: { flagUnions }`.
  - `unicorn/switch-case-braces`: `"single-statement"`.
  - `unicorn/prefer-ternary`: `checkVaryingBase` and `checkComputedMemberAccess`.
  - `unicorn/no-array-callback-reference`: `ignore`.
  - `unicorn/no-unreadable-array-destructuring`: `maximumIgnoredElements`.
- **Changed defaults:** `unicorn/prefer-number-properties` no longer checks `NaN` unless `checkNaN` is set.
- **Types in unicorn's rules:** as unicorn 79 does when the parser has a program, the unicorn rules use TypeScript's types (arrays, strings, numbers, BigInts, sets…).
- **The project service** lints a file from a program whose current directory is the one veslint runs in, as typescript-estree 8.72 does in a single run: `from: "file"` type specifiers are relative to it (with `--fix`, to the directory of the tsconfig, as before); `veslint --server` (the VS Code extension) does the same, so it gives what the command line gives.
- **Directive comments:** `__proto__` is a name like any other in `/* global */` and `/* exported */` comments (@eslint/plugin-kit 0.7.3). A comment that names `@typescript-eslint/no-generated-empty-object-type` or `@typescript-eslint/no-unsafe-enum-assignment` (new in typescript-eslint 8.72) no longer gets "Definition for rule … was not found.".
- **Scope:** as typescript-eslint 8.72's scope manager, a global declared by several of TypeScript's libraries is a type and a value when any of them declares it so (the `lib` of the tsconfig), and the global scope starts at the start of the file.
- **Fixes:**
  - `@typescript-eslint/no-unnecessary-type-assertion` overflowed the stack on a recursive generic type.
  - `prefer-const` takes every `let` declaration of a name declared more than once (TypeScript rejects it, ESLint lints it), as ESLint does: a name declared by a `const` and then by a `let` is reported, and a name declared by two `let`s is reported once for each.
  - `@typescript-eslint/prefer-readonly` and `@typescript-eslint/prefer-return-this-type` warned that a node was not analyzed on a `declare class`.
  - Grammar: after the block of an arrow function and a line break, an operator, template or regular expression starts a new statement, as in TypeScript.
- **Development:** the ESLint processes of `tests/rules/reference.sh` and `cross.sh` lint at most 15 files each (typescript-eslint 8.72 keeps a program per project).

## 0.19.1

- **VS Code extension: the open files are linted again when another file changes.** A problem that came from the types of another file (`@typescript-eslint/no-unsafe-return` on a type made `any` there, say) stayed in the editor after that file was fixed, until the file was edited, though the command line no longer gave it. Now, when a file changes (as you type, when it is saved, or on disk), the other open files of its folder are linted again after it: those on screen at once, the others when they are shown.

## 0.19.0

- **8 rules of eslint-plugin-unicorn for array lengths and indexes:** `unicorn/consistent-existence-index-check`, `unicorn/explicit-length-check`, `unicorn/no-unnecessary-array-flat-depth`, `unicorn/no-unnecessary-array-splice-count`, `unicorn/no-unnecessary-slice-end`, `unicorn/no-unreadable-array-destructuring`, `unicorn/no-useless-length-check` and `unicorn/prefer-set-size`. They come with their options, fixes and suggestions, and pass the cases of unicorn's own tests.

## 0.18.0

- **12 rules of eslint-plugin-unicorn for array methods and callbacks:** `unicorn/no-array-callback-reference`, `unicorn/no-array-for-each`, `unicorn/no-array-method-this-argument`, `unicorn/no-array-reverse`, `unicorn/no-array-sort`, `unicorn/no-new-array`, `unicorn/prefer-array-flat`, `unicorn/prefer-array-flat-map`, `unicorn/prefer-array-index-of`, `unicorn/prefer-array-some`, `unicorn/prefer-negative-index` and `unicorn/require-array-join-separator`. They come with their options, fixes and suggestions, and pass the cases of unicorn's own tests.

## 0.17.0

- **5 rules of eslint-plugin-unicorn for math and coercion:** `unicorn/prefer-math-min-max`, `unicorn/prefer-math-trunc`, `unicorn/prefer-modern-math-apis`, `unicorn/prefer-native-coercion-functions` and `unicorn/require-number-to-fixed-digits-argument`. They come with their fixes and suggestions, and pass the cases of unicorn's own tests.
- **Development:** `tests/rules/reference.sh` and `tests/rules/cross.sh` run ESLint in parallel (`JOBS`, the CPUs by default).

## 0.16.0

- **13 rules of eslint-plugin-unicorn for strings and numbers:** `unicorn/consistent-template-literal-escape`, `unicorn/escape-case`, `unicorn/no-console-spaces`, `unicorn/no-hex-escape`, `unicorn/no-zero-fractions`, `unicorn/prefer-bigint-literals`, `unicorn/prefer-code-point`, `unicorn/prefer-number-properties`, `unicorn/prefer-string-raw`, `unicorn/prefer-string-replace-all`, `unicorn/prefer-string-slice`, `unicorn/prefer-string-trim-start-end` and `unicorn/text-encoding-identifier-case`. They come with their options, fixes and suggestions, and pass the cases of unicorn's own tests.
- **Fix (grammar):** a number that starts with a dot at the start of a line (`a⏎.5`) continued the statement before it, where JavaScript ends that statement.

## 0.15.0

- **12 rules of eslint-plugin-unicorn for errors and built-ins:** `unicorn/consistent-assert`, `unicorn/consistent-date-clone`, `unicorn/custom-error-definition`, `unicorn/error-message`, `unicorn/new-for-builtins`, `unicorn/no-instanceof-builtins`, `unicorn/no-new-buffer`, `unicorn/no-useless-error-capture-stack-trace`, `unicorn/prefer-date-now`, `unicorn/prefer-structured-clone`, `unicorn/prefer-type-error` and `unicorn/throw-new-error`. They come with their options, fixes and suggestions, and pass the cases of unicorn's own tests.
- **Fix (grammar):** `new` at the end of a line (`return new⏎Foo()`, or with a comment after `new`) was read as a name, which ended the statement there. Two cases of typescript-eslint's own tests that were listed as known differences now pass.

## 0.14.0

- **12 rules of eslint-plugin-unicorn for conditions and switches:** `unicorn/no-lonely-if`, `unicorn/no-negated-condition`, `unicorn/no-negation-in-equality-check`, `unicorn/no-nested-ternary`, `unicorn/no-typeof-undefined`, `unicorn/no-useless-switch-case`, `unicorn/prefer-logical-operator-over-ternary`, `unicorn/prefer-simple-condition-first`, `unicorn/prefer-switch`, `unicorn/prefer-ternary`, `unicorn/switch-case-braces` and `unicorn/switch-case-break-position`. They come with their options, fixes and suggestions, and pass the cases of unicorn's own tests.
- **Rule options:** the `minimum` and `maximum` keywords of a rule's schema are now validated, as ESLint does.
- **The README** is shorter: install, usage, configuration and the list of supported rules.
- **Development:** `make test` runs its slow checks in parallel (`JOBS`, the CPUs by default): about 18 minutes instead of 45 on four CPUs.

## 0.13.0

- **The VS Code extension is on the Visual Studio Marketplace** as `MARCROCK22.veslint`, with the veslint logo. A `.vsix` installed from an earlier release has the identifier `veslint.veslint`: uninstall it, so that only one runs.
- **`veslint: Update veslint`** downloads the latest release for Linux x64 or Windows x64, with the TypeScript 7 compiler it runs, into the extension's storage, and lints with it from then on (unless `veslint.path` is set). When the extension cannot run veslint, it offers to download it.
- **Update notice:** at most once a day, the extension looks for a newer release and asks whether to install it, with `Update`, `Release Notes` or `Skip This Version`. Nothing is installed without asking; `veslint.checkForUpdates` turns the check off.
- **`veslint --version`** prints the version.
- The text of each GitHub release is its section of this changelog.

## 0.12.0

- **Where each problem ends.** Every rule now ends its report where ESLint's does (ESLint's `endLine` and `endColumn`): `--fixes` gives the end of each problem, and the VS Code extension underlines the same range as ESLint. For example, `restrict-template-expressions` on `${track.info.uri}` underlines `track.info.uri`, not only `track`. Problems ESLint gives no end, such as unused directives, have none.
- Every rule's fixtures now check the ends against ESLint, and so do the upstream tests of typescript-eslint, ESLint and @slipher/eslint-plugin.

## 0.11.1

- **Fix (grammar):** a member named `in` or `instanceof` at the start of a line, with no `;` before it, was read as the operator. Types generated by Prisma 6 (`commonInputTypes.ts` with `in?: string[]`) gave syntax errors and were partly left unanalyzed.

## 0.11.0

- **17 rules of ESLint core:**
  - Code paths: `constructor-super`, `getter-return`, `no-fallthrough`, `no-this-before-super`, `no-unreachable`, `no-unreachable-loop`, `no-useless-assignment` and `no-useless-return`.
  - Others: `no-constructor-return`, `no-promise-executor-return`, `no-invalid-this`, `no-restricted-exports`, `no-restricted-globals`, `no-restricted-imports`, `no-restricted-properties`, `no-restricted-syntax` and `no-warning-comments`.
- **`veslint .` and `veslint <dir>`** lint the TypeScript files of a directory as `eslint .` does, leaving out what the ESLint configuration ignores. Without `--config` or `--rule`, the closest `eslint.config.*` is used.
- **`--summary`** prints a table of the rules that reported problems (problems, errors, warnings, files) instead of a line per problem.
- **Fixes:**
  - `seyfert/no-deep-imports` keeps the quotes of the import in its fix.
  - The `pattern` keyword is now applied when rule options are validated.
  - `no-useless-assignment` skips what `@typescript-eslint/naming-convention` marks as used, as ESLint does when both run.

## 0.10.0

- **9 rules of ESLint core for regular expressions:** `no-control-regex`, `no-div-regex`, `no-empty-character-class`, `no-invalid-regexp`, `no-misleading-character-class`, `no-regex-spaces`, `no-useless-backreference`, `no-useless-escape` and `prefer-regex-literals`.

## 0.9.0

- **10 rules of ESLint core for declarations and loops:** `no-var`, `prefer-const`, `vars-on-top`, `sort-vars`, `strict`, `no-inner-declarations`, `no-lone-blocks`, `no-loop-func`, `no-implicit-globals` and `no-unmodified-loop-condition`.
- **Fix:** options of ESLint core rules past their defaults were lost every other one.

## 0.8.0

- **12 rules of ESLint core for bindings:** `no-class-assign`, `no-const-assign`, `no-ex-assign`, `no-func-assign`, `no-global-assign`, `no-import-assign`, `no-label-var`, `no-shadow-restricted-names`, `no-unassigned-vars`, `no-delete-var`, `block-scoped-var` and `consistent-this`.

## 0.7.0

- **11 rules of ESLint core for globals and properties:** `no-extend-native`, `no-implied-eval`, `no-caller`, `no-iterator`, `no-proto`, `no-script-url`, `no-prototype-builtins`, `prefer-object-has-own`, `prefer-object-spread`, `dot-notation` and `preserve-caught-error`.

## 0.6.0

- **13 rules of ESLint core for calls and constructors:** `no-new`, `no-new-func`, `no-new-wrappers`, `no-new-native-nonconstructor`, `no-obj-calls`, `no-object-constructor`, `no-async-promise-executor`, `no-extra-bind`, `no-useless-call`, `prefer-spread`, `prefer-rest-params`, `symbol-description` and `radix`.

## 0.5.0

- **12 rules of ESLint core for literals and strings:** `no-loss-of-precision`, `no-nonoctal-decimal-escape`, `no-octal`, `no-octal-escape`, `prefer-numeric-literals`, `no-multi-str`, `no-template-curly-in-string`, `no-useless-concat`, `prefer-template`, `no-irregular-whitespace`, `unicode-bom` and `no-sparse-arrays`.

## 0.4.0

- **11 rules of ESLint core for operators and equality:** `eqeqeq`, `yoda`, `no-eq-null`, `no-extra-boolean-cast`, `no-implicit-coercion`, `logical-assignment-operators`, `operator-assignment`, `prefer-exponentiation-operator`, `no-sequences`, `no-return-assign` and `no-unexpected-multiline`.
- **Fix:** `@typescript-eslint/no-unnecessary-condition` on the left side of `??` (`!!a ?? b`).

## 0.3.0

- **13 rules of ESLint core for functions, classes and objects:** `arrow-body-style`, `prefer-arrow-callback`, `func-name-matching`, `func-names`, `grouped-accessor-pairs`, `no-setter-return`, `no-dupe-args`, `no-dupe-keys`, `no-empty-pattern`, `no-useless-rename`, `no-useless-computed-key`, `object-shorthand` and `require-yield`.
- **Fix:** decorators start a class member, auto-accessors are not class fields, and overloads count as methods.

## 0.2.0

- **13 rules of ESLint core for statements and blocks:** `curly`, `no-else-return`, `no-empty`, `no-empty-static-block`, `default-case-last`, `no-case-declarations`, `no-labels`, `no-extra-label`, `no-unused-labels`, `no-with`, `no-debugger`, `no-unsafe-finally` and `no-useless-catch`.
- **Fix:** options of ESLint core rules past their defaults are kept.

## 0.1.0

- **13 rules of ESLint core for comparisons and conditions:** `no-compare-neg-zero`, `use-isnan`, `valid-typeof`, `no-dupe-else-if`, `no-duplicate-case`, `no-self-compare`, `no-self-assign`, `no-unsafe-negation`, `no-unsafe-optional-chaining`, `no-cond-assign`, `for-direction`, `no-constant-condition` and `no-constant-binary-expression`.
- **Fix:** `@typescript-eslint/no-unnecessary-condition` on a comparison with a negated operand (`!1 < 2`).

## 0.0.2

- **Faster while typing:**
  - The server reads requests on a thread of its own and gives up a lint when a newer one for the same file arrives.
  - The extension sends a lint without waiting for the answer to the one before.
- **Faster constant evaluation**, and less garbage collection on large files.

## 0.0.1

- First release.
- 105 typescript-eslint rules and the 15 `seyfert/*` rules of @slipher/eslint-plugin, with the same messages, fixes and suggestions.
- ESLint's directive comments and configuration files.
- A server mode (`--server`) and the VS Code extension.
- Linux x64 and Windows x64.
