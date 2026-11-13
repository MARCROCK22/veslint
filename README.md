<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/veslint-logo-dark.svg">
    <img alt="veslint" src="assets/veslint-logo.svg" height="72">
  </picture>
</p>
<p align="center">A TypeScript linter in V that talks to TypeScript 7 (<code>tsc --api</code>) directly</p>

# veslint

veslint lints TypeScript with ESLint's rules, without ESLint. It parses with tree-sitter, gets the types from the native TypeScript 7 compiler, and needs no JavaScript runtime to lint.

- **Same results as ESLint.** The rules of ESLint, typescript-eslint, eslint-plugin-unicorn and @slipher/eslint-plugin are ported to V. They report the same problems, with the same messages, positions, fixes and suggestions.
- **Your ESLint configuration.** veslint reads `eslint.config.*`, the directive comments (`// eslint-disable-next-line`, `/* eslint rule: … */`, `/* global */`) and rule options. A rule it does not have yet is skipped with a warning.
- **Fast.** On a Discord bot of 65 TypeScript files, the 105 typescript-eslint rules in one run take 3.2 s with veslint and 11.7 s with ESLint (one core of an old i3). In the editor, a file is linted again about 0.1 s after you type.
- **An editor extension** for VS Code shows the problems as you type, with quick fixes.

## Install

### VS Code

