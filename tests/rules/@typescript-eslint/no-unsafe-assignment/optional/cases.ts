// no-unsafe-assignment with exactOptionalPropertyTypes: typescript-eslint requests the type of each
// destructured property with getTypeOfSymbolAtLocation, which removes the implicit `undefined`
// from optional ones; with getTypeOfSymbol, `a` would not be a tuple.
declare const withOptional: { a?: [any]; b?: any };
const { a: [x], b } = withOptional;
void [x, b];
