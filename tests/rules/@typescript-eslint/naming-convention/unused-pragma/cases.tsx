// The JSX pragma: typescript-eslint's scope manager references the factory (`jsxFactory`, here `h`)
// from the first element that has a variable with that name in its scopes, and the fragment
// factory from the first fragment, so those variables are used. `React` is not the pragma here.
function h() {
  return null;
}
function Fragment() {
  return null;
}
function React() {
  return null;
}
function unusedFunction() {
  return null;
}
const unusedVariable = 1;
export const a = <div />;
export const b = <></>;
export function inner(h: unknown, Fragment: unknown) {
  // The pragma was referenced by the element above: these parameters are not.
  return <><span /></>;
}
