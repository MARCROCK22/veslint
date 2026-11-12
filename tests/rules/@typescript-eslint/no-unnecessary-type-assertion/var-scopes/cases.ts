declare const flag: boolean;

// A `var` used in a scope its declarator is nested in may be used before it is assigned.
function nestedBlock(): number {
  if (flag) {
    var inBlock: number = 1;
  }
  return inBlock!;
}
function sameScope(): number {
  var sameLevel: number = 1;
  return sameLevel!;
}
function usedInChild(): () => number {
  var outer: number = 1;
  return () => outer!;
}
function deeper(): number {
  {
    {
      var deep: number = 1;
    }
  }
  return deep!;
}
function loopVar(): number {
  for (var i: number = 0; i < 1; i++) {}
  return i!;
}
function withoutInitializer(): number {
  let later: number;
  later = 1;
  return later!;
}
function definite(): number {
  let sure!: number;
  return sure!;
}
let moduleLevel: number | undefined = 1;
const narrowed = moduleLevel!;

export { nestedBlock, sameScope, usedInChild, deeper, loopVar, withoutInitializer, definite, narrowed };
