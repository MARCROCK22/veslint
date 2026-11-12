/**
 * @deprecated First reason.
 * @deprecated Second reason.
 */
function twice(): void {}
twice();

/** @deprecated Earlier block. */
/** Later block. */
function twoBlocks(): void {}
twoBlocks();

/**
 * @typedef {string} Alias
 * @deprecated Typedef host.
 */
function typedefHost(): void {}
typedefHost();
/**
 * @typedef {string} Alias2
 * @param x Documented.
 * @deprecated Typedef with a parameter.
 */
function typedefWithParam(x?: number): void {
  void x;
}
typedefWithParam();

class IB2 {
  /** @deprecated Base reason. */
  m(): void {}
}
class ID2 extends IB2 {
  /**
   * @inheritDoc
   * @deprecated Own reason.
   */
  m(): void {}
}
new ID2().m();

function expando() {}
/** @deprecated Expando property. */
expando.prop = () => {};
expando.prop();
function expando2() {}
/** @deprecated Defaulted. */
expando2.prop = undefined || function named(): void {
  named();
};
void expando2.prop;

type Tup = [
  /** @deprecated First element. */
  first: number,
  second: number,
];
declare const tup: Tup;
void tup[0];
void tup[1];

interface Shape {
  /** @deprecated Property doc. */
  prop: string;
}
declare const shape: Shape;
function usesShape({ prop }: Shape) {
  return prop;
}
let assigned: string;
({ prop: assigned } = shape);
({ prop: assigned = '' } = shape);
for (const { prop } of [shape]) {
  void prop;
}
const { prop: withDefault = '' } = shape;
void shape?.['prop'];
void shape[`prop`];
try {
  void 0;
} catch ({ message }) {
  void message;
}
type Query = typeof shape.prop;
void [usesShape, assigned, withDefault];
export type { Query };

/** @deprecated Default export. */
const defaulted = 1;
export default defaulted;

// More expando assignments: TypeScript adds the `f` of each top-level `f.x = …` to the
// declarations of the function `f`, and a defaulted one gives it its JSDoc.
const arrowExpando = () => {};
/** @deprecated Arrow defaulted. */
arrowExpando.prop = undefined ?? function () {};
arrowExpando();
void arrowExpando;
function nestedExpando() {}
function nestedScope() {
  /** @deprecated Not at the top level. */
  nestedExpando.prop = undefined || 1;
}
void nestedExpando;
void nestedScope;
function chainedExpando() {}
let sink: unknown;
/** @deprecated Chained. */
sink = chainedExpando.prop = undefined || 2;
void chainedExpando;
void sink;
function elementExpando() {}
/** @deprecated Element access. */
elementExpando['prop'] = undefined || 3;
void elementExpando;
function plainExpando() {}
/** @deprecated Not defaulted. */
plainExpando.prop = 4;
void plainExpando;
void plainExpando.prop;
