// eslint_server.mjs ESLINT_PACKAGE CONFIG: ESLint kept alive between lints, as the VS Code ESLint
// extension keeps it: one `ESLint` instance (typescript-eslint keeps its project service in it) that
// lints the text of each request with lintText. A request is a JSON line {"file", "text"}; the answer
// a JSON line {"problems"}. Used by tests/bench/server.py.
import { createRequire } from 'node:module';
import readline from 'node:readline';

const [eslintPackage, config] = process.argv.slice(2);
const { ESLint } = createRequire(eslintPackage)('eslint');
const eslint = new ESLint({ overrideConfigFile: config });
const lines = readline.createInterface({ input: process.stdin });
for await (const line of lines) {
  const { file, text } = JSON.parse(line);
  const [result] = await eslint.lintText(text, { filePath: file });
  process.stdout.write(JSON.stringify({ problems: result.messages.length }) + '\n');
}
