declare const x: any;
type Foo = any;
const a1 = <Foo>(
  x
);
const a2 = {
  a: 1,
} as Foo;
const a3 = <Foo>{
  b: 2,
};
export {};
