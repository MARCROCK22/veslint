declare function getArray(): Promise<number[]>;
declare function getObject(): Promise<{ foo: number; bar: number }>;

async function f() {
  // Fixed.
  const first = (await getArray())[0];
  const second = (await getArray())[1];
  const foo = (await getObject()).foo;
  const minus = (await getArray())[-0];
  // Reported, not fixed.
  const third = (await getArray())[2];
  const other = (await getObject()).bar;
  const typed: number = (await getArray())[0];
  const comment = (await getArray() /* c */)[0];
  const optional = (await getObject())?.foo;
  (await getObject()).foo = 1;
  const nested = { a: (await getObject()).foo };
  const object = (await ({ 0: 1 } as unknown as Promise<number[]>))[0];
  // Not reported.
  const value = await getObject();
  return [first, second, foo, minus, third, other, typed, comment, optional, nested, object, value];
}
export { f };
