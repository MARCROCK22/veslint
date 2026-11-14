/* global hasOwnProperty, propertyIsEnumerable */
declare const object: object;
declare const key: string;
declare const dynamic: string;

const a = [].forEach.call(object, () => {});
const b = ({}).hasOwnProperty.call(object, key);
const c = {}.toString.call(object);
const d = Reflect.apply([].map, object, []);
const e = [][dynamic].call(object);
const f = []['slice'].bind(object);
const g = [/* keep */].join.call(object);
const h = hasOwnProperty.call(object, key);
const i = globalThis.propertyIsEnumerable.call(object, key);
const j = typeof[].slice.call(object);
function k() {
	return[].slice.apply(object);
}

const valid1 = Array.prototype.forEach.call(object, () => {});
const valid2 = [1].forEach.call(object, () => {});
const valid3 = ({a: 1}).hasOwnProperty.call(object, key);
const valid4 = []?.forEach.call(object);
const valid5 = [].forEach?.call(object);
const valid6 = Reflect.apply?.([].map, object, []);
const valid7 = [].forEach(object);

export {a, b, c, d, e, f, g, h, i, j, k, valid1, valid2, valid3, valid4, valid5, valid6, valid7};
