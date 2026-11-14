// Classes with modifiers before `class` (declare, export, decorators): the class is the same node for
// TypeScript.
declare class A { private x: number; }
export declare class B { private y: number; }
declare abstract class C { private z: number; }
export class D { private w = 1; m() { return this; } }
@dec class E { private v = 1; }
declare function dec(c: unknown): void;
export {};
