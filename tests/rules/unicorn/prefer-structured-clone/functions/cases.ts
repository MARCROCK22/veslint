// unicorn/prefer-structured-clone: `structuredClone(…)` instead of `JSON.parse(JSON.stringify(…))`
// and lodash's `cloneDeep`, and of the functions of the options (in functions/).
declare const value: unknown;
declare const _: { cloneDeep<T>(v: T): T };
declare const lodash: { cloneDeep<T>(v: T): T };
declare function clone<T>(v: T): T;
declare const utils: { deep: { clone<T>(v: T): T } };

const c1 = JSON.parse(JSON.stringify(value));
const c2 = JSON.parse(JSON.stringify(value,));
const c3 = JSON.parse((JSON.stringify)(value));
const c4 = JSON.parse(JSON.stringify(value as object));
const c5 = _.cloneDeep(value);
const c6 = lodash.cloneDeep(value);
const c7 = clone(value);
const c8 = utils.deep.clone(value);
class K {
  copy<T>(v: T): T {
    return v;
  }
  m() {
    return this.copy(value);
  }
}

// Not reported.
const z1 = JSON.parse(JSON.stringify(value), undefined);
const z2 = JSON.parse(JSON.stringify(value, null, 2));
const z3 = JSON.parse?.(JSON.stringify(value));
const z4 = _.cloneDeep(value, 1);
const z5 = _?.cloneDeep(value);
const z6 = _['cloneDeep'](value);
