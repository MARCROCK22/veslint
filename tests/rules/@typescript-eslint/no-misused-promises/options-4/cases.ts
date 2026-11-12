// The same cases under different options: each group belongs to one check.
declare const p: Promise<boolean>;
declare function takesVoid(cb: () => void): void;
declare const list: number[];
// checksConditionals
if (p) {
}
const ternary = p ? 1 : 2;
while (p) {
  break;
}
const logical = p || true;
const negated = !p;
list.filter(async () => true);
// checksSpreads
const spread = { ...p };
// checksVoidReturn.arguments
takesVoid(async () => {});
new (class {
  constructor(cb: () => void) {
    cb();
  }
})(async () => {});
// checksVoidReturn.variables
const variable: () => void = async () => {};
let assigned: () => void;
assigned = async () => {};
// checksVoidReturn.properties
const object: { m: () => void } = { m: async () => {} };
// checksVoidReturn.returns
function returns(): () => void {
  return async () => {};
}
// checksVoidReturn.inheritedMethods
class Base {
  m(): void {}
}
class Derived extends Base {
  async m(): Promise<void> {}
}
interface Plain {
  m(): void;
}
interface Thenable extends Plain {
  m(): Promise<void>;
}
export { ternary, logical, negated, spread, variable, assigned, object, returns, Derived };
export type { Thenable };
