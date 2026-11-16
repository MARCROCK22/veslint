declare let a: any, b: any, c: any;
declare function A(props: object): any;
export const s1 = <A {...b} />;
export const s2 = <A {...(b)} />;
export const s3 = <A {...((b))} />;
export const s4 = <A {...(b, c)} />;
export const s5 = <A {...((b, c))} />;
export const s6 = <A {...(b ?? c)} />;
export const s7 = <A {...(a ? b : c)} />;
export const s8 = <A {...(b as object)} {...(c satisfies object)} />;
export const s9 = <A {...((b as object))} />;
export const s10 = <A {...(b && c)} {...(b || c)} />;
export async function s11() { return <A {...(await b)} />; }
export const s12 = <A {...(b = c)} />;
export const s13 = <A {...(() => b)} />;
export const s14 = <A {...(b!)} />;
export const s15 = <A {...(b.c)} {...(b())} />;
export const s16 = <A>{...(b)}</A>;
