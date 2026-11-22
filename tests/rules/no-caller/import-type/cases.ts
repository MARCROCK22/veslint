// The names after `import('…')` in a type are the qualifier of a TSImportType (an Identifier or a
// TSQualifiedName), no member access: no-caller reports none of them, only `arguments.callee`.
export const arguments_ = {};
export type A = typeof import('./cases').arguments.callee;
export type B = typeof import('./cases').arguments.caller.x;
export type C = import('./cases').arguments.caller;
export function f(): void {
  console.log(arguments.callee);
}
export function g(): typeof arguments.callee {
  return 0 as never;
}
