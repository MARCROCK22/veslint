// JSX: deprecated components (as identifiers, as members and by the signature they resolve to)
// and deprecated props.
declare global {
  namespace JSX {
    interface Element {
      kind: string;
    }
    interface IntrinsicElements {
      /** @deprecated Use section. */
      center: { align?: string };
      div: {
        /** @deprecated Use className. */
        class?: string;
        className?: string;
      };
    }
  }
}
/** @deprecated Use NewButton. */
declare function OldButton(props: { label?: string }): JSX.Element;
declare function NewButton(props: {
  label?: string;
  /** @deprecated Use label. */
  text?: string;
}): JSX.Element;
/** @deprecated The form with a title. */
declare function Overloaded(props: { title: string }): JSX.Element;
declare function Overloaded(props: { name: string }): JSX.Element;
declare const Ns: {
  /** @deprecated Use Ns.New. */
  Old: (props: { a?: number }) => JSX.Element;
  New: (props: { a?: number }) => JSX.Element;
};
/** @deprecated Whole namespace. */
declare const OldNs: { Item: (props: { a?: number }) => JSX.Element };
const a = <OldButton label="x" />;
const b = <OldButton>text</OldButton>;
const c = <NewButton label="x" text="y" />;
const d = <Overloaded title="x" />;
const e = <Overloaded name="x" />;
const f = <Ns.Old a={1} />;
const g = <Ns.New a={1}></Ns.New>;
const h = <OldNs.Item></OldNs.Item>;
const i = <center align="x" />;
const j = <div class="x" className="y" />;
const k = (
  <NewButton text={`t`}>
    <OldButton />
  </NewButton>
);
export { a, b, c, d, e, f, g, h, i, j, k };
