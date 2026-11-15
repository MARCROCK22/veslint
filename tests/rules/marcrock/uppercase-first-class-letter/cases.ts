// Reported: a class declaration whose name starts with a lower-case letter.
class foo {}
class fooBar {}
export class bar {}
export default class baz {}
abstract class qux {}
declare class quux {}
class corge<T> {
	value?: T;
}
class grault extends foo {}
@decorate
class garply {}
namespace N {
	export class waldo {}
}
function f() {
	class fred {}
	return fred;
}
class z {}
class a1 {}

// Not reported.
class Foo {}
class FooBar {}
class _foo {}
class $foo {}
class Ñandu {}
class ñandu {}
class éclair {}
class Ü {}
const x = class lower {};
const y = class {};
interface lowerInterface {}
type lowerType = {};
enum lowerEnum {}
class _ {}
class $ {}
class A {}

declare const decorate: ClassDecorator;
export { foo, fooBar, qux, quux, corge, grault, garply, f, z, a1, Foo, FooBar, _foo, $foo, Ñandu, ñandu, éclair, Ü, x, y, _, $, A };
export type { lowerInterface, lowerType };
export { lowerEnum };
