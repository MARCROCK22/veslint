const foo = 1;
const baz = 2;
// Reported.
export { foo };
export const barOne = 1, { barTwo } = { barTwo: 2 };
export function then() {}
export class barClass {}
export { baz as default };
export { default as other } from './other';
export { qux as default } from './other';
export { default } from './other';
export * as default from './other';
export * as bar from './other';
export default baz;
// Not reported.
export const ok = 1;
export { baz as "quux" };
export * from './other';
export type { Kind } from './other';
