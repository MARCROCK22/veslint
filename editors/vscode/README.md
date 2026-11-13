<p align="center"><img alt="veslint" src="images/icon.png" width="96"></p>

# veslint for VS Code

Shows in the editor what veslint reports: 134 rules of ESLint core, 105 rules of typescript-eslint (its 61 type-aware rules, which get their types from the TypeScript 7 compiler, and 44 that need no types), 12 rules of eslint-plugin-unicorn and the 15 `seyfert/*` rules of @slipher/eslint-plugin, for Seyfert bots. The full list is in [veslint's README](https://github.com/MARCROCK22/veslint#rules). What each version brings is in the [changelog](https://github.com/MARCROCK22/veslint/blob/main/CHANGELOG.md).

- **Problems** of the TypeScript files (`.ts`, `.mts`, `.cts`, `.tsx`) you open, save and type, in the editor and in the Problems panel, with a link to the documentation of each rule.
- **A server per workspace folder:** `veslint --server` keeps the TypeScript compiler and the project between lints, so a lint after a save or a change takes about a tenth of a run of the command line on a file of a small project: 55 ms instead of 0.54 s on one core of a Ryzen 7 5800XT, and about 115 ms instead of 1.15 s on one core of an i3-4150T from 2014. veslint keeps itself and the compiler on two CPUs, where those lints are fastest: on all four CPUs of that i3 they took about twice as long (`VESLINT_CPUS` changes it). The text you have not saved is linted, and the files linted after it see that text too, until it is saved, reverted or closed. A lint does not wait for the answer to the one before it: the server gives up a lint that a newer change of the file made useless. The server is told which TypeScript files changed on disk, and reads everything again when a `tsconfig.json` or a `package.json` changes. A server that fails is shown as the error of that lint, and the next lint starts another. A veslint without the server mode still works: each lint runs it again, and only saved text is linted.
- **Quick fixes:** the fix of a problem, its suggestions, and a comment that disables the rule for that line.
- **Configuration resolved once:** an `eslint.config.*` is JavaScript, and asking the project's ESLint for it takes more than the lint itself (about 0.7 s on one core for a file of Spider-Byte). The extension asks once per file, for all the open files that need it in one call, keeps the result (what `veslint --print-config` prints) and gives veslint that copy until a configuration file changes. `veslint: Reload the ESLint Configuration` asks again, for a change the extension cannot see (a module the configuration imports, a plugin updated).
- **Fix all:** the command `veslint: Fix All Problems That Have a Fix`, also as the code action `source.fixAll.veslint` (for `editor.codeActionsOnSave`). It applies the fixes that do not overlap, once; run it again after the next lint for the ones that were waiting, or use `veslint --fix` on the command line, which repeats up to ten times.

## Getting veslint

- **Install the extension** from the Visual Studio Marketplace (search for veslint in the Extensions view), or a `veslint-<version>.vsix` of the [releases](https://github.com/MARCROCK22/veslint/releases) with `Extensions: Install from VSIX...`.
- **Get the binary** with `veslint: Update veslint` (Linux x64 and Windows x64): it downloads the latest release from GitHub, with the TypeScript 7 compiler it runs, into the extension's storage, and uses it from then on. When the extension cannot run veslint, it offers to download it.
- **Updates:** once a day at most, the extension looks for a newer release and asks whether to install it: `Update`, `Release Notes` (its page on GitHub, with the summary of the version) or `Skip This Version`. It is never installed without asking; `veslint.checkForUpdates` turns the check off, and `veslint: Update veslint` looks for one at any time.
- **Your own binary:** set `veslint.path` to it (one built from this repository with `make build`, or in your `PATH`). Then the downloaded one is not used. It needs the TypeScript 7 compiler in the `node_modules` next to the binary, as the release packages have it.

## Requirements

- A configuration: an `eslint.config.*` file at the root of the workspace folder (veslint asks the project's own ESLint for it through `bun`), or the file `veslint.config` names: the JSON `veslint --print-config` prints, or a JSON with a `rules` section.

## Settings

| Setting | Default | What it is |
|---|---|---|
| `veslint.enable` | `true` | Lint TypeScript files. |
| `veslint.path` | (not set) | The binary: a name in `PATH`, an absolute path, or a path relative to the workspace folder. Not set: the one `veslint: Update veslint` installed, or else `veslint` in `PATH`. |
| `veslint.config` | (empty) | The configuration file, relative to the workspace folder. Empty: the `eslint.config.*` at its root. |
| `veslint.project` | (empty) | The `tsconfig.json` to use. Empty: the closest one to each file. |
| `veslint.run` | `onType` | `onType` lints a file when it is opened, saved, and as you type (after `veslint.typingDelay`); `onSave`, when it is opened and saved; `manual`, only with the commands. |
| `veslint.typingDelay` | `0` | Milliseconds that typing must pause before a file is linted with `onType`. `0` lints after every change: a lint that the next change makes useless is skipped if it has not started, and given up by the server if it has; the problems of a text that changed while it was linted are not shown. A larger value lints less often while you type, which saves CPU on large files. |
| `veslint.severity` | `warning` | How the problems of the rules are shown. |
| `veslint.timeout` | `120000` | Milliseconds after which a lint is stopped (with its server: the next lint starts another). |
| `veslint.checkForUpdates` | `true` | Look for a newer veslint release once a day at most, and ask whether to install it. |

## Limits

- **The fixes of a lint are offered until the text changes;** the next lint brings them back.
- **On a large project most of the time is the rules:** on one core, a lint of a file of 5,000 lines of the TypeScript compiler takes about 1.1 s through the server after a save or a change on a Ryzen 7 5800XT (2.0 s with a new veslint each time), and 2.6 s on an i3-4150T (4.0 s). Lints go one at a time.
- **The server reads a file again only when it is told:** the extension tells it what VS Code sees change on disk. A change it does not see (a file outside the workspace) is read after the next `tsconfig.json` or `package.json` change, or after a restart of the extension.
- **A file is linted when it is opened, saved or edited,** not when a file it imports changes: `veslint: Lint All Open Files` lints them all again.
- **Each server keeps the TypeScript compiler of its folder in memory** while VS Code is open, as the TypeScript language service does.
- **A resolved configuration is renewed when an `eslint.config.*` file changes** (or with the reload command), not when something it imports changes.
- **One severity for every rule.** veslint's output does not tell `error` from `warn`, so the problems of the rules are shown with `veslint.severity`.
- **A problem is underlined over ESLint's range,** from where it starts to where it ends (veslint 0.12.0 and later); with an older veslint, whose output has only where a problem starts, from there to the end of the word.
- **After an update, reload the window** (`Developer: Reload Window`): VS Code keeps the settings of the version it loaded first until then (in the Settings editor, `veslint.run` may still show `onSave` as its default). The extension lints while typing anyway, unless `veslint.run` is set.
- JavaScript files are not linted: veslint only reads TypeScript.

## Development

```sh
npm test    # the parser, the runner and the server client (with ../../veslint), and the extension against a stub of the editor
vsce package --no-dependencies --skip-license -o ../../build/    # builds build/veslint-<version>.vsix
```

The extension is plain JavaScript without dependencies, so there is nothing to compile or bundle.
