// consistent-return with treatUndefinedAsUnspecified.
declare const flag: boolean;
declare const value: number;
declare function call(): number;
declare const anyValue: any;

function mixed() {
  if (flag) {
    return 1;
  }
  return;
}
function mixedReverse(): number | undefined {
  if (flag) {
    return;
  }
  return 1;
}
function consistentValues() {
  if (flag) {
    return 1;
  }
  return 2;
}
function consistentEmpty(): void {
  if (flag) {
    return;
  }
  return;
}
function missingAtEnd() {
  if (flag) {
    return 1;
  }
}
function voidFunction(): void {
  if (flag) {
    return;
  }
  return call() as unknown as void;
}
async function asyncVoid(): Promise<void> {
  if (flag) {
    return;
  }
  return Promise.resolve();
}
async function asyncNested(): Promise<Promise<void>> {
  if (flag) {
    return;
  }
  return Promise.resolve();
}
async function asyncNumber(): Promise<number | undefined> {
  if (flag) {
    return;
  }
  return 1;
}
function voidUnion(): void | number {
  if (flag) {
    return;
  }
  return 1;
}
function undefinedValue() {
  if (flag) {
    return undefined;
  }
  return;
}
function voidValue() {
  if (flag) {
    return void 0;
  }
  return;
}
function threeReturns() {
  if (flag) {
    return 1;
  }
  if (value) {
    return;
  }
  return;
}
const expression = function () {
  if (flag) {
    return 1;
  }
};
const named = function inner() {
  if (flag) {
    return 1;
  }
  return;
};
const arrow = () => {
  if (flag) {
    return 1;
  }
};
const asyncArrow = async () => {
  if (flag) {
    return 1;
  }
  return;
};
const shortArrow = () => 1;
function* generator() {
  if (flag) {
    return 1;
  }
  yield 2;
}
async function* asyncGenerator() {
  if (flag) {
    return 1;
  }
  return;
}
function Constructor(this: any) {
  if (flag) {
    return 1;
  }
}
function Émile() {
  if (flag) {
    return 1;
  }
}
export default function () {
  if (flag) {
    return 1;
  }
}

class Members {
  constructor() {
    if (flag) {
      return anyValue;
    }
  }
  method() {
    if (flag) {
      return 1;
    }
  }
  static shared() {
    if (flag) {
      return 1;
    }
    return;
  }
  async later() {
    if (flag) {
      return 1;
    }
  }
  static async *stream() {
    if (flag) {
      return 1;
    }
  }
  get accessor() {
    if (flag) {
      return 1;
    }
  }
  set accessor(input: number) {
    if (flag) {
      return anyValue;
    }
    return;
  }
  #hidden() {
    if (flag) {
      return 1;
    }
  }
  static #secret() {
    if (flag) {
      return 1;
    }
    return;
  }
  ['computed']() {
    if (flag) {
      return 1;
    }
  }
  [`template`]() {
    if (flag) {
      return 1;
    }
  }
  [value]() {
    if (flag) {
      return 1;
    }
  }
  'quoted name'() {
    if (flag) {
      return 1;
    }
  }
  123() {
    if (flag) {
      return 1;
    }
  }
  field = () => {
    if (flag) {
      return 1;
    }
  };
  static functionField = function () {
    if (flag) {
      return 1;
    }
    return;
  };
  #privateField = async function named() {
    if (flag) {
      return 1;
    }
  };
}
const object = {
  method() {
    if (flag) {
      return 1;
    }
  },
  property: function () {
    if (flag) {
      return 1;
    }
    return;
  },
  arrowProperty: () => {
    if (flag) {
      return 1;
    }
  },
  namedProperty: function own() {
    if (flag) {
      return 1;
    }
  },
  async asyncMethod() {
    if (flag) {
      return 1;
    }
  },
  *generatorMethod() {
    if (flag) {
      return 1;
    }
  },
  get getter() {
    if (flag) {
      return 1;
    }
  },
  set setter(input: number) {
    if (flag) {
      return anyValue;
    }
    return;
  },
  [value]: function () {
    if (flag) {
      return 1;
    }
  },
  ['literal']: () => {
    if (flag) {
      return 1;
    }
  },
  1: function () {
    if (flag) {
      return 1;
    }
  },
};

