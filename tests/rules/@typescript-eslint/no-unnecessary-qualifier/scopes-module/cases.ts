// Cases of no-unnecessary-qualifier in a module: imports are aliases, whose flags are not those
// of what they name, and `arguments` is not a variable for getSymbolsInScope.
import { x, T, named as renamed } from './values';
import * as star from './values';
import Lib = require('./exported');
export namespace InModule {
  export const x = 1;
  export type T = string;
  export const star = 2;
  export const a = InModule.x;
  export const b: InModule.T = '';
  export const c = InModule.star;
  namespace Inner {
    export const d = InModule.x + x;
    export const e: InModule.T | T = '';
    import x = InModule.star;
    export const f = InModule.x + x;
  }
  void Inner;
}
namespace Hidden {
  export const x = 1;
  export const y = Hidden.x + x;
}
export default function named(): void {}
namespace WithDefault {
  export const named = 1;
  export const renamed = 2;
  export const z = WithDefault.named + WithDefault.renamed + renamed;
}
namespace WithArguments {
  export var arguments = 1;
  export function f(): unknown { return [WithArguments.arguments, arguments]; }
  export const g = (): unknown => WithArguments.arguments;
  export const h = WithArguments.arguments;
}
namespace Exported {
  const local = 1;
  export { local as v };
  export const w = Exported.v + Lib.v + star.x;
}
void [x, Hidden, WithDefault, WithArguments, Exported, null as unknown as T];
