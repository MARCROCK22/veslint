<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/veslint-logo-dark.svg">
    <img alt="veslint" src="assets/veslint-logo.svg" height="72">
  </picture>
</p>
<p align="center">A TypeScript linter in V that talks to TypeScript 7 (<code>tsc --api</code>) directly</p>

# veslint

veslint lints TypeScript with ESLint's rules, without ESLint. It parses with tree-sitter, gets the types from the native TypeScript 7 compiler, and needs no JavaScript runtime to lint.

- **Same results as ESLint.** The rules of ESLint, typescript-eslint, eslint-plugin-unicorn, @stylistic/eslint-plugin, eslint-plugin-perfectionist and @slipher/eslint-plugin are ported to V. They report the same problems, with the same messages, positions, fixes and suggestions.
- **Your ESLint configuration.** veslint reads `eslint.config.*`, the directive comments (`// eslint-disable-next-line`, `/* eslint rule: … */`, `/* global */`) and rule options. A rule it does not have yet is skipped with a warning.
- **Fast.** On a Discord bot of 65 TypeScript files, the 105 typescript-eslint rules in one run take 3.2 s with veslint and 11.7 s with ESLint (one core of an old i3). In the editor, a file is linted again about 0.1 s after you type.
- **An editor extension** for VS Code shows the problems as you type, with quick fixes.

## Install

### VS Code

