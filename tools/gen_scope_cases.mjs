// Generates tests/scope_cases.json for rules/scope_oracle_test.v: for each program of
// tests/scope/ (see below), what ESLint's scope manager holds for it once
// ESLint has finished it (SourceCode#finalize): the real @typescript-eslint/parser and
// @typescript-eslint/scope-manager analyze the program inside the real ESLint Linter, with the
// languageOptions, linterOptions and (through a project on disk) compilerOptions of the case.
// Per scope: its type, block range, upper and variable scope, isStrict and the references it left to
// the upper scope (through); its variables in order, each with
// its definitions (type and start of the name), identifiers and the references that resolved to
// it, in ESLint's order; and its references in order, each with its identifier, read/write/init
// flags, type/value kind and the variable it resolved to. Of the global scope only the variables
// that are not implicit lib variables or that have references are listed; all of them, with their
// flags, are in `global.digest` (SHA-1 of one line per variable). Positions are byte offsets; of
// an identifier only the start is kept, as ESTree's range includes its type annotation. Of the
// global scope, also its implicit variables (an assignment to an undeclared name outside strict
// code) with the start of each definition's name and node.
//
// A case is a file of tests/scope/: `<name>.ts` or `<name>.tsx`, with an optional
// `<name>.json` next to it: {"languageOptions": {…}, "linterOptions": {…}, "compilerOptions": {…}}.
// languageOptions may have ecmaVersion, sourceType, globals and parserOptions (lib, jsxPragma,
// jsxFragmentName, sourceType, ecmaFeatures.globalReturn); with compilerOptions the case is
// parsed with a TypeScript program (a temporary project with that tsconfig), which is where the
// parser takes `lib`, `jsxFactory` and `jsxFragmentFactory` from.
// Dev-time only: run `node tools/gen_scope_cases.mjs` after adding or changing cases; it uses the
// node_modules that tests/eval_spider_byte.sh installs. A case whose files did not change keeps
// what tests/scope_cases.json has for it (`--force` analyzes every case again: needed after
// changing this tool or the versions of ESLint or typescript-eslint).
// `node tools/gen_scope_cases.mjs --globals <name>` prints the lines behind the digest of a case
// instead.
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

const root = path.join(import.meta.dirname, '..');
const nodeModules = path.join(root, 'build/eval/spider-byte/node_modules');
const require = createRequire(nodeModules + '/');
const { Linter } = require('eslint');
const parser = require('@typescript-eslint/parser');
const version = pkg => JSON.parse(fs.readFileSync(path.join(nodeModules, pkg, 'package.json'), 'utf8')).version;

const casesDir = path.join(root, 'tests/scope');
const outputPath = path.join(root, 'tests/scope_cases.json');
const dumpGlobals = process.argv[2] === '--globals' ? process.argv[3] : null;
const force = process.argv.includes('--force');
const generator = `tools/gen_scope_cases.mjs: eslint ${version('eslint')}, @typescript-eslint/parser ${version('@typescript-eslint/parser')}, @typescript-eslint/scope-manager ${version('@typescript-eslint/scope-manager')}, typescript ${version('typescript')}`;
// What the last run wrote, by case, when the same versions wrote it.
const previous = new Map();
if (!force && !dumpGlobals && fs.existsSync(outputPath)) {
  const last = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  if (last.generator === generator) for (const item of last.cases) previous.set(item.name, item);
}

// globalLine is the line of a variable of the global scope in the digest.
function globalLine(variable, references) {
  return [
    variable.name,
    variable.constructor.name === 'ImplicitLibVariable' ? 'lib' : 'variable',
    (variable.isTypeVariable ? 'T' : '') + (variable.isValueVariable ? 'V' : ''),
    variable.writeable === true ? 'writable' : '',
    variable.eslintExplicitGlobal === true ? 'explicit' : '',
    variable.eslintImplicitGlobalSetting ?? '',
    variable.eslintUsed === true ? 'used' : '',
    String(references),
  ].join('\t');
}

