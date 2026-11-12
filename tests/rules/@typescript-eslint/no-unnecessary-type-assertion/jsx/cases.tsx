// A JSX element or fragment is "conceptually a literal" for the rule.
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
declare function takes(element: JSX.Element): void;
declare const maybe: string | undefined;
const a = <div /> as JSX.Element;
const b = (<div>text</div>) as JSX.Element;
const c = <></> as JSX.Element;
takes(<div /> as JSX.Element);
const d: JSX.Element = <div /> as JSX.Element;
const e = <div title={maybe!}>{maybe!}</div>;
const f = <div>{(maybe as string | undefined)}</div>;
const g = maybe!;
export { a, b, c, d, e, f, g };
