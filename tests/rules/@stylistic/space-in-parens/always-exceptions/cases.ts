declare function work(...args: unknown[]): number;
declare const value: number;
declare function decorate(...args: unknown[]): (target: unknown) => void;

work( value );
work(value );
work( value);
work(value);
work();
work( );
work(
	value
);
work( /* block */ value );
work(/* block */ value);
work(/*{*/ value);
work(/*{*/value /*}*/);
work(/*(*/value/*)*/);
work( // line
	value);
work(`template ${ value }`);
work( `template` );
work( { a: 1 } );
work({ a: 1 });
work( [ 1, 2 ] );
work([1, 2]);
work( work( value ) );
work(work(value));
work( () => value );
work(() => value);
work(( value ));
if ( value ) {
	work( value );
}
for ( let i = 0; i < 1; i++ ) {
	work(i);
}
for (;;) {
	break;
}
const typed: ( string | number )[] = [];
const fnType: ( a: string ) => void = (a) => work(a);
const generic = work<number>( value );
class Decorated {
	@decorate( value )
	method( a: number ): number {
		return ( a + 1 ) * 2;
	}
}
const regex = work( /x/ );
const nested = work( (value) );
const emptyArrow = ( ) => value;

export { typed, fnType, generic, Decorated, regex, nested, emptyArrow };
