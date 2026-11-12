// checksVoidReturn.attributes: a Promise-returning function given to a JSX attribute that
// expects a function returning void.
declare global {
  namespace JSX {
    interface Element {
      kind: string;
    }
    interface IntrinsicElements {
      button: { onClick?: () => void; onLoad?: () => Promise<void>; title?: string };
    }
  }
}
declare function Button(props: { onClick: () => void; onSave?: () => Promise<void>; label?: string }): JSX.Element;
declare const asyncHandler: () => Promise<void>;
declare const syncHandler: () => void;
const a = <Button onClick={async () => {}} />;
const b = <Button onClick={asyncHandler} />;
const c = <Button onClick={syncHandler} onSave={asyncHandler} />;
const d = <button onClick={async () => {}} onLoad={async () => {}} title="x" />;
const e = <Button onClick={(async () => {})} label={`x`} />;
const f = <Button onClick={/* nothing */} />;
const g = <Button {...{ onClick: async () => {} }} />;
const h = (
  <button onClick={async function named() {}}>
    <Button onClick={() => Promise.resolve()} />
  </button>
);
export { a, b, c, d, e, f, g, h };
