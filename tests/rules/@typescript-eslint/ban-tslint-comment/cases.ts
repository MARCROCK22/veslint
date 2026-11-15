// tslint:disable
/* tslint:enable */
const a = 1; // tslint:disable-line
const b = 2;/*tslint:disable-next-line:no-any */const c = 3;
//tslint:disable:rule1 rule2
/*
 tslint:disable
 */
/*   tslint:enable-line
*/
const é = 4;// tslint:enable-next-line
// tslint:disable-line-but-more
// tslint:disabled
// not tslint:disable
//	tslint:enable	tab
/* tslint:disable */é
export { a, b, c, é };
/* tslint:disable */