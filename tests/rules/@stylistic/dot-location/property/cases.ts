declare const obj: { prop: { deep: number }; method(): number; 5: number };
declare const maybe: { prop: number } | undefined;
declare namespace NS { namespace Inner { type T = number } }

const a = obj.prop;
const b = obj.
	prop;
const c = obj
	.prop;
const d = (obj)
	.prop;
const e = obj.prop
	.deep;
const f = obj
	/* comment */ .prop;
const g = obj. // comment
	prop;
const h = maybe
	?.prop;
const i = maybe?.
	prop;
const j = obj
	['prop'];
const k = 5
	.toFixed();
const l = 5.
	toFixed();
const m = 5.0
	.toFixed();
const n = 0x5
	.toFixed();
const o = 1_000
	.toFixed();
const p = obj.method
	();

function meta() {
	return new.
		target;
}
function meta2() {
	return new
		.target;
}
const url = import.
	meta.url;
const url2 = import
	.meta.url;

type Q1 = NS.
	Inner.T;
type Q2 = NS
	.Inner
	.T;
type Imported = import('node:fs').
	Stats;
type Imported2 = import('node:fs')
	.Stats;
type Imported3 = typeof import('node:fs');
