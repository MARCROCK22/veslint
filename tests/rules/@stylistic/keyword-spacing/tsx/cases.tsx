declare const a: any;
const e1 = <div>{typeof a}</div>;
const e2 = <div>{a as any}</div>;
const e3 = <div>(</div>;
const e4 = <div>{a}if{a}</div>;
const e5 = <div b="x">{this}</div>;
const e6 = <div>{a > this}</div>;
const e7 = <div>{(<span />)}</div>;
const e8 = [<div />]instanceof Array;
const e9 = <T,>(x: T) => typeof(x);
const e10 = <div>{async () => 1}</div>;
const e11 = (<div />)as any;
const e12 = <div>{a}</div>as any;
const e13 = <div>{(a)as any}</div>;
const e14 = <div>{[a]satisfies any[]}</div>;
const e15 = <div>{a ?<b />:this}</div>;
function e16() { return<div />; }
function e17() { return(<div />); }
