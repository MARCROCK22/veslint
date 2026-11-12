// strict-void-return in JSX attributes.
declare global {
  namespace JSX {
    interface Element {
      kind: string;
    }
    interface IntrinsicElements {
      button: { onClick?: () => void; onLoad?: () => number; title?: string; children?: unknown };
    }
  }
}
declare const numberFn: () => number;
declare function Custom(props: { onDone: () => void; render: () => number }): JSX.Element;
const a = <button onClick={() => 1} />;
const b = <button onClick={() => {}} onLoad={() => 1} />;
const c = <button onClick={numberFn} title="text" />;
const d = <button onClick={async () => {}}>{() => 1}</button>;
const e = <button onClick={(() => { return 'x'; })} />;
const f = <Custom onDone={() => 1} render={() => 2} />;
const g = <Custom onDone={function () { return 1; }} render={numberFn} />;
const h = <button onClick={/* empty */} />;
export { a, b, c, d, e, f, g, h };
