declare const Foo: any;
// Not reported: JSX values.
const a = <Foo max={10} />;
const b = <Foo>{20}</Foo>;
// Reported.
const c = <Foo max={10 + 1} />;
const d = <Foo>{[30]}</Foo>;
