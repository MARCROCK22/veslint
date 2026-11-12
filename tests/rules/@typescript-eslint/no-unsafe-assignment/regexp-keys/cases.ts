// Cases of no-unsafe-assignment with a computed key that is a regular expression: its name is
// String(new RegExp(pattern, flags)), or "null" when the engine rejects the literal.
declare const source: {
  '/a/': any;
  '/a/gi': any;
  '/[/]\\d+/u': any;
  '/\\//dgimsuy': any;
  '/b/': string;
  '/c/': { inner: any };
  '/d/': [any, string];
  null: any;
  safe: string;
};
declare const safeSource: { '/a/': string; null: string; '/x/g': any; '/x/gg': any };
const { [/a/]: plain } = source;
const { [/a/ig]: reordered } = source;
const { [/a/gi]: ordered } = source;
const { [/a/g]: otherFlags } = source;
const { [/[/]\d+/u]: withClass } = source;
const { [/\//yusmigd]: everyFlag } = source;
const { [/b/]: safe } = source;
const { [/c/]: { inner } } = source;
const { [/d/]: [first, second] } = source;
const { [(/a/)]: parenthesized } = source;
const { [/a/]: fromSafe } = safeSource;
// Literals V8 rejects have no value: String(null).
const { [/a/gg]: repeatedFlag } = source;
const { [/a/uv]: bothModes } = source;
const { [/x/gg]: repeatedInSafe } = safeSource;
const { [/\p{Nope}/u]: unknownProperty } = source;
const { [/(?<n>a)(?<n>b)/]: repeatedName } = source;
const { [/a{2,1}/]: outOfOrder } = source;
const { [/\p{Nope}/]: annexB } = source;
let assigned: unknown;
({ [/a/]: assigned } = source);
({ [/b/]: assigned } = source);
function parameter({ [/a/]: value }: typeof source): void { void value; }
void [plain, reordered, ordered, otherFlags, withClass, everyFlag, safe, inner, first, second];
void [parenthesized, fromSafe, repeatedFlag, bothModes, repeatedInSafe, unknownProperty];
void [repeatedName, outOfOrder, annexB, assigned, parameter];
