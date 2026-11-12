declare const value: {
  b: { c: number; list: number[] };
  f(): { g(): number };
  generic<T>(x?: T): T;
  ['quoted key']: number;
  #secret?: never;
};
declare const fn: () => number;
declare const key: 'b';

void value?.b;
void value?.b?.c;
void value?.['b'];
void value?.[key];
void value?.[`quoted key`];
void value?.f();
void value.f?.();
void value?.f?.()?.g?.();
void fn?.();
void value.generic?.<number>(1);
void (value)?.b;
void (value?.b)?.c;
void value /* before */ ?. /* after */ b;
void value
  ?.b
  ?.c;
void value?.b!.c;
void value!?.b;
void value?.b.list?.[0];
const résumé = '🎉é'; void value?.b;
void [résumé];
