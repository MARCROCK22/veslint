// eslint-plugin-svelte's getTypeScript (utils/ts-utils, for svelte/require-event-prefix) loads
// `typescript` from the current directory (`createRequire(cwd + '/__placeholder__.js')`). Here
// that is veslint's root, whose `typescript` is TypeScript 7.1 (tsgo, a different JavaScript API:
// no `SymbolFlags`), so the rule throws. A Svelte project has there the TypeScript its
// typescript-eslint uses: imported by the ESLint configurations of tests/rules, this makes that
// request load TypeScript 6.0.3 of build/eval/spider-byte, the one of the program.
import Module from 'node:module';
import path from 'node:path';

const typescript = path.resolve(import.meta.dirname, '../../../build/eval/spider-byte/node_modules/typescript/lib/typescript.js');
const resolve = Module._resolveFilename;
Module._resolveFilename = function (request, parent, ...rest) {
  if (request === 'typescript' && parent?.filename?.endsWith('__placeholder__.js')) {
    return typescript;
  }
  return resolve.call(this, request, parent, ...rest);
};
