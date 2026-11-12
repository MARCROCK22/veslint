// The `globals` of the configuration are variables of the global scope, whatever their name: for
// naming-convention, a class expression with the name of one that nothing references is unused.
configUsed;
export const a = class configUnused {};
export const b = class configUsed {};
export const c = class configOff {};
// Off in the configuration, but the lib declares it: an implicit variable, never unused.
export const d = class Map {};
export const e = class WeakMap {};
