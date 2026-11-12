// Decorators, overloads, parameter properties, `this` types and the rest.
declare function d(...args: unknown[]): any;
declare const token: string;
@d(token)
class Service {
  @d(token) private dep: Service | undefined;
  constructor(@d(token) private readonly a: string, @d() public b = a, c?: number) { c; }
  @d(() => Service) method(@d(token) p: Service, @d q = p): void { q; }
  @d static create(): Service { return new Service(token); }
  @d get value() { return this.a; }
}
function overloaded(a: string): string;
function overloaded(a: number, b?: typeof a): number;
function overloaded(a: any, b?: any): any { return b ?? a; }
declare function ambient(this: Service, cb: (err: Error | null, ...rest: unknown[]) => void): void;
abstract class Shape { abstract area(scale: number): number; describe(this: Shape, unit: string) { return unit; } }
const generic = <T,>(x: T) => x;
const instantiated = generic<string>;
const asserted = (token as unknown as number)!;
const satisfied = { k: token } satisfies Record<string, string>;
let assigned: number;
(assigned as number) = 1;
(<number>assigned) = 2;
assigned! = 3;
(assigned satisfies number) = 4;
(assigned as number)++;
(assigned as number as unknown as number)--;
[assigned] = [5];
({ assigned } = { assigned: 6 });
({ k: assigned = 7 } = satisfied as any);
for (assigned of [8]) {}
function outerFn() { function innerFn() { return outerFn; } return innerFn; }
const selfRef = () => selfRef;
if (token) { function inIf() {} inIf(); }
label: { break label; }
export { Service, overloaded, ambient, Shape, instantiated, asserted, outerFn, selfRef };
