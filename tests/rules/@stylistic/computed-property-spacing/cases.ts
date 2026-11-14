declare const obj: Record<string, any>;
declare const k: string;
declare const n: number;

obj[k];
obj[ k];
obj[k ];
obj[ k ];
obj[  k  ];
obj?.[ k ];
obj[ (k) ];
obj[(k)];
obj[/* c */ k /* d */];
obj[ /* c */k/* d */ ];
obj[
  k
];
obj[ k
];
obj[
  k ];
obj[ obj[ k ] ];
obj[obj[k]];
obj[ `${k}` ];
obj[ 'key' ][ n ];
obj.k;
obj[ k ] = 1;
const o1 = { [ k ]: 1, [k]: 2, [ n ](): void {}, get [ 'g' ](): number { return 1; } };
const { [ k ]: v1, [k]: v2 } = obj;
class C1 {
  [ k ] = 1;
  [n]: number = 2;
  static [ 'a' ]: number;
  [ 'm' ](): void {}
  get [ 'g' ](): number { return 1; }
  set [ 'g' ](value: number) { void value; }
  accessor [ 'acc' ] = 1;
  static accessor ['acc2'] = 2;
}
abstract class C2 {
  abstract [ 'm' ](): void;
  abstract [ 'p' ]: number;
}
interface I1 {
  [ 'a' ]: number;
  [ 'b' ](): void;
}
type T1 = I1[ 'a' ];
type T2 = I1['a'];
type T3 = string[][ number ];
type T4 = [ 1, 2 ][ 0 ];
type T5 = { [ K in 'a' ]: K };
type T6 = { [ key: string ]: number };
enum E1 { 'A' = 1 }
void o1; void v1; void v2; void C1; void C2; void E1;
export type { T1, T2, T3, T4, T5, T6 };
