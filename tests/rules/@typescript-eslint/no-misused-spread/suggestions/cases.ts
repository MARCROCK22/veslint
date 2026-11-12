declare const promise: Promise<{ a: number }>;
declare function getPromise(): Promise<{ a: number }>;
declare const holder: { promise: Promise<{ a: number }>; maps: Map<string, number>[] };
declare const map: Map<string, number>;
declare const readonlyMap: ReadonlyMap<string, number>;
declare const weakMap: WeakMap<object, number>;
declare const maybeMap: Map<string, number> | undefined;
declare const mapOrObject: Map<string, number> | { a: number };
declare const eitherMap: Map<string, number> | ReadonlyMap<string, number>;
declare const cond: boolean;

// addAwait
const p1 = { ...promise };
const p2 = { ...getPromise() };
const p3 = { ...(promise) };
const p4 = { ...(cond ? promise : getPromise()) };
const p5 = { ...(promise as Promise<{ a: number }>) };
const p6 = { ...new Promise<{ a: number }>(() => {}) };
const p7 = { a: 1, ...promise, b: 2 };
const p8 = { ...promise! };
const p9 = { .../* c */ promise };
const p10 = { ...holder.promise };
const p11 = { ...holder['promise'] };
const p12 = { ...(cond && promise) };
const p13 = { ...(0, promise) };
const p14 = { ...(<Promise<{ a: number }>>promise) };
const p15 = { ...new Promise<{ a: number }> };
async function inside() {
  return { ...getPromise(), ...(promise satisfies Promise<{ a: number }>) };
}

// replaceMapSpreadInObject
const m1 = { ...map };
const m2 = { ...map, a: 1 };
const m3 = { ...readonlyMap };
const m4 = { ...weakMap };
const m5 = { ...(cond ? map : readonlyMap) };
const m6 = { ...maybeMap };
const m7 = { ...mapOrObject };
const m8 = { ...(map) };
const m9 = ({ ...map }).a;
const m10 = () => ({ ...map });
function m11() {
  return { ...map };
}
const m12 = [{ ...map }];
const m13 = { ...eitherMap };
const m14 = { a: 1, ...(cond ? map : readonlyMap) };
const m15 = { ...holder.maps[0] };
const m16 = { ...new Map<string, number>() };
const m17 = { .../* c */ map /* d */ };
const m18 = !{ ...map };
const m19 = { ...(map as Map<string, number>) };
const m20 = { nested: { ...map } };
const résumé = '🎉é'; const m21 = { ...map };
const m22 = { ...holder?.maps[0] };
const m23 = { a: 1, ...holder?.maps[0] };
const p16 = { ...holder?.promise };
const m24 = { ...(map), b: 2 };
const m25 = typeof { ...map };
const m26 = { ...map }!;
async function awaited() {
  return [await { ...map }, await { ...promise }, { ...(await promise) }];
}
const m27 = cond ? { ...map } : { a: 1, ...map };
const m28 = { ...(cond ? map : readonlyMap), };
const m29 = { ...map satisfies Map<string, number> };
const m30 = { ...(map, readonlyMap) };
const m31 = `${{ ...map }}`;
const m32 = { ...map }.toString();
const m33 = { ...(map as Map<string, number> & { extra: 1 }) };
const p17 = { ...(async () => ({ a: 1 }))() };
const p18 = { ...promise satisfies Promise<{ a: number }> };
void [m22, m23, p16, m24, m25, m26, awaited, m27, m28, m29, m30, m31, m32, m33, p17, p18];
void [p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, inside];
void [m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16, m17, m18, m19, m20, m21, résumé];
