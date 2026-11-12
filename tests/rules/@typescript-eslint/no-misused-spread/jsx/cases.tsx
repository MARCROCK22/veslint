// JSXSpreadAttribute is checked like a spread in an object; a spread among the children is not.
declare global {
  namespace JSX {
    interface Element {
      kind: string;
    }
    interface IntrinsicElements {
      [name: string]: Record<string, unknown>;
    }
  }
}
declare function Box(props: Record<string, unknown>): JSX.Element;
declare const promise: Promise<{ a: number }>;
declare const map: Map<string, number>;
declare const maybeMap: Map<string, number> | undefined;
declare function fn(): void;
declare const list: number[];
declare const text: string;
declare const props: { a: number };
class Thing {
  value = 1;
}
declare const thing: Thing;
const a = <Box {...promise} />;
const b = <Box {...map} />;
const c = <Box {...fn} />;
const d = <Box {...list} />;
const e = <Box {...thing} />;
const f = <Box {...props} {...(map)} />;
const g = <div {...promise}>{...list}</div>;
const h = <Box {...maybeMap} {...text} />;
const i = <Box {...(await promise)} />;
export { a, b, c, d, e, f, g, h, i };
