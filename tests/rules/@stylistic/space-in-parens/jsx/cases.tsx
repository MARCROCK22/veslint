declare function work(...args: unknown[]): number;
declare const value: number;
declare namespace JSX {
	interface IntrinsicElements {
		[name: string]: unknown;
	}
}

const a = ( <div>(</div> );
const b = (<div>( <b>{ work( value ) }</b> )</div>);
const c = <div>(<span />)</div>;
const d = <div>{( value )}</div>;

export { a, b, c, d };
