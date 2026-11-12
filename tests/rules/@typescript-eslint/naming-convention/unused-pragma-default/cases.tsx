// Without `jsxFactory` the pragma is `React`, and there is no fragment name. The first element is
// visited before `React` is declared, so the reference comes from the element of `second`; the
// `React` and the `Fragment` of `third` are never referenced.
export function first() {
  return <div />;
}
const React = { createElement: () => null };
const Fragment = 1;
export function second() {
  return <span />;
}
export function third() {
  const element = <><p /></>;
  const React = 1;
  const Fragment = 2;
  return element;
}
// The other names of a JSX element the scope manager references: both parts of a namespaced
// name, the types of its type arguments and, of a member name, its leftmost object.
const svg = 1;
const rect = 2;
const lowerObject = { Inner: () => null };
type OnlyInTypeArguments = { a: number };
type NeverUsed = { b: number };
const Generic = <T,>(props: { value?: T }) => null;
export const namespaced = <svg:rect />;
export const typed = <Generic<OnlyInTypeArguments> />;
export const member = <lowerObject.Inner></lowerObject.Inner>;
