declare const s: string;
declare const maybe: string | undefined;
declare const obj: { s: string; nested: { s: string } };
declare const list: number[];
declare const one: 1;
declare const str: 'a' | 'b';
declare function take(x: string | undefined): void;
declare function takeString(x: string): void;
let target: string;

// TSNonNullExpression: the last `!` goes.
const n1 = s!;
const n2 = s!.length;
const n3 = obj.s!;
const n4 = obj!.s;
const n5 = (s)!;
const n6 = s /* c */ !;
const n7 = s!!;
const n8 = obj!.nested!.s!;
target! = 'x';
take(maybe!);
const n9: string | undefined = maybe!;
const n10 = (obj.nested)!.s!
const n11 = [s!, obj.s!];
const n12 = s! + s!;

// TSAsExpression: from the end of the token before `as` to the end of the assertion.
const a1 = s as string;
const a2 = (s) as string;
const a3 = s /* c */ as string;
const a4 = s as /* c */ string /* d */;
const a5 = (s as string).length;
const a6 = s as string as string;
const a7 = obj.s as (string);
const a8 = s as
  string;
const a9 = s /* one */ /* two */ as string;
const a10 = { a: 1 } as { a: number };
const a11 = () => ({ a: 1 }) as { a: number };
const a12 = [s as string, s as string];
const a13 = `${s as string}`;
const a14 = (s as string) + (s as string);

// TSTypeAssertion: the angle brackets and what is between them go.
const t1 = <string>s;
const t2 = <string>(s);
const t3 = < /* a */ string /* b */ > s;
const t4 = <(string)>s;
const t5 = <Array<number>>list;
const t6 = () => <{ a: number }>{ a: 1 };
const t7 = () => (<{ a: number }>{ a: 1 });
const t8 = () => <{ a: number }>({ a: 1 });
<{ a: number }>{ a: 1 };
(<{ a: number }>{ a: 1 });
<{ a: number }>({ a: 1 });
const t9 = <{ a: number }>{ a: 1 };
const t10 = () => <string>s;
const t11 = () => { <{ a: number }>{ a: 1 }; };
const t12 = (<string>s).length;
const t13 = <string><string>s;
const t14 = () => <{ a: number }> /* c */ { a: 1 };

// contextuallyUnnecessary
takeString(str as string);
const c1: string = str as string;
const c2: number = <number>one;
takeString(<string>str);

// Double assertions: the original expression takes the place of the whole.
const d1 = s as unknown as string;
const d2 = (s as unknown) as string;
const d3 = <string>(<unknown>s);
const d4 = () => ({ a: 1 } as unknown as { a: number });
const d5 = () => <{ a: number }><unknown>{ a: 1 };
const d6 = s as any as string;
takeString(str as unknown as string);
const d7 = () => <{ a: number }>(<unknown>{ a: 1 });
const d8 = () => ({ a: 1 }) as unknown as { a: number };
const d9 = (s /* c */ as unknown /* d */ as string).length;
const d10 = <string>(s as unknown);
const résumé = '🎉é'; const d11 = s as string; const d12 = s!; const d13 = <string>s;
declare function fn(): string;
declare const holder: { list: number[]; fn(): string; nested: { s: string } };
const e1 = fn!();
const e2 = list![0];
const e3 = obj!['s'];
const e4 = holder?.nested!.s;
const e5 = (s!);
const e6 = holder.fn!()!;
const e7 = () => s as string;
const e8 = <{ a: number }>{ a: 1 } ? 1 : 2;
const e9 = <T,>(x: T) => x as T;
const e10 = <T,>(x: T) => <T>x;
const e11 = (s as string)!;
const e12 = (<string>s)!.length;
const e13 = [<{ a: number }>{ a: 1 }];
const e14 = (x = <{ a: number }>{ a: 1 }) => x;
class Box {
  value = 'v';
  read() {
    return this!.value! as string;
  }
}
void [e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13, e14, Box];
void [n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n11, n12, target];
void [a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14];
void [t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, c1, c2];
void [d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, résumé];
