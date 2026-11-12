declare const s: string;
declare const n: number;
declare const b: boolean;
declare const big: bigint;
declare const one: 1;
declare const obj: { s: string; get(): string };
declare const cond: boolean;
declare function take(...values: unknown[]): void;
let text = 'a';

String(s);
s.toString();
s + '';
'' + s;
text += '';
take((text += ''));
!!b;
+n;
~~one;
Number(n);
Boolean(b);
BigInt(big);
String(obj.s);
String(obj.get());
String(s + s);
String(cond ? s : 'x');
String(s).length;
(String(s)).length;
String(s) + s;
take(String(s));
take(s + '');
const t1 = `${String(s)}`;
const t2 = String(s) ? 1 : 2;
const t3 = !String(s);
const t4 = !!b && b;
const t5 = (s + '').length;
const t6 = ('' + s).length;
const t7 = s.toString().length;
const t8 = obj.s.toString();
const t9 = (s + s).toString();
const t10 = (cond ? s : 'x').toString();
const t11 = +(n + n);
const t12 = +n + 1;
const t13 = -+n;
const t14 = !!(b && b);
const t15 = typeof !!b;
const t16 = ~~one + 1;
const t17 = { a: String(s) };
const t18 = () => String(s);
const t19 = async () => await String(s);
function f() {
  return String(s);
}
const t20 = String(s as string);
const t21 = String((s));
const t22 = String(/* c */ s /* d */);
const t23 = s /* c */ + /* d */ '';
const t24 = [String(s), s.toString(), s + '', '' + s];
const t25 = String(s)!;
const t26 = String(s)[0];
const t27 = String(`a${s}`);
const t28 = `a${s}`.toString();
const t29 = (text += '').length;
if (cond) text += '';
const u1 = s
String(`x${s}`).length
const u2 = s
;`x${s}`.toString()
const u3 = s
'' + `x${s}`
const u4 = s
!!b ? 1 : 2
const u5 = s;
String(`x${s}`).length
const résumé = '🎉é'; String(s);
declare const holder: { s: string; n: number; flag: boolean };
const v1 = holder?.s.toString();
const v2 = (holder?.s).toString();
const v3 = String?.(s);
const v4 = String(holder?.s);
const v5 = !(!b);
const v6 = ~(~one);
const v7 = !!(b);
const v8 = !!!b;
const v9 = +(+n);
const v10 = String(s) as string;
const v11 = () => (text += '');
const v12 = (text += '', 1);
for (; cond; text += '') {
}
text += '' // trailing comment
const v13 = +holder?.n;
const v14 = !!holder?.flag;
const v15 = '' + holder?.s;
const v16 = holder?.s + '';
const v17 = (+n) ** 2 === 1 ? String(s) : '' + s;
const v18 = [...String(s)];
const v19 = { [String(s)]: +n, ...{ k: !!b } };
const v20 = (String)(s);
const v21 = String((s), 1 as never);
const v22 = s.toString /* c */ ();
const v23 = (s as string).toString();
const v24 = s!.toString();
const v25 = `a${s}b`.toString().length;
void [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15, v16, v17, v18, v19, v20];
void [v21, v22, v23, v24, v25];
void [t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, f];
void [t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, u1, u2, u3, u4, u5, résumé];