function analyze(file) {
  const name = path.basename(file).replace(/\.tsx?$/, '');
  const source = fs.readFileSync(path.join(casesDir, file), 'utf8');
  const sidecar = path.join(casesDir, `${name}.json`);
  const setupText = fs.existsSync(sidecar) ? fs.readFileSync(sidecar, 'utf8') : '{}';
  const key = crypto.createHash('sha1').update(`${file}\n${source}\n${setupText}`).digest('hex');
  if (previous.get(name)?.key === key) return previous.get(name);
  const setup = JSON.parse(setupText);
  const languageOptions = setup.languageOptions ?? {};
  const parserOptions = { ...(languageOptions.parserOptions ?? {}) };
  let cwd = path.join(os.tmpdir(), 'veslint-scope-cases');
  let temporary = null;
  if (setup.compilerOptions) {
    // A project on disk: the parser reads lib, jsxFactory and jsxFragmentFactory from its program.
    temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-scope-'));
    cwd = temporary;
    fs.writeFileSync(path.join(cwd, 'tsconfig.json'), JSON.stringify({ compilerOptions: setup.compilerOptions, include: ['*.ts', '*.tsx'] }));
    fs.writeFileSync(path.join(cwd, file), source);
    parserOptions.project = ['./tsconfig.json'];
    parserOptions.tsconfigRootDir = cwd;
  }
  let result;
  const plugin = {
    rules: {
      dump: {
        create(context) {
          result = { scopeManager: context.sourceCode.scopeManager, services: context.sourceCode.parserServices, languageOptions: context.languageOptions };
          return {};
        },
      },
    },
  };
  const config = {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: { ...languageOptions, parser, parserOptions },
    linterOptions: setup.linterOptions ?? {},
    plugins: { scope: plugin },
    rules: { 'scope/dump': 'error' },
  };
  const linter = new Linter({ configType: 'flat', cwd });
  const messages = linter.verify(source, [config], { filename: path.join(cwd, file) });
  if (temporary) fs.rmSync(temporary, { recursive: true });
  const fatal = messages.filter(message => message.fatal && !/^'.*' has no effect|is not a valid configuration for a global/.test(message.message));
  if (!result || fatal.length > 0) {
    throw new Error(`${file}: ESLint could not analyze it: ${JSON.stringify(messages)}`);
  }
  const { scopeManager } = result;
  // Byte offsets of the UTF-16 offsets ESTree has.
  const bytes = offset => Buffer.byteLength(source.slice(0, offset));
  const scopeIndex = new Map(scopeManager.scopes.map((scope, index) => [scope, index]));
  const referenceId = new Map();
  for (const scope of scopeManager.scopes) for (const reference of scope.references) referenceId.set(reference, referenceId.size);
  const variableIndex = variable => variable.scope.variables.indexOf(variable);
  const globalScope = scopeManager.scopes[0];
  const scopes = scopeManager.scopes.map((scope, index) => ({
    type: scope.type,
    block: scope.block.type,
    start: bytes(scope.block.range[0]),
    end: bytes(scope.block.range[1]),
    upper: scope.upper ? scopeIndex.get(scope.upper) : -1,
    variableScope: scopeIndex.get(scope.variableScope),
    isStrict: scope.isStrict,
    through: scope.through.map(reference => referenceId.get(reference)),
    variables: scope.variables
      .map((variable, position) => ({ variable, position }))
      .filter(({ variable }) => index !== 0 || variable.constructor.name !== 'ImplicitLibVariable' || variable.references.length > 0)
      .map(({ variable, position }) => ({
        name: variable.name,
        index: position,
        defs: variable.defs.map(def => ({
          type: def.type,
          start: bytes(def.name.range[0]),
          node: def.node.type,
          nodeStart: bytes(def.node.range[0]),
          nodeEnd: bytes(def.node.range[1]),
        })),
        identifiers: variable.identifiers.map(identifier => bytes(identifier.range[0])),
        references: variable.references.map(reference => referenceId.get(reference)),
      })),
    references: scope.references.map(reference => ({
      id: referenceId.get(reference),
      name: reference.identifier.name,
      start: bytes(reference.identifier.range[0]),
      flags: (reference.isRead() ? 'R' : '') + (reference.isWrite() ? 'W' : '') + (reference.init ? 'i' : ''),
      kind: (reference.isTypeReference ? 'T' : '') + (reference.isValueReference ? 'V' : ''),
      resolved: reference.resolved ? [scopeIndex.get(reference.resolved.scope), variableIndex(reference.resolved)] : [],
    })),
  }));
  const lines = globalScope.variables.map(variable => globalLine(variable, variable.references.length));
  if (dumpGlobals === name) process.stdout.write(lines.join('\n') + '\n');
  const compilerOptions = result.services.program ? result.services.program.getCompilerOptions() : null;
  // What the case gives veslint: the languageOptions as its resolver reports them (the
  // normalized ecmaVersion, the sourceType, the globals and the parser options the scopes depend
  // on), the linterOptions, and the compiler options as TypeScript holds them.
  const slimParser = {};
  for (const key of ['lib', 'jsxPragma', 'jsxFragmentName', 'sourceType']) {
    if (languageOptions.parserOptions?.[key] !== undefined) slimParser[key] = languageOptions.parserOptions[key];
  }
  if (languageOptions.parserOptions?.ecmaFeatures?.globalReturn !== undefined) {
    slimParser.ecmaFeatures = { globalReturn: languageOptions.parserOptions.ecmaFeatures.globalReturn };
  }
  return {
    name,
    key,
    file,
    source,
    languageOptions: {
      ecmaVersion: result.languageOptions.ecmaVersion,
      sourceType: result.languageOptions.sourceType,
      globals: result.languageOptions.globals ?? {},
      parserOptions: slimParser,
    },
    linterOptions: setup.linterOptions ?? {},
    compilerOptions: compilerOptions
      ? Object.fromEntries(['lib', 'target', 'jsxFactory', 'jsxFragmentFactory'].filter(key => compilerOptions[key] !== undefined).map(key => [key, compilerOptions[key]]))
      : null,
    scopes,
    global: {
      count: globalScope.variables.length,
      digest: crypto.createHash('sha1').update(lines.join('\n')).digest('hex'),
      through: globalScope.through.map(reference => referenceId.get(reference)),
      implicit: globalScope.implicit.variables.map(variable => ({
        name: variable.name,
        defs: variable.defs.map(def => [bytes(def.name.range[0]), bytes(def.node.range[0])]),
      })),
    },
  };
}

const files = fs
  .readdirSync(casesDir)
  .filter(file => /\.tsx?$/.test(file))
  .sort();
const cases = [];
for (const file of files) {
  if (dumpGlobals && path.basename(file).replace(/\.tsx?$/, '') !== dumpGlobals) continue;
  cases.push(analyze(file));
  // One line per case, as each one with compiler options builds a TypeScript program.
  if (!dumpGlobals) process.stderr.write(`${file}\n`);
}
if (!dumpGlobals) {
  const output = { generator, cases };
  fs.writeFileSync(outputPath, JSON.stringify(output) + '\n');
  const references = cases.reduce((sum, item) => sum + item.scopes.reduce((count, scope) => count + scope.references.length, 0), 0);
  console.log(`${cases.length} cases, ${references} references`);
}
