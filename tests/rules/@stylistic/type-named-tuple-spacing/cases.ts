// Spacing around the colon of named tuple members.
type T1 = [i: number];
type T2 = [i:number];
type T3 = [i:  number];
type T4 = [i : number];
type T5 = [i ?: number];
type T6 = [i? :number];
type T7 = [i  ?  :   number];
type T8 = [i?: number, j:string, ...rest:boolean[]];
type T9 = [...rest :boolean[]];
type T10 = [first: [inner:number, other : string]];
type T11 = [i:
	number];
type T12 = [i: {
	a:number;
}];
type T13 = [i:{
	a: number;
}];
type T14 = [i/* comment */:number];
type T15 = [i: /* comment */number];
type T16 = [i:/* comment */ number];
type T17 = [a$1:string];
type T18 = [$:'$&'];
type T19 = [x:'$$'];
type T20 = [x:"$'"];
type T21 = [x:'$`'];
type T22 = [x:'$10'];
type T23 = [x:'$3'];
type T24 = [x?:'$3'];
type T25 = [x:'$6'];
type T26 = [x:'$0'];
type T27 = [x:'$<name>'];
type T28 = [_x$:'$5$4$2$1'];
type T29 = [x :'end$'];
type T30 = [ñ:string];
type T31 = [x	:	string];
type T32 = { change: [id:number]; update: [value? :string] };
type T33 = [x: string];
type T34 = [x:  string];
type T35 = [x　:string];
type T36 = [x? :string];
