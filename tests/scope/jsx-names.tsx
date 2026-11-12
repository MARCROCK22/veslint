// The names of JSX elements: opening and closing tags, member and namespaced names, `this`.
import React from 'react';
declare const Upper: any, lower: any, ns: any, $dollar: any, _under: any;
export class C {
  Field = Upper;
  render() {
    return [<this.Field />, <this.Field></this.Field>, <this />];
  }
}
export const all = [
  <Upper></Upper>,
  <lower></lower>,
  <ns.Member.Deep></ns.Member.Deep>,
  <svg:rect xlink:href="x"></svg:rect>,
  <$dollar />,
  <_under />,
  <Upper<string> generic={lower} {...ns} plain="s" nested=<Upper /> frag=<></> bool />,
  <Upper>{lower}{...ns}text{/* empty */}</Upper>,
];
