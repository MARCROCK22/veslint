# Changelog

Each version is a release on GitHub with the veslint binaries (Linux x64, Windows x64) and the VS Code extension. The section of a version is the text of its release.

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
