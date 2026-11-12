// A JSX attribute with an expression is an assignment to the attribute.
declare global {
  namespace JSX {
    interface Element {
      kind: string;
    }
    interface IntrinsicElements {
      input: { value?: string; count?: number; data?: unknown; anything?: any; tags?: Set<string> };
    }
  }
}
declare function Field(props: { value: string; items?: string[]; tags?: Set<string> }): JSX.Element;
declare const anything: any;
declare const anySet: Set<any>;
declare const anyList: any[];
const a = <input value={anything} />;
const b = <input value={(anything)} count={1} />;
const c = <input data={anything} anything={anything} />;
const d = <Field value={anything} items={anyList} tags={anySet} />;
const e = <Field value="text" items={[anything as string]} />;
const f = <input value={/* empty */} />;
const g = <input {...anything} />;
const h = <input tags={anySet} value={`${anything as string}`}>{anything}</input>;
export { a, b, c, d, e, f, g, h };
