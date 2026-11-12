export {};
declare function voidFn(): void;
declare function undefinedFn(): undefined;
declare function numberFn(): number;
declare function promiseVoid(): Promise<void>;
declare const maybe: boolean;
declare const holder: { method(): void; optional?: () => void };
declare function tag(strings: TemplateStringsArray): void;
declare function generic<T>(value: T): T;

// Valid positions.
voidFn();
maybe && voidFn();
maybe ? voidFn() : voidFn();
maybe || (maybe && voidFn());
voidFn(), numberFn();
holder?.method();
holder.optional?.();
tag`text`;
label: voidFn();
const number = numberFn();
generic(numberFn());
async function awaits(): Promise<void> {
  await promiseVoid();
}

// Invalid positions.
const value = voidFn();
const other = undefinedFn();
console.log(voidFn());
numberFn(), voidFn();
const sequence = (numberFn(), voidFn());
const ternary = maybe ? voidFn() : 1;
const logical = maybe && voidFn();
const nullish = numberFn() ?? voidFn();
for (voidFn(); maybe; voidFn()) {
  break;
}
const template = `${voidFn()}`;
void voidFn();
const tagged = tag`text`;
const generic2 = generic(voidFn());
async function awaited(): Promise<void> {
  const awaitedValue = await promiseVoid();
  console.log(await promiseVoid());
}

// Arrow shorthand bodies.
const arrow = () => voidFn();
const arrowParens = () => (voidFn());
const arrowChain = () => holder?.method();
const arrowTernary = () => (maybe ? voidFn() : voidFn());
const arrowVoid = () => void voidFn();
const arrowNumber = () => numberFn();

// Returns.
function returnsLast() {
  return voidFn();
}
function returnsEarly() {
  if (maybe) {
    return voidFn();
  }
  voidFn();
}
function returnsInIf() {
  if (maybe) return voidFn();
}
function returnsNumber() {
  return numberFn();
}
const arrowBlock = () => {
  return voidFn();
};
class Holder {
  field = voidFn();
  method() {
    return voidFn();
  }
}
const objectMethods = {
  method() {
    return voidFn();
  },
};
function* generator() {
  return voidFn();
}

// Functions that return void by annotation or by context.
function annotated(): void {
  return voidFn();
}
const annotatedArrow = (): void => voidFn();
const unionAnnotation = (): void | number => voidFn();
const numberAnnotation = (): number | undefined => voidFn();
const contextual: () => void = () => voidFn();
const contextualBlock: () => void = () => {
  return voidFn();
};
[1].forEach(() => voidFn());
const functionExpression = function () {
  return voidFn();
};
const contextualObject: { handle(): void } = {
  handle() {
    return voidFn();
  },
};
const parenthesizedAnnotation = (): (void) => voidFn();
