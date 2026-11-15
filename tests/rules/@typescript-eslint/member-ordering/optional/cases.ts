class A {
  b = 1;
  a = 2;
  c? = 3;
  d? = 4;
}
class B {
  a? = 1;
  b = 2;
}
class C {
  b = 1;
  a? = 2;
  c = 3;
}
interface I {
  a?: string;
  m(): void;
  b: string;
}
interface J {
  m?(): void;
  a?: string;
  b: string;
  c: string;
}
type T = {
  b: string;
  a?: string;
};
