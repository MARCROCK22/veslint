enum Fruit {
  Apple,
}
declare function Comp(props: { fruit: Fruit; n?: number }): any;
// Reported.
const a = <Comp fruit={1} />;
// Not reported.
const b = <Comp fruit={Fruit.Apple} n={1} />;
const c = <Comp fruit={Fruit.Apple}>{1}</Comp>;
