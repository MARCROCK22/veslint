// A global exported by name keeps its exported name: `export { Number.parseFloat as parseFloat }`.
// (ESLint with typescript-eslint's no-use-before-define crashes on this file: tests/rules/cross.sh.)
export { parseFloat };
