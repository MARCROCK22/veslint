declare function work(...args: unknown[]): void;
declare const value: number | string;
declare const flag: boolean;

switch (value) {
	case 1: work(); break;
	case 2 : work(); break;
	case 3 :work(); break;
	case 4:work(); break;
	case 5:	work(); break;
	case 6 /* before */: work(); break;
	case 7 /* before */ :work(); break;
	case 8:/* after */ work(); break;
	case 9: /* after */work(); break;
	case 10:
		work();
		break;
	case 11
	: work(); break;
	case (12) : work(); break;
	case flag ? 13 : 14 :work(); break;
	case 'a': {
		work();
		break;
	}
	case 'b' :{
		work();
		break;
	}
	case `c`:
	case 'd' :
	default :work();
}
switch (value) {
	case 1 :}
switch (value) {
	default:}
switch (value) {
	default :work();
	case 20:work();
}
