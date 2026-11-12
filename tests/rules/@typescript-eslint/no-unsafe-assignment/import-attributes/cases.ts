// Import attributes are a list of ImportAttribute nodes in ESTree, not an object literal: nothing
// is assigned there, also when the module is not found and what it gives is error typed.
import data from 'missing-module' with { type: 'json' };
import * as all from 'missing-module-2' with { type: 'json' };
import { named } from 'missing-module-3' with {};

// The options of `import()` are an object literal, checked like any other.
declare const anyValue: any;
const loaded = import('missing-module-4', { with: { type: anyValue } });
const object = { value: anyValue };

export { data, all, named, loaded, object };