Install **veslint** from the Visual Studio Marketplace (`MARCROCK22.veslint`), then run **veslint: Update veslint** from the command palette. It downloads veslint for your platform and keeps it up to date: once a day at most it asks whether to install a newer release. See [the extension's README](editors/vscode/README.md) for its settings.

### Command line

Download `veslint-<version>-linux-x64.tar.gz` or `veslint-<version>-win32-x64.zip` from the [releases](https://github.com/MARCROCK22/veslint/releases) and unpack it anywhere. It contains the `veslint` binary and the TypeScript 7 compiler it uses; keep them together. `veslint --version` prints the version.

veslint runs on **Linux x64** and **Windows x64**. On other platforms, [build it from source](#building-from-source).

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
veslint <file.ts | directory>... [--config <file>] [--rule <rule>] [--project <tsconfig.json>] [--fix] [--fixes | --summary]
```

| Option | What it does |
|---|---|
| `<directory>` | Lints the `.ts`, `.mts`, `.cts` and `.tsx` files under it, as `eslint .` does: `node_modules`, `.git` and what the configuration ignores are left out. |
| `<file.ts>` | Lints that file. JavaScript files are not linted: veslint only reads TypeScript. |
| `--config <file>` | The configuration (see below). Without it and without `--rule`, a directory is linted with the closest `eslint.config.*`. |
| `--rule <rule>` | Lints with one rule and its default options, named as in ESLint: `no-var`, `@typescript-eslint/await-thenable`. |
| `--project <tsconfig.json>` | The tsconfig to use. Without it, the one the configuration names in `parserOptions.project`, or the closest `tsconfig.json`. |
| `--fix` | Applies the fixes and rewrites the files, like `eslint --fix`, and prints the problems that remain. |
| `--fixes` | Prints each problem with its fix, its suggestions and where it ends. |
| `--summary` | Instead of a line per problem, a table of the rules that reported problems: how many, errors, warnings and files. |
| `--print-config` | Prints the configuration resolved for the files, a JSON that `--config` reads without running JavaScript. |
| `--server` | A process for editors that stays alive between lints (the VS Code extension uses it). |
| `--version` | Prints the version. |

With files and neither `--config` nor `--rule`, veslint prints the type TypeScript infers for each declared name, a mode for debugging.

The exit code is 0 when there are no problems, 1 when there are (warnings do not count, as in ESLint) or veslint failed, and 2 for a usage error.

Environment variables: `VESLINT_TIMEOUT_MS` (how long to wait for each answer of the TypeScript compiler, 30000 by default) and `VESLINT_CPUS` (how many CPUs veslint and the compiler use: 2 by default, which is fastest; 0 for all).

## Configuration

`--config` takes one of these:

- **An ESLint configuration** (`eslint.config.js`, `.mjs`, `.cjs`, `.ts`, `.mts`, `.cts`). It is JavaScript, so veslint asks your project's own ESLint to resolve it, which needs [`bun`](https://bun.sh) and ESLint installed in the project. `files`, `ignores`, rules per folder, `linterOptions` and `languageOptions` work as in ESLint.
- **The resolved configuration** that `--print-config` prints. It needs neither `bun` nor ESLint: save it once and lint with it.
- **A JSON with a `rules` section**, like the output of `eslint --print-config`:

  ```json
  {"rules": {"@typescript-eslint/no-floating-promises": "error", "eqeqeq": ["warn", "smart"]}}
  ```

Rule options are validated like ESLint validates them, with the same error messages. Rules veslint does not have are skipped with a warning that names them.

Directive comments work as in ESLint 10: `eslint-disable`, `eslint-enable`, `eslint-disable-line` and `eslint-disable-next-line` (with a `-- reason` or not), `/* eslint rule: value */`, `/* global name */` and `/* exported name */`. Unused `eslint-disable` comments are reported, with a fix that removes them.

## Rules

veslint has **266 rules**, each with all its options, fixes and suggestions:

<details>
<summary><b>ESLint 10.6.0</b>: 134 rules</summary>

`arrow-body-style`, `block-scoped-var`, `consistent-this`, `constructor-super`, `curly`, `default-case-last`, `dot-notation`, `eqeqeq`, `for-direction`, `func-name-matching`, `func-names`, `getter-return`, `grouped-accessor-pairs`, `logical-assignment-operators`, `no-async-promise-executor`, `no-caller`, `no-case-declarations`, `no-class-assign`, `no-compare-neg-zero`, `no-cond-assign`, `no-const-assign`, `no-constant-binary-expression`, `no-constant-condition`, `no-constructor-return`, `no-control-regex`, `no-debugger`, `no-delete-var`, `no-div-regex`, `no-dupe-args`, `no-dupe-else-if`, `no-dupe-keys`, `no-duplicate-case`, `no-else-return`, `no-empty`, `no-empty-character-class`, `no-empty-pattern`, `no-empty-static-block`, `no-eq-null`, `no-ex-assign`, `no-extend-native`, `no-extra-bind`, `no-extra-boolean-cast`, `no-extra-label`, `no-fallthrough`, `no-func-assign`, `no-global-assign`, `no-implicit-coercion`, `no-implicit-globals`, `no-implied-eval`, `no-import-assign`, `no-inner-declarations`, `no-invalid-regexp`, `no-invalid-this`, `no-irregular-whitespace`, `no-iterator`, `no-label-var`, `no-labels`, `no-lone-blocks`, `no-loop-func`, `no-loss-of-precision`, `no-misleading-character-class`, `no-multi-str`, `no-new`, `no-new-func`, `no-new-native-nonconstructor`, `no-new-wrappers`, `no-nonoctal-decimal-escape`, `no-obj-calls`, `no-object-constructor`, `no-octal`, `no-octal-escape`, `no-promise-executor-return`, `no-proto`, `no-prototype-builtins`, `no-regex-spaces`, `no-restricted-exports`, `no-restricted-globals`, `no-restricted-imports`, `no-restricted-properties`, `no-restricted-syntax`, `no-return-assign`, `no-script-url`, `no-self-assign`, `no-self-compare`, `no-sequences`, `no-setter-return`, `no-shadow-restricted-names`, `no-sparse-arrays`, `no-template-curly-in-string`, `no-this-before-super`, `no-unassigned-vars`, `no-unexpected-multiline`, `no-unmodified-loop-condition`, `no-unreachable`, `no-unreachable-loop`, `no-unsafe-finally`, `no-unsafe-negation`, `no-unsafe-optional-chaining`, `no-unused-labels`, `no-useless-assignment`, `no-useless-backreference`, `no-useless-call`, `no-useless-catch`, `no-useless-computed-key`, `no-useless-concat`, `no-useless-escape`, `no-useless-rename`, `no-useless-return`, `no-var`, `no-warning-comments`, `no-with`, `object-shorthand`, `operator-assignment`, `prefer-arrow-callback`, `prefer-const`, `prefer-exponentiation-operator`, `prefer-numeric-literals`, `prefer-object-has-own`, `prefer-object-spread`, `prefer-regex-literals`, `prefer-rest-params`, `prefer-spread`, `prefer-template`, `preserve-caught-error`, `radix`, `require-yield`, `sort-vars`, `strict`, `symbol-description`, `unicode-bom`, `use-isnan`, `valid-typeof`, `vars-on-top`, `yoda`

</details>

<details>
<summary><b>typescript-eslint 8.62.0</b>: 105 rules (61 of them use types)</summary>

`@typescript-eslint/adjacent-overload-signatures`, `@typescript-eslint/array-type`, `@typescript-eslint/await-thenable`, `@typescript-eslint/class-literal-property-style`, `@typescript-eslint/consistent-generic-constructors`, `@typescript-eslint/consistent-indexed-object-style`, `@typescript-eslint/consistent-return`, `@typescript-eslint/consistent-type-assertions`, `@typescript-eslint/consistent-type-definitions`, `@typescript-eslint/consistent-type-exports`, `@typescript-eslint/consistent-type-imports`, `@typescript-eslint/dot-notation`, `@typescript-eslint/naming-convention`, `@typescript-eslint/no-array-constructor`, `@typescript-eslint/no-array-delete`, `@typescript-eslint/no-base-to-string`, `@typescript-eslint/no-confusing-non-null-assertion`, `@typescript-eslint/no-confusing-void-expression`, `@typescript-eslint/no-deprecated`, `@typescript-eslint/no-dupe-class-members`, `@typescript-eslint/no-duplicate-enum-values`, `@typescript-eslint/no-duplicate-type-constituents`, `@typescript-eslint/no-dynamic-delete`, `@typescript-eslint/no-empty-function`, `@typescript-eslint/no-extra-non-null-assertion`, `@typescript-eslint/no-extraneous-class`, `@typescript-eslint/no-floating-promises`, `@typescript-eslint/no-for-in-array`, `@typescript-eslint/no-implied-eval`, `@typescript-eslint/no-import-type-side-effects`, `@typescript-eslint/no-inferrable-types`, `@typescript-eslint/no-invalid-void-type`, `@typescript-eslint/no-meaningless-void-operator`, `@typescript-eslint/no-misused-new`, `@typescript-eslint/no-misused-promises`, `@typescript-eslint/no-misused-spread`, `@typescript-eslint/no-mixed-enums`, `@typescript-eslint/no-namespace`, `@typescript-eslint/no-non-null-asserted-nullish-coalescing`, `@typescript-eslint/no-non-null-asserted-optional-chain`, `@typescript-eslint/no-redundant-type-constituents`, `@typescript-eslint/no-require-imports`, `@typescript-eslint/no-shadow`, `@typescript-eslint/no-this-alias`, `@typescript-eslint/no-unnecessary-boolean-literal-compare`, `@typescript-eslint/no-unnecessary-condition`, `@typescript-eslint/no-unnecessary-parameter-property-assignment`, `@typescript-eslint/no-unnecessary-qualifier`, `@typescript-eslint/no-unnecessary-template-expression`, `@typescript-eslint/no-unnecessary-type-arguments`, `@typescript-eslint/no-unnecessary-type-assertion`, `@typescript-eslint/no-unnecessary-type-constraint`, `@typescript-eslint/no-unnecessary-type-conversion`, `@typescript-eslint/no-unnecessary-type-parameters`, `@typescript-eslint/no-unsafe-argument`, `@typescript-eslint/no-unsafe-assignment`, `@typescript-eslint/no-unsafe-call`, `@typescript-eslint/no-unsafe-declaration-merging`, `@typescript-eslint/no-unsafe-enum-comparison`, `@typescript-eslint/no-unsafe-function-type`, `@typescript-eslint/no-unsafe-member-access`, `@typescript-eslint/no-unsafe-return`, `@typescript-eslint/no-unsafe-type-assertion`, `@typescript-eslint/no-unsafe-unary-minus`, `@typescript-eslint/no-unused-expressions`, `@typescript-eslint/no-unused-private-class-members`, `@typescript-eslint/no-unused-vars`, `@typescript-eslint/no-use-before-define`, `@typescript-eslint/no-useless-constructor`, `@typescript-eslint/no-useless-default-assignment`, `@typescript-eslint/no-useless-empty-export`, `@typescript-eslint/no-wrapper-object-types`, `@typescript-eslint/non-nullable-type-assertion-style`, `@typescript-eslint/only-throw-error`, `@typescript-eslint/prefer-as-const`, `@typescript-eslint/prefer-destructuring`, `@typescript-eslint/prefer-enum-initializers`, `@typescript-eslint/prefer-find`, `@typescript-eslint/prefer-for-of`, `@typescript-eslint/prefer-function-type`, `@typescript-eslint/prefer-includes`, `@typescript-eslint/prefer-namespace-keyword`, `@typescript-eslint/prefer-nullish-coalescing`, `@typescript-eslint/prefer-optional-chain`, `@typescript-eslint/prefer-promise-reject-errors`, `@typescript-eslint/prefer-readonly`, `@typescript-eslint/prefer-readonly-parameter-types`, `@typescript-eslint/prefer-reduce-type-parameter`, `@typescript-eslint/prefer-regexp-exec`, `@typescript-eslint/prefer-return-this-type`, `@typescript-eslint/prefer-string-starts-ends-with`, `@typescript-eslint/promise-function-async`, `@typescript-eslint/related-getter-setter-pairs`, `@typescript-eslint/require-array-sort-compare`, `@typescript-eslint/require-await`, `@typescript-eslint/restrict-plus-operands`, `@typescript-eslint/restrict-template-expressions`, `@typescript-eslint/return-await`, `@typescript-eslint/strict-boolean-expressions`, `@typescript-eslint/strict-void-return`, `@typescript-eslint/switch-exhaustiveness-check`, `@typescript-eslint/triple-slash-reference`, `@typescript-eslint/unbound-method`, `@typescript-eslint/unified-signatures`, `@typescript-eslint/use-unknown-in-catch-callback-variable`

</details>

<details>
<summary><b>eslint-plugin-unicorn 64.0.0</b>: 12 rules</summary>

`unicorn/no-lonely-if`, `unicorn/no-negated-condition`, `unicorn/no-negation-in-equality-check`, `unicorn/no-nested-ternary`, `unicorn/no-typeof-undefined`, `unicorn/no-useless-switch-case`, `unicorn/prefer-logical-operator-over-ternary`, `unicorn/prefer-simple-condition-first`, `unicorn/prefer-switch`, `unicorn/prefer-ternary`, `unicorn/switch-case-braces`, `unicorn/switch-case-break-position`

</details>

<details>
<summary><b>@slipher/eslint-plugin 1.1.0</b> (Seyfert bots): 15 rules</summary>

`seyfert/autocomplete-respond`, `seyfert/config-default-export`, `seyfert/context-menu-declare`, `seyfert/declare-description`, `seyfert/decorator-on-command`, `seyfert/decorator-target`, `seyfert/group-exists`, `seyfert/i18n-resolve-with-get`, `seyfert/no-deep-imports`, `seyfert/no-hanging-middleware`, `seyfert/no-method-destructure`, `seyfert/options-use-builders`, `seyfert/prefer-typed-group`, `seyfert/require-declare`, `seyfert/required-options-order`

</details>

What each version added is in the [changelog](CHANGELOG.md).

### How it is checked

Every rule passes all the cases of its own upstream tests, linted as TypeScript: 26,823 cases of typescript-eslint, 13,198 of ESLint and 470 of @slipher/eslint-plugin, plus the tests of eslint-plugin-unicorn. On fixtures of its own, every rule gives exactly what ESLint gives: problems, messages, positions, fixes and suggestions. The rules are also compared with ESLint on real projects (a Discord bot, zod, recharts and the TypeScript compiler).

## VS Code extension

The extension shows the problems of the TypeScript files you open and type, underlined where ESLint would underline them. It offers their fixes and suggestions as quick fixes, adds a comment that disables a rule for a line, and has a fix-all action. A veslint server per workspace folder keeps the project loaded, so the text you type is linted in about 0.1 s. Its commands, settings and limits are in [its README](editors/vscode/README.md).

## Limits

- **TypeScript only.** JavaScript files are not linted, even in a project with `allowJs`.
- **Linux x64 and Windows x64.** Other platforms need a build from source, which is not tested there.
- **An `eslint.config.*` needs `bun`** to be read; the resolved configuration (`--print-config`) does not.
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
```

**Windows:** run `pwsh ./build-windows.ps1` with PowerShell 7, Git for Windows, MSYS2's UCRT64 gcc in `PATH` (`pacman -S mingw-w64-ucrt-x86_64-gcc`) and Node.js. It builds V and the dependencies itself; the generated grammar is copied from a Linux checkout of the same commit (`build/tree-sitter-typescript`, which `make` writes).

## Changelog

See [CHANGELOG.md](CHANGELOG.md). Each version is also a [GitHub release](https://github.com/MARCROCK22/veslint/releases) with its binaries and the extension.
