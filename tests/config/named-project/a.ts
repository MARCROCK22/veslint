// The program of this folder is the tsconfig `parserOptions.project` names (tsconfig.lint.json,
// strict), not the closest one (tsconfig.json, not strict): with it, `maybe` may be null.
declare const maybe: string | null;
export function fallback(): string {
  return maybe ?? '';
}
export function unchecked(): boolean {
  return maybe !== null;
}
