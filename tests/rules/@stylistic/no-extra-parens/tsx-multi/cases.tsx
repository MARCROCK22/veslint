declare const a: boolean;
export const single = (<div />);
export const multi = (
  <div>
    <span />
  </div>
);
export const fragment = (<>text</>);
export const cond = a ? (<b />) : (<i />);
export function render() {
  return (
    <div />
  );
}
export const inExpr = <div>{(a)}</div>;
export const typed = (<div /> as unknown);
