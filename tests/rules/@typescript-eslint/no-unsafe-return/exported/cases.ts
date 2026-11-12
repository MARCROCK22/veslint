// no-unsafe-return in exported functions and decorated methods: in TypeScript, `export` and the
// decorators are part of the function node, which starts earlier than in tree-sitter.
declare const anyValue: any;
declare function deco(...args: unknown[]): any;
export function exported() { return anyValue; }
export function exportedUnknown(): unknown { return anyValue; }
export function* generatorFn() { return anyValue; }
export default function (): Set<string> { return new Set<any>(); }
export class WithDecorator {
  @deco method(): Set<string> { return new Set<any>(); }
  @deco static other() { return anyValue; }
}
export const arrow = () => anyValue;
