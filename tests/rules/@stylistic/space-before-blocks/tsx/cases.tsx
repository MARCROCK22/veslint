declare const a: any;
const e1 = <div>{() =>{}}</div>;
const e2 = <div>{function(){}}</div>;
function F(){ return <div>{a}</div>; }
if (a){ <span />; }
