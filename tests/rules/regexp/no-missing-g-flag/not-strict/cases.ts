// Reported (strictTypes: false): with typescript-eslint's parser, as with strictTypes.
declare const text: string;
export const a1 = text.matchAll(/foo/);
// Not reported: the type is not a string.
declare const value: unknown;
export const b1 = (value as any).matchAll(/foo/);
