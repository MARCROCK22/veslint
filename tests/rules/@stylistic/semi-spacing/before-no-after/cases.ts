declare function work(...args: unknown[]): void;
declare let value: number;

let tight = 1;
let spaced = 2 ;
work();work();
work() ; work() ;
work();	work();
for (let i = 0;i < 1;i++) {
	work(i);
}
for (let j = 0 ; j < 1 ; j++) {
	work(j);
}
type Tight = string;type Spaced = number ;
interface Shape { name: string;area(): number ; }
class Fields { one = 1;two: number = 2 ; }
value = 1;
;work()
work()
;
const afterTemplate = `x
` ;work();
for (;; ) {
	break;
}

export { tight, spaced, afterTemplate, Fields };
export type { Tight, Spaced, Shape };
