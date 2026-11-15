declare const a: any;
const f1 = () => 1;
const f2 = ()=>1;
const f3 = () =>1;
const f4 = ()=> 1;
const f5 = (x: number)=>x;
const f6 = x=>x;
const f7 = async()=>{};
const f8 = ()/* c */=>/* d */1;
const f9 = () /* c */ => /* d */ 1;
const f10 = ()=>(1);
const f11 = ()=>({ a });
const f12 = (): number=>1;
const f13 = <T>(x: T)=>x;
const f14 = ()
  =>1;
const f15 = () =>
  1;
const f16 = ()=>()=>1;
const f17 = ()=>// c
  1;
type T1 = ()=>void;
type T2 = (x: number) => void;
type T3 = new()=>object;
type T4 = abstract new () =>object;
type T5 = ()=>()=>void;
type T6 = (cb: ()=>void)=>void;
type T7 = (x: unknown)=>x is string;
let v1: ()=>void;
function g(cb: (x: number)=>void = ()=>{}) {}