// Whether the end is reachable.
function alwaysReturns() {
  if (flag) {
    return 1;
  } else {
    return 2;
  }
}
function throwsAtEnd() {
  if (flag) {
    return 1;
  }
  throw new Error('x');
}
function infiniteWhile() {
  while (true) {
    if (flag) {
      return 1;
    }
  }
}
function infiniteWhileNumber() {
  while (1) {
    if (flag) {
      return 1;
    }
  }
}
function infiniteWhileString() {
  while ('yes') {
    if (flag) {
      return 1;
    }
  }
}
function finiteWhileZero() {
  while (0) {
    return 1;
  }
}
function whileNotLiteral() {
  while (!0) {
    if (flag) {
      return 1;
    }
  }
}
function whileBreak() {
  while (true) {
    if (flag) {
      return 1;
    }
    break;
  }
}
function infiniteFor() {
  for (;;) {
    if (flag) {
      return 1;
    }
  }
}
function forWithTest() {
  for (let i = 0; i < value; i++) {
    return i;
  }
}
function forTrue() {
  for (; true; ) {
    if (flag) {
      return 1;
    }
  }
}
function forOf() {
  for (const item of [1, 2]) {
    return item;
  }
}
function forIn() {
  for (const key in object) {
    return key;
  }
}
function doWhileTrue() {
  do {
    if (flag) {
      return 1;
    }
  } while (true);
}
function doWhileCondition() {
  do {
    if (flag) {
      return 1;
    }
  } while (flag);
}
function doWhileReturns() {
  do {
    return 1;
  } while (flag);
}
function doWhileContinue() {
  do {
    if (flag) {
      continue;
    }
    return 1;
  } while (flag);
}
function labeledBreak() {
  outer: while (true) {
    while (true) {
      if (flag) {
        return 1;
      }
      break outer;
    }
  }
}
function labeledBlock() {
  block: {
    if (flag) {
      break block;
    }
    return 1;
  }
}
function labeledBlockReturns() {
  block: {
    return 1;
  }
}
function labeledContinue() {
  outer: for (;;) {
    for (;;) {
      if (flag) {
        return 1;
      }
      continue outer;
    }
  }
}
function switchDefault() {
  switch (value) {
    case 1:
      return 1;
    default:
      return 2;
  }
}
function switchNoDefault() {
  switch (value) {
    case 1:
      return 1;
    case 2:
      return 2;
  }
}
function switchBreak() {
  switch (value) {
    case 1:
      return 1;
    default:
      break;
  }
}
function switchFallthrough() {
  switch (value) {
    case 1:
    case 2:
      return 1;
    default:
      throw new Error('x');
  }
}
function switchDefaultFirst() {
  switch (value) {
    default:
      return 0;
    case 1:
      return 1;
  }
}
function switchDefaultMiddleFalls() {
  switch (value) {
    case 1:
      return 1;
    default:
    case 2:
      call();
  }
}
function switchEmpty() {
  if (flag) {
    return 1;
  }
  switch (value) {
  }
}
function switchLastFalls() {
  switch (value) {
    case 1:
      return 1;
    default:
      call();
  }
}
function tryReturns() {
  try {
    return call();
  } catch (error) {
    return 0;
  }
}
function tryCatchFalls() {
  try {
    return call();
  } catch (error) {
    console.log(error);
  }
}
function tryLiteralCatchFalls() {
  try {
    return 1;
  } catch (error) {
    console.log(error);
  }
}
function tryIdentifierCatchFalls() {
  try {
    return value;
  } catch {
  }
}
function tryArrowCatchFalls() {
  try {
    return () => call();
  } catch {
  }
}
function tryThrowLiteral() {
  try {
    if (flag) {
      return 1;
    }
    throw 1;
  } catch {
  }
}
function tryFinallyReturns() {
  try {
    return call();
  } finally {
    call();
  }
}
function tryFinallyFalls() {
  try {
    if (flag) {
      return 1;
    }
  } finally {
    call();
  }
}
function finallyReturns() {
  try {
    if (flag) {
      return 1;
    }
  } finally {
    return 2;
  }
}
function tryCatchFinally() {
  try {
    return call();
  } catch {
    return 0;
  } finally {
    call();
  }
}
function tryCatchThrowsFinally() {
  try {
    return call();
  } catch (error) {
    throw error;
  } finally {
    call();
  }
}
function tryCatchFallsFinally() {
  try {
    return call();
  } catch {
    call();
  } finally {
    call();
  }
}
function nestedTry() {
  try {
    try {
      return 1;
    } catch {
      return 2;
    }
  } catch {
    call();
  }
}
function nestedTryThrowable() {
  try {
    try {
      return call();
    } catch {
      return 2;
    }
  } catch {
    call();
  }
}
function typeAnnotationInTry() {
  try {
    const local: Members | undefined = undefined;
    return 1;
  } catch {
  }
}
function unreachableThrowable() {
  try {
    return 1;
    call();
  } catch {
  }
}
function nestedFunctions() {
  const inner = () => {
    if (flag) {
      return 1;
    }
    return;
  };
  function declared() {
    return;
  }
  return inner;
}
function afterReturn() {
  if (flag) {
    return 1;
  }
  return 2;
  call();
}
function withBlock() {
  {
    if (flag) {
      return 1;
    }
  }
}
function ifWithoutElse() {
  if (flag) return 1;
  else if (value) return 2;
}
function parenthesized() {
  if (flag) {
    return (1);
  }
  return;
}
declare const undefinedConstant: undefined;
declare const maybe: number | undefined;
function returnsUndefinedConstant() {
  if (flag) {
    return undefinedConstant;
  }
  return;
}
function returnsMaybe() {
  if (flag) {
    return maybe;
  }
  return;
}
function returnsUndefinedAndValue() {
  if (flag) {
    return undefined;
  }
  return 1;
}
function returnsVoidAndValue() {
  if (flag) {
    return void call();
  }
  return 1;
}
function onlyUndefined() {
  if (flag) {
    return undefined;
  }
}
function onlyUndefinedConstant() {
  if (flag) {
    return undefinedConstant;
  }
  return (undefined);
}
