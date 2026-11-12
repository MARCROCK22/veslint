// JSX: the pragma is referenced once, from the scope that declares it.
import React from 'react';
import * as NS from 'ns';
import { Upper, lower } from 'c';
declare const obj: { Inner: any };
function inner(props: { v: unknown }) {
  const local = <div className="a" {...props} key={lower}>{props.v}</div>;
  return local;
}
export const a = <Upper attr={inner} />;
export const b = <lower />;
export const c = <NS.Component<string> />;
export const d = <obj.Inner.Deep />;
export const e = <svg:rect />;
export const f = <>{a}<Upper>text</Upper></>;
export class C {
  Field = 1;
  render() {
    return <this.Field />;
  }
}
export const g = <Upper {...obj} attr=<b /> />;
