// checksSpreads listens to ESTree's SpreadElement: the spread of an object, an array or an
// argument list. The spread of a JSX attribute or of a JSX child is another node, which the rule
// does not check, also when what is spread is a Promise.
declare global {
  namespace JSX {
    interface Element {
      kind: string;
    }
    interface IntrinsicElements {
      div: { title?: string; children?: unknown };
    }
  }
}
declare function Box(props: { title?: string; children?: unknown }): JSX.Element;
declare const promise: Promise<{ title: string }>;
declare const maybe: Promise<{ title: string }> | { title: string };
declare const list: Promise<string>[];
declare function take(...values: unknown[]): void;

// Not reported: JSX spreads.
const a = <Box {...promise} />;
const b = <div {...promise}>{...list}</div>;
const c = <Box {...maybe} {...(promise)} />;

// Reported: the spreads inside the expressions of the same elements.
const d = <Box {...{ ...promise }} />;
const e = <Box title={String({ ...maybe })} />;
const f = <div>{take(...[promise], { ...promise })}</div>;
export { a, b, c, d, e, f };
