// Not reported: typed by JSX.
declare const Foo: any;
const a = <Foo onClick={() => 1} />;
const b = <Foo>{() => 1}</Foo>;
const c = <Foo {...(() => 1)} />;
// Reported.
const d = <Foo onClick={[() => 1]} />;
const e = () => <Foo />;
