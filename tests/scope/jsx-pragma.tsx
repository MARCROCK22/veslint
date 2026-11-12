// The pragma is referenced by the first element whose scopes have a variable with its name when
// the element is visited: `React` is imported after `first` and is a parameter in `second`.
export function first() {
  return <div />;
}
import React from 'react';
export function second(React: unknown) {
  return <span>{React}</span>;
}
export const third = <p />;
