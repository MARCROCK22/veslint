import a1 from './a1.json' with { a: '1', b: '2' };
import a2 from './a2.json' with { b: '1', a: '2' };
import type a3 from './a3.json' with { a: '1', b: '2' };
import type a4 from './a4.json' with { b: '1', a: '2' };
export { a1, a2 };
export type { a3, a4 };
