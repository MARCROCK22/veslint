export {};
declare const obj: { x: number };
export function f(): void {
  // Outside an async function, TypeScript reads `await` as a tag: it is not checked.
  // @ts-expect-error
  void await `${obj}`;
}
export async function g(): Promise<void> {
  void await `${obj}`;
}
// What follows belongs to the same expression: `await (obj).x` is `(await(obj)).x`.
declare const list: Array<{ x: number }>;
export function chains(): void {
  // @ts-expect-error
  void `${await (obj).x} ${await [0].x} ${await `${obj}`.length}`;
  // @ts-expect-error
  void `${await (list)[0]} ${await -obj}`;
}
export async function asyncChains(): Promise<void> {
  void `${await (obj).x} ${await (list)[0]} ${await [obj].length} ${await `${obj}`.length}`;
}
