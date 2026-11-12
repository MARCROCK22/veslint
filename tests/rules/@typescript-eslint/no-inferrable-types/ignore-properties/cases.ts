const a: number = 1;
function f(b: string = '', c?: boolean = true) {}
const g = (d: number = 1) => d;
class C {
  constructor(private e: number = 1) {}
  f: number = 1;
  g!: string = '';
  accessor h: boolean = true;
  m(i: number = 1) {}
}
export {};
