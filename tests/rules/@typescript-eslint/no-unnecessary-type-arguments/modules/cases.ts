import Fallback, { Remote, RemoteBox, remote } from './declarations';
import * as all from './declarations';
import type { Remote as Renamed } from './declarations';

// Declarations from another file, through imports (aliases).
type A = Remote<string>;
type B = Renamed<string>;
type C = all.Remote<string>;
type D = Fallback<bigint>;
new RemoteBox<number>();
new all.RemoteBox<number>();
remote<boolean>();
class Child extends RemoteBox<number> {}
class Other implements Remote<string> {
  value = '';
}

export type { A, B, C, D };
export { Child, Other };