Install **veslint** from the Visual Studio Marketplace (`MARCROCK22.veslint`), then run **veslint: Update veslint** from the command palette. It downloads veslint for your platform and keeps it up to date: once a day at most it asks whether to install a newer release. See [the extension's README](editors/vscode/README.md) for its settings.

### Command line

Download `veslint-<version>-linux-x64.tar.gz` or `veslint-<version>-win32-x64.zip` from the [releases](https://github.com/MARCROCK22/veslint/releases) and unpack it anywhere. It contains the `veslint` binary and the TypeScript 7 compiler it uses; keep them together. `veslint --version` prints the version.

### npm

```sh
npm install --save-dev @marcrock22/veslint   # or: bun add -d, pnpm add -D, yarn add -D
npx veslint .
```

It installs the `veslint` command with the binary of your platform and the TypeScript 7 compiler it uses. `npm install --global @marcrock22/veslint` puts `veslint` in your `PATH`.

veslint runs on **Linux x64** (glibc) and **Windows x64**. On other platforms, [build it from source](#building-from-source).

## Quick start

```sh
veslint .                          # lint the TypeScript files of the project with its eslint.config.*
veslint src --fix                  # apply the fixes, and print what is left
veslint . --summary                # a table of the rules that report problems
veslint --rule @typescript-eslint/no-floating-promises src/index.ts
```

Each problem is one line: `path:line:column`, the rule, its `messageId` and the message, separated by tabs.

```
src/index.ts:12:3	@typescript-eslint/no-floating-promises	floatingVoid	Promises must be awaited, end with a call to .catch, end with a call to .then with a rejection handler or be explicitly marked as ignored with the `void` operator.
```

## Command line

```
veslint <file.ts | directory>... [--config <file>] [--rule <rule> [--no-config-lookup]] [--project <tsconfig.json>] [--fix] [--fixes | --summary]
```

| Option | What it does |
|---|---|
| `<directory>` | Lints the `.ts`, `.mts`, `.cts`, `.tsx`, `.vue` and `.svelte` files under it, as `eslint .` does: `node_modules`, `.git` and what the configuration ignores are left out. |
| `<file.ts>` | Lints that file. JavaScript files are not linted: veslint only reads TypeScript. |
| `<file.vue>` | Lints the TypeScript script of a Vue file (`<script lang="ts">` and `<script setup lang="ts">`) and, with the `vue/*` rules, its template, as ESLint does with vue-eslint-parser and typescript-eslint's parser: the rules see the script with the positions of the file, and the types are those typescript-eslint gives with `extraFileExtensions: ['.vue']`. A Vue file whose script is JavaScript is skipped with a warning. |
| `<file.svelte>` | Lints the TypeScript script of a Svelte file (`<script lang="ts">`, `<script module lang="ts">`) and the `.svelte.ts` modules, as ESLint does with svelte-eslint-parser and typescript-eslint's parser: runes, stores (`$store`), `$:` statements, props and generics as svelte-eslint-parser models them, and the types typescript-eslint gives with `extraFileExtensions: ['.svelte']`. A Svelte file whose script is JavaScript is not linted (with a warning). The rules of eslint-plugin-svelte come in the next versions. |
| `--config <file>` | The configuration (see below). Without it and without `--rule`, a directory is linted with the closest `eslint.config.*`. |
| `--rule <rule>` | Lints with one rule, named as in ESLint: `no-var`, `@typescript-eslint/await-thenable`. Its options, and the files it lints, are the ones the closest `eslint.config.*` gives it (on with its default options when the configuration has it off); without a configuration, its default options. Directive comments for other rules are left alone: they are never reported as unused, and `--fix` keeps them. |
| `--no-config-lookup` | With `--rule`: the rule's default options, without looking for an `eslint.config.*`. |
| `--project <tsconfig.json>` | The tsconfig to use. Without it, the one the configuration names in `parserOptions.project`, or the closest `tsconfig.json`. |
| `--fix` | Applies the fixes and rewrites the files, like `eslint --fix`, and prints the problems that remain. |
| `--fixes` | Prints each problem with its fix, its suggestions and where it ends. |
| `--summary` | Instead of a line per problem, a table of the rules that reported problems: how many, errors, warnings and files. |
| `--print-config` | Prints the configuration resolved for the files, a JSON that `--config` reads without running JavaScript. |
| `--server` | A process for editors that stays alive between lints (the VS Code extension uses it). |
| `--version` | Prints the version. |

With files and neither `--config` nor `--rule`, veslint prints the type TypeScript infers for each declared name, a mode for debugging.

The exit code is 0 when there are no problems, 1 when there are (warnings do not count, as in ESLint) or veslint failed, and 2 for a usage error.

Environment variables: `VESLINT_TIMEOUT_MS` (how long to wait for each answer of the TypeScript compiler, 30000 by default), `VESLINT_CPUS` (how many CPUs veslint and the compiler use: 2 by default, which is fastest; 0 for all) and `VESLINT_CONFIG_CACHE` (`0` resolves the `eslint.config.*` again on every run, see [Configuration](#configuration)).

## Configuration

`--config` takes one of these:

- **An ESLint configuration** (`eslint.config.js`, `.mjs`, `.cjs`, `.ts`, `.mts`, `.cts`). It is JavaScript, so veslint asks your project's own ESLint to resolve it, which needs [`bun`](https://bun.sh) and ESLint installed in the project. `files`, `ignores`, rules per folder, `linterOptions` and `languageOptions` work as in ESLint.

  Resolving it loads ESLint and every plugin, often more than a second, so veslint saves what ESLint resolved in `node_modules/.cache/veslint` (the closest `node_modules`) and uses it again until something it came from changes: the configuration, a file or module it reads (including the plugins), an environment variable it reads, the files to lint, or the `eslint.config.*` that applies to a folder. `VESLINT_CONFIG_CACHE=0` turns that off.
- **The resolved configuration** that `--print-config` prints. It needs neither `bun` nor ESLint: save it once and lint with it. The paths in it are relative to its own folder, so save it inside the project, at the place you ran `--print-config` from or above it, for example next to the `eslint.config.*` (`veslint --print-config . > veslint.json`). Saved elsewhere, its files are not found.
- **A JSON with a `rules` section**, like the output of `eslint --print-config`:

  ```json
  {"rules": {"@typescript-eslint/no-floating-promises": "error", "eqeqeq": ["warn", "smart"]}}
  ```

Rule options are validated like ESLint validates them, with the same error messages. Rules veslint does not have are skipped with a warning that names them.

Directive comments work as in ESLint 10: `eslint-disable`, `eslint-enable`, `eslint-disable-line` and `eslint-disable-next-line` (with a `-- reason` or not), `/* eslint rule: value */`, `/* global name */` and `/* exported name */`. Unused `eslint-disable` comments are reported, with a fix that removes them.

## Rules

veslint has **746 rules**, each with all its options, fixes and suggestions:

<details>
<summary><b>ESLint 10.15.0</b>: 139 rules</summary>

`array-callback-return`, `arrow-body-style`, `block-scoped-var`, `consistent-this`, `constructor-super`, `curly`, `default-case-last`, `dot-notation`, `eqeqeq`, `for-direction`, `func-name-matching`, `func-names`, `getter-return`, `grouped-accessor-pairs`, `logical-assignment-operators`, `no-async-promise-executor`, `no-caller`, `no-case-declarations`, `no-class-assign`, `no-compare-neg-zero`, `no-cond-assign`, `no-const-assign`, `no-constant-binary-expression`, `no-constant-condition`, `no-constructor-return`, `no-control-regex`, `no-debugger`, `no-delete-var`, `no-div-regex`, `no-dupe-args`, `no-dupe-else-if`, `no-dupe-keys`, `no-duplicate-case`, `no-else-return`, `no-empty`, `no-empty-character-class`, `no-empty-pattern`, `no-empty-static-block`, `no-eq-null`, `no-ex-assign`, `no-extend-native`, `no-extra-bind`, `no-extra-boolean-cast`, `no-extra-label`, `no-fallthrough`, `no-func-assign`, `no-global-assign`, `no-implicit-coercion`, `no-implicit-globals`, `no-implied-eval`, `no-import-assign`, `no-inner-declarations`, `no-invalid-regexp`, `no-invalid-this`, `no-irregular-whitespace`, `no-iterator`, `no-label-var`, `no-labels`, `no-lone-blocks`, `no-lonely-if`, `no-loop-func`, `no-loss-of-precision`, `no-misleading-character-class`, `no-multi-str`, `no-negated-condition`, `no-new`, `no-new-func`, `no-new-native-nonconstructor`, `no-new-wrappers`, `no-nonoctal-decimal-escape`, `no-obj-calls`, `no-object-constructor`, `no-octal`, `no-octal-escape`, `no-promise-executor-return`, `no-proto`, `no-prototype-builtins`, `no-regex-spaces`, `no-restricted-exports`, `no-restricted-globals`, `no-restricted-imports`, `no-restricted-properties`, `no-restricted-syntax`, `no-return-assign`, `no-script-url`, `no-self-assign`, `no-self-compare`, `no-sequences`, `no-setter-return`, `no-shadow-restricted-names`, `no-sparse-arrays`, `no-template-curly-in-string`, `no-this-before-super`, `no-throw-literal`, `no-unassigned-vars`, `no-unexpected-multiline`, `no-unmodified-loop-condition`, `no-unreachable`, `no-unreachable-loop`, `no-unsafe-finally`, `no-unsafe-negation`, `no-unsafe-optional-chaining`, `no-unused-labels`, `no-useless-assignment`, `no-useless-backreference`, `no-useless-call`, `no-useless-catch`, `no-useless-computed-key`, `no-useless-concat`, `no-useless-escape`, `no-useless-rename`, `no-useless-return`, `no-var`, `no-warning-comments`, `no-with`, `object-shorthand`, `operator-assignment`, `prefer-arrow-callback`, `prefer-const`, `prefer-exponentiation-operator`, `prefer-numeric-literals`, `prefer-object-has-own`, `prefer-object-spread`, `prefer-regex-literals`, `prefer-rest-params`, `prefer-spread`, `prefer-template`, `preserve-caught-error`, `radix`, `require-atomic-updates`, `require-yield`, `sort-vars`, `strict`, `symbol-description`, `unicode-bom`, `use-isnan`, `valid-typeof`, `vars-on-top`, `yoda`

</details>

<details>
<summary><b>typescript-eslint 8.72.2</b>: 127 rules (63 of them use types)</summary>

`@typescript-eslint/adjacent-overload-signatures`, `@typescript-eslint/array-type`, `@typescript-eslint/await-thenable`, `@typescript-eslint/ban-ts-comment`, `@typescript-eslint/ban-tslint-comment`, `@typescript-eslint/class-literal-property-style`, `@typescript-eslint/class-methods-use-this`, `@typescript-eslint/consistent-generic-constructors`, `@typescript-eslint/consistent-indexed-object-style`, `@typescript-eslint/consistent-return`, `@typescript-eslint/consistent-type-assertions`, `@typescript-eslint/consistent-type-definitions`, `@typescript-eslint/consistent-type-exports`, `@typescript-eslint/consistent-type-imports`, `@typescript-eslint/default-param-last`, `@typescript-eslint/dot-notation`, `@typescript-eslint/explicit-function-return-type`, `@typescript-eslint/explicit-member-accessibility`, `@typescript-eslint/explicit-module-boundary-types`, `@typescript-eslint/init-declarations`, `@typescript-eslint/max-params`, `@typescript-eslint/member-ordering`, `@typescript-eslint/method-signature-style`, `@typescript-eslint/naming-convention`, `@typescript-eslint/no-array-constructor`, `@typescript-eslint/no-array-delete`, `@typescript-eslint/no-base-to-string`, `@typescript-eslint/no-confusing-non-null-assertion`, `@typescript-eslint/no-confusing-void-expression`, `@typescript-eslint/no-deprecated`, `@typescript-eslint/no-dupe-class-members`, `@typescript-eslint/no-duplicate-enum-values`, `@typescript-eslint/no-duplicate-type-constituents`, `@typescript-eslint/no-dynamic-delete`, `@typescript-eslint/no-empty-function`, `@typescript-eslint/no-empty-object-type`, `@typescript-eslint/no-explicit-any`, `@typescript-eslint/no-extra-non-null-assertion`, `@typescript-eslint/no-extraneous-class`, `@typescript-eslint/no-floating-promises`, `@typescript-eslint/no-for-in-array`, `@typescript-eslint/no-generated-empty-object-type`, `@typescript-eslint/no-implied-eval`, `@typescript-eslint/no-import-type-side-effects`, `@typescript-eslint/no-inferrable-types`, `@typescript-eslint/no-invalid-this`, `@typescript-eslint/no-invalid-void-type`, `@typescript-eslint/no-magic-numbers`, `@typescript-eslint/no-meaningless-void-operator`, `@typescript-eslint/no-misused-new`, `@typescript-eslint/no-misused-promises`, `@typescript-eslint/no-misused-spread`, `@typescript-eslint/no-mixed-enums`, `@typescript-eslint/no-namespace`, `@typescript-eslint/no-non-null-asserted-nullish-coalescing`, `@typescript-eslint/no-non-null-asserted-optional-chain`, `@typescript-eslint/no-non-null-assertion`, `@typescript-eslint/no-redeclare`, `@typescript-eslint/no-redundant-type-constituents`, `@typescript-eslint/no-require-imports`, `@typescript-eslint/no-restricted-types`, `@typescript-eslint/no-shadow`, `@typescript-eslint/no-this-alias`, `@typescript-eslint/no-unnecessary-boolean-literal-compare`, `@typescript-eslint/no-unnecessary-condition`, `@typescript-eslint/no-unnecessary-parameter-property-assignment`, `@typescript-eslint/no-unnecessary-qualifier`, `@typescript-eslint/no-unnecessary-template-expression`, `@typescript-eslint/no-unnecessary-type-arguments`, `@typescript-eslint/no-unnecessary-type-assertion`, `@typescript-eslint/no-unnecessary-type-constraint`, `@typescript-eslint/no-unnecessary-type-conversion`, `@typescript-eslint/no-unnecessary-type-parameters`, `@typescript-eslint/no-unsafe-argument`, `@typescript-eslint/no-unsafe-assignment`, `@typescript-eslint/no-unsafe-call`, `@typescript-eslint/no-unsafe-declaration-merging`, `@typescript-eslint/no-unsafe-enum-assignment`, `@typescript-eslint/no-unsafe-enum-comparison`, `@typescript-eslint/no-unsafe-function-type`, `@typescript-eslint/no-unsafe-member-access`, `@typescript-eslint/no-unsafe-return`, `@typescript-eslint/no-unsafe-type-assertion`, `@typescript-eslint/no-unsafe-unary-minus`, `@typescript-eslint/no-unused-expressions`, `@typescript-eslint/no-unused-private-class-members`, `@typescript-eslint/no-unused-vars`, `@typescript-eslint/no-use-before-define`, `@typescript-eslint/no-useless-constructor`, `@typescript-eslint/no-useless-default-assignment`, `@typescript-eslint/no-useless-empty-export`, `@typescript-eslint/no-wrapper-object-types`, `@typescript-eslint/non-nullable-type-assertion-style`, `@typescript-eslint/only-throw-error`, `@typescript-eslint/parameter-properties`, `@typescript-eslint/prefer-as-const`, `@typescript-eslint/prefer-destructuring`, `@typescript-eslint/prefer-enum-initializers`, `@typescript-eslint/prefer-find`, `@typescript-eslint/prefer-for-of`, `@typescript-eslint/prefer-function-type`, `@typescript-eslint/prefer-includes`, `@typescript-eslint/prefer-literal-enum-member`, `@typescript-eslint/prefer-namespace-keyword`, `@typescript-eslint/prefer-nullish-coalescing`, `@typescript-eslint/prefer-optional-chain`, `@typescript-eslint/prefer-promise-reject-errors`, `@typescript-eslint/prefer-readonly`, `@typescript-eslint/prefer-readonly-parameter-types`, `@typescript-eslint/prefer-reduce-type-parameter`, `@typescript-eslint/prefer-regexp-exec`, `@typescript-eslint/prefer-return-this-type`, `@typescript-eslint/prefer-string-starts-ends-with`, `@typescript-eslint/promise-function-async`, `@typescript-eslint/related-getter-setter-pairs`, `@typescript-eslint/require-array-sort-compare`, `@typescript-eslint/require-await`, `@typescript-eslint/restrict-plus-operands`, `@typescript-eslint/restrict-template-expressions`, `@typescript-eslint/return-await`, `@typescript-eslint/strict-boolean-expressions`, `@typescript-eslint/strict-void-return`, `@typescript-eslint/switch-exhaustiveness-check`, `@typescript-eslint/triple-slash-reference`, `@typescript-eslint/unbound-method`, `@typescript-eslint/unified-signatures`, `@typescript-eslint/use-unknown-in-catch-callback-variable`

</details>

<details>
<summary><b>eslint-plugin-unicorn 79.0.0</b>: 105 rules</summary>

`unicorn/better-regex`, `unicorn/consistent-assert`, `unicorn/consistent-date-clone`, `unicorn/consistent-empty-array-spread`, `unicorn/consistent-existence-index-check`, `unicorn/consistent-function-scoping`, `unicorn/consistent-template-literal-escape`, `unicorn/custom-error-definition`, `unicorn/error-message`, `unicorn/escape-case`, `unicorn/explicit-length-check`, `unicorn/isolated-functions`, `unicorn/new-for-builtins`, `unicorn/no-accessor-recursion`, `unicorn/no-anonymous-default-export`, `unicorn/no-array-callback-reference`, `unicorn/no-array-method-this-argument`, `unicorn/no-array-reverse`, `unicorn/no-array-sort`, `unicorn/no-await-expression-member`, `unicorn/no-await-in-promise-methods`, `unicorn/no-console-spaces`, `unicorn/no-for-each`, `unicorn/no-hex-escape`, `unicorn/no-immediate-mutation`, `unicorn/no-instanceof-builtins`, `unicorn/no-invalid-fetch-options`, `unicorn/no-keyword-prefix`, `unicorn/no-lonely-if`, `unicorn/no-named-default`, `unicorn/no-negated-condition`, `unicorn/no-negation-in-equality-check`, `unicorn/no-nested-ternary`, `unicorn/no-new-array`, `unicorn/no-new-buffer`, `unicorn/no-process-exit`, `unicorn/no-single-promise-in-promise-methods`, `unicorn/no-static-only-class`, `unicorn/no-thenable`, `unicorn/no-this-assignment`, `unicorn/no-typeof-undefined`, `unicorn/no-unnecessary-array-flat-depth`, `unicorn/no-unnecessary-array-splice-count`, `unicorn/no-unnecessary-await`, `unicorn/no-unnecessary-slice-end`, `unicorn/no-unreadable-array-destructuring`, `unicorn/no-unreadable-iife`, `unicorn/no-unused-properties`, `unicorn/no-useless-collection-argument`, `unicorn/no-useless-error-capture-stack-trace`, `unicorn/no-useless-fallback-in-spread`, `unicorn/no-useless-iterator-to-array`, `unicorn/no-useless-length-check`, `unicorn/no-useless-promise-resolve-reject`, `unicorn/no-useless-spread`, `unicorn/no-useless-switch-case`, `unicorn/no-useless-undefined`, `unicorn/no-zero-fractions`, `unicorn/prefer-array-flat`, `unicorn/prefer-array-flat-map`, `unicorn/prefer-array-index-of`, `unicorn/prefer-array-some`, `unicorn/prefer-bigint-literals`, `unicorn/prefer-blob-reading-methods`, `unicorn/prefer-class-fields`, `unicorn/prefer-code-point`, `unicorn/prefer-date-now`, `unicorn/prefer-default-parameters`, `unicorn/prefer-export-from`, `unicorn/prefer-import-meta-properties`, `unicorn/prefer-json-parse-buffer`, `unicorn/prefer-logical-operator-over-ternary`, `unicorn/prefer-math-min-max`, `unicorn/prefer-math-trunc`, `unicorn/prefer-modern-math-apis`, `unicorn/prefer-module`, `unicorn/prefer-native-coercion-functions`, `unicorn/prefer-negative-index`, `unicorn/prefer-node-protocol`, `unicorn/prefer-number-properties`, `unicorn/prefer-object-from-entries`, `unicorn/prefer-prototype-methods`, `unicorn/prefer-reflect-apply`, `unicorn/prefer-response-static-json`, `unicorn/prefer-set-size`, `unicorn/prefer-simple-condition-first`, `unicorn/prefer-single-call`, `unicorn/prefer-spread`, `unicorn/prefer-string-raw`, `unicorn/prefer-string-replace-all`, `unicorn/prefer-string-slice`, `unicorn/prefer-string-trim-start-end`, `unicorn/prefer-structured-clone`, `unicorn/prefer-switch`, `unicorn/prefer-ternary`, `unicorn/prefer-type-error`, `unicorn/relative-url-style`, `unicorn/require-array-join-separator`, `unicorn/require-module-attributes`, `unicorn/require-module-specifiers`, `unicorn/require-number-to-fixed-digits-argument`, `unicorn/switch-case-braces`, `unicorn/switch-case-break-position`, `unicorn/text-encoding-identifier-case`, `unicorn/throw-new-error`

</details>

<details>
<summary><b>@stylistic/eslint-plugin 6.0.1</b>: 54 rules</summary>

`@stylistic/array-bracket-spacing`, `@stylistic/arrow-parens`, `@stylistic/arrow-spacing`, `@stylistic/block-spacing`, `@stylistic/brace-style`, `@stylistic/comma-dangle`, `@stylistic/comma-spacing`, `@stylistic/comma-style`, `@stylistic/computed-property-spacing`, `@stylistic/dot-location`, `@stylistic/eol-last`, `@stylistic/exp-jsx-props-style`, `@stylistic/function-call-argument-newline`, `@stylistic/function-call-spacing`, `@stylistic/function-paren-newline`, `@stylistic/implicit-arrow-linebreak`, `@stylistic/key-spacing`, `@stylistic/keyword-spacing`, `@stylistic/lines-between-class-members`, `@stylistic/list-style`, `@stylistic/member-delimiter-style`, `@stylistic/multiline-ternary`, `@stylistic/new-parens`, `@stylistic/no-extra-parens`, `@stylistic/no-extra-semi`, `@stylistic/no-floating-decimal`, `@stylistic/no-mixed-spaces-and-tabs`, `@stylistic/no-multi-spaces`, `@stylistic/no-trailing-spaces`, `@stylistic/no-whitespace-before-property`, `@stylistic/nonblock-statement-body-position`, `@stylistic/object-curly-newline`, `@stylistic/object-curly-spacing`, `@stylistic/object-property-newline`, `@stylistic/one-var-declaration-per-line`, `@stylistic/quote-props`, `@stylistic/quotes`, `@stylistic/rest-spread-spacing`, `@stylistic/semi`, `@stylistic/semi-spacing`, `@stylistic/semi-style`, `@stylistic/space-before-blocks`, `@stylistic/space-before-function-paren`, `@stylistic/space-in-parens`, `@stylistic/space-infix-ops`, `@stylistic/space-unary-ops`, `@stylistic/spaced-comment`, `@stylistic/switch-colon-spacing`, `@stylistic/template-curly-spacing`, `@stylistic/template-tag-spacing`, `@stylistic/type-annotation-spacing`, `@stylistic/type-generic-spacing`, `@stylistic/type-named-tuple-spacing`, `@stylistic/yield-star-spacing`

</details>

<details>
<summary><b>eslint-plugin-perfectionist 5.13.0</b>: 14 rules</summary>

`perfectionist/sort-array-includes`, `perfectionist/sort-classes`, `perfectionist/sort-export-attributes`, `perfectionist/sort-exports`, `perfectionist/sort-heritage-clauses`, `perfectionist/sort-import-attributes`, `perfectionist/sort-imports`, `perfectionist/sort-intersection-types`, `perfectionist/sort-maps`, `perfectionist/sort-named-exports`, `perfectionist/sort-named-imports`, `perfectionist/sort-sets`, `perfectionist/sort-switch-case`, `perfectionist/sort-union-types`

</details>

<details>
<summary><b>eslint-plugin-vue 10.12.1</b> (the templates and scripts of <code>.vue</code> files, and the components of TypeScript files): 254 rules</summary>

`vue/array-bracket-newline`, `vue/array-bracket-spacing`, `vue/array-element-newline`, `vue/arrow-spacing`, `vue/attribute-hyphenation`, `vue/attributes-order`, `vue/block-lang`, `vue/block-order`, `vue/block-spacing`, `vue/block-tag-newline`, `vue/brace-style`, `vue/camelcase`, `vue/comma-dangle`, `vue/comma-spacing`, `vue/comma-style`, `vue/comment-directive`, `vue/component-api-style`, `vue/component-definition-name-casing`, `vue/component-name-in-template-casing`, `vue/component-options-name-casing`, `vue/custom-event-name-casing`, `vue/define-emits-declaration`, `vue/define-macros-order`, `vue/define-props-declaration`, `vue/define-props-destructuring`, `vue/dot-location`, `vue/dot-notation`, `vue/enforce-style-attribute`, `vue/eqeqeq`, `vue/first-attribute-linebreak`, `vue/func-call-spacing`, `vue/html-button-has-type`, `vue/html-closing-bracket-newline`, `vue/html-closing-bracket-spacing`, `vue/html-comment-content-newline`, `vue/html-comment-content-spacing`, `vue/html-comment-indent`, `vue/html-end-tags`, `vue/html-quotes`, `vue/html-self-closing`, `vue/jsx-uses-vars`, `vue/key-spacing`, `vue/keyword-spacing`, `vue/match-component-file-name`, `vue/match-component-import-name`, `vue/max-attributes-per-line`, `vue/max-len`, `vue/max-lines-per-block`, `vue/max-props`, `vue/max-template-depth`, `vue/multi-word-component-names`, `vue/multiline-html-element-content-newline`, `vue/multiline-ternary`, `vue/mustache-interpolation-spacing`, `vue/new-line-between-multi-line-property`, `vue/next-tick-style`, `vue/no-arrow-functions-in-watch`, `vue/no-async-in-computed-properties`, `vue/no-bare-strings-in-template`, `vue/no-boolean-default`, `vue/no-child-content`, `vue/no-computed-properties-in-data`, `vue/no-console`, `vue/no-constant-condition`, `vue/no-content-outside-block`, `vue/no-custom-modifiers-on-v-model`, `vue/no-define-model-default`, `vue/no-deprecated-data-object-declaration`, `vue/no-deprecated-delete-set`, `vue/no-deprecated-destroyed-lifecycle`, `vue/no-deprecated-dollar-listeners-api`, `vue/no-deprecated-dollar-scopedslots-api`, `vue/no-deprecated-events-api`, `vue/no-deprecated-filter`, `vue/no-deprecated-functional-template`, `vue/no-deprecated-html-element-is`, `vue/no-deprecated-inline-template`, `vue/no-deprecated-model-definition`, `vue/no-deprecated-props-default-this`, `vue/no-deprecated-router-link-tag-prop`, `vue/no-deprecated-scope-attribute`, `vue/no-deprecated-slot-attribute`, `vue/no-deprecated-slot-scope-attribute`, `vue/no-deprecated-v-bind-sync`, `vue/no-deprecated-v-is`, `vue/no-deprecated-v-on-native-modifier`, `vue/no-deprecated-v-on-number-modifiers`, `vue/no-deprecated-vue-config-keycodes`, `vue/no-dupe-keys`, `vue/no-dupe-v-else-if`, `vue/no-duplicate-attr-inheritance`, `vue/no-duplicate-attributes`, `vue/no-duplicate-class-names`, `vue/no-empty-component-block`, `vue/no-empty-pattern`, `vue/no-export-in-script-setup`, `vue/no-expose-after-await`, `vue/no-extra-parens`, `vue/no-implicit-coercion`, `vue/no-import-compiler-macros`, `vue/no-irregular-whitespace`, `vue/no-lifecycle-after-await`, `vue/no-literals-in-template`, `vue/no-lone-template`, `vue/no-loss-of-precision`, `vue/no-multi-spaces`, `vue/no-multiple-objects-in-class`, `vue/no-multiple-slot-args`, `vue/no-multiple-template-root`, `vue/no-mutating-props`, `vue/no-negated-condition`, `vue/no-negated-v-if-condition`, `vue/no-parsing-error`, `vue/no-potential-component-option-typo`, `vue/no-props-shadow`, `vue/no-ref-as-operand`, `vue/no-ref-object-reactivity-loss`, `vue/no-required-prop-with-default`, `vue/no-reserved-component-names`, `vue/no-reserved-keys`, `vue/no-reserved-props`, `vue/no-restricted-block`, `vue/no-restricted-call-after-await`, `vue/no-restricted-class`, `vue/no-restricted-component-names`, `vue/no-restricted-component-options`, `vue/no-restricted-custom-event`, `vue/no-restricted-html-elements`, `vue/no-restricted-props`, `vue/no-restricted-static-attribute`, `vue/no-restricted-syntax`, `vue/no-restricted-v-bind`, `vue/no-restricted-v-on`, `vue/no-root-v-if`, `vue/no-setup-props-reactivity-loss`, `vue/no-shadow-native-events`, `vue/no-shared-component-data`, `vue/no-side-effects-in-computed-properties`, `vue/no-spaces-around-equal-signs-in-attribute`, `vue/no-sparse-arrays`, `vue/no-static-inline-styles`, `vue/no-template-key`, `vue/no-template-shadow`, `vue/no-template-target-blank`, `vue/no-textarea-mustache`, `vue/no-this-in-before-route-enter`, `vue/no-undef-components`, `vue/no-undef-directives`, `vue/no-undef-properties`, `vue/no-unsupported-features`, `vue/no-unused-components`, `vue/no-unused-emit-declarations`, `vue/no-unused-properties`, `vue/no-unused-refs`, `vue/no-unused-vars`, `vue/no-use-computed-property-like-method`, `vue/no-use-v-else-with-v-for`, `vue/no-use-v-if-with-v-for`, `vue/no-useless-concat`, `vue/no-useless-mustaches`, `vue/no-useless-template-attributes`, `vue/no-useless-v-bind`, `vue/no-v-for-template-key`, `vue/no-v-for-template-key-on-child`, `vue/no-v-html`, `vue/no-v-model-argument`, `vue/no-v-text`, `vue/no-v-text-v-html-on-component`, `vue/no-watch-after-await`, `vue/object-curly-newline`, `vue/object-curly-spacing`, `vue/object-property-newline`, `vue/object-shorthand`, `vue/one-component-per-file`, `vue/operator-linebreak`, `vue/order-in-components`, `vue/padding-line-between-blocks`, `vue/padding-line-between-tags`, `vue/padding-lines-in-component-definition`, `vue/prefer-define-options`, `vue/prefer-import-from-vue`, `vue/prefer-prop-type-boolean-first`, `vue/prefer-separate-static-class`, `vue/prefer-single-event-payload`, `vue/prefer-template`, `vue/prefer-true-attribute-shorthand`, `vue/prefer-use-template-ref`, `vue/prefer-v-model`, `vue/prop-name-casing`, `vue/quote-props`, `vue/require-component-is`, `vue/require-default-export`, `vue/require-default-prop`, `vue/require-direct-export`, `vue/require-emit-validator`, `vue/require-explicit-emits`, `vue/require-explicit-slots`, `vue/require-expose`, `vue/require-macro-variable-name`, `vue/require-name-property`, `vue/require-prop-comment`, `vue/require-prop-type-constructor`, `vue/require-prop-types`, `vue/require-render-return`, `vue/require-slots-as-functions`, `vue/require-toggle-inside-transition`, `vue/require-typed-object-prop`, `vue/require-typed-ref`, `vue/require-v-for-key`, `vue/require-valid-default-prop`, `vue/restricted-component-names`, `vue/return-in-computed-property`, `vue/return-in-emits-validator`, `vue/singleline-html-element-content-newline`, `vue/slot-name-casing`, `vue/sort-keys`, `vue/space-in-parens`, `vue/space-infix-ops`, `vue/space-unary-ops`, `vue/static-class-names-order`, `vue/template-curly-spacing`, `vue/this-in-template`, `vue/use-v-on-exact`, `vue/v-bind-style`, `vue/v-for-delimiter-style`, `vue/v-if-else-key`, `vue/v-on-event-hyphenation`, `vue/v-on-handler-style`, `vue/v-on-style`, `vue/v-slot-style`, `vue/valid-attribute-name`, `vue/valid-define-emits`, `vue/valid-define-options`, `vue/valid-define-props`, `vue/valid-model-definition`, `vue/valid-next-tick`, `vue/valid-template-root`, `vue/valid-v-bind`, `vue/valid-v-bind-sync`, `vue/valid-v-cloak`, `vue/valid-v-else`, `vue/valid-v-else-if`, `vue/valid-v-for`, `vue/valid-v-html`, `vue/valid-v-if`, `vue/valid-v-is`, `vue/valid-v-memo`, `vue/valid-v-model`, `vue/valid-v-on`, `vue/valid-v-once`, `vue/valid-v-pre`, `vue/valid-v-show`, `vue/valid-v-slot`, `vue/valid-v-text`

Its 38 wrappers of rules of ESLint core and ESLint Stylistic, which run veslint's port of the wrapped rule on the expressions of the template (ESLint Stylistic's when `@stylistic/eslint-plugin` resolves from the current directory, as eslint-plugin-vue chooses, ESLint core's otherwise): `vue/array-bracket-newline`, `vue/array-bracket-spacing`, `vue/array-element-newline`, `vue/arrow-spacing`, `vue/block-spacing`, `vue/brace-style`, `vue/camelcase`, `vue/comma-dangle`, `vue/comma-spacing`, `vue/comma-style`, `vue/dot-location`, `vue/dot-notation`, `vue/eqeqeq`, `vue/func-call-spacing`, `vue/key-spacing`, `vue/keyword-spacing`, `vue/multiline-ternary`, `vue/no-console`, `vue/no-constant-condition`, `vue/no-empty-pattern`, `vue/no-extra-parens`, `vue/no-implicit-coercion`, `vue/no-loss-of-precision`, `vue/no-negated-condition`, `vue/no-restricted-syntax`, `vue/no-sparse-arrays`, `vue/no-useless-concat`, `vue/object-curly-newline`, `vue/object-curly-spacing`, `vue/object-property-newline`, `vue/object-shorthand`, `vue/operator-linebreak`, `vue/prefer-template`, `vue/quote-props`, `vue/space-in-parens`, `vue/space-infix-ops`, `vue/space-unary-ops`, `vue/template-curly-spacing`.

</details>

<details>
<summary><b>eslint-plugin-svelte 3.24.1</b> (the templates of <code>.svelte</code> files): 62 rules</summary>

`svelte/block-lang`, `svelte/button-has-type`, `svelte/comment-directive`, `svelte/derived-has-same-inputs-outputs`, `svelte/first-attribute-linebreak`, `svelte/html-closing-bracket-new-line`, `svelte/html-closing-bracket-spacing`, `svelte/html-quotes`, `svelte/html-self-closing`, `svelte/infinite-reactive-loop`, `svelte/max-attributes-per-line`, `svelte/mustache-spacing`, `svelte/no-add-event-listener`, `svelte/no-at-const-tags`, `svelte/no-at-debug-tags`, `svelte/no-at-html-tags`, `svelte/no-conflicting-module-names`, `svelte/no-dom-manipulating`, `svelte/no-dupe-else-if-blocks`, `svelte/no-dupe-on-directives`, `svelte/no-dupe-use-directives`, `svelte/no-dynamic-slot-name`, `svelte/no-export-load-in-svelte-module-in-kit-pages`, `svelte/no-extra-reactive-curlies`, `svelte/no-goto-without-base`, `svelte/no-ignored-unsubscribe`, `svelte/no-immutable-reactive-statements`, `svelte/no-inline-styles`, `svelte/no-inner-declarations`, `svelte/no-inspect`, `svelte/no-nested-style-tag`, `svelte/no-not-function-handler`, `svelte/no-object-in-text-mustaches`, `svelte/no-raw-special-elements`, `svelte/no-reactive-functions`, `svelte/no-reactive-literals`, `svelte/no-reactive-reassign`, `svelte/no-spaces-around-equal-signs-in-attribute`, `svelte/no-store-async`, `svelte/no-svelte-internal`, `svelte/no-target-blank`, `svelte/no-trailing-spaces`, `svelte/no-unnecessary-state-wrap`, `svelte/no-useless-children-snippet`, `svelte/no-useless-mustaches`, `svelte/prefer-attribute-interpolation`, `svelte/prefer-class-directive`, `svelte/prefer-const`, `svelte/prefer-derived-over-derived-by`, `svelte/prefer-destructured-store-props`, `svelte/prefer-svelte-reactivity`, `svelte/prefer-writable-derived`, `svelte/require-each-key`, `svelte/require-event-dispatcher-types`, `svelte/require-store-callbacks-use-set-param`, `svelte/require-stores-init`, `svelte/shorthand-attribute`, `svelte/shorthand-directive`, `svelte/spaced-html-comment`, `svelte/system`, `svelte/valid-each-key`, `svelte/valid-prop-names-in-kit-pages`

</details>

<details>
<summary><b>@slipher/eslint-plugin 1.1.0</b> (Seyfert bots): 15 rules</summary>

`seyfert/autocomplete-respond`, `seyfert/config-default-export`, `seyfert/context-menu-declare`, `seyfert/declare-description`, `seyfert/decorator-on-command`, `seyfert/decorator-target`, `seyfert/group-exists`, `seyfert/i18n-resolve-with-get`, `seyfert/no-deep-imports`, `seyfert/no-hanging-middleware`, `seyfert/no-method-destructure`, `seyfert/options-use-builders`, `seyfert/prefer-typed-group`, `seyfert/require-declare`, `seyfert/required-options-order`

</details>

<details>
<summary><b>@marcrock22/eslintcf</b> (its own rules): 4 rules</summary>

`marcrock/no-newline-if-body-class-empty`, `marcrock/numeric-separators`, `marcrock/prefer-at`, `marcrock/uppercase-first-class-letter`

</details>

What each version added is in the [changelog](CHANGELOG.md).

### How it is checked

Every rule passes all the cases of its own upstream tests, linted as TypeScript: 29,862 cases of typescript-eslint, 14,092 of ESLint, 14,962 of eslint-plugin-unicorn, 9,528 of @stylistic/eslint-plugin, 3,278 of eslint-plugin-perfectionist, 459 of @slipher/eslint-plugin, 206 of @marcrock22/eslintcf, 10,085 of eslint-plugin-vue and 314 of eslint-plugin-svelte (their JavaScript cases with `lang="ts"`, with what ESLint gives for them). On fixtures of its own, every rule gives exactly what ESLint gives: problems, messages, positions, fixes and suggestions. The rules are also compared with ESLint on real projects (a Discord bot, zod, recharts and the TypeScript compiler).

## VS Code extension

The extension shows the problems of the TypeScript files you open and type, underlined where ESLint would underline them. It offers their fixes and suggestions as quick fixes, adds a comment that disables a rule for a line, and has a fix-all action. A veslint server per workspace folder keeps the project loaded, so the text you type is linted in about 0.1 s. Its commands, settings and limits are in [its README](editors/vscode/README.md).

## Limits

- **TypeScript only.** JavaScript files are not linted, even in a project with `allowJs`, nor the JavaScript scripts of Vue and Svelte files.
- **Vue files:** 254 rules of eslint-plugin-vue so far (the others are skipped with a warning). `<!-- eslint-disable -->` comments in a template work when `vue/comment-directive` is on, as with eslint-plugin-vue's processor. `parserOptions.vueFeatures` is not read (the defaults are used). Two scripts that are not modules (no `import` or `export`) see each other's globals in veslint, where typescript-eslint has the other `.vue` files of the program as the text of the file.
- **Linux x64 and Windows x64.** Other platforms need a build from source, which is not tested there.
- **An `eslint.config.*` needs `bun`** to be read; the resolved configuration (`--print-config`) does not. A cached resolution is reused while the files and modules the configuration read and the environment variables it read stay the same: a configuration that depends on something else (the date, a file it lists but does not read, a new `tsconfig.json` a glob of `parserOptions.project` matches) needs `VESLINT_CONFIG_CACHE=0`.
- **The newest TypeScript syntax** may not be read yet: veslint warns when a file has syntax it does not understand, and some problems of that file may be missing.
- **Plugins:** only the rules listed above. Rules of other plugins are skipped with a warning.

## Building from source

Requirements:

- [V](https://github.com/vlang/v) at commit `841595141fbb` (the release workflow builds it from the vlang/vc commit `45add16eb714`).
- GCC, `make`, `git`, `patch` and `npm`. npm only downloads two pinned binaries: TypeScript 7.1.0-beta and the tree-sitter 0.24.4 CLI.

```sh
make deps            # TypeScript 7, tree-sitter and the patched TypeScript grammar
make build V=<v>     # ./veslint
make test V=<v>      # the tests (JOBS=<n> checks at once; the CPUs by default)
VESLINT_MATRIX=1 make test V=<v>   # also each rule alone on every fixture (before a release)
```

**Windows:** run `pwsh ./build-windows.ps1` with PowerShell 7, Git for Windows, MSYS2's UCRT64 gcc in `PATH` (`pacman -S mingw-w64-ucrt-x86_64-gcc`) and Node.js. It builds V and the dependencies itself; the generated grammar is copied from a Linux checkout of the same commit (`build/tree-sitter-typescript`, which `make` writes).

## Changelog

See [CHANGELOG.md](CHANGELOG.md). Each version is also a [GitHub release](https://github.com/MARCROCK22/veslint/releases) with its binaries and the extension.
