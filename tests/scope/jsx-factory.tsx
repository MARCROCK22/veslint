// jsxFactory and jsxFragmentFactory of the compiler options.
import { h, Fragment } from 'preact';
import React from 'react';
export function inner(Fragment: unknown) {
  const h = 1;
  return [<div />, <></>, h, Fragment];
}
export const b = <><Upper>text</Upper></>;
declare const Upper: (props: { children?: unknown }) => null;
export { React };
