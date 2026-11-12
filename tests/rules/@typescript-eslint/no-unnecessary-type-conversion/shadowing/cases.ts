declare const text: string;
declare const num: number;
declare const flag: boolean;

// Only a declaration in the innermost scope of the call hides the built-in function.
function local(): string {
  function String(value: string): string {
    return value;
  }
  return String(text);
}
function outer(): number {
  const Number = (value: number): number => value;
  return (() => Number(num))();
}
function parameter(Boolean: (value: boolean) => boolean): boolean {
  return Boolean(flag);
}
function nested(Boolean: (value: boolean) => boolean): boolean {
  if (flag) {
    return Boolean(flag);
  }
  return false;
}
function block(): string {
  {
    let String = (value: string): string => value;
    return String(text);
  }
}
function typeOnly(): string {
  type String = string;
  return String(text);
}
class Scoped {
  method(): string {
    return String(text);
  }
}
const String2 = String(text);

export { local, outer, parameter, nested, block, typeOnly, Scoped, String2 };

function loopScope(): string {
  for (let String = 0; String < 1; String++) {
    return globalThis.String(text);
  }
  for (const Number of [1]) {
    return `${Number}`;
  }
  return '';
}
function catchScope(): string {
  try {
    return '';
  } catch (String) {
    return String(text);
  }
}
function interfaceShadow(): string {
  interface String {
    extra: number;
  }
  return String(text);
}
function enumShadow(): number {
  enum Number {
    A,
  }
  return Number(1);
}
function switchScope(value: number): string {
  switch (value) {
    case 1:
      let String = (x: string): string => x;
      return String(text);
    default:
      return String(text);
  }
}

export { loopScope, catchScope, interfaceShadow, enumShadow, switchScope };
