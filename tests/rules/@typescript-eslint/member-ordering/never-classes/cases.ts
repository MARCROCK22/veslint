class A {
  m() {}
  f = 1;
}
const B = class {
  f = 1;
  m() {}
};
type T = {
  f: string;
  m(): void;
};
interface I {
  new (): I;
  m(): void;
  f: string;
}
