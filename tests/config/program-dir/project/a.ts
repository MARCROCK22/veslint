// `from: "file"` type specifiers are relative to the current directory of ESLint's program. Here
// the parser gets the types with `parserOptions.project`: the directory is the one ESLint runs in.
import type { Shared } from '../shared';
import type { ByProjectDirectory, ByWorkingDirectory } from './types';
declare const byWorkingDirectory: ByWorkingDirectory;
declare const byProjectDirectory: ByProjectDirectory;
declare const shared: Shared;
export function f() {
  byWorkingDirectory;
  byProjectDirectory;
  shared;
}
